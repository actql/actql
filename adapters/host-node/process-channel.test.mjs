import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareManagedExecution, startManagedExecution } from './process-channel.mjs';
import {encodeProcessFrame, executionProtocol} from './process-frames.mjs';
import {pathToFileURL} from 'node:url';

const configuration = () => ({
  entry: new URL('./process-fixture.mjs', import.meta.url), run: 'owned-run',
  frames: { maxBytes: 4096, maxNodes: 100, maxDepth: 10 },
  maxRequests: 4, graceMs: 50, startupMs: 5000,
});

test('pure preparation snapshots configuration and is consumed by exactly one launch', async t => {
  const config = configuration();
  const prepared = prepareManagedExecution(config);
  config.entry.pathname = '/missing-executor.mjs';
  config.run = 'changed-run';
  config.frames.maxBytes = 1;
  const channel = await startManagedExecution(prepared);
  t.after(() => channel.close());
  assert.equal(channel.identity().run, 'owned-run');
  assert.equal((await channel.request({command: 'echo', value: 3})).value, 3);
  await assert.rejects(startManagedExecution(prepared));
});

test('managed execution uses a separate process and bounded sequential requests', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  const first = await channel.request({ command: 'echo', value: 'a' });
  assert.notEqual(first.pid, process.pid);
  assert.equal(first.value, 'a');
  const second = await channel.request({ command: 'echo', value: 'b' });
  assert.equal(second.pid, first.pid);
  assert.equal(channel.status().requests, 2);
  assert.equal(channel.cleanupHandle.status().pending, true);
  await channel.close();
  assert.equal(channel.status().exited, true);
  assert.equal(channel.cleanupHandle.status().pending, false);
});

test('trusted interpreter URL is snapshotted with the existing process owner', async t => {
  const runtime = pathToFileURL(process.execPath);
  const prepared = prepareManagedExecution({...configuration(), runtime});
  runtime.pathname = '/missing-interpreter';
  const channel = await startManagedExecution(prepared);
  t.after(() => channel.close());
  assert.notEqual((await channel.request({command: 'echo', value: 1})).pid, process.pid);
  await channel.close();
  assert.equal(channel.cleanupHandle.status().pending, false);
});

test('interpreter configuration rejects non-file input and retains failed-spawn cleanup', async () => {
  for (const runtime of ['python', new URL('https://example.invalid/python')]) {
    assert.throws(() => prepareManagedExecution({...configuration(), runtime}),
      {code: 'InvalidExecutionConfiguration'});
  }
  let error;
  try {
    await startManagedExecution({...configuration(), runtime: new URL('file:///missing-interpreter')});
  } catch (caught) { error = caught; }
  assert.equal(error.code, 'ExecutionSpawnFailure');
  await error.cleanupHandle.retry();
  assert.equal(error.cleanupHandle.status().pending, false);
});

test('invalid request is correctable without consuming the sequence', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'echo', value: 'x'.repeat(5000) }), { code: 'FrameByteLimit' });
  assert.equal(channel.status().requests, 0);
  assert.equal((await channel.request({ command: 'echo', value: 1 })).value, 1);
});

test('control wire counters include exact UTF8 envelopes but not rejected unsent requests', async t => {
  const config = configuration();
  const channel = await startManagedExecution(config);
  t.after(() => channel.close());
  const {session, run} = channel.identity();
  const bytes = (kind, sequence, body) => BigInt(encodeProcessFrame(
    {protocol: executionProtocol, session, run, kind, sequence, body}, config.frames).byteLength);
  const initial = channel.status().transport;
  assert.equal(BigInt(initial.submittedBytes), bytes('hello', 0, null));
  assert.equal(BigInt(initial.receivedBytes), bytes('ready', 0, null));
  await assert.rejects(channel.request({command: 'echo', value: 'x'.repeat(5000)}), {code: 'FrameByteLimit'});
  assert.deepEqual(channel.status().transport, initial);
  const request = {command: 'echo', value: '日本語🙂'};
  const response = await channel.request(request);
  const after = channel.status().transport;
  assert.equal(BigInt(after.submittedBytes), bytes('hello', 0, null) + bytes('execute', 1, request));
  assert.equal(BigInt(after.receivedBytes), bytes('ready', 0, null) + bytes('reply', 1, response));
  await channel.close();
  assert.equal(BigInt(channel.status().transport.submittedBytes),
    BigInt(after.submittedBytes) + bytes('stop', 1, null));
  assert.equal(initial.submittedBytes, String(bytes('hello', 0, null)), 'status snapshots remain immutable');
});

test('undefined rejection is failure and prevents another dispatch', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'undefined-failure' }), { code: 'ExecutionFailed' });
  await assert.rejects(channel.request({ command: 'echo', value: 1 }), { code: 'ExecutionNotReady' });
  await channel.close();
});

test('cancelled unstarted requests consume nothing; running cancellation retains cleanup until exit', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'echo', value: 1 }, AbortSignal.abort()));
  assert.equal(channel.status().requests, 0);
  const controller = new AbortController();
  const work = channel.request({ command: 'wait' }, controller.signal);
  const rejected = assert.rejects(work, { code: 'ExecutionCancelled' });
  controller.abort();
  assert.equal(channel.cleanupHandle.status().pending, true);
  await rejected;
  await channel.cleanupHandle.retry();
  assert.equal(channel.status().exited, true);
});

test('noncooperative process is terminated without pretending cancellation settled it', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  const work = channel.request({ command: 'hang' });
  const rejected = assert.rejects(work, { code: 'ExecutionExited' });
  assert.equal(channel.status().exited, false);
  await channel.close();
  await rejected;
  assert.equal(channel.status().exit.signal, 'SIGKILL');
});

test('spawn and handshake failures retain an explicit process cleanup handle', async () => {
  let error;
  try { await startManagedExecution({ ...configuration(), entry: new URL('./missing-executor.mjs', import.meta.url) }); }
  catch (caught) { error = caught; }
  assert.ok(error);
  assert.equal(typeof error.cleanupHandle.retry, 'function');
  await error.cleanupHandle.retry();
  assert.equal(error.cleanupHandle.status().pending, false);
});

for (const corrupt of ['run', 'session', 'sequence', 'extra']) {
  test(`foreign ${corrupt} response cannot authorize another request`, async t => {
    const channel = await startManagedExecution({
      ...configuration(), entry: new URL('./foreign-process-fixture.mjs', import.meta.url),
    });
    t.after(() => channel.close());
    await assert.rejects(channel.request({ corrupt }), {
      code: corrupt === 'sequence' ? 'UnexpectedExecutionMessage' : 'ForeignExecutionMessage',
    });
    assert.equal(channel.status().stopped, true);
    assert.equal(channel.status().requests, 1);
    await assert.rejects(channel.request({ corrupt }), { code: 'ExecutionNotReady' });
    await channel.cleanupHandle.retry();
    assert.equal(channel.cleanupHandle.status().pending, false);
  });
}

for (const corrupt of ['missing-usage', 'usage-run', 'usage-session', 'usage-sequence', 'usage-terminal', 'usage-duplicate']) {
  test(`delegated channel rejects ${corrupt} independently of ordinary reply contents`, async t => {
    let reports = 0;
    const channel = await startManagedExecution({...configuration(),
      entry: new URL('./foreign-process-fixture.mjs', import.meta.url),
      accounting: {limits: {planning_work: 0, attempts: 1, holdings: 0,
        transfer_bytes: 0n, retained_bytes: 0n, execution_bytes: 1n},
      report: () => { reports++; }},
    });
    t.after(() => channel.close());
    await assert.rejects(channel.request({corrupt}), {
      code: corrupt === 'missing-usage' ? 'MissingExecutionAccounting'
        : ['usage-run', 'usage-session'].includes(corrupt) ? 'ForeignExecutionMessage' : 'InvalidExecutionAccounting',
    });
    assert.equal(reports, corrupt === 'usage-duplicate' ? 1 : 0);
    await assert.rejects(channel.request({corrupt}), {code: 'ExecutionNotReady'});
  });
}


test('installed handoff runs once only after preparation and abort refusals', async t => {
  let entries = 0;
  const enter = () => { entries++; };
  await assert.rejects(startManagedExecution({...configuration(), startupMs: 0}, undefined, enter));
  await assert.rejects(startManagedExecution(configuration(), AbortSignal.abort(), enter));
  await assert.rejects(startManagedExecution(configuration(), undefined, {}), /InvalidExecutionHandoff/);
  assert.equal(entries, 0);
  const prepared = prepareManagedExecution(configuration());
  const channel = await startManagedExecution(prepared, undefined, enter);
  t.after(() => channel.close());
  assert.equal(entries, 1);
  assert.notEqual((await channel.request({command: 'echo', value: 1})).pid, process.pid);
  await assert.rejects(startManagedExecution(prepared, undefined, enter));
  assert.equal(entries, 1);
  await channel.close();
  assert.equal(entries, 1);
});

test('rejected handoff consumes its prepared token without launching or replaying', async t => {
  const childProcess = (await import('node:child_process')).default;
  const {syncBuiltinESMExports} = await import('node:module');
  const originalSpawn = childProcess.spawn;
  let spawns = 0;
  t.mock.method(childProcess, 'spawn', (...args) => {
    spawns++;
    return originalSpawn(...args);
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  const prepared = prepareManagedExecution(configuration());
  let entries = 0;
  const rejected = new Error('OriginalDebitRefused');
  await assert.rejects(startManagedExecution(prepared, undefined, () => {
    entries++;
    throw rejected;
  }), error => error === rejected && error.cleanupHandle === undefined);
  await assert.rejects(startManagedExecution(prepared, undefined, () => { entries++; }));
  assert.equal(entries, 1);
  const abort = new AbortController();
  await assert.rejects(startManagedExecution(configuration(), abort.signal, () => {
    abort.abort(rejected);
  }), error => error === rejected && error.cleanupHandle === undefined);
  await assert.rejects(startManagedExecution(configuration(), undefined, async () => {
    throw rejected;
  }), /InvalidExecutionHandoff/);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(spawns, 0);
});

test('prepared process retains the original synchronous body backing entry through handshake and response', async t => {
  const lengths=[];
  const config={...configuration(),beforeBodyAllocation(length){lengths.push(length);}};
  const prepared=prepareManagedExecution(config);
  config.beforeBodyAllocation=()=>assert.fail('a replaced configuration cannot supply another original');
  assert.deepEqual(lengths,[],'pure configuration preparation receives no frame');
  const channel=await startManagedExecution(prepared);
  t.after(()=>channel.close());
  assert.equal(lengths.length,1,'the original ready frame is backed too');
  const original='e\u0301\r\n';
  assert.equal((await channel.request({command:'echo',value:original})).value,original);
  assert.equal(lengths.length,2);
  assert(lengths.every(value=>Number.isSafeInteger(value)&&value>0&&value<=config.frames.maxBytes));
  await channel.close();assert.equal(channel.status().exited,true);assert.equal(channel.cleanupHandle.status().pending,false);
});

for(const [kind,original] of [['frozen',Object.freeze(new Error('OriginalBodyBackingRefusal'))],['undefined',undefined]]){
  test(`process body backing ${kind} refusal retains original cause and SAME exit cleanup`,async()=>{
    let entries=0,failure;
    try{await startManagedExecution({...configuration(),beforeBodyAllocation(){entries++;throw original;}});}
    catch(error){failure=error;}
    assert.equal(entries,1);assert.equal(failure.code,'ExecutionChannelFailure');
    assert.equal(Object.hasOwn(failure,'cause'),true);assert.strictEqual(failure.cause,original);
    const cleanup=failure.cleanupHandle;assert.equal(typeof cleanup.retry,'function');
    await cleanup.retry();assert.strictEqual(failure.cleanupHandle,cleanup);assert.equal(cleanup.status().pending,false);
    assert.strictEqual(failure.cause,original);
  });
}

test('returned asynchronous body backing never admits a frame or releases its process cleanup early', async () => {
  let release;
  const original=new Promise(resolve=>{release=resolve;});
  let channel,failure;
  try {
    try{channel=await startManagedExecution({...configuration(),beforeBodyAllocation(){return original;}});}
    catch(error){failure=error;}
    if(failure===undefined){await channel.close();assert.fail('an asynchronous backing handoff cannot dispatch ready');}
    assert.equal(failure.code,'ExecutionChannelFailure');
    assert.equal(failure.cause?.message,'InvalidFrameCapacityHandoff');
    const cleanup=failure.cleanupHandle;
    const finishing=cleanup.retry();
    await cleanup.whenStopped();
    assert.equal(cleanup.status().pending,true,'process exit alone cannot retire the original callback task');
    release();await finishing;
    assert.equal(cleanup.status().pending,false);
  } finally {release();if(channel)await channel.close();}
});

test('declared async frame entry is refused during inert process preparation', () => {
  let calls=0;
  assert.throws(()=>prepareManagedExecution({...configuration(),async beforeBodyAllocation(){calls++;}}),{code:'InvalidExecutionConfiguration'});
  assert.equal(calls,0);
});

test('Table bridge forwards the same read body backing entry to the original process owner', async () => {
  const {createIcebergPhysicalBridge}=await import('../connectors/local/host/iceberg-process.mjs');
  const cid=digit=>`sha256:${digit.repeat(64)}`;
  const bridge=createIcebergPhysicalBridge({python:pathToFileURL(process.execPath),run:'table-backing-read',
    entry:new URL('./process-fixture.mjs',import.meta.url),
    catalog:{database:'/UNOPENED/table.db',warehouse:'/UNOPENED/warehouse',catalogCid:cid('a'),limits:{bytes:1,files:1,operations:1}}});
  const original=Object.freeze(new Error('OriginalTableBodyBackingRefusal'));let calls=0,failure;
  try{await bridge.read({}, {}, undefined,()=>{calls++;throw original;});}catch(error){failure=error;}
  try{assert.equal(calls,1);assert.strictEqual(failure?.cause,original);assert.equal(failure.cleanupHandle.status().pending,false);}
  finally{if(failure?.cleanupHandle)await failure.cleanupHandle.retry();}
});

test('Table prepared and readonly operations keep the original per-call body entry outside wire DATA', async () => {
  const [{createIcebergPhysicalBridge},{createHash}]=await Promise.all([
    import('../connectors/local/host/iceberg-process.mjs'),import('node:crypto')]);
  const cid=digit=>`sha256:${digit.repeat(64)}`;
  const original=Object.freeze(new Error('OriginalTableBodyBackingRefusal'));let calls=0;
  const beforeBodyAllocation=()=>{calls++;throw original;};
  const make=()=>createIcebergPhysicalBridge({python:pathToFileURL(process.execPath),run:'table-backing-prepared',
    entry:new URL('./process-fixture.mjs',import.meta.url),
    catalog:{database:'/UNOPENED/table.db',warehouse:'/UNOPENED/warehouse',catalogCid:cid('a'),limits:{bytes:1,files:1,operations:1}}});
  const refused=async action=>{
    const before=calls;let failure;
    try{await action();}catch(error){failure=error;}
    try{assert.equal(calls,before+1);assert.strictEqual(failure?.cause,original);assert.equal(failure.cleanupHandle.status().pending,false);}
    finally{if(failure?.cleanupHandle)await failure.cleanupHandle.retry();}
  };
  const bridge=make();
  const selector={catalog_identity_cid:cid('a'),namespace:['analytics'],table_name:'rows',
    table_uuid:'00000000-0000-0000-0000-000000000001',schema_cid:cid('b')};
  await refused(()=>bridge.resolveGeneration(selector,undefined,beforeBodyAllocation));
  await refused(()=>bridge.reconcileOperation({request_cid:cid('c')},undefined,beforeBodyAllocation));
  // A transport-bound shape only: no Common Mapping/operation admission or
  // Catalog command is supplied, and the first incoming ready frame refuses.
  const schemaWire='{"fields":[]}',schemaCid=`sha256:${createHash('sha256').update(schemaWire).digest('hex')}`;
  const input={operation:{action:'create',request_cid:cid('c'),schema_cid:schemaCid,input_carrier:{kind:'relation',cid:cid('d')}},
    mapping:{},rows:[],reservation:{bytes:1,files:1},schemaWire,beforeBodyAllocation};
  const prepared=bridge.prepareWrite(input);
  input.beforeBodyAllocation=()=>assert.fail('mutated DATA cannot replace the selected original');
  await refused(()=>bridge.inspect(prepared));
  await refused(()=>bridge.execute(prepared,{useCid:cid('e')}));
  assert.deepEqual(bridge.status(prepared),{attempted:true,stopped:true});
  await refused(()=>bridge.reconcile(prepared));
  await refused(()=>bridge.cleanup(prepared));
  assert.equal(calls,6);
});

test('Table original pending body callback custody cannot become a stopped writer after process exit', async () => {
  const [{createIcebergPhysicalBridge},{createHash}] = await Promise.all([
    import('../connectors/local/host/iceberg-process.mjs'),import('node:crypto')]);
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const bridge = createIcebergPhysicalBridge({python:pathToFileURL(process.execPath),run:'table-pending-body',
    entry:new URL('./process-fixture.mjs',import.meta.url),
    catalog:{database:'/UNOPENED/table.db',warehouse:'/UNOPENED/warehouse',catalogCid:cid('a'),
      limits:{bytes:1,files:1,operations:1}}});
  // A foreign thenable is neither assimilated nor promoted to a settled
  // callback. No Python/Catalog/resource/ordinary operation is supplied here.
  const original = Object.freeze({then() {assert.fail('foreign callback result cannot be assimilated');}});
  const schemaWire = '{"fields":[]}', schemaCid = `sha256:${createHash('sha256').update(schemaWire).digest('hex')}`;
  const prepared = bridge.prepareWrite({operation:{action:'create',request_cid:cid('c'),schema_cid:schemaCid,
    input_carrier:{kind:'relation',cid:cid('d')}},mapping:{},rows:[],reservation:{bytes:1,files:1},schemaWire,
    beforeBodyAllocation() {return original;}});
  let failure;
  try {await bridge.execute(prepared,{useCid:cid('e')});} catch (error) {failure = error;}
  assert.equal(failure?.code,'ExecutionChannelFailure');
  assert.equal(failure.cause?.message,'InvalidFrameCapacityHandoff');
  const cleanup = failure.cleanupHandle;
  await cleanup.whenStopped();
  assert.equal(cleanup.status().pending,true,'the original callback duty survives actual process exit');
  assert.deepEqual(bridge.status(prepared),{attempted:true,stopped:false});
  assert.strictEqual(failure.cleanupHandle,cleanup);
  await assert.rejects(bridge.cleanup(prepared),{code:'TableWriterNotStopped'});
  assert.equal(cleanup.status().pending,true);
});

test('Table pure body callback refusal before launcher selection has no physical cleanup debt', async () => {
  const [{createIcebergPhysicalBridge},{createHash}] = await Promise.all([
    import('../connectors/local/host/iceberg-process.mjs'),import('node:crypto')]);
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const bridge = createIcebergPhysicalBridge({python:pathToFileURL(process.execPath),run:'table-inert-body',
    entry:new URL('./process-fixture.mjs',import.meta.url),
    catalog:{database:'/UNOPENED/table.db',warehouse:'/UNOPENED/warehouse',catalogCid:cid('a'),
      limits:{bytes:1,files:1,operations:1}}});
  const schemaWire = '{"fields":[]}', schemaCid = `sha256:${createHash('sha256').update(schemaWire).digest('hex')}`;
  let called = false;
  const prepared = bridge.prepareWrite({operation:{action:'create',request_cid:cid('c'),schema_cid:schemaCid,
    input_carrier:{kind:'relation',cid:cid('d')}},mapping:{},rows:[],reservation:{bytes:1,files:1},schemaWire,
    async beforeBodyAllocation() {called = true;}});
  await assert.rejects(bridge.execute(prepared,{useCid:cid('e')}),{code:'InvalidExecutionConfiguration'});
  assert.equal(called,false);
  assert.deepEqual(bridge.status(prepared),{attempted:true,stopped:true});
});
