import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareAcquiredEffectKeyedPrefix} from './acquired-effect-keyed-prefix.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';

const ok = value => ({$tag: 1, _0: value});

// Explicit nominal ports exercise the actual shared composition. They do not
// issue a Run, Source evidence, capacity, permission or physical cleanup ACK.
function fixture({rawProtocol = false} = {}) {
  const prepared = {}, managedRun = {}, graph = {}, scope = {}, compiled = {};
  const definition = {identity: 'sha256:' + '1'.repeat(64),
    wire: '{"valid_until":"2027-01-01T00:00:00.000Z"}'};
  const compilation = {}, runRef = {namespaceId:'local', runDefinitionCid: definition.identity};
  const originalLookup = {}, keyedRequest = {}, activation = {}, activationRecord = {}, retention = {};
  const acquisition = {}, selected = {}, prefix = {}, execution = {}, left = {};
  const rawBytes = new Uint8Array([1,2,3]), raw = {}, page = {}, capturedPage = {};
  const rawBinding = {name:'lookup_raw_response', semanticCid:'sha256:'+'3'.repeat(64),
    holdingCid:'sha256:'+'4'.repeat(64), contentCid:'sha256:'+'5'.repeat(64), byteCount:3, wire:'raw metadata'};
  let physicalRecord;
  const preparedObjects = [6,7].map(digit => {
    let pending = true;
    return {physicalCid:'sha256:'+String(digit).repeat(64), bytes:8,
      prepared:{status:()=>({pending}), async release() {pending = false; return true;}}};
  });
  const store = {storeAuthorityCid:'sha256:'+'2'.repeat(64),
    async confirmLookupRawEvidence(value) {
      assert.equal(value.semanticCid, rawBinding.semanticCid);
      return physicalRecord === undefined ? undefined : {record:physicalRecord};
    },
    async prepareLookupRawEvidence(value, bytes) {
      assert.equal(value.semanticCid, rawBinding.semanticCid); assert.strictEqual(bytes, rawBytes);
      events.push('raw-prepare'); return preparedObjects;
    },
    async commitPhysicalHolding(value, handles) {
      assert.equal(value.holding_cid, rawBinding.holdingCid);
      assert.deepEqual(handles, preparedObjects.map(value=>value.prepared));
      physicalRecord = value; events.push('raw-commit');
    },
  };
  const sourceRef = {}, access = {}, preparedKeyed = {}, ledger = {}, observation = {}, original = {}, evidence = {};
  const captures = [{capture: {}}, {capture: {}}], events = [];
  let duty, current = true, acquired = 0, prepares = 0, advances = 0, closes = 0, cleanups = 0, ack = true;
  const lookup = {async close() {events.push('lookup-close'); closes++;},
    async cleanup() {events.push('lookup-cleanup'); cleanups++; return ack;},
    cleanupPending: () => !ack,
    async issueObservation(value) {assert.equal(value.authorityScopeCid, 'authority'); return {observation};},
    async borrowSerializationInput() {return original;}};
  const fileReadDeclarations = Object.freeze([{}]);
  const adapter = {fileReadDeclarations, sourceAccess: access, admitsSource: value => value === sourceRef,
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
      assert.equal(value.sourceAccess, access);
      value.publication.initialize(originalLookup);
      const attempt = value.publication.activate(originalLookup, keyedRequest);
      assert.equal(attempt.activation, activation); assert.equal(attempt.record, activationRecord);
      if (rawProtocol) {
        const retained = await value.publication.retainRawResponse(originalLookup, keyedRequest, attempt, rawBytes);
        assert.strictEqual(retained, raw);
        value.publication.adopt(originalLookup, keyedRequest, attempt, capturedPage, retained);
        assert.strictEqual(value.publication.finishInput(originalLookup), original);
      }
      acquired++; return lookup;
    }};
  const request = {};
  const control = {startInstalledOriginalComposedKeyedPrefix(...args) {
    assert(duty, 'retain cleanup before the actual constructor');
    assert.deepEqual(args, [managedRun, compiled, definition, graph, scope, acquisition, captures]);
    events.push('prefix-start'); return prefix;
  }, prepareKeyedLookupSourceMetadata(value, identity, originals, sourceOriginals, _retention, _output, _work, _limits, declarations) {
    assert.equal(value, originalLookup); assert.equal(identity, request);
    assert.strictEqual(originals, captures);
    assert.strictEqual(declarations, fileReadDeclarations);
    assert.deepEqual(sourceOriginals.map(value => value.captured), captures);
    events.push('metadata'); return retention;
  }, prepareKeyedLookupRawCapture(k, c, d, r, storage, cid, bytes) {
    assert.strictEqual(k,keyedRequest); assert.strictEqual(c,compiled); assert.strictEqual(d,definition);
    assert.strictEqual(r,retention); assert.equal(storage.namespaceId,'local');
    assert.equal(storage.storeAuthorityCid,store.storeAuthorityCid); assert.equal(bytes,3);
    assert.match(cid,/^sha256:[0-9a-f]{64}$/u); events.push('raw-metadata');
    return {original:raw,binding:rawBinding};
  }, prepareKeyedLookupCapturedPage(k, capture, value) {
    assert.strictEqual(k,keyedRequest); assert.strictEqual(capture,capturedPage); assert.strictEqual(value,raw);
    assert(physicalRecord); events.push('page-prepare'); return page;
  }, keyedLookupPublicationEvidence(value) {assert.equal(value, observation); return evidence;}};
  const moon = {
    clientProgramKeyedLookupDeclaredFilePublicationInput(value) {
      assert.strictEqual(value,originalLookup); events.push('lookup-completion'); return ok(original);
    },
    clientProgramKeyedLookupStartDeclaredFileRequestPlan(value, at, ms, issuer) {
      assert.equal(value, originalLookup); assert.equal(at, '2026-11-05T00:00:00.000Z');
      assert.equal(typeof ms, 'bigint'); assert.equal(issuer, 'authority');
      events.push('plan-start'); return ok(undefined);
    },
    clientProgramKeyedLookupPrepareActivation(value, r, identity, issuer, at, ms) {
      assert.equal(value, originalLookup); assert.equal(r, keyedRequest); assert.equal(identity, request);
      assert.equal(issuer, 'authority'); assert.equal(at, '2026-11-05T00:00:00.000Z');
      assert.equal(typeof ms, 'bigint'); events.push('activation'); return ok(activation);
    }, clientProgramEffectAcquisitionCount: () => captures.length,
    clientProgramEffectComposedModelKeyedAcquisition(p, g) {
    assert.equal(p, prepared); assert.equal(g, graph); return ok(acquisition);
  }, clientProgramKeyedAcquisitionSourceEvidenceFacts: value => {assert.equal(value, acquisition); return ok([sourceRef]);},
  clientProgramOriginalComposedKeyedPrefixExecution: value => {assert.equal(value, prefix); return execution;},
  clientProgramOriginalComposedKeyedPrefixAdvance(value, quantum) {
    assert.equal(value, prefix); assert.equal(quantum, 64); advances++; return ok({_0:true, _1:true});
  }, clientProgramCompleteOriginalComposedKeyedPrefix: value => {assert.equal(value, prefix); return ok(left);},
  clientProgramSerializationPrefixCancel(value) {assert.equal(value, execution); events.push('prefix-cancel');},
  clientProgramSerializationPrefixCleanup(value) {assert.equal(value, execution); events.push('prefix-cleanup'); return ok(true);}};
  const now = () => '2026-11-05T00:00:00.000Z';
  const requestJournal = {persistOriginalKeyedLookupPage(ref,value,actualMoon,actualControl) {
    assert.strictEqual(ref,runRef); assert.strictEqual(value.page,page);
    assert.strictEqual(value.activationRecord,activationRecord); assert.strictEqual(value.keyedRequest,keyedRequest);
    assert.strictEqual(actualMoon,moon); assert.strictEqual(actualControl,control);
    events.push('journal-page'); return {};
  }, persistOriginalKeyedLookupActivation(ref, value, actualMoon, actualControl) {
    assert.strictEqual(ref, runRef); assert.equal(value.activation, activation);
    assert.equal(value.identity, request); assert.equal(value.preparedEffect, prepared);
    assert.equal(value.compilation, compilation); assert.equal(value.compiled, compiled);
    assert.equal(value.runDefinition, definition); assert.equal(value.graph, graph);
    assert.equal(actualMoon, moon); assert.equal(actualControl, control);
    events.push('journal'); return activationRecord;
  }};
  const options = {moon, acquired: {prepared, requestIdentity:request, authorityScopeCid:'authority', control,
      compilation, runDefinition: definition, now}, requestJournal, runRef,
    sources: captures.map(captured => ({captured, sourceEvidence: {}})),
    store, managedRun, infer: {graph}, selected, originalPreparation:{scope}, plan:{compiled, runDefinition:definition},
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
  assert.deepEqual(f.events, ['prefix-start', 'metadata', 'plan-start', 'activation', 'journal', 'lookup-close', 'lookup-cleanup', 'prefix-cancel', 'prefix-cleanup']);
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

test('same original Journal failure preserves undefined before a keyed Source or Model can proceed', async () => {
  const f = fixture();
  f.options.requestJournal.persistOriginalKeyedLookupActivation = () => {throw undefined;};
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), cause => cause === undefined);
  assert.equal(f.counts().acquired, 0);
  assert.deepEqual(f.events, ['prefix-start', 'metadata', 'plan-start', 'activation']);
  // The explicit port supplies no stopped/cleanup witness for its thrown
  // undefined. The caller must preserve that unknown, never infer an ACK.
  assert.equal(await f.duty().cleanup(), false);
});

test('missing original keyed Journal refuses before a physical keyed Source is opened', async () => {
  const f = fixture();
  await assert.rejects(prepareAcquiredEffectKeyedPrefix({...f.options, requestJournal: undefined}),
    /OriginalKeyedLookupJournalUnavailable/u);
  assert.equal(f.counts().acquired, 0);
  assert.equal(await f.duty().cleanup(), true);
  assert.deepEqual(f.events, ['prefix-start', 'prefix-cancel', 'prefix-cleanup']);
});


test('same original transport is stored before page adoption and completed lookup reaches Model', async () => {
  const f = fixture({rawProtocol:true});
  const value = await prepareAcquiredEffectKeyedPrefix(f.options);
  assert.strictEqual(value.lookup,f.original);
  assert.deepEqual(f.events.slice(0,10), ['prefix-start','metadata','plan-start','activation','journal',
    'raw-metadata','raw-prepare','raw-commit','page-prepare','journal-page']);
  assert.equal(f.events[10],'lookup-completion');
  assert.equal(await f.duty().cleanup(),true);
  assert.equal(f.counts().acquired,1);
});

test('retirement during original raw Store await prevents page adoption and Model progress', async () => {
  const f = fixture({rawProtocol:true}), commit = f.options.store.commitPhysicalHolding;
  f.options.store.commitPhysicalHolding = async (...args) => {await commit(...args); f.setCurrent(false);};
  await assert.rejects(prepareAcquiredEffectKeyedPrefix(f.options), /OriginalNotCurrent/u);
  assert.equal(f.events.includes('raw-commit'),true);
  assert.equal(f.events.includes('journal-page'),false);
  assert.equal(f.events.includes('lookup-completion'),false);
  assert.equal(f.counts().acquired,0);
});
