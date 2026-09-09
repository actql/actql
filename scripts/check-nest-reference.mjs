import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fixtures } from '../portability/corpus/nest-graph-fixtures.mjs';
import { machineCid } from './actql-spec-family.mjs';

function lower(inputs, success = true) {
  const result = spawnSync('python3', ['-B', 'portability/python/nest_graph.py'], {
    input: JSON.stringify(inputs), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  if (!success) { assert.notEqual(result.status, 0); return; }
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return JSON.parse(result.stdout);
}
const artifacts = lower(fixtures);
const expressionCid = machineCid(JSON.parse(readFileSync('spec/contracts/actql-expressions.json', 'utf8')));
for (const [i, fixture] of fixtures.entries()) {
  const artifact = artifacts[i];
  if (fixture.name === 'unresolved-authored-tie') {
    assert.deepEqual(artifact, { error: 'ACTQL_E_ORDER_REQUIRED' }); continue;
  }
  // Build the specified preimages from authored input, independently of Python output.
  const { id, ...local } = fixture.program.stages[0];
  const stage = { version: 'actql-stage-semantics/0.1', expression_contract_cid: expressionCid,
    parameters: {}, parameter_references: [], bindings: {}, binding_references: [], local_body: { ...local, effects: {} } };
  const program = { version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
    expression_contract_cid: expressionCid, parameters: {}, parameter_references: [], bindings: {}, binding_references: [],
    program_template: { stages: [{ id, stage_semantics_cid: machineCid(stage), after: 'initial', imports: {} }], exports: fixture.program.results } };
  const definition = { version: 'actql-program-definition/0.1', id: fixture.program.id, program_semantics_cid: machineCid(program) };
  assert.deepEqual(artifact.identity_envelopes, { stage, program, definition });
  assert.equal(artifact.stage_semantics_cid, machineCid(stage));
  assert.equal(artifact.program_semantics_cid, machineCid(program));
  assert.equal(artifact.program_definition_cid, machineCid(definition));
  assert.equal(artifact.aoa_logical_cid, machineCid(artifact.pipeline));
}
const renamed = structuredClone(fixtures[0]); renamed.program.id += '.renamed';
const renamedArtifact = lower([renamed])[0];
assert.equal(renamedArtifact.stage_semantics_cid, artifacts[0].stage_semantics_cid);
assert.equal(renamedArtifact.program_semantics_cid, artifacts[0].program_semantics_cid);
assert.notEqual(renamedArtifact.program_definition_cid, artifacts[0].program_definition_cid);
const renamedStage = structuredClone(fixtures[0]); renamedStage.program.stages[0].id = 'renamed';
renamedStage.program.results.main.from.stage = 'renamed';
const renamedStageArtifact = lower([renamedStage])[0];
assert.equal(renamedStageArtifact.stage_semantics_cid, artifacts[0].stage_semantics_cid);
assert.notEqual(renamedStageArtifact.program_semantics_cid, artifacts[0].program_semantics_cid);
const invalid = structuredClone(fixtures[0]); invalid.program.inputs = {};
lower([invalid], false);
const flat = structuredClone(fixtures[0]);
flat.program = { version: 'actql/0.1', ...flat.program.stages[0] };
lower([flat], false);

const expected = { version: 'actql-nest-canonical-goldens/0.1', oracle: 'portability/python/nest_graph.py',
  cases: fixtures.map((fixture, i) => ({ name: fixture.name, ...artifacts[i] })) };
const path = 'portability/corpus/actql-nest-canonical-v0.1.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(expected, null, 2) + '\n');
else assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), expected, 'Independent nest golden drift');
console.log(JSON.stringify({ cases: fixtures.length, independent_identity_checks: true, runtime_conformance: false }));
