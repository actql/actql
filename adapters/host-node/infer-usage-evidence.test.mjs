import assert from 'node:assert/strict';
import test from 'node:test';
import {configureInferEvidence, projectInferEvidence, withPreparedInferEvidence} from './infer-evaluation-evidence.mjs';
import {runtimePair} from '../host-common/compiler-binding.generated.mjs';

// Actual imported physical binding with a finite, explicitly scripted Common
// action port. This fixture does not decide Common state, funding or custody;
// original_usage_publication_wbtest exercises those on the actual Resource.
function fixture({actions = ['retain', 'authorize', 'capture', 'record', 'retire'],
  observations = ['retained', 'authorized', 'captured', 'recorded', 'cleaned'],
  completion = 'complete', items = [[0, 'complete']], wire = '{"input_tokens":0,"output_tokens":null}',
  authorize, capture, record, current, keepItemsOnStop = false} = {}) {
  const children = [], captured = [], recorded = [], trace = [], observed = [];
  const usage = {}, tokens = actions.map((kind, index) => ({kind, index}));
  let cursor = 0, active, stopped = false, finished = false;
  const ok = _0 => ({$tag: 1, _0});
  const moon = {
    clientProgramInferTargetName: () => 'answer',
    clientProgramReserveInferEvidenceCopy() {assert.fail('SeparateLedgerForbidden');},
    clientProgramNextOriginalInferUsageAction(value) {
      assert.strictEqual(value, usage); assert.equal(active, undefined);
      if (finished) return ok(undefined);
      if (stopped) cursor = actions.indexOf('retire');
      active = tokens[cursor]; return ok(active);
    },
    clientProgramOriginalInferUsageActionKind: token => token === active ? token.kind : undefined,
    clientProgramOriginalInferUsageActionSlot: () => 0,
    clientProgramOriginalInferUsageActionWire: () => wire,
    clientProgramOriginalInferUsageBindingMatches(value, token, slot, attempt) {
      assert.strictEqual(value, usage);
      assert.strictEqual(token, active);
      return slot === 'original-slot' && attempt === 'original-attempt';
    },
    clientProgramObserveOriginalInferUsageAction(value, token, observation) {
      assert.strictEqual(value, usage);
      assert.strictEqual(token, active);
      assert.equal(observation, observations[cursor]);
      observed.push(observation); active = undefined; cursor++;
      if (observation === 'cleaned') finished = true;
      return ok(undefined);
    },
    clientProgramStopOriginalInferUsagePublication(value) {assert.strictEqual(value, usage); stopped = true;},
    clientProgramOriginalInferUsageCompletion: () => stopped ? 'RequiredEvidenceUnavailable' : completion,
    clientProgramOriginalInferUsageItemCount: () => stopped && !keepItemsOnStop ? 0 : items.length,
    clientProgramOriginalInferUsageItem: (_, index) => {
      trace.push('retained item read'); return runtimePair(...items[index]);
    },
    clientProgramOriginalInferUsageItemAttempt: () => 'original-attempt',
  };
  const facts = {moon,
    control: {compiledInferEvaluationPolicy: () => ({cid: 'original-policy'})},
    plan: {runDefinition: {identity: 'original-run'}, compiled: {}},
    selected: {step: 0}, authorityScopeCid: 'original-authority',
    current() {trace.push('current'); current?.();},
    captureOwner: {
      usageInventory(check) {
        check(); trace.push('original fixed window admitted');
        return {count: 1, cid: 'original-bundle', calls: [{slotCid: 'original-slot', outcome: 'ok'}]};
      },
      beginUsage(maxBytes, check) {
        assert.equal(maxBytes, 4096); check(); trace.push('same Common continuation'); return usage;
      },
      evaluationBundle() {assert.fail('FullBundleForbidden');},
    },
    continuation: {entry: () => ({slotCid: 'original-slot', attemptCid: 'original-attempt'})},
    retainCopy(child) {children.push(child);},
  };
  facts.configuration = configureInferEvidence({kind: 'usage', target: 'answer', destination: 'local:usage', maxBytes: 4096,
    authorize: async binding => {
      trace.push('authorize'); assert.equal(children.length, 1);
      assert.equal(children[0].cleanupPending(), true);
      return authorize ? authorize(binding, facts) : true;
    },
    sink: {
      capture: async value => {captured.push(value); return capture ? capture(value, facts) : {status: 'complete'};},
      record: async value => {recorded.push(value); return record?.(value, facts);},
    }});
  return {facts, trace, children, captured, recorded, observed};
}

test('usage physical binding executes issued original actions without deciding completion or another Ledger', async () => {
  for (const wire of ['{"input_tokens":2,"output_tokens":3}', '{"input_tokens":0,"output_tokens":0}',
    '{"input_tokens":null,"output_tokens":null}']) {
    const f = fixture({wire});
    const manifest = await projectInferEvidence(f.facts);
    assert.equal(manifest.status, 'complete');
    assert.deepEqual(f.captured[0].wires, {usage: wire});
    assert.deepEqual(f.captured[0].subject, {runDefinitionCid: 'original-run', authorityScopeCid: 'original-authority'});
    assert.deepEqual(f.captured[0].original, {captureBundleCid: 'original-bundle', modelCallSlotCid: 'original-slot'});
    assert.equal(f.captured[0].attemptCid, 'original-attempt');
    assert.deepEqual(f.observed, ['retained', 'authorized', 'captured', 'recorded', 'cleaned']);
    assert.equal(f.children[0].cleanupPending(), false); assert.equal(await f.children[0].close(), true);
    assert.strictEqual(f.recorded[0].manifest, manifest);
  }
});

test('usage retention refusal emits no Sink callback even when the original child was adopted then thrown', async () => {
  for (const adopted of [false, true]) {
    const f = fixture({actions: ['retain', 'retire'], observations: ['refused', 'cleaned'],
      completion: 'RequiredEvidenceUnavailable', items: []});
    const originalPlan = f.facts.plan, originalContinuation = f.facts.continuation;
    f.facts.retainCopy = child => {
      assert.equal(child.cleanupPending(), true);
      if (adopted) f.children.push(child);
      throw Error('OriginalCopyRetentionRefused');
    };
    assert.equal((await projectInferEvidence(f.facts)).status, 'incomplete');
    assert.equal(f.captured.length, 0); assert.equal(f.recorded.length, 0);
    assert.strictEqual(f.facts.plan, originalPlan); assert.strictEqual(f.facts.continuation, originalContinuation);
    assert.deepEqual(f.observed, ['refused', 'cleaned']);
    if (adopted) {
      assert.equal(f.children[0].cleanupPending(), false);
      assert.equal(await f.children[0].cleanup(), true);
    }
  }
});

test('usage record await remains with the same retained child until actual callback settlement', async () => {
  let release, entered;
  const recording = new Promise(resolve => {entered = resolve;});
  const f = fixture({record: async () => {entered(); await new Promise(resolve => {release = resolve;});}});
  const result = projectInferEvidence(f.facts);
  await recording;
  assert.equal(f.children[0].cleanupPending(), true);
  assert.equal(await f.children[0].cleanup(), false);
  assert.equal(f.observed.includes('cleaned'), false);
  release(); await result;
  assert.equal(f.children[0].cleanupPending(), false);
  assert.equal(f.observed.at(-1), 'cleaned');
});

test('usage reports only own DATA Sink completion without enumerating callback payloads', async () => {
  let gets = 0;
  for (const response of [{get status() {gets++; return 'complete';}},
    new Proxy({}, {ownKeys() {assert.fail('ProxyTrap');}})]) {
    const f = fixture({capture: () => response,
      observations: ['retained', 'authorized', 'incomplete', 'recorded', 'cleaned'],
      completion: 'EvidenceSinkFailure', items: [[0, 'EvidenceSinkFailure']]});
    const manifest = await projectInferEvidence(f.facts);
    assert.equal(manifest.status, 'incomplete');
    assert.equal(manifest.items[0].reason, 'EvidenceSinkFailure');
  }
  const f = fixture({capture: () => ({status: 'complete', get extra() {gets++; return 'unread';}})});
  assert.equal((await projectInferEvidence(f.facts)).status, 'complete');
  assert.equal(gets, 0);
});

test('usage current loss after authorize reports stop and retires without capture record or resend', async () => {
  let lost = false;
  const f = fixture({current() {if (lost) throw Error('OriginalRetired');},
    authorize() {lost = true; return true;}});
  assert.equal((await projectInferEvidence(f.facts)).status, 'incomplete');
  assert.equal(f.captured.length, 0); assert.equal(f.recorded.length, 0);
  assert.deepEqual(f.observed, ['retained', 'authorized', 'cleaned']);
  assert.equal(f.children[0].cleanupPending(), false);
});

test('usage omission from prepared full-input preservation never enters its legacy copy Ledger', async () => {
  const f = fixture(); let calls = 0;
  assert.equal(await withPreparedInferEvidence({...f.facts, selected: {occurrence: {}},
    moon: {clientProgramInferOccurrenceTargetName: () => 'answer'},
    consume(value) {assert.equal(value, undefined); calls++; return 'same consumer';}}), 'same consumer');
  assert.equal(calls, 1); assert.deepEqual(f.trace, []); assert.equal(f.children.length, 0);
});

test('usage claims its existing flight before a current callback can reenter', async () => {
  let nested, entered = false;
  const f = fixture({current() {
    if (!entered) {entered = true; nested = projectInferEvidence(f.facts);}
  }});
  assert.equal((await projectInferEvidence(f.facts)).status, 'complete');
  assert.equal((await nested).status, 'incomplete');
  assert.equal(f.trace.filter(item => item === 'same Common continuation').length, 1);
});

test('usage current loss after record reuses its retained items without another original snapshot', async () => {
  let lost = false;
  const f = fixture({current() {if (lost) throw Error('OriginalRetired');},
    record() {lost = true;}, keepItemsOnStop: true});
  const result = await projectInferEvidence(f.facts);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.reason, 'RequiredEvidenceUnavailable');
  assert.equal(f.recorded.length, 1); assert.equal(f.captured.length, 1);
  assert.equal(f.recorded[0].manifest.status, 'complete');
  assert.notStrictEqual(result, f.recorded[0].manifest);
  assert.strictEqual(result.items, f.recorded[0].manifest.items);
  assert.strictEqual(result.subject, f.recorded[0].manifest.subject);
  assert.equal(f.trace.filter(value => value === 'retained item read').length, 1);
  assert.equal(f.children[0].cleanupPending(), false);
  assert.equal(f.observed.at(-1), 'cleaned');
});
