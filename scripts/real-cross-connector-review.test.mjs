import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {checkRealRoutePreview, checkRealRouteReviewProjection} from './fixtures/real-cross-connector-preview.mjs';
const vector = JSON.parse(readFileSync(new URL('./fixtures/real-cross-connector-review-vector.json', import.meta.url)));
const cid = digit => 'sha256:' + digit.repeat(64);
const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const clone = value => JSON.parse(JSON.stringify(value));
function fixture() {
  const body = clone(vector.body), expected = clone(vector.expected);
  return {body, expected, review: {artifactCid: body.review_projection_cid, bytes: Buffer.from(canonicalText(body))}};
}
function reseal(value) {
  const {review_projection_cid: ignored, ...preimage} = value.body; void ignored;
  value.body.review_projection_cid = digest(canonicalText(preimage));
  value.review = {artifactCid: value.body.review_projection_cid, bytes: Buffer.from(canonicalText(value.body))};
  value.expected.checkpoint.reviewProjectionCid = value.body.review_projection_cid;
  return value;
}

test('public Table review uses the fixed independent self-CID vector and keeps the full-byte digest separate', () => {
  const f = fixture();
  assert.equal(f.review.artifactCid, 'sha256:df029ec5db85b4a87d8444497f713719d0253db7b72e6356a198bf534810ffa9');
  assert.notEqual(digest(f.review.bytes), f.review.artifactCid);
  const checked = checkRealRouteReviewProjection(f.review, f.expected);
  assert.equal(checked.identity.sha256, digest(f.review.bytes).slice(7));
  assert.equal(checked.operation.action, 'create');
  assert.equal(checked.preApprovalPayload, 'unavailable_in_review_projection');
  assert.deepEqual(checked.reviewBinding.claims, ['effect_scope_approved']);
  // The unchanged historical private oracle rejects this different input.
  assert.throws(() => checkRealRoutePreview(f.review, {catalogCid: cid('1'), mappingCid: cid('2')}));
});

test('restored public Table review requires identical original bytes and identity', () => {
  const f = fixture(), first = checkRealRouteReviewProjection(f.review, f.expected);
  assert.deepEqual(checkRealRouteReviewProjection(f.review, {...f.expected, original: first.identity}), first);
  assert.throws(() => checkRealRouteReviewProjection({...f.review, bytes: Buffer.concat([f.review.bytes, Buffer.from(' ')])},
    {...f.expected, original: first.identity}));
  assert.throws(() => checkRealRouteReviewProjection({...f.review, artifactCid: digest(f.review.bytes)}, f.expected));
});

test('each of the fourteen public review fields remains mandatory', () => {
  assert.equal(Object.keys(vector.body).length, 14);
  for (const key of Object.keys(vector.body)) {
    const f = fixture(); delete f.body[key]; f.review.bytes = Buffer.from(canonicalText(f.body));
    assert.throws(() => checkRealRouteReviewProjection(f.review, f.expected), key);
  }
});

test('complete canonical DATA and the original semantic preimage are required', () => {
  const f = fixture();
  const variants = [Buffer.from(JSON.stringify(f.body)), Buffer.from(f.review.bytes.toString() + '\n'),
    Buffer.from(f.review.bytes.toString().replace('restricted', 'private')), Buffer.from([0xff])];
  for (const bytes of variants) assert.throws(() => checkRealRouteReviewProjection({...f.review, bytes}, f.expected));
});

test('public identity does not replace original Run, required Preview, scope, claim or authoring binding', () => {
  for (const fault of ['run', 'physical-run', 'preview', 'scope', 'claims', 'authoring', 'context-preimage', 'checkpoint-kind', 'phase']) {
    const f = fixture();
    if (fault === 'run') f.expected.runRef.runDefinitionCid = cid('f');
    if (fault === 'physical-run') f.expected.runId = 'foreign-run';
    if (fault === 'phase') f.expected.checkpoint.phase = 'preflight';
    if (fault === 'preview') f.body.effect_preview_cid = cid('f');
    if (fault === 'scope') f.body.authority_scope_cid = cid('f');
    if (fault === 'claims') f.body.approval_claims = ['partial_application_accepted'];
    if (fault === 'authoring') f.body.displayed_authoring_context[0].authoring_context_cid = cid('f');
    if (fault === 'context-preimage') f.body.displayed_authoring_context[0].program_definition_cid = cid('f');
    if (fault === 'checkpoint-kind') f.expected.checkpoint.kind = 'run_scope';
    reseal(f);
    assert.throws(() => checkRealRouteReviewProjection(f.review, f.expected), fault);
  }
});

test('public Table review keeps original scope, permission and restricted retention facts', () => {
  for (const fault of ['target', 'kind', 'count', 'permission', 'sensitivity', 'retention', 'encryption', 'extra']) {
    const f = fixture();
    const effect = f.body.displayed_scope.effects[0];
    if (fault === 'target') effect.target = 'connector://foreign/catalog';
    if (fault === 'kind') effect.kind = 'update';
    if (fault === 'count') effect.count = 2;
    if (fault === 'permission') f.body.displayed_permissions = [];
    if (fault === 'sensitivity') f.body.sensitivity = 'public';
    if (fault === 'retention') f.body.retention_class = 'temporary';
    if (fault === 'encryption') f.body.encryption_required = false;
    if (fault === 'extra') f.body.executed = false;
    reseal(f); assert.throws(() => checkRealRouteReviewProjection(f.review, f.expected), fault);
  }
});

test('each original row strength, guard, intended operation and before/after state is retained', () => {
  for (const fault of ['strength', 'guard', 'before', 'after', 'intended', 'row', 'member', 'extra', 'missing']) {
    const f = fixture(), row = f.body.displayed_rows[0];
    if (fault === 'strength') row.preview_strength = 'targeted';
    if (fault === 'guard') row.target_guard = {state: 'version', version_cid: cid('f')};
    if (fault === 'before') row.before = {state: 'unavailable'};
    if (fault === 'after') row.after = {state: 'absent'};
    if (fault === 'intended') row.intended_changes = {state: 'not_applicable'};
    if (fault === 'row') row.target_row_identity = cid('f');
    if (fault === 'member') row.effect_id = 'other';
    if (fault === 'extra') row.mapping = 'mapping:foreign';
    if (fault === 'missing') delete row.target_guard;
    reseal(f); assert.throws(() => checkRealRouteReviewProjection(f.review, f.expected), fault);
  }
});

test('the complete public Table operation retains original create target, schema, carrier and request identity', () => {
  for (const fault of ['catalog', 'action', 'namespace', 'table', 'expected', 'schema', 'carrier', 'input', 'missing', 'request']) {
    const f = fixture(), operation = f.body.displayed_rows[0].intended_changes.value;
    if (fault === 'catalog') operation.catalog_identity_cid = cid('f');
    if (fault === 'action') operation.action = 'replace';
    if (fault === 'namespace') operation.namespace = ['foreign'];
    if (fault === 'table') operation.table_name = 'foreign';
    if (fault === 'expected') operation.expected_table = {};
    if (fault === 'schema') operation.schema_cid = cid('f');
    if (fault === 'carrier') operation.input_carrier.kind = 'graph';
    if (fault === 'input') operation.input_artifact_cid = cid('f');
    if (fault === 'missing') delete operation.logical_request_scope_cid;
    if (fault === 'request') operation.request_cid = cid('f');
    reseal(f); assert.throws(() => checkRealRouteReviewProjection(f.review, f.expected), fault);
  }
});
