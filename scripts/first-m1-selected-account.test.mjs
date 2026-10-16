// Independent application bytes/conditions only. These do not admit an Account
// or prove Host/Checkpoint/Provider permission, funding or public acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {firstM1AccountConfiguration, firstM1ProviderId, firstM1InferEntryId,
  firstM1ReviewerId} from './fixtures/first-m1-selected-account.mjs';

const task = 'sha256:' + '1'.repeat(64);
test('first M1 selected Account delegates Model and limits raw capture to the same original tuple', () => {
  const value = JSON.parse(firstM1AccountConfiguration('selected-local-principal', task));
  assert.equal(value.version, 'actql-execution-account-config/0.1');
  assert.equal(value.account_id, 'first-m1-owner');
  assert.equal(firstM1ProviderId, 'models/fixture');
  assert.equal(firstM1ReviewerId, 'first-m1-reviewer');
  assert.deepEqual(value.entries.map(entry => [entry.entry_id, entry.outcome]), [
    ['first-m1-infer', 'delegate'], ['first-m1-raw', 'allow'], ['first-m1-run', 'allow'],
  ]);
  assert.equal(value.entries[0].entry_id, firstM1InferEntryId);
  for (const entry of value.entries) {
    assert.deepEqual(entry.principal, {any_of: ['selected-local-principal']});
    assert.deepEqual(entry.exclusions, []);
  }
  for (const entry of value.entries.slice(0, 2)) {
    assert.deepEqual(entry.connection, {any_of: ['models/fixture']});
    assert.deepEqual(entry.resource, {any_of: [task]});
  }
  assert.deepEqual(value.entries.map(entry => entry.operation), [
    {any_of: ['infer']}, {any_of: ['model_raw_capture']}, {any_of: ['write']},
  ]);
});

test('first M1 selected Account authors sorted input fields without changing principal text', () => {
  const principal = 'original e\u0301\r\n';
  const wire = firstM1AccountConfiguration(principal, task);
  const value = JSON.parse(wire);
  const checkOrder = item => {
    if (Array.isArray(item)) {for (const value of item) checkOrder(value);}
    else if (item !== null && typeof item === 'object') {
      assert.deepEqual(Object.keys(item), Object.keys(item).sort());
      for (const value of Object.values(item)) checkOrder(value);
    }
  };
  checkOrder(value);
  assert.equal(value.entries[0].principal.any_of[0], principal);
  assert.equal(firstM1AccountConfiguration(principal, task), wire);
});

test('first M1 selected name ceiling is existing UTF16 units rather than UTF8 or an arbitrary principal', () => {
  const principal = '\u0800'.repeat(512);
  assert.equal(Buffer.byteLength(principal), 1536);
  assert.equal(JSON.parse(firstM1AccountConfiguration(principal, task))
    .entries[0].principal.any_of[0], principal);
  for (const invalid of ['', null, {}, 'a'.repeat(513), '\ud83d\ude00'.repeat(257)]) {
    assert.throws(() => firstM1AccountConfiguration(invalid, task), TypeError);
  }
  for (const invalid of ['', task.slice(0, -1), 'sha256:' + 'A'.repeat(64)]) {
    assert.throws(() => firstM1AccountConfiguration('original', invalid), TypeError);
  }
});
