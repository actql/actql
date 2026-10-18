// Actual same-runtime Connector/Common projection. Private authored Preview
// DATA is neither captured publication, approval, response custody nor a claim.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {sendMappedKintoneDelete, projectMappedKintoneDeleteOutcome} from '../site/kintone-delete-execution.mjs';
import {projectKintoneDeleteObservation} from '../site/kintone-record-delete.mjs';
import {deleteFixture} from './kintone-record-delete.fixture.mjs';
import {originalForm} from './installed-kintone.fixture.mjs';
const template = {"authoring_context":{"annotations":[],"authoring_context_cid":"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a","program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-authoring-context/0.1"},"barrier_provenance_cids":[],"check_environment_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effects":[{"approval":"required","authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_evidence_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"after":{"state":"absent"},"before":{"state":"present","value":{"$id":"9007199254740993","Subject":"original"}},"intended_changes":{"state":"not_applicable"},"row_idempotency_key":"sha256:4444444444444444444444444444444444444444444444444444444444444444","row_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","target_guard":{"state":"version","version_cid":"sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd"},"target_row_identity":"9007199254740993"}],"count":1,"effect_id":"DeleteOne","effect_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_kind":"delete","effect_member_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executed":false,"mapping":"mapping:fixture","max_items":1,"on_item_failure":"halt","preview_strength":"full_diff","required_permissions":["kintone:records:delete"],"resolved_mapping_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_order":["sha256:3333333333333333333333333333333333333333333333333333333333333333"],"source_binding_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","target":"inquiries","write_footprint":{"kind":"opaque","provider_boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"kintone","provider_object_identity_cids":[],"resource_identity_scheme_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","resource_kind":"inquiries"}}],"encryption_required":true,"executed":false,"invocation_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","model_derived":false,"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"model_task_contract_cids":[],"program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","program_semantics_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_class":"authority-evidence","run_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sensitivity":"private","version":"actql-effect-preview/0.1"};
const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const bytes = value => Buffer.from(JSON.stringify(value));
const limits = Object.freeze({maxRequestBytes: 16384, maxResponseBytes: 16384,
  maxNodes: 2000, maxDepth: 24, maxRows: 100, maxIdentityBytes: 1000,
  maxComparisonWork: 10000, maxColumns: 8, maxNameUnits: 512,
  maxValueNodes: 2000, maxValueDepth: 24, maxValueTextBytes: 16384});
const declaration = (common, catalog, fields = ['Subject']) => checked(common.clientProgramKintoneDeclareRecords(
  catalog, undefined, fields, 'kintone', 'kintone/0.1', 'inquiries',
  common.clientProgramKintoneValueLimits(8, 512, 2000, 24, 16384),
  common.clientProgramKintoneDeclarationLimits(200000, 20000, 32, 16, 16)));
const mapping = (common, original) => checked(common.clientProgramKintonePrepareDeleteMapping(original,
  'inquiries', 'required', common.clientProgramKintoneDeclarationLimits(200000, 20000, 32, 16, 16)));
function fixture() {
  const catalog = checked(moon.clientProgramKintoneProjectForm(bytes({revision: '7',
    properties: {Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'}}}), '12',
    moon.clientProgramKintoneFormLimits(16384, 2000, 24, 16, 512)));
  const declared = declaration(moon, catalog), owned = mapping(moon, declared);
  const prepare = (revision = '9007199254740994') => {
    const page = checked(moon.clientProgramKintoneProjectRecordPage(bytes({records: [{
      $id: {type: '__ID__', value: '9007199254740993'},
      $revision: {type: '__REVISION__', value: revision},
      Subject: {type: 'SINGLE_LINE_TEXT', value: 'original'},
    }], totalCount: null}), catalog, ['Subject'], moon.clientProgramKintonePageLimits(16384, 2000, 24, 4, 8, 32, 16)));
    return checked(moon.clientProgramKintoneDeleteRequest([
      checked(moon.clientProgramKintoneOriginalRecordTarget(page, 0, 1000)),
    ], moon.clientProgramKintoneMutationLimits(100, 1000, 10000, 16384, 2000, 24)));
  };
  const request = prepare();
  const response = checked(moon.clientProgramKintoneDeleteResponse(request, 200, Buffer.from('{}'), 16384, 2000, 24));
  const control = runtimeCore(moon).effectApplicationControl;
  const previewOf = (changes = {}) => {
    const body = structuredClone(template), member = body.effects[0];
    const selected = JSON.parse(moon.clientProgramKintoneDeleteMappingBody(owned));
    member.mapping = selected.mapping_ref;
    member.resolved_mapping_contract_cid = selected.mapping_contract_cid;
    member.authority_scope_cid = 'sha256:' + 'e'.repeat(64);
    if (changes.mappingCid) member.resolved_mapping_contract_cid = changes.mappingCid;
    if (changes.mappingRef) member.mapping = changes.mappingRef;
    if (changes.target) member.changes[0].target_row_identity = changes.target;
    if (changes.version) member.changes[0].target_guard.version_cid = changes.version;
    const scope = control.logicalRequestScope(member.authority_scope_cid, 'delete-outcome-component', 128);
    const authored = checked(moon.clientProgramAuthorEffectPreview(canonicalJson(body, {dataKeys: true}),
      body.run_identity_cid, body.authoring_context.authoring_context_cid,
      scope, 16384, 2000, 24, 1, 1, 128, 8, 3));
    return control.admitPreviewIdentity(runtimeField(authored, 0), body.run_identity_cid,
      body.authoring_context.authoring_context_cid, scope, runtimeField(authored, 1), 16384, 2000, 24);
  };
  const preview = previewOf();
  const project = options => projectMappedKintoneDeleteOutcome({moon, mapping: owned, declaration: declared,
    request, response, preview, memberIndex: 0, rowIndex: 0, limits, ...options});
  return {catalog, declaration: declared, mapping: owned, request, response, preview, prepare, previewOf, project};
}

test('actual Common DELETE outcome binds wide API ID and exact revision to the original Preview', () => {
  const f = fixture(), projected = f.project();
  assert.equal(projected.kind, 'typed-success-response');
  assert.deepEqual(projected.outcome, {result: {}, state: 'applied'});
  assert.equal(projected.responseSha256, createHash('sha256').update('{}').digest('hex'));
  assert.equal(projected.rowPreviewCid, moon.strategyEffectPreviewOrderedRowCid(f.preview, 0, 0));
  assert.equal(moon.clientProgramKintoneDeletePreviewOutcomeMatches(projected.projected,
    f.mapping, f.request, f.preview, 0, 0), true);
  assert.equal(moon.clientProgramKintoneDeletePreviewOutcomeMatches(projected.projected,
    f.mapping, f.request, f.previewOf(), 0, 0), false);
  assert.equal(moon.clientProgramKintoneDeleteBody(f.request),
    '{"app":"12","ids":["9007199254740993"],"revisions":["9007199254740994"]}');
});

test('DELETE outcome refuses another approved target guard Mapping or row', () => {
  const f = fixture();
  for (const changes of [{target: '9007199254740992'}, {version: cid('foreign revision')},
    {mappingCid: cid('foreign Mapping')}, {mappingRef: 'mapping:foreign'}]) {
    assert.throws(() => f.project({preview: f.previewOf(changes)}));
  }
  for (const changes of [{memberIndex: 1}, {rowIndex: 1}, {rowIndex: -1},
    {request: f.prepare()}, {request: f.prepare('9007199254740995')}]) {
    assert.throws(() => f.project(changes));
  }
});

test('DELETE projection refuses copied native request response and Mapping and missing actual runtime ports', () => {
  const f = fixture();
  for (const changes of [{request: {...f.request}}, {response: {...f.response}}, {mapping: {...f.mapping}},
    {declaration: {...f.declaration}}]) assert.throws(() => f.project(changes));
  assert.throws(() => f.project({moon: {...moon, clientProgramKintoneDeletePreviewOutcome: undefined}}),
    {code: 'KintoneDeleteOutcomeRuntimeUnavailable'});
  assert.throws(() => f.project({limits: {...limits, maxValueNodes: 0}}), {code: 'InvalidKintoneDeleteOutcome'});
  assert.throws(() => f.project({limits: {...limits, maxRequestBytes: 1}}), {code: 'InvalidKintoneDeleteOutcome'});
});

test('mapped DELETE retains real original Account Site response custody and raw batch semantics', async t => {
  const f = await deleteFixture(t);
  const declared = declaration(f.common, f.catalog, ['RecordNumber', 'Subject', 'Tags']);
  const owned = mapping(f.common, declared);
  const raw = await f.send({mapping: owned, declaration: declared,
    send: sendMappedKintoneDelete});
  // Exercise the actual thin caller, with the same original nominal use and
  // binding held by the raw fixture. It is a fresh fixture, never a retry.
  assert.equal(raw.observation.statusCode, 200);
  assert.equal(f.state.writes, 1); assert.equal(f.state.charges, 3);
  assert.equal(f.state.consumed, 3); assert.deepEqual(f.state.fixtureFailures, []);
  const response = projectKintoneDeleteObservation({moon: f.common, request: f.request,
    observation: raw.observation, limits: f.options.limits});
  assert.equal(response.kind, 'typed-delete-response');
  // A provider batch cannot stand for an individual Effect row.
  const one = fixture();
  assert.throws(() => projectMappedKintoneDeleteOutcome({moon: f.common, mapping: owned,
    declaration: declared, request: f.request, response: response.response,
    preview: one.preview, memberIndex: 0, rowIndex: 0, limits}));
  f.row.assertNoCapture();
});

test('mapped physical DELETE refuses an equal foreign declaration before provider I/O', async t => {
  const f = await deleteFixture(t);
  const foreign = checked(f.common.clientProgramKintoneProjectForm(bytes(originalForm), '12',
    f.common.clientProgramKintoneFormLimits(16384, 2000, 24, 16, 512)));
  const declared = declaration(f.common, foreign, ['RecordNumber', 'Subject', 'Tags']);
  const owned = mapping(f.common, declared);
  await assert.rejects(sendMappedKintoneDelete({...f.options, mapping: owned, declaration: declared}),
    {code: 'ForeignKintoneDeleteRequest'});
  assert.equal(f.tls.seen().length, 0); assert.equal(f.state.writes, 0); assert.equal(f.state.resolutions, 0);
});
