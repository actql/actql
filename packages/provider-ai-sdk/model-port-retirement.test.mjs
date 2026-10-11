import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {interceptSdkRequest} from './_internal/intercepted-request.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';

const endpoint = 'https://fixture.invalid/chat';
const limits = {maxBytes: 128, maxChunkBytes: 128, maxChunks: 4,
  maxHeaderBytes: 128, observedHeaders: ['content-type']};
const moon = {
  clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
  clientProgramModelAsyncPhysicalRequestPlan: (...args) => ({start: args.at(-1)}),
  clientProgramModelPhysicalCall: (entry, prepared, poll, cancel, cleanup) =>
    ({poll, cancel, cleanup}),
  clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
  clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
  clientProgramModelPhysicalSavedChat: value => ({kind: 'chat', value}),
};

// Each factory callback intentionally borrows the original input. Retaining
// one callback after retirement therefore retains that input too. The Core
// interface and SDK builder are doubles; the preparation/transport/cleanup
// implementation is real. No Provider, public Run, grant or heap byte bound
// is established by this finite reachability check.
function borrowing(input, action) {
  return (...args) => {
    assert.equal(input.marker, 'Original e\u0301\r\n');
    return action(...args);
  };
}

function fixture({saveFailure} = {}) {
  const input = Object.freeze({marker: 'Original e\u0301\r\n', value: null});
  const ref = new WeakRef(input);
  const state = {fetches: 0, saves: 0, cleanups: 0, cleanupAllowed: false,
    cleanupThrows: false, saveFailure};
  const preparation = interceptSdkRequest({endpoint, maxRequestBytes: 128,
    maxHeaderBytes: 128, maxHeaders: 4, notify() {},
    async runSdk(fetch) {
      const response = await fetch(endpoint, {method: 'POST', body: '{}'});
      return response.text();
    }});
  const port = createSdkModelPreflight({moon, request: input, preparation,
    profile: Object.freeze({input}), installation: Object.freeze({input}),
    quantities: Object.freeze({tokens: 1n, costUnits: 0n, durationMs: 1n, input}),
    responseLimits: limits,
    fetch: borrowing(input, () => {
      state.fetches++;
      return new Response('original', {headers: {'content-type': 'text/plain'}});
    }),
    persistRaw: borrowing(input, (call, raw) => {
      state.saves++;
      if (state.saveFailure) throw state.saveFailure;
      return {response: Object.freeze({raw, marker: 'Saved e\u0301\r\n'})};
    }),
    notify: borrowing(input, () => {}), checked: borrowing(input, value => value),
    observeAt: borrowing(input, () => '2026-10-12T00:00:00.000Z'),
    cleanupRaw: borrowing(input, () => {
      state.cleanups++;
      if (state.cleanupThrows) throw new Error('CleanupStillPending');
      return state.cleanupAllowed;
    }),
  });
  port.bindPrepared(Object.freeze({input}));
  return {port, state, ref};
}

async function until(read, accept) {
  for (let i = 0; i < 50; i++) {
    const value = read();
    if (accept(value)) return value;
    await turn();
  }
  assert.fail('Finite original port observation was not reached');
}

async function collected(ref) {
  assert.equal(typeof global.gc, 'function', 'Run this selection with --expose-gc');
  for (let i = 0; i < 24; i++) {
    // WeakRef dereferencing protects a target for the current job; collect in
    // a later job. This tests reachability, not V8 allocation size or RSS.
    await turn();
    global.gc();
    await turn();
    if (ref.deref() === undefined) return true;
  }
  return false;
}

test('unused SDK port retires factory input only after original preparation cleanup',
  {timeout: 5000}, async () => {
    const f = fixture();
    assert.equal(f.port.preflight.cleanup(), false);
    assert.ok(f.ref.deref(), 'Original input remains borrowed while stop is pending');
    await until(() => f.port.preflight.cleanup(), value => value === true);
    assert.equal(await collected(f.ref), true,
      'An escaped retired preflight must not retain its factory input/callbacks');
    assert.equal(f.port.preflight.cleanup(), true);
    assert.deepEqual(f.port.preflight.advance(), {_0: true, _1: undefined});
    assert.equal(f.state.fetches, 0);
    assert.equal(f.state.saves, 0);
  });

test('saved SDK port preserves pending cleanup and escaped immutable raw view',
  {timeout: 5000}, async () => {
    const f = fixture();
    const {_1: plan} = await until(() => f.port.preflight.advance(), value => value._0);
    const call = plan.start({});
    const saved = (await until(() => call.poll(), value => value.kind === 'chat')).value;
    f.state.cleanupThrows = true;
    assert.equal(call.cleanup(), false);
    assert.ok(f.ref.deref());
    f.state.cleanupThrows = false;
    assert.equal(call.cleanup(), false);
    assert.ok(f.ref.deref());
    f.state.cleanupAllowed = true;
    await until(() => call.cleanup(), value => value === true);
    assert.equal(await collected(f.ref), true,
      'Escaped call/plan/port must release factory references only on successful cleanup');
    assert.equal(saved.marker, 'Saved e\u0301\r\n');
    assert.equal(Buffer.from(saved.raw.body).toString(), 'original');
    assert.equal(call.cleanup(), true);
    assert.equal(plan.start({}), undefined);
    assert.throws(() => call.poll(), {code: 'ForeignSdkPreparation'});
    assert.throws(() => call.cancel(), {code: 'ForeignSdkPreparation'});
    assert.equal(f.state.fetches, 1);
    assert.equal(f.state.saves, 1);
  });

test('failed save keeps original error and cleanup responsibility without resend',
  {timeout: 5000}, async () => {
    const primary = Object.freeze(new Error('OriginalCommitResponseLost'));
    const f = fixture({saveFailure: primary});
    const {_1: plan} = await until(() => f.port.preflight.advance(), value => value._0);
    const call = plan.start({});
    await until(() => call.poll(), value => value.kind === 'unknown');
    assert.equal(f.port.rawFailure(), primary);
    assert.equal(call.cleanup(), false);
    assert.ok(f.ref.deref());
    f.state.cleanupAllowed = true;
    await until(() => call.cleanup(), value => value === true);
    assert.equal(await collected(f.ref), true);
    assert.equal(f.port.rawFailure(), primary, 'Primary error is not retired as an input alias');
    assert.equal(call.poll().kind, 'unknown');
    assert.equal(call.cleanup(), true);
    assert.equal(f.state.fetches, 1);
    assert.equal(f.state.saves, 1);
  });
