// Controlled boundaries test the real history validator and composition call site.
// Actual repository ancestry/blob/mode acceptance is a separate required check.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
for (const scenario of ['inspection-bundle', 'inspection-historical-edit', 'inspection-composition-reject']) {
  test(`one foundation inspection preserves validation: ${scenario}`, t => {
    const root = mkdtempSync(join(tmpdir(), 'actql-foundation-inspection-'));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    const result = spawnSync(process.execPath, ['--experimental-test-module-mocks',
      fileURLToPath(new URL('./fixtures/history-driver.mjs', import.meta.url)), root, scenario],
    {encoding: 'utf8', timeout: 20000, maxBuffer: 2 * 1024 * 1024});
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(JSON.parse(result.stdout.trim()).scenario, scenario);
  });
}
