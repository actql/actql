import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {generateKeyPairSync, sign} from 'node:crypto';
import {connect} from '../../packages/sdk/index.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {mkdtemp, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {setImmediate} from 'node:timers/promises';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';
import * as resultAccess from '../host-common/result-access.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';
import {createResultDeliveryFixture} from
  '../../scripts/fixtures/result-delivery-acceptance.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'volatile', scopeRef: 'local-principal',
  capabilities: [], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
    maxBatchRetainedValueBytes: 2048}};

test('Local public ingress excludes private handler causes and stacks', async t => {
  const privateFailure = Object.assign(new Error('private-handler-secret'), {
    code: 'PrivateStorageFailure', cause: new Error('private-handler-secret'),
    stack: 'private-handler-secret', sourceLocator: 'connector://private-handler-secret',
  });
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    createNodeInProcessClientHost({authenticate: () => 'local-principal',
      authorizeConnection: () => true, negotiate: () => profile,
      attach() { throw privateFailure; }, maxRowBytes: 1024}));
  t.after(() => client.close());
  let failure;
  try { await client.attach(ref); }
  catch (error) { failure = error; }
  assert.equal(failure?.code, 'ClientHostFailure');
  assert.equal(failure.cause, undefined, '[check-mutation:local-disclosure]');
  assert.equal(failure.stack, undefined);
  assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-handler-secret/u);
});

test('in-process Host checks current scope and exact attach reference',
  async () => {
    let attached = 0;
    const host = createNodeInProcessClientHost({
      authenticate: () => 'local-principal',
      authorizeConnection: ({ref: requested}) =>
        requested === undefined || requested.namespaceId === 'namespace-a',
      negotiate: () => profile,
      attach: () => {
        attached++;
        return {ref: {...ref, runDefinitionCid: cid('c')},
          durability: 'volatile', revision: 1};
      },
      maxRowBytes: 1024,
    });
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      host);
    await assert.rejects(client.attach({...ref, namespaceId: 'namespace-b'}),
      {code: 'ClientConnectionDenied'});
    assert.equal(attached, 0);
    await assert.rejects(client.attach(ref),
      {code: 'InvalidClientHostAdmission'});
    assert.equal(attached, 1);
    client.close();
  });

test('in-process Checkpoint operations use the public Host contract',
  async () => {
    const calls = [];
    const host = createNodeInProcessClientHost({
      authenticate: () => 'local-principal',
      authorizeConnection: ({operation}) => {
        calls.push(operation);
        return true;
      },
      negotiate: () => profile,
      checkpoints: () => ({items: []}),
      checkpointReview: () => {
        throw Object.assign(new Error('CheckpointReviewDenied'),
          {code: 'CheckpointReviewDenied'});
      },
      maxRowBytes: 1024,
    });
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      host);
    assert.deepEqual(await client.checkpoints(), {items: []});
    await assert.rejects(client.reviewCheckpoint(cid('c')),
      {code: 'CheckpointReviewDenied'});
    assert.ok(calls.includes('checkpoints'));
    assert.ok(calls.includes('checkpoint-review'));
    client.close();
  });

// These tests exercise the actual Result control/service and a physical Store
// reader. Only contract persistence is the existing bounded Store fixture.
async function localDelivery(t, {signal, maxRowBytes = 1024,
  readFailure, beforeAppend} = {}) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-local-read-'));
  const physical = await createLocalRetainedStore({parentDirectory,
    capacityBytes: 1024, maxFrameBytes: 1024});
  let iterator;
  t.after(async () => {
    await iterator?.return();
    physical.close();
    assert.equal(await physical.cleanup(), true);
    await rmdir(parentDirectory);
  });
  const rows = [7, 8, 9, 10].map(value => JSON.stringify({value}));
  const writer = physical.reserve(1024);
  await writer.start();
  await writer.append(rows.join('\n'));
  const body = await writer.sealPhysical();
  let reached;
  const backpressured = new Promise(resolve => { reached = resolve; });
  let terminal;
  const settled = new Promise(resolve => { terminal = resolve; });
  const fixture = createResultDeliveryFixture(resultAccess,
    openResultDeliveryControl(), {rows,
      async beforeAppend(record) {
        await beforeAppend?.(record);
        if (JSON.parse(record.wire).state !== 'streaming') terminal();
      },
      async readRows(accept) {
        await body.consume(async bytes => {
          let count = 0;
          for (const row of new TextDecoder().decode(bytes).split('\n')) {
            if (++count === 3) reached();
            await accept(row);
            if (readFailure) throw readFailure;
          }
        });
      },
    });
  const response = authorizedLocalResultFrames(fixture.service, {
    indexKey: {namespaceId: 'namespace', authorityScopeCid: cid('a'),
      runDefinitionCid: cid('9')},
    principalId: 'principal', purpose: 'download', resultName: 'answer',
    attemptId: 'local-read',
  }, signal, {maxRowBytes});
  iterator = response.frames[Symbol.asyncIterator]();
  return {...fixture, body, physical, iterator, backpressured, settled};
}

async function within(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('LocalDeliveryDidNotSettle')),
        5000);
    })]);
  } finally { clearTimeout(timer); }
}

test('aborting a paused Local read releases backpressured physical capacity',
  async t => {
    const controller = new AbortController();
    const f = await localDelivery(t, {signal: controller.signal});
    assert.deepEqual((await f.iterator.next()).value.value, {value: 7});
    await f.backpressured;
    await setImmediate();
    assert.equal(f.physical.status().activeReaders, 1);
    assert.ok(f.physical.status().reservedReadBufferBytes > 0);
    const reason = new Error('ReadCancelled');
    controller.abort(reason);
    controller.abort(new Error('DuplicateAbort'));
    // No next/return call is allowed to drive the producer's cleanup here.
    await within(f.settled);
    await setImmediate();
    assert.equal(f.physical.status().activeReaders, 0);
    assert.equal(f.physical.status().reservedReadBufferBytes, 0);
    assert.equal(JSON.parse(f.state.record.wire).state, 'cancelled');
    assert.equal(f.state.records.length, 2);
    assert.equal(f.body.available(), true);
    await f.body.consume(async () => {});
    await assert.rejects(f.iterator.next(), error => error === reason);
  });

test('public SDK abort releases a paused Local physical reader without another next call', async t => {
  const f = await localDelivery(t);
  const boundRef = {namespaceId: 'namespace', authorityScopeCid: cid('a'),
    runDefinitionCid: cid('9')};
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    createNodeInProcessClientHost({authenticate: () => 'principal',
      authorizeConnection: () => true, negotiate: () => profile,
      attach: () => ({ref: boundRef, durability: 'volatile', revision: 1}),
      resultService: f.service, maxRowBytes: 1024}));
  t.after(() => client.close());
  const controller = new AbortController();
  const reader = (await client.attach(boundRef)).result('answer')
    .rows({signal: controller.signal});
  const iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual((await iterator.next()).value, {value: 7});
  await f.backpressured;
  assert.equal(f.physical.status().activeReaders, 1);
  controller.abort();
  await within(f.settled);
  await setImmediate();
  assert.equal(f.physical.status().activeReaders, 0);
  assert.equal(f.physical.status().reservedReadBufferBytes, 0);
  assert.equal(JSON.parse(f.state.record.wire).state, 'cancelled');
  assert.equal(reader.rowsYielded(), 1);
  assert.equal(reader.state(), 'prefix');
  assert.equal(f.state.admissions, 1);
  assert.equal(f.state.grantUses, 1);
  await assert.rejects(iterator.next(), error => error.attemptId === reader.attemptId &&
    error.rowsYielded === 1);
  assert.equal(f.body.available(), true);
});

test('pre-aborted Local read never admits a delivery or physical reader',
  async t => {
    const reason = new Error('ReadAlreadyCancelled');
    const f = await localDelivery(t, {signal: AbortSignal.abort(reason)});
    await assert.rejects(f.iterator.next(), error => error === reason);
    assert.equal(f.state.admissions, 0);
    assert.equal(f.state.readers, 0);
    assert.equal(f.physical.status().activeReaders, 0);
  });

test('Local consumer return settles a paused read without revoking its body',
  async t => {
    const f = await localDelivery(t);
    await f.iterator.next();
    await f.backpressured;
    await f.iterator.return();
    assert.equal(f.physical.status().activeReaders, 0);
    assert.equal(JSON.parse(f.state.record.wire).state, 'cancelled');
    assert.equal(f.body.available(), true);
  });

test('Local normal exhaustion releases its reader and records success',
  async t => {
    const f = await localDelivery(t);
    const values = [];
    for await (const frame of f.iterator) values.push(frame.value.value);
    assert.deepEqual(values, [7, 8, 9, 10]);
    assert.equal(f.physical.status().activeReaders, 0);
    assert.equal(JSON.parse(f.state.record.wire).state, 'succeeded');
    assert.equal(f.body.available(), true);
  });

test('Local terminal record failure survives a normal wire terminator', async t => {
  const unavailable = new Error('terminal record unavailable');
  const f = await localDelivery(t, {async beforeAppend(record) {
    if (JSON.parse(record.wire).state === 'succeeded') throw unavailable;
  }});
  const seen = [];
  await assert.rejects(async () => {
    for await (const frame of f.iterator) seen.push(frame.value.value);
  }, error => error.code === 'ResultDeliveryDurabilityPending' &&
    error.primaryFailure === unavailable && error.cleanupPending === true);
  assert.deepEqual(seen, [7, 8, 9, 10]);
  assert.equal(f.physical.status().activeReaders, 0);
  assert.equal(f.physical.status().reservedReadBufferBytes, 0);
  assert.equal(JSON.parse(f.state.record.wire).state, 'streaming');
  assert.equal(f.body.available(), true);
});

test('Local delivery keeps the upstream failure after channel cleanup',
  async t => {
    const reason = new Error('PhysicalReadFailed');
    const f = await localDelivery(t, {readFailure: reason});
    assert.deepEqual((await f.iterator.next()).value.value, {value: 7});
    await assert.rejects(f.iterator.next(), error => error === reason);
    assert.equal(f.physical.status().activeReaders, 0);
    assert.equal(JSON.parse(f.state.record.wire).state, 'failed');
  });

test('Local frame refusal keeps its original error while releasing the reader',
  async t => {
    const f = await localDelivery(t, {maxRowBytes: 1});
    await assert.rejects(f.iterator.next(), {message: 'InvalidLocalResultFrame'});
    assert.equal(f.physical.status().activeReaders, 0);
    assert.equal(JSON.parse(f.state.record.wire).state, 'cancelled');
  });


const checkpoint = {
  checkpointId: 'prepare-a-preparation', checkpointCid: cid('c'),
  kind: 'run_scope', phase: 'preflight',
  subject: {kind: 'prepare_attempt', prepareAttemptId: 'prepare-a',
    requestId: 'saved-a'},
  requiredArtifact: {type: 'prepared_invocation', cid: cid('d')},
  reviewProjectionCid: cid('e'), requirements: ['invocation_scope_approved'],
  createdAt: '2026-09-26T00:00:00.000Z',
  expiresAt: '2026-09-27T00:00:00.000Z', humanSummary: 'Run on site-a',
};

async function checkpointClient(t, transport, handlers) {
  const configuration = {
    authenticate: () => 'local-principal', authorizeConnection: () => true,
    negotiate: () => profile, maxRowBytes: 1024, ...handlers,
  };
  let client;
  if (transport === 'in-process') {
    client = await connectInProcess({mode: 'local', owner: 'local'},
      createNodeInProcessClientHost(configuration));
  } else {
    const server = createServer(createClientHttpHandler(configuration));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    });
    client = await connect({mode: 'local', owner: 'local',
      endpoint: `http://127.0.0.1:${server.address().port}/`,
      token: 'test-token'});
  }
  t.after(() => client.close());
  return client;
}

for (const transport of ['http', 'in-process']) {
  for (const failure of ['internal-error', 'malformed-reply']) {
    for (const operation of ['cancel-request', 'resolve']) {
      test(`${transport} ${operation} retains recovery after ${failure}`,
        async t => {
          const received = [];
          let recovering = false, signatures = 0;
          const keys = generateKeyPairSync('ed25519');
          const signer = {keyId: 'test-key', reviewerId: 'reviewer',
            sign(bytes) { signatures++; return sign(null, bytes, keys.privateKey); }};
          const handler = request => {
            received.push(structuredClone(request));
            if (!recovering) {
              if (failure === 'internal-error') {
                throw new Error('reply failed after the mutation was recorded');
              }
              return {};
            }
            if (operation === 'cancel-request') {
              return {requestId: request.requestId, kind: 'already_requested'};
            }
            return {results: request.items.map(item => ({
              checkpointCid: item.checkpointCid, status: 'duplicate',
              decision: 'rejected',
              resolutionCid: JSON.parse(item.resolutionWire).resolution_cid,
            }))};
          };
          const client = await checkpointClient(t, transport,
            operation === 'cancel-request' ? {cancelRequest: handler}
              : {resolve: handler});
          let uncertain;
          await assert.rejects(operation === 'cancel-request'
            ? client.cancelRequest('saved-a')
            : client.resolveCheckpoints([{checkpoint, decision: 'rejected'}],
              {signer}), error => {
            uncertain = error;
            return error.code === (operation === 'cancel-request'
              ? 'CancellationUnknown' : 'ResolutionUnknown');
          });
          assert.equal(received.length, 1);
          assert.equal(uncertain.cause.status, 500);
          recovering = true;
          if (operation === 'cancel-request') {
            assert.equal(uncertain.requestId, 'saved-a');
            await client.cancelRequest(uncertain.requestId);
            assert.equal(received[1].requestId, received[0].requestId);
            assert.equal(signatures, 0);
          } else {
            assert.deepEqual(uncertain.signed, received[0].items);
            const recovered = await client.resolveCheckpoints(uncertain.signed);
            assert.equal(recovered.results[0].status, 'duplicate');
            assert.deepEqual(received[1].items, received[0].items);
            assert.equal(signatures, 1);
          }
          assert.equal(received.length, 2);
        });
    }
  }

  for (const refusal of ['authentication', 'connection', 'request', 'handler']) {
    test(`${transport} Checkpoint ${refusal} refusal remains known`, async t => {
      let connected = false, invoked = 0;
      const denied = code => { throw Object.assign(new Error(code), {code}); };
      const client = await checkpointClient(t, transport, {
        authenticate() {
          if (connected && refusal === 'authentication') {
            denied('ClientAuthenticationDenied');
          }
          return 'local-principal';
        },
        authorizeConnection: () => !(connected && refusal === 'connection'),
        cancelRequest() { invoked++; denied('ClientRequestCancellationDenied'); },
        resolve() { invoked++; denied('CheckpointAnswerDenied'); },
      });
      connected = true;
      const expected = refusal === 'authentication' ? 'ClientAuthenticationDenied'
        : refusal === 'connection' ? 'ClientConnectionDenied'
          : refusal === 'request' ? 'InvalidClientRequest'
            : 'ClientRequestCancellationDenied';
      await assert.rejects(client.cancelRequest(refusal === 'request'
        ? 'x'.repeat(257) : 'saved-a'), error => error.code === expected &&
          error.requestId === undefined);
      assert.equal(invoked, refusal === 'handler' ? 1 : 0);
      if (refusal === 'request') return;
      const keys = generateKeyPairSync('ed25519');
      await assert.rejects(client.resolveCheckpoints([
        {checkpoint, decision: 'rejected'},
      ], {signer: {keyId: 'test-key', reviewerId: 'reviewer',
        sign: bytes => sign(null, bytes, keys.privateKey)}}), error =>
        error.code === (refusal === 'handler' ? 'CheckpointAnswerDenied'
          : expected) && error.signed === undefined);
      assert.equal(invoked, refusal === 'handler' ? 2 : 0);
    });
  }
}
