import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {stopGeneratedContentPrefix} from './generated-content-write.mjs';

// Extract the actual installed execution cleanup, including its original
// lexical aliases. The explicit ports below are not Store/Resource admission
// or physical ACK. No product inspection API or replacement cleanup is added.
function cleanupFixture({managed = {}, selectedKeyed, retained, physical,
  writer, byteHolding, control, store, failureCleanup} = {}) {
  const source = readFileSync(new URL('./installed-content-run.mjs', import.meta.url), 'utf8');
  let selected;
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === 'cleanup') {
      assert.equal(selected, undefined); selected = node.init;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(selected);
  const prefix = {}, input = {}, publication = {}, calls = [];
  let work = 3n;
  const initial = {prefix, input, writer, physical, byteHolding, retained,
    publication, failureCleanup, managed: managed === null ? undefined : managed, selectedKeyed};
  const ports = {control, store, key: {}, chargeWork(delta) {work += BigInt(delta); return false;},
    stopGeneratedContentPrefix};
  const actual = Function('initial', 'ports', `
    let ledger;
    const acquiredLedgers=new Map();
    let {prefix,input,writer,physical,byteHolding,retained,publication,failureCleanup,
      managed,selectedKeyed}=initial;
    let cleaned=false,cleanupFlight,retired=false,generatedRetained=false;
    const retirement=new Map();
    const {control,store,key,chargeWork,stopGeneratedContentPrefix}=ports;
    const cleanup=(${source.slice(selected.start, selected.end)});
    return {cleanup, snapshot:()=>({prefix,input,writer,physical,byteHolding,retained,
      publication,failureCleanup,cleaned,retired,retirementSize:retirement.size})};
  `)(initial, ports);
  return {...actual, prefix, input, calls, work: () => work};
}

const assertCut = snapshot => {
  for (const key of ['prefix', 'input', 'writer', 'physical', 'byteHolding', 'retained', 'publication']) {
    assert.equal(snapshot[key], undefined, key);
  }
  assert.equal(snapshot.retirementSize, 0);
};

test('actual Content cleanup cuts acknowledged physical aliases before pending managed prefix settlement', async () => {
  let f, released = false, ready = false, releases = 0, cancellations = 0, settlements = 0;
  const original = new Error('same original physical release');
  let refused;
  const physical = {prepared: {status: () => ({pending: !released}), async release() {
    releases++; if (refused) throw refused;
  }}};
  f = cleanupFixture({physical, writer: {async cancel() {}, status: () => ({reservationHeld: false})},
    control: {prefixCancel(value) {assert.equal(value, f.prefix); cancellations++;},
      inputCancel(value) {assert.equal(value, f.input);},
      cleanupRequestPrefix() {settlements++; assertCut(f.snapshot()); return ready;}},
    store: {async confirmCommittedIndex() {return {};}}});
  assert.equal(await f.cleanup(), false);
  assert.equal(f.snapshot().physical, physical);
  assert.equal(f.snapshot().prefix, f.prefix);
  assert.equal(settlements, 0);
  refused = original; await assert.rejects(f.cleanup, error => error === original);
  assert.equal(f.snapshot().physical, physical);
  refused = undefined; released = true;
  assert.equal(await f.cleanup(), false);
  assertCut(f.snapshot()); assert.equal(f.snapshot().cleaned, false);
  const cancellationsAtAck = cancellations;
  ready = true; assert.equal(await f.cleanup(), true);
  assert.equal(cancellations, cancellationsAtAck, 'native owner retains its own pending prefix');
  assert.equal(releases, 2); assert.equal(settlements, 2);
  assert.equal(await f.cleanup(), true); assert.equal(settlements, 2);
  assert.equal(f.work(), 3n, 'cleanup must not fabricate zero work');
});

test('actual Content cleanup keeps holding and retirement aliases until original acknowledgements and is single flight before callbacks', async () => {
  let f, holdingReady = false, retirementReady = false, aborts = 0, creations = 0, settles = 0;
  let nested;
  const holding = {async abort() {aborts++; return false;}, status: () => ({
    committed: holdingReady, abandoned: false, preparedPending: !holdingReady, operationPending: false})};
  const retained = {holdings: [holding], bindings: [{holdingCid: 'same-evidence'}]};
  const child = {status: () => ({pending: !retirementReady}), async retry() {}};
  let reenter = true;
  f = cleanupFixture({retained, byteHolding: {holding_cid: 'same-bytes'},
    control: {prefixCancel() {if (reenter) {reenter = false; nested = f.cleanup();}}, inputCancel() {},
      cleanupRequestPrefix() {assertCut(f.snapshot()); settles++; return true;}},
    store: {async confirmCommittedIndex() {return undefined;},
      async retirePhysicalHolding() {creations++; return {cleanup: child};}}});
  const first = f.cleanup();
  assert.equal(await first, false);
  assert.equal(nested, first, 'same cleanup flight must exist before callback entry');
  assert.equal(f.snapshot().retained, retained); assert.equal(creations, 0); assert.equal(settles, 0);
  holdingReady = true; assert.equal(await f.cleanup(), false);
  assert.equal(f.snapshot().retained, retained); assert.equal(creations, 1); assert.equal(settles, 0);
  retirementReady = true; assert.equal(await f.cleanup(), true);
  assertCut(f.snapshot()); assert.equal(creations, 2); assert.equal(settles, 1);
  assert.equal(aborts, 3);
});

test('actual legacy Content cleanup keeps the original prefix and work through pending stop', async () => {
  let f, ready = false, work = 4n;
  f = cleanupFixture({managed: null,
    control: {prefixCancel() {}, inputCancel() {}, prefixCleanup: () => ready,
      prefixWork: () => work, prefixAdvance() {work++; return {stopped: true};}},
    store: {async confirmCommittedIndex() {return {};}}});
  // The explicit legacy fixture has no managed owner; no new fallback or
  // acquisition is exercised here.
  assert.equal(await f.cleanup(), false);
  assert.equal(f.snapshot().prefix, f.prefix);
  assert.equal(f.work(), 4n);
  ready = true; assert.equal(await f.cleanup(), true);
  assertCut(f.snapshot()); assert.equal(f.work(), 4n);
});
