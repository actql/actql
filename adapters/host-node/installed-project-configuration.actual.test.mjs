import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {admitInstalledProjectConfiguration} from './installed-project-configuration.mjs';

// The outer source/artifact guard supplies an exact newly built runtime. Never
// silently fall back to another retained package or count registration as run.
if (!process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME) {
  throw new Error('MissingActualProjectCommonRuntime');
}
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
const config = ' {"version":"actql-config/0.1","state_dir":"./.actql","model_tasks":"./model-tasks.json","profile":"mock","mock":{"data":"./mock/data.json","answers":{"model-task:risk.v1":"./mock/answers.yaml"}}} ';
const registry = ' {"version":"actql-model-tasks/0.1","tasks":{"model-task:risk.v1":"./model-tasks/risk.yaml"},"providers":{"original":{"type":"openai","api_key_env":"KEY_NOT_READ"}},"default_provider":"original"} ';

test('actual Common retains the original project registry pair and all selected locators', () => {
  const selected = admitInstalledProjectConfiguration(moon, config, registry);
  const original = selected.originalsForRuntime(moon);
  assert.equal(original.configurationWire, config);
  assert.equal(original.modelRegistryWire, registry);
  assert.equal(moon.clientProjectConfigurationStateDirectory(original.configuration), './.actql');
  assert.equal(moon.clientProjectConfigurationModelTasksFile(original.configuration), './model-tasks.json');
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
  assert.equal(moon.clientProjectConfigurationModelTasksFile(original.configuration) == null, true);
  assert.equal(original.modelRegistry, undefined);
  assert.throws(() => admitInstalledProjectConfiguration(moon,
    '{"version":"actql-config/0.1"}', registry),
  {code: 'UnexpectedInstalledProjectRegistry'});
});
