import assert from 'node:assert/strict';
import test from 'node:test';
import {configureInferEvidence, projectInferEvidence, withPreparedInferEvidence} from './infer-evaluation-evidence.mjs';

// Actual imported Host routing with explicit original/capacity ports. These
// controls do not establish Core issuance, Store durability or SDK usage values.
function fixture({wire = '{"input_tokens":0,"output_tokens":null}', authorize, capture, record,
  inventory = true, current} = {}) {
  const trace = [], children = [], captured = [], recorded = [];
  let configuration;
  const facts = {
    moon: {clientProgramInferTargetName: () => 'answer',
      clientProgramReserveInferEvidenceCopy() {throw Error('SeparateLedgerForbidden');}},
    control: {compiledInferEvaluationPolicy: () => ({cid: 'original-policy'})},
    plan: {runDefinition: {identity: 'original-run'}, compiled: {}},
    selected: {step: 0}, authorityScopeCid: 'original-authority',
    current() {trace.push('current'); current?.();},
    captureOwner: {
      usageInventory(check) {
        check(); trace.push('original fixed window admitted');
        return inventory ? {count: 1, cid: 'original-bundle', calls: [{slotCid: 'original-slot', outcome: 'ok'}]} : undefined;
      },
      projectUsage(slot, maxBytes, check) {
        check(); assert.equal(slot, 0); assert.equal(maxBytes, 4096);
        trace.push('original bounded projection'); return wire;
      },
      evaluationBundle() {throw Error('FullBundleForbidden');},
    },
    continuation: {entry: () => ({slotCid: 'original-slot', attemptCid: 'original-attempt'})},
    retainCopy(child) {children.push(child);},
  };
  configuration = configureInferEvidence({kind: 'usage', target: 'answer', destination: 'local:usage', maxBytes: 4096,
    authorize: async binding => {
      trace.push('authorize');
      assert.equal(children.length, 1);
      assert.equal(children[0].cleanupPending(), true);
      assert(trace.includes('original fixed window admitted'));
      return authorize ? authorize(binding, facts) : true;
    },
    sink: {
      capture: async value => {trace.push('capture'); captured.push(value); return capture ? capture(value, facts) : {status: 'complete'};},
      record: async value => {trace.push('record'); recorded.push(value); return record?.(value, facts);},
    }});
  facts.configuration = configuration;
  return {facts, trace, children, captured, recorded};
}

test('usage forwards only the bounded original wire and binding without full Evidence or another Ledger', async () => {
  for (const wire of ['{"input_tokens":2,"output_tokens":3}', '{"input_tokens":0,"output_tokens":0}',
    '{"input_tokens":null,"output_tokens":null}']) {
    const f = fixture({wire});
    const manifest = await projectInferEvidence(f.facts);
    assert.equal(manifest.kind, 'usage'); assert.equal(manifest.status, 'complete');
    assert.deepEqual(f.captured[0].wires, {usage: wire});
    assert.deepEqual(f.captured[0].subject, {runDefinitionCid: 'original-run', authorityScopeCid: 'original-authority'});
    assert.deepEqual(f.captured[0].original, {captureBundleCid: 'original-bundle', modelCallSlotCid: 'original-slot'});
    assert.equal(f.captured[0].attemptCid, 'original-attempt');
    assert.equal(f.children[0].cleanupPending(), false); assert.equal(await f.children[0].close(), true);
    assert.strictEqual(f.recorded[0].manifest, manifest);
  }
});

test('usage omission from prepared full-input preservation cannot authorize allocate or enter its legacy copy Ledger', async () => {
  const f = fixture(); let calls = 0;
  assert.equal(await withPreparedInferEvidence({...f.facts, selected: {occurrence: {}},
    moon: {clientProgramInferOccurrenceTargetName: () => 'answer'},
    consume(value) {assert.equal(value, undefined); calls++; return 'same original consumer';}}), 'same original consumer');
  assert.equal(calls, 1); assert.deepEqual(f.trace, []); assert.equal(f.children.length, 0);
});

test('usage current loss after authorization stops projection capture and record without replacing Model success', async () => {
  let lost = false;
  const f = fixture({current() {if (lost) throw Error('OriginalRetired');}, authorize() {lost = true; return true;}});
  const result = await projectInferEvidence(f.facts);
  assert.equal(result.status, 'incomplete'); assert.equal(f.captured.length, 0); assert.equal(f.recorded.length, 0);
  assert.equal(f.trace.includes('original bounded projection'), false); assert.equal(f.children[0].cleanupPending(), false);
});

test('usage denial or missing adopted inventory never falls back to a bundle or fabricated observations', async () => {
  const denied = fixture({authorize: () => false});
  const manifest = await projectInferEvidence(denied.facts);
  assert.equal(manifest.status, 'incomplete'); assert.equal(manifest.items[0].reason, 'EvidenceReadDenied');
  assert.equal(denied.captured.length, 0); assert.equal(denied.recorded.length, 1);
  const absent = fixture({inventory: false});
  assert.equal((await projectInferEvidence(absent.facts)).status, 'incomplete');
  assert.equal(absent.trace.includes('authorize'), false); assert.equal(absent.children.length, 0);
  assert.equal(absent.recorded.length, 0);
});

test('usage Sink completion reads one own DATA status without enumerating or retaining callback payload', async () => {
  let gets = 0;
  for (const completion of [{get status() {gets++; return 'complete';}},
    new Proxy({}, {ownKeys() {throw Error('ProxyTrap');}})]) {
    const f = fixture({capture: () => completion});
    const manifest = await projectInferEvidence(f.facts);
    assert.equal(manifest.status, 'incomplete'); assert.equal(manifest.items[0].reason, 'EvidenceSinkFailure');
    assert.deepEqual(Object.keys(manifest.items[0]).sort(), ['attemptCid', 'modelCallSlotCid', 'reason', 'status']);
  }
  const extra = fixture({capture: () => ({status: 'complete', get secret() {gets++; throw Error('DoNotRead');}})});
  const manifest = await projectInferEvidence(extra.facts);
  assert.equal(manifest.status, 'complete');
  assert.deepEqual(Object.keys(manifest.items[0]).sort(), ['attemptCid', 'modelCallSlotCid', 'status']);
  assert.equal(gets, 0);
});

test('usage keeps the same copy child pending through capture and record awaits and refuses reentry', async () => {
  let captureRelease, recordRelease;
  const captureWait = new Promise(resolve => {captureRelease = resolve;});
  const recordWait = new Promise(resolve => {recordRelease = resolve;});
  let captureEntered, recordEntered;
  const captureReady = new Promise(resolve => {captureEntered = resolve;});
  const recordReady = new Promise(resolve => {recordEntered = resolve;});
  const f = fixture({async capture() {captureEntered(); await captureWait; return {status: 'complete'};},
    async record() {recordEntered(); await recordWait;}});
  const pending = projectInferEvidence(f.facts); await captureReady;
  assert.equal(await f.children[0].close(), false); assert.equal(await f.children[0].cleanup(), false);
  const traceCount = f.trace.length;
  assert.equal((await projectInferEvidence(f.facts)).status, 'incomplete'); assert.equal(f.trace.length, traceCount);
  captureRelease(); await recordReady;
  assert.equal(f.children[0].cleanupPending(), true); assert.equal(await f.children[0].close(), false);
  recordRelease(); assert.equal((await pending).status, 'complete');
  assert.equal(f.children[0].cleanupPending(), false); assert.equal(await f.children[0].close(), true);
});

test('usage Sink failure and post-capture current loss never create another callback or send', async () => {
  const failed = fixture({capture() {throw Error('SinkFailed');}});
  assert.equal((await projectInferEvidence(failed.facts)).status, 'incomplete');
  assert.equal(failed.captured.length, 1); assert.equal(failed.recorded.length, 1);
  let lost = false;
  const retired = fixture({current() {if (lost) throw Error('Retired');}, capture() {lost = true; return {status: 'complete'};}});
  const manifest = await projectInferEvidence(retired.facts);
  assert.equal(manifest.status, 'incomplete'); assert.equal(manifest.items[0].status, 'complete');
  assert.equal(retired.captured.length, 1); assert.equal(retired.recorded.length, 0);
});


test('usage claims its flight before current can reenter and refuses missing current before inventory', async () => {
  let nested, entered = false;
  const f = fixture({current() {
    if (!entered) {entered = true; nested = projectInferEvidence(f.facts);}
  }});
  assert.equal((await projectInferEvidence(f.facts)).status, 'complete');
  assert.equal((await nested).status, 'incomplete');
  assert.equal(f.trace.filter(value => value === 'original fixed window admitted').length, 1);
  const absent = fixture(); delete absent.facts.current;
  assert.equal((await projectInferEvidence(absent.facts)).status, 'incomplete');
  assert.deepEqual(absent.trace, []);
});

test('usage checks current after the original entry callback and enforces remaining bytes before Sink', async () => {
  let lost = false;
  const retired = fixture({current() {if (lost) throw Error('Retired');}});
  retired.facts.continuation.entry = () => {lost = true; return {slotCid: 'original-slot', attemptCid: 'original-attempt'};};
  assert.equal((await projectInferEvidence(retired.facts)).status, 'incomplete');
  assert.equal(retired.trace.includes('authorize'), false); assert.equal(retired.recorded.length, 0);
  const oversized = fixture({wire: 'x'.repeat(4097)});
  assert.equal((await projectInferEvidence(oversized.facts)).status, 'incomplete');
  assert.equal(oversized.captured.length, 0); assert.equal(oversized.recorded.length, 1);
});

test('usage retention refusal never calls a Sink and an adopted-then-thrown child finishes only its local work', async () => {
  for (const adopted of [false, true]) {
    const f = fixture();
    const originalPlan = f.facts.plan, originalContinuation = f.facts.continuation;
    f.facts.retainCopy = child => {
      // An actual callback can adopt and then throw. It must see pending work
      // during the callback; after refusal no Sink work may have started.
      assert.equal(child.cleanupPending(), true);
      if (adopted) f.children.push(child);
      throw Error('OriginalCopyRetentionRefused');
    };
    const result = await projectInferEvidence(f.facts);
    assert.equal(result.status, 'incomplete');
    assert.equal(f.captured.length, 0); assert.equal(f.recorded.length, 0);
    assert.equal(f.trace.includes('authorize'), false);
    assert.equal(f.trace.includes('original bounded projection'), false);
    assert.strictEqual(f.facts.plan, originalPlan);
    assert.strictEqual(f.facts.continuation, originalContinuation);
    assert.equal(f.children.length, adopted ? 1 : 0);
    if (adopted) {
      assert.equal(f.children[0].cleanupPending(), false);
      assert.equal(await f.children[0].cleanup(), true);
      assert.equal(await f.children[0].close(), true);
    }
  }
});
