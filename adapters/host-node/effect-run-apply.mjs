import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {confirmCompletedEffectfulApplySources} from
  '../host-common/completed-run-publication.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

const preflightRejections = new WeakSet();

export function isEffectApplyPreflightRejection(error) {
  return error !== null && typeof error === 'object' &&
    preflightRejections.has(error);
}

// A checked preflight rejection is a definitive refusal of this Preview.
// Provider observation failures occur before this boundary and remain
// retryable; they must not be converted into a terminal Run result.
function checkedPreflight(result) {
  if (result?.$tag === 0) {
    const error = Object.assign(new Error('MoonBitHostFailure', {
      cause: result._0}), {code: 'MoonBitHostFailure'});
    preflightRejections.add(error);
    throw error;
  }
  return checked(result);
}

const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 512;

const validDispatch = (dispatchRow, bindDispatch) =>
  (typeof dispatchRow === 'function' && bindDispatch === undefined) ||
  (dispatchRow === undefined && typeof bindDispatch === 'function');

// Bind physical requests to the exact claims retained by this apply owner.
// Recovery creates new opaque claims; callers must not substitute claims from
// an earlier ledger read. Binding is synchronous and performs no physical I/O.
// `decisions` are this claim generation's Effect commit dispatch decisions,
// one per distinct Host tuple in member order of first appearance; a
// provider binds each physical write grant to its member's decision and
// never to a decision of another tuple or an earlier generation.
function bindOwnedDispatch(dispatchRow, bindDispatch, members, subjectCid,
  signal, decisions) {
  const dispatch = bindDispatch === undefined ? dispatchRow :
    bindDispatch(Object.freeze({members, subjectCid, signal, decisions}));
  if (typeof dispatch !== 'function') fail('InvalidEffectDispatchBinding');
  return dispatch;
}

// Account operation of an Effect commit in the Read/Write/Effect operation
// classification. The boundary kind (effect_commit) and the sealed Set
// Preview stay in the decision subject.
const EFFECT_OPERATION = 'effect';
const READ_OPERATION = 'read';

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

// Authorize the credentialed target reads of the guard refresh: one
// acquisition decision per distinct Effect target, bound to the sealed Set
// Preview. Only dispatch continues; nothing is read otherwise.
async function authorizeTargetReads(authorization, subjectCid, signal) {
  const tuples = new Map(authorization.scopes.map(scope => [
    JSON.stringify([scope.connection, scope.resource]),
    Object.freeze({connection: scope.connection, resource: scope.resource,
      operation: READ_OPERATION})]));
  const decisions = [];
  for (const tuple of tuples.values()) {
    signal?.throwIfAborted();
    const decision = await authorization.gate.authorize('acquisition', tuple,
      {subjectCid, signal});
    decisions.push(decision);
    if (decision.action !== 'dispatch') break;
  }
  return Object.freeze(decisions);
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
        {subjectCid, signal, resumption,
          setApproval: decisions.find(previous =>
            previous.basis === 'resumed' &&
            previous.admission !== undefined)});
    decisions.push(decision);
    if (decision.action !== 'dispatch') break;
  }
  // Every resumed dispatch, account allow or delegated permit, carries the
  // journal-authoritative admission; it is entered once, synchronously,
  // immediately before the first protected send of this claim generation.
  // A resumed commit without one sends nothing.
  const admission = decisions.find(decision =>
    decision.admission !== undefined)?.admission;
  if (resumption !== undefined && admission === undefined &&
      decisions.length > 0 &&
      decisions.every(decision => decision.action === 'dispatch')) {
    throw Object.assign(new Error('EffectApplyResumeAdmissionUnavailable'),
      {code: 'EffectApplyResumeAdmissionUnavailable'});
  }
  return Object.freeze({subjectCid, decisions: Object.freeze(decisions),
    claim: resumption?.claim.claim, admission});
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

const ownPreflight = (supplied, requireProofs = true) => {
  if (!supplied) fail('InvalidCapturedEffectApply');
  const preflight = {...supplied};
  const names = ['sources', 'contracts', 'capabilities',
    'authorities', 'observedRows', 'guardVersions', 'routes'];
  if (requireProofs) names.unshift('proofs');
  for (const name of names) {
    if (!Array.isArray(preflight[name])) fail('InvalidCapturedEffectApply');
    preflight[name] = Object.freeze([...preflight[name]]);
  }
  if (!Array.isArray(preflight.keys) ||
      !preflight.keys.every(Array.isArray)) {
    fail('InvalidCapturedEffectApply');
  }
  preflight.keys = Object.freeze(preflight.keys.map(keys =>
    Object.freeze([...keys])));
  if (!requireProofs) preflight.proofs = Object.freeze([]);
  return Object.freeze(preflight);
};

const driveAdmittedFrontier = async ({control, frontier, members,
  maxFrontierWork, dispatchRow, signal, beforeDispatch,
  currentPreflight}) => {
  const totalRows = members.reduce((sum, member) =>
    sum + member.claims.length, 0);
  let dispatched = 0;
  for (;;) {
    signal?.throwIfAborted();
    const current = frontier(members, maxFrontierWork);
    if (control.setFrontierReadyCount(current) === 0) {
      return Object.freeze({dispatched, frontier: current});
    }
    if (dispatched === totalRows) fail('EffectApplyDidNotAdvance');
    const memberIndex = control.setFrontierReadyMember(current, 0);
    const rowIndex = control.setFrontierReadyRow(current, 0);
    const claim = members[memberIndex]?.claims[rowIndex];
    if (claim === undefined) fail('InvalidCapturedEffectFrontier');
    beforeDispatch?.();
    // Keep physical dispatch bound to this invocation's refreshed facts.
    // The callback cannot swap in a later refresh from another apply flight.
    await dispatchRow(Object.freeze({memberIndex, rowIndex, claim,
      currentPreflight}));
    dispatched++;
    const next = frontier(members, maxFrontierWork);
    for (let index = 0; index < control.setFrontierReadyCount(next);
      index++) {
      if (control.setFrontierReadyMember(next, index) === memberIndex &&
          control.setFrontierReadyRow(next, index) === rowIndex) {
        fail('EffectApplyDidNotAdvance');
      }
    }
  }
};

// Drive only the rows admitted by the retained MoonBit Effect frontier.
// Before any ready row sends, refresh the complete current-use preflight, not
// only target guards. The Site operation owns credential use and physical
// observation; this Host never infers an outcome from its return value.
export async function applyCapturedEffectSet({
  moon, capturedInputs, preflight: suppliedPreflight, ledger, members,
  dispatchRow, bindDispatch,
  maxFrontierWork, signal, refreshPreflight, authorization,
}) {
  if (!moon || !capturedInputs || !suppliedPreflight || !ledger ||
      typeof ledger.frontierFromCapturedHeads !== 'function' ||
      typeof ledger.prepareCapturedSetIntents !== 'function' ||
      !Array.isArray(members) || members.length === 0 ||
      !validDispatch(dispatchRow, bindDispatch) ||
      (refreshPreflight !== undefined &&
        typeof refreshPreflight !== 'function') ||
      !Number.isSafeInteger(maxFrontierWork) || maxFrontierWork < 1) {
    fail('InvalidCapturedEffectApply');
  }
  const preflight = ownPreflight(suppliedPreflight);
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
  // Risk acceptance is Host policy, not a member-count floor: a body is
  // passed only when the Host holds one, and `partial_application_accepted`
  // is required only when the Host's delegated-decision policy declares it.
  signal?.throwIfAborted();
  const control = runtimeCore(moon).effectApplicationControl;
  const initialFrontier = ledger.frontierFromCapturedHeads(
    capturedInputs, ownedMembers, maxFrontierWork);
  const noReadyRows = control.setFrontierReadyCount(initialFrontier) === 0;
  // Historical progress needs no new mutation authority when every row is
  // already terminal or uncertain. Evidence viewing remains separately gated.
  if (!noReadyRows && typeof refreshPreflight !== 'function') {
    fail('InvalidCapturedEffectApply');
  }
  const commit = noReadyRows ? undefined :
    checkedAuthorization(authorization, ownedMembers.length);
  const subjectCid = sealedSubject(moon, capturedInputs, ownedMembers.length);
  let readDecisions = Object.freeze([]);
  if (!noReadyRows) {
    readDecisions = await authorizeTargetReads(commit, subjectCid, signal);
    const read = readDecisions.at(-1);
    if (read?.action === 'waiting') {
      return Object.freeze({status: 'waiting', dispatched: 0, subjectCid,
        checkpoint: read.checkpoint, authorization: readDecisions});
    }
    if (read?.action !== 'dispatch') {
      throw Object.assign(new ExecutionAuthorizationError(read),
        {subjectCid});
    }
  }
  const refreshed = noReadyRows ? undefined :
    await refreshPreflight({signal, preflight});
  const current = noReadyRows ? preflight : ownPreflight(refreshed);
  if (current.requirePartialApplication !== undefined &&
      typeof current.requirePartialApplication !== 'boolean') {
    fail('InvalidCapturedEffectApply');
  }
  const requirePartialApplication =
    current.requirePartialApplication === true;
  signal?.throwIfAborted();
  checkedPreflight(moon.clientProgramCheckEffectApplyPreflight(
    capturedInputs, current.proofs, current.sources,
    current.contracts, current.capabilities, current.authorities,
    current.observedRows, current.guardVersions,
    current.routes,
    current.risk ?? undefined, requirePartialApplication,
    current.reviewProjectionCid,
    current.authorityScopeCid, current.policyCid,
    current.validityCid, current.issuerCid,
    current.authenticationCid, current.issuerKind,
    current.decision, current.requestScope, current.keys,
    current.maxMembers, current.maxRows,
    current.maxFootprintWork, current.maxWork,
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
  const identity = effectSetApplyIdentity(control, current.requestScope,
    subjectCid);
  let entered;
  let prepared = false;
  const dispatch = bindOwnedDispatch(dispatchRow, bindDispatch,
    ownedMembers, subjectCid, signal, authorized.decisions);
  const result = await driveAdmittedFrontier({control, members: ownedMembers,
    maxFrontierWork, dispatchRow: dispatch, signal,
    currentPreflight: refreshed,
    beforeDispatch: () => {
      if (authorized.admission !== undefined && entered === undefined) {
        entered = enterResumedAdmission(authorized.admission, identity);
      }
      if (!prepared) {
        ledger.prepareCapturedSetIntents(
          capturedInputs, ownedMembers, maxFrontierWork);
        prepared = true;
      }
    },
    frontier: (members, maxWork) => ledger.frontierFromCapturedHeads(
      capturedInputs, members, maxWork),
  });
  return Object.freeze({status: 'applied', ...result, subjectCid, identity,
    authorization: authorized.decisions,
    readAuthorization: readDecisions, resume: authorized.claim,
    admission: entered});
}

// Continue only exact durable intents owned by the recovered captured Run.
// Recovery confirms physical source holdings, reauthorizes target reads and
// the Effect commit, refreshes current observations, and uses the same
// MoonBit frontier and dispatch loop as the live path. A prepared Ledger
// head alone is never permission for another physical call.
export async function applyRecoveredEffectSet({
  moon, store, publicationControl, computation, preview, ledger,
  requestScope, programId, nodeId, maxRows, maxFrontierWork,
  maxRecoveryWork, keyLimits,
  reconcileStoredResponses, refreshPreflight, dispatchRow, bindDispatch, signal,
  authorization,
}) {
  if (!moon || !store || !publicationControl || !computation || !preview ||
      typeof ledger?.recoverClaimFacts !== 'function' ||
      typeof ledger?.frontierFromDurableHeads !== 'function' ||
      typeof ledger?.recoveredTargetGuards !== 'function' ||
      !requestScope || typeof programId !== 'string' ||
      typeof nodeId !== 'string' ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 ||
      !Number.isSafeInteger(maxFrontierWork) || maxFrontierWork < 1 ||
      !Number.isSafeInteger(maxRecoveryWork) || maxRecoveryWork < 1 ||
      !Number.isSafeInteger(keyLimits?.maxBytes) ||
      !Number.isSafeInteger(keyLimits.maxNodes) ||
      !Number.isSafeInteger(keyLimits.maxDepth) ||
      !Number.isSafeInteger(keyLimits.maxWork) ||
      keyLimits.maxBytes < 1 || keyLimits.maxNodes < 1 ||
      keyLimits.maxDepth < 1 || keyLimits.maxWork < 1 ||
      (reconcileStoredResponses !== undefined &&
        typeof reconcileStoredResponses !== 'function') ||
      typeof refreshPreflight !== 'function' ||
      !validDispatch(dispatchRow, bindDispatch)) {
    fail('InvalidRecoveredEffectApply');
  }
  signal?.throwIfAborted();
  const control = runtimeCore(moon).effectApplicationControl;
  const admittedPreview = publicationControl
    .effectComputationPreviewLedgerIdentity(preview);
  let recovered = ledger.recoverClaimFacts({preview: admittedPreview,
    scope: requestScope, programId, nodeId, maxRows,
    maxWork: maxRecoveryWork});
  await confirmCompletedEffectfulApplySources({store,
    control: publicationControl, computation, preview});
  if (reconcileStoredResponses !== undefined) {
    await reconcileStoredResponses(Object.freeze({
      members: recovered.members, preview: admittedPreview, signal,
    }));
    recovered = ledger.recoverClaimFacts({preview: admittedPreview,
      scope: requestScope, programId, nodeId, maxRows,
      maxWork: maxRecoveryWork});
  }
  const initial = recovered.frontier;
  if (control.setFrontierReadyCount(initial) === 0) {
    return Object.freeze({dispatched: 0, frontier: initial});
  }
  const commit = checkedAuthorization(authorization, recovered.members.length);
  const subjectCid = publicationControl.effectComputationPreviewSemanticCid(
    preview);
  const readDecisions = await authorizeTargetReads(commit, subjectCid, signal);
  const read = readDecisions.at(-1);
  if (read?.action === 'waiting') {
    return Object.freeze({status: 'waiting', dispatched: 0, subjectCid,
      checkpoint: read.checkpoint, authorization: readDecisions});
  }
  if (read?.action !== 'dispatch') {
    throw Object.assign(new ExecutionAuthorizationError(read), {subjectCid});
  }
  const current = await refreshPreflight({signal});
  const keys = control.recoveredPreviewKeys(
    admittedPreview, requestScope, current?.maxMembers,
    current?.maxRows, keyLimits.maxWork, keyLimits.maxBytes,
    keyLimits.maxNodes, keyLimits.maxDepth);
  const preflight = ownPreflight({...current, keys}, false);
  // A fresh authorization cannot silently change the logical request that
  // owns the already prepared intents.
  if (control.logicalRequestScopeCid(preflight.requestScope) !==
      control.logicalRequestScopeCid(requestScope)) {
    fail('EffectRecoveredRequestScopeChanged');
  }
  if (preflight.requirePartialApplication !== undefined &&
      typeof preflight.requirePartialApplication !== 'boolean') {
    fail('InvalidRecoveredEffectApply');
  }
  signal?.throwIfAborted();
  checkedPreflight(moon.clientProgramCheckRecoveredEffectApplySemantics(
    admittedPreview,
    ledger.recoveredTargetGuards(admittedPreview, recovered.members,
      maxRecoveryWork),
    preflight.sources, preflight.contracts,
    preflight.capabilities, preflight.authorities,
    preflight.observedRows, preflight.guardVersions, preflight.routes,
    preflight.risk ?? undefined,
    preflight.requirePartialApplication === true,
    preflight.reviewProjectionCid,
    preflight.authorityScopeCid, preflight.policyCid,
    preflight.validityCid, preflight.issuerCid,
    preflight.authenticationCid, preflight.issuerKind,
    preflight.decision, preflight.requestScope, preflight.keys,
    preflight.maxMembers, preflight.maxRows,
    preflight.maxFootprintWork, preflight.maxWork,
  ));
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
  const identity = effectSetApplyIdentity(control, requestScope, subjectCid);
  let entered;
  const dispatch = bindOwnedDispatch(dispatchRow, bindDispatch,
    recovered.members, subjectCid, signal, authorized.decisions);
  const result = await driveAdmittedFrontier({control,
    members: recovered.members, maxFrontierWork, dispatchRow: dispatch, signal,
    currentPreflight: current,
    beforeDispatch: () => {
      if (authorized.admission !== undefined && entered === undefined) {
        entered = enterResumedAdmission(authorized.admission, identity);
      }
    },
    frontier: (members, maxWork) => ledger.frontierFromDurableHeads(
      admittedPreview, members, maxWork),
  });
  return Object.freeze({...result, members: recovered.members, subjectCid,
    identity, authorization: authorized.decisions,
    readAuthorization: readDecisions, resume: authorized.claim,
    admission: entered});
}
