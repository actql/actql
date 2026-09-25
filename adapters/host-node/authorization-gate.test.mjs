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
    coveredOperations: 0,
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
  const unanswerable = await fixtureAuthorization(delegateEntries);
  const decision = await unanswerable.authorize('acquisition', scope,
    {subjectCid});
  assert.equal(decision.action, 'failure');
  assert.equal(decision.reason, 'unavailable');
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
  assert.equal(pending[0].requiredArtifact.cid, subjectCid);
  assert.equal(
    deferral.journal.getRunState(decision.checkpoint.runId).status,
    'waiting_checkpoint',
  );
  assert.equal(gate.counters().checkpointsPersisted, 1);
  assert.equal(gate.counters().protectedDispatches, 0);
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
