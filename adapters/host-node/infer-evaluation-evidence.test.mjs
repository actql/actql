import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {configureInferEvidence, projectInferEvidence, withPreparedInferEvidence} from './infer-evaluation-evidence.mjs';

function fixture({kind, authorize = () => true, capture = async () => ({status: 'complete', references: {}}), releaseFails = false, maxBytes = 4096,
  structuredResponse = {risk: 'high'}} = {}) {
  const trace = [], retained = [], manifests = [];
  const record = {model_call_slot_cid: 'slot', semantic_request_cid: 'request', structured_response: structuredResponse,
    evidence: {model_call_slot_cid: 'slot', model_task_contract_cid: 'task', validated_structured_output_cid: 'output'}};
  const config = configureInferEvidence({...(kind === undefined ? {} : {kind}), target: 'named', destination: 'local:evaluator', maxBytes, authorize,
    sink: {capture: async input => {trace.push('copy handed to sink'); return capture(input);}, record: async input => manifests.push(input)}});
  const moon = {clientProgramInferTargetName: () => 'named',
    clientProgramReserveInferEvidenceCopy: () => {trace.push('reserved'); return {$tag: 1, _0: {_0: 'ledger', _1: 'reservation'}};},
    clientProgramReleaseInferEvidenceCopy: () => {trace.push('release'); return {$tag: releaseFails ? 0 : 1};},
    clientProgramModelRequestInputFrame: () => {trace.push('serialize'); return '{}';}, clientProgramDefinitionCid: () => 'program'};
  const facts = {configuration: config, moon, control: {compiledInferEvaluationPolicy: () => ({kind: 'data_policy', cid: 'policy', wire: '{}'})},
    plan: {runDefinition: {identity: 'run'}, compiled: {}}, selected: {step: 0, providerBinding: {identity: 'provider'}},
    captureOwner: {evaluationBundle: () => ({count: 1, cid: 'bundle', wire: JSON.stringify({captures: [record]}),
      calls: [{slotCid: 'slot', callWire: '{"model_call_slot_cid":"slot","model_task_cid":"task"}', outcome: 'ok'}]})},
    operation: {evaluationRequest: () => ({_0: {}, _1: '{}', _2: '{}'})}, continuation: {entry: () => ({slotCid: 'slot', attemptCid: 'attempt'})},
    authorityScopeCid: 'scope', retainCopy: value => retained.push(value)};
  return {trace, retained, manifests, facts, config};
}

function preparedFixture(options) {
  const f = fixture(options);
  const original = 'e\u0301/é/CR\r/LF\n/CRLF\r\n/\u0000/\\/"/😀';
  Object.assign(f.facts.moon, {
    clientProgramInferOccurrenceTargetName: () => 'named',
    clientProgramInferPreparedCallCount: () => 1,
    clientProgramInferPreparedCallAt: () => ({wire: '{"slot":"original"}'}),
    strategyRunEvidenceJson: value => value.wire,
    clientProgramModelRequestInputFrameBounded: () => {f.trace.push('serialize'); return '{}';},
  });
  f.facts.selected.occurrence = {};
  f.facts.preparedCallSet = {};
  f.facts.operation.preparedPhysicalRequest = () => ({_0: {}, _1: original, _2: '{"unknown":true}'});
  return {...f, original};
}

test('fresh Effect omission skips only optional provider input preservation and retains the mandatory snapshot', async () => {
  const source = readFileSync(new URL('./installed-model-continuation.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let configuration;
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'CallExpression' && value.callee.name === 'withPreparedInferEvidence') {
      configuration = value.arguments[0].properties.find(property => property.key.name === 'configuration').value;
    }
    for (const child of Object.values(value)) {
      if (Array.isArray(child)) child.forEach(visit); else visit(child);
    }
  };
  visit(ast); assert(configuration);
  const select = Function('preserveEvidenceInputs', 'inferEvidence', `return (${source.slice(configuration.start, configuration.end)});`);
  const original = {}, snapshot = {version: 'actql-installed-model-input/0.1', rows: [['same original']]};
  assert.strictEqual(select(true, original), original);
  assert.equal(select(false, original), undefined);
  let retained = 0;
  assert.strictEqual(await withPreparedInferEvidence({configuration: select(false, original),
    selected: {step: 0}, moon: {clientProgramInferTargetName: () => 'original'},
    consume(optional) {assert.equal(optional, undefined); retained++; return snapshot;}}), snapshot);
  assert.equal(retained, 1);
});

function partialFixture(options = {}) {
  const f = fixture(options);
  const calls = ['saved', 'unknown'].map((name, slot) => ({slotCid: name,
    callWire: JSON.stringify({model_call_slot_cid: name, model_task_cid: 'task',
      input_key_cid: `key-${slot}`, fixed_request_cid: `request-${slot}`}),
    state: slot === 0 ? 'SavedSuccess' : 'EnteredUnknown',
    outcome: slot === 0 ? 'ok' : 'result_unknown',
    entry: {slotCid: name, attemptCid: `attempt-${slot}`},
    ...(slot === 0 ? {captureBundleCid: 'saved-bundle'} : {})}));
  const inventory = {count: 2, calls, async readBundle(slot, beforeRead) {
    assert.equal(slot, 0);
    beforeRead(options.physicalBytes ?? 100);
    f.trace.push('private decode');
    return {count: 1, cid: 'saved-bundle', wire: JSON.stringify({captures: [{
      model_call_slot_cid: 'saved', semantic_request_cid: 'request-0', structured_response: {risk: 'low'},
      evidence: {model_call_slot_cid: 'saved', model_task_contract_cid: 'task', validated_structured_output_cid: 'output'},
    }]})};
  }};
  f.facts.continuation = {evaluationInventory: () => inventory};
  f.facts.partial = true;
  return {...f, inventory};
}

test('partial Evidence reserves before private reading and retains the original unknown inventory', async () => {
  const f = partialFixture();
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['reserved', 'private decode', 'serialize', 'copy handed to sink', 'release']);
  const manifest = f.manifests[0].manifest;
  assert.equal(manifest.status, 'incomplete');
  assert.deepEqual(manifest.items.map(item => [item.modelCallSlotCid, item.attemptCid,
    item.inputKeyCid, item.callState, item.status]), [
    ['saved', 'attempt-0', 'key-0', 'SavedSuccess', 'complete'],
    ['unknown', 'attempt-1', 'key-1', 'EnteredUnknown', 'incomplete'],
  ]);
  assert.equal(manifest.items[1].reason, 'ModelResultUnknown');
  assert.equal(Object.hasOwn(manifest.items[1], 'references'), false);
});

test('denied partial Evidence cannot decode private captures or disclose typed key identities', async () => {
  const f = partialFixture({authorize: () => false});
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['reserved', 'release']);
  assert.equal(f.manifests[0].manifest.items.length, 2);
  for (const item of f.manifests[0].manifest.items) {
    assert.equal(item.reason, 'EvidenceReadDenied');
    assert.equal(Object.hasOwn(item, 'inputKeyCid'), false);
    assert.equal(Object.hasOwn(item, 'references'), false);
  }
});

test('partial physical copy exhaustion refuses before decoding without dropping unknown items', async () => {
  const f = partialFixture({physicalBytes: 1000});
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['reserved', 'release']);
  assert.deepEqual(f.manifests[0].manifest.items.map(item => [item.modelCallSlotCid, item.reason]), [
    ['saved', 'EvaluationBudgetExceeded'], ['unknown', 'ModelResultUnknown'],
  ]);
});

test('missing partial originals keep the complete required inventory without invented responses', async () => {
  const f = partialFixture();
  f.inventory.readBundle = async () => undefined;
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.manifests[0].manifest.items.map(item => [item.modelCallSlotCid, item.reason]), [
    ['saved', 'RequiredEvidenceUnavailable'], ['unknown', 'ModelResultUnknown'],
  ]);
  assert.deepEqual(f.trace, ['reserved', 'release']);
});

test('a foreign original capture cannot be shifted into a partial saved slot', async () => {
  const f = partialFixture();
  f.inventory.readBundle = async () => ({count: 1, cid: 'foreign',
    wire: JSON.stringify({captures: [{model_call_slot_cid: 'foreign'}]})});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.items[0].reason, 'EvidenceSubjectMismatch');
  assert.equal(f.manifests[0].manifest.items.length, 2);
  assert.deepEqual(f.trace, ['reserved', 'release']);
});

test('partial copy cleanup failure preserves inventory and retries the same reservation once', async () => {
  const f = partialFixture({releaseFails: true});
  await projectInferEvidence(f.facts);
  const manifest = f.manifests[0].manifest;
  assert.equal(manifest.reason, 'EvidenceCopyCleanupPending');
  assert.equal(manifest.cleanupPending, true);
  assert.deepEqual(manifest.items.map(item => item.modelCallSlotCid), ['saved', 'unknown']);
  assert.equal(f.retained[0].cleanupPending(), true);
  assert.equal(await f.retained[0].cleanup(), false);
  let retries = 0;
  f.facts.moon.clientProgramReleaseInferEvidenceCopy = () => {retries++; return {$tag: 1};};
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(retries, 1);
  assert.equal(f.retained[0].cleanupPending(), false);
  assert.equal(f.trace.filter(value => value === 'reserved').length, 1);
});

test('prepared originals reserve copy custody before persistence and retain exact raw text', async () => {
  const f = preparedFixture();
  let saved;
  await withPreparedInferEvidence({...f.facts, consume: async inputs => {
    f.trace.push('persist'); saved = structuredClone(inputs);
    assert.equal(await f.retained[0].close(), false);
  }});
  assert.deepEqual(f.trace, ['reserved', 'serialize', 'persist', 'release']);
  assert.deepEqual(saved, [{callWire: '{"slot":"original"}', typedInputWire: '{}',
    renderedInput: f.original, contextManifest: '{"unknown":true}'}]);
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('capture denial omits optional originals before reserving or serializing', async () => {
  const f = preparedFixture({authorize: facts => {
    assert.equal(facts.purpose, 'capture'); return false;
  }});
  let count = 0;
  await withPreparedInferEvidence({...f.facts, consume: inputs => {
    assert.equal(inputs, undefined); count++;
  }});
  assert.equal(count, 1);
  assert.deepEqual(f.trace, []);
});

test('prepared capture accounts JSON escaping at the exact existing copy ceiling', async () => {
  const initial = preparedFixture();
  const saved = [{callWire: '{"slot":"original"}', typedInputWire: '{}',
    renderedInput: initial.original, contextManifest: '{"unknown":true}'}];
  const exact = Buffer.byteLength(JSON.stringify(saved));
  for (const [maxBytes, accepted] of [[exact, true], [exact - 1, false]]) {
    const f = preparedFixture({maxBytes});
    await withPreparedInferEvidence({...f.facts, consume: inputs => {
      assert.deepEqual(inputs, accepted ? saved : undefined);
    }});
    assert.equal(f.retained[0].cleanupPending(), false);
    assert.equal(f.trace.filter(value => value === 'release').length, 1);
  }
});

test('failed prepared copy release retains the same retry handle without repeating persistence', async () => {
  const f = preparedFixture({releaseFails: true});
  let persisted = 0;
  await withPreparedInferEvidence({...f.facts, consume: () => {persisted++;}});
  assert.equal(f.retained[0].cleanupPending(), true);
  assert.equal(await f.retained[0].cleanup(), false);
  await withPreparedInferEvidence({...f.facts, consume: inputs => assert.equal(inputs, undefined)});
  assert.equal(f.trace.filter(value => value === 'reserved').length, 1);
  f.facts.moon.clientProgramReleaseInferEvidenceCopy = () => {f.trace.push('retry'); return {$tag: 1};};
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(f.trace.filter(value => value === 'retry').length, 1);
  assert.equal(persisted, 1);
});

test('persistence rejection releases optional copy custody and propagates the actual commit failure', async () => {
  const f = preparedFixture();
  await assert.rejects(withPreparedInferEvidence({...f.facts, consume: async () => {
    throw new Error('OriginalInputCommitFailed');
  }}), {message: 'OriginalInputCommitFailed'});
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('concurrent capture authorization cannot acquire two persistence flights', async () => {
  const authorize = [], f = preparedFixture({authorize: () => new Promise(resolve => authorize.push(resolve))});
  let finish, copied, omitted = 0;
  const entered = new Promise(resolve => {copied = resolve;});
  const first = withPreparedInferEvidence({...f.facts, consume: inputs => {
    assert.equal(inputs.length, 1); copied(); return new Promise(resolve => {finish = resolve;});
  }});
  const second = withPreparedInferEvidence({...f.facts, consume: inputs => {
    assert.equal(inputs, undefined); omitted++;
  }});
  assert.equal(authorize.length, 2);
  for (const permit of authorize) permit(true);
  await entered;
  await second;
  assert.equal(omitted, 1);
  assert.equal(f.trace.filter(value => value === 'reserved').length, 1);
  assert.equal(await f.retained[0].close(), false);
  finish(); await first;
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('optional projection reserves before serialization and returns copy capacity after sink settlement', async () => {
  const f = fixture();
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['reserved', 'serialize', 'copy handed to sink', 'release']);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('Effect projection uses original funding before decode and never allocates a destination-sized Ledger', async () => {
  let settle, entered;
  const gate = new Promise(resolve => {settle = resolve;});
  const started = new Promise(resolve => {entered = resolve;});
  const f = fixture({capture: async () => {entered(); await gate; return {status: 'complete'};}});
  f.facts.moon.clientProgramReserveInferEvidenceCopy = () => assert.fail('No independent Ledger for this Effect copy');
  f.facts.moon.clientProgramReleaseInferEvidenceCopy = () => assert.fail('Do not settle a foreign/absent reservation');
  const flight = projectInferEvidence({...f.facts, copyFunding(bundle) {
    assert.equal(bundle.count, 1); assert.equal(bundle.cid, 'bundle');
    f.trace.push('original funding');
  }});
  await started;
  assert.deepEqual(f.trace, ['original funding', 'serialize', 'copy handed to sink']);
  assert.equal(f.retained[0].cleanupPending(), true);
  assert.equal(await f.retained[0].close(), false, 'A pending Sink cannot acknowledge retirement');
  settle(); await flight;
  assert.equal(f.retained[0].cleanupPending(), false);
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(f.manifests[0].manifest.status, 'complete');
});

test('original Effect funding refusal records incomplete without serializing or acquiring another copy', async () => {
  const f = fixture();
  const failure = Object.assign(new Error('OriginalFundingRefused'), {code: 'OriginalFundingRefused'});
  await projectInferEvidence({...f.facts, copyFunding() {throw failure;}});
  assert.deepEqual(f.trace, []);
  assert.equal(f.retained.length, 0);
  assert.deepEqual(f.manifests[0].manifest, {status: 'incomplete', reason: 'OriginalFundingRefused'});
});

test('Effect external authorization and Sink returns recheck original current before any later capture', async () => {
  for (const boundary of ['authorize', 'sink']) {
    let closed = false, captures = 0;
    const f = fixture({authorize: async () => {if (boundary === 'authorize') closed = true; return true;},
      capture: async () => {captures++; closed = true; return {status: 'complete'};}});
    f.facts.moon.clientProgramReserveInferEvidenceCopy = () => assert.fail('No independent copy Ledger');
    const first = f.facts.captureOwner.evaluationBundle();
    const records = JSON.parse(first.wire).captures;
    records.push({...records[0], model_call_slot_cid: 'slot-2',
      evidence: {...records[0].evidence, model_call_slot_cid: 'slot-2'}});
    f.facts.captureOwner.evaluationBundle = () => ({...first, count: 2, wire: JSON.stringify({captures: records}),
      calls: [...first.calls, {...first.calls[0], slotCid: 'slot-2'}]});
    f.facts.continuation.entry = slot => ({slotCid: slot === 0 ? 'slot' : 'slot-2', attemptCid: 'attempt-' + slot});
    await projectInferEvidence({...f.facts, copyFunding() {}, current() {if (closed) throw new Error('OriginalClosed');}});
    assert.equal(captures, boundary === 'authorize' ? 0 : 1);
    assert.equal(f.retained[0].cleanupPending(), false);
    const manifest = f.manifests[0].manifest;
    assert.equal(manifest.status, 'incomplete'); assert.equal(manifest.items.length, 2);
    assert.deepEqual(manifest.items.map(item => item.status), boundary === 'authorize'
      ? ['incomplete', 'incomplete'] : ['complete', 'incomplete']);
    assert.equal(manifest.items[1].reason, 'RequiredEvidenceUnavailable');
    assert.equal(manifest.items[1].modelCallSlotCid, 'slot-2');
    assert.equal(f.trace.includes('reserved'), false);
  }
});

test('typed output preserves distinct decomposed/composed and CR/LF data member names', async () => {
  const original = {'e\u0301': {'line\r': 'CR\r', 'line\n': 'LF\n'}, 'é': 'CRLF\r\n'};
  let copied;
  const f = fixture({structuredResponse: original, capture: async ({wires}) => {
    copied = JSON.parse(wires.typedOutput).value;
    return {status: 'complete', references: {}};
  }});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.deepEqual(copied, {'e\u0301': {'line\r': 'CR\r', 'line\n': 'LF\n'}, 'é': 'CRLF\r\n'});
});

test('optional sink failure reports missing Evidence and releases its bounded copy', async () => {
  const f = fixture({capture: async () => {throw Object.assign(new Error('failure'), {code: 'SinkUnavailable'});}});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'incomplete');
  assert.equal(f.manifests[0].manifest.reason, 'SinkUnavailable');
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('typed output retains missing members and explicit NULL as different values', async () => {
  let copied;
  const f = fixture({structuredResponse: {absent: {}, present: {value: null}}, capture: async ({wires}) => {
    copied = JSON.parse(wires.typedOutput).value;
    return {status: 'complete', references: {}};
  }});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.deepEqual(copied, {absent: {}, present: {value: null}});
  assert.equal(Object.hasOwn(copied.absent, 'value'), false);
  assert.equal(Object.hasOwn(copied.present, 'value'), true);
});

test('copy exhaustion does not serialize or hand off protected originals', async () => {
  const f = fixture({maxBytes: 1});
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, []);
  assert.equal(f.manifests[0].manifest.reason, 'EvaluationBudgetExceeded');
});

test('failed common release stays in normal dispatch custody and is not successful cleanup', async () => {
  const f = fixture({releaseFails: true});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.reason, 'EvidenceCopyCleanupPending');
  assert.equal(f.retained[0].cleanupPending(), true);
  assert.equal(await f.retained[0].cleanup(), false);
  f.facts.moon.clientProgramReleaseInferEvidenceCopy = () => ({$tag: 1});
  assert.equal(await f.retained[0].cleanup(), true);
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('an active sink copy cannot be released by concurrent close or allocated twice', async () => {
  let finish, entered;
  const waiting = new Promise(resolve => {entered = resolve;});
  const f = fixture({capture: () => new Promise(resolve => {finish = resolve; entered();})});
  const flight = projectInferEvidence(f.facts);
  await waiting;
  assert.equal(await f.retained[0].close(), false);
  assert.equal(f.retained[0].cleanupPending(), true);
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.reason, 'EvaluationBudgetExceeded');
  assert.equal(f.trace.filter(value => value === 'reserved').length, 1);
  finish({status: 'complete'});
  await flight;
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('multiple calls match original slots even when successful captures arrive in reverse order', async () => {
  const copied = [];
  const f = fixture({capture: async input => {copied.push(input); return {status: 'complete', references: {}};}});
  const calls = [
    {slotCid: 'slot-first', callWire: '{"model_call_slot_cid":"slot-first","model_task_cid":"task","source_ordinal":3}', outcome: 'ok'},
    {slotCid: 'slot-second', callWire: '{"model_call_slot_cid":"slot-second","model_task_cid":"task","source_ordinal":3}', outcome: 'ok'},
  ];
  const records = ['second', 'first'].map(name => ({model_call_slot_cid: `slot-${name}`,
    semantic_request_cid: `request-${name}`, structured_response: {risk: name},
    evidence: {model_call_slot_cid: `slot-${name}`, model_task_contract_cid: 'task',
      validated_structured_output_cid: `output-${name}`}}));
  f.facts.captureOwner.evaluationBundle = () => ({count: 2, calls, cid: 'bundle',
    wire: JSON.stringify({captures: records})});
  f.facts.continuation.entry = slot => ({slotCid: calls[slot].slotCid, attemptCid: `attempt-${slot}`});
  f.facts.operation.evaluationRequest = slot => ({_0: {slot}, _1: JSON.stringify({sent: slot}), _2: '{}'});
  f.facts.moon.clientProgramModelRequestInputFrame = request => JSON.stringify({key: ['repeated-business-key', request.slot],
    model_call_slot_cid: calls[request.slot].slotCid, inputs: {text: request.slot === 0 ? 'e\u0301\r' : 'é\n'}});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.deepEqual(copied.map(item => [item.original.modelCallSlotCid, item.attemptCid,
    JSON.parse(item.wires.typedOutput).value.risk]), [
    ['slot-first', 'attempt-0', 'first'], ['slot-second', 'attempt-1', 'second'],
  ]);
  assert.deepEqual(f.manifests[0].manifest.items.map(item => item.modelCallSlotCid), ['slot-first', 'slot-second']);
});

test('a no-response call remains incomplete without shifting the next successful call to its slot', async () => {
  const copied = [];
  const f = fixture({capture: async input => {copied.push(input); return {status: 'complete', references: {}};}});
  const calls = [{slotCid: 'failed', callWire: '{"model_call_slot_cid":"failed","model_task_cid":"task"}', outcome: 'provider_failure'},
    {slotCid: 'success', callWire: '{"model_call_slot_cid":"success","model_task_cid":"task"}', outcome: 'ok'}];
  f.facts.captureOwner.evaluationBundle = () => ({count: 2, calls, cid: 'bundle', wire: JSON.stringify({captures: [{
    model_call_slot_cid: 'success', semantic_request_cid: 'request-success', structured_response: {risk: 'high'},
    evidence: {model_call_slot_cid: 'success', model_task_contract_cid: 'task', validated_structured_output_cid: 'output'},
  }]})});
  f.facts.continuation.entry = slot => ({slotCid: calls[slot].slotCid, attemptCid: `attempt-${slot}`});
  f.facts.operation.evaluationRequest = slot => ({_0: {slot}, _1: '{}', _2: '{}'});
  await projectInferEvidence(f.facts);
  const manifest = f.manifests[0].manifest;
  assert.equal(manifest.status, 'incomplete');
  assert.deepEqual(manifest.items.map(item => [item.modelCallSlotCid, item.status]), [
    ['failed', 'incomplete'], ['success', 'complete'],
  ]);
  assert.equal(copied.length, 1);
  assert.equal(copied[0].original.modelCallSlotCid, 'success');
  assert.equal(copied[0].attemptCid, 'attempt-1');
});

test('an entirely response-less inventory retains every required item in its incomplete manifest', async () => {
  const f = fixture({capture: () => assert.fail('missing responses cannot be copied as successes')});
  const calls = ['first', 'second'].map(name => ({slotCid: name,
    callWire: JSON.stringify({model_call_slot_cid: name, model_task_cid: 'task'}), outcome: 'provider_failure'}));
  f.facts.captureOwner.evaluationBundle = () => ({count: 2, calls, cid: 'bundle', wire: '{"captures":[]}'});
  f.facts.continuation.entry = slot => ({slotCid: calls[slot].slotCid, attemptCid: `attempt-${slot}`});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'incomplete');
  assert.equal(f.manifests[0].manifest.modelTaskCid, 'task');
  assert.deepEqual(f.manifests[0].manifest.items.map(item => item.modelCallSlotCid), ['first', 'second']);
});

test('named occurrence capture supports two explicit targets without acquiring another copy flight', async () => {
  const f = fixture();
  const captures = [];
  f.facts.configuration = configureInferEvidence({target: ['first', 'second'], destination: 'local:evaluator',
    maxBytes: 4096, authorize: () => true,
    sink: {capture: async input => {captures.push(input.target); return {status: 'complete'};},
      record: async input => f.manifests.push(input)}});
  f.facts.moon.clientProgramInferOccurrenceTargetName = occurrence => occurrence.name;
  for (const name of ['first', 'second']) {
    await projectInferEvidence({...f.facts, selected: {...f.facts.selected, occurrence: {name}}});
  }
  assert.deepEqual(captures, ['first', 'second']);
  assert.deepEqual(f.manifests.map(item => item.target), ['first', 'second']);
  assert.throws(() => configureInferEvidence({target: ['first', 'first'], destination: 'local:evaluator',
    maxBytes: 4096, authorize: () => true, sink: {capture() {}, record() {}}}),
  {name: 'TypeError', message: 'InvalidInferEvidenceConfiguration'});
});


function typedInputFixture(options = {}) {
  const f = fixture({kind: 'typed-input', ...options});
  const bundle = f.facts.captureOwner.evaluationBundle(), request = {};
  f.facts.captureOwner.evaluationBundle = () => bundle;
  f.facts.operation.evaluationRequest = () => assert.fail('Typed input is no physical request evidence');
  f.facts.operation.evaluationInput = slot => {
    assert.equal(slot, 0); return {request, callWire: bundle.calls[0].callWire};
  };
  f.facts.moon.clientProgramModelRequestInputFrameBounded = (actual, limit) => {
    assert.strictEqual(actual, request); assert(limit > 0);
    f.trace.push('typed serialize'); return '{"actual":"logical input"}';
  };
  f.facts.copyFunding = (actual, kind) => {
    assert.strictEqual(actual, bundle); assert.equal(kind, 'typed-input'); f.trace.push('original funding');
  };
  f.facts.moon.clientProgramReserveInferEvidenceCopy = () => assert.fail('No new destination Ledger');
  f.facts.moon.clientProgramReleaseInferEvidenceCopy = () => assert.fail('No unrelated reservation');
  return {...f, bundle, request};
}

test('typed-input projection funds and binds same logical request without physical evidence', async () => {
  const captured = [], f = typedInputFixture({capture: async input => {captured.push(input);return {status: 'complete'};}});
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['original funding', 'typed serialize', 'copy handed to sink']);
  assert.equal(captured.length, 1);
  assert.equal(captured[0].kind, 'typed-input');
  assert.deepEqual(captured[0].wires, {typedInput: '{"actual":"logical input"}'});
  assert.equal(captured[0].attemptCid, 'attempt');
  assert.equal(captured[0].original.modelCallSlotCid, 'slot');
  assert.equal(captured[0].original.semanticRequestCid, 'request');
  assert.equal(f.manifests[0].manifest.kind, 'typed-input');
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.equal(f.retained[0].cleanupPending(), false);
});

test('typed-input projection refuses missing foreign denied and revoked originals before encoding', async () => {
  for (const mode of ['missing', 'foreign-call', 'denied', 'revoked', 'changed-request', 'partial']) {
    const f = typedInputFixture({capture: () => assert.fail('No foreign or unqualified input')});
    if (mode === 'missing') f.facts.operation.evaluationInput = () => undefined;
    if (mode === 'foreign-call') f.facts.operation.evaluationInput = () => ({request: f.request, callWire: 'foreign'});
    if (mode === 'partial') f.facts.partial = true;
    if (mode === 'denied' || mode === 'revoked' || mode === 'changed-request') {
      let current = true;
      f.facts.current = () => {if (!current) throw new Error('OriginalCurrentLost');};
      f.facts.configuration = configureInferEvidence({kind: 'typed-input', target: 'named',
        destination: 'local:evaluator', maxBytes: 4096,
        authorize: async () => {
          if (mode === 'revoked') current = false;
          if (mode === 'changed-request') f.facts.operation.evaluationInput = () => ({request: {}, callWire: f.bundle.calls[0].callWire});
          return mode !== 'denied';
        }, sink: {capture: () => assert.fail('No capture after original changed'), record: async value => f.manifests.push(value)}});
    }
    await projectInferEvidence(f.facts);
    assert.equal(f.trace.includes('typed serialize'), false, mode);
    assert.equal(f.manifests[0].manifest.kind, 'typed-input');
    assert.equal(f.manifests[0].manifest.status, 'incomplete');
  }
});

test('typed-input projection retains pending Sink copy and skips physical-only snapshot preservation', async () => {
  let resolve, entered;
  const started = new Promise(yes => {entered = yes;});
  const f = typedInputFixture({capture: () => {entered();return new Promise(yes => {resolve = yes;});}});
  const flight = projectInferEvidence(f.facts);
  await started;
  assert.equal(await f.retained[0].close(), false);
  resolve({status: 'complete'}); await flight;
  assert.equal(f.retained[0].cleanupPending(), false);
  let retained = 0;
  f.facts.operation.preparedPhysicalRequest = () => assert.fail('No invented Mock physical snapshot');
  await withPreparedInferEvidence({...f.facts, selected: {occurrence: {}},
    moon: {...f.facts.moon, clientProgramInferOccurrenceTargetName: () => 'named'},
    consume(value) {assert.equal(value, undefined);retained++;}});
  assert.equal(retained, 1);
});

test('default physical projection stays incomplete when physical originals are missing', async () => {
  const f = fixture({capture: () => assert.fail('No physical original, no complete capture')});
  f.facts.operation.evaluationRequest = () => undefined;
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'incomplete');
  assert.equal(f.manifests[0].manifest.items[0].reason, 'RequiredEvidenceUnavailable');
  assert.equal(Object.hasOwn(f.manifests[0].manifest, 'kind'), false);
});

test('typed-input projection requires its existing parent funding and explicit supported kind', async () => {
  const f = typedInputFixture();
  f.facts.copyFunding = undefined;
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.manifests[0].manifest, {kind: 'typed-input', status: 'incomplete', reason: 'RequiredEvidenceUnavailable'});
  assert.deepEqual(f.trace, []);
  assert.throws(() => configureInferEvidence({kind: 'physical-reconstruction', target: 'named',
    destination: 'local:test', maxBytes: 100, authorize: () => true,
    sink: {capture: async () => ({}), record: async () => {}}}), {name: 'TypeError'});
});

test('typed logical getter retains only original prepared call and executed invocation before cleanup', () => {
  const source = readFileSync(new URL('./infer-operation.mjs', import.meta.url), 'utf8');
  let property;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key.name === 'evaluationInput') property = node;
    for (const value of Object.values(node)) {
      for (const child of Array.isArray(value) ? value : [value]) visit(child);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(property);
  const active = {}, prepared = {}, request = {}, call = {};
  for (const mode of ['original', 'reclaimed', 'no-prepared', 'no-invocation', 'no-request', 'no-call']) {
    const seen = [];
    const moon = {
      clientProgramInferInvocationEvidence(owner, slot) {
        assert.strictEqual(owner, active);assert.equal(slot, 1);seen.push('invocation');
        return mode === 'no-invocation' ? undefined : {};
      },
      clientProgramInferPreparedRequest(owner, slot) {
        assert.strictEqual(owner, prepared);assert.equal(slot, 1);seen.push('request');
        return mode === 'no-request' ? undefined : request;
      },
      clientProgramInferPreparedCallAt(owner, slot) {
        assert.strictEqual(owner, prepared);assert.equal(slot, 1);seen.push('call');
        return mode === 'no-call' ? undefined : call;
      },
      strategyRunEvidenceJson(owner) {assert.strictEqual(owner, call);return 'original-call';},
    };
    const get = new Function('moon', 'active', 'reclaimed', 'originalPreparedCallSet',
      `return (${source.slice(property.value.start, property.value.end)});`)(moon, active,
        mode === 'reclaimed', mode === 'no-prepared' ? undefined : prepared);
    const actual = get(1);
    if (mode === 'original') {
      assert.strictEqual(actual.request, request); assert.equal(actual.callWire, 'original-call'); assert(Object.isFrozen(actual));
    } else assert.equal(actual, undefined);
    if (mode === 'reclaimed' || mode === 'no-prepared') assert.deepEqual(seen, []);
    if (mode === 'no-invocation') assert.deepEqual(seen, ['invocation']);
  }
});


test('typed-input Effect manifest preserves the original Effect definition without a pure Program cast', async () => {
  const f = typedInputFixture();
  f.facts.programDefinitionCid = 'original-effect-program';
  f.facts.moon.clientProgramDefinitionCid = () => {throw new TypeError('EffectRunIsNotPreparedClientProgram');};
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.equal(f.manifests[0].manifest.programCid, 'original-effect-program');
  assert.equal(f.manifests[0].manifest.providerBindingCid, 'provider');
});
