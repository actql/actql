import assert from 'node:assert/strict';
import test from 'node:test';
import {configureInferEvidence, projectInferEvidence} from './infer-evaluation-evidence.mjs';

function fixture({authorize = () => true, capture = async () => ({status: 'complete', references: {}}), releaseFails = false, maxBytes = 4096,
  structuredResponse = {risk: 'high'}} = {}) {
  const trace = [], retained = [], manifests = [];
  const record = {model_call_slot_cid: 'slot', semantic_request_cid: 'request', structured_response: structuredResponse,
    evidence: {model_call_slot_cid: 'slot', model_task_contract_cid: 'task', validated_structured_output_cid: 'output'}};
  const config = configureInferEvidence({target: 'named', destination: 'local:evaluator', maxBytes, authorize,
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

test('optional projection reserves before serialization and returns copy capacity after sink settlement', async () => {
  const f = fixture();
  await projectInferEvidence(f.facts);
  assert.deepEqual(f.trace, ['reserved', 'serialize', 'copy handed to sink', 'release']);
  assert.equal(f.manifests[0].manifest.status, 'complete');
  assert.equal(f.retained[0].cleanupPending(), false);
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
