import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {applyModelSlotObservationSchema, checkModelSlotObservationSchema,
  modelSlotCaptureReferences} from './model-slot-observation-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const pin = digit => `sha256:${digit.repeat(64)}`;
const call = key => ({version: 'actql-model-call-slot/0.1',
  program_definition_cid: pin('1'), unit_definition_cid: pin('2'),
  source_ordinal: 2, effective_inputs_cid: pin('3'),
  input_artifact_cid: pin('4'), input_key_cid: pin(key),
  model_task_cid: pin('5'), fixed_request_cid: pin('6')});
const first = call('7');
const second = call('8');
const capture = (input, outcome) => ({
  version: 'actql-model-slot-capture/0.1', slot_cid: machineCid(input),
  model_task_cid: input.model_task_cid,
  fixed_request_cid: input.fixed_request_cid,
  input_artifact_cid: input.input_artifact_cid,
  input_key_cid: input.input_key_cid,
  ordered_attempt_cids: [pin('9')], adopted_attempt_cid: pin('9'),
  outcome, typed_value_artifact_cid: outcome === 'ok' ? pin('a') : null,
  accounting_evidence_cid: pin('b'), authority_evidence_cid: pin('c'),
  policy_cid: pin('d'), outcome_evidence_cid: pin('e'),
  response_artifact_cid: outcome === 'ok' ? pin('f') : null,
  response_issuer_evidence_cid: outcome === 'ok' ? pin('e') : null,
  attachment_admission_cids: [],
});
// Symbolic evidence roots isolate wire/identity matching. These fixtures do
// not pretend to prove cost, egress authority or production capture custody.
const ok = capture(first, 'ok');
const timeout = capture(second, 'failed:timeout');
const base = {version: 'actql-observation-set/0.1',
  invocation_template_cid: pin('1'), source_evidence_cids: [],
  captured_input_artifact_cids: [], consistency: 'no_external_sources',
  capture_started_at: null, capture_completed_at: null,
  replayability: {materialized: false, availability_evidence_cids: []},
  data_policy_cid: pin('2')};
const expected = [machineCid(ok), machineCid(timeout)];
const modelTemplate = program => ({version: 'actql-bound-invocation-template/0.1',
  program_definition_cid: pin(program), parameter_values_cid: pin('2'),
  invocation_bindings_cid: pin('3'), check_environment_cid: pin('4'),
  grammar_manifest_cid: pin('5'), required_profile_contracts: [{
    profile_id: 'actql-infer/0.1',
    contract_cid: 'sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd',
  }], barrier_contract_manifest_cid: pin('6'), source_evidence: 'unbound'});
const bodies = [
  ['success adopted slot', 'model_slot_capture', ok],
  ['response-less failed slot', 'model_slot_capture', timeout],
  ['non-INFER observation unchanged', 'observation_set', base],
  ['zero-key INFER observation', 'observation_set', {...base,
    model_slot_capture_cids: []}],
  ['success and failure observation', 'observation_set', {...base,
    model_slot_capture_cids: expected}],
];
const corpus = {version: 'actql-model-slot-observation-vectors/0.1',
  cases: bodies.map(([id, kind, body]) => ({id, kind, body,
    expected_canonical_bytes: canonicalText(body), expected_cid: machineCid(body)}))};
const corpusPath = 'portability/corpus/model-slot-observation.json';
const moonPath = 'src/run_publication/model_slot_observation.generated_test.mbt';
const seal = (kind, body) => `seal_run_evidence_value(${JSON.stringify(kind)}, ` +
  `${JSON.stringify(canonicalText(body))}, 16384, 1024, 20).unwrap()`;
let moonSource = '// Generated independent slot/ObservationSet vectors.\n';
for (const fixture of corpus.cases) {
  moonSource += `\n///|\ntest ${JSON.stringify('model slot observation: ' + fixture.id)} {\n` +
    `  let value = ${seal(fixture.kind, fixture.body)}\n` +
    `  assert_eq(run_evidence_value_identity(value), ${JSON.stringify(fixture.expected_cid)})\n` +
    `  let restored = admit_run_evidence_value(${JSON.stringify(fixture.kind)},\n` +
    `    run_evidence_value_json(value), 16384, 1024, 20).unwrap()\n` +
    `  assert_eq(run_evidence_value_identity(restored), run_evidence_value_identity(value))\n}\n`;
}
moonSource += `\n///|\ntest "slot observation exact ordered success and failure bindings" {\n` +
  `  let first = ${seal('model_call_slot', first)}\n` +
  `  let second = ${seal('model_call_slot', second)}\n` +
  `  let success = ${seal('model_slot_capture', ok)}\n` +
  `  let timeout = ${seal('model_slot_capture', timeout)}\n` +
  `  let a = bind_model_slot_capture(first, success).unwrap()\n` +
  `  let b = bind_model_slot_capture(second, timeout).unwrap()\n` +
  `  assert_true(bind_model_slot_capture(first, timeout) is Err(_))\n` +
  `  assert_true(bind_model_slot_capture(second, success) is Err(_))\n`;
for (const [references, accepted] of [[expected, true], [[], false],
  [[expected[0]], false], [[...expected, pin('a')], false],
  [expected.toReversed(), false]]) {
  moonSource += `  assert_${accepted ? 'true' : 'false'}(verify_model_observation_slots(\n` +
    `    ${seal('observation_set', {...base, model_slot_capture_cids: references})}, [a, b]) is Ok(_))\n`;
}
moonSource += `  let observation = ${seal('observation_set', {...base, model_slot_capture_cids: expected})}\n` +
  `  assert_true(verify_model_observation_slots(observation, [b, a]) is Err(_))\n` +
  `  assert_true(verify_model_observation_slots(observation, [a, a]) is Err(_))\n` +
  `  assert_true(verify_model_observation_slots(${seal('observation_set', base)}, []) is Err(_))\n` +
  `  assert_true(verify_model_observation_slots(${seal('observation_set', {...base, model_slot_capture_cids: []})}, []) is Ok(_))\n` +
  `  let template = ${seal('bound_invocation_template', modelTemplate('1'))}\n` +
  `  assert_true(issue_run_invocation(template, observation, 16384, 1024, 20) is Err(_))\n` +
  `  let wire = ${JSON.stringify(canonicalText({...base, model_slot_capture_cids: expected}))}\n` +
  `    .replace(old=${JSON.stringify(pin('1'))}, new=run_evidence_value_identity(template))\n` +
  `  let matched = seal_run_evidence_value("observation_set", wire, 16384, 1024, 20).unwrap()\n` +
  `  assert_true(issue_model_run_invocation(template, matched, [a, b], 16384, 1024, 20) is Ok(_))\n` +
  `  assert_true(issue_model_run_invocation(template, matched, [b, a], 16384, 1024, 20) is Err(_))\n` +
  `  assert_true(issue_model_run_invocation(template, matched, [a], 16384, 1024, 20) is Err(_))\n` +
  `  let foreign = ${seal('bound_invocation_template', modelTemplate('0'))}\n` +
  `  assert_true(issue_model_run_invocation(foreign, matched, [a, b], 16384, 1024, 20) is\n` +
  `    Err(RunEvidenceReferenceMismatch("observation.invocation_template_cid")))\n` +
  `  let wire = wire.replace(old=run_evidence_value_identity(template),\n` +
  `    new=run_evidence_value_identity(foreign))\n` +
  `  let other_program = seal_run_evidence_value("observation_set", wire, 16384, 1024, 20).unwrap()\n` +
  `  assert_true(issue_model_run_invocation(foreign, other_program, [a, b], 16384, 1024, 20) is\n` +
  `    Err(RunEvidenceReferenceMismatch("model_slot_capture.program_definition_cid")))\n` +
  `  let wire = ${JSON.stringify(canonicalText({...base, model_slot_capture_cids: []}))}\n` +
  `    .replace(old=${JSON.stringify(pin('1'))}, new=run_evidence_value_identity(template))\n` +
  `  let zero = seal_run_evidence_value("observation_set", wire, 16384, 1024, 20).unwrap()\n` +
  `  assert_true(issue_model_run_invocation(template, zero, [], 16384, 1024, 20) is Ok(_))\n` +
  `  assert_true(issue_run_invocation(template, evidence_test_observation(template),\n` +
  `    16384, 1024, 20) is Err(RunEvidenceReferenceMismatch("model_slot_capture_cids")))\n` +
  `  let source_only = evidence_test_template(${JSON.stringify(pin('1'))})\n` +
  `  assert_true(issue_model_run_invocation(source_only, evidence_test_observation(source_only),\n` +
  `    [], 16384, 1024, 20) is Err(RunEvidenceReferenceMismatch("model_slot_capture_cids")))\n` +
  `}\n`;
const malformed = [
  ...['slot_cid', 'model_task_cid', 'fixed_request_cid', 'input_artifact_cid',
    'input_key_cid'].map(field => ({...ok, [field]: pin('0')})),
  {...ok, ordered_attempt_cids: []},
  {...ok, ordered_attempt_cids: [pin('9'), pin('9')]},
  {...ok, adopted_attempt_cid: pin('0')},
  {...ok, adopted_attempt_cid: null},
  {...ok, typed_value_artifact_cid: null},
  {...ok, response_artifact_cid: null},
  {...timeout, typed_value_artifact_cid: pin('a')},
  {...timeout, response_artifact_cid: pin('a')},
];
moonSource += `\n///|\ntest "slot capture cannot repair foreign inputs or fabricated outcomes" {\n` +
  `  let call = ${seal('model_call_slot', first)}\n`;
for (const body of malformed) {
  moonSource += `  assert_true(bind_model_slot_capture(call, ${seal('model_slot_capture', body)}) is Err(_))\n`;
}
moonSource += `}\n`;
moonSource += `\n///|\ntest "observation slot references reject duplicate identities before binding" {\n` +
  `  assert_true(seal_run_evidence_value("observation_set",\n` +
  `    ${JSON.stringify(canonicalText({...base, model_slot_capture_cids: [expected[0], expected[0]]}))},\n` +
  `    16384, 1024, 20) is Err(RunEvidenceInvalidShape))\n}\n`;
const savedEvidence = {
  version: 'actql-model-invocation-evidence/0.1',
  model_task_contract_cid: ok.model_task_cid,
  semantic_request_cid: ok.fixed_request_cid,
  model_call_slot_cid: ok.slot_cid,
  input_result_artifact_cid: ok.input_artifact_cid,
  input_row_identity_cid: ok.input_key_cid,
  input_row_identity: 'fixture-key', authored_model_selector: 'fixture-model',
  provider_reported_model_id: 'fixture-model', provider_request_id: 'fixture-1',
  attempt: 1, structured_response_artifact_cid: ok.response_artifact_cid,
  validated_structured_output_cid: ok.typed_value_artifact_cid,
  input_tokens: 1, output_tokens: 2, finish_reason: 'stop',
  observed_at: '2026-10-02T00:00:00.000Z',
};
const savedRecord = evidence => ({model_call_slot_cid: evidence.model_call_slot_cid,
  semantic_request_cid: evidence.semantic_request_cid, structured_response: {},
  evidence: {...evidence, model_invocation_evidence_cid: machineCid(evidence)}});
const bundle = records => ({version: 'actql-model-capture-bundle/0.1',
  captures: records, barrier_receipts: []});
moonSource += `\n///|\ntest "adopted slots match only exact successful saved bundle records" {\n` +
  `  let a = bind_model_slot_capture(${seal('model_call_slot', first)},\n` +
  `    ${seal('model_slot_capture', ok)}).unwrap()\n` +
  `  let b = bind_model_slot_capture(${seal('model_call_slot', second)},\n` +
  `    ${seal('model_slot_capture', timeout)}).unwrap()\n`;
const savedCases = [
  [[savedRecord(savedEvidence)], '[a, b]', true],
  [[], '[a, b]', false],
  [[savedRecord(savedEvidence), savedRecord(savedEvidence)], '[a, b]', false],
  [[savedRecord(savedEvidence)], '[a, a]', false],
  [[], '[b]', true],
  [[savedRecord(savedEvidence)], '[b]', false],
  ...['model_call_slot_cid', 'model_task_contract_cid', 'semantic_request_cid',
    'input_result_artifact_cid', 'input_row_identity_cid',
    'structured_response_artifact_cid', 'validated_structured_output_cid']
    .map(field => [[savedRecord({...savedEvidence, [field]: pin('0')})], '[a, b]', false]),
];
for (const [records, slots, accepted] of savedCases) {
  moonSource += `  let saved = ${seal('model_capture_bundle', bundle(records))}\n` +
    `  let read = read_model_capture_bundle(run_evidence_value_json(saved),\n` +
    `    run_evidence_value_identity(saved), 16384, 1024, 20).unwrap()\n` +
    `  assert_${accepted ? 'true' : 'false'}(verify_model_slot_capture_bundle(${slots}, read) is Ok(_))\n` +
    `  assert_true(release_model_capture_bundle_read(read))\n` +
    `  assert_true(verify_model_slot_capture_bundle(${slots}, read) is Err(_))\n`;
}
moonSource += `}\n`;
const moon = execFileSync(process.env.MOON_HOME
  ? join(process.env.MOON_HOME, 'bin/moonfmt') : 'moonfmt', ['-'],
{input: moonSource, encoding: 'utf8'});
if (process.argv.includes('--write')) {
  writeFileSync(corpusPath, JSON.stringify(corpus, null, 2) + '\n');
  writeFileSync(moonPath, moon);
}
assert.deepEqual(read(corpusPath), corpus);
assert.equal(readFileSync(moonPath, 'utf8'), moon);

test('dedicated slot field is optional, unique and retained in embedded schemas', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  checkModelSlotObservationSchema(registry);
  const observation = registry.artifact_schemas.observation_set;
  assert.equal(observation.required.includes('model_slot_capture_cids'), false);
  assert.deepEqual(observation.properties.model_slot_capture_cids,
    modelSlotCaptureReferences);
  for (const [name, schema] of Object.entries(registry.artifact_schemas)) {
    if (['run_receipt', 'captured_run'].includes(name)) {
      let count = 0;
      function visit(value) {
        if (value === null || typeof value !== 'object') return;
        if (value.properties?.version?.const === 'actql-observation-set/0.1') {
          count++;
          assert.deepEqual(value.properties.model_slot_capture_cids,
            modelSlotCaptureReferences);
        }
        for (const child of Object.values(value)) visit(child);
      }
      visit(schema);
      assert.ok(count > 0, name);
    }
  }
  assert.deepEqual(applyModelSlotObservationSchema(registry), registry);
});

test('only the optional slot field changes existing embedded schema identities', () => {
  const registry = read('spec/contracts/actql-protocol-schemas.json');
  const previousPins = {
    run_receipt: 'sha256:d017cd0e95bce341edd4fabf859fc521588ee8d12eadfa9fd2704d8d8a94f526',
    captured_run: 'sha256:7b3d173c3a078431c99352e3bac4e5a2341ea2217c1995ab8c97dd9c56027ac1',
  };
  for (const [name, pin] of Object.entries(previousPins)) {
    const previous = structuredClone(registry.artifact_schemas[name]);
    function removeOptionalSlotField(value) {
      if (value === null || typeof value !== 'object') return;
      if (value.properties?.version?.const === 'actql-observation-set/0.1') {
        delete value.properties.model_slot_capture_cids;
      }
      for (const child of Object.values(value)) removeOptionalSlotField(child);
    }
    removeOptionalSlotField(previous);
    assert.equal(machineCid(previous), pin, name);
  }
});

test('independent slot outcomes differ from saved successful-response bundles', () => {
  for (const fixture of read(corpusPath).cases) {
    verifyIdentity(fixture.body, fixture.expected_cid,
      fixture.expected_canonical_bytes);
  }
  assert.notEqual(machineCid(base), machineCid({...base, model_slot_capture_cids: []}));
  assert.notEqual(machineCid({...base, model_slot_capture_cids: expected}),
    machineCid({...base, model_slot_capture_cids: expected.toReversed()}));
  assert.notEqual(machineCid(timeout), machineCid({...timeout, outcome: 'ok'}));
  const slotSchema = read('spec/contracts/actql-stage-contracts.json')
    .schemas.model_slot_capture;
  for (const value of [ok, timeout]) {
    assert.deepEqual([...Object.keys(value), 'self_cid'].sort(),
      slotSchema.required.toSorted());
  }
  assert.equal(Object.hasOwn(base, 'model_slot_capture_cids'), false);
});
