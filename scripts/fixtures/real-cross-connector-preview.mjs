// Acceptance assertions over the original authorized review projection only.
// Artifact references do not expose pre-approval row payloads or grant reads.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

// Independent canonical recursive field map, following relation_schema_identity.
export const realRouteSchemaWire = '{"id":{"nullable":false,"type":"number"},"tag":{"nullable":false,"type":"string"}}';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const cid = value => assert.match(value, /^sha256:[0-9a-f]{64}$/u);

export function checkRealRoutePreview(review, {catalogCid, mappingCid, original} = {}) {
  const bytes = Buffer.from(review.bytes);
  cid(review.artifactCid);
  const identity = {artifactCid: review.artifactCid, byteLength: bytes.length, sha256: sha256(bytes)};
  if (original !== undefined) assert.deepEqual(identity, original, 'Restore must review the original sealed Preview');
  const body = JSON.parse(bytes.toString('utf8'));
  assert.equal(body.version, 'actql-effect-preview/0.1');
  assert.equal(body.executed, false);
  assert.equal(body.effects.length, 1);
  const member = body.effects[0];
  assert.equal(member.effect_kind, 'store');
  assert.equal(member.target, 'connector://table/catalog');
  assert.equal(member.mapping, 'mapping:table.catalog.v1');
  assert.equal(member.resolved_mapping_contract_cid, mappingCid);
  assert.equal(member.approval, 'required');
  assert.equal(member.executed, false);
  assert.equal(member.count, 1); assert.equal(member.max_items, 1);
  assert.equal(member.changes.length, 1);
  const change = member.changes[0];
  assert.deepEqual(change.target_guard, {state: 'not_applicable'});
  assert.deepEqual(change.before, {state: 'not_applicable'});
  assert.deepEqual(change.after, {state: 'not_applicable'});
  assert.equal(change.intended_changes.state, 'present');
  const operation = change.intended_changes.value;
  assert.equal(operation.version, 'actql-table-operation/0.1');
  assert.equal(operation.action, 'create');
  assert.equal(operation.catalog_identity_cid, catalogCid);
  assert.deepEqual(operation.namespace, ['test']);
  assert.equal(operation.table_name, 'rows');
  assert.equal(operation.expected_table, null);
  assert.equal(operation.schema_cid, `sha256:${sha256(realRouteSchemaWire)}`);
  for (const value of [member.result_artifact_cid, member.source_binding_cid,
    operation.input_artifact_cid, operation.input_carrier.cid, operation.effect_identity_cid,
    operation.storage_mapping_cid, operation.request_cid]) cid(value);
  assert.equal(operation.input_carrier.kind, 'relation');
  assert.equal(operation.input_artifact_cid, member.result_artifact_cid);
  assert.equal(operation.effect_identity_cid, member.effect_identity_cid);
  assert.equal(change.target_row_identity, operation.request_cid);
  return {identity, operation, target: member.target, mapping: member.mapping,
    mappingCid, sourceBindingCid: member.source_binding_cid,
    preApprovalPayload: 'unavailable_in_existing_review_projection'};
}
