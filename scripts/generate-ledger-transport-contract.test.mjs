import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {projectCoreLedger, renderLedgerTransportContract, projectLedgerUsageSpentFields, renderLedgerUsageDiagnostic, renderLedgerAccountingValues} from './generate-ledger-transport-contract.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

const core = readFileSync(new URL('../src/physical_resources/ledger.mbt', import.meta.url), 'utf8') + '\n' +
  readFileSync(new URL('../src/physical_resources/ledger_usage_pending.mbt', import.meta.url), 'utf8');

test('actual Core owns the complete current limits and thirteen-field usage contract', () => {
  const contract = projectCoreLedger(core);
  assert.deepEqual(contract.usage, [
    {name: 'planning_work', bits: 32}, {name: 'attempts', bits: 32},
    {name: 'reserved_attempts', bits: 32}, {name: 'holdings', bits: 32},
    {name: 'live_reservations', bits: 32}, {name: 'live_delegations', bits: 32},
    {name: 'transferred_bytes', bits: 64}, {name: 'uncertain_transfer_bytes', bits: 64},
    {name: 'reserved_transfer_bytes', bits: 64}, {name: 'held_bytes', bits: 64},
    {name: 'reserved_retention_bytes', bits: 64}, {name: 'reserved_execution_bytes', bits: 64},
    {name: 'peak_retention_bytes', bits: 64},
  ]);
  assert.equal(contract.limits.length, 6);
  assert.equal(renderLedgerTransportContract(core), readFileSync(
    new URL('../adapters/host-node/ledger-contract.generated.mjs', import.meta.url), 'utf8'));
});

test('adding a Core field mechanically reaches the generated transport without another schema edit', async () => {
  const changed = core.replace('pub(all) struct LedgerUsage {', 'pub(all) struct LedgerUsage {\n  future_count : Int');
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-ledger-contract-', label: 'Core ledger contract projection'});
  writeFileSync(join(scratch.path, 'ledger-contract.generated.mjs'), renderLedgerTransportContract(changed));
  // The exact production consumer imports the independently changed Core
  // projection. No handwritten replacement codec or field schema is supplied.
  writeFileSync(join(scratch.path, 'process-accounting.mjs'), readFileSync(
    new URL('../adapters/host-node/process-accounting.mjs', import.meta.url)));
  const module = await import(pathToFileURL(join(scratch.path, 'ledger-contract.generated.mjs')).href);
  assert.deepEqual(module.ledgerUsageFields[0], {name: 'future_count', bits: 32});
  assert.equal(module.ledgerUsageFields.length, 14);
  assert(Object.isFrozen(module.ledgerUsageFields));
  assert(module.ledgerUsageFields.every(Object.isFrozen));
  const codec = await import(pathToFileURL(join(scratch.path, 'process-accounting.mjs')).href);
  const usage = {...codec.emptyProcessUsage(), future_count: 7};
  assert.equal(Object.keys(usage).length, 14);
  assert.deepEqual(codec.decodeProcessUsage(codec.encodeProcessUsage(usage)), usage);
  scratch.passed();
});

test('unknown duplicate or missing Core declarations cannot silently produce a transport subset', () => {
  for (const changed of [
    core.replace('reserved_attempts : Int', 'reserved_attempts : String'),
    core.replace('reserved_attempts : Int', 'attempts : Int'),
    core.replace('pub(all) struct LedgerUsage', 'priv struct LedgerUsage'),
    core + '\npub(all) struct LedgerUsage {\n future : Int\n}\n',
  ]) assert.throws(() => projectCoreLedger(changed), /Core ledger/u);
});


test('diagnostic writer and spent projection follow the same Core owner without a parallel field list', () => {
  assert.equal(renderLedgerUsageDiagnostic(core), readFileSync(
    new URL('../src/physical_resources/ledger_usage_diagnostic.generated.mbt', import.meta.url), 'utf8'));
  assert.deepEqual(projectLedgerUsageSpentFields(core), [
    'planning_work', 'attempts', 'transferred_bytes', 'peak_retention_bytes',
  ]);
  const changed = core.replace('pub(all) struct LedgerUsage {', 'pub(all) struct LedgerUsage {\n  future_count : Int');
  assert.match(renderLedgerUsageDiagnostic(changed), /usage\.future_count\.to_string\(\)/u);
  assert.match(renderLedgerUsageDiagnostic(changed), /future_count/u);
  assert(!projectLedgerUsageSpentFields(changed).includes('future_count'));
});

test('an unknown or changed Core pending rule cannot silently produce a spent-field whitelist', () => {
  for (const changed of [
    core.replace('pending != initial_ledger_usage', 'true'),
    core.replace('    transferred_bytes: 0L,\n    peak_retention_bytes: 0L,', '    transferred_bytes: 0,\n    peak_retention_bytes: 0L,'),
    core.replace('    peak_retention_bytes: 0L,\n  }\n  pending', '    absent_count: 0,\n  }\n  pending'),
    core + core.slice(core.indexOf('pub fn ledger_usage_has_pending_resources')),
  ]) assert.throws(() => projectLedgerUsageSpentFields(changed), /Core ledger/u);
});


test('complete Core accounting snapshot uses declared order and exact primitive conversion', () => {
  const generated = renderLedgerAccountingValues(core);
  assert.equal(generated, readFileSync(new URL('../src/physical_resources/ledger_accounting.generated.mbt', import.meta.url), 'utf8'));
  assert.match(generated, /ledger_limits_usage_values\(ledger : Ledger\)/u);
  assert.match(generated, /ledger_usage_values\(usage : LedgerUsage\)/u);
  assert(generated.indexOf('usage.reserved_attempts.to_int64()') < generated.indexOf('usage.holdings.to_int64()'));
  assert.match(generated, /usage\.transferred_bytes,/u);
  assert(!generated.includes('usage.transferred_bytes.to_int64()'));
  const changed = core.replace('pub(all) struct LedgerUsage {', 'pub(all) struct LedgerUsage {\n  future_count : Int');
  const after = renderLedgerAccountingValues(changed);
  assert.match(after, /usage\.future_count\.to_int64\(\)/u);
  assert(after.indexOf('usage.future_count.to_int64()') < after.indexOf('usage.planning_work.to_int64()'));
  assert.throws(() => renderLedgerAccountingValues(core.replace('reserved_attempts : Int', 'reserved_attempts : String')), /Core ledger/u);
});
