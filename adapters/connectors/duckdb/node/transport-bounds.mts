// Connector-private capacity contract for the pinned Neo vector representation.
// Keep configuration/planning independent of loading the native SDK.
export const boundedVectorVersion = '1.5.5-r.4';
export const maxNativeVectorRows = 2048;
type TransportWindow = Readonly<{maxChunkRows?: number; maxChunkBytes?: number}>;
export const boundedTransport = <Limits extends TransportWindow>(limits: Limits):
  limits is Limits & Required<TransportWindow> => limits.maxChunkRows !== undefined && limits.maxChunkBytes !== undefined;
