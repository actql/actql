// Independent semantic wire fixture, not compiler output or product acceptance.
import {createHash} from 'node:crypto';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
const cid = unit => `sha256:${unit.repeat(64)}`;
const sealed = body => ({...body, self_cid: `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`});
export function gatewayLaunchPlanFixture() {
  const plan = cid('a'), carrier = cid('b');
  const key = ordinal => sealed({version: 'actql-logical-step-key/0.1',
    compiled_plan_cid: plan, stage_ordinal: 0,
    occurrence: {kind: 'operation', operation_ordinal: ordinal}});
  const step = (ordinal, operator) => ({step_id: key(ordinal).self_cid,
    key: key(ordinal), names: [`e\u0301\r\n-${ordinal}`], operator, ports: [],
    can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed'});
  const producer = step(0, 'values'), join = step(1, 'join');
  const port = (node, role, ordinal, source) => ({port_id: sealed({
    version: 'actql-logical-port-key/0.1', compiled_plan_cid: plan,
    step_id: node.step_id, role, port_ordinal: ordinal}).self_cid,
  role, port_ordinal: ordinal, carrier: 'relation', carrier_contract_cid: carrier,
  source, can_sample: false, sample_reason: 'not_installed'});
  const output = port(producer, 'output', 0, {kind: 'logical_output',
    step_id: producer.step_id, output_port_id: cid('c')});
  // Bind the output's self locator to the exact original port.
  output.source.output_port_id = output.port_id;
  producer.ports.push(output);
  for (const ordinal of [0, 1]) join.ports.push(port(join, 'input', ordinal,
    {kind: 'logical_output', step_id: producer.step_id,
      output_port_id: output.port_id}));
  const joined = port(join, 'output', 0,
    {kind: 'logical_output', step_id: join.step_id, output_port_id: cid('d')});
  joined.source.output_port_id = joined.port_id;
  join.ports.push(joined);
  return {version: 'actql-plan-view/0.1', compiled_plan_cid: plan,
    logical_map: sealed({version: 'actql-logical-map/0.1', compiled_plan_cid: plan,
      program_definition_cid: cid('e'), steps: [producer, join]}),
    observation: 'static', provider_io: 0, quantities: [], capabilities: {
      static_plan: true, inspect: true, durable_control: false,
      sample_capture: [], full_intermediate_retention: [], cost_guard: false,
      execution_batch: false, policy_revision_cid: cid('f')}};
}
