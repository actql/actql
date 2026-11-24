export type EffectDispatchClaim = Readonly<{
  scope: unknown; locator: unknown; key: unknown; basis: unknown;
  intentFingerprintCid?: string; canonicalRequestCid?: string;
}>;
type ClaimInput = Partial<EffectDispatchClaim> | null | undefined;
type Claim = ReturnType<typeof snapshotEffectDispatchClaim>;
type Awaitable<Value> = Value | PromiseLike<Value>;
type Observation = Readonly<{useCid?: unknown; statusCode?: unknown; body?: unknown}>;
type Physical = Readonly<{observation?: Observation}>;
type RecordedObservation = Readonly<{
  credentialUseCid: string; statusCode: number; responseBytes: Uint8Array;
}>;
type Ownership<Dispatching> = Readonly<{claimed: true; dispatching: Dispatching}> | Readonly<{claimed: false}>;
type LedgerFlight<Dispatching, Claims> = Readonly<{
  beginPhysicalFlight(dispatching: Dispatching, claims: Claims): () => void;
}>;
type SingleLedger<Response> = LedgerFlight<unknown, Claim> & Readonly<{
  claimDispatch(claim: Claim): Ownership<unknown>;
  recordResponse(observation: RecordedObservation & Pick<Claim, 'scope' | 'locator' | 'key'> &
    Readonly<{dispatching: unknown; canonicalRequestCid: string}>): Readonly<{response: Response}>;
}>;
type BatchOwner = Ownership<readonly unknown[]>;
type BatchLedger<Response, Recorded> = LedgerFlight<readonly unknown[], readonly Claim[]> & Readonly<{
  claimDispatchBatch(claims: readonly Claim[]): BatchOwner;
  recordBatchResponse(observation: RecordedObservation & Readonly<{
    claims: readonly Claim[]; ownership: Extract<BatchOwner, {claimed: true}>;
  }>): Recorded;
  readClaimedBatchResponse?(claims: readonly Claim[]): Response | undefined;
}>;
type ExecuteOptions<Original extends Physical, Response, Projected> = Readonly<{
  requestCid: string; execute(): Awaitable<Original>;
  projectStored?: (stored: Response) => Projected;
}>;
type CaptureOptions<Original extends Physical, Response, Projected> =
  ExecuteOptions<Original, Response, Projected> & Readonly<{ledger: SingleLedger<Response>; claim: ClaimInput}>;
type CaptureBatchOptions<Original extends Physical, Response, Projected, Recorded> =
  ExecuteOptions<Original, Response, Projected> & Readonly<{
    ledger: BatchLedger<Response, Recorded>; claims: readonly ClaimInput[];
  }>;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

// Own the JS wrapper across the physical await. The MoonBit values remain
// opaque, exact objects; cloning or serializing them would lose their owner.
export const snapshotEffectDispatchClaim = (claim: ClaimInput) => Object.freeze({
  scope: claim?.scope,
  locator: claim?.locator,
  key: claim?.key,
  basis: claim?.basis,
  intentFingerprintCid: claim?.intentFingerprintCid,
  canonicalRequestCid: claim?.canonicalRequestCid,
});

export const snapshotEffectDispatchClaims = (claims: readonly ClaimInput[]) => Object.freeze(
  claims.map(snapshotEffectDispatchClaim));

// The MoonBit ledger decision and Store CAS establish physical send ownership.
// This bridge records only the bounded Site observation. It does not classify
// an Effect outcome, issue a receipt, or authorize a replay after uncertainty.
export async function captureClaimedEffectResponse<Original extends Physical, Response, Projected>({
  ledger,
  claim,
  requestCid,
  execute,
  projectStored,
}: CaptureOptions<Original, Response, Projected>) {
  const ownedClaim = snapshotEffectDispatchClaim(claim);
  if (!ledger || typeof ledger.claimDispatch !== 'function' ||
      typeof ledger.recordResponse !== 'function' ||
      typeof ledger.beginPhysicalFlight !== 'function' || !claim ||
      typeof requestCid !== 'string' ||
      requestCid !== ownedClaim.canonicalRequestCid ||
      typeof execute !== 'function' ||
      (projectStored !== undefined && typeof projectStored !== 'function')) {
    fail('InvalidEffectPhysicalDispatch');
  }
  const ownership = ledger.claimDispatch(ownedClaim);
  if (!ownership.claimed) {
    return Object.freeze({claimed: false, ownership});
  }
  // Any throw after the durable claim leaves a possible-dispatch fact. An
  // exact retry must reconcile it; it must never invoke execute again.
  const endFlight = ledger.beginPhysicalFlight(ownership.dispatching,
    ownedClaim);
  let physical;
  try { physical = await execute(); }
  finally { endFlight(); }
  const observation = physical?.observation;
  if (typeof observation?.useCid !== 'string' ||
      !Number.isSafeInteger(observation.statusCode) ||
      !(observation.body instanceof Uint8Array)) {
    fail('EffectPhysicalObservationMissing');
  }
  const stored = ledger.recordResponse({
    dispatching: ownership.dispatching,
    scope: ownedClaim.scope,
    locator: ownedClaim.locator,
    key: ownedClaim.key,
    canonicalRequestCid: ownedClaim.canonicalRequestCid,
    credentialUseCid: observation.useCid,
    statusCode: observation.statusCode as number,
    responseBytes: observation.body,
  });
  // Provider interpretation follows durable custody of the exact raw bytes.
  // A projection failure leaves those bytes available for read-only recovery.
  const projected = projectStored === undefined
    ? physical : projectStored(stored.response);
  return Object.freeze({claimed: true, ownership, physical: projected,
    response: stored.response});
}

// A collection is one physical send with several logical row owners. Every
// row must be durably dispatching before execute; the observed HTTP response
// is then committed once with references for all rows. This bridge does not
// interpret member or row outcomes.
export async function captureClaimedEffectCollectionResponse<Original extends Physical, Response, Projected, Recorded>({
  ledger,
  claims,
  requestCid,
  execute,
  projectStored,
}: CaptureBatchOptions<Original, Response, Projected, Recorded>) {
  const ownedClaims = Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims) : undefined;
  if (!ledger || typeof ledger.claimDispatchBatch !== 'function' ||
      typeof ledger.recordBatchResponse !== 'function' ||
      typeof ledger.beginPhysicalFlight !== 'function' ||
      !ownedClaims || ownedClaims.length === 0 ||
      typeof requestCid !== 'string' ||
      ownedClaims.some(claim => claim.canonicalRequestCid !== requestCid) ||
      typeof execute !== 'function' ||
      (projectStored !== undefined &&
        (typeof projectStored !== 'function' ||
          typeof ledger.readClaimedBatchResponse !== 'function'))) {
    fail('InvalidEffectPhysicalDispatch');
  }
  const ownership = ledger.claimDispatchBatch(ownedClaims);
  if (!ownership.claimed) {
    return Object.freeze({claimed: false, ownership});
  }
  // A thrown/unknown physical result cannot authorize another send. The
  // durable batch claim remains available for reconciliation after restart.
  const endFlight = ledger.beginPhysicalFlight(ownership.dispatching,
    ownedClaims);
  let physical;
  try { physical = await execute(); }
  finally { endFlight(); }
  const observation = physical?.observation;
  if (typeof observation?.useCid !== 'string' ||
      !Number.isSafeInteger(observation.statusCode) ||
      !(observation.body instanceof Uint8Array)) {
    fail('EffectPhysicalObservationMissing');
  }
  const stored = ledger.recordBatchResponse({
    claims: ownedClaims,
    ownership,
    credentialUseCid: observation.useCid,
    statusCode: observation.statusCode as number,
    responseBytes: observation.body,
  });
  const response = projectStored === undefined
    ? undefined : ledger.readClaimedBatchResponse!(ownedClaims);
  if (projectStored !== undefined && response === undefined) {
    fail('EffectPhysicalResponseMissingAfterStore');
  }
  const projected = projectStored === undefined
    ? physical : projectStored(response!);
  return Object.freeze({claimed: true, ownership, physical: projected,
    response: stored});
}
