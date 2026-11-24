import test from 'node:test';
import assert from 'node:assert/strict';
import {registerRetainedInput} from '../store-local/representations.mjs';
import {readLocalRetainedInput} from './retained-input.mjs';
type Read = Parameters<typeof readLocalRetainedInput>;
type Prepare = Parameters<Read[0]['strategyPrepareDurableResultRowFrames']>;
type Consume = Parameters<typeof registerRetainedInput>[2]['consume'];
type Event = string | ['charge', bigint] | ['row', string];

const runtimePath = '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
const moon = await import(runtimePath) as Read[0];

const bytes = (text: string) => new TextEncoder().encode(text);
const checked: Read[2] = result => {
  if ((result as {error?: unknown} | null | undefined)?.error) throw (result as {error: unknown}).error;
  return result;
};
function fixture(consume: Consume, overrides: Partial<Pick<Read[1], 'charge'>> = {}, bodyBytes?: number) {
  const material = {}, input = {}, events: Event[] = [];
  registerRetainedInput(material, read => read === input, Object.freeze({consume,
    ...(bodyBytes === undefined ? {} : {bytes: bodyBytes})}),
    {wire: {max_bytes: 100}, maxFrameBytes: 64});
  const operation = {material, input,
    frames: {maxBytes: 100, maxRows: 3, maxRowBytes: 64, maxDepth: 4, maxFrameBytes: 64},
    begin: () => events.push('begin'),
    charge: (value: bigint) => events.push(['charge', value]),
    append: (value: string) => events.push(['row', value]),
    finish: () => events.push('finish'),
    ...overrides,
  };
  return {operation, events};
}

test('Local retained reader charges provisional bytes and verifies only after the Store read completes', async () => {
  let events: Event[];
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

test('Local reader bounds the static frame constructor by the same sealed stream extent', async () => {
  for (const known of [true, false]) {
    const prepared: Prepare[] = [];
    const facade = {...moon, strategyPrepareDurableResultRowFrames(...args: Prepare) {
      prepared.push(args); return moon.strategyPrepareDurableResultRowFrames(...args);
    }};
    const f = fixture(async accept => {await accept(bytes('[{"id":3}]'));}, {}, known ? 10 : undefined);
    assert.deepEqual(await readLocalRetainedInput(facade, f.operation, checked), {bytes: 10, rows: 1});
    assert.deepEqual(prepared, [[known ? 10 : 100, 3, known ? 10 : 64, 4, 64]]);
    assert.deepEqual(f.operation.frames, {maxBytes:100,maxRows:3,maxRowBytes:64,maxDepth:4,maxFrameBytes:64});
    assert.equal(f.events.at(-1), 'finish');
  }
});

test('A custom extent accessor remains on the legacy framing path without invocation', async () => {
  const material = {}, input = {}, prepared: Prepare[] = [];
  const f = fixture(async () => {});
  registerRetainedInput(material, read => read === input, Object.freeze({
    get bytes() { return assert.fail('custom extent getter must not run'); },
    consume: async accept => { await accept(bytes('[{"id":3}]')); },
  }), {wire: {max_bytes: 100}, maxFrameBytes: 64});
  const facade = {...moon, strategyPrepareDurableResultRowFrames(...args: Prepare) {
    prepared.push(args); return moon.strategyPrepareDurableResultRowFrames(...args);
  }};
  assert.deepEqual(await readLocalRetainedInput(facade, {...f.operation, material, input}, checked),
    {bytes: 10, rows: 1});
  assert.deepEqual(prepared, [[100, 3, 64, 4, 64]]);
  assert.equal(f.events.at(-1), 'finish');
});

test('Known stream extent retains tighter byte/row policies and exact input custody', async () => {
  for (const limit of [{maxRowBytes: 1}, {maxBytes: 4}]) {
    const f=fixture(async accept=>accept(bytes('[{"id":3}]')),{},10);
    Object.assign(f.operation.frames,limit);
    await assert.rejects(readLocalRetainedInput(moon,f.operation,checked));
    assert(!f.events.includes('finish'));
  }
  const empty = fixture(async () => {}, {}, 0);
  await assert.rejects(readLocalRetainedInput(moon, empty.operation, checked));
  assert.deepEqual(empty.events, ['begin']);
  const f=fixture(()=>assert.fail('foreign input must not consume'),{},10);
  await assert.rejects(readLocalRetainedInput(moon,{...f.operation,material:{}},checked), {code:'RetainedInputUnavailable'});
  await assert.rejects(readLocalRetainedInput(moon,{...f.operation,input:{}},checked), {code:'RetainedInputUnavailable'});
  assert.deepEqual(f.events,[]);
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
    let release!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
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
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
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
