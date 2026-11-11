import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute only the real verification fixture's synchronization seam. No Host,
// Model, Evidence replacement, runtime build or physical resource is created.
const source = readFileSync(new URL('./source-multi-infer-evidence-worker.fixture.mjs', import.meta.url), 'utf8');
const declaration = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'captureSinkWithCompletion');
assert.ok(declaration);
const wrap = Function('assert', `${source.slice(declaration.start, declaration.end)}\nreturn captureSinkWithCompletion;`)(assert);
const subject = Object.freeze({runDefinitionCid: 'original-run', authorityScopeCid: 'original-scope'});

function fixture() {
  const writes = new Map(['first', 'second'].map(target => [target, Promise.withResolvers()]));
  const calls = [];
  const original = {
    capture(value) {assert.strictEqual(this, original); return value;},
    async record(receipt) {assert.strictEqual(this, original); calls.push(['record', receipt.target]);
      await writes.get(receipt.target).promise; return receipt.target;},
    async lookup(actual, target) {assert.strictEqual(this, original); calls.push(['lookup', target]);
      assert.deepEqual(actual, subject); return {subject: actual, target};},
    pendingBytes() {assert.strictEqual(this, original); return 0;},
    cleanupPending() {assert.strictEqual(this, original); return false;},
  };
  return {writes, calls, original, sink: wrap(original, ['first', 'second'])};
}

test('each Evidence lookup waits for its own actual sink record settlement', async () => {
  const f = fixture();
  const first = f.sink.record({subject, target: 'first'});
  const firstLookup = f.sink.lookup(subject, 'first');
  let secondRead = false;
  const secondLookup = f.sink.lookup(subject, 'second').then(value => {secondRead = true; return value;});
  await Promise.resolve();
  assert.deepEqual(f.calls, [['record', 'first']]);
  f.writes.get('first').resolve();
  assert.equal(await first, 'first');
  assert.equal((await firstLookup).target, 'first');
  assert.equal(secondRead, false, 'One target cannot acknowledge the other target');
  const second = f.sink.record({subject, target: 'second'});
  f.writes.get('second').resolve();
  await second;
  assert.equal((await secondLookup).target, 'second');
  assert.equal(f.sink.pendingBytes(), 0);
  assert.equal(f.sink.cleanupPending(), false);
  const value = {};
  assert.strictEqual(f.sink.capture(value), value);
});

test('an original undefined sink failure remains a failure for the later lookup', async () => {
  const f = fixture();
  const write = f.sink.record({subject, target: 'first'});
  f.writes.get('first').reject(undefined);
  let writeFailed = false;
  try {await write;} catch (cause) {writeFailed = true; assert.strictEqual(cause, undefined);}
  assert.equal(writeFailed, true);
  let lookupFailed = false;
  try {await f.sink.lookup(subject, 'first');}
  catch (cause) {lookupFailed = true; assert.strictEqual(cause, undefined);}
  assert.equal(lookupFailed, true);
  assert.deepEqual(f.calls, [['record', 'first']]);
});

test('a different recorded subject cannot acknowledge the requested original', async () => {
  const f = fixture();
  const write = f.sink.record({subject: {...subject, runDefinitionCid: 'other-run'}, target: 'first'});
  f.writes.get('first').resolve();
  await write;
  await assert.rejects(f.sink.lookup(subject, 'first'), assert.AssertionError);
  assert.deepEqual(f.calls, [['record', 'first']]);
});
