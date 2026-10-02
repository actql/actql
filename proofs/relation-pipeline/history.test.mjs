import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
function run(scenario) {
  const root = mkdtempSync(join(tmpdir(), 'actql-pipeline-history-'));
  try {
    return spawnSync(process.execPath, ['--experimental-test-module-mocks',
      fileURLToPath(new URL('./fixtures/history-driver.mjs', import.meta.url)), root, scenario], { encoding: 'utf8' });
  } finally { rmSync(root, { recursive: true, force: true }); }
}
test('frozen migration checks exact historical, committed and working-tree bytes', () => {
  const result = run('valid');
  assert.equal(result.status, 0, result.stderr);
});
for (const scenario of ['historical-edit', 'historical-remove-entry', 'historical-add-entry',
  'missing-baseline', 'missing-historical-object', 'missing-baseline-object', 'missing-current-object',
  'changed-ci', 'changed-unlisted-file', 'unlisted-change', 'spurious-change', 'duplicate-change',
  'unknown-change', 'fake-before', 'fake-after', 'record-and-source-edit', 'wrong-anchor',
  'wrong-baseline-digest', 'wrong-baseline-revision', 'missing-addition', 'duplicate-addition',
  'changed-addition', 'missing-addition-object', 'uncommitted-record', 'missing-record', 'non-ancestor']) {
  test(`frozen migration rejects ${scenario}`, () => {
    const result = run(scenario);
    assert.notEqual(result.status, 0, 'Invalid foundation was accepted');
    assert.match(result.stderr, /AssertionError|ENOENT/);
  });
}

test('repository foundation composes exact declared source at HEAD', async () => {
  const { checkFoundation, currentFoundation } = await import('./history.mjs');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  checkFoundation(root);
  const first = currentFoundation(root);
  assert.equal(JSON.stringify(first), JSON.stringify(currentFoundation(root)), 'Nondeterministic repository foundation');
  const head = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' });
  assert.equal(head.status, 0);
  assert.equal(first.sourceRevision, head.stdout.trim());
});
