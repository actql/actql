import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';

type StartupStatus = 'host-tasks-failed' | 'host-tasks-completed' | 'host-tasks-waiting';
type FixtureOptions = {
  status?: StartupStatus; handoff?: boolean; physicalReady?: boolean; retireReady?: boolean; retireFailure?: unknown;
};
type Custody = Readonly<{close(): Promise<void>; cleanup(): Promise<boolean>; cleanupPending(): boolean}>;

// Execute the imported coordination with explicit original Source/Run and
// physical cleanup ports. Core admission is qualified by the separate actual
// same-Ledger test; these ports supply no provider, budget or cleanup grant.
let sequence = 0;
async function fixture({status = 'host-tasks-failed', handoff = true,
  physicalReady = true, retireReady = true, retireFailure}: FixtureOptions = {}) {
  const events: string[] = [], prepared = {}, request = {}, managedRun = {}, plan = {}, host = {}, dag = {}, ledger = {};
  const primary = Object.freeze(new Error('OriginalManagedStartRefusal'));
  let custody: Custody | undefined, physicalClosed = false, consumersRetired = false;
  let runCalls = 0, retireCalls = 0, sourceCloses = 0;
  const physical = Object.freeze({status, failure: primary,
    checkpoint: Object.freeze({id: 'original-checkpoint'}),
    close() {events.push('physical-close');physicalClosed = true;},
    async cleanup() {
      events.push('physical-cleanup');
      if (!physicalClosed || !physicalReady) return false;
      if (status !== 'host-tasks-failed') consumersRetired = true;
      return true;
    }, cleanupPending: () => !physicalClosed || !physicalReady,
  });
  const moon = {
    clientProgramEffectAcquisitionCount: (value: unknown) => {assert.strictEqual(value, prepared);return 2;},
    clientProgramEffectSerializationOccurrences: () => [],
    clientProgramInstalledEffectManagedOperationPlan(parent: unknown, value: unknown, identity: unknown) {
      assert.strictEqual(parent, managedRun);assert.strictEqual(value, prepared);assert.strictEqual(identity, request);return {$tag: 1, _0: plan};
    },
    clientProgramInstalledEffectManagedSourcesLedger(parent: unknown, value: unknown, identity: unknown) {
      assert.strictEqual(parent, managedRun);assert.strictEqual(value, prepared);assert.strictEqual(identity, request);return {$tag: 1, _0: ledger};
    },
    clientProgramInstalledEffectManagedHostOpen(parent: unknown, bound: unknown, sources: readonly unknown[]) {
      assert.strictEqual(parent, managedRun);assert.equal(sources.length, 2);return {$tag: 1, _0: host};
    },
    clientProgramLocalEffectHostRuntime: (value: unknown) => {assert.strictEqual(value, host);return dag;},
    strategyHostRun: (value: unknown) => {assert.strictEqual(value, dag);return dag;},
    clientProgramMultiCapturedLedgerUsage: (value: unknown) => {assert.strictEqual(value, ledger);return undefined;},
    clientProgramRetireInstalledEffectCapturedConsumers(value: unknown) {
      assert.strictEqual(value, managedRun);assert.equal(physicalClosed, true);assert.equal(physicalReady, true);
      events.push('consumer-retire');retireCalls++;
      if (retireFailure !== undefined) throw retireFailure;
      if (retireReady) consumersRetired = true;
      return {$tag: 1, _0: retireReady};
    },
    clientProgramRefreshAcquiredEffectCleanup: (value: unknown) => {assert.strictEqual(value, host);return true;},
  };
  const selected = Object.freeze(Array.from({length: 2}, (_, index) => {
    const original = {}, preparedSource = {}, occurrence = Object.freeze({stage: 0, input: index, task: index, computeTask: 0});
    const captured = {occurrence, checkedSource: {sourceDataPolicyCid: 'original-policy'},
      capture: {source: () => original, retainTask(actual: unknown, task: number) {assert.strictEqual(actual, dag);assert.equal(task, 0);}},
      issueSourceEvidence: async () => '{}',
      async close() {
        assert.equal(consumersRetired, true, 'a stopped startup still owns its captured input until original retirement');
        events.push('source-close');sourceCloses++;
      },
    };
    const adapter = {async prepare(options: Readonly<{managedRun: unknown}>) {assert.strictEqual(options.managedRun, managedRun);return preparedSource;},
      ledgerCapacity(value: unknown) {assert.strictEqual(value, preparedSource);return {managedRun, wholeInput: true};},
      async open(options: Readonly<{preparedSource: unknown}>) {assert.strictEqual(options.preparedSource, preparedSource);events.push('source-complete');return captured;},
    };
    return Object.freeze({adapter, occurrence, sourceKind: 'whole-input'});
  }));
  const key = `actql.test.startup-custody.${++sequence}`;
  const ports = {async run(value: unknown) {
    assert.strictEqual(value, host);assert.equal(events.filter(v => v === 'source-complete').length, 2);runCalls++;
    if (!handoff) throw primary;
    return physical;
  }, publication() {return {};}};
  (globalThis as typeof globalThis & Record<symbol, typeof ports | undefined>)[Symbol.for(key)] = ports;
  const entry = 'data:text/javascript,' + encodeURIComponent(`const p=globalThis[Symbol.for(${JSON.stringify(key)})];export const runCapturedEffectComputation=(...args)=>p.run(...args);`);
  const publication = 'data:text/javascript,' + encodeURIComponent(`const p=globalThis[Symbol.for(${JSON.stringify(key)})];
    export const acquiredMultiEffectPublicationPlan=options=>p.publication(options);
    export const acquiredEffectPublicationPlan=options=>p.publication(options);
    export const acquiredKeyedEffectPublicationPlan=()=>{throw Error('UnexpectedKeyed');};
    export const prepareAcquiredEffectSourceUnits=()=>{throw Error('UnexpectedUnits');};
    export const acquiredInferEffectPublicationPlan=()=>{throw Error('UnexpectedInfer');};
    export const sourceFreeInferEffectPublicationPlan=()=>{throw Error('UnexpectedInfer');};
    export const sourceFreeContentEffectPublicationPlan=()=>{throw Error('UnexpectedContent');};
    export const localContractLimits=Object.freeze({});`);
  const target = new URL(`./acquired-effect-computation.mjs?startup-custody=${sequence}`, import.meta.url).href;
  const hook = registerHooks({resolve(specifier, context, next) {
    if (context.parentURL === target && specifier === './entry.mjs') return {url: entry, shortCircuit: true};
    if (context.parentURL === target && specifier === './local-values-plan.mjs') return {url: publication, shortCircuit: true};
    return next(specifier, context);
  }});
  let open: (options: Readonly<{
    moon: typeof moon; acquired: Readonly<{prepared: object; requestIdentity: object}>; managedRun: object;
    sourceProfile: object; owner: object; sourceSelection: typeof selected; sourceSelectionPlan: object;
    now(): string; retainComputationOwner(value: Custody): void;
  }>) => Promise<unknown>;
  try {({openAcquiredEffectComputation: open} = await import(target));}
  finally {hook.deregister();delete (globalThis as typeof globalThis & Record<symbol, typeof ports | undefined>)[Symbol.for(key)];}
  const promise = open({moon, acquired: {prepared, requestIdentity: request}, managedRun, sourceProfile: {}, owner: {},
    sourceSelection: selected, sourceSelectionPlan: plan, now: () => '2026-11-16T00:00:00Z',
    retainComputationOwner(value) {assert.equal(custody, undefined);custody = value;},
  });
  if (handoff && status !== 'host-tasks-failed') await promise;
  else await assert.rejects(promise, error => error === primary);
  assert.equal(runCalls, 1);
  return {custody: custody!, primary, events,
    counts: () => ({runCalls, retireCalls, sourceCloses}),
    physicalReady() {physicalReady = true;}, retireReady() {retireReady = true;retireFailure = undefined;},
  };
}

test('failed startup retires the same captured consumers after physical cleanup and before first Source close', async () => {
  const f = await fixture();
  await f.custody.close();assert.equal(await f.custody.cleanup(), true);assert.equal(f.custody.cleanupPending(), false);
  assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 1, sourceCloses: 2});
  assert(f.events.indexOf('consumer-retire') > f.events.indexOf('physical-cleanup'));
  assert(f.events.indexOf('source-close') > f.events.indexOf('consumer-retire'));
});

test('failed startup keeps Sources until its actual physical cleanup acknowledges', async () => {
  const f = await fixture({physicalReady: false});await f.custody.close();assert.equal(await f.custody.cleanup(), false);
  assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 0, sourceCloses: 0});
  f.physicalReady();assert.equal(await f.custody.cleanup(), true);assert.equal(f.custody.cleanupPending(), false);
  assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 1, sourceCloses: 2});
});

for (const throwing of [false, true]) test(`failed startup ${throwing ? 'throwing' : 'pending'} original retirement retains both Sources until retry`, async () => {
  const secondary = new Error('OriginalRetirementRefusal');
  const f = await fixture({retireReady: false, ...(throwing ? {retireFailure: secondary} : {})});
  await f.custody.close();
  if (throwing) await assert.rejects(f.custody.cleanup(), error => error === secondary);
  else assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.custody.cleanupPending(), true);assert.equal(f.counts().sourceCloses, 0);
  assert.equal(Object.isFrozen(f.primary), true);f.retireReady();
  assert.equal(await f.custody.cleanup(), true);assert.equal(f.custody.cleanupPending(), false);
  assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 2, sourceCloses: 2});
});

test('a thrown startup without the actual execution handoff retains unknown custody', async () => {
  const f = await fixture({handoff: false});await f.custody.close();assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.custody.cleanupPending(), true);assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 0, sourceCloses: 0});
});

for (const status of ['host-tasks-completed', 'host-tasks-waiting'] as const) test(`${status} preserves its original publication owner without failed-consumer retirement`, async () => {
  const f = await fixture({status, physicalReady: false});await f.custody.close();assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.custody.cleanupPending(), true);assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 0, sourceCloses: 0});
  f.physicalReady();assert.equal(await f.custody.cleanup(), true);assert.equal(f.custody.cleanupPending(), false);
  assert.deepEqual(f.counts(), {runCalls: 1, retireCalls: 0, sourceCloses: 2});
});
