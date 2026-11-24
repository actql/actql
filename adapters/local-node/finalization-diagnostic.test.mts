// Thin caller regressions with explicit result/projector ports. The retained
// cleanup progress methods are the immutable 6c Core implementation; these
// cases are not ordinary Host, capacity or physical-ACK acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {publicBudgetFailureMessage} from '../host-node/client-dispatch-diagnostic.mjs';
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';
import type {beginManagedFailureProgress, ManagedFailure, settleFailedManagedOperations} from '../host-common/managed-failure.mjs';

type Stage = 'prepare' | 'advance' | 'settle' | 'complete';
type FixtureFailure = Omit<ManagedFailure, 'primaryFailure' | 'primaryDiagnostic'> & {
  primaryFailure: Error;
  primaryDiagnostic?: Readonly<{dimension: string; task: number}>;
};
type FixtureEntry = Readonly<{
  prepareNext(outputs: ReadonlyMap<unknown, unknown>): Promise<unknown>;
  runPrepared(prepared: unknown): Promise<{diagnostic: {outputRows: number}}>;
}>;
type FixtureStrategyModule = Readonly<{
  localStrategyContribution(moon: object, setup: object, check: typeof checked): FixtureEntry;
}>;

type FailurePorts = Parameters<typeof settleFailedManagedOperations>;
type ProgressFactory = Parameters<typeof beginManagedFailureProgress>[0]['strategyHostBeginManagedFailureProgress'];
type Reject<Actual, Port> = Actual extends Port ? false : true;
type Assert<A extends true> = A;
type _ProgressIsSynchronous = Assert<Reject<(...args: Parameters<ProgressFactory>) => Promise<ReturnType<ProgressFactory>>, ProgressFactory>>;
type _CloseIsSynchronous = Assert<Reject<() => Promise<void>, FailurePorts[0]['close']>>;
type _SettleIsSynchronous = Assert<Reject<() => Promise<object>, FailurePorts[0]['settle']>>;
type _CheckIsSynchronous = Assert<Reject<(result: unknown) => PromiseLike<object>, FailurePorts[1]>>;
type _AdditionalCloseIsSynchronous = Assert<Reject<() => Promise<void>,
  NonNullable<NonNullable<FailurePorts[4]>[number]['close']>>>;

const source = process.env.ACTQL_FINALIZATION_STRATEGY_SOURCE ??
  new URL('./strategy-bundle.mjs', import.meta.url).href;
const {localStrategyContribution} = await import(source) as FixtureStrategyModule;
// Keep the original URL inputs that Node coerces at this test import boundary.
const originalCore = await import((process.env.ACTQL_FINALIZATION_CORE_SOFTWARE
  ? pathToFileURL(process.env.ACTQL_FINALIZATION_CORE_SOFTWARE)
  : new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)) as unknown as string);
const ok = (value?: unknown) => ({$tag: 1, _0: value});

function fixture(failedStage: Stage | undefined, {classified = true} = {}) {
  const calls: string[] = [], setup = {}, configuration = {}, issue = {}, material = {};
  const originalFailure = {$tag: 0, _0: issue};
  let failureIssued = false, stopped = false, cleanupCalls = 0, projects = 0;
  const result = (stage: Stage) => {
    calls.push(stage);
    if (stage === failedStage && !failureIssued) {
      failureIssued = true;
      return originalFailure;
    }
    return ok();
  };
  const operations = {
    inputs: [], storage_bytes: 0,
    advance() { calls.push('execute'); return ok({complete: true, progress: 1n, work: 1n}); },
    prepare_finalization() { return result('prepare'); },
    advance_finalization() {
      const value = result('advance');
      return value === originalFailure ? value : ok({complete: true, progress: 1n, work: 1n});
    },
    settle() { return result('settle'); },
    complete() {
      const value = result('complete');
      return value === originalFailure ? value : ok({});
    },
    request_cancel() { stopped = true; return true; },
    execution_stopped() { return stopped; },
    close() { calls.push('close'); stopped = true; },
    cleanup_refresh() { cleanupCalls++; return cleanupCalls > 1; },
    cleanup_local_continuation: () => -1n,
    output_rows: () => 1,
    output_row: () => ok('{"id":1}'),
    material: () => material,
  };
  const moon = {
    ...originalCore,
    strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local',
    strategyHostNextTask: () => 7,
    strategyHostManagedProducers: () => [],
    strategyHostManagedInputCount: () => 0,
    strategyHostReleasableManagedProducers: () => [],
    strategyModule_local_ManagedCarrierDispatch: () => ok(configuration),
    strategyModule_local_ManagedDuration: () => 1n,
    strategyModule_local_ManagedCapacity: () => [0n, 0n],
    strategyModule_local_ManagedStart: () => ok(operations),
    strategyModule_local_ManagedAdvanceResourceDimension(value: unknown) {
      assert.strictEqual(this, moon);
      assert.strictEqual(value, originalFailure);
      projects++;
      return classified ? 'execution_bytes' : undefined;
    },
    strategyModule_local_ManagedAdvanceBudget: () => undefined,
    strategyModule_local_ManagedAdvanceControlWorkLimit: () => undefined,
    strategyModule_local_ManagedAdvanceCaptureWork: () => undefined,
    strategyModule_local_ManagedAdvanceCause: () => undefined,
    strategyModule_local_ManagedAdvanceRowStep: () => -1,
  };
  const entry = localStrategyContribution(moon, setup, checked);
  return {entry, issue, calls, projectCount: () => projects};
}

for (const stage of ['prepare', 'advance', 'settle', 'complete'] as const) {
  test(`finalization diagnostic preserves same original ${stage} refusal through cleanup`, async () => {
    const f = fixture(stage);
    const prepared = await f.entry.prepareNext(new Map());
    const failure = await f.entry.runPrepared(prepared).then(
      () => assert.fail('original finalization refusal was lost'), (error: unknown) => error as FixtureFailure);
    assert.equal(failure.code, 'MoonBitHostFailure');
    assert.equal(failure.primaryFailure.cause, f.issue);
    assert.equal(f.projectCount(), 1);
    assert.equal(failure.primaryDiagnostic!.dimension, 'execution_bytes');
    assert.equal(failure.primaryDiagnostic!.task, 7);
    assert(Object.isFrozen(failure.primaryDiagnostic));
    assert.match(publicBudgetFailureMessage(failure)!,
      /dimension=execution_bytes; requested_delta=unavailable; remaining=unavailable; policy=unavailable; unit=logical_bytes; setting=installation\.requestMemory\.executionBytes/);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(f.calls.filter(value => value === 'execute').length, 1);
    assert.equal(f.calls.filter(value => value === 'complete').length, stage === 'complete' ? 1 : 0);
    assert.equal(failure.primaryFailure.cause, f.issue);
  });
}

test('finalization diagnostic successful completion never invokes a failure projector', async () => {
  const f = fixture(undefined);
  const prepared = await f.entry.prepareNext(new Map());
  const output = await f.entry.runPrepared(prepared);
  assert.equal(f.projectCount(), 0);
  assert.equal(output.diagnostic.outputRows, 1);
  assert.deepEqual(f.calls, ['execute', 'prepare', 'advance', 'settle', 'complete']);
});

test('finalization diagnostic leaves an unclassified original refusal unclassified', async () => {
  const f = fixture('prepare', {classified: false});
  const prepared = await f.entry.prepareNext(new Map());
  const failure = await f.entry.runPrepared(prepared).then(
    () => assert.fail('original refusal was lost'), (error: unknown) => error as FixtureFailure);
  assert.equal(failure.primaryFailure.cause, f.issue);
  assert.equal(failure.primaryDiagnostic, undefined);
  assert.equal(publicBudgetFailureMessage(failure), undefined);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
});

test('finalization diagnostic never projects a foreign checker error from Ok or malformed DATA', () => {
  for (const result of [ok('original'), {}, undefined]) {
    const primary = Object.assign(new Error('foreign checker'), {code: 'MoonBitHostFailure'});
    const moon = {strategyModule_local_ManagedAdvanceResourceDimension() {
      assert.fail('non-Err must not reach the typed Core getter');
    }};
    assert.throws(() => checkedLocalManagedAdvance(moon, result, () => { throw primary; }, 7),
      error => error === primary);
    assert.equal((primary as Error & {primaryDiagnostic?: unknown}).primaryDiagnostic, undefined);
    assert.equal(publicBudgetFailureMessage(primary), undefined);
  }
});
