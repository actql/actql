import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-writer-close-'));
const executable = join(scratch, 'actual-writer-close');
before(() => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-filesystem-writer-close.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  console.log(JSON.stringify({scratch, executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    sourceSha256: createHash('sha256').update(readFileSync(join(root, 'src/platform_native/filesystem/filesystem_stub.c'))).digest('hex'),
    qualification: 'Actual C Writer boundary with diagnostic fault injection; not installed key adoption'}));
});
for (const name of ['seal-close-eio', 'cancel-close-eio', 'cancel-close-eintr',
  'sync-before-close', 'confirmed-seal', 'foreign-conflict', 'finalizer-unknown']) {
  test(`original Writer ${name}`, () => {
    const directory = join(scratch, name); mkdirSync(directory, {mode: 0o700});
    const run = spawnSync(executable, [name, directory], {cwd: root, encoding: 'utf8', timeout: 10_000});
    assert.equal(run.status, 0, `${scratch}\n${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.throws(() => process.kill(run.pid, 0), {code: 'ESRCH'});
    assert.deepEqual(JSON.parse(run.stdout), {case: name, passed: true, kernelFaultObserved: false});
  });
}
