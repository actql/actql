// Orchestration controls only: no packages, Host, compiler or Provider execute.
import assert from 'node:assert/strict';
import {appendFileSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {parse} from 'acorn';
import {configuration} from './fixtures/installed-infer-fixture.mjs';
import {exercisePackedInferSource} from './packed-infer-source-acceptance.mjs';

// Independent literal inventories, never read from the selected fixture map.
const fullPositiveCases = [
  'default-keep', 'wildcard-keep', 'omitted-item-key', 'historical-key',
  'historical-key-frozen', 'historical-key-original-rename',
  'historical-key-composite', 'literal-input', 'expression-input', 'minimal',
  'folded-input', 'quoted-input', 'keep', 'keep-filter', 'folded-filter',
  'folded-projection', 'folded-key', 'folded-empty', 'nullable-keep', 'empty',
  'provider-error', 'provider-error-folded', 'provider-error-projection',
  'guard-distinct', 'guard-nonnull',
];
const fullRefusalCases = [
  'historical-key-hidden-lookup', 'historical-key-label-collision',
  'omitted-key-unproven', 'omitted-key-ambiguous', 'unknown-input',
  'duplicate-input', 'unknown-member', 'folded-unproven-key', 'dropped-input',
  'old-alias', 'unproven-key', 'name-collision',
];
const fullRuntimeRefusalCases = ['guard-duplicate', 'guard-null'];
const fullCaptureCases = ['minimal', 'historical-key-frozen'];
const sourceSha = '1111111111111111111111111111111111111111';
const commonConnectionSha = 'f9e6dbe36d263ef7baf4799646a1c53ebca47df9';

function expectedSelection(inputFieldsOnly) {
  return inputFieldsOnly ? {
    positiveCases: ['minimal', 'folded-input', 'quoted-input'],
    refusalCases: ['unknown-input', 'duplicate-input'],
    runtimeRefusalCases: [],
    captureCases: ['minimal'],
  } : {
    positiveCases: fullPositiveCases,
    refusalCases: fullRefusalCases,
    runtimeRefusalCases: fullRuntimeRefusalCases,
    captureCases: fullCaptureCases,
  };
}

function expectedCommands(selection) {
  return ['local', 'remote'].flatMap(transport => [
    ...selection.positiveCases.map(name => [transport, 'success', name]),
    ...selection.refusalCases.map(name => [transport, 'refusal', name]),
    ...selection.runtimeRefusalCases.map(name => [transport, 'runtime-refusal', name]),
    ...selection.captureCases.flatMap(name => [
      [transport, 'capture', name], [transport, 'replay', name],
    ]),
  ]);
}

function expectedProviderCalls(selection) {
  return ['local', 'remote'].flatMap(transport => [
    ...selection.positiveCases
      .filter(name => !['empty', 'folded-empty'].includes(name))
      .map(name => `${transport}:success:${name}`),
    ...selection.captureCases.map(name => `${transport}:capture:${name}`),
  ]);
}

async function fixture(t, inputFieldsOnly, failAt) {
  const base = await mkdtemp(join(tmpdir(), 'actql-infer-orchestration-'));
  t.after(() => rm(base, {recursive: true, force: true}));
  const root = join(base, 'installed');
  const directory = join(base, 'evidence');
  await mkdir(root);
  await mkdir(directory);
  const callPath = join(root, 'source-provider-calls.jsonl');
  await writeFile(callPath, '');
  const environment = Object.freeze({ACTQL_ORCHESTRATION_CONTROL: 'not-runtime'});
  const selection = expectedSelection(inputFieldsOnly);
  const commands = expectedCommands(selection);
  const providerCalls = expectedProviderCalls(selection);
  const calls = [];
  const messages = [];
  t.mock.method(console, 'log', value => messages.push(value));
  const failure = new Error('IndependentlyAuthoredInferCommandFailure');
  const options = {
    root, directory, environment, sourceSha, inputFieldsOnly,
    run(command, args, cwd, env, timeout) {
      assert.equal(command, process.execPath);
      assert.deepEqual(args, ['packed-infer-source.mjs', ...commands[calls.length]]);
      assert.equal(cwd, root);
      assert.equal(env, environment, 'pass the original selected environment');
      assert.equal(timeout, 120_000, 'retain the existing per-process bound');
      const selected = args.slice(1);
      calls.push(selected);
      if (failAt !== undefined && selected.join(':') === failAt) throw failure;
      const [transport, phase, caseName] = selected;
      if (providerCalls.includes(selected.join(':'))) {
        appendFileSync(callPath, JSON.stringify({transport, phase, caseName}) + '\n');
      }
      return 'orchestration-only control\n';
    },
  };
  return {options, selection, commands, providerCalls, calls, messages, failure,
    provenance: async () => JSON.parse(await readFile(
      join(directory, 'infer-source-provenance.json'), 'utf8'))};
}

for (const inputFieldsOnly of [false, true]) {
  test(`INFER orchestration pins the ${inputFieldsOnly ? 'input-fields' : 'full'} cohort without runtime execution`, async t => {
    const f = await fixture(t, inputFieldsOnly);
    await exercisePackedInferSource(f.options);
    assert.deepEqual(f.calls, f.commands);
    assert.equal(f.calls.length, inputFieldsOnly ? 14 : 86);
    assert.equal(f.providerCalls.length, inputFieldsOnly ? 8 : 50);
    assert.deepEqual(await f.provenance(), {
      sourceSha, commonConnectionSha, ...f.selection,
    });
    assert.equal(f.messages.length, f.commands.length + 1);
    assert.deepEqual(JSON.parse(f.messages.at(-1)), {
      sourceSha, acceptance: 'source-infer', transports: ['local', 'remote'],
      ...f.selection, calls: f.providerCalls,
    });
  });
}

for (const failAt of [
  'local:refusal:historical-key-hidden-lookup',
  'local:runtime-refusal:guard-duplicate',
  'local:capture:historical-key-frozen',
  'local:replay:historical-key-frozen',
]) {
  test(`INFER orchestration preserves command failure at ${failAt}`, async t => {
    const f = await fixture(t, false, failAt);
    await assert.rejects(exercisePackedInferSource(f.options), error => error === f.failure);
    const failedIndex = f.commands.findIndex(command => command.join(':') === failAt);
    assert.notEqual(failedIndex, -1);
    assert.deepEqual(f.calls, f.commands.slice(0, failedIndex + 1));
    assert.equal(f.messages.length, failedIndex, 'no success summary or later command after failure');
    assert.deepEqual(await f.provenance(), {
      sourceSha, commonConnectionSha, ...f.selection,
    });
  });
}


test('Source INFER Hosts retain the same authored Environment capacity as their Model original', async () => {
  const source = await readFile(new URL('./fixtures/packed-infer-source.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const calls = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' &&
        ['connect', 'openInstalledRemoteHttpHost'].includes(node.callee.name)) calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  }
  visit(tree);
  const baseEnvironment = JSON.parse(await readFile(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const {installation} = configuration(baseEnvironment);
  const authorization = Object.freeze({fixture: 'same-authorization'});
  const registerModelProviders = () => {throw new Error('NoProviderExecutionInSourceControl');};
  const entrances = calls.filter(call => call.callee.name === 'openInstalledRemoteHttpHost' ||
    call.arguments[0]?.properties?.some(property => property.key.name === 'installation'));
  assert.equal(entrances.length, 2, 'exercise the actual Local and HTTPS Host option expressions');
  for (const call of entrances) {
    const argument = call.arguments[0];
    const options = new Function('root', 'authorization', 'installation',
      'registerModelProviders', 'baseEnvironment', 'userInfo',
      `return (${source.slice(argument.start, argument.end)});`)(
      'fixture-root', authorization, installation, registerModelProviders,
      baseEnvironment, () => ({username: 'fixture-owner'}));
    const selected = call.callee.name === 'connect' ? options.installation : options;
    assert.equal(selected.hostCapacityPolicy, baseEnvironment.host_policy_profile.capacity,
      'the Host must select the same original policy that configuration encoded');
    assert.equal(selected.modelInstallation, installation);
    assert.equal(selected.authorization, authorization);
    assert.equal(selected.registerModelProviders, registerModelProviders);
    assert.deepEqual(JSON.parse(selected.modelInstallation.environmentWire).host_policy_profile.capacity,
      selected.hostCapacityPolicy, 'no replacement policy or derived capacity');
  }
});
