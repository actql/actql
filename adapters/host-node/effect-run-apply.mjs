import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Drive only the rows admitted by the retained MoonBit Effect frontier.
// The Site operation owns current credential use and physical observation;
// this Host boundary never infers a row outcome from its return value.
export async function applyCapturedEffectSet({
  moon, capturedInputs, preflight: suppliedPreflight, ledger, members,
  dispatchRow,
  maxFrontierWork, signal, refreshGuardObservations,
}) {
  if (!moon || !capturedInputs || !suppliedPreflight || !ledger ||
      typeof ledger.frontierFromCapturedHeads !== 'function' ||
      typeof ledger.prepareCapturedSetIntents !== 'function' ||
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
  signal?.throwIfAborted();
  const control = runtimeCore(moon).effectApplicationControl;
  const initialFrontier = ledger.frontierFromCapturedHeads(
    capturedInputs, ownedMembers, maxFrontierWork);
  const noReadyRows = control.setFrontierReadyCount(initialFrontier) === 0;
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
    preflight.risk, preflight.reviewProjectionCid,
    preflight.authorityScopeCid, preflight.policyCid,
    preflight.validityCid, preflight.issuerCid,
    preflight.authenticationCid, preflight.issuerKind,
    preflight.decision, preflight.requestScope, preflight.keys,
    preflight.maxMembers, preflight.maxRows,
    preflight.maxFootprintWork, preflight.maxWork,
  ));
  if (noReadyRows) {
    return Object.freeze({dispatched: 0, frontier: initialFrontier});
  }
  ledger.prepareCapturedSetIntents(
    capturedInputs, ownedMembers, maxFrontierWork);
  let dispatched = 0;
  for (;;) {
    signal?.throwIfAborted();
    const frontier = ledger.frontierFromCapturedHeads(
      capturedInputs, ownedMembers, maxFrontierWork);
    if (control.setFrontierReadyCount(frontier) === 0) {
      return Object.freeze({dispatched, frontier});
    }
    if (dispatched === totalRows) fail('EffectApplyDidNotAdvance');
    const memberIndex = control.setFrontierReadyMember(frontier, 0);
    const rowIndex = control.setFrontierReadyRow(frontier, 0);
    const claim = ownedMembers[memberIndex]?.claims[rowIndex];
    if (claim === undefined) fail('InvalidCapturedEffectFrontier');
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
