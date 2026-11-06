import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, realpathSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {before, test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-command-prearguments-'));
const binaries = {};
before(() => {
  assert((process.platform === 'darwin' && process.arch === 'arm64') ||
    (process.platform === 'linux' && process.arch === 'x64' && process.report.getReport().header.glibcVersionRuntime),
    'actual selected Native Local wrapper requires Darwin arm64 or Linux x64 glibc');
  assert.ok(process.env.MOON_HOME, 'use the pinned Moon toolchain include');
  for (const pin of ['selected', 'missing']) {
    const executable = join(scratch, pin);
    const args = ['-std=c11', '-O0', ...(process.platform === 'linux' ? ['-D_GNU_SOURCE'] : []), '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', '-I'+resolve(process.env.MOON_HOME, 'include'),
      join(root, 'src/cmd/native_client/stdout_stub.c'),
      join(root, 'scripts/fixtures/native-command-prearguments.c'),
      join(root, 'scripts/fixtures/native-command-member-unavailable.c'),
      resolve(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
      resolve(process.env.MOON_HOME, 'lib/runtime/backtrace.c'),
      resolve(process.env.MOON_HOME, 'lib/libmoonbitrun.o'), '-o', executable];
    if (pin === 'selected') args.push('-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"');
    const build = spawnSync('cc', args, {cwd: root, encoding: 'utf8', timeout: 60_000});
    assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
    binaries[pin] = executable;
    console.log(JSON.stringify({pin, executable, sha256:createHash('sha256').update(readFileSync(executable)).digest('hex'),
      allocator:{path:resolve(process.env.MOON_HOME, 'lib/libmoonbitrun.o'),sha256:createHash('sha256').update(readFileSync(resolve(process.env.MOON_HOME, 'lib/libmoonbitrun.o'))).digest('hex')},
      qualification:'actual C/O0 wrapper with pinned mimalloc size/usable conformance; no Host, Read or command admission'}));
  }
});
for (const name of ['selected','absent','missing-source','context-limit','invalid-bound','quoted-growth','home-absent','home-overlong','home-unicode','home-empty','mimalloc-boundary','scratch-absent','scratch-empty','scratch-exact','scratch-overlong']) {
  test(`original preargument wrapper ${name}`, () => {
    const env = {...process.env};
    if (name === 'absent') delete env.ACTQL_NATIVE_LOCAL_RUNTIME;
    else env.ACTQL_NATIVE_LOCAL_RUNTIME = '{"original":"fixture"}';
    if (name === 'home-absent') delete env.HOME;
    if (name === 'home-overlong') env.HOME = '/' + 'x'.repeat(4096 * 3 + 3);
    if (name === 'home-unicode') env.HOME = '/' + 'あ'.repeat(4095);
    if (name === 'home-empty') env.HOME = '';
    if (name === 'scratch-absent') delete env.TMPDIR;
    if (name === 'scratch-empty') env.TMPDIR = '';
    if (name === 'scratch-exact') env.TMPDIR = '/' + 'x'.repeat(4095);
    if (name === 'scratch-overlong') env.TMPDIR = '/' + 'x'.repeat(4096);
    const run = spawnSync(binaries[name === 'missing-source' ? 'missing' : 'selected'], name === 'quoted-growth' ? [name, '', 'ascii', '日本語', '😀', 'x', 'y', 'z', 'tail'] : name === 'mimalloc-boundary' ? [name, 'x'.repeat(135)] : [name],
      {env, cwd:root, encoding:'utf8', timeout:10_000});
    assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
    assert.equal(run.stdout.trim(), 'original preargument wrapper passed');
  });
}
