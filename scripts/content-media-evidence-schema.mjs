import assert from 'node:assert/strict';

// Closed schema contribution for the existing Content issuer evidence. This
// function does not write a registry, repin history, or grant Ref authority.
// Coordinate both current occurrences and their dependent pins before adoption.
const report = Object.freeze({type: 'string', minLength: 1, maxLength: 256});
const condition = Object.freeze({
  if: {properties: {issuer_kind: {const: 'connector_capture'}}, required: ['issuer_kind']},
  then: {required: ['reported_media_type']},
  else: {not: {required: ['reported_media_type']}},
});
const fields = ['version', 'issuer_kind', 'issuer_contract_cid', 'content_store_cid',
  'workspace_scope_cid', 'content_cid', 'effective_data_policy_cid',
  'capture_authority_cid', 'evidence_cid'];

export function capturedMediaEvidenceSchema(original) {
  assert.equal(original.type, 'object');
  assert.equal(original.additionalProperties, false);
  assert.equal(original.properties.version.const, 'actql-content-issuer-evidence/0.1');
  assert.deepEqual(original.properties.issuer_kind.enum, ['connector_capture', 'content_derivation']);
  assert.deepEqual([...original.required].sort(), [...fields].sort());
  assert.deepEqual(Object.keys(original.properties).filter(name => name !== 'reported_media_type').sort(),
    [...fields].sort());
  const schema = structuredClone(original);
  if (Object.hasOwn(schema.properties, 'reported_media_type')) {
    assert.deepEqual(schema.properties.reported_media_type, report);
    assert.deepEqual(schema.allOf, [condition]);
    return schema;
  }
  assert.equal(schema.allOf, undefined, 'do not overwrite another closed evidence rule');
  schema.properties.reported_media_type = structuredClone(report);
  schema.allOf = [structuredClone(condition)];
  // This is a character bound only. Core separately enforces the existing
  // 256 UTF-8 byte MIME limit; neither bound is physical reservation evidence.
  return schema;
}
