// Build the existing selected bundle command for its actual test platform.
// The producer owns source/allocator/header checks; raw unselected executables
// are never a fallback for an install/activate acceptance path.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync, realpathSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';

export function prepareNativeRuntimeBundle(repository, destination, {
  execute = execFileSync, platform = process.platform, arch = process.arch,
  moonHome = process.env.MOON_HOME, seconds = 600,
} = {}) {
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 1800);
  const target = platform === 'darwin' && arch === 'arm64' ? 'darwin-arm64'
    : platform === 'linux' && arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No selected bundle command recipe for this actual platform');
  assert(typeof moonHome === 'string' && moonHome.length > 0,
    'The existing pinned Moon toolchain is required');
  repository = realpathSync(repository);
  destination = join(realpathSync(dirname(resolve(destination))), basename(destination));
  const run = (command, args) => execute(command, args, {cwd: repository,
    encoding: 'utf8', timeout: (seconds + 30) * 1000, maxBuffer: 8 * 1024 ** 2});
  const source = run('git', ['rev-parse', 'HEAD']).trim();
  assert.match(source, /^[0-9a-f]{40}$/u);
  assert.equal(run('git', ['status', '--porcelain']), '', 'Clean fixed bundle build Source required');
  const clang = platform === 'darwin' ? run('xcrun', ['--find', 'clang']).trim()
    : run('sh', ['-c', 'command -v cc']).trim();
  const sdk = platform === 'darwin' ? run('xcrun', ['--show-sdk-path']).trim() : undefined;
  run('python3', [join(repository, 'scripts/produce-native-remote-scoped-runtime.py'),
    '--source', source, '--moon-home', realpathSync(moonHome), '--clang', clang,
    ...(sdk === undefined ? [] : ['--sdk', sdk]), '--target', target,
    '--destination', destination, '--seconds', String(seconds),
    '--entry', 'src/cmd/native_runtime_bundle']);
  const receiptPath = join(destination, 'build.json');
  const receipt = JSON.parse(readFileSync(receiptPath, 'utf8'));
  assert.equal(receipt.source, source);assert.equal(receipt.entry, 'src/cmd/native_runtime_bundle');
  assert.equal(receipt.target, target);assert.equal(receipt.plan_only, false);
  assert.equal(receipt.moon_build_exit, 0);assert.equal(receipt.providers, 1);
  const binary = join(destination, 'emission/native/release/build/cmd/native_runtime_bundle/native_runtime_bundle.exe');
  assert.equal(receipt.executable.path, binary);
  const original = lstatSync(binary);assert(original.isFile() && !original.isSymbolicLink() && (original.mode & 0o111) !== 0);
  const bytes = readFileSync(binary);
  assert.equal(bytes.length, receipt.executable.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), receipt.executable.sha256);
  assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
  assert.equal(run('git', ['status', '--porcelain']), '');
  const after = lstatSync(binary);
  for (const key of ['dev','ino','size','mode','mtimeMs','ctimeMs']) assert.equal(after[key],original[key]);
  return binary;
}
