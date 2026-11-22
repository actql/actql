import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

type Data = Readonly<Record<string, unknown>>;
type Refuse = () => never;
type FieldNames<Fields extends string> = Fields extends `${infer First},${infer Rest}`
  ? First | FieldNames<Rest> : Fields;
type FieldsSnapshot<Fields extends string> = Fields extends string
  ? Readonly<Record<FieldNames<Fields>, unknown>> : never;
type StoreBootstrapLimits = Readonly<{maxWireBytes: number; maxDirectoryEntries: number}>;
type MetadataLimits = Readonly<{maxWireBytes: number; maxLedgerEntries: number}>;
type ByteCapacity = Readonly<{retainedBytes: bigint; workspaceBytes: bigint}>;
type ModelCapacity = Readonly<{modelRetainedBytes: bigint; modelExecutionBytes: bigint}>;
type Bootstrap = Readonly<{
  bootstrapRetainedBytes: bigint; bootstrapExecutionBytes: bigint;
  maxReservations: number; maxHoldings: number; maxDelegations: number;
}>;
type InferPlanRuntime = Readonly<{
  clientProgramInferPlanProgramCid?(graph: unknown): string;
  clientProgramInferPlanParametersCid?(graph: unknown): string;
  clientProgramInferPlanBoundary?(graph: unknown): unknown;
}>;

// Trusted installation declaration only. It selects the existing Common
// scope/layout issuer; these values neither prove physical adequacy nor issue
// a new grant. The reviewed installation must cover initialization before a
// Run starts, and the full simultaneous read envelope before child allocation.
const keys = (value: unknown, expected: string) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === expected;
const int64 = (value: unknown, minimum: bigint): value is bigint => typeof value === 'bigint' && value >= minimum &&
  value <= 9_223_372_036_854_775_807n;
const originals = new WeakMap<object, ModelCapacity | undefined>();
const count = (value: unknown, minimum = 0): value is number => Number.isSafeInteger(value) && (value as number) >= minimum;
const unavailable: Refuse = () => { throw Object.assign(new Error('InferOriginalMetadataAcquisitionUnavailable'),
  {code: 'InferOriginalMetadataAcquisitionUnavailable'}); };

// Retain inspected DATA once. Accessors/Proxy property callbacks cannot swap
// validated amounts or original selections during the subsequent copy. This
// is an installation snapshot, not a physical adequacy check or new grant.
function snapshotData(value: unknown, required: readonly string[] | undefined, optional: readonly string[], fail: Refuse): Data {
  if (value===null || typeof value!=='object' || Array.isArray(value)) fail();
  const names=Reflect.ownKeys(value);
  if (names.some(name=>typeof name!=='string') ||
      required!==undefined && (required.some(name=>!names.includes(name)) ||
        names.some(name=>!required.includes(name as string) && !optional.includes(name as string)))) fail();
  const entries=names.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(value,name);
    if (descriptor===undefined || descriptor.enumerable!==true ||
        !Object.hasOwn(descriptor,'value')) fail();
    return [name,descriptor.value];
  });
  return Object.freeze(Object.fromEntries(entries));
}
const exactData=<Fields extends string>(value: unknown, fields: Fields, fail: Refuse) =>
  snapshotData(value,fields.split(','),[],fail) as FieldsSnapshot<Fields>;

// Shared codec DATA validation only, never an installation or capacity grant.
export function snapshotInferOriginalCurrentStateCodec(codec: unknown) {
  const fail: Refuse = () => {throw Object.assign(new Error('ModelOriginalCurrentCodecUnavailable'),
    {code:'ModelOriginalCurrentCodecUnavailable'});};
  const snapshot = exactData(codec,'comparisonWork,decode,quantum',fail);
  const decode=exactData(snapshot.decode,'maxWork,parse,tree',fail);
  const parse=exactData(decode.parse,'max_depth,max_input_bytes,max_nodes',fail);
  const tree=exactData(decode.tree,'max_depth,max_nodes,max_string_bytes,max_total_string_bytes',fail);
  const bounded = <Fields extends string>(value: Readonly<Record<Fields, unknown>>): value is Readonly<Record<Fields, number>> =>
    Object.values(value).every(n=>Number.isSafeInteger(n)&&(n as number)>=0&&(n as number)<=2147483647);
  if (
      !Number.isSafeInteger(snapshot.quantum)||(snapshot.quantum as number)<1||(snapshot.quantum as number)>2147483647 ||
      !Number.isSafeInteger(snapshot.comparisonWork)||(snapshot.comparisonWork as number)<1||(snapshot.comparisonWork as number)>2147483647 ||
      !Number.isSafeInteger(decode.maxWork)||(decode.maxWork as number)<1||(decode.maxWork as number)>2147483647 ||
      !bounded(parse) || !bounded(tree)) fail();
  return Object.freeze({quantum:snapshot.quantum as number,comparisonWork:snapshot.comparisonWork as number,
    decode:Object.freeze({maxWork:decode.maxWork as number,parse,tree})});
}

// Only the exact retained installation supplies this finite serializer role.
// Matching codec fields/CIDs or a copied selection do not select it.
export function selectedInferOriginalCurrentStateCodec(original: RetainedRead, nodeInstallation: unknown) {
  if (!originals.has(original) || original.nodeInstallation!==nodeInstallation ||
      original.currentStateCodec===undefined) {
    throw Object.assign(new Error('InferOriginalStateCodecUnavailable'),
      {code:'InferOriginalStateCodecUnavailable'});
  }
  return original.currentStateCodec;
}

function retainMetadata(value: unknown) {
  if (value === undefined) return undefined;
  const fail: Refuse=()=>{throw new TypeError('InvalidInstalledInferMetadataAcquisition');};
  const snapshot = exactData(value,'directory,metadata,retainedBytes,workspaceBytes',fail);
  const metadata=exactData(snapshot.metadata,'maxLedgerEntries,maxWireBytes',fail);
  const directory=exactData(snapshot.directory,'maxDirectoryEntries,maxWireBytes',fail);
  if (!count(metadata.maxWireBytes, 1) || !count(metadata.maxLedgerEntries) ||
      !count(directory.maxWireBytes, 1) || !count(directory.maxDirectoryEntries) ||
      !int64(snapshot.retainedBytes, 1n) || !int64(snapshot.workspaceBytes, 1n)) {
    throw new TypeError('InvalidInstalledInferMetadataAcquisition');
  }
  // Complete simultaneous amounts are supplied by the reviewed installation,
  // never derived from wire/count clamps, metadata payloads or object limits.
  return Object.freeze({metadata: metadata as MetadataLimits,
    directory: directory as StoreBootstrapLimits, retainedBytes: snapshot.retainedBytes,
    workspaceBytes: snapshot.workspaceBytes});
}

// Data selector of this existing installation issuer, not a grant factory.
// Copies and independently matching CIDs cannot substitute for the retained
// original and exact five-field selection captured by its installed operation.
export function selectedInferOriginalMetadataLimits(original: RetainedRead, nodeInstallation: unknown) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.metadataAcquisition === undefined) unavailable();
  return original.metadataAcquisition;
}

// A distinct private physical acquisition role of the SAME installation.
// Metadata/list clamps cannot stand in for the complete Store opening scan.
export function selectedInferOriginalStoreBootstrapLimits(original: RetainedRead, nodeInstallation: unknown) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.storeBootstrap === undefined) unavailable();
  return original.storeBootstrap;
}

// Private declaration selection only. The same original Model owner must
// separately reserve its complete, justified simultaneous publication bytes.
// Neither positive amounts nor this nominal installation select a profile,
// restore a Ledger, acknowledge cleanup or authorize Model/Result dispatch.
export function selectedInferOriginalPublicationCapacity(original: RetainedRead, nodeInstallation: unknown) {
  if (!originals.has(original) || original.nodeInstallation !== nodeInstallation ||
      original.publicationCapacity === undefined) {
    throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
      {code: 'InferOriginalPublicationCapacityUnavailable'});
  }
  return original.publicationCapacity;
}

function retainPublicationCapacity(value: unknown): ByteCapacity | undefined {
  if (value === undefined) return undefined;
  const fail: Refuse=()=>{throw new TypeError('InvalidInstalledInferPublicationCapacity');};
  // The existing closed DATA helper checks shape/enumerability and captures
  // each descriptor once. Object.keys followed by another descriptor walk can
  // inspect two different originals on a Proxy; neither is a capacity grant.
  const snapshot = exactData(value,'retainedBytes,workspaceBytes',fail);
  if (!int64(snapshot.retainedBytes, 1n) || !int64(snapshot.workspaceBytes, 0n)) fail();
  return snapshot as ByteCapacity;
}

export function retainInferOriginalReadInstallation(value: object): RetainedRead;
export function retainInferOriginalReadInstallation(value: unknown): RetainedRead | undefined;
export function retainInferOriginalReadInstallation(value: unknown) {
  return retainOriginalReadDeclaration(value, false);
}

// The installation owns the actual Profile and complete all-row envelope.
// The three per-Program identities are bound later from the SAME checked Graph,
// before its original module/Plan/Scope constructor. This DATA issues no grant.
export function retainInferOriginalReadRecipe(value: unknown) {
  return retainOriginalReadDeclaration(value, true);
}

// Original recipe controls remain distinct from the complete native+Node
// Model allowance. This association adds no registration or resource owner.
export function inferOriginalReadStartupCapacity<Original extends object>(original: Original) {
  return originals.get(original) ?? original;
}

export function bindInferOriginalReadRecipe(moon: InferPlanRuntime, original: RetainedRead,
  graph: unknown, limits: readonly bigint[], modelLedgerBytes: readonly bigint[]) {
  if (!originals.has(original) || graph === undefined ||
      Object.hasOwn(original.nodeInstallation.layout, 'program_definition_cid') ||
      typeof moon.clientProgramInferPlanProgramCid !== 'function' ||
      typeof moon.clientProgramInferPlanParametersCid !== 'function' ||
      typeof moon.clientProgramInferPlanBoundary !== 'function' ||
      !Array.isArray(limits) || limits.length !== 9 ||
      limits.some(value => !int64(value, 0n)) ||
      limits.slice(6).some(value => value > 2147483647n) ||
      !Array.isArray(modelLedgerBytes) || modelLedgerBytes.length !== 2 ||
      modelLedgerBytes.some(value => !int64(value, 0n))) {
    throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  const modelRetained = modelLedgerBytes[0], modelExecution = modelLedgerBytes[1];
  const program = moon.clientProgramInferPlanProgramCid(graph);
  const parameters = moon.clientProgramInferPlanParametersCid(graph);
  const barrier = runtimeField(moon.clientProgramInferPlanBoundary(graph), 3);
  if (![program, parameters, barrier].every(value =>
    typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value))) {
    throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  const add = (a: bigint, b: bigint) => {
    const value = a + b;
    if (!int64(value, 0n)) throw Object.assign(new Error('InferOriginalReadRecipeUnavailable'),
      {code: 'InferOriginalReadRecipeUnavailable'});
    return value;
  };
  // Native construction/read/Model bounds stay intact. The installed recipe
  // adds its separately declared Node controls and physical buffer overlap;
  // it cannot replace or lower any stored native allowance.
  const bound = retainInferOriginalReadInstallation({...original,
    bootstrap: {...original.bootstrap,
      bootstrapRetainedBytes: add(limits[0], original.bootstrap.bootstrapRetainedBytes),
      bootstrapExecutionBytes: add(limits[1], original.bootstrap.bootstrapExecutionBytes),
      maxReservations: Math.max(Number(limits[6]), original.bootstrap.maxReservations),
      maxHoldings: Math.max(Number(limits[7]), original.bootstrap.maxHoldings),
      maxDelegations: Math.max(Number(limits[8]), original.bootstrap.maxDelegations)},
    modelRetainedBytes: add(modelRetained, original.modelRetainedBytes),
    modelExecutionBytes: add(modelExecution, original.modelExecutionBytes),
    ...(original.currentStateCodec === undefined ? {} : {currentStateCodec: {
      ...original.currentStateCodec, comparisonWork: Math.max(original.currentStateCodec.comparisonWork,
        2 + Math.max(Number(limits[6]), original.bootstrap.maxReservations) +
        Math.max(Number(limits[7]), original.bootstrap.maxHoldings) +
        Math.max(Number(limits[8]), original.bootstrap.maxDelegations))}}),
    nodeInstallation: {...original.nodeInstallation, layout: {
      ...original.nodeInstallation.layout, program_definition_cid: program,
      parameter_values_cid: parameters, barrier_cid: barrier,
      retained_bytes: add(limits[2], original.nodeInstallation.layout.retained_bytes as bigint),
      execution_bytes: add(limits[3], original.nodeInstallation.layout.execution_bytes as bigint)}}});
  originals.set(bound, Object.freeze({modelRetainedBytes: original.modelRetainedBytes,
    modelExecutionBytes: original.modelExecutionBytes}));
  return bound;
}

type RetainedRead = NonNullable<ReturnType<typeof retainOriginalReadDeclaration>>;

function retainOriginalReadDeclaration(value: unknown, recipe: boolean) {
  if (value === undefined) return undefined;
  const fail: Refuse=()=>{throw new TypeError('InvalidInstalledInferOriginalReadInstallation');};
  const snapshot = snapshotData(value,['bootstrap','modelExecutionBytes','modelRetainedBytes','nodeInstallation'],
    ['metadataAcquisition','storeBootstrap','currentStateCodec','publicationCapacity'],fail);
  const bootstrap=exactData(snapshot.bootstrap,
    'bootstrapExecutionBytes,bootstrapRetainedBytes,maxDelegations,maxHoldings,maxReservations',fail);
  const node=exactData(snapshot.nodeInstallation,
    'installation,layout,layoutArtifactCid,probability,runtimeArtifactCid',fail);
  const layout=exactData(node.layout,recipe
    ? 'execution_bytes,layout_artifact_cid,prepared_rows,response_profile,retained_bytes,runtime_artifact_cid'
    : 'barrier_cid,execution_bytes,layout_artifact_cid,parameter_values_cid,prepared_rows,program_definition_cid,response_profile,retained_bytes,runtime_artifact_cid',fail);
  const installation=snapshotData(node.installation,undefined,[],fail);
  const sdk=installation.sdk===undefined || installation.sdk===null ? installation.sdk
    : snapshotData(installation.sdk,undefined,[],fail);
  if (recipe && (!int64(layout.retained_bytes, 1n) ||
      !int64(layout.execution_bytes, 1n) || !int64(layout.prepared_rows, 0n))) fail();
  if (!int64(bootstrap.bootstrapRetainedBytes, 1n) ||
      !int64(bootstrap.bootstrapExecutionBytes, 0n) ||
      !['maxReservations', 'maxHoldings', 'maxDelegations'].every(name =>
        Number.isInteger(bootstrap[name as keyof Bootstrap]) && (bootstrap[name as keyof Bootstrap] as number) >= 0 &&
        (bootstrap[name as keyof Bootstrap] as number) <= 2_147_483_647) ||
      !int64(snapshot.modelRetainedBytes, 1n) || !int64(snapshot.modelExecutionBytes, 0n)) {
    throw new TypeError('InvalidInstalledInferOriginalReadInstallation');
  }
  // Copy the finite declaration, not the opaque admitted profile/Owner. Common
  // still checks every original reference and all-R bound before read reserve
  // and again before one-shot claim. There is no permissive fallback.
  const metadataAcquisition = retainMetadata(snapshot.metadataAcquisition);
  const publicationCapacity = retainPublicationCapacity(snapshot.publicationCapacity);
  const currentStateCodec = snapshot.currentStateCodec===undefined ? undefined
    : snapshotInferOriginalCurrentStateCodec(snapshot.currentStateCodec);
  const storeBootstrap = snapshot.storeBootstrap===undefined ? undefined
    : exactData(snapshot.storeBootstrap,'maxDirectoryEntries,maxWireBytes',
      ()=>{throw new TypeError('InvalidInstalledInferStoreBootstrap');});
  if (storeBootstrap !== undefined &&
      (!keys(storeBootstrap, 'maxDirectoryEntries,maxWireBytes') ||
        !count(storeBootstrap.maxWireBytes, 1) || !count(storeBootstrap.maxDirectoryEntries))) {
    throw new TypeError('InvalidInstalledInferStoreBootstrap');
  }
  const retained = Object.freeze({bootstrap: bootstrap as Bootstrap,
    modelRetainedBytes: snapshot.modelRetainedBytes,
    modelExecutionBytes: snapshot.modelExecutionBytes,
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
    ...(storeBootstrap === undefined ? {} : {storeBootstrap: storeBootstrap as StoreBootstrapLimits})});
  originals.set(retained, undefined);
  return retained;
}
