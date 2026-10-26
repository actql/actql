// Synthetic diagnostic admission controls, not a Native execution or stop ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {ledgerUsageFields} from '../../adapters/host-node/ledger-contract.generated.mjs';
import {admitNativeDiagnosticLedgerUsage} from './native-ledger-usage.mjs';

const empty = () => Object.fromEntries(ledgerUsageFields.map(({name}) => [name, 0]));

test('complete Core usage preserves spent work after live resources settle', () => {
  const usage = {...empty(), planning_work: 5, attempts: 2,
    transferred_bytes: 31, peak_retention_bytes: 64};
  assert.deepEqual(admitNativeDiagnosticLedgerUsage(usage), usage);
  assert(Object.isFrozen(admitNativeDiagnosticLedgerUsage(usage)));
});

test('each count-only pending state is refused even with zero byte coverage', () => {
  for (const name of ['reserved_attempts', 'holdings', 'live_reservations', 'live_delegations']) {
    const usage = {...empty(), [name]: 1};
    assert.throws(() => admitNativeDiagnosticLedgerUsage(usage),
      new RegExp(`NativeProductCleanupPending:${name}`));
  }
});

test('uncertain or reserved physical bytes remain pending independently', () => {
  for (const name of ['uncertain_transfer_bytes', 'reserved_transfer_bytes', 'held_bytes',
    'reserved_retention_bytes', 'reserved_execution_bytes']) {
    assert.throws(() => admitNativeDiagnosticLedgerUsage({...empty(), [name]: 1}),
      new RegExp(`NativeProductCleanupPending:${name}`));
  }
});

test('a legacy ten-field report is incomplete, while foreign fields cannot hide it', () => {
  const usage = empty();
  delete usage.reserved_attempts; delete usage.live_reservations; delete usage.live_delegations;
  assert.throws(() => admitNativeDiagnosticLedgerUsage(usage), /InvalidNativeProductLedgerFields/);
  assert.throws(() => admitNativeDiagnosticLedgerUsage({...empty(), foreign: 0}),
    /InvalidNativeProductLedgerFields/);
});

test('numeric diagnostics reject lossy, wrong-width, negative and callback fields', () => {
  for (const value of [Number.MAX_SAFE_INTEGER + 1, -1, '0', NaN, 0.5]) {
    assert.throws(() => admitNativeDiagnosticLedgerUsage({...empty(), transferred_bytes: value}),
      /InvalidNativeProductLedger:transferred_bytes/);
  }
  assert.throws(() => admitNativeDiagnosticLedgerUsage({...empty(), attempts: 2147483648}),
    /InvalidNativeProductLedger:attempts/);
  const usage = empty(); let called = 0;
  Object.defineProperty(usage, 'attempts', {get() { called++; return 0; }});
  assert.throws(() => admitNativeDiagnosticLedgerUsage(usage), /InvalidNativeProductLedger:attempts/);
  assert.equal(called, 0);
});
