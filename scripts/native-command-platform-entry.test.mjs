import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-command-entry-'));
const executable = join(scratch, 'entry');
before(() => {
  assert.equal(process.platform, 'darwin');
  assert.ok(process.env.MOON_HOME, 'use the pinned Native toolchain');
  const build = spawnSync('cc', ['-std=c11', '-O0',
    '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
    '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"',
    '-I'+resolve(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-command-platform-entry.c'),
    join(root, 'scripts/fixtures/native-command-platform-member.c'),
    resolve(process.env.MOON_HOME, 'lib/libmoonbitrun.o'), '-o', executable],
  {cwd:root, encoding:'utf8', timeout:60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
});
for (const name of ['capture', 'one-shot', 'partial-current', 'thread-fork', 'runtime']) {
  test(`original command entry record ${name}`, () => {
    const run = spawnSync(executable, [name], {cwd:root,
      env:{...process.env, ACTQL_NATIVE_LOCAL_RUNTIME:'{"controlled":"record protocol only"}'},
      encoding:'utf8', timeout:10_000});
    assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.equal(run.stdout.trim(), 'original entry record passed');
  });
}
