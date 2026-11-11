import assert from 'node:assert/strict';
import {openAcquiredEffectComputation as openEffectComputation} from '../acquired-effect-computation.mjs';

// These failure fixtures stop before the compiled runtime. Their nominal
// Plan, Request and Ledger ports do not issue real funding or provider custody.
export const openAcquiredEffectComputation = options => {
  const {sourceRefs = ['selected'], rowSourceTasks = [], ...original} = options;
  const prepared = original.acquired.prepared;
  const request = original.acquired.requestIdentity ?? {};
  const managedRun = original.managedRun ?? {}, plan = {}, ledger = {};
  const sourceBudget = Object.freeze({managedRun, capacity: {}, transferBytes: 17n, executionBytes: 19n});
  let ledgerPrepared = false;
  const sameOriginal = (parent, value, identity) => {
    assert.equal(parent, managedRun); assert.equal(value, prepared); assert.equal(identity, request);
  };
  const moon = original.moon ?? {};
  const defaults = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramEffectDirectSourceCoordinates: () => ({$tag: 1,
      _0: sourceRefs.map((_, index) => [index, 0, index, index])}),
    clientProgramEffectSerializationOccurrences: () => [],
    clientProgramEffectPrepareLocalQueryRequirement() {assert.fail('The original Plan already owns the checked requirement');},
    clientProgramQueryRequirementSourceRef: value => value,
    clientProgramInstalledEffectManagedOperationPlan(parent, value, identity) {
      assert.equal(this, moon); sameOriginal(parent, value, identity);
      return {$tag: 1, _0: plan};
    },
    clientProgramSelectInstalledEffectSourceInput(value, identity, task, input) {
      assert.equal(this, moon); assert.equal(value, prepared); assert.equal(identity, request);
      assert.equal(input, 0);
      assert(Number.isSafeInteger(task) && task >= 0 && task < sourceRefs.length);
      return {$tag: 1, _0: sourceRefs[task]};
    },
    clientProgramSelectedSourceInputKind: () => 'query',
    clientProgramSelectedSourceInputRef: value => value,
    clientProgramInstalledEffectManagedDuckDBCapture(parent, value, identity, task) {
      assert.equal(this, moon); sameOriginal(parent, value, identity);
      assert(Number.isSafeInteger(task) && task >= 0 && task < sourceRefs.length);
      assert.equal(rowSourceTasks.includes(task), false, 'Native getter cannot substitute for a Row capture');
      return {$tag: 1, _0: {_0: sourceRefs[task], _1: sourceBudget.capacity}};
    },
    clientProgramInstalledEffectManagedPlanSource(originalPlan, task) {
      assert.equal(this, moon); assert.equal(originalPlan, plan);
      assert.equal(rowSourceTasks.includes(task), true, 'Native adapter selection must not demand a Row-only capture');
      return {$tag: 1, _0: {_0: {}, _1: sourceRefs[task], _2: {}, _3: sourceBudget.capacity}};
    },
    clientProgramInstalledEffectManagedRunPrepareLedger(parent, value, identity, capacities, transfer, execution,
      registry, values, fragment, ordered) {
      assert.equal(this, moon); sameOriginal(parent, value, identity);
      assert.equal(ledgerPrepared, false); ledgerPrepared = true;
      assert.deepEqual(capacities, [sourceBudget.capacity]);
      assert.deepEqual(transfer, [sourceBudget.transferBytes]);
      assert.deepEqual(execution, [sourceBudget.executionBytes]);
      assert.deepEqual([registry, values, fragment, ordered],
        [original.registry, original.values, original.fragment, original.ordered]);
      return {$tag: 1, _0: ledger};
    },
    clientProgramMultiCapturedLedgerUsage(actual) {assert.equal(actual, ledger); return undefined;},
    clientProgramInstalledEffectManagedHostOpen() {assert.fail('These refusal fixtures cannot construct a Compute Host');}};
  for (const [name, value] of Object.entries(defaults)) {
    if (!Object.hasOwn(moon, name)) Object.defineProperty(moon, name, {value,
      enumerable: true, writable: true, configurable: true});
  }
  const sourceProfile = original.sourceProfile?.sources === undefined
    ? {realizationKey: 'duckdb-acquired', admitsSource: ref => ref === 'selected', ...original.sourceProfile}
    : original.sourceProfile;
  for (const adapter of sourceProfile.sources ?? [sourceProfile]) {
    if (typeof adapter.ledgerCapacity !== 'function') Object.defineProperty(adapter, 'ledgerCapacity', {value(value) {
      assert.equal(this, adapter); assert.notEqual(value, undefined);
      assert.equal(sourceRefs.length, 1, 'Multi-Source refusal fixtures must stop before Ledger construction');
      return sourceBudget;
    }});
  }
  return openEffectComputation({...original, moon, managedRun, sourceProfile,
    acquired: {...original.acquired, requestIdentity: request}});
};
