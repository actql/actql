import assert from 'node:assert/strict';
import test from 'node:test';
import {admitInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {runtimeFailure, runtimePair} from '../host-common/compiler-binding.generated.mjs';

// Pure adapter counters with explicit Common doubles; actual generated runtime
// acceptance is a separate test. No file, Host, secret, Provider or Run opens.
function common(selected) {
  const calls = [], configuration = Object.freeze({fixture: 'configuration'}),
    registry = Object.freeze({fixture: 'registry'});
  const moon = {
    clientProjectConfigurationAdmit(wire) {
      assert.strictEqual(this, moon); calls.push(['configuration', wire]);
      return {$tag: 1, _0: configuration};
    },
    clientProjectConfigurationModelTasksFile(original) {
      assert.strictEqual(this, moon); assert.strictEqual(original, configuration);
      return selected;
    },
    clientProjectModelRegistryAdmit(wire) {
      assert.strictEqual(this, moon); calls.push(['registry', wire]);
      return {$tag: 1, _0: registry};
    },
  };
  return {moon, configuration, registry, calls};
}

test('project adapter retains the exact original configuration registry and receiver', () => {
  const {moon, configuration, registry, calls} = common('./tasks.json');
  const configWire = ' {"original":"configuration"}\n', registryWire = ' {"original":"registry"} ';
  const admitted = admitInstalledProjectConfiguration(moon, configWire, registryWire);
  const original = admitted.originalsForRuntime(moon);
  assert.strictEqual(original.configuration, configuration);
  assert.strictEqual(original.modelRegistry, registry);
  assert.equal(original.configurationWire, configWire);
  assert.equal(original.modelRegistryWire, registryWire);
  assert.strictEqual(admitted.originalsForRuntime(moon), original);
  assert(Object.isFrozen(admitted)); assert(Object.isFrozen(original));
  assert.deepEqual(calls, [['configuration', configWire], ['registry', registryWire]]);
  assert.throws(() => admitted.originalsForRuntime({...moon}),
    {code: 'ForeignInstalledProjectRuntime'});
});

test('plain project does not require or fabricate a Model registry', () => {
  const {moon, configuration, calls} = common(undefined);
  delete moon.clientProjectModelRegistryAdmit;
  const original = admitInstalledProjectConfiguration(moon, '{}').originalsForRuntime(moon);
  assert.strictEqual(original.configuration, configuration);
  assert.equal(original.modelRegistry, undefined);
  assert.deepEqual(calls, [['configuration', '{}']]);
  assert.throws(() => admitInstalledProjectConfiguration(moon, '{}', '{}'),
    {code: 'UnexpectedInstalledProjectRegistry'});
});

test('selected missing registry cannot become a source-free project or ambient runtime', () => {
  const {moon, calls} = common('./selected.json');
  assert.throws(() => admitInstalledProjectConfiguration(moon, '{}'),
    {code: 'InstalledProjectRegistryUnavailable'});
  assert.deepEqual(calls, [['configuration', '{}']]);
  assert.throws(() => admitInstalledProjectConfiguration(null, '{}'),
    {code: 'InstalledProjectRuntimeUnavailable'});
  delete moon.clientProjectModelRegistryAdmit;
  assert.throws(() => admitInstalledProjectConfiguration(moon, '{}', '{}'),
    {code: 'InstalledProjectRuntimeUnavailable'});
});

test('Common rejection and abnormal return are not a successful original pair', () => {
  const {moon, calls} = common('./tasks.json');
  const issue = Object.freeze({fixture: 'original refusal'});
  moon.clientProjectConfigurationAdmit = () => runtimeFailure(issue);
  assert.throws(() => admitInstalledProjectConfiguration(moon, '{}', '{}'),
    error => error.code === 'MoonBitHostFailure' && error.cause === issue);
  assert.deepEqual(calls, []);
  moon.clientProjectConfigurationAdmit = () => runtimePair('not', 'a result');
  assert.throws(() => admitInstalledProjectConfiguration(moon, '{}', '{}'),
    {code: 'InvalidHostRuntimeResult'});
  const accepted = common('./tasks.json');
  accepted.moon.clientProjectModelRegistryAdmit = () => runtimeFailure(issue);
  assert.throws(() => admitInstalledProjectConfiguration(accepted.moon, '{}', '{}'),
    error => error.code === 'MoonBitHostFailure' && error.cause === issue);
});

test('project material strings are not coerced or replaced through object callbacks', () => {
  const {moon, calls} = common('./tasks.json');
  const hostile = {toString() { assert.fail('do not coerce materials'); }};
  for (const wire of [null, false, 0, {}, hostile]) {
    assert.throws(() => admitInstalledProjectConfiguration(moon, wire),
      {code: 'InvalidInstalledProjectMaterials'});
    assert.throws(() => admitInstalledProjectConfiguration(moon, '{}', wire),
      {code: 'InvalidInstalledProjectMaterials'});
  }
  assert.deepEqual(calls, []);
});
