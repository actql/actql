import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Execute the exact private method source, with an isolated nominal-map
// fixture and a consumed-token failure. This is a state-transition unit test,
// NOT a Core resource admission/public Run or a forged supplier original.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const start = source.indexOf('    severPreparation(prepared, original) {');
const end = source.indexOf('    retireSeveredPreparation(original) {', start);
assert.ok(start >= 0 && end > start, 'private method source must remain identifiable');
const method = source.slice(start, end).trim().replace(/,$/, '');
function fixture(body = method) {
  const prepared = Object.freeze({}), original = Object.freeze({}), holder = Object.freeze({});
  let cuts = 0, returns = 0;
  const consumed = Object.assign(new Error('injected consumed-token settlement pending'), {code: 'CleanupPending'});
  const state = {adopting: true, prepared, holder, parent: Object.freeze({}), context: {runtime: {
    clientProgramPreparationBorrowRead(token) {
      if(token!==holder)return undefined;
      cuts++;return prepared;
    },
    clientProgramPreparationBorrowRetirementStarted(token) {
      assert.equal(token,holder);return true;
    },
    clientProgramPreparationBorrowReturn(token) {
      assert.equal(token, holder); returns++; return {error: consumed};
    },
  }}};
  const producer = {preparation: state, body: Object.freeze({}), request: Object.freeze({}), snapshotPublication: Object.freeze({})};
  const run = {original, prepared, request: producer.request, producer};
  const runs = new WeakMap([[prepared, run]]);
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const checked = result => {if (result.error) throw result.error; return result.value;};
  const cut = Function('runs', 'fail', 'checked', `return ({${body}}).severPreparation;`)(runs, fail, checked);
  return {cut, prepared, original, state, producer, run, consumed, counts: () => ({cuts, returns})};
}

test('manager retries an already witnessed cut after consumed-token return failure', () => {
  const f = fixture();
  assert.throws(() => f.cut(f.prepared, f.original), error => error === f.consumed);
  assert.equal(f.state.holder, undefined);
  for (const value of [f.state.prepared, f.run.prepared, f.run.request, f.producer.body, f.producer.request, f.producer.snapshotPublication]) {
    assert.equal(value, undefined);
  }
  f.cut(f.prepared, f.original);
  f.cut(f.prepared, f.original);
  assert.deepEqual(f.counts(), {cuts: 1, returns: 1});
  assert.throws(() => f.cut(f.prepared, {}), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => f.cut({}, f.original), {code: 'ForeignInstalledSourceProducer'});
});

test('a missing holder is not proof of completed alias severing or Run adoption', () => {
  const f = fixture();
  f.state.holder = undefined;
  assert.throws(() => f.cut(f.prepared, f.original), {code: 'ForeignInstalledSourceProducer'});
  f.state.prepared = f.run.prepared = f.run.request = f.producer.body = f.producer.request = f.producer.snapshotPublication = undefined;
  f.state.adopting = false;
  assert.throws(() => f.cut(f.prepared, f.original), {code: 'ForeignInstalledSourceProducer'});
  assert.deepEqual(f.counts(), {cuts: 0, returns: 0});
});

test('mutation guard reproduces old retry failure when completed-cut branch is absent', () => {
  const begin = method.indexOf('      if (state.holder === undefined) {');
  const next = method.indexOf('      const moon = state.context.runtime;', begin);
  assert.ok(begin >= 0 && next > begin);
  const old = method.slice(0, begin) + method.slice(next);
  const f = fixture(old);
  assert.throws(() => f.cut(f.prepared, f.original), error => error === f.consumed);
  assert.throws(() => f.cut(f.prepared, f.original), {code: 'ForeignInstalledSourceProducer'});
  assert.deepEqual(f.counts(), {cuts: 1, returns: 1});
});
