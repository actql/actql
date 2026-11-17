import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

// Physical row wire sorts names and preserves Text verbatim. Host-local
// identity canonicalJson also NFC-normalizes Text, so it is not this oracle.
// These independently authored receipts
// certify save/revocation/reload on the original Task, whose restored generation
// subsequently supplies the live consumers and ordinary Result publication.
export function assertRetainedRelationSnapshots(snapshots, rows, minimum = 1) {
  const wire = JSON.stringify(rows, (_key, value) => {
    if (value === null || Array.isArray(value) || typeof value !== 'object') return value;
    return Object.fromEntries(Object.entries(value).sort(([left], [right]) =>
      left < right ? -1 : left > right ? 1 : 0));
  });
  const expected = {
    cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
    bytes: Buffer.byteLength(wire), verifiedReadBytes: Buffer.byteLength(wire),
    rows: rows.length, sourceReleased: true, sourceReadRejected: true,
    restored: true, temporaryBodyReclaimed: true,
  };
  assert.ok(Array.isArray(snapshots));
  const matching = snapshots.filter(snapshot => snapshot.cid === expected.cid);
  assert.ok(matching.length >= minimum, JSON.stringify({
    requirement: 'original output and consumer generations cross the Store', expected,
    actual: snapshots.map(({task, cid, bytes, verifiedReadBytes, rows,
      sourceReleased, sourceReadRejected, restored, temporaryBodyReclaimed}) =>
      ({task, cid, bytes, verifiedReadBytes, rows, sourceReleased,
        sourceReadRejected, restored, temporaryBodyReclaimed})),
  }));
  const tasks = new Set();
  for (const {task, ...snapshot} of matching) {
    assert.ok(Number.isSafeInteger(task) && task >= 0 && !tasks.has(task));
    tasks.add(task);
    assert.deepEqual(snapshot, expected);
  }
}
