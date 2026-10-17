// Test-only original Accounted RowRun assembly, not a normal funding quote.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
const repo = new URL('../../../../', import.meta.url);
const read = name => readFile(new URL(name, repo), 'utf8');

export async function accountedKintoneResponses(catalog, stopped, {fields, programId}) {
  const original = checked(common.clientProgramKintoneDeclareRecords(catalog,
    undefined, fields, 'kintone', 'kintone/0.1', 'inquiries',
    common.clientProgramKintoneValueLimits(8, 512, 1000, 16, 8192),
    common.clientProgramKintoneDeclarationLimits(200000, 20000, 20, 16, 16)));
  const declaration = common.clientProgramKintoneRecordDeclaration(original);
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(await read('spec/local-check-environment.json'), declared);
  const check = common.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(check);
  const outcome = common.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: programId, stages: [{id: 'scan',
      inputs: {remote: {connector: 'kintone', resource: 'inquiries', view: 'records'}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: ['$id'], as: 'output'}],
      results: {r: {from: 'output', fields: ['$id']}}}],
    results: {r: {from: {stage: 'scan', result: 'r'}}}}), 'json', check, undefined);
  const program = common.clientProgramPreparationReady(outcome);
  assert.ok(program);
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'), read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'), read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement = checked(common.clientProgramPrepareLocalQueryRequirement(program, 0, 0,
    registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const prepared = checked(common.clientProgramKintonePrepareRead(original, requirement, query, evidence));
  // Explicit independent fixture units, never a normal physical funding quote.
  const ledger = checked(common.clientProgramAcquisitionLedger(1, 1, 65536n, 100000000n, 100000000n, 0));
  const acquisition = common.clientProgramKintoneReadAcquisition(prepared);
  const run = checked(common.clientProgramRowSourceStartAccounted(
    acquisition, randomUUID(), stopped, ledger, 65536n, 32768n));
  checked(common.clientProgramRowSourceBegin(run, 8192, 2, 2, undefined));
  const borrow = checked(common.clientProgramRowSourceBorrowResponses(run, acquisition));
  checked(common.clientProgramRowSourceBindResponseCleanup(borrow, stopped));
  return {
    charge: body => checked(common.clientProgramRowSourceChargePage(run, body)),
    consume: charge => checked(common.clientProgramRowSourceConsumeObservationCharge(run, charge)),
    usage: () => common.clientProgramMultiCapturedLedgerUsage(ledger),
    close: () => checked(common.clientProgramRowSourceCloseAccounted(run)),
    assertNoCapture: () => assert.throws(() => checked(common.clientProgramRowSourceCapture(run)),
      {code: 'MoonBitHostFailure'}),
  };
}

