import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';

function beforeInstallation({failClose = false, retainedBytes = 0n, abort = false} = {}) {
  const setup = {};
  const cause = new Error('InjectedBeforeDriverOwnership');
  const controller = new AbortController();
  let owner, stops = 0, closes = 0, reservations = retainedBytes;
  const moon = {
    clientProgramResultCount: () => 0,
    clientProgramOpenCapturedComposedInferHost: () => setup,
    strategyHostStop(actual) {assert.equal(actual, setup); stops++;},
    strategyHostCloseOutputs(actual) {
      assert.equal(actual, setup); closes++;
      if (failClose && closes === 1) throw cause;
    },
    strategyHostUsage(actual) {
      assert.equal(actual, setup);
      return [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, reservations, 0n, 0n];
    },
  };
  return {
    cause, controller,
    arguments: {
      moon, selected: {components: []}, preparedProgram: {},
      plan: {runDefinition: {wire: '{"run_id":"original-run"}'}},
      acquiredInfer: {captured: {capture: {source: () => ({})}}},
      modelController: {discover: () => []}, computeConfigurations: {},
      signal: controller.signal,
      retainExecution(value) {assert.equal(owner, undefined); owner = value;},
      beginPhysicalWork() {
        assert.ok(owner, 'retain custody before the asynchronous driver boundary');
        if (abort) controller.abort(cause);
        else throw cause;
      },
    },
    owner: () => owner,
    counts: () => ({stops, closes}),
    releaseReservations() {reservations = 0n;},
  };
}

test('composed setup keeps the original Owner when start fails before driver installation', async () => {
  const boundary = beforeInstallation();
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  const owner = boundary.owner();
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.equal(owner.cleanupPending(), false);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1});
  assert.equal(await owner.close(), true);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1}, 'successful cleanup is not repeated');
});

test('composed setup retains failed output close and retries the same exact setup', async () => {
  const boundary = beforeInstallation({failClose: true});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  const owner = boundary.owner();
  await assert.rejects(owner.close(), error => error === boundary.cause);
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.deepEqual(boundary.counts(), {stops: 2, closes: 2});
  assert.equal(owner.cleanupPending(), false);
});

test('composed setup does not report release while its retained reservations remain', async () => {
  const boundary = beforeInstallation({retainedBytes: 64n});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments));
  const owner = boundary.owner();
  assert.equal(await owner.cleanup(), false);
  assert.equal(owner.cleanupPending(), true);
  boundary.releaseReservations();
  assert.equal(await owner.cleanup(), true);
  assert.equal(owner.cleanupPending(), false);
  assert.deepEqual(boundary.counts(), {stops: 2, closes: 2});
});

test('composed cleanup retains the actual reserved-attempt and holding fields', async () => {
  for (const index of [2, 3]) {
    const boundary = beforeInstallation();
    const original = boundary.arguments.moon.strategyHostUsage;
    let pending = true;
    boundary.arguments.moon.strategyHostUsage = actual => {
      original(actual);
      const values = Array(13).fill(0n);
      if (pending) values[index] = 1n;
      return values;
    };
    await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
    assert.equal(await boundary.owner().cleanup(), false);
    assert.equal(boundary.owner().cleanupPending(), true);
    pending = false;
    assert.equal(await boundary.owner().cleanup(), true);
  }
});

test('composed cleanup does not retain spent transfer or historical peak as a live resource', async () => {
  const boundary = beforeInstallation();
  const original = boundary.arguments.moon.strategyHostUsage;
  boundary.arguments.moon.strategyHostUsage = actual => {
    original(actual);
    return [7n, 3n, 0n, 0n, 0n, 0n, 83n, 0n, 0n, 0n, 0n, 0n, 211n];
  };
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  assert.equal(await boundary.owner().cleanup(), true);
  assert.equal(boundary.owner().cleanupPending(), false);
});

test('composed setup is retained across the actual captured driver early AbortSignal check', async () => {
  const boundary = beforeInstallation({abort: true});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  assert.equal(boundary.controller.signal.aborted, true);
  const owner = boundary.owner();
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1});
});

// Isolate a cached driver close failure without changing the real early-abort
// test above or adding a product dependency-injection execution path.
test('composed driver cleanup recovers without awaiting its rejected close again', () => {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import {registerHooks} from 'node:module';
    const cause = new Error('InjectedDriverClose');
    const rejected = Promise.reject(cause);
    rejected.catch(() => {});
    let closes = 0, retries = 0, pending = true, owner;
    globalThis.composedTestExecution = {
      status: 'host-tasks-failed',
      close() {closes++; return rejected;},
      cleanupPending: () => pending,
      async cleanup() {retries++; pending = false; return true;},
    };
    const entry = new URL('./adapters/host-node/entry.mjs', 'file://' + process.cwd() + '/').href;
    const hook = registerHooks({load(url, context, next) {
      if (url === entry) return {format: 'module', shortCircuit: true,
        source: 'export async function runCapturedStrategy() {return globalThis.composedTestExecution;}'};
      return next(url, context);
    }});
    const {runInstalledComposedInfers} = await import('./adapters/host-node/installed-composed-infer-run.mjs');
    hook.deregister();
    const setup = {};
    const moon = {clientProgramResultCount: () => 0,
      clientProgramOpenCapturedComposedInferHost: () => setup,
      strategyHostStop() {assert.fail('returned execution owns the setup');}};
    await assert.rejects(runInstalledComposedInfers({
      moon, selected: {components: []}, preparedProgram: {},
      plan: {runDefinition: {wire: '{"run_id":"original-run"}'}},
      acquiredInfer: {captured: {capture: {source: () => ({})}}},
      modelController: {discover: () => [], unresolved: () => false},
      computeConfigurations: {}, signal: new AbortController().signal,
      retainExecution(value) {owner = value;}, beginPhysicalWork() {},
    }), {message: 'InstalledComposedInferComputationFailed'});
    await assert.rejects(owner.close(), error => error === cause);
    assert.equal(owner.cleanupPending(), true);
    assert.equal(await owner.cleanup(), true);
    assert.equal(owner.cleanupPending(), false);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
    assert.equal(await owner.close(), true);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
  `], {cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8', timeout: 30000});
  assert.equal(child.status, 0, child.stdout + child.stderr);
});
