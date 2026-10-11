import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {decisionTaskCore, decisionPayload, decisionInput, decisionOutput, answerCases}
  from './fixtures/decision-contract.mjs';

// Independent canonical oracle + Node crypto, not any Task reader or issuer.
const hash = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const seal = (value, field) => ({...value, [field]: hash(value)});
export const promptFixture = seal({version: 'actql-model-prompt/0.1', payload: decisionPayload}, 'self_cid');
export const taskFixture = seal({...decisionTaskCore, input_schema_cid: hash(decisionInput),
  output_schema_cid: hash(decisionOutput), prompt_template_cid: promptFixture.self_cid}, 'contract_cid');
export const generationFixture = seal({...Object.fromEntries(Object.entries(taskFixture)
  .filter(([name]) => !['contract_cid', 'decision_config'].includes(name))),
  task_kind: 'structured_generate', generation_config: {temperature: 0, top_p: 1, max_output_tokens: 32}}, 'contract_cid');
const retryFixture = seal({version: 'actql-model-retry-policy/0.1', retryable_failures: []}, 'self_cid');
const backoffFixture = seal({version: 'actql-model-backoff/0.1', delays_ms: []}, 'self_cid');
const executionFixture = seal({version: 'actql-model-execution-contract/0.1',
  model_task_contract_cid: taskFixture.contract_cid,
  retry_classification_contract_cid: retryFixture.self_cid,
  backoff_contract_cid: backoffFixture.self_cid, default_publication: 'outcomes',
  max_attempts_per_slot: 1, max_total_attempts: 1, max_total_cost_units: 0,
  max_total_duration_ms: 1000, max_total_token_reservation: 128,
  max_total_wire_bytes: 2048, media_input_contracts: {}}, 'self_cid');
const literal = value => JSON.stringify(canonicalText(value));

const mutate = (value, change) => {const result = structuredClone(value); change(result); return result;};
const taskCases = [
  ['old Decision is not a generation Task', t => {t.schema = 'actql.model_task/0.1';}],
  ['unknown Task revision', t => {t.schema = 'actql.model_task/invalid';}],
  ['missing Decision config', t => {delete t.decision_config;}],
  ['NULL Decision config', t => {t.decision_config = null;}],
  ['dummy generation forbidden', t => {t.generation_config = {temperature: 0, top_p: 1, max_output_tokens: 32};}],
  ['estimated probabilities forbidden', t => {t.decision_config.probability_source = 'model_estimate';}],
  ['missing distributions policy', t => {delete t.decision_config.distribution_policy;}],
  ['unknown config field', t => {t.decision_config.tolerance = 1;}],
];
const promptCases = [
  ['format not schema', p => {p.schema = p.format; delete p.format;}, 'InvalidPrompt'],
  ['type not kind', p => {p.questions[0].kind = p.questions[0].type; delete p.questions[0].type;}, 'InvalidPrompt'],
  ['unknown state input', p => {p.state_input = 'missing';}, 'InputField'],
  ['empty question list', p => {p.questions = [];}, 'InvalidPrompt'],
  ['duplicate question', p => {p.questions.push(p.questions[0]);}, 'InvalidPrompt'],
  ['changed question/output', p => {p.questions[0].id = 'renamed';}, 'OutputContract'],
  ['no implicit boolean criteria', p => {p.questions[2].criteria = 'fixture';}, 'InvalidPrompt'],
  ['duplicate option', p => {p.questions[0].options[1].id = 'toString';}, 'InvalidPrompt'],
  ['empty choices', p => {p.questions[0].options = [];}, 'InvalidPrompt'],
  ['singleton score', p => {p.questions[1].levels = ['low'];}, 'InvalidPrompt'],
  ['mixed question variants', p => {p.questions[1].options = p.questions[0].options;}, 'InvalidPrompt'],
  ['instructions absent', p => {delete p.questions[0].instructions;}, 'InvalidPrompt'],
  ['instructions NULL', p => {p.questions[0].instructions = null;}, 'InvalidPrompt'],
  ['description absent', p => {delete p.questions[0].options[0].description;}, 'InvalidPrompt'],
  ['description NULL', p => {p.questions[0].options[0].description = null;}, 'InvalidPrompt'],
  ['level descriptions absent', p => {delete p.questions[1].levels;}, 'InvalidPrompt'],
  ['level description NULL', p => {p.questions[1].levels[0] = null;}, 'InvalidPrompt'],
];
const emptyPromptCases = [
  ['instructions', p => {p.questions[0].instructions = '';}],
  ['description', p => {p.questions[0].options[0].description = '';}],
  ['level description', p => {p.questions[1].levels[0] = '';}],
];

export function decisionVectors() {
  const corpus = {version: 'actql-decision-vectors/0.1',
    prompt: promptFixture, task: taskFixture, generation: generationFixture,
    execution: executionFixture, retry: retryFixture, backoff: backoffFixture,
    answers: answerCases.map(([id, body, issue]) => ({id, body, issue}))};
  let moon = `// Generated from independent scripts/fixtures/decision-contract.mjs.

///|
fn decision_fixture_limits() -> DecisionLimits {
  {max_questions: 8, max_options: 8, max_levels: 8, max_name_bytes: 10000, max_work: 10000}
}

///|
fn decision_fixture_task() -> ModelTaskContract {
  let tasks = check_model_tasks(model_wire([${literal(taskFixture)}]), model_limits()).unwrap()
  resolve_model_task(tasks, "model-task:decision-fixture").unwrap()
}

///|
fn decision_fixture_prompt() -> ModelDependency {
  read_model_dependency(ModelPrompt, @utf8.encode(${literal(promptFixture)}), ${JSON.stringify(promptFixture.self_cid)}, model_limits().bodies, 100000).unwrap()
}

///|
fn decision_fixture_cursor(wire : String) -> @decode.Cursor {
  let tree = @source.parse_json_bytes_preserving(@utf8.encode(wire), {max_input_bytes: 10000, max_nodes: 1000, max_depth: 50}).unwrap()
  @decode.admit(tree, {max_nodes: 1000, max_depth: 50, max_string_bytes: 10000, max_total_string_bytes: 10000}).unwrap()
}

///|
test "Decision independent Task/prompt CID, output correspondence and no generation defaults" {
  let task = decision_fixture_task()
  let prompt = decision_fixture_prompt()
  assert_eq(model_task_identity(task).2, ${JSON.stringify(taskFixture.contract_cid)})
  assert_eq(model_task_prompt_cid(task), ${JSON.stringify(promptFixture.self_cid)})
  assert_eq(model_task_kind(task), Decision)
  assert_true(model_task_generation_config(task) is None)
  let checked = read_decision_contract(task, prompt, decision_fixture_limits()).unwrap()
  assert_true(decision_contract_matches(checked, task, prompt))
  assert_eq(decision_state_input(checked), "state")
  assert_false(decision_contract_matches(checked, decision_fixture_task(), prompt))
  assert_eq(@value_contract.stringify_checked(decision_output_contract(checked), 10000, 1000, 50), ${literal(decisionOutput)})
  let generated = check_model_tasks(model_wire([${literal(generationFixture)}]), model_limits()).unwrap()
  let generation = resolve_model_task(generated, "model-task:decision-fixture").unwrap()
  assert_eq(model_task_identity(generation).2, ${JSON.stringify(generationFixture.contract_cid)})
  assert_eq(model_task_kind(generation), StructuredGenerate)
  assert_eq(model_task_generation_config(generation).unwrap().max_output_tokens, 32L)
}
`;
  for (const [id, change] of taskCases) {
    const core = mutate(taskFixture, change);
    delete core.contract_cid;
    const task = seal(core, 'contract_cid');
    moon += `\n///|\ntest ${JSON.stringify('Decision Task refusal: ' + id)} {\n  assert_true(check_model_tasks(model_wire([${literal(task)}]), model_limits()) is Err({kind: InvalidBody, ..}))\n}\n`;
  }
  for (const [id, change, issue] of promptCases) {
    const prompt = seal({version: 'actql-model-prompt/0.1', payload: mutate(decisionPayload, change)}, 'self_cid');
    const {contract_cid: ignored, ...core} = taskFixture;
    void ignored;
    const task = seal({...core, prompt_template_cid: prompt.self_cid}, 'contract_cid');
    moon += `\n///|\ntest ${JSON.stringify('Decision prompt refusal: ' + id)} {
  let task = resolve_model_task(check_model_tasks(model_wire([${literal(task)}]), model_limits()).unwrap(), "model-task:decision-fixture").unwrap()
  let prompt = read_model_dependency(ModelPrompt, @utf8.encode(${literal(prompt)}), ${JSON.stringify(prompt.self_cid)}, model_limits().bodies, 100000).unwrap()
  assert_true(read_decision_contract(task, prompt, decision_fixture_limits()) is Err({kind: ${issue}, ..}))
}
`;
  }
  for (const [id, change] of emptyPromptCases) {
    const prompt = seal({version: 'actql-model-prompt/0.1', payload: mutate(decisionPayload, change)}, 'self_cid');
    const {contract_cid: ignored, ...core} = taskFixture;
    void ignored;
    const task = seal({...core, prompt_template_cid: prompt.self_cid}, 'contract_cid');
    moon += `\n///|\ntest ${JSON.stringify('Decision preserves empty ' + id)} {
  let task = resolve_model_task(check_model_tasks(model_wire([${literal(task)}]), model_limits()).unwrap(), "model-task:decision-fixture").unwrap()
  let prompt = read_model_dependency(ModelPrompt, @utf8.encode(${literal(prompt)}), ${JSON.stringify(prompt.self_cid)}, model_limits().bodies, 100000).unwrap()
  assert_eq(model_task_prompt_cid(task), ${JSON.stringify(prompt.self_cid)})
  assert_true(read_decision_contract(task, prompt, decision_fixture_limits()) is Ok(_))
}
`;
  }
  for (const [id, body, issue] of answerCases) {
    const call = `validate_decision_answers(checked, decision_fixture_cursor(${literal(body)}), initial_jev_decision_profile(), 10000)`;
    moon += `\n///|\ntest ${JSON.stringify('Decision answer: ' + id)} {\n  let checked = read_decision_contract(decision_fixture_task(), decision_fixture_prompt(), decision_fixture_limits()).unwrap()\n`;
    moon += issue ? `  assert_true(${call} is Err({kind: ${issue}, ..}))\n` : `  assert_true(${call} is Ok(_))\n`;
    moon += '}\n';
  }
  // Adjacent binary64 values come from an independent bit-level oracle, not
  // measuring the product validator and replacing its expected threshold.
  const nextUp = value => {
    const bytes = new ArrayBuffer(8), view = new DataView(bytes);
    view.setFloat64(0, value); view.setBigUint64(0, view.getBigUint64(0) + 1n);
    return view.getFloat64(0);
  };
  const sumError = 3 * 0.005 + 0.000001;
  const weightedError = 0.005 * 3 + 0.005 + 0.000001;
  const objectWork = value => 1 + Object.keys(value).length + Object.keys(value).reduce((n, key) => n + key.length, 0);
  const textWork = value => 1 + value.length;
  const equalityWork = type => 1 + (type.type === 'object' ?
    Object.entries(type.fields).reduce((n, [name, child]) => n + 1 + Math.ceil(name.length / 64) + equalityWork(child), 0) :
    type.type === 'array' ? equalityWork(type.items) : 0);
  const readerWork = objectWork(decisionPayload) + textWork(decisionPayload.format) + textWork(decisionPayload.state_input) +
    decisionPayload.state_input.length + 1 + decisionPayload.questions.length + 1 +
    decisionPayload.questions.reduce((sum, q) => sum + objectWork(q) + textWork(q.id) + textWork(q.type) + textWork(q.instructions) + 8 +
      (q.type === 'choice' ? q.options.length + 1 + q.options.reduce((n, option) => n + objectWork(option) + textWork(option.id) + textWork(option.description), 0) :
        q.type === 'score' ? q.levels.length + 1 + q.levels.reduce((n, description) => n + textWork(description), 0) : 0), 0) + equalityWork(decisionOutput);
  const good = answerCases[0][1];
  const answerWork = decisionPayload.questions.length + objectWork(good) +
    decisionPayload.questions.reduce((sum, q) => {
      const answer = good[q.id];
      return sum + objectWork(answer) + (q.type === 'boolean' ? 1 :
        (q.type === 'choice' ? textWork(answer.choice) : 1) + answer.probabilities.length + 1 +
        answer.probabilities.reduce((n, p) => n + objectWork(p) + (q.type === 'choice' ? textWork(p.option) : 1) + 1 + 4, 0));
    }, 0);
  moon += `\n///|\ntest "Decision independent exact and one-short validation work" {
  let task = decision_fixture_task()
  let prompt = decision_fixture_prompt()
  let limits = {..decision_fixture_limits(), max_work: ${readerWork}}
  let checked = read_decision_contract(task, prompt, limits).unwrap()
  assert_eq(decision_contract_usage(checked), ${readerWork})
  assert_true(read_decision_contract(task, prompt, {..limits, max_work: ${readerWork - 1}}) is Err({kind: WorkLimit, ..}))
  let answer = decision_fixture_cursor(${literal(good)})
  assert_eq(validate_decision_answers(checked, answer, initial_jev_decision_profile(), ${answerWork}).unwrap(), ${answerWork})
  assert_true(validate_decision_answers(checked, answer, initial_jev_decision_profile(), ${answerWork - 1}) is Err({kind: WorkLimit, ..}))
}
\n///|
test "Decision dependencies connect the original checked Task and prompt" {
  let task = decision_fixture_task()
  let execution = read_model_execution_contract(task, @utf8.encode(${literal(executionFixture)}), ${JSON.stringify(executionFixture.self_cid)}, model_limits().bodies, 100000).unwrap()
  let dependencies = read_single_attempt_model_dependencies(execution, Some(@utf8.encode(${literal(promptFixture)})), Some(@utf8.encode(${literal(retryFixture)})), Some(@utf8.encode(${literal(backoffFixture)})), model_limits().bodies, 100000).unwrap()
  let decision = single_attempt_model_decision(dependencies).unwrap()
  assert_true(single_attempt_model_dependencies_match(dependencies, execution))
  assert_true(decision_contract_matches(decision, task, single_attempt_model_prompt(dependencies)))
  assert_eq(decision_contract_usage(decision), ${readerWork})
}
\n///|
test "Decision rejects typed NaN and infinity without repair" {
  let checked = read_decision_contract(decision_fixture_task(), decision_fixture_prompt(), decision_fixture_limits()).unwrap()
  for value in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    let tree = @source.parse_json_bytes_preserving(@utf8.encode(${literal(good)}), {max_input_bytes: 10000, max_nodes: 1000, max_depth: 50}).unwrap()
    guard tree.value is @source.Object(fields) else { fail("fixture root") }
    for field in fields {
      if field.key == "enabled" {
        guard field.value.value is @source.Object(entries) else { fail("fixture answer") }
        let original = entries[0]
        entries[0] = {..original, value: {..original.value, value: @source.Number(value)}}
      }
    }
    let cursor = @decode.admit(tree, {max_nodes: 1000, max_depth: 50, max_string_bytes: 10000, max_total_string_bytes: 10000}).unwrap()
    assert_true(validate_decision_answers(checked, cursor, initial_jev_decision_profile(), 10000) is Err({kind: InvalidAnswer, ..}))
  }
}
`;
  const arithmetic = `// Generated independent binary64 boundary vectors.\n\n///|\ntest "Decision fixed arithmetic margin exact and next representation" {
  let profile = initial_jev_decision_profile()
  assert_true(decision_distribution_error_allowed(${sumError}, 3, profile))
  assert_false(decision_distribution_error_allowed(${nextUp(sumError)}, 3, profile))
  assert_true(decision_score_error_allowed(${weightedError}, 3.0, profile))
  assert_false(decision_score_error_allowed(${nextUp(weightedError)}, 3.0, profile))
  assert_false(decision_score_error_allowed(0.0, 9007199254740992.0, profile))
}
`;
  const legacyInput = {type: 'object', nullable: false, additional_properties: false,
    fields: {text: {type: 'string', nullable: true}}};
  const legacyOutput = {type: 'object', nullable: false, additional_properties: false,
    fields: {reason: {type: 'string', nullable: true}, risk: {type: 'string', nullable: false}}};
  const guardedTask = seal({...decisionTaskCore, task_id: 'model-task:risk-score.v1',
    authored_model_selector: 'fixture-risk-model', input_contract: legacyInput, output_contract: legacyOutput,
    input_schema_cid: hash(legacyInput), output_schema_cid: hash(legacyOutput),
    prompt_template_cid: 'sha256:' + 'a'.repeat(64), max_items: 2,
    data_handling: {accepted_classifications: ['public', 'internal'], allowed_regions: ['fixture-region'],
      contract_cid: 'sha256:' + 'a'.repeat(64), retention: 'none', training_use: 'forbidden'}}, 'contract_cid');
  const guard = `// Generated independent Decision compatibility boundary.\n
///|
test "Decision synchronous profile refuses before physical start and retains input cleanup" {
  let environment_wire = infer_fixture_environment
    .replace(old="\\\"generation_config\\\":{\\\"max_output_tokens\\\":32,\\\"seed_requested\\\":-7,\\\"temperature\\\":0,\\\"top_p\\\":1}", new=${JSON.stringify('"decision_config":' + canonicalText(guardedTask.decision_config))})
    .replace(old="actql.model_task/0.1", new="actql.model_task/0.2")
    .replace(old="\\\"task_kind\\\":\\\"structured_generate\\\"", new="\\\"task_kind\\\":\\\"decision\\\"")
    .replace(old="sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560", new=${JSON.stringify(guardedTask.contract_cid)})
  assert_true(environment_wire != infer_fixture_environment)
  let prepared = fixture_prepared(environment_wire~)
  let calls = Ref(0)
  let active = fixture_start(prepared, () => calls.val += 1)
  assert_true(fixture_finish(active) is Failed(Model(@model.InvalidProvider), ..))
  assert_eq(calls.val, 0)
  assert_true(active.model is None)
  assert_true(active.rows is Some(_))
  assert_true(acquire_output(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}
`;
  return {corpus, moon, arithmetic, guard};
}

export function checkDecisionVectors(write = false) {
  const {corpus, moon, arithmetic, guard} = decisionVectors();
  for (const [path, output] of [
    ['portability/corpus/decision-contracts.json', JSON.stringify(corpus, null, 2) + '\n'],
    ['src/check_environment/decision_vectors.generated_test.mbt', moon],
    ['src/check_environment/decision_arithmetic.generated_wbtest.mbt', arithmetic],
    ['src/client_infer_host/decision_admission.generated_wbtest.mbt', guard],
  ]) {
    if (write) writeFileSync(path, output);
    assert.equal(readFileSync(path, 'utf8'), output, `Stale Decision vectors: ${path}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  checkDecisionVectors(process.argv.includes('--write'));
}
