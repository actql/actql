import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync,
  symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {gzipSync} from 'node:zlib';

test('trusted bootstrap parent preserves private child and original namespace', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit memory runtime is required');
  const source = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-bootstrap-parent-'));
  const executable = join(scratch, 'diagnostic');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    ...(process.env.ACTQL_DIAGNOSTIC_LEGACY === '1' ? ['-DACTQL_DIAGNOSTIC_LEGACY'] : []),
    '-I', join(process.env.MOON_HOME, 'include'),
    join(source, 'scripts/fixtures/native-bootstrap-parent.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: source, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  let cases = 0;
  const pids = [compile.pid];
  const fixtureAcls = [];
  function run(mode, path, expected) {
    const child = spawnSync(executable, [mode, path], {encoding: 'utf8', timeout: 5_000});
    assert.equal(child.status, 0, `${scratch}\n${child.error ?? ''}\n${child.stderr}`);
    assert.equal(child.stdout.trim(), expected);
    assert.throws(() => process.kill(child.pid, 0), {code: 'ESRCH'});
    pids.push(child.pid); cases++;
  }
  function directory(name, mode = 0o755) {
    const path = join(scratch, name);
    mkdirSync(path); chmodSync(path, mode);
    return path;
  }
  for (const [name, mode, expected] of [
    ['private', 0o700, '1 1'], ['home-755', 0o755, '1 0'],
    ['home-750', 0o750, '1 0'], ['group-write', 0o770, '0 0'],
    ['other-write', 0o707, '0 0'], ['all-write', 0o777, '0 0'],
    ['owner-no-write', 0o500, '0 0'],
  ]) run('probe', directory(name, mode), expected);
  const alias = join(scratch, 'alias');
  symlinkSync(directory('alias-target'), alias);
  run('probe', alias, '0 0');
  for (const mode of ['child', 'mode-change', 'replacement', 'alias-replacement', 'acl-failure', 'foreign-uid-metadata']) {
    run(mode, directory(mode), 'checked');
  }
  if (process.platform === 'darwin') {
    function acl(path, entry) {
      const child = spawnSync('/bin/chmod', ['+a', entry, path], {encoding: 'utf8', timeout: 5_000});
      assert.equal(child.status, 0, child.stderr); pids.push(child.pid); fixtureAcls.push(path);
    }
    const denied = directory('deny-only', 0o750);
    acl(denied, 'everyone deny delete');
    run('probe', denied, '1 0');
    run('child', denied, 'checked');
    const allowed = directory('allow-write');
    acl(allowed, 'everyone allow add_file');
    run('probe', allowed, '0 0');
    const mixed = directory('mixed');
    acl(mixed, 'everyone deny delete'); acl(mixed, 'everyone allow add_subdirectory');
    run('probe', mixed, '0 0');
  }
  const homeMetadataCases = process.env.ACTQL_BOOTSTRAP_PARENT_METADATA_PATH ? 1 : 0;
  if (homeMetadataCases) run('probe', process.env.ACTQL_BOOTSTRAP_PARENT_METADATA_PATH, '1 0');
  // Remove only ACLs installed by this fixture, never a parent/HOME ACL.
  for (const path of new Set(fixtureAcls)) {
    const child = spawnSync('/bin/chmod', ['-N', path], {encoding: 'utf8', timeout: 5_000});
    assert.equal(child.status, 0, child.stderr); pids.push(child.pid);
  }
  if (process.env.ACTQL_NATIVE_DIAGNOSTIC_OUTPUT) {
    const original = readFileSync(executable);
    writeFileSync(join(process.env.ACTQL_NATIVE_DIAGNOSTIC_OUTPUT, 'bootstrap-parent-diagnostic.gz'),
      gzipSync(original), {flag: 'wx', mode: 0o600});
  }
  assert.equal(cases, (process.platform === 'darwin' ? 18 : 14) + homeMetadataCases);
  pids.forEach(pid => assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'}));
  console.log(JSON.stringify({cases, physicalCases: cases - 1, foreignUidMetadataCases: 1, homeMetadataCases, platform: process.platform, pids,
    sourceSha256: createHash('sha256').update(readFileSync(join(source,
      'src/platform_native/filesystem/filesystem_stub.c'))).digest('hex'),
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    publicCliAcceptance: false, installedAcceptance: false}));
  rmSync(scratch, {recursive: true});
});
