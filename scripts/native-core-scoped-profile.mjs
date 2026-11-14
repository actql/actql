// Explicit selected-provider test tooling. Preparation is neither a physical
// acquisition, a test result nor a Native artifact/installation authority.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {accessSync, constants, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync,
  renameSync, symlinkSync, writeFileSync} from 'node:fs';
import {basename, delimiter, dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreCArguments, nativeCoreCObjectCommands, runNativeCoreCCommands} from './native-core-c-compiler.mjs';
import {parseCommands} from './verification-actions.mjs';

const runtimeNames = new Set(['backtrace.c', 'env.c', 'runtime.c', 'sync_io.c', 'utf.c']);
const cSource = value => /\.(?:c|cc|cpp|cxx)$/u.test(value);
const allocator = '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC';
const profiles = new Set(['runtime-values', 'scoped-review-values']);
const targets = new Map([['darwin-arm64', 'aarch64-apple-darwin'],
  ['linux-arm64', 'aarch64-unknown-linux-gnu'], ['linux-x64', 'x86_64-unknown-linux-gnu']]);
const linuxDefinitions = target => ['_GNU_SOURCE', 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
  ...(target === 'x86_64-unknown-linux-gnu' ? ['ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY'] : [])];
const identity = bytes => ({bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex')});
const canonicalSource = (root, value) => resolve(root, value);
const providerOwner = new URL('./produce-native-remote-scoped-runtime.py', import.meta.url);

// The existing producer owns this closed import surface. Read only its literal
// tuple, never evaluate Python or maintain a second driftable list of ports.
export function parseNativeCoreComponentProviderExports(source) {
  assert.equal([...source.matchAll(/^LOCAL_COMPONENT_PROVIDER_EXPORTS\b/gmu)].length, 1,
    'One literal component-provider export owner required');
  const tuple = /^LOCAL_COMPONENT_PROVIDER_EXPORTS = \(\n((?:    '[A-Za-z_][A-Za-z0-9_]*',\n)+)\)$/mu.exec(source);
  assert(tuple, 'Component-provider exports must be an identifier-only literal tuple');
  const symbols = [...tuple[1].matchAll(/'([A-Za-z_][A-Za-z0-9_]*)'/gu)].map(match => match[1]);
  assert.equal(new Set(symbols).size, symbols.length, 'Duplicate component-provider export');
  return symbols;
}

export function nativeCoreComponentProviderOwner() {
  const bytes = readFileSync(providerOwner);
  return {path: fileURLToPath(providerOwner), ...identity(bytes),
    symbols: parseNativeCoreComponentProviderExports(bytes.toString('utf8'))};
}

function componentProviderLinkArguments(target, symbols) {
  const prefix = target === 'aarch64-apple-darwin'
    ? '-Wl,-exported_symbol,_' : '-Wl,--export-dynamic-symbol=';
  return symbols.map(symbol => prefix + symbol);
}

function generatedTestLink(root, source, output) {
  const path = relative(root, source).split('\\').join('/');
  return /^_build\/(?:[^/]+\/)*native\/(?:debug|release)\/test\/.+\.(?:internal|whitebox|blackbox)_test\.c$/u.test(path) &&
    output === source.slice(0, -2) + '.exe';
}

export function nativeCoreScopedInputs(root, plan, moonHome) {
  const inputs = [];
  for (const line of plan.split('\n')) {
    const parsed = parseCommands(line);
    if (parsed.reason !== null) {
      assert(!(line.includes(' -o ') && /\.(?:c|cc|cpp|cxx)(?:\s|['"]|$)/u.test(line)),
        'Unparsed scoped C command');
      continue;
    }
    for (const {argv} of parsed.commands) {
      if (basename(argv[0]) === 'moonc' || !argv.some(cSource)) continue;
      const args = argv.slice(1).map(value => value.replaceAll('${MOON_HOME}', moonHome)
        .replaceAll('$MOON_HOME', moonHome));
      const sources = args.filter(cSource);
      assert.equal(sources.length, 1, 'One original scoped C source per command');
      assert.equal(args.filter(value => value === '-o').length, 1, 'One scoped output');
      const output = args[args.indexOf('-o') + 1];
      assert(output, 'Missing scoped C output');
      assert(args.filter(value => value === '-c').length <= 1, 'One original compile-only selection');
      const mode = args.includes('-c') ? 'compile' : 'link';
      const input = {source: canonicalSource(root, sources[0]), output: resolve(root, output), mode};
      assert(mode !== 'link' || generatedTestLink(root, input.source, input.output),
        'Only original generated test executable links may select component exports');
      inputs.push(input);
    }
  }
  assert(inputs.length > 0, 'No scoped C inputs');
  assert.equal(new Set(inputs.map(value => value.output)).size, inputs.length,
    'Duplicate scoped C output');
  const providers = inputs.filter(value => value.source === join(root,
    'src/platform_native/host_bootstrap/bootstrap_stub.c'));
  assert.equal(providers.length, 1, 'Exactly one original scoped provider');
  const runtimes = inputs.filter(value => dirname(value.source) === join(moonHome, 'lib/runtime'));
  assert.equal(runtimes.length, runtimeNames.size, 'One compile per original runtime source');
  assert.deepEqual(new Set(runtimes.map(value => basename(value.source))), runtimeNames,
    'Keep all five original runtime compilation inputs');
  return inputs;
}

export function nativeCoreScopedCArguments(config, args) {
  assert(profiles.has(config.profile), 'Unknown Native Core allocation profile');
  assert([...targets.values()].includes(config.target), 'Unknown original scoped target');
  const sources = args.filter(cSource);
  assert.equal(sources.length, 1, 'One original scoped C source per invocation');
  assert.equal(args.filter(value => value === '-o').length, 1, 'One scoped C output');
  const source = canonicalSource(config.repository, sources[0]);
  const output = resolve(config.repository, args[args.indexOf('-o') + 1]);
  const input = config.inputs.find(value => value.source === source && value.output === output);
  assert(input, 'C input/output is outside the original scoped Moon plan');
  assert(args.filter(value => value === '-c').length <= 1, 'Duplicate compile-only selection');
  assert.equal(input.mode, args.includes('-c') ? 'compile' : 'link',
    'Original scoped compile/link mode changed');
  assert.deepEqual(config.componentProviderOwner, nativeCoreComponentProviderOwner(),
    'Original component-provider export owner changed');
  // These are selected only by this same closed owner, never from a caller's
  // broad, duplicate, replacement or target-incompatible export option.
  assert(!args.some(value => /(?:rdynamic|export[-_]dynamic|exported[-_]symbols?|dynamic[-_]list)/u.test(value) ||
    /(?:^|,)(?:-E|--export-all-symbols)(?:,|$)/u.test(value)),
    'Do not replace original component-provider exports');
  if (input.mode === 'link') assert(generatedTestLink(config.repository, source, output),
    'Only original generated test executable links may select component exports');
  assert(args.filter(value => value.startsWith('-DMOONBIT_ALLOCATOR=')).every(value => value === allocator),
    'Scoped tests retain the original mimalloc selection');
  assert(!args.some(value => /^-[DU]ACTQL_(?:SCOPED_READ_|RUNTIME_MANAGED_VALUES|BOOTSTRAP_IMPORT_PROVIDER|NATIVE_LINUX_|NATIVE_OWNED_LINUX_|BUNDLE_STOCK_FILE_CONTROL_BYTES)/u.test(value)),
    'Do not replace a preselected provider profile');
  const selected = nativeCoreCArguments(config.repository, args).map(value =>
    value === sources[0] && dirname(source) === join(config.moonHome, 'lib/runtime')
      ? join(config.sourceDirectory, basename(source)) : value);
  const prefix = ['-I' + config.sourceDirectory, '-DACTQL_SCOPED_READ_ALLOCATOR',
    ...(config.profile === 'runtime-values' ? ['-DACTQL_RUNTIME_MANAGED_VALUES=1'] : [])];
  if (config.target !== 'aarch64-apple-darwin') {
    assert([...targets.values()].includes(config.target), 'Unknown original scoped target');
    const control = config.stockFileControl;
    assert(control && control.slots > 0 && Number.isSafeInteger(control.slots),
      'Original Linux test control required');
    for (const member of [control.recipe, control.header]) {
      assert.deepEqual(identity(readFileSync(member.path)), {bytes: member.bytes, sha256: member.sha256},
        'Original Linux test control changed');
    }
    prefix.push(...linuxDefinitions(config.target).map(value => '-D' + value),
      '-include', control.header.path);
  }
  if (source === join(config.repository, 'src/platform_native/host_bootstrap/bootstrap_stub.c')) {
    prefix.push('-DACTQL_SCOPED_READ_PROVIDER=' + JSON.stringify(join(config.sourceDirectory, 'owned_capacity.c')));
  }
  // Empty internal/blackbox harnesses may not link the provider at all.
  // Export only the original provider that this exact executable consumes;
  // Darwin otherwise treats each absent export as an undefined symbol.
  const provider = config.inputs.find(value => value.source === join(config.repository,
    'src/platform_native/host_bootstrap/bootstrap_stub.c'));
  const linksProvider = input.mode === 'link' && provider &&
    args.some(value => resolve(config.repository, value) === provider.output);
  return [...prefix, ...selected, ...(linksProvider
    ? componentProviderLinkArguments(config.target, config.componentProviderOwner.symbols) : [])];
}

// Decompose only after the existing full Scoped command admission. All original
// profile definitions/headers compile into the object; owned exports stay on its
// fresh link. Unknown generated-C flags keep the original combined compiler call.
export function nativeCoreScopedCObjectCommands(config, compiler, args, object) {
  const selected = nativeCoreScopedCArguments(config, args);
  if (config.target !== 'aarch64-apple-darwin') return;
  const plan = nativeCoreCObjectCommands(config.repository, compiler, args, object);
  if (!plan) return;
  const base = nativeCoreCArguments(config.repository, args);
  const offset = selected.findIndex((_, index) => base.every((value, item) => selected[index + item] === value));
  assert(offset >= 0, 'Original generated Scoped command required');
  return {...plan, compile: [...selected.slice(0, offset), ...plan.compile],
    link: [...plan.link, ...selected.slice(offset + base.length)]};
}

// Only compiler-information queries may bypass the closed source/output plan.
export function runNativeCoreScopedCompiler(configPath, kind, args) {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  assert(Object.hasOwn(config.compilers, kind), 'Unknown scoped compiler role');
  const information = args.length > 0 && args.every(value =>
    ['--version', '-v', '-dumpmachine', '-dumpversion', '-print-search-dirs'].includes(value));
  const selected = information ? args : nativeCoreScopedCArguments(config, args);
  const started = performance.now();
  const result = information ? spawnSync(config.compilers[kind], selected, {stdio: 'inherit'})
    : runNativeCoreCCommands(config.repository, config.compilers[kind], selected,
      object => nativeCoreScopedCObjectCommands(config, config.compilers[kind], args, object));
  try {
    console.error('ACTQL_NATIVE_CI_PHASE ' + JSON.stringify({phase: 'scoped-c-compiler',
      profile: config.profile, operation: information ? 'information' : args.includes('-c') ? 'compile' : 'link',
      milliseconds: Math.round(performance.now() - started),
      succeeded: !result.error && !result.signal && result.status === 0}));
  } catch { /* Timing diagnostics never replace the original compiler result. */ }
  if (result.error) throw result.error;
  if (result.signal) process.kill(process.pid, result.signal);
  process.exitCode = result.status ?? 1;
}

export function prepareNativeCoreScopedProfile(repository, scratch, args, {
  env = process.env, platform = process.platform, arch = process.arch,
  execute = execFileSync, profile = 'runtime-values', linuxStockFileSlots, softwareDirectory,
} = {}) {
  assert(profiles.has(profile), 'Unknown Native Core allocation profile');
  const target = targets.get(`${platform}-${arch}`);
  assert(target, 'Unsupported scoped Core test target');
  if (platform === 'linux') {
    assert(Number.isSafeInteger(linuxStockFileSlots) && linuxStockFileSlots > 0 && linuxStockFileSlots <= 65536,
      'An explicit finite diagnostic Linux stock-File control is required');
  } else assert.equal(linuxStockFileSlots, undefined, 'Linux control cannot select another target');
  assert.equal(env.MOON_CC, undefined, 'Keep an explicit Moon compiler profile authoritative');
  assert(env.MOON_HOME, 'Explicit pinned Moon toolchain required');
  assert(env.MOONBIT_ALLOCATOR === undefined || env.MOONBIT_ALLOCATOR === 'mimalloc',
    'Scoped tests require the original mimalloc profile');
  assert(!args.some(value => value === '--target-dir' || value.startsWith('--target-dir=') ||
    ['--dry-run', '--outline', '--build-only'].includes(value)), 'Scoped preparation owns its distinct target directory');
  assert.equal(args.filter(value => value === '--target').length, 1, 'One explicit Native target required');
  assert.equal(args[args.indexOf('--target') + 1], 'native', 'Original Native test target required');
  repository = realpathSync(repository); scratch = realpathSync(scratch);
  assert(relative(repository, scratch).startsWith('_build/'), 'Scoped scratch must be owned under repository/_build');
  const moonHome = realpathSync(env.MOON_HOME);
  const directory = join(scratch, 'native-core-scoped-profile');
  mkdirSync(directory, {mode: 0o700});
  let retireSoftware;
  if (softwareDirectory !== undefined) {
    assert.equal(softwareDirectory, join(repository, '_build/native-core-scoped/compiler-software', profile),
      'Only the original profile software directory may be selected');
    let existingParent = dirname(softwareDirectory);
    while (!existsSync(existingParent)) existingParent = dirname(existingParent);
    assert.equal(realpathSync(existingParent), existingParent,
      'Actual software directory required, never a path alias');
    mkdirSync(dirname(softwareDirectory), {recursive: true, mode: 0o700});
    assert.equal(realpathSync(dirname(softwareDirectory)), dirname(softwareDirectory),
      'Actual software directory required, never a path alias');
    mkdirSync(softwareDirectory, {mode: 0o700});
    const original = lstatSync(softwareDirectory);
    let retired = false;
    retireSoftware = () => {
      if (retired) return;
      const current = lstatSync(softwareDirectory);
      assert(current.isDirectory() && !current.isSymbolicLink() &&
        current.dev === original.dev && current.ino === original.ino,
      'Keep the original software directory owner; never retire its replacement');
      renameSync(softwareDirectory, join(directory, 'retired-software'));
      retired = true;
    };
  }
  try {
  const sourceDirectory = join(softwareDirectory ?? directory, 'derived-read-source');
  const prepare = join(repository, 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py');
  const record = JSON.parse(execute('python3', [prepare, '--moonbit', moonHome,
    '--destination', sourceDirectory, ...(platform === 'linux' ? ['--target', target] : [])], {cwd: repository, env, encoding: 'utf8',
    timeout: 60000, maxBuffer: 2 * 1024 ** 2}));
  assert.equal(record.target, target);
  assert.equal(record.status, 'review-source-only');
  assert.equal(record.installed_supplier, false);
  assert.deepEqual(record.required_defines,
    ['MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', 'ACTQL_SCOPED_READ_ALLOCATOR',
      ...(platform === 'linux' ? linuxDefinitions(target) : [])]);
  let stockFileControl;
  if (platform === 'linux') {
    assert.deepEqual(record.required_source_parameters, ['ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS']);
    // This test-owned finite table is explicit diagnostic input, never the
    // Local command's initial-control envelope or an installed capacity claim.
    // The x64 provider already checks its actual 24-byte record and 8-byte
    // entry with C static assertions. Retain that check against this test's
    // exact finite extent; do not borrow the Local command's 4096-byte page.
    const extent = target === 'x86_64-unknown-linux-gnu'
      ? {stockFileControlBytes: linuxStockFileSlots * 24 + 8} : {};
    const recipe = Buffer.from(JSON.stringify({kind: 'private-native-core-stock-file-control',
      target, slots: linuxStockFileSlots, ...extent}) + '\n');
    const header = Buffer.from('#define ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS ' + linuxStockFileSlots + '\n' +
      (extent.stockFileControlBytes === undefined ? ''
        : '#define ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES ' + extent.stockFileControlBytes + '\n'));
    const member = (name, bytes) => {
      const path = join(directory, name); writeFileSync(path, bytes, {flag: 'wx'});
      return {path, ...identity(bytes)};
    };
    stockFileControl = {slots: linuxStockFileSlots, ...extent,
      recipe: member('stock-file-control.json', recipe), header: member('stock-file-control.h', header)};
  } else assert.equal(record.required_source_parameters, undefined);
  // Keep test-only O0 recognition in the existing owner: its pattern is rooted
  // under _build, while this fresh target remains separate from default Core.
  const targetDirectory = join(softwareDirectory ?? directory, 'target');
  mkdirSync(targetDirectory);
  const selectedEnv = {...env, MOON_HOME: moonHome, MOONBIT_NEW_NATIVE: '0'};
  const locate = name => execute('/bin/sh', ['-c', 'command -v "$1"', 'scoped-compiler', name],
    {env, encoding: 'utf8', timeout: 5000}).trim();
  const cc = locate('cc'), cxx = locate('c++');
  const compilers = {'cc': cc, 'c++': cxx};
  if (env.CC !== undefined) compilers['package-cc'] = locate(env.CC);
  if (env.CXX !== undefined) compilers['package-c++'] = locate(env.CXX);
  for (const compiler of Object.values(compilers)) {
    assert(compiler && !/[\n\r]/u.test(compiler), 'One selected original compiler path');
    accessSync(compiler, constants.X_OK);
  }
  const companion = join(dirname(cc), 'ar'); accessSync(companion, constants.X_OK);
  const plan = execute(join(moonHome, 'bin/moon'), ['test', ...args,
    '--target-dir', targetDirectory, '--dry-run'], {cwd: repository, env: selectedEnv,
    encoding: 'utf8', timeout: 60000, maxBuffer: 16 * 1024 ** 2});
  const inputs = nativeCoreScopedInputs(repository, plan, moonHome);
  const configPath = join(directory, 'compiler-inputs.json');
  const componentProviderOwner = nativeCoreComponentProviderOwner();
  const config = {repository, moonHome, sourceDirectory, targetDirectory, inputs,
    compilers, profile, target, componentProviderOwner, ...(stockFileControl ? {stockFileControl} : {})};
  writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', {flag: 'wx'});
  const bin = join(directory, 'bin'); mkdirSync(bin);
  for (const kind of Object.keys(compilers)) writeFileSync(join(bin, kind),
    '#!' + process.execPath + '\nimport(' + JSON.stringify(import.meta.url) +
    ').then(m=>m.runNativeCoreScopedCompiler(' + JSON.stringify(configPath) + ',' +
    JSON.stringify(kind) + ',process.argv.slice(2)));\n', {mode: 0o700, flag: 'wx'});
  symlinkSync(realpathSync(companion), join(bin, 'ar'));
  const environment = {...selectedEnv, PATH: bin + delimiter + env.PATH,
    CC: join(bin, env.CC === undefined ? 'cc' : 'package-cc'),
    CXX: join(bin, env.CXX === undefined ? 'c++' : 'package-c++')};
  return {environment, targetDirectory, ...(retireSoftware ? {retireSoftware} : {}), compilerInputs: {
    qualification: 'selected-provider compiler inputs only; no test execution or artifact authority',
    configPath, sourceDirectory, inputs, profile, componentProviderOwner, recipeSha256: record.recipe_sha256,
    patchSha256: record.patch_sha256, target: record.target,
    ...(softwareDirectory ? {softwareDirectory, retiredSoftwareDirectory: join(directory, 'retired-software')} : {}),
    ...(stockFileControl ? {stockFileControl} : {}),
  }};
  } catch (error) {
    try { retireSoftware?.(); }
    catch (retirement) {
      throw new AggregateError([error, retirement], 'Scoped preparation failed with software retirement pending', {cause: error});
    }
    throw error;
  }
}
