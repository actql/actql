import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectOwnedPhysicalChild} from './installed-effect-owned-operation.mjs';
const ok = value => ({$tag: 1, _0: value});

// Explicit native ports: these test original custody, not real grants or I/O.
function fixture(invoke) {
  const parent = {}, prepared = {}, request = {}, plan = {}, extent = {}, token = {}, calls = [];
  let aliases = false, pending = true;
  const original = {status() {assert.strictEqual(this, original); return {pending};}};
  const runtime = {
    clientProgramInstalledEffectManagedPlanOperation(selected, member, perRow, index, operation) {
      assert.strictEqual(selected, plan); assert.deepEqual([member, perRow, index, operation], [0, true, 1, 'files.write']);
      return ok(extent);
    }, clientProgramInstalledEffectOperationExtentPhysical: selected => {assert.strictEqual(selected, extent); return true;},
    clientProgramInstalledEffectOperationExtentTransfer: selected => {assert.strictEqual(selected, extent); return 10n;},
    clientProgramInstalledEffectOperationBorrow(p, source, intent, selected, ...coordinates) {
      assert.deepEqual([p, source, intent, selected], [parent, prepared, request, plan]);
      assert.deepEqual(coordinates, [0, true, 1, 2, 'files.write']); calls.push('borrow'); return ok(token);
    }, clientProgramInstalledEffectOperationStart(selected) {assert.strictEqual(selected, token); calls.push('start'); return ok();},
    clientProgramInstalledEffectOperationCharge(selected, bytes) {assert.strictEqual(selected, token); calls.push(['charge', bytes]); return ok();},
    clientProgramInstalledEffectOperationRetire(selected, ack) {assert.strictEqual(selected, token); assert.equal(ack, true); calls.push('retire'); return ok(true);},
  };
  const run = {runtime, value: parent, prepared, request, operationPlan: plan, readPlan: () => ok(plan)};
  const create = () => prepareInstalledEffectOwnedPhysicalChild({run, memberIndex: 0, rowIndex: 2,
    operationIndex: 1, operation: 'files.write', transferBytes: 10n,
    invoke: context => invoke(context, original, calls), requestsRetired: () => aliases});
  return {create, run, runtime, original, calls, close() {pending = false;}, retireAliases() {aliases = true;}};
}

test('same physical child starts once and charges chunks without a second writer or cleanup owner', async () => {
  const f = fixture(({retainPhysicalChild, chargeBytes}, original, calls) => {
    assert.deepEqual(calls, ['borrow']); retainPhysicalChild(original);
    chargeBytes(3n); calls.push('write3'); chargeBytes(2n); calls.push('write2'); return 'same observation';
  });
  const child = f.create(); assert.equal(await child.prepare(), 'same observation');
  assert.deepEqual(f.calls, ['borrow', 'start', ['charge', 3n], 'write3', ['charge', 2n], 'write2']);
  f.retireAliases(); assert.equal(child.release(), false, 'original physical close is still pending');
  f.close(); assert.equal(child.retry(), true); assert.equal(child.status().pending, false);
  assert.equal(f.calls.at(-1), 'retire');
  await assert.rejects(child.prepare(), {code: 'InstalledEffectOperationAlreadyPrepared'});
});

test('original undefined failure keeps its physical child until actual cleanup and request retirement', async () => {
  const f = fixture(({retainPhysicalChild}, original) => {retainPhysicalChild(original); throw undefined;});
  const child = f.create(); let caught = false;
  try {await child.prepare();} catch (error) {caught = true; assert.equal(error, undefined);}
  assert(caught); f.close(); assert.equal(child.release(), false);
  f.retireAliases(); assert.equal(child.retry(), true);
  assert.deepEqual(f.calls, ['borrow', 'start', 'retire']);
});

test('same physical operation retains in-flight task and refuses a second child or unstarted charge', async () => {
  let release;
  const wait = new Promise(resolve => {release = resolve;});
  const f = fixture(async ({retainPhysicalChild, chargeBytes}, original) => {
    assert.throws(() => chargeBytes(1n), {code: 'ForeignInstalledEffectPhysicalChild'});
    retainPhysicalChild(original);
    assert.throws(() => retainPhysicalChild({}), {code: 'ForeignInstalledEffectPhysicalChild'});
    await wait; return 'done';
  });
  const child = f.create(), flight = child.prepare();
  f.close(); f.retireAliases(); assert.equal(child.release(), false);
  release(); assert.equal(await flight, 'done'); assert.equal(child.retry(), true);
});

test('physical extent refusal precedes any borrow and foreign Run cannot dispatch', async () => {
  const f = fixture(() => assert.fail('must not invoke'));
  f.runtime.clientProgramInstalledEffectOperationExtentTransfer = () => 9n;
  assert.throws(f.create, {code: 'InsufficientInstalledEffectOperationTransfer'}); assert.deepEqual(f.calls, []);
  f.runtime.clientProgramInstalledEffectOperationExtentTransfer = () => 10n;
  const child = f.create(); f.run.value = {};
  await assert.rejects(child.prepare(), {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(f.calls, ['borrow']); f.retireAliases(); assert.equal(child.release(), true);
});

test('physical child method observation cannot reenter close and then start I/O', async () => {
  let child, f;
  f = fixture(({retainPhysicalChild}, original) => {
    const status = original.status;
    Object.defineProperty(original, 'status', {get() {assert.equal(child.release(), false); return status;}});
    retainPhysicalChild(original); assert.fail('must not start physical work after close');
  });
  child = f.create(); await assert.rejects(child.prepare(), {code: 'InstalledEffectOperationAlreadyPrepared'});
  assert.deepEqual(f.calls, ['borrow']); f.close(); f.retireAliases(); assert.equal(child.retry(), true);
});
