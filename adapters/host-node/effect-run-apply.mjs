import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Drive only the rows admitted by the retained MoonBit Effect frontier.
// The Site operation owns current credential use and physical observation;
// this Host boundary never infers a row outcome from its return value.
export async function applyCapturedEffectSet({
  moon, capturedInputs, preflight, ledger, members, dispatchRow,
  maxFrontierWork, signal,
}) {
  if (!moon || !capturedInputs || !preflight || !ledger ||
      typeof ledger.frontierFromCapturedHeads !== 'function' ||
      !Array.isArray(members) || members.length === 0 ||
      typeof dispatchRow !== 'function' ||
      !Number.isSafeInteger(maxFrontierWork) || maxFrontierWork < 1) {
    fail('InvalidCapturedEffectApply');
  }
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
  checked(moon.clientProgramCheckEffectApplyPreflight(
    capturedInputs, preflight.proofs, preflight.sources,
    preflight.contracts, preflight.capabilities, preflight.authorities,
    preflight.observedRows, preflight.guardVersions, preflight.routes,
    preflight.risk, preflight.reviewProjectionCid,
    preflight.authorityScopeCid, preflight.policyCid,
    preflight.validityCid, preflight.issuerCid,
    preflight.authenticationCid, preflight.issuerKind,
    preflight.decision, preflight.requestScope, preflight.keys,
    preflight.maxMembers, preflight.maxRows,
    preflight.maxFootprintWork, preflight.maxWork,
  ));
  const control = runtimeCore(moon).effectApplicationControl;
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
