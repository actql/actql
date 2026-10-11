import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {historicalModelObservation, nullableModelObservation,
  reportedModelObservation, observationRefusals} from './fixtures/model-observation.mjs';

const hash = body => 'sha256:' + createHash('sha256')
  .update(canonicalText(body), 'utf8').digest('hex');
const literal = body => JSON.stringify(canonicalText(body));
const complete = body => ({...body, model_invocation_evidence_cid: hash(body)});
const record = evidence => ({model_call_slot_cid: evidence.model_call_slot_cid,
  semantic_request_cid: evidence.semantic_request_cid,
  structured_response: {answer: 'original-e\u0301\r\n'}, evidence: complete(evidence)});
const bundle = (evidence, version) => ({version, captures: [record(evidence)],
  barrier_receipts: []});

export function modelObservationVectors() {
  const cases = [
    ['historical admitted metadata', historicalModelObservation],
    ['unknown input and observed zero output', nullableModelObservation],
    ['reported raw text and independently unknown output', reportedModelObservation],
    ['observed empty metadata is not unknown', {...nullableModelObservation,
      provider_metadata: {}}],
  ].map(([id, body]) => ({id, body, expected_cid: hash(body),
    expected_canonical_bytes: canonicalText(body)}));
  const seal = body => `seal_run_evidence_value("model_invocation_evidence", ${literal(body)}, 16384, 1024, 20)`;
  const read = (body, version) => {
    const value = bundle(body, version);
    return `read_model_capture_bundle(${literal({...value, bundle_cid: hash(value)})}, ${JSON.stringify(hash(value))}, 16384, 1024, 20)`;
  };
  let moon = '// Generated from independent scripts/fixtures/model-observation.mjs.\n';
  for (const [index, fixture] of cases.entries()) {
    const old = index === 0;
    moon += `\n///|\ntest ${JSON.stringify('Model observation: ' + fixture.id)} {\n` +
      `  let evidence = ${seal(fixture.body)}.unwrap()\n` +
      `  assert_eq(run_evidence_value_identity(evidence), ${JSON.stringify(fixture.expected_cid)})\n` +
      `  assert_eq(run_evidence_value_json(admit_run_evidence_value("model_invocation_evidence", run_evidence_value_json(evidence), 16384, 1024, 20).unwrap()), run_evidence_value_json(evidence))\n` +
      `  let saved = ${read(fixture.body, old ? 'actql-model-capture-bundle/0.1' : 'actql-model-capture-bundle/0.2')}.unwrap()\n` +
      `  let value = model_capture_record_observation(model_capture_bundle_record(saved, 0).unwrap()).unwrap()\n` +
      `  assert_eq(value.origin, ${old ? 'HistoricalAdmitted' : 'Reported'})\n` +
      `  assert_eq(value.input_tokens, ${fixture.body.input_tokens === null ? 'None' : 'Some(' + fixture.body.input_tokens + 'L)'})\n` +
      `  assert_eq(value.output_tokens, ${fixture.body.output_tokens === null ? 'None' : 'Some(' + fixture.body.output_tokens + 'L)'})\n` +
      `  assert_eq(value.provider_finish_reason, ${old || fixture.body.finish_reason === null ? 'None' : 'Some(' + JSON.stringify(fixture.body.finish_reason) + ')'})\n` +
      `  assert_eq(value.historical_finish_reason, ${old ? 'Some("stop")' : 'None'})\n` +
      `  assert_eq(value.response_complete, ${old ? 'None' : 'Some(true)'})\n` +
      `  assert_eq(value.provider_model, ${fixture.body.provider_reported_model_id === null ? 'None' : 'Some(' + JSON.stringify(fixture.body.provider_reported_model_id) + ')'})\n` +
      `  assert_${fixture.body.provider_metadata == null ? 'true' : 'false'}(value.provider_metadata is None)\n` +
      (fixture.body.provider_metadata == null ? '' :
        `  assert_eq(@json.stringify_value(value.provider_metadata.unwrap(), 16384, 1024, 20), ${literal(fixture.body.provider_metadata)})\n`) +
      `  assert_true(release_model_capture_bundle_read(saved))\n` +
      `  assert_false(release_model_capture_bundle_read(saved))\n}\n`;
  }
  for (const [id, metadata, bytes, depth] of [
    ['metadata byte ceiling', {long: 'x'.repeat(17000)}, 16384, 20],
    ['metadata depth ceiling', {a: {b: {c: {d: {e: {f: 1}}}}}}, 16384, 4],
  ]) {
    const body = {...nullableModelObservation, provider_metadata: metadata};
    moon += `\n///|\ntest ${JSON.stringify('Model observation limit refusal: ' + id)} {\n` +
      `  assert_true(seal_run_evidence_value("model_invocation_evidence", ${literal(body)}, ${bytes}, 1024, ${depth}) is Err(_))\n}\n`;
  }
  for (const [id, mutate] of observationRefusals) {
    const body = structuredClone(nullableModelObservation);
    mutate(body);
    moon += `\n///|\ntest ${JSON.stringify('Model observation refusal: ' + id)} {\n` +
      `  assert_true(${seal(body)} is Err(_))\n}\n`;
  }
  for (const [id, body, version] of [
    ['old evidence in new bundle', historicalModelObservation, 'actql-model-capture-bundle/0.2'],
    ['new evidence in old bundle', nullableModelObservation, 'actql-model-capture-bundle/0.1'],
    ['unknown bundle version', nullableModelObservation, 'actql-model-capture-bundle/invalid'],
  ]) {
    moon += `\n///|\ntest ${JSON.stringify('Model observation version refusal: ' + id)} {\n` +
      `  assert_true(${read(body, version)} is Err(_))\n}\n`;
  }
  for (const [id, mutate] of [
    ['foreign slot', value => {value.captures[0].model_call_slot_cid = 'sha256:' + 'a'.repeat(64);}],
    ['foreign semantic request', value => {value.captures[0].semantic_request_cid = 'sha256:' + 'b'.repeat(64);}],
    ['changed original evidence CID', value => {value.captures[0].evidence.output_tokens = 42;}],
  ]) {
    const value = bundle(nullableModelObservation, 'actql-model-capture-bundle/0.2');
    mutate(value);
    moon += `\n///|\ntest ${JSON.stringify('Model observation original refusal: ' + id)} {\n` +
      `  let saved = read_model_capture_bundle(${literal({...value, bundle_cid: hash(value)})}, ${JSON.stringify(hash(value))}, 16384, 1024, 20).unwrap()\n` +
      `  assert_true(model_capture_bundle_record(saved, 0) is Err(_))\n` +
      `  assert_true(release_model_capture_bundle_read(saved))\n}\n`;
  }
  const body = {...reportedModelObservation,
    raw_response_artifact_cid: 'sha256:' + 'a'.repeat(64)};
  moon += `\n///|\ntest "Model observation original raw artifact CID is retained" {\n` +
    `  let original = ${seal(reportedModelObservation)}.unwrap()\n` +
    `  let changed = ${seal(body)}.unwrap()\n` +
    `  assert_false(run_evidence_value_identity(original) == run_evidence_value_identity(changed))\n` +
    `  let saved = ${read(reportedModelObservation, 'actql-model-capture-bundle/0.2')}.unwrap()\n` +
    `  let observed = model_capture_record_observation(model_capture_bundle_record(saved, 0).unwrap()).unwrap()\n` +
    `  assert_eq(observed.raw_response_artifact_cid, Some(${JSON.stringify(reportedModelObservation.raw_response_artifact_cid)}))\n` +
    `  assert_eq(observed.response_profile_cid, Some(${JSON.stringify(reportedModelObservation.response_profile_cid)}))\n` +
    `  assert_true(release_model_capture_bundle_read(saved))\n}\n`;
  return {corpus: {version: 'actql-model-observation-vectors/0.1', cases}, moon};
}

export function checkModelObservationVectors() {
  const {corpus, moon} = modelObservationVectors();
  assert.deepEqual(JSON.parse(readFileSync('portability/corpus/model-observations.json', 'utf8')), corpus);
  assert.equal(readFileSync('src/run_publication/model_observation_vectors.generated_test.mbt', 'utf8'), moon);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--write')) {
    const {corpus, moon} = modelObservationVectors();
    writeFileSync('portability/corpus/model-observations.json', JSON.stringify(corpus, null, 2) + '\n');
    writeFileSync('src/run_publication/model_observation_vectors.generated_test.mbt', moon);
  }
  checkModelObservationVectors();
}
