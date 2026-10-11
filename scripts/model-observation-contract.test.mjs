import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {modelObservationSchemas, checkModelObservationSchemas}
  from './model-observation-contract.mjs';
import {checkModelObservationVectors, modelObservationVectors}
  from './model-observation-vectors.mjs';

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
const hash = body => 'sha256:' + createHash('sha256')
  .update(canonicalText(body)).digest('hex');

test('historical invocation and embedded capture schema pins remain exact', () => {
  assert.equal(hash(registry.artifact_schemas.model_invocation_evidence),
    'sha256:9b883bf32553da51b01bd88ff912f460eb2308034b33a591a18f7f6e91c38b27');
  assert.equal(hash(registry.artifact_schemas.model_capture_bundle),
    'sha256:9e4c76623e09216b81f70ca5573b90dc6f17f4a8754638345da2f8ec617507ba');
  assert.deepEqual(registry.artifact_schemas.model_invocation_evidence
    .properties.finish_reason, {const: 'stop'});
  assert.deepEqual(registry.artifact_schemas.model_capture_bundle.properties
    .captures.items.properties.evidence.properties.version,
  {const: 'actql-model-invocation-evidence/0.1'});
});

test('version compatibility is exact and never repairs mixed evidence', () => {
  const schemas = modelObservationSchemas(registry.artifact_schemas);
  assert.deepEqual(schemas.model_invocation_evidence_compatible.oneOf,
    [registry.artifact_schemas.model_invocation_evidence,
      schemas.model_invocation_evidence_v02]);
  assert.deepEqual(schemas.model_capture_bundle_compatible.oneOf,
    [registry.artifact_schemas.model_capture_bundle,
      schemas.model_capture_bundle_v02]);
  assert.deepEqual(schemas.model_capture_bundle_v02.properties.captures.items
    .properties.evidence.properties.version,
  {const: 'actql-model-invocation-evidence/0.2'});
  for (const name of ['input_tokens', 'output_tokens', 'finish_reason',
    'provider_reported_model_id', 'provider_reported_revision',
    'provider_request_id', 'gateway_request_id', 'raw_response_artifact_cid']) {
    const schema = schemas.model_invocation_evidence_v02;
    assert.ok(schema.required.includes(name), name);
    assert.deepEqual(schema.properties[name].oneOf.at(-1), {type: 'null'});
  }
});

test('complete evidence binds a profile independently of opaque metadata', () => {
  const schema = registry.artifact_schemas.model_invocation_evidence_v02;
  assert.ok(schema.required.includes('response_profile_cid'));
  assert.deepEqual(schema.properties.response_complete, {const: true});
  assert.deepEqual(schema.properties.provider_metadata,
    {oneOf: [{type: 'object'}, {type: 'null'}]});
  assert.equal(schema.properties.structured_response_artifact_cid.type, 'string');
  assert.equal(schema.properties.validated_structured_output_cid.type, 'string');
  assert.equal(schema.properties.attempt.const, 1);
  checkModelObservationSchemas(registry);
});

test('independent observed zero, unknown usage and original Unicode differ', () => {
  const {corpus} = modelObservationVectors();
  for (const item of corpus.cases) {
    assert.equal(item.expected_cid, hash(item.body));
    assert.equal(item.expected_canonical_bytes, canonicalText(item.body));
  }
  const unknown = corpus.cases[1].body;
  assert.equal(unknown.input_tokens, null);
  assert.equal(unknown.output_tokens, 0);
  assert.notEqual(hash({...unknown, input_tokens: 0}), hash(unknown));
  const raw = corpus.cases[2].body;
  assert.equal(raw.provider_reported_model_id, 'raw-e\u0301\r\nmodel');
  assert.notEqual(hash({...raw, provider_reported_model_id: 'raw-é\nmodel'}), hash(raw));
  assert.equal(unknown.provider_metadata, null);
  assert.deepEqual(corpus.cases[3].body.provider_metadata, {});
  assert.notEqual(hash({...unknown, provider_metadata: {}}), hash(unknown));
  assert.equal(raw.provider_metadata.provider.nested.complete, false);
  assert.equal(raw.response_complete, true);
  assert.notEqual(hash({...raw, raw_response_artifact_cid: 'sha256:' + 'a'.repeat(64)}), hash(raw));
  checkModelObservationVectors();
});
