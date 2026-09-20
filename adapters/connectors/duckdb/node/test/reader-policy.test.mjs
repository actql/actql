import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedReaderPolicy} from '../examples/reader-policy.mjs';

const profile = () => ({source_rows: 100, task_rows: 100, columns: 64, value_bytes: 2048,
  wire_bytes: 1000000, value_nodes: 100000, text_bytes: 1000000, work: 1000000,
  entries: 100000, batch_bytes: 1000});

test('reader bounds use the configured schema and simultaneous frame, not cumulative counts', () => {
  const supplied = profile();
  const policy = retainedReaderPolicy(supplied);
  assert.equal(policy.recordLimits.maxColumns, 64);
  assert.equal(policy.decodeLimits.max_nodes, 1000);
  assert.equal(policy.scratchBytes, 3056000n);
  supplied.columns = 1;
  supplied.batch_bytes = 1;
  assert.equal(policy.recordLimits.maxColumns, 64);
  assert.equal(policy.decodeLimits.max_bytes, 1000);
  const larger = retainedReaderPolicy({...profile(), source_rows: 10000, task_rows: 10000,
    value_nodes: 1000000, text_bytes: 10000000, work: 10000000});
  assert.equal(larger.scratchBytes, policy.scratchBytes);
  assert.equal(larger.frameLimits.maxRows, 10000);
  assert.equal(retainedReaderPolicy({...profile(), batch_bytes: 1001}).scratchBytes,
    policy.scratchBytes + 1056n);
});

test('reader rejects invalid profiles before reserving and keeps bounded defaults', () => {
  assert.throws(() => retainedReaderPolicy({...profile(), batch_bytes: 1000001}), /InvalidApplicationDataProfile/);
  assert.throws(() => retainedReaderPolicy({...profile(), columns: 257}), /InvalidApplicationDataProfile/);
  const policy = retainedReaderPolicy();
  assert.equal(policy.recordLimits.maxColumns, 10);
  assert.equal(policy.decodeLimits.max_nodes, 10000);
  assert(policy.scratchBytes < 268435456n);
  assert(Object.isFrozen(policy.decodeLimits));
});
