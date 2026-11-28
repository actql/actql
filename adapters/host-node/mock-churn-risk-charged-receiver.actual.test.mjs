import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {inspect} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source-environment.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';

assert.ok(process.env.ACTQL_TEST_DECLARED_MOCK_COMMON_RUNTIME,
  'Select the matching Common runtime containing the charged document receiver');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_DECLARED_MOCK_COMMON_RUNTIME));
assert.equal(typeof moon.clientProgramRelationAcceptChargedDocument, 'function',
  'The selected runtime must contain the original charged document receiver');
const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
const [base, registry, aoa, queryContract, evidenceContract] = await Promise.all([
  read('spec/local-check-environment.json'),
  read('spec/dependencies/aoa-pipeline-registry.json'),
  read('spec/contracts/actql-aoa.json').then(JSON.parse),
  read('spec/contracts/actql-query-acquisition.json'),
  read('spec/contracts/actql-query-process-evidence.json'),
]);
const values = JSON.stringify(aoa.execution_contracts['REL.values']);
const fragment = JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
const ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
const sequenceContracts = checked(moon.clientPrepareInstalledSequenceContracts(registry, values, fragment, ordered));
const project = projectTemplateFiles('churn-risk-mock');
const catalogue = checked(moon.clientProjectCatalogAdmit(project['mock/catalog.json']));
assert.equal(moon.clientProjectCatalogCount(catalogue), 2);
const body = Buffer.from(project['mock/data.json'], 'utf8');
assert.equal(createHash('sha256').update(body).digest('hex'),
  'ea64e222b458b216e18c0ee5b926da728bfcc65545caca7bbb5d3ee806329979',
  'Use the unchanged public project records, including both original keys');

// These are real Common receiver regressions with explicitly unaccounted
// diagnostic RowRuns. The small per-source Programs isolate ticket custody;
// they do not replace the public JOIN/INFER/UPDATE Program or supply a Host,
// authorization, physical capacity, response cleanup or installed acceptance.
function fixture() {
  const entries = Array.from({length: 2}, (_, index) => {
    const name = moon.clientProjectCatalogName(catalogue, index);
    const entry = JSON.parse(moon.clientProjectCatalogEntryOriginalJson(catalogue, index));
    assert.equal(entry.views.length, 1);
    assert.equal(entry.data.length, 1);
    assert.equal(entry.data[0].resource, entry.views[0].resource);
    return {name, view: entry.views[0], binding: entry.data[0],
      declaration: checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
        name, 'declared_file', 'declared_file/0.1',
        checked(moon.clientProjectCatalogRelationDeclarationInput(catalogue, index)), undefined))};
  });
  assert.deepEqual(entries.map(entry => entry.name), ['salesforce', 'snowflake']);
  const acquisitions = entries.map(({name, view, declaration}) => {
    const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
    const environment = rowSourceCheckEnvironment(base, declared);
    const admitted = moon.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
      false, false, true, false, false, false, false);
    assert.ok(admitted);
    const fields = Object.keys(view.schema);
    const program = {version: 'actql/0.1', id: `mock-charge-${name}`,
      stages: [{id: 'scan', inputs: {remote: {connector: name,
        resource: view.resource}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: fields, as: 'rows'}],
      results: {r: {from: 'rows', fields}}}],
      results: {r: {from: {stage: 'scan', result: 'r'}}}};
    const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
      JSON.stringify(program), 'json', admitted, undefined);
    const prepared = moon.clientProgramPreparationReady(outcome);
    assert.ok(prepared, 'The real Common checker must admit the diagnostic source Program');
    let requirement;
    try {
      requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(prepared,
        0, 0, sequenceContracts, values, fragment, ordered));
    } catch (error) {
      assert.fail(`Original ${name} requirement: ${inspect(error.cause ?? error, {depth: 12})}`);
    }
    const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
      declaration, requirement, queryContract, evidenceContract, undefined));
    assert.equal(checked(moon.clientProgramRowSourceRequestWire(acquisition)), '{}');
    return {acquisition, requirement};
  });
  const runs = [];
  function pending(index, nonce) {
    const run = checked(moon.clientProgramRowSourceStart(acquisitions[index].acquisition,
      nonce, () => true));
    runs.push(run);
    return run;
  }
  function start(index, nonce) {
    const run = pending(index, nonce);
    checked(moon.clientProgramRowSourceBegin(run, 65536, 100, 100, undefined));
    return run;
  }
  // begin_row_run uses the existing 400,000-node page ceiling and 20,000,000
  // admission-work ceiling. The decoder conservatively charges those original
  // node ceilings for contract comparisons; this explicit diagnostic budget
  // follows that existing ceiling, not a sampled document size or a grant.
  function projectDocument({binding, declaration}, bytes) {
    const document = checked(moon.clientProgramRelationAdmitDocument(
      bytes, 1048576, 4096, 32, 100, 16777216));
    return checked(moon.clientProgramRelationProjectTargetDocument(document, declaration,
      binding.resource, binding.items_path, binding.key_path, binding.primary_identity, undefined, []));
  }
  function accept(run, charge, index, {acquisition = acquisitions[index].acquisition,
    selected = entries[index], maxWork = 20000000} = {}) {
    try {
      return checked(moon.clientProgramRelationAcceptChargedDocument(run, charge,
        acquisition, projectDocument(selected, body), maxWork));
    } catch (error) {
      error.message += `: ${inspect(error.cause, {depth: 12})}`;
      throw error;
    }
  }
  return {entries, acquisitions, pending, start, accept,
    close() { for (const run of runs) moon.clientProgramRowSourceClose(run); }};
}

function cannotCapture(run) {
  assert.throws(() => checked(moon.clientProgramRowSourceFinish(run)),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)),
    {code: 'MoonBitHostFailure'});
}

test('actual charged receiver captures both original sources with separate one-use tickets', () => {
  const f = fixture();
  try {
    const insufficient = f.start(0, 'original-source-short-work');
    const shortCharge = checked(moon.clientProgramRowSourceChargePage(insufficient, body));
    assert.throws(() => f.accept(insufficient, shortCharge, 0, {maxWork: 1000000}), {code: 'MoonBitHostFailure'});
    cannotCapture(insufficient);
    for (const index of [0, 1]) {
      const run = f.start(index, `original-source-${index}`);
      const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
      assert.equal(f.accept(run, charge, index), 2);
      checked(moon.clientProgramRowSourceFinish(run));
      const capture = checked(moon.clientProgramRowSourceCapture(run));
      const source = checked(moon.clientProgramRowSourceCaptureSource(capture));
      const exported = checked(moon.clientProgramExportSourceCapture(source,
        f.acquisitions[index].requirement, `original-source-${index}`));
      const rows = moon.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
      assert.deepEqual(rows.map(row => row[index === 0 ? 'id' : 'account_id']),
        ['001Acme', '001Globex']);
      if (index === 0) assert.deepEqual(rows.map(row => row.Risk_Reason__c), [null, null]);
      else assert.deepEqual(rows.map(row => row.active_users), ['4', '12']);
    }
  } finally { f.close(); }
});

test('actual charged receiver rejects another RowRun ticket before capture', () => {
  const f = fixture();
  try {
    const first = f.start(0, 'ticket-owner'), second = f.start(1, 'ticket-foreign');
    const charge = checked(moon.clientProgramRowSourceChargePage(first, body));
    assert.throws(() => f.accept(second, charge, 1),
      {code: 'MoonBitHostFailure'});
    cannotCapture(second);
    // Rejection by the foreign Run does not consume the owner's ticket.
    assert.equal(f.accept(first, charge, 0), 2);
  } finally { f.close(); }
});

test('actual charged receiver rejects a replayed ticket without a second capture', () => {
  const f = fixture();
  try {
    const run = f.start(1, 'ticket-replay');
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    assert.equal(f.accept(run, charge, 1), 2);
    assert.throws(() => f.accept(run, charge, 1),
      {code: 'MoonBitHostFailure'});
    cannotCapture(run);
  } finally { f.close(); }
});

test('actual charged receiver rejects an equal-wire foreign acquisition with the original body', () => {
  const f = fixture(), foreign = fixture();
  try {
    const run = f.start(0, 'foreign-acquisition');
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    assert.equal(checked(moon.clientProgramRowSourceRequestWire(f.acquisitions[0].acquisition)),
      checked(moon.clientProgramRowSourceRequestWire(foreign.acquisitions[0].acquisition)));
    assert.throws(() => f.accept(run, charge, 0, {acquisition: foreign.acquisitions[0].acquisition}),
      {code: 'MoonBitHostFailure'});
    cannotCapture(run);
  } finally { f.close(); foreign.close(); }
});

test('actual charged receiver rejects equal-wire declarations issued as different originals', () => {
  const f = fixture(), foreign = fixture();
  try {
    const run = f.start(0, 'foreign-declarations');
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    assert.equal(moon.clientProgramRowSourceDeclarationJson(f.entries[0].declaration),
      moon.clientProgramRowSourceDeclarationJson(foreign.entries[0].declaration));
    assert.throws(() => f.accept(run, charge, 0, {selected: foreign.entries[0]}),
      {code: 'MoonBitHostFailure'});
    cannotCapture(run);
  } finally { f.close(); foreign.close(); }
});

test('actual charged receiver cannot resume a closed attempt with its pending ticket', () => {
  const f = fixture();
  try {
    const run = f.start(0, 'closed-attempt');
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    moon.clientProgramRowSourceClose(run);
    assert.throws(() => f.accept(run, charge, 0),
      {code: 'MoonBitHostFailure'});
    cannotCapture(run);
  } finally { f.close(); }
});

test('same original RowRun admits the document under a narrower page and work envelope', () => {
  const f = fixture();
  try {
    for (const index of [0, 1]) {
      const run = f.pending(index, `narrow-original-${index}`);
      checked(moon.clientProgramRowSourceBeginWithPageLimits(
        run, 1048576, 4096, 32, 100, 100, undefined));
      const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
      assert.equal(f.accept(run, charge, index, {maxWork: 2097152}), 2);
      checked(moon.clientProgramRowSourceFinish(run));
      checked(moon.clientProgramRowSourceCapture(run));
    }
  } finally { f.close(); }
});

test('same original RowRun enforces the selected small node ceiling before capture', () => {
  const f = fixture();
  try {
    const run = f.pending(0, 'narrow-nodes-refusal');
    checked(moon.clientProgramRowSourceBeginWithPageLimits(
      run, 1048576, 10, 32, 100, 100, undefined));
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    assert.throws(() => f.accept(run, charge, 0, {maxWork: 2097152}), {code: 'MoonBitHostFailure'});
    cannotCapture(run);
  } finally { f.close(); }
});

test('original page bounds refuse invalid or widened standard envelopes without capture', () => {
  const f = fixture();
  try {
    for (const [nodes, depth] of [[0, 32], [4096, 0], [400001, 32], [4096, 33]]) {
      const run = f.pending(0, `invalid-page-${nodes}-${depth}`);
      assert.throws(() => checked(moon.clientProgramRowSourceBeginWithPageLimits(
        run, 1048576, nodes, depth, 100, 100, undefined)), {code: 'MoonBitHostFailure'});
      cannotCapture(run);
    }
  } finally { f.close(); }
});
