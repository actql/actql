import {checked} from '../../../host-common/runtime-result.mjs';


type Bounds = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxNameUnits: number}>;
type RetainedCatalog = Readonly<{observationJson: string; listBodyBase64: unknown;
  describeBodyBase64: readonly (string | null)[]; maxObservationBytes: number;
  listLimits: Bounds & Readonly<{maxResources: number; maxSelected: number}>;
  describeLimits: Bounds & Readonly<{maxFields: number}>}>;
type EvidenceBinding = Readonly<Record<'namespace_id' | 'principal' | 'environment' | 'connection_revision' |
  'org_id' | 'site_key' | 'connector_registration' | 'connector_revision' | 'resource_origin' |
  'run_invocation_cid' | 'dispatch_request_cid' | 'sync_occurrence', string> & {site_generation: number}>;
type EvidenceResource = Readonly<{outcome?: string; use_cid?: string | null; response_sha256?: string | null}>;
type Evidence = Readonly<{version: unknown; binding: EvidenceBinding; listing_use_cid: string;
  listed_resources: readonly EvidenceResource[]}>;
type Runtime = Readonly<{
  salesforceRecoverCatalogObservation(observation: string, listing: Uint8Array,
    describes: readonly (Uint8Array | undefined)[], outcomes: readonly number[], namespace: string,
    principal: string, environment: string, revision: string, org: string, site: string, generation: number,
    registration: string, connectorRevision: string, origin: string, invocation: string, dispatch: string,
    occurrence: string, listingUse: string, describeUses: readonly (string | undefined)[],
    responseDigests: readonly (string | undefined)[], listBytes: number, listNodes: number, listDepth: number,
    listResources: number, listSelected: number, listNameUnits: number, describeBytes: number, describeNodes: number,
    describeDepth: number, describeFields: number, describeNameUnits: number, observationBytes: number): unknown;
  salesforceCatalogObservationCid(observation: unknown): string;
  salesforceCatalogObservationJson(observation: unknown): string;
}>;
type Recovery = Readonly<{moon: Runtime; retained: RetainedCatalog;
  expectedObservationCid: string; maxRetainedBytes: number}>;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};
const outcomeCodes = Object.freeze({
  described: 1,
  permission_denied: 2,
  rate_limited: 3,
  provider_unavailable: 4,
  transport_interrupted: 5,
  invalid_metadata: 6,
  cancelled: 7,
  not_found: 8,
});
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

function decodeBoundedBase64(value: unknown, remaining: number) {
  if (typeof value !== 'string' || !positive(remaining) ||
      value.length > Math.ceil(remaining / 3) * 4 + 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u
        .test(value)) {
    fail('InvalidRetainedSalesforceCatalog');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.byteLength > remaining || bytes.toString('base64') !== value) {
    fail('InvalidRetainedSalesforceCatalog');
  }
  return bytes;
}

// Restore historical metadata from bounded retained response bytes. The
// MoonBit Catalog owner reprojections must reproduce the exact observation;
// this function never grants a current credential use or a write dispatch.
export function recoverRetainedSalesforceCatalog({moon, retained,
  expectedObservationCid, maxRetainedBytes}: Recovery) {
  if (!moon || !retained || !positive(maxRetainedBytes) ||
      typeof expectedObservationCid !== 'string' ||
      typeof retained.observationJson !== 'string' ||
      !Array.isArray(retained.describeBodyBase64) ||
      !retained.listLimits || !retained.describeLimits ||
      !positive(retained.maxObservationBytes)) {
    fail('InvalidRetainedSalesforceCatalog');
  }
  let body: Evidence;
  try { body = JSON.parse(retained.observationJson); }
  catch { fail('InvalidRetainedSalesforceCatalog'); }
  if (body.version !== 'actql-salesforce-catalog-observation/0.1' ||
      !body.binding || !Array.isArray(body.listed_resources) ||
      body.listed_resources.length !== retained.describeBodyBase64.length) {
    fail('InvalidRetainedSalesforceCatalog');
  }
  let remaining = maxRetainedBytes;
  const listing = decodeBoundedBase64(retained.listBodyBase64, remaining);
  remaining -= listing.byteLength;
  const describes = retained.describeBodyBase64.map(encoded => {
    if (encoded === null) return undefined;
    const bytes = decodeBoundedBase64(encoded, remaining);
    remaining -= bytes.byteLength;
    return bytes;
  });
  const outcomes = body.listed_resources.map(entry => {
    const code = outcomeCodes[entry?.outcome as keyof typeof outcomeCodes];
    if (code === undefined) fail('InvalidRetainedSalesforceCatalog');
    return code;
  });
  const binding = body.binding;
  const list = retained.listLimits;
  const describe = retained.describeLimits;
  const observation = checked(moon.salesforceRecoverCatalogObservation(
    retained.observationJson, listing, describes, outcomes,
    binding.namespace_id, binding.principal, binding.environment,
    binding.connection_revision, binding.org_id, binding.site_key,
    binding.site_generation, binding.connector_registration,
    binding.connector_revision, binding.resource_origin,
    binding.run_invocation_cid, binding.dispatch_request_cid,
    binding.sync_occurrence, body.listing_use_cid,
    body.listed_resources.map(entry => entry.use_cid ?? undefined),
    body.listed_resources.map(entry => entry.response_sha256 ?? undefined),
    list.maxBytes, list.maxNodes, list.maxDepth, list.maxResources,
    list.maxSelected, list.maxNameUnits, describe.maxBytes,
    describe.maxNodes, describe.maxDepth, describe.maxFields,
    describe.maxNameUnits, retained.maxObservationBytes,
  ));
  const observationCid = moon.salesforceCatalogObservationCid(observation);
  if (observationCid !== expectedObservationCid) {
    fail('ForeignRetainedSalesforceCatalog');
  }
  return Object.freeze({observation, observationCid,
    observationJson: moon.salesforceCatalogObservationJson(observation)});
}
