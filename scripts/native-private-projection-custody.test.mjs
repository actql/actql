import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync,
  rmSync, statSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('original private projection restores in a different exited-process lifetime', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-projection-custody-'));
  const executable = join(scratch, 'diagnostic');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-private-projection-custody.c'),
    join(root, 'src/platform_native/filesystem/filesystem_stub.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${scratch}\n${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  let cases = 0;
  function run(mode, directory, original, expected) {
    const child = spawnSync(executable, [mode, directory, original],
      {encoding: 'utf8', timeout: 5_000});
    assert.equal(child.status, expected, `${scratch}\n${child.error ?? ''}\n${child.stderr}`);
    assert.throws(() => process.kill(child.pid, 0), {code: 'ESRCH'});
    return child.pid;
  }
  function fixture(name) {
    const directory = join(scratch, name);
    mkdirSync(directory, {mode: 0o700});
    writeFileSync(join(directory, 'bearer'), 'fixture-token\n', {mode: 0o600});
    const original = join(scratch, `${name}.original`);
    const pid = run('adopt', directory, original, 0);
    return {directory, original, pid};
  }
  function refuses(name, change) {
    const item = fixture(name);
    change(item);
    run('restore', item.directory, item.original, 3);
    cases++;
  }
  const item = fixture('original');
  assert.notEqual(run('restore', item.directory, item.original, 0), item.pid);
  const encoded = readFileSync(item.original);
  // Independent representation expectation; no struct layout or product oracle.
  assert.equal(encoded.length, 112);
  assert.deepEqual([...encoded.subarray(0, 10)],
    [65, 81, 76, 80, 70, 80, 48, 49, process.platform === 'darwin' ? 1 : 2, 6]);
  assert.equal(encoded.subarray(106).toString(), 'bearer');
  const rootStat = statSync(item.directory, {bigint: true});
  const fileStat = statSync(join(item.directory, 'bearer'), {bigint: true});
  const facts = [rootStat.dev, rootStat.ino, fileStat.dev, fileStat.ino,
    fileStat.mode, fileStat.uid, fileStat.gid, fileStat.size,
    fileStat.mtimeNs / 1_000_000_000n, fileStat.mtimeNs % 1_000_000_000n,
    fileStat.ctimeNs / 1_000_000_000n, fileStat.ctimeNs % 1_000_000_000n];
  facts.forEach((value, index) => assert.equal(encoded.readBigUInt64BE(10 + index * 8), value));
  assert(!encoded.includes(Buffer.from('fixture-token')));
  cases++;
  refuses('replacement', ({directory}) => {
    renameSync(join(directory, 'bearer'), join(directory, 'retired'));
    writeFileSync(join(directory, 'bearer'), 'fixture-token\n', {mode: 0o600});
  });
  refuses('root-replacement', ({directory}) => {
    renameSync(directory, `${directory}-retired`);
    mkdirSync(directory, {mode: 0o700});
    writeFileSync(join(directory, 'bearer'), 'fixture-token\n', {mode: 0o600});
  });
  refuses('rename', ({directory}) => renameSync(join(directory, 'bearer'), join(directory, 'retired')));
  refuses('symlink', ({directory}) => {
    renameSync(join(directory, 'bearer'), join(directory, 'retired'));
    symlinkSync('retired', join(directory, 'bearer'));
  });
  refuses('revoked-root', ({directory}) => chmodSync(directory, 0o750));
  refuses('revoked-file', ({directory}) => chmodSync(join(directory, 'bearer'), 0o640));
  refuses('missing-original', ({original}) => rmSync(original));
  for (const [name, mutate] of [
    ['corrupt-version', value => {value[0] ^= 1;}],
    ['foreign-platform', value => {value[8] = value[8] === 1 ? 2 : 1;}],
    ['invalid-name', value => {value[106] = 47;}],
    ['invalid-time', value => {value.writeBigUInt64BE(1_000_000_000n, 82);}],
    ['corrupt-file-identity', value => {value[41] ^= 1;}],
  ]) refuses(name, ({original}) => {
    const body = readFileSync(original); mutate(body); writeFileSync(original, body);
  });
  refuses('truncated', ({original}) => writeFileSync(original, encoded.subarray(0, 111)));
  refuses('trailing', ({original}) => writeFileSync(original, Buffer.concat([encoded, Buffer.from([0])])));
  assert.equal(cases, 15);
  console.log(JSON.stringify({cases, executedTarget: process.platform,
    sourceSha256: createHash('sha256').update(readFileSync(join(root,
      'src/platform_native/filesystem/filesystem_stub.c'))).digest('hex'),
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    publicAcceptance: false, authenticatedHostCustody: false}));
  rmSync(scratch, {recursive: true});
});
