import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {createModelRawTransportPersistence} from './infer-raw-capture.mjs';
import {rawCaptureStoreFixture} from './infer-raw-capture.fixture.mjs';

// Reachability only: no numerical envelope, physical GC/ACK or Model grant
// follows from collecting a retired adapter's otherwise unused aliases.
async function collected(ref) {
  assert.equal(typeof global.gc, 'function', 'Use the selected --expose-gc recipe');
  for (let i = 0; i < 24; i++) {
    await turn();
    global.gc();
    await turn();
    if (ref.deref() === undefined) return true;
  }
  return false;
}

function unused() {
  const original = Object.freeze({marker: Symbol('original installation borrow')});
  const port = createModelRawTransportPersistence({
    store: {original}, moon: {original}, registration: {original},
    operation: {original},
    retainHolding() { assert.fail(String(original.marker)); },
    notify() { assert.fail(String(original.marker)); },
  });
  return {port, ref: new WeakRef(original)};
}

test('unused raw caller retires installation and callback aliases without issuing a Save',
  {timeout: 5000}, async () => {
    const f = unused();
    assert.ok(f.ref.deref());
    assert.equal(f.port.cleanup(undefined), true);
    assert.equal(await collected(f.ref), true);
    assert.equal(f.port.cleanup(undefined), true);
    await assert.rejects(f.port({}, {}), {message: 'OriginalRawPersistenceRetired'});
  });

async function saved(f) {
  const call = Object.freeze({marker: Symbol('original physical Call double')});
  const raw = Object.freeze({body: f.bytes, status: 200,
    transportComplete: true, observedAt: '2026-10-17T00:00:00.000Z'});
  f.moon.clientProgramObserveInferRawCapture = () => ({$tag: 1, _0: f.view});
  let holding;
  const port = createModelRawTransportPersistence({store: f.physical, moon: f.moon,
    registration: {}, retainHolding(value) { holding = value; }, notify() {}});
  const result = await port(call, raw);
  assert.equal(port.cleanup({}), false);
  assert.equal(port.cleanup(call), true);
  assert.equal(port.cleanup(call), true);
  assert.equal(port.cleanup({}), false);
  return {port, result, holding, ref: new WeakRef(call)};
}

test('saved raw caller weakens only its retired Call alias and preserves original holding and receipt',
  {timeout: 5000}, async t => {
    // The encrypted Store is real; nominal Model/Entry/receipt admission is
    // explicitly doubled by the existing fixture, not an installed Run.
    const f = await rawCaptureStoreFixture(t, {bytes: Buffer.from('{"answer":"original"}')});
    const original = await saved(f);
    assert.equal(await collected(original.ref), true);
    assert.equal(original.port.cleanup({}), false);
    assert.equal(original.result.receipt, f.receipt);
    assert.equal(original.holding.holding.status().committed, true);
    assert.equal(f.state.writes, 1);
    assert.equal(f.state.acknowledgements, 1);
    assert.equal(original.result.response.body, '{"answer":"original"}');
    await f.store.retirePhysicalHolding(f.binding.holdingCid);
  });
