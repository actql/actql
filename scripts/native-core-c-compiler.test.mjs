import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {nativeCoreCArguments, nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import * as compilerModule from './native-core-c-compiler.mjs';
import {nativeRuntimeReaderCustodyFixture, nativeRuntimeReaderCustodyCacheInput} from './native-runtime-reader-custody-fixture.mjs';

test('the pinned Moon ordinary release command reaches the closed Darwin cache planner',
  {skip: process.platform !== 'darwin'}, t => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-moon-cache-command-')));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    writeFileSync(join(root, 'moon.mod'), 'name = "fixture/cache-command"\n');
    writeFileSync(join(root, 'moon.pkg'), '');
    writeFileSync(join(root, 'main_test.mbt'), 'test "original command" { assert_eq(1, 1) }\n');
    const tools = join(root, 'tools'); mkdirSync(tools);
    const captured = join(root, 'original-command.json');
    const module = new URL('./native-core-c-compiler.mjs', import.meta.url).href;
    // Capture the actual original argv at Moon's normal PATH-selected cc,
    // rather than parsing dry-run quoting or using the different MOON_CC plan.
    // Refuse before C compilation; this never produces or executes a test exe.
    writeFileSync(join(tools, 'cc'), '#!' + process.execPath + '\n' +
      '(async()=>{const {writeFileSync}=await import("node:fs");' +
      `const {nativeCoreCObjectCommands}=await import(${JSON.stringify(module)});` +
      'const args=process.argv.slice(2);' +
      'if(!args.some(x=>/\\.(?:internal|whitebox|blackbox)_test\\.c$/u.test(x))){' +
      'const {spawnSync}=await import("node:child_process");' +
      'const r=spawnSync("/usr/bin/cc",args,{stdio:"inherit"});' +
      'if(r.signal)process.kill(process.pid,r.signal);process.exit(r.status??1);}' +
      `writeFileSync(${JSON.stringify(captured)},JSON.stringify({args,` +
      'plan:nativeCoreCObjectCommands(process.cwd(),"/usr/bin/cc",args)}));process.exit(23);})();\n', {mode: 0o700});
    symlinkSync(realpathSync('/usr/bin/ar'), join(tools, 'ar'));
    const env = {...process.env, PATH: tools + delimiter + process.env.PATH, MOONBIT_NEW_NATIVE: '0'};
    delete env.MOON_CC;
    const result = spawnSync(join(process.env.MOON_HOME, 'bin/moon'),
      ['test', '--target', 'native', '--release', '--strip', '-j', '1'],
      {cwd: root, encoding: 'utf8', timeout: 10000, env});
    assert.ifError(result.error); assert.notEqual(result.status, 0, 'the capture port intentionally refuses before C compilation');
    assert(existsSync(captured), result.stderr);
    const {args, plan} = JSON.parse(readFileSync(captured));
    assert(plan, JSON.stringify(args));
    assert(args.includes('-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC'));
    assert(args.some(arg => arg.endsWith('/libmoonbitrun.o')));
    assert(plan.compile.includes('-O0')); assert(!plan.compile.includes('-O2'));
    assert(plan.link.includes('-O0')); assert.equal(plan.compile[0], '-c');
  });

test('Reader compiler cache inputs refuse changed physical or recipe data without keying fresh library identities',
  {skip: process.platform !== 'darwin'}, t => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-reader-cache-input-')));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    const source = join(root, 'scripts/fixtures/native-runtime-reader-custody.c');
    mkdirSync(join(root, 'scripts/fixtures'), {recursive: true});
    copyFileSync(new URL('./fixtures/native-runtime-reader-custody.c', import.meta.url), source);
    const selected = process.env.ACTQL_TEST_NATIVE_CORE_CCACHE;
    process.env.ACTQL_TEST_NATIVE_CORE_CCACHE = '/not-consumed-by-this-input-test';
    try {
      const first = join(root, 'first'); mkdirSync(first);
      const original = nativeRuntimeReaderCustodyFixture(root, first);
      const value = nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', original);
      assert(value); assert.equal(value.source, source);
      const missing = {...original}; delete missing.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_CACHE_PROFILE;
      assert.equal(nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', missing), undefined);
      assert.equal(nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', {...original,
        DYLD_INSERT_LIBRARIES: original.DYLD_INSERT_LIBRARIES + ':foreign.dylib'}), undefined);
      assert.equal(nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/clang', original), undefined);
      const changed = JSON.parse(original.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_CACHE_PROFILE);
      changed.recipe.flags[1] = '-O1';
      assert.equal(nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', {...original,
        ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_CACHE_PROFILE: JSON.stringify(changed)}), undefined);
      const old = original.DYLD_INSERT_LIBRARIES + '.original';
      renameSync(original.DYLD_INSERT_LIBRARIES, old); copyFileSync(old, original.DYLD_INSERT_LIBRARIES);
      assert.equal(nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', original), undefined,
        'byte-identical replacement cannot claim the original physical construction');
      writeFileSync(source, readFileSync(source, 'utf8') + '\n// Changed actual fixture source.\n');
      const second = join(root, 'second'); mkdirSync(second);
      const next = nativeRuntimeReaderCustodyFixture(root, second);
      const nextValue = nativeRuntimeReaderCustodyCacheInput(root, '/usr/bin/cc', next);
      assert(nextValue); assert.notEqual(nextValue.recipeSha256, value.recipeSha256);
    } finally {
      if (selected === undefined) delete process.env.ACTQL_TEST_NATIVE_CORE_CCACHE;
      else process.env.ACTQL_TEST_NATIVE_CORE_CCACHE = selected;
    }
  });

test('ordinary generated C object planning preserves effective flags and ordered fresh link inputs', () => {
  assert.equal(typeof compilerModule.nativeCoreCObjectCommands, 'function');
  const source = '/original/_build/native/release/test/pkg/pkg.whitebox_test.c';
  const output = source.slice(0, -2) + '.exe';
  const args = ['-o', output, '-I/pinned/include', '-fwrapv', '-fno-strict-aliasing',
    '-Wno-unused-value', '-Wall', '-Wextra', '-Werror', '-O2',
    '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', 'before.o', source, 'after.a', '-lm'];
  const plan = compilerModule.nativeCoreCObjectCommands('/original', '/usr/bin/clang', args, '/owned/object.o');
  assert.deepEqual(plan, {source, output,
    compile: ['-c', source, '-o', '/owned/object.o', '-I/pinned/include', '-fwrapv',
      '-fno-strict-aliasing', '-Wno-unused-value', '-Wall', '-Wextra', '-Werror', '-O0',
      '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', '-dumpdir', output + '-'],
    link: ['-o', output, '-Werror', '-O0', 'before.o', '/owned/object.o', 'after.a', '-lm']});
  assert.deepEqual(args.slice(-4), ['before.o', source, 'after.a', '-lm']);
});

test('ordinary object planning refuses unsupported profiles before any compiler or cache work', () => {
  assert.equal(typeof compilerModule.nativeCoreCObjectCommands, 'function');
  const source = '/original/_build/native/release/test/pkg/pkg.whitebox_test.c';
  const args = ['-o', source.slice(0, -2) + '.exe', '-O2', source, 'original.a', '-lm'];
  for (const [compiler, changed] of [
    ['/usr/bin/c++', args], ['/usr/bin/clang++', args], ['/foreign/compiler', args],
    ['/usr/bin/clang', [...args, '-flto']], ['/usr/bin/clang', [...args, '-shared']],
    ['/usr/bin/clang', [...args, '@response']], ['/usr/bin/clang', [...args, '-x', 'c']],
    ['/usr/bin/clang', [...args, '-DACTQL_SCOPED_READ_ALLOCATOR']],
    ['/usr/bin/clang', [...args, '-DACTQL_RUNTIME_MANAGED_VALUES=1']],
    ['/usr/bin/clang', [...args, '-unknown-option']], ['/usr/bin/clang', [...args, '/original/second.c']],
    ['/usr/bin/clang', args.map(x => x === '-O2' ? '-O0' : x)],
    ['/usr/bin/clang', args.map(x => x === source ? source.replace('/release/', '/debug/') : x)],
    ['/usr/bin/clang', args.map(x => x.endsWith('.exe') ? '/foreign/output.exe' : x)],
  ]) assert.equal(compilerModule.nativeCoreCObjectCommands('/original', compiler, changed, '/owned/object.o'),
    undefined, JSON.stringify([compiler, changed]));
});

test('unsupported cache mode keeps the original combined compiler result and actual OS signal', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-cache-fallback-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const compiler = join(root, 'original-compiler');
  const module = new URL('./native-core-c-compiler.mjs', import.meta.url).href;
  const script = `import {runNativeCoreCCompiler} from ${JSON.stringify(module)};` +
    `runNativeCoreCCompiler(${JSON.stringify(root)},${JSON.stringify(compiler)},process.argv.slice(1));`;
  const args = ['-o', 'unsupported.exe', '-O2', 'original.c', '-flto'];
  const env = {...process.env, ACTQL_TEST_NATIVE_CORE_CCACHE: '/absent/cache',
    ACTQL_TEST_NATIVE_CORE_CCACHE_DIR: '/absent/unused', ACTQL_FIXTURE_CURRENT: 'original'};
  writeFileSync(compiler, '#!' + process.execPath + '\nconsole.log(JSON.stringify({' +
    'args:process.argv.slice(2),current:process.env.ACTQL_FIXTURE_CURRENT}));process.exit(23);\n', {mode: 0o700});
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', script, '--', ...args],
    {cwd: root, env, encoding: 'utf8', timeout: 5000});
  assert.ifError(result.error); assert.equal(result.status, 23); assert.equal(result.signal, null);
  assert.deepEqual(JSON.parse(result.stdout), {args, current: 'original'});
  writeFileSync(compiler, '#!' + process.execPath + '\nprocess.kill(process.pid,"SIGTERM");\n');
  const stopped = spawnSync(process.execPath, ['--input-type=module', '-e', script, '--', ...args],
    {cwd: root, env, encoding: 'utf8', timeout: 5000});
  assert.ifError(stopped.error); assert.equal(stopped.status, null); assert.equal(stopped.signal, 'SIGTERM');
});

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
  const compile = spawnSync('c++', ['-O2', '-Werror', '-c', stub, '-o', object],
    {cwd: root, env: {...env, ...profile}, encoding: 'utf8', timeout: 10000});
  assert.ifError(compile.error); assert.equal(compile.signal, null); assert.equal(compile.status, 0, compile.stderr);
  for (const [directory, optimized] of [[testDirectory, false], [productDirectory, true]]) {
    const input = join(directory, optimized ? 'pkg.c' : 'pkg.whitebox_test.c'), executable = join(directory, 'original.exe');
    writeFileSync(input, (optimized ? '#ifndef' : '#ifdef') + ' __OPTIMIZE__\n#error wrong C optimization boundary\n#endif\n' +
      'extern int original_stub(void);\nint main(void) { return original_stub() == 7 ? 0 : 1; }\n');
    const linked = spawnSync(driver, ['-O2', '-Werror', input, object, '-o', executable],
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


test('same selected Native Core compiler reuses actual release test C from prerequisite to complete tiny selection', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-core-cache-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const tools = join(root, 'tools'), scratch = join(root, 'scratch'), pkg = join(root, 'pkg');
  for (const path of [tools, scratch, pkg]) mkdirSync(path);
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_core_cache"\nversion = "0.0.0"\n');
  writeFileSync(join(pkg, 'moon.pkg'), '');
  writeFileSync(join(pkg, 'library.mbt'), 'pub fn original() -> Int { 7 }\n');
  writeFileSync(join(pkg, 'case_wbtest.mbt'), 'test "original prerequisite" { assert_eq(original(), 7) }\n');
  writeFileSync(join(pkg, 'case_test.mbt'), 'test "independent remaining case" { assert_eq(2 + 3, 5) }\n');
  const compiler = execFileSync('/bin/sh', ['-c', 'command -v cc'], {encoding:'utf8'}).trim();
  const archiver = execFileSync('/bin/sh', ['-c', 'command -v ar'], {encoding:'utf8'}).trim();
  const observations = join(root, 'compiler-inputs.jsonl');
  // Observe operands/flags only, then run the actual selected C compiler.
  // Never read the generated C, object, module, executable or private state.
  writeFileSync(join(tools, 'cc'), '#!' + process.execPath + '\n' +
    'const {spawnSync}=require("node:child_process");const{appendFileSync}=require("node:fs");' +
    'const args=process.argv.slice(2),inputs=args.filter(x=>/\\.(?:internal|whitebox|blackbox)_test\\.c$/.test(x));' +
    'if(inputs.length)appendFileSync(' + JSON.stringify(observations) +
    ',JSON.stringify({inputs,flags:args.filter(x=>/^-O[0-3]$/.test(x)),backend:process.env.MOONBIT_NEW_NATIVE})+"\\n");' +
    'const result=spawnSync(' + JSON.stringify(compiler) + ',args,{stdio:"inherit"});' +
    'if(result.error)throw result.error;if(result.signal)process.kill(process.pid,result.signal);process.exitCode=result.status??1;\n',
    {mode:0o700});
  symlinkSync(archiver, join(tools, 'ar'));
  const env = {...process.env, PATH: tools + delimiter + process.env.PATH, MOONBIT_NEW_NATIVE:'0'};
  delete env.MOON_CC; delete env.CXX;
  const profile = nativeCoreCCompiler(root, scratch, env), selected = {...env, ...profile};
  const run = tail => {
    const result = spawnSync(join(selected.MOON_HOME, 'bin/moon'),
      ['test', '--target', 'native', '--release', '--strip', '--deny-warn', '-j', '2', '--no-parallelize', ...tail],
      {cwd:root, env:selected, encoding:'utf8', timeout:30000, maxBuffer:2*1024**2});
    assert.ifError(result.error); assert.equal(result.signal,null); assert.equal(result.status,0,result.stderr);
    return result.stdout;
  };
  assert.match(run(['pkg/case_wbtest.mbt', '--index', '0']), /Total tests: 1, passed: 1, failed: 0\./u);
  // A later canonical invocation creates fresh fixture inputs, but must keep
  // the exact already selected compiler profile and its actual warm software.
  const secondScratch = join(root, 'second-scratch'); mkdirSync(secondScratch);
  assert.deepEqual(nativeCoreCCompiler(root, secondScratch, selected), {});
  assert.equal(existsSync(join(secondScratch, 'test-c-compiler')), false);
  const before = readFileSync(observations,'utf8').trim().split('\n').map(JSON.parse);
  const whitebox = values => values.filter(row => row.inputs.some(input => input.endsWith('.whitebox_test.c')));
  assert(whitebox(before).length > 0);
  assert.match(run([]), /Total tests: 2, passed: 2, failed: 0\./u);
  const after = readFileSync(observations,'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(whitebox(after), whitebox(before), 'the full selection must not recompile its original prerequisite');
  assert(after.some(row => row.inputs.some(input => input.endsWith('.blackbox_test.c'))),
    'the remaining independent test must still be compiled and executed');
  for (const row of after) { assert.deepEqual(row.flags, ['-O0']); assert.equal(row.backend, '0'); }
});


test('retained Native compiler profile refuses changed launcher or companion and foreign repository reuse', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-retained-profile-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const first = join(root, 'first'); mkdirSync(first);
  const env = {...process.env}; delete env.MOON_CC; delete env.CXX;
  const profile = nativeCoreCCompiler(root, first, env), selected = {...env, ...profile};
  const directory = profile.PATH.split(delimiter)[0];
  const cc = join(directory, 'cc'), original = readFileSync(cc, 'utf8');
  for (const mode of ['changed-launcher', 'changed-companion', 'foreign-repository']) {
    const scratch = join(root, mode); mkdirSync(scratch);
    if (mode === 'changed-launcher') writeFileSync(cc, original + '// changed caller shim\n');
    if (mode === 'changed-companion') {
      unlinkSync(join(directory, 'ar')); symlinkSync(process.execPath, join(directory, 'ar'));
    }
    const actual = nativeCoreCCompiler(mode === 'foreign-repository' ? scratch : root, scratch, selected);
    assert.equal(actual.PATH.split(delimiter)[0], join(scratch, 'test-c-compiler'));
    assert.notEqual(actual.PATH, selected.PATH);
    writeFileSync(cc, original);
    if (mode === 'changed-companion') {
      unlinkSync(join(directory, 'ar'));
      const compiler = execFileSync('/bin/sh', ['-c', 'command -v cc'], {env, encoding: 'utf8'}).trim();
      symlinkSync(realpathSync(join(compiler, '../ar')), join(directory, 'ar'));
    }
  }
});
