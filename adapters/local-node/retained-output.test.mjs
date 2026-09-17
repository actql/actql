import test from 'node:test';
import assert from 'node:assert/strict';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {installLocalRetainedStore} from './retained-store.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const ok = value => ({$tag: 1, _0: value});
function fixture({seal = async () => {}, cleanup = async () => {}} = {}) {
  const events = [], material = {}, input = {};
  let releaseCheck, closed = false, clean = false, bound = false, allocated = false, index = 0;
  const configuration = installLocalRetainedStore((key, bytes, frame) => {
    assert.equal(key, 'task-2'); assert.equal(bytes, 100); assert.equal(frame, 64);
    assert.equal(typeof releaseCheck, 'function');
    events.push('lease'); allocated = true;
    return {
      status: () => ({reservedBytes: clean ? 0 : 100, cleanupPending: closed && !clean}),
      reserve: value => {
        assert.equal(value, 100);
        return {
          start: async () => {events.push('start');},
          append: async text => {events.push(['append', text]);},
          seal: async identity => {
            events.push(['seal', identity]); await seal();
            return {available: () => !closed, close() {closed = true;}, consume: async () => {}};
          },
        };
      },
      close() {closed = true; events.push('store-close');},
      async cleanup() {events.push('cleanup'); await cleanup(); clean = true;},
    };
  });
  const output = {
    key: 'task-2', limits: {wire: {max_bytes: 100}, max_batch_bytes: 64},
    install: check => {events.push('install'); releaseCheck = check; return ok();},
    begin: () => {events.push('begin'); return ok();},
    next: () => ok(index++ === 0 ? '[{"n":1}' : undefined),
    finish: () => ok({cid: 'verified-content', bytes: 9, rows: 1, tail: ']',
      bind: available => {
        assert.equal(available(), true); events.push('bind'); bound = true;
        return ok({material, readable: read => read === input});
      },
    }),
    refresh: () => {events.push('refresh'); return ok(releaseCheck());},
  };
  const operations = {
    inputs: [], output,
    execute: () => {events.push('execute'); return ok();},
    settle: () => {events.push('settle'); return ok();},
    complete: () => {assert(bound); events.push('complete'); return ok();},
    close: () => {events.push('task-close');},
  };
  const moon = {strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local-test',
    strategyModule_local_Dispatch: () => {events.push('reserved'); return ok(operations);}};
  const entry = localStrategyContribution(moon, {}, checked, configuration);
  return {entry, events, configuration, allocated: () => allocated, released: () => releaseCheck?.()};
}

test('Local output seals exact content before completion and retains cleanup until physical confirmation', async () => {
  let allowCleanup = false;
  const f = fixture({cleanup: async () => {if (!allowCleanup) throw Error('busy');}});
  assert.equal(f.allocated(), false);
  const result = await f.entry.run({});
  assert.equal(result.diagnostic.outputRepresentation, 'retained-file');
  assert(f.events.indexOf('bind') < f.events.indexOf('complete'));
  assert(f.events.indexOf('install') < f.events.indexOf('lease'));
  let failure;
  await assert.rejects(result.close(), error => {failure = error; return true;});
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(f.released(), false);
  allowCleanup = true;
  await failure.cleanupHandle.retry();
  assert.equal(f.released(), true);
  assert.equal(failure.cleanupHandle.status().pending, false);
});

test('cancel during Local storage seal waits for the started work and never publishes', async () => {
  let release, entered;
  const arrived = new Promise(resolve => {entered = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const f = fixture({seal: async () => {entered(); await gate;}});
  const controller = new AbortController();
  const work = f.entry.run({}, controller.signal);
  await arrived;
  controller.abort();
  assert.equal(f.events.includes('task-close'), false);
  release();
  let failure;
  await assert.rejects(work, error => {failure = error; return error.name === 'AbortError';});
  assert.equal(f.events.includes('complete'), false);
  assert.equal(f.events.includes('bind'), false);
  assert.equal(f.released(), false);
  await failure.cleanupHandle.retry();
  assert.equal(f.released(), true);
});

test('reasonless Store rejection remains failed and copied Local wiring is not accepted', async () => {
  const f = fixture({seal: () => Promise.reject()});
  let failure;
  await assert.rejects(f.entry.run({}), error => {failure = error; return true;});
  assert.equal(f.events.includes('complete'), false);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.throws(() => localStrategyContribution({}, {}, checked, {...f.configuration}), /InvalidLocalStoreConfiguration/);
});
