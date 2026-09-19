import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, X509Certificate} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';
import {
  receiveHttpsTransferObject,
  startHttpsTransferObjectStore,
  uploadHttpsTransferObject,
} from './https-transfer-store.mjs';
import {openSqliteTransferJournal} from './sqlite-transfer-journal.mjs';

const control = runtimeCore(moon).remoteTransferControl;
const contractControl = createPublicationContractControlFixture();
const cid = digit => `sha256:${digit.repeat(64)}`;
const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;

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
    '-subj', '/CN=ActQL Transfer Store Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'store.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
  );
  issueCertificate(root, 'store', '/CN=localhost', 'store.ext');
  issueCertificate(root, 'source', '/CN=source-a');
  issueCertificate(root, 'destination', '/CN=destination-b');
  const read = name => readFile(join(root, name));
  const sourceCertificate = await read('source.crt');
  const destinationCertificate = await read('destination.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    storeKey: await read('store.key'),
    storeCertificate: await read('store.crt'),
    sourceKey: await read('source.key'),
    sourceCertificate,
    sourceFingerprint: new X509Certificate(sourceCertificate).fingerprint256,
    destinationKey: await read('destination.key'),
    destinationCertificate,
    destinationFingerprint: new X509Certificate(
      destinationCertificate,
    ).fingerprint256,
  });
}

async function retainedBody(store, value) {
  const bytes = Buffer.from(value, 'utf8');
  const writer = store.reserve(bytes.byteLength);
  await writer.start();
  for (let offset = 0; offset < bytes.byteLength; offset += 3) {
    await writer.appendBytes(bytes.subarray(offset, offset + 3));
  }
  return await writer.sealPhysical();
}

function publicationConfiguration(directory, authority) {
  return Object.freeze({
    directory,
    storeAuthorityCid: authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: 4096,
    maxContractDepth: 64,
  });
}

function transferRequest(values) {
  return control.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: 'transfer-store-a',
    route: 'store',
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
    expiresAtMilliseconds: BigInt(Date.now() + 60_000),
    sourceGrantCid: cid('4'),
    destinationGrantCid: cid('5'),
    routeCapabilityCid: cid('6'),
  }));
}

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-transfer-store-'));
  const sourceRoot = join(root, 'source');
  const transferRoot = join(root, 'transfer');
  const destinationRoot = join(root, 'destination');
  const material = await certificates(root);
  await mkdir(sourceRoot);
  const sourceStore = await createLocalRetainedStore({
    parentDirectory: sourceRoot,
    capacityBytes: 1024,
    maxFrameBytes: 3,
    maxEntries: 8,
    maxReadersPerBody: 2,
  });
  const transferStore = await openLocalPublicationStore(
    publicationConfiguration(transferRoot, cid('7')),
    contractControl,
  );
  const destinationStore = await openLocalPublicationStore(
    publicationConfiguration(destinationRoot, cid('8')),
    contractControl,
  );
  const journal = openSqliteTransferJournal(join(destinationRoot, 'journal'), {
    destinationSiteKey: 'destination-b',
    destinationSiteGeneration: 2,
    maxChunks: 8,
    maxManifestBytes: 8192,
    maxReferencedBytes: 1024n,
  });
  const service = await startHttpsTransferObjectStore({
    key: material.storeKey,
    cert: material.storeCertificate,
    ca: material.ca,
    peerAuthorities: new Map([
      [material.sourceFingerprint, 'source-a'],
      [material.destinationFingerprint, 'destination-b'],
    ]),
    control,
    store: transferStore,
    authorize: ({request, phase, peer, useId}) => {
      const projection = control.requestProjection(request);
      if (phase.startsWith('upload:')) {
        return peer.siteKey === 'source-a' && projection[10] === cid('4');
      }
      return peer.siteKey === 'destination-b' &&
        projection[11] === cid('5') &&
        (phase === 'download:admit' || useId === 'download-a' ||
          useId === 'download-b');
    },
    maxManifestBytes: 8192,
    maxChunks: 8,
    maxReferencedBytes: 1024n,
    maxFrameBytes: 3,
  });
  t.after(async () => {
    try { await service.close(); }
    catch (error) {
      if (error.code !== 'RemoteTransferCleanupPending') throw error;
    }
    journal.close();
    sourceStore.close();
    await sourceStore.cleanup();
    await transferStore.close();
    await destinationStore.close();
    await rm(root, {recursive: true, force: true});
  });
  return Object.freeze({
    root,
    material,
    sourceStore,
    transferStore,
    destinationStore,
    journal,
    service,
  });
}

test('outbound Store Transfer persists exact destination evidence', async t => {
  const setup = await fixture(t);
  const values = ['alpha', '日本語'];
  const sources = [];
  for (const value of values) {
    sources.push(await retainedBody(setup.sourceStore, value));
  }
  const transfer = transferRequest(values);
  assert.equal((await uploadHttpsTransferObject({
    origin: setup.service.origin,
    ca: setup.material.ca,
    cert: setup.material.sourceCertificate,
    key: setup.material.sourceKey,
    control,
    request: transfer,
    sourceBodies: sources,
  })).sealed, true);
  assert.equal(setup.sourceStore.status().activeReaders, 0);

  const received = await receiveHttpsTransferObject({
    origin: setup.service.origin,
    ca: setup.material.ca,
    cert: setup.material.destinationCertificate,
    key: setup.material.destinationKey,
    control,
    request: transfer,
    useId: 'download-a',
    journal: setup.journal,
    destinationStore: setup.destinationStore,
  });
  assert.deepEqual(
    control.recordProjection(received.record),
    [3, 2, 3, 1, 0, 1, 1, 0, 1],
  );
  assert.deepEqual(
    control.destinationReceiptProjection(
      setup.journal.inspectDestinationReceipt(transfer, control),
    ),
    control.destinationReceiptProjection(received.receipt),
  );
  const contents = [];
  for (let index = 0; index < values.length; index++) {
    const frames = [];
    await setup.destinationStore.consumePhysicalHolding(
      control.identity(transfer),
      index,
      frame => frames.push(Buffer.from(frame)),
    );
    contents.push(Buffer.concat(frames).toString('utf8'));
  }
  assert.deepEqual(contents, values);
  for (const source of sources) source.close();
  await setup.sourceStore.cleanup();
  assert.equal((await setup.transferStore.retirePhysicalHolding(
    control.identity(transfer),
  )).deleted, true);
  assert.equal((await setup.destinationStore.retirePhysicalHolding(
    control.identity(transfer),
  )).deleted, true);
  assert.equal(await setup.service.close(), true);
});

test('sealed Store object is reused without reading source again', async t => {
  const setup = await fixture(t);
  const source = await retainedBody(setup.sourceStore, 'stable');
  const transfer = transferRequest(['stable']);
  await uploadHttpsTransferObject({
    origin: setup.service.origin,
    ca: setup.material.ca,
    cert: setup.material.sourceCertificate,
    key: setup.material.sourceKey,
    control,
    request: transfer,
    sourceBodies: [source],
  });
  let reusedReads = 0;
  const reused = Object.freeze({
    cid: source.cid,
    bytes: source.bytes,
    async consume() { reusedReads++; },
  });
  assert.equal((await uploadHttpsTransferObject({
    origin: setup.service.origin,
    ca: setup.material.ca,
    cert: setup.material.sourceCertificate,
    key: setup.material.sourceKey,
    control,
    request: transfer,
    sourceBodies: [reused],
  })).sealed, true);
  assert.equal(reusedReads, 0);
  await receiveHttpsTransferObject({
    origin: setup.service.origin,
    ca: setup.material.ca,
    cert: setup.material.destinationCertificate,
    key: setup.material.destinationKey,
    control,
    request: transfer,
    useId: 'download-b',
    journal: setup.journal,
    destinationStore: setup.destinationStore,
  });
  source.close();
  await setup.sourceStore.cleanup();
  await setup.transferStore.retirePhysicalHolding(control.identity(transfer));
  await setup.destinationStore.retirePhysicalHolding(
    control.identity(transfer),
  );
  assert.equal(await setup.service.close(), true);
});
