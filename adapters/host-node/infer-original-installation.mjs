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

// Shared codec DATA validation only, never an installation or capacity grant.
export function snapshotInferOriginalCurrentStateCodec(codec) {
  const fail = () => {throw Object.assign(new Error('ModelOriginalCurrentCodecUnavailable'),
    {code:'ModelOriginalCurrentCodecUnavailable'});};
  const bounded = (value, fields) => keys(value, fields) &&
    Object.values(Object.getOwnPropertyDescriptors(value)).every(d=>'value' in d) &&
    Object.values(value).every(n=>Number.isSafeInteger(n)&&n>=0&&n<=2147483647);
  if (!keys(codec, 'comparisonWork,decode,quantum') ||
      !Object.values(Object.getOwnPropertyDescriptors(codec)).every(d=>'value' in d) ||
      !Number.isSafeInteger(codec.quantum)||codec.quantum<1||codec.quantum>2147483647 ||
      !Number.isSafeInteger(codec.comparisonWork)||codec.comparisonWork<1||codec.comparisonWork>2147483647 ||
      !keys(codec.decode, 'maxWork,parse,tree') ||
      !Object.values(Object.getOwnPropertyDescriptors(codec.decode)).every(d=>'value' in d) ||
      !Number.isSafeInteger(codec.decode.maxWork)||codec.decode.maxWork<1||codec.decode.maxWork>2147483647 ||
      !bounded(codec.decode.parse, 'max_depth,max_input_bytes,max_nodes') ||
      !bounded(codec.decode.tree, 'max_depth,max_nodes,max_string_bytes,max_total_string_bytes')) fail();
  return Object.freeze({quantum:codec.quantum,comparisonWork:codec.comparisonWork,
    decode:Object.freeze({maxWork:codec.decode.maxWork,parse:Object.freeze({...codec.decode.parse}),
      tree:Object.freeze({...codec.decode.tree})})});
}

// Only the exact retained installation supplies this finite serializer role.
// Matching codec fields/CIDs or a copied selection do not select it.
export function selectedInferOriginalCurrentStateCodec(original, nodeInstallation) {
  if (!originals.has(original) || original.nodeInstallation!==nodeInstallation ||
      original.currentStateCodec===undefined) {
    throw Object.assign(new Error('InferOriginalStateCodecUnavailable'),
      {code:'InferOriginalStateCodecUnavailable'});
  }
  return original.currentStateCodec;
}

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

// A distinct private physical acquisition role of the SAME installation.
// Metadata/list clamps cannot stand in for the complete Store opening scan.
/** @typedef {Readonly<{maxWireBytes: number, maxDirectoryEntries: number}>} OriginalStoreBootstrapLimits */
/** @returns {OriginalStoreBootstrapLimits} */
export function selectedInferOriginalStoreBootstrapLimits(original, nodeInstallation) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.storeBootstrap === undefined) unavailable();
  return original.storeBootstrap;
}

// Private declaration selection only. The same original Model owner must
// separately reserve its complete, justified simultaneous publication bytes.
// Neither positive amounts nor this nominal installation select a profile,
// restore a Ledger, acknowledge cleanup or authorize Model/Result dispatch.
export function selectedInferOriginalPublicationCapacity(original, nodeInstallation) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.publicationCapacity === undefined) {
    throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
      {code: 'InferOriginalPublicationCapacityUnavailable'});
  }
  return original.publicationCapacity;
}

function retainPublicationCapacity(value) {
  if (value === undefined) return undefined;
  if (!keys(value, 'retainedBytes,workspaceBytes')) {
    throw new TypeError('InvalidInstalledInferPublicationCapacity');
  }
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const retainedBytes = descriptors.retainedBytes?.value;
  const workspaceBytes = descriptors.workspaceBytes?.value;
  if (Reflect.ownKeys(descriptors).length !== 2 ||
      !Object.values(descriptors).every(d => 'value' in d) ||
      !int64(retainedBytes, 1n) || !int64(workspaceBytes, 0n)) {
    throw new TypeError('InvalidInstalledInferPublicationCapacity');
  }
  // Validate and retain the same descriptor DATA without another property read.
  return Object.freeze({retainedBytes, workspaceBytes});
}

export function retainInferOriginalReadInstallation(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).filter(name => !['metadataAcquisition', 'storeBootstrap', 'currentStateCodec', 'publicationCapacity'].includes(name)).sort().join(',') !==
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
  const publicationCapacity = retainPublicationCapacity(value.publicationCapacity);
  const currentStateCodec = value.currentStateCodec===undefined ? undefined
    : snapshotInferOriginalCurrentStateCodec(value.currentStateCodec);
  const storeBootstrap = value.storeBootstrap;
  if (storeBootstrap !== undefined &&
      (!keys(storeBootstrap, 'maxDirectoryEntries,maxWireBytes') ||
        !count(storeBootstrap.maxWireBytes, 1) || !count(storeBootstrap.maxDirectoryEntries))) {
    throw new TypeError('InvalidInstalledInferStoreBootstrap');
  }
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
    ...(metadataAcquisition === undefined ? {} : {metadataAcquisition}),
    ...(publicationCapacity === undefined ? {} : {publicationCapacity}),
    ...(currentStateCodec === undefined ? {} : {currentStateCodec}),
    ...(storeBootstrap === undefined ? {} : {storeBootstrap: Object.freeze({...storeBootstrap})})});
  originals.add(retained);
  return retained;
}
