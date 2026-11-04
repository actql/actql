// Reduce C optimization only for generated release test executables. Moon's
// release IR, runtime allocator, package linker overrides and FFI stay intact.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {accessSync, constants, mkdirSync, realpathSync, statSync, symlinkSync, writeFileSync} from 'node:fs';
import {delimiter, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';

export function nativeCoreCArguments(repository, args) {
  const inputs = args.filter(arg => /\.(?:c|cc|cpp|cxx)$/u.test(arg));
  if (inputs.length !== 1) return args;
  const path = relative(repository, resolve(inputs[0])).split(sep).join('/');
  if (isAbsolute(path) || !/^_build\/(?:[^/]+\/)*native\/release\/test\/.+\.(?:internal|whitebox|blackbox)_test\.c$/u.test(path)) return args;
  const optimization = args.filter(arg => /^-O(?:[0-3sgz]|fast)$/u.test(arg));
  if (optimization.length !== 1 || optimization[0] !== '-O2') return args;
  return args.map(arg => arg === '-O2' ? '-O1' : arg);
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
  writeFileSync(join(directory, 'cc'), '#!' + process.execPath + '\nimport(' +
    JSON.stringify(import.meta.url) +
    ').then(m => m.runNativeCoreCCompiler(' + JSON.stringify(repository) + ',' +
    JSON.stringify(compiler) + ',process.argv.slice(2)));\n',
  {mode: 0o700, flag: 'wx'});
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
