declare const scopeBrand: unique symbol;
declare const budgetBrand: unique symbol;
export type ObservationScope = Readonly<{[scopeBrand]: true}>;
export type ObservationBudget = Readonly<{[budgetBrand]: true}>;
export type ObservationBudgetSnapshot = Readonly<{
  scopeKey: string; requestKey: string; maxRecords: number; maxBytes: number;
  records: number; bytes: number; factHashes: readonly string[];
}>;
/** The caller supplies an existing, authorized installation; no authority grant. */
export function admitObservationScope(options: Readonly<{
  workspace: string; authorityScopeCid: string;
  destinationRevision: string; disclosureRevision: string;
  purpose: 'customer_telemetry' | 'service_operations';
}>): ObservationScope;
export function observationScopeKey(scope: ObservationScope): string;
/** Missing custody on an existing request refuses further optional observation. */
export function openObservationBudget(scope: ObservationScope, requestKey: string,
  options: Readonly<{maxRecords: number; maxBytes: number; freshRequest: boolean;
    saved?: ObservationBudgetSnapshot}>): ObservationBudget;
/** Charge before persistence/enqueue. False is a repeated diagnostic fact only. */
export function chargeObservation(budget: ObservationBudget, scope: ObservationScope,
  requestKey: string, recordBytes: number, fact?: string): boolean;
export function observationBudgetSnapshot(budget: ObservationBudget):
  ObservationBudgetSnapshot;
