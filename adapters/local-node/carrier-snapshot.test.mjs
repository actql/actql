import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readdir, writeFile} from 'node:fs/promises';
import test from 'node:test';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {prepareLocalCarrierSnapshot, prepareLocalRelationSnapshot} from './carrier-snapshot.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

// Transport-only fixture: the real common family/driver is tested separately.
// These bytes are authored here, never obtained from a product snapshot.
const text = '{"key":[1,"雪"],"labels":["Node"]}\n';
const content = {bytes: Buffer.byteLength(text),
  cid: `sha256:${createHash('sha256').update(text).digest('hex')}`};
const checked = value => value;
function operationFixture() {
  const events = [];
  let released;
  const operation = {
    key: 'task-3', maximum_bytes: 256, maximum_frame_bytes: 256,
    advance_save: () => {events.push('save'); return {complete:true,work:1n,progress:1n};},
    take_output: () => text,
    content: () => content,
    release_source: cid => {assert.equal(cid, content.cid); events.push('revoke-source');},
    begin_reload: (actual, available) => {
      assert.equal(actual, text); assert.equal(available(), true);
      assert(events.includes('revoke-source')); events.push('reload');
    },
    advance_reload: () => {events.push('restore'); return {complete:true,work:1n,progress:1n};},
    finish: () => {assert.equal(released(), true); events.push('finish');},
  };
  return {events, operations: {prepare_carrier_snapshot: check => {
    released = check; events.push('prepare'); return operation;
  }}};
}
async function fileFixture() {
  const parent = new URL('../../_build/carrier-snapshot-transport/', import.meta.url);
  await mkdir(parent, {recursive:true});
  const directory = await mkdtemp(new URL('case-', parent));
  const store = await createLocalRetainedStore({parentDirectory:directory,
    capacityBytes:256,maxFrameBytes:256,maxEntries:1});
  return {directory,store};
}

for (const mode of ['synchronous throw', 'promise rejection']) {
  test(`snapshot factory ${mode} before acquisition leaves no cleanup responsibility`, async () => {
    const f = operationFixture();
    const failure = new Error('FactoryRejectedBeforeAllocation');
    let factories = 0;
    const factory = () => {
      factories++;
      if (mode === 'synchronous throw') throw failure;
      return Promise.reject(failure);
    };
    const owner = prepareLocalCarrierSnapshot(f.operations, factory, checked);
    await assert.rejects(owner.roundtrip(), error => error === failure);
    assert.deepEqual(f.events, ['prepare']);
    assert.equal(owner.cleanupHandle.status().pending, false);
    for (let retry = 0; retry < 2; retry++) {
      assert.deepEqual(await owner.cleanupHandle.retry(), {pending:false});
      owner.close();
    }
    assert.equal(factories, 1);
    assert.deepEqual(f.events, ['prepare']);
    await assert.rejects(owner.roundtrip(), /LocalSnapshotAlreadyStarted/);
    assert.equal(factories, 1);
  });
}

for (const boundary of ['reserve', 'start', 'save']) {
  test(`snapshot ${boundary} failure after acquisition retains the same cleanup owner`, async () => {
    const {directory,store} = await fileFixture();
    const f = operationFixture();
    const failure = new Error(`SnapshotFailureAfterAcquisition:${boundary}`);
    const cleanupFailure = new Error('SnapshotCleanupRetryRequired');
    let factories = 0, cleanups = 0;
    const lease = {...store, reserve(bytes) {
      if (boundary === 'reserve') throw failure;
      const writer = store.reserve(bytes);
      return {...writer, async start() {
        await writer.start();
        if (boundary === 'start') throw failure;
      }};
    }, async cleanup() {
      if (++cleanups === 1) throw cleanupFailure;
      return store.cleanup();
    }};
    const operations = {prepare_carrier_snapshot(released) {
      const operation = f.operations.prepare_carrier_snapshot(released);
      return {...operation, advance_save() {
        f.events.push('save');
        throw failure;
      }};
    }};
    const owner = prepareLocalCarrierSnapshot(operations, () => {
      factories++; return lease;
    }, checked);
    await assert.rejects(owner.roundtrip(), error => error === failure);
    assert.equal(owner.cleanupHandle.status().pending, true);
    assert.deepEqual(f.events, boundary === 'save' ? ['prepare','save'] : ['prepare']);
    await assert.rejects(owner.cleanupHandle.retry(), error => error === cleanupFailure);
    assert.equal(owner.cleanupHandle.status().pending, true);
    if (boundary !== 'reserve') assert.equal(store.status().reservedBytes, 256);
    assert.deepEqual(await owner.cleanupHandle.retry(), {pending:false});
    assert.deepEqual(await owner.cleanupHandle.retry(), {pending:false});
    owner.close(); owner.close();
    assert.equal(factories, 1);
    assert.equal(cleanups, 2);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().cleanupPending, false);
    assert.deepEqual(await readdir(directory), []);
    assert.deepEqual(f.events, boundary === 'save' ? ['prepare','save'] : ['prepare']);
  });
}

test('snapshot verifies actual sealed bytes before reload and releases physical capacity before finish', async () => {
  const {directory,store} = await fileFixture();
  const f = operationFixture();
  let leases = 0;
  const owner = prepareLocalCarrierSnapshot(f.operations, () => {leases++; return store;}, checked);
  const diagnostic = await owner.roundtrip();
  assert.deepEqual(diagnostic, {...content,verifiedReadBytes:content.bytes,
    sourceReleased:true,restored:true,temporaryBodyReclaimed:true});
  assert.deepEqual(f.events, ['prepare','save','revoke-source','reload','restore','finish']);
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().cleanupPending, false);
  assert.deepEqual(await readdir(directory), []);
  assert.equal(owner.cleanupHandle.status().pending, false);
  await owner.cleanupHandle.retry(); owner.close();
  assert.equal(leases, 1);
  await assert.rejects(owner.roundtrip(), /LocalSnapshotAlreadyStarted/);
});

test('cleanup failure retains the same physical owner without repeating save or reload', async () => {
  const {directory,store} = await fileFixture();
  const f = operationFixture();
  let fail = true, leases = 0;
  const lease = {...store, async cleanup() {
    if (fail) {fail = false; throw new Error('InjectedSnapshotCleanup');}
    return store.cleanup();
  }};
  const owner = prepareLocalCarrierSnapshot(f.operations, () => {leases++; return lease;}, checked);
  await assert.rejects(owner.roundtrip(), /InjectedSnapshotCleanup/);
  assert.equal(owner.cleanupHandle.status().pending, true);
  assert.equal(store.status().reservedBytes, content.bytes);
  assert.equal(f.events.includes('finish'), false);
  await owner.cleanupHandle.retry(); await owner.cleanupHandle.retry();
  assert.equal(owner.cleanupHandle.status().pending, false);
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(await readdir(directory), []);
  assert.deepEqual(f.events, ['prepare','save','revoke-source','reload','restore']);
  assert.equal(leases, 1);
});

test('provisional read of changed physical bytes never reaches family reload', async () => {
  const {directory,store} = await fileFixture();
  const f = operationFixture();
  const lease = {...store, reserve(bytes) {
    const writer = store.reserve(bytes);
    return {...writer, async seal(identity) {
      const body = await writer.seal(identity);
      const borrow = body.delegateRead('transport-tamper-fixture');
      const path = borrow.descriptor.path;
      // No external reader started: release the test's descriptor borrow.
      borrow.confirmStopped();
      await writeFile(path, text.replace('Node', 'Gone'));
      return body;
    }};
  }};
  const owner = prepareLocalCarrierSnapshot(f.operations, () => lease, checked);
  await assert.rejects(owner.roundtrip(), {code:'RetainedBodyChanged'});
  assert.deepEqual(f.events, ['prepare','save','revoke-source']);
  assert.equal(owner.cleanupHandle.status().pending, true);
  await owner.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(await readdir(directory), []);
});

test('local process close and zero local usage cannot substitute for parent typed release', async () => {
  const f = operationFixture();
  let closed = false, reclaimed = false, releases = 0;
  const body = { ...content, available:() => !closed, close:() => {closed = true;},
    consume: async accept => {await accept(new TextEncoder().encode(text));} };
  const lease = {reserve:() => ({start:async () => {},append:async () => {},seal:async () => body}),
    close:() => {closed = true;}, cleanup:async () => {},
    status:() => ({reservedBytes:0,cleanupPending:false}),
    release:async () => {releases++; return {pending:!reclaimed};}};
  const owner = prepareLocalCarrierSnapshot(f.operations, () => lease, checked);
  await assert.rejects(owner.roundtrip(), /LocalSnapshotCleanupPending/);
  assert.equal(closed, true);
  assert.equal(owner.cleanupHandle.status().pending, true);
  assert.equal(f.events.includes('finish'), false);
  reclaimed = true;
  await owner.cleanupHandle.retry(); await owner.cleanupHandle.retry();
  assert.equal(releases, 2);
  assert.equal(owner.cleanupHandle.status().pending, false);
  assert.deepEqual(f.events, ['prepare','save','revoke-source','reload','restore']);
});

test('cancellation after seal preserves custody and publishes no restored material', async () => {
  const {directory,store} = await fileFixture();
  const f = operationFixture(), controller = new AbortController();
  const lease = {...store, reserve(bytes) {
    const writer = store.reserve(bytes);
    return {...writer, async seal(identity) {
      const body = await writer.seal(identity);
      controller.abort(new Error('SnapshotCancelled')); return body;
    }};
  }};
  const owner = prepareLocalCarrierSnapshot(f.operations, () => lease, checked, controller.signal);
  await assert.rejects(owner.roundtrip(), /SnapshotCancelled/);
  assert.deepEqual(f.events, ['prepare','save']);
  assert.equal(owner.cleanupHandle.status().pending, true);
  await owner.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(await readdir(directory), []);
});

// The transport exercises the real common row framer. The public Host test
// separately exercises the real completion export/import and Graph bridge.
function relationFixture() {
  const rows = [{id:1,p:7},{id:2,p:null},{id:3}];
  const serialized = JSON.stringify(rows);
  const identity = {bytes:Buffer.byteLength(serialized),
    cid:`sha256:${createHash('sha256').update(serialized).digest('hex')}`};
  const events = [], restored = [];
  let cursor = 0, available = true, released;
  const operation = {
    key:'relation-rows', frames:{maxBytes:256,maxFrameBytes:256,
      maxRows:3,maxRowBytes:128,maxDepth:8},
    next() {events.push('save'); return cursor++ === 0 ? serialized : undefined;},
    content:() => identity,
    release_source(actual, physical) {
      assert.equal(actual, identity.cid); assert.equal(physical(),true);
      events.push('revoke-source'); available = false;
    },
    source_available:() => available,
    begin_reload() {assert.equal(available,false); events.push('reload');},
    append_reload(row) {restored.push(JSON.parse(row)); events.push('row');},
    finish_reload() {assert.deepEqual(restored,rows); events.push('restore');},
    finish() {assert.equal(released(),true); events.push('finish');},
  };
  const operations = {
    prepare_relation_snapshot(check) {released = check; events.push('prepare'); return operation;},
    output_rows:() => rows.length,
    output_row(index) {if (!available) throw new Error('OriginalOutputUnavailable'); return rows[index];},
  };
  return {operation,operations,events,rows,restored,identity};
}

test('Relation Store roundtrip preserves ordered missing/NULL/value rows after source revocation', async () => {
  const {directory,store} = await fileFixture();
  const f = relationFixture();
  const owner = prepareLocalRelationSnapshot(f.operations,() => store,checked,undefined,moon);
  assert.deepEqual(await owner.roundtrip(),{...f.identity,
    verifiedReadBytes:f.identity.bytes,rows:3,sourceReleased:true,
    sourceReadRejected:true,restored:true,temporaryBodyReclaimed:true});
  assert.deepEqual(f.restored,f.rows);
  assert.equal(Object.hasOwn(f.restored[2],'p'),false);
  assert.equal(f.restored[1].p,null);
  assert.deepEqual(f.events,['prepare','save','save','revoke-source','reload',
    'row','row','row','restore','finish']);
  assert.throws(() => f.operations.output_row(0),/OriginalOutputUnavailable/);
  assert.equal(store.status().reservedBytes,0);
  assert.deepEqual(await readdir(directory),[]);
});

for (const mode of ['synchronous throw','promise rejection']) {
  test(`Relation factory ${mode} leaves no fictitious cleanup pending`, async () => {
    const f = relationFixture(), failure = new Error('RelationFactoryRejected');
    const owner = prepareLocalRelationSnapshot(f.operations,() => {
      if (mode === 'synchronous throw') throw failure;
      return Promise.reject(failure);
    },checked,undefined,moon);
    await assert.rejects(owner.roundtrip(),error => error === failure);
    assert.deepEqual(f.events,['prepare']);
    assert.deepEqual(await owner.cleanupHandle.retry(),{pending:false});
    assert.deepEqual(await owner.cleanupHandle.retry(),{pending:false});
  });
}

test('Relation cleanup retry releases the same holding without save/reload or Compute replay', async () => {
  const {directory,store} = await fileFixture();
  const f = relationFixture();
  let factories = 0, cleanups = 0;
  const owner = prepareLocalRelationSnapshot(f.operations,() => {
    factories++;
    return {...store,async cleanup() {
      if (++cleanups === 1) throw new Error('RelationCleanupRetry');
      await store.cleanup();
    }};
  },checked,undefined,moon);
  await assert.rejects(owner.roundtrip(),/RelationCleanupRetry/);
  assert.equal(owner.cleanupHandle.status().pending,true);
  assert.equal(f.events.includes('finish'),false);
  assert.equal(store.status().reservedBytes,f.identity.bytes);
  const before = [...f.events];
  await owner.cleanupHandle.retry(); await owner.cleanupHandle.retry();
  owner.close(); owner.close();
  assert.deepEqual(f.events,before);
  assert.equal(factories,1); assert.equal(cleanups,2);
  assert.equal(store.status().reservedBytes,0);
  assert.deepEqual(await readdir(directory),[]);
});

test('Relation cancellation after original output revocation retains cleanup and publishes nothing', async () => {
  const {directory,store} = await fileFixture();
  const f = relationFixture(), controller = new AbortController();
  const begin = f.operation.begin_reload;
  f.operation.begin_reload = () => {
    begin(); controller.abort(new Error('RelationReloadCancelled'));
  };
  const owner = prepareLocalRelationSnapshot(f.operations,() => store,checked,controller.signal,moon);
  await assert.rejects(owner.roundtrip(),/RelationReloadCancelled/);
  assert.throws(() => f.operations.output_row(0),/OriginalOutputUnavailable/);
  assert.equal(f.events.includes('restore'),false);
  assert.equal(f.events.includes('finish'),false);
  assert.equal(owner.cleanupHandle.status().pending,true);
  await owner.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes,0);
  assert.deepEqual(await readdir(directory),[]);
});

test('Relation Store byte-limit failure does not revoke the original output or begin reload', async () => {
  const {directory,store} = await fileFixture();
  const f = relationFixture();
  f.operation.frames.maxBytes = 8; f.operation.frames.maxFrameBytes = 8;
  const owner = prepareLocalRelationSnapshot(f.operations,() => store,checked,undefined,moon);
  await assert.rejects(owner.roundtrip(),/LocalSnapshotByteLimit/);
  assert.deepEqual(f.events,['prepare','save']);
  assert.deepEqual(f.operations.output_row(0),f.rows[0]);
  await owner.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes,0);
  assert.deepEqual(await readdir(directory),[]);
});
