import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, realpathSync, readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {before, test} from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-command-entry-'));
const executable = join(scratch, 'entry');
const unavailable = join(scratch, 'unavailable');
before(() => {
  assert((process.platform === 'darwin' && process.arch === 'arm64') ||
    (process.platform === 'linux' && process.arch === 'x64' && process.report.getReport().header.glibcVersionRuntime));
  assert.ok(process.env.MOON_HOME, 'use the pinned Native toolchain');
  const build = spawnSync('cc', ['-std=c11', '-O0', ...(process.platform === 'linux' ? ['-D_GNU_SOURCE'] : []),
    '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
    '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"',
    '-I'+resolve(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-command-platform-entry.c'),
    join(root, 'scripts/fixtures/native-command-platform-member.c'),
    join(root, 'scripts/fixtures/native-command-platform-default.c'),
    resolve(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    resolve(process.env.MOON_HOME, 'lib/runtime/backtrace.c'),
    resolve(process.env.MOON_HOME, 'lib/libmoonbitrun.o'), '-o', executable],
  {cwd:root, encoding:'utf8', timeout:60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
  const absent = spawnSync('cc', ['-std=c11', '-O0', ...(process.platform === 'linux' ? ['-D_GNU_SOURCE'] : []),
    join(root, 'scripts/fixtures/native-command-platform-unavailable.c'),
    join(root, 'scripts/fixtures/native-command-platform-default.c'),
    '-o', unavailable], {cwd:root, encoding:'utf8', timeout:60_000});
  assert.equal(absent.status, 0, `${absent.error ?? ''}\n${absent.stderr}`);
  console.log(JSON.stringify({executable,
    sha256:createHash('sha256').update(readFileSync(executable)).digest('hex'),
    qualification:'C/O0 normal-main and public-stdio boundary; fixture members only, no actual dlopen or module ACK'}));
});
test('unselected bootstrap has no CLI or filesystem dependency', () => {
  const run = spawnSync(unavailable, [], {cwd:root, encoding:'utf8', timeout:10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  assert.equal(run.stdout.trim(), 'unselected bootstrap entry passed');
});
for (const name of ['capture', 'used-streams', 'one-shot', 'partial-current', 'thread-fork', 'runtime', 'argument-currentness']) {
  test(`original command entry record ${name}`, () => {
    const run = spawnSync(executable, [name], {cwd:root,
      env:{...process.env, TMPDIR:name === 'used-streams' ? scratch : '/original/command-scratch',
        ACTQL_NATIVE_LOCAL_RUNTIME:'{"controlled":"record protocol only"}'},
      encoding:'utf8', timeout:10_000});
    assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.equal(run.stdout.trim(), 'original entry record passed');
  });
}
