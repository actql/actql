// Independently authored closed metadata. No compiler, Host or product issuer
// supplies these expected facts or their canonical-byte oracle.
import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';
import {cid, planBody, planCid, mapBody} from './interactive-run-control-vectors.mjs';
const hash = value => `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`;
export const computationPlan = {
  version: 'actql-plan-view/0.1', compiled_plan_cid: planCid,
  logical_map: {...mapBody, self_cid: hash(mapBody)}, observation: 'static', provider_io: 0,
  quantities: [{kind: 'unknown', unit: 'work', reason: 'not_observed'}],
  capabilities: {static_plan: true, inspect: false, durable_control: false,
    sample_capture: [], full_intermediate_retention: [], cost_guard: false,
    execution_batch: false, policy_revision_cid: cid('9')},
};
const unknown = () => ({state: 'unknown', reason: 'not_observed'});
export const effectfulStaticPlan = {
  version: 'actql-effectful-static-plan-view/0.1',
  program_definition_cid: planBody.program_definition_cid,
  parameter_values_cid: cid('a'), check_environment_cid: cid('b'),
  computation: {scope: 'computation_component', plan_view: computationPlan},
  effect_set: {unit_id: 'source', members: [{member_ordinal: 0, stage_ordinal: 0,
    effect_id: 'save', effect_kind: 'update', failure_policy: 'halt',
    contract: {kind: 'mapping', reference: 'mapping:crm.account.v1',
      contract_cid: cid('c'), declared_target: 'connector://crm/account'},
    input: {kind: 'result', result_name: 'out'},
    minimum_approval: {kind: 'contract_minimum', value: 'required'}}]},
  observation: 'static', provider_io: 0,
  observations: {resolved_targets: unknown(), changed_values: unknown(),
    permission: unknown(), gate: unknown(), approval: unknown(),
    preview: {state: 'unavailable', reason: 'not_sealed'}},
};
export const commandMember = {member_ordinal: 0, stage_ordinal: 0,
  effect_id: 'refresh', effect_kind: 'command', failure_policy: 'continue',
  contract: {kind: 'command', reference: 'command:refresh', contract_cid: cid('d'), resource_kind: 'dataset'},
  input: {kind: 'none'}, minimum_approval: {kind: 'not_represented'}};

// Independently authored projection for the Explorer consumer. This vector
// exercises presentation correspondence, not a compiler issuance or grant.
export function effectfulStaticExplanationFixture() {
  const plan = structuredClone(effectfulStaticPlan), computation = plan.computation.plan_view;
  const originalMap = computation.logical_map;
  const keyBody = {version: 'actql-logical-step-key/0.1', compiled_plan_cid: planCid,
    stage_ordinal: 1, occurrence: {kind: 'operation', operation_ordinal: 0}};
  const key = {...keyBody, self_cid: hash(keyBody)};
  const portId = role => hash({version: 'actql-logical-port-key/0.1', compiled_plan_cid: planCid,
    step_id: key.self_cid, role, port_ordinal: 0});
  const original = originalMap.steps[0];
  const infer = {step_id: key.self_cid, key, names: ['review'], operator: 'infer', ports: [
    {...original.ports[0], port_id: portId('input'),
      source: {kind: 'logical_output', step_id: original.step_id, output_port_id: original.ports[1].port_id}},
    {...original.ports[1], port_id: portId('output'),
      source: {kind: 'logical_output', step_id: key.self_cid, output_port_id: portId('output')}},
  ], can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed'};
  const map = {...mapBody, steps: [original, infer]};
  computation.logical_map = {...map, self_cid: hash(map)};
  const binding = {program_definition_cid: plan.program_definition_cid,
    parameter_values_cid: plan.parameter_values_cid, check_environment_cid: plan.check_environment_cid,
    compiled_plan_cid: planCid, logical_map_cid: computation.logical_map.self_cid};
  const {check_environment_cid, ...factsBinding} = binding;
  const facts = {version: 'actql-explanation-facts/0.1', disclosure: 'structural', ...factsBinding,
    steps: map.steps.map(step => ({step_id: step.step_id, key: step.key, operator: step.operator,
      input_ports: [step.ports[0].port_id], output_ports: [step.ports[1].port_id],
      meaning: step.operator === 'infer' ? {kind: 'not_projected', reason: 'operation_facts_not_projected'}
        : {kind: 'input_output'}}))};
  const type = {projection: 'shape_and_nullability', kind: 'string', nullable: false};
  const producer = {state: 'projected', step_id: infer.step_id, port_id: infer.ports[1].port_id};
  const view = {version: 'actql-static-explanation/0.1', plan, facts: {...facts, self_cid: hash(facts)},
    context: {version: 'actql-explanation-context/0.1', disclosure: 'structural', binding, items: [
      {kind: 'source', stage_input: {...original.ports[0].source},
        source_view: {catalog_cid: cid('e'), connector: 'crm', contract_cid: cid('f'),
          resource: 'accounts', selection: 'explicit', view: 'accounts'}, request_kind: 'direct', link_state: 'linked',
        consuming_ports: [{step_id: original.step_id, port_id: original.ports[0].port_id}]},
      {kind: 'model_task', task_id: 'model-task:review', task_version: '1', contract_cid: cid('d'),
        dispatch_unit: 'input_row', producer, input_bindings: [{role: 'notes', binding: {state: 'redacted'}, type}],
        output_fields: [{name: 'tag', type}]},
      {kind: 'result', name: 'updates', stage_ordinal: 1, producer},
      {kind: 'effect_set', unit_id: plan.effect_set.unit_id,
        members: [{declaration: structuredClone(plan.effect_set.members[0]), write_fields: {state: 'declared', fields: ['tag']}}]},
    ]}};
  // Exercise a wire tree rather than sharing fixture objects between facets.
  return JSON.parse(JSON.stringify(view));
}
export const positiveEffectfulPlans = [effectfulStaticPlan,
  {...effectfulStaticPlan, effect_set: {unit_id: 'source', members: [{...effectfulStaticPlan.effect_set.members[0],
    minimum_approval: {kind: 'contract_minimum', value: 'none'}}]}},
  {...effectfulStaticPlan, effect_set: {unit_id: 'source', members: [commandMember]}},
  {...effectfulStaticPlan, effect_set: {unit_id: 'source', members: [{...effectfulStaticPlan.effect_set.members[0],
    effect_kind: 'store', input: {kind: 'table', table_name: 'private_write_input'}}]}},
];
const member = effectfulStaticPlan.effect_set.members[0];
export const negativeEffectfulPlans = [
  {...effectfulStaticPlan, version: 'actql-plan-view/0.1'},
  {...effectfulStaticPlan, self_cid: cid('f')},
  {...effectfulStaticPlan, provider_io: 1},
  {...effectfulStaticPlan, run_ref: {}},
  {...effectfulStaticPlan, computation: {...effectfulStaticPlan.computation, scope: 'full_physical_plan'}},
  {...effectfulStaticPlan, observations: {...effectfulStaticPlan.observations, permission: {state: 'allowed'}}},
  {...effectfulStaticPlan, observations: {...effectfulStaticPlan.observations, gate: {state: 'none'}}},
  {...effectfulStaticPlan, observations: {...effectfulStaticPlan.observations, approval: {state: 'approved'}}},
  {...effectfulStaticPlan, observations: {...effectfulStaticPlan.observations,
    preview: {state: 'available', checkpoint_cid: cid('e')}}},
  {...effectfulStaticPlan, effect_set: {unit_id: 'source', members: []}},
  {...effectfulStaticPlan, effect_set: {unit_id: 'source', members: Array(65).fill(member)}},
  ...[{...commandMember, minimum_approval: {kind: 'contract_minimum', value: 'none'}},
    {...member, minimum_approval: {kind: 'not_represented'}},
    {...member, contract: commandMember.contract},
    {...member, minimum_approval: {kind: 'contract_minimum', value: 'human_only'}},
    {...member, contract: {...member.contract, resolved_target: 'captured-value'}},
    {...member, input: {...member.input, table_name: 'another-namespace'}},
    {...member, failure_policy: 'stop'},
  ].map(value => ({...effectfulStaticPlan, effect_set: {unit_id: 'source', members: [value]}})),
];
