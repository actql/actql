import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';
import {ledgerUsageFields} from '../host-node/ledger-contract.generated.mjs';

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
