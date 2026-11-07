import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import test from 'node:test';
import {nativeCoreTestSelection, nativeCoreHttpArguments, nativeCoreHttpTestFiles,
  nativeCoreOrdinaryPartitions, nativeCorePartitionProfiles} from './native-core-test-selection.mjs';
import {assertTestExecution} from './test-execution.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-test-selection-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['active', 'empty']) {
    mkdirSync(join(root, name));
    writeFileSync(join(root, name, 'main.mbt'), 'Original explicit compiler-input fixture\n');
  }
  return root;
}

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

test('Native compiler discovery connects both partitions to unchanged original driver inputs without C compilation', t => {
  const root = fixture(t);
  const command = name => ['moon', 'generate-test-driver', '--output-driver', '_build/'+name+'/driver.mbt',
    '--output-metadata', '_build/'+name+'/info.json', name+'/main.mbt', '--target', 'native',
    '--pkg-name', 'fixture/'+name, '--driver-kind', 'blackbox'].join(' ');
  let generated = 0;
  const execute = (_tool, values) => {
    if (values[0] === 'test') return [command('active'), command('empty')].join('\n');
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


test('Source wrapper Native cases retain scoped file/index identities and exclude ordinary profile', t => {
  const root = fixture(t), directory = 'src/platform_native/installed_arena_control';
  const file = 'request_source_frame_physical_scoped_wbtest.mbt';
  mkdirSync(join(root, directory), {recursive: true});
  for (const name of [file, 'ordinary_wbtest.mbt']) writeFileSync(join(root, directory, name), 'test {}\n');
  const command = ['moon', 'generate-test-driver', '--output-driver', '_build/driver.mbt',
    '--output-metadata', '_build/info.json', directory+'/'+file, directory+'/ordinary_wbtest.mbt',
    '--target', 'native', '--pkg-name', 'fixture/installed_arena_control', '--driver-kind', 'whitebox'].join(' ');
  const execute = (tool, args) => {
    assert.equal(tool, 'moon');
    if (args[0] === 'test') return command;
    assert.equal(args[0], 'generate-test-driver');
    const output = resolve(root, args[args.indexOf('--output-metadata')+1]);
    mkdirSync(dirname(output), {recursive: true});
    writeFileSync(output, JSON.stringify({tests: {
      [file]: [0, 1].map(index => ({index, name:'Source original '+index, attrs:[], line_number:index+1})),
      'ordinary_wbtest.mbt': [{index:0, name:'ordinary sibling', attrs:[], line_number:1}],
    }}));
    return '';
  };
  const selected = nativeCoreTestSelection(root, ['--release'], {execute, partitionProfiles:true});
  assert.deepEqual(selected.profiles.scoped, {
    args:['--release', directory+'/'+file], cases:2,
    tests:[0, 1].map(index => ({source:directory+'/'+file, index})),
  });
  assert.deepEqual(selected.profiles.ordinary, {
    args:['--release', directory+'/ordinary_wbtest.mbt'], cases:1,
  });
  assert.equal(selected.profiles.physicalCases, 2);
  assert.equal(selected.profiles.uniqueCases, 3);
});
