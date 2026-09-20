import assert from 'node:assert/strict';
import test from 'node:test';
import {installStrategyContributions} from '../adapters/connectors-builtin/strategy.generated.mjs';
import '../adapters/host-node/installation.test.mjs';

test('Node installation touches only the configured module subset', async () => {
  const setup = {};
  const registration = {};
  const task = {};
  let executions = 0;
  const moon = new Proxy({
    strategyHostBeginManagedFailureProgress: () => ({}),
    strategyHostRecordManagedFailureAdditionalClosed: () => true,
    strategyHostRecordManagedFailureOperationsCloseAttempted: () => true,
    strategyHostRecordManagedFailureOperationsClosed: () => true,
    strategyHostRecordManagedFailureCleanupStopped: () => true,
    strategyHostRecordManagedFailureExecutionSettled: () => true,
    strategyHostRecordManagedFailureCleanupRefreshed: () => true,
    strategyHostManagedFailureAction: () => 5,
    strategyHostModules: value => { assert.equal(value, setup); return ['local']; },
    strategyModule_local_Registration: value => { assert.equal(value, setup); return registration; },
    strategyHostRegistrationSelectionKey: value => {
      assert.equal(value, registration);
      return 'local-test';
    },
    strategyModule_local_Dispatch: (owner, value) => {
      assert.equal(owner, setup); assert.equal(value, task); executions++;
      return {inputs: [], execute() {}, settle() {}, complete() {}, close() {}};
    },
  }, {
    get(target, key) {
      assert.ok(Object.hasOwn(target, key), `Absent module accessed ${String(key)}`);
      return target[key];
    },
  });
  const options = new Proxy({}, {get() { throw new Error('Absent module read settings'); }});
  const entries = await installStrategyContributions(moon, setup, value => value, {duckdb: options});
  assert.equal(entries.length, 1);
  assert.equal(entries[0].registration, registration);
  await entries[0].run(task);
  assert.equal(executions, 1);
  assert.equal(entries[0].finish, undefined);
  assert.ok(Object.isFrozen(entries));
});

test('empty installation invokes no factory and malformed subsets fail before any factory', async () => {
  for (const keys of [[], ['local', 'local'], ['local', 'not-installed'], undefined]) {
    let configured = 0;
    const moon = {
      strategyHostModules: () => keys,
      strategyModule_local_Registration: () => { configured++; return {}; },
    };
    if (Array.isArray(keys) && keys.length === 0) {
      assert.deepEqual(await installStrategyContributions(moon, {}, x => x), []);
    } else {
      await assert.rejects(installStrategyContributions(moon, {}, x => x), /unique Node implementation/);
    }
    assert.equal(configured, 0);
  }
});
