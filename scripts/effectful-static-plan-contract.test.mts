import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {buildControlRegistry, privateSampleEvidenceNames} from './interactive-run-control-contract.mjs';
import {validWireEffectfulStaticPlanViewShape, validWireExplanationContextShape,
  validWirePlanViewShape, validWireRunExplanationContextViewShape, validWireStaticExplanationViewShape} from
  '../packages/client-wire/interactive-control.generated.js';
import {effectfulStaticPlan, computationPlan, commandMember,
  positiveEffectfulPlans, negativeEffectfulPlans} from './fixtures/effectful-static-plan-vectors.mjs';
import {cid} from './fixtures/interactive-run-control-vectors.mjs';

test('Explanation Context admits structural declarations and refuses leaked or invented data', () => {
  const type = {projection: 'shape_and_nullability', kind: 'string', nullable: false};
  const unprojected = {state: 'not_projected', reason: 'no_original_port'};
  const source = {kind: 'source',
    stage_input: {kind: 'stage_input', stage_ordinal: 0, input_port_ordinal: 0},
    source_view: {catalog_cid: cid('1'), connector: 'crm', contract_cid: cid('2'),
      resource: 'account', selection: 'explicit', view: 'records'},
    request_kind: 'direct', link_state: 'linked', consuming_ports: [{step_id: cid('3'), port_id: cid('4')}]};
  const model = {kind: 'model_task', task_id: 'model-task:tag.v1', task_version: 'test', contract_cid: cid('5'),
    dispatch_unit: 'input_row', producer: unprojected,
    input_bindings: [{role: 'value', binding: {state: 'redacted'}, type}], output_fields: [{name: 'tag', type}]};
  const result = {kind: 'result', name: 'out', stage_ordinal: 0, producer: unprojected};
  const effect = {kind: 'effect_set', unit_id: effectfulStaticPlan.effect_set.unit_id,
    members: [{declaration: effectfulStaticPlan.effect_set.members[0], write_fields: {state: 'declared', fields: ['tag']}}]};
  const context = {version: 'actql-explanation-context/0.1', disclosure: 'structural',
    binding: {program_definition_cid: effectfulStaticPlan.program_definition_cid,
      parameter_values_cid: effectfulStaticPlan.parameter_values_cid,
      check_environment_cid: effectfulStaticPlan.check_environment_cid,
      compiled_plan_cid: computationPlan.compiled_plan_cid, logical_map_cid: computationPlan.logical_map.self_cid},
    items: [source, model, result, effect]};
  // Retained Context without links remains readable without gaining origins.
  assert.equal(validWireExplanationContextShape(context), true);
  const link = {producer: {step_id: cid('6'), port_id: cid('7')},
    consumer: {step_id: cid('3'), port_id: cid('4')}, result_projection: true};
  assert.equal(validWireExplanationContextShape({...context, stage_result_links: [link]}), true);
  for (const invalid of [null, [{}], [{...link, result_projection: 'true'}],
    [{...link, consumer: {...link.consumer, request_body: {}}}]]) {
    assert.equal(validWireExplanationContextShape({...context, stage_result_links: invalid}), false);
  }
  assert.equal(Object.hasOwn(buildControlRegistry().identity_domains, 'explanation_context'), false);
  const mapping = effect.members[0];
  const command = {declaration: commandMember,
    write_fields: {state: 'not_projected', reason: 'command_fields_not_projected'}};
  const contextWithMembers = (members: unknown[]) => ({...context, items: [{...effect, members}]});
  assert.equal(validWireExplanationContextShape(contextWithMembers([command])), true);
  assert.equal(validWireExplanationContextShape(contextWithMembers(
    Array.from({length: 64}, (_, member_ordinal) => ({...mapping,
      declaration: {...mapping.declaration, member_ordinal}})))), true);
  for (const members of [[], Array(65).fill(mapping),
    [{...command, write_fields: mapping.write_fields}],
    [{...mapping, write_fields: command.write_fields}],
  ]) assert.equal(validWireExplanationContextShape(contextWithMembers(members)), false);
  for (const item of [
    {...source, link_state: 'not_projected'},
    {...source, consuming_ports: []},
    {...source, source_view: {...source.source_view, request_body: {}}},
    {...model, prompt: 'secret'},
    {...model, input_bindings: [{...model.input_bindings[0], binding: {state: 'redacted', length: 6}}]},
    {...result, actual_rows: 1},
    {...effect, current_approval: 'approved'},
  ]) assert.equal(validWireExplanationContextShape({...context, items: [item]}), false);
});

test('Effectful static envelope preserves the independent original Plan/map schemas', () => {
  const registry = buildControlRegistry();
  assert.equal(registry.schema_cids.plan_view,
    'sha256:51856c457b3eae9724d9626319ad865f38baee748f341f179d3575b2558c5bf4');
  assert.equal(validWireEffectfulStaticPlanViewShape(effectfulStaticPlan), true);
  assert.equal(validWirePlanViewShape(computationPlan), true);
  assert.equal(validWirePlanViewShape(effectfulStaticPlan), false);
  assert.equal(Object.hasOwn(registry.identity_domains, 'effectful_static_plan_view'), false);
  assert.equal(JSON.parse(canonicalText(effectfulStaticPlan)).computation.scope, 'computation_component');
});

test('versioned static Explanation composes the existing closed schema families', () => {
  const registry = buildControlRegistry();
  const publicPins = Object.fromEntries(Object.entries(registry.schema_cids)
    .filter(([name]) => !privateSampleEvidenceNames.includes(name)));
  const {static_explanation_view: added, run_explanation_context_view: saved,
    explanation_context: contextPin, explanation_expression_node: expressionPin, ...originalPins} = publicPins;
  assert.equal(contextPin, 'sha256:146f86ffe25bc0026368ee0a9d5a3ae03b7f3652de281c5534a95496c615b2fb');
  assert.equal(expressionPin, 'sha256:94384e11128cb1984bad30bd7f3a8867ab73cdfce8a18ded1dd17e4f0cdc00bd');
  assert.match(added, /^sha256:[0-9a-f]{64}$/u);
  assert.match(saved, /^sha256:[0-9a-f]{64}$/u);
  assert.equal(Object.keys(originalPins).length, 43);
  assert.equal(createHash('sha256').update(canonicalText(originalPins)).digest('hex'),
    'cbc75a5d68ee9bc7ba81c5667bee173f95c3fafc599c6a9ec33ea5a21da58a99');
  assert.equal(Object.hasOwn(registry.identity_domains, 'static_explanation_view'), false);
  const binding = {program_definition_cid: effectfulStaticPlan.program_definition_cid,
    parameter_values_cid: effectfulStaticPlan.parameter_values_cid,
    compiled_plan_cid: computationPlan.compiled_plan_cid, logical_map_cid: computationPlan.logical_map.self_cid};
  const envelope = {version: 'actql-static-explanation/0.1', plan: effectfulStaticPlan,
    facts: {version: 'actql-explanation-facts/0.1', disclosure: 'structural', ...binding, steps: [], self_cid: cid('f')},
    context: {version: 'actql-explanation-context/0.1', disclosure: 'structural',
      binding: {...binding, check_environment_cid: effectfulStaticPlan.check_environment_cid}, items: []}};
  assert.equal(validWireStaticExplanationViewShape(envelope), true);
  assert.equal(validWireStaticExplanationViewShape({...envelope, plan: computationPlan}), true);
  for (const value of [effectfulStaticPlan, {...envelope, version: undefined},
    {...envelope, version: 'actql-explanation-context/0.1'}, {...envelope, facts: undefined},
    {...envelope, context: undefined}, {...envelope, plan: null}, {...envelope, run_ref: {}},
    {...envelope, context: {...envelope.context, source_body: {}}},
  ]) assert.equal(validWireStaticExplanationViewShape(value), false);
});

test('Saved Explanation Context has its own closed original Run response', () => {
  const saved = {version: 'actql-run-explanation-context-view/0.1',
    run_ref: {namespaceId: 'local', authorityScopeCid: cid('1'), runDefinitionCid: cid('2')},
    explanation: {state: 'not_projected', reason: 'not_retained'}};
  assert.equal(validWireRunExplanationContextViewShape(saved), true);
  for (const value of [{...saved, version: 'actql-static-explanation/0.1'},
    {...saved, run_ref: undefined},
    {...saved, run_ref: {...saved.run_ref, runDefinitionCid: 'foreign'}},
    {...saved, explanation: {...saved.explanation, context: {}}},
    {...saved, explanation: {state: 'not_projected', reason: 'forbidden'}},
    {...saved, explanation: {state: 'projected'}},
  ]) assert.equal(validWireRunExplanationContextViewShape(value), false);
});

test('declared minimum none/required and Command not-represented remain separate from permission', () => {
  for (const value of positiveEffectfulPlans) {
    assert.equal(validWireEffectfulStaticPlanViewShape(value), true);
    assert.deepEqual(value.observations.permission, {state: 'unknown', reason: 'not_observed'});
    assert.deepEqual(value.observations.preview, {state: 'unavailable', reason: 'not_sealed'});
  }
  assert.deepEqual(commandMember.minimum_approval, {kind: 'not_represented'});
});

test('independent closed negatives refuse physical, approval and input-namespace inventions', () => {
  for (const value of negativeEffectfulPlans) assert.equal(validWireEffectfulStaticPlanViewShape(value), false);
});

test('independent envelope canonical bytes stay fixed and validation does not mutate them', () => {
  const value = structuredClone(effectfulStaticPlan), before = canonicalText(value);
  assert.equal(Buffer.byteLength(before), 3344);
  assert.equal(createHash('sha256').update(before).digest('hex'),
    '3517c301ab1ade01b82ac5dcefbd2b00420e9a6b103a7fea7ee6ba94bda278e6');
  assert.equal(validWireEffectfulStaticPlanViewShape(value), true);
  assert.equal(canonicalText(value), before);
});
