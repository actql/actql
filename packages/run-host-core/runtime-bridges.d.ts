// Static ports of the two generated Run Host Core runtime modules. The
// package builder installs their JavaScript after the clean TypeScript emit.
declare module '*/dist/checkpoint_runtime_node.js' {
  export const checkpointAdmit: typeof import('./checkpoints.d.ts').checkpointAdmit;
  export const checkpointWaitingState: typeof import('./checkpoints.d.ts').checkpointWaitingState;
  export const checkpointSealBody: typeof import('./checkpoints.d.ts').checkpointSealBody;
  export const checkpointLifecycleState: typeof import('./checkpoints.d.ts').checkpointLifecycleState;
  export const waitingExitState: typeof import('./checkpoints.d.ts').waitingExitState;
  export const revalidationFailedState: typeof import('./checkpoints.d.ts').revalidationFailedState;
  export const checkpointExpiredAt: typeof import('./checkpoints.d.ts').checkpointExpiredAt;
  export const runStateAdmit: typeof import('./checkpoints.d.ts').runStateAdmit;
  export const runTransitionAllowed: typeof import('./checkpoints.d.ts').runTransitionAllowed;
  export const resumeCompletionAllowed: typeof import('./checkpoints.d.ts').resumeCompletionAllowed;
  export const effectSettlementCompletionAllowed: typeof import('./checkpoints.d.ts').effectSettlementCompletionAllowed;
  export const resolutionProofPreimage: typeof import('./checkpoints.d.ts').resolutionProofPreimage;
  export const resolutionAdmit: typeof import('./checkpoints.d.ts').resolutionAdmit;
  export const resolutionDecide: typeof import('./checkpoints.d.ts').resolutionDecide;
  export const verifiedAttestationPreimage: typeof import('./checkpoints.d.ts').verifiedAttestationPreimage;
  export const resumedApprovalAt: typeof import('./checkpoints.d.ts').resumedApprovalAt;
  export const effectResumeClaimDecide: typeof import('./checkpoints.d.ts').effectResumeClaimDecide;
  export const resumeFenceDecide: typeof import('./checkpoints.d.ts').resumeFenceDecide;
  export function runStateObservationPrepare(wire: string, runId: string, revision: bigint,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  export function runStateObservationKey(value: unknown): string;
  export function runStateObservationNextRevision(value: unknown, hasPrior: boolean,
    priorKey: string, revision: bigint): unknown;
  export function runStateObservationWire(value: unknown, revision: bigint): unknown;
  export function runStateWaitDecision(wire: string, hasSince: boolean, since: bigint,
    maxWireBytes: number, maxNodes: number, maxDepth: number): string;
}

declare module '*/dist/client_values_host_abi.js' {
  export function clientValuesHostObservationScope(workspace: string, authority: string,
    destinationRevision: string, disclosureRevision: string, customer: boolean): object | undefined;
  export function clientValuesHostObservationScopeKey(scope: unknown): string;
  export function clientValuesHostObservationBudget(scope: unknown, requestKey: string,
    maxRecords: number, maxBytes: number, freshRequest: boolean, savedScopeKey: string | undefined,
    savedRequestKey: string, savedMaxRecords: number, savedMaxBytes: number, savedRecords: number,
    savedBytes: number, savedFactHashes: readonly string[]): unknown;
  export function clientValuesHostChargeObservation(budget: unknown, scope: unknown,
    requestKey: string, fact: string | undefined, recordBytes: number): unknown;
  export function clientValuesHostObservationBudgetSnapshot(budget: unknown):
    readonly [string, string, number, number, number, number, readonly string[]];
  export function clientValuesHostRenderStaticExplanation(wire: string, locale: string): unknown;
}
