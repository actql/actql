import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {
  ExecutionAuthorizationError,
  createAuthorizationGate,
  missingAuthorizationGate,
  requireAuthorizedDispatch,
} from '../host-common/authorization-gate.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';
import {
  FIXTURE_CONFIGURATION_CID,
  FIXTURE_CONTEXT,
  accountConfiguration,
  accountEntry,
  fixtureAuthorization,
  sqliteDeferral,
} from './authorization-fixture.mjs';

const scope = Object.freeze({
  connection: 'warehouse',
  resource: 'orders',
  operation: 'read',
});
const subjectCid = `sha256:${'5'.repeat(64)}`;
const delegateEntries = [accountEntry('review-warehouse', 'delegate', {
  connection: 'warehouse',
})];
const permitWith = (overrides = {}) => view => ({
  decision: 'permit',
  subject: view.subject,
  authority: 'reviewer',
  claims: [...view.requiredClaims],
  ...overrides,
});

async function workspace(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-authorization-gate-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

test('allow dispatches with zero Host calls and zero Checkpoints', async () => {
  let calls = 0;
  const gate = await fixtureAuthorization(
    [accountEntry('local-read', 'allow', {operation: 'read'})],
    {decide: () => { calls++; }, answeringAuthorities: ['reviewer']},
  );
  const decision = await gate.authorize('acquisition', scope, {subjectCid});
  assert.equal(decision.action, 'dispatch');
  assert.equal(decision.basis, 'account_allow');
  assert.equal(decision.entryId, 'local-read');
  assert.deepEqual(decision.tuple, {principal: 'local-user', ...scope});
  assert.equal(calls, 0);
  assert.deepEqual(gate.counters(), {
    evaluations: 1, hostDecisionCalls: 0, checkpointsPersisted: 0,
    protectedDispatches: 1, deniedBeforeDispatch: 0, decisionFailures: 0,
    unsupportedDefers: 0, hostRejections: 0, reusedDecisions: 0,
    coveredOperations: 0, resumedDecisions: 0,
  });
});

test('explicit deny, no-match deny and missing configuration never ask the Host',
  async () => {
    let calls = 0;
    const decide = () => { calls++; return {decision: 'permit'}; };
    const gate = await fixtureAuthorization([
      accountEntry('delegate-warehouse', 'delegate', {
        connection: 'warehouse',
        exclusions: [{resource: 'payroll'}],
      }),
      accountEntry('deny-payroll', 'deny', {
        connection: 'warehouse', resource: 'payroll',
      }),
    ], {decide, answeringAuthorities: ['reviewer']});
    const explicit = await gate.authorize('acquisition',
      {...scope, resource: 'payroll'}, {subjectCid});
    assert.equal(explicit.action, 'deny');
    assert.equal(explicit.reason, 'explicit');
    const unmatched = await gate.authorize('acquisition',
      {...scope, connection: 'crm'}, {subjectCid});
    assert.equal(unmatched.action, 'deny');
    assert.equal(unmatched.reason, 'no_match');
    const missing = missingAuthorizationGate();
    const absent = await missing.authorize('acquisition', scope, {subjectCid});
    assert.equal(absent.action, 'deny');
    assert.equal(absent.reason, 'configuration_missing');
    const runtime = await loadExecutionAuthorizationRuntime();
    const installedMissing = createAuthorizationGate({
      runtime, context: FIXTURE_CONTEXT, decide,
      answeringAuthorities: ['reviewer'],
    });
    assert.equal((await installedMissing.authorize('acquisition', scope))
      .reason, 'configuration_missing');
    await assert.rejects(
      requireAuthorizedDispatch(gate, 'acquisition',
        {...scope, resource: 'payroll'}, {subjectCid}),
      error => error instanceof ExecutionAuthorizationError &&
        error.code === 'ExecutionAuthorizationDenied',
    );
    assert.equal(calls, 0);
    assert.equal(gate.counters().deniedBeforeDispatch, 3);
    assert.equal(gate.counters().hostDecisionCalls, 0);
  });

test('a rejected configuration fails installation instead of granting',
  async () => {
    const runtime = await loadExecutionAuthorizationRuntime();
    assert.throws(() => createAuthorizationGate({
      runtime,
      configuration: accountConfiguration([
        accountEntry('allow-all', 'allow'),
        accountEntry('deny-orders', 'deny', {resource: 'orders'}),
      ]),
      configurationCid: FIXTURE_CONFIGURATION_CID,
      context: FIXTURE_CONTEXT,
    }), {code: 'ExecutionAuthorizationConfigurationRejected'});
  });

test('delegate permit dispatches; reject is a recorded Host rejection',
  async () => {
    const seen = [];
    const permitting = await fixtureAuthorization(delegateEntries, {
      decide: view => { seen.push(view); return permitWith()(view); },
      answeringAuthorities: ['reviewer'],
    });
    const permitted = await permitting.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(permitted.action, 'dispatch');
    assert.equal(permitted.basis, 'host_permit');
    assert.equal(permitted.authority, 'reviewer');
    assert.equal(seen.length, 1);
    assert.equal(seen[0].subject.boundary, 'acquisition');
    assert.equal(seen[0].subject.subject_cid, subjectCid);
    assert.equal(seen[0].subject.context_cid, FIXTURE_CONTEXT.contextCid);
    assert.equal(seen[0].subject.configuration_cid, FIXTURE_CONFIGURATION_CID);
    assert.equal(permitting.counters().checkpointsPersisted, 0);

    const rejecting = await fixtureAuthorization(delegateEntries, {
      decide: view => ({decision: 'reject', subject: view.subject,
        authority: 'reviewer'}),
      answeringAuthorities: ['reviewer'],
    });
    const rejected = await rejecting.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(rejected.action, 'deny');
    assert.equal(rejected.basis, 'rejected_by_host');
    assert.equal(rejecting.counters().hostRejections, 1);
    assert.equal(rejecting.counters().decisionFailures, 0);
  });

test('decision failures are not rejections and dispatch nothing', async () => {
  const cases = [
    ['throws', () => { throw new Error('ServiceDown'); }, 'adapter_error'],
    ['times out', () => new Promise(() => {}), 'timeout'],
    ['returns malformed', () => ({decision: 'maybe'}), 'malformed_answer'],
    ['echoes another subject', view => permitWith({
      subject: {...view.subject, resource: 'payroll'},
    })(view), 'malformed_answer'],
    ['names an unauthorized authority', permitWith({authority: 'mallory'}),
      'malformed_answer'],
    ['omits a required claim', permitWith({claims: []}), 'malformed_answer'],
    ['is unavailable', () => ({decision: 'unavailable'}), 'unavailable'],
  ];
  for (const [label, decide, reason] of cases) {
    const gate = await fixtureAuthorization(delegateEntries, {
      decide, answeringAuthorities: ['reviewer'],
      requiredClaims: ['partial_application_accepted'],
      decisionTimeoutMs: 20,
    });
    const decision = await gate.authorize('acquisition', scope, {subjectCid});
    assert.equal(decision.action, 'failure', label);
    assert.equal(decision.reason, reason, label);
    const counts = gate.counters();
    assert.equal(counts.decisionFailures, 1, label);
    assert.equal(counts.hostRejections, 0, label);
    assert.equal(counts.protectedDispatches, 0, label);
    // A failure is never reused as a decision.
    await gate.authorize('acquisition', scope, {subjectCid});
    assert.equal(gate.counters().hostDecisionCalls, 2, label);
  }
  // Local delegate default: no decision function and no durable answer path
  // stops before the operation as not configured, never a reject.
  const unanswerable = await fixtureAuthorization(delegateEntries);
  const decision = await unanswerable.authorize('acquisition', scope,
    {subjectCid});
  assert.equal(decision.action, 'unsupported');
  assert.equal(decision.reason, 'decision_function_not_configured');
  assert.equal(unanswerable.counters().hostRejections, 0);
  assert.equal(unanswerable.counters().protectedDispatches, 0);
  await assert.rejects(
    requireAuthorizedDispatch(unanswerable, 'acquisition', scope, {subjectCid}),
    {code: 'ExecutionAuthorizationDeferralUnsupported',
      runtimeCode: 'ACTQL_E_DELEGATION_UNAVAILABLE'},
  );
});

test('without a decision function a durable journal waits in a Checkpoint',
  async t => {
    const root = await workspace(t);
    const deferral = await sqliteDeferral(root);
    t.after(() => deferral.journal.close());
    const gate = await fixtureAuthorization(delegateEntries, {deferral});
    const decision = await gate.authorize('acquisition', scope, {subjectCid});
    assert.equal(decision.action, 'waiting');
    assert.equal(gate.counters().hostDecisionCalls, 0);
    assert.equal(gate.counters().checkpointsPersisted, 1);
    assert.equal(gate.counters().protectedDispatches, 0);
    assert.equal(deferral.journal.listPending()[0].checkpointCid,
      decision.checkpoint.checkpointCid);
  });

test('defer persists a durable Checkpoint before waiting', async t => {
  const root = await workspace(t);
  const deferral = await sqliteDeferral(root);
  t.after(() => deferral.journal.close());
  const gate = await fixtureAuthorization(delegateEntries, {
    decide: view => ({decision: 'defer', subject: view.subject}),
    answeringAuthorities: ['reviewer'],
    deferral,
  });
  const decision = await gate.authorize('acquisition', scope, {subjectCid});
  assert.equal(decision.action, 'waiting');
  const pending = deferral.journal.listPending();
  assert.equal(pending.length, 1);
  assert.equal(pending[0].checkpointCid, decision.checkpoint.checkpointCid);
  assert.equal(pending[0].kind, 'read_access');
  // The reviewed artifact is the sealed subject artifact itself; the exact
  // decision subject is a separate binding stored next to the Checkpoint.
  assert.equal(pending[0].requiredArtifact.cid, subjectCid);
  assert.equal(decision.checkpoint.requiredArtifactCid, subjectCid);
  assert.equal(pending[0].decisionSubjectCid,
    decision.checkpoint.decisionSubjectCid);
  assert.match(pending[0].decisionSubjectCid, /^sha256:[0-9a-f]{64}$/);
  assert.notEqual(pending[0].decisionSubjectCid, subjectCid);
  assert.equal(
    deferral.journal.getRunState(decision.checkpoint.runId).status,
    'waiting_checkpoint',
  );
  assert.equal(gate.counters().checkpointsPersisted, 1);
  assert.equal(gate.counters().protectedDispatches, 0);
});

test('defer requires the sealed subject artifact and no substitute',
  async t => {
    const root = await workspace(t);
    const deferral = await sqliteDeferral(root);
    t.after(() => deferral.journal.close());
    const defer = view => ({decision: 'defer', subject: view.subject});
    const gate = await fixtureAuthorization(delegateEntries, {
      decide: defer, answeringAuthorities: ['reviewer'], deferral,
    });
    // No or malformed subject artifact: nothing to seal, nothing persisted.
    for (const options of [{}, {subjectCid: 'sha256:short'}]) {
      const failed = await gate.authorize('acquisition', scope, options);
      assert.equal(failed.action, 'failure');
      assert.match(failed.detail, /^Invalid(SubjectCid|SubjectArtifact)$/);
    }
    // A Host `describe` naming another artifact is a decision failure.
    const substituting = await fixtureAuthorization(delegateEntries, {
      decide: defer, answeringAuthorities: ['reviewer'],
      deferral: {...deferral, describe(view) {
        const described = deferral.describe(view);
        return {...described, body: {...described.body, required_artifact: {
          artifact_cid: `sha256:${'6'.repeat(64)}`}}};
      }},
    });
    const substituted = await substituting.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(substituted.action, 'failure');
    assert.equal(substituted.detail, 'SubjectArtifactMismatch');
    assert.equal(deferral.journal.listPending().length, 0);
    // Naming the same artifact is accepted.
    const same = await fixtureAuthorization(delegateEntries, {
      decide: defer, answeringAuthorities: ['reviewer'],
      deferral: {...deferral, describe(view) {
        const described = deferral.describe(view);
        return {...described, body: {...described.body, required_artifact: {
          artifact_cid: subjectCid}}};
      }},
    });
    assert.equal((await same.authorize('acquisition', scope, {subjectCid}))
      .action, 'waiting');
  });

test('an immediate answer naming another artifact or subject is malformed',
  async () => {
    let seen;
    const answer = extra => async view => {
      seen = view;
      return {decision: 'permit', subject: view.subject,
        authority: 'reviewer', ...extra(view)};
    };
    const gateFor = extra => fixtureAuthorization(delegateEntries, {
      decide: answer(extra), answeringAuthorities: ['reviewer'],
    });
    const exact = await (await gateFor(view => ({
      subjectArtifactCid: view.subjectArtifactCid,
      decisionSubjectCid: view.decisionSubjectCid,
    }))).authorize('acquisition', scope, {subjectCid});
    assert.equal(exact.action, 'dispatch');
    assert.equal(seen.subjectArtifactCid, subjectCid);
    assert.match(seen.decisionSubjectCid, /^sha256:[0-9a-f]{64}$/);
    for (const extra of [
      () => ({subjectArtifactCid: `sha256:${'6'.repeat(64)}`}),
      () => ({decisionSubjectCid: subjectCid}),
    ]) {
      const other = await (await gateFor(extra)).authorize('acquisition',
        scope, {subjectCid});
      assert.equal(other.action, 'failure');
      assert.equal(other.reason, 'malformed_answer');
    }
  });

async function deferredGate(t, entries = delegateEntries) {
  const root = await workspace(t);
  const deferral = await sqliteDeferral(root);
  t.after(() => deferral.journal.close());
  let calls = 0;
  const gate = await fixtureAuthorization(entries, {
    decide: view => { calls++; return {decision: 'defer', subject: view.subject}; },
    answeringAuthorities: ['reviewer'],
    deferral,
  });
  const waiting = await gate.authorize('acquisition', scope, {subjectCid});
  assert.equal(waiting.action, 'waiting');
  return {deferral, gate, waiting, calls: () => calls};
}

function claimResume(deferral, waiting, claimant = 'owner-a') {
  return deferral.journal.claimResume(waiting.checkpoint.runId,
    {claimant, leaseMs: 60_000, binding: deferral.binding});
}

test('resume dispatches only from a committed approval for the exact subject',
  async t => {
    const {deferral, gate, waiting, calls} = await deferredGate(t);
    const resolution = await deferral.answer(
      waiting.checkpoint.checkpointCid, 'approved');
    assert.equal(resolution.decision, 'approved');
    const claim = claimResume(deferral, waiting);
    assert.equal(claim.action, 'claimed');
    const resumption = {claim, resolution};
    // The committed approval binds the real sealed artifact.
    const checkpoint = deferral.journal.inspect(
      waiting.checkpoint.checkpointCid);
    assert.equal(checkpoint.requiredArtifact.cid, subjectCid);
    const verified = JSON.parse(resolution.verifiedResolutionWire);
    assert.equal(verified.resolution.required_artifact_cid, subjectCid);
    assert.equal(verified.approval_evidence.compatibility_approval
      .prepared_invocation_cid, subjectCid);
    // Another resource, boundary, subject, context or connection is not the
    // approved subject.
    const otherContext = gate.withContext({principal: 'local-user',
      contextCid: `sha256:${'7'.repeat(64)}`});
    for (const [target, boundary, changed, subject] of [
      [gate, 'acquisition', {...scope, resource: 'items'}, subjectCid],
      [gate, 'acquisition', {...scope, operation: 'write'}, subjectCid],
      [gate, 'transfer', scope, subjectCid],
      [gate, 'acquisition', scope, `sha256:${'6'.repeat(64)}`],
      [otherContext, 'acquisition', scope, subjectCid],
    ]) {
      const other = await target.resume(boundary, changed,
        {subjectCid: subject, resumption});
      assert.equal(other.action, 'failure');
      assert.equal(other.detail, 'ResolutionSubjectMismatch');
    }
    const decision = await gate.resume('acquisition', scope,
      {subjectCid, resumption});
    assert.equal(decision.action, 'dispatch');
    assert.equal(decision.basis, 'resumed');
    assert.equal(decision.authority, 'reviewer');
    assert.equal(decision.checkpointCid, waiting.checkpoint.checkpointCid);
    assert.equal(decision.resolutionCid, resolution.resolutionCid);
    // Resumption asks no new Host decision.
    assert.equal(calls(), 1);
    assert.equal(gate.counters().resumedDecisions, 1);
    // A resume without a claimed intent is not a committed approval.
    const unclaimed = await gate.resume('acquisition', scope,
      {subjectCid, resumption: {claim: {action: 'busy'}, resolution}});
    assert.equal(unclaimed.action, 'failure');
    assert.equal(unclaimed.detail, 'ResumeNotClaimed');
  });

test('a rejected Checkpoint has no resume and a later deny still denies',
  async t => {
    const rejected = await deferredGate(t);
    const resolution = await rejected.deferral.answer(
      rejected.waiting.checkpoint.checkpointCid, 'rejected');
    assert.equal(resolution.decision, 'rejected');
    assert.throws(() => claimResume(rejected.deferral, rejected.waiting),
      {code: 'ResumeIntentNotFound'});
    const forged = await rejected.gate.resume('acquisition', scope, {
      subjectCid,
      resumption: {claim: {action: 'claimed',
        checkpointCid: rejected.waiting.checkpoint.checkpointCid,
        claim: {runId: rejected.waiting.checkpoint.runId}},
      resolution: {...resolution, decision: 'approved'}},
    });
    assert.equal(forged.action, 'failure');
    assert.equal(forged.detail, 'RunNotResuming');

    // Approved while waiting, but the account now denies the tuple.
    const approved = await deferredGate(t);
    const committed = await approved.deferral.answer(
      approved.waiting.checkpoint.checkpointCid, 'approved');
    const claim = claimResume(approved.deferral, approved.waiting);
    const denying = await fixtureAuthorization([accountEntry(
      'review-warehouse', 'deny', {connection: 'warehouse'})], {
      deferral: approved.deferral,
    });
    const denied = await denying.resume('acquisition', scope,
      {subjectCid, resumption: {claim, resolution: committed}});
    assert.equal(denied.action, 'deny');
    assert.equal(denied.basis, 'account');
  });

test('defer without a durable journal and answer path is unsupported',
  async t => {
    const root = await workspace(t);
    const durable = await sqliteDeferral(root);
    t.after(() => durable.journal.close());
    for (const deferral of [undefined, {describe: durable.describe},
      {...durable, authorities: []}]) {
      const gate = await fixtureAuthorization(delegateEntries, {
        decide: view => ({decision: 'defer', subject: view.subject}),
        answeringAuthorities: ['reviewer'],
        deferral,
      });
      const decision = await gate.authorize('acquisition', scope, {subjectCid});
      assert.equal(decision.action, 'unsupported');
      assert.equal(gate.counters().unsupportedDefers, 1);
      assert.equal(gate.counters().checkpointsPersisted, 0);
      await assert.rejects(
        requireAuthorizedDispatch(gate, 'acquisition', scope, {subjectCid}),
        {code: 'ExecutionAuthorizationDeferralUnsupported'},
      );
    }
    assert.equal(durable.journal.listPending().length, 0);
  });

test('decisions are reused only for the exact scope and never widened',
  async () => {
    let calls = 0;
    const gate = await fixtureAuthorization(delegateEntries, {
      decide: view => { calls++; return permitWith()(view); },
      answeringAuthorities: ['reviewer'],
    });
    await gate.authorize('acquisition', scope, {subjectCid});
    await gate.authorize('acquisition', scope, {subjectCid});
    assert.equal(calls, 1);
    assert.equal(gate.counters().reusedDecisions, 1);
    // Changed resource, boundary, subject or context each re-evaluate.
    await gate.authorize('acquisition', {...scope, resource: 'items'},
      {subjectCid});
    await gate.authorize('transfer', scope, {subjectCid});
    await gate.authorize('acquisition', scope,
      {subjectCid: `sha256:${'6'.repeat(64)}`});
    const retried = gate.withContext({
      principal: 'local-user', contextCid: `sha256:${'7'.repeat(64)}`,
    });
    await retried.authorize('acquisition', scope, {subjectCid});
    assert.equal(calls, 5);
    // A new principal is evaluated against the account configuration again;
    // a permit for one principal cannot authorize another.
    const other = gate.withContext({
      principal: 'other-user', contextCid: FIXTURE_CONTEXT.contextCid,
    });
    const otherDecision = await other.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(calls, 6);
    assert.equal(otherDecision.tuple.principal, 'other-user');
  });

test('covered operations cost no evaluation and no Host call', async () => {
  let calls = 0;
  const gate = await fixtureAuthorization(delegateEntries, {
    decide: () => { calls++; },
    answeringAuthorities: ['reviewer'],
  });
  for (let index = 0; index < 1000; index++) {
    gate.cover('activation', {connection: 'in-process', resource: 'compute',
      operation: 'write'});
  }
  assert.equal(calls, 0);
  assert.equal(gate.counters().evaluations, 0);
  assert.equal(gate.counters().coveredOperations, 1000);
});
