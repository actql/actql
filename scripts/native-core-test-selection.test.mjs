import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import test from 'node:test';
import {nativeCoreTestSelection, portableMoonTestCount, nativeCoreHttpArguments, nativeCoreHttpTestFiles,
  nativeCoreOrdinaryPartitions, nativeCorePartitionProfiles, nativeScopedTestFiles, nativeCoreScopedAllocationProfile,
  nativeCoreScopedTestEnvironment, nativeCoreCheckpointRequired} from './native-core-test-selection.mjs';
import {assertTestExecution} from './test-execution.mjs';

test('Journal metadata original Read selects its scoped allocator without changing sibling profiles', () => {
  const source = 'src/platform_native/client_host/journal_metadata_original_read_physical_scoped_wbtest.mbt';
  assert.equal(nativeScopedTestFiles.filter(file => file === source).length, 1);
  assert.equal(nativeCoreScopedAllocationProfile(source), 'scoped-review-values');
  for (const sibling of ['run_plan_fresh_construction_native_wbtest.mbt',
    'run_plan_cold_construction_native_wbtest.mbt', 'run_effect_receipt_wbtest.mbt']) {
    assert.equal(nativeCoreScopedAllocationProfile('src/platform_native/client_host/' + sibling), 'runtime-values');
  }
  assert.deepEqual(nativeCoreScopedTestEnvironment({source, index: 0}), {});
});

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-test-selection-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['active', 'empty']) {
    mkdirSync(join(root, name));
    writeFileSync(join(root, name, 'main.mbt'), 'Original explicit compiler-input fixture\n');
  }
  return root;
}

function dependencyFixture(t, {nested = false, changedDriver = false} = {}) {
  const root = fixture(t);
  const physical = nativeScopedTestFiles[0], http = 'src/platform_native/http_client/original_wbtest.mbt';
  const source = 'src/platform_native/remote_resident_source_compute_tests/original_wbtest.mbt';
  const paths = ['active/main.mbt', 'empty/main.mbt', 'unrelated/main.mbt', physical, http, source,
    ...(nested ? ['active/nested/main.mbt'] : [])];
  for (const path of paths) {
    mkdirSync(dirname(join(root, path)), {recursive:true});
    writeFileSync(join(root, path), 'test "compiler original" { assert_eq(7, 7) }\n');
  }
  const directory = path => path.slice(0, path.lastIndexOf('/'));
  const command = path => ['moon', 'generate-test-driver', '--output-driver', `_build/${path}/driver.mbt`,
    '--output-metadata', `_build/${path}/info.json`, path, '--target', 'native',
    '--pkg-name', 'fixture/' + directory(path), '--driver-kind', 'blackbox'].join(' ');
  const commands = [];
  const execute = (_tool, values) => {
    commands.push(values[0]);
    if (values[0] === 'test') {
      const selected = paths.filter(path => values.includes(path) || values.some(value =>
        value === directory(path) || path.startsWith(value + '/')));
      const input = (selected.length ? selected : paths).map(command).join('\n');
      return changedDriver && selected.length ? input.replace('--driver-kind blackbox', '--driver-kind whitebox') : input;
    }
    assert.equal(values[0], 'generate-test-driver', 'Only metadata commands may be executed');
    const original = values.find(value => paths.includes(value));
    assert(original);
    writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({tests:{
      [basename(original)]:[{index:0, name:'same opaque original', attrs:[], line_number:1, original:{same:true}}],
    }}));
    return '';
  };
  const selectedPackages = ['active', 'empty', directory(physical), directory(http), directory(source)];
  return {root, commands, execute, selectedPackages, physical, source, http, originalCases:paths.length};
}

test('Native dependency scope narrows compiler originals and preserves physical profiles and both partitions', t => {
  const f = dependencyFixture(t);
  const selected = nativeCoreTestSelection(f.root, ['--release'], {execute:f.execute,
    partitionProfiles:true, ordinaryPartitions:true, executionPackages:f.selectedPackages});
  assert.equal(selected.executionScope.mode, 'subset');
  assert.equal(selected.executionScope.originalCases, 6); assert.equal(selected.cases, 5);
  assert.equal(selected.executionScope.selectedCases, 5);
  assert(!selected.args.includes('unrelated'));
  assert.deepEqual(selected.profiles.ordinary.partitions.map(part => part.cases), [1, 1]);
  assert.equal(selected.profiles.http.cases, 1); assert.equal(selected.profiles.source.cases, 1);
  assert.deepEqual(selected.profiles.scoped.tests, [{source:f.physical, index:0}]);
  const first = nativeCorePartitionProfiles(selected.profiles, '1/2');
  const second = nativeCorePartitionProfiles(selected.profiles, '2/2');
  assert.equal(first.http.cases + first.source.cases + first.scoped.cases, 3);
  assert.equal(second.http.cases + second.source.cases + second.scoped.cases, 0);
  assert.equal(first.ordinary.cases + second.ordinary.cases + 3, selected.cases);
  assert(f.commands.every(command => ['test', 'generate-test-driver'].includes(command)));
});

test('Native dependency scope explains full fallback instead of admitting an empty original partition', t => {
  for (const selectedPackages of [['active'], ['empty']]) {
    const f = dependencyFixture(t);
    const selected = nativeCoreTestSelection(f.root, ['--release'], {execute:f.execute,
      partitionProfiles:true, ordinaryPartitions:true, executionPackages:selectedPackages});
    assert.equal(selected.executionScope.mode, 'full-fallback');
    assert.equal(selected.executionScope.originalCases, selected.cases);
    assert.equal(selected.cases, f.originalCases);
    assert(selected.profiles.ordinary.partitions.every(part => part.cases > 0));
  }
});

test('Native dependency scope keeps full originals for skipped-only selections or either skipped-only partition', t => {
  const scenarios = [
    {skip:['active', 'empty'], ordinaryPartitions:true},
    {skip:['empty'], ordinaryPartitions:true},
    {skip:['active', 'empty'], ordinaryPartitions:false, allSkipped:true},
    {skip:['unrelated'], ordinaryPartitions:true, extraSkipped:100},
  ];
  for (const scenario of scenarios) {
    const f = dependencyFixture(t);
    const execute = (tool, values, options) => {
      const result = f.execute(tool, values, options);
      if (values[0] !== 'generate-test-driver') return result;
      const metadataPath = values[values.indexOf('--output-metadata') + 1];
      const metadata = JSON.parse(readFileSync(metadataPath, 'utf8'));
      const skipped = scenario.allSkipped || scenario.skip.some(directory => values.includes(directory + '/main.mbt'));
      if (skipped) for (const tests of Object.values(metadata.tests)) {
        tests[0].attrs = ['skip'];
        if (scenario.extraSkipped) for (let index = 1; index <= scenario.extraSkipped; index++)
          tests.push({...tests[0], index});
      }
      writeFileSync(metadataPath, JSON.stringify(metadata));
      return result;
    };
    const packages = [...f.selectedPackages, ...(scenario.extraSkipped ? ['unrelated'] : [])];
    const selected = nativeCoreTestSelection(f.root, ['--release'], {execute,
      partitionProfiles:true, ordinaryPartitions:scenario.ordinaryPartitions, executionPackages:packages});
    assert.equal(selected.executionScope.mode, 'full-fallback', JSON.stringify(scenario));
    assert.equal(selected.cases, selected.executionScope.originalCases);
  }
});

test('Native dependency scope keeps a full plan for an unselected nested compiler package', t => {
  const f = dependencyFixture(t, {nested:true});
  const selected = nativeCoreTestSelection(f.root, ['--release'], {execute:f.execute,
    partitionProfiles:true, ordinaryPartitions:true, executionPackages:f.selectedPackages});
  assert.equal(selected.executionScope.mode, 'full-fallback');
  assert.match(selected.executionScope.reason, /nested/u);
  assert.equal(selected.cases, f.originalCases);
});

test('explicit Native file scope excludes nested packages while retaining every selected physical profile', t => {
  const f = dependencyFixture(t, {nested: true});
  const selected = nativeCoreTestSelection(f.root, ['--release'], {execute: f.execute,
    partitionProfiles: true, ordinaryPartitions: true, executionPackages: ['active', 'empty'],
    allowNestedFileInputs: true});
  assert.equal(selected.executionScope.mode, 'subset');
  assert.equal(selected.cases, 2);
  assert.deepEqual(selected.args, ['--release', 'active/main.mbt', 'empty']);
  assert.deepEqual(selected.profiles.ordinary.partitions.flatMap(part => part.args.slice(1)).sort(),
    ['active/main.mbt', 'empty']);
  assert.equal(selected.profiles.http.cases + selected.profiles.source.cases + selected.profiles.scoped.cases, 0);
  const physical = nativeCoreTestSelection(f.root, ['--release'], {execute: f.execute,
    partitionProfiles: true, ordinaryPartitions: true,
    executionPackages: f.selectedPackages, allowNestedFileInputs: true});
  assert.equal(physical.executionScope.mode, 'subset');
  assert.equal(physical.cases, 5);
  assert.equal(physical.profiles.ordinary.cases, 2);
  assert.equal(physical.profiles.http.cases, 1);
  assert.equal(physical.profiles.source.cases, 1);
  assert.equal(physical.profiles.physicalCases, 1);
  assert.deepEqual(physical.profiles.scoped.tests, [{source: f.physical, index: 0}]);
  assert(!physical.args.includes('active/nested'));
});

test('Native dependency selection refuses changed original drivers and foreign or duplicate package paths', t => {
  const f = dependencyFixture(t, {changedDriver:true});
  assert.throws(() => nativeCoreTestSelection(f.root, ['--release'], {execute:f.execute,
    partitionProfiles:true, ordinaryPartitions:true, executionPackages:f.selectedPackages}), /Foreign selected/u);
  for (const executionPackages of [[], ['active', 'active'], ['../outside'], ['/foreign']]) {
    const other = dependencyFixture(t);
    assert.throws(() => nativeCoreTestSelection(other.root, ['--release'], {execute:other.execute,
      partitionProfiles:true, ordinaryPartitions:true, executionPackages}));
  }
});

test('Native ordinary partitions preserve complete original package drivers and exhaustive disjoint inputs', () => {
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'];
  const records = [], paths = [];
  for (const [directory, files] of [
    ['src/a', ['public_test.mbt', 'private_wbtest.mbt']],
    ['src/b', ['original_test.mbt']], ['src/c', ['original_test.mbt']],
    ['src/mixed', ['ordinary_wbtest.mbt']],
  ]) {
    paths.push(directory === 'src/mixed' ? directory + '/ordinary_wbtest.mbt' : directory);
    for (const file of files) for (let index = 0; index < 3; index++) {
      records.push({directory, source: directory + '/' + file, benchmark: index === 2,
        entry: [directory + '/' + file, file, {index, name: 'original-' + index, attrs: ['opaque']}]});
    }
  }
  const parts = nativeCoreOrdinaryPartitions(args, paths, records);
  assert.equal(parts.length, 2);
  assert(parts.every(part => part.cases > 0));
  assert.equal(parts.reduce((sum, part) => sum + part.cases, 0), 10);
  assert.deepEqual(parts.flatMap(part => part.args.slice(args.length)).sort(), [...paths].sort());
  for (const path of paths) assert.equal(parts.filter(part => part.args.includes(path)).length, 1);
  for (const part of parts) {
    assert.deepEqual(part.args.slice(0, args.length), args);
    const originalRecords = records.filter(record => part.args.includes(record.directory) || part.args.includes(record.source));
    assert.equal(part.cases, originalRecords.filter(record => !record.benchmark).length);
  }
  assert.deepEqual(nativeCoreOrdinaryPartitions(args, paths, [...records].reverse()), parts,
    'Compiler metadata traversal order cannot choose a different partition');
  assert.equal(JSON.stringify(records).includes('opaque'), true);
});

test('Native ordinary partitions refuse duplicate missing foreign and empty original inventories', () => {
  const record = (directory, index = 0) => ({directory, source: directory + '/original_test.mbt',
    benchmark: false, entry: [directory, 'original_test.mbt', {index}]});
  const records = [record('src/a'), record('src/b')], paths = ['src/a', 'src/b'];
  assert.throws(() => nativeCoreOrdinaryPartitions([], paths, [...records, records[0]]), /Duplicate/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], paths, [...records, record('src/foreign')]), /no original/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], [...paths, 'src/missing'], records), /omitted/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], paths, []), /nonempty/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], ['src/a'], [record('src/a')]), /nonempty/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], paths, records.map(r => ({...r, benchmark: true}))), /nonempty/u);
});

test('Native ordinary nested package inputs retain their exact owner instead of their parent directory', () => {
  const paths = ['src/parent', 'src/parent/child', 'src/other'];
  const records = paths.map(directory => ({directory, source: directory + '/original_test.mbt',
    benchmark: false, entry: [directory, 'original_test.mbt', {index: 0}]}));
  const parts = nativeCoreOrdinaryPartitions(['--release'], paths, records);
  assert.deepEqual(parts.flatMap(part => part.args.slice(1)).sort(), [...paths].sort());
  assert.equal(parts.reduce((sum, part) => sum + part.cases, 0), 3);
  for (const part of parts) assert.equal(part.args.length - 1, part.cases);
});

test('Native partition ownership runs HTTP Source scoped and repeated geometry exactly once', () => {
  const parts = [{args: ['--release', 'src/a'], cases: 4}, {args: ['--release', 'src/b'], cases: 7}];
  const profiles = {ordinary: {args: ['--release', 'src/a', 'src/b'], cases: 11, partitions: parts},
    http: {args: ['src/http'], cases: 3}, source: {args: ['src/source'], cases: 5},
    scoped: {args: ['src/scoped'], cases: 2, tests: [{source: 'src/scoped/original_test.mbt', index: 0}]},
    physicalCases: 1, repeatedGeometryCases: 1, uniqueCases: 20};
  assert.equal(nativeCorePartitionProfiles(profiles, undefined), profiles);
  assert.equal(nativeCorePartitionProfiles(profiles, ''), profiles);
  const first = nativeCorePartitionProfiles(profiles, '1/2'), second = nativeCorePartitionProfiles(profiles, '2/2');
  assert.equal(first.ordinary, parts[0]); assert.equal(second.ordinary, parts[1]);
  for (const name of ['http', 'source', 'scoped']) {
    assert.equal(first[name], profiles[name]);
    assert.equal(second[name].args, null); assert.equal(second[name].cases, 0);
  }
  assert.equal(first.physicalCases, 1); assert.equal(first.repeatedGeometryCases, 1);
  assert.equal(second.physicalCases, 0); assert.equal(second.repeatedGeometryCases, 0);
  for (const value of ['0/2', '3/2', '1/3', '1', ' 1/2'])
    assert.throws(() => nativeCorePartitionProfiles(profiles, value), /Invalid/u);
  assert.throws(() => nativeCorePartitionProfiles({...profiles, ordinary: {cases: 11}}, '1/2'), /Missing/u);
  assert.throws(() => nativeCorePartitionProfiles({...profiles, ordinary: {partitions: [parts[0], {args: [], cases: 0}]}}, '2/2'), /Empty/u);
});

test('eight Linux ordinary partitions retain original case ownership without physical profile adoption', () => {
  const paths = Array.from({length: 16}, (_, i) => `src/package-${i}`);
  const records = paths.flatMap(directory => Array.from({length: 3}, (_, index) => ({
    directory, source: `${directory}/original_test.mbt`, benchmark: false,
    entry: [directory, 'original_test.mbt', {index}],
  })));
  const partitions = nativeCoreOrdinaryPartitions(['--release'], paths, records, 8);
  const profiles = {ordinary: {args: ['--release', ...paths], cases: 48, partitions},
    http: {args: ['src/http'], cases: 3}, source: {args: ['src/source'], cases: 5},
    scoped: {args: ['src/scoped'], cases: 9, tests: [{source: 'original', index: 0}]},
    physicalCases: 7, repeatedGeometryCases: 2};
  const original = JSON.stringify(profiles);
  const lanes = Array.from({length: 8}, (_, i) => nativeCorePartitionProfiles(profiles, `${i + 1}/8`));
  assert.equal(lanes.reduce((n, lane) => n + lane.ordinary.cases, 0), 48);
  assert.deepEqual(lanes.flatMap(lane => lane.ordinary.args.slice(1)).sort(), [...paths].sort());
  for (const [i, lane] of lanes.entries()) {
    assert.equal(lane.ordinary, partitions[i]);
    for (const name of ['http', 'source', 'scoped']) {
      assert.equal(lane[name].cases, 0); assert.equal(lane[name].args, null);
    }
    assert.equal(lane.physicalCases, 0); assert.equal(lane.repeatedGeometryCases, 0);
  }
  assert.equal(JSON.stringify(profiles), original);
  for (const invalid of ['0/8', '9/8', '01/8', '1/9'])
    assert.throws(() => nativeCorePartitionProfiles(profiles, invalid), /Invalid/u);
});

test('four hosted Darwin jobs keep HTTP Source scoped and repeated geometry under their original profile owners', () => {
  const partitions = [{args: ['--release', 'src/a'], cases: 4}, {args: ['--release', 'src/b'], cases: 7}];
  const profiles = {ordinary: {args: ['--release', 'src/a', 'src/b'], cases: 11, partitions},
    http: {args: ['src/http'], cases: 3}, source: {args: ['src/source'], cases: 5},
    scoped: {args: ['src/scoped'], cases: 9, tests: [{source: 'original', index: 0}]},
    physicalCases: 7, repeatedGeometryCases: 2};
  const original = JSON.stringify(profiles);
  const selected = ['1/2', '2/2', 'source', 'scoped'].map(value =>
    nativeCorePartitionProfiles(profiles, value, {hostedDarwin: true}));
  for (const name of ['ordinary', 'http', 'source', 'scoped'])
    assert.equal(selected.reduce((sum, value) => sum + value[name].cases, 0), profiles[name].cases);
  assert.equal(selected[0].ordinary, partitions[0]);
  assert.equal(selected[1].ordinary, partitions[1]);
  assert.equal(selected[0].http, profiles.http);
  assert.equal(selected[2].source, profiles.source);
  assert.equal(selected[3].scoped, profiles.scoped);
  assert.equal(selected.reduce((sum, value) => sum + value.physicalCases, 0), 7);
  assert.equal(selected.reduce((sum, value) => sum + value.repeatedGeometryCases, 0), 2);
  assert.equal(JSON.stringify(profiles), original);
  assert.throws(() => nativeCorePartitionProfiles({...profiles, http: {args: null, cases: 0}},
    '1/2', {hostedDarwin: true}), /retain the original HTTP/u);
  assert.throws(() => nativeCorePartitionProfiles(profiles, '1/2', {hostedDarwin: 'true'}), /Invalid/u);
});

test('four Native ordinary jobs and independent physical jobs exhaust the original profile inventory', () => {
  const paths = Array.from({length: 12}, (_, i) => `src/package-${i}`);
  const records = paths.flatMap(directory => Array.from({length: 3}, (_, index) => ({
    directory, source: `${directory}/original_test.mbt`, benchmark: false,
    entry: [directory, 'original_test.mbt', {index}],
  })));
  const partitions = nativeCoreOrdinaryPartitions(['--release'], paths, records, 4);
  assert.equal(partitions.length, 4);
  assert.deepEqual(partitions.flatMap(p => p.args.slice(1)).sort(), [...paths].sort());
  assert.deepEqual(nativeCoreOrdinaryPartitions(['--release'], paths, [...records].reverse(), 4), partitions);
  const profiles = {ordinary: {args: ['--release', ...paths], cases: 36, partitions},
    http: {args: ['src/http'], cases: 3}, source: {args: ['src/source'], cases: 5},
    scoped: {args: ['src/scoped'], cases: 9, tests: [{source: 'original', index: 0}]},
    physicalCases: 7, repeatedGeometryCases: 2};
  const lanes = ['1/4', '2/4', '3/4', '4/4', 'http', 'source', 'scoped'];
  const selected = lanes.map(lane => nativeCorePartitionProfiles(profiles, lane));
  for (const name of ['ordinary', 'http', 'source', 'scoped']) {
    assert.equal(selected.reduce((sum, p) => sum + p[name].cases, 0), profiles[name].cases);
    assert.equal(selected.filter(p => p[name].args !== null).length, name === 'ordinary' ? 4 : 1);
  }
  assert.equal(selected.reduce((sum, p) => sum + p.physicalCases, 0), 7);
  assert.equal(selected.reduce((sum, p) => sum + p.repeatedGeometryCases, 0), 2);
  assert.equal(selected.at(-1).scoped.tests, profiles.scoped.tests);
  for (const lane of ['0/4', '5/4', '3/2', '1/3', 'HTTP', 'scoped/4'])
    assert.throws(() => nativeCorePartitionProfiles(profiles, lane), /Invalid/u);
  assert.throws(() => nativeCorePartitionProfiles({...profiles, http: {args: null, cases: 0}}, 'http'), /Empty/u);
  assert.throws(() => nativeCoreOrdinaryPartitions([], paths.slice(0, 3), records.slice(0, 9), 4), /nonempty/u);
});

test('four Native ordinary bins separate measured large packages without splitting original drivers', () => {
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'];
  const heavy = ['src/canonical_value', 'src/query_integration', 'src/cmd/native_client'];
  const other = ['src/ordinary-a', 'src/ordinary-b', 'src/ordinary-c'];
  const paths = [...other, ...heavy], records = [];
  for (const directory of paths) for (let driver = 0; driver < (heavy.includes(directory) ? 1 : 10); driver++) {
    const source = `${directory}/original-${driver}_test.mbt`;
    for (let index = 0; index < 2; index++) records.push(Object.freeze({directory, source,
      benchmark: index === 1,
      entry: Object.freeze([`${directory}/driver-${driver}`, source, Object.freeze({index, attrs: ['original']})]),
    }));
  }
  const original = JSON.stringify(records);
  const parts = nativeCoreOrdinaryPartitions(args, paths, records, 4);
  const owners = heavy.map(path => parts.findIndex(part => part.args.includes(path)));
  assert.equal(new Set(owners).size, 3, 'Measured large packages must not collect in the same ordinary bin');
  assert(owners.every(owner => owner >= 0));
  assert.equal(parts.length, 4);
  assert.deepEqual(parts.flatMap(part => part.args.slice(args.length)).sort(), [...paths].sort());
  for (const part of parts) {
    assert.deepEqual(part.args.slice(0, args.length), args);
    const selected = records.filter(record => part.args.includes(record.directory));
    assert.equal(part.cases, selected.filter(record => !record.benchmark).length);
    assert(part.cases > 0);
    for (const record of selected) assert.equal(parts.filter(p => p.args.includes(record.directory)).length, 1);
  }
  assert.equal(parts.reduce((sum, part) => sum + part.cases, 0), 33);
  assert.deepEqual(nativeCoreOrdinaryPartitions(args, [...paths].reverse(), [...records].reverse(), 4),
    parts.map(part => ({...part, args: [...args, ...part.args.slice(args.length).reverse()]})));
  assert.equal(JSON.stringify(records), original, 'Original compiler records must remain unchanged');
  assert.deepEqual(nativeCoreOrdinaryPartitions(args, paths, records, 2).map(part => part.args.slice(args.length)),
    [[other[0], other[2]], [other[1], ...heavy]], 'The existing two-way local plan is unchanged');
});

test('actual compiler four-way Native inventory never duplicates a generated test driver', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-four-partitions-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_four"\nversion = "0.0.0"\n');
  const heavy = ['src/canonical_value', 'src/query_integration', 'src/cmd/native_client'];
  for (const path of [...heavy, ...Array.from({length: 5}, (_, i) => `src/package-${i}`)]) {
    const directory = join(root, path);
    mkdirSync(directory, {recursive: true});
    writeFileSync(join(directory, 'moon.pkg'), '');
    writeFileSync(join(directory, 'main.mbt'), 'test "original case" { assert_eq(7, 7) }\n');
  }
  const args = ['--release', '--deny-warn'];
  const selected = nativeCoreTestSelection(root, args, {partitionProfiles: true, ordinaryPartitions: 4});
  const parts = selected.profiles.ordinary.partitions;
  assert.equal(parts.length, 4);
  assert.equal(selected.cases, 8);
  assert.deepEqual(parts.map(p => p.cases), [2, 2, 2, 2]);
  assert.equal(new Set(heavy.map(path => parts.findIndex(part => part.args.includes(path)))).size, 3);
  const paths = parts.flatMap(p => p.args.slice(args.length));
  assert.equal(new Set(paths).size, 8);
  const drivers = parts.flatMap(p => p.drivers);
  assert(drivers.length >= 8);
  assert.equal(new Set(drivers).size, drivers.length);
  assert.deepEqual(paths.sort(), selected.profiles.ordinary.args.slice(args.length).sort());
});

test('split Native jobs do not multiply the large checkpoint prerequisite compilation', () => {
  const ordinary = {args: ['--release', 'src/platform_native/client_host'], cases: 4};
  const profiles = {ordinary: {...ordinary, partitions: [ordinary,
    ...['other', 'third', 'fourth'].map(name => ({args: ['src/' + name], cases: 2}))]},
    http: {args: ['src/http'], cases: 1}, source: {args: ['src/source'], cases: 1},
    scoped: {args: ['src/scoped'], cases: 1,
      tests: [{source: 'src/platform_native/client_host/run_effect_file_response_wbtest.mbt', index: 0}]},
    physicalCases: 1, repeatedGeometryCases: 0};
  const required = ['1/4', '2/4', '3/4', '4/4', 'http', 'source', 'scoped']
    .filter(lane => nativeCoreCheckpointRequired(nativeCorePartitionProfiles(profiles, lane)));
  assert.deepEqual(required, ['1/4', 'scoped']);
  assert.equal(nativeCoreCheckpointRequired({...profiles, ordinary: {args: [
    'src/platform_native/client_host/another_original_wbtest.mbt']}, scoped: {tests: []}}), true);
  assert.equal(nativeCoreCheckpointRequired({ordinary: {args: null}, scoped: {tests: []}}), false);
});

test('Native compiler discovery connects both partitions to unchanged original driver inputs without C compilation', t => {
  const root = fixture(t);
  const command = name => ['moon', 'generate-test-driver', '--output-driver', '_build/'+name+'/driver.mbt',
    '--output-metadata', '_build/'+name+'/info.json', name+'/main.mbt', '--target', 'native',
    '--pkg-name', 'fixture/'+name, '--driver-kind', 'blackbox'].join(' ');
  let generated = 0;
  const execute = (_tool, values) => {
    if (values[0] === 'test') {
      const paths = ['active', 'empty'].filter(name => values.includes(name));
      return (paths.length ? paths : ['active', 'empty']).map(command).join('\n');
    }
    assert.equal(values[0], 'generate-test-driver'); generated++;
    const path = values[values.indexOf('--output-metadata') + 1];
    writeFileSync(path, JSON.stringify({tests: {'main.mbt': [
      {index: 0, name: 'original', attrs: [], line_number: 1},
    ]}}));
    return '';
  };
  const selected = nativeCoreTestSelection(root, ['--release'], {execute,
    partitionProfiles: true, ordinaryPartitions: true});
  assert.equal(generated, 2);
  assert.equal(selected.profiles.ordinary.cases, 2);
  assert.deepEqual(selected.profiles.ordinary.partitions.map(p => p.cases), [1, 1]);
  assert.deepEqual(selected.profiles.ordinary.partitions.flatMap(p => p.args.slice(1)).sort(), ['active', 'empty']);
  assert(selected.profiles.ordinary.partitions.every(p => p.drivers.length === 1));
});

test('Native compiler partition rejects foreign overlapping omitted and changed actual driver selections', t => {
  const root = fixture(t);
  const command = name => ['moon', 'generate-test-driver', '--output-driver', '_build/'+name+'/driver.mbt',
    '--output-metadata', '_build/'+name+'/info.json', name+'/main.mbt', '--target', 'native',
    '--pkg-name', 'fixture/'+name, '--driver-kind', 'blackbox'].join(' ');
  for (const mode of ['foreign', 'omitted', 'changed']) {
    const execute = (_tool, values) => {
      if (values[0] === 'test') {
        const paths = ['active', 'empty'].filter(name => values.includes(name));
        if (paths.length === 1) return mode === 'foreign' ? [command('active'), command('empty')].join('\n')
          : mode === 'omitted' ? '' : command(paths[0]).replace('/main.mbt', '/changed.mbt');
        return [command('active'), command('empty')].join('\n');
      }
      writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({tests: {
        'main.mbt': [{index: 0, name: 'original', attrs: [], line_number: 1}],
      }}));
      return '';
    };
    assert.throws(() => nativeCoreTestSelection(root, ['--release'], {execute,
      partitionProfiles: true, ordinaryPartitions: true}),
    /foreign or nested|overlapping|No compiler-owned|changed original compiler/u, mode);
  }
});

test('actual Native compiler partition isolates nested package drivers using original parent file inputs', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-nested-partition-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_nested"\nversion = "0.0.0"\n');
  for (const directory of ['src/parent', 'src/parent/child', 'src/other']) {
    mkdirSync(join(root, directory), {recursive: true});
    writeFileSync(join(root, directory, 'moon.pkg'), '');
    writeFileSync(join(root, directory, 'main.mbt'), 'test "original case" { assert_eq(7, 7) }\n');
  }
  mkdirSync(join(root, 'src/other/testless-child'), {recursive: true});
  writeFileSync(join(root, 'src/other/testless-child/moon.pkg'), '');
  writeFileSync(join(root, 'src/other/testless-child/main.mbt'), 'pub fn answer() -> Int { 7 }\n');
  const full = nativeCoreTestSelection(root, ['--release'], {partitionProfiles: true});
  assert.equal(full.profiles.ordinary.cases, 3);
  assert(!full.profiles.ordinary.args.includes('src/parent'));
  assert(!full.profiles.ordinary.args.includes('src/other'));
  const selected = nativeCoreTestSelection(root, ['--release'], {
    partitionProfiles: true, ordinaryPartitions: true,
  });
  const parts = selected.profiles.ordinary.partitions;
  assert.equal(selected.profiles.ordinary.cases, 3);
  assert.equal(parts.reduce((sum, p) => sum + p.cases, 0), 3);
  assert.deepEqual(parts.flatMap(p => p.args.slice(1)).sort(), full.profiles.ordinary.args.slice(1).sort());
  assert(!parts.some(p => p.args.includes('src/parent')));
  assert(!parts.some(p => p.args.includes('src/other')));
  assert.equal(parts.filter(p => p.args.includes('src/parent/main.mbt')).length, 1);
  const drivers = parts.flatMap(p => p.drivers);
  assert.equal(new Set(drivers).size, drivers.length);
  assert(parts.every(p => p.cases > 0));
});

test('Native compiler partition retains empty sibling drivers only for the same assigned original package', t => {
  const root = fixture(t);
  const command = (name, kind) => ['moon', 'generate-test-driver', '--output-driver', `_build/${name}/${kind}.mbt`,
    '--output-metadata', `_build/${name}/${kind}.json`, ...(kind === 'internal' ? [] : [name+'/main.mbt']),
    '--target', 'native', '--pkg-name', 'fixture/'+name, '--driver-kind', kind].join(' ');
  const execute = (_tool, values) => {
    if (values[0] === 'test') {
      const paths = ['active', 'empty'].filter(name => values.includes(name));
      return (paths.length ? paths : ['active', 'empty']).flatMap(name =>
        ['internal', 'blackbox'].map(kind => command(name, kind))).join('\n');
    }
    const kind = values[values.indexOf('--driver-kind') + 1];
    writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({tests:
      kind === 'internal' ? {} : {'main.mbt': [{index: 0, name: 'original', attrs: [], line_number: 1}]}}));
    return '';
  };
  const selection = nativeCoreTestSelection(root, ['--release'], {execute,
    partitionProfiles: true, ordinaryPartitions: true});
  assert.equal(selection.profiles.ordinary.cases, 2);
  assert(selection.profiles.ordinary.partitions.every(p => p.cases === 1 && p.drivers.length === 2));
  const drivers = selection.profiles.ordinary.partitions.flatMap(p => p.drivers);
  assert.equal(drivers.length, 4); assert.equal(new Set(drivers).size, 4);
});

test('Native metadata selection retains opaque doc/skip identities and refuses a changed selected inventory', t => {
  const root = fixture(t), args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'];
  const command = name => ['moon', 'generate-test-driver', '--output-driver', '_build/'+name+'/driver.mbt',
    '--output-metadata', '_build/'+name+'/info.json', name+'/main.mbt', '--target', 'native',
    '--pkg-name', 'fixture/'+name, '--driver-kind', 'blackbox'].join(' ');
  for (const changed of [false, true]) {
    let generated = 0;
    const execute = (tool, values, options) => {
      assert.equal(tool, 'moon');assert.equal(options.cwd, root);
      assert(options.timeout > 0 && options.timeout <= 60000);
      if (values[0] === 'test') {
        assert.deepEqual(values.slice(0, 3), ['test', '--target', 'native']);
        const selected = values.includes('active');
        return (selected ? [command(changed ? 'empty' : 'active')]
          : [command('active'), command('empty'), 'cc must-never-execute.c']).join('\n');
      }
      assert.equal(values[0], 'generate-test-driver');generated++;
      const name = values.includes('empty/main.mbt') ? 'empty' : 'active';
      const expected = command(name).split(' ').slice(1);
      const output = values[values.indexOf('--output-driver') + 1];
      const path = resolve(root, values[values.indexOf('--output-metadata') + 1]);
      assert.notEqual(output, expected[expected.indexOf('--output-driver') + 1]);
      assert.equal(basename(output), 'driver.mbt');
      assert.equal(dirname(output), dirname(path));
      const actual = [...values];
      for (const option of ['--output-driver', '--output-metadata']) {
        actual[actual.indexOf(option) + 1] = expected[expected.indexOf(option) + 1];
      }
      assert.deepEqual(actual, expected, 'Only discovery output destinations may change');
      mkdirSync(dirname(path), {recursive: true});
      writeFileSync(path, JSON.stringify({tests:{'main.mbt':name === 'empty' ? [] : [
        {index:0,name:null,attrs:[],line_number:2},
        {index:1,name:'original skipped case',attrs:['skip'],line_number:5},
      ]}}));
      return '';
    };
    if (changed) assert.throws(() => nativeCoreTestSelection(root, args, {execute}), /case identity or order/u);
    else assert.deepEqual(nativeCoreTestSelection(root, args, {execute}),
      {args:[...args,'active'],cases:2,packages:1,prunedDrivers:1});
    assert.equal(generated, 2);
  }
});

test('Native metadata discovery preserves original compiler failures and refuses zero cases', t => {
  const root = fixture(t), original = new Error('original metadata compiler refusal');
  assert.throws(() => nativeCoreTestSelection(root, [], {execute:()=>{throw original;}}), error=>error===original);
  let failedScratch;
  const command = ['moon','generate-test-driver','--output-driver','_build/active/driver.mbt',
    '--output-metadata','_build/active/info.json','active/main.mbt','--target','native',
    '--pkg-name','fixture/active','--driver-kind','blackbox'].join(' ');
  assert.throws(() => nativeCoreTestSelection(root, [], {execute: (_tool, values) => {
    if (values[0] === 'test') return command;
    failedScratch = dirname(dirname(values[values.indexOf('--output-metadata')+1]));
    throw original;
  }}), error=>error===original, 'A redirected compiler refusal remains the original exception');
  t.after(() => rmSync(failedScratch,{recursive:true,force:true}));
  assert.throws(() => nativeCoreTestSelection(root, [], {execute:()=>''}), /No compiler-owned Native test drivers/u);
});

test('portable metadata counts only runnable originals and never treats an empty driver as execution', t => {
  const root = fixture(t);
  const tests = [{index:0, name:null, attrs:[]}, {index:1, name:'skip', attrs:['skip']},
    {index:2, name:'bench', attrs:[]}];
  for (const target of ['js', 'wasm']) for (const entries of [[], tests.slice(1), tests]) {
    let generated = 0;
    const execute = (_tool, values) => {
      if (values[0] === 'test') {
        assert.deepEqual(values.slice(0, 3), ['test', '--target', target]);
        return ['moon', 'generate-test-driver', '--output-driver', '_build/driver.mbt',
          '--output-metadata', '_build/info.json', 'active/main.mbt', '--target', target,
          '--pkg-name', 'fixture/active', '--driver-kind', 'whitebox'].join(' ');
      }
      assert.equal(values[0], 'generate-test-driver'); generated++;
      writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({
        tests:{'main.mbt':entries}, with_bench_args_tests:{'main.mbt':entries.filter(test => test.index === 2)},
      }));
      return '';
    };
    assert.equal(portableMoonTestCount(root, ['active/main.mbt'], target, {execute}), entries === tests ? 1 : 0);
    assert.equal(generated, 1);
  }
  assert.equal(portableMoonTestCount(root, [], 'js', {execute:() => ''}), 0);
  assert.throws(() => portableMoonTestCount(root, [], 'native'));
});

test('Native metadata deadline funds all original preparation from one explicit caller envelope', t => {
  const root = fixture(t), timeouts = [], commands = [];
  let clock = 1000;
  const command = name => ['moon', 'generate-test-driver', '--output-driver', '_build/'+name+'/driver.mbt',
    '--output-metadata', '_build/'+name+'/info.json', name+'/main.mbt', '--target', 'native',
    '--pkg-name', 'fixture/'+name, '--driver-kind', 'blackbox'].join(' ');
  const execute = (tool, values, options) => {
    assert.equal(tool, 'moon'); timeouts.push(options.timeout); commands.push(values[0]);
    clock += 25_000;
    if (values[0] === 'test') {
      assert(values.includes('--dry-run'));
      const paths = ['active', 'empty'].filter(name => values.includes(name));
      return (paths.length ? paths : ['active', 'empty']).map(command).join('\n');
    }
    assert.equal(values[0], 'generate-test-driver');
    writeFileSync(values[values.indexOf('--output-metadata') + 1], JSON.stringify({tests: {
      'main.mbt': [{index:0, name:'same original', attrs:[], line_number:1}],
    }}));
    return '';
  };
  const selected = nativeCoreTestSelection(root, ['--release'], {execute, now:()=>clock,
    timeoutMs:300_000, partitionProfiles:true, ordinaryPartitions:true});
  assert.deepEqual(commands, ['test', 'generate-test-driver', 'generate-test-driver', 'test', 'test', 'test']);
  assert.deepEqual(timeouts, [300_000, 275_000, 250_000, 225_000, 200_000, 175_000]);
  assert.equal(clock - 1000, 150_000, 'A complete valid preparation may exceed the old one-minute envelope');
  assert.equal(selected.cases, 2);
  assert.deepEqual(selected.profiles.ordinary.partitions.map(part => part.cases), [1, 1]);
  const drivers = selected.profiles.ordinary.partitions.flatMap(part => part.drivers);
  assert.equal(drivers.length, 2); assert.equal(new Set(drivers).size, 2);
});

test('Native metadata deadline rejects invalid expired and backwards budgets before child work', t => {
  const root = fixture(t);
  let calls = 0;
  const execute = () => {calls++;throw new Error('MustNotExecute');};
  for (const timeoutMs of [0, -1, 0.5, NaN, Infinity, 2147483648, '300000']) {
    assert.throws(() => nativeCoreTestSelection(root, [], {execute, timeoutMs}), /finite positive timer/u);
  }
  for (const [times, expected] of [
    [[100, 200], /deadline exhausted/u], [[100, 99], /clock cannot move backwards/u],
  ]) assert.throws(() => nativeCoreTestSelection(root, [], {execute, timeoutMs:100,
    now:()=>times.shift()}), expected);
  assert.equal(calls, 0);
});

test('Native metadata deadline never refills across generated drivers or replaces compiler timeout', t => {
  const root = fixture(t), timeouts = [];
  let clock = 0, failedScratch;
  const command = ['moon','generate-test-driver','--output-driver','_build/active/driver.mbt',
    '--output-metadata','_build/active/info.json','active/main.mbt','--target','native',
    '--pkg-name','fixture/active','--driver-kind','blackbox'].join(' ');
  assert.throws(() => nativeCoreTestSelection(root, [], {now:()=>clock, execute:(_tool, values, options)=>{
    timeouts.push(options.timeout); clock += 30_000;
    if (values[0] === 'test') return command;
    failedScratch = dirname(dirname(values[values.indexOf('--output-metadata')+1]));
    writeFileSync(values[values.indexOf('--output-metadata')+1], JSON.stringify({tests:{'main.mbt':[]}}));
    return '';
  }}), /deadline exhausted/u);
  t.after(() => rmSync(failedScratch,{recursive:true,force:true}));
  assert.deepEqual(timeouts, [60_000, 30_000], 'The component default and remaining absolute deadline stay finite');
  const original = Object.assign(new Error('OriginalCompilerTimeout'), {code:'ETIMEDOUT', signal:'SIGTERM'});
  assert.throws(() => nativeCoreTestSelection(root, [], {timeoutMs:300_000,
    execute:()=>{throw original;}}), error=>error===original);
});

test('actual Native profile partition executes every original and both geometry configurations', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-test-profiles-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const directory = 'src/cmd/native_client';
  mkdirSync(join(root, directory), {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_profiles"\nversion = "0.0.0"\n');
  writeFileSync(join(root, directory, 'moon.pkg'), '');
  writeFileSync(join(root, directory, 'main.mbt'), 'pub fn answer() -> Int { 7 }\n');
  for (const [file, name] of [
    ['ordinary_wbtest.mbt', 'ordinary profile original'],
    ['local_command_business_cleanup_wbtest.mbt', 'physical profile original'],
    ['local_command_business_wbtest.mbt', 'both geometry configurations'],
  ]) writeFileSync(join(root, directory, file),
    `test "${name}" { assert_eq(answer(), 7) }\n`);
  const http = 'src/platform_native/http_client';
  mkdirSync(join(root, http), {recursive: true});
  writeFileSync(join(root, http, 'moon.pkg'), '');
  writeFileSync(join(root, http, 'main_wbtest.mbt'),
    'test "HTTP original with its own peer profile" { assert_eq(7, 7) }\n');
  const credential = 'src/platform_native/credential_resource';
  mkdirSync(join(root, credential), {recursive: true});
  writeFileSync(join(root, credential, 'moon.pkg'), '');
  for (const [file, name] of [
    ['ordinary_wbtest.mbt', 'credential ordinary sibling'],
    ['remote_use_retention_native_wbtest.mbt', 'credential retention peer original'],
    ['remote_initial_use_native_wbtest.mbt', 'credential initial peer original'],
  ]) writeFileSync(join(root, credential, file), `test "${name}" { assert_eq(7, 7) }\n`);
  const retained = 'src/platform_native/remote_resident_source_compute_tests';
  mkdirSync(join(root,retained),{recursive:true});
  writeFileSync(join(root,retained,'moon.pkg'),'');
  writeFileSync(join(root,retained,'retained_compute_wbtest.mbt'),
    'test "retained Provider original with its own peers" { assert_eq(7, 7) }\n');
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0'};
  const moon = join(env.MOON_HOME, 'bin/moon');
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose'];
  const selected = nativeCoreTestSelection(root, args, {env, partitionProfiles: true});
  assert.equal(selected.cases, 8);
  assert.deepEqual(selected.profiles.ordinary.args.slice(0, args.length), args);
  assert.deepEqual(new Set(selected.profiles.ordinary.args.slice(args.length)), new Set([
    directory+'/ordinary_wbtest.mbt', directory+'/local_command_business_wbtest.mbt',
    credential+'/ordinary_wbtest.mbt']));
  assert.equal(selected.profiles.ordinary.cases, 3);
  assert.deepEqual(selected.profiles.http.args.slice(0, args.length), args);
  assert.deepEqual(new Set(selected.profiles.http.args.slice(args.length)),
    new Set([http, ...nativeCoreHttpTestFiles]));
  assert.equal(selected.profiles.http.cases, 3);
  assert.deepEqual(selected.profiles.source, {args: [...args, retained], cases: 1});
  assert.deepEqual(selected.profiles.scoped, {
    args: [...args, directory+'/local_command_business_wbtest.mbt',
      directory+'/local_command_business_cleanup_wbtest.mbt'], cases: 2, tests: [
      {source: directory+'/local_command_business_wbtest.mbt', index: 0},
      {source: directory+'/local_command_business_cleanup_wbtest.mbt', index: 0},
    ],
  });
  assert.equal(selected.profiles.physicalCases, 1);
  assert.equal(selected.profiles.repeatedGeometryCases, 1);
  assert.equal(selected.profiles.uniqueCases, 8);
  // These tiny programs test real compiler file selection, not a provider or
  // physical acceptance. A case count alone cannot detect equal-sized swaps.
  const execute = profile => {
    const result = spawnSync(moon, ['test', '--target', 'native', ...profile.args],
      {cwd: root, env, encoding: 'utf8', timeout: 30000, maxBuffer: 2*1024**2});
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(assertTestExecution('moon', moon,
      ['test', '--target', 'native', ...profile.args], result).counts.passed, profile.cases);
    return result.stdout;
  };
  const ordinary = execute(selected.profiles.ordinary);
  assert.match(ordinary, /ordinary profile original/u);
  assert.match(ordinary, /both geometry configurations/u);
  assert.doesNotMatch(ordinary, /physical profile original/u);
  assert.doesNotMatch(ordinary, /HTTP original|credential (?:initial|retention) peer original/u);
  assert.match(ordinary, /credential ordinary sibling/u);
  const transport = execute(selected.profiles.http);
  assert.match(transport, /HTTP original with its own peer profile/u);
  assert.match(transport, /credential initial peer original/u);
  assert.match(transport, /credential retention peer original/u);
  assert.doesNotMatch(transport, /credential ordinary sibling/u);
  assert.doesNotMatch(transport, /ordinary profile original|both geometry configurations|physical profile original/u);
  const retainedOutput=execute(selected.profiles.source);
  assert.match(retainedOutput,/retained Provider original with its own peers/u);
  assert.doesNotMatch(retainedOutput,/ordinary profile original|both geometry configurations|physical profile original|HTTP original/u);
  assert.doesNotMatch(ordinary,/retained Provider original/u);
  const scoped = selected.profiles.scoped.tests.map(test => execute({
    args: [...args, test.source, '--index', String(test.index)], cases: 1,
  })).join('\n');
  assert.match(scoped, /physical profile original/u);
  assert.match(scoped, /both geometry configurations/u);
  assert.doesNotMatch(scoped, /ordinary profile original/u);
});

test('actual Native package selection preserves full WB/BB/inline/doc outline and execution while omitting an empty executable', t => {
  const root = fixture(t);
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_selection"\nversion = "0.0.0"\n');
  writeFileSync(join(root, 'active/moon.pkg'), '');
  writeFileSync(join(root, 'active/main.mbt'),
    '/// ```mbt check\n/// test { assert_eq(@active.answer(), 7) }\n/// ```\n' +
    'pub fn answer() -> Int { 7 }\ntest "inline original" { assert_eq(answer(), 7) }\n');
  writeFileSync(join(root, 'active/original_wbtest.mbt'), 'test "WB original" { assert_eq(answer(), 7) }\n');
  writeFileSync(join(root, 'active/original_test.mbt'), 'test "BB original" { assert_eq(@active.answer(), 7) }\n');
  writeFileSync(join(root, 'empty/moon.pkg'), 'pkgtype(kind: "executable")\n');
  writeFileSync(join(root, 'empty/main.mbt'), 'fn main { println("no test cases") }\n');
  const env = {...process.env, MOONBIT_NEW_NATIVE:'0'};
  const moon = join(env.MOON_HOME, 'bin/moon');
  const args = ['--deny-warn','--release','--strip','-j','2','--no-parallelize'];
  const run = values => {
    const result = spawnSync(moon, ['test','--target','native',...values],
      {cwd:root,env,encoding:'utf8',timeout:30000,maxBuffer:2*1024**2});
    assert.ifError(result.error);assert.equal(result.signal,null);
    assert.equal(result.status,0,result.stderr);return result;
  };
  const full = run([...args,'--target-dir',join(root,'full-outline'),'--outline']);
  const selected = nativeCoreTestSelection(root, args, {env});
  assert.equal(selected.cases,4);assert.equal(selected.packages,1);assert.equal(selected.prunedDrivers,2);
  assert.deepEqual(selected.args,[...args,'active']);
  const profiled = nativeCoreTestSelection(root, args, {env, partitionProfiles: true});
  assert.deepEqual(profiled.profiles, {
    ordinary: {args: selected.args, cases: 4},
    http: {args: null, cases: 0},
    source: {args: null, cases: 0},
    scoped: {args: null, cases: 0, tests: []},
    physicalCases: 0, repeatedGeometryCases: 0, uniqueCases: 4,
  });
  const outline = run([...selected.args,'--outline']);
  assert.equal(outline.stdout,full.stdout,'compiler-owned outline identity and order must remain exact');
  const actual = run(selected.args);
  const checked = assertTestExecution('moon',moon,['test','--target','native',...selected.args],actual);
  assert.equal(checked.counts.passed,4);
  const files = path => readdirSync(path,{withFileTypes:true}).flatMap(entry => entry.isDirectory()
    ? files(join(path,entry.name)) : [join(path,entry.name)]);
  const built = files(join(root,'_build/native/release/test'));
  assert.equal(built.filter(path=>path.endsWith('.exe')).length,3);
  // Full discovery deliberately emits metadata for the omitted package, but
  // the selected build must never compile/link its empty driver.
  assert.equal(built.some(path=>path.includes('/empty/') && /\.(?:c|core|exe)$/u.test(path)),false);
  assert(existsSync(join(root,'full-outline/native/release/test/empty/empty.blackbox_test.exe')));
  // Warm every driver, including the empty package, in the SAME target dir.
  // Discovery must still enumerate all original cases and the omitted drivers.
  assert.equal(run([...args,'--outline']).stdout,full.stdout);
  const drivers = files(join(root,'_build/native/release/test')).filter(path => /\.(?:mbt|json)$/u.test(path));
  assert(drivers.length > 0, 'Actual warm test drivers and metadata required');
  const identities = paths => paths.map(path => {
    const stat = statSync(path, {bigint:true});
    return {path, bytes:stat.size, inode:stat.ino, mtime:stat.mtimeNs,
      sha256:createHash('sha256').update(readFileSync(path)).digest('hex')};
  });
  const before = identities(drivers);
  assert.deepEqual(nativeCoreTestSelection(root,args,{env}),selected);
  assert.deepEqual(identities(drivers),before,'Metadata-only discovery must not rewrite warm actual Native drivers or metadata');
  const software = files(join(root,'_build/native/release/test')).filter(path => /\.(?:c|core|exe)$/u.test(path));
  const warm = identities(software);
  assert.equal(run([...selected.args,'--outline']).stdout,full.stdout);
  assert.deepEqual(identities(software),warm,'The warm outline must not regenerate or recompile Native software');
});


test('actual Native compiler retains benchmark declarations without counting them as executed tests', t => {
  const root = fixture(t);
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_benchmark_class"\nversion = "0.0.0"\n');
  writeFileSync(join(root, 'active/moon.pkg'), 'import { "moonbitlang/core/bench" } for "wbtest"\n');
  writeFileSync(join(root, 'active/main.mbt'), 'pub fn answer() -> Int { 7 }\n');
  writeFileSync(join(root, 'active/original_wbtest.mbt'),
    'test "ordinary original" { assert_eq(answer(), 7) }\n' +
    'test "compiler benchmark declaration" (it : @bench.T) { it.bench(fn() { it.keep(answer()) }) }\n');
  writeFileSync(join(root, 'empty/moon.pkg'), 'pkgtype(kind: "executable")\n');
  writeFileSync(join(root, 'empty/main.mbt'), 'fn main { println("no tests") }\n');
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0'};
  const moon = join(env.MOON_HOME, 'bin/moon');
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose'];
  const selected = nativeCoreTestSelection(root, args, {env, partitionProfiles: true});
  assert.equal(selected.cases, 2);
  assert.equal(selected.benchmarkDeclarations, 1);
  assert.deepEqual(selected.args, [...args, 'active']);
  assert.equal(selected.profiles.uniqueCases, 2);
  assert.equal(selected.profiles.benchmarkDeclarations, 1);
  assert.deepEqual(selected.profiles.ordinary, {args: selected.args, cases: 1});
  const actual = spawnSync(moon, ['test', '--target', 'native', ...selected.profiles.ordinary.args],
    {cwd: root, env, encoding: 'utf8', timeout: 30_000});
  const observed = assertTestExecution('moon', moon, ['test', '--target', 'native',
    ...selected.profiles.ordinary.args], actual, {expectedTests: 1});
  assert.equal(observed.counts.tests, 1);
  assert.equal(observed.counts.passed, 1);
  assert.match(actual.stdout, /ordinary original/u);
  assert.doesNotMatch(actual.stdout, /compiler benchmark declaration/u);
});


test('Core HTTP arguments retain only the existing credential peer callers and Native target', () => {
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
    'src/platform_native/http_client', ...nativeCoreHttpTestFiles];
  assert.equal(nativeCoreHttpArguments(args), args);
  assert.deepEqual(nativeCoreHttpArguments(nativeCoreHttpTestFiles), nativeCoreHttpTestFiles);
  for (const invalid of [[], ['src/platform_native/credential_resource'],
    ['src/platform_native/http_client', 'src/platform_native/client_host'],
    ['src/platform_native/http_client', 'src/platform_native/http_client'],
    ['--target', 'native', 'src/platform_native/http_client'], [null]])
    assert.throws(() => nativeCoreHttpArguments(invalid));
});


test('Native physical consumers retain scoped file/index identities and exclude ordinary profile', t => {
  for (const [directory, file, cases, profile] of [
    ['src/platform_native/installed_arena_control', 'request_source_frame_physical_scoped_wbtest.mbt', 2, 'scoped-review-values'],
    ['src/platform_native/installed_arena_control', 'owned_body_extent_physical_scoped_wbtest.mbt', 3, 'scoped-review-values'],
    ['src/cmd/native_client', 'local_project_mock_request_physical_scoped_wbtest.mbt', 2, 'runtime-values'],
    ['src/cmd/native_client', 'local_effect_capture_wbtest.mbt', 5, 'runtime-values'],
    ['src/cmd/native_client', 'local_project_mock_content_physical_scoped_wbtest.mbt', 4, 'runtime-values'],
    ['src/platform_native/row_source', 'target_io_physical_scoped_wbtest.mbt', 4, 'scoped-review-values'],
    ['src/platform_native/row_source', 'target_io_lineage_physical_scoped_wbtest.mbt', 3, 'scoped-review-values'],
    ['src/platform_native/client_host', 'run_effect_file_response_wbtest.mbt', 4, 'scoped-review-values'],
  ]) {
    const root = fixture(t);
    const indexes = Array.from({length: cases}, (_, index) => index);
    const ordinaryFile = file === 'target_io_physical_scoped_wbtest.mbt'
      ? 'target_io_physical_foreign_wbtest.mbt' : 'ordinary_wbtest.mbt';
    mkdirSync(join(root, directory), {recursive: true});
    for (const name of [file, ordinaryFile]) writeFileSync(join(root, directory, name), 'test {}\n');
    const command = ['moon', 'generate-test-driver', '--output-driver', '_build/driver.mbt',
      '--output-metadata', '_build/info.json', directory+'/'+file, directory+'/'+ordinaryFile,
      '--target', 'native', '--pkg-name', 'fixture/installed_arena_control', '--driver-kind', 'whitebox'].join(' ');
    const execute = (tool, args) => {
      assert.equal(tool, 'moon');
      if (args[0] === 'test') return command;
      assert.equal(args[0], 'generate-test-driver');
      const output = resolve(root, args[args.indexOf('--output-metadata')+1]);
      mkdirSync(dirname(output), {recursive: true});
      writeFileSync(output, JSON.stringify({tests: {
        [file]: indexes.map(index => ({index, name:'Source original '+index, attrs:[], line_number:index+1})),
        [ordinaryFile]: [{index:0, name:'ordinary sibling', attrs:[], line_number:1}],
      }}));
      return '';
    };
    const selected = nativeCoreTestSelection(root, ['--release'], {execute, partitionProfiles:true});
    assert.deepEqual(selected.profiles.scoped, {
      args:['--release', directory+'/'+file], cases,
      tests:indexes.map(index => ({source:directory+'/'+file, index})),
    });
    assert.deepEqual(selected.profiles.ordinary, {
      args:['--release', directory+'/'+ordinaryFile], cases:1,
    });
    assert.equal(selected.profiles.physicalCases, cases);
    assert.equal(selected.profiles.uniqueCases, cases + 1);
    assert.equal(nativeCoreScopedAllocationProfile(directory+'/'+file), profile);
  }
});

test('Native Project Mock real Read keeps its selected provider out of ordinary command tests', () => {
  const physical = 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt';
  assert.equal(nativeScopedTestFiles.filter(source => source === physical).length, 1);
  assert.equal(nativeCoreScopedAllocationProfile(physical), 'runtime-values');
  assert.equal(nativeScopedTestFiles.includes('src/cmd/native_client/local_project_configuration_wbtest.mbt'), false);
});

test('Native initial CID and signing counters select every original case in runtime-values only', t => {
  const directory = 'src/platform_native/client_host';
  const cid = directory + '/local_initial_configuration_cid_wbtest.mbt';
  const signing = directory + '/local_initial_host_signing_original_wbtest.mbt';
  const ordinary = directory + '/ordinary_wbtest.mbt';
  // Compiler-owned discovery must retain later authored cases without a pinned
  // signing-case count in either the environment selector or the driver.
  for (const signingCases of [4, 6]) {
    const root = fixture(t);
    mkdirSync(join(root, directory), {recursive: true});
    for (const source of [cid, signing, ordinary]) writeFileSync(join(root, source), 'test {}\n');
    const command = ['moon', 'generate-test-driver', '--output-driver', '_build/driver.mbt',
      '--output-metadata', '_build/info.json', cid, signing, ordinary, '--target', 'native',
      '--pkg-name', 'fixture/client_host', '--driver-kind', 'whitebox'].join(' ');
    const entries = (count, name) => Array.from({length: count}, (_, index) =>
      ({index, name: name + index, attrs: [], line_number: index + 1}));
    const execute = (tool, args) => {
      assert.equal(tool, 'moon');
      if (args[0] === 'test') return command;
      assert.equal(args[0], 'generate-test-driver');
      const output = resolve(root, args[args.indexOf('--output-metadata') + 1]);
      mkdirSync(dirname(output), {recursive: true});
      writeFileSync(output, JSON.stringify({tests: {
        [basename(cid)]: entries(2, 'CID original '),
        [basename(signing)]: entries(signingCases, 'signing original '),
        [basename(ordinary)]: entries(1, 'ordinary original '),
      }}));
      return '';
    };
    const selected = nativeCoreTestSelection(root, ['--release'], {execute, partitionProfiles: true});
    const expected = [cid, signing].flatMap(source =>
      Array.from({length: source === cid ? 2 : signingCases}, (_, index) => ({source, index})));
    assert.deepEqual(selected.profiles.scoped.tests, expected);
    assert.equal(new Set(expected.map(item => JSON.stringify(item))).size, 2 + signingCases);
    assert.equal(selected.profiles.scoped.cases, 2 + signingCases);
    assert.equal(selected.profiles.uniqueCases, 3 + signingCases);
    assert.deepEqual(selected.profiles.ordinary, {args: ['--release', ordinary], cases: 1});
    for (const original of selected.profiles.scoped.tests) {
      assert.equal(nativeScopedTestFiles.filter(source => source === original.source).length, 1);
      assert.equal(nativeCoreScopedAllocationProfile(original.source), 'runtime-values');
      assert.deepEqual(nativeCoreScopedTestEnvironment(original), {ACTQL_NATIVE_TIMINGS: '1'});
    }
    assert.deepEqual(nativeCoreScopedTestEnvironment({source: ordinary, index: 0}), {});
    assert.deepEqual(nativeCoreScopedTestEnvironment({source: cid + '.foreign', index: 0}), {});
  }
  const mock = 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt';
  assert.deepEqual(nativeCoreScopedTestEnvironment({source: mock, index: 13}), {ACTQL_NATIVE_TIMINGS: '1'});
  for (const index of [0, 12, 14]) assert.deepEqual(nativeCoreScopedTestEnvironment({source: mock, index}), {});
});
