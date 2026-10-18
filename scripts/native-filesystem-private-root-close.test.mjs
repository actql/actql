import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-private-root-close-'));
const executable = join(scratch, 'actual-private-root-close');
before(() => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const result = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-filesystem-private-root-close.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(result.status, 0, `${scratch}\n${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  console.log(JSON.stringify({scratch, executable,
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    sourceSha256: createHash('sha256').update(readFileSync(join(root, 'src/platform_native/filesystem/filesystem_stub.c'))).digest('hex'),
    qualification: 'Actual C private Root boundary; diagnostic close faults, no installed session or kernel fault claim'}));
});
const originals = ['missing', 'confirmed-privacy-rejection', 'privacy-close-eio',
  'privacy-close-eintr', 'confirmed-private'];
for (const name of [...originals, ...originals.map(value => 'custody-' + value),
  'custody-walk-close-eio', 'custody-namespace-close-eio', 'custody-current-close-eio']) {
  test(`private Root original retirement ${name}`, () => {
    const directory = join(scratch, name);
    if (!name.endsWith('missing')) mkdirSync(directory, {mode: 0o700});
    const run = spawnSync(executable, [name, directory], {cwd: root, encoding: 'utf8', timeout: 10_000});
    assert.equal(run.status, 0, `${scratch}\n${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.throws(() => process.kill(run.pid, 0), {code: 'ESRCH'});
    assert.deepEqual(JSON.parse(run.stdout), {case: name, passed: true, kernelFaultObserved: false});
  });
}
