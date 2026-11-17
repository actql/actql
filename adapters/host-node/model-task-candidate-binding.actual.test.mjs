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
import {installConfiguredModelProviders} from './installed-model-configuration.mjs';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

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

test('normal configuration adopts actual Common Task DATA without caller-created identities', async t => {
  const resource = await boundConstructionActualFixture(t);
  const f = await fixture(t); let data, context, callbacks = 0, invokes = 0;
  const configured = await installConfiguredModelProviders({moon, project: f.project,
    installationServices: resource.services,
    taskLimits: limits, assertCurrent: f.check, assertHostRuntime: f.check, assertNewHostRuntime: f.check,
    async register(runtime, actual) {
      assert.strictEqual(runtime, moon); context = actual; callbacks++;
      const selected = await actual.prepareTasks([{providerId, bindingOriginals: f.bindings}]);
      assert.equal(selected.tasks.length, 1); data = selected.tasks[0];
      assert.equal(data.outputSchemaCid, original({additional_properties: false,
        fields: {answer: {nullable: false, type: 'boolean'}}, nullable: false, type: 'object'}).cid);
      assert.equal(data.modelSelector, 'selected');
      assert.equal(data.promptPayloadWire,
        canonical({format: 'actql.openai_chat_prompt/0.1', instructions: 'Exact é\r\n'}));
      assert.equal(data.normalized, undefined, 'the plugin needs DATA, not an opaque Task handle');
      return [{providerId, bindingOriginals: selected.bindingOriginalsFor(providerId),
        validatePrompt: () => true, invoke() {invokes++; assert.fail('No model invocation');}}];
    }});
  const task = configured.projectTasks.originalsForRuntime(moon)[0];
  const provider = configured.providers.get(providerId);
  assert.equal(task.taskCid, data.taskCid);
  assert.equal(task.promptCid, data.promptCid);
  assert.strictEqual(task.provider, provider);
  assert.strictEqual(provider.resolveTaskDefaults(undefined, undefined, readerLimits).value, task.defaults.value);
  assert.equal(callbacks, 1); assert.equal(invokes, 0);
  assert.throws(() => context.prepareTasks([]), {code: 'InstalledModelConfigurationClosed'});
});

test('normal configuration cannot install after losing currentness across actual Task reads', async t => {
  const resource = await boundConstructionActualFixture(t);
  const f = await fixture(t); let callbacks = 0, context;
  await assert.rejects(installConfiguredModelProviders({moon, project: f.project,
    installationServices: resource.services,
    taskLimits: limits, assertCurrent: f.check, assertHostRuntime: f.check, assertNewHostRuntime: f.check,
    async register(_, actual) {
      callbacks++; context = actual;
      const selected = await actual.prepareTasks([{providerId, bindingOriginals: f.bindings}]);
      const bindingOriginals = selected.bindingOriginalsFor(providerId);
      f.loseCurrent();
      return [{providerId, bindingOriginals, validatePrompt: () => true,
        invoke() {assert.fail('No model invocation');}}];
    }}), {code: 'OriginalLost'});
  assert.equal(callbacks, 1);
  assert.throws(() => context.prepareTasks([]), {code: 'OriginalLost'});
});

test('normal configuration funded preparation rejects duplicate and accessor bindings before Task reads', async t => {
  for (const accessor of [false, true]) {
    const resource = await boundConstructionActualFixture(t), f = await fixture(t);
    let gets = 0;
    const binding = {providerId, bindingOriginals: f.bindings};
    const second = accessor ? Object.defineProperty({}, 'providerId', {
      enumerable: true, get() {gets++; return providerId;},
    }) : {...binding};
    // Invalid Task bytes cannot mask the earlier original descriptor refusal.
    await writeFile(join(f.directory, 'task.json'), 'not JSON');
    await assert.rejects(installConfiguredModelProviders({moon, project: f.project,
      installationServices: resource.services, taskLimits: limits,
      assertCurrent: f.check, assertHostRuntime: f.check, assertNewHostRuntime: f.check,
      async register(_, context) {
        await context.prepareTasks([binding, second]);
        assert.fail('No Provider registration after invalid binding');
      }}), {code: 'InvalidInstalledModelTaskPreparation'});
    assert.equal(gets, 0);
  }
});

test('normal configuration uses the real initial Resource for secret text and Task material', async t => {
  const resource = await boundConstructionActualFixture(t), f = await fixture(t);
  assert.strictEqual(resource.moon, moon, 'use the same actual Resource/runtime module');
  const originalLimits = moon.clientLocalPreparationResourceLimits(moon.clientLocalResourcePolicyOriginal());
  assert.equal(originalLimits[4], 536870912n);
  const secretPath = join(resource.root, 'model-secret.txt');
  const secret = 'synthetic-provider-secret';
  await writeFile(secretPath, secret, {mode: 0o600});
  let callbacks = 0;
  const configured = await installConfiguredModelProviders({moon, project: f.project,
    installationServices: resource.services, taskLimits: limits,
    assertCurrent: f.check, assertHostRuntime: f.check, assertNewHostRuntime: f.check,
    async register(_, context) {
      callbacks++;
      assert.equal(await context.readText(secretPath, {maxBytes: 128}), secret);
      const selected = await context.prepareTasks([{providerId, bindingOriginals: f.bindings}]);
      assert.equal(selected.tasks[0].modelSelector, 'selected');
      assert.equal(JSON.stringify(selected.tasks).includes(secret), false);
      return [{providerId, bindingOriginals: selected.bindingOriginalsFor(providerId),
        validatePrompt: () => true, invoke() {assert.fail('No Model invocation');}}];
    }});
  assert.equal(configured.projectTasks.originalsForRuntime(moon).length, 1);
  assert.equal(callbacks, 1);
  await resource.close();
  assert.equal(resource.pending(), false);
  assert.equal(resource.retire(), true);
});

test('normal configuration real parent refuses excessive read funding without fallback', async t => {
  const resource = await boundConstructionActualFixture(t);
  assert.strictEqual(resource.moon, moon);
  const secretPath = join(resource.root, 'refused-model-secret.txt');
  await writeFile(secretPath, 'synthetic', {mode: 0o600});
  let primary, callbacks = 0;
  await assert.rejects(installConfiguredModelProviders({moon,
    installationServices: resource.services, assertCurrent() {}, async register(_, context) {
      callbacks++;
      try {await context.readText(secretPath, {maxBytes: 536870912});}
      catch (cause) {primary = cause;}
      return [];
    }}), cause => cause === primary && cause.code === 'MoonBitHostFailure' && cause.cause !== undefined);
  assert.equal(callbacks, 1);
  await resource.close();
  assert.equal(resource.pending(), false);
  assert.equal(resource.retire(), true);
});

async function rawConfigurationFixture(t) {
  let store;
  // Close the actual Store before its owning scratch root/Resource fixture.
  t.after(async () => {if (store !== undefined) assert.equal(await store.close(), true);});
  const resource = await boundConstructionActualFixture(t), f = await fixture(t);
  const control = runtimeCore(moon).publicationControl;
  const originals = ['retention_contract', 'metadata_retention_policy', 'clock_contract', 'data_policy']
    .map(kind => ({kind, ...original(kind === 'data_policy'
      ? {version: 'actql-effective-data-policy/0.1', classification: 'unknown',
        source_data_policy_cids: [], source_response_policy_cids: [], unknown_provenance: true}
      : {version: 'actql-installed-local-policy/0.1',
        name: `configuration-${kind}-Exact é\r\n`})}));
  const [retention, metadata, clock, data] = originals.map(value => checked(
    moon.clientProgramAdmitEffectDependencyBody(value.kind, value.cid, value.wire, 10000, 1000, 32)));
  const selection = {retention, metadata, clock, data, profile: undefined,
    installation: {}, probability: undefined, selectedAt: '2026-11-18T00:00:00.000Z',
    availableUntil: '2026-11-19T00:00:00.000Z', deleteBy: '2026-11-20T00:00:00.000Z',
    extensionCeilingAt: '2026-11-20T00:00:00.000Z', metadataDeleteBy: '2026-11-21T00:00:00.000Z',
    selectionAvailable: () => true};
  const configured = await installConfiguredModelProviders({moon, project: f.project,
    installationServices: resource.services, taskLimits: limits,
    assertCurrent: f.check, assertHostRuntime: f.check, assertNewHostRuntime: f.check,
    async register(_, context) {
      const selected = await context.prepareTasks([{providerId, bindingOriginals: f.bindings}]);
      // Only the admitted policy bodies are exercised here. No response
      // profile, raw grant or send capability is claimed by this fixture.
      return [{providerId, entryPersistence: 'async', rawCaptureSelection: selection,
        bindingOriginals: selected.bindingOriginalsFor(providerId), validatePrompt: () => true,
        quantityCapacity: {limits: {tokens: 128n, costUnits: 0n, durationMs: 1000n},
          perAttempt: {tokens: 128n, costUnits: 0n, durationMs: 1000n}},
        physicalPreflight() {assert.fail('No Model invocation');}}];
    }});
  const authority = original({purpose: 'configuration-policy-store'}).cid;
  store = await openLocalPublicationStore({directory: join(resource.root, 'model-store'),
    storeAuthorityCid: authority, capacityBytes: 1048576, maxObjectBytes: 16384,
    maxObjects: 64, maxContractNodes: 4096, maxContractDepth: 64,
    privateEvidenceKey: Buffer.alloc(32, 7)}, control);
  return {...f, configured, resource, originals, store, authority};
}

test('normal configuration persists exact Common policy originals through the real Store', async t => {
  const f = await rawConfigurationFixture(t);
  await assert.rejects(f.store.confirmModelRawCaptureOriginals(f.originals, f.authority));
  await f.configured.persistOriginals(f.store);
  assert.equal(await f.store.confirmModelRawCaptureOriginals(f.originals, f.authority), true);
  const wrong = f.originals.map((value, index) => index === 0
    ? {...value, wire: value.wire.replace('é', 'é')} : value);
  await assert.rejects(f.store.confirmModelRawCaptureOriginals(wrong, f.authority),
    {code: 'PublicationModelRawOriginalMismatch'});
});

test('normal configuration stops policy persistence on actual current loss after a Store await', async t => {
  const f = await rawConfigurationFixture(t); let writes = 0;
  await assert.rejects(f.configured.persistOriginals({async putSemantic(wire, cid) {
    writes++;
    await f.store.putSemantic(wire, cid);
    f.loseCurrent();
  }}), {code: 'OriginalLost'});
  assert.equal(writes, 1, 'no later policy body is written after current loss');
  await assert.rejects(f.store.confirmModelRawCaptureOriginals(f.originals, f.authority));
});

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
  assert.throws(() => installed.originalsForRuntime(moon), {code: 'InferTrustedRuntimeOriginalChanged'});
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
