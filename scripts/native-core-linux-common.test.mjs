import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {nativeCoreFocusedTestCount} from './native-core-test-selection.mjs';
import {partitionNativeCorePlatformPackages} from './native-core-platform-packages.mjs';
import {nativeCoreLinuxCommonArguments, nativeCoreLinuxCommonPartitions, runNativeCoreLinuxCommon} from './test-native-core-linux-common.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('Linux common Native is mandatory without removing the original Darwin matrix', () => {
  const core = workflow.jobs['core-common'], matrix = core.strategy.matrix;
  assert.deepEqual(matrix.partition, ['1/4', ...nativeCoreLinuxCommonPartitions]);
  assert.equal(core.strategy['fail-fast'], false);
  assert.equal(core['continue-on-error'], undefined);
  assert(workflow.jobs.check.needs.includes('core'));
  for (const target of ['js', 'wasm']) {
    for (const partition of nativeCoreLinuxCommonPartitions)
      assert(matrix.exclude.some(row => row.target === target && row.partition === partition));
  }
  assert.equal(core['runs-on'], 'ubuntu-24.04');
  assert.equal(workflow.jobs['core-darwin']['runs-on'], 'macos-15');
  assert.deepEqual([...workflow.jobs['core-darwin'].strategy.matrix.partition].sort(),
    ['1/4', '2/4', '3/4', '4/4', 'http', 'scoped', 'source']);
});

test('Linux common Native uses its selected compiler profile rather than Darwin preparation', () => {
  const core = workflow.jobs['core-common'];
  const platform = core.steps.find(step => step.name === 'Require the supported Core Native platform');
  assert(platform.run.includes('linux-common'));
  assert(platform.run.includes('Linux'));
  const run = core.steps.find(step => step.name === 'Test common core');
  assert(run.run.includes('MOONBIT_NEW_NATIVE=0 node scripts/test-native-core-linux-common.mjs'));
  assert(run.run.indexOf('test-native-core-linux-common.mjs') < run.run.indexOf('platform_native/trusted_clock'));
  assert.equal(run.env.ACTQL_TEST_NATIVE_CORE_PARTITION,
    "${{ matrix.target == 'native' && !startsWith(matrix.partition, 'linux-common-') && matrix.partition || '' }}");
  const cache = core.steps.find(step => step.id === 'native-c-object-cache');
  assert(!cache.if.includes('linux-common'));
  assert.equal(nativeCoreLinuxCommonPartitions.length, 8);
  const reader = core.steps.find(step => step.name === 'Test actual Native Reader callbacks and original empty compiler driver');
  assert(reader.if.includes("!startsWith(matrix.partition, 'linux-common-')"));
});

test('Linux common Native orchestration retains exact flags, compiler environment, case count and failure', async () => {
  assert.deepEqual(nativeCoreLinuxCommonArguments, [
    '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
  ]);
  const original = {PATH: '/original/pinned/bin', RUNNER_TEMP: '/original/runner', ORIGINAL: 'retained'};
  for (const status of [0, 17]) {
    const calls = [];
    const actual = await runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-8/8', env: original,
      createScratch: async options => {
        assert.equal(options.parent, '/original/runner/core-linux-common');
        return {path: '/original/owned/compiler', passed: () => calls.push('passed')};
      },
      platformPackages: () => ({common: ['src/portable'], graphSha256: 'a'.repeat(64)}),
      selectTests: (_root, args, options) => {
        assert.deepEqual(args, [...nativeCoreLinuxCommonArguments]);
        assert.equal(options.ordinaryPartitions, 8);
        assert.deepEqual(options.executionPackages, ['src/portable']);
        return {executionScope: {mode: 'subset'}, profiles: {
          ordinary: {partitions: Array.from({length: 8}, (_, index) => ({args: [...args, `src/selected-${index}`], cases: 73}))},
          http: {cases: 0}, source: {cases: 0}, scoped: {cases: 0}}};
      },
      selectCompiler: (_root, scratch, env) => {
        assert.equal(scratch, '/original/owned/compiler'); assert.equal(env, original);
        calls.push('compiler'); return {PATH: '/original/owned/compiler/test-c-compiler:/original/pinned/bin'};
      },
      countTests: (_root, args, options) => {
        assert.deepEqual(args, [...nativeCoreLinuxCommonArguments, 'src/selected-7']);
        assert.equal(options.env.MOONBIT_NEW_NATIVE, '0');
        assert.equal(options.timeoutMs, 300000); calls.push('metadata'); return 73;
      },
      executeTests: (kind, args, options) => {
        assert.equal(kind, 'moon');
        assert.deepEqual(args, ['--target', 'native', ...nativeCoreLinuxCommonArguments, 'src/selected-7']);
        assert.equal(options.expectedTests, 73); assert.equal(options.timeout, 3600000);
        assert.equal(options.env.PATH, '/original/owned/compiler/test-c-compiler:/original/pinned/bin');
        assert.equal(options.env.ORIGINAL, 'retained');
        assert.equal(options.env.MOONBIT_NEW_NATIVE, '0');
        calls.push('execute'); return status;
      }});
    assert.equal(actual, status);
    assert.deepEqual(calls, ['compiler', 'metadata', 'execute', ...(status === 0 ? ['passed'] : [])]);
  }
  assert.deepEqual(original, {PATH: '/original/pinned/bin', RUNNER_TEMP: '/original/runner', ORIGINAL: 'retained'});
});

test('Linux common Native refuses a foreign platform, empty metadata or failed discovery before execution', async () => {
  let allocated = false, executed = false;
  await assert.rejects(runNativeCoreLinuxCommon({platform: 'darwin',
    createScratch: async () => { allocated = true; }}), /actual Linux runner/u);
  assert.equal(allocated, false);
  const original = new Error('original metadata refusal');
  for (const countTests of [() => 0, () => { throw original; }]) {
    await assert.rejects(runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8', env: {},
      createScratch: async () => ({path: '/owned', passed() { throw new Error('unconfirmed owner'); }}),
      selectCompiler: () => ({}), countTests,
      platformPackages: () => ({common: ['src/portable']}),
      selectTests: () => ({executionScope: {mode: 'subset'}, profiles: {
        ordinary: {partitions: Array.from({length: 8}, () => ({args: [...nativeCoreLinuxCommonArguments, 'src/portable']}))},
        http: {cases: 0}, source: {cases: 0}, scoped: {cases: 0}}}),
      executeTests: () => { executed = true; }}),
    error => error === original || /Nonempty compiler-owned/u.test(error.message));
  }
  assert.equal(executed, false);
});

test('Linux common Native metadata counts original native runnable cases without compiling or linking', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-linux-common-metadata-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'selected'));
  writeFileSync(join(root, 'selected/cases_test.mbt'), 'Original compiler metadata fixture\n');
  const calls = [];
  const args = ['--release', '--strip', '--deny-warn', 'selected'];
  const count = nativeCoreFocusedTestCount(root, args, {execute: (command, values) => {
    assert.equal(command, 'moon'); calls.push(values[0]);
    if (values[0] === 'test') {
      assert.deepEqual(values, ['test', '--target', 'native', ...args, '--dry-run']);
      return 'moon generate-test-driver --output-driver _build/driver.mbt --output-metadata _build/info.json selected/cases_test.mbt --target native --pkg-name fixture/selected --driver-kind blackbox';
    }
    assert.equal(values[0], 'generate-test-driver');
    const first = {index: 0, name: 'same original', attrs: []};
    const benchmark = {index: 2, name: 'benchmark', attrs: []};
    writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({
      tests: {'cases_test.mbt': [first, {index: 1, name: 'skipped', attrs: ['skip']}, benchmark]},
      with_bench_args_tests: {'cases_test.mbt': [benchmark]},
    }));
    return '';
  }});
  assert.equal(count, 1);
  assert.deepEqual(calls, ['test', 'generate-test-driver']);
});

test('Native platform classes separate original FFI owners from every source and test importer', () => {
  const names = ['scalar', 'canonical', 'platform_native/sqlite', 'native_fixture', 'caller', 'transitive', 'cmd/native_client', 'linker'];
  const packages = names.map(name => ({name: 'actql/actql/' + name, path: 'src/' + name}));
  const edge = (from, to, kinds) => ({from: packages[from].name, to: packages[to].name, kinds});
  const graph = {packages, digest: 'd'.repeat(64), edges: [
    edge(1, 0, ['source']), edge(4, 3, ['whitebox-test']),
    edge(5, 4, ['blackbox-test']), edge(3, 2, ['source']),
  ]};
  const original = JSON.stringify(graph);
  const selected = partitionNativeCorePlatformPackages(graph, path => path.endsWith('/native_fixture')
    ? 'options("native-stub": ["actual.c"])' : path.endsWith('/linker')
      ? 'options(link: {"native": {"cc": "./original-driver"}})' : 'supported_targets = "+js+wasm+native"');
  assert.deepEqual(selected.common, ['src/scalar', 'src/canonical']);
  assert.deepEqual(selected.importers, ['src/caller', 'src/transitive']);
  assert.deepEqual(selected.darwin, ['src/platform_native/sqlite', 'src/native_fixture',
    'src/cmd/native_client', 'src/linker']);
  assert.equal(selected.graphSha256, graph.digest);
  assert.equal(JSON.stringify(graph), original);
});

test('Linux common scope cannot silently accept missing metadata or an unreviewed physical fallback', async () => {
  assert.throws(() => partitionNativeCorePlatformPackages({packages: [{name: 'original', path: 'src/original'}], edges: []},
    () => { throw new Error('missing original manifest'); }), /missing original manifest/u);
  let executed = false;
  for (const mode of ['full-fallback', 'subset']) {
    await assert.rejects(runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8', env: {},
      createScratch: async () => ({path: '/owned', passed() { throw new Error('unconfirmed owner'); }}),
      selectCompiler: () => ({}), platformPackages: () => ({common: ['src/original']}),
      selectTests: () => ({executionScope: {mode}, profiles: {
        ordinary: {}, http: {cases: 1}, source: {cases: 0}, scoped: {cases: 0}}}),
      executeTests: () => { executed = true; }}),
    /cannot fall back|unrelated physical fixture/u);
  }
  assert.equal(executed, false);
});

test('hosted Darwin Core selects the complementary scope without changing local full diagnostics', () => {
  const run = workflow.jobs['core-common'].steps.find(step => step.name === 'Test common core');
  const expression = run.env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE;
  assert.equal(expression,
    "${{ matrix.target == 'native' && !startsWith(matrix.partition, 'linux-common-') && 'darwin-differences' || '' }}");
  for (const [target, partition, expected] of [
    ['native', '1/4', 'darwin-differences'], ['native', 'scoped', 'darwin-differences'],
    ['native', 'linux-common-1/8', ''], ['js', '1/4', ''], ['wasm', '1/4', ''],
  ]) assert.equal(runInNewContext(expression.slice(3, -2), {matrix: {target, partition},
    startsWith: (value, prefix) => value.startsWith(prefix)}), expected);
  const core = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert(core.includes("platformScope !== 'darwin-differences'"));
  assert(core.includes("process.platform !== 'darwin'"));
  assert(core.includes('platformPackages?.darwin'));
  assert(core.includes('allowNestedFileInputs: platformPackages !== undefined'));
  assert.equal((core.match(/ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: undefined/gu) ?? []).length, 2,
    'The selection-only marker cannot leak into original producers or runtime children');
});
