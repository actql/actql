import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {prepareInstalledEffectResultProgress} from './effect-result-work.mjs';
// Whole-Relation Table projections for the existing installed Effect Site.
// The common Run, Checkpoint, capture, Ledger, apply and publication owners
// remain authoritative. A Table member is one operation, including zero rows.
import {runtimeField, runtimeOptionalField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {checkedTableWriteBinding, verifyTableWriteBinding} from './table-write-binding.mjs';
import {mkdir} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
// @ts-expect-error TS7016: the Common runtime facade still has a JavaScript entry.
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {issueCompletedEffectfulComputationEvidence,
  releaseCompletedRunPreparedPayloads, releasePreparedResults, storeCompletedRunResultSet,
  prepareCompletedEffectfulPublication}
  from '../host-common/completed-run-publication.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
// @ts-expect-error TS7016: the installed Row Effect still has a JavaScript entry.
import {installedRowEffectUnit} from './installed-row-effect.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from './installed-effect-recipe-construction.mjs';
import {prepareInstalledEffectManagedPlan} from './installed-effect-managed-plan.mjs';
import {preparePinnedEffectSourceSet, preparePinnedEffectSourceHoldings,
  retainPinnedEffectDependencyPayloads}
  // @ts-expect-error TS7016: the Effect source export owner still has a JavaScript entry.
  from './effect-input-export.mjs';
import {authorTableOperationPreview} from './table-operation-preview.mjs';
import {capturedTableRecoveryRecord, prepareRecoveredTableInput}
  from './table-capture-recovery.mjs';
import {prepareCapturedTableCommit, prepareRecoveredTableCommit,
  bindApprovedTableCommitDispatch, refreshCapturedTableTargets,
  cleanupCapturedTableCommit} from './table-commit-apply.mjs';
import {reconcileOriginalTableCommit} from './table-commit-reconciliation.mjs';
// @ts-expect-error TS7016: the durable Effect Ledger still has a JavaScript entry.
import {openEffectLedger} from './effect-ledger.mjs';
import {localContractLimits} from './local-publication-limits.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction, closeInstalledSourceConstruction}
  from './installed-host-services.mjs';

import type {createNodeAuthorizationGate} from './authorization.mjs';
import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';
import type {applyCapturedEffectSet} from './effect-run-apply.mjs';

type PreviewOptions = Parameters<typeof authorTableOperationPreview>[0];
type PreviewContext = Omit<PreviewOptions['context'], 'storeAuthorityCid'>;
type CaptureResult = Parameters<typeof storeCompletedRunResultSet>[0];
type IssueCapture = Parameters<typeof issueCompletedEffectfulComputationEvidence>[0];
type DurableOptions = Parameters<typeof prepareRecoveredTableInput>[0];
type DispatchOwner = Parameters<typeof bindApprovedTableCommitDispatch>[0];
type DispatchFacts = Parameters<typeof bindApprovedTableCommitDispatch>[1];
type PhysicalOptions = Parameters<typeof prepareCapturedTableCommit>[0];
type ReconcileOptions = Parameters<typeof reconcileOriginalTableCommit>[0];
type Apply = Parameters<typeof applyCapturedEffectSet>[0];
type Publication = Parameters<typeof import('../host-common/completed-run-publication.mjs').publishCompletedEffectfulRun>[0];
type EffectControl = Pick<ReturnType<typeof effectApplicationControl>, 'logicalItemLocator' | 'ledgerBasis' |
  'admitPreviewIdentity' | 'recoveredPreviewKeys' | 'setFrontierReadyCount' | 'setFrontierReadyMember'>;
type Gate = Awaited<ReturnType<typeof createNodeAuthorizationGate>>;
type Decision = Awaited<ReturnType<Gate['authorize']>>;
type Bridge = PhysicalOptions['bridge'] & DurableOptions['bridge'] & PreviewOptions['bridge'] &
  ReconcileOptions['bridge'] & Pick<ReturnType<typeof createIcebergPhysicalBridge>, 'supportsOperation'> &
  Partial<Pick<ReturnType<typeof createIcebergPhysicalBridge>, 'frameLimits' | 'effectPlanConstruction'>>;
type InstalledTarget = PreviewOptions['members'][number]['target'] & Readonly<{
  effectId: string; resource: string; queryName?: string; installationBindingCid: string;
}>;
type Unit = Readonly<{programId: string; stageId: string; stageIndex: number; effectIds: readonly string[]}>;
type Keys = NonNullable<ReturnType<typeof authorTableOperationPreview>['keys']>;
type Binding = Parameters<typeof capturedTableRecoveryRecord>[0];
type Control = CaptureResult['control'] & IssueCapture['control'] & DurableOptions['control'] &
  PreviewOptions['control'] & DispatchOwner['control'] & PhysicalOptions['control'] & Binding['control'] &
  Readonly<{
    effectComputationPreviewWire(preview: IssueCapture['preview']): string;
    bindCheckedInstalledEffectSourceFreeInvocation(parent: unknown, prepared: unknown,
      request: unknown, operationPlan: unknown, checkedHost: unknown, admission: unknown,
      runDefinition: unknown, sourceFreeInvocation: unknown): unknown;
  }>;
type Member = DispatchFacts['members'][number];
type Ledger = DispatchOwner['ledger'] & ReconcileOptions['ledger'] & Apply['ledger'] & Readonly<{
  close(): unknown;
  frontierFromDurableHeads(preview: unknown, members: readonly Member[], maxWork: number): unknown;
  recoverClaimFacts(facts: Readonly<{preview: unknown; scope: unknown; programId: string;
    nodeId: string; maxRows: number; maxWork: number}>): Readonly<{members: readonly Member[]}>;
}>;
type PlanBuilder = Parameters<typeof prepareInstalledEffectManagedPlan>[0];
type PhysicalPlanBuilder = Parameters<typeof prepareInstalledPhysicalWritePlanRecipe>[0];
type Runtime = PreviewOptions['moon'] & Apply['moon'] & PlanBuilder['moon'] & PhysicalPlanBuilder['moon'] & Readonly<{
  clientProgramEffectCompilationPlanWire(compilation: unknown): string;
  clientProgramEffectCompilationCompiledPlanWire(compilation: unknown): string;
  clientProgramEffectInputExportLimits(...limits: number[]): unknown;
  clientProgramEffectApplyCapabilityFromCodes(cid: string, route: number, idempotency: number,
    confirmation: number, readBack: boolean, reconciles: boolean, operation: number, rows: number): unknown;
  clientProgramEffectRequestScope(prepared: unknown, identity: unknown): unknown;
  clientProgramInstalledEffectDependencySourcesPin(parent: unknown, prepared: unknown, identity: unknown,
    plan: unknown, checkedHost: unknown, maxResults: number): unknown;
  clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation: string, capacity: unknown,
    bytes: bigint, staged: boolean): unknown;
  clientProgramPinEffectSources(host: unknown, maxResults: number): unknown;
  clientProgramReleaseEffectInputs(inputs: unknown): unknown;
  clientRequestAuthorityScopeCid(identity: unknown): string;
  clientRequestCallerId(identity: unknown): string;
  strategyPublicationAdmit(name: string, wire: string, bytes: number, nodes: number, depth: number): unknown;
}>;
type OutputLimits = Readonly<Record<'maxResultFields' | 'maxResultMappingWork' | 'maxResultOrderWork' |
  'maxResultWorkspaceEntries' | 'maxRows' | 'maxValueNodes' | 'maxValueTextBytes' | 'maxValueDepth' |
  'maxValueWork' | 'maxWireBytes' | 'maxWireNodes' | 'maxWireDepth' | 'maxColumns' | 'maxOrderWork' |
  'maxLogicalWireBytes' | 'maxLogicalWireNodes' | 'maxLogicalWireDepth' | 'maxSchemaFields' |
  'maxSchemaBytes' | 'maxSchemaNodes' | 'maxSchemaDepth' | 'maxBatchBytes', number>>;
type Limits = {[K in keyof typeof defaults]: typeof defaults[K] extends object
  ? {[Field in keyof typeof defaults[K]]: number} : number};
type LimitOverrides = Readonly<Partial<{[K in keyof Limits]: Partial<Limits[K]>}>>;
type InstallOptions = Readonly<{
  moon: Runtime; environmentWire: string; sourceInitialization?: object; environment?: Readonly<{wire: string}>;
  connectorId: string; connectorRegistration: string; connectorRevision: string; connection: string;
  runtimeBundleCid: string; bindingCid: string; catalogCid: string; targets: readonly unknown[];
  bridge: Bridge; authorization: Pick<Gate, 'authorize'> & Readonly<{close?(): boolean}>;
  ledgerRoot: string; limits?: LimitOverrides;
}>;
type Plan = Pick<CaptureResult, 'runDefinition' | 'invocation' | 'results' | 'contractLimits'> &
  Pick<IssueCapture, 'admission' | 'observation' | 'normalizationJournal' | 'receiptEvidence' | 'captureEvidence'> &
  Pick<Publication, 'request' | 'attempt' | 'now'> & Readonly<{
    outputLimits: OutputLimits; invocationOwner: unknown; effectInputRetention: Readonly<{identity: string}>;
    localEvidenceContext?: unknown; sourceFreeInvocationOriginal?: unknown;
  }>;
type CapturedFacts = Readonly<{
  moon: Runtime; control: Control; store: CaptureResult['store']; execution: CaptureResult['execution'];
  checkedHost: unknown; prepared: unknown; identity: unknown; compilation: unknown; unit?: Unit;
  definition?: unknown; publicationPlan?: Plan; plan?: Plan; previewContext?: PreviewContext;
  managedEffect?: Parameters<typeof prepareInstalledEffectResultProgress>[0] & Readonly<{controlConstruction?: unknown}>;
  signal?: AbortSignal;
}>;
type StoredProvider = Readonly<{
  version: string; binding_cid: string; program_id: string; stage_id: string;
  members: readonly Readonly<{effect_id: string; mapping_cid: string}>[];
  request: Publication['request']; attempt: Publication['attempt'];
}>;
type RecoveryFacts = Readonly<{
  moon: Runtime; control: Control; store: CaptureResult['store'];
  recovered: Readonly<{requestIdentity: unknown; requestScope: unknown; computation: DurableOptions['recovered'];
    recoveryResources?: DurableOptions['recoveryResources']}>;
  continuation: (Partial<StoredProvider> & Readonly<{provider?: StoredProvider}>) | undefined;
  retainRecoveryOwner?: (owner: CleanupOwner) => unknown; signal?: AbortSignal;
}>;
type Operation = Readonly<{request_cid: string; catalog_identity_cid: string; action: string;
  table_name: string; namespace: readonly string[]; expected_table: unknown; schema_cid: string}>;
type PreviewBody = Readonly<{
  run_identity_cid: string; authoring_context: Readonly<{authoring_context_cid: string}>;
  effects: readonly Readonly<{
    source_binding_cid: string; effect_member_preview_cid: string; effect_id: string; effect_kind: string;
    target: string; mapping: string; resolved_mapping_contract_cid: string; source_result?: string;
    source_table_input?: string; capability_evidence_cid: string;
    changes: readonly Readonly<{intended_changes: Readonly<{value: Operation}>; row_preview_cid: string}>[];
  }>[];
}>;
type Schema = Awaited<ReturnType<CaptureResult['store']['putPreparedResultSchema']>>['prepared'];
type Material = Awaited<ReturnType<typeof prepareCapturedTableCommit>>;
type CleanupOwner = Readonly<{
  materials: (Material | undefined)[]; schemas: (Schema | undefined)[];
  setLedger(value: Ledger): void; close(): Promise<void>; cleanup(): Promise<boolean>; cleanupPending(): boolean;
}>;
type StagedResults = Parameters<typeof prepareCompletedEffectfulPublication>[0]['storedResults'];
type Stage<Results extends StagedResults> = Pick<Publication, 'request' | 'attempt' | 'now' | 'contractLimits'> & Readonly<{
  control: Control; store: CaptureResult['store']; execution: CaptureResult['execution'] | null;
  storedResults: Results; computation: DurableOptions['recovered']['computation'];
  preview: IssueCapture['preview']; applyPreview: unknown; ledger: Ledger; body: PreviewBody;
  members: readonly Member[]; scopes: DispatchOwner['scopes']; owner: CleanupOwner; continuationWire: string;
}>;
type SourceInventory = Readonly<{
  members: readonly Readonly<{payload: PreviewOptions['members'][number]['payload']}>[];
  payloads: readonly Readonly<{prepared: Schema}>[];
  dependencies?: unknown;
}>;
type RetainedSources = Readonly<{
  holdings: IssueCapture['effectSourceHoldings'];
  commit(): Promise<IssueCapture['effectSourceHoldings']>;
}>;
type OperationSlot = Readonly<{operation: string; extent: unknown}>;
type ManagedRecipe = Readonly<{memberOperations: readonly OperationSlot[]; rowOperations: readonly OperationSlot[]}>;

const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const hash = (value: unknown) => `sha256:${createHash('sha256').update(wire(value)).digest('hex')}`;
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const cid = (value: unknown) => /^sha256:[0-9a-f]{64}$/u.test((value ?? '') as string);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0;
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const exportLimits = (o: OutputLimits) => [o.maxResultFields, o.maxResultMappingWork,
  o.maxResultOrderWork, o.maxResultWorkspaceEntries, o.maxRows, o.maxValueNodes,
  o.maxValueTextBytes, o.maxValueDepth, o.maxValueWork, o.maxWireBytes,
  o.maxWireNodes, o.maxWireDepth, o.maxColumns, o.maxOrderWork,
  o.maxLogicalWireBytes, o.maxLogicalWireNodes, o.maxLogicalWireDepth,
  o.maxSchemaFields, o.maxSchemaBytes, o.maxSchemaNodes, o.maxSchemaDepth,
  o.maxBatchBytes];
const defaults = Object.freeze({
  maxMembers: 16, maxPinnedResults: 64, maxFields: 100, planWork: 10000,
  maxWork: 10000, maxFrontierWork: 1000, maxRevisions: 100,
  maxInputBytes: 1000000, maxEntryBytes: 1000000,
  preview: {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64},
  // Table operation/receipt admission has a smaller closed envelope than the
  // containing Effect Preview. These bounds also admit storage mappings.
  material: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 16, maxWork: 10000},
  key: {maxBytes: 4096, maxNodes: 64, maxDepth: 8},
  locator: {maxBytes: 4096},
  entry: {maxWireBytes: 1000000, maxNodes: 1000, maxDepth: 32},
  reservation: {bytes: 16777216, files: 64},
});

// Installation and runtime use the same finite budget vocabulary. A typo must
// not silently select a default, including inside a nested physical budget.
export function checkInstalledTableEffectLimits(supplied: unknown = {}): LimitOverrides {
  const object = (value: unknown): value is Readonly<Record<string, unknown>> => value !== null && typeof value === 'object' &&
    !Array.isArray(value);
  if (!object(supplied) || Object.keys(supplied).some(key => !Object.hasOwn(defaults, key))) {
    fail('InvalidInstalledTableEffectLimits');
  }
  for (const [key, value] of Object.entries(supplied)) {
    const model = defaults[key as keyof Limits];
    if (typeof model === 'object'
      ? !object(value) || Object.entries(value).some(([name, bound]) =>
        !Object.hasOwn(model, name) || !positive(bound))
      : !positive(value)) fail('InvalidInstalledTableEffectLimits');
  }
  if (Object.entries(supplied.material as LimitOverrides['material'] ?? {}).some(([key, bound]) =>
    bound > (key === 'maxWork' ? 2147483647 : defaults.material[key as keyof Limits['material']]))) {
    fail('InvalidInstalledTableEffectLimits');
  }
  return supplied as LimitOverrides;
}

// `targets` are explicit installed member/Mapping bindings, not a Program's request
// for an arbitrary Catalog/name. Each binding fixes create or an approved
// replacement generation. Publication/republication of those bindings belongs
// to the installation loader, separately from these runtime hooks.
export async function createInstalledTableEffect({moon, environmentWire, sourceInitialization, environment,
  connectorId, connectorRegistration, connectorRevision, connection,
  runtimeBundleCid, bindingCid, catalogCid, targets, bridge, authorization,
  ledgerRoot, limits: suppliedLimits = {}}: InstallOptions) {
  if (sourceInitialization !== undefined) {
    assertInstalledSourceConstruction(sourceInitialization, undefined, undefined, environment);
    if (environment?.wire !== environmentWire) fail('ForeignInstalledSourceConstruction');
  }
  checkInstalledTableEffectLimits(suppliedLimits);
  const limits = Object.freeze(Object.fromEntries(Object.entries(defaults)
    .map(([key,value]) => [key, typeof value === 'object'
      ? Object.freeze({...value, ...suppliedLimits[key as keyof Limits] as object})
      : suppliedLimits[key as keyof Limits] ?? value]))) as Limits;
  if (!moon || ![environmentWire, connectorId, connectorRegistration,
    connectorRevision, connection, ledgerRoot].every(text) ||
    ![runtimeBundleCid, bindingCid, catalogCid].every(cid) ||
    !Array.isArray(targets) || targets.length === 0 ||
    typeof authorization?.authorize !== 'function' ||
    !['prepareWrite','execute','inspect','cleanup','status','reconcileOperation',
      'projectCommitResponse','issueStorageMapping','admitStorageMapping','supportsOperation']
      .every(name => typeof bridge?.[name as keyof Bridge] === 'function') ||
    Object.values(limits).some(value => typeof value === 'object'
      ? Object.values(value).some(bound => !positive(bound)) : !positive(value))) {
    fail('InvalidInstalledTableEffect');
  }
  const installed = Object.freeze(targets.map((value: unknown) => {
    // Copy installation metadata before any physical or authorization await.
    const target = JSON.parse(wire(value)) as Omit<InstalledTarget, 'capabilityCid' | 'installationBindingCid'>;
    if (target.queryName !== undefined && (!text(target.queryName) || target.queryName.length > 1024) ||
      !text(target.effectId) || !text(target.resource) || !text(target.targetRef) ||
      !text(target.mappingRef) || !cid(target.mappingCid) ||
      target.catalogCid !== catalogCid || !['create','replace'].includes(target.action) ||
      !Array.isArray(target.namespace) || target.namespace.length === 0 ||
      !target.namespace.every(text) || !text(target.tableName) ||
      target.action === 'create' && target.expectedTable !== null ||
      target.action === 'replace' && (!text(target.expectedTable?.table_uuid) ||
        !cid(target.expectedTable?.generation_cid)) ||
      !Array.isArray(target.permissions) || target.permissions.length === 0 ||
      !target.permissions.every(text) ||
      new Set(target.permissions).size !== target.permissions.length || !target.footprint) {
      fail('InvalidInstalledTableTarget');
    }
    // The current captured input consumer is Relation-only. The selected
    // Connector declares whether this operation/kind is actually implemented;
    // admitting an opaque mapping never supplies that capability or authority.
    if (bridge.supportsOperation({action: target.action, kind: 'relation'}) !== true) {
      fail('UnsupportedTableCarrierOperation');
    }
    const capabilityCid = hash({version: 'actql-installed-table-capability/0.1',
      connector_registration: connectorRegistration, connector_revision: connectorRevision,
      runtime_bundle_cid: runtimeBundleCid, binding_cid: bindingCid,
      connection, target, input_kind: 'relation', route: 'single_serial', idempotency: 'unavailable'});
    return Object.freeze({...target, capabilityCid, installationBindingCid: bindingCid});
  }));
  if (new Set(installed.map(target => wire([target.effectId, target.mappingRef]))).size !== installed.length) {
    fail('DuplicateInstalledTableMapping');
  }
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  const effect: EffectControl = runtimeCore(moon).effectApplicationControl;
  const openLedger = (identity: unknown): Ledger => openEffectLedger({moon, root: ledgerRoot,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
    callerRequestId: moon.clientRequestCallerId(identity), maxEntryBytes: limits.maxEntryBytes});
  const resolve = (descriptor: unknown, capabilityCid: unknown) => {
    const target = installed.find(target => (capabilityCid === undefined
      ? target.effectId === runtimeField(descriptor, 1) : target.capabilityCid === capabilityCid) && target.targetRef === runtimeField(descriptor, 3) &&
      target.mappingRef === runtimeField(descriptor, 4) && target.mappingCid === runtimeField(descriptor, 5));
    if (runtimeField(descriptor, 2) !== 'store' ||
        (runtimeField(descriptor, 6) === undefined) === (runtimeField(descriptor, 8) === undefined) || target === undefined) {
      fail('InstalledTableMappingNotInstalled');
    }
    return target;
  };
  const scopesOf = (targets: readonly InstalledTarget[]) => Object.freeze(targets.map(target =>
    Object.freeze({connection, resource: target.resource})));
  let managedRecipe: ManagedRecipe | undefined;
  const prepareManagedPlan = (facts: PlanBuilder['facts'] & Pick<CapturedFacts, 'compilation'>,
    inputs: PlanBuilder['inputs']): unknown => {
    const unit: Unit = installedRowEffectUnit(moon, facts?.compilation);
    if (unit.effectIds.length === 0 || unit.effectIds.length > limits.maxMembers) {
      fail('InstalledTableUnitUnsupported');
    }
    const members = unit.effectIds.map(effectId => {
      const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
        facts.prepared, unit.stageIndex, effectId, limits.planWork));
      const binding = checkedTableWriteBinding(moon, facts.prepared, unit.stageIndex,
        effectId, limits.planWork);
      verifyTableWriteBinding(resolve(descriptor, runtimeOptionalField(binding, 4)), binding);
      return {effectId, memberIndex: runtimeField(descriptor, 0) as number};
    }).sort((a, b) => a.memberIndex - b.memberIndex);
    if (members.some((member, index) => member.memberIndex !== index)) fail('InstalledTableUnitUnsupported');
    if (managedRecipe === undefined) {
      const frame = bridge.frameLimits;
      if (!frame || ![frame.maxBytes, frame.maxNodes, frame.maxDepth, limits.maxInputBytes,
        limits.maxEntryBytes, ...Object.values(limits.preview)]
        .every(value => positive(value) && value <= 2147483647) ||
        2 * (frame.maxBytes + 4) > 2147483647) {
        fail('InstalledTableConstructionUnavailable');
      }
      const recipe = prepareInstalledPhysicalWritePlanRecipe({moon, operation: 'table.commit',
        inputLimits: {body: {maxBytes: limits.maxInputBytes,
          maxNodes: limits.maxInputBytes, maxDepth: limits.preview.maxDepth}, preview: limits.preview},
        limits: {maxRequestBytes: frame.maxBytes, maxRecoveryBytes: limits.maxEntryBytes,
          maxResponseBytes: limits.material.maxWireBytes, maxOutcomeBytes: limits.maxEntryBytes,
          maxTransferBytes: 2 * (frame.maxBytes + 4)}, construction: bridge.effectPlanConstruction});
      // A Table member dispatches ONE whole Relation, even for zero input
      // rows. Only capture storage follows Core's checked row inventory. Its
      // request, physical operation and saved controls occur once per member;
      // copying the ordinary row-operation slots would invent extra sends.
      const controls = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
        'table.commit.controls', recipe.controlsPerRow, 0n, false));
      managedRecipe = Object.freeze({memberOperations: Object.freeze([
        ...recipe.memberOperations, ...recipe.rowOperations,
        Object.freeze({operation: 'table.commit.controls', extent: controls}),
      ]), rowOperations: Object.freeze([])});
    }
    // The existing Request adopts this complete Plan and grows its SAME
    // Ledger before capture construction. Keep all selected upper extents
    // until normal managed-Run retirement, including failed construction.
    return prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members,
      recipeFor: () => managedRecipe});
  };
  const capabilityRoute = (target: InstalledTarget) => checked(moon.clientProgramEffectApplyCapabilityFromCodes(
    target.capabilityCid, 0, 0, 0, true, true, 2, 1));
  const preflightOf = (body: PreviewBody, targets: readonly InstalledTarget[], requestScope: unknown, keys?: Keys) => ({
    proofs: [], sources: body.effects.map(member => member.source_binding_cid),
    contracts: targets.map(target => target.mappingCid),
    capabilities: targets.map(target => target.capabilityCid),
    authorities: targets.map(() => moon.clientProgramEffectRequestAuthority(requestScope)),
    observedRows: [], guardVersions: [], routes: targets.map(capabilityRoute),
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '', policyCid: '',
    validityCid: '', issuerCid: '', authenticationCid: '', issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}), maxMembers: targets.length,
    maxRows: targets.length, maxFootprintWork: limits.maxWork, maxWork: limits.maxWork,
  });

  // Cleanup tracks handles, not Run states. Failed close stays pending under
  // the same Site custody. Never clean another process's uncertain staging.
  const cleanupOwner = (): CleanupOwner => {
    let ledger: Ledger | undefined, closed = false, disposed = false;
    let flight: Promise<boolean> | undefined;
    const materials: (Material | undefined)[] = [];
    const schemas: (Schema | undefined)[] = [];
    const drain = async () => {
      if (disposed) return true;
      for (let index=0; index<materials.length; index++) {
        const prepared = materials[index];
        if (prepared === undefined) continue;
        const result = await cleanupCapturedTableCommit({prepared});
        if (result?.ok !== true || result.result?.pending !== false) return false;
        // Drop verified-clean handles so their physical input arrays can leave
        // the existing WeakMap custody, without disposing another input.
        materials[index] = undefined;
      }
      for (let index=0; index<schemas.length; index++) {
        const prepared = schemas[index];
        if (prepared === undefined) continue;
        await prepared.release();
        if (prepared.status().pending) return false;
        schemas[index] = undefined;
      }
      if (ledger && !closed) { ledger.close(); closed = true; }
      disposed = true;
      return true;
    };
    const owner = Object.freeze({
      materials,
      schemas,
      setLedger(value: Ledger) { if (ledger) fail('TableLedgerAlreadyOwned'); ledger = value; },
      async close() {},
      cleanup() {
        // Concurrent close/retry uses the same physical cleanup flight.
        if (flight === undefined) flight = drain().finally(() => { flight = undefined; });
        return flight;
      },
      cleanupPending: () => !disposed &&
        (materials.some(Boolean) || schemas.some(Boolean) || Boolean(ledger && !closed)),
    });
    return owner;
  };
  const dispose = (owner: CleanupOwner) => async () => {
    if (!await owner.cleanup()) fail('TableCleanupPending');
  };
  const useCid = (kind: string, body: PreviewBody, subjectCid: string | undefined, decisions: readonly Decision[]) => hash({
    version: 'actql-installed-table-use/0.1', kind, binding_cid: bindingCid,
    subject_cid: subjectCid,
    request_cids: body.effects.map(member => member.changes[0].intended_changes.value.request_cid),
    decisions: decisions.map(value => ({boundary: value.boundary, subject: value.subjectCid,
      configuration_cid: authorizationDispatchFacts(value)?.configurationCid ?? null,
      principal: authorizationDispatchFacts(value)?.principal ?? null,
      checkpoint_cid: value.checkpointCid ?? null, resolution_cid: value.resolutionCid ?? null})),
  });
  const dispatchBinder = (control: Control, ledger: Ledger, owner: CleanupOwner,
    body: PreviewBody, scopes: DispatchOwner['scopes']) => (binding: DispatchFacts) => {
    // This identity records actual current approval use; it grants nothing.
    // bindApprovedTableCommitDispatch admits the opaque dispatch decisions.
    return bindApprovedTableCommitDispatch({control, ledger, prepared: owner.materials,
      scopes, credentialUseCid: useCid('commit', body, binding.subjectCid,
        binding.decisions ?? []), limits: limits.material}, binding);
  };
  const claimsOf = (body: PreviewBody, keys: Keys, requestScope: unknown, unit: Unit, retentionId: string) =>
    body.effects.map((member,index) => {
      const operation = member.changes[0].intended_changes.value;
      const locator = effect.logicalItemLocator(requestScope, unit.programId, unit.stageId,
        member.effect_id, wire(operation.request_cid), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const unitCid = hash({version: 'actql-installed-table-unit/0.1',
        run_definition_cid: body.run_identity_cid, stage_id: unit.stageId});
      const recoveryCid = hash({version: 'actql-installed-table-recovery/0.1',
        request_cid: operation.request_cid});
      const basis = effect.ledgerBasis(requestScope, locator, keys[index][0], unitCid,
        member.effect_member_preview_cid, member.changes[0].row_preview_cid,
        operation.request_cid, recoveryCid, 'unavailable', member.capability_evidence_cid,
        retentionId);
      return {claims: [{scope: requestScope, locator, key: keys[index][0], basis,
        intentFingerprintCid: member.changes[0].row_preview_cid,
        canonicalRequestCid: operation.request_cid}]};
    });
  const commonStage = <Results extends StagedResults>({control, store, execution, storedResults, computation,
    preview, applyPreview, ledger, body, members, scopes, owner,
    request, attempt, contractLimits, now, continuationWire}: Stage<Results>) => ({
    preview, computation, storedResults,
    receipt: {ledger, preview: applyPreview, commonMoon: moon, publicationPreview: preview,
      authorizeEvidenceRead: async () => true,
      members: members.map(member => ({rowOwners: member.claims.map(claim => ({claim})),
        replayed: execution === null})), limits: contractLimits},
    publication: {execution, store, storedResults, control, computation, preview, ledger,
      request, attempt, contractLimits, now},
    scopes, continuationWire, cleanupOwner: owner, dispose: dispose(owner),
  });

  async function prepareCaptured(facts: CapturedFacts) {
    const {moon: runMoon, control, store, execution, checkedHost, prepared,
      identity, compilation, signal} = facts ?? {};
    const plan = facts?.publicationPlan ?? facts?.plan;
    if (runMoon !== moon || !plan || !execution || !checkedHost || !prepared || !identity) {
      fail('InvalidInstalledTableCapture');
    }
    signal?.throwIfAborted();
    // This initial source-free authoring profile does not invent Model barrier
    // provenance. A Model-derived Table needs that existing owner's connection.
    if (plan.receiptEvidence?.modelEvidence?.length || plan.captureEvidence?.modelEvidence?.length) {
      fail('InstalledTableModelProvenanceUnsupported');
    }
    const managedEffect = facts.managedEffect;
    const dependencyConstruction = managedEffect?.controlConstruction;
    if (managedEffect !== undefined && typeof dependencyConstruction !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    // The existing managed Run supplies the same registered late Catalog
    // constructor used by row Effects. A copied shape or equal CID cannot
    // lend another parent, checked preparation, Request or operation Plan.
    const dependencyOriginal = managedEffect === undefined ? undefined
      : installedEffectDependencyOriginal(dependencyConstruction, moon);
    if (dependencyOriginal !== undefined &&
        (dependencyOriginal.parent !== managedEffect!.value ||
          dependencyOriginal.prepared !== prepared || dependencyOriginal.request !== identity ||
          dependencyOriginal.plan !== managedEffect!.operationPlan)) {
      fail('ForeignInstalledEffectManagedRun');
    }
    if (dependencyOriginal !== undefined && plan.sourceFreeInvocationOriginal !== undefined) {
      control.bindCheckedInstalledEffectSourceFreeInvocation(dependencyOriginal.parent,
        prepared, identity, dependencyOriginal.plan, checkedHost, plan.admission,
        plan.runDefinition, plan.sourceFreeInvocationOriginal);
      dependencyOriginal.current();
    }
    const unit: Unit = facts.unit ?? installedRowEffectUnit(moon, compilation);
    const descriptors = unit.effectIds.map(effectId => ({effectId,
      descriptor: checked(moon.clientProgramEffectMemberDescriptor(prepared,
        unit.stageIndex, effectId, limits.planWork))})).sort((a,b) => (runtimeField(a.descriptor, 0) as number)-(runtimeField(b.descriptor, 0) as number));
    if (!descriptors.length || descriptors.length > limits.maxMembers ||
      descriptors.some((entry,index) => runtimeField(entry.descriptor, 0) !== index)) fail('InstalledTableUnitUnsupported');
    const targets = descriptors.map(entry => {
      const binding = checkedTableWriteBinding(moon, prepared, unit.stageIndex,
        entry.effectId, limits.planWork);
      const target = resolve(entry.descriptor, runtimeOptionalField(binding, 4));
      verifyTableWriteBinding(target, binding);
      return target;
    });
    const requestScope = moon.clientProgramEffectRequestScope(prepared, identity);
    const context = facts.previewContext ?? {runDefinition: facts.definition,
      runInvocation: plan.invocationOwner,
      compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
        plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes, plan.contractLimits.maxDepth))};
    const resultProgress = managedEffect === undefined ? undefined
      : prepareInstalledEffectResultProgress(managedEffect, checkedHost);
    const storedResults = (await storeCompletedRunResultSet({execution, store, control,
      runDefinition: plan.runDefinition, invocation: plan.invocation, results: plan.results,
      outputLimits: plan.outputLimits, contractLimits: plan.contractLimits,
      signal, resultProgress}))!;
    const owner = cleanupOwner();
    let inputs: unknown, sources: SourceInventory | undefined, releasedInputs = false;
    const releaseInputs = () => {
      if (inputs && !releasedInputs) {
        moon.clientProgramReleaseEffectInputs(inputs); releasedInputs = true;
      }
    };
    try {
      inputs = dependencyOriginal === undefined
        ? checked(moon.clientProgramPinEffectSources(checkedHost, limits.maxPinnedResults))
        : checked(moon.clientProgramInstalledEffectDependencySourcesPin(dependencyOriginal.parent,
          prepared, identity, dependencyOriginal.plan, checkedHost, limits.maxPinnedResults));
      dependencyOriginal?.current();
      sources = await preparePinnedEffectSourceSet({moon, checkedOwner: prepared,
        dependencyConstruction,
        execution, inputs, maxMembers: descriptors.length,
        // Counts bound inventories; the existing Host work policy bounds
        // grouping and checked dependency-import correspondence across Units.
        maxGroupingWork: limits.maxWork,
        limits: moon.clientProgramEffectInputExportLimits(...exportLimits(plan.outputLimits)),
        store, control, maxBytes: limits.maxInputBytes, invocation: plan.invocation,
        retention: plan.effectInputRetention, contractLimits: plan.contractLimits,
        localEvidenceContext: plan.localEvidenceContext,
        sourceBindingCid: hash({version: 'actql-installed-local-table-source/0.1',
          run_invocation_cid: plan.invocation.identity, store_authority_cid: store.storeAuthorityCid}), signal}) as SourceInventory;
      if (sources.dependencies !== undefined) retainPinnedEffectDependencyPayloads({sources,
        execution, store, storedResults, control, runDefinition: plan.runDefinition});
      const authored = authorTableOperationPreview({moon, control, prepared, inputs, bridge,
        checkedHost, requestScope, context: {...context, storeAuthorityCid: store.storeAuthorityCid},
        members: descriptors.map((entry,index) => ({stageIndex: unit.stageIndex,
          effectId: entry.effectId, payload: sources!.members[index].payload, target: targets[index]})), limits});
      const body = JSON.parse(authored.wire) as PreviewBody;
      const authoringContext = control.admitRunEvidence('authoring_context',
        wire(body.authoring_context), plan.contractLimits);
      const preview = control.admitEffectComputationPreview(authored.wire,
        plan.runDefinition, authoringContext, plan.contractLimits);
      const retained: RetainedSources = preparePinnedEffectSourceHoldings({sources, store, control, preview,
        invocation: plan.invocation,
        resultArtifacts: sources.members.map(member => member.payload.localResultArtifact)});
      await retained.commit();
      const computation = await issueCompletedEffectfulComputationEvidence({execution,
        store, storedResults, control, admission: plan.admission,
        runDefinition: plan.runDefinition, invocation: plan.invocation,
        observation: plan.observation, normalizationJournal: plan.normalizationJournal,
        authoringContext, receiptEvidence: plan.receiptEvidence,
        captureEvidence: plan.captureEvidence, preview, plans: [], effectSourceHoldings: retained.holdings,
        connectorRecovery: authored.tableInputs.map((tableInput,index) =>
          capturedTableRecoveryRecord({control, tableInput, tablePreview: authored.tablePreviews[index]})),
        contractLimits: plan.contractLimits, signal});
      for (const [index,holding] of retained.holdings.entries()) {
        // A private input schema differs from the public Result projection.
        // Keep its exact checked bytes under the existing Store schema lease;
        // public publication adopts it, or the same cleanup owner releases it.
        const schema = await store.putPreparedResultSchema(
          control.tableInputSchemaWire(authored.tableInputs[index]),
          authored.operations[index].schema_cid, plan.runDefinition.identity);
        owner.schemas.push(schema.prepared);
        owner.materials.push(await prepareCapturedTableCommit({control, store, holding,
          tableInput: authored.tableInputs[index], identity: authored.identities[index],
          tablePreview: authored.tablePreviews[index], bridge, reservation: limits.reservation,
          maxBytes: limits.maxInputBytes, limits: limits.material, signal}));
      }
      for (const payload of sources.payloads) if (payload.prepared.status().pending) await payload.prepared.release();
      const ledger = openLedger(identity);
      owner.setLedger(ledger);
      const applyPreview = effect.admitPreviewIdentity(authored.wire, body.run_identity_cid,
        authored.authoringCid, requestScope, authored.keys, limits.preview.maxWireBytes,
        limits.preview.maxNodes, limits.preview.maxDepth);
      const members = claimsOf(body, authored.keys, requestScope, unit, plan.effectInputRetention.identity);
      const scopes = scopesOf(targets);
      const continuationWire = wire({version: 'actql-installed-table-continuation/0.1',
        binding_cid: bindingCid, program_id: unit.programId, stage_id: unit.stageId,
        request: plan.request, attempt: plan.attempt,
        members: body.effects.map(member => ({effect_id: member.effect_id,
          mapping_cid: member.resolved_mapping_contract_cid}))});
      return Object.freeze({...commonStage({control, store, execution, storedResults,
        computation, preview, applyPreview, ledger, body, members, scopes, owner,
        request: plan.request, attempt: plan.attempt, contractLimits: plan.contractLimits,
        now: plan.now, continuationWire}), releaseInputs,
        apply: {moon, capturedInputs: authored.capturedInputs,
          preflight: preflightOf(body, targets, requestScope, authored.keys), ledger, members,
          maxFrontierWork: limits.maxFrontierWork,
          refreshPreflight: ({preflight,signal}: Parameters<NonNullable<Apply['refreshPreflight']>>[0]) => refreshCapturedTableTargets(
            {prepared: owner.materials, preflight, signal}),
          bindDispatch: dispatchBinder(control, ledger, owner, body, scopes)}});
    } catch (error) {
      // No physical send is possible during capture preparation. Still retain
      // every failed Store/handle cleanup, rather than losing it on the throw.
      let cleaned = false;
      const cleanup = async () => {
        if (cleaned) return true;
        if (!await owner.cleanup()) return false;
        for (const payload of sources?.payloads ?? []) {
          if (payload.prepared.status().pending) await payload.prepared.release();
        }
        releaseInputs();
        await releaseCompletedRunPreparedPayloads(storedResults, control);
        cleaned = true;
        return true;
      };
      // The existing publication cleanup owner preserves immutable/primitive
      // failures and any nested cleanup handle alongside this Table custody.
      await releasePreparedResults([{prepared: Object.freeze({
        release: cleanup, retry: cleanup,
        status: () => Object.freeze({pending: !cleaned}),
      })}], error, control);
    }
  }

  async function prepareRecovered(facts: RecoveryFacts) {
    const {moon: runMoon, control, store, recovered, continuation,
      retainRecoveryOwner, signal} = facts ?? {};
    if (runMoon !== moon || !recovered?.computation) fail('InvalidInstalledTableRecovery');
    const provider = (continuation?.provider ?? continuation) as StoredProvider | undefined;
    if (provider?.version !== 'actql-installed-table-continuation/0.1' ||
      !cid(provider.binding_cid) || !text(provider.program_id) || !text(provider.stage_id) ||
      !Array.isArray(provider.members)) fail('InstalledTableContinuationMismatch');
    if (provider.binding_cid !== bindingCid) fail('InstalledTableInstallationChanged');
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {preview, computation, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = JSON.parse(previewWire) as PreviewBody;
    if (body.effects.length !== provider.members.length || body.effects.length > limits.maxMembers) {
      fail('InstalledTableContinuationMismatch');
    }
    const targets = body.effects.map((member,index) => {
      const saved = provider.members[index];
      const target = resolve(runtimeTupleFromFields({1: member.effect_id, 2: member.effect_kind, 3: member.target, 4: member.mapping, 5: member.resolved_mapping_contract_cid, 6: member.source_result, 8: member.source_table_input}), member.capability_evidence_cid);
      if (saved?.effect_id !== member.effect_id || saved.mapping_cid !== target.mappingCid ||
        member.changes.length !== 1 || member.capability_evidence_cid !== target.capabilityCid) {
        fail('InstalledTableInstallationChanged');
      }
      const operation = member.changes[0].intended_changes?.value;
      if (!operation || operation.catalog_identity_cid !== catalogCid ||
        operation.action !== target.action || operation.table_name !== target.tableName ||
        wire(operation.namespace) !== wire(target.namespace) ||
        wire(operation.expected_table) !== wire(target.expectedTable)) fail('InstalledTableInstallationChanged');
      return target;
    });
    const owner = cleanupOwner();
    try {
      retainRecoveryOwner?.(owner);
      const ledger = openLedger(requestIdentity);
      owner.setLedger(ledger);
      const admitted = control.effectComputationPreviewLedgerIdentity(preview);
      const keys = effect.recoveredPreviewKeys(admitted, requestScope, targets.length,
        targets.length, limits.maxWork, limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth) as Keys;
      const applyPreview = effect.admitPreviewIdentity(previewWire, body.run_identity_cid,
        body.authoring_context.authoring_context_cid, requestScope, keys,
        limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth);
      const recorded = ledger.recoverClaimFacts({preview: admitted, scope: requestScope,
        programId: provider.program_id, nodeId: provider.stage_id,
        maxRows: targets.length, maxWork: limits.maxWork});
      const recoveredInputs: Awaited<ReturnType<typeof prepareRecoveredTableInput>>[] = [];
      const inventory = prepareCompletedEffectfulPublication({execution: null,
        store, control, storedResults, computation, preview});
      for (let index=0; index<targets.length; index++) {
        const input = await prepareRecoveredTableInput({recovered: durable, store,
          control, memberIndex: index, requestScope, contractLimits: localContractLimits,
          tableLimits: limits.material, bridge, signal,
          recoveryResources: recovered.recoveryResources});
        recoveredInputs.push(input);
        const schema = await store.putPreparedResultSchema(input.schemaWire,
          (JSON.parse(input.operationWire) as Operation).schema_cid, inventory.chain.runDefinition.identity);
        owner.schemas.push(schema.prepared);
      }
      const scopes = scopesOf(targets);
      // Read evidence under the installation's current gate before any lookup
      // and after its await. No head check can manufacture original success.
      const evidenceDecision = async (index: number) => {
        const claim = recorded.members[index]?.claims[0];
        const decision = await authorization.authorize('acquisition',
          {...scopes[index], operation: 'read'}, {subjectCid: claim?.canonicalRequestCid!, signal});
        if (!authorizationDispatchFacts(decision) || decision?.action !== 'dispatch') {
          fail('TableReconciliationReadNotAuthorized');
        }
        return decision;
      };
      const reconcileStoredResponses = async ({members}: Readonly<{members: readonly Member[]}>) => {
        for (const [index,member] of members.entries()) {
          if (member.claims.length !== 1) fail('InstalledTableContinuationMismatch');
          const decision = await evidenceDecision(index);
          await reconcileOriginalTableCommit({control, commonMoon: moon, ledger,
            tablePreview: recoveredInputs[index].tablePreview, claim: member.claims[0], bridge,
            authorizeEvidenceRead: async () => { await evidenceDecision(index); return true; },
            credentialUseCid: useCid('reconciliation', body, member.claims[0].canonicalRequestCid, [decision]),
            maxRevisions: limits.maxRevisions, entryLimits: limits.entry, limits: limits.material, signal});
        }
      };
      const refreshPreflight = async ({signal}: Readonly<{signal?: AbortSignal}> = {}) => {
        while (owner.materials.length < recoveredInputs.length) {
          owner.materials.push(await prepareRecoveredTableCommit({control,
            recoveredInput: recoveredInputs[owner.materials.length], bridge,
            reservation: limits.reservation, maxBytes: limits.maxInputBytes, signal}));
        }
        // Only common-frontier Ready members need a current target guard.
        // A committed create must not be rejected because its name now exists;
        // an uncertain original operation must not inspect a head as success.
        const frontier = ledger.frontierFromDurableHeads(applyPreview,
          recorded.members, limits.maxFrontierWork);
        const ready = new Set(Array.from({length: effect.setFrontierReadyCount(frontier)},
          (_,index) => effect.setFrontierReadyMember(frontier,index)));
        return refreshCapturedTableTargets({prepared: owner.materials.filter((_,index) => ready.has(index)),
          preflight: preflightOf(body, targets, requestScope, keys), signal});
      };
      return Object.freeze({...commonStage({control, store, execution: null, storedResults,
        computation, preview, applyPreview, ledger, body, members: recorded.members, scopes,
        owner, request: provider.request,
        // JSON omits an undefined optional key. Restore the existing closed
        // publication-attempt shape without issuing a new attempt or key.
        attempt: {...provider.attempt,
          externalIdempotencyKey: provider.attempt?.externalIdempotencyKey},
        contractLimits: localContractLimits, now: () => new Date().toISOString(),
        continuationWire: wire(provider)}),
        apply: {moon, store, publicationControl: control, computation, preview, ledger,
          requestScope, programId: provider.program_id, nodeId: provider.stage_id,
          maxRows: targets.length, maxFrontierWork: limits.maxFrontierWork,
          maxRecoveryWork: limits.maxWork, keyLimits: {...limits.key, maxWork: limits.maxWork},
          reconcileStoredResponses, refreshPreflight,
          bindDispatch: dispatchBinder(control, ledger, owner, body, scopes)}});
    } catch (error) {
      if (retainRecoveryOwner === undefined) {
        await releasePreparedResults([{prepared: Object.freeze({
          release: owner.cleanup, retry: owner.cleanup,
          status: () => Object.freeze({pending: owner.cleanupPending()}),
        })}], error, control);
      }
      throw error;
    }
  }

  if (sourceInitialization !== undefined) {
    assertInstalledSourceConstruction(sourceInitialization, undefined, undefined, environment);
  }
  let constructionClosed = false;
  const adapter = Object.freeze({environmentWire, connectorRegistration, connectorRevision,
    connectorBindings: Object.freeze([{connectorId, bindingCid}]),
    queryTableBindings: Object.freeze(installed.filter(target => target.queryName !== undefined).map(target => Object.freeze({
      name: target.queryName, targetRef: target.targetRef, mappingRef: target.mappingRef,
      mappingCid: target.mappingCid, capabilityCid: target.capabilityCid,
      installationBindingCid: bindingCid, action: target.action,
      expectedTable: target.expectedTable === null ? null : Object.freeze({...target.expectedTable}),
    }))),
    queryTableWriteAccesses: Object.freeze(installed.filter(target => target.queryName !== undefined)
      .map(target => Object.freeze({connection, resource: target.resource,
        capabilityCid: target.capabilityCid, authorization}))),
    effectSelectors: Object.freeze(installed.map(target => Object.freeze({
      kind: 'store', target: target.targetRef, mappingRef: target.mappingRef,
      mappingCid: target.mappingCid, effectId: target.effectId, capabilityCid: target.capabilityCid}))),
    prepareManagedPlan, prepareCaptured, prepareRecovered, close() {
      if (sourceInitialization === undefined || constructionClosed) return;
      if (authorization.close!() !== true) fail('InstalledTableAuthorizationCleanupPending');
      closeInstalledSourceConstruction(sourceInitialization, adapter);
      constructionClosed = true;
    }});
  if (sourceInitialization !== undefined) {
    retainInstalledSourceConstruction(sourceInitialization, adapter, undefined, undefined, environment);
  }
  return adapter;
}
