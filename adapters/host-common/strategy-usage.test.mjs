import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore, ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources} from './runtime-core.mjs';
import {ledgerUsageFields} from './ledger-contract.generated.mjs';

const camel = name => name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase());

test('strategy usage preserves every actual Core field and its original nonzero value', () => {
  const setup = {};
  const values = ledgerUsageFields.map(({bits}, index) =>
    bits === 64 ? (1n << 53n) + BigInt(index) : BigInt(index + 101));
  const original = [...values];
  let reads = 0;
  const core = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'unused fixture metadata',
    strategyHostUsage(actual) {
    assert.strictEqual(actual, setup);
    reads++;
    return values;
  }});
  const usage = core.usage(setup);
  assert.deepEqual(Object.keys(usage), ledgerUsageFields.map(({name}) => camel(name)));
  for (const [index, {name}] of ledgerUsageFields.entries()) {
    assert.equal(usage[camel(name)], original[index], name);
  }
  assert.equal(reads, 1);
  assert(Object.isFrozen(usage));
  values.fill(0n);
  assert.equal(usage.reservedAttempts, 103n);
  assert.equal(usage.liveReservations, 105n);
  assert.equal(usage.liveDelegations, 106n);
  assert.equal(usage.uncertainTransferBytes, (1n << 53n) + 7n);
  assert.equal(usage.peakRetentionBytes, (1n << 53n) + 12n);
});

test('strategy usage refuses a missing or extended runtime layout without padding fields', () => {
  for (const values of [Array(8).fill(1n), Array(ledgerUsageFields.length + 1).fill(1n), {}]) {
    const core = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'unused fixture metadata',
      strategyHostUsage: () => values});
    assert.throws(() => core.usage({}), {name: 'TypeError', message: 'InvalidStrategyLedgerUsage'});
  }
});

test('shared usage adapter preserves each pending counter and only Core-owned spent exclusions', () => {
  const spent = new Set(['planning_work', 'attempts', 'transferred_bytes', 'peak_retention_bytes']);
  for (const [index, {name}] of ledgerUsageFields.entries()) {
    const values = Array(ledgerUsageFields.length).fill(0n);
    values[index] = 17n;
    assert.equal(ledgerUsageHasPendingResources(values), !spent.has(name), name);
    assert.equal(ledgerUsageSnapshot(values)[camel(name)], 17n);
    assert.equal(ledgerUsageDiagnostic(values)[camel(name)], '17');
  }
});

test('all shared usage projections refuse old sparse noninteger and out-of-range layouts', () => {
  const malformed = [Array(9).fill(0n), Array(14).fill(0n), Array(13), {}];
  for (const [index, value] of [[0, 1], [0, -1n], [0, 2147483648n], [12, 9223372036854775808n]]) {
    const values = Array(13).fill(0n); values[index] = value; malformed.push(values);
  }
  for (const value of malformed) for (const project of [ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources]) {
    assert.throws(() => project(value), {name:'TypeError', message:'InvalidStrategyLedgerUsage'});
  }
});
