// Read-only acceptance diagnostics after the actual Native processes exit.
// This observes existing custody; it never creates or repairs a journal.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function describeNativeLocalJournal(records, capacity, claims) {
  let epoch = null;
  const originals = [];
  for (const row of records) {
    const bytes = Buffer.from(row.body);
    if (row.namespace !== 'client_submission_epoch') {
      originals.push({namespace: row.namespace, record_key: row.record_key,
        revision: row.revision, bodySha256: hash(bytes)});
      continue;
    }
    assert.equal(row.record_key, 'authority', 'Only the original epoch authority is admissible');
    assert.equal(epoch, null, 'Duplicate epoch custody');
    let body;
    try { body = JSON.parse(bytes.toString('utf8')); }
    catch { throw new Error('Malformed original epoch custody'); }
    assert(body !== null && typeof body === 'object' && !Array.isArray(body), 'Invalid epoch custody');
    assert(Object.keys(body).sort().join(',') === 'authentication_key,observed_at,version', 'Invalid epoch custody fields');
    assert(body.version === 'actql-native-submission-epoch-custody/0.1', 'Invalid epoch custody version');
    assert(typeof body.authentication_key === 'string', 'Invalid epoch authentication material');
    const key = Buffer.from(body.authentication_key, 'base64');
    assert.equal(key.length, 32);
    assert(key.toString('base64') === body.authentication_key, 'Invalid epoch authentication encoding');
    assert(Number.isSafeInteger(row.revision) && row.revision >= 0);
    assert(Number.isFinite(body.observed_at) && body.observed_at >= 0);
    // Keep only a digest of the secret key in diagnostics and receipts.
    epoch = {revision: row.revision, version: body.version,
      observedAt: body.observed_at, authenticationKeySha256: hash(key)};
  }
  return {records: originals, capacity, claims, epoch};
}

export function inspectNativeLocalJournal(path) {
  const database = new DatabaseSync(path, {readOnly: true});
  try {
    return describeNativeLocalJournal(
      database.prepare('SELECT namespace, record_key, revision, body FROM actql_records ORDER BY namespace, record_key').all(),
      database.prepare('SELECT * FROM actql_capacity ORDER BY namespace, reservation_key').all(),
      database.prepare('SELECT * FROM actql_claims ORDER BY namespace, claim_key').all());
  } finally { database.close(); }
}

export function assertNativeLocalJournalUnchanged(before, after, message) {
  assert.deepEqual(after.records, before.records, message);
  assert.deepEqual(after.capacity, before.capacity, message);
  assert.deepEqual(after.claims, before.claims, message);
  if (before.epoch === null || after.epoch === null) {
    assert.deepEqual(after.epoch, before.epoch, message);
    return;
  }
  assert.equal(after.epoch.version, before.epoch.version, message);
  assert.equal(after.epoch.authenticationKeySha256, before.epoch.authenticationKeySha256,
    'Lookup cannot replace the original epoch authentication key');
  assert(after.epoch.revision >= before.epoch.revision, 'Epoch custody revision cannot regress');
  assert(after.epoch.observedAt >= before.epoch.observedAt, 'Durable epoch clock cannot regress');
  if (after.epoch.observedAt !== before.epoch.observedAt) {
    assert(after.epoch.revision > before.epoch.revision, 'Changed clock requires its durable CAS');
  }
}
