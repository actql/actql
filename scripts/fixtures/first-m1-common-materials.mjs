// Independent application originals for the selected first-M1 input.
// Static admission only: the historical handling policy and execution amounts
// are fixture DATA, not an OpenAI policy, numerical profile or dispatch grant.
import {createHash} from 'node:crypto';

export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
export const identity = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;
export const instructions = 'Original e\u0301\r\n';
export const program = {
  version: 'actql/0.1', id: 'infer-prefix', stages: [{id: 'main', inputs: {},
    steps: [
      {values: {schema: {id: {type: 'string', nullable: false},
        text: {type: 'string', nullable: true}}, rows: [{id: 'a', text: 'hello'}]},
      as: 'input'},
      {assert_rows: {unique_by: ['id']}, as: 'unique'},
      {infer: {contract: 'model-task:risk-score.v1', key: 'id',
        input: {text: {field: 'text'}}}, as: 'captured'},
    ], results: {captured: {from: 'captured', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}},
};
export const input = {additional_properties: false,
  fields: {text: {nullable: true, type: 'string'}}, nullable: false, type: 'object'};
export const output = {additional_properties: false, fields: {
  reason: {nullable: true, type: 'string'}, risk: {nullable: false, type: 'string'},
}, nullable: false, type: 'object'};
export const prompt = {version: 'actql-model-prompt/0.1', payload: {
  format: 'actql.openai_chat_prompt/0.1', instructions,
}};
const retry = {version: 'actql-model-retry-policy/0.1', retryable_failures: []};
const backoff = {version: 'actql-model-backoff/0.1', delays_ms: []};
export const task = {
  schema: 'actql.model_task/0.1', task_id: 'model-task:risk-score.v1', version: '1',
  task_kind: 'structured_generate', authored_model_selector: 'fixture-risk-model',
  connector_id: 'models/fixture', input_contract: input, input_schema_cid: identity(input),
  output_contract: output, output_schema_cid: identity(output),
  prompt_template_cid: identity(prompt), max_items: 2,
  generation_config: {max_output_tokens: 32, seed_requested: -7, temperature: 0, top_p: 1},
  data_handling: {accepted_classifications: ['public', 'internal'],
    allowed_regions: ['fixture-region'], contract_cid: `sha256:${'a'.repeat(64)}`,
    retention: 'none', training_use: 'forbidden'},
  retrieval_policy: 'none', streaming: false, tool_policy: 'none',
};
export const execution = {version: 'actql-model-execution-contract/0.1',
  model_task_contract_cid: identity(task), retry_classification_contract_cid: identity(retry),
  backoff_contract_cid: identity(backoff), max_attempts_per_slot: 1, max_total_attempts: 1,
  max_total_cost_units: 0, max_total_duration_ms: 500, max_total_wire_bytes: 66536,
  max_total_token_reservation: 33, media_input_contracts: {}, default_publication: 'outcomes'};

export function configuration(base) {
  const {evidence_bundle_cid: ignored, ...environment} = base;
  void ignored;
  environment.model_task_contracts = [{...task, contract_cid: identity(task)}];
  return {
    environmentWire: canonical({...environment, evidence_bundle_cid: identity(environment)}),
    executionContracts: [{modelTaskCid: identity(task), cid: identity(execution),
      bodyWire: canonical({...execution, self_cid: identity(execution)})}],
    dependencyBodies: [prompt, retry, backoff].map(body => ({cid: identity(body),
      bodyWire: canonical({...body, self_cid: identity(body)})})),
  };
}
