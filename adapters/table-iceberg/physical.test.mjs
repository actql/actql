// Execute real optional Host I/O through the existing bounded Node test gate.
// No silent skip: this explicit test needs the pinned Table Host environment.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../../', import.meta.url));

test('pinned Iceberg physical I/O preserves and rejects presence states', () => {
  const run = spawnSync(process.env.ACTQL_TABLE_PYTHON ?? `${root}.venv-table/bin/python`,
    ['-m', 'unittest', '-v', 'physical_test'], {
      cwd: fileURLToPath(new URL('.', import.meta.url)),
      encoding: 'utf8', timeout: 60000, maxBuffer: 1024 * 1024,
    });
  assert.ifError(run.error);
  assert.equal(run.status, 0, run.stdout + run.stderr);
  assert.match(run.stderr, /Ran 5 tests/u);
  assert.match(run.stderr, /\nOK\n/u);
});

test('pinned Catalog publication binds original receipt atomically', () => {
  const run = spawnSync(process.env.ACTQL_TABLE_PYTHON ?? `${root}.venv-table/bin/python`,
    ['-m', 'unittest', '-v', 'catalog_test'], {
      cwd: fileURLToPath(new URL('.', import.meta.url)),
      encoding: 'utf8', timeout: 60000, maxBuffer: 1024 * 1024,
    });
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}${run.stderr}`);
  assert.match(run.stderr, /Ran 5 tests/u);
  assert.match(run.stderr, /\nOK\n/u);
});

test('stopped writer custody preserves published files and retries cleanup', () => {
  const run = spawnSync(process.env.ACTQL_TABLE_PYTHON ?? `${root}.venv-table/bin/python`,
    ['-m', 'unittest', '-v', 'custody_test'], {
      cwd: fileURLToPath(new URL('.', import.meta.url)),
      encoding: 'utf8', timeout: 60000, maxBuffer: 1024 * 1024,
    });
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}${run.stderr}`);
  assert.match(run.stderr, /Ran 7 tests/u);
  assert.match(run.stderr, /\nOK\n/u);
});
