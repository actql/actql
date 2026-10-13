import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';

// Independent literals and Node hashing, never projected product output.
const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
const seal = (body, key = 'self_cid') => ({...body, [key]: cid(body)});
const literal = body => JSON.stringify(canonicalText(body));
const format = 'actql.openai_chat_prompt/0.1';
const inputs = {type: 'object', nullable: false, additional_properties: false,
  fields: {amount: {type: 'decimal', nullable: false, precision: 20, scale: 2},
    absent: {type: 'boolean', nullable: true},
    text: {type: 'string', nullable: true}}};
const output = {type: 'object', nullable: false, additional_properties: false,
  fields: {answer: {type: 'string', nullable: true}}};
const schema = {additionalProperties: false, properties: {
  answer: {anyOf: [{type: 'string'}, {type: 'null'}]}},
  required: ['answer'], type: 'object'};
const payloads = [
  ['empty', {format, instructions: ''}, true],
  ['raw Unicode and line endings', {format, instructions: 'e\u0301\r\né\n😀'}, true],
  ['missing instructions', {format}, false],
  ['NULL instructions', {format, instructions: null}, false],
  ['wrong type', {format, instructions: false}, false],
  ['extra key', {format, instructions: '', tool: null}, false],
  ['wrong format', {format: 'fixture-other/0.1', instructions: ''}, false],
  ['NULL payload', null, false],
];

export function openAIChatVectors() {
  const cases = payloads.map(([id, payload, accepted]) => {
    const body = {version: 'actql-model-prompt/0.1', payload};
    return {id, payload, accepted, body: seal(body),
      expected_cid: cid(body), expected_preimage: canonicalText(body)};
  });
  const prompt = cases[1].body;
  const task = seal({schema: 'actql.model_task/0.1', task_id: 'model-task:chat-fixture',
    version: '1', task_kind: 'structured_generate', connector_id: 'models/fixture',
    authored_model_selector: 'fixture-chat', input_schema_cid: cid(inputs),
    output_schema_cid: cid(output), input_contract: inputs, output_contract: output,
    max_items: 1, prompt_template_cid: prompt.self_cid, generation_config: {
      temperature: 0.25, top_p: 0.875, max_output_tokens: 16, seed_requested: -7},
    data_handling: {contract_cid: 'sha256:' + 'a'.repeat(64), retention: 'none',
      training_use: 'forbidden', accepted_classifications: ['public'],
      allowed_regions: ['fixture']}, tool_policy: 'none', retrieval_policy: 'none',
    streaming: false}, 'contract_cid');
  const retry = seal({version: 'actql-model-retry-policy/0.1', retryable_failures: []});
  const backoff = seal({version: 'actql-model-backoff/0.1', delays_ms: []});
  const execution = seal({version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: retry.self_cid, backoff_contract_cid: backoff.self_cid,
    default_publication: 'outcomes', max_attempts_per_slot: 1, max_total_attempts: 1,
    max_total_cost_units: 0, max_total_duration_ms: 1000,
    max_total_token_reservation: 17, max_total_wire_bytes: 65536,
    media_input_contracts: {}});
  const environment = seal({version: 'actql-check-environment/0.1',
    command_contracts: [], connector_capabilities: [], connector_catalogs: [],
    contract_registry: [], host_policy_profile: {}, mapping_contracts: [],
    model_task_contracts: [task], schema_snapshots: [], source_views: []}, 'evidence_bundle_cid');
  const corpus = {version: 'actql-openai-chat-vectors/0.1', cases, task, execution,
    prompt, retry, backoff, environment, schema, schema_cid: cid(schema)};
  let payloadMoon = '// Generated independent OpenAI prompt payload vectors.\n';
  for (const c of cases) {
    payloadMoon += `\n///|\ntest ${JSON.stringify('OpenAI payload: ' + c.id)} {\n` +
      `  let prompt = read_model_dependency(ModelPrompt, @utf8.encode(${literal(c.body)}), ${JSON.stringify(c.expected_cid)}, model_limits().bodies, 100000).unwrap()\n` +
      `  assert_eq(model_openai_chat_instructions(prompt), ${c.accepted ? 'Some(' + JSON.stringify(c.payload.instructions) + ')' : 'None'})\n}\n`;
  }
  const limits = '{max_bytes:100000,max_nodes:10000,max_depth:100,max_members:10}';
  let modelMoon = `// Generated independent original Provider projection fixture.\n
///|
fn openai_projection_fixture() -> (AdmittedModelProvider, ModelRequest, () -> Int) {
  let limits : @environment.Limits = ${limits}
  let env = @environment.read(@utf8.encode(${literal(environment)}), ${JSON.stringify(environment.evidence_bundle_cid)}, limits).unwrap()
  let tasks = @environment.check_model_tasks(env,{bodies:limits,contracts:{max_nodes:1000,max_depth:50,max_text_bytes:10000},max_work:1000000}).unwrap()
  let task = @environment.resolve_model_task(tasks,"model-task:chat-fixture").unwrap()
  let execution = @environment.read_model_execution_contract(task,@utf8.encode(${literal(execution)}),${JSON.stringify(execution.self_cid)},limits,1000000).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(execution,Some(@utf8.encode(${literal(prompt)})),Some(@utf8.encode(${literal(retry)})),Some(@utf8.encode(${literal(backoff)})),limits,1000000).unwrap()
  let mut calls = 0
  let provider = install_model_provider("models/fixture",_ => { calls += 1; Err(Cancelled) }).unwrap()
  let admitted = admit_model_provider(provider,execution,dependencies,(_,p) => @environment.model_openai_chat_instructions(p) is Some(_)).unwrap()
  let text = @admitted.text_value("é\\r\\n😀",100).unwrap()
  let input = @admitted.recheck_runtime_value(text,@contract.primitive(@contract.StringType,nullable=true),{max_nodes:10,max_depth:4,max_text_bytes:100}).unwrap()
  let amount = @admitted.recheck_runtime_value(@admitted.decimal_from_coefficient("900719925474099300",20,2).unwrap(),@contract.decimal_contract(20,2,nullable=false).unwrap(),{max_nodes:10,max_depth:4,max_text_bytes:100}).unwrap()
  let absent = @admitted.recheck_runtime_value(@admitted.null_value(),@contract.primitive(@contract.BooleanType,nullable=true),{max_nodes:10,max_depth:4,max_text_bytes:100}).unwrap()
  let request : ModelRequest = {task,slot:0,slot_cid:"sha256:"+"1".repeat(64),fixed_request_cid:"sha256:"+"2".repeat(64),key:[],inputs:[("absent",absent),("amount",amount),("text",input)]}
  (admitted,request,() => calls)
}

///|
test "original OpenAI projection binds actual Task prompt schema and preserves input" {
  let (provider,request,calls) = openai_projection_fixture()
  let value = project_openai_chat_request(provider,request,10000,1000,40,100,10000).unwrap()
  assert_eq(value,(${JSON.stringify(prompt.payload.instructions)},${JSON.stringify(canonicalText({absent:null,amount:'9007199254740993.00',text:'é\r\n😀'}))},${JSON.stringify(canonicalText(schema))},${JSON.stringify(task.contract_cid)},${JSON.stringify(prompt.self_cid)},${JSON.stringify(task.output_schema_cid)},"fixture-chat"))
  assert_eq("sha256:"+@sha.hex(@utf8.encode(value.2)),${JSON.stringify(cid(schema))})
  let (foreign,_,foreign_calls) = openai_projection_fixture()
  assert_true(project_openai_chat_request(foreign,request,10000,1000,40,100,10000) is Err(ForeignRequest))
  assert_true(project_openai_chat_request(provider,request,10000,1000,40,100,0) is Err(Limit))
  assert_true(project_openai_chat_request(provider,request,10,1000,40,100,10000) is Err(Limit))
  assert_eq(calls(),0)
  assert_eq(foreign_calls(),0)
}
`;
  const fmt = source => execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME,'bin/moonfmt') : 'moonfmt', ['-'], {input:source,encoding:'utf8'});
  return {corpus, payloadMoon:fmt(payloadMoon),modelMoon:fmt(modelMoon)};
}

export function checkOpenAIChatVectors() {
  const {corpus,payloadMoon,modelMoon}=openAIChatVectors();
  for (const [path,expected] of [
    ['portability/corpus/openai-chat.json',JSON.stringify(corpus,null,2)+'\n'],
    ['src/check_environment/openai_chat.generated_test.mbt',payloadMoon],
    ['src/model_execution/openai_chat_projection.generated_wbtest.mbt',modelMoon],
  ]) assert.equal(readFileSync(path,'utf8'),expected);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--write')) {
    const {corpus,payloadMoon,modelMoon}=openAIChatVectors();
    writeFileSync('portability/corpus/openai-chat.json',JSON.stringify(corpus,null,2)+'\n');
    writeFileSync('src/check_environment/openai_chat.generated_test.mbt',payloadMoon);
    writeFileSync('src/model_execution/openai_chat_projection.generated_wbtest.mbt',modelMoon);
  }
  checkOpenAIChatVectors();
}
