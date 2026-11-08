import assert from 'node:assert/strict';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import {installedHubSpotFixture, properties, expected, objectBody} from './installed-hubspot.fixture.mjs';

// Real existing installed Source, TLS/Credential/Account and RowRun/Ledger.
// Full declarations remain intact; the original query still selects its own
// fields. Explicit fixture bounds cover this data, not another product cap.
// Independently authored full native response. Presence is explicit even when
// the selected nullable value is null; MissingProperty remains a refusal.
const additionalProperties = Object.fromEntries(Array.from({length:99}, (_, i) => [`field_${i}`, null]));
const completeNativeResponse = JSON.stringify({results:[{id:'9007199254740993', archived:false,
  properties:{amount:'9007199254740993.01', tags:'a;b', ...additionalProperties}}]});
// Whole-page admitted values: id1 + amount1 + tags(array1+items2) + null99 =104.
// Canonical row wire adds its row object and the enclosing rows array =106.
// These are selected fixture units, not the unrelated Values default100.
const options = () => ({objectResponseBody:completeNativeResponse, propertyDefinitions: {results: [...properties.results,
  ...Array.from({length: 99}, (_, i) => ({name: `field_${i}`, type: 'string', fieldType: 'text'}))]},
sourceLimits: {maxResponseBytes: 8192, maxProperties: 128, maxNameUnits: 2048,
  maxColumns: 128, maxDeclarationBytes: 32768, maxDeclarationNodes: 2000,
  maxValueNodes:104, maxRowsWireNodes:106}});
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
  // Independent fixture inventory, not counts obtained from provider output.
  const nodeCount = value => value === null || typeof value !== 'object' ? 1
    : 1 + Object.values(value).reduce((total, child) => total + nodeCount(child), 0);
  assert.equal(1 + 1 + (1 + 2) + 99, 104);
  assert.equal(nodeCount([{...expected, ...additionalProperties}]), 106);
  const ledger = f.ledger();
  let opened;
  try { opened = await source.openCapture({...preparation, ledger}); }
  catch (error) {
    // Diagnostic enum identity/counts only; never serialize owned state or DATA.
    const enums = [];
    for (let value = error, depth = 0; value && depth < 12; depth++) {
      const name = value.constructor?.name;
      if (typeof name === 'string' && /^_M0DTP[0-9A-Za-z_]+$/.test(name)) {
        enums.push({name:name.match(/\d+([A-Z][A-Za-z]+)$/)?.[1], tag:value.$tag,
          nestedTag:Number.isInteger(value._0) ? value._0 : value._0?.$tag});
        value = value._0;
      } else value = value.cause;
    }
    t.diagnostic(JSON.stringify({enums,requests:f.state.requests.length,resolutions:f.state.resolutions}));
    throw error;
  }
  f.captures.push(opened);
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


test('wide Source still refuses an omitted selected nullable property', async t => {
  const selected = options(); selected.objectResponseBody = objectBody;
  const f = await installedHubSpotFixture(t, selected), source = await f.load(), preparation = await f.prepare(source);
  const ledger = f.ledger();
  await assert.rejects(source.openCapture({...preparation, ledger}), error =>
    error.code === 'MoonBitHostFailure' &&
    error.cause?.cause?.constructor?.name.endsWith('MissingProperty') &&
    error.cause.cause.$tag === 7);
  assert.equal(f.state.requests.length, 3); assert.equal(f.state.resolutions, 3);
  assert.deepEqual(held(ledger), [0n, 0n, 0n, 0n]);
});
