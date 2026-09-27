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
const decisionBudgets = new WeakMap();

// A Host installation shares physical callback capacity across its short-lived
// decision scopes. Judgments remain private to each scope, never global.
export function createAuthorizationDecisionBudget({maxInFlightDecisions = 16,
  maxRetainedDecisions = 1024} = {}) {
  if (![maxInFlightDecisions, maxRetainedDecisions].every(value =>
    Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidAuthorizationCapacity');
  }
  const state = {pending: new Set(), retention: {entries: 0},
    scopes: new Set(), maxInFlightDecisions, maxRetainedDecisions,
    closed: false};
  const budget = Object.freeze({
    usage: () => Object.freeze({inFlightDecisions: state.pending.size,
      retainedDecisions: state.retention.entries,
      scopes: state.scopes.size, closed: state.closed}),
    close() {
      state.closed = true;
      for (const close of [...state.scopes]) close();
      return state.pending.size === 0 && state.retention.entries === 0;
    },
    cleanupPending: () => state.pending.size !== 0 ||
      state.retention.entries !== 0,
  });
  decisionBudgets.set(budget, state);
  return budget;
}

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
// the Effect Set Preview, or the prepared invocation a two-phase preparation
// seals only on its defer path), so approval evidence binds the real artifact.
// The journal stores this binding next to the
// Checkpoint, and resume admits the approval only for the exact account
// entry, principal, connection, resource, operation, boundary, subject and
// context it names.
export async function decisionSubjectCid(subject) {
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
  maxInFlightDecisions = 16,
  maxRetainedDecisions = 1024,
  decisionBudget,
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
  if (![maxInFlightDecisions, maxRetainedDecisions].every(value =>
    Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidAuthorizationCapacity');
  }
  const capacity = decisionBudget === undefined
    ? decisionBudgets.get(createAuthorizationDecisionBudget({
      maxInFlightDecisions, maxRetainedDecisions}))
    : decisionBudgets.get(decisionBudget);
  if (capacity === undefined || capacity.closed) {
    fail('InvalidAuthorizationDecisionBudget');
  }
  if (!Array.isArray(protectedSites) || !protectedSites.every(text)) {
    fail('InvalidProtectedSites');
  }
  const missing = configuration === undefined || configuration === null;
  if (!missing && (typeof configuration !== 'string' ||
      (configurationCid !== undefined && !cid(configurationCid)))) {
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
  // The configuration CID is the admitted configuration's own identity;
  // a Host-supplied CID is only a cross-check. Decision subjects,
  // Checkpoints and resume admission bind this CID, so a stale one could
  // let a continuation outlive a configuration change.
  if (state.state === 'admitted' && configurationCid !== undefined &&
      configurationCid !== state.configuration_cid) {
    fail('AuthorizationConfigurationCidMismatch');
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
    configurationCid: state.state === 'admitted' ? state.configuration_cid
      : undefined,
    decide,
    answeringAuthorities: Object.freeze([...answering]),
    requiredClaims: Object.freeze([...requiredClaims]),
    decisionTimeoutMs,
    maxInFlightDecisions: capacity.maxInFlightDecisions,
    maxRetainedDecisions: capacity.maxRetainedDecisions,
    deferral: durable,
    protectedSites: new Set(protectedSites),
    counts: Object.fromEntries(COUNTERS.map(name => [name, 0])),
    // Shared capacity, not shared judgments. Pending callbacks keep their
    // physical slot until settlement, including after deadline or close.
    pending: capacity.pending,
    retention: capacity.retention,
    capacity,
  });
  return gateFor(core, Object.freeze({
    principal: context.principal,
    contextCid: context.contextCid,
  }));
}

function gateFor(core, context) {
  const cache = new Map();
  const pending = new Set();
  let closed = false;
  const ensureOpen = () => {
    if (closed) fail('AuthorizationDecisionScopeClosed');
  };
  const release = (key, entry) => {
    if (cache.get(key) !== entry) return;
    cache.delete(key);
    core.retention.entries--;
  };
  const closeScope = () => {
    closed = true;
    core.capacity.scopes.delete(closeScope);
    for (const [key, entry] of cache) {
      if (entry.settled) release(key, entry);
    }
    for (const entry of pending) entry.abort();
    return cache.size === 0 && pending.size === 0;
  };
  core.capacity.scopes.add(closeScope);
  const count = (name, delta = 1) => { core.counts[name] += delta; };
  const record = decision => {
    if (decision.action === 'dispatch') count('protectedDispatches');
    else if (decision.action === 'deny') count('deniedBeforeDispatch');
    else if (decision.action === 'failure') count('decisionFailures');
    else if (decision.action === 'unsupported') count('unsupportedDefers');
    return decision;
  };

  async function askHost(view, signal) {
    if (closed || signal?.aborted) {
      return {kind: 'failure', failure: 'unavailable'};
    }
    if (core.pending.size >= core.maxInFlightDecisions) {
      return {kind: 'failure', failure: 'adapter_error',
        error: new Error('AuthorizationDecisionCapacity')};
    }
    const controller = new AbortController();
    let timer;
    let onAbort;
    let stop;
    const stopped = new Promise(resolve => { stop = resolve; });
    const entry = {abort(reason = 'unavailable') {
      stop({kind: 'failure', failure: reason});
      controller.abort(reason);
    }};
    core.pending.add(entry);
    pending.add(entry);
    const operation = Promise.resolve().then(() => {
      if (controller.signal.aborted) return {decision: 'unavailable'};
      count('hostDecisionCalls');
      return core.decide(view, {signal: controller.signal});
    }).then(
        answerOf,
        error => ({kind: 'failure', failure: 'adapter_error', error}),
    ).finally(() => {
      core.pending.delete(entry);
      pending.delete(entry);
    });
    entry.operation = operation;
    timer = setTimeout(() => entry.abort('timeout'), core.decisionTimeoutMs);
    if (signal !== undefined) {
      onAbort = () => entry.abort();
      if (signal.aborted) onAbort();
      else signal.addEventListener('abort', onAbort, {once: true});
    }
    try {
      return await Promise.race([operation, stopped]);
    } finally {
      clearTimeout(timer);
      if (onAbort !== undefined) signal.removeEventListener('abort', onAbort);
    }
  }

  async function defer(base, view, sealDeferredSubject) {
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
    // A Host-required claim no deferred approval evidence profile can
    // establish can never be admitted at resume: refuse before capture,
    // before any Checkpoint is persisted and before any reviewer is asked.
    if (!representableClaims(view.requiredClaims)) {
      return frozenDecision({...base, action: 'failure',
        reason: 'adapter_error', detail: 'RequiredClaimUnrepresentable'});
    }
    // Two-phase boundary (preparation): the decision was made on the request
    // subject before any capture; only now, on the defer path, the Host
    // captures its inputs and seals the reviewed artifact (the prepared
    // invocation). The decision-subject binding still names the request.
    let artifactCid = base.subjectCid;
    if (sealDeferredSubject !== undefined) {
      try { artifactCid = await sealDeferredSubject(view); }
      catch (error) {
        return frozenDecision({...base, action: 'failure',
          reason: 'adapter_error', detail: 'SubjectArtifactNotSealed', error});
      }
      if (!cid(artifactCid)) {
        return frozenDecision({...base, action: 'failure',
          reason: 'adapter_error', detail: 'InvalidSubjectArtifact'});
      }
    }
    const sealedView = Object.freeze({...view, requiredArtifactCid: artifactCid});
    let persisted;
    let bindingCid;
    try {
      bindingCid = await decisionSubjectCid(view.subject);
      const described = await deferral.describe(sealedView);
      ensureOpen();
      const supplied = described?.body?.required_artifact?.artifact_cid;
      // `describe` may not substitute another artifact for the subject.
      if (supplied !== undefined && supplied !== artifactCid) {
        return frozenDecision({...base, action: 'failure',
          reason: 'adapter_error', detail: 'SubjectArtifactMismatch'});
      }
      const kind = described?.body?.kind ?? CHECKPOINT_KIND[base.boundary];
      // ... and exactly for the evidence profile of this Checkpoint kind.
      if (!representableClaims(view.requiredClaims, kind)) {
        return frozenDecision({...base, action: 'failure',
          reason: 'adapter_error', detail: 'RequiredClaimUnrepresentable'});
      }
      const phase = base.boundary === 'effect_commit' ? 'commit' : 'preflight';
      const body = {
        version: 'actql-execution-checkpoint/0.1',
        phase,
        kind,
        // An Effect Set review asks the reviewer for the optional
        // partial-application claim only when the Host requires it.
        requirements: kind !== 'effect_set' ? ['invocation_scope_approved']
          : view.requiredClaims.includes('partial_application_accepted')
            ? ['effect_scope_approved', 'partial_application_accepted']
            : ['effect_scope_approved'],
        reason_code: 'delegated_decision_deferred',
        ...described.body,
        // The reviewed artifact of an authorization deferral is the sealed
        // subject artifact of the boundary; the gate owns this binding.
        required_artifact: {
          artifact_type: ARTIFACT_TYPE[kind],
          ...described.body?.required_artifact,
          artifact_cid: artifactCid,
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
        // The claims this decision was requested with; resume admits the
        // approval only if they are unchanged and its evidence establishes
        // every one of them.
        requestedClaims: [...view.requiredClaims],
        // The configuration this decision was evaluated under; a resume
        // under another configuration is refused whatever it now says.
        configurationCid: core.configurationCid,
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
        requiredArtifactCid: artifactCid,
        decisionSubjectCid: bindingCid,
      })});
  }

  async function evaluateResumed(boundary, tuple, subjectCid, resumption,
    sealedSubjectCid = subjectCid, signal = undefined) {
    const base = {boundary, tuple, subjectCid, contextCid: context.contextCid};
    count('evaluations');
    if (core.moon === undefined) {
      return frozenDecision({...base, action: 'deny', basis: 'account',
        reason: 'configuration_missing'});
    }
    const moon = core.moon;
    // The account is evaluated again for the current tuple: a deny added
    // while the Run waited still denies. An allow needs no Resolution for
    // this tuple, but it does not make the continuation anyone's to resume:
    // the resume ownership admission below applies to every resumed
    // dispatch, allow or delegate.
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
      const decided = {...base, action: projected.action,
        basis: projected.basis, reason: projected.reason ?? undefined,
        entryId: outcome.entry_id};
      if (projected.action !== 'dispatch') return frozenDecision(decided);
      // Ownership only: live claim, current intent, committed approval of
      // the resumed Checkpoint still valid, same configuration. No approval
      // claim is asked of an allow.
      const owned = admitResumedDispatch(core.deferral?.journal, resumption,
        {configurationCid: core.configurationCid, approvalClaims: false});
      if (owned.detail !== undefined) {
        return frozenDecision({...decided, action: 'failure',
          reason: 'adapter_error', detail: owned.detail, error: owned.error});
      }
      count('resumedDecisions');
      return frozenDecision({...decided,
        checkpointCid: owned.admission.checkpointCid,
        resolutionCid: owned.admission.resolutionCid,
        admission: owned.admission,
        runtimeDecision});
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
    const boundSubjectCid = await decisionSubjectCid(bound.subject);
    ensureOpen();
    signal?.throwIfAborted();
    // From here on nothing awaits: the admission read below and the answer
    // it produces describe the journal at one Host trusted instant. The
    // caller still enters the admission immediately before its send.
    const admitted = admitResumedDispatch(core.deferral.journal, resumption,
      {requiredClaims: bound.required_claims,
        configurationCid: core.configurationCid});
    if (admitted.detail !== undefined) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: admitted.detail,
        error: admitted.error});
    }
    const {admission, claims} = admitted;
    // The approval covers only the sealed artifact and the decision subject
    // bound at defer time: another artifact, Site, registration, boundary,
    // subject, context, tuple or entry is not it. A two-phase preparation
    // names its captured prepared invocation as `sealedSubjectCid`.
    if (!cid(subjectCid) || !cid(sealedSubjectCid) ||
        admission.requiredArtifactCid !== sealedSubjectCid ||
        admission.decisionSubjectCid !== boundSubjectCid) {
      return frozenDecision({...withEntry, action: 'failure',
        reason: 'adapter_error', detail: 'ResolutionSubjectMismatch'});
    }
    // The committed approval is admitted as the Host permit for the bound
    // request with only the claims its evidence established, so the runtime
    // still checks subject, authority and the exact required claims.
    const subject = SUBJECT_FIELDS.map(name => bound.subject[name]);
    const runtimeDecision = moon.executionAuthorizationAnswer(request,
      'permit', subject, admission.authority, [...claims], '');
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
      checkpointCid: admission.checkpointCid,
      resolutionCid: admission.resolutionCid,
      admission,
      runtimeDecision});
  }

  async function evaluate(boundary, tuple, subjectCid, signal,
    sealDeferredSubject) {
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
    ensureOpen();
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
    if (projected.action === 'checkpoint') {
      return defer(withEntry, view, sealDeferredSubject);
    }
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
    //
    // `sealDeferredSubject` makes the boundary two-phase: the account outcome
    // and any immediate Host answer are decided on `subjectCid` (for
    // preparation, the invocation request, before any path read); only on a
    // deferred Host answer is it called with the Host view to capture inputs
    // and return the CID of the artifact the Checkpoint requires (the
    // prepared invocation). A throw or a non-CID result is a decision failure
    // and nothing is persisted.
    async authorize(boundary, scope, {subjectCid, signal,
      sealDeferredSubject} = {}) {
      ensureOpen();
      if (!AUTHORIZATION_BOUNDARIES.includes(boundary)) {
        fail('InvalidAuthorizationBoundary');
      }
      checkedScope(scope);
      if (subjectCid !== undefined && typeof subjectCid !== 'string') {
        fail('InvalidAuthorizationSubject');
      }
      if (sealDeferredSubject !== undefined &&
          typeof sealDeferredSubject !== 'function') {
        fail('InvalidAuthorizationSealer');
      }
      signal?.throwIfAborted();
      const tuple = Object.freeze({
        principal: context.principal,
        connection: scope.connection,
        resource: scope.resource,
        operation: scope.operation,
      });
      // Bound retained key material before serialization. This is a Host
      // capacity failure, not an account rejection or a permission TTL.
      const capacityFailure = () => record(frozenDecision({boundary, tuple,
        subjectCid, contextCid: context.contextCid, action: 'failure',
        reason: 'adapter_error', detail: 'AuthorizationDecisionCapacity'}));
      if ((subjectCid?.length ?? 0) > 512) return capacityFailure();
      const key = JSON.stringify([
        boundary, tuple.principal, tuple.connection, tuple.resource,
        tuple.operation, subjectCid ?? '', context.contextCid,
      ]);
      const cached = cache.get(key);
      if (cached !== undefined) {
        const decision = await cached.operation;
        ensureOpen();
        signal?.throwIfAborted();
        count('reusedDecisions');
        return record(decision);
      }
      if (core.retention.entries >= core.maxRetainedDecisions) {
        return capacityFailure();
      }
      // Reserve before starting, so concurrent evaluations cannot overfill
      // the installation. The exact subject joins one pending evaluation.
      const entry = {};
      cache.set(key, entry);
      core.retention.entries++;
      entry.operation = evaluate(boundary, tuple, subjectCid, signal,
        sealDeferredSubject).then(decision => {
        ensureOpen();
        if (decision.action !== 'dispatch' && decision.action !== 'deny') {
          release(key, entry);
        }
        return decision;
      }).catch(error => { release(key, entry); throw error; }).finally(() => {
        entry.settled = true;
        if (closed) release(key, entry);
      });
      return record(await entry.operation);
    },

    // Continue a deferred boundary from its committed Resolution. The
    // `resumption` is {claim}: the claim the caller holds, as the Checkpoint
    // journal's claimResume result (or its `claim`). It only names the claim;
    // the claim, the committed Resolution and its evidence are read from the
    // journal through `admitResumedDispatch` (fence, approval validity and
    // observed claims at the Host trusted time). Anything else the caller
    // supplies, such as a Resolution or verified wrapper, is ignored. The
    // account is evaluated again for the current scope. A deny stops. Allow
    // and delegate both pass the same ownership admission (live claim,
    // committed approval of the resumed Checkpoint still valid, unchanged
    // configuration); for a delegate the committed approval then authorizes
    // only the exact decision subject its Checkpoint bound. No Host decision
    // is asked and nothing is cached. For a two-phase boundary
    // `sealedSubjectCid` is the artifact the Checkpoint sealed on its defer
    // path (default: `subjectCid`).
    //
    // Caller contract (remote dispatch, Effect commit and any other resumed
    // protected operation): a `dispatch` decision carries `admission`; the
    // caller calls `admission.enter()` synchronously immediately before the
    // protected send, with no await in between. `enter` fences again at the
    // Host trusted time, rechecks the approval's validity and records the
    // single protected dispatch start of this claim generation; if it throws
    // nothing may be sent. The decision itself is not a reusable token. When
    // an earlier claim generation already started a protected dispatch,
    // `enter` refuses the fresh start (`PriorAdmissionUnresolved`): the
    // caller may only re-send that exact durable dispatch identity through
    // `admission.reconcile(identity)`, or leave the intent unresolved.
    async resume(boundary, scope, {subjectCid, signal, resumption,
      sealedSubjectCid} = {}) {
      ensureOpen();
      if (!AUTHORIZATION_BOUNDARIES.includes(boundary)) {
        fail('InvalidAuthorizationBoundary');
      }
      checkedScope(scope);
      if ((subjectCid !== undefined && typeof subjectCid !== 'string') ||
          (sealedSubjectCid !== undefined &&
           typeof sealedSubjectCid !== 'string')) {
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
        resumption, sealedSubjectCid ?? subjectCid, signal));
    },

    // Explicit no-protected-scope coverage for pure compute over captured
    // inputs on an unprotected in-process Site. No evaluation, no Host call.
    cover(boundary, scope) {
      ensureOpen();
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

    // A new execution-owned decision scope under the same immutable account
    // and shared capacity. Reuse this returned scope within that execution;
    // close it at the end. No installation-wide Map retains old contexts.
    withContext(next) {
      ensureOpen();
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
    resourceUsage() {
      return Object.freeze({retainedDecisions: core.retention.entries,
        scopeDecisions: cache.size, inFlightDecisions: core.pending.size,
        scopeInFlightDecisions: pending.size});
    },
    close: closeScope,
    cleanupPending() { return cache.size !== 0 || pending.size !== 0; },
    cleanup: closeScope,
  });
}

// Claims each deferred approval evidence profile can establish. A run-scope
// style approval establishes its single invocation claim; an Effect Set
// attestation its effect and optional partial-application claims. A Host
// requirement outside this set cannot be answered by a deferred approval.
const REPRESENTABLE_CLAIMS = Object.freeze({
  effect_set: Object.freeze(['effect_scope_approved',
    'partial_application_accepted']),
  other: Object.freeze(['invocation_scope_approved']),
});

// Whether every required claim is representable by the approval evidence
// profile of `kind` or, with no kind, by any deferred profile.
function representableClaims(claims, kind) {
  const profiles = kind === undefined ? Object.values(REPRESENTABLE_CLAIMS)
    : [REPRESENTABLE_CLAIMS[kind] ?? REPRESENTABLE_CLAIMS.other];
  const representable = new Set(profiles.flat());
  return [...claims].every(claim => representable.has(claim));
}

const heldClaim = resumption => {
  const held = resumption?.claim;
  const claim = held?.claim ?? held;
  return Object.freeze({
    checkpointCid: text(held?.checkpointCid) ? held.checkpointCid : undefined,
    claim: claim === null || typeof claim !== 'object' ? undefined
      : Object.freeze({intentId: claim.intentId, claimant: claim.claimant,
        generation: claim.generation}),
  });
};

// The one authoritative resumed-dispatch admission path, shared by
// `gate.resume` and every resumed dispatch caller (the remote Coordinator,
// the Local Host resume port and Effect callers).
//
// Inputs: the Checkpoint journal, the caller's `resumption` ({claim}, which
// only names the held claim), the current account configuration CID and the
// Host's current required claims. `approvalClaims: false` (a resumed tuple
// the account now allows) checks ownership only and admits no claim.
// Checks, all from committed journal rows at the journal's Host trusted time:
// the claim is the current intent's live claim (MoonBit fence: claimant,
// generation, unexpired lease), the Checkpoint is resolved by that intent's
// committed approved Resolution, the Run or preparation is `resuming`, and
// the approval's own permission is still current (`admitResume`); the
// Checkpoint was deferred under the current configuration. Then the
// claims: the requirements bound when the decision was deferred must equal
// the current ones, each must be representable by the evidence profile, and
// each must be established by the committed evidence (observed claims). No
// claim is ever taken from configuration or from what the Host asks for.
// Output: `{admission, claims}` or `{detail}`. The admission binds Run or
// preparation, Checkpoint, intent, Resolution, claimant, generation and
// lease; its `enter()` must be called immediately before the protected send
// and succeeds at most once per claim generation.
export function admitResumedDispatch(journal, resumption, {
  requiredClaims = [], configurationCid, approvalClaims = true,
} = {}) {
  if (journal === null || typeof journal !== 'object' ||
      typeof journal.admitResume !== 'function' ||
      typeof journal.enterResumedDispatch !== 'function') {
    return {detail: 'ResumeJournalUnavailable'};
  }
  const held = heldClaim(resumption);
  if (held.claim === undefined) return {detail: 'ResumeNotClaimed'};
  let admitted;
  try {
    admitted = journal.admitResume(held.claim,
      {checkpointCid: held.checkpointCid});
  } catch (error) {
    return {detail: typeof error?.code === 'string' ? error.code
      : 'ResumeAdmissionFailed', error};
  }
  // A configuration change while the Run waited revokes the continuation:
  // no resume under another (or an unrecorded) configuration.
  if (!cid(configurationCid) ||
      admitted.configurationCid !== configurationCid) {
    return {detail: 'ResumeConfigurationChanged'};
  }
  // An allowed tuple asks no claim: ownership only.
  const requested = approvalClaims ? [...admitted.requestedClaims].sort()
    : [];
  if (approvalClaims) {
    const current = [...new Set(requiredClaims)].sort();
    if (JSON.stringify(requested) !== JSON.stringify(current)) {
      return {detail: 'RequiredClaimsChanged'};
    }
    const representable = REPRESENTABLE_CLAIMS[admitted.kind] ??
      REPRESENTABLE_CLAIMS.other;
    if (!requested.every(claim => representable.includes(claim))) {
      return {detail: 'RequiredClaimUnrepresentable'};
    }
    if (!requested.every(claim => admitted.observedClaims.includes(claim))) {
      return {detail: 'RequiredClaimNotEstablished'};
    }
  }
  let used = false;
  const once = (method, dispatchIdentity) => {
    if (used) {
      throw Object.assign(new Error('ResumeAdmissionConsumed'),
        {code: 'ResumeAdmissionConsumed'});
    }
    if (method === 'enterResumedReconciliation' &&
        typeof journal[method] !== 'function') {
      throw Object.assign(new Error('ResumeJournalUnavailable'),
        {code: 'ResumeJournalUnavailable'});
    }
    const entered = journal[method]({
      intentId: admitted.intentId,
      claimant: admitted.claimant,
      generation: admitted.generation,
    }, {checkpointCid: admitted.checkpointCid,
      resolutionCid: admitted.resolutionCid,
      ...(dispatchIdentity === undefined ? {} : {dispatchIdentity})});
    // Only a recorded entry consumes the admission: a refused fresh start
    // (`PriorAdmissionUnresolved`) leaves the reconciliation path open.
    used = true;
    if (entered.intentId !== admitted.intentId ||
        entered.generation !== admitted.generation ||
        entered.claimant !== admitted.claimant) {
      throw Object.assign(new Error('ResumeClaimStale'),
        {code: 'ResumeClaimStale'});
    }
    return entered;
  };
  const admission = Object.freeze({
    ...admitted,
    // Fence again at the Host trusted time immediately before the send and
    // record the single protected dispatch start of this claim generation,
    // with the send's durable identity when it has one. Throws
    // `PriorAdmissionUnresolved` when an earlier claim generation of the
    // same intent already started a protected dispatch: no fresh start.
    enter(dispatchIdentity) {
      return once('enterResumedDispatch', dispatchIdentity);
    },
    // The physical reconciliation path after `PriorAdmissionUnresolved`:
    // the same fence, admitting only a re-send of the earlier generation's
    // exact durable dispatch identity (never a second distinct dispatch).
    reconcile(dispatchIdentity) {
      return once('enterResumedReconciliation', dispatchIdentity);
    },
  });
  return {admission, claims: Object.freeze(requested)};
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
