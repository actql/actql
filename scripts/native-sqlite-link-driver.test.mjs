import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('native SQLite link driver rescans dependency-first archives without changing the implementation', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-link-'));
  const driver = fileURLToPath(new URL('./native-sqlite-link-driver.sh', import.meta.url));
  const run = (command, args) => spawnSync(command, args, {cwd: root, encoding: 'utf8'});
  const success = result => assert.equal(result.status, 0, result.stderr || result.error?.message);
  try {
    writeFileSync(join(root, 'provider.c'), 'int timing_count(void) { return 7; }\n');
    writeFileSync(join(root, 'sqlite.c'), 'int timing_count(void); int sqlite_count(void) { return timing_count(); }\n');
    writeFileSync(join(root, 'main.c'), 'int sqlite_count(void); int main(void) { return sqlite_count() == 7 ? 0 : 1; }\n');
    for (const name of ['provider', 'sqlite', 'main']) {
      success(run(driver, ['-c', `${name}.c`, '-o', `${name}.o`]));
    }
    for (const name of ['provider', 'sqlite']) {
      success(run(process.env.AR || 'ar', ['rcs', `${name}.a`, `${name}.o`]));
    }
    const args = ['main.o', 'provider.a', 'sqlite.a', '-o', 'test'];
    if (process.platform === 'linux') {
      assert.notEqual(run(process.env.CC || 'cc', args).status, 0,
        'The dependency-first fixture must expose GNU archive ordering');
    }
    success(run(driver, args));
    success(run(join(root, 'test'), []));
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});
