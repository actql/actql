import type {OriginalCancellation, CancellationObservation} from './cancellation-types.js';
export type {OriginalCancellation, CancellationObservation, CancellationPanelProps} from './cancellation-types.js';
export function captureCancellation(cancelRef:unknown,attemptRef:unknown):OriginalCancellation;
export function validCancellationObservation(value:unknown,original:unknown):value is CancellationObservation;
