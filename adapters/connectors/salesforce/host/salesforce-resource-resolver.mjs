import {requireAuthorizedDispatch} from
  '../../../host-common/authorization-gate.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

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
      reason: state === -2 ? 'listing_truncated' :
        state === -1 ? 'not_visible' : 'describe_unavailable',
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
