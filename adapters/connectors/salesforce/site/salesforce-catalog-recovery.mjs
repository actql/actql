import {checked} from '../../../host-common/runtime-result.mjs';

const fail = code => {
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
const positive = value => Number.isSafeInteger(value) && value > 0;

function decodeBoundedBase64(value, remaining) {
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
  expectedObservationCid, maxRetainedBytes}) {
  if (!moon || !retained || !positive(maxRetainedBytes) ||
      typeof expectedObservationCid !== 'string' ||
      typeof retained.observationJson !== 'string' ||
      !Array.isArray(retained.describeBodyBase64) ||
      !retained.listLimits || !retained.describeLimits ||
      !positive(retained.maxObservationBytes)) {
    fail('InvalidRetainedSalesforceCatalog');
  }
  let body;
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
    const code = outcomeCodes[entry?.outcome];
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
