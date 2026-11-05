import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';

const source = readFileSync(new URL('./installed-infer-run.mjs', import.meta.url), 'utf8');
const declaration = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'installNodeInferRun');
assert(declaration);
const load = compileFunction(`return (${source.slice(declaration.start, declaration.end)});`, [
  'runtimeField', 'checked', 'acquiredEffectContinuation', 'openNodeInferOperation', 'openNodeInferCaptureCustody',
]);

// These explicit ports execute the actual installed single-Unit connection.
// They stop at restoreRead or its existing waiting Model boundary; no physical
// Source, Model request, Ledger, Store or installed-runtime qualification is made.
function fixture({count = 1, coordinates = [[4, 6, 9]], missingClosure = false,
  missingRetained = false, missingAdapter = false, fault, loseCurrentAt,
  continueToModel = false} = {}) {
  const prepared = {}, graph = {}, compiled = {}, occurrence = {}, savedScope = {}, read = {};
  const definition = {identity: 'original-definition', wire: '{"run_id":"original-run"}'};
  const restoredRun = {compiled, graph, runDefinition: definition};
  const selected = {graph, occurrence, restoredRun};
  const plan = {inferGraph: graph, compiled, runDefinition: definition};
  const record = {inventory: {taskIndex: 0}}, closure = {sources: [{task: 9}]};
  const snapshot = {callScopeSnapshotWire: '{"sources":[{"source_evidence_wire":"original-evidence"}]}',
    ...(missingClosure ? {} : {sourceContinuation: closure})};
  const token = {snapshot}, preparedSource = {}, adapter = {}, access = {}, retained = {}, evidence = {};
  const checkpoints = {}, submission = {}, waiting = {status: 'waiting_checkpoint'}, events = [];
  const boundary = new Error('StopAtOriginalRestoreRead'), currentFailure = new Error('OriginalCurrentChanged');
  const counters = {prepare: 0, authorized: 0, restoredRead: 0, sourceClose: 0, scope: 0, release: 0};
  const sourceClose = {}, ready = {capture: false, model: false};
  let owner, original, current = true, captureClosed = false, modelClosed = false, tokenAvailable = true;
  const failAt = phase => {
    if (loseCurrentAt === phase) current = false;
    if (fault?.phase === phase) throw fault.cause;
  };
  const assertCurrent = () => {if (!current) throw currentFailure;};
  const control = {
    checkRestoredClientInferRunOwner(actual, checkedPrepared) {
      assert.strictEqual(actual, restoredRun); assert.strictEqual(checkedPrepared, prepared);
    },
    admitRunEvidence(kind, wire, limits) {
      assert.equal(kind, 'source_evidence'); assert.equal(wire, 'original-evidence');
      assert.deepEqual(limits, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}); return evidence;
    },
  };
  const view = {control, compiled, runDefinition: definition, selection: selected, sourceCoordinates: coordinates,
    retain() {events.push('retain-original');},
    assertRuntimeCurrent() {assertCurrent();},
    restoreRead(input) {
      counters.restoredRead++; events.push('restore-original-read');
      assert.strictEqual(input.token, token); assert.strictEqual(input.savedScope, savedScope);
      if (count !== 0) assert.equal(counters.authorized, 1, 'Source authorization precedes the original read');
      failAt('restoreRead');
      if (!continueToModel) throw boundary;
      return read;
    },
    sourceLedger() {assert.fail('SavedInputScope already owns the Model input');},
    async retire() {
      assert.equal(original === undefined || original.closed, true, 'Source continuation must close before Scope');
      assert.equal(!continueToModel || captureClosed && modelClosed, true, 'Model children must close before Scope');
      counters.scope++; events.push('retire-original-scope'); return true;
    },
  };
  const modelController = {
    async prime(actual) {assert.strictEqual(actual, record); return token;},
    capturedContent: () => undefined, capturedContentBinding: () => undefined,
    state: () => ({slots: []}), savedScope: () => savedScope,
    release(actual) {
      assert.strictEqual(actual, token);
      if (tokenAvailable) {tokenAvailable = false; counters.release++; events.push('release-model-input');}
    },
    async open(options) {
      assert.strictEqual(options.existing, record); assert.strictEqual(options.inputToken, token);
      events.push('retain-model-continuation');
      return {observe() {}, entry() {}, authorize: async () => waiting,
        async close() {events.push('close-model-continuation'); modelClosed = ready.model; return modelClosed;},
        async cleanup() {events.push('cleanup-model-continuation'); modelClosed = ready.model; return modelClosed;},
        cleanupPending: () => !modelClosed};
    },
  };
  function continuationPort(options) {
    assert(owner, 'cleanup custody exists before retaining the Source continuation');
    assert.equal(owner.cleanupPending(), true);
    assert.strictEqual(options.checkpoints, checkpoints); assert.strictEqual(options.submission, submission);
    assert.strictEqual(options.acquired.prepared, prepared); assert.strictEqual(options.acquired.runDefinition, definition);
    assert.strictEqual(options.restore.continuation, closure);
    assert.equal(options.unitId, 'composed-source-input');
    assert.deepEqual(options.restore.view, {kind: 'model_invocation', prepareAttemptId: null,
      runId: 'original-run', runDefinitionCid: 'original-definition'});
    assert.deepEqual(options.declaredResults, ['answer']);
    original = {closed: false,
      accessFor(actualAccess, actualOccurrence) {
        assert.strictEqual(actualAccess, access); assert(Object.isFrozen(actualOccurrence));
        assert.deepEqual(actualOccurrence, {stage: 4, input: 6, task: 9}); events.push('bind-original-access');
      },
      async prepared(sources) {
        assert.equal(sources.length, 1);
        assert.strictEqual(sources[0].preparedSource, preparedSource); assert.strictEqual(sources[0].adapter, adapter);
        assert.deepEqual(sources[0].occurrence, {stage: 4, input: 6, task: 9});
        events.push('bind-retained-closure'); failAt('prepared');
      },
      async beforeRead(actual) {
        assert.strictEqual(actual.preparedSource, preparedSource); assert.strictEqual(actual.adapter, adapter);
        counters.authorized++; events.push('authorize-retained-source'); failAt('beforeRead');
        return missingRetained ? {waiting: {}} : {retained};
      },
      restore() {assert.fail('do not create a second Source capture');},
      captured() {assert.fail('do not reacquire Source rows');},
      retainAll() {assert.fail('do not export or copy the already saved Model input');},
      async close() {
        counters.sourceClose++; events.push('close-source-continuation');
        if (sourceClose.throw) throw sourceClose.cause;
        if (sourceClose.pending) return false;
        original.closed = true;
      },
    };
    return original;
  }
  const operation = {
    bindRun(actualControl, actualPlan) {assert.strictEqual(actualControl, control); assert.strictEqual(actualPlan, plan);},
    run: async () => ({status: 'waiting', preparedCallSet: {}}),
  };
  const install = load((tuple, index) => tuple[index], checked, continuationPort, options => {
    assert(continueToModel); assert.strictEqual(options.restoredPreparation, read);
    assert.strictEqual(options.restoredInput.token, token); assert.equal(counters.authorized, count === 0 ? 0 : 1);
    events.push('open-original-kernel'); options.retainOperation(operation); return operation;
  }, options => {
    assert.strictEqual(options.operation, operation); assert.deepEqual(options.sourceEvidence, [evidence]);
    return {configureModelJournal() {}, custody: {
      async close() {events.push('close-capture'); captureClosed = ready.capture; return captureClosed;},
      async cleanup() {events.push('cleanup-capture'); captureClosed = ready.capture; return captureClosed;},
      cleanupPending: () => !captureClosed,
    }};
  });
  const run = install({moon: {
    clientProgramTaskCount: () => 1, clientProgramAcquisitionCount: () => count,
    clientProgramSelectSingleKeyedAcquisition: () => ({$tag: 1, _0: undefined}),
    clientProgramInferPlanBoundary: () => [0], clientProgramResultCount: () => 1,
    clientProgramResultName: () => 'answer',
    clientProgramRestoreSourceCapture() {assert.fail('no redundant Source capture');},
  }, core: {publicationControl: control}, selections: new Map([[prepared, selected]]), modelController,
    checkpoints,
    prepareModelRecoveryPlan(actual, actualPlan, actualSelected) {
      assert.strictEqual(actual, prepared); assert.strictEqual(actualPlan, plan); assert.strictEqual(actualSelected, selected);
      return view;
    },
    async prepareAcquisition(actual, override, actualOccurrence) {
      assert(owner); assert.equal(owner.cleanupPending(), true);
      assert.strictEqual(actual, prepared); assert.equal(override, undefined); assert(Object.isFrozen(actualOccurrence));
      assert.deepEqual(actualOccurrence, {stage: 4, input: 6, task: 9});
      counters.prepare++; events.push('prepare-original-source'); failAt('prepare'); return preparedSource;
    },
    sourceAdapterFor(actual) {assert.strictEqual(actual, preparedSource); return missingAdapter ? undefined : adapter;},
    sourceAccessFor(actual) {assert.strictEqual(actual, preparedSource); return access;},
  });
  const options = {preparedProgram: prepared, plan, existingModel: record, submission,
    principalId: 'original-principal', signal: new AbortController().signal, assertCurrent,
    retainExecution(actual) {assert.equal(owner, undefined); owner = actual;},
    beginPhysicalWork() {events.push('bind-original-physical-owner');},
  };
  return {run: () => run(options), options, view, boundary, currentFailure, counters, events, sourceClose, ready,
    waiting, owner: () => owner};
}

test('single-Unit cold recovery authorizes its exact retained Source before restoreRead without reacquisition', async () => {
  const f = fixture(); await assert.rejects(f.run(), cause => cause === f.boundary);
  assert.equal(f.counters.prepare, 1); assert.equal(f.counters.authorized, 1); assert.equal(f.counters.restoredRead, 1);
  assert(f.events.indexOf('authorize-retained-source') < f.events.indexOf('restore-original-read'));
  assert.equal(await f.owner().cleanup(), true);
  assert(f.events.indexOf('close-source-continuation') < f.events.indexOf('retire-original-scope'));
  assert.equal(f.owner().cleanupPending(), false);
});

test('source-free single-Unit recovery needs no Source continuation or extra input construction', async () => {
  const f = fixture({count: 0}); await assert.rejects(f.run(), cause => cause === f.boundary);
  assert.equal(f.counters.prepare, 0); assert.equal(f.counters.authorized, 0); assert.equal(f.counters.restoredRead, 1);
  assert.equal(await f.owner().cleanup(), true); assert.equal(f.counters.sourceClose, 0);
});

test('single-Unit recovery refuses absent original closure or invalid singleton coordinates before Source work', async () => {
  for (const config of [{missingClosure: true}, {coordinates: []}, {coordinates: [[4, 6]]},
    {coordinates: [[4, -1, 9]]}, {coordinates: [[4, 6, 9], [5, 7, 10]]}, {count: 2}]) {
    const f = fixture(config); await assert.rejects(f.run(), /ModelSourceClosureCustodyUnavailable/);
    assert.equal(f.counters.prepare, 0); assert.equal(f.counters.restoredRead, 0);
    assert.equal(await f.owner().cleanup(), true);
  }
});

test('failed Source preparation, foreign closure, and denied consumption keep the original primary and cleanup', async () => {
  for (const phase of ['prepare', 'prepared', 'beforeRead']) for (const cause of [new Error('OriginalSourceRefused'), undefined]) {
    const f = fixture({fault: {phase, cause}});
    let caught = false;
    try {await f.run();} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
    assert.equal(caught, true); assert.equal(f.counters.restoredRead, 0);
    assert.equal(await f.owner().cleanup(), true); assert.equal(f.counters.sourceClose, 1);
  }
});

test('waiting without retained Source custody cannot start the saved kernel', async () => {
  const f = fixture({missingRetained: true});
  await assert.rejects(f.run(), /ModelSourceClosureCustodyUnavailable/);
  assert.equal(f.counters.restoredRead, 0); assert.equal(await f.owner().cleanup(), true);
});

test('missing current adapter and current loss refuse before restoreRead and keep continuation cleanup', async () => {
  for (const config of [{missingAdapter: true}, {loseCurrentAt: 'prepare'}, {loseCurrentAt: 'beforeRead'}]) {
    const f = fixture(config);
    await assert.rejects(f.run(), config.missingAdapter ? /InstalledComposedInferSourceOwnerUnavailable/
      : cause => cause === f.currentFailure);
    assert.equal(f.counters.restoredRead, 0); assert.equal(await f.owner().cleanup(), true);
    assert.equal(f.counters.sourceClose, 1);
  }
});

test('pending Source continuation close blocks Scope and retries the same authorization owner', async () => {
  const f = fixture(); await assert.rejects(f.run(), cause => cause === f.boundary);
  f.sourceClose.pending = true;
  assert.equal(await f.owner().cleanup(), false); assert.equal(f.counters.scope, 0);
  assert.equal(f.owner().cleanupPending(), true);
  f.sourceClose.pending = false;
  assert.equal(await f.owner().cleanup(), true);
  assert.equal(f.counters.sourceClose, 2); assert.equal(f.counters.prepare, 1); assert.equal(f.counters.authorized, 1);
});

test('throwing Source continuation close preserves even an undefined primary until the same retry succeeds', async () => {
  for (const cause of [new Error('OriginalSourceCleanupPending'), undefined]) {
    const f = fixture(); await assert.rejects(f.run(), actual => actual === f.boundary);
    f.sourceClose.throw = true; f.sourceClose.cause = cause;
    let caught = false;
    try {await f.owner().cleanup();} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
    assert.equal(caught, true); assert.equal(f.counters.scope, 0); assert.equal(f.owner().cleanupPending(), true);
    f.sourceClose.throw = false;
    assert.equal(await f.owner().cleanup(), true);
    assert.equal(f.counters.sourceClose, 2); assert.equal(f.counters.prepare, 1);
  }
});

test('Model and capture child acknowledgements precede Source continuation and recovery Scope cleanup', async () => {
  const f = fixture({continueToModel: true}); assert.strictEqual(await f.run(), f.waiting);
  assert.equal(await f.owner().cleanup(), false);
  assert.equal(f.counters.sourceClose, 0); assert.equal(f.counters.scope, 0);
  f.ready.capture = true;
  assert.equal(await f.owner().cleanup(), false);
  assert.equal(f.counters.sourceClose, 0); assert.equal(f.counters.scope, 0);
  f.ready.model = true;
  assert.equal(await f.owner().cleanup(), true);
  assert(f.events.indexOf('cleanup-capture') < f.events.indexOf('close-source-continuation'));
  assert(f.events.lastIndexOf('cleanup-model-continuation') < f.events.indexOf('close-source-continuation'));
  assert(f.events.indexOf('close-source-continuation') < f.events.indexOf('retire-original-scope'));
});
