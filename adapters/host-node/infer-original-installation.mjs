// Trusted installation declaration only. It selects the existing Common
// scope/layout issuer; these values neither prove physical adequacy nor issue
// a new grant. The reviewed installation must cover initialization before a
// Run starts, and the full simultaneous read envelope before child allocation.
const keys = (value, expected) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === expected;
const int64 = (value, minimum) => typeof value === 'bigint' && value >= minimum &&
  value <= 9_223_372_036_854_775_807n;
const originals = new WeakSet();
const count = (value, minimum = 0) => Number.isSafeInteger(value) && value >= minimum;
const unavailable = () => { throw Object.assign(new Error('InferOriginalMetadataAcquisitionUnavailable'),
  {code: 'InferOriginalMetadataAcquisitionUnavailable'}); };

function retainMetadata(value) {
  if (value === undefined) return undefined;
  if (!keys(value, 'directory,metadata,retainedBytes,workspaceBytes') ||
      !keys(value.metadata, 'maxLedgerEntries,maxWireBytes') ||
      !keys(value.directory, 'maxDirectoryEntries,maxWireBytes') ||
      !count(value.metadata.maxWireBytes, 1) || !count(value.metadata.maxLedgerEntries) ||
      !count(value.directory.maxWireBytes, 1) || !count(value.directory.maxDirectoryEntries) ||
      !int64(value.retainedBytes, 1n) || !int64(value.workspaceBytes, 1n)) {
    throw new TypeError('InvalidInstalledInferMetadataAcquisition');
  }
  // Complete simultaneous amounts are supplied by the reviewed installation,
  // never derived from wire/count clamps, metadata payloads or object limits.
  return Object.freeze({metadata: Object.freeze({...value.metadata}),
    directory: Object.freeze({...value.directory}), retainedBytes: value.retainedBytes,
    workspaceBytes: value.workspaceBytes});
}

// Data selector of this existing installation issuer, not a grant factory.
// Copies and independently matching CIDs cannot substitute for the retained
// original and exact five-field selection captured by its installed operation.
export function selectedInferOriginalMetadataLimits(original, nodeInstallation) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.metadataAcquisition === undefined) unavailable();
  return original.metadataAcquisition;
}

export function retainInferOriginalReadInstallation(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).filter(name => name !== 'metadataAcquisition').sort().join(',') !==
        'bootstrap,modelExecutionBytes,modelRetainedBytes,nodeInstallation' ||
      !keys(value.bootstrap,
        'bootstrapExecutionBytes,bootstrapRetainedBytes,maxDelegations,maxHoldings,maxReservations') ||
      !int64(value.bootstrap.bootstrapRetainedBytes, 1n) ||
      !int64(value.bootstrap.bootstrapExecutionBytes, 0n) ||
      !['maxReservations', 'maxHoldings', 'maxDelegations'].every(name =>
        Number.isInteger(value.bootstrap[name]) && value.bootstrap[name] >= 0 &&
        value.bootstrap[name] <= 2_147_483_647) ||
      !int64(value.modelRetainedBytes, 1n) || !int64(value.modelExecutionBytes, 0n) ||
      !keys(value.nodeInstallation,
        'installation,layout,layoutArtifactCid,probability,runtimeArtifactCid') ||
      !keys(value.nodeInstallation.layout,
        'barrier_cid,execution_bytes,layout_artifact_cid,parameter_values_cid,prepared_rows,program_definition_cid,response_profile,retained_bytes,runtime_artifact_cid') ||
      value.nodeInstallation.installation === null ||
      typeof value.nodeInstallation.installation !== 'object') {
    throw new TypeError('InvalidInstalledInferOriginalReadInstallation');
  }
  const node = value.nodeInstallation;
  // Copy the finite declaration, not the opaque admitted profile/Owner. Common
  // still checks every original reference and all-R bound before read reserve
  // and again before one-shot claim. There is no permissive fallback.
  const metadataAcquisition = retainMetadata(value.metadataAcquisition);
  const retained = Object.freeze({bootstrap: Object.freeze({...value.bootstrap}),
    modelRetainedBytes: value.modelRetainedBytes,
    modelExecutionBytes: value.modelExecutionBytes,
    nodeInstallation: Object.freeze({layout: Object.freeze({...node.layout}),
      installation: Object.freeze({...node.installation,
        ...(node.installation.sdk === undefined ? {} : {
          sdk: node.installation.sdk === null ? null : Object.freeze({...node.installation.sdk}),
        })}),
      runtimeArtifactCid: node.runtimeArtifactCid, layoutArtifactCid: node.layoutArtifactCid,
      probability: node.probability}),
    ...(metadataAcquisition === undefined ? {} : {metadataAcquisition})});
  originals.add(retained);
  return retained;
}
