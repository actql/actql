import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareAcquiredEffectKeyedPrefix} from './acquired-effect-keyed-prefix.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';

const ok = value => ({$tag: 1, _0: value});

// Explicit nominal ports exercise the actual shared composition. They do not
// issue a Run, Source evidence, capacity, permission or physical cleanup ACK.
function fixture() {
  const prepared = {}, managedRun = {}, graph = {}, scope = {}, compiled = {}, definition = {};
  const acquisition = {}, selected = {}, prefix = {}, execution = {}, left = {};
  const sourceRef = {}, access = {}, preparedKeyed = {}, ledger = {}, observation = {}, original = {}, evidence = {};
  const captures = [{capture: {}}, {capture: {}}], events = [];
  let duty, current = true, acquired = 0, prepares = 0, advances = 0, closes = 0, cleanups = 0, ack = true;
  const lookup = {async close() {events.push('lookup-close'); closes++;},
    async cleanup() {events.push('lookup-cleanup'); cleanups++; return ack;},
    cleanupPending: () => !ack,
    async issueObservation(value) {assert.equal(value.authorityScopeCid, 'authority'); return {observation};},
    async borrowSerializationInput() {return original;}};
  const adapter = {sourceAccess: access, admitsSource: value => value === sourceRef,
    keyedLedgerCapacity(value) {assert.equal(value, acquisition); return {maxBytes: 17, maxWork: 19};},
    async prepareKeyed(value) {
      assert.deepEqual(value, {preparedEffect: prepared, keyedAcquisition: acquisition,
        requestIdentity: request, sourceAccess: access}); prepares++; return {prepared: preparedKeyed};
    },
    async openKeyedLookup(value) {
      assert.equal(value.preparedEffect, prepared); assert.equal(value.managedRun, managedRun);
      assert.equal(value.keyedAcquisition, acquisition); assert.equal(value.left, left);
      assert.equal(value.ledger, ledger); assert.equal(value.preparedKeyed, preparedKeyed);
      assert.deepEqual(value.originalCaptures, captures.map(member => member.capture));
      assert.equal(value.sourceAccess, access); acquired++; return lookup;
    }};
  const request = {};
  const control = {startInstalledOriginalComposedKeyedPrefix(...args) {
    assert(duty, 'retain cleanup before the actual constructor');
    assert.deepEqual(args, [managedRun, compiled, definition, graph, scope, acquisition, captures]);
    events.push('prefix-start'); return prefix;
  }, keyedLookupPublicationEvidence(value) {assert.equal(value, observation); return evidence;}};
  const moon = {clientProgramEffectComposedModelKeyedAcquisition(p, g) {
    assert.equal(p, prepared); assert.equal(g, graph); return ok(acquisition);
  }, clientProgramKeyedAcquisitionSourceEvidenceFacts: value => {assert.equal(value, acquisition); return ok([sourceRef]);},
  clientProgramOriginalComposedKeyedPrefixExecution: value => {assert.equal(value, prefix); return execution;},
  clientProgramOriginalComposedKeyedPrefixAdvance(value, quantum) {
    assert.equal(value, prefix); assert.equal(quantum, 64); advances++; return ok({_0:true, _1:true});
  }, clientProgramCompleteOriginalComposedKeyedPrefix: value => {assert.equal(value, prefix); return ok(left);},
  clientProgramSerializationPrefixCancel(value) {assert.equal(value, execution); events.push('prefix-cancel');},
  clientProgramSerializationPrefixCleanup(value) {assert.equal(value, execution); events.push('prefix-cleanup'); return ok(true);}};
  const options = {moon, acquired: {prepared, requestIdentity:request, authorityScopeCid:'authority', control},
    managedRun, infer: {graph}, selected, originalPreparation:{scope}, plan:{compiled, runDefinition:definition},
    captures, sourceProfile:adapter, ledger, now: () => '2026-11-05T00:00:00.000Z',
    current() {if (!current) throw new Error('OriginalNotCurrent');},
    retain(value) {assert.equal(duty, undefined); duty = value;}};
  return {options, moon, adapter, events, lookup, original, observation, evidence,
    duty: () => duty, counts: () => ({acquired, prepares, advances, closes, cleanups}),
    setCurrent: value => {current = value;}, acknowledge: value => {ack = value;}};
}

test('same two captured originals execute one prefix and one keyed observation before Model', async () => {
  const f = fixture(), result = await prepareAcquiredEffectKeyedPrefix(f.options);
  assert.equal(result.lookup, f.original); assert.equal(result.observation, f.observation);
  assert.equal(result.evidence, f.evidence);
  assert.deepEqual(f.counts(), {acquired:1, prepares:1, advances:1, closes:0, cleanups:0});
  assert.equal(await f.duty().cleanup(), true);
  assert.deepEqual(f.events, ['prefix-start', 'lookup-close', 'lookup-cleanup', 'prefix-cancel', 'prefix-cleanup']);
  assert.equal(await f.duty().cleanup(), true);
  assert.deepEqual(f.counts(), {acquired:1, prepares:1, advances:1, closes:1, cleanups:1});
});

test('absence of a checked keyed obligation acquires no prefix or cleanup owner', async () => {
  const f = fixture(); f.moon.clientProgramEffectComposedModelKeyedAcquisition = () => ok(undefined);
  assert.equal(await prepareAcquiredEffectKeyedPrefix(f.options), undefined);
  assert.equal(f.duty(), undefined); assert.deepEqual(f.events, []);
});

test('missing originals refuse before a constructor and current refusal still retains cleanup', async () => {
  const f = fixture();
  await assert.rejects(prepareAcquiredEffectKeyedPrefix({...f.options, captures:[f.options.captures[0]]}),
    /InstalledComposedKeyedOriginalUnavailable/);
  assert.equal(f.duty(), undefined);
  f.setCurrent(false);
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), /OriginalNotCurrent/);
  assert(f.duty()); assert.equal(await f.duty().cleanup(), true); assert.deepEqual(f.events, []);
});

test('pending keyed cleanup retains prefix custody and retries only that same cleanup', async () => {
  const f = fixture(); await prepareAcquiredEffectKeyedPrefix(f.options);
  f.acknowledge(false); assert.equal(await f.duty().cleanup(), false);
  assert.equal(f.duty().cleanupPending(), true); assert(!f.events.includes('prefix-cleanup'));
  f.acknowledge(true); assert.equal(await f.duty().cleanup(), true);
  assert.deepEqual(f.counts(), {acquired:1, prepares:1, advances:1, closes:2, cleanups:2});
});

test('an undefined acquisition throw preserves its unknown custody without a retry or inferred ACK', async () => {
  const f = fixture(); f.adapter.openKeyedLookup = async () => {throw undefined;};
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), cause => cause === undefined);
  assert.equal(await f.duty().cleanup(), false); assert.equal(f.duty().cleanupPending(), true);
  assert.deepEqual(f.events, ['prefix-start']);
});

test('stated failed acquisition retains its actual recovery until it acknowledges cleanup', async () => {
  const f = fixture(), primary = new Error('PhysicalSourceFailed');
  let ack = false, closes = 0;
  const recovery = {async close() {closes++;}, async cleanup() {return ack;}, cleanupPending: () => !ack};
  const failure = acquisitionFailure(primary, 'unknown', recovery);
  f.adapter.openKeyedLookup = async () => {throw failure;};
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), cause => cause === failure);
  assert.equal(await f.duty().cleanup(), false); assert(!f.events.includes('prefix-cleanup'));
  ack = true; assert.equal(await f.duty().cleanup(), true); assert.equal(closes, 2);
});

test('a current failure after asynchronous preparation cleans the same prefix without opening a Source', async () => {
  const f = fixture(), prepare = f.adapter.prepareKeyed;
  f.adapter.prepareKeyed = async value => {const result = await prepare(value); f.setCurrent(false); return result;};
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), /OriginalNotCurrent/);
  assert.equal(f.counts().acquired, 0); assert.equal(await f.duty().cleanup(), true);
  assert.deepEqual(f.events, ['prefix-start', 'prefix-cancel', 'prefix-cleanup']);
});
