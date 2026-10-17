import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {admitInstalledProjectConfiguration,
  loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

// The outer source/artifact guard supplies an exact newly built runtime. Never
// silently fall back to another retained package or count registration as run.
if (!process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME) {
  throw new Error('MissingActualProjectCommonRuntime');
}
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
const config = ' {"version":"actql-config/0.1","state_dir":"./.actql","connectors":"./connectors.json","model_tasks":"./model-tasks.json","lock":"./project.lock","profile":"mock","mock":{"data":"./mock/data.json","answers":{"model-task:risk.v1":"./mock/answers.yaml"}}} ';
const registry = ' {"version":"actql-model-tasks/0.1","tasks":{"model-task:risk.v1":"./model-tasks/risk.yaml"},"providers":{"original":{"type":"openai","api_key_env":"KEY_NOT_READ"}},"default_provider":"original"} ';

test('actual Common retains the original project registry pair and all selected locators', () => {
  const selected = admitInstalledProjectConfiguration(moon, config, registry);
  const original = selected.originalsForRuntime(moon);
  assert.equal(original.configurationWire, config);
  assert.equal(original.modelRegistryWire, registry);
  assert.equal(moon.clientProjectConfigurationStateDirectory(original.configuration), './.actql');
  assert.equal(moon.clientProjectConfigurationConnectorsFile(original.configuration), './connectors.json');
  assert.equal(moon.clientProjectConfigurationModelTasksFile(original.configuration), './model-tasks.json');
  assert.equal(moon.clientProjectConfigurationLockFile(original.configuration), './project.lock');
  assert.equal(moon.clientProjectConfigurationSelectedProfile(original.configuration), 'mock');
  assert.equal(moon.clientProjectConfigurationMockDataFile(original.configuration), './mock/data.json');
  assert.equal(moon.clientProjectConfigurationMockAnswerCount(original.configuration), 1);
  assert.equal(moon.clientProjectConfigurationMockAnswerTask(original.configuration, 0), 'model-task:risk.v1');
  assert.equal(moon.clientProjectConfigurationMockAnswerFile(original.configuration, 0), './mock/answers.yaml');
  assert.equal(moon.clientProjectModelRegistryOriginalWire(original.modelRegistry), registry);
  assert.equal(moon.clientProjectModelRegistryTaskCount(original.modelRegistry), 1);
  assert.equal(moon.clientProjectModelRegistryTaskName(original.modelRegistry, 0), 'model-task:risk.v1');
  assert.equal(moon.clientProjectModelRegistryTaskFile(original.modelRegistry, 0), './model-tasks/risk.yaml');
  assert.equal(moon.clientProjectModelRegistryProviderCount(original.modelRegistry), 1);
  assert.equal(moon.clientProjectModelRegistryProviderName(original.modelRegistry, 0), 'original');
  assert.equal(moon.clientProjectModelRegistryProviderType(original.modelRegistry, 0), 'openai');
  assert.equal(moon.clientProjectModelRegistryProviderKeyEnvironment(original.modelRegistry, 0), 'KEY_NOT_READ');
  assert.equal(moon.clientProjectModelRegistryDefaultProvider(original.modelRegistry), 'original');
  assert.equal(moon.clientProjectModelRegistryTaskName(original.modelRegistry, 1) == null, true);
  assert.equal(moon.clientProjectConfigurationMockAnswerTask(original.configuration, -1) == null, true);
  assert.strictEqual(selected.originalsForRuntime(moon), original);
  assert.throws(() => selected.originalsForRuntime({...moon}),
    {code: 'ForeignInstalledProjectRuntime'});
});

test('actual Common refuses changed closed shapes and unresolved original registry selection', () => {
  for (const wire of ['null', config.replace('"profile":"mock"', '"profile":null'),
    config.replace('"profile":"mock"', '"profile":"mock","allow":true')]) {
    assert.throws(() => admitInstalledProjectConfiguration(moon, wire, registry),
      {code: 'MoonBitHostFailure'});
  }
  for (const wire of ['null', registry.replace('"default_provider":"original"', '"default_provider":"foreign"'),
    registry.replace('"type":"openai"', '"type":"openai","api_key":"not-a-secret"'),
    registry.replace('"tasks":{', '"tasks":{},"tasks":{')]) {
    assert.throws(() => admitInstalledProjectConfiguration(moon, config, wire),
      {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => admitInstalledProjectConfiguration(moon, config),
    {code: 'InstalledProjectRegistryUnavailable'});
});

test('actual Common plain project keeps absent registry and does not accept unrelated material', () => {
  const selected = admitInstalledProjectConfiguration(moon, '{"version":"actql-config/0.1"}');
  const original = selected.originalsForRuntime(moon);
  assert.equal(moon.clientProjectConfigurationStateDirectory(original.configuration), './.actql');
  assert.equal(moon.clientProjectConfigurationConnectorsFile(original.configuration) == null, true);
  assert.equal(moon.clientProjectConfigurationLockFile(original.configuration) == null, true);
  assert.equal(moon.clientProjectConfigurationModelTasksFile(original.configuration) == null, true);
  assert.equal(original.modelRegistry, undefined);
  assert.throws(() => admitInstalledProjectConfiguration(moon,
    '{"version":"actql-config/0.1"}', registry),
  {code: 'UnexpectedInstalledProjectRegistry'});
});

test('actual Common receives one discovered original pair from real bounded file reads', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-originals-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const child = join(directory, 'nested', 'work');
  await mkdir(child, {recursive: true});
  const configWire = ' {"version":"actql-config/0.1","state_dir":"./state-e\u0301😀","model_tasks":"./tasks.json"}\n';
  await writeFile(join(directory, 'actql.config.json'), configWire);
  await writeFile(join(directory, 'tasks.json'), registry);
  const selected = await loadInstalledProjectConfiguration(moon, {directory: child});
  assert.equal(selected.configurationPath, join(directory, 'actql.config.json'));
  assert.equal(selected.directory, directory);
  assert.equal(selected.stateDirectory, join(directory, 'state-e\u0301😀'));
  assert.equal(selected.registryPath, join(directory, 'tasks.json'));
  const original = selected.originalsForRuntime(moon);
  assert.equal(original.configurationWire, configWire);
  assert.equal(original.modelRegistryWire, registry);
  assert.equal(moon.clientProjectConfigurationStateDirectory(original.configuration), './state-e\u0301😀');
  assert.equal(moon.clientProjectModelRegistryOriginalWire(original.modelRegistry), registry);
  assert.equal(moon.clientProjectModelRegistryTaskName(original.modelRegistry, 0), 'model-task:risk.v1');
  assert.strictEqual(selected.originalsForRuntime(moon), original);
  assert.throws(() => selected.originalsForRuntime({...moon}),
    {code: 'ForeignInstalledProjectRuntime'});
});

test('actual Common nearer malformed configuration never adopts a valid parent', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-refusal-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const child = join(directory, 'child');
  await mkdir(child);
  await writeFile(join(directory, 'actql.config.json'), '{"version":"actql-config/0.1"}');
  for (const wire of ['{"version":"actql-config/0.1","version":"actql-config/0.1"}',
    '{"version":"actql-config/0.1","permission":"allow"}',
    '{"version":"actql-config/0.1","state_dir":null}']) {
    await writeFile(join(child, 'actql.config.json'), wire);
    await assert.rejects(loadInstalledProjectConfiguration(moon, {directory: child}),
      {code: 'MoonBitHostFailure'});
  }
  await writeFile(join(child, 'actql.config.json'), Buffer.from([0xff]));
  await assert.rejects(loadInstalledProjectConfiguration(moon, {directory: child}),
    {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
});

test('actual Common selected registry absence and foreign shape cannot become a plain project', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-registry-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  await writeFile(join(directory, 'actql.config.json'),
    '{"version":"actql-config/0.1","model_tasks":"./selected.json"}');
  await assert.rejects(loadInstalledProjectConfiguration(moon, {directory}), {code: 'ENOENT'});
  await writeFile(join(directory, 'selected.json'),
    registry.replace('"default_provider":"original"', '"default_provider":"foreign"'));
  await assert.rejects(loadInstalledProjectConfiguration(moon, {directory}),
    {code: 'MoonBitHostFailure'});
});
