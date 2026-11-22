// The installed Table adapter's pure authoring connection. It consumes the
// checked Program and actual captured input owners; it neither fabricates
// Relation rows nor grants approval, availability, staging or send authority.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkedTableWriteBinding, verifyTableWriteBinding} from './table-write-binding.mjs';

import type {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';

type WireBounds = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type MaterialBounds = WireBounds & Readonly<{maxWork: number}>;
type PreviewBounds = Readonly<{maxMembers: number; maxFields: number; planWork: number;
  material: MaterialBounds; preview: WireBounds;
  key: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>}>;
type Runtime = Parameters<typeof checkedTableWriteBinding>[0] & Readonly<{
  clientProgramEffectRequestAuthority(scope: unknown): string;
  clientProgramEffectDefinitionCid(prepared: unknown): string;
  strategyRunEvidenceSeal(name: string, wire: string, bytes: number, nodes: number, depth: number): unknown;
  strategyRunEvidenceJson(evidence: unknown): string;
  strategyPublicationContractIdentity(contract: unknown): string;
  clientProgramEffectMemberDescriptor(prepared: unknown, stage: number, effectId: string, work: number): unknown;
  strategyEffectLogicalRequestScopeCid(scope: unknown): string;
  clientProgramEffectPlanCid(prepared: unknown, member: number, fields: number, work: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramEffectSemanticsCid(prepared: unknown): string;
  clientProgramEffectEnvironmentCid(prepared: unknown): string;
  clientProgramCanonicalEffectPreviewDraft(wire: string, bytes: number, nodes: number, depth: number): unknown;
  clientProgramAuthorEffectPreview(wire: string, runCid: string, authoringCid: string, scope: unknown,
    bytes: number, nodes: number, depth: number, members: number, rows: number,
    keyBytes: number, keyNodes: number, keyDepth: number): unknown;
  clientProgramBindEffectPreviewInputs(host: unknown, inputs: unknown, invocation: unknown,
    stage: number, wire: string, authoringCid: string, limits: unknown): unknown;
  clientProgramEffectPreviewInputLimits(bytes: number, nodes: number, depth: number,
    bindingWork: number, planFields: number, planBytes: number, planNodes: number, planDepth: number,
    members: number, targets: number, footprintWork: number, sourceWork: number): unknown;
}>;
type Bridge = Pick<ReturnType<typeof createIcebergPhysicalBridge>, 'issueStorageMapping' | 'admitStorageMapping'>;
type WireIdentity = Readonly<{wire: string; identity: string}>;
type TableInput = Readonly<{wire: string}>;
type TablePreview = Readonly<{operationWire: string; subjectCid: string}>;
type Control = Parameters<Bridge['issueStorageMapping']>[0]['control'] &
  Parameters<Bridge['admitStorageMapping']>[0]['control'] & Readonly<{
    issueSourceFreeLocalEffectIdentity(prepared: unknown, inputs: unknown, index: number,
      artifact: WireIdentity, limits: MaterialBounds): WireIdentity;
    bindTableInput(prepared: unknown, inputs: unknown, index: number, artifact: WireIdentity,
      identity: WireIdentity, scope: unknown, operationWire: string, mappingWire: string,
      limits: MaterialBounds): TableInput;
    effectTableSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string,
      sourceRef: string, authorityCid: string): unknown;
    effectSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string,
      sourceRef: string, authorityCid: string): unknown;
    checkSourceFreeLocalEffectPreviewIdentities(prepared: unknown, inputs: unknown, wire: string,
      runCid: string, authoringCid: string, identities: readonly WireIdentity[], limits: WireBounds): unknown;
    bindTablePreview(input: TableInput, captured: unknown, index: number): TablePreview;
}>;
type Target = Parameters<typeof verifyTableWriteBinding>[0] & Readonly<{
  targetRef: string; mappingRef: string; mappingCid: string; permissions: readonly string[];
  catalogCid: string; namespace: readonly string[]; tableName: string; footprint: unknown;
}>;
type Member = Readonly<{stageIndex: number; effectId: string; target: Target;
  payload: Readonly<{localResultArtifact: WireIdentity; summary: Readonly<{artifact: unknown}>}>}>;
type PreviewInputs = Readonly<{
  moon: Runtime; control: Control; prepared: unknown; inputs: unknown; checkedHost: unknown; requestScope: unknown;
  context: Readonly<{runDefinition: unknown; runInvocation: unknown; compiledPlan: unknown; storeAuthorityCid: string}>;
  members: readonly Member[]; bridge: Bridge; limits: PreviewBounds;
}>;
type ArtifactBody = Readonly<{logical_result_cid: string; result_schema_cid: string; effective_data_policy_cid: string}>;
type Operation = Readonly<{request_cid: string; schema_cid: string; effect_identity_cid: string}> & (
  Readonly<{action: 'replace'; expected_table: NonNullable<Target['expectedTable']>}> |
  Readonly<{action: 'create'; expected_table: null}>
);

const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const pendingCid = `sha256:${'0'.repeat(64)}`;
const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const hash = (value: unknown) => `sha256:${createHash('sha256').update(wire(value)).digest('hex')}`;
const positive = (value: number | undefined) => Number.isSafeInteger(value) && value! > 0;

// Targets are the installation's resolved Mapping/target bindings, not
// caller-supplied input identities. Common admission rechecks the input facts
// and the captured Preview. An installation must separately validate its
// capability and current authorization before using these results for apply.
export function authorTableOperationPreview({moon, control, prepared, inputs,
  checkedHost, requestScope, context, members, bridge, limits}: PreviewInputs) {
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
  const authoringBody = JSON.parse(moon.strategyRunEvidenceJson(authoring)) as Readonly<{authoring_context_cid: string}>;
  const runCid = moon.strategyPublicationContractIdentity(context.runDefinition);
  const invocationCid = moon.strategyPublicationContractIdentity(context.runInvocation);
  const identities: WireIdentity[] = [], tableInputs: TableInput[] = [], operations: Operation[] = [];
  let stageIndex: number | undefined;
  const effects = members.map((member, index) => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(prepared,
      member.stageIndex, member.effectId, limits.planWork));
    const target = member.target;
    if (runtimeField(descriptor, 0) !== index || runtimeField(descriptor, 2) !== 'store' ||
        (runtimeField(descriptor, 6) === undefined) === (runtimeField(descriptor, 8) === undefined) ||
        target?.targetRef !== runtimeField(descriptor, 3) ||
        target.mappingRef !== runtimeField(descriptor, 4) || target.mappingCid !== runtimeField(descriptor, 5) ||
        !Array.isArray(target.permissions) || target.permissions.length === 0 ||
        target.permissions.some((value: unknown) => typeof value !== 'string' || value.length === 0) ||
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
    const issuedMapping = bridge.issueStorageMapping({control, artifact, limits: material}) as WireIdentity;
    const mapping = bridge.admitStorageMapping({control,
      mappingWire: issuedMapping?.wire, limits: material}) as WireIdentity;
    if (mapping?.wire !== issuedMapping?.wire || mapping.identity !== issuedMapping?.identity) {
      fail('ForeignTableStorageMapping');
    }
    const source = JSON.parse(artifact.wire) as ArtifactBody;
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
    const admittedOperation = JSON.parse(tableInput.wire) as Operation;
    identities.push(identity);
    tableInputs.push(tableInput);
    operations.push(Object.freeze(admittedOperation));
    const privateInput = runtimeField(descriptor, 8) !== undefined;
    const binding = (privateInput ? control.effectTableSourceArtifactPreviewBinding
      : control.effectSourceArtifactPreviewBinding)(
      member.payload.summary.artifact, invocationCid, (runtimeField(descriptor, 8) ?? runtimeField(descriptor, 6)) as string,
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
    preview.maxWireBytes, preview.maxNodes, preview.maxDepth)) as string;
  const authored = checked(moon.clientProgramAuthorEffectPreview(canonical, runCid,
    authoringBody.authoring_context_cid, requestScope, preview.maxWireBytes,
    preview.maxNodes, preview.maxDepth, members.length, members.length,
    key.maxBytes, key.maxNodes, key.maxDepth));
  control.checkSourceFreeLocalEffectPreviewIdentities(prepared, inputs,
    runtimeField(authored, 0) as string, runCid, authoringBody.authoring_context_cid, identities, preview);
  const capturedInputs = checked(moon.clientProgramBindEffectPreviewInputs(checkedHost,
    inputs, context.runInvocation, stageIndex!, runtimeField(authored, 0) as string,
    authoringBody.authoring_context_cid,
    moon.clientProgramEffectPreviewInputLimits(preview.maxWireBytes,
      preview.maxNodes, preview.maxDepth, limits.planWork, limits.maxFields,
      preview.maxWireBytes, preview.maxNodes, preview.maxDepth,
      members.length, members.length, limits.planWork, limits.planWork)));
  const tablePreviews = tableInputs.map((input,index) =>
    control.bindTablePreview(input, capturedInputs, index));
  return Object.freeze({wire: runtimeField(authored, 0) as string, keys: runtimeField(authored, 1) as readonly (readonly unknown[])[],
    authoringCid: authoringBody.authoring_context_cid, capturedInputs,
    tableInputs: Object.freeze(tableInputs), tablePreviews: Object.freeze(tablePreviews),
    identities: Object.freeze(identities), operations: Object.freeze(operations)});
}
