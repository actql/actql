import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedCase, retainedMatrix, workloads} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';

test('managed benchmark settings preserve independent cumulative and per-case ceilings', () => {
  const fixture = retainedCase(workloads[1], 'narrow', 100);
  const config = managedCaseConfiguration(fixture, {}, '/source', '/store');
  assert.equal(config.finalTask, 4);
  assert.equal(config.input.dataProfile.source_rows, 100);
  assert.equal(config.input.dataProfile.task_rows, 200);
  assert.equal(config.input.dataProfile.batch_bytes, 6400);
  assert.equal(config.limits.planning_work, 125600);
  // Source/capture allowance 19,200 plus five 232,192-byte task envelopes.
  assert.equal(config.limits.transfer_bytes, 1180160n);
  assert.equal(config.limits.attempts, 12);
  assert.equal(config.childLimits.attempts, 10);
  assert.equal(config.limits.execution_bytes, 4294967296n);
});

test('every registered profile uses snapshotted shared setup without changing pinned fixtures', () => {
  for (const fixture of retainedMatrix()) {
    const contracts = {query: 'original'};
    const config = managedCaseConfiguration(fixture, contracts, '/source', '/store');
    contracts.query = 'changed';
    assert.equal(config.input.query, 'original');
    assert.equal(config.input.database, '/source');
    assert.equal(config.input.retainedOutput.parentDirectory, '/store');
    assert.equal(config.input.retainedOutput.wire.max_bytes, fixture.limits.representationBytes);
    assert.equal(config.timeoutMs, fixture.limits.timeoutMs);
    assert(Object.isFrozen(config.input.dataProfile));
    assert(Object.isFrozen(config.input.retainedOutput.wire));
    assert.deepEqual(JSON.parse(config.input.programText), fixture.program());
  }
});
