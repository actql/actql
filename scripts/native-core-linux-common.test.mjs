import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {nativeCoreTestCaseInventory} from './native-core-test-selection.mjs';
import {nativeCoreCiPartitions} from './ci-core-partitions.mjs';
import {partitionNativeCorePlatformPackages} from './native-core-platform-packages.mjs';
import {nativeCoreLinuxCommonArguments, nativeCoreLinuxCommonPartitions, runNativeCoreLinuxCommon} from './test-native-core-linux-common.mjs';
import {reviewedNativeCoreFiles, selectReviewedNativeCoreCases,
  verifyReviewedNativeCoreOutput, runReviewedNativeCoreSuite} from './native-core-reviewed-suite.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('Linux importers retain eight mandatory shards and five explicit Darwin profile owners', () => {
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
    [...nativeCoreCiPartitions].sort());
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
  const inventory = nativeCoreTestCaseInventory(root, args, {execute: (command, values) => {
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
  assert.equal(inventory.runnableCases, 1);
  assert(inventory.records.some(record => record.entry[2].name === 'skipped'));
  assert(inventory.records.some(record => record.entry[2].name === 'benchmark' && record.benchmark));
  assert(inventory.records.every(record => record.source === 'selected/cases_test.mbt'));
  assert.deepEqual(calls, ['test', 'generate-test-driver']);
});

test('reviewed Native child follows only the successful first Linux shard and preserves failures', async () => {
  const events = [], original = {PATH: '/original/tool', RUNNER_TEMP: '/original/scratch'};
  for (const partition of nativeCoreLinuxCommonPartitions) {
    events.length = 0;
    const status = await runNativeCoreLinuxCommon({platform: 'linux', partition, env: original,
      executeProfile: () => {events.push('original'); return 0;},
      executeReviewedSuite: ({env}) => {
        events.push('reviewed');
        assert.equal(env.PATH, original.PATH); assert.equal(env.RUNNER_TEMP, original.RUNNER_TEMP);
        assert.equal(env.MOONBIT_NEW_NATIVE, '0');
        assert.equal(env.ACTQL_TEST_NATIVE_CORE_PARTITION, undefined);
        assert.equal(env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE, undefined);
        return 29;
      }});
    assert.deepEqual(events, partition === 'linux-common-1/8' ? ['original', 'reviewed'] : ['original']);
    assert.equal(status, partition === 'linux-common-1/8' ? 29 : 0);
  }
  for (const status of [1, 130, 124]) {
    assert.equal(await runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8',
      executeProfile: () => status, executeReviewedSuite: () => assert.fail('Failed predecessor')}), status);
  }
  const failure = new Error('reviewed execution failed');
  await assert.rejects(runNativeCoreLinuxCommon({platform: 'linux', partition: 'linux-common-1/8',
    executeProfile: () => 0, executeReviewedSuite: () => {throw failure;}}), error => error === failure);
  assert.deepEqual(original, {PATH: '/original/tool', RUNNER_TEMP: '/original/scratch'});
});

const reviewedRecords = () => reviewedNativeCoreFiles.flatMap(file => file.names.map((name, index) => ({
  source: file.source, directory: 'src/platform_native/row_source', benchmark: false,
  entry: [JSON.stringify(['actql/actql/platform_native/row_source', 'whitebox']), file.source.split('/').at(-1),
    {name, index, attrs: []}],
})));

test('reviewed compiler selection refuses changed cases without adopting physical siblings', () => {
  const records = reviewedRecords();
  assert.deepEqual([...new Set(records.map(record => record.entry[1]))].sort(), [
    'capacity_wbtest.mbt', 'file_content_bytes_wbtest.mbt', 'file_listing_page_wbtest.mbt', 'keyed_read_profile_wbtest.mbt',
  ]);
  const sibling = {...records[0], source: 'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt'};
  assert.deepEqual(selectReviewedNativeCoreCases({records: [sibling, ...records]}), records);
  const mutations = [
    values => values.pop(), values => values.push(structuredClone(values[0])),
    values => {values[0].entry[2].name = 'unreviewed replacement';},
    values => {values[0].entry[2].attrs = ['skip'];},
    values => {values[0].benchmark = true;},
    values => {values[0].entry[0] = JSON.stringify(['foreign/package', 'whitebox']);},
    values => {values[0].entry[1] = 'keyed_read_profile_wbtest.mbt';},
    values => {values.splice(0, values.filter(value => value.source === values[0].source).length);},
    values => {values[0].entry[2].index = values[1].entry[2].index;},
  ];
  for (const mutate of mutations) {
    const changed = structuredClone(records); mutate(changed);
    assert.throws(() => selectReviewedNativeCoreCases({records: changed}));
  }
  assert.throws(() => selectReviewedNativeCoreCases({records: []}), /Missing/u);
});

test('reviewed Native proof requires every actual original name beyond the nonzero total', () => {
  const records = reviewedRecords();
  const lines = records.map(({entry, source}) => '[actql/actql] test ' + source.slice('src/'.length) + ':1 (' +
    JSON.stringify(entry[2].name) + ') ok');
  verifyReviewedNativeCoreOutput(records, lines.join('\n'));
  for (const output of ['', lines.slice(1).join('\n'), [...lines, lines[0]].join('\n'),
    lines.join('\n').replace(') ok', ') failed'), lines.join('\n').replace('Native transport', 'Changed transport'),
    lines.join('\n').replace('keyed_read_profile_wbtest.mbt', 'capacity_wbtest.mbt'),
    [...lines, '[actql/actql] test platform_native/row_source/physical_wbtest.mbt:1 ("other") ok'].join('\n')])
    assert.throws(() => verifyReviewedNativeCoreOutput(records, output));
});

test('reviewed Native entry uses the existing finite supervisor and preserves cancellation', async () => {
  const root = realpathSync(new URL('../', import.meta.url));
  let calls = 0;
  const original = {PATH: '/pinned/bin', ACTQL_TEST_NATIVE_CORE_PARTITION: '1/8',
    ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: 'linux-common-importers'};
  for (const status of [0, 17, 130]) {
    assert.equal(await runReviewedNativeCoreSuite({root, env: original, platform: 'linux', arch: 'x64',
      execute: async config => {
        calls++;
        assert.equal(config.root, root); assert.equal(config.heavy, true);
        assert(Number.isSafeInteger(config.timeoutSeconds) && config.timeoutSeconds > 0);
        const jobMinutes = runInNewContext(workflow.jobs['core-common']['timeout-minutes'].slice(3, -2),
          {matrix: {target: 'native'}});
        assert(config.timeoutSeconds + config.graceSeconds < jobMinutes * 60);
        assert.equal(config.steps.length, 1);
        assert.equal(config.steps[0].command, process.execPath);
        assert(config.steps[0].args.some(value => value.includes('executeReviewedNativeCoreSuite')));
        assert.equal(config.steps[0].env.PATH, original.PATH);
        assert.equal(config.steps[0].env.ACTQL_TEST_NATIVE_CORE_PARTITION, undefined);
        assert.equal(config.steps[0].env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE, undefined);
        return status;
      }}), status);
  }
  for (const options of [{platform: 'darwin', arch: 'x64'}, {platform: 'linux', arch: 'arm64'}])
    await assert.rejects(runReviewedNativeCoreSuite({...options, execute: () => assert.fail('Foreign platform')}));
  assert.equal(calls, 3);
  assert.equal(original.ACTQL_TEST_NATIVE_CORE_PARTITION, '1/8');
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
  // test-native-core.test.mjs exercises the imported selection owner, including
  // one discovery and refusal of every foreign physical profile.
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
  assert(core.includes('[...platformPackages.common, ...platformPackages.importers].sort()'));
  assert.equal((core.match(/ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: undefined/gu) ?? []).length, 2,
    'The selection-only marker cannot leak into original producers or runtime children');
});
