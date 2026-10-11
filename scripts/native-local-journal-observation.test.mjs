import assert from 'node:assert/strict';
import {test} from 'node:test';
import {describeNativeLocalJournal, assertNativeLocalJournalUnchanged} from './native-local-journal-observation.mjs';

const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const keySha256 = '66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925';
const records = [
  {namespace: 'client_submission_epoch', record_key: 'authority', revision: 0,
    body: Buffer.from(JSON.stringify({authentication_key: key, observed_at: 100,
      version: 'actql-native-submission-epoch-custody/0.1'}))},
  {namespace: 'original-run', record_key: 'original', revision: 2, body: Buffer.from('immutable-run')},
];
const capacity = [{namespace: 'original-run', reservation_key: 'reserved-original',
  reserved_bytes: 1024, reserved_objects: 1}];
const claims = [{namespace: 'original-run', claim_key: 'original-claim', ordinal: 1}];
const original = () => describeNativeLocalJournal(records, structuredClone(capacity), structuredClone(claims));

test('Native journal diagnostics retain exact originals without publishing secret key bytes', () => {
  const snapshot = original();
  assert.equal(snapshot.epoch.authenticationKeySha256, keySha256);
  assert.equal(JSON.stringify(snapshot).includes(key), false);
  assert.equal(JSON.stringify(snapshot).includes('immutable-run'), false);
  assertNativeLocalJournalUnchanged(snapshot, original());
});

test('Native original lookup permits only the durable epoch clock progression', () => {
  const before = original(), after = original();
  after.epoch.revision = 1; after.epoch.observedAt = 101;
  assertNativeLocalJournalUnchanged(before, after);
  const sameTime = original(); sameTime.epoch.revision = 1;
  assertNativeLocalJournalUnchanged(before, sameTime);
  for (const change of [
    value => { value.epoch.authenticationKeySha256 = 'changed-key'; },
    value => { value.epoch.observedAt = 99; },
    value => { value.epoch.revision = -1; },
    value => { value.epoch.observedAt = 101; },
    value => { value.epoch = null; },
  ]) {
    const changed = original(); change(changed);
    assert.throws(() => assertNativeLocalJournalUnchanged(before, changed));
  }
});

test('Native clock advancement cannot hide operation grant capacity or claim mutations', () => {
  const before = original();
  for (const change of [
    value => { value.records[0].revision++; },
    value => { value.records[0].bodySha256 = 'changed-original'; },
    value => { value.records.push({namespace: 'new-grant', record_key: 'new', revision: 0, bodySha256: 'unexpected'}); },
    value => { value.records = []; },
    value => { value.capacity[0].reserved_bytes--; },
    value => { value.capacity = []; },
    value => { value.claims[0].ordinal++; },
    value => { value.claims = []; },
  ]) {
    const changed = original(); changed.epoch.revision = 1; changed.epoch.observedAt = 101;
    change(changed);
    assert.throws(() => assertNativeLocalJournalUnchanged(before, changed));
  }
});

test('Native Store journals without epoch history require complete unchanged custody', () => {
  const snapshot = describeNativeLocalJournal(records.slice(1), capacity, claims);
  assert.equal(snapshot.epoch, null);
  assertNativeLocalJournalUnchanged(snapshot, structuredClone(snapshot));
  const changed = structuredClone(snapshot); changed.epoch = original().epoch;
  assert.throws(() => assertNativeLocalJournalUnchanged(snapshot, changed));
});

test('Native malformed epoch custody refuses without showing the original body', () => {
  const secret = 'retained-secret-must-not-be-printed';
  assert.throws(() => describeNativeLocalJournal([{...records[0], body: Buffer.from(secret)}], [], []),
    error => error.message === 'Malformed original epoch custody' && !error.message.includes(secret));
  assert.throws(() => describeNativeLocalJournal([{...records[0], record_key: 'foreign'}], [], []));
  assert.throws(() => describeNativeLocalJournal([records[0], records[0]], [], []));
});
