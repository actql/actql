import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readdirSync, statSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// Real harness startup failure before any Native work, not a passing mock CLI.
test('Native runtime harness retains its owned root after compiler launch failure', () => {
  const parent = mkdtempSync(join(tmpdir(), 'native-runtime-custody-'));
  try {
    const result = spawnSync(process.execPath,
      [fileURLToPath(new URL('./test-native-remote-runtime.mjs', import.meta.url)), '--values-https-only'],
      {encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024,
        env: {...process.env, ACTQL_TEST_SCRATCH_ROOT: parent,
          MOON_HOME: join(parent, 'missing-toolchain'), ACTQL_TEST_PRESERVE_SCRATCH: '0'}});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /ENOENT/u);
    const roots = readdirSync(parent).filter(name => name.startsWith('native-remote-runtime-'));
    assert.equal(roots.length, 1);
    const root = join(parent, roots[0]);
    assert.match(result.stdout, /Native remote runtime scratch kept:/u);
    assert.equal(statSync(root).isDirectory(), true);
    for (const owned of ['store', 'agent', 'standard', 'values', 'values-https']) {
      assert.equal(statSync(join(root, owned)).isDirectory(), true);
    }
  } finally {
    // This test created the namespace and never started a Native process/DB.
    rmSync(parent, {recursive: true, force: true});
  }
});
