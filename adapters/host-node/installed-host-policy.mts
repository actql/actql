// Explicit Host configuration of the existing capacity contract. This is
// neither caller Program input nor an adapter-owned policy override.
import contract from '../../spec/contracts/actql-capacity-host-policy.json' with {type: 'json'};
import environmentContract from '../../spec/contracts/actql-check-environment.json' with {type: 'json'};
import {canonicalJson, contentCid} from './local-account-config.mjs';
import type {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type CapacityField = Exclude<keyof typeof contract.schema.properties, 'version'>;
type LookupField = Exclude<keyof typeof environmentContract.policy_components.lookup_execution.schema.properties, 'version'>;
type CapacityPolicy = Readonly<{version: string} & Partial<Record<CapacityField, number>>>;
type LookupPolicy = Readonly<{version: string} & Record<LookupField, number>>;
type RequestMemory = Readonly<{retainedBytes: number; executionBytes: number}>;
type Rule = Readonly<{const?: unknown; minimum?: number; maximum?: number}>;
type WirePolicy = Readonly<{
  evidence_bundle_cid?: unknown;
  host_policy_profile: Readonly<{capacity: CapacityPolicy; lookup_execution?: LookupPolicy}>;
}>;
type Checker = Parameters<typeof composeInstalledCheckEnvironment>[0];
type ResourceOriginal = Extract<SynchronousRuntimeData, object>;
type ResourceLookup = Readonly<{
  clientLocalPreparationResourceLimits(original: ResourceOriginal, retainedBytes?: bigint, executionBytes?: bigint): unknown;
}>;
type ResourcePolicy = ResourceLookup & Readonly<{
  clientLocalResourcePolicyOriginal(): ResourceOriginal;
  clientLocalResourcePolicyRowCeiling(original: ResourceOriginal, retainedBytes?: bigint, executionBytes?: bigint): number;
  clientLocalResourcePolicyModelRequestByteCeiling(original: ResourceOriginal): bigint;
}>;

const snapshots = new WeakSet<object>();
const fail: (cause: unknown) => never = cause => {
  throw Object.assign(new TypeError('InvalidInstalledHostCapacityPolicy', {cause}),
    {code: 'InvalidInstalledHostCapacityPolicy'});
};

export function snapshotHostCapacityPolicy(value: unknown): CapacityPolicy | undefined {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && snapshots.has(value)) return value as CapacityPolicy;
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) fail('PolicyShape');
    // Read each application-owned field once before any asynchronous boundary.
    // The registered contract is flat; no private/nested object is retained.
    const entries = Object.entries(value) as [string, unknown][];
    const shape = contract.schema;
    const keys = new Set(entries.map(([key]) => key));
    if (entries.length > Object.keys(shape.properties).length ||
        shape.required.some(key => !keys.has(key))) fail('PolicyFields');
    for (const [key, item] of entries) {
      const rule = (shape.properties as Readonly<Record<string, Rule>>)[key];
      if (!Object.hasOwn(shape.properties, key) || (Object.hasOwn(rule, 'const') ? item !== rule.const :
        !Number.isSafeInteger(item) || Object.is(item, -0) ||
          (item as number) < rule.minimum! || (item as number) > rule.maximum!)) fail('PolicyField');
    }
    const snapshot = Object.freeze(Object.fromEntries(entries));
    snapshots.add(snapshot);
    return snapshot as CapacityPolicy;
  } catch { fail('PolicySnapshot'); }
}

// Only a detached representation of the finite pair. Common validates the
// installed envelope and the SAME original supplier admits actual capacity.
const requestMemorySnapshots = new WeakSet<object>();
export function snapshotRequestMemory(value: unknown): RequestMemory | undefined {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && requestMemorySnapshots.has(value)) return value as RequestMemory;
  const invalid: () => never = () => {throw Object.assign(new TypeError('InvalidInstalledRequestMemory'),
    {code: 'InvalidInstalledRequestMemory'});};
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) invalid();
  const entries = Object.entries(value) as [string, unknown][];
  if (entries.length !== 2 || !entries.some(([name]) => name === 'retainedBytes') ||
      !entries.some(([name]) => name === 'executionBytes') ||
      entries.some(([, amount]) => !Number.isSafeInteger(amount) || Object.is(amount, -0))) invalid();
  const snapshot = Object.freeze(Object.fromEntries(entries));
  requestMemorySnapshots.add(snapshot);
  return snapshot as RequestMemory;
}

const lookupSnapshots = new WeakSet<object>();

// Validate finite lookup ceilings at the Host boundary, never from caller
// Program text. Generic absence remains unresolved; a selected ordinary Local
// factory supplies its installed service limits separately.
export function snapshotHostLookupExecutionPolicy(value: unknown): LookupPolicy | undefined {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && lookupSnapshots.has(value)) return value as LookupPolicy;
  const invalid: () => never = () => { throw Object.assign(new TypeError('InvalidInstalledHostLookupExecutionPolicy'),
    {code: 'InvalidInstalledHostLookupExecutionPolicy'}); };
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) invalid();
    const entries = Object.entries(value) as [string, unknown][];
    const shape = environmentContract.policy_components.lookup_execution.schema;
    const keys = new Set(entries.map(([key]) => key));
    if (entries.length !== shape.required.length ||
        shape.required.some(key => !keys.has(key))) invalid();
    for (const [key, item] of entries) {
      const rule = (shape.properties as Readonly<Record<string, Rule>>)[key];
      if (!Object.hasOwn(shape.properties, key) || (Object.hasOwn(rule, 'const') ? item !== rule.const :
        !Number.isSafeInteger(item) || Object.is(item, -0) ||
          (item as number) < rule.minimum! || (item as number) > rule.maximum!)) invalid();
    }
    const snapshot = Object.freeze(Object.fromEntries(entries));
    lookupSnapshots.add(snapshot);
    return snapshot as LookupPolicy;
  } catch { invalid(); }
}

// The selected ordinary Local factory owns these installed service limits.
// Quote the existing lookup contract conservatively; this DATA is neither
// physical backing, Account/egress permission nor a cleanup acknowledgement.
// Generic and unselected Hosts still keep an omitted policy unresolved.
export function localFilesLookupExecutionPolicy(sourceLimits: unknown) {
  if (!Array.isArray(sourceLimits) || sourceLimits.length < 1) {
    throw new TypeError('InvalidLocalFilesLookupExecutionPolicy');
  }
  // A constant-size projection over the original finite installation, not an
  // independently admitted Source table. Keep every selected service bound;
  // per-entry arithmetic and the nominal transfer Owner still decide limits.
  let perRequest = 0n, total = 0n, duration = 0;
  for (const limits of sourceLimits) {
    const selected = ['maxFiles', 'maxPages', 'maxPageBytes', 'maxDurationMs'].map(name => {
      const field = limits !== null && typeof limits === 'object'
        ? Object.getOwnPropertyDescriptor(limits, name) : undefined;
      if (field === undefined || !Object.hasOwn(field, 'value') ||
          !Number.isSafeInteger(field.value) || field.value <= 0 ||
          field.value > 2147483647) throw new TypeError('InvalidLocalFilesLookupExecutionPolicy');
      return field.value as number;
    });
    const [files, pages, bytes, milliseconds] = selected;
    const request = BigInt(bytes);
    const response = BigInt(files) * BigInt(pages) * request;
    if (response > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new TypeError('InvalidLocalFilesLookupExecutionPolicy');
    }
    if (request > perRequest) perRequest = request;
    if (response > total) total = response;
    if (milliseconds > duration) duration = milliseconds;
  }
  return snapshotHostLookupExecutionPolicy({
    version: 'actql-lookup-execution-policy/0.1',
    // A Local request is attempted once. Historical field names do not
    // create a network plan, retry opportunity or external send authority.
    max_network_attempts_per_request: 1,
    max_request_bytes_per_attempt: Number(perRequest),
    max_total_request_bytes: Number(total),
    max_total_response_bytes: Number(total),
    max_total_decoded_response_bytes: Number(total),
    max_total_duration_ms: duration,
  });
}

// A selected Local service keeps its explicit lookup policy. Only response
// wire transfer has the same dimension as the nominal Resource counter. Peak
// memory is not a cumulative decoded-byte budget, and no row estimate is used.
// This initial ceiling is not remaining capacity: the same Run Ledger still
// reserves actual transfer before every provider operation.
export function localResourceLookupExecutionPolicy(moon: ResourceLookup, original: ResourceOriginal, selected: unknown) {
  const policy = snapshotHostLookupExecutionPolicy(selected);
  if (policy === undefined) return undefined;
  const limits = moon.clientLocalPreparationResourceLimits(original);
  if (!Array.isArray(limits) || limits.length !== 6 ||
      (typeof limits[3] !== 'bigint' && !Number.isSafeInteger(limits[3]))) {
    fail('LocalLookupResourcePolicy');
  }
  const transfer = BigInt(limits[3] as bigint | number);
  if (transfer <= 0n || transfer > BigInt(Number.MAX_SAFE_INTEGER)) fail('LocalLookupResourcePolicy');
  return snapshotHostLookupExecutionPolicy({...policy,
    max_total_response_bytes: Math.min(policy.max_total_response_bytes, Number(transfer))});
}

// The materializing Local Task and SDK collection share one installed byte
// policy. Common derives its necessary row ceiling; this projection grants
// no allocation or permission. Streaming keeps per-row/wire/batch backpressure,
// not collection's cumulative retained-row/byte ceiling.
export function localResourceResultReadLimits(moon: ResourcePolicy, requestMemory: unknown) {
  const memory = snapshotRequestMemory(requestMemory);
  const original = moon.clientLocalResourcePolicyOriginal();
  const limits = moon.clientLocalPreparationResourceLimits(original,
    memory === undefined ? undefined : BigInt(memory.retainedBytes),
    memory === undefined ? undefined : BigInt(memory.executionBytes));
  const maxRows = moon.clientLocalResourcePolicyRowCeiling(original,
    memory === undefined ? undefined : BigInt(memory.retainedBytes),
    memory === undefined ? undefined : BigInt(memory.executionBytes));
  if (!Array.isArray(limits) || limits.length !== 6 ||
      [limits[3], limits[4]].some(value => typeof value !== 'bigint' ||
        value < 1n || value > BigInt(Number.MAX_SAFE_INTEGER)) ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 || maxRows > 2147483647) {
    fail('LocalResultReadPolicyProjection');
  }
  // The existing parser uses one-based Core Int end coordinates, so its
  // selected byte extent must be strictly below Int.max (source_value/input).
  const maxReadWireBytes = Math.min(2147483646, Number(limits[3]));
  const maxRetainedValueBytes = Number(limits[4]);
  return Object.freeze({maxReadWireBytes,
    maxRowWireBytes: Math.min(2147483647, maxReadWireBytes),
    maxRowRetainedValueBytes: maxRetainedValueBytes,
    maxRetainedValueBytes, maxRows, maxBatchRows: 1000,
    maxBatchRetainedValueBytes: Math.min(10 * 1024 * 1024, maxRetainedValueBytes)});
}

export function selectInstalledHostEnvironment(moon: Checker, baseWire: string, selection?: unknown, lookupSelection?: unknown) {
  const policy = snapshotHostCapacityPolicy(selection);
  const lookup = snapshotHostLookupExecutionPolicy(lookupSelection);
  if (policy === undefined && lookup === undefined) return baseWire;
  const {evidence_bundle_cid: ignored, ...body} = JSON.parse(baseWire) as WirePolicy;
  void ignored;
  body.host_policy_profile = {...body.host_policy_profile,
    ...(policy === undefined ? {} : {capacity: policy}),
    ...(lookup === undefined ? {} : {lookup_execution: lookup})};
  const evidenceCid = contentCid(body);
  const wire = canonicalJson({...body, evidence_bundle_cid: evidenceCid});
  if (moon.clientProgramCheckEnvironment(wire, evidenceCid,
    false, false, true, false, false, false, false) === undefined) fail('PolicyAdmission');
  return wire;
}

// Only the selected in-process materializing Local installation consumes this
// nominal policy. It is a necessary row ceiling, not a new resource grant:
// the actual checked plan must still fund all cells, names and live workspaces.
// With no explicit Host policy, use the same installed Model request window
// as execution; the generic Environment defaults are not this service profile.
// Generic Hosts and independently installed Effect/streaming profiles retain
// their original selector and policy identity.
export function selectInstalledLocalMaterializationEnvironment(
  moon: ResourcePolicy & Checker, baseWire: string, selection?: unknown, lookupSelection?: unknown,
  requestMemory?: unknown, selectFinalGraphDefaults = false,
) {
  const explicit = snapshotHostCapacityPolicy(selection);
  const memory = snapshotRequestMemory(requestMemory);
  const original = moon.clientLocalResourcePolicyOriginal();
  const rows = moon.clientLocalResourcePolicyRowCeiling(original,
    memory === undefined ? undefined : BigInt(memory.retainedBytes),
    memory === undefined ? undefined : BigInt(memory.executionBytes));
  if (!Number.isSafeInteger(rows) || rows < 1 || rows > 2147483647) {
    fail('LocalResourcePolicyProjection');
  }
  const base = (JSON.parse(baseWire) as WirePolicy).host_policy_profile.capacity;
  // The no-Model/no-Calendar Host can select its same existing final defaults
  // before Source constructors receive their base. Independent Model and
  // Calendar documents keep their existing separate final admission route.
  const capacity = {...(selectFinalGraphDefaults === true ? {
    max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000} : {}),
    ...(explicit ?? base)};
  if (explicit === undefined) {
    const modelRequestBytes = moon.clientLocalResourcePolicyModelRequestByteCeiling(original);
    if (typeof modelRequestBytes !== 'bigint' || modelRequestBytes < 1n ||
        modelRequestBytes > BigInt(Number.MAX_SAFE_INTEGER)) fail('LocalModelRequestPolicyProjection');
    capacity.max_model_request_bytes_per_item = Number(modelRequestBytes);
  }
  for (const field of ['max_relation_output_rows', 'max_artifact_rows', 'max_file_listing_items'] as const) {
    // The ordinary Local service selects a finite listing policy from its
    // same Resource owner. It is a ceiling, never an observed Source count.
    // An explicitly omitted optional policy stays unresolved.
    if (explicit === undefined || explicit[field] !== undefined) {
      capacity[field] = explicit === undefined ? rows : Math.min(explicit[field]!, rows);
    }
  }
  return selectInstalledHostEnvironment(moon, baseWire, capacity, lookupSelection);
}
