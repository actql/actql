import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
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
      const path = join(root, values[values.indexOf('--output-metadata') + 1]);
      mkdirSync(dirname(path), {recursive: true});
      writeFileSync(path, JSON.stringify({tests:{'main.mbt':path.includes('/empty/') ? [] : [
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
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0'};
  const moon = join(env.MOON_HOME, 'bin/moon');
  const args = ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose'];
  const selected = nativeCoreTestSelection(root, args, {env, partitionProfiles: true});
  assert.equal(selected.cases, 3);
  assert.deepEqual(selected.profiles, {
    ordinary: {args: [...args, directory+'/ordinary_wbtest.mbt',
      directory+'/local_command_business_wbtest.mbt'], cases: 2},
    scoped: {args: [...args, directory+'/local_command_business_wbtest.mbt',
      directory+'/local_command_business_cleanup_wbtest.mbt'], cases: 2},
    physicalCases: 1, repeatedGeometryCases: 1, uniqueCases: 3,
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
  const scoped = execute(selected.profiles.scoped);
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
    scoped: {args: null, cases: 0},
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
  assert.deepEqual(nativeCoreTestSelection(root,args,{env}),selected);
});
