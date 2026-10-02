import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {checkModelDependencySchemas, modelRetryOrder} from
  './model-dependency-contract.mjs';

// Independent Node hashing and literal bodies, never values returned by the
// product reader, provider, execution, or an evidence issuer.
const prompt = {version: 'actql-model-prompt/0.1',
  payload: {format: 'fixture-risk/0.1', instructions: 'Classify the text.'}};
const retry = {version: 'actql-model-retry-policy/0.1', retryable_failures: []};
const backoff = {version: 'actql-model-backoff/0.1', delays_ms: []};
const cases = [
  ['prompt object', 'ModelPrompt', prompt, true],
  ['prompt null', 'ModelPrompt', {...prompt, payload: null}, true],
  ['nested self is payload', 'ModelPrompt', {...prompt,
    payload: {self_cid: 'ordinary business data'}}, true],
  ['no retries', 'ModelRetryPolicy', retry, true],
  ['ordered transient classes', 'ModelRetryPolicy', {...retry,
    retryable_failures: [...modelRetryOrder]}, true],
  ['no backoff', 'ModelBackoff', backoff, true],
  ['finite backoff', 'ModelBackoff', {...backoff,
    delays_ms: [0, 125, Number.MAX_SAFE_INTEGER]}, true],
  ['unknown envelope member', 'ModelPrompt', {...prompt, extra: null}, false],
  ['unknown version', 'ModelPrompt', {...prompt,
    version: 'actql-model-prompt/invalid'}, false],
  ['missing payload', 'ModelPrompt', {version: prompt.version}, false],
  ['unknown retry class', 'ModelRetryPolicy', {...retry,
    retryable_failures: ['schema_invalid']}, false],
  ['duplicate retry class', 'ModelRetryPolicy', {...retry,
    retryable_failures: ['timeout', 'timeout']}, false],
  ['retry order violation', 'ModelRetryPolicy', {...retry,
    retryable_failures: ['timeout', 'rate_limit']}, false],
  ['negative delay', 'ModelBackoff', {...backoff, delays_ms: [-1]}, false],
  ['fractional delay', 'ModelBackoff', {...backoff, delays_ms: [0.5]}, false],
  ['unsafe delay', 'ModelBackoff', {...backoff,
    delays_ms: [Number.MAX_SAFE_INTEGER + 1]}, false],
  ['NULL delay', 'ModelBackoff', {...backoff, delays_ms: [null]}, false],
  ['wrong role', 'ModelPrompt', retry, false],
].map(([id, kind, body, accepted]) => {
  const expected_cid = machineCid(body);
  const wire = canonicalText({...body, self_cid: expected_cid});
  const valueNodes = value => 1 + (value !== null && typeof value === 'object'
    ? Object.values(value).reduce((sum, child) => sum + valueNodes(child), 0) : 0);
  const listWork = kind === 'ModelRetryPolicy' ?
    body.retryable_failures?.length +
      body.retryable_failures?.reduce((sum, value) => sum + value.length, 0) :
    kind === 'ModelBackoff' ? 2 * body.delays_ms.length : 0;
  const expected_work = accepted ? 3 * Buffer.byteLength(wire) + 3 +
    Object.keys({...body, self_cid: expected_cid}).reduce((sum, key) =>
      sum + key.length, 0) + body.version.length + 71 + listWork : null;
  return {id, kind, body, accepted, expected_cid,
    expected_canonical_bytes: canonicalText(body),
    wire, expected_work, expected_nodes: valueNodes({...body, self_cid: expected_cid})};
});
const corpus = {version: 'actql-model-dependency-vectors/0.1', cases};
const corpusPath = 'portability/corpus/model-dependencies.json';
const moonPath = 'src/check_environment/model_dependencies.generated_test.mbt';
const providerPath = 'src/model_execution/provider_admission.generated_wbtest.mbt';
let moon = '// Generated independent Model dependency admission vectors.\n';
for (const fixture of cases) {
  moon += `\n///|\ntest ${JSON.stringify('Model dependency: ' + fixture.id)} {\n` +
    `  let value = read_model_dependency(${fixture.kind},\n` +
    `    @utf8.encode(${JSON.stringify(fixture.wire)}),\n` +
    `    ${JSON.stringify(fixture.expected_cid)},\n` +
    '    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, }, 100000)\n';
  moon += fixture.accepted ?
    `  let admitted = value.unwrap()\n` +
    `  assert_eq(model_dependency_identity(admitted), ${JSON.stringify(fixture.expected_cid)})\n` +
    `  assert_eq(model_dependency_usage(admitted), (${Buffer.byteLength(fixture.wire)}, ${fixture.expected_nodes}, ${fixture.expected_work}))\n` +
    `  let limits : Limits = { max_bytes: ${Buffer.byteLength(fixture.wire)}, max_nodes: ${fixture.expected_nodes}, max_depth: 20, max_members: 3, }\n` +
    `  assert_true(read_model_dependency(${fixture.kind}, @utf8.encode(${JSON.stringify(fixture.wire)}), ${JSON.stringify(fixture.expected_cid)}, limits, ${fixture.expected_work}) is Ok(_))\n` +
    `  assert_true(read_model_dependency(${fixture.kind}, @utf8.encode(${JSON.stringify(fixture.wire)}), ${JSON.stringify(fixture.expected_cid)}, limits, ${fixture.expected_work - 1}) is Err({kind: WorkLimit, ..}))\n` +
    `  assert_true(read_model_dependency(${fixture.kind}, @utf8.encode(${JSON.stringify(fixture.wire)}), ${JSON.stringify(fixture.expected_cid)}, { ..limits, max_bytes: limits.max_bytes - 1 }, ${fixture.expected_work}) is Err({kind: BodyLimit, ..}))\n` +
    `  assert_true(read_model_dependency(${fixture.kind}, @utf8.encode(${JSON.stringify(fixture.wire)}), ${JSON.stringify(fixture.expected_cid)}, { ..limits, max_nodes: limits.max_nodes - 1 }, ${fixture.expected_work}) is Err({kind: BodyLimit, ..}))\n` :
    '  assert_true(value is Err(_))\n';
  moon += '}\n';
}
const valid = cases[0];
moon += `\n///|\ntest "Model dependency rejects reference substitution, body substitution and noncanonical bytes" {\n` +
  `  let wire = ${JSON.stringify(valid.wire)}\n` +
  `  let pin = ${JSON.stringify(valid.expected_cid)}\n` +
  '  let limits : Limits = {max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3}\n' +
  '  assert_true(read_model_dependency(ModelPrompt, @utf8.encode(wire), "sha256:" + "f".repeat(64), limits, 100000) is Err({kind: IdentityMismatch, ..}))\n' +
  '  assert_true(read_model_dependency(ModelPrompt, @utf8.encode(wire.replace(old="Classify", new="Ignore")), pin, limits, 100000) is Err({kind: IdentityMismatch, ..}))\n' +
  '  assert_true(read_model_dependency(ModelPrompt, @utf8.encode(" " + wire), pin, limits, 100000) is Err({kind: InvalidBody, ..}))\n' +
  '  assert_true(read_model_dependency(ModelPrompt, @utf8.encode(wire), pin, {..limits, max_depth: 1}, 100000) is Err({kind: BodyLimit, ..}))\n' +
  '}\n';
moon = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
  : 'moonfmt', ['-'], {input: moon, encoding: 'utf8'});
// The provider oracle begins with the same independently authored Task,
// then seals its real dependency references without using a product issuer.
const taskText = readFileSync('src/model_execution/execution_wbtest.mbt', 'utf8')
  .match(/let body =\n\s+#\|(.+)/u)[1];
const {contract_cid: ignoredTask, ...taskCore} = JSON.parse(taskText);
void ignoredTask;
taskCore.prompt_template_cid = cases[0].expected_cid;
const taskCid = machineCid(taskCore);
const environmentCore = {command_contracts: [], connector_capabilities: [],
  connector_catalogs: [], contract_registry: [], host_policy_profile: {},
  mapping_contracts: [], model_task_contracts: [{...taskCore, contract_cid: taskCid}],
  schema_snapshots: [], source_views: [], version: 'actql-check-environment/0.1'};
const environmentCid = machineCid(environmentCore);
const executionCore = {version: 'actql-model-execution-contract/0.1',
  model_task_contract_cid: taskCid,
  retry_classification_contract_cid: cases.find(value => value.id === 'no retries').expected_cid,
  backoff_contract_cid: cases.find(value => value.id === 'no backoff').expected_cid,
  max_attempts_per_slot: 1, max_total_attempts: 1, max_total_cost_units: 0,
  max_total_duration_ms: 500, max_total_wire_bytes: 66536,
  max_total_token_reservation: 33, media_input_contracts: {}, default_publication: 'outcomes'};
let providerMoon = `// Generated independent provider capability binding fixture.\n
///|
fn provider_admission_fixture() -> (@environment.ModelExecutionContract, @environment.SingleAttemptModelDependencies) {
  let limits : @environment.Limits = {max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10}
  let environment = @environment.read(@utf8.encode(${JSON.stringify(canonicalText({...environmentCore, evidence_bundle_cid: environmentCid}))}), ${JSON.stringify(environmentCid)}, limits).unwrap()
  let tasks = @environment.check_model_tasks(environment, {bodies: limits, contracts: {max_nodes: 1000, max_depth: 50, max_text_bytes: 10000}, max_work: 1000000}).unwrap()
  let task = @environment.resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  let execution = @environment.read_model_execution_contract(task, @utf8.encode(${JSON.stringify(canonicalText({...executionCore, self_cid: machineCid(executionCore)}))}), ${JSON.stringify(machineCid(executionCore))}, limits, 1000000).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(execution,
    Some(@utf8.encode(${JSON.stringify(cases[0].wire)})),
    Some(@utf8.encode(${JSON.stringify(cases.find(value => value.id === 'no retries').wire)})),
    Some(@utf8.encode(${JSON.stringify(cases.find(value => value.id === 'no backoff').wire)})), limits, 1000000).unwrap()
  (execution, dependencies)
}

///|
test "Provider payload admission retains the exact execution without dispatch" {
  let (execution, dependencies) = provider_admission_fixture()
  let (foreign, foreign_dependencies) = provider_admission_fixture()
  let mut calls = 0
  let mut validations = 0
  let provider = install_model_provider("models/fixture", _ => { calls += 1; Err(Cancelled) }).unwrap()
  let validate = (task, prompt) => {
    validations += 1
    @environment.model_task_identity(task).2 == ${JSON.stringify(taskCid)} &&
      @environment.model_task_model_selector(task) == "fixture-risk-model" &&
      @environment.model_dependency_identity(prompt) == ${JSON.stringify(cases[0].expected_cid)}
  }
  assert_true(admit_model_provider(provider, execution, foreign_dependencies, validate) is Err(ForeignDependencies))
  let wrong = install_model_provider("models/foreign", _ => Err(Cancelled)).unwrap()
  assert_true(admit_model_provider(wrong, execution, dependencies, validate) is Err(ForeignProvider))
  assert_eq(validations, 0)
  assert_true(admit_model_provider(provider, execution, dependencies, (_, _) => false) is Err(UnsupportedPrompt))
  let admitted = admit_model_provider(provider, execution, dependencies, validate).unwrap()
  assert_eq(validations, 1)
  assert_true(admitted_model_provider_for(admitted, execution) is Some(actual) && physical_equal(actual, provider))
  assert_true(admitted_model_provider_for(admitted, foreign) is None)
  assert_eq(calls, 0)
}
`;
providerMoon = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
  : 'moonfmt', ['-'], {input: providerMoon, encoding: 'utf8'});
if (process.argv.includes('--write')) {
  writeFileSync(corpusPath, JSON.stringify(corpus, null, 2) + '\n');
  writeFileSync(moonPath, moon);
  writeFileSync(providerPath, providerMoon);
}
assert.deepEqual(JSON.parse(readFileSync(corpusPath, 'utf8')), corpus);
assert.equal(readFileSync(moonPath, 'utf8'), moon);
assert.equal(readFileSync(providerPath, 'utf8'), providerMoon);

test('Model dependency schemas and independent preimages are pinned', () => {
  checkModelDependencySchemas(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
  for (const fixture of cases) verifyIdentity(fixture.body,
    fixture.expected_cid, fixture.expected_canonical_bytes);
});

test('payload and ordered policies remain identity-bearing', () => {
  assert.notEqual(machineCid(prompt), machineCid({...prompt, payload: null}));
  assert.notEqual(machineCid(backoff), machineCid({...backoff, delays_ms: [0]}));
  assert.notEqual(machineCid({...retry, retryable_failures: ['rate_limit', 'timeout']}),
    machineCid({...retry, retryable_failures: ['timeout', 'rate_limit']}));
});
