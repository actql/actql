import {ledgerUsageFields} from './ledger-contract.generated.mjs';
import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from './fixtures/ledger-usage.mjs';
// Physical-accounting component cases using the real checked RowRun owner.
// The in-process page driver is not an HTTP, credential, or installed artifact
// acceptance fixture. Its observation does not issue an identity or permission.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from
  './installed-row-source.mjs';

const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
const observation = Buffer.from('{"portalId":7}');
const rows = [{id: 2}];
const body = Buffer.from(JSON.stringify(rows));

async function fixture(readPages) {
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{
      resource: 'records', resource_kind: 'record', fields: [{
        name: 'id', type: 'number', nullable: false}]}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(
    (await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(
    environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: 'observation-accounting', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'records'}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: ['id'], as: 'output'}],
      results: {r: {from: 'output', fields: ['id']}}}],
    results: {r: {from: {stage: 'scan', result: 'r'}}}}),
  'json', checkedEnvironment, undefined);
  const preparedProgram = moon.clientProgramPreparationReady(outcome);
  assert.ok(preparedProgram);
  const [registry, aoa] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse)]);
  const adapter = await createInstalledRowSource({moon, declaration, declared,
    environmentWire: environment.wire, connectorId: 'fixture',
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    site: {connection: 'fixture:records', issueReadGrant: () => ({}), close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: 'fixture-context'}},
    readOperation: 'read', physicalTarget: (resource, fields) => ({resource, fields}),
    readPages, bindingCid: `sha256:${'a'.repeat(64)}`,
    limits: {maxPages: 2, maxPageBytes: 128, maxPageRows: 2, maxCaptureRows: 2}});
  const inputs = {preparedProgram, registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  const preparedSource = await adapter.prepare(inputs);
  // Independent finite test capacity, not an adopted normal Host price.
  const ledger = checked(moon.clientProgramAcquisitionLedger(
    1, 1, 256n, 100000000n, 100000000n, 0));
  return {adapter, inputs: {...inputs, preparedSource}, ledger};
}

test('accounted ordinary driver charges an observation without adding a captured row', async t => {
  let originalCharge, retainedCallback;
  const value = await fixture(async ({chargePage, consumeObservation, consumePage}) => {
    assert.equal(typeof consumeObservation, 'function');
    originalCharge = chargePage(observation);
    consumeObservation(originalCharge);
    retainedCallback = consumeObservation;
    assert.equal(consumePage(rows, {charge: chargePage(body)}), 1);
  });
  const capture = await value.adapter.openCapture({...value.inputs, ledger: value.ledger});
  t.after(() => capture.close());
  assert.equal(moon.clientProgramCapturedSourceRowCount(capture.identity), 1);
  assert.notEqual(capture.capture.originalRead(), undefined);
  const usage = moon.clientProgramMultiCapturedLedgerUsage(value.ledger);
  assert.equal(ledgerUsageSnapshot(usage).transferredBytes, BigInt(observation.byteLength + body.byteLength));
  // Ordinary capture moves the measured original allocation into its holding
  // and settles the remaining attempt capacity (file_listing_capacity.mbt).
  // The holding, rather than the settled scratch reservation, stays live.
  assert.ok(ledgerUsageSnapshot(usage).heldBytes > 0n);
  assert.deepEqual([ledgerUsageSnapshot(usage).reservedTransferBytes, ledgerUsageSnapshot(usage).reservedRetentionBytes, ledgerUsageSnapshot(usage).reservedExecutionBytes], [0n, 0n, 0n]);
  capture.close();
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(value.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),
    [0n, 0n, 0n, 0n]);
  assert.throws(() => retainedCallback(originalCharge), {code: 'MoonBitHostFailure'});
});

test('omitting or replaying an observation ticket refuses capture and retires its original reservation', async () => {
  for (const replay of [false, true]) {
    const value = await fixture(async ({chargePage, consumeObservation}) => {
      const charge = chargePage(observation);
      if (replay) {
        consumeObservation(charge);
        consumeObservation(charge);
      }
    });
    await assert.rejects(value.adapter.openCapture({...value.inputs, ledger: value.ledger}),
      {code: 'MoonBitHostFailure'});
    const usage = moon.clientProgramMultiCapturedLedgerUsage(value.ledger);
    assert.equal(ledgerUsageSnapshot(usage).transferredBytes, BigInt(observation.byteLength));
    assert.deepEqual(ledgerUsageFieldsFor(usage, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
});

test('unaccounted legacy driver receives no observation-consumption capability', async () => {
  let calls = 0;
  const value = await fixture(async ({consumeObservation, consumePage}) => {
    calls++;
    assert.equal(consumeObservation, undefined);
    assert.equal(consumePage(rows), 1);
  });
  const capture = await value.adapter.openCapture(value.inputs);
  assert.equal(calls, 1);
  assert.equal(moon.clientProgramCapturedSourceRowCount(capture.identity), 1);
  capture.close();
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(value.ledger),
    Array(ledgerUsageFields.length).fill(0n));
});
