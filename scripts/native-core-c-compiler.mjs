// Disable expensive C optimization only for generated release test executables. Moon's
// release IR, runtime allocator, package linker overrides and FFI stay intact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {accessSync, constants, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync} from 'node:fs';
import {version as kernelVersion} from 'node:os';
import {basename, delimiter, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';

export function nativeCoreCArguments(repository, args) {
  const inputs = args.filter(arg => /\.(?:c|cc|cpp|cxx)$/u.test(arg));
  if (inputs.length !== 1) return args;
  const path = relative(repository, resolve(inputs[0])).split(sep).join('/');
  if (isAbsolute(path) || !/^_build\/(?:[^/]+\/)*native\/release\/test\/.+\.(?:internal|whitebox|blackbox)_test\.c$/u.test(path)) return args;
  const optimization = args.filter(arg => /^-O(?:[0-3sgz]|fast)$/u.test(arg));
  if (optimization.length !== 1 || optimization[0] !== '-O2') return args;
  return args.map(arg => arg === '-O2' ? '-O0' : arg);
}

// One official binary pin for the optional Darwin diagnostic path. No tool is
// downloaded or installed by a compiler invocation, and the default is unchanged.
export const nativeCoreCCachePin = Object.freeze({
  version: '4.14.3',
  url: 'https://github.com/ccache/ccache/releases/download/v4.14.3/ccache-4.14.3-darwin.tar.gz',
  archiveSha256: '764dd2a8100ff83e6bbd7b9a1e2016cc401be34bee8a70ea99698186622c34d5',
  binarySha256: 'a2b2f42ba5c6dda37e8176da64dba698b375f454627fb88909c88024109509e5',
});

// This is a closed decomposition of the existing ordinary generated-C command,
// not another build planner. Unfamiliar flags retain the original combined call.
export function nativeCoreCObjectCommands(repository, compiler, args, object) {
  if (!['cc', 'clang'].includes(basename(compiler))) return;
  const selected = nativeCoreCArguments(repository, args);
  if (selected === args || selected.filter(x => x === '-o').length !== 1) return;
  const source = selected.find(x => x.endsWith('.c'));
  const outputIndex = selected.indexOf('-o'), output = selected[outputIndex + 1];
  if (!output || /[\0\r\n]/u.test(output) || resolve(output) !== resolve(source).slice(0, -2) + '.exe') return;
  object ??= resolve(source) + '.object.o';
  const compile = [], link = [];
  for (let index = 0; index < selected.length; index++) {
    const arg = selected[index];
    if (index === outputIndex) { index++; continue; }
    if (arg === source) { link.push(object); continue; }
    if (['-fwrapv', '-fno-strict-aliasing', '-Wno-unused-value', '-Wall', '-Wextra'].includes(arg)) {
      compile.push(arg); continue;
    }
    // Clang forwards O0 to ld as well, including its no-deduplication choice.
    if (['-O0', '-Werror'].includes(arg)) { compile.push(arg); link.push(arg); continue; }
    if (/^-I[^\0\r\n]+$/u.test(arg) || /^-std=(?:gnu|c)(?:99|11|17)$/u.test(arg)) {
      compile.push(arg); continue;
    }
    if (/^-D[A-Za-z_][A-Za-z0-9_]*(?:=[^\0\r\n]*)?$/u.test(arg)) {
      if (arg.startsWith('-DACTQL_')) return;
      if (arg.startsWith('-DMOONBIT_ALLOCATOR=') &&
          arg !== '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC') return;
      compile.push(arg); continue;
    }
    if ((/\.(?:o|a)$/u.test(arg) && !arg.startsWith('-')) || arg === '-lm') {
      link.push(arg); continue;
    }
    return;
  }
  return {source, output,
    compile: ['-c', source, '-o', object, ...compile, '-dumpdir', output + '-'],
    link: ['-o', output, ...link]};
}

function ordinaryObjectCache(compiler) {
  const tool = process.env.ACTQL_TEST_NATIVE_CORE_CCACHE;
  if (tool === undefined || process.platform !== 'darwin' || process.arch !== 'arm64' ||
      process.env.MOON_CC !== undefined || process.env.DYLD_INSERT_LIBRARIES || process.env.LD_PRELOAD) return;
  const actualClang = realpathSync(execFileSync('/usr/bin/xcrun', ['--find', 'clang'],
    {encoding: 'utf8', timeout: 5000}).trim());
  if (![realpathSync('/usr/bin/clang'), actualClang].includes(realpathSync(compiler))) return;
  assert(isAbsolute(tool), 'Explicit absolute pinned compiler-cache tool required');
  const binary = lstatSync(tool);
  assert(binary.isFile() && !binary.isSymbolicLink());
  assert.equal(createHash('sha256').update(readFileSync(tool)).digest('hex'), nativeCoreCCachePin.binarySha256,
    'Selected compiler-cache binary differs from its official pin');
  const cacheDirectory = process.env.ACTQL_TEST_NATIVE_CORE_CCACHE_DIR;
  assert(typeof cacheDirectory === 'string' && isAbsolute(cacheDirectory), 'Private compiler-cache directory required');
  mkdirSync(cacheDirectory, {recursive: true, mode: 0o700});
  const directory = lstatSync(cacheDirectory);
  assert(directory.isDirectory() && !directory.isSymbolicLink() && directory.uid === process.getuid(),
    'Original private compiler-cache directory required');
  const cache = realpathSync(cacheDirectory);
  mkdirSync(join(cache, 'tmp'), {recursive: true, mode: 0o700});
  const sdk = realpathSync(execFileSync('/usr/bin/xcrun', ['--show-sdk-path'],
    {encoding: 'utf8', timeout: 5000}).trim());
  const namespace = createHash('sha256').update(JSON.stringify({platform: process.platform,
    arch: process.arch, kernel: kernelVersion(), sdk,
    SDKROOT: process.env.SDKROOT, MACOSX_DEPLOYMENT_TARGET: process.env.MACOSX_DEPLOYMENT_TARGET,
    DEVELOPER_DIR: process.env.DEVELOPER_DIR})).digest('hex');
  // An explicit empty config and cleared cache environment exclude global,
  // remote, ignored-header and sloppiness settings. Actual headers/flags still
  // form standard ccache keys; links and runtime owners are always fresh.
  const environment = {...Object.fromEntries(Object.entries(process.env)
    .filter(([name]) => !name.startsWith('CCACHE_'))),
    CCACHE_CONFIGPATH: '/dev/null', CCACHE_DIR: cache, CCACHE_TEMPDIR: join(cache, 'tmp'),
    CCACHE_LOGFILE: join(cache, 'compiler.log'),
    CCACHE_COMPILERCHECK: 'content', CCACHE_EXTRAFILES: [actualClang, join(sdk, 'SDKSettings.json')].join(delimiter),
    CCACHE_SLOPPINESS: '', CCACHE_REMOTE_STORAGE: '', CCACHE_NAMESPACE: 'actql-core-ordinary-' + namespace};
  return {tool, environment};
}

function compilerLauncher(repository, original) {
  return '#!' + process.execPath + '\nimport(' + JSON.stringify(import.meta.url) +
    ').then(m => m.runNativeCoreCCompiler(' + JSON.stringify(repository) + ',' +
    JSON.stringify(original) + ',process.argv.slice(2)));\n';
}

// Reuse only this same generated software profile, never the enclosing prior
// fixture namespace. Its original compiler/companion and current launcher bytes
// must still match. A changed or foreign caller shim follows normal selection.
function retainedCompilerProfile(repository, selected, env) {
  try {
    const directory = realpathSync(dirname(selected));
    if (basename(directory) !== 'test-c-compiler' || selected !== join(directory, 'cc')) return false;
    const owner = lstatSync(directory);
    if (!owner.isDirectory() || owner.uid !== process.getuid() || (owner.mode & 0o777) !== 0o700) return false;
    const expected = env.CXX ? ['ar', 'cc'] : ['ar', 'c++', 'cc'];
    if (JSON.stringify(readdirSync(directory).sort()) !== JSON.stringify(expected.sort())) return false;
    const originalEnv = {...env, PATH: env.PATH.split(delimiter).filter(path => {
      try { return realpathSync(path || '.') !== directory; } catch { return true; }
    }).join(delimiter)};
    const original = name => execFileSync('/bin/sh', ['-c', 'command -v ' + name],
      {env: originalEnv, encoding: 'utf8', timeout: 5000}).trim();
    const matches = (name, compiler) => {
      const path = join(directory, name), stat = lstatSync(path);
      return stat.isFile() && stat.uid === process.getuid() && (stat.mode & 0o777) === 0o700 &&
        readFileSync(path, 'utf8') === compilerLauncher(repository, compiler);
    };
    const compiler = original('cc'), companion = join(dirname(compiler), 'ar');
    accessSync(companion, constants.X_OK);
    if (!statSync(companion).isFile()) return false;
    if (!matches('cc', realpathSync(compiler)) || !lstatSync(join(directory, 'ar')).isSymbolicLink() ||
        readlinkSync(join(directory, 'ar')) !== realpathSync(companion)) return false;
    if (!env.CXX && !matches('c++', original('c++'))) return false;
    return true;
  } catch {
    return false;
  }
}

export function nativeCoreCCompiler(repository, scratch, env = process.env) {
  if (env.MOON_CC !== undefined) {
    // An explicitly selected driver remains authoritative, including its
    // allocator and package override behaviour. Do not replace that profile.
    return {};
  }
  repository = realpathSync(repository);
  const selected = execFileSync('/bin/sh', ['-c', 'command -v cc'],
    {env, encoding: 'utf8', timeout: 5000}).trim();
  if (retainedCompilerProfile(repository, selected, env)) return {};
  // Moon selects ar beside the PATH-selected cc before resolving symlinks.
  // Keep that original companion, never a realpath or unrelated PATH archiver.
  const companion = join(dirname(selected), 'ar');
  accessSync(companion, constants.X_OK);
  assert(statSync(companion).isFile(), 'Native archiver must be an executable file');
  const archiver = realpathSync(companion), compiler = realpathSync(selected);
  const directory = join(realpathSync(scratch), 'test-c-compiler');
  mkdirSync(directory, {mode: 0o700});
  // Launch Node directly, without another system shell stripping the original
  // Reader injection environment before it reaches the selected compiler.
  const launcher = (name, original) => writeFileSync(join(directory, name),
    compilerLauncher(repository, original), {mode: 0o700, flag: 'wx'});
  launcher('cc', compiler);
  // The package C++ link driver compiles its generated test C through c++,
  // so shadowing cc alone leaves those large inputs at O2. Keep that actual
  // linker/runtime and change only the same recognized generated test input.
  // An explicit CXX selection remains authoritative; stubs and product C
  // are outside nativeCoreCArguments' test-only boundary.
  if (!env.CXX) {
    const selectedCxx = execFileSync('/bin/sh', ['-c', 'command -v c++'],
      {env, encoding: 'utf8', timeout: 5000}).trim();
    // clang++ can share a realpath with clang. Keep its selected invocation
    // name so the original C++ runtime/link behaviour is retained as well.
    launcher('c++', selectedCxx);
  }
  symlinkSync(archiver, join(directory, 'ar'));
  // PATH probing preserves Moon's normal allocator/runtime object selection.
  // MOON_CC would also override package C++/archive drivers and FFI compilers.
  return {PATH: directory + delimiter + env.PATH};
}

export function runNativeCoreCCompiler(repository, compiler, args) {
  const finish = result => {
    if (result.error) throw result.error;
    if (result.signal) process.kill(process.pid, result.signal);
    process.exitCode = result.status ?? 1;
  };
  const selected = nativeCoreCArguments(repository, args);
  const eligible = process.env.ACTQL_TEST_NATIVE_CORE_CCACHE === undefined ? undefined
    : nativeCoreCObjectCommands(repository, compiler, args);
  const cache = eligible && ordinaryObjectCache(compiler);
  if (!cache) return finish(spawnSync(compiler, selected, {stdio: 'inherit'}));
  const temporary = mkdtempSync(join(dirname(resolve(eligible.output)), '.ordinary-c-object-'));
  const plan = nativeCoreCObjectCommands(repository, compiler, args, join(temporary, 'test.o'));
  const compiled = spawnSync(cache.tool, [compiler, ...plan.compile],
    {stdio: 'inherit', env: cache.environment});
  if (compiled.error || compiled.signal || compiled.status !== 0) return finish(compiled);
  const linked = spawnSync(compiler, plan.link, {stdio: 'inherit'});
  if (!linked.error && !linked.signal && linked.status === 0) rmSync(temporary, {recursive: true});
  // Keep one enclosing caller deadline. No retry, fresh allowance or fallback
  // follows an actual compiler/link failure; failed object evidence is retained.
  finish(linked);
}
