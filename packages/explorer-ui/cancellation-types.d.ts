import type {WireCancellationRef, WireOperationAttemptRef, WireCancellationAttempt, WireCancellationLookup} from '@actql/client-wire';
export type OriginalCancellation = Readonly<{
  cancelRef: WireCancellationRef; attemptRef: Readonly<WireOperationAttemptRef & {operation:'cancel'}>;
}>;
/** Client presentation state, not an Owner wire, permission or physical stop. */
export type CancellationObservation = Readonly<{state:'unknown';original:OriginalCancellation}> |
  Readonly<{state:'observed';original:OriginalCancellation;outcome:WireCancellationAttempt}>;
export type CancellationPanelProps = Readonly<{
  original:OriginalCancellation|null; observation:CancellationObservation|null;
  history:WireCancellationLookup|null; pending:boolean;
  canPrepare:boolean; canRequest:boolean; canLookup:boolean;
  onPrepare:()=>void; onRequest:()=>void; onLookup:()=>void;
}>;
