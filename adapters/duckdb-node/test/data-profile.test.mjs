import test from 'node:test';
import assert from 'node:assert/strict';
import {snapshotDataProfile} from '../examples/data-profile.mjs';

test('explicit data profile snapshots exact integers and rejects cumulative receiver overflow', () => {
  const input = {source_rows: 1000, task_rows: 2000, columns: 64,
    value_bytes: 2048, wire_bytes: 1000000, value_nodes: 200000,
    text_bytes: 1000000, work: 10000000, entries: 200000, batch_bytes: 100000};
  const snapshot = snapshotDataProfile(input);
  input.source_rows = 1;
  assert.equal(snapshot.source_rows, 1000);
  assert(Object.isFrozen(snapshot));
  assert.equal(snapshotDataProfile(undefined), undefined);
  for (const invalid of [null, {}, {...snapshot, extra: 1}, {...snapshot, work: 0},
    {...snapshot, task_rows: 0.5}, {...snapshot, wire_bytes: 2147483648},
    {...snapshot, wire_bytes: 715827883},
    {...snapshot, batch_bytes: 1000001}, {...snapshot, columns: 257},
    {...snapshot, source_rows: 20000000, task_rows: 20000000}]) {
    assert.throws(() => snapshotDataProfile(invalid), /InvalidApplicationDataProfile/);
  }
});
