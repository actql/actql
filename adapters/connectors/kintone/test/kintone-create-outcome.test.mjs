// Matching ordinary Common component only. Preview/response fixtures are DATA;
// no captured Run, physical provider write, saved response or approval grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {prepareMappedKintoneCreate, projectMappedKintoneCreateOutcome} from '../site/kintone-create-execution.mjs';
const runtime = process.env.ACTQL_TEST_KINTONE_COMMON_RUNTIME_URL ??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href;
const moon = await import(runtime);
const template = {"authoring_context":{"annotations":[],"authoring_context_cid":"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a","program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-authoring-context/0.1"},"barrier_provenance_cids":[],"check_environment_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effects":[{"approval":"none","authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_evidence_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"after":{"state":"present","value":{"Subject":"requested","Tags":["東京","東京"]}},"before":{"state":"absent"},"intended_changes":{"state":"present","value":{"Subject":"requested","Tags":["東京","東京"]}},"row_idempotency_key":"sha256:4444444444444444444444444444444444444444444444444444444444444444","row_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","target_guard":{"state":"not_applicable"},"target_row_identity":"create-original-correlation"}],"count":1,"effect_id":"CreateOne","effect_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_kind":"create","effect_member_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executed":false,"mapping":"mapping:fixture","max_items":1,"on_item_failure":"halt","preview_strength":"full_diff","required_permissions":["kintone:records:create"],"resolved_mapping_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_order":["sha256:3333333333333333333333333333333333333333333333333333333333333333"],"source_binding_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","target":"inquiries","write_footprint":{"kind":"collection","provider_boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"kintone","provider_object_identity_cids":[],"resource_identity_scheme_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","resource_kind":"inquiries"}}],"encryption_required":true,"executed":false,"invocation_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","model_derived":false,"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"model_task_contract_cids":[],"program_definition_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","program_semantics_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_class":"authority-evidence","run_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sensitivity":"private","version":"actql-effect-preview/0.1"};
const cid = c => `sha256:${c.repeat(64)}`;
const limits = Object.freeze({maxRequestBytes: 16384, maxResponseBytes: 16384,
  maxNodes: 2000, maxDepth: 24, maxFields: 16, maxNameUnits: 512,
  maxRows: 100, maxIdentityBytes: 1000, maxComparisonWork: 10000});
const value = {Subject: 'requested', Tags: ['東京', '東京']};
const responseBytes = Buffer.from('{"ids":["9007199254740993"],"revisions":["0009007199254740994"]}');
function fixture() {
  const catalog = checked(moon.clientProgramKintoneProjectForm(Buffer.from(JSON.stringify({revision: '7',
    properties: {Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT', expression: '', required: true},
      Tags: {code: 'Tags', type: 'MULTI_SELECT', required: false}}})), '12',
    moon.clientProgramKintoneFormLimits(16384, 2000, 24, 16, 512)));
  const declaration = checked(moon.clientProgramKintoneDeclareRecords(catalog, undefined,
    ['Subject', 'Tags'], 'kintone', 'kintone/0.1', 'inquiries',
    moon.clientProgramKintoneValueLimits(8, 512, 2000, 24, 16384),
    moon.clientProgramKintoneDeclarationLimits(200000, 20000, 24, 16, 16)));
  const mapping = checked(moon.clientProgramKintonePrepareCreateMapping(declaration, 'inquiries',
    [{target: 'Subject', field: 'subject', null_behavior: 'reject'},
      {target: 'Tags', field: 'tags', null_behavior: 'omit'}], 'required',
    moon.clientProgramKintoneDeclarationLimits(200000, 20000, 24, 16, 16)));
  const prepare = row => prepareMappedKintoneCreate({moon, mapping, declaration,
    bytes: Buffer.from(JSON.stringify([row])), limits});
  const request = prepare(value);
  const response = checked(moon.clientProgramKintoneCreateResponse(request, 200, responseBytes,
    moon.clientProgramKintoneMutationLimits(100, 1000, 10000, 16384, 2000, 24)));
  const effect = runtimeCore(moon).effectApplicationControl;
  const previewOf = row => {
    const body = structuredClone(template);
    const member = body.effects[0];
    const after = {state: 'present', value: row};
    const inventory = checked(moon.clientProgramEffectCreateRowInventory(
      [canonicalJson(after, {dataKeys: true})], 1, 16384, 2000, 24));
    member.changes[0].target_row_identity = JSON.parse(runtimeField(inventory[0], 1));
    member.changes[0].after = after;
    member.changes[0].intended_changes = after;
    member.authority_scope_cid = cid('e');
    const scope = effect.logicalRequestScope(cid('e'), 'create-outcome-component', 128);
    const authored = checked(moon.clientProgramAuthorEffectPreview(canonicalJson(body, {dataKeys: true}),
      body.run_identity_cid, body.authoring_context.authoring_context_cid,
      scope, 16384, 2000, 24, 1, 1, 128, 8, 3));
    return effect.admitPreviewIdentity(runtimeField(authored, 0), body.run_identity_cid,
      body.authoring_context.authoring_context_cid, scope, runtimeField(authored, 1), 16384, 2000, 24);
  };
  const preview = previewOf(value);
  const project = options => projectMappedKintoneCreateOutcome({moon, mapping, declaration,
    request, response, preview, memberIndex: 0, rowIndex: 0, limits, ...options});
  return {mapping, declaration, request, response, preview, previewOf, prepare, project};
}

test('matching actual Common CREATE projection retains original wide IDs response and Preview', () => {
  const f = fixture(), value = f.project();
  assert.equal(value.kind, 'typed-success-response');
  assert.deepEqual(value.outcome, {result: {created: true, record_id: '9007199254740993',
    revision: '0009007199254740994'}, state: 'applied'});
  assert.equal(value.rowPreviewCid, moon.strategyEffectPreviewOrderedRowCid(f.preview, 0, 0));
  assert.equal(moon.clientProgramKintoneCreatePreviewOutcomeMatches(value.projected,
    f.mapping, f.request, f.preview, 0, 0), true);
  assert.equal(moon.clientProgramKintoneCreatePreviewOutcomeMatches(value.projected,
    f.mapping, f.request, f.previewOf({Subject: 'requested', Tags: ['東京', '東京']}), 0, 0), false);
});

test('CREATE projection refuses changed row values order omission and foreign response request', () => {
  const f = fixture();
  for (const row of [{Subject: 'changed', Tags: ['東京', '東京']},
    {Subject: 'requested', Tags: ['東京']}, {Subject: 'requested'}]) {
    assert.throws(() => f.project({preview: f.previewOf(row)}));
  }
  assert.throws(() => f.project({request: f.prepare(value)}));
  assert.throws(() => f.project({rowIndex: 1}));
});

test('CREATE projection refuses copied native request acknowledgement and Mapping', () => {
  const f = fixture();
  for (const changes of [{request: {...f.request}}, {response: {...f.response}}, {mapping: {...f.mapping}}]) {
    assert.throws(() => f.project(changes));
  }
});

test('CREATE projection refuses a missing actual runtime port before accepting a response', () => {
  const f = fixture();
  const missing = {...moon, clientProgramKintoneCreatePreviewOutcome: undefined};
  assert.throws(() => f.project({moon: missing}), {code: 'KintoneCreateOutcomeRuntimeUnavailable'});
});
