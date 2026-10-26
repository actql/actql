/** Admit existing canonical Checkpoint bytes through the common Owner.
 * Returns its JSON success/refusal envelope; performs no physical I/O. */
export declare function checkpointAdmit(wire: string): string;

/** Confirm exact persisted bytes before projecting waiting state.
 * The Host must separately commit its Run transition before publishing this
 * projection. A projection grants neither approval nor permission to resume. */
export declare function checkpointWaitingState(sealedWire: string,
  storedWire: string, updatedAt: string, declaredResultsJson: string): string;

/** Seal bounded request facts; never asserts that the Host persisted them. */
export declare function checkpointSealBody(bodyWire: string): string;
export declare function checkpointLifecycleState(runId: string, status: string,
  updatedAt: string, declaredResultsJson: string): string;
/** Project rejection/expiry/cancellation without dispatch from common Owner facts.
 * Unknown Effect outcomes remain needs_reconciliation, never completed cleanup. */
export declare function waitingExitState(runId: string, updatedAt: string,
  declaredResultsJson: string, unknownEffectsJson: string): string;
/** Existing failed-revalidation projection. Current recorded outcomes and the
 * atomic Run/intent commit remain with the receiving Run owner. */
export declare function revalidationFailedState(runId: string, updatedAt: string,
  declaredResultsJson: string, unknownEffectsJson: string): string;
export declare function checkpointExpiredAt(checkpointWire: string, now: string): string;
export declare function runStateAdmit(wire: string): string;
export declare function runTransitionAllowed(from: string, to: string): boolean;
export declare function resumeCompletionAllowed(to: string): boolean;
export declare function effectSettlementCompletionAllowed(to: string): boolean;

/** Preimage for reviewer verification with Host-trusted keys, not submitted keys. */
export declare function resolutionProofPreimage(resolutionWire: string): string;
/** The trusted Host authenticates signatures/current authority before admission.
 * Returned attestation facts are not a persisted Resolution or resume permit. */
export declare function resolutionAdmit(checkpointWire: string,
  resolutionWire: string, evidenceWire: string, authenticationJson: string,
  authoritiesJson: string, verifiedAt: string): string;
/** The Host signs the admitted preimage and supplies closure/unknown facts read
 * inside its transaction. It must atomically persist the decision and resume
 * intent with the Run transition; the returned JSON performs no storage I/O. */
export declare function resolutionDecide(checkpointWire: string,
  resolutionWire: string, evidenceWire: string, authenticationJson: string,
  authoritiesJson: string, verifiedAt: string, hostKeyId: string,
  signature: string, closureState: string, closureResolutionCid: string,
  unknownEffectsJson: string): string;
export declare function verifiedAttestationPreimage(verifiedWire: string): string;
/** Original approval claims/lifetime; current Host/provider authority is separate. */
export declare function resumedApprovalAt(verifiedWire: string, at: string): string;
/** Existing Effect resume/settlement decision. Persist the claimed generation
 * and recheck the fence before a protected operation; unknown is not replay. */
export declare function effectResumeClaimDecide(intentJson: string,
  claimant: string, nowMs: number, leaseMs: number, boundJson: string,
  currentJson: string, settlementOnly: boolean): string;
export declare function resumeFenceDecide(intentJson: string, claimant: string,
  generation: number, nowMs: number): string;

/** Bounded DATA from the existing Run owner. Not a Run, authority or ACK. */
declare const runStateObservationBrand: unique symbol;
export interface RunStateObservation {
  readonly [runStateObservationBrand]: true;
}
/** Required DATA-projection bounds; they do not replace original Host transport
 * maxima, same-Ledger funding, current authorization or confirmed durable CAS. */
export interface RunStateObservationLimits {
  readonly maxWireBytes: number;
  readonly maxNodes: number;
  readonly maxDepth: number;
}
/** Prepare only: the Host supplies the actual counter from that original Run
 * row. A missing intermediate wire revision is completed by Core, not by a
 * fixture/default. The Host must confirm its durable CAS before disclosure. */
export declare function prepareRunStateObservation(wire: string, runId: string,
  currentRevision: number, limits: RunStateObservationLimits): RunStateObservation;
/** Equivalence excludes observation clocks; this key is not a grant or CID. */
export declare function runStateObservationKey(value: RunStateObservation): string;
/** Use the prior key/counter read from the very same original durable Run row. */
export declare function nextRunStateRevision(value: RunStateObservation,
  priorKey: string | null, currentRevision: number): number;
/** DATA only; confirmed COMMIT/current permission remain the physical Owner's. */
export declare function runStateObservationWire(value: RunStateObservation,
  revision: number): string;
/** Same Common stable/since predicate as the normal Node Host; no polling or
 * permission. Future/invalid since and missing revision remain typed refusal. */
export declare function runWaitDecision(wire: string, since: number | null,
  limits: RunStateObservationLimits): 'ready' | 'pending';
