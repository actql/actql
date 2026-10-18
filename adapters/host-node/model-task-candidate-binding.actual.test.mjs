import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, writeFile, rm, open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {prepareInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {installModelProviders, prepareInstalledModelProviderDefaults,
  assertInstalledModelDefaultsPreparation} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

assert.ok(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME,
  'A matching actual Common runtime is required; do not skip');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const original = body => {
  const wire = canonical(body);
  return {wire, cid: 'sha256:' + createHash('sha256').update(wire).digest('hex')};
};
const providerId = 'models/candidate-fixture';
const limits = Object.freeze({maxTasks: 4, maxBytes: 16384, maxNodes: 1000,
  maxDepth: 32, maxMembers: 100, contractNodes: 100, contractDepth: 16,
  contractTextBytes: 1000, maxWork: 1000000});
const readerLimits = Object.freeze(Object.fromEntries(
  ['maxBytes', 'maxNodes', 'maxDepth', 'maxMembers', 'maxWork'].map(key => [key, limits[key]])));
const policy = original({schema: 'actql.contract/0.1', id: 'candidate-fixture-policy',
  version: 'fixture-1', kind: 'request_data_handling', body: {
    accepted_classifications: ['public'], allowed_regions: ['fixture'],
    retention: 'none', training_use: 'forbidden'}});

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-task-candidates-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  await writeFile(join(directory, 'actql.config.json'),
    '{"version":"actql-config/0.1","model_tasks":"./model-tasks.json"}');
  await writeFile(join(directory, 'model-tasks.json'), canonical({version: 'actql-model-tasks/0.1',
    tasks: {'model-task:candidate': './task.json'},
    providers: {[providerId]: {type: 'fixture'}}, default_provider: providerId}));
  await writeFile(join(directory, 'task.json'), canonical({task: 'model-task:candidate',
    instructions: 'Exact é\r\n', input: {text: 'string'}, output: {answer: 'boolean'},
    limits: {max_output_tokens: 200}}));
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  const bindings = providerBindingOriginals(providerId);
  bindings.configurationContract = original({...JSON.parse(bindings.configurationContract.wire),
    required: ['endpoint', 'principal', 'selector', 'tenant', 'model_defaults']});
  bindings.configuration = original({...JSON.parse(bindings.configuration.wire), model_defaults: {
    default_model: 'selected', models: [{model: 'selected',
      data_handling: {...JSON.parse(policy.wire), cid: policy.cid},
      generation_config: {temperature: 0, top_p: 1, max_output_tokens: 100}}]}});
  let current = true, registrations = 0, invokes = 0;
  const check = () => { if (!current) throw Object.assign(new Error('OriginalLost'), {code: 'OriginalLost'}); };
  const defaults = prepareInstalledModelProviderDefaults(moon, providerId, bindings, {assertCurrent: check});
  const candidates = new Map([[providerId, defaults]]);
  const prepare = options => prepareInstalledProjectModelTasks(moon, project, candidates,
    {limits, assertCurrent: check, ...options});
  const register = (selected = defaults, entryBindings = selected.bindingOriginals, runtime = moon) => {
    const entry = selected.bindRegistration({providerId, bindingOriginals: entryBindings,
      validatePrompt: () => true,
      // Explicit synchronous no-I/O fixture, not a physical Model supplier.
      invoke() { invokes++; assert.fail('No Model call'); }});
    return installModelProviders(runtime, actual => {
      assert.equal(actual, runtime); registrations++; return [entry];
    }, check, check);
  };
  return {directory, project, bindings, defaults, candidates, prepare, register, check,
    loseCurrent: () => { current = false; }, counts: () => ({registrations, invokes})};
}

test('actual Common Task candidates precede registration and retain the same defaults after adoption', async t => {
  const f = await fixture(t), view = await f.prepare();
  const candidates = view.originalsForRuntime(moon), task = candidates[0];
  assert.equal(candidates.length, 1);
  assert.equal(task.provider, undefined);
  assert.equal(view.projectEnvironmentForRuntime, undefined);
  assert.equal(JSON.parse(task.taskWire).generation_config.max_output_tokens, 200);
  assert.equal(JSON.parse(task.taskWire).data_handling.contract_cid, policy.cid);
  assert.equal(JSON.parse(task.promptWire).payload.instructions, 'Exact é\r\n');
  assert.deepEqual(f.counts(), {registrations: 0, invokes: 0});
  const providers = f.register(), provider = providers.get(providerId);
  const installed = view.bindInstalledProviders(providers);
  const bound = installed.originalsForRuntime(moon)[0];
  assert.equal(bound.provider, provider);
  assert.equal(bound.normalized, task.normalized);
  assert.equal(bound.task, task.task);
  assert.equal(bound.selection, task.selection);
  assert.equal(bound.taskWire, task.taskWire);
  const adopted = provider.resolveTaskDefaults(undefined, undefined, readerLimits);
  assert.equal(adopted.value, task.defaults.value, 'same Common profile, not equal-wire re-admission');
  assert.equal(adopted.binding.value, task.defaults.binding.value);
  assert.equal(adopted.binding.originals, f.defaults.bindingOriginals);
  assert.equal(typeof installed.projectEnvironmentForRuntime, 'function');
  const base = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
  const projected = installed.projectEnvironmentForRuntime(moon, base, JSON.parse(base).evidence_bundle_cid);
  assert.deepEqual(JSON.parse(projected.environmentWire).model_task_contracts,
    [JSON.parse(task.taskWire)]);
  assert.deepEqual(f.counts(), {registrations: 1, invokes: 0});
});

test('candidate adoption refuses copied/equal configuration and another runtime before Core installation', async t => {
  const f = await fixture(t);
  assert.throws(() => f.register(f.defaults, {...f.defaults.bindingOriginals}),
    {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.throws(() => f.register(f.defaults, f.defaults.bindingOriginals, {...moon}),
    {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.throws(() => assertInstalledModelDefaultsPreparation({...f.defaults}, moon, providerId),
    {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.throws(() => assertInstalledModelDefaultsPreparation(f.defaults, moon, 'foreign'),
    {code: 'InstalledModelDefaultsForeignOriginal'});
  const view = await f.prepare();
  const other = prepareInstalledModelProviderDefaults(moon, providerId, f.bindings, {assertCurrent: f.check});
  const foreign = f.register(other);
  assert.throws(() => view.bindInstalledProviders(foreign), {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.equal(f.counts().invokes, 0);
});

test('one candidate cannot issue a second installed Provider or move to another installation', async t => {
  const f = await fixture(t), view = await f.prepare(), first = f.register();
  const installed = view.bindInstalledProviders(first);
  assert.throws(() => f.register(), {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.equal(installed.originalsForRuntime(moon)[0].provider, first.get(providerId));
  first.set(providerId, {...first.get(providerId)});
  assert.throws(() => installed.originalsForRuntime(moon), {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.equal(f.counts().invokes, 0);
});

test('candidate rejects another installation current original before its first adoption', async t => {
  const f = await fixture(t);
  const entry = f.defaults.bindRegistration({providerId, bindingOriginals: f.defaults.bindingOriginals,
    validatePrompt: () => true, invoke() { assert.fail('No Model call'); }});
  const foreignCurrent = () => f.check();
  assert.throws(() => installModelProviders(moon, () => [entry], foreignCurrent, foreignCurrent),
    {code: 'InstalledModelDefaultsForeignOriginal'});
  // A refused foreign original cannot spend the intended installation's DATA.
  const view = await f.prepare();
  assert.equal(view.bindInstalledProviders(f.register()).originalsForRuntime(moon).length, 1);
});

test('candidate preparation retains its original snapshot and single-attempt reader bounds', async t => {
  const f = await fixture(t);
  const small = {...readerLimits, maxWork: 1}; let failure;
  assert.throws(() => f.defaults.resolveTaskDefaults(undefined, undefined, small), error => {
    failure = error; return error.code === 'MoonBitHostFailure';
  });
  f.bindings.configuration = original({replacement: true});
  assert.throws(() => f.defaults.resolveTaskDefaults(undefined, undefined, small), error => error === failure);
  assert.throws(() => f.defaults.resolveTaskDefaults(undefined, undefined, readerLimits),
    {code: 'InstalledModelDefaultsLimitsChanged'});
  assert.throws(() => Reflect.apply(f.defaults.resolveTaskDefaults, {...f.defaults},
    [undefined, undefined, small]), {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.deepEqual(f.counts(), {registrations: 0, invokes: 0});
});

test('candidate files retain after-await current and pending original FD cleanup obligations', async t => {
  const f = await fixture(t); let closes = 0, failure;
  await assert.rejects(f.prepare({openFile: async (...args) => {
    const fd = await open(...args);
    return {read: (...args) => fd.read(...args), async close() {
      if (++closes === 1) return false;
      await fd.close();
    }};
  }}), error => { failure = error; return error.cleanupPending === true; });
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(closes, 2);
  await assert.rejects(f.prepare({openFile: async (...args) => {
    const fd = await open(...args);
    return {read: (...args) => fd.read(...args), async close() { await fd.close(); f.loseCurrent(); }};
  }}), {code: 'OriginalLost'});
  assert.throws(() => f.register(), {code: 'OriginalLost'});
  assert.deepEqual(f.counts(), {registrations: 0, invokes: 0});
});

test('bound candidate currentness keeps both original project and actual registration fences', async t => {
  const f = await fixture(t), view = await f.prepare(), providers = f.register();
  const installed = view.bindInstalledProviders(providers);
  assert.throws(() => installed.originalsForRuntime({...moon}), {code: 'ForeignInstalledProjectRuntime'});
  f.loseCurrent();
  assert.throws(() => view.originalsForRuntime(moon), {code: 'OriginalLost'});
  assert.throws(() => installed.originalsForRuntime(moon), {code: 'OriginalLost'});
  assert.throws(() => providers.get(providerId).resolveTaskDefaults(undefined, undefined, readerLimits),
    {code: 'OriginalLost'});
  assert.equal(f.counts().invokes, 0);
});
