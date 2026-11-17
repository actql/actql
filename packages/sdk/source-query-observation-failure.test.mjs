import {submissionEpoch, readySubmissionAttempt} from './submission-fixture.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {validRunState} from '@actql/client-wire';
import * as sdk from './index.mjs';
import {connectInProcess} from './host-port.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'original-query', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'original-principal', capabilities: [], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const running = {version: 'actql-run-state/0.1', run_id: 'original-run', status: 'running',
  updated_at: '2026-10-07T00:00:00.000Z', next_action: {kind: 'none'},
  result_available: false, result_availability: {answer: {state: 'unavailable',
    reason: 'not_published', observed_at: '2026-10-07T00:00:00.000Z'}}};
const hint = 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.';
const expected = (kind, problem, target = ref) => ({kind, problem, operation: 'wait',
  next: {operation: 'status', ref: target}, hint,
  summary: {observation_unavailable: 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.',
    unknown_state: 'The Run reply contains a state this SDK cannot interpret.',
    contract_mismatch: 'The Run reply does not match this SDK’s registered state contract.',
    malformed_response: 'The Run reply violates the registered state contract.'}[problem]});
async function fixture(t, reply, target = ref) {
  const operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      operations.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'submit-intent') return readySubmissionAttempt(body, {ref: target, durability: 'durable', revision: 1});
      if (operation === 'close') return;
      assert.deepEqual(body.ref, target);
      return reply(operation);
    },
  });
  t.after(() => client.close());
  return {client, operations};
}
const faults = [
  ['unavailable', 'observation_unavailable', () => {throw new sdk.ClientError('ClientConnectionDenied', {cause: new Error('private-credential-value')});}],
  ['uninterpretable', 'unknown_state', () => ({...running, status: 'private-future-state'})],
  ['protocol_failure', 'contract_mismatch', () => ({...running, version: 'private-contract/0.1'})],
  ['protocol_failure', 'malformed_response', () => ({...running, result_available: 'true', private_value: 'private-value'})],
];
for (const language of ['sql', 'aql']) {
  for (const [kind, problem, reply] of faults) {
    test(`${language}: short query retains ${problem} Run observation without retry`, async t => {
      const f = await fixture(t, reply);
      const parameters = {x: 1};
      const declarations = {x: {type: 'number'}};
      const query = f.client[language]('SELECT @x AS id', parameters,
        {submissionRef: f.client.newSubmission({nonce: 'original-query'}), parameterDeclarations: declarations});
      parameters.x = 99; declarations.x.type = 'string';
      let error;
      try {await query;} catch (value) {error = value;}
      assert.equal(error instanceof sdk.ClientError, true);
      assert.equal(error.code, 'QueryObservationUnknown');
      assert.deepEqual(sdk.explainRunObservationFailure(error), expected(kind, problem),
        '[check-mutation:query-run-failure]');
      assert.deepEqual(sdk.explainRunObservationFailure(error.cause), expected(kind, problem));
      assert.deepEqual(sdk.getSubmissionInput(error)?.input, {text: 'SELECT @x AS id',
        format: language === 'sql' ? 'sql' : 'aql-text',
        parameterDeclarations: {x: {type: 'number'}}}, '[check-mutation:query-failure-input]');
      assert.deepEqual(sdk.getSubmissionInput(error).parameters, {x: 1});
      assert.equal(sdk.getSubmissionInput(error).requestId, query.requestId);
      assert.equal(sdk.getSubmissionInput({...error}), undefined);
      assert.equal(sdk.explainRunObservationFailure({...error}), undefined,
        '[check-mutation:query-failure-custody]');
      assert.equal(sdk.explainRunObservationFailure(structuredClone(error)), undefined);
      assert.equal(sdk.formatRunObservationFailure({...error}), undefined);
      assert.deepEqual(JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json'})).explanation,
        expected(kind, problem));
      for (const format of ['text', 'html']) assert.ok(sdk.formatRunObservationFailure(error, {format}).includes(`observation/${kind}:`));
      assert.doesNotMatch(inspect({error, explanation: sdk.explainRunObservationFailure(error)},
        {showHidden: true, depth: 8}), /private-credential-value|private-future-state|private-contract|private_value/);
      error.code = 'Succeeded'; error.kind = 'success'; error.next = {operation: 'submit'};
      assert.deepEqual(sdk.explainRunObservationFailure(error), expected(kind, problem));
      const translated = sdk.explainRunObservationFailure(error, {locale: 'ja'});
      assert.deepEqual({kind: translated.kind, problem: translated.problem, operation: translated.operation, next: translated.next},
        {kind, problem, operation: 'wait', next: {operation: 'status', ref}});
      await assert.rejects(query, value => value === error);
      await assert.rejects(query.all(), value => value === error);
      assert.deepEqual(f.operations, ['connect', 'submit-intent', 'wait'], '[check-mutation:query-failure-passive]');
    });
  }
}

test('short query valid failed state retains input without claiming failed observation', async t => {
  // This authored Host reply represents its original revision1 observation;
  // the SDK must neither infer a missing revision nor accept a malformed reply.
  const failed = {...running, status: 'failed', revision: 1};
  assert.equal(validRunState(failed), true);
  const {revision, ...missingRevision} = failed;
  assert.equal(validRunState(missingRevision), false);
  const f = await fixture(t, () => failed);
  let error;
  try {await f.client.sql('SELECT 1 AS id', undefined, {submissionRef: f.client.newSubmission({nonce: 'failed-query'})});}
  catch (value) {error = value;}
  assert.equal(error.code, 'ExecutionUnsuccessful');
  assert.deepEqual(error.observation, failed);
  assert.equal(sdk.explainRunObservationFailure(error), undefined);
  assert.equal(sdk.formatRunObservationFailure(error), undefined);
  assert.deepEqual(sdk.getSubmissionInput(error)?.input, {text: 'SELECT 1 AS id', format: 'sql'},
    '[check-mutation:query-failure-input]');
  assert.deepEqual(f.operations, ['connect', 'submit-intent', 'wait']);
});

test('short queries sharing a borrowed exception retain distinct original inputs and Run targets', async t => {
  const borrowed = new sdk.ClientError('ClientConnectionDenied');
  const retained = [];
  for (const [index, language] of ['sql', 'aql'].entries()) {
    const target = {...ref, namespaceId: `original-query-${index}`};
    const f = await fixture(t, () => {throw borrowed;}, target);
    const text = `SELECT ${index + 1} AS id`;
    let error;
    try {await f.client[language](text, undefined, {submissionRef: f.client.newSubmission({nonce: target.namespaceId})});}
    catch (value) {error = value;}
    retained.push({error, target, text, language});
    assert.deepEqual(f.operations, ['connect', 'submit-intent', 'wait']);
  }
  assert.notEqual(retained[0].error, retained[1].error);
  assert.notEqual(retained[0].error.cause, retained[1].error.cause);
  assert.equal(sdk.explainRunObservationFailure(borrowed), undefined);
  for (const {error, target, text, language} of retained) {
    assert.deepEqual(sdk.explainRunObservationFailure(error), expected('unavailable', 'observation_unavailable', target),
      '[check-mutation:query-run-failure]');
    assert.deepEqual(sdk.getSubmissionInput(error)?.input, {text, format: language === 'sql' ? 'sql' : 'aql-text'},
      '[check-mutation:query-failure-input]');
  }
});

test('short query exposes original public memory and runtime-work diagnostics through execution and observation', async t => {
  for (const [dimension, setting, demand, unit, explanation] of [
    ['retained_bytes', 'installation.requestMemory.retainedBytes', '19', 'logical_bytes', 'Logical quota, not process RSS.'],
    ['execution_bytes', 'installation.requestMemory.executionBytes', '19', 'logical_bytes', 'Logical quota, not process RSS.'],
    ['value_capture_work', 'installation.sourceFreeMaxWork', '>=8', 'work_units', 'Runtime work, not Program parsing/checking. A lower bound does not give the complete UTF8 demand.'],
  ]) {
    const message = `Budget exceeded: phase=local_managed_advance; dimension=${dimension}; requested_delta=${demand}; remaining=7; policy=100; unit=${unit}; setting=${setting}. ${explanation}`;
    const failed = {...running, status: 'failed', revision: 1,
      terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message}};
    assert.equal(validRunState(failed), true);
    const f = await fixture(t, () => failed);
    let error;
    try {await f.client.sql('SELECT 1 AS id', undefined,
      {submissionRef: f.client.newSubmission({nonce: `budget-${dimension}`})});}
    catch (original) {error = original;}
    assert.equal(error.code, 'ExecutionUnsuccessful');
    assert.equal(error.observation.terminal_error.message, message);
    assert.equal(error.execution.ref.runDefinitionCid, ref.runDefinitionCid);
    assert.equal((await error.execution.status()).terminal_error.message, message);
    assert.deepEqual(f.operations, ['connect', 'submit-intent', 'wait', 'status']);
    assert.equal(sdk.explainRunObservationFailure(error), undefined,
      'A known failed execution is not an unknown observation or retry permission');
    assert.equal(JSON.stringify(error).includes(message), false, 'Explicit original inspection stays nonenumerable');
  }
});
