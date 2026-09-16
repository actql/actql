// Connector-private capacity contract for the pinned Neo vector representation.
// Keep configuration/planning independent of loading the native SDK.
export const boundedVectorVersion = '1.5.5-r.4';
export const maxNativeVectorRows = 2048;
export const boundedTransport = limits => limits.maxChunkRows !== undefined && limits.maxChunkBytes !== undefined;
