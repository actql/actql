// Explicit optional Host test: missing dependencies refuse, never skip.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('real Arrow and Iceberg preserve the declared data channel', () => {
  const root = fileURLToPath(new URL('../../../../', import.meta.url));
  const result = spawnSync(process.env.ACTQL_TABLE_PYTHON ?? `${root}.venv-table/bin/python`,
    ['-B', '-m', 'unittest', '-v', 'data_channel_test', 'physical_test', 'process_worker_test'], {
      cwd: fileURLToPath(new URL('.', import.meta.url)), encoding: 'utf8',
      timeout: 30000, maxBuffer: 1024 * 1024,
      env: {...process.env, PYTHONDONTWRITEBYTECODE: '1'},
    });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /Ran 17 tests/u);
  assert.match(result.stderr, /\nOK\n/u);
});
