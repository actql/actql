import test from 'node:test';
import assert from 'node:assert/strict';
import {registerRetainedInput} from '../store-local/representations.mjs';
import {readLocalRetainedInput} from './retained-input.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const bytes = text => new TextEncoder().encode(text);
const checked = result => { if (result?.error) throw result.error; return result; };
function fixture(consume, overrides = {}) {
  const material = {}, input = {}, events = [];
  registerRetainedInput(material, read => read === input, {consume},
    {wire: {max_bytes: 100}, maxFrameBytes: 64});
  const operation = {material, input,
    frames: {maxBytes: 100, maxRows: 3, maxRowBytes: 64, maxDepth: 4, maxFrameBytes: 64},
    begin: () => events.push('begin'),
    charge: value => events.push(['charge', value]),
    append: value => events.push(['row', value]),
    finish: () => events.push('finish'),
    ...overrides,
  };
  return {operation, events};
}

test('Local retained reader charges provisional bytes and verifies only after the Store read completes', async () => {
  let events;
  const f = fixture(async accept => {
    await accept(bytes('[{"id":3}'));
    await accept(bytes(']'));
    events.push('store-verified');
  });
  events = f.events;
  assert.deepEqual(await readLocalRetainedInput(moon, f.operation, checked),
    {bytes: 10, rows: 1});
  assert.deepEqual(events, ['begin', ['charge', 9n], ['row', '{"id":3}'],
    ['charge', 1n], 'store-verified', 'finish']);
});

test('Store failure after rows, including a reasonless rejection, cannot finish a Local import', async () => {
  for (const failure of [new Error('physical integrity'), undefined, null]) {
    const f = fixture(async accept => { await accept(bytes('[{"id":3}]')); throw failure; });
    let failed = false;
    try { await readLocalRetainedInput(moon, f.operation, checked); }
    catch (error) { failed = true; assert.equal(error, failure); }
    assert.equal(failed, true);
    assert.deepEqual(f.events, ['begin', ['charge', 10n], ['row', '{"id":3}']]);
  }
});

test('Local import rejects unreserved bytes before row acceptance and preserves the failure', async () => {
  const failure = new Error('TransferLimit');
  const f = fixture(async accept => { await accept(bytes('[{}]')); },
    {charge: () => ({error: failure})});
  await assert.rejects(readLocalRetainedInput(moon, f.operation, checked),
    error => error === failure);
  assert.deepEqual(f.events, ['begin']);
});

test('Local import checks cancellation before begin and after an awaited Store read', async () => {
  for (const before of [true, false]) {
    const controller = new AbortController();
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const f = fixture(async accept => { await gate; await accept(bytes('[]')); });
    if (before) controller.abort();
    const work = readLocalRetainedInput(
      moon, f.operation, checked, controller.signal,
    );
    controller.abort(); release();
    await assert.rejects(work, {name: 'AbortError'});
    assert.deepEqual(f.events, before ? [] : ['begin']);
  }
});

test('Local reader snapshots port operations and refuses unsupported frames before beginning', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const f = fixture(async accept => { await gate; await accept(bytes('[{}]')); });
  const work = readLocalRetainedInput(moon, f.operation, checked);
  f.operation.append = () => assert.fail('replacement append');
  f.operation.finish = () => assert.fail('replacement finish');
  f.operation.frames.maxRows = 0;
  release();
  assert.equal((await work).rows, 1);
  assert.equal(f.events.at(-1), 'finish');
  const invalid = fixture(() => assert.fail('must not read'));
  invalid.operation.frames.maxFrameBytes = 32;
  await assert.rejects(
    readLocalRetainedInput(moon, invalid.operation, checked),
    /LocalImportFrameLimit/,
  );
  assert.deepEqual(invalid.events, []);
});
