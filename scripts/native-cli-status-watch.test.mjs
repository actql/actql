import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';

// Compile the actual selected private C boundary, injecting one syscall error
// while all other calls and signal/clock operations use the real OS. Each
// invocation owns only its new child process; no Run/Store/Provider is opened.
test('actual Native CLI watch C retains partial and unconfirmed signal cleanup', () => {
  const pin = process.env.MOON_HOME;
  assert.equal(typeof pin, 'string', 'use the existing pinned toolchain');
  const parent = resolve('_build/local-checks/status-watch-c');
  mkdirSync(parent, {recursive:true});
  const root = mkdtempSync(join(parent, 'probe-'));
  const executable = join(root, 'watch-probe');
  const compile = spawnSync('/usr/bin/cc', ['-I' + join(pin, 'include'),
    'scripts/fixtures/native-cli-status-watch.c', '-o', executable],
  {encoding:'utf8', timeout:20000, maxBuffer:65536});
  writeFileSync(join(root, 'compile.json'), JSON.stringify({status:compile.status,
    signal:compile.signal, stdout:compile.stdout, stderr:compile.stderr}) + '\n');
  assert.equal(compile.status, 0, compile.stderr);
  for (const name of ['normal', 'partial', 'restore', 'interrupted']) {
    const actual = spawnSync(executable, [name], {encoding:'utf8', timeout:2000,
      maxBuffer:65536});
    writeFileSync(join(root, name + '.json'), JSON.stringify({status:actual.status,
      signal:actual.signal, stdout:actual.stdout, stderr:actual.stderr}) + '\n');
    assert.equal(actual.status, 0, name + ': private C boundary refused');
    assert.deepEqual(JSON.parse(actual.stdout), {case:name,
      cleanup:name === 'restore' ? 'pending' : 'closed', newScope:false});
  }
});
