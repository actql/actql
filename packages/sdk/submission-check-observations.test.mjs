import test from 'node:test';
import assert from 'node:assert/strict';
import * as sdk from './index.mjs';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '@actql/client-wire';
import {submissionEpoch, originalSubmission} from './submission-fixture.mjs';

const revision = 'rev:' + '4'.repeat(64);
const text = '/*😀*/\r\nSELECT';
const original = originalSubmission('syntax-original');
const location = {kind: 'text', document_id: 'source', revision,
  start_byte: 16, end_byte: 16, precision: 'exact'};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'submission-checks', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
function observation(verdict = 'invalid') {
  return {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
    outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'completed', report: {
      context_ref: 'ctx:original', scope: {kind: 'bound_input'}, verdict,
      inputs: [{document_id: 'source', kind: 'text', revision, byte_length: verdict === 'verified' ? 13 : 16}],
      reasons: verdict === 'invalid' ? [{code: 'query_syntax_invalid', location: {...location}}] : [],
      requirements: [], coverage: {limits: [], unresolved: []}}};
}
async function fixture(t, {phase = 'not_accepted', change = () => {}, verified = false} = {}) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
    calls.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'close') return;
    assert.equal(operation, 'submit-intent');
    const checked = observation(verified ? 'verified' : 'invalid'); change(checked);
    return {kind: phase, submissionRef: body.submissionRef, intentCid: body.intentCid,
      problem: {code: verified ? 'ClientProgramRejected' : 'ClientProgramInvalidInput',
        classification: verified ? 'operation_failed' : 'invalid_input'}, checkObservation: checked};
  }});
  t.after(() => client.close());
  let error;
  try {await client.startSource(verified ? 'SELECT 1 AS n' : text, {format: 'sql', submissionRef: original});}
  catch (cause) {error = cause;}
  return {error, calls};
}
for (const phase of ['not_accepted', 'preparation_failed']) {
  test(`submission check binds original UTF-8 syntax bytes without changing ${phase}`, async t => {
    const {error, calls} = await fixture(t, {phase});
    assert.equal(sdk.getSubmissionOutcome(error)?.kind, phase, '[check-mutation:submission-check-phase]');
    const checked = sdk.getSubmissionCheckObservation(error);
    assert.deepEqual(checked, observation(), '[check-mutation:submission-check-observation]');
    assert.equal(sdk.getCheckInput(checked, 'source', revision).text, text);
    assert.deepEqual(sdk.resolveCheckTextRange(checked, location).range,
      {start: {line: 1, character: 6}, end: {line: 1, character: 6}},
      '[check-mutation:submission-check-position]');
    assert.equal(sdk.resolveCheckTextRange(checked, location,
      {...sdk.getCheckInput(checked, 'source'), text: 'SELECT 1'}), undefined);
    assert.equal(sdk.getCheckInput(structuredClone(checked), 'source'), undefined);
    assert.equal(sdk.getSubmissionCheckObservation(structuredClone(error)), undefined);
    assert.equal(Object.hasOwn(sdk.getSubmissionOutcome(error), 'checkObservation'), false);
    assert.deepEqual(calls, ['connect', 'submit-intent']);
  });
}
for (const [name, change] of [
  ['wrong original byte length', checked => {checked.report.inputs[0].byte_length = 17;}],
  ['split UTF-8 scalar', checked => {checked.report.reasons[0].location = {...location, start_byte: 3, end_byte: 4};}],
]) {
  test(`submission check refuses ${name} without acquiring report custody`, async t => {
    const {error} = await fixture(t, {change});
    assert.equal(error.code, 'SubmissionUnknown', '[check-mutation:submission-check-binding]');
    assert.equal(sdk.getSubmissionOutcome(error), undefined);
    assert.equal(typeof sdk.getSubmissionCheckObservation, 'function');
    assert.equal(sdk.getSubmissionCheckObservation(error), undefined);
    assert.deepEqual(sdk.getSubmissionInput(error).input, {text, format: 'sql'});
  });
}
test('verified checking does not convert accepted preparation failure into execution success', async t => {
  const {error} = await fixture(t, {phase: 'preparation_failed', verified: true});
  assert.equal(sdk.getSubmissionOutcome(error)?.kind, 'preparation_failed', '[check-mutation:submission-check-phase]');
  assert.equal(sdk.getSubmissionCheckObservation(error).report.verdict, 'verified');
  assert.equal(sdk.explainSubmission(error).observation, 'preparation_failed');
});

test('reused submission replies preserve each owned source observation', async t => {
  const shared = observation();
  let call = 0;
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
    if (operation === 'connect') return profile;
    if (operation === 'close') return;
    assert.equal(operation, 'submit-intent');
    if (++call === 2) {
      shared.report.inputs[0] = {document_id: 'source', kind: 'text',
        revision: 'rev:' + '5'.repeat(64), byte_length: 6};
      shared.report.reasons[0].location = {...location, revision: 'rev:' + '5'.repeat(64),
        start_byte: 6, end_byte: 6};
    }
    return {kind: 'not_accepted', submissionRef: body.submissionRef, intentCid: body.intentCid,
      problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}, checkObservation: shared};
  }});
  t.after(() => client.close());
  const errors = [];
  for (const [source, nonce] of [[text, 'first-source'], ['SELECT', 'second-source']]) {
    try {await client.startSource(source, {format: 'sql', submissionRef: originalSubmission(nonce)});}
    catch (error) {errors.push(error);}
  }
  assert.equal(errors.length, 2);
  const first = sdk.getSubmissionCheckObservation(errors[0]);
  const second = sdk.getSubmissionCheckObservation(errors[1]);
  assert.notEqual(first, second);
  assert.equal(sdk.getCheckInput(first, 'source').text, text,
    '[check-mutation:submission-check-reuse]');
  assert.equal(sdk.getCheckInput(second, 'source').text, 'SELECT');
  assert.deepEqual(sdk.resolveCheckTextRange(first, first.report.reasons[0].location).range,
    {start: {line: 1, character: 6}, end: {line: 1, character: 6}});
  assert.equal(Object.isFrozen(shared), false);
});
