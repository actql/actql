// Portable MoonBit observation custody. No SDK, network, timers, or Run state.
import * as owner from './dist/client_values_host_abi.js';

const scopes = new WeakMap(), budgets = new WeakMap();
const integer = value => Number.isInteger(value) && value >= -2147483648 &&
  value <= 2147483647;
const fields = ['scopeKey', 'requestKey', 'maxRecords', 'maxBytes',
  'records', 'bytes', 'lastFact'];
function token(map, value, kind) {
  const handle = Object.freeze({kind});
  map.set(handle, value);
  return handle;
}
function requireToken(map, handle) {
  const value = map.get(handle);
  if (value === undefined) throw new TypeError('ForeignObservationHandle');
  return value;
}
function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error('ObservationCustodyRejected', {cause: result._0}),
      {code: 'ObservationCustodyRejected'});
  }
  throw new TypeError('InvalidObservationOwnerResult');
}
export function admitObservationScope({workspace, authorityScopeCid,
  destinationRevision, disclosureRevision, purpose}) {
  if ([workspace, authorityScopeCid, destinationRevision, disclosureRevision]
    .some(value => typeof value !== 'string') ||
    !['customer_telemetry', 'service_operations'].includes(purpose)) {
    throw new TypeError('InvalidObservationScope');
  }
  const value = owner.clientValuesHostObservationScope(workspace,
    authorityScopeCid, destinationRevision, disclosureRevision,
    purpose === 'customer_telemetry');
  if (value === undefined) throw new TypeError('InvalidObservationScope');
  return token(scopes, value, 'observation-scope');
}
export function observationScopeKey(scope) {
  return owner.clientValuesHostObservationScopeKey(requireToken(scopes, scope));
}
export function openObservationBudget(scope, requestKey,
  {maxRecords, maxBytes, freshRequest, saved}) {
  if (typeof requestKey !== 'string' || !integer(maxRecords) ||
    !integer(maxBytes) || typeof freshRequest !== 'boolean') {
    throw new TypeError('InvalidObservationBudget');
  }
  if (saved !== undefined && (saved === null || typeof saved !== 'object' ||
    Array.isArray(saved) || Object.keys(saved).length !== fields.length ||
    Object.keys(saved).some(key => !fields.includes(key)) ||
    typeof saved.scopeKey !== 'string' || typeof saved.requestKey !== 'string' ||
    ['maxRecords', 'maxBytes', 'records', 'bytes'].some(key => !integer(saved[key])) ||
    saved.lastFact !== null && typeof saved.lastFact !== 'string')) {
    throw new TypeError('InvalidObservationBudgetSnapshot');
  }
  const value = checked(owner.clientValuesHostObservationBudget(
    requireToken(scopes, scope), requestKey, maxRecords, maxBytes, freshRequest,
    saved?.scopeKey, saved?.requestKey ?? '', saved?.maxRecords ?? 0,
    saved?.maxBytes ?? 0, saved?.records ?? 0, saved?.bytes ?? 0,
    saved?.lastFact ?? undefined));
  return token(budgets, value, 'observation-budget');
}
export function chargeObservation(budget, scope, requestKey, recordBytes, fact) {
  if (typeof requestKey !== 'string' || !integer(recordBytes) ||
    fact !== undefined && typeof fact !== 'string') {
    throw new TypeError('InvalidObservationCharge');
  }
  return checked(owner.clientValuesHostChargeObservation(
    requireToken(budgets, budget), requireToken(scopes, scope), requestKey,
    fact, recordBytes));
}
export function observationBudgetSnapshot(budget) {
  const values = owner.clientValuesHostObservationBudgetSnapshot(
    requireToken(budgets, budget));
  return Object.freeze(Object.fromEntries(fields.map((key, index) =>
    [key, values[`_${index}`] ?? null])));
}
