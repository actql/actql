import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join} from 'node:path';
import test from 'node:test';
import {prepareNativeHttpCompilerScope} from './native-http-compiler-scope.mjs';
import * as httpScope from './native-http-compiler-scope.mjs';
import {parse as parseYaml} from 'yaml';
import {parse} from 'acorn';
import {nativeCoreHostedPartitions, nativeCoreLinuxCommonArguments} from './ci-core-partitions.mjs';
import {executeNativeCoreSourceRelease, nativeCoreSourceCompilerEnvironment,
  nativeCoreSourceReleaseSelection, runNativeCoreSourceRelease} from './native-core-source-release.mjs';

const groups = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

const sourcePackage = 'src/platform_native/remote_resident_source_compute_tests';
const sourceInventory = () => ({runnableCases: 2, records: [0, 1].map(index => ({
  directory: sourcePackage, source: sourcePackage + '/original_wbtest.mbt', benchmark: false,
  entry: [JSON.stringify(['actql/actql/platform_native/remote_resident_source_compute_tests', 'whitebox']),
    'original_wbtest.mbt', {index, name: 'original ' + index, attrs: []}],
}))});

test('Linux Source release retains the actual complete compiler count and refuses changed execution classes', () => {
  const inventory = sourceInventory(), selected = nativeCoreSourceReleaseSelection(inventory);
  assert.equal(selected.cases, inventory.records.length);
  assert.equal(selected.args.at(-1), sourcePackage);
  for (const flag of ['--deny-warn', '--release', '--strip', '--no-parallelize', '--verbose'])
    assert(selected.args.includes(flag));
  assert(!selected.args.some(value => ['--filter', '--index', '--doc-index'].includes(value)));
  for (const mutate of [value => { value.records = []; value.runnableCases = 0; },
    value => { value.runnableCases++; }, value => { value.records.push(value.records[0]); value.runnableCases++; },
    value => { value.records[0].benchmark = true; }, value => { value.records[0].entry[2].attrs = ['skip']; },
    value => { value.records[0].directory = 'src/other'; },
    value => { value.records[0].entry[1] = '../other.mbt'; },
    value => { value.records[0].entry[0] = JSON.stringify(['foreign', 'whitebox']); },
    value => { value.records[1].entry[2].index = value.records[0].entry[2].index; }]) {
    const changed = structuredClone(inventory); mutate(changed);
    assert.throws(() => nativeCoreSourceReleaseSelection(changed));
  }
});

test('Linux Source release compiler is confined to the matching Native child', () => {
  const env = {ORIGINAL: 'retained', PATH: '/original/compiler/bin',
    ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json'};
  const args = [...nativeCoreLinuxCommonArguments, sourcePackage];
  let calls = 0;
  const compiler = (root, scratch, original) => {
    assert.equal(root, '/repository'); assert.equal(scratch, '/fresh/source'); assert.equal(original, env);
    calls++; return {PATH: '/fresh/test-c-compiler' + delimiter + original.PATH};
  };
  const selected = nativeCoreSourceCompilerEnvironment(args, '/repository', '/fresh/source', env,
    {platform: 'linux', compiler});
  assert.equal(calls, 1); assert.equal(selected.PATH, '/fresh/test-c-compiler' + delimiter + env.PATH);
  assert.equal(selected.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION, env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION);
  assert.equal(env.MOON_CC, undefined);
  assert.equal(env.PATH, '/original/compiler/bin');
  for (const [platform, original] of [['darwin', args], ['linux', [sourcePackage]]])
    assert.equal(nativeCoreSourceCompilerEnvironment(original, '/repository', '/fresh/source', env,
      {platform, compiler}), env);
  assert.equal(calls, 1);
  assert.throws(() => nativeCoreSourceCompilerEnvironment([...args, '--filter', 'other'],
    '/repository', '/fresh/source', env, {platform: 'linux', compiler}));
  assert.equal(calls, 1);
});

test('Linux Source release verifies original preparation before a fresh counted fixture and confirms cleanup only after join', async () => {
  const original = {revision: 'a'.repeat(40), dirty: false}, events = [], reports = [];
  const env = {RUNNER_TEMP: '/original/tmp', ORIGINAL: 'same',
    ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json'};
  const run = overrides => executeNativeCoreSourceRelease({root: process.cwd(), env,
    platform: 'linux', arch: 'x64', source: () => original,
    verifyPreparation: (root, receipt, options) => {
      assert.equal(root, realpathSync(process.cwd())); assert.equal(receipt, env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION);
      assert.equal(options.env, env); events.push('verified');
    }, scratch: async options => {
      assert.deepEqual(events, ['verified']); assert.equal(options.parent, '/original/tmp/native-source-release');
      events.push('fresh');
      return {path: '/fresh/source', passed: () => events.push('passed'), close: () => events.push('closed')};
    }, discover: (root, args, options) => {
      assert.deepEqual(events, ['verified', 'fresh']); assert.equal(options.env, env);
      assert(args.includes('--release') && args.at(-1) === sourcePackage);
      events.push('discovered'); return sourceInventory();
    }, execute: (command, args, options) => {
      assert.deepEqual(events, ['verified', 'fresh', 'discovered']); assert.equal(command, process.execPath);
      assert.deepEqual(args, ['scripts/test-native-http-client.mjs']);
      assert.equal(options.env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION, env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION);
      assert.equal(options.env.ACTQL_TEST_SCRATCH_ROOT, '/fresh/source');
      assert.equal(options.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'core-source');
      assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_SOURCE_COUNT, '2');
      assert.equal(options.env.MOON_CC, undefined, 'The portable verifier must see its original compiler environment');
      const selected = JSON.parse(options.env.ACTQL_TEST_NATIVE_CORE_SOURCE_ARGS);
      assert(selected.includes('--release') && selected.at(-1) === sourcePackage);
      events.push('joined'); return {status: 0, signal: null};
    }, report: value => reports.push(value), ...overrides});
  assert.equal(await run(), 0);
  assert.deepEqual(events, ['verified', 'fresh', 'discovered', 'joined', 'passed', 'closed']);
  assert.equal(reports.filter(value => value.startsWith('ACTQL_NATIVE_SOURCE_RELEASE_EXECUTION ')).length, 1);
  for (const result of [{status: 7, signal: null}, {status: null, signal: 'SIGTERM'},
    {error: new Error('original fixture failure'), status: null, signal: null}]) {
    events.length = reports.length = 0;
    const execute = () => { events.push('joined'); return result; };
    if (result.error || result.signal) await assert.rejects(run({execute}), result.error ? error => error === result.error : /signal/);
    else assert.equal(await run({execute}), 7);
    assert(!events.includes('passed') && !events.includes('closed'));
    assert(!reports.some(value => value.startsWith('ACTQL_NATIVE_SOURCE_RELEASE_EXECUTION ')));
  }
  events.length = reports.length = 0;
  const primary = new Error('foreign preparation');
  await assert.rejects(run({verifyPreparation: () => { throw primary; }}), error => error === primary);
  assert.deepEqual(events, []);
});

test('Linux Source release uses one bounded existing owner and preserves the original debug fixture', async () => {
  const workflow = parseYaml(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['native-http'];
  const original = job.steps.find(step => step.id === 'native-http');
  const release = job.steps.find(step => step.run?.includes('node scripts/native-core-source-release.mjs'));
  const preparation = job.steps.filter(step => step.run?.includes('prepareNativeResidentPortableRuntime('));
  assert.equal(job['runs-on'], 'ubuntu-24.04'); assert.equal(preparation.length, 1);
  assert(original.run.includes('node scripts/test-native-http-client.mjs'));
  assert.equal(original.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, undefined, 'Original complete debug fixture remains selected');
  assert.equal(original.env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION,
    release.env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION);
  assert(job.steps.indexOf(preparation[0]) < job.steps.indexOf(original) && job.steps.indexOf(original) < job.steps.indexOf(release));
  assert.equal(release.if, undefined, 'A failed original prerequisite cannot run the new proof');
  assert(!release['continue-on-error']);
  let calls = 0;
  const env = {ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json'};
  assert.equal(await runNativeCoreSourceRelease({env, platform: 'linux', arch: 'x64', execute: async config => {
    calls++; assert(config.heavy); assert(config.timeoutSeconds > 0 && config.graceSeconds > 0);
    assert(config.timeoutSeconds + config.graceSeconds < release['timeout-minutes'] * 60);
    assert.equal(config.steps.length, 1);
    assert.equal(config.steps[0].env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION, env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION);
    return 9;
  }}), 9);
  assert.equal(calls, 1);
  for (const options of [{platform: 'darwin', arch: 'arm64', env}, {platform: 'linux', arch: 'arm64', env},
    {platform: 'linux', arch: 'x64', env: {}},
    ...['MOON_CC', 'CC', 'CXX'].map(name => ({platform: 'linux', arch: 'x64', env: {...env, [name]: '/foreign/compiler'}}))])
    await assert.rejects(runNativeCoreSourceRelease({...options, execute: () => { throw new Error('must not execute'); }}));
});

test('Linux Source release keeps changed-source and invalid-discovery duties unconfirmed', async () => {
  const original = {revision: 'a'.repeat(40), dirty: false};
  for (const failure of ['changed-source', 'empty-inventory']) {
    let reads = 0, executed = 0, passed = 0, closed = 0;
    const reports = [];
    await assert.rejects(executeNativeCoreSourceRelease({root: process.cwd(),
      env: {ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json'},
      platform: 'linux', arch: 'x64',
      source: () => ++reads === 1 ? original : {...original, dirty: true},
      verifyPreparation: () => {},
      scratch: async () => ({path: '/fresh/source', passed: () => passed++, close: () => closed++}),
      discover: () => failure === 'empty-inventory' ? {records: [], runnableCases: 0} : sourceInventory(),
      execute: () => { executed++; return {status: 0, signal: null}; },
      report: value => reports.push(value),
    }), failure === 'changed-source' ? /Source changed/ : /nonempty/);
    assert.equal(executed, failure === 'empty-inventory' ? 0 : 1);
    assert.equal(passed, 0); assert.equal(closed, 0);
    assert(!reports.some(value => value.startsWith('ACTQL_NATIVE_SOURCE_RELEASE_EXECUTION ')));
  }
});

test('Source coverage defaults to complete and only the closed Darwin package owner can redistribute it', () => {
  assert.equal(typeof httpScope.nativeHttpSourceCoverage, 'function');
  for (const platform of ['linux', 'darwin'])
    for (const focus of [undefined, 'http-packages', 'http-controls', 'core-source'])
      assert.deepEqual(httpScope.nativeHttpSourceCoverage(focus, {platform, owner: undefined}),
        {includeSource: true, effectTargets: {reads: 3, writes: 1}});
  const owner = 'linux-http+darwin-core-source';
  assert.deepEqual(httpScope.nativeHttpSourceCoverage('http-packages', {platform: 'darwin', owner}),
    {includeSource: false, effectTargets: {reads: 0, writes: 0}});
  for (const options of [{platform: 'linux', owner}, {platform: 'darwin', owner: ''},
    {platform: 'darwin', owner: 'other'}, {platform: 'darwin', owner: null}])
    assert.throws(() => httpScope.nativeHttpSourceCoverage('http-packages', options));
  for (const focus of [undefined, 'http-controls', 'core-source', 'core-http'])
    assert.throws(() => httpScope.nativeHttpSourceCoverage(focus, {platform: 'darwin', owner}));
});

test('Source coverage redistribution requires current Linux HTTP and complete Darwin Core outcomes', () => {
  const workflow = parseYaml(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const gate = workflow.jobs['native-http-macos'];
  assert.deepEqual(gate.needs, ['select-targets', 'native-macos-workloads', 'native-http', 'core']);
  assert.equal(gate['runs-on'], 'ubuntu-24.04');
  const step = gate.steps[0];
  assert.equal(step.env.LINUX_HTTP_RESULT, '${{ needs.native-http.result }}');
  assert.equal(step.env.DARWIN_CORE_RESULT, '${{ needs.core.result }}');
  assert.equal(step.env.CORE_TARGETS, '${{ needs.select-targets.outputs.targets }}');
  const selected = groups['native-macos'].flatMap(group => group.steps).filter(step => step.env?.ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER);
  assert.equal(selected.length, 1); assert.equal(selected[0].id, 'native-http');
  assert.equal(selected[0].env.ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER, 'linux-http+darwin-core-source');
  const keys = ['WORKLOAD_RESULT', 'HTTP_RESULT', 'LINUX_HTTP_RESULT', 'DARWIN_CORE_RESULT'];
  const success = {...Object.fromEntries(keys.map(key => [key, 'success'])), CORE_TARGETS: '["js","wasm","native"]'};
  const run = env => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    encoding: 'utf8', timeout: 5000, env: {...process.env, ...env},
  });
  assert.equal(run(success).status, 0);
  for (const key of keys) for (const value of ['failure', 'cancelled', 'skipped', '']) {
    const result = run({...success, [key]: value});
    assert.equal(result.error, undefined); assert.equal(result.signal, null);
    assert.notEqual(result.status, 0, `${key}=${value || 'missing'} cannot certify coverage`);
  }
  for (const value of ['', '[]', '["js","wasm"]', 'null', 'invalid'])
    assert.notEqual(run({...success, CORE_TARGETS: value}).status, 0);
  const darwin = workflow.jobs['core-darwin'];
  assert(darwin.strategy.matrix.target.includes('native'));
  const hosted = darwin.strategy.matrix.partition.filter(partition =>
    !(darwin.strategy.matrix.exclude ?? []).some(row => row.target === 'native' && row.partition === partition));
  const profiles = hosted.flatMap(nativeCoreHostedPartitions);
  assert.deepEqual(profiles.sort(), ['1/2', '2/2', 'source', 'scoped-runtime', 'scoped-review'].sort(),
    'Current hosted jobs must execute every original logical profile exactly once');
  const core = workflow.jobs['core-darwin'].steps.find(step => step.name === 'Test common core');
  assert(core.run.includes('MOONBIT_NEW_NATIVE=0 node scripts/test-native-core.mjs --deny-warn --release --strip -j 2 --no-parallelize --verbose'));
  const linux = workflow.jobs['native-http'];
  assert.equal(linux['runs-on'], 'ubuntu-24.04');
  assert(linux.steps.some(step => step.run?.includes('node scripts/test-native-http-client.mjs')));
});

test('Source coverage caller omits only the repeated complete package and keeps independent exact physical oracles', () => {
  const source = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const found = [];
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'ForOfStatement' && node.left.declarations?.[0]?.id.name === 'packagePath') found.push(node);
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) for (const value of child) walk(value);
      else if (child && typeof child === 'object') walk(child);
    }
  }
  walk(tree); assert.equal(found.length, 1);
  const loop = found[0];
  assert.equal(loop.right.alternate.elements.length, 15);
  const skip = loop.body.body[0];
  assert.equal(skip.type, 'IfStatement'); assert.equal(skip.consequent.type, 'ContinueStatement');
  assert.equal(source.slice(skip.test.start, skip.test.end),
    "packagePath === 'src/platform_native/remote_resident_source_compute_tests' && !sourceCoverage.includeSource");
  assert(source.includes('assert.deepEqual(bearerServers.effectTargets(), sourceCoverage.effectTargets)'));
  assert(source.includes('sourceCoverage.includeSource ? [{Id: \'001000000000001AAA\', Count__c: 3}] : []'));
  assert(source.includes('assert.deepEqual(bearerServers.effectTargets(), {reads: 3, writes: 1})'),
    'The complete original Core Source fixture keeps its independent 3/1 oracle');
});

test('macOS HTTP packages and original CLI controls use the existing two workers', () => {
  const mac = groups['native-macos'];
  assert.equal(mac.length, 2);
  const packages = mac.flatMap(group => group.steps).find(step => step.id === 'native-http');
  const controls = mac.flatMap(group => group.steps).find(step => step.id === 'native-http-controls');
  assert(packages && controls);
  assert.equal(packages.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-packages');
  assert.equal(controls.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-controls');
  assert(mac.find(group => group.steps.includes(packages)) !== mac.find(group => group.steps.includes(controls)));
  assert.notEqual(packages.env.ACTQL_TEST_SCRATCH_ROOT, controls.env.ACTQL_TEST_SCRATCH_ROOT);
  assert.equal(packages.run, controls.run);
  assert.equal(packages.timeoutMinutes, controls.timeoutMinutes);
});

test('the original complete HTTP path remains and both closed phases retain its original cleanup', () => {
  const source = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(source.includes("'http-packages', 'http-controls'"));
  assert(source.includes("focus === 'http-controls' ? []"));
  assert(source.includes("if (focus === 'http-packages') break verification;"));
  assert(source.includes('prepareNativeHttpCompilerScope'));
  assert(source.includes('await standardGateway.close()'));
  assert(source.includes('await effectCheckpointServer?.close()'));
});

test('HTTP phase compiler keeps original Native argv and environment in disjoint actual child roots', t => {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'actql-http-phase-')));
  t.after(() => rmSync(parent, {recursive: true, force: true}));
  const scopes = [];
  const env = {MOON_HOME: '/original/installed/tool',
    ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json',
    ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: '/original/native'};
  for (const phase of ['packages', 'controls']) {
    const root = join(parent, phase); mkdirSync(root);
    const scope = prepareNativeHttpCompilerScope(process.cwd(), root, {env,
      platform: 'darwin', arch: 'arm64', copyTools: (original, target, marker) => {
        assert.equal(original, env.MOON_HOME); assert.equal(JSON.parse(marker).platform, 'darwin-arm64');
        mkdirSync(join(target, 'bin'), {recursive: true});
        writeFileSync(join(target, 'bin/moon'), '#!' + process.execPath + '\n' +
          'console.log(JSON.stringify({args:process.argv.slice(2),home:process.env.MOON_HOME,path:process.env.PATH,original:process.env.ORIGINAL_MARKER}));' +
          'process.exitCode=Number(process.env.HTTP_FIXTURE_EXIT??0);\n', {mode: 0o700});
      }});
    scopes.push(scope);
    const args = ['test', 'src/original', '--target', 'native', '--build-only'];
    const childEnv = {...process.env, ORIGINAL_MARKER: 'same environment'};
    const value = JSON.parse(execFileSync(scope.moon, args, {env: childEnv, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(value.args, [...args, '--target-dir', scope.targetDirectory]);
    assert.equal(value.home, join(root, 'compiler-tool'));
    assert(value.path.startsWith(join(root, 'compiler-bin') + delimiter + value.home + '/bin' + delimiter));
    assert.equal(value.original, childEnv.ORIGINAL_MARKER);
    const reused = JSON.parse(execFileSync(scope.moon, [...args, '--target-dir', scope.targetDirectory],
      {env: childEnv, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(reused.args, value.args);
    const nested = JSON.parse(execFileSync('moon', args, {
      env: {...childEnv, ...scope.environment}, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(nested.args, value.args, 'Nested original test wrappers must keep the same private target');
    const failed = spawnSync(scope.moon, args, {env: {...childEnv, HTTP_FIXTURE_EXIT: '17'}, encoding: 'utf8', timeout: 5000});
    assert.equal(failed.status, 17);
    const foreign = spawnSync(scope.moon, [...args, '--target-dir', join(parent, 'foreign')],
      {env: childEnv, encoding: 'utf8', timeout: 5000});
    assert.notEqual(foreign.status, 0); assert.equal(foreign.stdout, '');
  }
  assert.notEqual(scopes[0].targetDirectory, scopes[1].targetDirectory);
  assert.notEqual(scopes[0].moon, scopes[1].moon);
  assert.equal(env.MOON_HOME, '/original/installed/tool');
});

test('HTTP phase compiler refuses unsupported hosts and missing completed preparation before copying tools', () => {
  let copied = false;
  for (const options of [{platform: 'linux', arch: 'x64', env: {}},
    {platform: 'darwin', arch: 'arm64', env: {MOON_HOME: '/original'}}]) {
    assert.throws(() => prepareNativeHttpCompilerScope(process.cwd(), process.cwd(), {
      ...options, copyTools() { copied = true; }}));
  }
  assert.equal(copied, false);
});
