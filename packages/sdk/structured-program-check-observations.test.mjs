// Independent received-response fixtures establish custody, not checker semantics.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as sdk from './index.mjs';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '@actql/client-wire';
import {submissionEpoch, submissionAttempt} from './submission-fixture.mjs';
const revision = digit => 'rev:' + digit.repeat(64);
const program = () => ({version: 'actql/0.1', id: 'original', 'e\u0301/😀~': null});
const pointer = '/e\u0301~1😀~0';
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'structured-checks', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const observation = (input, rev = revision('4')) => ({version: 'actql-check-outcome/0.1',
  reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
  outcome: 'completed', report: {context_ref: 'ctx:structured-original',
    scope: {kind: 'bound_input'}, verdict: 'invalid',
    inputs: [{document_id: 'program', kind: 'structured', revision: rev,
      byte_length: Buffer.byteLength(JSON.stringify(input))}],
    reasons: [{code: 'program_structure_invalid', facts: {issue: 'invalid_structure'},
      location: {kind: 'structured', document_id: 'program', revision: rev, pointer}}],
    requirements: [], coverage: {limits: [], unresolved: []}}});
const rejection = (body, checked, phase = 'not_accepted') => ({kind: phase,
  submissionRef: body.submissionRef, intentCid: body.intentCid,
  problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}, checkObservation: checked});
async function fixture(t, perform) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'close') return;
      assert.equal(operation, 'submit-intent');
      return submissionAttempt(body, await perform(body));
    },
  });
  t.after(() => client.close());
  return {client, calls};
}
for (const phase of ['not_accepted', 'preparation_failed']) {
  test(`structured Program original snapshot and Unicode pointer survive ${phase}`, async t => {
    let entered, release;
    const sent = new Promise(resolve => {entered = resolve;});
    const response = new Promise(resolve => {release = resolve;});
    const {client, calls} = await fixture(t, body => {entered(body); return response;});
    const input = program();
    const pending = client.start(input);
    const body = await sent;
    input['e\u0301/😀~'] = 'edited'; input.id = 'edited';
    release(rejection(body, observation(program()), phase));
    let error; try {await pending;} catch (cause) {error = cause;}
    const checked = sdk.getSubmissionCheckObservation(error);
    assert.equal(sdk.getSubmissionOutcome(error)?.kind, phase, '[check-mutation:program-phase]');
    const owned = sdk.getCheckInput(checked, 'program');
    assert.deepEqual(owned.value, program(), '[check-mutation:program-snapshot]');
    assert.equal(Object.isFrozen(owned.value), true);
    const location = checked.report.reasons[0].location;
    assert.equal(sdk.resolveCheckLocation(checked, location).pointer, pointer, '[check-mutation:program-pointer]');
    assert.equal(sdk.resolveCheckTextRange(checked, location), undefined);
    assert.equal(sdk.resolveCheckLocation(checked, location, {...owned, value: input}), undefined);
    assert.equal(sdk.resolveCheckLocation(checked, {...location, revision: revision('5')}), undefined);
    assert.equal(sdk.getCheckInput(structuredClone(checked), 'program'), undefined, '[check-mutation:program-copy]');
    assert.equal(sdk.getSubmissionCheckObservation({...error}), undefined);
    assert.deepEqual(sdk.getCheckFixes(checked), []);
    assert.equal(sdk.explainCheckReason(checked.report.reasons[0]).kind, 'known');
    assert.deepEqual(calls, ['connect', 'submit-intent'], '[check-mutation:program-passive]');
  });
}
for (const [name, mutate] of [
  ['missing node', checked => {checked.report.reasons[0].location.pointer = '/missing';}],
  ['wrong revision', checked => {checked.report.reasons[0].location.revision = revision('5');}],
  ['text substitution', checked => {checked.report.inputs[0].kind = 'text';}],
  ['wrong original byte length', checked => {checked.report.inputs[0].byte_length++;}],
]) {
  test(`structured Program rejects ${name} before custody`, async t => {
    const {client} = await fixture(t, body => {
      const checked = observation(program()); mutate(checked); return rejection(body, checked);
    });
    let error; try {await client.start(program());} catch (cause) {error = cause;}
    assert.equal(error?.code, 'SubmissionUnknown', '[check-mutation:program-binding]');
    assert.equal(sdk.getSubmissionCheckObservation(error), undefined);
    assert.deepEqual(sdk.getSubmissionInput(error).input, program());
  });
}
test('structured Program reused replies cannot change older input or pointer custody', async t => {
  const shared = observation(program()); let index = 0;
  const {client} = await fixture(t, body => {
    if (index++) Object.assign(shared, observation(body.input, revision('5')));
    return rejection(body, shared);
  });
  const errors = [];
  for (const id of ['original', 'another']) {
    try {await client.start({...program(), id});} catch (error) {errors.push(error);}
  }
  const first = sdk.getSubmissionCheckObservation(errors[0]);
  const second = sdk.getSubmissionCheckObservation(errors[1]);
  assert.notEqual(first, second);
  const owned = sdk.getCheckInput(first, 'program');
  assert.deepEqual(owned.value, program(), '[check-mutation:program-reuse]');
  assert.equal(owned.revision, revision('4'));
  assert.equal(sdk.resolveCheckLocation(first, first.report.reasons[0].location,
    sdk.getCheckInput(second, 'program')), undefined);
  assert.equal(Object.isFrozen(shared), false);
});
test('structured Program old submission reply cannot bind a different intent', async t => {
  let old;
  const {client} = await fixture(t, body => old ??= rejection(body, observation(program())));
  const errors = [];
  for (const id of ['original', 'changed']) {
    try {await client.start({...program(), id});} catch (error) {errors.push(error);}
  }
  assert.equal(errors[0].code, 'SubmissionNotAccepted');
  assert.equal(errors[1].code, 'SubmissionUnknown', '[check-mutation:program-stale]');
  assert.equal(sdk.getSubmissionCheckObservation(errors[1]), undefined);
});
