// Native probe accounting DATA. The original Core record owns every field;
// the original physical close path owns its separate stop acknowledgement.
import assert from 'node:assert/strict';
import {ledgerUsageFields, ledgerUsageSpentFields} from '../../adapters/host-node/ledger-contract.generated.mjs';

// The same Core pending-resource predicate owns the spent-field projection.
// Every other declared field remains pending until its lifetime is reviewed.
const spent = new Set(ledgerUsageSpentFields);

export function admitNativeDiagnosticLedgerUsage(usage) {
  assert(usage && typeof usage === 'object' && !Array.isArray(usage),
    'InvalidNativeProductLedger');
  const keys = Reflect.ownKeys(usage);
  assert(keys.length === ledgerUsageFields.length && keys.every(key =>
    typeof key === 'string' && ledgerUsageFields.some(field => field.name === key)),
  'InvalidNativeProductLedgerFields');
  const snapshot = {};
  for (const {name, bits} of ledgerUsageFields) {
    const descriptor = Object.getOwnPropertyDescriptor(usage, name);
    const value = descriptor?.value;
    assert(descriptor && Object.hasOwn(descriptor, 'value') &&
      Number.isSafeInteger(value) && value >= 0 &&
      (bits > 53 || value <= Number((1n << BigInt(bits - 1)) - 1n)),
    `InvalidNativeProductLedger:${name}`);
    if (!spent.has(name)) assert.equal(value, 0, `NativeProductCleanupPending:${name}`);
    snapshot[name] = value;
  }
  return Object.freeze(snapshot);
}
