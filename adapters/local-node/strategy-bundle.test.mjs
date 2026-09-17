import test from 'node:test';
import assert from 'node:assert/strict';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {registerRetainedInput} from '../store-local/representations.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const ok = value => ({$tag: 1, _0: value});
function installed(consume, completionFailure) {
  const events = [], material = {}, input = {}, task = {}, setup = {};
  registerRetainedInput(material, value => value === input, {consume},
    {maxFrameBytes: 32, wire: {max_bytes: 32}});
  const operations = {
    inputs: [{material, input,
      frames: {maxBytes: 32, maxRows: 2, maxRowBytes: 32, maxFrameBytes: 32, maxDepth: 4},
      begin: () => { events.push('begin'); return ok(); },
      charge: bytes => { events.push(['charge', bytes]); return ok(); },
      append: row => { events.push(['row', row]); return ok(); },
      finish: () => { events.push('verified'); return ok(); },
    }],
    execute: () => { events.push('execute'); return ok(); },
    settle: () => { events.push('settle'); return ok(); },
    complete: () => {
      events.push('complete');
      if (completionFailure) return {$tag: 0, _0: completionFailure};
      return ok();
    },
    close: () => { events.push('close'); },
  };
  const entry = localStrategyContribution({
    strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local-test',
    strategyModule_local_Dispatch: (owner, work) => {
      assert.equal(owner, setup); assert.equal(work, task);
      events.push('reserved'); return ok(operations);
    },
  }, setup, checked);
  return {entry, task, events};
}

test('Local contribution admits, reads, executes and completes before exposing its close operation', async () => {
  const f = installed(async accept => { await accept(new TextEncoder().encode('[{"id":3}]')); });
  const output = await f.entry.run(f.task);
  assert.deepEqual(f.events, ['reserved', 'begin', ['charge', 10n], ['row', '{"id":3}'],
    'verified', 'execute', 'settle', 'complete']);
  assert.deepEqual(output.diagnostic, {realization: 'local', importedRows: 1, importedBytes: '10'});
  output.close();
  assert.equal(f.events.at(-1), 'close');
});

test('Local cancellation stops before reservation or awaits the current reader before settlement', async () => {
  for (const before of [true, false]) {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const f = installed(async () => { await gate; f.events.push('reader-returned'); });
    const controller = new AbortController();
    if (before) controller.abort();
    const work = f.entry.run(f.task, controller.signal);
    controller.abort();
    if (!before) assert.deepEqual(f.events, ['reserved', 'begin']);
    release();
    await assert.rejects(work, {name: 'AbortError'});
    assert.deepEqual(f.events, before ? [] : ['reserved', 'begin', 'reader-returned', 'close', 'settle']);
  }
});

test('reader rejection retains its cleanup handle and completion failure does not settle twice', async () => {
  for (const failure of [undefined, null, Object.assign(new Error('read'), {cleanupHandle: {}})]) {
    const f = installed(async () => { throw failure; });
    let rejected = false;
    try { await f.entry.run(f.task); }
    catch (error) { rejected = true; assert.equal(error, failure); }
    assert.equal(rejected, true);
    assert.deepEqual(f.events, ['reserved', 'begin', 'close', 'settle']);
  }
  const f = installed(async accept => { await accept(new TextEncoder().encode('[]')); }, 'capacity');
  await assert.rejects(f.entry.run(f.task), {code: 'MoonBitHostFailure'});
  assert.equal(f.events.filter(value => value === 'settle').length, 1);
  assert.equal(f.events.at(-1), 'close');
});
