import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {
  ExecutionAuthorizationError,
  createAuthorizationGate,
  decisionSubjectCid,
  missingAuthorizationGate,
  requireAuthorizedDispatch,
} from '../host-common/authorization-gate.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';
import {
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

test('deadline aborts only the child and retains uncooperative decisions',
  async () => {
    const parent = new AbortController();
    const pending = [];
    const gate = await fixtureAuthorization(delegateEntries, {
      answeringAuthorities: ['reviewer'], decisionTimeoutMs: 10,
      maxInFlightDecisions: 1,
      decide: (view, {signal}) => new Promise(resolve => {
        pending.push({signal, finish: () => resolve(permitWith()(view))});
      }),
    });
    assert.equal((await gate.authorize('acquisition', scope,
      {subjectCid, signal: parent.signal})).reason, 'timeout');
    assert.equal(pending[0].signal.aborted, true);
    assert.equal(parent.signal.aborted, false);
    assert.equal(gate.resourceUsage().inFlightDecisions, 1);
    const saturated = await gate.authorize('acquisition', scope, {subjectCid});
    assert.equal(saturated.action, 'failure');
    assert.equal(saturated.detail, 'AuthorizationDecisionCapacity');
    assert.equal(pending.length, 1);
    pending[0].finish();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(gate.resourceUsage().inFlightDecisions, 0);
    // The late permit is never installed in the decision scope.
    assert.equal(gate.resourceUsage().retainedDecisions, 0);
    gate.close();
  });

test('decision scopes retain exact judgments until explicit bounded release',
  async () => {
    let calls = 0;
    const gate = await fixtureAuthorization(delegateEntries, {
      answeringAuthorities: ['reviewer'], maxRetainedDecisions: 2,
      decide: view => { calls++; return permitWith()(view); },
    });
    for (let iteration = 0; iteration < 30; iteration++) {
      const scoped = gate.withContext({principal: 'local-user',
        contextCid: `sha256:${iteration.toString(16).padStart(64, '0')}`});
      await scoped.authorize('acquisition', scope, {subjectCid});
      await scoped.authorize('acquisition', scope, {subjectCid});
      assert.equal(scoped.resourceUsage().retainedDecisions, 1);
      scoped.close();
      assert.equal(gate.resourceUsage().retainedDecisions, 0);
      await assert.rejects(scoped.authorize('acquisition', scope, {subjectCid}),
        {code: 'AuthorizationDecisionScopeClosed'});
    }
    assert.equal(calls, 30);
    await gate.authorize('acquisition', scope, {subjectCid});
    await gate.authorize('transfer', scope, {subjectCid});
    const full = await gate.authorize('activation', scope, {subjectCid});
    assert.equal(full.action, 'failure');
    assert.equal(full.detail, 'AuthorizationDecisionCapacity');
    assert.equal(calls, 32);
    assert.equal((await gate.authorize('acquisition', scope,
      {subjectCid})).action, 'dispatch');
    assert.equal(calls, 32);
    gate.close();
    assert.equal(gate.resourceUsage().retainedDecisions, 0);
  });

test('parent abort and scope close preserve physical decision custody',
  async () => {
    for (const finish of ['parent', 'scope']) {
      let entered;
      const ready = new Promise(resolve => { entered = resolve; });
      let settle;
      let child;
      const parent = new AbortController();
      const gate = await fixtureAuthorization(delegateEntries, {
        answeringAuthorities: ['reviewer'],
        decide: (view, {signal}) => {
          child = signal;
          entered();
          return new Promise(resolve => {
            settle = () => resolve(permitWith()(view));
          });
        },
      });
      const response = gate.authorize('acquisition', scope,
        {subjectCid, signal: parent.signal});
      await ready;
      if (finish === 'parent') parent.abort();
      else assert.equal(gate.close(), false);
      if (finish === 'parent') assert.equal((await response).action, 'failure');
      else await assert.rejects(response,
        {code: 'AuthorizationDecisionScopeClosed'});
      assert.equal(child.aborted, true);
      assert.equal(parent.signal.aborted, finish === 'parent');
      assert.equal(gate.cleanupPending(), true);
      assert.equal(gate.cleanup(), false);
      settle();
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(gate.cleanup(), true);
      assert.equal(gate.cleanupPending(), false);
    }
  });

test('cooperative decisions settle after timeout without occupying capacity',
  async () => {
    let stopped = 0;
    const gate = await fixtureAuthorization(delegateEntries, {
      answeringAuthorities: ['reviewer'], decisionTimeoutMs: 10,
      maxInFlightDecisions: 1,
      decide: (_view, {signal}) => new Promise((_, reject) => {
        signal.addEventListener('abort', () => {
          stopped++;
          reject(new Error('Stopped'));
        }, {once: true});
      }),
    });
    for (let attempt = 0; attempt < 3; attempt++) {
      assert.equal((await gate.authorize('acquisition', scope,
        {subjectCid})).reason, 'timeout');
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(gate.resourceUsage().inFlightDecisions, 0);
    }
    assert.equal(stopped, 3);
    assert.equal(gate.close(), true);
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
      configurationCid: `sha256:${'c'.repeat(64)}`,
      context: FIXTURE_CONTEXT,
    }), {code: 'ExecutionAuthorizationConfigurationRejected'});
  });

test('the gate binds the admitted configuration CID, never a stale one',
  async () => {
    const runtime = await loadExecutionAuthorizationRuntime();
    const configuration = accountConfiguration([
      accountEntry('allow-all', 'allow')]);
    const admitted = createAuthorizationGate({runtime, configuration,
      context: FIXTURE_CONTEXT});
    assert.match(admitted.configurationCid, /^sha256:[0-9a-f]{64}$/);
    // A Host-supplied CID is a cross-check only: another configuration's
    // CID (for example one read before the file changed) fails installation.
    assert.equal(createAuthorizationGate({runtime, configuration,
      configurationCid: admitted.configurationCid,
      context: FIXTURE_CONTEXT}).configurationCid, admitted.configurationCid);
    assert.throws(() => createAuthorizationGate({runtime, configuration,
      configurationCid: `sha256:${'c'.repeat(64)}`,
      context: FIXTURE_CONTEXT}), {code: 'AuthorizationConfigurationCidMismatch'});
    const other = createAuthorizationGate({runtime, context: FIXTURE_CONTEXT,
      configuration: accountConfiguration([accountEntry('deny-all', 'deny')])});
    assert.notEqual(other.configurationCid, admitted.configurationCid);
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
    assert.equal(seen[0].subject.configuration_cid,
      permitting.configurationCid);
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

// Two-phase preparation: the request subject is decided first; only a
// deferred Host answer captures inputs and seals the prepared invocation.
const requestCid = subjectCid;
const preparedCid = `sha256:${'8'.repeat(64)}`;
const preparationDeferral = deferral => {
  let sequence = 0;
  return {...deferral, describe(view) {
    sequence += 1;
    const created = Date.now();
    return {
      priorStatus: undefined,
      declaredResults: ['result'],
      body: {
        checkpoint_id: `prepare-${sequence}-preparation`,
        continuation_state_cid: `sha256:${'2'.repeat(64)}`,
        subject: {kind: 'prepare_attempt', prepare_attempt_id: `prepare-${sequence}`,
          continuation: 'start_run'},
        review_projection_cid: `sha256:${'4'.repeat(64)}`,
        human_summary: `${view.boundary} ${view.tuple.connection}`,
        created_at: new Date(created).toISOString(),
        expires_at: new Date(created + 86_400_000).toISOString(),
      },
    };
  }};
};

test('preparation decides the request before sealing; only defer captures',
  async t => {
    const root = await workspace(t);
    const deferral = preparationDeferral(await sqliteDeferral(root));
    t.after(() => deferral.journal.close());
    const captures = [];
    const seal = async view => {
      captures.push(view);
      return preparedCid;
    };
    // Deny, no-match, allow, immediate permit, immediate reject, failure and
    // an unsupported defer never call the sealer: nothing is read or captured.
    const cases = [
      [[accountEntry('deny-warehouse', 'deny', {connection: 'warehouse'})], {},
        'deny'],
      [[accountEntry('other', 'allow', {connection: 'crm'})], {}, 'deny'],
      [[accountEntry('allow-warehouse', 'allow', {connection: 'warehouse'})], {},
        'dispatch'],
      [delegateEntries, {decide: permitWith(), answeringAuthorities: ['reviewer']},
        'dispatch'],
      [delegateEntries, {decide: view => ({decision: 'reject', subject: view.subject,
        authority: 'reviewer'}), answeringAuthorities: ['reviewer']}, 'deny'],
      [delegateEntries, {decide: () => ({decision: 'unavailable'}),
        answeringAuthorities: ['reviewer']}, 'failure'],
      [delegateEntries, {decide: view => ({decision: 'defer', subject: view.subject}),
        answeringAuthorities: ['reviewer']}, 'unsupported'],
    ];
    for (const [entries, options, action] of cases) {
      const gate = await fixtureAuthorization(entries, options);
      const decision = await gate.authorize('preparation', scope,
        {subjectCid: requestCid, sealDeferredSubject: seal});
      assert.equal(decision.action, action);
    }
    assert.equal(captures.length, 0);
    assert.equal(deferral.journal.listPending().length, 0);

    // Defer: the inputs are captured, then the run-scope Checkpoint requires
    // the prepared invocation while the decision subject binds the request.
    const gate = await fixtureAuthorization(delegateEntries, {deferral});
    const waiting = await gate.authorize('preparation', scope,
      {subjectCid: requestCid, sealDeferredSubject: seal});
    assert.equal(waiting.action, 'waiting');
    assert.equal(captures.length, 1);
    assert.equal(captures[0].subject.subject_cid, requestCid);
    assert.equal(waiting.subjectCid, requestCid);
    assert.equal(waiting.checkpoint.requiredArtifactCid, preparedCid);
    const checkpoint = deferral.journal.inspect(waiting.checkpoint.checkpointCid);
    assert.equal(checkpoint.kind, 'run_scope');
    assert.deepEqual({...checkpoint.requiredArtifact},
      {type: 'prepared_invocation', cid: preparedCid});
    assert.equal(checkpoint.decisionSubjectCid,
      await decisionSubjectCid(captures[0].subject));
    assert.equal(checkpoint.decisionSubjectCid,
      waiting.checkpoint.decisionSubjectCid);
    // The approval evidence binds the prepared invocation, not the request.
    const resolution = await deferral.answer(checkpoint.checkpointCid, 'approved');
    assert.equal(resolution.decision, 'approved');
    const verified = JSON.parse(resolution.verifiedResolutionWire);
    assert.equal(verified.resolution.required_artifact_cid, preparedCid);
    assert.equal(verified.approval_evidence.compatibility_approval
      .prepared_invocation_cid, preparedCid);
  });

test('a sealer or describe naming another artifact fails and persists nothing',
  async t => {
    const root = await workspace(t);
    const deferral = preparationDeferral(await sqliteDeferral(root));
    t.after(() => deferral.journal.close());
    const gate = await fixtureAuthorization(delegateEntries, {deferral});
    for (const [seal, detail] of [
      [() => { throw new Error('InputUnreadable'); }, 'SubjectArtifactNotSealed'],
      [async () => 'sha256:short', 'InvalidSubjectArtifact'],
      [async () => undefined, 'InvalidSubjectArtifact'],
    ]) {
      const failed = await gate.authorize('preparation', scope,
        {subjectCid: requestCid, sealDeferredSubject: seal});
      assert.equal(failed.action, 'failure');
      assert.equal(failed.reason, 'adapter_error');
      assert.equal(failed.detail, detail);
    }
    // `describe` must name the sealed prepared invocation or nothing.
    for (const other of [requestCid, `sha256:${'6'.repeat(64)}`]) {
      const substituting = await fixtureAuthorization(delegateEntries, {
        deferral: {...deferral, describe(view) {
          assert.equal(view.requiredArtifactCid, preparedCid);
          const described = deferral.describe(view);
          return {...described, body: {...described.body,
            required_artifact: {artifact_cid: other}}};
        }},
      });
      const failed = await substituting.authorize('preparation', scope,
        {subjectCid: requestCid, sealDeferredSubject: async () => preparedCid});
      assert.equal(failed.action, 'failure');
      assert.equal(failed.detail, 'SubjectArtifactMismatch');
    }
    assert.equal(deferral.journal.listPending().length, 0);
    assert.equal(gate.counters().checkpointsPersisted, 0);
    await assert.rejects(gate.authorize('preparation', scope,
      {subjectCid: requestCid, sealDeferredSubject: preparedCid}),
    {code: 'InvalidAuthorizationSealer'});
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
    assert.equal(decision.admission.claimant, 'owner-a');
    assert.equal(decision.admission.generation, 1);
    // Resumption asks no new Host decision.
    assert.equal(calls(), 1);
    assert.equal(gate.counters().resumedDecisions, 1);
    // A resume without a claimed intent is not a committed approval.
    const unclaimed = await gate.resume('acquisition', scope,
      {subjectCid, resumption: {claim: {action: 'busy'}, resolution}});
    assert.equal(unclaimed.action, 'failure');
    assert.equal(unclaimed.detail, 'ResumeNotClaimed');
  });

test('resume of a sealed two-phase subject requires that sealed artifact',
  async t => {
    const root = await workspace(t);
    const deferral = await sqliteDeferral(root);
    t.after(() => deferral.journal.close());
    const gate = await fixtureAuthorization(delegateEntries, {deferral});
    const waiting = await gate.authorize('acquisition', scope,
      {subjectCid, sealDeferredSubject: async () => preparedCid});
    assert.equal(waiting.action, 'waiting');
    const resolution = await deferral.answer(
      waiting.checkpoint.checkpointCid, 'approved');
    const resumption = {claim: claimResume(deferral, waiting), resolution};
    // The request subject alone, or another sealed artifact, is not it; nor
    // is the sealed artifact used as the decision subject.
    for (const options of [
      {subjectCid},
      {subjectCid, sealedSubjectCid: `sha256:${'6'.repeat(64)}`},
      {subjectCid: preparedCid, sealedSubjectCid: preparedCid},
    ]) {
      const other = await gate.resume('acquisition', scope,
        {...options, resumption});
      assert.equal(other.action, 'failure');
      assert.equal(other.detail, 'ResolutionSubjectMismatch');
    }
    const decision = await gate.resume('acquisition', scope,
      {subjectCid, sealedSubjectCid: preparedCid, resumption});
    assert.equal(decision.action, 'dispatch');
    assert.equal(decision.basis, 'resumed');
    assert.equal(decision.subjectCid, subjectCid);
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
    assert.equal(forged.detail, 'ResumeNotClaimed');
    // A rejected Checkpoint has no resume intent to claim.
    assert.equal(rejected.deferral.journal.currentResume(
      rejected.waiting.checkpoint.checkpointCid), undefined);

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

// Resumed-dispatch admission (review D-R1..D-R3). Every case runs the real
// gate, the compiled MoonBit runtimes and the real SQLite journal under a
// controlled Host trusted clock.
const T0 = Date.parse('2026-09-25T10:00:00.000Z');
const DAY = 86_400_000;
const otherSubjectCid = `sha256:${'6'.repeat(64)}`;
const effectScope = Object.freeze({
  connection: 'tickets', resource: 'queue', operation: 'effect',
});
const effectEntries = [accountEntry('review-tickets', 'delegate', {
  connection: 'tickets',
})];

async function clockedGate(t, {
  requiredClaims = [], boundary = 'acquisition', target = scope,
  entries = delegateEntries, hooks, describe,
} = {}) {
  const root = await workspace(t);
  const clock = {ms: T0};
  const durable = await sqliteDeferral(root, {now: () => clock.ms, hooks});
  t.after(() => durable.journal.close());
  const deferral = describe === undefined ? durable
    : {...durable, describe: view => describe(durable.describe(view))};
  const gate = await fixtureAuthorization(entries, {deferral, requiredClaims});
  const waiting = await gate.authorize(boundary, target, {subjectCid});
  assert.equal(waiting.action, 'waiting');
  const checkpointCid = waiting.checkpoint.checkpointCid;
  return {
    clock, deferral: durable, gate, waiting, checkpointCid,
    claim: (claimant, leaseMs = 60_000) => durable.journal.claimResume(
      waiting.checkpoint.runId,
      {claimant, leaseMs, binding: durable.binding}),
    resume: (resumption, options = {}) => (options.gate ?? gate).resume(
      options.boundary ?? boundary, options.target ?? target,
      {subjectCid, resumption}),
  };
}

test('review probe: stale, fabricated, expired and unapproved resumes refuse',
  async t => {
    // superseded_claim
    const superseded = await clockedGate(t);
    await superseded.deferral.answer(superseded.checkpointCid, 'approved');
    const old = superseded.claim('old', 1000);
    superseded.clock.ms += 2000;
    const newer = superseded.claim('new');
    assert.equal(old.claim.generation, 1);
    assert.equal(newer.claim.generation, 2);
    assert.throws(() => superseded.deferral.journal.renewResume(old.claim,
      60_000), {code: 'ResumeClaimStale'});
    const stale = await superseded.resume({claim: old});
    assert.equal(stale.action, 'failure');
    assert.equal(stale.detail, 'ResumeClaimStale');
    // approval_expired_before_resume
    const expired = await clockedGate(t);
    await expired.deferral.answer(expired.checkpointCid, 'approved');
    expired.clock.ms += DAY + 1;
    const late = expired.claim('late');
    assert.equal(late.action, 'claimed');
    const lapsed = await expired.resume({claim: late});
    assert.equal(lapsed.action, 'failure');
    assert.equal(lapsed.detail, 'ApprovalExpired');
    // never_claimed
    const fabricated = await clockedGate(t);
    const resolution = await fabricated.deferral.answer(
      fabricated.checkpointCid, 'approved');
    const never = await fabricated.resume({claim: {action: 'claimed',
      checkpointCid: fabricated.checkpointCid,
      claim: {runId: fabricated.waiting.checkpoint.runId}}, resolution});
    assert.equal(never.action, 'failure');
    assert.equal(never.detail, 'ResumeNotClaimed');
    // unapproved_claim: a Host-required claim no deferred evidence profile
    // can establish is refused when the decision defers, before any
    // Checkpoint exists, so no reviewer is asked to approve it.
    const root = await workspace(t);
    const durable = await sqliteDeferral(root, {now: () => T0});
    t.after(() => durable.journal.close());
    const unapproved = await fixtureAuthorization(delegateEntries,
      {deferral: durable, requiredClaims: ['host-required-risk']});
    const risk = await unapproved.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(risk.action, 'failure');
    assert.equal(risk.detail, 'RequiredClaimUnrepresentable');
    assert.equal(unapproved.counters().checkpointsPersisted, 0);
    assert.equal(durable.journal.listPending().length, 0);
    for (const gate of [superseded, expired, fabricated]) {
      assert.equal(gate.gate.counters().resumedDecisions, 0);
      assert.equal(gate.gate.counters().protectedDispatches, 0);
    }
    assert.equal(unapproved.counters().protectedDispatches, 0);
  });

test('an unrepresentable required claim is refused at defer and at resume',
  async t => {
    // Defer: the Effect Set profile cannot establish a run-scope claim, and
    // no profile establishes an arbitrary Host claim. Nothing is persisted.
    for (const [boundary, target, entries, claims] of [
      ['acquisition', scope, delegateEntries, ['host-required-risk']],
      ['acquisition', scope, delegateEntries, ['effect_scope_approved']],
      ['effect_commit', effectScope, effectEntries,
        ['invocation_scope_approved']],
    ]) {
      const root = await workspace(t);
      const durable = await sqliteDeferral(root, {now: () => T0});
      t.after(() => durable.journal.close());
      const gate = await fixtureAuthorization(entries,
        {deferral: durable, requiredClaims: claims});
      const refused = await gate.authorize(boundary, target, {subjectCid});
      assert.equal(refused.action, 'failure', claims.join());
      assert.equal(refused.detail, 'RequiredClaimUnrepresentable');
      assert.equal(gate.counters().checkpointsPersisted, 0);
    }
    // Resume keeps the check as defense: a Checkpoint whose bound requested
    // claims no profile can establish (persisted outside this gate) still
    // admits nothing.
    const root = await workspace(t);
    const clock = {ms: T0};
    const durable = await sqliteDeferral(root, {now: () => clock.ms});
    t.after(() => durable.journal.close());
    const injected = {...durable, journal: Object.freeze({
      ...Object.fromEntries(Object.entries(durable.journal)),
      persistCheckpoint: args => durable.journal.persistCheckpoint({...args,
        requestedClaims: ['host-required-risk']}),
    })};
    const deferring = await fixtureAuthorization(delegateEntries,
      {deferral: injected});
    const waiting = await deferring.authorize('acquisition', scope,
      {subjectCid});
    assert.equal(waiting.action, 'waiting');
    assert.deepEqual(durable.journal.inspect(waiting.checkpoint.checkpointCid)
      .requestedClaims, ['host-required-risk']);
    await durable.answer(waiting.checkpoint.checkpointCid, 'approved');
    const resuming = await fixtureAuthorization(delegateEntries,
      {deferral: durable, requiredClaims: ['host-required-risk']});
    const claim = durable.journal.claimResume(waiting.checkpoint.runId,
      {claimant: 'owner', leaseMs: 60_000, binding: durable.binding});
    const risk = await resuming.resume('acquisition', scope,
      {subjectCid, resumption: {claim}});
    assert.equal(risk.action, 'failure');
    assert.equal(risk.detail, 'RequiredClaimUnrepresentable');
    assert.equal(resuming.counters().protectedDispatches, 0);
  });

test('resume admits only the live claim of the current resume intent',
  async t => {
    const x = await clockedGate(t);
    const committed = await x.deferral.answer(x.checkpointCid, 'approved');
    const journal = x.deferral.journal;
    const pending = journal.currentResume(x.checkpointCid);
    assert.equal(pending.state, 'pending');
    // A guessed identity of the pending intent is not a claim.
    const guessed = await x.resume({claim: {checkpointCid: x.checkpointCid,
      claim: {intentId: pending.intentId, claimant: 'owner-a',
        generation: 1}}});
    assert.equal(guessed.detail, 'ResumeClaimStale');
    // An expired lease, and a superseded generation, are stale.
    const first = x.claim('owner-a', 1000);
    x.clock.ms += 1000;
    assert.equal((await x.resume({claim: first})).detail, 'ResumeClaimStale');
    const second = x.claim('owner-b');
    assert.equal((await x.resume({claim: first})).detail, 'ResumeClaimStale');
    // Another Checkpoint's intent is not this Checkpoint's intent.
    const other = await x.gate.authorize('acquisition', scope,
      {subjectCid: otherSubjectCid});
    await x.deferral.answer(other.checkpoint.checkpointCid, 'approved');
    const foreign = journal.claimResume(other.checkpoint.runId,
      {claimant: 'owner-c', leaseMs: 60_000, binding: x.deferral.binding});
    assert.equal((await x.resume({claim: {...foreign,
      checkpointCid: x.checkpointCid}})).detail, 'ResumeIntentMismatch');
    assert.equal((await x.resume({claim: foreign})).detail,
      'ResolutionSubjectMismatch');
    // A caller-supplied Resolution or verified wrapper is never read.
    const decision = await x.resume({claim: second, resolution: {
      decision: 'approved', resolutionCid: `sha256:${'f'.repeat(64)}`,
      verifiedResolutionWire: '{"forged":true}'}});
    assert.equal(decision.action, 'dispatch');
    assert.equal(decision.resolutionCid, committed.resolutionCid);
    assert.deepEqual(decision.claims, []);
    const {admission} = decision;
    assert.equal(admission.runId, x.waiting.checkpoint.runId);
    assert.equal(admission.checkpointCid, x.checkpointCid);
    assert.equal(admission.intentId, pending.intentId);
    assert.equal(admission.resolutionCid, committed.resolutionCid);
    assert.equal(admission.claimant, 'owner-b');
    assert.equal(admission.generation, 2);
    assert.equal(admission.leaseExpiresMs, second.claim.leaseExpiresMs);
    // The observation is not a reusable token: one start per generation.
    assert.equal(admission.enter().generation, 2);
    assert.throws(() => admission.enter(), {code: 'ResumeAdmissionConsumed'});
    const again = await x.resume({claim: second});
    assert.equal(again.action, 'dispatch');
    assert.throws(() => again.admission.enter(),
      {code: 'ResumeAdmissionConsumed'});
  });

test('a handoff between admission and send admits no start', async t => {
  const x = await clockedGate(t);
  await x.deferral.answer(x.checkpointCid, 'approved');
  const first = x.claim('owner-a', 1000);
  const decision = await x.resume({claim: first});
  assert.equal(decision.action, 'dispatch');
  // The lease lapses after admission and before the send.
  x.clock.ms += 1000;
  assert.throws(() => decision.admission.enter(), {code: 'ResumeClaimStale'});
  // A new claimant takes over; the old admission stays refused.
  const second = x.claim('owner-b', 1000);
  const next = await x.resume({claim: second});
  x.clock.ms += 1000;
  const third = x.claim('owner-c');
  assert.throws(() => next.admission.enter(), {code: 'ResumeClaimStale'});
  const current = await x.resume({claim: third});
  assert.equal(current.admission.enter().claimant, 'owner-c');
  const view = x.deferral.journal.currentResume(x.checkpointCid);
  assert.equal(view.claimant, 'owner-c');
  assert.equal(view.generation, 3);
});

test('resumed claims are only those the committed evidence established',
  async t => {
    // Default: no Host-required claim, none supplied.
    const none = await clockedGate(t);
    await none.deferral.answer(none.checkpointCid, 'approved');
    assert.deepEqual((await none.resume({claim: none.claim('o')})).claims, []);
    // Exact satisfied claim of the run-scope style approval.
    const exact = await clockedGate(t,
      {requiredClaims: ['invocation_scope_approved']});
    assert.deepEqual(exact.deferral.journal.inspect(exact.checkpointCid)
      .requestedClaims, ['invocation_scope_approved']);
    await exact.deferral.answer(exact.checkpointCid, 'approved');
    const satisfied = await exact.resume({claim: exact.claim('o')});
    assert.equal(satisfied.action, 'dispatch');
    assert.deepEqual(satisfied.claims, ['invocation_scope_approved']);
    // Requirements changed while the Run waited: the bound requirement is
    // the one approved against, so neither direction dispatches.
    for (const [before, after] of [
      [[], ['invocation_scope_approved']],
      [['invocation_scope_approved'], []],
    ]) {
      const changed = await clockedGate(t, {requiredClaims: before});
      await changed.deferral.answer(changed.checkpointCid, 'approved');
      const later = await fixtureAuthorization(delegateEntries, {
        deferral: changed.deferral, requiredClaims: after,
      });
      const refused = await changed.resume({claim: changed.claim('o')},
        {gate: later});
      assert.equal(refused.action, 'failure');
      assert.equal(refused.detail, 'RequiredClaimsChanged');
    }
  });

test('Effect resume claims: missing, different, exact and optional partial',
  async t => {
    const effect = options => clockedGate(t, {boundary: 'effect_commit',
      target: effectScope, entries: effectEntries, ...options});
    // The Host requires the optional partial-application claim: the
    // reviewer is asked for it, and an attestation without it is not
    // committed at all.
    const partial = await effect({requiredClaims:
      ['effect_scope_approved', 'partial_application_accepted']});
    const checkpoint = partial.deferral.journal.inspect(partial.checkpointCid);
    assert.equal(checkpoint.kind, 'effect_set');
    assert.deepEqual(checkpoint.requirements,
      ['effect_scope_approved', 'partial_application_accepted']);
    await assert.rejects(partial.deferral.answer(partial.checkpointCid,
      'approved', {claims: ['effect_scope_approved']}),
    {code: 'InvalidResolution'});
    assert.equal(partial.deferral.journal.currentResume(
      partial.checkpointCid), undefined);
    await partial.deferral.answer(partial.checkpointCid, 'approved');
    const both = await partial.resume({claim: partial.claim('o')});
    assert.equal(both.action, 'dispatch');
    assert.deepEqual(both.claims,
      ['effect_scope_approved', 'partial_application_accepted']);
    assert.equal(both.admission.approvalExpiresAt, null);
    // Without the optional policy the attested extra claim is not supplied.
    const plain = await effect({requiredClaims: ['effect_scope_approved']});
    assert.deepEqual(plain.deferral.journal.inspect(plain.checkpointCid)
      .requirements, ['effect_scope_approved']);
    await plain.deferral.answer(plain.checkpointCid, 'approved',
      {claims: ['effect_scope_approved', 'partial_application_accepted']});
    assert.deepEqual((await plain.resume({claim: plain.claim('o')})).claims,
      ['effect_scope_approved']);
    // A Host description that does not ask the reviewer for a required
    // claim commits an attestation without it: it is missing at resume.
    const missing = await effect({
      requiredClaims: ['partial_application_accepted'],
      describe: described => ({...described, body: {...described.body,
        requirements: ['effect_scope_approved']}}),
    });
    await missing.deferral.answer(missing.checkpointCid, 'approved');
    const absent = await missing.resume({claim: missing.claim('o')});
    assert.equal(absent.action, 'failure');
    assert.equal(absent.detail, 'RequiredClaimNotEstablished');
    // A claim of another evidence profile is different, not satisfied: it
    // is refused when the Effect Set decision defers (see the defer test).
  });

test('immediate answers must supply exactly the Host-required claims',
  async () => {
    for (const [claims, action] of [
      [[], 'failure'],
      [['other-claim'], 'failure'],
      [['host-required-risk', 'other-claim'], 'failure'],
      [['host-required-risk'], 'dispatch'],
    ]) {
      const gate = await fixtureAuthorization(delegateEntries, {
        decide: permitWith({claims}),
        answeringAuthorities: ['reviewer'],
        requiredClaims: ['host-required-risk'],
      });
      const decision = await gate.authorize('acquisition', scope,
        {subjectCid});
      assert.equal(decision.action, action, JSON.stringify(claims));
      if (action === 'dispatch') {
        assert.deepEqual(decision.claims, ['host-required-risk']);
      } else {
        assert.equal(decision.reason, 'malformed_answer');
      }
    }
    const effect = await fixtureAuthorization(effectEntries, {
      decide: permitWith({claims: ['partial_application_accepted']}),
      answeringAuthorities: ['reviewer'],
      requiredClaims: ['partial_application_accepted'],
    });
    const committed = await effect.authorize('effect_commit', effectScope,
      {subjectCid});
    assert.equal(committed.action, 'dispatch');
    assert.deepEqual(committed.claims, ['partial_application_accepted']);
  });

test('an expired permission authorizes no new resumed work', async t => {
  // Exact expiry instant, with a live lease.
  const exact = await clockedGate(t);
  await exact.deferral.answer(exact.checkpointCid, 'approved');
  const expiresAt = Date.parse(exact.deferral.journal.inspect(
    exact.checkpointCid).expiresAt);
  exact.clock.ms = expiresAt - 10_000;
  const held = exact.claim('owner');
  exact.clock.ms = expiresAt - 1;
  assert.equal((await exact.resume({claim: held})).action, 'dispatch');
  exact.clock.ms = expiresAt;
  assert.equal((await exact.resume({claim: held})).detail, 'ApprovalExpired');

  // Expiry after the answer, before the claim.
  const beforeClaim = await clockedGate(t);
  await beforeClaim.deferral.answer(beforeClaim.checkpointCid, 'approved',
    {approvalExpiresAt: new Date(T0 + 3_600_000).toISOString()});
  beforeClaim.clock.ms = T0 + 2 * 3_600_000;
  const claimed = beforeClaim.claim('owner');
  assert.equal(claimed.action, 'claimed');
  assert.equal((await beforeClaim.resume({claim: claimed})).detail,
    'ApprovalExpired');
  // The historical approval and the resuming Run are kept.
  assert.equal(beforeClaim.deferral.journal.resolutionOf(
    beforeClaim.checkpointCid).decision, 'approved');
  assert.equal(beforeClaim.deferral.journal.getRunState(
    beforeClaim.waiting.checkpoint.runId).status, 'resuming');

  // Expiry after the claim and admission, before the send.
  const beforeSend = await clockedGate(t);
  await beforeSend.deferral.answer(beforeSend.checkpointCid, 'approved',
    {approvalExpiresAt: new Date(T0 + 3_600_000).toISOString()});
  beforeSend.clock.ms = T0 + 3_600_000 - 5_000;
  const decision = await beforeSend.resume({claim: beforeSend.claim('owner')});
  assert.equal(decision.action, 'dispatch');
  beforeSend.clock.ms += 5_000;
  assert.throws(() => decision.admission.enter(), {code: 'ApprovalExpired'});
});

test('slow Host authentication cannot commit past the trusted deadline',
  async t => {
    let delay = 0;
    const slow = await clockedGate(t, {hooks: {
      authorize: async () => {
        await new Promise(resolve => setImmediate(resolve));
        slow.clock.ms += delay;
      },
      attest: async () => {
        await new Promise(resolve => setImmediate(resolve));
        slow.clock.ms += delay;
      },
    }});
    const deadline = Date.parse(slow.deferral.journal.inspect(
      slow.checkpointCid).expiresAt);
    // The approval's own permission lapses while the Host authenticates: it
    // is not committed and the Checkpoint keeps waiting.
    slow.clock.ms = T0 + 3_600_000;
    delay = 3_600_000;
    await assert.rejects(slow.deferral.answer(slow.checkpointCid, 'approved',
      {approvalExpiresAt: new Date(T0 + 2 * 3_600_000 + 1).toISOString()}),
    {code: 'ApprovalExpired'});
    assert.equal(slow.deferral.journal.inspect(slow.checkpointCid).closure,
      'open');
    // The Checkpoint deadline passes during authentication: no commit, no
    // resume intent, and the waiting Run is closed without dispatch.
    slow.clock.ms = deadline - 1_000;
    delay = 2_000;
    await assert.rejects(slow.deferral.answer(slow.checkpointCid,
      'approved'), {code: 'CheckpointExpired'});
    assert.equal(slow.deferral.journal.inspect(slow.checkpointCid).closure,
      'expired');
    assert.equal(slow.deferral.journal.currentResume(slow.checkpointCid),
      undefined);
    assert.throws(() => slow.claim('owner'), {code: 'ResumeIntentNotFound'});
    assert.equal(slow.gate.counters().resumedDecisions, 0);
  });
