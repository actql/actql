import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, rm, open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadInstalledProjectConfiguration, resolveInstalledProjectTaskPath, retireInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {loadInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {installModelProviders} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

assert.ok(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME,
  'An input-matching actual Common runtime is required; do not skip');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const original = body => {
  const wire = canonical(body);
  return {wire, cid: 'sha256:' + createHash('sha256').update(wire).digest('hex')};
};
const providerId = 'models/project-fixture';
const limits = Object.freeze({maxTasks: 4, maxBytes: 16384, maxNodes: 1000,
  maxDepth: 32, maxMembers: 100, contractNodes: 100, contractDepth: 16,
  contractTextBytes: 1000, maxWork: 1000000});
const policy = original({schema: 'actql.contract/0.1', id: 'explicit-fixture-policy',
  version: 'fixture-r1', kind: 'request_data_handling', body: {
    accepted_classifications: ['public'], allowed_regions: ['fixture'],
    retention: 'none', training_use: 'forbidden'}});
const declaration = name => `task: ${name}\ninput:\n  notes: string\noutput:\n  enabled: boolean\ninstructions: |-\n  Original é\n  second line\nlimits:\n  max_output_tokens: 200\n`;

async function fixture(t, tasks = {'model-task:project': './task.yaml'}, registry = 'model-tasks.json') {
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-tasks-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  await writeFile(join(directory, 'actql.config.json'),
    JSON.stringify({version: 'actql-config/0.1', model_tasks: './' + registry}));
  await mkdir(dirname(join(directory, registry)), {recursive: true});
  await writeFile(join(directory, registry), canonical({version: 'actql-model-tasks/0.1',
    tasks, providers: {[providerId]: {type: 'fixture'}}, default_provider: providerId}));
  await writeFile(join(directory, 'task.yaml'), declaration('model-task:root-decoy'));
  await writeFile(join(dirname(join(directory, registry)), 'task.yaml'), declaration('model-task:project'));
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  let current = true, sends = 0;
  const assertCurrent = () => {
    if (!current) throw Object.assign(new Error('OriginalProjectLost'), {code: 'OriginalProjectLost'});
  };
  const binding = providerBindingOriginals(providerId);
  binding.configurationContract = original({...JSON.parse(binding.configurationContract.wire),
    required: ['endpoint', 'principal', 'selector', 'tenant', 'model_defaults']});
  const setPolicy = present => {
    binding.configuration = original({...JSON.parse(binding.configuration.wire), model_defaults: {
      default_model: 'first', models: [{model: 'first',
        ...(present ? {data_handling: {...JSON.parse(policy.wire), cid: policy.cid}} : {}),
        generation_config: {temperature: 0, top_p: 1, max_output_tokens: 100}}]}});
  };
  setPolicy(true);
  const providers = () => installModelProviders(moon, actual => {
    assert.equal(actual, moon);
    return [{providerId, bindingOriginals: binding, validatePrompt: () => true,
      invoke() { sends++; assert.fail('No physical Provider invocation'); }}];
  }, assertCurrent, assertCurrent);
  return {directory, project, providers, setPolicy, assertCurrent,
    loseCurrent: () => { current = false; }, sends: () => sends};
}

test('actual project file and actual registration normalize the same retained Task originals', async t => {
  const f = await fixture(t), providers = f.providers();
  const view = await loadInstalledProjectModelTasks(moon, f.project, providers,
    {limits, assertCurrent: f.assertCurrent});
  const tasks = view.originalsForRuntime(moon);
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].name, 'model-task:project');
  assert.equal(tasks[0].path, join(f.directory, 'task.yaml'));
  assert.equal(tasks[0].wire, declaration('model-task:project'));
  assert.strictEqual(tasks[0].provider, providers.get(providerId));
  assert.equal(JSON.parse(tasks[0].taskWire).generation_config.max_output_tokens, 200);
  assert.equal(JSON.parse(tasks[0].taskWire).data_handling.contract_cid, policy.cid);
  assert.equal(JSON.parse(tasks[0].promptWire).payload.instructions, 'Original é\nsecond line');
  assert.ok(Object.isFrozen(tasks) && Object.isFrozen(tasks[0]));
  assert.strictEqual(view.originalsForRuntime(moon), tasks);
  await writeFile(join(f.directory, 'task.yaml'), declaration('model-task:replacement'));
  assert.equal(view.originalsForRuntime(moon)[0].wire, declaration('model-task:project'),
    'Retained originals do not re-resolve replacement files');
  assert.equal(f.sends(), 0);
  assert.throws(() => view.originalsForRuntime({...moon}), {code: 'ForeignInstalledProjectRuntime'});
  f.loseCurrent();
  assert.throws(() => view.originalsForRuntime(moon), {code: 'OriginalProjectLost'});
});

test('actual project rejects copied project and foreign runtime before file acquisition', async t => {
  const f = await fixture(t);
  let reads = 0;
  const options = {limits, assertCurrent: f.assertCurrent,
    openFile: async () => { reads++; assert.fail('No file acquisition'); }};
  await assert.rejects(loadInstalledProjectModelTasks(moon, {...f.project}, f.providers(), options),
    {code: 'ForeignInstalledProjectOriginal'});
  await assert.rejects(loadInstalledProjectModelTasks({...moon}, f.project, f.providers(), options),
    {code: 'ForeignInstalledProjectRuntime'});
  assert.equal(reads, 0);
});

test('actual project rejects a Task file declaring another registered occurrence', async t => {
  const f = await fixture(t, {'model-task:other': './task.yaml', 'model-task:project': './task.yaml'});
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(),
    {limits, assertCurrent: f.assertCurrent}), {code: 'InvalidInstalledProjectTaskSelection'});
  assert.equal(f.sends(), 0);
});

test('actual project rechecks currentness after awaited read and confirmed close', async t => {
  const f = await fixture(t);
  let closes = 0;
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(), {
    limits, assertCurrent: f.assertCurrent, openFile: async (...args) => {
      const fd = await open(...args);
      return {read: (...args) => fd.read(...args), async close() {
        await fd.close(); closes++; f.loseCurrent();
      }};
    },
  }), {code: 'OriginalProjectLost'});
  assert.equal(closes, 1);
  assert.equal(f.sends(), 0);
});

test('actual project rejects missing Provider or applicable handling original without invoking it', async t => {
  const f = await fixture(t);
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, new Map(),
    {limits, assertCurrent: f.assertCurrent}), {code: 'InstalledModelDefaultsUnavailable'});
  f.setPolicy(false);
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(),
    {limits, assertCurrent: f.assertCurrent}), {code: 'MoonBitHostFailure'});
  assert.equal(f.sends(), 0);
});

test('actual project keeps pending FD cleanup responsibility and refuses malformed UTF8', async t => {
  const f = await fixture(t);
  await writeFile(join(f.directory, 'task.yaml'), Buffer.from([0xff]));
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(),
    {limits, assertCurrent: f.assertCurrent}), {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
  await writeFile(join(f.directory, 'task.yaml'), declaration('model-task:project'));
  let closeCalls = 0;
  let failure;
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(), {
    limits, assertCurrent: f.assertCurrent, openFile: async (...args) => {
      const fd = await open(...args);
      return {read: (...args) => fd.read(...args), async close() {
        closeCalls++;
        if (closeCalls === 1) return false;
        return fd.close();
      }};
    },
  }), error => { failure = error; return error.cleanupPending === true; });
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(closeCalls, 2);
  assert.equal(f.sends(), 0);
});

test('actual project snapshots bounds once and refuses count overflow before file acquisition', async t => {
  const f = await fixture(t);
  let gets = 0, reads = 0;
  const selected = {...limits, get maxBytes() { gets++; return gets === 1 ? limits.maxBytes : 0; }};
  const view = await loadInstalledProjectModelTasks(moon, f.project, f.providers(),
    {limits: selected, assertCurrent: f.assertCurrent});
  assert.equal(view.originalsForRuntime(moon).length, 1);
  assert.equal(gets, 1);
  await assert.rejects(loadInstalledProjectModelTasks(moon, f.project, f.providers(), {
    limits: {...limits, maxTasks: 0}, assertCurrent: f.assertCurrent,
    openFile: async () => { reads++; assert.fail('No acquisition over count bound'); },
  }), {code: 'InstalledProjectTaskCountLimit'});
  assert.equal(reads, 0);
});

test('actual retained project detects replacement of the selected installation provider', async t => {
  const f = await fixture(t), providers = f.providers();
  const view = await loadInstalledProjectModelTasks(moon, f.project, providers,
    {limits, assertCurrent: f.assertCurrent});
  providers.set(providerId, f.providers().get(providerId));
  assert.throws(() => view.originalsForRuntime(moon), {code: 'InstalledModelDefaultsForeignOriginal'});
  assert.equal(f.sends(), 0);
});


test('actual normal Task loading uses the nested registry base instead of a project-root decoy', async t => {
  const f = await fixture(t, {'model-task:project': './task.yaml'}, 'models/registry.json');
  const view = await loadInstalledProjectModelTasks(moon, f.project, f.providers(),
    {limits, assertCurrent: f.assertCurrent});
  const [task] = view.originalsForRuntime(moon);
  assert.equal(task.path, join(f.directory, 'models', 'task.yaml'));
  assert.equal(task.wire, declaration('model-task:project'));
  assert.equal(f.sends(), 0);
});

test('shared Task locator keeps existing path interpretation and rejects foreign retired originals', async t => {
  const f = await fixture(t, {'model-task:project': './task.yaml'}, 'models/registry.json');
  assert.equal(resolveInstalledProjectTaskPath(f.project, moon, '../task.yaml'), join(f.directory, 'task.yaml'));
  const absolute = resolve(f.directory, 'elsewhere', 'task.yaml');
  assert.equal(resolveInstalledProjectTaskPath(f.project, moon, absolute), absolute);
  assert.throws(() => resolveInstalledProjectTaskPath({...f.project}, moon, './task.yaml'),
    {code: 'ForeignInstalledProjectOriginal'});
  assert.throws(() => resolveInstalledProjectTaskPath(f.project, {...moon}, './task.yaml'),
    {code: 'ForeignInstalledProjectRuntime'});
  retireInstalledProjectConfiguration(f.project, moon);
  assert.throws(() => resolveInstalledProjectTaskPath(f.project, moon, './task.yaml'),
    {code: 'InstalledProjectOriginalRetired'});
});
