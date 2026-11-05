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
  const prepared = {}, graph = {}, compiled = {}, occurrence = {}, savedScope = {}, read = {}, prefix = {}, suffix = {};
  const definition = {identity: 'original-definition', wire: '{"run_id":"original-run"}'};
  const restoredRun = {compiled, graph, runDefinition: definition};
  const selected = {graph, occurrence, restoredRun, deferredRestoredSegments: true};
  const plan = {inferGraph: graph, compiled, runDefinition: definition};
  const record = {inventory: {taskIndex: 0}}, closure = {sources: [{task: 9}]};
  const snapshot = {callScopeSnapshotWire: '{"sources":[{"source_evidence_wire":"original-evidence"}]}',
    ...(missingClosure ? {} : {sourceContinuation: closure})};
  const token = {snapshot}, preparedSource = {}, sourceSelection = {}, adapter = {}, access = {}, retained = {}, evidence = {};
  const checkpoints = {}, submission = {}, waiting = {status: 'waiting_checkpoint'}, events = [];
  const boundary = new Error('StopAtOriginalRestoreRead'), currentFailure = new Error('OriginalCurrentChanged');
  const counters = {prepare: 0, authorized: 0, restoredRead: 0, sourceClose: 0, scope: 0, release: 0};
  const sourceClose = {}, ready = {capture: false, model: false};
  let owner, original, current = true, captureClosed = false, modelClosed = false, tokenAvailable = true, kernelOpened = false;
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
    prepareSource(actualOccurrence, construct) {
      assert.deepEqual(actualOccurrence, {stage: 4, input: 6, task: 9});
      events.push('same-recovery-source-constructor');
      return construct(sourceSelection);
    },
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
      assert.equal(!kernelOpened || captureClosed && modelClosed, true, 'Model children must close before Scope');
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
    assert.strictEqual(options.composedInput.prefix, prefix); assert.strictEqual(options.computeSuffix, suffix);
    assert.equal(events.filter(event => event === 'lower-original-segments').length, 1);
    kernelOpened = true;
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
    clientProgramPrepareComposedInferSegments(actual, actualOccurrence) {
      assert.strictEqual(actual, prepared); assert.strictEqual(actualOccurrence, occurrence);
      assert.equal(counters.restoredRead, 1, 'same retained Read precedes checked segment construction');
      events.push('lower-original-segments'); failAt('segments');
      return {$tag: 1, _0: [prefix, suffix]};
    },
    clientProgramRestoreSourceCapture() {assert.fail('no redundant Source capture');},
  }, core: {publicationControl: control}, selections: new Map([[prepared, selected]]), modelController,
    checkpoints,
    prepareModelRecoveryPlan(actual, actualPlan, actualSelected) {
      assert.strictEqual(actual, prepared); assert.strictEqual(actualPlan, plan); assert.strictEqual(actualSelected, selected);
      return view;
    },
    prepareAcquisition() {assert.fail('Saved input must not create a fresh ManagedRun Source read');},
    prepareRetainedAcquisition(actual, actualOccurrence, selectedSource) {
      assert(owner); assert.equal(owner.cleanupPending(), true);
      assert.strictEqual(actual, prepared); assert.strictEqual(selectedSource, sourceSelection); assert(Object.isFrozen(actualOccurrence));
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

test('failed restored segment construction retains the same Read and Source cleanup without starting Model', async () => {
  for (const cause of [new Error('OriginalSegmentConstructionFailed'), undefined]) {
    const f = fixture({continueToModel: true, fault: {phase: 'segments', cause}});
    let caught = false;
    try {await f.run();} catch (actual) {caught = true; assert.strictEqual(actual, cause);}
    assert.equal(caught, true);
    assert.equal(f.counters.restoredRead, 1);
    assert.equal(f.events.filter(event => event === 'lower-original-segments').length, 1);
    assert.equal(f.events.includes('open-original-kernel'), false);
    f.sourceClose.pending = true;
    assert.equal(await f.owner().cleanup(), false); assert.equal(f.counters.scope, 0);
    f.sourceClose.pending = false;
    assert.equal(await f.owner().cleanup(), true);
    assert.equal(f.counters.scope, 1); assert.equal(f.counters.prepare, 1);
  }
});

test('current loss during restored segment construction refuses Model and keeps original cleanup', async () => {
  const f = fixture({continueToModel: true, loseCurrentAt: 'segments'});
  await assert.rejects(f.run(), actual => actual === f.currentFailure);
  assert.equal(f.counters.restoredRead, 1);
  assert.equal(f.events.includes('open-original-kernel'), false);
  assert.equal(await f.owner().cleanup(), true);
  assert.equal(f.counters.scope, 1); assert.equal(f.counters.sourceClose, 1);
});

// Execute the fresh single-Unit producer with its existing adapter/Source
// originals as explicit ports. No upstream read, Scope issuer or Store ACK.
function freshSingletonFixture(options = {}) {
  const {failAt} = options;
  const failure = Object.hasOwn(options,'failure') ? options.failure : new Error('OriginalSourceFailure');
  const prepared = {}, graph = {}, compiled = {}, occurrence = Object.freeze({stage: 4, input: 6, task: 0});
  const definition = {identity: 'original-definition', wire: '{"run_id":"original-run"}'};
  const selected = {graph, occurrence, computePrefix: {}}, plan = {compiled, runDefinition: definition, inferGraph: graph};
  const originalApproval = {}, captured = {}, preparedSource = {}, adapter = {}, access = {originalCheckpointApproval() {return originalApproval;}}, sourceEvidence = {}, sourceWire = 'original-evidence';
  const closure = Object.freeze({sources: Object.freeze([{task: 0, capture: 'original-private-material'}])});
  const acquired = {captured, preparedSource, adapter, sourceAccess: access, occurrence, sourceEvidence,
    sourceEvidenceWire: sourceWire, captureStartedAt: 'start', captureCompletedAt: 'end', managedRun: {}};
  const submission = {}, checkpoints = {}, scope = {}, read = {}, prefix = {}, sources = {}, events = [];
  const controllerOptions = [], waiting = {status: 'waiting_checkpoint'};
  let owner, sourceClosed = false, scopeClosed = false, operation;
  const current = () => {if (failAt === 'current') throw failure;};
  const original = {control: undefined, compiled, runDefinition: definition, scope, selection: selected,
    component: {bindOriginal() {assert.fail('single-Unit kernel is not the DAG component');}},
    openCapturedHost() {assert.fail('no replacement Host');},
    assertRuntimeCurrent: current,
    retain() {events.push('retain-original');},
    prepareRead() {events.push('prepare-original-read');return read;},
    async retire() {assert(sourceClosed);scopeClosed = true;events.push('retire-scope');return true;},
  };
  const control = {admitComposedInferSources(o, captures, evidence) {
    assert.equal(o,occurrence);assert.deepEqual(captures,[captured]);assert.deepEqual(evidence,[sourceEvidence]);return sources;
  }};original.control = control;
  const model = {};
  const moon = {clientProgramAcquisitionCount: () => 1,clientProgramTaskCount: () => 1,
    clientProgramInferPlanBoundary: () => [0],clientProgramResultCount: () => 1,clientProgramResultName: () => 'answer',
    clientProgramInstalledManagedRunModelInputPrefix(run, actual) {assert.equal(run,acquired.managedRun);assert.equal(actual,prepared);return {$tag:1,_0:prefix};},
  };
  const install = compileFunction(`return (${source.slice(declaration.start,declaration.end)});`,[
    'runtimeField','checked','sourceFreeModelPreparation','acquiredEffectContinuation','openNodeInferOperation','openNodeInferCaptureCustody',
  ])((value,index) => value[index],checked,
    (m,c,p,actualPlan,s,actualModel,a) => {
      assert.equal(m,moon);assert.equal(c,control);assert.equal(p,prepared);assert.equal(actualPlan,plan);
      assert.equal(s,selected);assert.equal(actualModel,model);assert.equal(a,acquired);return original;
    }, options => {
      assert(owner,'retain existing cleanup before Source preparation');assert.equal(options.checkpoints,checkpoints);
      assert.equal(options.submission,submission);assert.equal(options.acquired.prepared,prepared);
      assert.equal(options.acquired.runDefinition,definition);assert.equal(options.restore,undefined);
      return {
        accessFor(actual,actualOccurrence) {assert.equal(actual,access);assert.equal(actualOccurrence,occurrence);events.push('original-access');},
        async prepared(items) {
          assert.equal(items.length,1);assert.equal(items[0].preparedSource,preparedSource);assert.equal(items[0].adapter,adapter);
          assert.equal(items[0].occurrence,occurrence);events.push('original-source');if(failAt==='prepared')throw failure;
        },
        async captured(item,actual,wire,start,end,approval) {
          assert.equal(approval,originalApproval);assert.equal(item.preparedSource,preparedSource);assert.equal(actual,captured);assert.equal(wire,sourceWire);
          assert.equal(start,'start');assert.equal(end,'end');events.push('same-capture');if(failAt==='captured')throw failure;
        },
        async retainAll() {events.push('retain-closure');if(failAt==='retain')throw failure;return closure;},
        async close() {sourceClosed=true;events.push('close-source');},
        beforeRead() {assert.fail('no second Source authorization/read');},restore() {assert.fail('no replacement capture');},
      };
    }, options => {
      assert.equal(options.originalPreparation,read);assert.equal(options.composedInput.prefix,prefix);
      assert.equal(options.composedInput.sources,sources);
      operation={bindRun(){},run:async()=>({status:'waiting',preparedCallSet:{}}),pendingSettlement(){},physicalStopped:()=>true};
      options.retainOperation(operation);return operation;
    }, () => ({configureModelJournal(){},persistStoppedAttempts(){},custody:{close:async()=>true,cleanup:async()=>true,cleanupPending:()=>false}}));
  const run=install({moon,core:{publicationControl:control},selections:new Map([[prepared,selected]]),checkpoints,
    prepareOriginalModelRun:()=>model,modelController:{discover:()=>[],release(){},unresolved:()=>false,
      async open(options) {
        controllerOptions.push(options);assert.equal(options.sourceContinuation,closure,'Persist exactly the original Source closure with Model input');
        return {observe(){},entry(){},authorize:async()=>waiting,close:async()=>true,cleanup:async()=>true,cleanupPending:()=>false};
      }},
  });
  return {events,closure,controllerOptions,failure,waiting,owner:()=>owner,scopeClosed:()=>scopeClosed,
    run:()=>run({preparedProgram:prepared,plan,acquiredInfer:acquired,preparationHolder:{},submission,
      principalId:'original-principal',signal:new AbortController().signal,assertCurrent:current,
      retainExecution(actual){owner=actual;},beginPhysicalWork(){}})};
}

test('fresh single-Unit Model retains its original Source closure before storing the Model checkpoint', async () => {
  const f=freshSingletonFixture();assert.equal(await f.run(),f.waiting);
  assert.equal(f.controllerOptions.length,1);assert.equal(f.controllerOptions[0].sourceContinuation,f.closure);
  assert(f.events.indexOf('same-capture') < f.events.indexOf('retain-closure'));
  assert.equal(await f.owner().cleanup(),true);assert.equal(f.scopeClosed(),true);
  assert(f.events.indexOf('close-source') < f.events.indexOf('retire-scope'));
});

test('fresh singleton Source retention failures preserve the original failure and close before its Scope', async () => {
  for (const failAt of ['prepared','captured','retain']) for (const failure of [undefined,new Error('OriginalSourceRefusal')]) {
    const f=freshSingletonFixture({failAt,failure});
    let caught=false;
    try {await f.run();} catch(actual) {caught=true;assert.equal(actual,f.failure);}
    assert.equal(caught,true);assert.equal(f.controllerOptions.length,0);
    assert.equal(await f.owner().cleanup(),true);assert.equal(f.scopeClosed(),true);
    assert(f.events.indexOf('close-source') < f.events.indexOf('retire-scope'));
  }
});

test('retained row Source metadata uses the same original Request without issuing a physical read', async () => {
  const source = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  let node, description;
  (function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'FunctionDeclaration' && value.id.name === 'prepareRetained') node = value;
    if (value.type === 'FunctionDeclaration' && value.id.name === 'describePreparedSource') description = value;
    for (const child of Object.values(value)) {
      if (Array.isArray(child)) child.forEach(walk); else if (child && typeof child === 'object') walk(child);
    }
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(node); assert(description);
  const preparedProgram = {}, requestIdentity = {}, requirement = {}, declaration = {}, sourceAccess = {};
  const occurrence = Object.freeze({stage: 3, input: 1, task: 0}), preparations = new WeakMap();
  const calls = [];
  const moon = {
    clientProgramMatchesRequestIdentity: (p, r) => p === preparedProgram && r === requestIdentity,
    clientProgramPrepareLocalQueryRequirement(p, stage, input, ...contracts) {
      assert.equal(p, preparedProgram); assert.deepEqual([stage, input], [3, 1]);
      assert.deepEqual(contracts, ['registry', 'values', 'fragment', 'ordered']);
      calls.push('original requirement'); return {$tag: 1, _0: requirement};
    },
    clientProgramQueryRequirementSourceEvidenceFacts: value => {
      assert.equal(value, requirement); return {$tag: 1, _0: ['source', 'contract', 'schema', 'policy', 'internal', 'view']};
    },
    clientProgramRowSourceTarget(d, r) {assert.equal(d, declaration); assert.equal(r, requirement); return {$tag: 1, _0: ['table', 'id']};},
    clientProgramQueryRequirementCid: () => 'requirement',
    clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
  };
  const ports = {immutableTargets: undefined, physicalTargetGeneration: undefined, moon, checked,
    sourceRefs: new Set(['source']), declaration, site: {connection: 'original'}, sourceAccess, preparations,
    physicalTarget(resource, fields) {return {resource, fields};}, valueCid: value => JSON.stringify(value),
    ordinaryRecoveryBinding(prepared) {assert.equal(preparations.get(prepared).retainedOnly, true); calls.push('actual binding');},
    fail(code) {throw Object.assign(new Error(code), {code});}};
  const prepare = Function(...Object.keys(ports), source.slice(description.start, description.end) + '\nreturn (' + source.slice(node.start, node.end) + ');')(...Object.values(ports));
  const facts = {preparedProgram, requestIdentity, occurrence, registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered'};
  assert.throws(() => prepare({...facts, requestIdentity: {}}), {code: 'InstalledSourcePreparationMismatch'});
  const prepared = prepare(facts), owner = preparations.get(prepared);
  assert.deepEqual(calls, ['original requirement', 'actual binding']);
  assert.equal(owner.checkedOwner, preparedProgram); assert.equal(owner.access, sourceAccess);
  assert.equal(owner.originalRead, undefined); assert.equal(owner.managedRun, undefined);
  assert.equal(owner.acquisition, undefined); assert.equal(owner.providerCaptureCapacity, undefined);
  assert.deepEqual(prepared.physicalBinding, {resource: 'table', fields: ['id']});
  assert.deepEqual(prepared.occurrence, occurrence); assert(Object.isFrozen(prepared));
});
