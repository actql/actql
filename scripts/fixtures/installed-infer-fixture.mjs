// Independent application fixture: no compiler test-source extraction.
import {createHash} from 'node:crypto';

export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
export const cid = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;

export const program = {
  version: 'actql/0.1', id: 'packed-single-infer',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true}},
    rows: [{id: 'a', text: 'urgent'}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {filter: {eq: [{field: 'id'}, {literal: 'a'}]}},
    {infer: {contract: 'model-task:packed-risk.v1', key: 'id',
      input: {text: {field: 'text'}}}, as: 'captured'},
    {derive: {assessment: {object: {
      input_key: {object: {id: {field: 'id'}}},
      outcome: {field: 'outcome'}, value: {field: 'value'},
    }}}},
    {select: ['assessment'], as: 'answer'},
  ], results: {answer: {from: 'answer', fields: ['assessment']}}}],
  results: {answer: {from: {stage: 'main', result: 'answer'}}},
};
export const expected = [{assessment: {input_key: {id: 'a'}, outcome: 'ok',
  value: {reason: null, risk: 'high'}}}];

export function configuration(base) {
  const input = {additional_properties: false,
    fields: {text: {nullable: true, type: 'string'}},
    nullable: false, type: 'object'};
  const output = {additional_properties: false, fields: {
    reason: {nullable: true, type: 'string'},
    risk: {nullable: false, type: 'string'}}, nullable: false, type: 'object'};
  const bodies = [
    {version: 'actql-model-prompt/0.1',
      payload: {format: 'packed-risk/0.1', instructions: 'Classify urgency.'}},
    {version: 'actql-model-retry-policy/0.1', retryable_failures: []},
    {version: 'actql-model-backoff/0.1', delays_ms: []},
  ].map(body => ({cid: cid(body),
    bodyWire: canonical({...body, self_cid: cid(body)})}));
  const task = {
    schema: 'actql.model_task/0.1', task_id: 'model-task:packed-risk.v1',
    version: '1', task_kind: 'structured_generate',
    authored_model_selector: 'packed-risk-model', connector_id: 'models/packed',
    input_contract: input, input_schema_cid: cid(input),
    output_contract: output, output_schema_cid: cid(output),
    prompt_template_cid: bodies[0].cid, max_items: 2,
    generation_config: {max_output_tokens: 32, seed_requested: -7,
      temperature: 0, top_p: 1},
    data_handling: {accepted_classifications: ['public', 'internal'],
      allowed_regions: ['fixture-region'],
      contract_cid: `sha256:${'a'.repeat(64)}`,
      retention: 'none', training_use: 'forbidden'},
    retrieval_policy: 'none', streaming: false, tool_policy: 'none',
  };
  const taskCid = cid(task);
  const {evidence_bundle_cid: ignored, ...environment} = base;
  void ignored;
  environment.model_task_contracts = [{...task, contract_cid: taskCid}];
  const execution = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: taskCid,
    retry_classification_contract_cid: bodies[1].cid,
    backoff_contract_cid: bodies[2].cid,
    max_attempts_per_slot: 1, max_total_attempts: 1,
    max_total_cost_units: 0, max_total_duration_ms: 500,
    max_total_wire_bytes: 66536, max_total_token_reservation: 33,
    media_input_contracts: {}, default_publication: 'outcomes'};
  return {taskCid, installation: {
    environmentWire: canonical({...environment,
      evidence_bundle_cid: cid(environment)}),
    executionContracts: [{modelTaskCid: taskCid, cid: cid(execution),
      bodyWire: canonical({...execution, self_cid: cid(execution)})}],
    dependencyBodies: bodies,
  }};
}
