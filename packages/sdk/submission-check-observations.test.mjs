import test from 'node:test';
import assert from 'node:assert/strict';
import * as sdk from './index.mjs';
import {checkReasonSchemaCid, checkOutcomeSchemaCid, validCheckOutcome} from '@actql/client-wire';
import {submissionEpoch, originalSubmission, submissionAttempt} from './submission-fixture.mjs';

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
      runnable: verdict === 'verified' ? {verdict: 'yes', reasons: []} :
        {verdict: 'no', reasons: [{code: 'query_syntax_invalid'}]},
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
    return submissionAttempt(body, {kind: phase, submissionRef: body.submissionRef, intentCid: body.intentCid,
      problem: {code: verified ? 'ClientProgramRejected' : 'ClientProgramInvalidInput',
        classification: verified ? 'operation_failed' : 'invalid_input'}, checkObservation: checked});
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
    return submissionAttempt(body, {kind: 'not_accepted', submissionRef: body.submissionRef, intentCid: body.intentCid,
      problem: {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}, checkObservation: shared});
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

for (const phase of ['not_accepted', 'preparation_failed']) {
  test(`missing submission requirements bind pre-await declarations without changing ${phase}`, async t => {
    const source = 'SELECT @x AS n';
    const declarations = {x: {type: 'number'}};
    const declarationRevision = 'rev:' + '6'.repeat(64);
    const requirement = {code: 'parameter_value_required', facts: {
      parameter: 'x', expected_type: 'number', admission: {
        kind: 'parameter_declaration',
        contract_schema_cid: 'sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1',
        contract: {nullable: false, type: 'number'},
        constraints: [{kind: 'numeric', path: [], integer: false}], supplier: 'caller'}},
      location: {kind: 'structured', document_id: 'parameter_declarations',
        revision: declarationRevision, pointer: '/x'}};
    const report = {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
      outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'completed', report: {
        context_ref: 'ctx:missing-original', scope: {kind: 'bound_input'}, verdict: 'undetermined',
        runnable: {verdict: 'no', reasons: [{code: 'bound_values_missing'}, {code: 'parameter_value_required'}]},
        // Independently counted ASCII JSON and source byte lengths.
        inputs: [{document_id: 'source', kind: 'text', revision, byte_length: 14},
          {document_id: 'parameter_declarations', kind: 'structured',
            revision: declarationRevision, byte_length: 23}],
        reasons: [], requirements: [requirement],
        coverage: {limits: [{code: 'bound_values_missing'}], unresolved: []}}};
    let entered, release;
    const dispatched = new Promise(resolve => {entered = resolve;});
    const response = new Promise(resolve => {release = resolve;});
    const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
      if (operation === 'connect') return profile;
      if (operation === 'close') return;
      assert.equal(operation, 'submit-intent');
      entered(body);
      return response.then(outcome => submissionAttempt(body, outcome));
    }});
    t.after(() => client.close());
    const pending = client.startSource(source, {format: 'sql', parameterDeclarations: declarations,
      submissionRef: originalSubmission(`missing-${phase}`)});
    const request = await dispatched;
    declarations.x.type = 'string';
    release({kind: phase, submissionRef: request.submissionRef, intentCid: request.intentCid,
      problem: {code: 'ClientProgramNeedsInputs', classification: 'requirements'}, checkObservation: report});
    let error;
    try {await pending;} catch (cause) {error = cause;}
    assert.equal(sdk.getSubmissionOutcome(error)?.kind, phase, '[check-mutation:submission-missing-phase]');
    const checked = sdk.getSubmissionCheckObservation(error);
    assert.equal(checked?.report.verdict, 'undetermined', '[check-mutation:submission-missing-verdict]');
    assert.deepEqual(checked.report.requirements, [requirement], '[check-mutation:submission-missing-requirement]');
    const owned = sdk.getCheckInput(checked, 'parameter_declarations');
    assert.deepEqual(owned.value, {x: {type: 'number'}}, '[check-mutation:submission-missing-custody]');
    const resolved = sdk.resolveCheckLocation(checked, requirement.location);
    assert.equal(resolved.input, owned);
    assert.equal(resolved.pointer, '/x');
    assert.equal(resolved.input.value.x.type, 'number');
    assert.equal(sdk.resolveCheckLocation(checked, {...requirement.location, revision}), undefined);
    assert.equal(sdk.getCheckInput(structuredClone(checked), 'parameter_declarations'), undefined);
    assert.deepEqual(sdk.getCheckParameterAdmission(checked, 'x'), requirement.facts.admission);
    assert.equal(sdk.getCheckRequirementFrontier(checked).requirements.length, 1);
    assert.equal(sdk.equalCheckRequirementFrontiers(checked, structuredClone(checked)), undefined);
    assert.equal(declarations.x.type, 'string');
  });
}

for (const phase of ['not_accepted', 'preparation_failed']) {
  test(`submission requirements reject the old admission pin without acquiring ${phase} facts`, async t => {
    let currentPinVerified = false;
    const {error, calls} = await fixture(t, {phase, change(checked) {
      checked.report.verdict = 'undetermined';
      checked.report.runnable = {verdict: 'no',
        reasons: [{code: 'bound_values_missing'}, {code: 'parameter_value_required'}]};
      checked.report.reasons = [];
      checked.report.coverage.limits = [{code: 'bound_values_missing'}];
      checked.report.requirements = [{code: 'parameter_value_required', facts: {
        parameter: 'x', expected_type: 'number', admission: {
          kind: 'parameter_declaration',
          contract_schema_cid: 'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551',
          contract: {nullable: false, type: 'number'},
          constraints: [{kind: 'numeric', path: [], integer: false}], supplier: 'caller'}}}];
      assert.equal(validCheckOutcome(checked), false);
      const current = structuredClone(checked);
      current.report.requirements[0].facts.admission.contract_schema_cid =
        'sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1';
      assert.equal(validCheckOutcome(current), true, 'Only the reviewed admission pin differs');
      currentPinVerified = true;
    }});
    assert.equal(currentPinVerified, true, 'The current-pin positive control must complete outside transport error handling');
    assert.equal(error.code, 'SubmissionUnknown');
    assert.equal(sdk.getSubmissionOutcome(error), undefined);
    assert.equal(sdk.getSubmissionCheckObservation(error), undefined);
    assert.equal(sdk.getSubmissionInput(error).input.text, text);
    assert.deepEqual(calls, ['connect', 'submit-intent']);
  });
}
