// Explicit Host configuration of the existing capacity contract. This is
// neither caller Program input nor an adapter-owned policy override.
import contract from '../../spec/contracts/actql-capacity-host-policy.json' with {type: 'json'};
import environmentContract from '../../spec/contracts/actql-check-environment.json' with {type: 'json'};
import {canonicalJson, contentCid} from './local-account-config.mjs';

const snapshots = new WeakSet();
const fail = cause => {
  throw Object.assign(new TypeError('InvalidInstalledHostCapacityPolicy', {cause}),
    {code: 'InvalidInstalledHostCapacityPolicy'});
};

export function snapshotHostCapacityPolicy(value) {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && snapshots.has(value)) return value;
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) fail('PolicyShape');
    // Read each application-owned field once before any asynchronous boundary.
    // The registered contract is flat; no private/nested object is retained.
    const entries = Object.entries(value);
    const shape = contract.schema;
    const keys = new Set(entries.map(([key]) => key));
    if (entries.length > Object.keys(shape.properties).length ||
        shape.required.some(key => !keys.has(key))) fail('PolicyFields');
    for (const [key, item] of entries) {
      const rule = shape.properties[key];
      if (!Object.hasOwn(shape.properties, key) || (Object.hasOwn(rule, 'const') ? item !== rule.const :
        !Number.isSafeInteger(item) || Object.is(item, -0) ||
          item < rule.minimum || item > rule.maximum)) fail('PolicyField');
    }
    const snapshot = Object.freeze(Object.fromEntries(entries));
    snapshots.add(snapshot);
    return snapshot;
  } catch { fail('PolicySnapshot'); }
}

const lookupSnapshots = new WeakSet();

// Validate finite lookup ceilings at the Host boundary, never from caller
// Program text. Generic absence remains unresolved; a selected ordinary Local
// factory supplies its installed service limits separately.
export function snapshotHostLookupExecutionPolicy(value) {
  if (value === undefined) return undefined;
  if (value !== null && typeof value === 'object' && lookupSnapshots.has(value)) return value;
  const invalid = () => { throw Object.assign(new TypeError('InvalidInstalledHostLookupExecutionPolicy'),
    {code: 'InvalidInstalledHostLookupExecutionPolicy'}); };
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) invalid();
    const entries = Object.entries(value);
    const shape = environmentContract.policy_components.lookup_execution.schema;
    const keys = new Set(entries.map(([key]) => key));
    if (entries.length !== shape.required.length ||
        shape.required.some(key => !keys.has(key))) invalid();
    for (const [key, item] of entries) {
      const rule = shape.properties[key];
      if (!Object.hasOwn(shape.properties, key) || (Object.hasOwn(rule, 'const') ? item !== rule.const :
        !Number.isSafeInteger(item) || Object.is(item, -0) ||
          item < rule.minimum || item > rule.maximum)) invalid();
    }
    const snapshot = Object.freeze(Object.fromEntries(entries));
    lookupSnapshots.add(snapshot);
    return snapshot;
  } catch { invalid(); }
}

// The selected ordinary Local factory owns these installed service limits.
// Quote the existing lookup contract conservatively; this DATA is neither
// physical backing, Account/egress permission nor a cleanup acknowledgement.
// Generic and unselected Hosts still keep an omitted policy unresolved.
export function localFilesLookupExecutionPolicy(sourceLimits) {
  if (!Array.isArray(sourceLimits) || sourceLimits.length < 1 || sourceLimits.length > 128) {
    throw new TypeError('InvalidLocalFilesLookupExecutionPolicy');
  }
  let perRequest = 0n, total = 0n, duration = 0;
  for (const limits of sourceLimits) {
    const selected = ['maxFiles', 'maxPages', 'maxPageBytes', 'maxDurationMs'].map(name => {
      const field = limits !== null && typeof limits === 'object'
        ? Object.getOwnPropertyDescriptor(limits, name) : undefined;
      if (field === undefined || !Object.hasOwn(field, 'value') ||
          !Number.isSafeInteger(field.value) || field.value <= 0 ||
          field.value > 2147483647) throw new TypeError('InvalidLocalFilesLookupExecutionPolicy');
      return field.value;
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
export function localResourceLookupExecutionPolicy(moon, original, selected) {
  const policy = snapshotHostLookupExecutionPolicy(selected);
  if (policy === undefined) return undefined;
  const limits = moon.clientLocalPreparationResourceLimits(original);
  if (!Array.isArray(limits) || limits.length !== 6 ||
      (typeof limits[3] !== 'bigint' && !Number.isSafeInteger(limits[3]))) {
    fail('LocalLookupResourcePolicy');
  }
  const transfer = BigInt(limits[3]);
  if (transfer <= 0n || transfer > BigInt(Number.MAX_SAFE_INTEGER)) fail('LocalLookupResourcePolicy');
  return snapshotHostLookupExecutionPolicy({...policy,
    max_total_response_bytes: Math.min(policy.max_total_response_bytes, Number(transfer))});
}

export function selectInstalledHostEnvironment(moon, baseWire, selection, lookupSelection) {
  const policy = snapshotHostCapacityPolicy(selection);
  const lookup = snapshotHostLookupExecutionPolicy(lookupSelection);
  if (policy === undefined && lookup === undefined) return baseWire;
  const {evidence_bundle_cid: ignored, ...body} = JSON.parse(baseWire);
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
// Generic Hosts and independently installed Effect/streaming profiles retain
// their original selector and policy identity.
export function selectInstalledLocalMaterializationEnvironment(
  moon, baseWire, selection, lookupSelection,
) {
  const explicit = snapshotHostCapacityPolicy(selection);
  const original = moon.clientLocalResourcePolicyOriginal();
  const rows = moon.clientLocalResourcePolicyRowCeiling(original);
  if (!Number.isSafeInteger(rows) || rows < 1 || rows > 2147483647) {
    fail('LocalResourcePolicyProjection');
  }
  const base = JSON.parse(baseWire).host_policy_profile.capacity;
  const capacity = {...(explicit ?? base)};
  for (const field of ['max_relation_output_rows', 'max_artifact_rows']) {
    capacity[field] = explicit === undefined ? rows : Math.min(explicit[field], rows);
  }
  return selectInstalledHostEnvironment(moon, baseWire, capacity, lookupSelection);
}
