// Explicit selected-provider test tooling. Preparation is neither a physical
// acquisition, a test result nor a Native artifact/installation authority.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {accessSync, constants, mkdirSync, readFileSync, realpathSync,
  symlinkSync, writeFileSync} from 'node:fs';
import {basename, delimiter, dirname, join, relative, resolve} from 'node:path';
import {nativeCoreCArguments} from './native-core-c-compiler.mjs';
import {parseCommands} from './verification-actions.mjs';

const runtimeNames = new Set(['backtrace.c', 'env.c', 'runtime.c', 'sync_io.c', 'utf.c']);
const cSource = value => /\.(?:c|cc|cpp|cxx)$/u.test(value);
const allocator = '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC';
const profiles = new Set(['runtime-values', 'scoped-review-values']);
const canonicalSource = (root, value) => resolve(root, value);

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
      inputs.push({source: canonicalSource(root, sources[0]), output: resolve(root, output)});
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
  const sources = args.filter(cSource);
  assert.equal(sources.length, 1, 'One original scoped C source per invocation');
  assert.equal(args.filter(value => value === '-o').length, 1, 'One scoped C output');
  const source = canonicalSource(config.repository, sources[0]);
  const output = resolve(config.repository, args[args.indexOf('-o') + 1]);
  assert(config.inputs.some(value => value.source === source && value.output === output),
    'C input/output is outside the original scoped Moon plan');
  assert(args.filter(value => value.startsWith('-DMOONBIT_ALLOCATOR=')).every(value => value === allocator),
    'Scoped tests retain the original mimalloc selection');
  assert(!args.some(value => /^-[DU]ACTQL_(?:SCOPED_READ_|RUNTIME_MANAGED_VALUES|BOOTSTRAP_IMPORT_PROVIDER)/u.test(value)),
    'Do not replace a preselected provider profile');
  const selected = nativeCoreCArguments(config.repository, args).map(value =>
    value === sources[0] && dirname(source) === join(config.moonHome, 'lib/runtime')
      ? join(config.sourceDirectory, basename(source)) : value);
  const prefix = ['-I' + config.sourceDirectory, '-DACTQL_SCOPED_READ_ALLOCATOR',
    ...(config.profile === 'runtime-values' ? ['-DACTQL_RUNTIME_MANAGED_VALUES=1'] : [])];
  if (source === join(config.repository, 'src/platform_native/host_bootstrap/bootstrap_stub.c')) {
    prefix.push('-DACTQL_SCOPED_READ_PROVIDER=' + JSON.stringify(join(config.sourceDirectory, 'owned_capacity.c')));
  }
  return [...prefix, ...selected];
}

// Only compiler-information queries may bypass the closed source/output plan.
export function runNativeCoreScopedCompiler(configPath, kind, args) {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  assert(Object.hasOwn(config.compilers, kind), 'Unknown scoped compiler role');
  const information = args.length > 0 && args.every(value =>
    ['--version', '-v', '-dumpmachine', '-dumpversion', '-print-search-dirs'].includes(value));
  const selected = information ? args : nativeCoreScopedCArguments(config, args);
  const result = spawnSync(config.compilers[kind], selected, {stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.signal) process.kill(process.pid, result.signal);
  process.exitCode = result.status ?? 1;
}

export function prepareNativeCoreScopedProfile(repository, scratch, args, {
  env = process.env, platform = process.platform, arch = process.arch,
  execute = execFileSync, profile = 'runtime-values',
} = {}) {
  assert(profiles.has(profile), 'Unknown Native Core allocation profile');
  assert.equal(platform, 'darwin', 'This scoped Core test profile requires Darwin arm64');
  assert.equal(arch, 'arm64', 'This scoped Core test profile requires Darwin arm64');
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
  const sourceDirectory = join(directory, 'derived-read-source');
  const prepare = join(repository, 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py');
  const record = JSON.parse(execute('python3', [prepare, '--moonbit', moonHome,
    '--destination', sourceDirectory], {cwd: repository, env, encoding: 'utf8',
    timeout: 60000, maxBuffer: 2 * 1024 ** 2}));
  assert.equal(record.target, 'aarch64-apple-darwin');
  assert.equal(record.status, 'review-source-only');
  assert.equal(record.installed_supplier, false);
  assert.deepEqual(record.required_defines,
    ['MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', 'ACTQL_SCOPED_READ_ALLOCATOR']);
  // Keep test-only O0 recognition in the existing owner: its pattern is rooted
  // under _build, while this fresh target remains separate from default Core.
  const targetDirectory = join(directory, 'target');
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
  const config = {repository, moonHome, sourceDirectory, targetDirectory, inputs,
    compilers, profile};
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
  return {environment, targetDirectory, compilerInputs: {
    qualification: 'selected-provider compiler inputs only; no test execution or artifact authority',
    configPath, sourceDirectory, inputs, profile, recipeSha256: record.recipe_sha256,
    patchSha256: record.patch_sha256, target: record.target,
  }};
}
