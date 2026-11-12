import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {localStrategyContribution} from '../local-node/strategy-bundle.mjs';
import {withLocalExecutionPauseHandler} from '../local-node/retained-store.mjs';
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
      compilation, runDefinition: definition, now,
      selectRetention: () => ({availableUntil: '2027-01-01T00:00:00.000Z',
        deleteBy: '2027-01-02T00:00:00.000Z', metadataDeleteBy: '2027-01-03T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z'})}, requestJournal, runRef,
    sources: captures.map(captured => ({captured, sourceEvidence: {}})),
    store, managedRun, infer: {graph}, selected, originalPreparation:{scope}, plan:{compiled, runDefinition:definition},
    captures, sourceProfile:adapter, ledger, now: () => '2026-11-05T00:00:00.000Z',
    current() {if (!current) throw new Error('OriginalNotCurrent');},
    retain(value) {assert.equal(duty, undefined); duty = value;}};
  return {options, moon, adapter, events, lookup, original, observation, evidence, left,
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


test('same Host continuation selects original completed Result prefix without the raw-capture prefix entrance', async () => {
  const f = fixture(), host = {}, old = f.options.acquired.control.startInstalledOriginalComposedKeyedPrefix;
  let hostCalls = 0;
  f.options.acquired.control.startInstalledOriginalComposedKeyedPrefix = () => {throw new Error('raw prefix reentry');};
  f.options.acquired.control.prepareInstalledOriginalComposedKeyedHostInput = (...args) => {
    assert.strictEqual(args.at(-1), host); hostCalls++;
    return {prefix: old(...args.slice(0, -1))};
  };
  const result = await prepareAcquiredEffectKeyedPrefix({...f.options, originalHost: host});
  assert.strictEqual(result.lookup, f.original);
  assert.equal(hostCalls, 1);
  assert.equal(await f.duty().cleanup(), true);
});

function sameHostContinuation({failure, lostCurrent = false} = {}) {
  const text = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  let node;
  const walk = value => {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'FunctionDeclaration' && value.id?.name === 'beforeModelPrepare') node = value;
    for (const item of Object.values(value)) {
      if (Array.isArray(item)) item.forEach(walk);
      else if (item && typeof item === 'object') walk(item);
    }
  };
  walk(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(node);
  let settle, pending = new Promise(resolve => {settle = resolve;}), calls = 0, binds = 0, adopts = 0;
  let current = true;
  const host = {}, run = {}, member = {selection: {graph: {}}, originalSelection: {}, originalPreparation: {}};
  const original = {lookup: {}}, acquired = {}, controller = new AbortController();
  const ports = {deferredKeyedMember: member, moon: {
    clientProgramInferPlanBoundary: graph => {assert.strictEqual(graph, member.selection.graph); return {_0: 4};},
    clientProgramInstalledEffectManagedKeyedHostBind(actualRun, actualHost, lookup) {
      assert.strictEqual(actualRun, run); assert.strictEqual(actualHost, host); assert.strictEqual(lookup, original.lookup);
      binds++; return ok(undefined);
    }}, current() {controller.signal.throwIfAborted(); if (!current) throw new Error('same original retired');},
    runtimeField: (value, index) => value[`_${index}`], checked: value => {
      assert.equal(value.$tag, 1); return value._0;
    }, async prepareAcquiredEffectKeyedPrefix(options) {
      calls++; assert.strictEqual(options.originalHost, host); assert.strictEqual(options.acquired, acquired);
      options.retain({pending: true}); await pending;
      if (failure) throw failure.value;
      return original;
    }, managedRun: run, modelPlan: {}, captures: [], evidence: [], requestJournal: {}, runRef: {},
    sourceProfile: {}, ledger: {}, contentRun: {}, store: {}, principalId: 'explicit', signal: controller.signal,
    now: () => 'original time', checkedHost: host, acquired,
    modelGroup: {bindKeyedFamily(value) {assert.strictEqual(value, original); adopts++;}}};
  const create = new Function(...Object.keys(ports), `let keyedAttempted = false, keyedPreparation,
    keyedCleanup, keyedFamily, captureCompletedAt; ${text.slice(node.start, node.end)};
    return {beforeModelPrepare, retained: () => keyedCleanup};`);
  const actual = create(...Object.values(ports));
  return {...actual, settle() {if (lostCurrent) current = false; settle();}, controller,
    counts: () => ({calls, binds, adopts})};
}

test('same Host pre-Model await shares one pending original and never starts it for another task', async () => {
  const f = sameHostContinuation();
  await f.beforeModelPrepare(3); assert.deepEqual(f.counts(), {calls: 0, binds: 0, adopts: 0});
  const first = f.beforeModelPrepare(4), second = f.beforeModelPrepare(4);
  await Promise.resolve(); assert(f.retained()); assert.deepEqual(f.counts(), {calls: 1, binds: 0, adopts: 0});
  f.settle(); await Promise.all([first, second]); await f.beforeModelPrepare(4);
  assert.deepEqual(f.counts(), {calls: 1, binds: 1, adopts: 1});
});

test('same Host pre-Model current loss and original undefined failure cannot bind or retry', async () => {
  for (const options of [{lostCurrent: true}, {failure: {value: undefined}}]) {
    const f = sameHostContinuation(options), first = f.beforeModelPrepare(4);
    await Promise.resolve(); assert(f.retained()); f.settle();
    for (const pending of [first, f.beforeModelPrepare(4)]) {
      let rejected = false;
      try {await pending;} catch (error) {
        rejected = true;
        if (options.failure) assert.strictEqual(error, undefined);
        else assert.match(error.message, /retired/);
      }
      assert(rejected);
    }
    assert.deepEqual(f.counts(), {calls: 1, binds: 0, adopts: 0});
  }
});

test('actual Local input selection awaits original Host continuation before dispatch and refuses task replacement', async () => {
  for (const replace of [false, true]) {
    let resume, task = 4, dispatched = 0;
    const pending = new Promise(resolve => {resume = resolve;});
    const setup = {}, configuration = withLocalExecutionPauseHandler(undefined, () => {}, async actual => {
      assert.equal(actual, 4); await pending; if (replace) task = 5;
    });
    const entry = localStrategyContribution({
      strategyModule_local_Registration: () => ({}), strategyHostRegistrationSelectionKey: () => 'local',
      strategyHostNextTask: () => task, strategyHostManagedProducers: () => [], strategyHostManagedInputCount: () => 0,
      strategyModule_local_ManagedDispatch() {dispatched++; return ok({});},
      strategyModule_local_ManagedCapacity: () => [0n, 0n], strategyModule_local_ManagedDuration: () => 0n,
      strategyHostReleasableManagedProducers: () => [],
    }, setup, value => value._0, configuration);
    const result = entry.beforeNext().then(() => entry.prepareNext(new Map()));
    await Promise.resolve(); assert.equal(dispatched, 0); resume();
    if (replace) await assert.rejects(result, /LocalTaskChangedDuringPreparation/);
    else assert.equal((await result).task, 4);
    assert.equal(dispatched, replace ? 0 : 1);
  }
});


test('same Host pending original cancellation cannot publish the later Model input', async () => {
  const f = sameHostContinuation(), original = new Error('original cancellation');
  const pending = f.beforeModelPrepare(4); await Promise.resolve(); assert(f.retained());
  f.controller.abort(original); f.settle();
  await assert.rejects(pending, error => error === original);
  await assert.rejects(f.beforeModelPrepare(4), error => error === original);
  assert.deepEqual(f.counts(), {calls: 1, binds: 0, adopts: 0});
});


test('same Host direct Result left reaches one lookup without prefix execution or work', async () => {
  const f = fixture(), host = {};
  f.options.acquired.control.prepareInstalledOriginalComposedKeyedHostInput = (...args) => {
    assert.strictEqual(args.at(-1), host); assert(f.duty()); return {left: f.left};
  };
  f.options.acquired.control.startInstalledOriginalComposedKeyedPrefix = () => {throw new Error('unexpected raw prefix');};
  const result = await prepareAcquiredEffectKeyedPrefix({...f.options, originalHost: host});
  assert.strictEqual(result.lookup, f.original);
  assert.deepEqual(f.counts(), {acquired: 1, prepares: 1, advances: 0, closes: 0, cleanups: 0});
  assert.equal(await f.duty().cleanup(), true);
  assert(!f.events.includes('prefix-start')); assert(!f.events.includes('prefix-cancel'));
  assert(!f.events.includes('prefix-cleanup'));
});
