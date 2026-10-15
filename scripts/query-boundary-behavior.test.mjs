import test from 'node:test';
import assert from 'node:assert/strict';
import * as authorization from '../adapters/host-common/authorization-gate.mjs';
import * as transaction from '../adapters/host-common/sqlite-transaction.mjs';
import * as strategy from '../adapters/host-common/strategy.mjs';
import {installTaskObservation, projectTaskObservation} from '../adapters/host-common/task-observation.mjs';
import {authorizationBoundary, cleanupBoundary, unknownCommitBoundary} from './query-boundary-behavior.fixture.mjs';
import {hostApprovalBoundary, hostCompletionBoundary, hostPreflightCustodyBoundary} from './query-host-boundary.fixture.mjs';

// These exercise real adapter/SQLite boundaries. They do not claim full Host
// execution, Common semantic completion, recovery acceptance or installed E2E.
// The corresponding Host/Site and typed Core suites keep those responsibilities.

test('approval refuses protected dispatch before physical work', async () => {
  await authorizationBoundary(authorization);
});
test('failed cleanup retains its owner through retries and closes exactly once', () => {
  cleanupBoundary(transaction);
});
test('failed COMMIT remains Unknown after rollback without repeating physical work', () => {
  unknownCommitBoundary(transaction);
});
test('Host refuses activation before dispatch through its installed authorization gate', async () => {
  await hostApprovalBoundary(strategy);
});
test('Host uses exact registrations and Common completion rather than callback success', async () => {
  await hostCompletionBoundary(strategy);
});
test('Host transfers preflight cleanup custody before fallible physical stop', async () => {
  await hostPreflightCustodyBoundary(strategy);
});
test('optional task observation receives frozen facts and cannot change execution by throwing', () => {
  const seen = [];
  const observer = installTaskObservation(value => {
    seen.push(value);
    assert.ok(Object.isFrozen(value));
    throw new Error('observer failure');
  });
  projectTaskObservation(observer, 'completed', 7, 12);
  projectTaskObservation({...observer}, 'completed', 8, 13);
  assert.deepEqual(seen, [{event: 'completed', task: 7, durationMs: 12}]);
});
