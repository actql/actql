import assert from 'node:assert/strict';

// Node's outer runner exits 1 when the process-isolated fixture exits 77.
// Require its structured file failure; warning text and PIDs are not exits.
// The caller must separately inspect the original durable seed and row states.
export function assertPartialEffectSeedExit(result, file) {
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  assert.equal(result.error, undefined, output);
  assert.equal(result.signal, null, output);
  assert.equal(result.status, 1, output);
  const marker = 'ACTQL_TEST_CASE ';
  const cases = (result.stdout ?? '').split(/\r?\n/u)
    .filter(line => line.startsWith(marker))
    .map(line => JSON.parse(line.slice(marker.length)));
  assert.equal(cases.length, 1, `Expected one crashed fixture file\n${output}`);
  const entry = cases[0];
  assert.deepEqual({name: entry.name, file: entry.file, passed: entry.passed,
    skipped: entry.skipped, todo: entry.todo, failureType: entry.failureType,
    errorCode: entry.errorCode, exitCode: entry.exitCode, signal: entry.signal},
  {name: file, file, passed: false, skipped: false, todo: false,
    failureType: 'testCodeFailure', errorCode: 'ERR_TEST_FAILURE', exitCode: 77, signal: null},
  `The original fixture process must exit 77 without a signal\n${output}`);
}
