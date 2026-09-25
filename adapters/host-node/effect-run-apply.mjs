import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 512;

// Account operation of an Effect commit in the Read/Write/Effect operation
// classification. The boundary kind (effect_commit) and the sealed Set
// Preview stay in the decision subject.
const EFFECT_OPERATION = 'effect';

// Host-installed Effect commit authorization. `gate` is the execution-account
// gate; `scopes` gives the Host-derived connection and resource of each
// member in member order. `resume` is present only when continuing a Run
// whose deferred decision was answered. It either names a claim the caller
// already holds (`claim`, a Checkpoint journal claimResume result) or asks
// this function to claim the approved resume intent (`journal`, `runId`,
// `claimant`, `leaseMs`, `binding`). The committed Resolution and its
// evidence are read by the gate from the journal, never from the caller.
function checkedAuthorization(authorization, memberCount) {
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.gate?.authorize !== 'function' ||
      !Array.isArray(authorization.scopes) ||
      authorization.scopes.length !== memberCount ||
      !authorization.scopes.every(scope => text(scope?.connection) &&
        text(scope?.resource))) {
    fail('EffectApplyAuthorizationRequired');
  }
  const resume = authorization.resume;
  if (resume !== undefined && (resume === null || typeof resume !== 'object' ||
      typeof authorization.gate.resume !== 'function' ||
      (resume.claim === undefined &&
        (typeof resume.journal?.claimResume !== 'function' ||
          !text(resume.runId) || !text(resume.claimant) ||
          !Number.isSafeInteger(resume.leaseMs) || resume.leaseMs < 1)) ||
      (resume.claim !== undefined && (resume.claim === null ||
        typeof resume.claim !== 'object')))) {
    fail('EffectApplyAuthorizationRequired');
  }
  return Object.freeze({
    gate: authorization.gate,
    scopes: Object.freeze(authorization.scopes.map(scope => Object.freeze({
      connection: scope.connection, resource: scope.resource,
      operation: EFFECT_OPERATION}))),
    resume: resume === undefined ? undefined : Object.freeze({...resume}),
  });
}

function sealedSubject(moon, capturedInputs, memberCount) {
  const subjectCid = moon.clientProgramEffectApplySubjectCid(capturedInputs);
  if (typeof subjectCid !== 'string' ||
      moon.clientProgramEffectApplyMemberCount(capturedInputs) !==
        memberCount) {
    fail('InvalidCapturedEffectApply');
  }
  return subjectCid;
}

// Evaluate the Effect commit boundary for the complete sealed Effect Set
// Preview, once per distinct Host tuple of its members. Only dispatch
// continues; the first other outcome stops the whole set before any claim.
async function authorizeEffectCommit(authorization, subjectCid, signal) {
  const tuples = new Map(authorization.scopes.map(tuple => [
    JSON.stringify([tuple.connection, tuple.resource, tuple.operation]),
    tuple]));
  let resumption;
  if (authorization.resume !== undefined) {
    const resume = authorization.resume;
    const claimed = resume.claim ?? resume.journal.claimResume(resume.runId, {
      claimant: resume.claimant, leaseMs: resume.leaseMs,
      binding: resume.binding, unknownEffects: resume.unknownEffects ?? [],
    });
    if (claimed.action !== 'claimed') {
      throw Object.assign(new Error('EffectApplyResumeNotClaimed'), {
        code: 'EffectApplyResumeNotClaimed', resume: claimed,
      });
    }
    resumption = Object.freeze({claim: claimed});
  }
  const decisions = [];
  for (const tuple of tuples.values()) {
    signal?.throwIfAborted();
    const decision = resumption === undefined
      ? await authorization.gate.authorize('effect_commit', tuple,
        {subjectCid, signal})
      : await authorization.gate.resume('effect_commit', tuple,
        {subjectCid, signal, resumption});
    decisions.push(decision);
    if (decision.action !== 'dispatch') break;
  }
  // A resumed dispatch carries the journal-authoritative admission; it is
  // entered once, synchronously, immediately before the first protected
  // send of this claim generation.
  return Object.freeze({subjectCid, decisions: Object.freeze(decisions),
    claim: resumption?.claim.claim,
    // An account allow on resume dispatches without an admission; a
    // resumed delegated permit carries one.
    admission: decisions.find(decision =>
      decision.admission !== undefined)?.admission});
}

// Durable identity of one Effect Set apply: the logical request and the
// sealed Set Preview. Every row send of the set is idempotent under the
// Effect ledger for this identity, so a later claim generation may continue
// it only through the reconciliation path with this same identity.
function effectSetApplyIdentity(control, requestScope, subjectCid) {
  return `actql-effect-set-apply/0.1:${
    control.logicalRequestScopeCid(requestScope)}:${subjectCid}`;
}

// Enter the resumed admission for the set's first send. A fresh start is
// refused after an earlier generation already started this set
// (`PriorAdmissionUnresolved`); then only the same durable identity is
// admitted, through reconciliation. Any other refusal propagates and
// nothing is sent.
function enterResumedAdmission(admission, identity) {
  try {
    return admission.enter(identity);
  } catch (error) {
    if (error?.code !== 'PriorAdmissionUnresolved') throw error;
    return admission.reconcile(identity);
  }
}

// Drive only the rows admitted by the retained MoonBit Effect frontier.
// The Site operation owns current credential use and physical observation;
// this Host boundary never infers a row outcome from its return value.
//
// Effect commit is a protected boundary: after whole-set preflight and before
// the first frontier claim, the Host-installed gate must dispatch the exact
// sealed Effect Set Preview. deny, failure and unsupported throw
// ExecutionAuthorizationError; waiting returns the persisted Checkpoint.
// Neither appends a ledger entry nor reaches `dispatchRow`. A resumed commit
// enters the journal admission synchronously immediately before its first
// send. A set with no ready row sends nothing and needs no decision.
export async function applyCapturedEffectSet({
  moon, capturedInputs, preflight: suppliedPreflight, ledger, members,
  dispatchRow,
  maxFrontierWork, signal, refreshGuardObservations, authorization,
}) {
  if (!moon || !capturedInputs || !suppliedPreflight || !ledger ||
      typeof ledger.frontierFromCapturedHeads !== 'function' ||
      !Array.isArray(members) || members.length === 0 ||
      typeof dispatchRow !== 'function' ||
      (refreshGuardObservations !== undefined &&
        typeof refreshGuardObservations !== 'function') ||
      !Number.isSafeInteger(maxFrontierWork) || maxFrontierWork < 1) {
    fail('InvalidCapturedEffectApply');
  }
  const preflight = {...suppliedPreflight};
  for (const name of ['proofs', 'sources', 'contracts', 'capabilities',
    'authorities', 'observedRows', 'guardVersions', 'routes']) {
    if (!Array.isArray(preflight[name])) fail('InvalidCapturedEffectApply');
    preflight[name] = Object.freeze([...preflight[name]]);
  }
  if (!Array.isArray(preflight.keys) ||
      !preflight.keys.every(Array.isArray)) {
    fail('InvalidCapturedEffectApply');
  }
  preflight.keys = Object.freeze(preflight.keys.map(keys =>
    Object.freeze([...keys])));
  Object.freeze(preflight);
  const ownedMembers = Object.freeze(members.map(member => {
    if (!Array.isArray(member?.claims)) fail('InvalidCapturedEffectApply');
    return Object.freeze({claims: Object.freeze(member.claims.map(claim =>
      Object.freeze({...claim})))});
  }));
  const totalRows = ownedMembers.reduce((sum, member) =>
    sum + member.claims.length, 0);
  if (totalRows === 0 || totalRows > 100_000) {
    fail('InvalidCapturedEffectApply');
  }
  const commit = checkedAuthorization(authorization, ownedMembers.length);
  // Risk acceptance is Host policy, not a member-count floor: a body is
  // passed only when the Host holds one, and `partial_application_accepted`
  // is required only when the Host's delegated-decision policy declares it.
  if (preflight.requirePartialApplication !== undefined &&
      typeof preflight.requirePartialApplication !== 'boolean') {
    fail('InvalidCapturedEffectApply');
  }
  const requirePartialApplication =
    preflight.requirePartialApplication === true;
  signal?.throwIfAborted();
  const control = runtimeCore(moon).effectApplicationControl;
  const initialFrontier = ledger.frontierFromCapturedHeads(
    capturedInputs, ownedMembers, maxFrontierWork);
  const noReadyRows = control.setFrontierReadyCount(initialFrontier) === 0;
  const subjectCid = sealedSubject(moon, capturedInputs, ownedMembers.length);
  const currentGuards = noReadyRows || refreshGuardObservations === undefined
    ? preflight : await refreshGuardObservations({signal});
  if (!Array.isArray(currentGuards?.observedRows) ||
      !Array.isArray(currentGuards.guardVersions)) {
    fail('InvalidCapturedEffectGuardObservations');
  }
  signal?.throwIfAborted();
  checked(moon.clientProgramCheckEffectApplyPreflight(
    capturedInputs, preflight.proofs, preflight.sources,
    preflight.contracts, preflight.capabilities, preflight.authorities,
    currentGuards.observedRows, currentGuards.guardVersions,
    preflight.routes,
    preflight.risk ?? undefined, requirePartialApplication,
    preflight.reviewProjectionCid,
    preflight.authorityScopeCid, preflight.policyCid,
    preflight.validityCid, preflight.issuerCid,
    preflight.authenticationCid, preflight.issuerKind,
    preflight.decision, preflight.requestScope, preflight.keys,
    preflight.maxMembers, preflight.maxRows,
    preflight.maxFootprintWork, preflight.maxWork,
  ));
  if (noReadyRows) {
    return Object.freeze({status: 'applied', dispatched: 0,
      frontier: initialFrontier, subjectCid});
  }
  const authorized = await authorizeEffectCommit(commit, subjectCid, signal);
  const last = authorized.decisions.at(-1);
  if (last?.action === 'waiting') {
    return Object.freeze({status: 'waiting', dispatched: 0, subjectCid,
      checkpoint: last.checkpoint, authorization: authorized.decisions});
  }
  if (last?.action !== 'dispatch') {
    throw Object.assign(new ExecutionAuthorizationError(last), {
      subjectCid, resume: authorized.claim,
    });
  }
  const identity = effectSetApplyIdentity(control, preflight.requestScope,
    subjectCid);
  let entered;
  let dispatched = 0;
  for (;;) {
    signal?.throwIfAborted();
    const frontier = ledger.frontierFromCapturedHeads(
      capturedInputs, ownedMembers, maxFrontierWork);
    if (control.setFrontierReadyCount(frontier) === 0) {
      return Object.freeze({status: 'applied', dispatched, frontier,
        subjectCid, identity, authorization: authorized.decisions,
        resume: authorized.claim,
        admission: entered});
    }
    if (dispatched === totalRows) fail('EffectApplyDidNotAdvance');
    const memberIndex = control.setFrontierReadyMember(frontier, 0);
    const rowIndex = control.setFrontierReadyRow(frontier, 0);
    const claim = ownedMembers[memberIndex]?.claims[rowIndex];
    if (claim === undefined) fail('InvalidCapturedEffectFrontier');
    // No await between the admission entry and the first send.
    if (authorized.admission !== undefined && entered === undefined) {
      entered = enterResumedAdmission(authorized.admission, identity);
    }
    await dispatchRow(Object.freeze({memberIndex, rowIndex, claim}));
    dispatched++;
    const next = ledger.frontierFromCapturedHeads(
      capturedInputs, ownedMembers, maxFrontierWork);
    for (let index = 0; index < control.setFrontierReadyCount(next);
      index++) {
      if (control.setFrontierReadyMember(next, index) === memberIndex &&
          control.setFrontierReadyRow(next, index) === rowIndex) {
        fail('EffectApplyDidNotAdvance');
      }
    }
  }
}
