import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));

test('actual HTTP loader separates absent TLS from unknown or advertised TLS debt', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-http-lifetime-'));
  const executable = join(scratch, 'diagnostic');
  function compile(args) {
    const result = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', ...args],
      {cwd: root, encoding: 'utf8', timeout: 30_000});
    assert.equal(result.status, 0, `${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  }
  compile(['-Wno-unused-parameter', '-pthread', '-DACTQL_HTTP_LIFETIME_TEST',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-http-library-lifetime.c'),
    join(root, 'src/platform_native/filesystem/filesystem_stub.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable]);
  let cases = 0;
  for (const [variant, definitions, modes] of [
    ['no-ssl', [], ['no-ssl', 'ready-child', 'failed-child', 'foreign-process', 'lost-release']],
    ['ssl', ['-DACTQL_HTTP_SSL_CAPABILITY'], ['ssl-pending', 'inflight']],
    ['unknown', ['-DACTQL_HTTP_UNKNOWN_VERSION_INFO'], ['unknown-pending']],
    ['missing-info', ['-DACTQL_HTTP_OMIT_VERSION_INFO'], ['unknown-pending']],
    ['failed-load', ['-DACTQL_HTTP_OMIT_PERFORM'], ['foreign-failed-finalizer', 'concurrent-failed-load']],
  ]) {
    const module = join(scratch, `${variant}.${process.platform === 'darwin' ? 'dylib' : 'so'}`);
    compile([...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
      ...definitions, join(root, 'scripts/fixtures/native-http-lifetime-library.c'), '-o', module]);
    for (const mode of modes) {
      const result = spawnSync(executable, [module, mode], {cwd: root,
        encoding: 'utf8', timeout: 10_000});
      assert.equal(result.status, 0, `${variant}/${mode}: ${result.error ?? ''}\n${result.stderr}`);
      assert.match(result.stdout, /^PASS /u);
      cases++;
    }
  }
  assert.equal(cases, 11);
  console.log(JSON.stringify({cases, physical_requests: 0, public_acceptance: false}));
  rmSync(scratch, {recursive: true});
});
