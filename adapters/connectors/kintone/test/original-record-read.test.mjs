import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual normal Common and generated Node forwarding. These tests exercise
// original RowRun custody, not physical Site/App authentication or installed I/O.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';

const repo = new URL('../../../../', import.meta.url);
const read = path => readFile(new URL(path, repo), 'utf8');
const bytes = value => Buffer.from(JSON.stringify(value));
const form = {revision: '7', properties: {
  Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'},
  Tags: {code: 'Tags', type: 'MULTI_SELECT', options: {
    red: {label: 'red', index: '0'}, 東京: {label: '東京', index: '1'}}},
}};
const formBody = bytes(form);
const formLimits = () => moon.clientProgramKintoneFormLimits(8192, 1000, 16, 16, 512);
const pageLimits = () => moon.clientProgramKintonePageLimits(8192, 1000, 16, 4, 8, 64, 16);
const valueLimits = () => moon.clientProgramKintoneValueLimits(8, 128, 1000, 16, 8192);
const record = id => ({$id: {type: '__ID__', value: id},
  $revision: {type: '__REVISION__', value: '9'},
  Subject: {type: 'SINGLE_LINE_TEXT', value: '東京\r\nnext'},
  Tags: {type: 'MULTI_SELECT', value: ['red', '東京', 'red']}});
const page = ids => bytes({records: ids.map(record), totalCount: '999999'});

async function preparation() {
  const originalForm = checked(moon.clientProgramKintoneProjectForm(formBody, '12', formLimits()));
  const original = checked(moon.clientProgramKintoneDeclareRecords(originalForm, undefined,
    ['Subject', 'Tags'], 'kintone', 'kintone/0.1', 'inquiries', valueLimits(),
    moon.clientProgramKintoneDeclarationLimits(200000, 20000, 32, 1, 8)));
  const declaration = moon.clientProgramKintoneRecordDeclaration(original);
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(await read('spec/local-check-environment.json'), declared);
  const check = moon.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(check);
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: 'kintone-original-reader', stages: [{id: 'a',
      inputs: {remote: {connector: 'kintone', resource: 'inquiries', view: 'records'}},
      steps: [{filter: "Subject <> ''", as: 'filtered'},
        {select: ['$id', 'Subject', 'Tags'], as: 'captured'},
        {from: 'captured', assert_rows: {unique_by: ['$id']}, as: 'unique_records'},
        {from: 'unique_records', sort: [{$id: 'asc'}], as: 'ordered_records'}],
      results: {r: {from: 'ordered_records', fields: ['$id', 'Subject', 'Tags']}}}],
    results: {records: {from: {stage: 'a', result: 'r'}}}}), 'json', check, undefined);
  const program = moon.clientProgramPreparationReady(outcome);
  assert.ok(program, inspect(moon.clientProgramPreparationIssue(outcome), {depth: 8}));
  const [registry, aoa, query, evidence] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json')]);
  const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(program, 0, 0,
    registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  return checked(moon.clientProgramKintonePrepareRead(original, requirement, query, evidence));
}

async function originalRead(t) {
  const prepared = await preparation();
  const acquisition = moon.clientProgramKintoneReadAcquisition(prepared);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 32768n,
    100000000n, 100000000n, 0));
  let stopped = false;
  const run = checked(moon.clientProgramRowSourceStartAccounted(acquisition,
    randomUUID(), () => stopped, ledger, 32768n, 8192n));
  checked(moon.clientProgramRowSourceBegin(run, 8192, 4, 4, undefined));
  const reader = checked(moon.clientProgramKintoneBorrowRead(prepared, run,
    pageLimits(), valueLimits(), 100));
  checked(moon.clientProgramKintoneBindReadCleanup(reader, () => stopped));
  t.after(() => {
    stopped = true;
    checked(moon.clientProgramKintoneRetireRead(reader));
    checked(moon.clientProgramRowSourceCloseAccounted(run));
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  });
  return {prepared, acquisition, run, reader, ledger, stop: () => {stopped = true;}};
}

test('actual kintone bridge keeps the original App/projection and closed cursor presence', async () => {
  const prepared = await preparation();
  assert.equal(moon.clientProgramKintoneReadApp(prepared), '12');
  const fields = moon.clientProgramKintoneReadFields(prepared);
  fields[0] = 'foreign';
  assert.deepEqual(moon.clientProgramKintoneReadFields(prepared), ['Subject', 'Tags']);
  assert.deepEqual(JSON.parse(checked(moon.clientProgramKintoneFormRequestBody(prepared, 4096))), {app: '12'});
  assert.deepEqual(JSON.parse(checked(moon.clientProgramKintonePageRequestBody(prepared,
    ['9007199254740993'], 500, 4096))), {app: '12', fields: ['$id', '$revision', 'Subject', 'Tags'],
    query: '$id > 9007199254740993 order by $id asc limit 500'});
  for (const cursor of [[''], ['1', '2'], ['1 or true']]) {
    assert.throws(() => checked(moon.clientProgramKintonePageRequestBody(prepared,
      cursor, 2, 4096)), {code: 'MoonBitHostFailure'});
  }
});

test('actual kintone Form/page forwards consume original bytes and retain the same cleanup reservation', async t => {
  const f = await originalRead(t);
  checked(moon.clientProgramKintoneRecheckReadForm(f.reader, formBody, formLimits()));
  const body = page(['9007199254740992', '9007199254740993']);
  assert.equal(checked(moon.clientProgramKintoneAcceptReadPage(f.reader, body)), 2);
  assert.deepEqual(checked(moon.clientProgramKintonePageNextCursor(f.reader, [], 2)), ['9007199254740993']);
  const ids = checked(moon.clientProgramKintoneReadPageIds(f.reader));
  ids[0] = 'foreign';
  assert.deepEqual(checked(moon.clientProgramKintoneReadPageIds(f.reader)), ['9007199254740992', '9007199254740993']);
  assert.throws(() => checked(moon.clientProgramKintoneRetireRead(f.reader)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceCloseAccounted(f.run)), {code: 'MoonBitHostFailure'});
  assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(f.ledger)).reservedExecutionBytes > 0n);
});

test('actual kintone bridge refuses changed Form and cannot finish the original RowRun', async t => {
  const f = await originalRead(t);
  checked(moon.clientProgramKintoneRecheckReadForm(f.reader, formBody, formLimits()));
  assert.throws(() => checked(moon.clientProgramKintoneRecheckReadForm(f.reader,
    bytes({...form, revision: '8'}), formLimits())), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceFinish(f.run)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceCloseAccounted(f.run)), {code: 'MoonBitHostFailure'});
});

test('actual kintone bridge refuses foreign acquisition and repeated cross-page cursor', async t => {
  const f = await originalRead(t);
  const other = await preparation();
  assert.throws(() => checked(moon.clientProgramKintoneBorrowRead(other, f.run,
    pageLimits(), valueLimits(), 100)), {code: 'MoonBitHostFailure'});
  checked(moon.clientProgramKintoneAcceptReadPage(f.reader, page(['2'])));
  assert.throws(() => checked(moon.clientProgramKintonePageNextCursor(f.reader,
    ['2'], 2)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceFinish(f.run)), {code: 'MoonBitHostFailure'});
});
