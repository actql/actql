import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {checkpointApprovalFacts,recordCheckpointApproval} from '../host-common/checkpoint-approval.mjs';

// Composition-only fixtures. These exercise the original owner's synchronous
// assertion across real adapter awaits; they do not prove runtime admission,
// a physical provider's final send fence, or selected-acquisition support.
const changed = () => Object.assign(new Error('InstalledEffectOriginalSelectionChanged'),
  {code: 'InstalledEffectOriginalSelectionChanged'});
const expected = {code: 'InstalledEffectOriginalSelectionChanged'};
const ok = value => ({$tag: 1, _0: value});
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
};
const pause = value => {
  const entered = deferred(), released = deferred();
  return {entered: entered.promise, release: released.resolve,
    async run() { entered.resolve(); await released.promise; return value; }};
};

// Explicit original Plan/Request ports for the composition-only computation
// cases below. These preserve identity through the current entrance and stop
// at the authored await/refusal; they supply no actual runtime funding or Host.
function managedComposition(acquired, count) {
  const prepared = acquired.prepared, request = {}, managedRun = {}, operationPlan = {},
    requirement = {}, selected = {}, ledger = {}, preparedSource = {}, capacity = {};
  const budget = Object.freeze({managedRun, capacity, transferBytes: 17n, executionBytes: 19n});
  const same = (parent, actual, identity) => {
    assert.strictEqual(parent, managedRun); assert.strictEqual(actual, prepared); assert.strictEqual(identity, request);
  };
  const moon = {
    clientProgramEffectAcquisitionCount(actual) {assert.strictEqual(actual, prepared); return count;},
    clientProgramEffectDirectSourceCoordinates(actual) {assert.strictEqual(actual, prepared);
      return ok(Array.from({length: count}, (_, index) => [index, 0, index, index]));},
    clientProgramInstalledEffectManagedOperationPlan(parent, actual, identity) {
      assert.strictEqual(this, moon); same(parent, actual, identity); return ok(operationPlan);
    },
    clientProgramInstalledEffectManagedHostOpen() {assert.fail('Authored refusal cannot reach a Compute Host');},
    clientProgramSelectInstalledEffectSourceInput(actual, identity, task, input) {
      assert.strictEqual(actual, prepared); assert.strictEqual(identity, request);
      assert.equal(count, 1); assert.deepEqual([task, input], [0, 0]); return ok(selected);
    },
    clientProgramSelectedSourceInputKind(actual) {assert.strictEqual(actual, selected); return 'query';},
    clientProgramSelectedSourceInputRef(actual) {assert.strictEqual(actual, selected); return 'fixture';},
    clientProgramInstalledEffectManagedPlanSource(plan, task) {
      assert.strictEqual(plan, operationPlan); assert.equal(count, 1); assert.equal(task, 0);
      return ok({_0: {}, _1: requirement, _2: {}, _3: capacity});
    },
    clientProgramQueryRequirementSourceRef(actual) {assert.strictEqual(actual, requirement); return 'fixture';},
    clientProgramInstalledEffectManagedRunPrepareLedger(parent, actual, identity, capacities, transfer, execution) {
      same(parent, actual, identity); assert.deepEqual(capacities, [capacity]);
      assert.deepEqual(transfer, [budget.transferBytes]); assert.deepEqual(execution, [budget.executionBytes]);
      return ok(ledger);
    },
    clientProgramMultiCapturedLedgerUsage(actual) {
      assert.strictEqual(actual, ledger); return undefined; // No measured Resource DATA in this composition fixture.
    },
  };
  return {managedRun, acquired: {...acquired, requestIdentity: request}, moon, preparedSource,
    ledgerCapacity(actual) {assert.strictEqual(actual, preparedSource); return budget;}};
}

function fixture({restoring, selected = true} = {}) {
  let originalCurrent = true, runCurrent = true, claimCurrent = true;
  const calls = [];
  const signal = new AbortController();
  const occurrence = {stage: 0, input: 0, task: 0};
  const scope = {...occurrence, checkedSource: {sourceDataPolicyCid: 'source-policy'},
    readTuple: {source: 'fixture'}, physicalBinding: {binding: 'fixture'},
    physicalPolicy: {policy: 'fixture'}};
  const captured = {requirement: 'requirement', acquisition: null,
    capture: {source: () => 'source'}};
  const source = {occurrence, preparedSource: {...scope, occurrence},
    adapter: {retainedCapture: () => ({requirement: 'requirement', capacity: {},
      referenceIssuer: {}})}};
  const record = {version: 'actql-host-source-capture/0.1', run_definition_cid: 'run',
    scope, acquisition: null, source_evidence_wire: 'evidence',
    requirement_cid: 'requirement', descriptor: {}, rows: [],
    capture_started_at: 1, capture_completed_at: 2};
  const saved = {version: 'actql-acquired-effect-continuation/0.1',
    run_definition_cid: 'run', unit_id: 'unit', submission: {request: 'original'},
    pending_task: restoring === 'resume' ? 0 : null,
    sources: [{scope, ...(restoring === 'model' ? {capture_cid: 'retained'} : {})}]};
  const resume = restoring === 'resume' ? {active: true, claim: {},
    view: {checkpointCid: 'checkpoint'}, continuation: saved,
    assertCurrent() { if (!claimCurrent) throw new Error('ClaimExpired'); }} : undefined;
  const gate = {
    assertCurrent() {},
    async authorize() { calls.push('authorize'); return {action: 'dispatch'}; },
    async resume() { calls.push('resume'); return {action: 'dispatch'}; },
    close() { calls.push('gate-close'); },
  };
  const checkpoints = {
    journal: {committedApprovalAt: () => ({current: true})},
    async computationSourceAuthorization(options) {
      calls.push('gate'); this.options = options; return gate;
    },
    async computationSourceReferences() { calls.push('references'); return ['retained']; },
    async readComputationSource() { calls.push('read-retained'); return Buffer.from(JSON.stringify(record)); },
    async retainComputationSource() { calls.push('retain'); return 'retained'; },
    async retireComputationSources() { calls.push('retire'); },
  };
  let captureCurrent;
  const moon = {
    clientProgramExportSourceCapture: () => ok({}),
    clientProgramSourceCaptureExportRequirement: () => 'requirement',
    clientProgramSourceCaptureExportDescriptor: () => ({}),
    clientProgramSourceCaptureExportRows: () => [],
    clientProgramRestoreSourceCapture(...args) { captureCurrent = args[8]; return ok({}); },
    clientProgramSourceCaptureSource: () => 'source',
    clientProgramIdentifyQueryCapturedEffectSourceRelation(source, requirement) {
      assert.equal(source, 'source'); assert.equal(requirement, 'requirement'); return ok('identity');
    },
    clientProgramEffectIssueCapturedSourceLogicalAt: () => ok('logical'),
    clientProgramCloseSourceCapture() { calls.push('capture-close'); return true; },
  };
  const base = {authorization: {async authorize() {
    calls.push('base-authorize'); return {action: 'dispatch'};
  }}};
  const assertion = () => { if (!originalCurrent) throw changed(); };
  const options = {checkpoints, moon, acquired: {runDefinition: {identity: 'run'},
    control: {runDefinitionRunId: () => 'run-id'}},
    submission: saved.submission, unitId: 'unit', principalId: 'principal',
    declaredResults: [], signal: signal.signal, currentRun: () => runCurrent, resume,
    ...(selected ? {assertUpdateSelectionCurrent: assertion} : {}),
    ...(restoring === 'model' ? {restore: {view: {}, continuation: saved}} : {})};
  const continuation = acquiredEffectContinuation(options);
  const access = continuation.accessFor(base, occurrence);
  return {continuation, access, options, checkpoints, gate, base, calls,
    source, captured, record, signal, captureCurrent: () => captureCurrent(),
    prepare: () => continuation.prepared([source]),
    revoke: () => { originalCurrent = false; },
    cancel: () => { runCurrent = false; },
    expire: () => { claimCurrent = false; }};
}

async function rejectAfterPause(f, paused, start, mutate = f.revoke, error = expected) {
  const result = start();
  const rejected = assert.rejects(result, error);
  await paused.entered;
  mutate();
  paused.release();
  await rejected;
}

test('source gate creation rechecks the same owner and retains gate cleanup', async () => {
  const f = fixture();
  await f.prepare();
  const paused = pause(f.gate);
  f.checkpoints.computationSourceAuthorization = paused.run;
  await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source));
  assert.equal(f.calls.includes('authorize'), false);
  await f.continuation.close();
  assert.deepEqual(f.calls, ['gate-close', 'retire']);
});

for (const action of ['dispatch', 'waiting']) {
  test(`source authorization cannot return ${action} after owner change`, async () => {
    const f = fixture();
    await f.prepare();
    const paused = pause({action, checkpoint: {}});
    f.gate.authorize = paused.run;
    await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source));
  });
}

test('source acquisition entry rechecks after authorization returns', async () => {
  const f = fixture();
  await f.prepare();
  let entered = false;
  f.gate.authorize = async () => ({action: 'dispatch', admission: {
    enter() { entered = true; },
  }});
  const admission = await f.continuation.beforeRead(f.source);
  f.revoke();
  assert.throws(admission.enter, expected);
  assert.equal(entered, false);
});

test('source access refuses before and after the account authorization await', async () => {
  const before = fixture();
  before.revoke();
  await assert.rejects(before.access.authorization.authorize('acquisition', {}), expected);
  assert.deepEqual(before.calls, []);
  const f = fixture();
  const paused = pause({action: 'dispatch'});
  f.base.authorization.authorize = paused.run;
  await rejectAfterPause(f, paused,
    () => f.access.authorization.authorize('acquisition', {}));
});

test('resumed source gate cannot consume stale installed selection', async () => {
  const f = fixture({restoring: 'resume'});
  f.checkpoints.computationSourceReferences = async () => [];
  await f.prepare();
  const paused = pause({action: 'dispatch'});
  f.gate.resume = paused.run;
  await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source));
});

for (const boundary of ['references', 'read-retained']) {
  test(`Model source restoration fences the ${boundary} await`, async () => {
    const f = fixture({restoring: 'model'});
    const paused = pause(boundary === 'references' ? ['retained']
      : Buffer.from(JSON.stringify(f.record)));
    f.checkpoints[boundary === 'references' ? 'computationSourceReferences'
      : 'readComputationSource'] = paused.run;
    await rejectAfterPause(f, paused, f.prepare);
    assert.equal(f.calls.includes('gate'), false);
  });
}

test('retained source account revalidation fences before returning its original', async () => {
  const f = fixture({restoring: 'model'});
  await f.prepare();
  const paused = pause({action: 'dispatch'});
  f.base.authorization.authorize = paused.run;
  await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source));
});

test('a restored source runtime callback observes the original installed owner', async () => {
  const f = fixture({restoring: 'model'});
  await f.prepare();
  const {retained} = await f.continuation.beforeRead(f.source);
  f.continuation.restore(f.source, retained, {});
  assert.equal(f.captureCurrent(), true);
  f.revoke();
  assert.equal(f.captureCurrent(), false);
  await f.continuation.close();
  assert.equal(f.calls.includes('capture-close'), true);
});

test('retention cannot hand a Model closure forward after owner change', async () => {
  const f = fixture();
  await f.prepare();
  await f.continuation.captured(f.source, f.captured, 'evidence', 1, 2);
  const paused = pause('retained');
  f.checkpoints.retainComputationSource = paused.run;
  await rejectAfterPause(f, paused, () => f.continuation.retainAll());
  await f.continuation.close();
  assert.deepEqual(f.calls, ['retire']);
});

test('current Model closure preserves the original continuation shape', async () => {
  const f = fixture();
  await f.prepare();
  await f.continuation.captured(f.source, f.captured, 'evidence', 1, 2);
  const closure = await f.continuation.retainAll();
  assert.equal(closure.pending_task, null);
  assert.deepEqual(closure.submission, {request: 'original'});
  assert.equal(closure.sources[0].capture_cid, 'retained');
  assert.equal(Object.hasOwn(closure, 'assertUpdateSelectionCurrent'), false);
  assert.deepEqual(f.calls, ['retain']);
});

test('run cancellation, abort and resume expiry survive combined fencing', async () => {
  for (const kind of ['cancel', 'abort', 'claim']) {
    const f = fixture({restoring: kind === 'claim' ? 'resume' : undefined});
    f.checkpoints.computationSourceReferences = async () => [];
    await f.prepare();
    const paused = pause({action: 'dispatch'});
    f.gate[kind === 'claim' ? 'resume' : 'authorize'] = paused.run;
    await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source),
      kind === 'cancel' ? f.cancel : kind === 'claim' ? f.expire
        : () => f.signal.abort(new Error('Aborted')),
      kind === 'cancel' ? {code: 'ClientRunCancellationRequested'}
        : {message: kind === 'claim' ? 'ClaimExpired' : 'Aborted'});
  }
});

test('asynchronous selected assertions never admit a source', async () => {
  for (const value of [false, async () => {}, () => Promise.reject(changed())]) {
    const f = fixture();
    const owner = acquiredEffectContinuation({...f.options, assertUpdateSelectionCurrent: value});
    assert.throws(() => owner.accessFor(f.base, f.source.occurrence), expected);
    assert.deepEqual(f.calls, []);
  }
});

test('unselected current Source continuation requires no installed selection callback', async () => {
  const f = fixture({selected: false});
  await f.prepare();
  f.revoke();
  const admission = await f.continuation.beforeRead(f.source);
  assert.equal(typeof admission.enter, 'function');
  admission.enter();
});

test('Model prime refusal preserves its original token for cleanup', async () => {
  let current = true, custody, released;
  const token = {snapshot: {}}, record = {inventory: {taskIndex: 0}};
  const paused = pause(token);
  const ports = managedComposition({prepared: {}, runDefinition: {},
    control: {runDefinitionRunId: () => 'run'}}, 0);
  const result = openAcquiredEffectComputation({
    moon: Object.assign(ports.moon, {clientProgramInferPlanBoundary: () => ({_0: 0})}),
    managedRun: ports.managedRun, acquired: ports.acquired,
    infer: {graph: {}, observeAccount: () => ({})},
    retainComputationOwner(value) { custody = value; },
    assertUpdateSelectionCurrent() { if (!current) throw changed(); },
    modelController: {discover: () => [record], prime: paused.run,
      release(value) { released = value; }},
  });
  const rejected = assert.rejects(result, expected);
  await paused.entered;
  current = false;
  paused.release();
  await rejected;
  assert.equal(custody.cleanupPending(), true);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.equal(released, token);
});

test('asynchronous selected assertions never start acquisition computation', async () => {
  for (const assertion of [false, async () => {}, () => Promise.reject(changed())]) {
    let custody, selected = false;
    await assert.rejects(openAcquiredEffectComputation({
      moon: {clientProgramEffectAcquisitionCount() { return 0; },
        clientProgramInferPlanBoundary() { selected = true; return {_0: 0}; }},
      acquired: {prepared: {}}, infer: {graph: {}},
      retainComputationOwner(value) { custody = value; },
      assertUpdateSelectionCurrent: assertion,
    }), expected);
    assert.equal(selected, false);
    await custody.close();
    assert.equal(await custody.cleanup(), true);
  }
});

for (const boundary of ['prepare', 'open', 'evidence']) {
  test(`Source ${boundary} await refuses stale selection without losing cleanup`, async () => {
    let current = true, custody;
    const calls = [];
    const captured = {checkedSource: {sourceDataPolicyCid: 'policy'},
      async issueSourceEvidence() { calls.push('evidence'); return 'evidence'; },
      async close() { calls.push('close'); }};
    const ports = managedComposition({prepared: {}}, 1);
    const adapter = {admitsSource: () => true,
      ledgerCapacity: ports.ledgerCapacity,
      async prepare() { calls.push('prepare'); return ports.preparedSource; },
      async open() { calls.push('open'); return captured; }};
    const paused = pause(boundary === 'prepare' ? ports.preparedSource : boundary === 'open' ? captured : 'evidence');
    if (boundary === 'evidence') captured.issueSourceEvidence = paused.run;
    else adapter[boundary] = paused.run;
    const result = openAcquiredEffectComputation({
      moon: Object.assign(ports.moon, {clientProgramEffectPrepareLocalQueryRequirement() {
        assert.fail('The SAME managed Plan already owns its Source requirement');
      }, clientProgramEffectSerializationOccurrences: () => []}),
      managedRun: ports.managedRun, acquired: ports.acquired, sourceProfile: adapter, now: () => 1,
      retainComputationOwner(value) { custody = value; },
      assertUpdateSelectionCurrent() { if (!current) throw changed(); },
    });
    const rejected = assert.rejects(result, expected);
    await paused.entered;
    current = false;
    paused.release();
    await rejected;
    await custody.close();
    assert.equal(await custody.cleanup(), true);
    assert.deepEqual(calls, boundary === 'prepare' ? []
      : boundary === 'open' ? ['prepare', 'close'] : ['prepare', 'open', 'close']);
  });
}

async function modelSelectionFixture({selected = true, observer = true} = {}) {
  let originalCurrent = true, mutateDuringObservation = false, observations = 0;
  let custody, projection;
  const account = {}, graph = {}, token = {snapshot: {}};
  const record = {inventory: {taskIndex: 0}};
  const original = Object.freeze({graph, account,
    ...(observer ? {observeAccount() {
      assert.equal(this, original);
      observations++;
      if (mutateDuringObservation) originalCurrent = false;
      return account;
    }} : {})});
  const ports = managedComposition({prepared: {}, runDefinition: {}, control: {
    runDefinitionRunId: () => 'run', adoptCheckedClientEffectInferRun: () => ({}),
  }}, 0);
  const result = openAcquiredEffectComputation({
    moon: Object.assign(ports.moon, {
      clientProgramInferPlanBoundary: () => ({_0: 0}),
      clientProgramEffectSerializationOccurrences: () => []}),
    managedRun: ports.managedRun, acquired: ports.acquired,
    infer: original, now: () => 1,
    retainComputationOwner(value) { custody = value; },
    ...(selected ? {assertUpdateSelectionCurrent() {
      if (!originalCurrent) throw changed();
    }} : {}),
    modelController: {discover: () => [record], prime: async () => token,
      state: () => ({slots: []}), release() {},
      savedScope(plan, prepared, value) {
        projection = value;
        throw new Error('StopAtExistingSavedScope');
      }},
  });
  await assert.rejects(result, {message: observer || !selected
    ? 'StopAtExistingSavedScope' : 'InstalledInferAuthorityUnavailable'});
  return {account, graph, original, projection, custody,
    observations: () => observations,
    revoke: () => { originalCurrent = false; },
    revokeDuringObservation: () => { mutateDuringObservation = true; }};
}

test('selected Model observer preserves the actual account and selection fields', async () => {
  const f = await modelSelectionFixture();
  assert.notEqual(f.projection, f.original);
  assert.equal(Object.isFrozen(f.projection), true);
  assert.equal(f.projection.graph, f.graph);
  assert.equal(f.projection.account, f.account);
  assert.equal(f.projection.observeAccount(), f.account);
  assert.equal(f.observations(), 1);
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);
});

test('selected Model observer rechecks the same owner before and after observation', async () => {
  for (const during of [false, true]) {
    const f = await modelSelectionFixture();
    if (during) f.revokeDuringObservation();
    else f.revoke();
    assert.throws(() => f.projection.observeAccount(), expected);
    assert.equal(f.observations(), during ? 1 : 0);
    await f.custody.close();
    assert.equal(await f.custody.cleanup(), true);
  }
});

test('selected Model requires its original account observer within retained custody', async () => {
  const f = await modelSelectionFixture({observer: false});
  assert.equal(f.projection, undefined);
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);
});

test('unselected Model keeps its original selection and account observer', async () => {
  const f = await modelSelectionFixture({selected: false});
  assert.equal(f.projection, f.original);
  f.revoke();
  assert.equal(f.projection.observeAccount(), f.account);
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);
});

for (const selected of [false, true]) {
  test(`a ${selected ? 'selected' : 'unselected current'} resumed Source may defer its next Source`, async () => {
    const f = fixture({restoring: 'resume', selected});
    let completed = false, published;
    const successor = {checkpointCid: 'next-checkpoint'};
    f.options.resume.assertCurrent = () => {
      if (completed) throw Object.assign(new Error('ResumeClaimStale'), {code: 'ResumeClaimStale'});
    };
    f.checkpoints.journal.completeResume = (claim, {checkpoint}) => {
      assert.equal(claim, f.options.resume.claim);
      assert.equal(checkpoint, successor);
      assert.equal(completed, false);
      completed = true;
      published = checkpoint;
      return checkpoint;
    };
    f.checkpoints.computationSourceReferences = async () => [];
    const occurrence = {stage: 1, input: 0, task: 1};
    const source = {...f.source, occurrence,
      preparedSource: {...f.source.preparedSource, ...occurrence, occurrence}};
    f.continuation.accessFor(f.base, occurrence);
    const {occurrence: ignored, ...scope} = source.preparedSource;
    void ignored;
    f.options.resume.continuation.sources.push({scope});
    await f.continuation.prepared([f.source, source]);
    const first = await f.continuation.beforeRead(f.source);
    first.enter();
    await f.continuation.captured(f.source, f.captured, 'evidence', 1, 2);
    f.gate.authorize = async () => {
      await f.checkpoints.options.beforeDefer();
      const continuation = JSON.parse(await f.checkpoints.options.continuation());
      assert.equal(continuation.pending_task, 1);
      f.checkpoints.options.journalPort.persistCheckpoint(successor);
      return {action: 'waiting', checkpoint: successor};
    };
    const result = await f.continuation.beforeRead(source);
    assert.equal(result.waiting, successor);
    assert.equal(published, successor);
    assert.equal(f.options.resume.active, true, 'No fabricated lease-state transition');
    assert.throws(first.enter, {code: 'ResumeClaimStale'});
    await f.continuation.close();
  });
}

test('outer Source waiting handoff does not reuse a journal-consumed claim', async () => {
  let claimCurrent = true, custody, reads = 0;
  const checkpoint = {};
  const ports = managedComposition({prepared: {}}, 1);
  const result = await openAcquiredEffectComputation({
    moon: Object.assign(ports.moon, {clientProgramEffectPrepareLocalQueryRequirement() {
      assert.fail('The SAME managed Plan already owns its Source requirement');
    }, clientProgramEffectSerializationOccurrences: () => []}),
    managedRun: ports.managedRun, acquired: ports.acquired, now: () => 1,
    sourceProfile: {admitsSource: () => true, prepare: async () => ports.preparedSource,
      ledgerCapacity: ports.ledgerCapacity,
      async open() { reads++; assert.fail('Waiting is not a read admission'); }},
    sourceContinuation: {accessFor: () => undefined, prepared: async () => {},
      times: () => ({}), close: async () => {},
      async beforeRead() { claimCurrent = false; return {waiting: checkpoint}; }},
    assertUpdateSelectionCurrent() {},
    assertContinuationCurrent() { if (!claimCurrent) throw new Error('ResumeClaimStale'); },
    retainComputationOwner(value) { custody = value; },
  });
  assert.equal(result.status, 'waiting_checkpoint');
  assert.equal(result.checkpoint, checkpoint);
  assert.equal(reads, 0);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
});

test('selected Source account scope is rechecked after authorization awaits', async () => {
  const f = fixture();
  await f.prepare();
  let accountCurrent = true;
  f.gate.assertCurrent = () => {
    if (!accountCurrent) throw new Error('AuthorizationCurrentAccountChanged');
  };
  const paused = pause({action: 'dispatch'});
  f.gate.authorize = paused.run;
  await rejectAfterPause(f, paused, () => f.continuation.beforeRead(f.source),
    () => { accountCurrent = false; }, {message: 'AuthorizationCurrentAccountChanged'});
});

test('recorded Source approval keeps original account, selection, approval and entry owners', async () => {
  const f = fixture({restoring: 'resume'});
  f.checkpoints.computationSourceReferences = async () => [];
  let entered = 0, accountCurrent = true, approvalCurrent = true;
  f.gate.assertCurrent = () => {
    if (!accountCurrent) throw new Error('AuthorizationCurrentAccountChanged');
  };
  f.gate.resume = async () => ({action: 'dispatch', admission: {
    enter() { entered++; },
  }});
  f.base.authorization.authorize = async () => ({action: 'unsupported'});
  f.checkpoints.journal.committedApprovalAt = () => ({current: approvalCurrent});
  await f.prepare();
  const admission = await f.continuation.beforeRead(f.source);
  admission.enter();
  assert.equal(entered, 1);
  const decision = await f.access.authorization.authorize('acquisition', f.record.scope.readTuple);
  const approval = checkpointApprovalFacts(decision);
  assert.equal(typeof approval.assertCurrent, 'function');
  assert.equal(typeof approval.enter, 'function');
  assert.equal(approval.enter, admission.enter);
  approval.assertCurrent();
  assert.equal(entered, 1, 'Currency must never consume the original admission');
  approval.enter();
  assert.equal(entered, 1, 'The existing entry is never consumed twice');
  accountCurrent = false;
  assert.throws(approval.enter, {message: 'AuthorizationCurrentAccountChanged'});
  accountCurrent = true;
  approvalCurrent = false;
  assert.throws(approval.assertCurrent, {code: 'ApprovalExpired'});
  approvalCurrent = true;
  f.revoke();
  assert.throws(approval.enter, expected);
  assert.equal(entered, 1);
});

test('failed Source admission entry remains retryable through the same owner closure', async () => {
  const f = fixture();
  await f.prepare();
  let attempts = 0;
  f.gate.authorize = async () => ({action: 'dispatch', admission: {
    enter() {
      attempts++;
      if (attempts === 1) throw new Error('AdmissionEnterFailed');
    },
  }});
  const admission = await f.continuation.beforeRead(f.source);
  assert.throws(admission.enter, {message: 'AdmissionEnterFailed'});
  admission.enter();
  admission.enter();
  assert.equal(attempts, 2);
  f.revoke();
  assert.throws(admission.enter, expected);
  assert.equal(attempts, 2);
});

test('Source access current hook reuses the same original installation and account scope', async () => {
  const f = fixture();
  await f.prepare();
  await f.continuation.beforeRead(f.source);
  f.access.assertCurrent();
  f.gate.assertCurrent = () => { throw new Error('AuthorizationCurrentAccountChanged'); };
  assert.throws(f.access.assertCurrent, {message: 'AuthorizationCurrentAccountChanged'});
  f.gate.assertCurrent = () => {};
  f.revoke();
  assert.throws(f.access.assertCurrent, expected);
});


test('retained fresh Source carries its original approved decision into cold current authorization without a new read', async () => {
  const f=fixture(), scope=f.record.scope;
  const approval=recordCheckpointApproval(Object.freeze({action:'dispatch',boundary:'acquisition'}),{
    checkpointCid:'original-source-checkpoint',earlierCheckpointCids:Object.freeze(['earlier-source-checkpoint']),principalId:'principal',readTuple:scope.readTuple,
    checkedSource:scope.checkedSource,physicalBinding:scope.physicalBinding,
    occurrence:{...f.source.occurrence,requirement_cid:'original-requirement',selection_cid:'original-selection'}});
  let stored;
  f.checkpoints.retainComputationSource=async(run,definition,wire)=>{stored=JSON.parse(wire);return 'retained';};
  await f.prepare();await f.continuation.captured(f.source,f.captured,'evidence',1,2,approval);
  const closure=await f.continuation.retainAll();
  assert.equal(stored.checkpoint_cid,'original-source-checkpoint');assert.deepEqual(stored.earlier_checkpoint_cids,['earlier-source-checkpoint']);assert.equal(closure.sources[0].capture_cid,'retained');
  assert.equal(f.calls.includes('base-authorize'),false,'No second original authorization at retention');
  const cold=fixture({restoring:'model'});
  cold.checkpoints.readComputationSource=async()=>Buffer.from(JSON.stringify(stored));
  cold.base.authorization.authorize=async()=>({action:'waiting'});
  let current=true, earlierCurrent=true; cold.checkpoints.journal.committedApprovalAt=cid=>{assert(['original-source-checkpoint','earlier-source-checkpoint'].includes(cid));return {current:cid==='earlier-source-checkpoint'?earlierCurrent:current};};
  await cold.prepare();assert.equal((await cold.continuation.beforeRead(cold.source)).retained.checkpoint_cid,'original-source-checkpoint');
  assert.equal(cold.calls.includes('resume'),false);assert.equal(cold.calls.includes('authorize'),false);
  earlierCurrent=false;await assert.rejects(cold.continuation.beforeRead(cold.source),{code:'ApprovalExpired'});earlierCurrent=true;
  current=false;await assert.rejects(cold.continuation.beforeRead(cold.source),{code:'ApprovalExpired'});
  current=true;await cold.continuation.close();await f.continuation.close();
});

test('fresh Source closure refuses copied or foreign original approval facts before persistence', async () => {
  for(const changed of ['copy','tuple','source','binding','principal','installation','occurrence']) {
    const f=fixture(),scope=f.record.scope;
    const facts={checkpointCid:'original-source-checkpoint',principalId:'principal',readTuple:scope.readTuple,
      checkedSource:scope.checkedSource,physicalBinding:scope.physicalBinding};
    if(changed==='tuple')facts.readTuple={source:'foreign'};
    if(changed==='source')facts.checkedSource={sourceDataPolicyCid:'foreign'};
    if(changed==='binding')facts.physicalBinding={binding:'foreign'};
    if(changed==='principal')facts.principalId='foreign';
    if(changed==='installation')facts.installationBinding={binding:'foreign'};
    if(changed==='occurrence')facts.occurrence={stage:1,input:0,task:1};
    const original=recordCheckpointApproval(Object.freeze({action:'dispatch',boundary:'acquisition'}),facts);
    const approval=changed==='copy'?Object.freeze({...original}):original;
    await f.prepare();await assert.rejects(f.continuation.captured(f.source,f.captured,'evidence',1,2,approval),{code:'HeldAcquisitionChanged'});
    assert.equal(f.calls.includes('retain'),false);await f.continuation.close();
  }
});

test('fresh Source keeps its installed binding when singular approval has no installation fact', async () => {
  const f = fixture(), scope = f.record.scope;
  const binding = Object.freeze({connectorId: 'fixture', connectorRegistration: 'fixture',
    connectorRevision: 'original', bindingCid: `sha256:${'a'.repeat(64)}`});
  f.source.adapter.ordinaryRecoveryBinding = prepared => {
    assert.equal(prepared, f.source.preparedSource);
    return binding;
  };
  const approval = recordCheckpointApproval(Object.freeze({action: 'dispatch', boundary: 'acquisition'}), {
    checkpointCid: 'original-source-checkpoint', principalId: 'principal', readTuple: scope.readTuple,
    checkedSource: scope.checkedSource, physicalBinding: scope.physicalBinding});
  let stored;
  f.checkpoints.retainComputationSource = async (run, definition, wire) => {
    stored = JSON.parse(wire); return 'retained';
  };
  await f.prepare();
  await f.continuation.captured(f.source, f.captured, 'evidence', 1, 2, approval);
  const closure = await f.continuation.retainAll();
  assert.deepEqual(stored.scope.installationBinding, binding);
  assert.deepEqual(closure.sources[0].scope.installationBinding, binding);
  assert.equal(stored.checkpoint_cid, 'original-source-checkpoint');
  assert.equal(checkpointApprovalFacts(approval).installationBinding, undefined,
    'Retention must not add a binding to the original singular approval');
  assert.equal(f.calls.includes('base-authorize'), false);
  await f.continuation.close();
});

test('fresh Source checks a present installation approval fact against its actual installed binding', async () => {
  for (const foreign of [false, true]) {
    const f = fixture(), scope = f.record.scope;
    const binding = {connectorId: 'fixture', connectorRegistration: 'fixture',
      connectorRevision: 'original', bindingCid: `sha256:${'a'.repeat(64)}`};
    f.source.adapter.ordinaryRecoveryBinding = () => binding;
    const approval = recordCheckpointApproval(Object.freeze({action: 'dispatch', boundary: 'acquisition'}), {
      checkpointCid: 'original-source-checkpoint', principalId: 'principal', readTuple: scope.readTuple,
      checkedSource: scope.checkedSource, physicalBinding: scope.physicalBinding,
      installationBinding: {...binding, connectorRevision: foreign ? 'foreign' : 'original'}});
    await f.prepare();
    const result = f.continuation.captured(f.source, f.captured, 'evidence', 1, 2, approval);
    if (foreign) await assert.rejects(result, {code: 'HeldAcquisitionChanged'});
    else await result;
    assert.equal(f.calls.includes('retain'), false);
    await f.continuation.close();
  }
});
