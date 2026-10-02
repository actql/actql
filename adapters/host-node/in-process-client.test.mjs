import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
