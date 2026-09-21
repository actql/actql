import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash, X509Certificate} from 'node:crypto';
import {request as httpsRequest} from 'node:https';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {
  sendHttpsDirectTransfer,
  startHttpsDirectTransferReceiver,
} from './https-direct-transfer.mjs';
import {openSqliteTransferJournal} from './sqlite-transfer-journal.mjs';

const control = runtimeCore(moon).remoteTransferControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

function issueCertificate(root, name, subject, extensionFile) {
  openssl(root, 'genrsa', '-out', `${name}.key`, '2048');
  openssl(
    root,
    'req',
    '-new',
    '-key', `${name}.key`,
    '-out', `${name}.csr`,
    '-subj', subject,
  );
  openssl(
    root,
    'x509',
    '-req',
    '-in', `${name}.csr`,
    '-CA', 'ca.crt',
    '-CAkey', 'ca.key',
    '-CAcreateserial',
    '-out', `${name}.crt`,
    '-days', '1',
    ...(extensionFile === undefined ? [] : ['-extfile', extensionFile]),
  );
}

async function certificates(root) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(
    root,
    'req',
    '-x509',
    '-new',
    '-key', 'ca.key',
    '-out', 'ca.crt',
    '-subj', '/CN=ActQL Transfer Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'destination.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
  );
  issueCertificate(
    root,
    'destination',
    '/CN=localhost',
    'destination.ext',
  );
  issueCertificate(root, 'source', '/CN=source-a');
  issueCertificate(root, 'foreign', '/CN=foreign-source');
  const read = name => readFile(join(root, name));
  const sourceCertificate = await read('source.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    destinationKey: await read('destination.key'),
    destinationCertificate: await read('destination.crt'),
    sourceKey: await read('source.key'),
    sourceCertificate,
    sourceFingerprint: new X509Certificate(sourceCertificate).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}

async function body(store, value) {
  const bytes = Buffer.from(value, 'utf8');
  const writer = store.reserve(bytes.byteLength);
  await writer.start();
  for (let offset = 0; offset < bytes.byteLength; offset += 4) {
    await writer.appendBytes(bytes.subarray(offset, offset + 4));
  }
  return await writer.sealPhysical();
}

async function contents(retained) {
  const chunks = [];
  await retained.consume(frame => { chunks.push(Buffer.from(frame)); });
  return Buffer.concat(chunks).toString('utf8');
}

async function receiverRequest(setup, {path, method = 'POST', headers, body}) {
  return await new Promise((resolve, reject) => {
    const target = new URL(path, setup.receiver.origin);
    const request = httpsRequest(target, {
      method,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      servername: 'localhost',
      headers,
    }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve(Object.freeze({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      })));
    });
    request.once('error', reject);
    request.end(body);
  });
}

async function postCancel(setup, requestCid) {
  return await receiverRequest(setup, {
    path: `/v1/sites/destination-b/generations/2/transfers/` +
      `${encodeURIComponent(requestCid)}/cancel`,
    headers: {'content-length': '0'},
  });
}

async function startReceiver(material, destinationStore, journal, authorize) {
  return await startHttpsDirectTransferReceiver({
    key: material.destinationKey,
    cert: material.destinationCertificate,
    ca: material.ca,
    sourceAuthorities: new Map([
      [material.sourceFingerprint, 'source-a'],
    ]),
    destinationSiteKey: 'destination-b',
    destinationSiteGeneration: 2,
    control,
    journal,
    store: destinationStore,
    authorize: authorize ?? (({request, peer}) =>
      peer.sourceSite === 'source-a' &&
      control.requestProjection(request)[11] === cid('5')),
    maxControlBytes: 32_768,
    maxManifestBytes: 8192,
    maxChunks: 8,
    maxReferencedBytes: 1024n,
    maxFrameBytes: 4,
  });
}

async function fixture(t, {authorize, decorateJournal} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-direct-transfer-'));
  const material = await certificates(root);
  const sourceStore = await createLocalRetainedStore({
    parentDirectory: root,
    capacityBytes: 1024,
    maxFrameBytes: 4,
    maxEntries: 8,
    maxReadersPerBody: 2,
  });
  const destinationStore = await createLocalRetainedStore({
    parentDirectory: root,
    capacityBytes: 1024,
    maxFrameBytes: 4,
    maxEntries: 8,
    maxReadersPerBody: 2,
  });
  const durableJournal = openSqliteTransferJournal(join(root, 'journal'), {
    destinationSiteKey: 'destination-b',
    destinationSiteGeneration: 2,
    maxChunks: 8,
    maxManifestBytes: 8192,
    maxReferencedBytes: 1024n,
  });
  const journal = decorateJournal === undefined ? durableJournal :
    decorateJournal(durableJournal);
  const receiver = await startReceiver(
    material,
    destinationStore,
    journal,
    authorize,
  );
  t.after(async () => {
    try { await receiver.close(); }
    catch (error) {
      if (error.code !== 'RemoteTransferCleanupPending') throw error;
    }
    journal.close();
    sourceStore.close();
    destinationStore.close();
    await sourceStore.cleanup();
    await destinationStore.cleanup();
    await rm(root, {recursive: true, force: true});
  });
  return Object.freeze({
    root,
    material,
    sourceStore,
    destinationStore,
    journal,
    receiver,
  });
}

function transferRequest(values, expiresAtMilliseconds) {
  return control.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: 'transfer-direct-a',
    route: 'direct',
    sourceSite: 'source-a',
    sourceSiteGeneration: 1,
    destinationSite: 'destination-b',
    destinationSiteGeneration: 2,
    sourceMaterialGeneration: 'source-material-a',
    physicalManifest: Object.freeze({
      version: 'actql-managed-physical-manifest/0.1',
      schemaContractCid: cid('1'),
      viewContractCid: cid('2'),
      codecContractCid: cid('3'),
      rowCount: values.length,
      chunks: Object.freeze(values.map(value => Object.freeze({
        cid: digest(value),
        byteLength: BigInt(Buffer.byteLength(value, 'utf8')),
        rowCount: 1,
      }))),
    }),
    limits: Object.freeze({
      maxChunks: 8,
      maxManifestBytes: 8192,
      maxReferencedBytes: 1024n,
    }),
    capacityBytes: 1024n,
    expiresAtMilliseconds,
    sourceGrantCid: cid('4'),
    destinationGrantCid: cid('5'),
    routeCapabilityCid: cid('6'),
  }));
}

test('mTLS direct Transfer preserves ordered chunks without a bulk relay',
  async t => {
    const setup = await fixture(t);
    const sourceBodies = [
      await body(setup.sourceStore, 'alpha'),
      await body(setup.sourceStore, '日本語'),
    ];
    const request = transferRequest(
      ['alpha', '日本語'],
      BigInt(Date.now() + 60_000),
    );
    const result = await sendHttpsDirectTransfer({
      origin: setup.receiver.origin,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      control,
      request,
      sourceBodies,
    });
    assert.equal(result.requestCid, control.identity(request));
    assert.deepEqual(result.state, [3, 2, 0, 1, 0, 1, 1, 1, 1]);
    const claimed = setup.receiver.claim(control.identity(request));
    assert.equal(claimed.materialGeneration,
      control.destinationReceiptProjection(claimed.destinationReceipt)[4]);
    assert.equal(claimed.destinationReceiptCid,
      control.destinationReceiptIdentity(claimed.destinationReceipt));
    assert.equal(
      control.destinationReceiptProjection(claimed.destinationReceipt)[1],
      control.identity(request),
    );
    assert.equal(await contents(claimed.bodies[0]), 'alpha');
    assert.equal(await contents(claimed.bodies[1]), '日本語');
    await assert.rejects(setup.receiver.consume(
      control.identity(request),
      () => false,
      async () => assert.fail('unauthorized consumer received bytes'),
    ), {code: 'RemoteTransferUnauthorized'});
    const streamed = [[], []];
    const consumed = await setup.receiver.consume(
      control.identity(request),
      value => value.destinationReceiptCid ===
        claimed.destinationReceiptCid,
      async (index, frame) => streamed[index].push(Buffer.from(frame)),
    );
    assert.equal(consumed.destinationReceiptCid,
      claimed.destinationReceiptCid);
    assert.deepEqual(streamed.map(chunks => Buffer.concat(chunks).toString()),
      ['alpha', '日本語']);
    assert.equal(setup.destinationStore.status().reservedBytes, 14);
    assert.equal(setup.sourceStore.status().activeReaders, 0);
    assert.equal(await setup.receiver.release(control.identity(request)), true);
    assert.equal(setup.destinationStore.status().reservedBytes, 0);
    assert.deepEqual(
      setup.journal.inspect(request, control).state,
      [4, 2, 0, 1, 1, 1, 1, 1, 1],
    );
    for (const source of sourceBodies) source.close();
    await setup.sourceStore.cleanup();
    assert.equal(await setup.receiver.close(), true);
  });

test('direct Transfer rejects a foreign authenticated client before use',
  async t => {
    const setup = await fixture(t);
    const source = await body(setup.sourceStore, 'alpha');
    const request = transferRequest(
      ['alpha'],
      BigInt(Date.now() + 60_000),
    );
    await assert.rejects(
      sendHttpsDirectTransfer({
        origin: setup.receiver.origin,
        ca: setup.material.ca,
        cert: setup.material.foreignCertificate,
        key: setup.material.foreignKey,
        control,
        request,
        sourceBodies: [source],
      }),
      {code: 'RemoteTransferRejected'},
    );
    assert.equal(setup.destinationStore.status().reservedBytes, 0);
    assert.equal(setup.journal.recover(control).length, 0);
    source.close();
    await setup.sourceStore.cleanup();
    assert.equal(await setup.receiver.close(), true);
  });

test('live direct receiver reconciles a commit without source access',
  async t => {
    const setup = await fixture(t);
    const source = await body(setup.sourceStore, 'alpha');
    const request = transferRequest(
      ['alpha'],
      BigInt(Date.now() + 60_000),
    );
    await sendHttpsDirectTransfer({
      origin: setup.receiver.origin,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      control,
      request,
      sourceBodies: [source],
    });
    let reads = 0;
    const result = await sendHttpsDirectTransfer({
      origin: setup.receiver.origin,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      control,
      request,
      sourceBodies: [Object.freeze({
        cid: digest('alpha'),
        bytes: 5,
        async consume() {
          reads++;
          throw new Error('source must not be read during reconciliation');
        },
      })],
    });
    assert.deepEqual(result.state, [3, 2, 0, 1, 0, 1, 1, 1, 1]);
    assert.equal(reads, 0);
    assert.equal(setup.destinationStore.status().reservedBytes, 5);
    assert.equal(await setup.receiver.release(control.identity(request)), true);
    source.close();
    await setup.sourceStore.cleanup();
    assert.equal(await setup.receiver.close(), true);
  });

test('direct commit resumes after durable source settlement', async t => {
  let destinationCommitFailures = 1;
  const setup = await fixture(t, {
    authorize: ({request, peer, phase}) =>
      phase !== 'cancel' && peer.sourceSite === 'source-a' &&
      control.requestProjection(request)[11] === cid('5'),
    decorateJournal: journal => Object.freeze({
      ...journal,
      advance(transition, transferControl) {
        const [before, after] = transferControl.transitionProjection(transition);
        if (destinationCommitFailures > 0 && before[1] === 1 &&
            before[5] === 1 && after[1] === 2) {
          destinationCommitFailures--;
          throw Object.assign(new Error('injected destination commit failure'), {
            code: 'InjectedDestinationCommitFailure',
          });
        }
        return journal.advance(transition, transferControl);
      },
    }),
  });
  const source = await body(setup.sourceStore, 'alpha');
  const request = transferRequest(
    ['alpha'],
    BigInt(Date.now() + 60_000),
  );
  await assert.rejects(
    sendHttpsDirectTransfer({
      origin: setup.receiver.origin,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      control,
      request,
      sourceBodies: [source],
    }),
    {code: 'RemoteTransferRejected'},
  );
  assert.deepEqual(setup.journal.inspect(request, control).state,
    [2, 1, 0, 1, 0, 1, 0, 1, 0]);
  const requestCid = control.identity(request);
  const commitPath = `/v1/sites/destination-b/generations/2/transfers/` +
    `${encodeURIComponent(requestCid)}/commit`;
  const resumed = await receiverRequest(setup, {
    path: commitPath,
    headers: {'content-length': '0'},
  });
  assert.equal(resumed.status, 200);
  assert.deepEqual(
    control.recordProjection(control.admitReplyJson(resumed.body, request)),
    [3, 2, 0, 1, 0, 1, 1, 1, 1],
  );
  for (let retry = 0; retry < 2; retry++) {
    const repeated = await receiverRequest(setup, {
      path: commitPath,
      headers: {'content-length': '0'},
    });
    assert.equal(repeated.status, 200);
    assert.deepEqual(
      control.recordProjection(control.admitReplyJson(repeated.body, request)),
      [3, 2, 0, 1, 0, 1, 1, 1, 1],
    );
  }
  assert.equal(setup.destinationStore.status().reservedBytes, 5);
  assert.equal(await setup.receiver.release(requestCid), true);
  source.close();
  await setup.sourceStore.cleanup();
  assert.equal(await setup.receiver.close(), true);
});

test('cancel after direct commit preserves destination material', async t => {
  const setup = await fixture(t);
  const source = await body(setup.sourceStore, 'alpha');
  const request = transferRequest(
    ['alpha'],
    BigInt(Date.now() + 60_000),
  );
  await sendHttpsDirectTransfer({
    origin: setup.receiver.origin,
    ca: setup.material.ca,
    cert: setup.material.sourceCertificate,
    key: setup.material.sourceKey,
    control,
    request,
    sourceBodies: [source],
  });
  const requestCid = control.identity(request);
  const cancelled = await postCancel(setup, requestCid);
  assert.equal(cancelled.status, 200);
  assert.deepEqual(
    control.recordProjection(control.admitReplyJson(cancelled.body, request)),
    [3, 2, 0, 1, 0, 1, 1, 1, 1],
  );
  const claimed = setup.receiver.claim(requestCid);
  assert.equal(await contents(claimed.bodies[0]), 'alpha');
  assert.equal(setup.destinationStore.status().reservedBytes, 5);
  assert.equal(await setup.receiver.release(requestCid), true);
  assert.equal(setup.destinationStore.status().reservedBytes, 0);
  source.close();
  await setup.sourceStore.cleanup();
  assert.equal(await setup.receiver.close(), true);
});

test('cancel authorization rechecks a concurrently committed destination',
  async t => {
    let enterCancel;
    let resumeCancel;
    const cancelEntered = new Promise(resolve => { enterCancel = resolve; });
    const cancelResume = new Promise(resolve => { resumeCancel = resolve; });
    const setup = await fixture(t, {
      async authorize({request, peer, phase}) {
        if (phase === 'cancel') {
          enterCancel();
          await cancelResume;
        }
        return peer.sourceSite === 'source-a' &&
          control.requestProjection(request)[11] === cid('5');
      },
    });
    const request = transferRequest(
      ['four'],
      BigInt(Date.now() + 60_000),
    );
    const requestCid = control.identity(request);
    const base = `/v1/sites/destination-b/generations/2/transfers/` +
      encodeURIComponent(requestCid);
    const envelope = Buffer.from(control.admissionEnvelopeJson(request));
    const projection = control.requestProjection(request);
    assert.equal((await receiverRequest(setup, {
      path: '/v1/sites/destination-b/generations/2/transfers',
      headers: {
        'content-type': 'application/json',
        'content-length': String(envelope.byteLength),
        'actql-transfer-cid': requestCid,
        'actql-manifest-cid': projection[7],
      },
      body: envelope,
    })).status, 201);
    assert.equal((await receiverRequest(setup, {
      path: `${base}/chunks/0`,
      method: 'PUT',
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '4',
      },
      body: Buffer.from('four'),
    })).status, 200);
    const cancelling = postCancel(setup, requestCid);
    await cancelEntered;
    assert.equal((await receiverRequest(setup, {
      path: `${base}/commit`,
      headers: {'content-length': '0'},
    })).status, 200);
    resumeCancel();
    assert.equal((await cancelling).status, 200);
    const claimed = setup.receiver.claim(requestCid);
    assert.equal(await contents(claimed.bodies[0]), 'four');
    assert.equal(setup.destinationStore.status().reservedBytes, 4);
    assert.equal(await setup.receiver.release(requestCid), true);
    assert.equal(await setup.receiver.close(), true);
  });

test('fresh direct receiver does not claim historical material availability',
  async t => {
    const setup = await fixture(t);
    const source = await body(setup.sourceStore, 'alpha');
    const request = transferRequest(
      ['alpha'],
      BigInt(Date.now() + 60_000),
    );
    await sendHttpsDirectTransfer({
      origin: setup.receiver.origin,
      ca: setup.material.ca,
      cert: setup.material.sourceCertificate,
      key: setup.material.sourceKey,
      control,
      request,
      sourceBodies: [source],
    });
    const restarted = await startReceiver(
      setup.material,
      setup.destinationStore,
      setup.journal,
    );
    t.after(async () => { await restarted.close(); });
    let reads = 0;
    await assert.rejects(
      sendHttpsDirectTransfer({
        origin: restarted.origin,
        ca: setup.material.ca,
        cert: setup.material.sourceCertificate,
        key: setup.material.sourceKey,
        control,
        request,
        sourceBodies: [Object.freeze({
          cid: digest('alpha'),
          bytes: 5,
          async consume() { reads++; },
        })],
      }),
      {code: 'RemoteTransferRejected'},
    );
    assert.equal(reads, 0);
    assert.equal(setup.destinationStore.status().reservedBytes, 5);
    assert.equal(await restarted.close(), true);
    assert.equal(await setup.receiver.release(control.identity(request)), true);
    source.close();
    await setup.sourceStore.cleanup();
    assert.equal(await setup.receiver.close(), true);
  });

test('fresh direct receiver does not recreate an unfinished Transfer',
  async t => {
    const setup = await fixture(t);
    const request = transferRequest(
      ['alpha'],
      BigInt(Date.now() + 60_000),
    );
    setup.journal.accept(request, control);
    const restarted = await startReceiver(
      setup.material,
      setup.destinationStore,
      setup.journal,
    );
    t.after(async () => { await restarted.close(); });
    let reads = 0;
    await assert.rejects(
      sendHttpsDirectTransfer({
        origin: restarted.origin,
        ca: setup.material.ca,
        cert: setup.material.sourceCertificate,
        key: setup.material.sourceKey,
        control,
        request,
        sourceBodies: [Object.freeze({
          cid: digest('alpha'),
          bytes: 5,
          async consume(emit) {
            reads++;
            await emit(Buffer.from('alpha', 'utf8'));
          },
        })],
      }),
      {code: 'RemoteTransferRejected'},
    );
    assert.equal(reads, 0);
    assert.equal(setup.destinationStore.status().reservedBytes, 0);
    assert.equal(await restarted.close(), true);
    assert.equal(await setup.receiver.close(), true);
  });

test('direct Transfer returns durable cleanup without retransmitting bytes',
  async t => {
    const setup = await fixture(t);
    const request = transferRequest(
      ['alpha'],
      BigInt(Date.now() + 60_000),
    );
    const wrongSource = Object.freeze({
      cid: digest('alpha'),
      bytes: 5,
      async consume(emit) { await emit(Buffer.from('omega', 'utf8')); },
    });
    await assert.rejects(
      sendHttpsDirectTransfer({
        origin: setup.receiver.origin,
        ca: setup.material.ca,
        cert: setup.material.sourceCertificate,
        key: setup.material.sourceKey,
        control,
        request,
        sourceBodies: [wrongSource],
      }),
      {code: 'RemoteTransferRejected'},
    );
    assert.equal(setup.destinationStore.status().reservedBytes, 0);
    const durable = setup.journal.inspect(request, control);
    assert.equal(
      control.directCleanupConfirmed(
        control.restore(request, durable.state),
      ),
      true,
    );
    let reads = 0;
    await assert.rejects(
      sendHttpsDirectTransfer({
        origin: setup.receiver.origin,
        ca: setup.material.ca,
        cert: setup.material.sourceCertificate,
        key: setup.material.sourceKey,
        control,
        request,
        sourceBodies: [Object.freeze({
          cid: digest('alpha'),
          bytes: 5,
          async consume() { reads++; },
        })],
      }),
      {code: 'RemoteTransferTerminalFailure'},
    );
    assert.equal(reads, 0);
    assert.equal(setup.destinationStore.status().reservedBytes, 0);
    assert.equal(await setup.receiver.close(), true);
  });
