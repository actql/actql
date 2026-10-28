import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const fixture = JSON.parse(read('portability/corpus/policy-candidates.json'));
assert.equal(fixture.version, 'actql-policy-candidates-vectors/0.1');
assert.equal(fixture.body[0], 'actql-policy-candidates/0.1');
verifyIdentity(fixture.body, fixture.expected_cid);
// Reconstruct this fixed test's Program identity and assignment projection from
// its authored inputs, independently of MoonBit emitters and planner output.
const expression_contract_cid = machineCid(JSON.parse(read('spec/contracts/actql-expressions.json')));
const declaration = {type: 'number', nullable: false};
const reference = {name: 'minimum', path: '/steps/0/filter/gt/1', type: declaration};
const imported = stage => ({result: {stage, result: 'r'}});
const inputs = [{remote: {connector: 'crm/main', resource: 'r'}},
  {x: imported('a')}, {x: imported('a')}, {x: imported('compute_a')}];
const stages = inputs.map((input, index) => ({
  version: 'actql-stage-semantics/0.1', expression_contract_cid,
  parameters: index === 0 ? {minimum: declaration} : {},
  parameter_references: index === 0 ? [reference] : [],
  bindings: {}, binding_references: [],
  local_body: {effects: {}, inputs: input,
    steps: [{filter: {[index === 3 ? 'lt' : 'gt']: [{field: 'id'},
      index === 0 ? {$param: 'minimum'} : {literal: [0, 2, 0, 9][index]}]},
    ...(index === 0 ? {as: 'filtered'} : {})},
    {select: ['id'], as: index === 0 ? 'captured' : 'out'}],
    results: {r: {from: index === 0 ? 'captured' : 'out', fields: ['id']}}},
}));
const semantics = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
  expression_contract_cid, parameters: {minimum: declaration},
  parameter_references: [{...reference, path: '/stages/0' + reference.path}],
  bindings: {}, binding_references: [],
  program_template: {stages: stages.map((stage, index) => ({
    id: ['a', 'compute_a', 'compute_b', 'compute_c'][index],
    after: index === 0 ? 'initial' : 'completed',
    imports: index === 0 ? {} : inputs[index], stage_semantics_cid: machineCid(stage),
  })), exports: {b: {from: {stage: 'compute_b', result: 'r'}},
    c: {from: {stage: 'compute_c', result: 'r'}}}},
};
const program = {version: 'actql-program-definition/0.1', id: 'p',
  program_semantics_cid: machineCid(semantics)};

// Retain both original fixture pins with complete independent preimages. Only
// the governing expression contract changes when projecting this fixed Program
// into the current envelope; offers and placement expectations stay authored.
const history = JSON.parse(read('portability/corpus/policy-candidates-history.json'));
assert.deepEqual(history.snapshots.map(snapshot => [snapshot.source,
  snapshot.program_definition_cid, snapshot.candidate_body_cid]), [
  ['b8d02a73532e54f30b3fb50c4544d2cc22064910',
    'sha256:63af34b702f8d1b719cc9492d220c9c6929b2b047cd0e4837d70d1ef9d3a0dfd',
    'sha256:5b3f6dac6e99538cb6963afd12a73d6e59a0ff67cfd85a17f850bff0cb3fe261'],
  ['43de8ca411b01d09ca86f9e5ef300fa22f1c9bc2',
    'sha256:45157dc423eb7eed95271b2f1ed9780a86cc2718b3f49386cb7cc58db9b293f2',
    'sha256:0a3c4757bbdc6c2907b2a0cdb05d80b2b1074bb173d0cf62f331434078542726'],
]);
for (const snapshot of history.snapshots) {
  assert.equal(snapshot.stage_semantics.length, stages.length);
  for (const [index, stage] of snapshot.stage_semantics.entries()) {
    assert.equal(stage.expression_contract_cid, snapshot.expression_contract_cid);
    assert.equal(machineCid(stage),
      snapshot.program_semantics.program_template.stages[index].stage_semantics_cid);
    assert.deepEqual({...stage, expression_contract_cid}, stages[index]);
  }
  assert.equal(snapshot.program_semantics.expression_contract_cid,
    snapshot.expression_contract_cid);
  verifyIdentity(snapshot.program_semantics,
    snapshot.program_definition.program_semantics_cid);
  verifyIdentity(snapshot.program_definition, snapshot.program_definition_cid);
  assert.deepEqual(snapshot.program_definition,
    {...program, program_semantics_cid: machineCid(snapshot.program_semantics)});
  assert.deepEqual({...snapshot.program_semantics, expression_contract_cid,
    program_template: {...snapshot.program_semantics.program_template,
      stages: snapshot.program_semantics.program_template.stages.map((stage, index) =>
        ({...stage, stage_semantics_cid: machineCid(stages[index])}))}}, semantics);
  assert.equal(snapshot.candidate_body[1], snapshot.program_definition_cid);
  verifyIdentity(snapshot.candidate_body, snapshot.candidate_body_cid);
  assert.deepEqual([snapshot.candidate_body[0], fixture.body[1],
    ...snapshot.candidate_body.slice(2)], fixture.body);
}
const offer = (task, duckdb) => duckdb
  ? [task, 'duckdb', '21', 8, '100000', '100', '134217728', '0',
    [[[0, 2, 3, 5, 6, 7], '1'], [[1, 4], '20']], null]
  : [task, 'local', '10', 5, '0', '8000000', '64000000', '0',
    [[[0, 1, 2, 3, 4], '10']], null];
const assignments = Array.from({length: 8}, (_, position) => {
  const selected = [(position >> 2) & 1, (position >> 1) & 1, position & 1];
  const duckdb = selected.reduce((sum, value) => sum + value, 0);
  return [position, String(30 + 11 * duckdb), String(100000 * duckdb),
    String(8000000 * (3 - duckdb) + 100 * duckdb),
    duckdb ? '134217728' : '64000000',
    [null, ...selected.map((value, index) => offer(index + 1, value))]];
});
// Repin this independently authored current fixture when its Program contract
// changes. Never read the product writer or change the fixed offer projection.
const expectedBody = ['actql-policy-candidates/0.1', machineCid(program), 0, 1, true, assignments];
if (process.argv.includes('--write')) {
  assert.deepEqual([fixture.body[0], expectedBody[1], ...fixture.body.slice(2)], expectedBody);
  fixture.body[1] = machineCid(program);
  fixture.expected_cid = machineCid(fixture.body);
  writeFileSync(new URL('../portability/corpus/policy-candidates.json', import.meta.url),
    JSON.stringify(fixture, null, 2) + '\n');
}
assert.deepEqual(fixture.body, expectedBody);
const text = canonicalText(fixture.body);
const generated = `// Generated by scripts/check-policy-candidates.mjs --write. Do not edit.
// Independently authored projection; never captured from the product writer.

///|
fn expected_policy_candidates() -> String {
  (
    #|${text}
  )
}

///|
fn expected_policy_candidates_cid() -> String {
  ${JSON.stringify(fixture.expected_cid)}
}
`;
const path = new URL('../src/query_integration/policy_candidates_body_wbtest.mbt', import.meta.url);
assert(process.argv.length === 2 || process.argv.length === 3 && process.argv[2] === '--write');
if (process.argv[2] === '--write') writeFileSync(path, generated);
else assert.equal(readFileSync(path, 'utf8'), generated, 'stale policy candidate body/CID vector');
console.log('Policy candidate initial-contract body, CID and consuming vector verified.');
