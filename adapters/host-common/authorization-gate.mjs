// Host-installed execution-authorization gate for protected boundaries.
//
// Account interpretation, delegated-request binding and Host-answer admission
// are owned by MoonBit `execution_authorization` and reached through the
// runtime's `executionAuthorization*` exports. This adapter owns only trusted
// Host context, the optional embedded decision function, the optional durable
// Checkpoint journal, an exact-scope decision cache and cheap counters. It
// performs no network I/O and never reads Program input: the principal and
// authorization context come from the Host that installs it. The only digest
// it computes is the decision-subject binding of a deferred decision (below),
// over the ten-field decision subject projection, never over data.

export const AUTHORIZATION_BOUNDARIES = Object.freeze([
  'preparation', 'acquisition', 'activation', 'transfer', 'effect_commit',
]);

// Default Checkpoint kind per boundary. A Host `describe` may choose another
// kind allowed by the Checkpoint subject/phase table.
const CHECKPOINT_KIND = Object.freeze({
  preparation: 'run_scope',
  acquisition: 'read_access',
  activation: 'cost_scope',
  transfer: 'data_egress',
  effect_commit: 'effect_set',
});
const ARTIFACT_TYPE = Object.freeze({
  run_scope: 'prepared_invocation',
  read_access: 'read_scope',
  data_egress: 'egress_scope',
  cost_scope: 'budget_scope',
  effect_set: 'effect_set_preview',
});
const SUBJECT_FIELDS = Object.freeze([
  'account_id', 'configuration_cid', 'entry_id', 'principal', 'connection',
  'resource', 'operation', 'boundary', 'subject_cid', 'context_cid',
]);
const FAILURE_REASONS = new Set(['timeout', 'unavailable', 'malformed_answer']);
const COUNTERS = Object.freeze([
  'evaluations', 'hostDecisionCalls', 'checkpointsPersisted',
  'protectedDispatches', 'deniedBeforeDispatch', 'decisionFailures',
  'unsupportedDefers', 'hostRejections', 'reusedDecisions',
  'coveredOperations', 'resumedDecisions',
]);

const ERROR_CODES = Object.freeze({
  deny: 'ExecutionAuthorizationDenied',
  failure: 'ExecutionAuthorizationDecisionFailed',
  waiting: 'ExecutionAuthorizationWaiting',
  unsupported: 'ExecutionAuthorizationDeferralUnsupported',
});

// Runtime error codes (phase `admission`) pinned by Execution, Account
// authorization routing. A persisted wait has none: it is not an error end.
const ACCOUNT_DENY_CODES = Object.freeze({
  explicit: 'ACTQL_E_ACCOUNT_DENIED',
  no_match: 'ACTQL_E_ACCOUNT_NO_MATCH',
  configuration_missing: 'ACTQL_E_ACCOUNT_CONFIG_INVALID',
});

export function authorizationRuntimeCode(decision) {
  switch (decision?.action) {
    case 'deny':
      return decision.basis === 'rejected_by_host'
        ? 'ACTQL_E_DELEGATION_REJECTED'
        : ACCOUNT_DENY_CODES[decision.reason] ?? 'ACTQL_E_ACCOUNT_DENIED';
    case 'failure':
    case 'unsupported':
      return 'ACTQL_E_DELEGATION_UNAVAILABLE';
    default:
      return undefined;
  }
}

export class ExecutionAuthorizationError extends Error {
  constructor(decision) {
    const code = ERROR_CODES[decision?.action] ??
      'ExecutionAuthorizationInvalidDecision';
    super(code);
    this.code = code;
    this.runtimeCode = authorizationRuntimeCode(decision);
    this.authorization = decision;
  }
}

const fail = code => {
  throw Object.assign(new TypeError(code), {code});
};
const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 512;
const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/.test(value);
const names = value => Array.isArray(value) && value.every(text);

function checkedScope(scope) {
  if (scope === null || typeof scope !== 'object' || !text(scope.connection) ||
      !text(scope.resource) || !text(scope.operation)) {
    fail('InvalidAuthorizationScope');
  }
  return scope;
}

function frozenDecision(fields) {
  return Object.freeze(fields);
}

// Decision-subject binding of a deferred decision: SHA-256 over the canonical
// JSON of the ten-field decision subject projection (all members are strings;
// keys sorted; ECMAScript string serialization is the canonical string form).
// It is not the Checkpoint's required artifact: the required artifact is the
// sealed review subject itself (the `subjectCid` of the boundary, for example
// the Effect Set Preview or the prepared invocation), so approval evidence
// binds the real artifact. The journal stores this binding next to the
// Checkpoint, and resume admits the approval only for the exact account
// entry, principal, connection, resource, operation, boundary, subject and
// context it names.
async function decisionSubjectCid(subject) {
  const body = `{${[...SUBJECT_FIELDS].sort().map(name =>
    `${JSON.stringify(name)}:${JSON.stringify(subject[name])}`).join(',')}}`;
  const digest = await globalThis.crypto.subtle.digest('SHA-256',
    new TextEncoder().encode(body));
  return `sha256:${Array.from(new Uint8Array(digest),
    byte => byte.toString(16).padStart(2, '0')).join('')}`;
}

function subjectFields(subject) {
  if (subject === null || typeof subject !== 'object') return undefined;
  const fields = SUBJECT_FIELDS.map(name => subject[name]);
  return fields.every(value => typeof value === 'string') ? fields : undefined;
}

// Map one decision-function result to the adapter vocabulary. Anything that
// is not exactly permit/reject/defer/unavailable is a malformed answer.
function answerOf(value) {
  if (value === null || typeof value !== 'object') {
    return {kind: 'failure', failure: 'malformed_answer'};
  }
  const decision = value.decision;
  if (decision === 'unavailable') return {kind: 'failure', failure: 'unavailable'};
  if (decision !== 'permit' && decision !== 'reject' && decision !== 'defer') {
    return {kind: 'failure', failure: 'malformed_answer'};
  }
  const subject = subjectFields(value.subject);
  if (subject === undefined) return {kind: 'failure', failure: 'malformed_answer'};
  if (decision === 'defer') return {kind: 'defer', subject};
  if (!text(value.authority)) return {kind: 'failure', failure: 'malformed_answer'};
  const claims = value.claims ?? [];
  if (decision === 'permit' && !names(claims)) {
    return {kind: 'failure', failure: 'malformed_answer'};
  }
  return {
    kind: decision,
    subject,
    authority: value.authority,
    claims: decision === 'permit' ? [...claims] : [],
    // Optional bindings an immediate answer states (for example from its
    // verified immediate Resolution); checked against the bound request.
    subjectArtifactCid: value.subjectArtifactCid,
    decisionSubjectCid: value.decisionSubjectCid,
  };
}

// Immediate path: a permit or reject that states the artifact or decision
// subject it answers must state exactly the bound ones; another artifact or
// subject is a malformed answer, never a permit or a rejection.
function immediateBinding(answer, view) {
  if (answer.kind !== 'permit' && answer.kind !== 'reject') return answer;
  if ((answer.subjectArtifactCid !== undefined &&
       answer.subjectArtifactCid !== view.subjectArtifactCid) ||
      (answer.decisionSubjectCid !== undefined &&
       answer.decisionSubjectCid !== view.decisionSubjectCid)) {
    return {kind: 'failure', failure: 'malformed_answer'};
  }
  return answer;
}

function requireRuntime(runtime) {
  for (const name of [
    'executionAuthorizationAdmit', 'executionAuthorizationMissing',
    'executionAuthorizationAccountJson', 'executionAuthorizationEvaluate',
    'executionAuthorizationEvaluationJson',
    'executionAuthorizationEvaluationAction', 'executionAuthorizationPrepare',
    'executionAuthorizationRequestJson', 'executionAuthorizationAnswer',
    'executionAuthorizationDecisionJson',
  ]) {
    if (typeof runtime?.[name] !== 'function') {
      fail('InvalidExecutionAuthorizationRuntime');
    }
  }
  return runtime;
}

function checkedDeferral(deferral) {
  if (deferral === undefined) return undefined;
  if (deferral === null || typeof deferral !== 'object' ||
      typeof deferral.describe !== 'function') {
    fail('InvalidAuthorizationDeferral');
  }
  const journal = deferral.journal;
  // A deferred decision needs both durable persistence and a later answer
  // path (Resolution submission to reviewer authorities). Without either,
  // defer stops before the protected operation as unsupported.
  const durable = journal !== null && typeof journal === 'object' &&
    typeof journal.persistCheckpoint === 'function' &&
    typeof journal.submitResolution === 'function' &&
    Array.isArray(deferral.authorities) && deferral.authorities.length > 0 &&
    deferral.binding !== null && typeof deferral.binding === 'object';
  return durable ? Object.freeze({...deferral}) : undefined;
}

// Create one gate from Host installation. `configuration` is the account
// configuration wire text; `undefined`/`null` is an explicit Missing state
// (every protected boundary denies with configuration_missing). A rejected
// configuration fails installation: it grants nothing and is not Missing.
export function createAuthorizationGate({
  runtime,
  configuration,
  configurationCid,
  context,
  decide,
  answeringAuthorities = [],
  requiredClaims = [],
  decisionTimeoutMs = 30_000,
  deferral,
  protectedSites = [],
} = {}) {
  if (context === null || typeof context !== 'object' ||
      !text(context.principal) || !cid(context.contextCid)) {
    fail('InvalidAuthorizationContext');
  }
  if (decide !== undefined && typeof decide !== 'function') {
    fail('InvalidAuthorizationDecisionFunction');
  }
  if (!names(answeringAuthorities) || !names(requiredClaims) ||
      (decide !== undefined && answeringAuthorities.length === 0)) {
    fail('InvalidAuthorizationAuthorities');
  }
  if (!Number.isSafeInteger(decisionTimeoutMs) || decisionTimeoutMs < 1) {
    fail('InvalidAuthorizationTimeout');
  }
  if (!Array.isArray(protectedSites) || !protectedSites.every(text)) {
    fail('InvalidProtectedSites');
  }
  const missing = configuration === undefined || configuration === null;
  if (!missing && (typeof configuration !== 'string' || !cid(configurationCid))) {
    fail('InvalidAuthorizationConfiguration');
  }
  const moon = missing && runtime === undefined ? undefined
    : requireRuntime(runtime);
  const account = moon === undefined ? undefined
    : missing ? moon.executionAuthorizationMissing()
      : moon.executionAuthorizationAdmit(configuration);
  const state = account === undefined ? {state: 'missing'}
    : JSON.parse(moon.executionAuthorizationAccountJson(account));
  if (state.state === 'rejected') {
    throw Object.assign(new Error('ExecutionAuthorizationConfigurationRejected'), {
      code: 'ExecutionAuthorizationConfigurationRejected',
      issue: state.issue,
    });
  }
  const durable = checkedDeferral(deferral);
  // Without a decision function the durable journal's reviewer authorities
  // are the only answering authorities of a deferred subject.
  const answering = decide === undefined && answeringAuthorities.length === 0 &&
    durable !== undefined
    ? durable.authorities.map(authority => authority.reviewerId)
    : answeringAuthorities;
  const core = Object.freeze({
    moon,
    account,
    accountId: state.state === 'admitted' ? state.account_id : undefined,
    configurationCid: missing ? undefined : configurationCid,
    decide,
    answeringAuthorities: Object.freeze([...answering]),
    requiredClaims: Object.freeze([...requiredClaims]),
    decisionTimeoutMs,
    deferral: durable,
    protectedSites: new Set(protectedSites),
    counts: Object.fromEntries(COUNTERS.map(name => [name, 0])),
    // Exact-scope reuse: keyed by the full subject under this configuration.
    cache: new Map(),
  });
  return gateFor(core, Object.freeze({
    principal: context.principal,
    contextCid: context.contextCid,
  }));
}

function gateFor(core, context) {
  const count = (name, delta = 1) => { core.counts[name] += delta; };
  const record = decision => {
    if (decision.action === 'dispatch') count('protectedDispatches');
    else if (decision.action === 'deny') count('deniedBeforeDispatch');
    else if (decision.action === 'failure') count('decisionFailures');
    else if (decision.action === 'unsupported') count('unsupportedDefers');
    return decision;
  };

  async function askHost(view, signal) {
    count('hostDecisionCalls');
    let timer;
    let onAbort;
    const pending = [
      Promise.resolve().then(() => core.decide(view, {signal})).then(
        answerOf,
        error => ({kind: 'failure', failure: 'adapter_error', error}),
      ),
      new Promise(resolve => {
        timer = setTimeout(
          () => resolve({kind: 'failure', failure: 'timeout'}),
          core.decisionTimeoutMs,
        );
      }),
    ];
    if (signal !== undefined) {
      pending.push(new Promise(resolve => {
        onAbort = () => resolve({kind: 'failure', failure: 'unavailable'});
        if (signal.aborted) onAbort();
        else signal.addEventListener('abort', onAbort, {once: true});
      }));
    }
    try {
      return await Promise.race(pending);
    } finally {
      clearTimeout(timer);
      if (onAbort !== undefined) signal.removeEventListener('abort', onAbort);
    }
  }

  async function defer(base, view) {
    const deferral = core.deferral;
    if (deferral === undefined) {
      return frozenDecision({...base, action: 'unsupported',
        reason: 'checkpoint_journal_not_configured'});
    }
    // The sealed review subject is the artifact the Checkpoint requires. A
    // boundary without a valid sealed subject artifact cannot be deferred.
    if (!cid(base.subjectCid)) {
      return frozenDecision({...base, action: 'failure',
        reason: 'adapter_error', detail: 'InvalidSubjectArtifact'});
    }
    let persisted;
    let bindingCid;
    try {
      bindingCid = await decisionSubjectCid(view.subject);
      const described = await deferral.describe(view);
      const supplied = described?.body?.required_artifact?.artifact_cid;
      // `describe` may not substitute another artifact for the subject.
      if (supplied !== undefined && supplied !== base.subjectCid) {
        return frozenDecision({...base, action: 'failure',
          reason: 'adapter_error', detail: 'SubjectArtifactMismatch'});
      }
      const kind = described?.body?.kind ?? CHECKPOINT_KIND[base.boundary];
      const phase = base.boundary === 'effect_commit' ? 'commit' : 'preflight';
      const body = {
        version: 'actql-execution-checkpoint/0.1',
        phase,
        kind,
        requirements: kind === 'effect_set'
          ? ['effect_scope_approved'] : ['invocation_scope_approved'],
        reason_code: 'delegated_decision_deferred',
        ...described.body,
        // The reviewed artifact of an authorization deferral is the sealed
        // subject artifact of the boundary; the gate owns this binding.
        required_artifact: {
          artifact_type: ARTIFACT_TYPE[kind],
          ...described.body?.required_artifact,
          artifact_cid: base.subjectCid,
        },
      };
      // Durable commit happens before any waiting claim is made.
      // A preparation Checkpoint precedes its Run and names no prior Run
      // status; a Host `describe` may bind the current resume context.
      persisted = await deferral.journal.persistCheckpoint({
        body,
        priorStatus: 'priorStatus' in described ? described.priorStatus
          : 'running',
        declaredResults: described.declaredResults,
        authorities: deferral.authorities,
        binding: described.binding ?? deferral.binding,
        decisionSubjectCid: bindingCid,
      });
    } catch (error) {
      return frozenDecision({...base, action: 'failure',
        reason: 'adapter_error', detail: 'CheckpointNotPersisted', error});
    }
    count('checkpointsPersisted');
    return frozenDecision({...base, action: 'waiting', reason: 'deferred',
      checkpoint: Object.freeze({
        checkpointCid: persisted.checkpointCid,
        checkpointId: persisted.checkpointId,
        runId: persisted.runId,
        prepareAttemptId: persisted.prepareAttemptId ?? null,
        runState: persisted.runState,
        preparation: persisted.preparation,
        requiredArtifactCid: base.subjectCid,
        decisionSubjectCid: bindingCid,
      })});
  }

  // Resume check for one committed Resolution. Only the journal's committed
  // rows count: a claimed resume intent (which exists only for an approved
  // Resolution), the resolved Checkpoint carrying that Resolution, and a Run
  // still `resuming`. Returns the Checkpoint and reviewer authority, or a
  // failure detail.
  function committedApproval(resumption) {
    const journal = core.deferral.journal;
    const claimed = resumption?.claim;
    const resolution = resumption?.resolution;
    if (claimed?.action !== 'claimed' || !text(claimed.checkpointCid) ||
        !text(claimed.claim?.runId) || resolution?.decision !== 'approved' ||
        !text(resolution.resolutionCid) ||
        typeof resolution.verifiedResolutionWire !== 'string') {
      return {detail: 'ResumeNotClaimed'};
    }
    if (typeof journal.inspect !== 'function' ||
        typeof journal.getRunState !== 'function') {
      return {detail: 'ResumeJournalUnavailable'};
    }
    const checkpoint = journal.inspect(claimed.checkpointCid);
    if (checkpoint === undefined || checkpoint.closure !== 'resolved' ||
        checkpoint.resolutionCid !== resolution.resolutionCid ||
        checkpoint.runId !== claimed.claim.runId) {
      return {detail: 'ResolutionNotCommitted'};
    }
    if (journal.getRunState(checkpoint.runId)?.status !== 'resuming') {
      return {detail: 'RunNotResuming'};
    }
    let verified;
    try { verified = JSON.parse(resolution.verifiedResolutionWire); }
    catch { return {detail: 'ResolutionNotCommitted'}; }
    if (verified?.resolution?.checkpoint_cid !== checkpoint.checkpointCid ||
        verified.resolution.decision !== 'approved' ||
        !text(verified.verified_reviewer_id)) {
      return {detail: 'ResolutionNotCommitted'};
    }
    return {checkpoint, authority: verified.verified_reviewer_id};
  }

  async function evaluateResumed(boundary, tuple, subjectCid, resumption) {
    const base = {boundary, tuple, subjectCid, contextCid: context.contextCid};
    count('evaluations');
    if (core.moon === undefined) {
      return frozenDecision({...base, action: 'deny', basis: 'account',
        reason: 'configuration_missing'});
    }
    const moon = core.moon;
    // The account is evaluated again for the current tuple: a deny added
    // while the Run waited still denies; an allow needs no Resolution.
    const evaluation = moon.executionAuthorizationEvaluate(
      core.account, tuple.principal, tuple.connection, tuple.resource,
      tuple.operation,
    );
    const outcome = JSON.parse(
      moon.executionAuthorizationEvaluationJson(evaluation));
    if (outcome.outcome !== 'delegate') {
      const runtimeDecision = moon.executionAuthorizationEvaluationAction(
        evaluation);
      const projected = JSON.parse(
        moon.executionAuthorizationDecisionJson(runtimeDecision));
      return frozenDecision({...base, action: projected.action,
        basis: projected.basis, reason: projected.reason ?? undefined,
        entryId: outcome.entry_id,
        runtimeDecision: projected.action === 'dispatch'
          ? runtimeDecision : undefined});
    }
    const withEntry = {...base, entryId: outcome.entry_id, basis: 'resumed'};
    if (core.deferral === undefined) {
      return frozenDecision({...withEntry, action: 'unsupported',
        reason: 'checkpoint_journal_not_configured'});
    }
    const request = moon.executionAuthorizationPrepare(
      evaluation, core.configurationCid, boundary, subjectCid ?? '',
      context.contextCid, [...core.answeringAuthorities],
      [...core.requiredClaims],
    );
    const bound = JSON.parse(moon.executionAuthorizationRequestJson(request));
    if (bound.ok !== true) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: bound.issue});
    }
    let approval;
    try { approval = committedApproval(resumption); }
    catch (error) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: 'ResolutionNotCommitted', error});
    }
    if (approval.detail !== undefined) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: approval.detail});
    }
    // The approval covers only the sealed artifact and the decision subject
    // bound at defer time: another artifact, Site, registration, boundary,
    // subject, context, tuple or entry is not it.
    if (!cid(subjectCid) ||
        approval.checkpoint.requiredArtifact.cid !== subjectCid ||
        approval.checkpoint.decisionSubjectCid !==
          await decisionSubjectCid(bound.subject)) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: 'ResolutionSubjectMismatch'});
    }
    // The committed approval is admitted as the Host permit for the bound
    // request, so the runtime still checks subject, authority and claims.
    const subject = SUBJECT_FIELDS.map(name => bound.subject[name]);
    const runtimeDecision = moon.executionAuthorizationAnswer(request,
      'permit', subject, approval.authority, [...core.requiredClaims], '');
    const projected = JSON.parse(
      moon.executionAuthorizationDecisionJson(runtimeDecision));
    if (projected.action !== 'dispatch') {
      return frozenDecision({...withEntry, action: 'failure',
        reason: projected.reason ?? 'malformed_answer',
        detail: projected.detail ?? projected.issue ?? undefined});
    }
    count('resumedDecisions');
    return frozenDecision({...withEntry, action: 'dispatch',
      authority: projected.authority,
      claims: Object.freeze([...projected.claims]),
      checkpointCid: approval.checkpoint.checkpointCid,
      resolutionCid: approval.checkpoint.resolutionCid,
      runtimeDecision});
  }

  async function evaluate(boundary, tuple, subjectCid, signal) {
    const base = {boundary, tuple, subjectCid, contextCid: context.contextCid};
    count('evaluations');
    if (core.moon === undefined) {
      return frozenDecision({...base, action: 'deny', basis: 'account',
        reason: 'configuration_missing'});
    }
    const moon = core.moon;
    const evaluation = moon.executionAuthorizationEvaluate(
      core.account, tuple.principal, tuple.connection, tuple.resource,
      tuple.operation,
    );
    const outcome = JSON.parse(
      moon.executionAuthorizationEvaluationJson(evaluation));
    if (outcome.outcome !== 'delegate') {
      const runtimeDecision = moon.executionAuthorizationEvaluationAction(
        evaluation);
      const projected = JSON.parse(
        moon.executionAuthorizationDecisionJson(runtimeDecision));
      return frozenDecision({...base, action: projected.action,
        basis: projected.basis, reason: projected.reason ?? undefined,
        entryId: outcome.entry_id,
        runtimeDecision: projected.action === 'dispatch'
          ? runtimeDecision : undefined});
    }
    const withEntry = {...base, entryId: outcome.entry_id, basis: 'delegate'};
    // Local delegate default: without a Host decision function, wait in a
    // Checkpoint only when durable storage and a later answer path exist;
    // otherwise stop before the protected operation as not configured. This
    // is neither a rejection nor a non-durable wait.
    if (core.decide === undefined && core.deferral === undefined) {
      return frozenDecision({...withEntry, action: 'unsupported',
        reason: 'decision_function_not_configured'});
    }
    const request = moon.executionAuthorizationPrepare(
      evaluation, core.configurationCid, boundary, subjectCid ?? '',
      context.contextCid, [...core.answeringAuthorities],
      [...core.requiredClaims],
    );
    const bound = JSON.parse(moon.executionAuthorizationRequestJson(request));
    if (bound.ok !== true) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: bound.issue});
    }
    // The Host sees the sealed subject artifact and the decision-subject
    // binding, so an immediate answer binds the same artifact and subject a
    // deferred Checkpoint would.
    const view = Object.freeze({
      boundary,
      tuple,
      subject: Object.freeze({...bound.subject}),
      subjectArtifactCid: cid(subjectCid) ? subjectCid : null,
      decisionSubjectCid: await decisionSubjectCid(bound.subject),
      answeringAuthorities: Object.freeze([...bound.answering_authorities]),
      requiredClaims: Object.freeze([...bound.required_claims]),
    });
    signal?.throwIfAborted();
    // No decision function: the durable journal and its answer path are the
    // Host's decision route, so the bound subject is deferred as is.
    const answer = core.decide === undefined
      ? {kind: 'defer', subject: SUBJECT_FIELDS.map(name => view.subject[name])}
      : immediateBinding(await askHost(view, signal), view);
    const runtimeDecision = moon.executionAuthorizationAnswer(
      request,
      answer.kind,
      answer.subject ?? [],
      answer.authority ?? '',
      answer.claims ?? [],
      answer.kind === 'failure'
        ? (FAILURE_REASONS.has(answer.failure) ? answer.failure
          : String(answer.error?.code ?? answer.error?.message ??
            'adapter_error'))
        : '',
    );
    const projected = JSON.parse(
      moon.executionAuthorizationDecisionJson(runtimeDecision));
    if (projected.action === 'dispatch') {
      return frozenDecision({...withEntry, action: 'dispatch',
        basis: 'host_permit', authority: projected.authority,
        claims: Object.freeze([...projected.claims]), runtimeDecision});
    }
    if (projected.action === 'deny') {
      count('hostRejections');
      return frozenDecision({...withEntry, action: 'deny',
        basis: 'rejected_by_host', reason: 'rejected',
        authority: projected.authority});
    }
    if (projected.action === 'checkpoint') return defer(withEntry, view);
    return frozenDecision({...withEntry, action: 'failure',
      reason: projected.reason ?? 'malformed_answer',
      detail: projected.detail ?? projected.issue ?? undefined,
      error: answer.error});
  }

  return Object.freeze({
    accountId: core.accountId,
    configurationCid: core.configurationCid,
    principal: context.principal,
    contextCid: context.contextCid,

    // Evaluate one protected boundary for the exact scope. The tuple principal
    // is the Host context principal; the caller supplies only the Host-derived
    // connection/resource/operation and the sealed subject CID.
    async authorize(boundary, scope, {subjectCid, signal} = {}) {
      if (!AUTHORIZATION_BOUNDARIES.includes(boundary)) {
        fail('InvalidAuthorizationBoundary');
      }
      checkedScope(scope);
      if (subjectCid !== undefined && typeof subjectCid !== 'string') {
        fail('InvalidAuthorizationSubject');
      }
      signal?.throwIfAborted();
      const tuple = Object.freeze({
        principal: context.principal,
        connection: scope.connection,
        resource: scope.resource,
        operation: scope.operation,
      });
      const key = JSON.stringify([
        boundary, tuple.principal, tuple.connection, tuple.resource,
        tuple.operation, subjectCid ?? '', context.contextCid,
      ]);
      const cached = core.cache.get(key);
      if (cached !== undefined) {
        count('reusedDecisions');
        return record(cached);
      }
      const decision = await evaluate(boundary, tuple, subjectCid, signal);
      // Only final decisions are reused, and only for this exact scope.
      // Failures, unsupported defers and waits are evaluated again.
      if (decision.action === 'dispatch' || decision.action === 'deny') {
        core.cache.set(key, decision);
      }
      return record(decision);
    },

    // Continue a deferred boundary from its committed Resolution. The
    // `resumption` is {claim, resolution}: the Checkpoint journal's
    // claimResume result and its committed submitResolution result. The
    // account is evaluated again for the current scope; the committed
    // approval then authorizes only the exact decision subject its Checkpoint
    // bound. No Host decision is asked and nothing is cached.
    async resume(boundary, scope, {subjectCid, signal, resumption} = {}) {
      if (!AUTHORIZATION_BOUNDARIES.includes(boundary)) {
        fail('InvalidAuthorizationBoundary');
      }
      checkedScope(scope);
      if (subjectCid !== undefined && typeof subjectCid !== 'string') {
        fail('InvalidAuthorizationSubject');
      }
      signal?.throwIfAborted();
      const tuple = Object.freeze({
        principal: context.principal,
        connection: scope.connection,
        resource: scope.resource,
        operation: scope.operation,
      });
      return record(await evaluateResumed(boundary, tuple, subjectCid,
        resumption));
    },

    // Explicit no-protected-scope coverage for pure compute over captured
    // inputs on an unprotected in-process Site. No evaluation, no Host call.
    cover(boundary, scope) {
      if (!AUTHORIZATION_BOUNDARIES.includes(boundary)) {
        fail('InvalidAuthorizationBoundary');
      }
      checkedScope(scope);
      count('coveredOperations');
      return frozenDecision({boundary, action: 'dispatch', basis: 'covered',
        tuple: Object.freeze({principal: context.principal,
          connection: scope.connection, resource: scope.resource,
          operation: scope.operation})});
    },

    isProtectedSite(key) { return core.protectedSites.has(key); },

    // Same installation under another trusted context. Counters and cache are
    // shared; the cache key includes the context, so nothing is widened.
    withContext(next) {
      if (next === null || typeof next !== 'object' ||
          !text(next.principal) || !cid(next.contextCid)) {
        fail('InvalidAuthorizationContext');
      }
      return gateFor(core, Object.freeze({
        principal: next.principal,
        contextCid: next.contextCid,
      }));
    },

    counters() { return Object.freeze({...core.counts}); },
  });
}

// Boundary helper: continue only with a dispatch decision for this exact
// scope. Every other outcome stops before the protected operation.
export async function requireAuthorizedDispatch(gate, boundary, scope, options) {
  const decision = await gate.authorize(boundary, scope, options);
  if (decision.action !== 'dispatch') {
    throw new ExecutionAuthorizationError(decision);
  }
  return decision;
}

// A gate for a Host installation without account configuration. It denies
// every protected boundary (configuration_missing) and still allows explicit
// no-protected-scope coverage.
export function missingAuthorizationGate(context = {
  principal: 'host',
  contextCid: `sha256:${'0'.repeat(64)}`,
}) {
  return createAuthorizationGate({context});
}
