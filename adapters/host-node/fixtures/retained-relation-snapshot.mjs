import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalJson} from '../local-account-config.mjs';

// Author the expected body from the independent Result oracle. These receipts
// certify save/revocation/reload on the original Task, whose restored generation
// subsequently supplies the live consumers and ordinary Result publication.
export function assertRetainedRelationSnapshots(snapshots, rows, minimum = 1) {
  const wire = canonicalJson(rows);
  const expected = {
    cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
    bytes: Buffer.byteLength(wire), verifiedReadBytes: Buffer.byteLength(wire),
    rows: rows.length, sourceReleased: true, sourceReadRejected: true,
    restored: true, temporaryBodyReclaimed: true,
  };
  assert.ok(Array.isArray(snapshots));
  const matching = snapshots.filter(snapshot => snapshot.cid === expected.cid);
  assert.ok(matching.length >= minimum, 'original output and consumer generations cross the Store');
  const tasks = new Set();
  for (const {task, ...snapshot} of matching) {
    assert.ok(Number.isSafeInteger(task) && task >= 0 && !tasks.has(task));
    tasks.add(task);
    assert.deepEqual(snapshot, expected);
  }
}
