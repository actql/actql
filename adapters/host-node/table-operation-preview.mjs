// The installed Table adapter's pure authoring connection. It consumes the
// checked Program and actual captured input owners; it neither fabricates
// Relation rows nor grants approval, availability, staging or send authority.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkedTableWriteBinding, verifyTableWriteBinding} from './table-write-binding.mjs';

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
  checkedHost, requestScope, context, members, bridge, limits}) {
  const {material, preview, key} = limits ?? {};
  if (!Array.isArray(members) || members.length === 0 ||
      typeof bridge?.issueStorageMapping !== 'function' ||
      typeof bridge?.admitStorageMapping !== 'function' ||
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
    if (runtimeField(descriptor, 0) !== index || runtimeField(descriptor, 2) !== 'store' ||
        (runtimeField(descriptor, 6) === undefined) === (runtimeField(descriptor, 8) === undefined) ||
        target?.targetRef !== runtimeField(descriptor, 3) ||
        target.mappingRef !== runtimeField(descriptor, 4) || target.mappingCid !== runtimeField(descriptor, 5) ||
        !Array.isArray(target.permissions) || target.permissions.length === 0 ||
        target.permissions.some(value => typeof value !== 'string' || value.length === 0) ||
        new Set(target.permissions).size !== target.permissions.length ||
        (index > 0 && stageIndex !== member.stageIndex)) {
      fail('TablePreviewMappingNotInstalled');
    }
    stageIndex = member.stageIndex;
    verifyTableWriteBinding(target, checkedTableWriteBinding(moon, prepared,
      member.stageIndex, member.effectId, limits.planWork));
    const artifact = member.payload.localResultArtifact;
    const identity = control.issueSourceFreeLocalEffectIdentity(prepared, inputs,
      index, artifact, material);
    const issuedMapping = bridge.issueStorageMapping({control, artifact, limits: material});
    const mapping = bridge.admitStorageMapping({control,
      mappingWire: issuedMapping?.wire, limits: material});
    if (mapping?.wire !== issuedMapping?.wire || mapping.identity !== issuedMapping?.identity) {
      fail('ForeignTableStorageMapping');
    }
    const source = JSON.parse(artifact.wire);
    const operation = {
      version: 'actql-table-operation/0.1', action: target.action,
      catalog_identity_cid: target.catalogCid, namespace: target.namespace,
      table_name: target.tableName, expected_table: target.expectedTable,
      logical_request_scope_cid: moon.strategyEffectLogicalRequestScopeCid(requestScope),
      effect_identity_cid: identity.identity, input_artifact_cid: artifact.identity,
      input_carrier: {kind: 'relation', cid: source.logical_result_cid}, schema_cid: source.result_schema_cid,
      storage_mapping_cid: mapping.identity,
      data_policy_cid: source.effective_data_policy_cid,
    };
    const operationWire = wire({...operation, request_cid: hash(operation)});
    const tableInput = control.bindTableInput(prepared, inputs, index, artifact,
      identity, requestScope, operationWire, mapping.wire, material);
    const admittedOperation = JSON.parse(tableInput.wire);
    identities.push(identity);
    tableInputs.push(tableInput);
    operations.push(Object.freeze(admittedOperation));
    const privateInput = runtimeField(descriptor, 8) !== undefined;
    const binding = (privateInput ? control.effectTableSourceArtifactPreviewBinding
      : control.effectSourceArtifactPreviewBinding)(
      member.payload.summary.artifact, invocationCid, runtimeField(descriptor, 8) ?? runtimeField(descriptor, 6),
      context.storeAuthorityCid);
    const planCid = checked(moon.clientProgramEffectPlanCid(prepared, index,
      limits.maxFields, limits.planWork, preview.maxWireBytes,
      preview.maxNodes, preview.maxDepth));
    return {
      effect_id: runtimeField(descriptor, 1), effect_kind: 'store', target: runtimeField(descriptor, 3),
      mapping: runtimeField(descriptor, 4), resolved_mapping_contract_cid: runtimeField(descriptor, 5),
      effect_identity_cid: identity.identity,
      ...(privateInput ? {source_table_input: runtimeField(descriptor, 8)} : {source_result: runtimeField(descriptor, 6)}),
      ...(planCid === undefined ? {} : {effect_plan_logical_cid: planCid}),
      // A Table names the semantic completed Result Artifact. The separate
      // source binding still comes from the actual Run-bound physical owner.
      result_artifact_cid: artifact.identity, source_binding_cid: runtimeField(binding, 1),
      preview_strength: 'full_diff', capability_evidence_cid: target.capabilityCid,
      authority_scope_cid: requestAuthority, write_footprint: target.footprint,
      count: 1, max_items: 1, required_permissions: target.permissions,
      approval: 'required', on_item_failure: runtimeField(descriptor, 7),
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
    runtimeField(authored, 0), runCid, authoringBody.authoring_context_cid, identities, preview);
  const capturedInputs = checked(moon.clientProgramBindEffectPreviewInputs(checkedHost,
    inputs, context.runInvocation, stageIndex, runtimeField(authored, 0),
    authoringBody.authoring_context_cid,
    moon.clientProgramEffectPreviewInputLimits(preview.maxWireBytes,
      preview.maxNodes, preview.maxDepth, limits.planWork, limits.maxFields,
      preview.maxWireBytes, preview.maxNodes, preview.maxDepth,
      members.length, members.length, limits.planWork, limits.planWork)));
  const tablePreviews = tableInputs.map((input,index) =>
    control.bindTablePreview(input, capturedInputs, index));
  return Object.freeze({wire: runtimeField(authored, 0), keys: runtimeField(authored, 1),
    authoringCid: authoringBody.authoring_context_cid, capturedInputs,
    tableInputs: Object.freeze(tableInputs), tablePreviews: Object.freeze(tablePreviews),
    identities: Object.freeze(identities), operations: Object.freeze(operations)});
}
