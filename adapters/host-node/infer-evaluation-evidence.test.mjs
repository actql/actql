import assert from 'node:assert/strict';
import test from 'node:test';
import {configureInferEvidence, projectInferEvidence} from './infer-evaluation-evidence.mjs';

function fixture({authorize = () => true, capture = async () => ({status: 'complete', references: {}}), releaseFails = false, maxBytes = 4096} = {}) {
  const trace = [], retained = [], manifests = [];
  const record = {model_call_slot_cid: 'slot', semantic_request_cid: 'request', structured_response: {risk: 'high'},
    evidence: {model_call_slot_cid: 'slot', model_task_contract_cid: 'task', validated_structured_output_cid: 'output'}};
  const config = configureInferEvidence({target: 'named', destination: 'local:evaluator', maxBytes, authorize,
    sink: {capture: async input => {trace.push('copy handed to sink'); return capture(input);}, record: async input => manifests.push(input)}});
  const moon = {clientProgramInferTargetName: () => 'named',
    clientProgramReserveInferEvidenceCopy: () => {trace.push('reserved'); return {$tag: 1, _0: {_0: 'ledger', _1: 'reservation'}};},
    clientProgramReleaseInferEvidenceCopy: () => {trace.push('release'); return {$tag: releaseFails ? 0 : 1};},
    clientProgramModelRequestInputFrame: () => {trace.push('serialize'); return '{}';}, clientProgramDefinitionCid: () => 'program'};
  const facts = {configuration: config, moon, control: {compiledInferSourceFreeResultPolicy: () => ({kind: 'data_policy', cid: 'policy', wire: '{}'})},
    plan: {runDefinition: {identity: 'run'}, compiled: {}}, selected: {step: 0, providerBinding: {identity: 'provider'}},
    captureOwner: {evaluationBundle: () => ({count: 1, cid: 'bundle', wire: JSON.stringify({captures: [record]})})},
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

test('optional sink failure reports missing Evidence and releases its bounded copy', async () => {
  const f = fixture({capture: async () => {throw Object.assign(new Error('failure'), {code: 'SinkUnavailable'});}});
  await projectInferEvidence(f.facts);
  assert.equal(f.manifests[0].manifest.status, 'incomplete');
  assert.equal(f.manifests[0].manifest.reason, 'SinkUnavailable');
  assert.equal(f.retained[0].cleanupPending(), false);
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
