import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-command-input-'));
const executable = join(scratch, 'command-input');
before(() => {
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    join(root, 'scripts/fixtures/native-command-input.c'), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  console.log(JSON.stringify({scratch,
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    sourceSha256: createHash('sha256').update(readFileSync(join(root,
      'src/platform_native/host_bootstrap/command_input.h'))).digest('hex'),
    qualification: 'Actual allocation-free C input observation; not backing, Read or installed command admission'}));
});
for (const name of ['exact-storage', 'no-partial-observation', 'argument-limit',
  'raw-bytes-and-original-argv', 'invalid-input', 'selected-preparation',
  'unselected-and-malformed-source', 'selected-context-refusal']) {
  test(`original command input ${name}`, () => {
    const run = spawnSync(executable, [name], {cwd: root, encoding: 'utf8', timeout: 10_000});
    assert.equal(run.status, 0, `${scratch}\n${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.throws(() => process.kill(run.pid, 0), {code: 'ESRCH'});
    assert.deepEqual(JSON.parse(run.stdout), {case: name, passed: true});
  });
}
