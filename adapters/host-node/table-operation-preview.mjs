// The installed Table adapter's pure authoring connection. It consumes the
// checked Program and actual captured input owners; it neither fabricates
// Relation rows nor grants approval, availability, staging or send authority.
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const pendingCid = `sha256:${'0'.repeat(64)}`;
const wire = value => canonicalJson(value, {dataKeys: true});
const hash = value => `sha256:${createHash('sha256').update(wire(value)).digest('hex')}`;
const positive = value => Number.isSafeInteger(value) && value > 0;

// Targets are the installation's resolved Mapping/target bindings, not
// caller-supplied input identities. Common admission rechecks the input facts
// and the captured Preview. An installation must separately validate its
// capability and current authorization before using these results for apply.
export function authorTableOperationPreview({moon, control, prepared, inputs,
  checkedHost, requestScope, context, members, limits}) {
  const {material, preview, key} = limits ?? {};
  if (!Array.isArray(members) || members.length === 0 ||
      ![limits?.maxMembers, limits?.maxFields, limits?.planWork,
        material?.maxWireBytes, material?.maxNodes, material?.maxDepth,
        material?.maxWork, preview?.maxWireBytes, preview?.maxNodes,
        preview?.maxDepth, key?.maxBytes, key?.maxNodes,
        key?.maxDepth].every(positive) || members.length > limits.maxMembers) {
    fail('InvalidTablePreviewConfiguration');
  }
  const requestAuthority = moon.clientProgramEffectRequestAuthority(requestScope);
  const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = checked(moon.strategyRunEvidenceSeal('authoring_context',
    wire({version: 'actql-authoring-context/0.1',
      program_definition_cid: definitionCid, annotations: []}),
    preview.maxWireBytes, preview.maxNodes, preview.maxDepth));
  const authoringBody = JSON.parse(moon.strategyRunEvidenceJson(authoring));
  const runCid = moon.strategyPublicationContractIdentity(context.runDefinition);
  const invocationCid = moon.strategyPublicationContractIdentity(context.runInvocation);
  const identities = [], tableInputs = [], operations = [];
  let stageIndex;
  const effects = members.map((member, index) => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(prepared,
      member.stageIndex, member.effectId, limits.planWork));
    const target = member.target;
    if (descriptor._0 !== index || descriptor._2 !== 'store' ||
        descriptor._6 === undefined || target?.targetRef !== descriptor._3 ||
        target.mappingRef !== descriptor._4 || target.mappingCid !== descriptor._5 ||
        !Array.isArray(target.permissions) || target.permissions.length === 0 ||
        target.permissions.some(value => typeof value !== 'string' || value.length === 0) ||
        new Set(target.permissions).size !== target.permissions.length ||
        (index > 0 && stageIndex !== member.stageIndex)) {
      fail('TablePreviewMappingNotInstalled');
    }
    stageIndex = member.stageIndex;
    const artifact = member.payload.localResultArtifact;
    const identity = control.issueSourceFreeLocalEffectIdentity(prepared, inputs,
      index, artifact, material);
    const mapping = control.localEffectTableStorageMapping(artifact, material);
    const source = JSON.parse(artifact.wire);
    const operation = {
      version: 'actql-table-operation/0.1', action: target.action,
      catalog_identity_cid: target.catalogCid, namespace: target.namespace,
      table_name: target.tableName, expected_table: target.expectedTable,
      logical_request_scope_cid: moon.strategyEffectLogicalRequestScopeCid(requestScope),
      effect_identity_cid: identity.identity, input_artifact_cid: artifact.identity,
      input_relation_cid: source.logical_result_cid, schema_cid: source.result_schema_cid,
      storage_mapping_cid: mapping.identity,
      data_policy_cid: source.effective_data_policy_cid,
    };
    const operationWire = wire({...operation, request_cid: hash(operation)});
    const tableInput = control.bindTableInput(prepared, inputs, index, artifact,
      identity, requestScope, operationWire, material);
    const admittedOperation = JSON.parse(tableInput.wire);
    identities.push(identity);
    tableInputs.push(tableInput);
    operations.push(Object.freeze(admittedOperation));
    const binding = control.effectSourceArtifactPreviewBinding(
      member.payload.summary.artifact, invocationCid, descriptor._6,
      context.storeAuthorityCid);
    const planCid = checked(moon.clientProgramEffectPlanCid(prepared, index,
      limits.maxFields, limits.planWork, preview.maxWireBytes,
      preview.maxNodes, preview.maxDepth));
    return {
      effect_id: descriptor._1, effect_kind: 'store', target: descriptor._3,
      mapping: descriptor._4, resolved_mapping_contract_cid: descriptor._5,
      effect_identity_cid: identity.identity, source_result: descriptor._6,
      ...(planCid === undefined ? {} : {effect_plan_logical_cid: planCid}),
      // A Table names the semantic completed Result Artifact. The separate
      // source binding still comes from the actual Run-bound physical owner.
      result_artifact_cid: artifact.identity, source_binding_cid: binding._1,
      preview_strength: 'full_diff', capability_evidence_cid: target.capabilityCid,
      authority_scope_cid: requestAuthority, write_footprint: target.footprint,
      count: 1, max_items: 1, required_permissions: target.permissions,
      approval: 'required', on_item_failure: descriptor._7,
      changes: [{target_row_identity: admittedOperation.request_cid,
        target_guard: admittedOperation.action === 'replace'
          ? {state: 'version', version_cid: admittedOperation.expected_table.generation_cid}
          : {state: 'not_applicable'},
        before: {state: 'not_applicable'}, after: {state: 'not_applicable'},
        intended_changes: {state: 'present', value: admittedOperation},
        row_preview_cid: pendingCid, row_idempotency_key: pendingCid}],
      row_order: [], effect_member_preview_cid: pendingCid, executed: false,
    };
  });
  const draft = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: definitionCid, invocation_cid: invocationCid,
    run_identity_cid: runCid,
    compiled_plan_cid: moon.strategyPublicationContractIdentity(context.compiledPlan),
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: authoringBody, barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [], effects, executed: false, effect_preview_cid: pendingCid,
  };
  const draftWire = wire(draft);
  if (Buffer.byteLength(draftWire) > preview.maxWireBytes) fail('TablePreviewByteLimit');
  const canonical = checked(moon.clientProgramCanonicalEffectPreviewDraft(draftWire,
    preview.maxWireBytes, preview.maxNodes, preview.maxDepth));
  const authored = checked(moon.clientProgramAuthorEffectPreview(canonical, runCid,
    authoringBody.authoring_context_cid, requestScope, preview.maxWireBytes,
    preview.maxNodes, preview.maxDepth, members.length, members.length,
    key.maxBytes, key.maxNodes, key.maxDepth));
  control.checkSourceFreeLocalEffectPreviewIdentities(prepared, inputs,
    authored._0, runCid, authoringBody.authoring_context_cid, identities, preview);
  const capturedInputs = checked(moon.clientProgramBindEffectPreviewInputs(checkedHost,
    inputs, context.runInvocation, stageIndex, authored._0,
    authoringBody.authoring_context_cid,
    moon.clientProgramEffectPreviewInputLimits(preview.maxWireBytes,
      preview.maxNodes, preview.maxDepth, limits.planWork, limits.maxFields,
      preview.maxWireBytes, preview.maxNodes, preview.maxDepth,
      members.length, members.length, limits.planWork, limits.planWork)));
  const tablePreviews = tableInputs.map((input,index) =>
    control.bindTablePreview(input, capturedInputs, index));
  return Object.freeze({wire: authored._0, keys: authored._1,
    authoringCid: authoringBody.authoring_context_cid, capturedInputs,
    tableInputs: Object.freeze(tableInputs), tablePreviews: Object.freeze(tablePreviews),
    identities: Object.freeze(identities), operations: Object.freeze(operations)});
}
