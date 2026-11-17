import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';
const cid = digit => `sha256:${digit.repeat(64)}`;

// Execute the actual Site with only its existing completion ports substituted.
// No Common issuer, provider send, durable receipt or physical ACK is invented.
let completionFixtureSequence = 0;
async function completionFailureSite(branch, primary, completion, {observing = false} = {}) {
  const key = `actql.test.site-completion.${++completionFixtureSequence}`;
  const calls = {captured: 0, recovered: 0, interrupted: 0, close: 0, cleanup: 0,
    authorizeClose: 0, completedResume: 0, current: 0};
  const ports = {async complete(kind, options) {
    calls[kind]++;
    assert.equal(options.apply.moon, moon);
    throw primary;
  }, async interrupted(options, recovered) {
    calls.interrupted++;
    assert.equal(recovered, branch === 'recovered');
    assert.equal(options.apply.moon, moon);
    throw completion;
  }};
  globalThis[Symbol.for(key)] = ports;
  const provider = 'data:text/javascript,' + encodeURIComponent(`
    const ports = globalThis[Symbol.for(${JSON.stringify(key)})];
    export const completeCapturedEffectRun = options => ports.complete('captured', options);
    export const completeRecoveredEffectRun = options => ports.complete('recovered', options);
    export const completeInterruptedEffectRun = (options, recovered) => ports.interrupted(options, recovered);
    export const settleRefusedEffectRun = () => {throw new Error('UnexpectedSettlement');};
  `);
  const siteUrl = new URL(`./installed-effect-site.mjs?completion-fixture=${completionFixtureSequence}`, import.meta.url).href;
  const hooks = registerHooks({resolve(specifier, context, next) {
    if (specifier === './entry.mjs' && context.parentURL === siteUrl)
      return {url: provider, shortCircuit: true};
    return next(specifier, context);
  }});
  let createSite;
  try { ({createInstalledEffectSite: createSite} = await import(siteUrl)); }
  finally { hooks.deregister(); delete globalThis[Symbol.for(key)]; }
  const moon = {clientProgramEffectCompilationUnitId: () => 'effect',
    clientProgramEffectCompilationResultNames: () => ['answer']};
  const control = {effectComputationPreviewSemanticCid: () => cid('a'),
    effectComputationPreviewWire: () => '{}', runDefinitionRunId: () => 'run-a'};
  const store = {}, computation = {}, storedResults = {}, preview = {}, claim = {};
  const physical = {close() {calls.close++;}, cleanup() {calls.cleanup++;return false;},
    cleanupPending: () => true};
  const stage = execution => ({preview, computation, storedResults,
    apply: {moon, computation, preview}, receipt: {commonMoon: moon},
    publication: {execution, store, control, computation, storedResults, preview},
    scopes: [{}], continuationWire: '{"provider":"original"}', cleanupOwner: physical});
  const site = createSite({environmentWire: '{}', prepareCaptured: () => stage(physical),
    prepareRecovered(facts) {facts.assertContinuationCurrent();return stage(null);}});
  let custody;
  const facts = {moon, control, store, ref: {runDefinitionCid: cid('b')},
    retainExecution(value) {custody = value;},
    effectAuthorization: () => ({close() {calls.authorizeClose++;}}),
    openComputation: () => ({execution: physical, checkedHost: {}}),
    assertContinuationCurrent() {calls.current++;}};
  if (branch === 'captured') facts.compilation = {};
  else Object.assign(facts, {reconciliationOnly: observing,
    view: {runId: 'run-a', checkpointCid: 'checkpoint', subject: {kind: 'run_unit', unit_id: 'effect'}},
    retained: {resultNames: ['answer']},
    continuation: {version: 'actql-installed-effect-continuation/0.1', unit_id: 'effect',
      run_definition_cid: cid('b'), preview_cid: cid('a'), provider: {provider: 'original'}},
    recoverCapture: async () => ({computation: {computation, storedResults, preview}}),
    checkpointJournal: {claimResume: () => ({action: 'claimed', claim}),
      admitResume(original) {assert.equal(original, claim);},
      completeResume() {calls.completedResume++;assert.fail('Failed completion cannot settle the claim');}}});
  return {calls, run: () => branch === 'captured' ? site.execute(facts) : site.resume(facts),
    custody: () => custody};
}

for (const branch of ['captured', 'recovered']) {
  for (const kind of ['mutable', 'frozen', 'nested', 'primitive', 'undefined']) {
    test(`Effect Site ${branch} retains original ${kind} cause when interrupted completion also fails`, async () => {
      const nested = new Error('OriginalInnerCause');
      const primary = kind === 'undefined' ? undefined : kind === 'primitive' ? 'original primitive'
        : new Error('OriginalCompletionFailure', kind === 'nested' ? {cause: nested} : undefined);
      if (kind === 'frozen') Object.freeze(primary);
      const completion = Object.freeze(new Error('InterruptedCompletionFailure'));
      const f = await completionFailureSite(branch, primary, completion);
      let failure;
      await assert.rejects(f.run(), error => {
        failure = error;
        assert(error instanceof AggregateError);
        assert.equal(error.cause, primary); assert.equal(error.primaryFailure, primary);
        assert.equal(error.completionFailure, completion);
        assert.deepEqual(error.errors, [primary, completion]);
        if (kind === 'nested') assert.equal(primary.cause, nested);
        return true;
      });
      assert.equal(f.calls[branch], 1); assert.equal(f.calls.interrupted, 1);
      assert.equal(f.calls.completedResume, 0); assert.equal(f.calls.authorizeClose, 1);
      assert.equal(f.custody().cleanupPending(), true);
      await f.custody().close();
      assert.equal(await f.custody().cleanup(), false, 'No terminal result substitutes for physical stop');
      assert.equal(f.custody().cleanupPending(), true);
      assert.equal(f.calls.close, 1); assert.equal(f.calls.cleanup, 1);
      assert.equal(failure.primaryFailure, primary);
    });
  }
  for (const completion of ['completion primitive', undefined]) {
    test(`Effect Site ${branch} retains primitive completion including undefined=${completion === undefined}`, async () => {
      const primary = Object.freeze(new Error('OriginalStructuredCause'));
      const f = await completionFailureSite(branch, primary, completion);
      await assert.rejects(f.run(), error => {
        assert.equal(error.cause, primary); assert.equal(error.primaryFailure, primary);
        assert.deepEqual(error.errors, [primary, completion]);
        assert.equal(error.completionFailure, completion); return true;
      });
      assert.equal(f.calls.interrupted, 1); assert.equal(f.calls.completedResume, 0);
    });
  }
  test(`Effect Site ${branch} retains both pending owners and uncertainty until their actual ACKs`, async () => {
    const retryCalls = [0, 0], released = [false, false];
    const cleanupNote = new Error('OriginalCleanupDiagnostic');
    class Cleanup {
      constructor(index) {this.index = index;}
      status() {return {pending: !released[this.index], errors: [cleanupNote]};}
      async retry() {retryCalls[this.index]++;return {pending: false};}
    }
    const handles = [Object.freeze(new Cleanup(0)), Object.freeze(new Cleanup(1))];
    const primary = Object.freeze(Object.assign(new Error('OriginalPending'),
      {cleanupPending: true, cleanupHandle: handles[0], outcome: 'unknown'}));
    const completion = Object.freeze(Object.assign(new Error('CompletionPending'),
      {cleanupPending: true, cleanupHandle: handles[1], uncertain: true}));
    const f = await completionFailureSite(branch, primary, completion);
    let failure;
    await assert.rejects(f.run(), error => {failure = error;return error.primaryFailure === primary;});
    assert.equal(failure.outcome, 'unknown'); assert.equal(failure.uncertain, true);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert(failure.cleanupHandle.status().errors.includes(cleanupNote));
    const first = failure.cleanupHandle.retry(), same = failure.cleanupHandle.retry();
    assert.equal(first, same); assert.equal((await first).pending, true, 'A retry return alone is not an ACK');
    assert.deepEqual(retryCalls, [1, 1]);
    released[0] = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.deepEqual(retryCalls, [1, 2]);
    released[1] = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(failure.cleanupPending, false); assert.deepEqual(retryCalls, [1, 2]);
    assert.equal(f.custody().cleanupPending(), true, 'Independent physical stop remains owned');
    assert.deepEqual(failure.errors, [primary, completion]);
  });
  test(`Effect Site ${branch} cannot acknowledge pending cleanup without its original owner`, async () => {
    const primary = Object.freeze(Object.assign(new Error('OriginalUnknownCleanup'), {cleanupPending: true}));
    const completion = Object.freeze(new Error('CompletionRejected'));
    const f = await completionFailureSite(branch, primary, completion);
    let failure;
    await assert.rejects(f.run(), error => {failure = error;return error.primaryFailure === primary;});
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(failure.cleanupPending, true); assert.deepEqual(failure.errors, [primary, completion]);
    assert.equal(f.custody().cleanupPending(), true);
  });
  test(`Effect Site ${branch} keeps the existing no-send primary without aggregate substitution`, async () => {
    const primary = new Error('OriginalNoSend');
    const completion = Object.freeze(Object.assign(new Error('EffectRunNoAttemptedSend'), {code: 'EffectRunNoAttemptedSend'}));
    const f = await completionFailureSite(branch, primary, completion);
    await assert.rejects(f.run(), error => error === primary);
    assert.equal(f.calls.interrupted, 1); assert.equal(f.calls.completedResume, 0);
  });
}

test('Effect Site recovered observation keeps its primary and never attempts interrupted publication', async () => {
  const primary = Object.freeze(new Error('ObservationRejected'));
  const f = await completionFailureSite('recovered', primary, new Error('MustNotReplace'), {observing: true});
  await assert.rejects(f.run(), error => error === primary);
  assert.equal(f.calls.interrupted, 0); assert.equal(f.calls.completedResume, 0);
  assert.equal(f.custody().cleanupPending(), true);
});
