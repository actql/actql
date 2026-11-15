import assert from 'node:assert/strict';
import test from 'node:test';
import resources from './ordinary-node-resource-runtime.cjs';
import {createLocalResultReadWorkspace} from './local-result-read-workspace.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';

// Actual JS workspace/open/cleanup adapter with explicit Core ports. This
// does not issue a Common original or certify physical reader/FD completion.
const ok = value => ({$tag: 1, _0: value});
function fixture({polls = 2, refuse, current = () => {}, payloadBytes = 8192} = {}) {
  const calls = [], request = {}, parent = {}, runtime = {};
  let ports, high = 0, count = 0;
  const method = (name, body) => runtime[name] = function(...args) {
    assert.equal(this, runtime);
    calls.push([name, ...args]);
    return body(...args);
  };
  runtime.clientLocalResourcePolicyOriginal = () => ({});
  runtime.clientLocalPreparationResourceLimits = () => [100000n, 1n, 1n, 0n, 1048576n, 1048576n];
  runtime.clientProgramPrepareLocalPreparationAdmission = (original, input) => {
    ports = resources.prepareOriginalLocalPreparationPorts(original, input);
    assert.equal(ports.status(0), 0);
    return ok({});
  };
  runtime.clientProgramBeginRequestPreparation = () => ok(parent);
  runtime.clientProgramAbortRequestPreparation = value => {
    assert.equal(value, parent);
    calls.push(['abort']);
    assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
    assert.equal(ports.status(2), 0);
    return ok(undefined);
  };
  method('clientProgramReserveRequestResultRead', () => ok(64));
  method('clientProgramBeginRequestResultReadWire', (p, r, bytes, rows) => {
    assert.equal(p, parent); assert.equal(r, request);
    assert.equal(bytes, BigInt(payloadBytes)); assert.equal(rows, 1);
    return ok(undefined);
  });
  method('clientProgramGrowRequestResultReadFrame', (p, r, units) => {
    assert.equal(p, parent); assert.equal(r, request);
    high = units;
    return ok({_0: high, _1: 64});
  });
  method('clientProgramBeginRequestResultReadWireRow', (p, r, wire) => {
    assert.equal(p, parent); assert.equal(r, request); assert.equal(typeof wire, 'string');
    return ok(undefined);
  });
  method('clientProgramAdvanceRequestResultReadWireRow', (p, r, quantum) => {
    assert.equal(p, parent); assert.equal(r, request); assert.equal(quantum, 4096);
    if (refuse) return {$tag: 0, _0: refuse};
    return ok({_0: ++count >= polls, _1: high, _2: 64});
  });
  for (const name of ['ReserveRequestResultMetadata', 'RetainRequestResultMetadataData',
    'ReleaseRequestResultMetadata', 'FinishRequestResultMetadata', 'ReconcileRequestResultReadSerializer']) {
    runtime[`clientProgram${name}`] = () => ok(undefined);
  }
  const workspace = createLocalResultReadWorkspace({runtime, assertCurrent: current});
  workspace.begin(request);
  workspace.prepare(request, {payloadBytes, rowCount: 1, resultSchemaWire: '{}', resultFields: []},
    {maxNodes: 8192, maxWireBytes: 8192}, {maxRowBytes: 8192, maxFrameBytes: 64});
  return {workspace, request, runtime, calls};
}

test('READ workspace captures original frame/wire methods and yields before parse readiness', async () => {
  const f = fixture();
  for (const name of ['GrowRequestResultReadFrame', 'BeginRequestResultReadWireRow', 'AdvanceRequestResultReadWireRow']) {
    f.runtime[`clientProgram${name}`] = () => assert.fail('method was looked up again');
  }
  assert.deepEqual(f.workspace.row(f.request, 8192), {units: 8192, window: 64});
  const wire = '"' + 'x'.repeat(5000) + '"';
  const pending = f.workspace.row(f.request, wire);
  assert.equal(f.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 1);
  assert.deepEqual(await pending, {units: 8192, window: 64});
  assert.equal(f.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 2);
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
});

test('READ workspace retains typed preflight refusal and current failure before serializer', async () => {
  const original = {}, f = fixture({refuse: original});
  f.workspace.row(f.request, 8192);
  await assert.rejects(f.workspace.row(f.request, '[]'), error => error.cause === original);
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  let deny = false;
  const cause = new Error('current changed'), changed = fixture({current() {if (deny) throw cause;}});
  changed.workspace.row(changed.request, 8192);
  const read = changed.workspace.row(changed.request, '[]');
  deny = true;
  await assert.rejects(read, error => error === cause);
  assert.equal(changed.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 1);
  changed.workspace.close(changed.request);
  assert.deepEqual(await changed.workspace.closeAll(), {pending: false});
});

test('READ close cannot retire the same parent while a yielded original row callback is live', async () => {
  const f = fixture();
  f.workspace.row(f.request, 8192);
  const row = f.workspace.row(f.request, '[]');
  f.workspace.close(f.request);
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 0);
  assert.deepEqual(await f.workspace.closeAll(), {pending: true});
  await assert.rejects(row, {code: 'ForeignResultReadWorkspace'});
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
});

test('READ aggregate work envelope stays wide while row and frame sizes remain bounded', async () => {
  const f = fixture({polls: 1, payloadBytes: 2147483648});
  f.workspace.row(f.request, 64);
  assert.deepEqual(await f.workspace.row(f.request, '[]'), {units: 64, window: 64});
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
});

// Both owners are real imported consumers; Core row/Resource responses remain
// explicit ports, so this does not establish a physical Result reader ACK.
test('Host shutdown keeps a yielded READ on its same parent until original row cleanup finishes', async () => {
  const f = fixture(); let finalizers = 0;
  f.workspace.row(f.request, 8192);
  const row = f.workspace.row(f.request, '[]');
  f.workspace.close(f.request);
  const shutdown = installedHostShutdown({dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {}},
    initialControl: {close() {return f.workspace.closeAll();}},
    retireModelRuntime() {finalizers++;}});
  await assert.rejects(shutdown.close(), {message: 'InstalledHostInitialControlCleanupPending'});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 0);
  assert.equal(finalizers, 0);
  await assert.rejects(row, {code: 'ForeignResultReadWorkspace'});
  await shutdown.close();
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
  assert.equal(finalizers, 1);
  await shutdown.close();
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
  assert.equal(finalizers, 1);
});
