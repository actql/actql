import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

const source = readFileSync(new URL('./installed-composed-infer-run.mjs', import.meta.url), 'utf8');
const declaration = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'runInstalledComposedInfers');
assert(declaration);

// Execute the actual installed driver with explicit continuation/Core ports.
// Stop before any Local execution: these controls qualify its original-input
// wiring and cleanup order, not a funded Host or a physical Source provider.
const load = compileFunction(`return (${source.slice(declaration.start, declaration.end)});`, [
  'runtimeField', 'acquiredEffectContinuation', 'canonicalJson', 'openNodeComposedInferProvider',
  'withLocalExecutionPauseHandler', 'ledgerUsageHasPendingResources',
]);

function fixture({count = 2, coordinates, closures, preparedFailure, restoreFailure, evidenceFailure,
  loseCurrentAt, stopAfterBind = false} = {}) {
  const prepared = {}, ledger = {}, dag = {}, setup = {}, checkpoints = {}, submission = {};
  const boundary = new Error('StopBeforeLocalExecution'), currentFailure = new Error('OriginalCurrentChanged');
  const occurrences = coordinates ?? [[3, 4, 7], [5, 9, 11]].slice(0, count);
  const continuation = {sources: occurrences.map(value => ({task: value[2]}))};
  const selections = [{graph: {task: 17}}, {graph: {task: 23}}];
  const records = selections.map((selection, index) => ({inventory: {
    taskIndex: selection.graph.task, scopeCid: `original-model-${index}`}, index}));
  const snapshots = records.map((_, index) => ({sourceContinuation: closures?.[index] ?? continuation}));
  const tokens = snapshots.map(snapshot => ({snapshot}));
  const selected = {restoredRun: {}, components: selections};
  const originals = selections.map(selection => ({selection}));
  const events = [], captures = [], sources = [{}, {}], adapters = [{}, {}], accesses = [{}, {}];
  const evidence = [{}, {}], providers = [{}, {}], live = new Set(), closeAttempts = [0, 0];
  const closeModes = [], continuationClose = {},
    counters = {ledger: 0, prepare: 0, restore: 0, scope: 0, continuation: 0};
  let owner, registered, current = true;
  const assertCurrent = () => {if (!current) throw currentFailure;};
  const plan = {runDefinition: {wire: JSON.stringify({run_id: 'original-run'}), identity: 'original-definition'}};
  const originalPreparation = {components: originals, sourceCoordinates: occurrences,
    retain() {events.push('retain-parent');},
    sourceLedger() {counters.ledger++; events.push('original-ledger'); return ledger;},
    async retire() {
      assert.equal(live.size, 0, 'all actual restored captures close before Scope retirement');
      counters.scope++; events.push('retire-scope'); return true;
    },
    openCapturedHost(actual, actualProviders) {
      assert.deepEqual(actual, captures);
      assert.equal(actual.length, count);
      actual.forEach((capture, index) => assert.strictEqual(capture, captures[index]));
      assert.deepEqual(actualProviders, providers);
      events.push('open-original-host');
      if (!stopAfterBind) throw boundary;
      return setup;
    },
    openSourceFreeHost() {assert.fail('nonempty original inventory is not source-free');},
  };
  function continuationPort(options) {
    assert.strictEqual(options.checkpoints, checkpoints);
    assert.strictEqual(options.acquired.prepared, prepared);
    assert.strictEqual(options.acquired.runDefinition, plan.runDefinition);
    assert.strictEqual(options.submission, submission);
    assert.strictEqual(options.restore.continuation, snapshots[0].sourceContinuation);
    assert.deepEqual(options.restore.view, {kind: 'model_invocation', prepareAttemptId: null,
      runId: 'original-run', runDefinitionCid: 'original-definition'});
    return {
      accessFor(access, occurrence) {
        const index = occurrences.findIndex(value => value[2] === occurrence.task);
        assert.strictEqual(access, accesses[index]);
        assert(Object.isFrozen(occurrence));
        assert.deepEqual(occurrence, {stage: occurrences[index][0], input: occurrences[index][1], task: occurrences[index][2]});
        events.push(`access-${index}`);
      },
      async prepared(actual) {
        assert.equal(actual.length, count);
        actual.forEach((value, index) => {
          assert.strictEqual(value.preparedSource, sources[index]);
          assert.strictEqual(value.adapter, adapters[index]);
        });
        registered = actual; events.push('prepare-complete-inventory');
        if (preparedFailure !== undefined) throw preparedFailure;
      },
      async beforeRead(original) {
        const index = registered.indexOf(original);
        assert(index >= 0); events.push(`authorize-retained-${index}`);
        if (loseCurrentAt === index) current = false;
        return {retained: snapshots[0]};
      },
      restore(original, retained, actualLedger) {
        const index = registered.indexOf(original);
        assert(index >= 0); assert.strictEqual(retained, snapshots[0]);
        assert.strictEqual(actualLedger, ledger);
        counters.restore++; events.push(`restore-${index}`);
        // Like the actual continuation, retain a created original before its
        // fallible capture projection. close() below also owns such partials.
        live.add(index);
        if (restoreFailure?.index === index) throw restoreFailure.cause;
        const captured = {occurrence: original.occurrence,
          capture: {retainTask(actualDag, task) {
            assert.strictEqual(actualDag, dag); assert.equal(task, original.occurrence.task);
            events.push(`bind-original-task-${task}`);
          }},
          async close() {
            closeAttempts[index]++; events.push(`close-source-${index}`);
            const mode = closeModes[index];
            if (mode?.pending) return false;
            if (mode?.throw) throw mode.cause;
            live.delete(index);
          }};
        captures.push(captured);
        return {captured, sourceEvidenceWire: `original-evidence-${index}`};
      },
      times: () => ({captureStartedAt: 100, captureCompletedAt: 200}),
      async close() {
        counters.continuation++; events.push('close-original-continuation');
        if (continuationClose.throw) throw continuationClose.cause;
        for (const index of live) {events.push(`close-partial-source-${index}`); live.delete(index);}
      },
    };
  }
  const run = load((tuple, index) => tuple[index], continuationPort, JSON.stringify, context => {
    const index = selections.indexOf(context.selected);
    assert(index >= 0); assert.strictEqual(context.originalPreparation, originals[index]);
    assert.strictEqual(context.restoredInput.token, tokens[index]);
    return {provider: providers[index]};
  }, () => {throw boundary;}, () => false);
  const options = {moon: {
    clientProgramAcquisitionCount(actual) {assert.strictEqual(actual, prepared); return count;},
    clientProgramResultCount: () => 0,
    clientProgramInferPlanBoundary: graph => [graph.task],
    strategyHostRun(actual) {assert.strictEqual(actual, setup); return dag;},
    strategyHostStop(actual) {assert.strictEqual(actual, setup); events.push('stop-original-setup');},
    strategyHostCloseOutputs(actual) {assert.strictEqual(actual, setup); events.push('close-original-outputs');},
    strategyHostUsage(actual) {assert.strictEqual(actual, setup); return {};},
  }, control: {
    admitRunEvidence(kind, wire, limits) {
      assert.equal(kind, 'source_evidence');
      assert.deepEqual(limits, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100});
      const index = wire === 'original-evidence-0' ? 0 : wire === 'original-evidence-1' ? 1 : -1;
      assert(index >= 0);
      if (evidenceFailure?.index === index) throw evidenceFailure.cause;
      return evidence[index];
    }}, preparedProgram: prepared, plan, selected, originalPreparation,
    modelController: {
      discover: () => records,
      async prime(record) {return tokens[record.index];},
      state: () => ({slots: []}), savedScope: () => ({}),
      release(token) {assert(tokens.includes(token)); events.push(`release-model-${tokens.indexOf(token)}`);},
    }, existingModel: records[0], assertCurrent,
    retainExecution(actual) {assert.equal(owner, undefined); owner = actual;},
    async prepareAcquisition(actual, access, occurrence) {
      assert.strictEqual(actual, prepared); assert.equal(access, undefined);
      const index = occurrences.findIndex(value => value[2] === occurrence.task);
      assert(index >= 0); assert(Object.isFrozen(occurrence));
      assert.deepEqual(occurrence, {stage: occurrences[index][0], input: occurrences[index][1], task: occurrences[index][2]});
      counters.prepare++; events.push(`prepare-original-${index}`); return sources[index];
    },
    sourceAccessFor: original => accesses[sources.indexOf(original)],
    sourceAdapterFor: original => adapters[sources.indexOf(original)],
    checkpoints, submission, signal: new AbortController().signal, computeConfigurations: {},
    beginPhysicalWork() {assert.fail('Source connection control stops before physical execution');},
  };
  return {run: () => run(options), options, originalPreparation, boundary, currentFailure,
    counters, events, captures, closeModes, continuationClose, closeAttempts, live, owner: () => owner};
}

test('cold composed recovery restores every checked Source coordinate through one original Ledger', async () => {
  const f = fixture({stopAfterBind: true});
  await assert.rejects(f.run(), cause => cause === f.boundary);
  assert.equal(f.counters.prepare, 2); assert.equal(f.counters.restore, 2); assert.equal(f.counters.ledger, 1);
  assert(f.events.includes('bind-original-task-7')); assert(f.events.includes('bind-original-task-11'));
  assert(f.events.indexOf('prepare-complete-inventory') < f.events.indexOf('original-ledger'));
  assert.equal(f.owner().cleanupPending(), true);
  assert.equal(await f.owner().cleanup(), true);
  assert(f.events.indexOf('close-source-0') < f.events.indexOf('close-source-1'));
  assert(f.events.indexOf('close-source-1') < f.events.indexOf('retire-scope'));
  assert.equal(f.owner().cleanupPending(), false);
  const before = f.events.slice(); assert.equal(await f.owner().cleanup(), true); assert.deepEqual(f.events, before);
});

test('cold singleton recovery uses its checked nondefault coordinate without a fresh Source path', async () => {
  const f = fixture({count: 1, coordinates: [[6, 8, 13]]});
  await assert.rejects(f.run(), cause => cause === f.boundary);
  assert.equal(f.counters.prepare, 1); assert.equal(f.counters.restore, 1); assert.equal(f.counters.ledger, 1);
  assert.equal(await f.owner().cleanup(), true); assert.equal(f.counters.scope, 1);
});

test('cold Source inventory refuses absent, duplicate, malformed or wrong-cardinality coordinates before preparation', async () => {
  for (const coordinates of [undefined, [[3, 4, 7]], [[3, 4, 7], [5, 9, 7]],
    [[3, 4, 7], [5, -1, 11]], [[3, 4, 7], [5, 9]]]) {
    const f = fixture(); f.originalPreparation.sourceCoordinates = coordinates;
    await assert.rejects(f.run(), /ModelSourceClosureCustodyUnavailable/);
    assert.equal(f.counters.prepare, 0); assert.equal(f.counters.restore, 0); assert.equal(f.counters.ledger, 0);
    assert.equal(await f.owner().cleanup(), true);
  }
});

test('cold composed recovery refuses different original saved closures before opening either Source', async () => {
  const f = fixture({closures: [{sources: ['first-original']}, {sources: ['foreign-original']}]});
  await assert.rejects(f.run(), /ModelSourceClosureMismatch/);
  assert.equal(f.counters.prepare, 0); assert.equal(f.counters.ledger, 0);
  assert.equal(await f.owner().cleanup(), true);
});

test('foreign retained Source binding refusal prevents any Ledger borrow or capture restoration', async () => {
  const cause = new Error('HeldAcquisitionChanged'), f = fixture({preparedFailure: cause});
  await assert.rejects(f.run(), actual => actual === cause);
  assert.equal(f.counters.prepare, 2); assert.equal(f.counters.ledger, 0); assert.equal(f.counters.restore, 0);
  assert.equal(await f.owner().cleanup(), true); assert.equal(f.counters.scope, 1);
});

test('a failed second restoration retains the first capture and the continuation partial until cleanup', async () => {
  const cause = new Error('SecondOriginalRefused'), f = fixture({restoreFailure: {index: 1, cause}});
  await assert.rejects(f.run(), actual => actual === cause);
  assert.equal(f.captures.length, 1); assert.equal(f.live.size, 2); assert.equal(f.owner().cleanupPending(), true);
  assert.equal(await f.owner().cleanup(), true);
  assert(f.events.indexOf('close-source-0') < f.events.indexOf('close-partial-source-1'));
  assert(f.events.indexOf('close-partial-source-1') < f.events.indexOf('retire-scope'));
  assert.equal(f.counters.prepare, 2); assert.equal(f.counters.ledger, 1);
});

test('failed evidence admission retains the already restored original capture for the same cleanup', async () => {
  const cause = new Error('OriginalEvidenceRefused'), f = fixture({evidenceFailure: {index: 0, cause}});
  await assert.rejects(f.run(), actual => actual === cause);
  assert.equal(f.captures.length, 1); assert.equal(f.live.size, 1);
  assert.equal(await f.owner().cleanup(), true); assert.equal(f.closeAttempts[0], 1);
});

test('current loss at the second retained read prevents construction and keeps the first original owned', async () => {
  const f = fixture({loseCurrentAt: 1});
  await assert.rejects(f.run(), actual => actual === f.currentFailure);
  assert.equal(f.counters.restore, 1); assert.equal(f.live.size, 1);
  assert.equal(await f.owner().cleanup(), true); assert.equal(f.counters.scope, 1);
});

test('a pending capture close prevents Scope retirement and retries that same original without another borrow', async () => {
  const f = fixture(); await assert.rejects(f.run(), actual => actual === f.boundary);
  f.closeModes[0] = {pending: true};
  assert.equal(await f.owner().cleanup(), false);
  assert.equal(f.counters.scope, 0); assert.equal(f.counters.continuation, 0);
  assert.deepEqual(f.closeAttempts, [1, 0]); assert.equal(f.owner().cleanupPending(), true);
  f.closeModes[0] = undefined;
  assert.equal(await f.owner().cleanup(), true);
  assert.deepEqual(f.closeAttempts, [2, 1]); assert.equal(f.counters.ledger, 1); assert.equal(f.counters.prepare, 2);
});

test('a throwing capture close retains its original primary and blocks Scope until the same retry succeeds', async () => {
  for (const cause of [new Error('OriginalCloseFailed'), undefined]) {
    const f = fixture(); await assert.rejects(f.run(), actual => actual === f.boundary);
    f.closeModes[1] = {throw: true, cause};
    let caught = false;
    try {await f.owner().cleanup();} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
    assert.equal(caught, true); assert.equal(f.counters.scope, 0); assert.equal(f.counters.continuation, 0);
    assert.deepEqual(f.closeAttempts, [1, 1]); assert.equal(f.owner().cleanupPending(), true);
    f.closeModes[1] = undefined;
    assert.equal(await f.owner().cleanup(), true);
    assert.deepEqual(f.closeAttempts, [1, 2]); assert.equal(f.counters.ledger, 1);
  }
});

test('continuation retirement failure keeps Scope pending without closing successful captures again', async () => {
  const f = fixture(), cause = new Error('OriginalContinuationCleanupPending');
  await assert.rejects(f.run(), actual => actual === f.boundary);
  f.continuationClose.throw = true; f.continuationClose.cause = cause;
  await assert.rejects(f.owner().cleanup(), actual => actual === cause);
  assert.equal(f.counters.scope, 0); assert.deepEqual(f.closeAttempts, [1, 1]);
  assert.equal(f.owner().cleanupPending(), true);
  f.continuationClose.throw = false;
  assert.equal(await f.owner().cleanup(), true);
  assert.deepEqual(f.closeAttempts, [1, 1]); assert.equal(f.counters.continuation, 2);
});
