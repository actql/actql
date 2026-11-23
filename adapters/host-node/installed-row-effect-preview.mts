import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {approvalOf} from './installed-row-effect-commit.mjs';
import {canonicalJson} from './local-account-config.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {ControlWork, prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type MappingKind = 'create' | 'update' | 'upsert' | 'delete';
type MemberKind = MappingKind | 'command';
type MemberRef = Readonly<{kind: MemberKind; effectId: string}>;
type PreflightEffect = Readonly<{
  source_binding_cid: string;
  capability_evidence_cid: string;
  effect_kind: MemberKind;
  changes: readonly Readonly<{target_guard: Readonly<{state: string}>; row_preview_cid: string}>[];
  row_order: readonly string[];
}>;
type Preflight<Member> = Readonly<{
  effects: readonly PreflightEffect[];
  members: readonly Member[];
  requestScope: unknown;
  keys?: readonly (readonly unknown[])[];
  limits: Readonly<{maxRows: number; maxWork: number}>;
}>;
type ContinuationPlan = Readonly<{request: unknown; attempt: unknown}>;
type ContinuationUnit = Readonly<{programId: string; stageId: string; stageIndex: number}>;
type ContinuationOwner = Readonly<{
  profile: Readonly<{continuation: string; continuationBinding: string}>;
  continuationBinding: unknown;
}>;
type ContextControls<Member extends MemberRef, Owner> = Readonly<{
  moon: Pick<PreviewRuntime, 'clientProgramEffectRequestAuthority'>;
  contractCidOf(member: Member): string;
  guarded(kind: MemberKind): boolean;
  singular?: ContinuationOwner;
  ROUTING_VERSION: string;
  ownerOf(member: Member): Owner;
  installationFacts(owner: Owner): unknown;
}>;

type FootprintMember = Readonly<{memberIndex: number; resource: string}> & (
  Readonly<{kind: MappingKind; mapping: Readonly<{primaryIdentity: unknown}>}> | Readonly<{kind: 'command'}>);
type Entry = Readonly<{request: unknown}>;
type RawFootprint = Readonly<{
  kind?: string; provider_boundary_cid?: string; provider_namespace?: unknown; resource_kind?: unknown;
  resource_identity_scheme_cid?: string; provider_object_identity_cids?: unknown;
  providerNamespace?: string; resourceKind?: string; boundaryCid?: string; then?: never;
}>;
type FootprintWork = ControlWork & Partial<Pick<ReturnType<typeof prepareInstalledEffectControlConstruction>, 'footprint'>>;
type FootprintControls<Member extends FootprintMember> = Readonly<{
  ownerOf(member: Member): Readonly<{
    owned: Readonly<{footprint(facts: Readonly<{member: Member; entries: readonly Entry[]}>): RawFootprint | undefined}>;
    connectorRegistration: string;
  }>;
  recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  footprintKinds: readonly string[];
  cidPattern: RegExp;
  text(value: unknown): boolean;
  cid(value: unknown): string;
  contractCidOf(member: Member): string;
  fail(code: string): never;
}>;

type Bounds = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type AuthorArguments = [canonical: string, runIdentityCid: string, authoringCid: string, requestScope: unknown,
  maxWireBytes: number, maxNodes: number, maxDepth: number, maxMembers: number, maxRows: number,
  maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number];
type PreviewRuntime = Readonly<{
  clientProgramEffectRequestAuthority(scope: unknown): string;
  clientProgramEffectDefinitionCid(prepared: unknown): string;
  strategyRunEvidenceSeal(kind: string, wire: string, bytes: number, nodes: number, depth: number): unknown;
  strategyRunEvidenceJson(evidence: unknown): string;
  clientProgramEffectMemberDescriptor(prepared: unknown, stage: number, effect: string, work: number): unknown;
  strategyPublicationContractIdentity(contract: unknown): string;
  clientProgramEffectPlanCid(prepared: unknown, member: number, fields: number, work: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramEffectSemanticsCid(prepared: unknown): string;
  clientProgramEffectEnvironmentCid(prepared: unknown): string;
  clientProgramCanonicalEffectPreviewDraft(wire: string, bytes: number, nodes: number, depth: number): unknown;
  clientProgramAuthorEffectPreview(...args: AuthorArguments): unknown;
  clientProgramAuthorInstalledEffectPreview(value: unknown, prepared: unknown, request: unknown,
    operationPlan: unknown, allowed: unknown, definition: unknown, invocation: unknown,
    ...args: AuthorArguments): SynchronousRuntimeData;
}>;
type HeldResult = Readonly<{identity: string}>;
type AuthoringContext = Readonly<{authoring_context_cid: string}>;
type PreviewControl = Readonly<{
  effectSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string, sourceResult: unknown,
    storeAuthorityCid: string): unknown;
  issueSourceFreeLocalEffectIdentity(prepared: unknown, inputs: unknown, member: number, artifact: HeldResult,
    limits: Bounds & Readonly<{maxWork: number}>): HeldResult;
  checkSourceFreeLocalEffectPreviewIdentities(prepared: unknown, inputs: unknown, wire: string,
    runIdentityCid: string, authoringCid: string, identities: readonly HeldResult[], limits: Bounds): unknown;
}>;
type PreviewMember = MemberRef & Readonly<{stageIndex: number}> & (
  Readonly<{kind: MappingKind; mapping: Readonly<{approval?: string}>}>
  | Readonly<{kind: 'command'}>);
type PreviewRow = Readonly<{
  identity?: unknown; entry: Readonly<{value?: unknown; target?: unknown}>;
  state?: string; versionCid?: string; before?: unknown;
}>;
type PreviewInput<Member> = Readonly<{
  control: PreviewControl;
  prepared: unknown;
  inputs: unknown;
  context: Readonly<{runInvocation: unknown; runDefinition: unknown; compiledPlan: unknown; storeAuthorityCid: string}>;
  requestScope: unknown;
  limits: Readonly<{
    preview: Bounds; planWork: number; maxRows: number; maxRowsPerMember: number; maxFields: number;
    key: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
  }>;
  managedEffect?: Readonly<{
    value: unknown; request: unknown; operationPlan: unknown;
    definitionOriginal: Readonly<{allowed: unknown}>; controlConstruction: ControlWork;
  }>;
  members: readonly Member[];
  rowsOf: readonly (readonly PreviewRow[])[];
  capabilities: readonly HeldResult[];
  footprints: readonly unknown[];
  payloads: readonly Readonly<{summary: Readonly<{artifact?: unknown}>; localResultArtifact: HeldResult}>[];
}>;
type PreviewControls<Member extends PreviewMember> = Readonly<{
  moon: PreviewRuntime;
  permissionsOf(member: Member): readonly string[];
  pendingCid: string;
  fail(code: string): never;
}>;

export function createInstalledRowEffectPreviewContext<Member extends MemberRef, Owner>({
  moon, contractCidOf, guarded, singular, ROUTING_VERSION, ownerOf, installationFacts,
}: ContextControls<Member, Owner>) {
  const basePreflight = ({effects, members, requestScope, keys, limits}: Preflight<Member>) => ({
    sources: effects.map(member => member.source_binding_cid),
    contracts: members.map(contractCidOf),
    capabilities: effects.map(member => member.capability_evidence_cid),
    authorities: effects.map(() => moon.clientProgramEffectRequestAuthority(
      requestScope)),
    observedRows: effects.flatMap(member => {
      if (!guarded(member.effect_kind)) return [];
      const versioned = new Set(member.changes.filter(row => row.target_guard.state === 'version')
        .map(row => row.row_preview_cid));
      return member.row_order.filter(row => versioned.has(row));
    }),
    guardVersions: [], routes: [],
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '',
    policyCid: '', validityCid: '', issuerCid: '', authenticationCid: '',
    issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}),
    maxMembers: members.length, maxRows: limits.maxRows,
    maxFootprintWork: limits.maxRows, maxWork: limits.maxWork,
  });

  const continuationOf = (plan: ContinuationPlan, unit: ContinuationUnit,
    members: readonly Member[], dispatches: readonly string[], selected: boolean) => canonicalJson({
    ...(singular === undefined ? {version: ROUTING_VERSION} : {
      version: singular.profile.continuation,
      [singular.profile.continuationBinding]: singular.continuationBinding}),
    program_id: unit.programId, stage_id: unit.stageId,
    ...(selected ? {stage_index: unit.stageIndex} : {}),
    request: plan.request, attempt: plan.attempt,
    members: members.map((member, index) => ({
      effect_id: member.effectId,
      ...(member.kind === 'command'
        ? {command_cid: contractCidOf(member)} : {mapping_cid: contractCidOf(member)}),
      dispatch_request_cid: dispatches[index],
      ...(singular === undefined || selected
        ? {installation: installationFacts(ownerOf(member))} : {}),
    }))});

  return {basePreflight, continuationOf};
}

export function createInstalledRowEffectFootprint<Member extends FootprintMember>({
  ownerOf, recipeOf, footprintKinds, cidPattern, text, cid, contractCidOf, fail,
}: FootprintControls<Member>) {
  const reject: FootprintControls<Member>['fail'] = fail;
  // A member's write footprint: the provider's complete footprint, or the
  // opaque footprint of its boundary.
  const footprintOf = (member: Member, entries: readonly Entry[], controlConstruction?: FootprintWork) => {
    const {owned, connectorRegistration} = ownerOf(member);
    const facts = {member, entries};
    const constructor = recipeOf(member)?.footprintConstruction;
    const footprint = controlConstruction === undefined ? owned.footprint(facts)
      : constructor === undefined || controlConstruction.footprint === undefined
        ? controlConstruction(owned, owned.footprint, [facts])
        : controlConstruction.footprint(member.memberIndex, constructor.operationIndex,
          owned, owned.footprint, [facts]);
    if (footprint?.kind !== undefined) {
      if (!footprintKinds.includes(footprint.kind) ||
          !cidPattern.test(footprint.provider_boundary_cid ?? '') ||
          !text(footprint.provider_namespace) ||
          !text(footprint.resource_kind) ||
          !cidPattern.test(footprint.resource_identity_scheme_cid ?? '') ||
          !Array.isArray(footprint.provider_object_identity_cids)) {
        reject('InvalidInstalledRowEffectDriver');
      }
      return {...footprint};
    }
    if (!text(footprint?.providerNamespace) ||
        !text(footprint!.resourceKind) ||
        !cidPattern.test(footprint!.boundaryCid ?? '')) {
      reject('InvalidInstalledRowEffectDriver');
    }
    return {kind: 'opaque', provider_boundary_cid: footprint!.boundaryCid!,
      provider_namespace: footprint!.providerNamespace!,
      resource_kind: footprint!.resourceKind!,
      resource_identity_scheme_cid: cid({
        version: 'actql-installed-row-effect-identity-scheme/0.1',
        connector_registration: connectorRegistration,
        resource: member.resource,
        ...(member.kind === 'command'
          ? {command_cid: contractCidOf(member)}
          : {primary_identity: member.mapping.primaryIdentity})}),
      provider_object_identity_cids: []};
  };

  return footprintOf;
}

export function createInstalledRowEffectPreview<Member extends PreviewMember>({
  moon, permissionsOf, pendingCid, fail,
}: PreviewControls<Member>) {
  // The Preview of the Effect Unit: the common draft with each member's rows
  // (create rows already in canonical order) stated as their exact values,
  // and each update row's observed target, version and before value.
  function authorPreview({control, prepared, inputs, context, requestScope, limits, managedEffect,
    members, rowsOf, capabilities, footprints, payloads}: PreviewInput<Member>) {
    const {maxWireBytes, maxNodes, maxDepth} = limits.preview;
    const requestAuthority = moon.clientProgramEffectRequestAuthority(
      requestScope);
    const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
    const authoring = checked(moon.strategyRunEvidenceSeal(
      'authoring_context', JSON.stringify({
        version: 'actql-authoring-context/0.1',
        program_definition_cid: definitionCid, annotations: []}),
      maxWireBytes, maxNodes, maxDepth));
    const identities: HeldResult[] = [];
    let rowCount = 0;
    const effects = members.map((member, index) => {
      const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
        prepared, member.stageIndex, member.effectId, limits.planWork));
      const source = control.effectSourceArtifactPreviewBinding(
        payloads[index].summary.artifact,
        moon.strategyPublicationContractIdentity(context.runInvocation),
        runtimeField(descriptor, 6), context.storeAuthorityCid);
      const identity = control.issueSourceFreeLocalEffectIdentity(
        prepared, inputs, runtimeField(descriptor, 0) as number, payloads[index].localResultArtifact,
        {maxWork: limits.planWork, maxWireBytes, maxNodes, maxDepth});
      identities.push(identity);
      const rows = rowsOf[index];
      rowCount += rows.length;
      if (rows.length > limits.maxRowsPerMember || rowCount > limits.maxRows) fail('InstalledRowEffectRowLimit');
      const planCid = checked(moon.clientProgramEffectPlanCid(prepared,
        runtimeField(descriptor, 0) as number, limits.maxFields, limits.planWork, maxWireBytes,
        maxNodes, maxDepth));
      return {
        effect_id: runtimeField(descriptor, 1), effect_kind: runtimeField(descriptor, 2),
        target: runtimeField(descriptor, 3),
        ...(member.kind === 'command'
          ? {contract: runtimeField(descriptor, 4), resolved_command_contract_cid: runtimeField(descriptor, 5)}
          : {mapping: runtimeField(descriptor, 4), resolved_mapping_contract_cid: runtimeField(descriptor, 5)}),
        effect_identity_cid: identity.identity,
        source_result: runtimeField(descriptor, 6),
        ...(planCid === undefined ? {} : {effect_plan_logical_cid: planCid}),
        // The identity names the checked semantic Result. Its physical
        // export is bound separately by the existing captured-source owner.
        result_artifact_cid: payloads[index].localResultArtifact.identity,
        preview_strength: 'full_diff',
        source_binding_cid: runtimeField(source, 1),
        capability_evidence_cid: capabilities[index].identity,
        authority_scope_cid: requestAuthority,
        write_footprint: footprints[index],
        count: rows.length, max_items: rows.length,
        required_permissions: permissionsOf(member),
        ...(member.kind === 'command' ? {} : {approval: approvalOf(member)}),
        on_item_failure: runtimeField(descriptor, 7),
        changes: rows.map(row => member.kind === 'create' ? {
          target_row_identity: row.identity,
          target_guard: {state: 'not_applicable'},
          before: {state: 'absent'},
          after: {state: 'present', value: row.entry.value},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : member.kind === 'command' ? {
          target_row_identity: row.entry.target,
          target_guard: {state: 'not_applicable'},
          before: {state: 'not_applicable'}, after: {state: 'not_applicable'},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : member.kind === 'delete' ? {
          target_row_identity: row.entry.target,
          target_guard: {state: 'version', version_cid: row.versionCid},
          before: {state: 'present', value: row.before},
          after: {state: 'absent'},
          intended_changes: {state: 'not_applicable'},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : {
          target_row_identity: row.entry.target,
          target_guard: row.state === 'absent' ? {state: 'not_applicable'}
            : {state: 'version', version_cid: row.versionCid},
          before: row.state === 'absent' ? {state: 'absent'} : {state: 'present', value: row.before},
          after: {state: 'present', value: row.entry.value},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        }),
        row_order: [], effect_member_preview_cid: pendingCid,
        executed: false,
      };
    });
    const draft = {
      version: 'actql-effect-preview/0.1', sensitivity: 'private',
      retention_class: 'authority-evidence', encryption_required: true,
      program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
      program_definition_cid: definitionCid,
      invocation_cid: moon.strategyPublicationContractIdentity(
        context.runInvocation),
      run_identity_cid: moon.strategyPublicationContractIdentity(
        context.runDefinition),
      compiled_plan_cid: moon.strategyPublicationContractIdentity(
        context.compiledPlan),
      check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
      authoring_context: JSON.parse(moon.strategyRunEvidenceJson(authoring)) as AuthoringContext,
      barrier_provenance_cids: [], model_derived: false,
      model_task_contract_cids: [], model_invocation_evidence_cids: [],
      model_response_artifact_cids: [], effects, executed: false,
      effect_preview_cid: pendingCid,
    };
    const draftWire = JSON.stringify(draft);
    if (Buffer.byteLength(draftWire, 'utf8') > maxWireBytes) {
      fail('InstalledRowEffectPreviewByteLimit');
    }
    const canonical = checked(moon.clientProgramCanonicalEffectPreviewDraft(
      draftWire, maxWireBytes, maxNodes, maxDepth)) as string;
    const authoringCid = draft.authoring_context.authoring_context_cid;
    const authored = managedEffect === undefined
      ? checked(moon.clientProgramAuthorEffectPreview(
        canonical, draft.run_identity_cid, authoringCid, requestScope,
        maxWireBytes, maxNodes, maxDepth, members.length, rowCount,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth))
      : checked(managedEffect.controlConstruction(moon, moon.clientProgramAuthorInstalledEffectPreview, [
        managedEffect.value, prepared, managedEffect.request, managedEffect.operationPlan,
        managedEffect.definitionOriginal.allowed, context.runDefinition, context.runInvocation,
        canonical, draft.run_identity_cid, authoringCid, requestScope,
        maxWireBytes, maxNodes, maxDepth, members.length, rowCount,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth]));
    control.checkSourceFreeLocalEffectPreviewIdentities(prepared, inputs,
      runtimeField(authored, 0) as string, draft.run_identity_cid, authoringCid, identities,
      {maxWireBytes, maxNodes, maxDepth});
    return Object.freeze({wire: runtimeField(authored, 0) as string, authoringCid,
      keys: runtimeField(authored, 1) as readonly (readonly unknown[])[]});
  }

  return authorPreview;
}
