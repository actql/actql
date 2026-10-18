import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-initial-crypto-backing-'));
const executable = join(scratch, 'actual-initial-backing');
before(() => {
  assert(process.env.MOON_HOME, 'The selected pinned MoonBit runtime is required');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', '-pthread',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-initial-crypto-backing.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  console.log(JSON.stringify({scratch,
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    sourceSha256: createHash('sha256').update(readFileSync(join(root, 'src/cmd/native_client/initial_crypto_backing_stub.c'))).digest('hex'),
    qualification: 'Actual private backing with diagnostic faults; no Library/domain or installed init acceptance'}));
});
for (const name of ['interrupted-initial-stat', 'consumed-close-unknown']) {
  test(`original initial Crypto backing ${name}`, () => {
    const run = spawnSync(executable, [name], {cwd: root, encoding: 'utf8', timeout: 10_000});
    assert.equal(run.status, 0, `${scratch}\n${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.throws(() => process.kill(run.pid, 0), {code: 'ESRCH'});
    assert.deepEqual(JSON.parse(run.stdout), {case: name, passed: true, kernelFaultObserved: false});
  });
}
