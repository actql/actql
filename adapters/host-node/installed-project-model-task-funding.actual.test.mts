import assert from 'node:assert/strict';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {createHash} from 'node:crypto';
import {readFile, mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {loadInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {readInstalledHostEnvironment, assertInstalledEnvironmentPublicationOriginal} from './installed-funded-environment.mjs';
import {installModelProviders} from './installed-model.mjs';
import {createInstalledLoaderParent} from './fixtures/installed-loader-parent.fixture.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

type Runtime = Parameters<typeof installModelProviders>[0] & Parameters<typeof loadInstalledProjectModelTasks>[0] &
  NonNullable<Parameters<typeof loadInstalledProjectConfiguration>[0]> &
  Parameters<typeof readInstalledHostEnvironment>[1] &
  Parameters<typeof createInstalledLoaderParent>[0]['moon'];
type InstrumentedRuntime = {-readonly [Name in keyof Runtime]: Runtime[Name]};
type Counters = {read: number; normalize: number; defaults: number; reserve: number;
  sends: number; wire: number; final: number};
type FixtureOptions = {count?: number; small?: boolean; observeCounters?: (counters: Counters) => void};

assert.ok(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME,
  'Select the actual matching Common runtime; this case may not skip');
const native = await import(pathToFileURL(process.env.ACTQL_TEST_PUBLIC_MODEL_TASK_RUNTIME).href);
const canonical = (value: unknown): string => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical((value as Record<string, unknown>)[key])).join(',') + '}'
    : JSON.stringify(value);
const original = (value: unknown) => {
  const wire = canonical(value);
  return {wire, cid: 'sha256:' + createHash('sha256').update(wire).digest('hex')};
};
const providerId = 'models/project-fixture';
const limits = Object.freeze({maxBytes: 65536, maxNodes: 4096, maxDepth: 64,
  maxMembers: 256, contractNodes: 4096, contractDepth: 64,
  contractTextBytes: 65536, maxWork: 2097152});
const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const numeric = JSON.parse(await readFile(new URL('../../spec/contracts/actql-numeric-reduction.json', import.meta.url), 'utf8'));
const graph = JSON.parse(await readFile(new URL('../../spec/dependencies/actql-graph-laws.json', import.meta.url), 'utf8'));

async function fixture(t: TestContext, {count = 129, small = false, observeCounters}: FixtureOptions = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-funded-model-registry-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const counters = {read: 0, normalize: 0, defaults: 0, reserve: 0, sends: 0, wire: 0, final: 0};
  observeCounters?.(counters);
  let current = true;
  const assertCurrent = () => {if (!current) throw Object.assign(new Error('OriginalProjectLost'), {code: 'OriginalProjectLost'});};
  const moon = {...native} as InstrumentedRuntime & Record<string, (...args: unknown[]) => unknown>;
  for (const [method, counter] of [['ReadPublicModelTask', 'read'],
    ['NormalizeProjectModelTask', 'normalize'], ['ReadInstalledModelDefaults', 'defaults'],
    ['ReadCheckEnvironmentWire', 'wire'], ['CheckEnvironmentModelFromWireWithGraphProfile', 'final']] as const) {
    moon['clientProgram' + method] = (...args: unknown[]) => {
      assert.ok(counters.reserve > 0, 'The actual parent must reserve before any constructor');
      counters[counter]++;
      return native['clientProgram' + method](...args);
    };
  }
  moon.clientProgramReserveInstalledSourceConstruction = (...args: unknown[]) => {
    counters.reserve++;
    return native.clientProgramReserveInstalledSourceConstruction(...args);
  };
  if (small) moon.clientLocalPreparationResourceLimits = policy =>
    native.clientLocalPreparationResourceLimits(policy, 2000000n, 2000000n);
  const parent = createInstalledLoaderParent({root: join(directory, '.state'), moon, assertCurrent});
  t.after(() => parent.close());
  parent.open();
  const tasks: Record<string, string> = {};
  for (let index = 0; index < count; index++) {
    const name = `model-task:funded.${String(index).padStart(3, '0')}`;
    tasks[name] = `./task-${index}.yaml`;
    await writeFile(join(directory, `task-${index}.yaml`),
      `task: ${name}\ninput:\n  notes: string\noutput:\n  enabled: boolean\ninstructions: Original é ${index}\nlimits:\n  max_output_tokens: 200\n`);
  }
  await writeFile(join(directory, 'actql.config.json'), '{"version":"actql-config/0.1","model_tasks":"./tasks.json"}');
  await writeFile(join(directory, 'tasks.json'), canonical({version: 'actql-model-tasks/0.1', tasks,
    providers: {[providerId]: {type: 'fixture'}}, default_provider: providerId}));
  const project = (await loadInstalledProjectConfiguration(moon, {directory}))!;
  const binding = providerBindingOriginals(providerId);
  const handling = original({schema: 'actql.contract/0.1', id: 'funded-project-policy',
    version: 'fixture-r1', kind: 'request_data_handling', body: {
      accepted_classifications: ['public'], allowed_regions: ['fixture'], retention: 'none', training_use: 'forbidden'}});
  binding.configurationContract = original({...JSON.parse(binding.configurationContract.wire),
    required: ['endpoint', 'principal', 'selector', 'tenant', 'model_defaults']});
  binding.configuration = original({...JSON.parse(binding.configuration.wire), model_defaults: {
    default_model: 'first', models: [{model: 'first', data_handling: {...JSON.parse(handling.wire), cid: handling.cid},
      generation_config: {temperature: 0, top_p: 1, max_output_tokens: 100}}]}});
  const providers = installModelProviders(moon, () => [{providerId, bindingOriginals: binding,
    validatePrompt: () => true, invoke() {counters.sends++; assert.fail('No registration-time Model invocation');}}],
  assertCurrent, assertCurrent);
  return {moon, parent, project, providers, counters, assertCurrent,
    loseCurrent: () => {current = false;},
    load: (selected: typeof limits & {maxTasks?: number} = limits) => loadInstalledProjectModelTasks(moon, project, providers,
      {limits: selected, assertCurrent, installationServices: parent.services})};
}

test('actual same-parent loader registers 129 original Tasks once and funds complete nonempty final admission', async t => {
  const f = await fixture(t), view = await f.load();
  const tasks = view.originalsForRuntime(f.moon);
  assert.equal(tasks.length, 129);
  assert.equal(new Set(tasks.map(task => task.taskCid)).size, 129);
  for (const task of tasks) {
    assert.equal(JSON.parse(task.taskWire).task_id, task.name);
    assert.equal(JSON.parse(task.taskWire).generation_config.max_output_tokens, 200);
    assert.match(JSON.parse(task.promptWire).payload.instructions, /^Original é /u);
  }
  const projection = view.projectEnvironmentForRuntime(f.moon, baseWire,
    JSON.parse(baseWire).evidence_bundle_cid, JSON.parse(baseWire));
  const final = readInstalledHostEnvironment(f.parent.services!, f.moon, projection.environmentWire,
    {textTime: false, calendar: false, numericProfileCid: original(numeric).cid, graphLawCid: original(graph).cid});
  assert.ok(final.admitted && final.raw);
  assert.equal((final.body!.model_task_contracts as readonly unknown[]).length, 129);
  assert.equal(native.clientProgramCheckEnvironmentFromWireConstructionCapacity(final.raw), undefined,
    'An empty-only construction recipe must refuse this populated original');
  assert.equal(native.clientProgramCheckEnvironmentFromWireWithGraphProfile(final.raw,
    false, true, true, true, true, false, false, original(numeric).cid, original(graph).cid), undefined);
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(f.parent.services!, f.moon,
    {...final}, undefined, final.wire), {code: 'ForeignInstalledEnvironmentOriginal'});
  const other = await fixture(t, {count: 0});
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(other.parent.services!, other.moon,
    final, undefined, final.wire), {code: 'ForeignInstalledEnvironmentOriginal'});
  assert.throws(() => readInstalledHostEnvironment({...f.parent.services!}, f.moon, final.wire,
    {textTime: false, calendar: false, numericProfileCid: original(numeric).cid, graphLawCid: original(graph).cid}),
  {code: 'ForeignInstalledHostServices'});
  assert.equal(f.counters.read, 129);
  assert.equal(f.counters.normalize, 129, 'No earlier prefix is re-normalized to quote a later member');
  assert.equal(f.counters.defaults, 1, 'The same three canonical originals and defaults profile are read once');
  assert.equal(f.counters.wire, 1);
  assert.equal(f.counters.final, 1);
  assert.equal(f.counters.sends, 0);
  f.loseCurrent();
  assert.throws(() => view.originalsForRuntime(f.moon), {code: 'OriginalProjectLost'});
});

test('actual explicit maxTasks128 refuses 129 before acquiring or decoding a Task', async t => {
  const f = await fixture(t);
  await assert.rejects(f.load({...limits, maxTasks: 128}), {code: 'InstalledProjectTaskCountLimit'});
  assert.equal(f.counters.read, 0); assert.equal(f.counters.normalize, 0);
  assert.equal(f.counters.defaults, 0); assert.equal(f.counters.sends, 0);
});

test('actual smaller original Host Resource refuses before Task construction and closes its partial parent', async t => {
  let counters: Counters | undefined;
  // This 2MB choice is insufficient for the initial Host constructor itself;
  // keep that original refusal, rather than claiming a later admitted Task.
  await assert.rejects(async () => {
    const f = await fixture(t, {count: 1, small: true, observeCounters(value) {counters = value;}});
    await f.load();
  }, {code: 'MoonBitHostFailure'});
  assert.ok(counters);
  assert.equal(counters.read, 0, 'Current Task decoder must not precede its actual parent refusal');
  assert.equal(counters.normalize, 0); assert.equal(counters.sends, 0);
});

test('actual populated constructor domain refuses an empty admitted original', async t => {
  const f = await fixture(t, {count: 0});
  const final = readInstalledHostEnvironment(f.parent.services!, f.moon, baseWire,
    {textTime: false, calendar: false, numericProfileCid: original(numeric).cid, graphLawCid: original(graph).cid});
  assert.ok(final.admitted);
  assert.equal(native.clientProgramCheckEnvironmentModelFromWireConstructionCapacity(final.raw), undefined);
  assert.equal(native.clientProgramCheckEnvironmentModelFromWireWithGraphProfile(final.raw,
    false, true, true, true, true, false, false, original(numeric).cid, original(graph).cid), undefined);
});
