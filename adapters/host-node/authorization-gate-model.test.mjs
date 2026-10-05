import assert from 'node:assert/strict';
import test from 'node:test';
import {createAuthorizationGate, decisionSubjectCid} from
  '../host-common/authorization-gate.mjs';

// Adapter-only coverage: the gate is real, but the finite runtime/journal
// ports below are explicit test doubles. These tests do not establish Core
// admission, atomic SQLite recovery, physical-input custody or provider I/O.
const cid = digit => `sha256:${digit.repeat(64)}`;
const subjectFields = ['account_id', 'configuration_cid', 'entry_id',
  'principal', 'connection', 'resource', 'operation', 'boundary',
  'subject_cid', 'context_cid'];
const scope = Object.freeze({connection: 'provider-1', resource: 'task-1',
  operation: 'infer'});
const context = Object.freeze({principal: 'principal-1', contextCid: cid('d')});

function fakeCore({outcome = () => 'delegate'} = {}) {
  const seen = [];
  return {seen,
    executionAuthorizationAdmit: () => ({state: 'admitted',
      account_id: 'account-1', configuration_cid: cid('c')}),
    executionAuthorizationMissing: () => ({state: 'missing'}),
    executionAuthorizationAccountJson: JSON.stringify,
    executionAuthorizationEvaluate(account, principal, connection,
      resource, operation) {
      seen.push({principal, connection, resource, operation});
      return {outcome: outcome(operation), entry_id: 'entry-1',
        principal, connection, resource, operation};
    },
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction(value) {
      return value.outcome === 'allow'
        ? {action: 'dispatch', basis: 'account'}
        : {action: 'deny', basis: 'account', reason: 'no_match'};
    },
    executionAuthorizationPrepare(evaluation, configurationCid, boundary,
      subjectCid, contextCid, answeringAuthorities, requiredClaims) {
      return {ok: true, subject: {account_id: 'account-1',
        configuration_cid: configurationCid, entry_id: evaluation.entry_id,
        principal: evaluation.principal, connection: evaluation.connection,
        resource: evaluation.resource, operation: evaluation.operation,
        boundary, subject_cid: subjectCid, context_cid: contextCid},
      answering_authorities: answeringAuthorities, required_claims: requiredClaims};
    },
    executionAuthorizationRequestJson: JSON.stringify,
    executionAuthorizationAnswer(request, kind, subject, authority, claims) {
      assert.deepEqual(subject, subjectFields.map(key => request.subject[key]));
      if (kind === 'defer') return {action: 'checkpoint'};
      if (kind === 'permit') return {action: 'dispatch', authority, claims};
      if (kind === 'reject') return {action: 'deny', authority};
      return {action: 'failure', reason: 'malformed_answer'};
    },
    executionAuthorizationDecisionJson: JSON.stringify,
  };
}

function bodyFor(view) {
  return {checkpoint_id: 'cp-model', continuation_state_cid: cid('1'),
    subject: view.boundary === 'preparation'
      ? {kind: 'prepare_attempt', prepare_attempt_id: 'prep-1',
        continuation: 'start_run'}
      : {kind: 'run_unit', run_id: 'run-1', unit_id: 'unit-1',
        continuation: 'resume_unit'},
    ...(view.boundary === 'preparation' ? {}
      : {run_id: 'run-1', run_definition_cid: cid('2')}),
    review_projection_cid: cid('3'), human_summary: 'Review fixture scope',
    created_at: '2026-10-04T00:00:00.000Z',
    expires_at: '2026-10-05T00:00:00.000Z'};
}

function fixture({describe, persist, decide, coreOptions, requiredClaims = []} = {}) {
  const calls = [];
  const described = [];
  const runtime = fakeCore(coreOptions);
  const journal = {
    async persistCheckpoint(request) {
      calls.push(request);
      if (persist !== undefined) await persist(request);
      return {checkpointCid: cid('4'), checkpointId: request.body.checkpoint_id,
        runId: request.body.run_id ?? null,
        prepareAttemptId: request.body.subject.prepare_attempt_id ?? null,
        runState: 'fixture-durable-wait'};
    },
    submitResolution() { throw new Error('Not used by deferral tests'); },
  };
  const gate = createAuthorizationGate({runtime, configuration: '{}', context,
    ...(decide === undefined ? {} : {decide,
      answeringAuthorities: ['reviewer-1']}),
    requiredClaims,
    maxInFlightDecisions: 1, maxRetainedDecisions: 16,
    deferral: {journal,
      authorities: [{keyId: 'reviewer-key', reviewerId: 'reviewer-1'}],
      binding: {authorizationContextCid: cid('5'), environmentBindingCid: cid('6')},
      describe(view) {
        described.push(view);
        return describe === undefined
          ? {body: bodyFor(view), declaredResults: ['result']}
          : describe(view);
      }}});
  return {gate, calls, described, runtime};
}

const modelDescription = (view, modelCallSet, overrides = {}) => ({
  body: {...bodyFor(view), kind: 'model_invocation',
    required_artifact: {artifact_type: 'model_invocation_scope'}, ...overrides},
  declaredResults: ['result'], modelCallSet,
});
const retainedCallSet = slots => Object.freeze({
  // The actual journal owns verification of these originals and custody.
  scopeWire: 'fixture-scope-original', fixedInputReceiptWire: 'fixture-custody',
  slotWires: Object.freeze(slots),
});

test('explicit infer activation forwards the exact retained inventory atomically', {timeout: 3000}, async () => {
  const held = retainedCallSet(['fixture-slot-0', 'fixture-slot-1']);
  let commit;
  let begin;
  const persisted = new Promise(resolve => { commit = resolve; });
  const started = new Promise(resolve => { begin = resolve; });
  const {gate, calls, described} = fixture({
    describe: view => modelDescription(view, held),
    persist: () => { begin(); return persisted; },
    requiredClaims: ['invocation_scope_approved']});
  try {
    let settled = false;
    const pending = gate.authorize('activation', scope, {subjectCid: cid('a')})
      .then(value => { settled = true; return value; });
    await started;
    assert.equal(calls.length, 1);
    assert.equal(settled, false);
    assert.equal(gate.counters().checkpointsPersisted, 0);
    const request = calls[0];
    assert.equal(request.modelCallSet, held);
    assert.equal(request.body.kind, 'model_invocation');
    assert.equal(request.body.phase, 'preflight');
    assert.deepEqual(request.body.required_artifact,
      {artifact_type: 'model_invocation_scope', artifact_cid: cid('a')});
    assert.deepEqual(request.body.requirements, ['invocation_scope_approved']);
    assert.equal(request.decisionSubjectCid,
      await decisionSubjectCid(described[0].subject));
    assert.equal(request.configurationCid, cid('c'));
    commit();
    const decision = await pending;
    assert.equal(decision.action, 'waiting');
    assert.equal(decision.checkpoint.requiredArtifactCid, cid('a'));
    assert.equal(gate.counters().checkpointsPersisted, 1);
    assert.equal(gate.counters().protectedDispatches, 0);
  } finally { commit(); gate.close(); }
});

test('declared empty inventory is valid while missing inventory fails before persistence', async () => {
  for (const [held, expected] of [[retainedCallSet([]), 'waiting'],
    [undefined, 'failure'], [null, 'failure'], [{}, 'failure'],
    [{slotWires: null}, 'failure'], [[], 'failure']]) {
    const {gate, calls} = fixture({describe: view => modelDescription(view, held)});
    try {
      const result = await gate.authorize('activation', scope, {subjectCid: cid('a')});
      assert.equal(result.action, expected);
      assert.equal(calls.length, expected === 'waiting' ? 1 : 0);
      if (expected === 'failure') assert.equal(result.detail, 'ModelCallInventoryRequired');
    } finally { gate.close(); }
  }
});

test('Model profile refuses wrong operation boundary phase subject artifact and claims', async () => {
  const cases = [
    {boundary: 'acquisition'}, {boundary: 'preparation'},
    {boundary: 'effect_commit'}, {boundary: 'transfer'},
    {operation: 'read'}, {operation: 'write'},
    {overrides: {phase: 'commit'}},
    {overrides: {subject: {kind: 'prepare_attempt'}}},
    {overrides: {required_artifact: {artifact_type: 'budget_scope'}}},
    {overrides: {requirements: ['effect_scope_approved']}},
  ];
  for (const item of cases) {
    const {gate, calls} = fixture({describe: view => modelDescription(view,
      retainedCallSet([]), item.overrides)});
    try {
      const result = await gate.authorize(item.boundary ?? 'activation',
        {...scope, operation: item.operation ?? 'infer'}, {subjectCid: cid('a')});
      assert.equal(result.action, 'failure');
      assert.equal(result.detail, 'ModelCheckpointProfileMismatch');
      assert.equal(calls.length, 0);
    } finally { gate.close(); }
  }
});

test('Model inventory and scope cannot be smuggled through another kind or later subject', async () => {
  for (const overrides of [{kind: 'cost_scope'}, {kind: 'read_access'},
    {kind: undefined}]) {
    const {gate, calls} = fixture({describe: view => modelDescription(view,
      retainedCallSet([]), overrides)});
    try {
      const result = await gate.authorize('activation', scope, {subjectCid: cid('a')});
      assert.equal(result.detail, 'ModelCheckpointProfileMismatch');
      assert.equal(calls.length, 0);
    } finally { gate.close(); }
  }
  const {gate, calls} = fixture({describe: view => modelDescription(view,
    retainedCallSet([]))});
  try {
    const result = await gate.authorize('activation', scope, {
      subjectCid: cid('a'), sealDeferredSubject: () => cid('b')});
    assert.equal(result.detail, 'SubjectArtifactMismatch');
    assert.equal(calls.length, 0);
  } finally { gate.close(); }
});

test('existing default profiles never receive Model inventory', async () => {
  const defaults = [['preparation', 'run_scope', 'prepared_invocation'],
    ['acquisition', 'read_access', 'read_scope'],
    ['activation', 'cost_scope', 'budget_scope'],
    ['transfer', 'data_egress', 'egress_scope'],
    ['effect_commit', 'effect_set', 'effect_set_preview']];
  for (const [boundary, kind, artifact] of defaults) {
    const {gate, calls} = fixture();
    try {
      const result = await gate.authorize(boundary, scope, {subjectCid: cid('a')});
      assert.equal(result.action, 'waiting');
      assert.equal(calls[0].body.kind, kind);
      assert.equal(calls[0].body.required_artifact.artifact_type, artifact);
      assert.equal(Object.hasOwn(calls[0], 'modelCallSet'), false);
    } finally { gate.close(); }
  }
});

test('read approval does not alias infer and immediate decisions do not persist inventories', async () => {
  const denied = fixture({coreOptions: {outcome: operation =>
    operation === 'read' ? 'allow' : 'deny'},
  describe: view => modelDescription(view, retainedCallSet([]))});
  try {
    const result = await denied.gate.authorize('activation', scope, {subjectCid: cid('a')});
    assert.equal(result.action, 'deny');
    assert.equal(denied.runtime.seen[0].operation, 'infer');
    assert.equal(denied.calls.length, 0);
    assert.equal(denied.described.length, 0);
  } finally { denied.gate.close(); }
  const immediate = fixture({decide: view => ({decision: 'permit',
    subject: view.subject, authority: 'reviewer-1', claims: []}),
  describe: view => modelDescription(view, retainedCallSet([]))});
  try {
    const result = await immediate.gate.authorize('activation', scope, {subjectCid: cid('a')});
    assert.equal(result.action, 'dispatch');
    assert.equal(immediate.calls.length, 0);
    assert.equal(immediate.described.length, 0);
  } finally { immediate.gate.close(); }
});

test('failed atomic Model persistence never reports waiting', async () => {
  const {gate, calls} = fixture({describe: view => modelDescription(view,
    retainedCallSet([])), persist: () => { throw new Error('fixture transaction rollback'); }});
  try {
    const result = await gate.authorize('activation', scope, {subjectCid: cid('a')});
    assert.equal(result.action, 'failure');
    assert.equal(result.detail, 'CheckpointNotPersisted');
    assert.equal(calls.length, 1);
    assert.equal(gate.counters().checkpointsPersisted, 0);
  } finally { gate.close(); }
});
