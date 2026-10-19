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
  assert.equal(process.platform, 'darwin');
  assert.ok(process.env.MOON_HOME, 'use the pinned Native toolchain');
  const main = readFileSync(join(root, 'src/cmd/native_client/main.mbt'), 'utf8');
  const command = main.slice(main.indexOf('fn command()'), main.indexOf('fn execute(matches'));
  assert.equal(createHash('sha256').update(command).digest('hex'),
    'bfe77b8e1c519362f2e531baae9afed8396099fad3cc050967edb061801d7df9',
    'changed selected grammar requires its own initial parser volume derivation');
  const build = spawnSync('cc', ['-std=c11', '-O0',
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
  const absent = spawnSync('cc', ['-std=c11', '-O0',
    join(root, 'scripts/fixtures/native-command-platform-unavailable.c'),
    join(root, 'scripts/fixtures/native-command-platform-default.c'),
    '-o', unavailable], {cwd:root, encoding:'utf8', timeout:60_000});
  assert.equal(absent.status, 0, `${absent.error ?? ''}\n${absent.stderr}`);
  console.log(JSON.stringify({executable,
    sha256:createHash('sha256').update(readFileSync(executable)).digest('hex'),
    qualification:'C/O0 controlled entry-record protocol; fixture member/admission only, no operational original, dlopen or module ACK'}));
});
test('unselected bootstrap has no CLI or filesystem dependency', () => {
  const run = spawnSync(unavailable, [], {cwd:root, encoding:'utf8', timeout:10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  assert.equal(run.stdout.trim(), 'unselected bootstrap entry passed');
});
for (const name of ['initial-candidate', 'initial-stack', 'initial-volume', 'capture', 'early-input', 'early-argv-change', 'one-shot', 'partial-current', 'thread-fork', 'runtime']) {
  test(`original command entry record ${name}`, () => {
    const run = spawnSync(executable, [name], {cwd:root,
      env:{...process.env, TMPDIR:'/original/command-scratch',
        ACTQL_NATIVE_LOCAL_RUNTIME:'{"controlled":"record protocol only"}'},
      encoding:'utf8', timeout:10_000});
    assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    if (name === 'initial-stack') {
      const lines = run.stdout.trim().split('\n');
      assert.match(lines[0], /^original stack bytes=[1-9][0-9]* entry bytes=[1-9][0-9]*$/u);
      assert.equal(lines.length, 2);
      assert.equal(lines[1], 'original entry record passed');
      console.log(lines[0]);
    } else assert.equal(run.stdout.trim(), 'original entry record passed');
  });
}
