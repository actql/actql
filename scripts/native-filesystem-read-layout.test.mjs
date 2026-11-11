import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('original filesystem layout projection performs no acquisition or allocation', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-f-filesystem-layout-'));
  const executable = join(scratch, 'diagnostic');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-filesystem-read-layout.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  const run = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(run.status, 0, `${scratch}\n${run.error ?? ''}\n${run.stderr}`);
  assert.throws(() => process.kill(run.pid, 0), {code: 'ESRCH'});
  const result = JSON.parse(run.stdout);
  assert.equal(result.cases, 9);
  for (const field of ['rootPayload', 'readerPayload', 'externalOverhead', 'observationPayload', 'acquisitionPayload']) {
    assert(Number.isSafeInteger(result[field]) && result[field] > 0);
  }
  assert.equal(result.heapEntries, 0);
  assert.equal(result.descriptorEntries, 0);
  assert.equal(result.publicAcceptance, false);
  console.log(JSON.stringify({...result, scratch,
    sourceSha256: createHash('sha256').update(readFileSync(join(root,
      'src/platform_native/filesystem/filesystem_stub.c'))).digest('hex'),
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    runtimeSha256: createHash('sha256').update(readFileSync(join(process.env.MOON_HOME,
      'lib/runtime/runtime.c'))).digest('hex')}));
  // Retain the small original binary and stdout's hashes for independent review.
});
