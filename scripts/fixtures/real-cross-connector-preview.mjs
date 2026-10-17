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

// The public review is a separately bound projection. The legacy private
// checker above remains an unchanged compatibility oracle for its old input;
// it must not be used as the shape of reviewCheckpoint()'s public response.
function reviewCanonical(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number') {
    assert(Number.isFinite(value) && !Object.is(value, -0));
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    assert(value.isWellFormed()); return JSON.stringify(value);
  }
  if (Array.isArray(value)) return '[' + value.map(reviewCanonical).join(',') + ']';
  assert(value && Object.getPrototypeOf(value) === Object.prototype);
  return '{' + Object.keys(value).sort().map(key => {
    assert(key.isWellFormed() && value[key] !== undefined);
    return JSON.stringify(key) + ':' + reviewCanonical(value[key]);
  }).join(',') + '}';
}

export function checkRealRouteReviewProjection(review, {catalogCid, checkpoint, runRef, runId, original} = {}) {
  const bytes = Buffer.from(review.bytes);
  cid(review.artifactCid);
  const identity = {artifactCid: review.artifactCid, byteLength: bytes.length, sha256: sha256(bytes)};
  if (original !== undefined) assert.deepEqual(identity, original, 'Restore must review the original sealed projection');
  const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes), body = JSON.parse(wire);
  assert.equal(body.version, 'actql-review-projection/0.1');
  assert.deepEqual(Object.keys(body).sort(), ['version', 'effect_preview_cid', 'authority_scope_cid',
    'approval_claims', 'authoring_context_cid', 'redaction_policy_cid', 'sensitivity', 'retention_class',
    'encryption_required', 'displayed_scope', 'displayed_permissions', 'displayed_rows',
    'displayed_authoring_context', 'review_projection_cid'].sort());
  assert.equal(reviewCanonical(body), wire, 'Exact canonical DATA keys and bytes');
  const {review_projection_cid: self, ...preimage} = body;
  assert.equal(self, `sha256:${sha256(Buffer.from(reviewCanonical(preimage)))}`);
  assert.equal(self, review.artifactCid);
  assert.equal(self, checkpoint.reviewProjectionCid);
  assert.equal(checkpoint.kind, 'effect_set');
  assert.equal(checkpoint.phase, 'commit');
  assert.equal(checkpoint.subject.kind, 'run_unit');
  assert.equal(typeof runId, 'string'); assert(runId.length > 0);
  assert.equal(checkpoint.subject.runId, runId);
  assert.equal(checkpoint.subject.runDefinitionCid, runRef.runDefinitionCid);
  assert.equal(checkpoint.requiredArtifact.type, 'effect_set_preview');
  assert.equal(body.effect_preview_cid, checkpoint.requiredArtifact.cid);
  assert.equal(body.authority_scope_cid, runRef.authorityScopeCid);
  assert.deepEqual(body.approval_claims, checkpoint.requirements);
  assert(body.approval_claims.includes('effect_scope_approved'));
  for (const value of [body.effect_preview_cid, body.authority_scope_cid,
    body.authoring_context_cid, body.redaction_policy_cid]) cid(value);
  assert.equal(body.sensitivity, 'restricted');
  assert.equal(body.retention_class, 'approval-evidence'); assert.equal(body.encryption_required, true);
  assert.deepEqual(body.displayed_scope, {effects: [{effect_id: 'save', kind: 'store',
    target: 'connector://table/catalog', count: 1}]});
  assert.deepEqual(body.displayed_permissions, ['scope:store']);
  assert.equal(body.displayed_authoring_context.length, 1);
  const authoring = body.displayed_authoring_context[0];
  assert.equal(authoring.version, 'actql-authoring-context/0.1');
  assert.equal(authoring.authoring_context_cid, body.authoring_context_cid);
  cid(authoring.program_definition_cid);
  const {authoring_context_cid: contextSelf, ...contextPreimage} = authoring;
  assert.equal(contextSelf, `sha256:${sha256(Buffer.from(reviewCanonical(contextPreimage)))}`);
  assert.equal(body.displayed_rows.length, 1);
  const row = body.displayed_rows[0];
  assert.deepEqual(Object.keys(row).sort(), ['effect_id', 'row_preview_cid', 'target_row_identity',
    'before', 'after', 'preview_strength', 'target_guard', 'intended_changes'].sort());
  assert.equal(row.effect_id, 'save'); cid(row.row_preview_cid);
  assert.equal(row.preview_strength, 'full_diff');
  assert.deepEqual(row.target_guard, {state: 'not_applicable'});
  assert.deepEqual(row.before, {state: 'not_applicable'});
  assert.deepEqual(row.after, {state: 'not_applicable'});
  assert.deepEqual(Object.keys(row.intended_changes).sort(), ['state', 'value']);
  assert.equal(row.intended_changes.state, 'present');
  const operation = row.intended_changes.value;
  assert.deepEqual(Object.keys(operation).sort(), ['version', 'logical_request_scope_cid',
    'effect_identity_cid', 'action', 'catalog_identity_cid', 'namespace', 'table_name',
    'expected_table', 'input_artifact_cid', 'input_carrier', 'schema_cid',
    'storage_mapping_cid', 'data_policy_cid', 'request_cid'].sort());
  assert.equal(operation.version, 'actql-table-operation/0.1');
  assert.equal(operation.action, 'create'); assert.equal(operation.catalog_identity_cid, catalogCid);
  assert.deepEqual(operation.namespace, ['test']); assert.equal(operation.table_name, 'rows');
  assert.equal(operation.expected_table, null);
  assert.equal(operation.schema_cid, `sha256:${sha256(realRouteSchemaWire)}`);
  for (const value of [operation.logical_request_scope_cid, operation.data_policy_cid,
    operation.input_artifact_cid, operation.input_carrier.cid,
    operation.effect_identity_cid, operation.storage_mapping_cid, operation.request_cid]) cid(value);
  assert.deepEqual(Object.keys(operation.input_carrier).sort(), ['cid', 'kind']);
  assert.equal(operation.input_carrier.kind, 'relation');
  const {request_cid: requestSelf, ...requestPreimage} = operation;
  assert.equal(requestSelf, `sha256:${sha256(Buffer.from(reviewCanonical(requestPreimage)))}`);
  assert.equal(row.target_row_identity, operation.request_cid);
  // These are assertions about displayed evidence, never an apply/current
  // decision. Unexposed private Mapping/source-binding/executed fields remain
  // covered by the legacy oracle at its original qualification, not invented
  // in this public artifact. The actual test still requires zero pre-approval
  // catalog commits and one approved commit of the independently expected rows.
  return {identity, operation, target: body.displayed_scope.effects[0].target,
    reviewBinding: {previewCid: body.effect_preview_cid, authorityScopeCid: body.authority_scope_cid,
      authoringContextCid: body.authoring_context_cid, claims: body.approval_claims},
    preApprovalPayload: 'unavailable_in_review_projection'};
}
