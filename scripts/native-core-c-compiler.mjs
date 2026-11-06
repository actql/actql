// Disable expensive C optimization only for generated release test executables. Moon's
// release IR, runtime allocator, package linker overrides and FFI stay intact.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {accessSync, constants, lstatSync, mkdirSync, readFileSync, readdirSync, readlinkSync, realpathSync, statSync, symlinkSync, writeFileSync} from 'node:fs';
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
  const result = spawnSync(compiler, nativeCoreCArguments(repository, args),
    {stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.signal) process.kill(process.pid, result.signal);
  process.exitCode = result.status ?? 1;
}
