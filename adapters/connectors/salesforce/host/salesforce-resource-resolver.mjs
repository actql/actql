import {requireAuthorizedDispatch} from
  '../../../host-common/authorization-gate.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

// Why an observation cannot answer for a Resource the caller may see. A
// Resource the caller may not see is refused before this (never disclosed,
// present or absent).
// - `listing_truncated`: a provider listing was cut off by its limits.
// - `not_visible`: a complete listing did not include it.
// - `not_observed`: outside a targeted (describe-only) observation's names.
// - `not_found`: an authorized describe was answered as not found for this
//   principal. A permission failure is never reported as `not_found`.
// - `describe_unavailable`: the describe failed, was refused by the provider
//   or was interrupted; the Resource's state is unknown.
export function catalogRequiredReason(state, named) {
  if (state === -2) return named ? 'not_observed' : 'listing_truncated';
  if (state === -1) return 'not_visible';
  if (state === 8) return 'not_found';
  return 'describe_unavailable';
}

const fields = Object.freeze([
  'tenant', 'principal', 'environment', 'connection_revision', 'org_id',
  'site_key', 'site_generation', 'connector_registration',
  'connector_revision', 'resource_origin', 'run_invocation_cid',
  'dispatch_request_cid', 'sync_occurrence',
]);
const names = /^[A-Za-z_][A-Za-z0-9_]{0,254}$/u;
const operations = Object.freeze({create: 0, update: 1, upsert: 2});

const fail = () => {
  throw Object.assign(new Error('InvalidSalesforceResourceResolution'), {
    code: 'InvalidSalesforceResourceResolution',
  });
};

// This is a disclosure-checked candidate from one exact Resource observation.
// The common Effect/Acquisition owner must still admit current use and refresh
// the Catalog before any external request. No credential is used here.
export async function resolveSalesforceResource({moon, catalog, binding,
  authorization, connection, resource, operation, fieldNames,
  externalIdField = '', maxSoqlBytes = 4096, maxFields = 256, signal}) {
  if (!moon || !catalog?.observation || !binding || !authorization ||
      typeof authorization.authorize !== 'function' ||
      typeof connection !== 'string' || connection.length === 0 ||
      typeof resource !== 'string' || !names.test(resource) ||
      !Array.isArray(fieldNames) || fieldNames.length === 0 ||
      fieldNames.length > maxFields || !fieldNames.every(name =>
        typeof name === 'string' && names.test(name)) ||
      !Number.isSafeInteger(maxSoqlBytes) || maxSoqlBytes < 1 ||
      maxSoqlBytes > 1_000_000 ||
      !Number.isSafeInteger(maxFields) || maxFields < 1 ||
      maxFields > 100_000 ||
      !(operation === 'read' || Object.hasOwn(operations, operation)) ||
      (operation === 'upsert' && !names.test(externalIdField)) ||
      (operation !== 'upsert' && externalIdField !== '')) fail();
  const ownedBinding = Object.freeze(Object.fromEntries(fields.map(name => {
    const value = binding[name];
    if (name === 'site_generation'
      ? !Number.isSafeInteger(value) || value < 0
      : typeof value !== 'string' || value.length === 0) fail();
    return [name, value];
  })));
  if (authorization.principal !== ownedBinding.principal ||
      connection !== `salesforce:${ownedBinding.org_id}`) fail();
  const ownedFields = Object.freeze([...fieldNames]);
  const observationCid = moon.salesforceCatalogObservationCid(
    catalog.observation);
  if (catalog.observationCid !== observationCid) fail();
  // Metadata visibility is a read admission. This does not authorize the
  // write operation being described, nor serve as an Effect apply permit.
  await requireAuthorizedDispatch(authorization, 'acquisition', {
    connection, resource, operation: 'read',
  }, {subjectCid: observationCid, signal});
  signal?.throwIfAborted();
  const arguments_ = [catalog.observation, ...fields.map(name =>
    ownedBinding[name]), resource];
  const state = checked(moon.salesforceCatalogObservedResourceState(
    ...arguments_));
  if (state !== 1) {
    return Object.freeze({status: 'catalog_required',
      reason: catalogRequiredReason(state,
        JSON.parse(catalog.observationJson ??
          moon.salesforceCatalogObservationJson(catalog.observation))
          .listing_use_cid === null),
      observationCid});
  }
  const requiredFields = operation === 'upsert'
    ? [...ownedFields, externalIdField] : ownedFields;
  const unconfirmed = checked(moon.salesforceCatalogFirstUnconfirmedField(
    ...arguments_, requiredFields));
  if (typeof unconfirmed === 'string') {
    return Object.freeze({status: 'catalog_required',
      reason: 'field_unconfirmed', field: unconfirmed, observationCid});
  }
  const projection = checked(operation === 'read'
    ? moon.salesforcePrepareReadProjection(...arguments_, ownedFields,
      maxSoqlBytes)
    : moon.salesforcePrepareWriteProjection(...arguments_,
      operations[operation], externalIdField, ownedFields, maxFields));
  return Object.freeze({status: 'ready', observationCid, projection});
}
