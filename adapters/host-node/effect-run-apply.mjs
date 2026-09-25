import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {confirmCompletedEffectfulApplySources} from
  '../host-common/completed-run-publication.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

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
  maxFrontierWork, dispatchRow, signal}) => {
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
    await dispatchRow(Object.freeze({memberIndex, rowIndex, claim}));
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
  dispatchRow,
  maxFrontierWork, signal, refreshPreflight,
}) {
  if (!moon || !capturedInputs || !suppliedPreflight || !ledger ||
      typeof ledger.frontierFromCapturedHeads !== 'function' ||
      typeof ledger.prepareCapturedSetIntents !== 'function' ||
      !Array.isArray(members) || members.length === 0 ||
      typeof dispatchRow !== 'function' ||
      typeof refreshPreflight !== 'function' ||
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
  const current = noReadyRows ? preflight :
    ownPreflight(await refreshPreflight({signal, preflight}));
  if (current.requirePartialApplication !== undefined &&
      typeof current.requirePartialApplication !== 'boolean') {
    fail('InvalidCapturedEffectApply');
  }
  const requirePartialApplication =
    current.requirePartialApplication === true;
  signal?.throwIfAborted();
  checked(moon.clientProgramCheckEffectApplyPreflight(
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
    return Object.freeze({dispatched: 0, frontier: initialFrontier});
  }
  ledger.prepareCapturedSetIntents(
    capturedInputs, ownedMembers, maxFrontierWork);
  return driveAdmittedFrontier({control, members: ownedMembers,
    maxFrontierWork, dispatchRow, signal,
    frontier: (members, maxWork) => ledger.frontierFromCapturedHeads(
      capturedInputs, members, maxWork),
  });
}

// Continue only exact durable intents owned by the recovered captured Run.
// Recovery confirms physical source holdings, refreshes current observations,
// and uses the same MoonBit frontier and dispatch loop as the live path. A
// prepared Ledger head alone is never permission for another physical call.
export async function applyRecoveredEffectSet({
  moon, store, publicationControl, computation, preview, ledger,
  requestScope, programId, nodeId, maxRows, maxFrontierWork,
  maxRecoveryWork, keyLimits,
  reconcileStoredResponses, refreshPreflight, dispatchRow, signal,
}) {
  if (!moon || !store || !publicationControl || !computation || !preview ||
      typeof ledger?.recoverClaimFacts !== 'function' ||
      typeof ledger?.frontierFromDurableHeads !== 'function' ||
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
      typeof dispatchRow !== 'function') {
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
  checked(moon.clientProgramCheckRecoveredEffectApplySemantics(
    admittedPreview, preflight.sources, preflight.contracts,
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
  const result = await driveAdmittedFrontier({control,
    members: recovered.members, maxFrontierWork, dispatchRow, signal,
    frontier: (members, maxWork) => ledger.frontierFromDurableHeads(
      admittedPreview, members, maxWork),
  });
  return Object.freeze({...result, members: recovered.members});
}
