import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {installModelProviders} from './installed-model.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

const runtime = process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME;
assert.ok(runtime, 'A matching actual Common runtime is required; do not skip');
const moon = await import(pathToFileURL(runtime));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const identity = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const original = body => { const wire = canonical(body); return {wire, cid: identity(wire)}; };
const providerId = 'models/actual-public-task';
const bounds = [10000, 1000, 32, 100, 100, 16, 1000, 100000];
const readerBounds = {maxBytes: 10000, maxNodes: 1000, maxDepth: 32, maxMembers: 100, maxWork: 100000};
const policy = {body: {accepted_classifications: ['public', 'internal'],
  allowed_regions: ['explicit-region'], retention: 'none', training_use: 'forbidden'},
id: 'operator-model-policy', kind: 'request_data_handling', schema: 'actql.contract/0.1', version: 'operator-revision-1'};
const policyCid = 'sha256:4ae245d55eb9bcb462b0e709d9b7495429918caab5207eb27c3e359428ca3763';
assert.equal(identity(canonical(policy)), policyCid, 'independent policy preimage');
const registryWire = canonical({version: 'actql-model-tasks/0.1',
  tasks: {'model-task:actual.original': 'original.yaml'},
  providers: {[providerId]: {type: 'fixture'}, foreign: {type: 'future'}}, default_provider: providerId});
const taskDocument = (extra = {}) => canonical({task: 'model-task:actual.original',
  input: {notes: 'string'}, output: {enabled: 'boolean'}, instructions: 'Original é\r\n', ...extra});
const read = wire => checked(moon.clientProgramReadPublicModelTask(wire, 'json', ...bounds));
const registry = () => checked(moon.clientProjectModelRegistryAdmit(registryWire));
function fixture() {
  let current = true, calls = 0;
  const originals = providerBindingOriginals(providerId);
  originals.configurationContract = original({...JSON.parse(originals.configurationContract.wire),
    required: ['endpoint', 'principal', 'selector', 'tenant', 'model_defaults']});
  originals.configuration = original({...JSON.parse(originals.configuration.wire), model_defaults: {
    default_model: 'first', models: [{model: 'first', data_handling: {...policy, cid: policyCid},
      generation_config: {temperature: 0, top_p: 1, max_output_tokens: 100}},
    {model: 'second', data_handling: {...policy, cid: policyCid},
      generation_config: {temperature: 0.25, top_p: 0.875, max_output_tokens: 300}}]}});
  const check = () => { if (!current) throw Object.assign(new Error('OriginalLost'), {code: 'OriginalLost'}); };
  const providers = installModelProviders(moon, actual => {
    assert.equal(actual, moon);
    // Explicit synchronous no-I/O fixture, not a physical Provider/grant.
    return [{providerId, bindingOriginals: originals, validatePrompt: () => true,
      invoke() { calls++; assert.fail('No Provider invocation'); }}];
  }, check, check);
  return {selected: providers.get(providerId), originals, providers,
    loseCurrent: () => { current = false; }, calls: () => calls};
}
function normalize(f, r, task, model, tokens) {
  const selection = checked(moon.clientProgramSelectProjectModelTask(r, task, 10000));
  const pair = runtimeUnboxedReferenceOption(moon.clientProgramProjectModelTaskSelectionFor(selection, r, task));
  assert.ok(pair);
  assert.equal(runtimeField(pair, 0), providerId);
  const defaults = f.selected.resolveTaskDefaults(model, tokens, readerBounds);
  const normalized = checked(moon.clientProgramNormalizeProjectModelTask(selection, r, task, defaults.value, ...bounds));
  const material = moon.clientProgramNormalizedPublicModelTaskMaterials(normalized);
  return {selection, defaults, normalized, taskWire: runtimeField(material, 0),
    taskCid: runtimeField(material, 1), promptWire: runtimeField(material, 2), promptCid: runtimeField(material, 3)};
}

test('actual private Host original supplies default policy and Task material without Provider I/O', () => {
  const f = fixture(), r = registry(), task = read(taskDocument({limits: {max_output_tokens: 200}}));
  const material = normalize(f, r, task, undefined, 200n);
  const body = JSON.parse(material.taskWire), prompt = JSON.parse(material.promptWire);
  assert.equal(body.version, 'model-task:actual.original');
  assert.equal(body.task_id, body.version);
  assert.equal(body.connector_id, providerId);
  assert.equal(body.authored_model_selector, 'first');
  assert.equal(body.generation_config.max_output_tokens, 200);
  assert.equal(body.data_handling.contract_cid, policyCid);
  assert.equal(prompt.payload.instructions, 'Original é\r\n');
  const {contract_cid, ...taskPreimage} = body;
  const {self_cid, ...promptPreimage} = prompt;
  assert.equal(identity(canonical(taskPreimage)), contract_cid);
  assert.equal(identity(canonical(promptPreimage)), self_cid);
  assert.equal(material.taskCid, contract_cid);
  assert.equal(material.promptCid, self_cid);
  assert.equal(f.calls(), 0);
});

test('actual public explicit model selection does not borrow a registry default generation', () => {
  const f = fixture(), r = registry();
  const task = read(taskDocument({model: {provider: providerId, name: 'second'}}));
  const body = JSON.parse(normalize(f, r, task, 'second', undefined).taskWire);
  assert.equal(body.authored_model_selector, 'second');
  assert.deepEqual(body.generation_config, {max_output_tokens: 300, temperature: 0.25, top_p: 0.875});
  assert.equal(f.calls(), 0);
});

test('actual public materials refuse equal reconstructed registry and Task originals', () => {
  const f = fixture(), r = registry(), task = read(taskDocument());
  const material = normalize(f, r, task, undefined, undefined);
  for (const [otherRegistry, otherTask] of [[registry(), task], [r, read(taskDocument())]]) {
    assert.equal(runtimeUnboxedReferenceOption(moon.clientProgramProjectModelTaskSelectionFor(
      material.selection, otherRegistry, otherTask)), undefined);
    assert.throws(() => checked(moon.clientProgramNormalizeProjectModelTask(material.selection,
      otherRegistry, otherTask, material.defaults.value, ...bounds)), {code: 'MoonBitHostFailure'});
  }
  assert.equal(f.calls(), 0);
});

test('actual retained configuration does not rewrite prior Task materials after caller replacement', () => {
  const f = fixture(), r = registry(), task = read(taskDocument());
  const first = normalize(f, r, task, undefined, undefined);
  f.originals.configuration = original({replacement: true});
  const second = normalize(f, r, task, undefined, undefined);
  assert.equal(second.defaults.value, first.defaults.value);
  assert.equal(second.taskWire, first.taskWire);
  assert.equal(second.promptWire, first.promptWire);
  f.loseCurrent();
  assert.throws(() => normalize(f, r, task, undefined, undefined), {code: 'OriginalLost'});
  assert.equal(f.calls(), 0);
});
