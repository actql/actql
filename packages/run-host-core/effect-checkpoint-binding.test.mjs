import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitEnvironment, prepareEffect, compileEffect, issueAllowedEffectRun,
  issueEffectRunDefinition, privateRunDefinition, issueEffectRunMaterials,
  admitEffectRunMaterials, effectReviewCheckpointBinding, effectReviewCheckpointMembers} from '@actql/run-host-core';
import {checkpointSealBody} from '@actql/run-host-core/checkpoints';
import {buildSync} from 'esbuild';
const fixed = character => 'sha256:' + character.repeat(64);
const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
function original(document = read('source-compute-effect.program.json')) {
  const environmentWire = read('source-compute-effect.environment.json');
  const environment = admitEnvironment(environmentWire, JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
  const prepared = prepareEffect(document, 'json', environment);
  const compilation = compileEffect(prepared);
  const allowed = issueAllowedEffectRun(prepared, compilation, {executionContextCid: fixed('a'), hostPolicyCid: fixed('b'), expiresAt: '2026-10-11T00:00:00.000Z'});
  const definition = issueEffectRunDefinition(allowed, 'scope', 'original-run', '2026-10-09T00:00:00.000Z', '2026-10-10T00:00:00.000Z');
  const body = {version: 'actql-execution-checkpoint/0.1', checkpoint_id: 'review', run_id: 'original-run',
    run_definition_cid: privateRunDefinition(definition).cid, continuation_state_cid: fixed('1'),
    subject: {kind: 'run_unit', run_id: 'original-run', unit_id: 'compute', continuation: 'resume_unit'},
    phase: 'commit', kind: 'effect_set', required_artifact: {artifact_type: 'effect_set_preview', artifact_cid: fixed('2')},
    review_projection_cid: fixed('3'), requirements: ['effect_scope_approved'], reason_code: 'effect_review', human_summary: 'Review',
    created_at: '2026-10-09T01:00:00.000Z', expires_at: '2026-10-09T02:00:00.000Z'};
  const seal = value => {const result = JSON.parse(checkpointSealBody(JSON.stringify(value))); assert.equal(result.ok, true); return result.checkpoint_wire;};
  return {allowed, definition, body, seal, document, environment, environmentWire};
}

test('Effect Checkpoint metadata binds the original Run/unit after exact materials restoration', () => {
  const f = original();
  const wire = f.seal(f.body);
  const bound = effectReviewCheckpointBinding(f.allowed, f.definition, wire);
  assert.deepEqual(bound, {checkpointCid: JSON.parse(wire).checkpoint_cid, checkpointWire: wire,
    runId: 'original-run', unitId: 'compute', runDefinitionCid: f.body.run_definition_cid,
    previewCid: fixed('2'), reviewProjectionCid: fixed('3'), continuationCid: fixed('1')});
  assert(Object.isFrozen(bound));
  const members = effectReviewCheckpointMembers(f.allowed, f.definition, wire);
  assert.deepEqual(members, ['save']); assert(Object.isFrozen(members));
  const materials = issueEffectRunMaterials(f.allowed, f.definition, {format: 'json', document: f.document, environment: f.environment, environmentWire: f.environmentWire});
  const restored = admitEffectRunMaterials(materials, f.body.run_definition_cid, {rela: true});
  assert.deepEqual(effectReviewCheckpointBinding(restored.allowed, restored.definition, wire), bound);
  assert.deepEqual(effectReviewCheckpointMembers(restored.allowed, restored.definition, wire), members);
  // Synthetic metadata CIDs exercise binding, not Native custody or approval.
});

test('Effect Checkpoint metadata refuses another unit, Run, review or extended window', () => {
  const f = original();
  const variants = [
    {...f.body, subject: {...f.body.subject, unit_id: 'acquire'}},
    {...f.body, run_id: 'other', subject: {...f.body.subject, run_id: 'other'}},
    {...f.body, run_definition_cid: fixed('f')},
    {...f.body, requirements: ['effect_scope_approved', 'partial_application_accepted']},
    {...f.body, expires_at: '2026-10-10T00:00:01.000Z'},
  ];
  for (const body of variants) {
    assert.throws(() => effectReviewCheckpointBinding(f.allowed, f.definition, f.seal(body)), {code: 'RunHostEffectCheckpointBindingRejected'});
    assert.throws(() => effectReviewCheckpointMembers(f.allowed, f.definition, f.seal(body)), {code: 'RunHostEffectCheckpointMembersRejected'});
  }
  const other = issueEffectRunDefinition(f.allowed, 'scope', 'other', '2026-10-09T00:00:00.000Z', '2026-10-10T00:00:00.000Z');
  assert.throws(() => effectReviewCheckpointBinding(f.allowed, other, f.seal(f.body)), {code: 'RunHostEffectCheckpointBindingRejected'});
  assert.throws(() => effectReviewCheckpointBinding({...f.allowed}, f.definition, f.seal(f.body)), /ForeignRunHostHandle/u);
  assert.throws(() => effectReviewCheckpointBinding(f.allowed, {...f.definition}, f.seal(f.body)), /ForeignRunHostHandle/u);
  assert.throws(() => effectReviewCheckpointBinding(f.allowed, f.definition, {}), /InvalidRunHostCheckpointWire/u);
  assert.throws(() => effectReviewCheckpointMembers({...f.allowed}, f.definition, f.seal(f.body)), /ForeignRunHostHandle/u);
  assert.throws(() => effectReviewCheckpointMembers(f.allowed, {...f.definition}, f.seal(f.body)), /ForeignRunHostHandle/u);
  assert.throws(() => effectReviewCheckpointMembers(f.allowed, f.definition, 'x'.repeat(65537)), /InvalidRunHostCheckpointWire/u);
});

test('Effect Checkpoint binding bundles for a Worker without a physical Host', () => {
  const result = buildSync({stdin: {contents: "export {effectReviewCheckpointBinding} from '@actql/run-host-core';", resolveDir: import.meta.dirname}, bundle: true, write: false, platform: 'browser', format: 'esm', target: 'es2022', metafile: true});
  assert(Object.keys(result.metafile.inputs).every(path => !path.includes('host-node') && !path.startsWith('node:')));
});

test('Checkpoint members use all original terminal-unit members without accepting a new caller selection', () => {
  const program = JSON.parse(read('source-compute-effect.program.json'));
  const effects = program.stages[1].effects;
  effects.secondary = structuredClone(effects.save);
  const f = original(JSON.stringify(program));
  const wire = f.seal(f.body);
  const expected = ['save', 'secondary'];
  assert.deepEqual(effectReviewCheckpointMembers(f.allowed, f.definition, wire), expected);
  const materials = issueEffectRunMaterials(f.allowed, f.definition,
    {format: 'json', document: f.document, environment: f.environment, environmentWire: f.environmentWire});
  const restored = admitEffectRunMaterials(materials, f.body.run_definition_cid, {rela: true});
  assert.deepEqual(effectReviewCheckpointMembers(restored.allowed, restored.definition, wire), expected);
  const foreign = f.seal({...f.body, subject: {...f.body.subject, unit_id: 'acquire'}});
  assert.throws(() => effectReviewCheckpointMembers(restored.allowed, restored.definition, foreign),
    {code: 'RunHostEffectCheckpointMembersRejected'});
});
