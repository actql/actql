import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {nativeCoreCArguments, nativeCoreCCompiler} from './native-core-c-compiler.mjs';

test('Native Core C profile changes only the default optimization of one generated release test input', () => {
  const root = '/original';
  for (const kind of ['whitebox', 'blackbox', 'internal']) {
    const input = `${root}/_build/native/release/test/pkg/pkg.${kind}_test.c`;
    const args = ['-o', 'original.exe', '-fwrapv', '-fno-strict-aliasing',
      '-O2', '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', input, 'original.a', '-lm'];
    assert.deepEqual(nativeCoreCArguments(root, args), args.map(x => x === '-O2' ? '-O0' : x));
  }
  for (const args of [
    ['-O2', '/original/_build/native/release/build/pkg/pkg.c'],
    ['-O2', '/original/src/platform_native/original_stub.c'],
    ['-O2', '/foreign/_build/native/release/test/pkg/pkg.whitebox_test.c'],
    ['-O2', '/original/_build/native/debug/test/pkg/pkg.whitebox_test.c'],
    ['-O2', '/original/_build/native/release/test/pkg/original_stub.c'],
    ['-O3', '/original/_build/native/release/test/pkg/pkg.whitebox_test.c'],
    ['-O1', '/original/_build/native/release/test/pkg/pkg.whitebox_test.c'],
    ['-O0', '-O2', '/original/_build/native/release/test/pkg/pkg.whitebox_test.c'],
    ['-O2', '/original/_build/native/release/test/pkg/pkg.whitebox_test.c', '/original/src/stub.c'],
    ['--version'],
  ]) assert.strictEqual(nativeCoreCArguments(root, args), args);
});

test('Native Core compiler PATH routing retains package C++/stub drivers and the original mimalloc runtime plan', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-cc-routing-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['plain', 'custom', 'scratch']) mkdirSync(join(root, name));
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/compiler_profile"\nversion = "0.0.0"\n');
  writeFileSync(join(root, 'plain/moon.pkg'), '');
  const driver = fileURLToPath(new URL('native-cxx-link-driver.sh', import.meta.url));
  writeFileSync(join(root, 'custom/moon.pkg'), 'options("native-stub": ["helper.c"], link: {"native": {' +
    '"cc": ' + JSON.stringify(driver) + ', "stub-cc": "c++", "cc-flags": "-O2"}})\n');
  writeFileSync(join(root, 'custom/helper.c'), 'int original_stub(void) { return 1; }\n');
  for (const name of ['plain', 'custom']) writeFileSync(join(root, name, 'main.mbt'),
    'test "original selection" { assert_eq(1, 1) }\n');
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0'};
  delete env.MOON_CC;delete env.MOONBIT_ALLOCATOR;delete env.CXX;
  const plan = profile => {
    const result = spawnSync(join(env.MOON_HOME, 'bin/moon'),
      ['test', '--target', 'native', '--release', '--strip', '--dry-run'],
      {cwd: root, env: {...env, ...profile}, encoding: 'utf8', timeout: 10000, maxBuffer: 2 * 1024 ** 2});
    assert.ifError(result.error);assert.equal(result.status, 0, result.stderr);
    const lines = result.stdout.split('\n');
    const command = lines.find(line => line.includes('/plain/plain.internal_test.c') && !line.includes('moonc'));
    assert(command);assert(command.includes('libmoonbitrun.o'));
    assert(command.includes('MOONBIT_ALLOCATOR_MIMALLOC'));
    return {command, overrides: lines.filter(line =>
      line.includes(driver + ' ') || line.includes('c++ ') && line.includes('helper'))};
  };
  const original = plan({}), profile = nativeCoreCCompiler(root, join(root, 'scratch'), env);
  const actual = plan(profile);
  assert(actual.command.includes('test-c-compiler/cc '));
  assert.equal(actual.command.slice(actual.command.indexOf(' ')),
    original.command.slice(original.command.indexOf(' ')));
  assert(actual.overrides.length > 0);
  const stub = lines => lines.find(line => line.includes('/custom/helper.o '));
  const originalStub = stub(original.overrides), actualStub = stub(actual.overrides);
  assert(originalStub && actualStub);
  assert.match(actualStub.slice(0, actualStub.indexOf(' ')), /test-c-compiler\/c\+\+$/u);
  assert.equal(actualStub.slice(actualStub.indexOf(' ')), originalStub.slice(originalStub.indexOf(' ')),
    'the C++ launcher retains every original stub flag and runtime input');
  assert.deepEqual(actual.overrides.filter(line => line !== actualStub),
    original.overrides.filter(line => line !== originalStub), 'the package link driver and all its arguments remain selected');
});

test('Native Core C launcher preserves compiler arguments, original environment and failure status', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "actql-native-cc-'original-")));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const tools = join(root, 'original tools'), scratch = join(root, 'scratch');
  mkdirSync(tools);mkdirSync(scratch);
  const compiler = join(tools, 'cc');
  writeFileSync(compiler, '#!' + process.execPath + '\n' +
    'console.log(JSON.stringify({args:process.argv.slice(2),allocator:process.env.MOONBIT_ALLOCATOR,' +
    'current:process.env.ACTQL_FIXTURE_CURRENT}));process.exit(7);\n');
  chmodSync(compiler, 0o700);
  writeFileSync(join(tools, 'ar'), '#!' + process.execPath + '\nprocess.exit(7);\n', {mode: 0o700});
  const env = {...process.env, PATH: tools + delimiter + process.env.PATH,
    MOONBIT_ALLOCATOR: 'mimalloc', ACTQL_FIXTURE_CURRENT: 'same-original'};
  delete env.MOON_CC;
  const profile = nativeCoreCCompiler(root, scratch, env);
  assert.deepEqual(Object.keys(profile), ['PATH']);
  assert.equal(profile.PATH.split(delimiter)[1], tools);
  for (const input of ['_build/native/release/test/pkg/pkg.whitebox_test.c',
    '_build/native/release/build/pkg/pkg.c', 'src/original_stub.c']) {
    const args = ['-fwrapv', '-O2', join(root, input), '-Wl,--start-group', 'original.a', '-Wl,--end-group'];
    const result = spawnSync('cc', args, {cwd: root, env: {...env, ...profile},
      encoding: 'utf8', timeout: 5000});
    assert.ifError(result.error);assert.equal(result.signal, null);
    assert.equal(result.status, 7, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), {args: nativeCoreCArguments(root, args),
      allocator: 'mimalloc', current: 'same-original'});
  }
  assert.equal(readFileSync(compiler, 'utf8').includes('process.exit(7)'), true);
  assert.deepEqual(nativeCoreCCompiler(root, scratch, {...env, MOON_CC: compiler}), {});
});

test('actual package C++ driver deoptimizes only generated release test C and retains optimized C++ stubs and product C', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-core-cxx-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const scratch = join(root, 'scratch'), testDirectory = join(root, '_build/native/release/test/pkg'),
    productDirectory = join(root, '_build/native/release/build/pkg');
  for (const path of [scratch, testDirectory, productDirectory]) mkdirSync(path, {recursive: true});
  const env = {...process.env}; delete env.MOON_CC; delete env.CXX;
  const profile = nativeCoreCCompiler(root, scratch, env);
  assert.equal(existsSync(join(profile.PATH.split(delimiter)[0], 'c++')), true);
  const driver = fileURLToPath(new URL('native-cxx-link-driver.sh', import.meta.url));
  const stub = join(root, 'original.cpp'), object = join(root, 'original.o');
  writeFileSync(stub, '#ifndef __OPTIMIZE__\n#error original C++ stub must stay optimized\n#endif\n' +
    '#include <sstream>\nextern "C" int original_stub(void) { std::ostringstream out; out << 7; return out.str().size() == 1 ? 7 : 0; }\n');
  const compile = spawnSync('c++', ['-O2', '-c', stub, '-o', object],
    {cwd: root, env: {...env, ...profile}, encoding: 'utf8', timeout: 10000});
  assert.ifError(compile.error); assert.equal(compile.signal, null); assert.equal(compile.status, 0, compile.stderr);
  for (const [directory, optimized] of [[testDirectory, false], [productDirectory, true]]) {
    const input = join(directory, optimized ? 'pkg.c' : 'pkg.whitebox_test.c'), executable = join(directory, 'original.exe');
    writeFileSync(input, (optimized ? '#ifndef' : '#ifdef') + ' __OPTIMIZE__\n#error wrong C optimization boundary\n#endif\n' +
      'extern int original_stub(void);\nint main(void) { return original_stub() == 7 ? 0 : 1; }\n');
    const linked = spawnSync(driver, ['-O2', input, object, '-o', executable],
      {cwd: root, env: {...env, ...profile}, encoding: 'utf8', timeout: 10000});
    assert.ifError(linked.error); assert.equal(linked.signal, null); assert.equal(linked.status, 0, linked.stderr);
    const result = spawnSync(executable, [], {encoding: 'utf8', timeout: 5000});
    assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 0, result.stderr);
  }
  const explicitScratch = join(root, 'explicit'); mkdirSync(explicitScratch);
  const explicit = nativeCoreCCompiler(root, explicitScratch, {...env, CXX: '/selected/original-c++'});
  assert.equal(existsSync(join(explicit.PATH.split(delimiter)[0], 'c++')), false,
    'an explicitly selected C++ driver is never replaced');
});


test('Native Core compiler retains the logical compiler companion without realpath or PATH fallback', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-core-ar-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const selected = join(root, 'selected tools'), original = join(root, 'real compiler'),
    unrelated = join(root, 'other tools'), scratch = join(root, 'scratch'), missing = join(root, 'missing');
  for (const directory of [selected, original, unrelated, scratch, missing]) mkdirSync(directory);
  const compiler = join(original, 'compiler');
  writeFileSync(compiler, '#!' + process.execPath + '\nthrow new Error("archive routing must not invoke cc");\n', {mode: 0o700});
  symlinkSync(compiler, join(selected, 'cc'));
  for (const [path, tool] of [[join(selected, 'archiver'), 'selected companion'],
    [join(original, 'ar'), 'realpath decoy'], [join(unrelated, 'ar'), 'PATH decoy']]) {
    writeFileSync(path, '#!' + process.execPath + '\n' +
      'console.log(JSON.stringify({tool:' + JSON.stringify(tool) + ',args:process.argv.slice(2)}));\n' +
      'if(process.argv.includes("--fail")){process.stderr.write("original archive refusal\\n");process.exit(7);}',
    {mode: 0o700});
  }
  symlinkSync(join(selected, 'archiver'), join(selected, 'ar'));
  const env = {...process.env, PATH: [selected, unrelated, process.env.PATH].join(delimiter)};
  delete env.MOON_CC;
  const profile = nativeCoreCCompiler(root, scratch, env), directory = profile.PATH.split(delimiter)[0];
  assert.equal(lstatSync(join(directory, 'ar')).isSymbolicLink(), true);
  assert.equal(realpathSync(join(directory, 'ar')), realpathSync(join(selected, 'ar')));
  for (const args of [['rcs', 'original archive.a', 'same object.o'], ['--fail', 'original archive.a']]) {
    const result = spawnSync(join(directory, 'ar'), args, {env: {...env, ...profile},
      encoding: 'utf8', timeout: 5000});
    assert.ifError(result.error);assert.equal(result.signal, null);
    assert.equal(result.status, args.includes('--fail') ? 7 : 0);
    assert.deepEqual(JSON.parse(result.stdout), {tool: 'selected companion', args});
    assert.equal(result.stderr, args.includes('--fail') ? 'original archive refusal\n' : '');
  }
  rmSync(join(selected, 'ar'));
  assert.throws(() => nativeCoreCCompiler(root, missing, env), error =>
    error.code === 'ENOENT' && error.path === join(selected, 'ar'));
  assert.equal(existsSync(join(missing, 'test-c-compiler')), false);
  assert.deepEqual(nativeCoreCCompiler(root, missing, {...env, MOON_CC: compiler}), {});
});
