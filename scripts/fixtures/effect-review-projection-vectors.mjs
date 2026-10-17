// Independently authored preimages. This fixture never imports a product
// sealer, compiler, runtime, schema generator or Host observation.
import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';
export const C = digit => `sha256:${digit.repeat(64)}`;
export const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;
export const scope = C('7');
export const policy = C('8');
export const claims = ['effect_scope_approved'];
export const originalRun = C('b');
export const authoringBody = {version: 'actql-authoring-context/0.1',
  program_definition_cid: C('a'), annotations: []};
export const authoring = {...authoringBody, authoring_context_cid: hash(authoringBody)};
export const resource = {$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
  resource_kind: 'file', provider_namespace: 'fixture', provider_identity_cid: C('a'),
  authority_scope_cid: C('7'), boundary_cid: C('c'), identity_cid: C('d')};

function vector(name, kind, strength, target, rowTarget) {
  const before = kind === 'create' ? {state: 'absent'}
    : kind === 'command' ? {state: 'not_applicable'}
      : strength === 'targeted' ? {state: 'unavailable'}
        : {state: 'present', value: {Name: 'Before'}};
  const after = kind === 'command' ? {state: 'not_applicable'}
    : {state: 'present', value: {Name: 'After'}};
  const guard = ['create', 'command'].includes(kind)
    ? {state: 'not_applicable'} : {state: 'version', version_cid: C('a')};
  const intended = {state: 'present', value: kind === 'command'
    ? {operation: 'reindex', input: {label: 'original-e\u0301\r\n'}} : {Name: 'After'}};
  if (kind === 'create') rowTarget = {content_cid: hash({
    value: after, version: 'actql-effect-content-row/0.1'}), occurrence: 0};
  const rowBody = {version: 'actql-effect-preview-row/0.1',
    program_definition_cid: C('a'), invocation_cid: C('a'),
    effect_identity_cid: C('a'), resolved_contract_cid: C('a'), operation: kind,
    target_row_identity: rowTarget, preview_strength: strength,
    target_guard: guard, intended_changes: intended, before, after};
  const row = {target_row_identity: rowTarget, target_guard: guard,
    intended_changes: intended, before, after, row_preview_cid: hash(rowBody)};
  const memberBody = {effect_id: 'WriteOne', effect_kind: kind, target,
    ...(kind === 'command' ? {contract: 'command:fixture', resolved_command_contract_cid: C('a')}
      : {mapping: 'mapping:fixture', resolved_mapping_contract_cid: C('a')}),
    effect_identity_cid: C('a'), preview_strength: strength,
    source_binding_cid: C('a'), capability_evidence_cid: C('a'), authority_scope_cid: C('7'),
    write_footprint: {kind: 'exact_targets', resource_identity_scheme_cid: C('a'),
      provider_namespace: 'fixture', provider_boundary_cid: C('c'), resource_kind: 'file',
      provider_object_identity_cids: [C('d')]}, count: 1, max_items: 1,
    required_permissions: ['write'], approval: 'required', on_item_failure: 'halt',
    changes: [row], row_order: [row.row_preview_cid], executed: false};
  const member = {...memberBody, effect_member_preview_cid: hash({
    version: 'actql-effect-member-preview/0.1', member: memberBody})};
  const previewBody = {version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: C('a'), program_definition_cid: C('a'), invocation_cid: C('a'),
    compiled_plan_cid: C('a'), check_environment_cid: C('a'), barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [], effects: [member], executed: false};
  const preview = {...previewBody, run_identity_cid: originalRun,
    authoring_context: authoring, effect_preview_cid: hash(previewBody),
    effects: [{...member, changes: [{...row, row_idempotency_key: C('4')}]}]};
  const body = {version: 'actql-review-projection/0.1', effect_preview_cid: preview.effect_preview_cid,
    authority_scope_cid: scope, approval_claims: claims,
    authoring_context_cid: authoring.authoring_context_cid, redaction_policy_cid: policy,
    sensitivity: 'restricted', retention_class: 'approval-evidence', encryption_required: true,
    displayed_scope: {effects: [{effect_id: 'WriteOne', kind, target, count: 1}]},
    displayed_permissions: ['write'], displayed_rows: [{effect_id: 'WriteOne',
      row_preview_cid: row.row_preview_cid, target_row_identity: rowTarget, before, after,
      preview_strength: strength, target_guard: guard, intended_changes: intended}],
    displayed_authoring_context: [authoring]};
  const review = {...body, review_projection_cid: hash(body)};
  return {name, preview, body, review, cid: hash(body),
    previewWire: canonicalText(preview), reviewWire: canonicalText(review)};
}

export const vectors = [
  vector('full diff update', 'update', 'full_diff', 'Object', '001000000000001'),
  vector('targeted field selector preserves unavailable before', 'update', 'targeted',
    {field: 'Target'}, resource),
  vector('create preserves absent before and content occurrence', 'create', 'full_diff', 'Object'),
  vector('command keeps concrete ResourceRef and typed request', 'command', 'full_diff', resource, resource),
  vector('store keeps concrete ResourceRef and intended value', 'store', 'full_diff', resource, resource),
];
export const legacyBody = structuredClone(vectors[0].body);
for (const name of ['preview_strength', 'target_guard', 'intended_changes']) delete legacyBody.displayed_rows[0][name];
export const legacy = {...legacyBody, review_projection_cid: hash(legacyBody)};
// Fixed independent preimage pins, established before executing Common.
export const expectedCids = [
  'sha256:78a38561db4024a12d1269cb5ca6e69aeba24a7516dfe04052e648aa4b53e152',
  'sha256:61f5851f0fa58a8a91b2314e204a71fbfbfb00881ad5159d207644fa00463766',
  'sha256:15e6eb2ba487f9350a6909300defb23de18bb0d31749f51ff4fc1379c09aa655',
  'sha256:65d5eba02275b8471fafaf8d6930729379624ac2ee1322b081ee8c9162805214',
  'sha256:069e220e25f61baed146575925e7a40c9c1895cd258d039c61beee6d17ac2bf5',
];
export const legacyCid = 'sha256:e93b31fcde78f6640c6997cad2d53b0e5cd44f17b2acb275220f76c183130d86';
export const mutations = [
  ...['preview_strength', 'target_guard', 'intended_changes'].map(name => {
    const body = structuredClone(vectors[0].body);delete body.displayed_rows[0][name];
    return {name: `missing ${name}`, body};
  }),
  ...[
    ['strength', b => {b.displayed_rows[0].preview_strength='targeted';}],
    ['guard', b => {b.displayed_rows[0].target_guard.version_cid=C('0');}],
    ['change', b => {b.displayed_rows[0].intended_changes.value.Name='Other';}],
    ['before', b => {b.displayed_rows[0].before.value.Name='Other';}],
    ['after', b => {b.displayed_rows[0].after.value.Name='Other';}],
    ['row identity', b => {b.displayed_rows[0].target_row_identity='other';}],
    ['row CID', b => {b.displayed_rows[0].row_preview_cid=C('0');}],
    ['member', b => {b.displayed_rows[0].effect_id='other';}],
    ['scope target', b => {b.displayed_scope.effects[0].target='other';}],
    ['scope count', b => {b.displayed_scope.effects[0].count=0;}],
    ['scope kind', b => {b.displayed_scope.effects[0].kind='delete';}],
    ['permissions', b => {b.displayed_permissions=[];}],
    ['Preview', b => {b.effect_preview_cid=C('0');}],
    ['authority', b => {b.authority_scope_cid=C('0');}],
    ['claims', b => {b.approval_claims.push('partial_application_accepted');}],
    ['authoring CID', b => {b.authoring_context_cid=C('0');}],
    ['redaction policy', b => {b.redaction_policy_cid=C('0');}],
    ['displayed authoring', b => {b.displayed_authoring_context=[];}],
  ].map(([name, change]) => {const body=structuredClone(vectors[0].body);change(body);return{name,body};}),
].map(({name, body})=>({name, wire:canonicalText({...body,review_projection_cid:hash(body)})}));
for(const name of Object.keys(vectors[0].review)){
  const body=structuredClone(vectors[0].body);delete body[name];
  const complete=name==='review_projection_cid'?body:{...body,review_projection_cid:hash(body)};
  mutations.push({name:`missing top-level ${name}`,wire:canonicalText(complete)});
}
