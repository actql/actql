import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

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

// Retain inspected DATA once. Accessors/Proxy property callbacks cannot swap
// validated amounts or original selections during the subsequent copy. This
// is an installation snapshot, not a physical adequacy check or new grant.
function snapshotData(value, required, optional, fail) {
  if (value===null || typeof value!=='object' || Array.isArray(value)) fail();
  const names=Reflect.ownKeys(value);
  if (names.some(name=>typeof name!=='string') ||
      required!==undefined && (required.some(name=>!names.includes(name)) ||
        names.some(name=>!required.includes(name) && !optional.includes(name)))) fail();
  const entries=names.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(value,name);
    if (descriptor===undefined || descriptor.enumerable!==true ||
        !Object.hasOwn(descriptor,'value')) fail();
    return [name,descriptor.value];
  });
  return Object.freeze(Object.fromEntries(entries));
}
const exactData=(value,fields,fail)=>snapshotData(value,fields.split(','),[],fail);

// Shared codec DATA validation only, never an installation or capacity grant.
export function snapshotInferOriginalCurrentStateCodec(codec) {
  const fail = () => {throw Object.assign(new Error('ModelOriginalCurrentCodecUnavailable'),
    {code:'ModelOriginalCurrentCodecUnavailable'});};
  codec=exactData(codec,'comparisonWork,decode,quantum',fail);
  const decode=exactData(codec.decode,'maxWork,parse,tree',fail);
  const parse=exactData(decode.parse,'max_depth,max_input_bytes,max_nodes',fail);
  const tree=exactData(decode.tree,'max_depth,max_nodes,max_string_bytes,max_total_string_bytes',fail);
  const bounded = value => Object.values(value).every(n=>Number.isSafeInteger(n)&&n>=0&&n<=2147483647);
  if (
      !Number.isSafeInteger(codec.quantum)||codec.quantum<1||codec.quantum>2147483647 ||
      !Number.isSafeInteger(codec.comparisonWork)||codec.comparisonWork<1||codec.comparisonWork>2147483647 ||
      !Number.isSafeInteger(decode.maxWork)||decode.maxWork<1||decode.maxWork>2147483647 ||
      !bounded(parse) || !bounded(tree)) fail();
  return Object.freeze({quantum:codec.quantum,comparisonWork:codec.comparisonWork,
    decode:Object.freeze({maxWork:decode.maxWork,parse,tree})});
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
  const fail=()=>{throw new TypeError('InvalidInstalledInferMetadataAcquisition');};
  value=exactData(value,'directory,metadata,retainedBytes,workspaceBytes',fail);
  const metadata=exactData(value.metadata,'maxLedgerEntries,maxWireBytes',fail);
  const directory=exactData(value.directory,'maxDirectoryEntries,maxWireBytes',fail);
  if (!count(metadata.maxWireBytes, 1) || !count(metadata.maxLedgerEntries) ||
      !count(directory.maxWireBytes, 1) || !count(directory.maxDirectoryEntries) ||
      !int64(value.retainedBytes, 1n) || !int64(value.workspaceBytes, 1n)) {
    throw new TypeError('InvalidInstalledInferMetadataAcquisition');
  }
  // Complete simultaneous amounts are supplied by the reviewed installation,
  // never derived from wire/count clamps, metadata payloads or object limits.
  return Object.freeze({metadata,
    directory, retainedBytes: value.retainedBytes,
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
  const fail=()=>{throw new TypeError('InvalidInstalledInferPublicationCapacity');};
  // The existing closed DATA helper checks shape/enumerability and captures
  // each descriptor once. Object.keys followed by another descriptor walk can
  // inspect two different originals on a Proxy; neither is a capacity grant.
  value=exactData(value,'retainedBytes,workspaceBytes',fail);
  if (!int64(value.retainedBytes, 1n) || !int64(value.workspaceBytes, 0n)) fail();
  return value;
}

export function retainInferOriginalReadInstallation(value) {
  return retainOriginalReadDeclaration(value, false);
}

// The installation owns the actual Profile and complete all-row envelope.
// The three per-Program identities are bound later from the SAME checked Graph,
// before its original module/Plan/Scope constructor. This DATA issues no grant.
export function retainInferOriginalReadRecipe(value) {
  return retainOriginalReadDeclaration(value, true);
}

export function bindInferOriginalReadRecipe(moon, original, graph, limits) {
  if (!originals.has(original) || graph === undefined ||
      Object.hasOwn(original.nodeInstallation.layout, 'program_definition_cid') ||
      typeof moon.clientProgramInferPlanProgramCid !== 'function' ||
      typeof moon.clientProgramInferPlanParametersCid !== 'function' ||
      typeof moon.clientProgramInferPlanBoundary !== 'function' ||
      !Array.isArray(limits) || limits.length !== 9 ||
      limits.some(value => !int64(value, 0n)) ||
      limits.slice(6).some(value => value > 2147483647n)) {
    throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  const program = moon.clientProgramInferPlanProgramCid(graph);
  const parameters = moon.clientProgramInferPlanParametersCid(graph);
  const barrier = runtimeField(moon.clientProgramInferPlanBoundary(graph), 3);
  if (![program, parameters, barrier].every(value =>
    typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value))) {
    throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  const add = (a, b) => {
    const value = a + b;
    if (!int64(value, 0n)) throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
    return value;
  };
  // Native construction/read/Model bounds stay intact. The installed recipe
  // adds its separately declared Node controls and physical buffer overlap;
  // it cannot replace or lower any stored native allowance.
  return retainInferOriginalReadInstallation({...original,
    bootstrap: {...original.bootstrap,
      bootstrapRetainedBytes: add(limits[0], original.bootstrap.bootstrapRetainedBytes),
      bootstrapExecutionBytes: add(limits[1], original.bootstrap.bootstrapExecutionBytes),
      maxReservations: Math.max(Number(limits[6]), original.bootstrap.maxReservations),
      maxHoldings: Math.max(Number(limits[7]), original.bootstrap.maxHoldings),
      maxDelegations: Math.max(Number(limits[8]), original.bootstrap.maxDelegations)},
    modelRetainedBytes: add(limits[4], original.modelRetainedBytes),
    modelExecutionBytes: add(limits[5], original.modelExecutionBytes),
    ...(original.currentStateCodec === undefined ? {} : {currentStateCodec: {
      ...original.currentStateCodec, comparisonWork: Math.max(original.currentStateCodec.comparisonWork,
        2 + Math.max(Number(limits[6]), original.bootstrap.maxReservations) +
        Math.max(Number(limits[7]), original.bootstrap.maxHoldings) +
        Math.max(Number(limits[8]), original.bootstrap.maxDelegations))}}),
    nodeInstallation: {...original.nodeInstallation, layout: {
      ...original.nodeInstallation.layout, program_definition_cid: program,
      parameter_values_cid: parameters, barrier_cid: barrier,
      retained_bytes: add(limits[2], original.nodeInstallation.layout.retained_bytes),
      execution_bytes: add(limits[3], original.nodeInstallation.layout.execution_bytes)}}});
}

function retainOriginalReadDeclaration(value, recipe) {
  if (value === undefined) return undefined;
  const fail=()=>{throw new TypeError('InvalidInstalledInferOriginalReadInstallation');};
  value=snapshotData(value,['bootstrap','modelExecutionBytes','modelRetainedBytes','nodeInstallation'],
    ['metadataAcquisition','storeBootstrap','currentStateCodec','publicationCapacity'],fail);
  const bootstrap=exactData(value.bootstrap,
    'bootstrapExecutionBytes,bootstrapRetainedBytes,maxDelegations,maxHoldings,maxReservations',fail);
  const node=exactData(value.nodeInstallation,
    'installation,layout,layoutArtifactCid,probability,runtimeArtifactCid',fail);
  const layout=exactData(node.layout,recipe
    ? 'execution_bytes,layout_artifact_cid,prepared_rows,response_profile,retained_bytes,runtime_artifact_cid'
    : 'barrier_cid,execution_bytes,layout_artifact_cid,parameter_values_cid,prepared_rows,program_definition_cid,response_profile,retained_bytes,runtime_artifact_cid',fail);
  const installation=snapshotData(node.installation,undefined,[],fail);
  const sdk=installation.sdk===undefined || installation.sdk===null ? installation.sdk
    : snapshotData(installation.sdk,undefined,[],fail);
  if (!int64(bootstrap.bootstrapRetainedBytes, 1n) ||
      !int64(bootstrap.bootstrapExecutionBytes, 0n) ||
      !['maxReservations', 'maxHoldings', 'maxDelegations'].every(name =>
        Number.isInteger(bootstrap[name]) && bootstrap[name] >= 0 &&
        bootstrap[name] <= 2_147_483_647) ||
      !int64(value.modelRetainedBytes, 1n) || !int64(value.modelExecutionBytes, 0n)) {
    throw new TypeError('InvalidInstalledInferOriginalReadInstallation');
  }
  // Copy the finite declaration, not the opaque admitted profile/Owner. Common
  // still checks every original reference and all-R bound before read reserve
  // and again before one-shot claim. There is no permissive fallback.
  const metadataAcquisition = retainMetadata(value.metadataAcquisition);
  const publicationCapacity = retainPublicationCapacity(value.publicationCapacity);
  const currentStateCodec = value.currentStateCodec===undefined ? undefined
    : snapshotInferOriginalCurrentStateCodec(value.currentStateCodec);
  const storeBootstrap = value.storeBootstrap===undefined ? undefined
    : exactData(value.storeBootstrap,'maxDirectoryEntries,maxWireBytes',
      ()=>{throw new TypeError('InvalidInstalledInferStoreBootstrap');});
  if (storeBootstrap !== undefined &&
      (!keys(storeBootstrap, 'maxDirectoryEntries,maxWireBytes') ||
        !count(storeBootstrap.maxWireBytes, 1) || !count(storeBootstrap.maxDirectoryEntries))) {
    throw new TypeError('InvalidInstalledInferStoreBootstrap');
  }
  const retained = Object.freeze({bootstrap,
    modelRetainedBytes: value.modelRetainedBytes,
    modelExecutionBytes: value.modelExecutionBytes,
    nodeInstallation: Object.freeze({layout,
      installation: Object.freeze({...installation,
        ...(installation.sdk === undefined ? {} : {
          sdk,
        })}),
      runtimeArtifactCid: node.runtimeArtifactCid, layoutArtifactCid: node.layoutArtifactCid,
      probability: node.probability}),
    ...(metadataAcquisition === undefined ? {} : {metadataAcquisition}),
    ...(publicationCapacity === undefined ? {} : {publicationCapacity}),
    ...(currentStateCodec === undefined ? {} : {currentStateCodec}),
    ...(storeBootstrap === undefined ? {} : {storeBootstrap})});
  originals.add(retained);
  return retained;
}
