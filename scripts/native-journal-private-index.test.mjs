import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-journal-private-index-'));
const copies = join(scratch, 'copies');
mkdirSync(copies, {mode: 0o700});
const executable = join(scratch, 'private-index');
before(() => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-journal-private-index.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stderr}`);
  console.log(JSON.stringify({scratch, executable,
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    qualification: 'Actual private inspection custody with controlled syscall faults; no SQLite execution'}));
});
for (const name of ['generic', 'selected', 'stat-failure', 'close-unknown', 'replacement', 'collision']) {
  test(`private Journal inspection index custody ${name}`, () => {
    const result = spawnSync(executable, [name, join(scratch, name)], {
      cwd: root, encoding: 'utf8', timeout: 10_000,
      env: {...process.env, TMPDIR: copies},
    });
    assert.equal(result.status, 0, `${scratch}\n${result.error ?? ''}\n${result.stderr}`);
    assert.deepEqual(JSON.parse(result.stdout), {
      case: name, passed: true, sqliteExecuted: false, kernelFaultObserved: false,
    });
  });
}
