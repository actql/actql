// Static readmission ports from the retained Host bridge. The generated MoonBit
// declarations take precedence when present. A clean TypeScript emit can use the
// same static runtime specifier before the separate MoonBit build.
declare module '*/retained_host_bridge/retained_host_bridge.js' {
  export const retainedFramesPrepare: import('../store-local/moonbit-row-frames.mjs').MoonBitRetainedFrameBindings['retainedFramesPrepare'];
  export const retainedFramesFeed: import('../store-local/moonbit-row-frames.mjs').MoonBitRetainedFrameBindings['retainedFramesFeed'];
  export const retainedFramesFinish: import('../store-local/moonbit-row-frames.mjs').MoonBitRetainedFrameBindings['retainedFramesFinish'];
  export const retainedFramesCancel: import('../store-local/moonbit-row-frames.mjs').MoonBitRetainedFrameBindings['retainedFramesCancel'];
  export function retainedContentAppend(reading: unknown, row: string, limits: unknown): unknown;
  export function retainedContentFinish(reading: unknown): unknown;
  export function retainedContentCancel(reading: unknown): boolean;
  export function retainedCompletionEvidence(output: unknown, maxInputs: number, maxColumns: number): unknown;
  export function retainedCompletionDescriptor(evidence: unknown): ReturnType<typeof import('./completion-record.mjs').snapshotCompletionDescriptor>;
  export function retainedCompletionMaterial(evidence: unknown, output: unknown): object | undefined;
  export function retainedReadmissionFactsControlBytes(): bigint;
  export function retainedReadmissionInstall(preparation: unknown, descriptor: unknown,
    accepts: (receipt: unknown) => boolean, permitted: () => boolean): unknown;
  export function retainedReadmissionComplete(installed: unknown, receipt: unknown): unknown;
  export function retainedReadmissionReadable(installed: unknown, input: unknown): boolean;
  export function retainedReadmissionClose(installed: unknown): void;
}

declare module '*/process_host_bridge/process_host_bridge.js' {
  export function processLedgerCreate(limits: ReturnType<typeof import('./process-accounting.mjs').snapshotProcessLimits>): unknown;
  export function processLedgerUsage(ledger: unknown): ReturnType<typeof import('./process-accounting.mjs').snapshotProcessUsage>;
  export function processReadReserve(ledger: unknown, bytes: bigint, scratch: bigint): unknown;
  export function processReadCharge(ledger: unknown, reservation: unknown, bytes: bigint): unknown;
  export function processStopped(ledger: unknown, reservation: unknown): unknown;
}
