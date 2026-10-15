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
