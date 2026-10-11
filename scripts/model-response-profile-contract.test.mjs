import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {checkModelResponseProfileSchema, responseProfileLimitNames,
  responseObservationOrder} from './model-response-profile-contract.mjs';
import {checkResponseProfileVectors, responseProfileVectors}
  from './model-response-profile-vectors.mjs';

test('owned response profile schema and independent vectors are fresh', () => {
  checkModelResponseProfileSchema(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
  checkResponseProfileVectors();
  for (const c of responseProfileVectors().corpus.cases) {
    assert.equal(c.expected_cid, machineCid(c.body));
  }
});

test('old schema bodies and identity pins are not broadened by a profile', () => {
  const r = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  assert.equal(machineCid(r.artifact_schemas.model_invocation_evidence),
    'sha256:9b883bf32553da51b01bd88ff912f460eb2308034b33a591a18f7f6e91c38b27');
  assert.equal(machineCid(r.artifact_schemas.model_capture_bundle),
    'sha256:9e4c76623e09216b81f70ca5573b90dc6f17f4a8754638345da2f8ec617507ba');
  assert.equal(machineCid(r.artifact_schemas.model_provider_binding),
    'sha256:a4a37e0016403b483aa267dca7aae6c682940d2b23343b95defbcac2a1ca92b3');
});

test('finite physical declarations do not replace nullable actual observations', () => {
  const schema = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'))
    .artifact_schemas.model_response_profile;
  assert.deepEqual(schema.properties.limits.required, [...responseProfileLimitNames]);
  assert.deepEqual(schema.properties.observations.items.enum, [...responseObservationOrder]);
  const evidence = JSON.parse(readFileSync('portability/corpus/model-observations.json'));
  assert.ok(evidence.cases.some(c => c.body.provider_metadata === null));
  assert.ok(evidence.cases.some(c => c.body.provider_metadata &&
    Object.keys(c.body.provider_metadata).length === 0));
  assert.ok(evidence.cases.some(c => c.body.provider_metadata &&
    Object.keys(c.body.provider_metadata).length > 0));
  assert.ok(evidence.cases.some(c => c.body.input_tokens === null));
  assert.ok(evidence.cases.some(c => c.body.output_tokens === 0));
});
