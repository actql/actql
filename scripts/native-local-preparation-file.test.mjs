import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('matching C original installation projection refuses replacement at preparation send', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-preparation-file-'));
  const privateRoot = join(scratch, 'private');
  mkdirSync(privateRoot, {mode: 0o700});
  const executable = join(scratch, 'diagnostic');
  const module = join(scratch, process.platform === 'darwin' ? 'transport.dylib' : 'transport.so');
  const moduleCompile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    ...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
    join(root, 'scripts/fixtures/native-http-lifetime-library.c'), '-o', module],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(moduleCompile.status, 0,
    `${moduleCompile.error ?? ''}\n${moduleCompile.stdout}\n${moduleCompile.stderr}`);
  // Existing libcurl callback parameters are intentionally unused in the stub.
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-Wno-unused-parameter',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-local-preparation-file.c'),
    join(root, 'src/platform_native/filesystem/filesystem_stub.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []),
    '-o', executable], {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  const result = spawnSync(executable, [privateRoot, module], {cwd: root,
    encoding: 'utf8', timeout: 10_000});
  console.log(result.stdout);
  assert.equal(result.status, 0, `${result.error ?? ''}\n${result.stderr}`);
  const summary = JSON.parse(result.stdout.trim().split('\n').at(-1));
  assert.deepEqual(summary, {cases: 14, transport_entries: 2,
    transport_cleanups: 4, public_acceptance: false});
  console.log(JSON.stringify({diagnosticExecutableSha256:
    createHash('sha256').update(readFileSync(executable)).digest('hex'),
    transportModuleSha256: createHash('sha256').update(readFileSync(module)).digest('hex'),
    runtimeSourceSha256: createHash('sha256')
      .update(readFileSync(join(process.env.MOON_HOME, 'lib/runtime/runtime.c')))
      .digest('hex'), boundary: 'C stubs and real memory runtime; deterministic transport callbacks'}));
  // Only a successful, fully reaped owned diagnostic is removed. Failures keep
  // their executable and scratch input for investigation.
  rmSync(scratch, {recursive: true});
});
