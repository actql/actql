import {ledgerUsageFields, ledgerUsageSpentFields} from './ledger-contract.generated.mjs';

type CamelCase<Name extends string> = Name extends `${infer Head}_${infer Tail}`
  ? `${Head}${Capitalize<CamelCase<Tail>>}` : Name;
type LedgerUsageName = CamelCase<typeof ledgerUsageFields[number]['name']>;
type LedgerUsageSnapshot = Readonly<Record<LedgerUsageName, bigint>>;

const usageKeys = Object.freeze(ledgerUsageFields.map(({name}) =>
  name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase())));
const spentUsageKeys = new Set(ledgerUsageSpentFields.map(name =>
  name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase())));

// Both strategy and MultiCaptured bridges return this SAME Core projection.
// Refuse an old/malformed layout; missing counters are never padded to zero.
export function ledgerUsageSnapshot(counts: unknown): LedgerUsageSnapshot {
  if (!Array.isArray(counts) || counts.length !== usageKeys.length ||
      ledgerUsageFields.some(({bits}, index) => typeof counts[index] !== 'bigint' ||
        counts[index] < 0n || BigInt.asIntN(bits, counts[index]) !== counts[index])) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  return Object.freeze(Object.fromEntries(counts.map((count: bigint, index) => [usageKeys[index], count]))) as LedgerUsageSnapshot;
}

// The generated exemptions come from Core's actual pending predicate. This
// is a counter observation only, never a physical stop or custody proof.
export function ledgerUsageHasPendingResources(counts: unknown) {
  const usage = ledgerUsageSnapshot(counts);
  return Object.entries(usage).some(([name, value]) => !spentUsageKeys.has(name) && value !== 0n);
}

// The strategy driver already holds the canonical named snapshot. Preserve
// that interface while applying exactly the same generated pending rule.
export function ledgerUsageSnapshotHasPendingResources(usage: unknown) {
  if (usage === null || typeof usage !== 'object' || Array.isArray(usage)) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  const fields = Object.getOwnPropertyDescriptors(usage);
  if (Reflect.ownKeys(fields).length !== usageKeys.length ||
      usageKeys.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
    throw new TypeError('InvalidStrategyLedgerUsage');
  }
  return ledgerUsageHasPendingResources(usageKeys.map(name => fields[name].value));
}

export function ledgerUsageDiagnostic(counts: unknown): Readonly<Record<LedgerUsageName, string>> {
  return Object.freeze(Object.fromEntries(Object.entries(ledgerUsageSnapshot(counts))
    .map(([name, value]) => [name, value.toString()]))) as Readonly<Record<LedgerUsageName, string>>;
}
