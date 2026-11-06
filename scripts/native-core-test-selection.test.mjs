import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import test from 'node:test';
import {nativeCoreTestSelection} from './native-core-test-selection.mjs';
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
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0'};
  const moon = join(env.MOON_HOME, 'bin/moon');
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose'];
  const selected = nativeCoreTestSelection(root, args, {env, partitionProfiles: true});
  assert.equal(selected.cases, 4);
  assert.deepEqual(selected.profiles, {
    ordinary: {args: [...args, directory+'/ordinary_wbtest.mbt',
      directory+'/local_command_business_wbtest.mbt'], cases: 2},
    http: {args: [...args, http], cases: 1},
    scoped: {args: [...args, directory+'/local_command_business_wbtest.mbt',
      directory+'/local_command_business_cleanup_wbtest.mbt'], cases: 2, tests: [
      {source: directory+'/local_command_business_wbtest.mbt', index: 0},
      {source: directory+'/local_command_business_cleanup_wbtest.mbt', index: 0},
    ]},
    physicalCases: 1, repeatedGeometryCases: 1, uniqueCases: 4,
  });
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
  assert.doesNotMatch(ordinary, /HTTP original/u);
  const transport = execute(selected.profiles.http);
  assert.match(transport, /HTTP original with its own peer profile/u);
  assert.doesNotMatch(transport, /ordinary profile original|both geometry configurations|physical profile original/u);
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
