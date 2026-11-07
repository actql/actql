import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeCoreScopedCArguments, nativeCoreScopedInputs,
  prepareNativeCoreScopedProfile, nativeCoreComponentProviderOwner,
  parseNativeCoreComponentProviderExports} from './native-core-scoped-profile.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-scoped-profile-test-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const repository = join(root, 'repository'), scratch = join(repository, '_build/scoped-scratch'), moonHome = join(root, 'moon');
  for (const path of [repository, scratch, moonHome, join(root, 'tools')]) mkdirSync(path, {recursive:true});
  return {root, repository, scratch, moonHome};
}
function plan(root, moon, target, driver = '/original/cc') {
  return ['backtrace', 'env', 'runtime', 'sync_io', 'utf'].map(name =>
    `${driver} -o ${target}/${name}.o -c -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC '${moon}/lib/runtime/${name}.c'`).concat([
    `${driver} -o ${target}/bootstrap.o -c -D_GNU_SOURCE ${root}/src/platform_native/host_bootstrap/bootstrap_stub.c`,
    `${driver} -o ${target}/native/release/test/pkg/pkg.whitebox_test.exe -O2 ${target}/native/release/test/pkg/pkg.whitebox_test.c original.a -lm`,
  ]).join('\n');
}
function config() {
  const repository = '/original', moonHome = '/pinned/moon', sourceDirectory = '/owned/read';
  const target = '/original/_build/scoped-owned';
  return {repository, moonHome, sourceDirectory, profile: 'runtime-values', target: 'aarch64-apple-darwin',
    componentProviderOwner: nativeCoreComponentProviderOwner(),
    inputs: nativeCoreScopedInputs(repository, plan(repository, moonHome, target), moonHome)};
}

test('closed selected C profile preserves original FFI/link flags and changes only recognized test optimization', () => {
  const c = config(), input = c.inputs.at(-1);
  const args = ['-x', 'c++', '-x', 'none', '-o', input.output, '-O2',
    '-fwrapv', '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
    '-x', 'c', input.source, '-x', 'none', '-Wl,--start-group', 'original.a',
    '-Wl,--end-group', '-lm'];
  assert.deepEqual(nativeCoreScopedCArguments(c, args), [
    '-I/owned/read', '-DACTQL_SCOPED_READ_ALLOCATOR', '-DACTQL_RUNTIME_MANAGED_VALUES=1',
    ...args.map(value => value === '-O2' ? '-O0' : value),
    ...c.componentProviderOwner.symbols.map(symbol => '-Wl,-exported_symbol,_' + symbol),
  ]);
  const provider = c.inputs.find(value => value.source.endsWith('/bootstrap_stub.c'));
  const original = ['-o', provider.output, '-c', '-O2', '-D_GNU_SOURCE', provider.source];
  assert.deepEqual(nativeCoreScopedCArguments(c, original), [
    '-I/owned/read', '-DACTQL_SCOPED_READ_ALLOCATOR', '-DACTQL_RUNTIME_MANAGED_VALUES=1',
    '-DACTQL_SCOPED_READ_PROVIDER="/owned/read/owned_capacity.c"', ...original,
  ]);
  for (const input of c.inputs.filter(value => value.source.includes('/lib/runtime/'))) {
    const original = ['-o', input.output, '-c', '-O2', input.source];
    const selected = nativeCoreScopedCArguments(c, original);
    assert.deepEqual(selected.slice(3), [...original.slice(0, -1), '/owned/read/' + input.source.split('/').at(-1)]);
    assert(!selected.some(value => value.startsWith('-DACTQL_SCOPED_READ_PROVIDER=')));
  }
});


test('explicit scoped review changes only the copied-value allocation selector for every original C input', () => {
  const c = config();
  for (const input of c.inputs) {
    const args = ['-o', input.output, ...(input.mode === 'compile' ? ['-c'] : []),
      '-O2', '-fwrapv', input.source, 'original.a', '-lm'];
    const runtime = nativeCoreScopedCArguments(c, args);
    const scoped = nativeCoreScopedCArguments({...c, profile:'scoped-review-values'}, args);
    assert(runtime.includes('-DACTQL_RUNTIME_MANAGED_VALUES=1'));
    assert.deepEqual(scoped, runtime.filter(value => value !== '-DACTQL_RUNTIME_MANAGED_VALUES=1'));
  }
  const input = c.inputs[0];
  for (const profile of [undefined, '', 'foreign']) assert.throws(() =>
    nativeCoreScopedCArguments({...c, profile}, ['-o',input.output,input.source]), /Unknown Native Core allocation profile/u);
});

test('closed C plan refuses missing/duplicate provider or runtime and foreign invocations', () => {
  const c = config(), input = c.inputs.at(-1);
  const original = plan(c.repository, c.moonHome, '/original/_build/scoped-owned');
  for (const changed of [original.replace(/^.*bootstrap_stub.*\n/mu, ''),
    original.replace(/^.*\/utf\.c'.*\n/mu, ''), original + '\n' + original.split('\n')[0],
    original + '\n' + original.split('\n')[0].replace('/backtrace.o', '/duplicate-backtrace.o')]) {
    assert.throws(() => nativeCoreScopedInputs(c.repository, changed, c.moonHome));
  }
  for (const args of [
    ['-o', '/foreign/output', input.source],
    ['-o', input.output, '/foreign/source.c'],
    ['-o', input.output, input.source, '/foreign/another.c'],
    ['-o', input.output, input.source, '-DMOONBIT_ALLOCATOR=FOREIGN'],
    ['-o', input.output, input.source, '-DACTQL_SCOPED_READ_PROVIDER="foreign.c"'],
    ['-o', input.output, input.source, '-DACTQL_BOOTSTRAP_IMPORT_PROVIDER'],
    ['-o', input.output, input.source, '-UACTQL_SCOPED_READ_ALLOCATOR'],
  ]) assert.throws(() => nativeCoreScopedCArguments(c, args));
});

test('preparation uses the normal verified source copier and preserves compiler/archiver routing without running tests', t => {
  const f = fixture(t), tools = join(f.root, 'tools');
  const compiler = join(tools, 'cc'), cxx = join(tools, 'c++'), ar = join(tools, 'ar');
  const packageCC = join(tools, 'package-original-cc'), packageCXX = join(tools, 'package-original-cxx');
  for (const file of [compiler, cxx, packageCC, packageCXX]) writeFileSync(file, '#!' + process.execPath +
    '\nconsole.log(JSON.stringify({args:process.argv.slice(2),original:process.env.ORIGINAL_ENV,role:' +
    JSON.stringify(file) + '}));process.exit(7);\n', {mode: 0o700});
  writeFileSync(ar, '#!/bin/sh\nexit 0\n', {mode: 0o700});
  const calls = [];
  const execute = (command, args, options) => {
    calls.push({command, args, options});
    if (command === 'python3') {
      assert(args[0].endsWith('/prepare_scoped_read.py'));
      assert.deepEqual(args.slice(1, 3), ['--moonbit', f.moonHome]);
      mkdirSync(args.at(-1));
      return JSON.stringify({status: 'review-source-only', target: 'aarch64-apple-darwin',
        installed_supplier: false, required_defines: ['MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
          'ACTQL_SCOPED_READ_ALLOCATOR'], recipe_sha256: 'original-recipe', patch_sha256: 'original-patch'});
    }
    if (command === '/bin/sh') return args.at(-1).startsWith('/') ? args.at(-1)
      : args.at(-1) === 'cc' ? compiler : cxx;
    assert.equal(command, join(f.moonHome, 'bin/moon'));
    assert.equal(args[0], 'test');assert.equal(args.at(-1), '--dry-run');
    assert.equal(options.env.MOONBIT_NEW_NATIVE, '0');
    return plan(f.repository, f.moonHome, args[args.indexOf('--target-dir') + 1]);
  };
  const args = ['--target', 'native', '--release', '--strip', '-j', '2', 'original_wbtest.mbt'];
  const env = {...process.env, MOON_HOME: f.moonHome, MOONBIT_NEW_NATIVE: '1', ORIGINAL_ENV: 'same-original', CC: packageCC, CXX: packageCXX};
  delete env.MOON_CC;delete env.MOONBIT_ALLOCATOR;
  const prepared = prepareNativeCoreScopedProfile(f.repository, f.scratch, args,
    {env, platform: 'darwin', arch: 'arm64', execute});
  assert.equal(prepared.targetDirectory, join(f.scratch, 'native-core-scoped-profile/target'));
  assert.equal(prepared.compilerInputs.inputs.length, 7);
  assert.equal(prepared.compilerInputs.profile, 'runtime-values');
  assert.equal(JSON.parse(readFileSync(prepared.compilerInputs.configPath)).profile, 'runtime-values');
  assert.equal(prepared.environment.MOON_HOME, f.moonHome);
  assert.equal(prepared.environment.MOONBIT_NEW_NATIVE, '0');
  assert.equal(realpathSync(join(prepared.environment.PATH.split(':')[0], 'ar')), ar);
  assert.equal(calls.filter(value => value.command === join(f.moonHome, 'bin/moon')).length, 1);
  assert(calls.every(value => value.command !== 'moon' && !value.args.includes('--build-only')));
  const input = prepared.compilerInputs.inputs.at(-1);
  for (const [selectedCompiler, expected] of [[prepared.environment.CC, packageCC],
    [prepared.environment.CXX, packageCXX],
    [join(prepared.environment.PATH.split(':')[0], 'cc'), compiler],
    [join(prepared.environment.PATH.split(':')[0], 'c++'), cxx]]) {
    const result = spawnSync(selectedCompiler, ['-o', input.output, '-O2', input.source],
      {cwd: f.repository, env: prepared.environment, encoding: 'utf8', timeout: 5000});
    assert.equal(result.status, 7, result.stderr);
    const observed = JSON.parse(result.stdout);
    assert.equal(observed.original, 'same-original');
    assert.equal(observed.role, expected, 'explicit package compilers do not replace Moon PATH compilers');
    assert(observed.args.includes('-O0'));
    assert(!observed.args.some(value => value.includes('main-interposer')));
  }
  assert.deepEqual(JSON.parse(readFileSync(prepared.compilerInputs.configPath)).compilers,
    {'cc':compiler,'c++':cxx,'package-cc':packageCC,'package-c++':packageCXX});
  const reviewScratch = join(f.repository, '_build/scoped-review');mkdirSync(reviewScratch);
  const review = prepareNativeCoreScopedProfile(f.repository, reviewScratch, args,
    {env, platform:'darwin', arch:'arm64', execute, profile:'scoped-review-values'});
  assert.equal(review.compilerInputs.profile, 'scoped-review-values');
  assert.equal(JSON.parse(readFileSync(review.compilerInputs.configPath)).profile, 'scoped-review-values');
  assert.notEqual(review.targetDirectory, prepared.targetDirectory);
  const reviewInput = review.compilerInputs.inputs.at(-1);
  const reviewResult = spawnSync(review.environment.CC, ['-o',reviewInput.output,'-O2',reviewInput.source],
    {cwd:f.repository,env:review.environment,encoding:'utf8',timeout:5000});
  assert.equal(reviewResult.status, 7, reviewResult.stderr);
  const reviewArgs = JSON.parse(reviewResult.stdout).args;
  assert(reviewArgs.includes('-DACTQL_SCOPED_READ_ALLOCATOR'));
  assert(!reviewArgs.includes('-DACTQL_RUNTIME_MANAGED_VALUES=1'));
  assert(reviewArgs.includes('-O0'));
});

test('unsupported host or an explicit foreign compiler/allocator refuses instead of skipping', t => {
  const f = fixture(t);
  const base = {env: {MOON_HOME: f.moonHome}, platform: 'darwin', arch: 'arm64', execute() {assert.fail('no execution');}};
  for (const changed of [{profile:'foreign'}, {platform: 'win32'}, {arch: 'x64'}, {platform: 'linux'}, {env: {...base.env, MOON_CC: '/original/owner'}},
    {env: {...base.env, MOONBIT_ALLOCATOR: 'foreign'}}]) {
    assert.throws(() => prepareNativeCoreScopedProfile(f.repository, f.scratch, ['--target', 'native'], {...base, ...changed}));
  }
});

for (const [arch, target] of [['x64', 'x86_64-unknown-linux-gnu'],
  ['arm64', 'aarch64-unknown-linux-gnu']]) test(`Linux ${arch} diagnostics use the exact source recipe and explicit test-owned control`, t => {
  const f = fixture(t), tools = join(f.root, 'tools');
  const compiler = join(tools, 'cc'), cxx = join(tools, 'c++');
  for (const file of [compiler, cxx, join(tools, 'ar')]) writeFileSync(file,
    '#!/bin/sh\nexit 0\n', {mode: 0o700});
  const calls = [], definitions = ['_GNU_SOURCE', 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
    ...(arch === 'x64' ? ['ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY'] : [])];
  const execute = (command, args) => {
    calls.push({command, args});
    if (command === 'python3') {
      assert.deepEqual(args.slice(-2), ['--target', target]);
      mkdirSync(args[args.indexOf('--destination') + 1]);
      return JSON.stringify({status:'review-source-only', target, installed_supplier:false,
        required_defines:['MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', 'ACTQL_SCOPED_READ_ALLOCATOR', ...definitions],
        required_source_parameters:['ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS'],
        recipe_sha256:'linux-original', patch_sha256:'same-original-patch'});
    }
    if (command === '/bin/sh') return args.at(-1) === 'cc' ? compiler : cxx;
    assert.equal(command, join(f.moonHome, 'bin/moon'));
    return plan(f.repository, f.moonHome, args[args.indexOf('--target-dir') + 1]);
  };
  const env = {MOON_HOME:f.moonHome, PATH:process.env.PATH};
  const prepared = prepareNativeCoreScopedProfile(f.repository, f.scratch,
    ['--target','native','--release','original_wbtest.mbt'],
    {env, platform:'linux', arch, execute, profile:'scoped-review-values', linuxStockFileSlots:64});
  const c = JSON.parse(readFileSync(prepared.compilerInputs.configPath));
  assert.equal(c.target, target);
  assert.equal(c.stockFileControl.slots, 64);
  assert.deepEqual(prepared.compilerInputs.stockFileControl, c.stockFileControl);
  assert.deepEqual(JSON.parse(readFileSync(c.stockFileControl.recipe.path)),
    {kind:'private-native-core-stock-file-control', target, slots:64,
      ...(arch === 'x64' ? {stockFileControlBytes:1544} : {})});
  assert.equal(readFileSync(c.stockFileControl.header.path, 'utf8'),
    '#define ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS 64\n' +
    (arch === 'x64' ? '#define ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES 1544\n' : ''));
  assert.equal(c.stockFileControl.stockFileControlBytes, arch === 'x64' ? 64 * 24 + 8 : undefined);
  assert(!calls.some(value => value.args.includes('--build-only')));
  for (const input of c.inputs) {
    const original = ['-o',input.output,...(input.mode === 'compile' ? ['-c'] : []),'-O2',input.source];
    const selected = nativeCoreScopedCArguments(c, original);
    for (const define of definitions) assert(selected.includes('-D' + define));
    assert(!selected.includes('-DACTQL_RUNTIME_MANAGED_VALUES=1'));
    assert.equal(selected[selected.indexOf('-include') + 1], c.stockFileControl.header.path);
    assert.deepEqual(selected.filter(value => value.startsWith('-Wl,--export-dynamic-symbol=')),
      input.mode === 'link' ? c.componentProviderOwner.symbols.map(symbol => '-Wl,--export-dynamic-symbol=' + symbol) : []);
    assert(!selected.some(value => value.includes('-exported_symbol')));
    assert(!selected.some(value => /stock_file_control\.linux-x64|local-stock-file-control/u.test(value)));
    for (const flag of ['-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=999',
      '-DACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES=4096', '-UACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES',
      '-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN', '-UACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY']) {
      assert.throws(() => nativeCoreScopedCArguments(c, [...original, flag]), /preselected provider/u);
    }
  }
  const input = c.inputs[0], args = ['-o',input.output,'-c',input.source];
  for (const target of [undefined, 'foreign']) assert.throws(() =>
    nativeCoreScopedCArguments({...c, target}, args), /Unknown original scoped target/u);
  for (const member of [c.stockFileControl.recipe, c.stockFileControl.header]) {
    const original = readFileSync(member.path);
    writeFileSync(member.path, 'changed original');
    assert.throws(() => nativeCoreScopedCArguments(c, args), /control changed/u);
    writeFileSync(member.path, original);
  }
});

test('Linux has no implicit stock-File extent and cannot substitute another source target', t => {
  const f = fixture(t);
  const options = {env:{MOON_HOME:f.moonHome}, platform:'linux', arch:'x64',
    execute() {assert.fail('invalid diagnostic must not copy or compile');}};
  for (const linuxStockFileSlots of [undefined, 0, -1, 0.5, '64', 65537]) {
    assert.throws(() => prepareNativeCoreScopedProfile(f.repository, f.scratch,
      ['--target','native'], {...options, linuxStockFileSlots}), /explicit finite/u);
  }
  assert.throws(() => prepareNativeCoreScopedProfile(f.repository, f.scratch,
    ['--target','native'], {...options, platform:'darwin', arch:'arm64', linuxStockFileSlots:64}),
    /cannot select another target/u);
});

test('the x64 diagnostic extent remains checked against actual provider C layout', () => {
  const source = readFileSync(new URL('../src/platform_native/host_bootstrap/bootstrap_stub.c', import.meta.url), 'utf8');
  assert.match(source, /_Static_assert\(sizeof\(struct stock_file_record\) == 24 && sizeof\(stock_file_entry\) == 8,/u);
  assert.match(source, /_Static_assert\(sizeof\(stock_files\) \+ sizeof\(stock_file_entry\) <= ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES,/u);
});

test('component exports come only from the existing pinned literal producer owner', () => {
  const owner = nativeCoreComponentProviderOwner();
  assert.deepEqual(owner.symbols, [
    'actql_native_owned_current', 'actql_native_owned_allocate', 'actql_native_owned_retire',
    'actql_read_context_retain', 'actql_read_context_release_after_owner_ack',
    'actql_bootstrap_current_read_context', 'actql_native_file_scoped_allocate',
    'actql_native_file_scoped_free', 'actql_native_private_scoped_allocate',
    'actql_native_private_scoped_free', 'actql_native_private_scoped_contains_allocation',
  ]);
  const body = readFileSync(owner.path, 'utf8');
  assert.equal(Buffer.byteLength(body), owner.bytes);
  assert.match(owner.sha256, /^[0-9a-f]{64}$/u);
  assert.deepEqual(parseNativeCoreComponentProviderExports(body), owner.symbols);
  for (const changed of [
    body.replace("    'actql_native_owned_current',", "    'actql_native_owned_current',\n    'actql_native_owned_current',"),
    body.replace("    'actql_native_owned_current',", "    'actql_native_owned_current*',"),
    body.replace("    'actql_native_owned_current',", "    lookup('actql_native_owned_current'),"),
    body.replace('LOCAL_COMPONENT_PROVIDER_EXPORTS = (', 'LOCAL_COMPONENT_PROVIDER_EXPORTS = tuple(('),
    body + '\nLOCAL_COMPONENT_PROVIDER_EXPORTS = ()\n',
  ]) assert.throws(() => parseNativeCoreComponentProviderExports(changed));
  const c = config(), input = c.inputs.at(-1), args = ['-o', input.output, input.source];
  for (const edit of [value => {value.bytes++;}, value => {value.sha256 = '0'.repeat(64);},
    value => {value.path = '/foreign/owner.py';}, value => {value.symbols.pop();},
    value => {value.symbols.push('foreign_port');}, value => {value.symbols.push(value.symbols[0]);}]) {
    const changed = structuredClone(c); edit(changed.componentProviderOwner);
    assert.throws(() => nativeCoreScopedCArguments(changed, args), /export owner changed/u);
  }
});

test('only exact planned final test links receive original provider exports', () => {
  const c = config();
  for (const input of c.inputs) {
    const compile = input.mode === 'compile';
    const args = ['-o', input.output, ...(compile ? ['-c'] : []), '-O2', input.source];
    const selected = nativeCoreScopedCArguments(c, args);
    const exports = selected.filter(value => value.includes('-exported_symbol'));
    assert.deepEqual(exports, compile ? [] : c.componentProviderOwner.symbols.map(symbol => '-Wl,-exported_symbol,_' + symbol));
    assert.throws(() => nativeCoreScopedCArguments(c, compile
      ? args.filter(value => value !== '-c') : [...args, '-c']), /compile\/link mode changed/u);
  }
  const input = c.inputs.at(-1), args = ['-o', input.output, input.source];
  for (const flags of [['-rdynamic'], ['-Wl,--export-dynamic'], ['-Wl,-E'], ['-Xlinker', '-export-dynamic'],
    ['-Wl,--export-dynamic-symbol=foreign'], ['-Wl,--export-dynamic-symbol=*'],
    ['-Wl,-exported_symbol,_foreign'], ['-Wl,--dynamic-list=/foreign'],
    ['-Wl,-exported_symbols_list,/foreign'], ['-Wl,-exported_symbol,_' + c.componentProviderOwner.symbols[0]]])
    assert.throws(() => nativeCoreScopedCArguments(c, [...args, ...flags]), /original component-provider exports/u);
  const original = plan(c.repository, c.moonHome, '/original/_build/scoped-owned');
  assert.throws(() => nativeCoreScopedInputs(c.repository,
    original.replace(' -c -D_GNU_SOURCE ', ' -D_GNU_SOURCE '), c.moonHome), /generated test executable/u);
  assert.throws(() => nativeCoreScopedInputs(c.repository,
    original.replaceAll('pkg.whitebox_test', 'foreign'), c.moonHome), /generated test executable/u);
});
