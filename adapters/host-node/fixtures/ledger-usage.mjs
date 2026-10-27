import {ledgerUsageSnapshot} from '../../host-common/runtime-core.mjs';

// A test may assert a named subset of counters. Read the original snapshot
// once; this helper defines no ABI order or pending-resource exemption.
export function ledgerUsageFieldsFor(values, names) {
  const usage = ledgerUsageSnapshot(values);
  return names.map(name => {
    if (!Object.hasOwn(usage, name)) throw new TypeError('UnknownTestLedgerUsageField');
    return usage[name];
  });
}
