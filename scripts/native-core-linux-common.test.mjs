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

test('Linux importers retain eight mandatory shards and four explicit Darwin profile owners', () => {
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
    ['1/2', '2/2', 'scoped', 'source']);
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

test('Linux dispatch leaves discovery and expected counts to the sole original Native entry', async () => {
  let entered = 0;
  const repeat = () => { throw new Error('Duplicate caller-side metadata discovery'); };
  const actual = await runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-4/8',
    platformPackages: repeat, selectTests: repeat, countTests: repeat,
    executeProfile: (_root, args, options) => {
      entered++;
      assert.deepEqual(args, [...nativeCoreLinuxCommonArguments]);
      assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE, 'linux-common-importers');
      assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_PARTITION, '4/8');
      assert.equal(options.expectedTests, undefined, 'The original counted entry owns its actual count');
      return 19;
    }});
  assert.equal(entered, 1); assert.equal(actual, 19);
});

test('Linux dispatch preserves original flags and environment and propagates profile failures', async () => {
  assert.deepEqual(nativeCoreLinuxCommonArguments, [
    '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
  ]);
  const original = {PATH: '/original/pinned/bin', RUNNER_TEMP: '/original/runner', ORIGINAL: 'retained'};
  for (const status of [0, 17]) {
    let calls = 0;
    const actual = await runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-8/8', env: original,
      executeProfile: (_root, args, options) => {
        calls++;
        assert.deepEqual(args, [...nativeCoreLinuxCommonArguments]);
        assert.equal(options.expectedTests, undefined);
        assert.equal(options.env.PATH, original.PATH);
        assert.equal(options.env.ORIGINAL, 'retained');
        assert.equal(options.env.MOONBIT_NEW_NATIVE, '0');
        assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE, 'linux-common-importers');
        assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_PARTITION, '8/8');
        return status;
      }});
    assert.equal(actual, status); assert.equal(calls, 1);
  }
  const failed = new Error('original profile failure');
  await assert.rejects(runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8',
    executeProfile: () => {throw failed;}}), error => error === failed);
  assert.deepEqual(original, {PATH: '/original/pinned/bin', RUNNER_TEMP: '/original/runner', ORIGINAL: 'retained'});
});

test('Linux dispatch refuses a foreign platform or partition before entering the original profile', async () => {
  let executed = false;
  for (const options of [{platform: 'darwin', partition: 'linux-common-1/8'},
    {platform: 'linux', partition: 'linux-common-9/8'}, {platform: 'linux'}])
    await assert.rejects(runNativeCoreLinuxCommon({...options,
      executeProfile: () => {executed = true;}}), /actual Linux runner|original Linux common partition/u);
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

test('the platform classifier preserves the original manifest failure and the entry owns all selection', () => {
  const failed = new Error('missing original manifest');
  assert.throws(() => partitionNativeCorePlatformPackages({packages: [{name: 'original', path: 'src/original'}], edges: []},
    () => {throw failed;}), error => error === failed);
  const wrapper = readFileSync(new URL('./test-native-core-linux-common.mjs', import.meta.url), 'utf8');
  assert(wrapper.includes("await import('./test-native-core.mjs')"));
  assert(wrapper.includes('process.argv.splice(2, process.argv.length - 2, ...args)'));
  for (const retired of ['spawnSync', 'nativeCoreCCompiler', 'nativeCoreTestSelection', 'nativeCoreFocusedTestCount', 'readNativeCorePlatformPackages'])
    assert(!wrapper.includes(retired), retired);
  const entry = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert(entry.includes('selection.profiles.http.cases + selection.profiles.source.cases + selection.profiles.scoped.cases !== 0'));
  assert.equal((entry.match(/full \? nativeCoreTestSelection/g) ?? []).length, 1);
});

test('the actual Native profile entry refuses library reentry before changing argv or importing fixtures', async () => {
  const argv = [...process.argv];
  await assert.rejects(runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8'}),
    /Original one-shot Linux cohort CLI required/u);
  assert.deepEqual(process.argv, argv);
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
  assert(core.includes("['darwin-differences', 'linux-common-importers'].includes(platformScope)"));
  assert(core.includes("process.platform !== (linuxCommonImporters ? 'linux' : 'darwin')"));
  assert(core.includes(': platformPackages.darwin)'));
  assert(core.includes("{hostedDarwin: platformScope === 'darwin-differences'}"));
  assert(core.includes('[...platformPackages.common, ...platformPackages.importers].sort()'));
  assert(core.includes('allowNestedFileInputs: platformPackages !== undefined'));
  assert.equal((core.match(/ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: undefined/gu) ?? []).length, 2,
    'The selection-only marker cannot leak into original producers or runtime children');
});
