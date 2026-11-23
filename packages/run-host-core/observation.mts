// Portable MoonBit observation custody. No SDK, network, timers, or Run state.
import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import * as owner from './dist/client_values_host_abi.js';

import type {ObservationScope, ObservationBudget, ObservationBudgetSnapshot} from './observation.d.ts';

type ScopeInput = Parameters<typeof import('./observation.d.ts').admitObservationScope>[0];
type BudgetInput = Parameters<typeof import('./observation.d.ts').openObservationBudget>[2];

const scopes = new WeakMap<object, unknown>(), budgets = new WeakMap<object, unknown>();
const integer = (value: number) => Number.isInteger(value) && value >= -2147483648 &&
  value <= 2147483647;
const fields = ['scopeKey', 'requestKey', 'maxRecords', 'maxBytes',
  'records', 'bytes', 'factHashes'] as const;
function token(map: WeakMap<object, unknown>, value: unknown, kind: string) {
  const handle = Object.freeze({kind});
  map.set(handle, value);
  return handle;
}
function requireToken(map: WeakMap<object, unknown>, handle: object) {
  const value = map.get(handle);
  if (value === undefined) throw new TypeError('ForeignObservationHandle');
  return value;
}
function checked(result: unknown) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('ObservationCustodyRejected', {cause: runtimeField(result, 0)}),
      {code: 'ObservationCustodyRejected'});
  }
  throw new TypeError('InvalidObservationOwnerResult');
}
export function admitObservationScope({workspace, authorityScopeCid,
  destinationRevision, disclosureRevision, purpose}: ScopeInput) {
  if ([workspace, authorityScopeCid, destinationRevision, disclosureRevision]
    .some(value => typeof value !== 'string') ||
    !['customer_telemetry', 'service_operations'].includes(purpose)) {
    throw new TypeError('InvalidObservationScope');
  }
  const value = owner.clientValuesHostObservationScope(workspace,
    authorityScopeCid, destinationRevision, disclosureRevision,
    purpose === 'customer_telemetry');
  if (value === undefined) throw new TypeError('InvalidObservationScope');
  return token(scopes, value, 'observation-scope') as unknown as ObservationScope;
}
export function observationScopeKey(scope: ObservationScope) {
  return owner.clientValuesHostObservationScopeKey(requireToken(scopes, scope));
}
export function openObservationBudget(scope: ObservationScope, requestKey: string,
  {maxRecords, maxBytes, freshRequest, saved}: BudgetInput) {
  if (typeof requestKey !== 'string' || !integer(maxRecords) ||
    !integer(maxBytes) || typeof freshRequest !== 'boolean') {
    throw new TypeError('InvalidObservationBudget');
  }
  if (saved !== undefined && (saved === null || typeof saved !== 'object' ||
    Array.isArray(saved) || Object.keys(saved).length !== fields.length ||
    Object.keys(saved).some(key => !fields.includes(key as typeof fields[number])) ||
    typeof saved.scopeKey !== 'string' || typeof saved.requestKey !== 'string' ||
    (['maxRecords', 'maxBytes', 'records', 'bytes'] as const).some(key => !integer(saved[key])) ||
    !Array.isArray(saved.factHashes) || saved.factHashes.length > 2048 ||
    Array.prototype.findIndex.call(saved.factHashes,
      (value: unknown) => typeof value !== 'string') !== -1)) {
    throw new TypeError('InvalidObservationBudgetSnapshot');
  }
  const value = checked(owner.clientValuesHostObservationBudget(
    requireToken(scopes, scope), requestKey, maxRecords, maxBytes, freshRequest,
    saved?.scopeKey, saved?.requestKey ?? '', saved?.maxRecords ?? 0,
    saved?.maxBytes ?? 0, saved?.records ?? 0, saved?.bytes ?? 0,
    saved?.factHashes ?? []));
  return token(budgets, value, 'observation-budget') as unknown as ObservationBudget;
}
export function chargeObservation(budget: ObservationBudget, scope: ObservationScope, requestKey: string, recordBytes: number, fact?: string) {
  if (typeof requestKey !== 'string' || !integer(recordBytes) ||
    fact !== undefined && typeof fact !== 'string') {
    throw new TypeError('InvalidObservationCharge');
  }
  return checked(owner.clientValuesHostChargeObservation(
    requireToken(budgets, budget), requireToken(scopes, scope), requestKey,
    fact, recordBytes)) as boolean;
}
export function observationBudgetSnapshot(budget: ObservationBudget) {
  const values = owner.clientValuesHostObservationBudgetSnapshot(
    requireToken(budgets, budget));
  return Object.freeze(Object.fromEntries(fields.map((key, index) =>
    [key, key === 'factHashes' ? Object.freeze([...(runtimeField(values, index) as readonly string[])]) :
      runtimeField(values, index)]))) as ObservationBudgetSnapshot;
}
