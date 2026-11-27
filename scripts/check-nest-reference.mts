import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fixtures } from '../portability/corpus/nest-graph-fixtures.mjs';
import { machineCid } from './actql-spec-family.mjs';

type Admitted = {identity_envelopes: unknown; stage_semantics_cid: string; program_semantics_cid: string;
  program_definition_cid: string; aoa_logical_cid: string; pipeline: unknown};
type Artifact = Admitted | {error: string};
function lower(inputs: unknown): Artifact[];
function lower(inputs: unknown, success: false): void;
function lower(inputs: unknown, success = true): Artifact[] | void {
  const result = spawnSync('python3', ['-B', 'portability/python/nest_graph.py'], {
    input: JSON.stringify(inputs), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  if (!success) { assert.notEqual(result.status, 0); return; }
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return JSON.parse(result.stdout);
}
const artifacts = lower(fixtures);
assert.equal(artifacts.length, fixtures.length, 'one lowering outcome per authored fixture');
function admitted(artifact: Artifact | undefined): Admitted {
  assert.ok(artifact && !('error' in artifact), 'expected admitted nest reference');
  return artifact;
}
const expressionCid = machineCid(JSON.parse(readFileSync('spec/contracts/actql-expressions.json', 'utf8')));
for (const [i, fixture] of fixtures.entries()) {
  const outcome = artifacts[i];
  if (fixture.name === 'unresolved-authored-tie') {
    assert.deepEqual(outcome, { error: 'ACTQL_E_ORDER_REQUIRED' }); continue;
  }
  const artifact = admitted(outcome);
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
const [original] = fixtures;
assert.ok(original);
const originalArtifact = admitted(artifacts[0]);
const renamed = structuredClone(original); renamed.program.id += '.renamed';
const renamedArtifact = admitted(lower([renamed])[0]);
assert.equal(renamedArtifact.stage_semantics_cid, originalArtifact.stage_semantics_cid);
assert.equal(renamedArtifact.program_semantics_cid, originalArtifact.program_semantics_cid);
assert.notEqual(renamedArtifact.program_definition_cid, originalArtifact.program_definition_cid);
const renamedStage = structuredClone(original); renamedStage.program.stages[0].id = 'renamed';
renamedStage.program.results.main.from.stage = 'renamed';
const renamedStageArtifact = admitted(lower([renamedStage])[0]);
assert.equal(renamedStageArtifact.stage_semantics_cid, originalArtifact.stage_semantics_cid);
assert.notEqual(renamedStageArtifact.program_semantics_cid, originalArtifact.program_semantics_cid);
lower([{...original, program: {...original.program, inputs: {}}}], false);
lower([{...original, program: {version: 'actql/0.1', ...original.program.stages[0]}}], false);

const expected = { version: 'actql-nest-canonical-goldens/0.1', oracle: 'portability/python/nest_graph.py',
  cases: fixtures.map((fixture, i) => ({ name: fixture.name, ...artifacts[i] })) };
const path = 'portability/corpus/actql-nest-canonical-v0.1.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(expected, null, 2) + '\n');
else assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), expected, 'Independent nest golden drift');
console.log(JSON.stringify({ cases: fixtures.length, independent_identity_checks: true, runtime_conformance: false }));
