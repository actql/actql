import assert from 'node:assert/strict';
import test from 'node:test';
import {admitInstalledProjectConfiguration,
  installedProjectOriginalsForRuntime, loadInstalledProjectConfiguration,
  retireInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from './installed-project-connections.mjs';
import {retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';
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

test('a caller scope method cannot admit Project work without the original startup', async () => {
  let runtimeReads = 0, opens = 0, callerChecks = 0;
  const moon = new Proxy({}, {get() {runtimeReads++; assert.fail('No Common reads');}});
  const scope = {assertCurrent() {callerChecks++; return true;}};
  for (const privateInputs of [
    {initialControl: scope}, {initialControlOriginals: {}},
    {initialControl: scope, initialControlOriginals: {}},
  ]) {
    await assert.rejects(loadInstalledProjectConfiguration(moon,
      {directory: '/project', openFile() {opens++;}, ...privateInputs}),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  }
  assert.equal(runtimeReads, 0); assert.equal(opens, 0); assert.equal(callerChecks, 0);
});

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

test('project retirement cuts original lookups without rewriting escaped canonical DATA', () => {
  const f = common('./tasks.json');
  const project = admitInstalledProjectConfiguration(f.moon, ' {"original":1} ', ' {"registry":1} ');
  const original = installedProjectOriginalsForRuntime(project, f.moon);
  const getter = project.originalsForRuntime;
  assert.equal(getter(f.moon), original);
  retireInstalledProjectConfiguration(project, f.moon);
  assert.throws(() => installedProjectOriginalsForRuntime(project, f.moon),
    {code: 'InstalledProjectOriginalRetired'});
  assert.throws(() => getter(f.moon), {code: 'InstalledProjectOriginalRetired'});
  assert.throws(() => retireInstalledProjectConfiguration(project, f.moon),
    {code: 'InstalledProjectOriginalRetired'});
  assert.equal(original.configuration, f.configuration);
  assert.equal(original.modelRegistry, f.registry);
  assert.equal(original.configurationWire, ' {"original":1} ');
  assert.equal(original.modelRegistryWire, ' {"registry":1} ');
  assert.ok(Object.isFrozen(original));
  assert.equal(f.calls.length, 2, 'retirement does not readmit or reconstruct originals');
});

test('copied and foreign-runtime retirement cannot retire the original project', () => {
  const f = common(undefined), project = admitInstalledProjectConfiguration(f.moon, '{}');
  const original = project.originalsForRuntime(f.moon);
  assert.throws(() => retireInstalledProjectConfiguration({...project}, f.moon),
    {code: 'ForeignInstalledProjectOriginal'});
  assert.throws(() => retireInstalledProjectConfiguration(project, {...f.moon}),
    {code: 'ForeignInstalledProjectRuntime'});
  assert.equal(project.originalsForRuntime(f.moon), original);
  retireInstalledProjectConfiguration(project, f.moon);
});

test('failed initialization retains its project until the same child completes', async () => {
  const f = common(undefined), project = admitInstalledProjectConfiguration(f.moon, '{}');
  const original = project.originalsForRuntime(f.moon);
  let pending = true, retries = 0, retired = 0;
  const child = {status: () => ({pending}), retry() {retries++;}};
  const primary = Object.freeze(new Error('OriginalPreparationFailed'));
  const failure = retainInstalledHostRuntimeFailure({primaryFailure: primary, cleanupHandle: child}, () => {
    retireInstalledProjectConfiguration(project, f.moon); retired++;
  });
  assert.equal(failure.primaryFailure, primary);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(project.originalsForRuntime(f.moon), original);
  assert.equal(retired, 0);
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retired, 1); assert.equal(retries, 1);
  assert.throws(() => project.originalsForRuntime(f.moon), {code: 'InstalledProjectOriginalRetired'});
});

test('retired project cannot begin downstream connections acquisition', async () => {
  const f = common(undefined), project = admitInstalledProjectConfiguration(f.moon, '{}');
  retireInstalledProjectConfiguration(project, f.moon);
  let reads = 0, currentChecks = 0;
  await assert.rejects(loadInstalledProjectConnections(f.moon, project, {
    assertCurrent() {currentChecks++;}, openFile() {reads++;},
  }), {code: 'InstalledProjectOriginalRetired'});
  assert.equal(reads, 0); assert.equal(currentChecks, 0);
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

function files(entries, {readFailure, closeFailure} = {}) {
  const attempts = [], handles = [];
  const openFile = async path => {
    attempts.push(path);
    if (!Object.hasOwn(entries, path)) {
      throw Object.assign(new Error('missing original'), {code: 'ENOENT'});
    }
    const bytes = Buffer.isBuffer(entries[path]) ? entries[path] : Buffer.from(entries[path]);
    let position = 0;
    const state = {path, reads: 0, bytes: 0, closes: 0, closeFailure};
    handles.push(state);
    return {
      async read(buffer, offset, length) {
        state.reads++;
        if (readFailure) throw readFailure;
        const count = Math.min(length, bytes.length - position);
        bytes.copy(buffer, offset, position, position + count);
        position += count;
        state.bytes += count;
        return {bytesRead: count};
      },
      async close() {
        state.closes++;
        if (state.closeFailure instanceof Error) throw state.closeFailure;
        return state.closeFailure ? false : undefined;
      },
    };
  };
  return {attempts, handles, openFile};
}

function loadingCommon(selected) {
  const result = common(selected);
  result.moon.clientProjectConfigurationStateDirectory = function(original) {
    assert.strictEqual(this, result.moon);
    assert.strictEqual(original, result.configuration);
    return './state';
  };
  return result;
}

test('project discovery retains the nearest original pair once with configuration-relative paths', async () => {
  const fixture = loadingCommon('./models/tasks.json');
  const configWire = ' {"original":"e\u0301😀"}\n', registryWire = ' {"tasks":"original"} ';
  const source = files({'/project/actql.config.json': configWire,
    '/project/models/tasks.json': registryWire});
  const project = await loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project/child', openFile: source.openFile});
  assert.equal(project.configurationPath, '/project/actql.config.json');
  assert.equal(project.directory, '/project');
  assert.equal(project.registryPath, '/project/models/tasks.json');
  assert.equal(project.stateDirectory, '/project/state');
  const original = project.originalsForRuntime(fixture.moon);
  assert.strictEqual(original.configuration, fixture.configuration);
  assert.strictEqual(original.modelRegistry, fixture.registry);
  assert.equal(original.configurationWire, configWire);
  assert.equal(original.modelRegistryWire, registryWire);
  assert.deepEqual(fixture.calls, [['configuration', configWire], ['registry', registryWire]]);
  assert.deepEqual(source.attempts, ['/project/child/actql.config.json',
    '/project/actql.config.json', '/project/models/tasks.json']);
  assert.deepEqual(source.handles.map(handle => handle.closes), [1, 1]);
  assert(Object.isFrozen(project));
  assert.throws(() => project.originalsForRuntime({...fixture.moon}),
    {code: 'ForeignInstalledProjectRuntime'});
});

test('discovered project and its captured getter share the same retirement record', async () => {
  const f = loadingCommon('./tasks.json');
  const source = files({'/project/actql.config.json': '{}', '/project/tasks.json': '{}'});
  const project = await loadInstalledProjectConfiguration(f.moon,
    {directory: '/project', openFile: source.openFile});
  const getter = project.originalsForRuntime;
  assert.equal(getter(f.moon), installedProjectOriginalsForRuntime(project, f.moon));
  retireInstalledProjectConfiguration(project, f.moon);
  assert.throws(() => getter(f.moon), {code: 'InstalledProjectOriginalRetired'});
  assert.throws(() => project.originalsForRuntime(f.moon), {code: 'InstalledProjectOriginalRetired'});
  assert.deepEqual(source.handles.map(handle => handle.closes), [1, 1]);
  assert.equal(source.attempts.length, 2, 'managed retirement does not reopen or close a file again');
});

test('project discovery reaches root only through acknowledged missing opens', async () => {
  const fixture = loadingCommon(undefined), source = files({});
  assert.equal(await loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/one/two', openFile: source.openFile}), undefined);
  assert.deepEqual(source.attempts, ['/one/two/actql.config.json',
    '/one/actql.config.json', '/actql.config.json']);
  assert.deepEqual(source.handles, []);
  assert.deepEqual(fixture.calls, []);
});

test('project discovery does not fall back after the nearer Common rejection', async () => {
  const fixture = loadingCommon('./unread.json');
  const issue = Object.freeze({fixture: 'original refusal'});
  fixture.moon.clientProjectConfigurationAdmit = () => runtimeFailure(issue);
  const source = files({'/project/child/actql.config.json': 'bad',
    '/project/actql.config.json': '{}'});
  await assert.rejects(loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project/child', openFile: source.openFile}),
  error => error.code === 'MoonBitHostFailure' && error.cause === issue);
  assert.deepEqual(source.attempts, ['/project/child/actql.config.json']);
  assert.equal(source.handles[0].closes, 1);
});

test('invalid original UTF-8 refuses before Common and never becomes replacement text', async () => {
  for (const bytes of [Buffer.from([0xc3, 0x28]), Buffer.from([0xed, 0xa0, 0x80]),
    Buffer.from([0xf0, 0x9f, 0x98])]) {
    const fixture = loadingCommon(undefined);
    const source = files({'/project/actql.config.json': bytes});
    await assert.rejects(loadInstalledProjectConfiguration(fixture.moon,
      {directory: '/project', openFile: source.openFile}), {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
    assert.deepEqual(fixture.calls, []);
    assert.deepEqual(source.attempts, ['/project/actql.config.json']);
    assert.equal(source.handles[0].closes, 1);
  }
});

test('original BOM is not stripped before the Common reader decides admission', async () => {
  const fixture = loadingCommon(undefined), wire = '\ufeff{}';
  const source = files({'/project/actql.config.json': wire});
  const project = await loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project', openFile: source.openFile});
  assert.equal(project.originalsForRuntime(fixture.moon).configurationWire, wire);
  assert.deepEqual(fixture.calls, [['configuration', wire]]);
});

test('project acquisition enforces exact 65536 bytes plus only one lookahead', async () => {
  for (const count of [65536, 65537, 100000]) {
    const fixture = loadingCommon(undefined);
    const source = files({'/project/actql.config.json': ' '.repeat(count)});
    const loading = loadInstalledProjectConfiguration(fixture.moon,
      {directory: '/project', openFile: source.openFile});
    if (count === 65536) {
      const project = await loading;
      assert.equal(project.originalsForRuntime(fixture.moon).configurationWire.length, count);
    } else {
      await assert.rejects(loading, {message: 'InvalidInstalledSourceProfile'});
      assert.deepEqual(fixture.calls, []);
    }
    assert.equal(source.handles[0].bytes, Math.min(count, 65537));
    assert.equal(source.handles[0].closes, 1);
  }
});

test('ENOENT after a successful open is not missing-project permission to continue', async () => {
  for (const phase of ['read', 'close']) {
    const fixture = loadingCommon(undefined);
    const original = Object.assign(new Error('original failure'), {code: 'ENOENT'});
    const source = files({'/project/actql.config.json': '{}'},
      phase === 'read' ? {readFailure: original} : {closeFailure: original});
    let failure;
    await assert.rejects(loadInstalledProjectConfiguration(fixture.moon,
      {directory: '/project', openFile: source.openFile}), error => {
      failure = error;
      assert.strictEqual(error, original);
      return true;
    });
    assert.deepEqual(source.attempts, ['/project/actql.config.json']);
    assert.deepEqual(fixture.calls, []);
    if (phase === 'close') {
      assert.equal(failure.cleanupPending, true);
      source.handles[0].closeFailure = false;
      await failure.cleanupHandle.retry();
      assert.equal(failure.cleanupPending, false);
    }
  }
});

test('project close pending retains the same FD and retries without reread or admission', async () => {
  const fixture = loadingCommon(undefined);
  const source = files({'/project/actql.config.json': '{}'}, {closeFailure: true});
  let failure;
  await assert.rejects(loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project', openFile: source.openFile}), error => {
    failure = error;
    assert.equal(error.cleanupPending, true);
    return true;
  });
  const reads = source.handles[0].reads;
  source.handles[0].closeFailure = false;
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupPending, false);
  assert.equal(source.handles[0].reads, reads);
  assert.equal(source.handles[0].closes, 2);
  assert.deepEqual(fixture.calls, []);
});

test('selected registry missing or malformed bytes cannot become an absent original', async () => {
  for (const registry of [undefined, Buffer.from([0xff])]) {
    const fixture = loadingCommon('../selected.json');
    const source = files({'/project/actql.config.json': '{}',
      ...(registry === undefined ? {} : {'/selected.json': registry})});
    await assert.rejects(loadInstalledProjectConfiguration(fixture.moon,
      {directory: '/project', openFile: source.openFile}),
    {code: registry === undefined ? 'ENOENT' : 'ERR_ENCODING_INVALID_ENCODED_DATA'});
    assert.deepEqual(source.attempts, ['/project/actql.config.json', '/selected.json']);
    assert.deepEqual(fixture.calls, [['configuration', '{}']]);
    assert(source.handles.every(handle => handle.closes === 1));
  }
});

test('missing runtime or invalid location refuses project discovery before file acquisition', async () => {
  const source = files({});
  for (const moon of [undefined, null, {}, common(undefined).moon]) {
    await assert.rejects(loadInstalledProjectConfiguration(moon,
      {directory: '/project', openFile: source.openFile}),
    {code: 'InstalledProjectRuntimeUnavailable'});
  }
  const {moon} = loadingCommon(undefined);
  for (const directory of [null, false, '', {}, 1]) {
    await assert.rejects(loadInstalledProjectConfiguration(moon,
      {directory, openFile: source.openFile}), {code: 'InvalidInstalledProjectLocation'});
  }
  assert.deepEqual(source.attempts, []);
});

test('project reader callbacks keep their original receiver across acquisition awaits', async () => {
  const fixture = loadingCommon('./tasks.json');
  const names = ['clientProjectConfigurationAdmit',
    'clientProjectConfigurationModelTasksFile', 'clientProjectModelRegistryAdmit',
    'clientProjectConfigurationStateDirectory'];
  const gets = Object.fromEntries(names.map(name => [name, 0]));
  for (const name of names) {
    const original = fixture.moon[name];
    Object.defineProperty(fixture.moon, name, {get() {
      assert.equal(++gets[name], 1, `${name} must be captured only once`);
      return original;
    }});
  }
  const source = files({'/project/actql.config.json': '{}', '/project/tasks.json': '{}'});
  const project = await loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project', openFile: source.openFile});
  assert.strictEqual(project.originalsForRuntime(fixture.moon).modelRegistry, fixture.registry);
  assert.deepEqual(Object.values(gets), [1, 1, 1, 1]);
});

test('pending original project read is not close completion or an admitted pair', async () => {
  const fixture = loadingCommon(undefined);
  let completeRead, enteredRead;
  const reading = new Promise(resolve => {enteredRead = resolve;});
  const released = new Promise(resolve => {completeRead = resolve;});
  let reads = 0, closes = 0, settled = false;
  const loading = loadInstalledProjectConfiguration(fixture.moon,
    {directory: '/project', openFile: async () => ({
      async read(buffer, offset) {
        if (++reads !== 1) return {bytesRead: 0};
        enteredRead();
        await released;
        buffer.write('{}', offset);
        return {bytesRead: 2};
      },
      async close() {closes++;},
    })});
  loading.then(() => {settled = true;});
  await reading;
  assert.equal(settled, false);
  assert.equal(closes, 0);
  assert.deepEqual(fixture.calls, []);
  completeRead();
  const project = await loading;
  assert.equal(closes, 1);
  assert.equal(project.originalsForRuntime(fixture.moon).configurationWire, '{}');
});
