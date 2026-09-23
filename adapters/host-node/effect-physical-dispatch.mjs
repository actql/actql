const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// The MoonBit ledger decision and Store CAS establish physical send ownership.
// This bridge records only the bounded Site observation. It does not classify
// an Effect outcome, issue a receipt, or authorize a replay after uncertainty.
export async function captureClaimedEffectResponse({
  ledger,
  claim,
  requestCid,
  execute,
}) {
  if (!ledger || typeof ledger.claimDispatch !== 'function' ||
      typeof ledger.recordResponse !== 'function' || !claim ||
      typeof requestCid !== 'string' ||
      requestCid !== claim.canonicalRequestCid ||
      typeof execute !== 'function') {
    fail('InvalidEffectPhysicalDispatch');
  }
  const ownership = ledger.claimDispatch(claim);
  if (!ownership.claimed) {
    return Object.freeze({claimed: false, ownership});
  }
  // Any throw after the durable claim leaves a possible-dispatch fact. An
  // exact retry must reconcile it; it must never invoke execute again.
  const physical = await execute();
  const observation = physical?.observation;
  if (typeof observation?.useCid !== 'string' ||
      !Number.isSafeInteger(observation.statusCode) ||
      !(observation.body instanceof Uint8Array)) {
    fail('EffectPhysicalObservationMissing');
  }
  const stored = ledger.recordResponse({
    dispatching: ownership.dispatching,
    scope: claim.scope,
    locator: claim.locator,
    key: claim.key,
    canonicalRequestCid: claim.canonicalRequestCid,
    credentialUseCid: observation.useCid,
    statusCode: observation.statusCode,
    responseBytes: observation.body,
  });
  return Object.freeze({claimed: true, ownership, physical,
    response: stored.response});
}
