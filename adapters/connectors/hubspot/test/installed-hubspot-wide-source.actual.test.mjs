import assert from 'node:assert/strict';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import {installedHubSpotFixture, properties, expected} from './installed-hubspot.fixture.mjs';

// Real existing installed Source, TLS/Credential/Account and RowRun/Ledger.
// Full declarations remain intact; the original query still selects its own
// fields. Explicit fixture bounds cover this data, not another product cap.
const options = () => ({propertyDefinitions: {results: [...properties.results,
  ...Array.from({length: 99}, (_, i) => ({name: `field_${i}`, type: 'string', fieldType: 'text'}))]},
sourceLimits: {maxResponseBytes: 8192, maxProperties: 128, maxNameUnits: 2048,
  maxColumns: 128, maxDeclarationBytes: 32768, maxDeclarationNodes: 2000}});
const held = ledger => ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger),
  ['reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']);

test('wide Source initialization preserves its complete declared schema without a Values-derived ceiling', async t => {
  const f = await installedHubSpotFixture(t, options()), source = await f.load();
  const env = JSON.parse(source.environmentWire), carrier = env.contract_registry.find(value => value.kind === 'carrier_schema');
  assert.equal(Object.keys(carrier.body.fields).length, 102);
  assert.deepEqual(carrier.body.fields.field_98, {type: 'string', nullable: true});
  assert.equal(common.clientProgramInstalledSourceReaderPolicy()[2], 100, 'the unrelated Values default stays unchanged');
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('wide Source reads the complete declared schema through its original funded RowRun', async t => {
  const f = await installedHubSpotFixture(t, options()), source = await f.load(), preparation = await f.prepare(source);
  const ledger = f.ledger();
  const opened = await source.openCapture({...preparation, ledger}); f.captures.push(opened);
  const exported = checked(common.clientProgramExportSourceCapture(opened.capture.source(), opened.requirement, 'wide-source-read'));
  assert.deepEqual(common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse), [expected]);
  assert.equal(f.state.requests.length, 4); assert.equal(f.state.resolutions, 4);
  await opened.close();
  assert.deepEqual(held(ledger), [0n, 0n, 0n, 0n]);
});

test('Source still refuses an unfunded original RowRun before credential resolution or transport', async t => {
  const f = await installedHubSpotFixture(t), source = await f.load(), preparation = await f.prepare(source);
  const ledger = checked(common.clientProgramAcquisitionLedger(1, 1, 32768n, 1n, 1n, 0));
  await assert.rejects(source.openCapture({...preparation, ledger}), error => {
    return error.code === 'MoonBitHostFailure' && error.outcome === 'not_started' &&
      error.cause?.cause?.constructor?.name.endsWith('Physical') &&
      error.cause.cause._0 === 5; // compiled LedgerIssue.RetentionLimit, as in the original Ledger enum
  });
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(held(ledger), [0n, 0n, 0n, 0n]);
});

test('declared Source column bounds still reject a complete wide schema before Site IO', async t => {
  const selected = options(); selected.sourceLimits.maxColumns = 101;
  const f = await installedHubSpotFixture(t, selected);
  await assert.rejects(f.load(), error => error.code === 'InstalledHostInitializationFailed' &&
    error.cause?.code === 'MoonBitHostFailure');
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});
