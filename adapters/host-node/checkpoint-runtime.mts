// The Node Host uses the original generated Checkpoint module at the same
// repository-relative address in a checkout and in the Local package.
// This interface describes its Checkpoint, Resolution and Model entry points.
// The compiler output is selected only when a caller opens the runtime.
export type CheckpointRuntime = Readonly<{
  resumeRevalidationFailedCode(): string;
  waitingExitState(
    runId: string,
    updatedAt: string,
    declaredResultsJson: string,
    unknownEffectsJson: string,
  ): string;
  revalidationFailedState(
    runId: string,
    updatedAt: string,
    declaredResultsJson: string,
    unknownEffectsJson: string,
  ): string;
  resolutionSealImmediate(
    bodyWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
    hostKeyId: string,
    signature: string,
  ): string;
  resolutionAdmitImmediate(
    bodyWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
  ): string;
  verifiedAttestationPreimage(verifiedWire: string): string;
  resolutionProofPreimage(resolutionWire: string): string;
  resumedApprovalAt(verifiedWire: string, at: string): string;
  resumeFenceDecide(
    intentJson: string,
    claimant: string,
    generation: number,
    nowMs: number,
  ): string;
  effectResumeClaimDecide(
    intentJson: string,
    claimant: string,
    nowMs: number,
    leaseMs: number,
    boundJson: string,
    currentJson: string,
    settlementOnly: boolean,
  ): string;
  resumeClaimDecide(
    intentJson: string,
    claimant: string,
    nowMs: number,
    leaseMs: number,
    boundJson: string,
    currentJson: string,
  ): string;
  resolutionDecide(
    checkpointWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
    hostKeyId: string,
    signature: string,
    closureState: string,
    closureResolutionCid: string,
    unknownEffectsJson: string,
  ): string;
  resolutionAdmit(
    checkpointWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
  ): string;
  checkpointExpiredAt(checkpointWire: string, now: string): string;
  effectSettlementCompletionAllowed(to: string): boolean;
  resumeCompletionAllowed(to: string): boolean;
  runTransitionAllowed(from: string, to: string): boolean;
  runOutcomeTerminal(status: string): boolean;
  runStateAdmit(wire: string): string;
  checkpointLifecycleState(
    runId: string,
    status: string,
    updatedAt: string,
    declaredResultsJson: string,
  ): string;
  checkpointWaitingState(
    sealedWire: string,
    storedWire: string,
    updatedAt: string,
    declaredResultsJson: string,
  ): string;
  checkpointAdmit(wire: string): string;
  checkpointSealBody(bodyWire: string): string;
  modelStoppedCallAdmit(
    requestWire: string,
    ordinal: number,
    attemptWire: string,
    authorityWire: string,
    accountingWire: string,
    outcomeWire: string,
  ): string;
  modelSavedCallAdmit(
    requestWire: string,
    ordinal: number,
    attemptWire: string,
    authorityWire: string,
    accountingWire: string,
    outcomeWire: string,
    captureWire: string,
    observationWire: string | undefined,
  ): string;
  modelImmediateCallAttemptAdmit(
    requestWire: string,
    ordinal: number,
    attemptWire: string,
    authorityWire: string,
    attemptIndex: number,
  ): string;
  modelImmediateCallSetAdmit(requestWire: string): string;
  modelImmediateInvocationGrantAt(
    requestWire: string,
    checkpointWire: string,
    sealedVerifiedWire: string,
    at: string,
  ): string;
  modelInvocationGrantAt(
    requestWire: string,
    checkpointWire: string,
    committedVerifiedWire: string,
    at: string,
  ): string;
  modelResolutionSealImmediate(
    requestWire: string,
    bodyWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
    hostKeyId: string,
    signature: string,
  ): string;
  modelResolutionAdmitImmediate(
    requestWire: string,
    bodyWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
  ): string;
  modelResolutionDecide(
    requestWire: string,
    checkpointWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
    hostKeyId: string,
    signature: string,
    closureState: string,
    closureResolutionCid: string,
    unknownEffectsJson: string,
  ): string;
  modelResolutionAdmit(
    requestWire: string,
    checkpointWire: string,
    resolutionWire: string,
    evidenceWire: string,
    authenticationJson: string,
    authoritiesJson: string,
    verifiedAt: string,
  ): string;
  modelCallAttemptAdmit(
    requestWire: string,
    ordinal: number,
    attemptWire: string,
    authorityWire: string,
    attemptIndex: number,
  ): string;
  modelCallSetAdmit(requestWire: string): string;
  modelOriginalRunAdmit(originalRunWire: string): string;
  modelOriginalJournalCutData(factsWire: string): string;
  modelOriginalJournalIdentity(requestWire: string, rowWire: string): string;
}>;

const runtimeUrl = new URL(
  '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js',
  import.meta.url,
);

export async function loadCheckpointRuntime(): Promise<CheckpointRuntime> {
  return import(runtimeUrl.href) as Promise<CheckpointRuntime>;
}
