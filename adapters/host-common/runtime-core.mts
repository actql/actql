import {runtimeField, runtimeOptionalField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {outputExportControl} from './output-export-control.mjs';
import {contentGenerationControl} from './content-generation-control.mjs';
import {contentCaptureControl} from './content-capture-control.mjs';
import {siteControl} from './site-control.mjs';
import {remoteStandardSourceControl} from './remote-standard-source-control.mjs';
import {remoteCredentialControl} from './remote-credential-control.mjs';
import {remoteBundleControl} from './remote-bundle-control.mjs';
import {remoteTransferControl} from './remote-transfer-control.mjs';
import {remoteSiteControl} from './remote-site-control.mjs';
import {effectApplicationControl} from './effect-application-control.mjs';
import {createRuntimeExecutionControls} from './runtime-execution-control.mjs';
import {createLocalSigningMetadata} from './local-signing-metadata.mjs';
import {createInstallationPreparationMetadata} from './installation-preparation-metadata.mjs';
import {publicationProgressControl} from './publication-progress-control.mjs';
import {createResultDeliveryControls} from './runtime-result-delivery-control.mjs';
import {createRunStateControls} from './runtime-run-state-control.mjs';
import {createPublicationContractControls} from './runtime-publication-contract-control.mjs';
import {createQueryTimeControls} from './runtime-query-time-control.mjs';
import {createContentPublicationControls} from './runtime-content-publication-control.mjs';
import {createContentInferenceControls} from './runtime-content-inference-control.mjs';
import {createEffectCaptureControls} from './runtime-effect-capture-control.mjs';
import {createPublicationValidationControls} from './runtime-publication-validation-control.mjs';
import {createCapturedPublicationControls} from './runtime-captured-publication-control.mjs';
import {createInferOriginalReadControls} from './runtime-infer-original-read-control.mjs';
import {createModelPreparationControls} from './runtime-model-preparation-control.mjs';
import {createEffectPreparationControls} from './runtime-effect-preparation-control.mjs';
import {createEffectUnitResultControls} from './runtime-effect-unit-result-control.mjs';
import {createEffectArtifactControls} from './runtime-effect-artifact-control.mjs';
import {createEffectRecoveryControls} from './runtime-effect-recovery-control.mjs';
import {createEffectPreviewControls} from './runtime-effect-preview-control.mjs';
import {createEffectPublicationControls} from './runtime-effect-publication-control.mjs';
import {createRunPlanControls} from './runtime-run-plan-control.mjs';
import {createInferAdmissionControls} from './runtime-infer-admission-control.mjs';
import {ledgerUsageSnapshot, ledgerUsageDiagnostic,
  ledgerUsageHasPendingResources, ledgerUsageSnapshotHasPendingResources} from './ledger-usage.mjs';
import {
  resultOutputLimitFields,
  validResultOutputLimits,
} from './result-output-limits.mjs';

type WireLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ContentLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxTextUnits: number}>;
type KeyedCaptureLimits = Readonly<{maxEntries: number; maxNameBytes: number; maxBytes: number; maxWork: number}>;
type Contract = Readonly<{name: string; identityField: string; identity: string; wire: string}>;
type Evidence = Readonly<{name: string; identity: string; wire: string}>;
type CommonObject = Extract<import('./runtime-result.mjs').SynchronousRuntimeData, object>;
type EvidenceBody = Readonly<{kind: string; cid?: string; wire: string}>;
type CompiledRun = Readonly<{kind: string}>;
type ClientCompilationKind = 'values' | 'tasks' | 'infer' | 'serialization';
type ResultPolicy = Readonly<{kind: string; cid: string; wire: string}>;
type SourceFreeResultPolicy = ResultPolicy & Readonly<{kind: 'data_policy'}>;
type CompilationPolicy = Readonly<{
  executionContextCid: string; hostPolicyCid: string; expiresAt: string; resultDataPolicy?: ResultPolicy;
}>;
type DefinitionOptions = Readonly<{namespaceId: string; runId: string; createdAt: string;
  validUntil: string; retainedDefinitionWire?: string}>;
type SourceCapture = Readonly<{
  inputKind: string; identity?: unknown; requirement?: unknown;
  logicalInput?: unknown; wholeCapacity?: unknown;
  capture: Readonly<{
    source(): unknown;
    originalWholeInput(): unknown;
    originalRowCapture(): unknown;
    originalCapturedInput(): unknown;
  }>;
}>;
type ComposedSourceCapture = Omit<SourceCapture, 'capture' | 'inputKind'> &
  Readonly<{inputKind?: string; capture: Pick<SourceCapture['capture'], 'source'>}>;
type SourceInput = Readonly<{captured: SourceCapture; sourceEvidence: unknown}>;
type InvocationSource = Readonly<{
  captured: SourceCapture; sourceEvidence: unknown; sources?: readonly SourceInput[];
  keyedObservation?: unknown; authorityScopeCid: string; captureStartedAt: string; captureCompletedAt: string;
}>;
type InvocationOptions = Readonly<{dataPolicyCid: string; source?: InvocationSource}>;
type CapturedInput = Readonly<{inferStep: number; capturedSource: unknown; identity: unknown; requirement: unknown; logicalInput: unknown}>;
type RetentionSelection = Readonly<{
  retentionContractCid: string; availableUntil: string; deleteBy: string;
  metadataDeleteBy: string; metadataRetentionPolicyCid: string; clockContractCid: string;
}>;
type PrivateStorage = Readonly<{namespaceId: string; storeAuthorityCid: string; availabilityEvidenceCid: string;
  issuerContractCid: string}>;
type InstalledEffectOriginal = Readonly<{runtime: unknown; closed?: boolean; prepared: unknown; value?: unknown; request?: unknown}>;
type EffectPreparationDependencyOwner = Parameters<Parameters<typeof createEffectPreparationControls>[1]['localEffectDependencyTokens']['set']>[1];
type ModelEffectDependency = Readonly<{kind: 'preconsumer_model' | 'model'; issued: unknown; original: unknown}>;
type ImportedEffectDependency = Readonly<{kind: 'imported'; issued: unknown; originalSources: readonly unknown[]}>;
type EffectDependencyOwner = EffectPreparationDependencyOwner | ModelEffectDependency |
  Readonly<{kind: 'source_free'; issued: unknown}> | ImportedEffectDependency;
type HoldingEntry = Readonly<{scopeCid: string; slotCid: string; attemptCid: string; attemptIndex: number}>;
type DispatchOptions = Readonly<{
  account: unknown; principalId: string; at: string; delegated: unknown;
  observeAccount: () => unknown; observeAt: () => string;
}>;
type ModelScopeOptions = Readonly<{
  scope: unknown; provider: unknown;
  expectedBoundary: Readonly<{task_index: number | bigint | string; strategy_revision: number | bigint | string}>;
}>;
type RawSelection = Readonly<{retention: unknown; metadata: unknown; clock: unknown; data: unknown}>;
type RawCaptureOptions = RawSelection & Readonly<{
  profile: unknown; installation: unknown; probability: unknown; storeAuthorityCid: string;
  selectedAt: string; availableUntil: string; deleteBy: string; extensionCeilingAt: string; metadataDeleteBy: string;
}>;
type RawCaptureRegistration = Readonly<{
  policy: unknown; profile: unknown; installation: unknown; probability: unknown; account: unknown;
  at: string; storeAuthorityCid: string; selectionAvailable: () => boolean;
  observeAccount: () => unknown; observeAt: () => string; delegated?: unknown;
}>;
type IssuedInvocation = Readonly<{binding: unknown; observation: Evidence; invocation: Contract}>;
type ModelObservation = Readonly<{task: number; unit: number; step: number; bodies: readonly EvidenceBody[]}>;
type RunDefinitionRequest = Readonly<{scopeId: string; runId: string; inputArtifactSetCid: string; createdAt: string; validUntil: string}>;
type ReceiptChain = Readonly<{admission: unknown; runDefinition: unknown; invocation: unknown; observation: unknown;
  definitions: readonly unknown[]; artifacts: readonly unknown[]; manifest: unknown}>;
type ReceiptProvenance = Readonly<{
  normalizationJournal: unknown; bindings: readonly Readonly<{name: string; sha256: string}>[];
  sourceEvidence: readonly unknown[]; modelEvidence: readonly unknown[];
  barrierAttemptReceiptCids: readonly string[]; contentGenerations?: readonly unknown[];
}>;
type BindingParameters<Name extends keyof DirectCommonBindings> = Parameters<DirectCommonBindings[Name]>;
type Tail<Tuple extends readonly unknown[], Count extends number, Skipped extends readonly unknown[] = []> =
  Skipped['length'] extends Count ? Tuple :
    Tuple extends readonly [unknown, ...infer Rest] ? Tail<Rest, Count, [...Skipped, unknown]> : never;
type WeakValue<Table> = Table extends WeakMap<infer _Key, infer Value> ? Value : never;
// WeakMap permits reads with foreign values and reports absence. Insertion
// is still restricted to issued object keys.
type TokenTable<Value> = WeakMap<object, Value> & {
  get(key: unknown): Value | undefined;
  has(key: unknown): boolean;
};

// Scalar arguments and returns follow the generated Common ABI. Nominal
// Core originals and boxed tagged values stay opaque at this boundary.
type DirectCommonBindings = Readonly<{
  clientProgramAcknowledgeOriginalExplanationCapture(original: unknown): unknown;
  clientProgramAcquiredEffectCatalogBodies(value: unknown, max_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  clientProgramAcquiredEffectDependencyBodies(value: unknown): readonly unknown[];
  clientProgramAcquiredEffectInvocation(value: unknown): unknown;
  clientProgramAcquiredEffectRequestCid(value: unknown): string;
  clientProgramAdmitCompiledRunDefinition(value: unknown, wire: string): unknown;
  clientProgramAdmitComposedInferSources(occurrence: unknown, captures: unknown, identities: unknown,
    requirements: unknown, logicals: unknown, evidence: unknown, authority_scope_cid: string, started_at: string,
    completed_at: string, keyed: unknown): unknown;
  clientProgramAdmitComposedInferWholeSources(occurrence: unknown, captures: unknown, identities: unknown,
    capacities: unknown, logicals: unknown, evidence: unknown, authority_scope_cid: string, started_at: string,
    completed_at: string, keyed: unknown): unknown;
  clientProgramAdmitInferCapturedInput(prepared: unknown, step: number, source: unknown, identity: unknown,
    requirement: unknown, logical: unknown, source_evidence: unknown, authority_scope_cid: string,
    data_policy_cid: string, started_at: string, completed_at: string): unknown;
  clientProgramAdmitPublication(prepared: unknown, template: unknown, invocation: unknown,
    authorization: unknown, plan: unknown): unknown;
  clientProgramAdmitSourceFreeResultPolicyBody(cid: string, wire: string, max_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  clientProgramBindCompiledInferResultPolicy(compiled: unknown, cid: string, wire: string, max_bytes: number,
    max_nodes: number, max_depth: number): unknown;
  clientProgramBindEffectRun(prepared: unknown, admission: unknown, definition: unknown): unknown;
  clientProgramBindInferDispatchAdmission(active: unknown, admission: unknown): unknown;
  clientProgramBindInferInvocation(active: unknown, compiled: unknown, definition: unknown, verified: unknown,
    invocation: unknown, data_policy_cid: string): unknown;
  clientProgramBindInferModelDispatch(active: unknown, prepared: unknown, admission: unknown,
    enter: (_arg0: unknown) => boolean): unknown;
  clientProgramBindInferModelEntryPersistence(active: unknown, prepared: unknown, admission: unknown,
    begin: (_arg0: unknown) => unknown): unknown;
  clientProgramBindInferModelScope(active: unknown, prepared: unknown, scope: unknown, provider: unknown,
    expected: unknown): unknown;
  clientProgramBindInferRun(active: unknown, compiled: unknown, definition: unknown): unknown;
  clientProgramBindIssuedInferInvocation(execution: unknown, compiled: unknown, definition: unknown,
    issued: unknown): unknown;
  clientProgramBindModelRawCapturePolicy(policy: unknown, retention: unknown, metadata: unknown, clock: unknown,
    data: unknown): unknown;
  clientProgramBindPreconsumerModelUnitObservation(binding: unknown, original: unknown): unknown;
  clientProgramCaptureRequestOriginalExplanation(original: unknown, compiled: unknown, definition: unknown): unknown;
  clientProgramCheckCompiledLocalExecutionOwner(compiled: unknown, definition: unknown): boolean;
  clientProgramCheckCompiledRunDefinition(compiled: unknown, definition: unknown): boolean;
  clientProgramCompileLocalInfer(prepared: unknown, graph: unknown): unknown;
  clientProgramCompileLocalInfers(prepared: unknown, graphs: unknown): unknown;
  clientProgramCompileLocalSerialization(owner: unknown, graph: unknown): unknown;
  clientProgramCompileLocalTasks(prepared: unknown): unknown;
  clientProgramCompileLocalValues(prepared: unknown): unknown;
  clientProgramCompiledRunAdmission(value: unknown): unknown;
  clientProgramCompiledRunAuthorization(value: unknown): unknown;
  clientProgramCompiledRunEffectMatches(compiled: unknown, prepared: unknown, compilation: unknown): boolean;
  clientProgramCompiledRunEvaluationPolicy(compiled: unknown): readonly [string, string, string] | undefined;
  clientProgramCompiledRunHasSerialization(run: unknown): boolean;
  clientProgramCompiledRunMatches(value: unknown, prepared: unknown): boolean;
  clientProgramCompiledRunPlan(value: unknown): unknown;
  clientProgramCompiledRunPrepared(value: unknown): unknown;
  clientProgramCompiledRunResultTransformation(value: unknown, prepared: unknown, result: number): unknown;
  clientProgramCompiledRunSerializationGraph(run: unknown): unknown;
  clientProgramCompiledRunSourceFreeResultPolicy(compiled: unknown): readonly [string, string, string] | undefined;
  clientProgramCompiledRunTemplate(value: unknown): unknown;
  clientProgramComposedInferSourcesMatch(sources: unknown, occurrence: unknown): boolean;
  clientProgramEffectAllowedInferRun(allowed: unknown): unknown;
  clientProgramEffectAllowedInferRunWithPolicyBody(allowed: unknown, policy_cid: string, policy_wire: string,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramEffectAllowedKeyedRun(allowed: unknown, plan: unknown, definition: unknown): unknown;
  clientProgramEffectInputExportLimits(max_result_fields: number, max_result_mapping_work: number,
    max_result_order_work: number, max_result_workspace_entries: number, max_rows: number,
    max_value_nodes: number, max_value_text_bytes: number, max_value_depth: number, max_value_work: number,
    max_wire_bytes: number, max_wire_nodes: number, max_wire_depth: number, max_columns: number,
    max_order_work: number, max_logical_wire_bytes: number, max_logical_wire_nodes: number,
    max_logical_wire_depth: number, max_schema_fields: number, max_schema_bytes: number,
    max_schema_nodes: number, max_schema_depth: number, max_batch_bytes: number): unknown;
  clientProgramEffectInputExportLogicalCid(receipt: unknown): string;
  clientProgramEffectInputExportSchemaCid(receipt: unknown): string;
  clientProgramEffectInputExportSchemaWire(receipt: unknown): string;
  clientProgramEffectKeyedDeclaredFileActivationRecord(activation: unknown, request: unknown, original: unknown,
    max_bytes: number): unknown;
  clientProgramEffectKeyedDeclaredFilePageRecord(page: unknown, keyed_request: unknown, request: unknown,
    original: unknown, max_bytes: number): unknown;
  clientProgramEffectKeyedGenericPublicationInput(parent: unknown, lookup: unknown, observed_at: string,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramEffectKeyedGenericSourceMetadata(parent: unknown, lookup: unknown, identity: unknown,
    logical: unknown, observation: unknown, retention_contract: string, available_until: string,
    delete_by: string, metadata_delete_by: string, metadata_policy: string, clock_contract: string,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramEffectKeyedNativeActivationMatches(activation: unknown, request: unknown, original: unknown): boolean;
  clientProgramEffectKeyedNativeCapturedPageMatches(page: unknown, keyed_request: unknown, request: unknown,
    original: unknown): boolean;
  clientProgramEffectKeyedOriginalSourceEvidenceFacts(original: unknown, owner: unknown, request: unknown): unknown;
  clientProgramInferInvocationBindingInvocation(binding: unknown): unknown;
  clientProgramInferInvocationBindingObservation(binding: unknown): unknown;
  clientProgramInferInvocationEvidence(active: unknown, slot: number): unknown;
  clientProgramInferModelIdentityBody(scan: unknown, receipt: unknown): string | undefined;
  clientProgramInitialJevDecisionProfile(): unknown;
  clientProgramInstalledEffectKeyedOriginal(owner: unknown, prepared: unknown, request: unknown): unknown;
  clientProgramInstalledManagedPublicationSourceKind(owner: unknown, prepared: unknown): unknown;
  clientProgramInstalledOriginalComposedKeyedHostInputLeft(owner: unknown, scope: unknown, compiled: unknown,
    definition: unknown, plan: unknown, keyed: unknown, rows: unknown, host: unknown): unknown;
  clientProgramIssueCapturedPublicationInvocation(owner: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, captures: unknown, identities: unknown, requirements: unknown, sources: unknown,
    inputs: unknown, keyed: unknown, authority_scope_cid: string, data_policy_cid: string,
    capture_started_at: string, capture_completed_at: string, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  clientProgramIssueCompiledRunDefinition(value: unknown, scope_id: string, run_id: string, created_at: string,
    valid_until: string): unknown;
  clientProgramIssueCompiledSourceFreeTaskInvocation(value: unknown, definition: unknown,
    data_policy_cid: string, max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramIssueCompiledValuesInvocation(value: unknown, definition: unknown, data_policy_cid: string,
    max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramIssueInferDispatchAdmission(compiled: unknown, definition: unknown, account: unknown,
    principal: string, at: string, delegated: unknown, observe_account: () => unknown, observe_at: () => string): unknown;
  clientProgramIssueInferInvocationBindingOriginalModelObservation(binding: unknown, receipt: unknown,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramIssueInferRawCapturePolicy(compiled: unknown, definition: unknown, dispatch: unknown,
    scope: unknown, profile: unknown, installation: unknown, probability: unknown, store_authority_cid: string,
    retention: unknown, metadata: unknown, clock: unknown, data: unknown, selected_at: string,
    available_until: string, delete_by: string, extension_ceiling_at: string, metadata_delete_by: string): unknown;
  clientProgramIssueOriginalTaskCompiledRun(prepared: unknown, original: unknown, execution_context_cid: string,
    host_policy_cid: string, expires_at: string): unknown;
  clientProgramIssueOriginalValuesCompiledRun(prepared: unknown, original: unknown,
    execution_context_cid: string, host_policy_cid: string, expires_at: string): unknown;
  clientProgramIssuePublicationInvocation(owner: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, data_policy_cid: string, max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramIssueScopedInferDispatchAdmission(compiled: unknown, definition: unknown, scope: unknown,
    account: unknown, principal: string, at: string, delegated: unknown, observe_account: () => unknown,
    observe_at: () => string): unknown;
  clientProgramIssueTaskCompiledRun(prepared: unknown, compilation: unknown, execution_context_cid: string,
    host_policy_cid: string, expires_at: string): unknown;
  clientProgramIssueValuesCompiledRun(prepared: unknown, compilation: unknown, execution_context_cid: string,
    host_policy_cid: string, expires_at: string): unknown;
  clientProgramIssueWholeSourcePublicationInvocation(owner: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, capture: unknown, identity: unknown, source: unknown, input: unknown,
    authority_scope_cid: string, data_policy_cid: string, capture_started_at: string,
    capture_completed_at: string, max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramIssueWholeSourcesPublicationInvocation(owner: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, captures: unknown, identities: unknown, sources: unknown, inputs: unknown,
    authority_scope_cid: string, data_policy_cid: string, capture_started_at: string,
    capture_completed_at: string, max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramKeyedLookupActivationFields(original: unknown): readonly [string, string, number, number];
  clientProgramKeyedLookupActivationMatches(original: unknown, request: unknown, compiled: unknown,
    definition: unknown, graph: unknown): boolean;
  clientProgramKeyedLookupBindDeclaredFilePhysicalSource(lookup: unknown, declarations: unknown): unknown;
  clientProgramKeyedLookupBindQuerySourceMetadata(lookup: unknown, index: number, requirement: unknown,
    identity: unknown, logical: unknown, observation: unknown, request: unknown, retention: unknown,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramKeyedLookupBindWholeSourceMetadata(lookup: unknown, index: number, identity: unknown,
    logical: unknown, observation: unknown, request: unknown, retention: unknown, max_bytes: number,
    max_nodes: number, max_depth: number): unknown;
  clientProgramKeyedLookupCapturedPageFields(page: unknown): readonly [string, string, string, number];
  clientProgramKeyedLookupCapturedPageMatches(page: unknown, keyed_request: unknown, request: unknown,
    compiled: unknown, definition: unknown, graph: unknown): boolean;
  clientProgramKeyedLookupDeclaredFileActivationRecord(original: unknown, request: unknown, compiled: unknown,
    definition: unknown, graph: unknown, max_bytes: number): unknown;
  clientProgramKeyedLookupDeclaredFilePageRecord(page: unknown, keyed_request: unknown, request: unknown,
    compiled: unknown, definition: unknown, graph: unknown, max_bytes: number): unknown;
  clientProgramKeyedLookupObservationOriginals(value: unknown): readonly [unknown, unknown, string] | undefined;
  clientProgramKeyedLookupPrepareCapturedPage(request: unknown, capture: unknown, raw: unknown,
    recorded_at: string, limits: unknown, max_work: number, max_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  clientProgramKeyedLookupPrepareDeclaredFileRawCapture(compiled: unknown, definition: unknown, request: unknown,
    retention: unknown, store_id: string, store_cid: string, availability_cid: string, issuer_cid: string,
    content_cid: string, size_bytes: number, captured_at: string, now_ms: bigint, max_bytes: number,
    max_nodes: number, max_depth: number, max_text_units: number): unknown;
  clientProgramKeyedLookupPrepareLeftIdentity(lookup: unknown, limits: unknown, max_work: number): unknown;
  clientProgramKeyedLookupPrepareLeftRelation(lookup: unknown, request: unknown, retention: unknown,
    issuer: string, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  clientProgramKeyedLookupPrepareRetention(lookup: unknown, request: unknown, retention_contract: string,
    available_until: string, delete_by: string, metadata_delete_by: string, metadata_policy: string,
    clock_contract: string, max_bytes: number): unknown;
  clientProgramKeyedLookupRawStoreBinding(raw: unknown): unknown;
  clientProgramLocalEffectResultArtifactCid(value: unknown): string;
  clientProgramLocalEffectResultArtifactJson(value: unknown): string;
  clientProgramLocalEffectResultDerivationJson(value: unknown): string;
  clientProgramLocalEffectResultOrderingJson(value: unknown): string;
  clientProgramModelPrivateHoldingCid(definition: unknown, store: string, role: string, slot: number): string | undefined;
  clientProgramModelRawSelectionOriginals(retention: unknown, metadata: unknown, clock: unknown, data: unknown): readonly unknown[];
  clientProgramModelScopedPrivateHoldingCid(definition: unknown, store: string, scope: string, slot: string,
    attempt: string, index: number, phase: string, role: string): string | undefined;
  clientProgramObserveOriginalDispatchFailure(original: unknown, host: unknown): unknown;
  clientProgramOriginalExplanationFactsWire(original: unknown): unknown;
  clientProgramOriginalExplanationPlanWire(original: unknown): unknown;
  clientProgramOriginalModelAcquiredEffectEvidence(value: unknown, retention: unknown, max_bytes: number,
    max_nodes: number, max_depth: number, imports: unknown, source_originals: unknown): unknown;
  clientProgramOriginalModelAcquiredEffectEvidenceIssueKind(result: unknown): string | undefined;
  clientProgramOriginalModelAcquiredEffectInvocation(value: unknown): unknown;
  clientProgramOriginalModelAcquiredEffectLookupBarrier(value: unknown): readonly [string, string] | undefined;
  clientProgramOriginalModelAcquiredEffectScope(value: unknown): string;
  clientProgramOriginalModelAcquiredEffectSources(value: unknown): readonly unknown[];
  clientProgramOriginalModelAcquiredLookupDependencyBodies(value: unknown): unknown;
  clientProgramOriginalModelAcquiredScopeImportBodies(value: unknown): readonly unknown[];
  clientProgramOriginalModelObservationBody(value: unknown): readonly [string, string] | undefined;
  clientProgramOriginalModelObservationCoordinates(value: unknown): readonly [number, number, number] | undefined;
  clientProgramOriginalModelObservationInputBodies(value: unknown): unknown;
  clientProgramPrepareLogicalObservation(run: unknown, prepared: unknown, compiled: unknown, definition: unknown,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramPreparedAuthoringContextEvidence(prepared: unknown, original: unknown, max_wire_bytes: number,
    max_nodes: number, max_depth: number): unknown;
  clientProgramPreparedLocalNormalizationEvidence(prepared: unknown, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  clientProgramPrivateContinuationRetentionShape(bytes: Uint8Array, prepare_attempt_id: string,
    max_wire_bytes: number, max_entries: number): string;
  clientProgramReadModelResponseProfile(wire: string, expected_cid: string, max_bytes: number, max_nodes: number,
    max_depth: number, max_members: number, max_work: number): unknown;
  clientProgramReadSavedComposedInferInputScope(compiled: unknown, definition: unknown, occurrence: unknown,
    graph: unknown, snapshot_wire: string, authority_scope_cid: string, custody_available: () => boolean): unknown;
  clientProgramReadSavedInferInputScope(compiled: unknown, definition: unknown, prepared: unknown, step: number,
    graph: unknown, snapshot_wire: string, authority_scope_cid: string, custody_available: () => boolean): unknown;
  clientProgramReadVerifiedInferSlotReplay(observation: unknown, records: unknown, bundle: unknown,
    proofs: unknown, saved: unknown, definition: unknown, max_slots: number, max_slot_wire_units: number): unknown;
  clientProgramRecoveredContentIssuerKind(wire: string, max_bytes: number, max_nodes: number, max_depth: number,
    max_text_units: number): unknown;
  clientProgramRecoveredEffectCapturedRunContract(value: unknown): unknown;
  clientProgramRecoveredEffectCapturedRunLimits(value: unknown): readonly [number, number, number];
  clientProgramRecoveredSourceContentCandidate(original: unknown, owner: unknown, request: unknown,
    reference_wire: string, binding_wire: string, max_bytes: number, max_nodes: number, max_depth: number,
    max_text_units: number): unknown;
  clientProgramRecoveredSourceContentConstructionCapacity(reference_wire: string, binding_wire: string,
    max_bytes: number, max_nodes: number, max_depth: number, max_text_units: number, role: string): unknown;
  clientProgramRegisterInferRawCapture(compiled: unknown, definition: unknown, dispatch: unknown, scope: unknown,
    policy: unknown, profile: unknown, installation: unknown, probability: unknown, account: unknown, at: string,
    store_authority_cid: string, selection_available: () => boolean, observe_account: () => unknown,
    observe_at: () => string, delegated: unknown): unknown;
  clientProgramRetainRequestResultMetadataContract(parent: unknown, input: unknown, slot: number,
    contract: unknown, mode: number): unknown;
  clientProgramReturnOriginalExplanationCapture(original: unknown): unknown;
  clientProgramRunCapturedContentCandidate(compiled: unknown, definition: unknown, acquisition: unknown,
    request: unknown, binding_wire: string, media_type: string, content_cid: string, size_bytes: number,
    max_bytes: number, max_nodes: number, max_depth: number, max_text_units: number): unknown;
  clientProgramSerializationCapture(generation: unknown): unknown;
  clientProgramStartInstalledEffectKeyedCaptureInput(owner: unknown, prepared: unknown, request: unknown,
    compiled: unknown, definition: unknown, plan: unknown, keyed: unknown, captures: unknown,
    max_entries: number, max_name_bytes: number, max_bytes: number, max_work: number): unknown;
  clientProgramStartInstalledOriginalComposedKeyedHostPrefix(owner: unknown, scope: unknown, compiled: unknown,
    definition: unknown, plan: unknown, keyed: unknown, rows: unknown, host: unknown): unknown;
  clientProgramStartInstalledOriginalComposedKeyedInputPrefix(owner: unknown, scope: unknown, compiled: unknown,
    definition: unknown, plan: unknown, keyed: unknown, inputs: unknown): unknown;
  clientProgramStartInstalledOriginalComposedKeyedPrefix(owner: unknown, scope: unknown, compiled: unknown,
    definition: unknown, plan: unknown, keyed: unknown, rows: unknown): unknown;
  clientProgramStartOriginalComposedKeyedPrefix(scope: unknown, compiled: unknown, definition: unknown,
    plan: unknown, keyed: unknown, rows: unknown, input_prefix: unknown): unknown;
  clientProgramStoredRunCapturedContentCandidate(compiled: unknown, definition: unknown, acquisition: unknown,
    original_wire: string, binding_wire: string, max_bytes: number, max_nodes: number, max_depth: number,
    max_text_units: number): unknown;
  clientRequestAuthorityScopeCid(value: unknown): string;
  strategyHostManagedExecutionProfileCid(): string;
  strategyHostOutputExportIssueResultArtifact(value: unknown, invocation: unknown, retention: unknown,
    max_wire_bytes: number, max_nodes: number, max_depth: number): unknown;
  strategyIssueEffectFreeRunReceipt(admission: unknown, run_definition: unknown, invocation: unknown,
    observation: unknown, definitions: unknown, artifacts: unknown, manifest: unknown,
    normalization_journal: unknown, binding_names: unknown, binding_digests: unknown, source_evidence: unknown,
    model_evidence: unknown, barrier_attempt_receipt_cids: unknown, max_wire_bytes: number, max_nodes: number,
    max_depth: number, content_generations: unknown): unknown;
  strategyIssueRunDefinition(admission: unknown, scope_id: string, run_id: string,
    input_artifact_set_cid: string, created_at: string, valid_until: string, max_wire_bytes: number,
    max_nodes: number, max_depth: number): unknown;
  strategyIssueRunInvocation(template: unknown, observation: unknown, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  strategyModule_local_ManagedFailureExplanation(cause: string): string | undefined;
  strategyPublicationAdmit(name: string, complete_wire: string, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  strategyPublicationContractIdentity(contract: unknown): string;
  strategyPublicationContractIdentityField(contract: unknown): string;
  strategyPublicationContractJson(contract: unknown): string;
  strategyPublicationContractName(contract: unknown): string;
  strategyPublicationSeal(name: string, body_wire: string, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  strategyRunEvidenceAdmit(name: string, complete_wire: string, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  strategyRunEvidenceIdentity(value: unknown): string;
  strategyRunEvidenceJson(value: unknown): string;
  strategyRunEvidenceName(value: unknown): string;
  strategyRunEvidenceSeal(name: string, body_wire: string, max_wire_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  strategyRunPublicationAdmit(template: unknown, prepared: unknown, authorization: unknown,
    compiled_plan: unknown): unknown;
}>;
type RuntimeBindings = DirectCommonBindings &
  Parameters<typeof outputExportControl>[0] &
  Parameters<typeof contentGenerationControl>[0] &
  Parameters<typeof contentCaptureControl>[0] &
  Parameters<typeof siteControl>[0] &
  Parameters<typeof remoteStandardSourceControl>[0] &
  Parameters<typeof remoteCredentialControl>[0] &
  Parameters<typeof remoteBundleControl>[0] &
  Parameters<typeof remoteTransferControl>[0] &
  Parameters<typeof remoteSiteControl>[0] &
  Parameters<typeof effectApplicationControl>[0] &
  Parameters<typeof createRuntimeExecutionControls>[0] &
  Parameters<typeof createLocalSigningMetadata>[0] &
  Parameters<typeof createInstallationPreparationMetadata>[0] &
  Parameters<typeof publicationProgressControl>[0] &
  Parameters<typeof createResultDeliveryControls>[0] &
  Parameters<typeof createRunStateControls>[0] &
  Parameters<typeof createPublicationContractControls>[0] &
  Parameters<typeof createQueryTimeControls>[0] &
  Parameters<typeof createContentPublicationControls>[0] &
  Parameters<typeof createContentInferenceControls>[0] &
  Parameters<typeof createEffectCaptureControls>[0] &
  Parameters<typeof createPublicationValidationControls>[0] &
  Parameters<typeof createCapturedPublicationControls>[0] &
  Parameters<typeof createInferOriginalReadControls>[0] &
  Parameters<typeof createModelPreparationControls>[0] &
  Parameters<typeof createEffectPreparationControls>[0] &
  Parameters<typeof createEffectUnitResultControls>[0] &
  Parameters<typeof createEffectArtifactControls>[0] &
  Parameters<typeof createEffectRecoveryControls>[0] &
  Parameters<typeof createEffectPreviewControls>[0] &
  Parameters<typeof createEffectPublicationControls>[0] &
  Parameters<typeof createRunPlanControls>[0] &
  Parameters<typeof createInferAdmissionControls>[0];
type LatePublicationPorts =
  ReturnType<Parameters<typeof createQueryTimeControls>[1]['currentControl']> &
  ReturnType<Parameters<typeof createModelPreparationControls>[1]['currentControl']> &
  ReturnType<Parameters<typeof createEffectArtifactControls>[1]['currentControl']> &
  ReturnType<Parameters<typeof createEffectRecoveryControls>[1]['currentControl']> &
  ReturnType<Parameters<typeof createRunPlanControls>[1]['currentControl']> &
  ReturnType<Parameters<typeof createInferAdmissionControls>[1]['currentControl']>;

export {contentCaptureControl, contentGenerationControl};
export {ledgerUsageSnapshot, ledgerUsageDiagnostic,
  ledgerUsageHasPendingResources, ledgerUsageSnapshotHasPendingResources};
const publicationControls: TokenTable<unknown> = new WeakMap<object, unknown>();

function publicationControl(moon: RuntimeBindings) {
  let control = publicationControls.get(moon) as LatePublicationPorts | undefined;
  if (control !== undefined) return control as typeof assembled;
  const tokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const recoveredEffectCaptures: TokenTable<unknown> = new WeakMap<object, unknown>();
  const capturedComputationPreparations: TokenTable<unknown> = new WeakMap<object, unknown>();
  const contractBounds: TokenTable<WireLimits> = new WeakMap<object, WireLimits>();
  const issuedDeliveryGrants: TokenTable<WeakValue<Parameters<typeof createResultDeliveryControls>[1]['issuedDeliveryGrants']>> = new WeakMap<object, WeakValue<Parameters<typeof createResultDeliveryControls>[1]['issuedDeliveryGrants']>>();
  const issuedDeliveryAttempts: TokenTable<WeakValue<Parameters<typeof createResultDeliveryControls>[1]['issuedDeliveryAttempts']>> = new WeakMap<object, WeakValue<Parameters<typeof createResultDeliveryControls>[1]['issuedDeliveryAttempts']>>();
  const originalDeliveryAttempts: TokenTable<WeakValue<Parameters<typeof createResultDeliveryControls>[1]['originalDeliveryAttempts']>> = new WeakMap<object, WeakValue<Parameters<typeof createResultDeliveryControls>[1]['originalDeliveryAttempts']>>();
  const evidenceTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const modelOriginalDocumentTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const admissionTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const compiledRunTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const originalRunPlanTokens: TokenTable<WeakValue<Parameters<typeof createRunPlanControls>[1]['originalRunPlanTokens']>> = new WeakMap<object, WeakValue<Parameters<typeof createRunPlanControls>[1]['originalRunPlanTokens']>>();
  // The installed namespace supplies these fixed methods before a first
  // admission can await. Later property replacement cannot return another
  // owner's loan or change the original projection selected by this control.
  const captureRequestExplanation = moon.clientProgramCaptureRequestOriginalExplanation;
  const originalExplanationPlanWire = moon.clientProgramOriginalExplanationPlanWire;
  const originalExplanationFactsWire = moon.clientProgramOriginalExplanationFactsWire;
  const returnExplanationCapture = moon.clientProgramReturnOriginalExplanationCapture;
  const acknowledgeExplanationCapture = moon.clientProgramAcknowledgeOriginalExplanationCapture;
  const observeOriginalDispatchFailure = moon.clientProgramObserveOriginalDispatchFailure;
  const describeExecutionFailure = moon.strategyModule_local_ManagedFailureExplanation;
  const prepareLogicalObservation = moon.clientProgramPrepareLogicalObservation;
  const originalInferRunTokens: TokenTable<WeakValue<Parameters<typeof createInferAdmissionControls>[1]['originalInferRunTokens']>> =
    new WeakMap<object, WeakValue<Parameters<typeof createInferAdmissionControls>[1]['originalInferRunTokens']>>();
  const restoredInferRuns = new WeakSet<object>();
  const serializationPlanTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const serializationGenerationTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const serializationInputEvidenceTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const compiledSourceFreeResultPolicy = (compiled: unknown) => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined) throw new TypeError('Foreign Client compiled Run');
    const original = moon.clientProgramCompiledRunSourceFreeResultPolicy(value);
    return original === undefined ? undefined : Object.freeze({
      kind: runtimeField(original, 0) as string, cid: runtimeField(original, 1) as string, wire: runtimeField(original, 2) as string,
    });
  };
  const inferInvocationTokens: TokenTable<Readonly<{compiled: unknown; definition: Contract}>> = new WeakMap<object, Readonly<{compiled: unknown; definition: Contract}>>();
  const inferModelObservationTokens: TokenTable<Readonly<{original: unknown; issued: IssuedInvocation}>> = new WeakMap<object, Readonly<{original: unknown; issued: IssuedInvocation}>>();
  const compiledRunResult = (result: unknown, code: string) => {
    try {
      return checked(result);
    } catch (error) {
      if ((error as {code?: unknown}).code !== 'MoonBitHostFailure') throw error;
      throw Object.assign(new Error(code, {cause: (error as Error).cause}), {code});
    }
  };
  const compiledContent = (compiled: unknown) => {
    const value = compiledRunTokens.get(compiled);
    if (value === undefined || !moon.clientProgramCompiledRunHasSerialization(value)) {
      throw new TypeError('Foreign Client compiled Content Run');
    }
    return value;
  };
  const contentCaptures = (values: unknown) => {
    if (values === undefined) return [];
    if (!Array.isArray(values)) throw new TypeError('Invalid Content capture inventory');
    return values.map(value => {
      const generation = serializationGenerationTokens.get(value);
      if (generation === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramSerializationCapture(generation),
        'Client Content capture unavailable');
    });
  };
  const snapshotTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const effectSourceTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const localEffectSourceTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const localEffectArtifactTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const localEffectIdentityTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const tableInputTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const tablePreviewTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const recoveredTablePreviewTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const localEffectManifestTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const localEffectArtifactSources: TokenTable<WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectArtifactSources']>> = new WeakMap<object, WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectArtifactSources']>>();
  const localEffectImportSources: TokenTable<WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectImportSources']>> = new WeakMap<object, WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectImportSources']>>();
  const localEffectDependencyTokens: TokenTable<EffectDependencyOwner> = new WeakMap<object, EffectDependencyOwner>();
  const localEffectImportTokens: TokenTable<WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectImportTokens']>> = new WeakMap<object, WeakValue<Parameters<typeof createEffectArtifactControls>[1]['localEffectImportTokens']>>();
  const inspectLocalEffectArtifact = (issued: unknown) => {
    const value = Object.freeze({
      identity: moon.clientProgramLocalEffectResultArtifactCid(issued),
      wire: moon.clientProgramLocalEffectResultArtifactJson(issued),
      derivationWire: moon.clientProgramLocalEffectResultDerivationJson(issued),
      orderingWire: moon.clientProgramLocalEffectResultOrderingJson(issued),
    });
    localEffectArtifactTokens.set(value, issued);
    return value;
  };
  // The actual Core-issued Source metadata is projected once. Only callers
  // with an admitted whole Unit register an Artifact dependency token below;
  // Model contributions remain inside their complete Model context.
  const inspectAcquiredEffectEvidence = (issued: unknown, publicationRetention: unknown, limits: WireLimits, deferCatalogs = false) => {
    return Object.freeze({
      invocation: moon.clientProgramAcquiredEffectInvocation(issued),
      bodies: Object.freeze([
        ...moon.clientProgramAcquiredEffectDependencyBodies(issued)
          .map(pair => Object.freeze({kind: runtimeField(pair, 0) as string, wire: runtimeField(pair, 1) as string,
            ...(runtimeField(pair, 0) as string === 'request_values' ? {
              cid: moon.clientProgramAcquiredEffectRequestCid(issued),
            } : {})})),
        Object.freeze({kind: 'result_retention_policy',
          wire: inspect(token(publicationRetention)).wire}),
      ]),
      ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze((checked(
        moon.clientProgramAcquiredEffectCatalogBodies(issued,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[])
        .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string,
          wire: runtimeField(body, 2) as string})))}),
    });
  };
  const localEffectContext = (context: unknown): readonly [unknown, unknown, unknown, unknown] => {
    if (context === null || typeof context !== 'object' ||
        !['admission', 'runDefinition', 'runInvocation', 'observation']
          .every(key => (context as Readonly<Record<string, unknown>>)[key] !== undefined)) {
      throw new TypeError('Invalid local Effect Result context');
    }
    return [admissionToken((context as Readonly<Record<string, unknown>>).admission), token((context as Readonly<Record<string, unknown>>).runDefinition),
      token((context as Readonly<Record<string, unknown>>).runInvocation), evidenceToken((context as Readonly<Record<string, unknown>>).observation)];
  };
  const sourceAdvanceTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const computationPreviewTokens: TokenTable<unknown> = new WeakMap<object, unknown>();
  const computationPreviewWires: TokenTable<WeakValue<Parameters<typeof createEffectPreviewControls>[1]['computationPreviewWires']>> = new WeakMap<object, WeakValue<Parameters<typeof createEffectPreviewControls>[1]['computationPreviewWires']>>();
  const inspect = (contract: unknown, limits?: WireLimits) => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    if (limits !== undefined) {
      // The actual issuer checked this complete immutable wire under these
      // bounds. Each JSON node needs at least one UTF-16 code unit; at most
      // three UTF-8 bytes encode one code unit. These conservative bounds
      // can prove a later looser limit without parsing or hashing again.
      contractBounds.set(value, Object.freeze({
        maxWireBytes: Math.min(limits.maxWireBytes, value.wire.length * 3),
        maxNodes: Math.min(limits.maxNodes, value.wire.length),
        maxDepth: limits.maxDepth,
      }));
    }
    return value;
  };
  // Complete immutable DATA only; callers retain their original Read/Run
  // reservation and all current/physical duties. Shared by fresh and recovery.
  const inspectPreparedEffectCapturedRun = (prepared: unknown) => {
    const existing = recoveredEffectCaptures.get(prepared);
    if (existing !== undefined) return existing as Contract;
    const actual = moon.clientProgramRecoveredEffectCapturedRunLimits(prepared);
    const limits = Object.freeze({maxWireBytes:runtimeField(actual,0) as number, maxNodes:runtimeField(actual,1) as number, maxDepth:runtimeField(actual,2) as number});
    issuanceLimits(limits, 'original Effect captured Run');
    const captured = inspect(moon.clientProgramRecoveredEffectCapturedRunContract(prepared), limits);
    recoveredEffectCaptures.set(captured, prepared); recoveredEffectCaptures.set(prepared as object, captured);
    return captured;
  };
  const token = (value: unknown) => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  const inspectEvidence = (evidence: unknown) => {
    const value = Object.freeze({
      name: moon.strategyRunEvidenceName(evidence),
      identity: moon.strategyRunEvidenceIdentity(evidence),
      wire: moon.strategyRunEvidenceJson(evidence),
    });
    evidenceTokens.set(value, evidence);
    return value;
  };
  const evidenceToken = (value: unknown) => {
    const result = evidenceTokens.get(value);
    if (result === undefined) throw new TypeError('Foreign Run evidence');
    return result;
  };
  const inspectAdmission = (admission: unknown) => {
    const value = Object.freeze({kind: 'run-publication-admission'});
    admissionTokens.set(value, admission);
    return value;
  };
  const admissionToken = (value: unknown) => {
    const result = admissionTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign Run publication admission');
    }
    return result;
  };
  const inspectSnapshot = (snapshot: unknown) => {
    const value = Object.freeze({kind: 'captured-result-snapshot'});
    snapshotTokens.set(value, snapshot);
    return value;
  };
  const snapshotToken = (value: unknown) => {
    const result = snapshotTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Result snapshot');
    }
    return result;
  };
  const inspectEffectSource = (source: unknown) => {
    const value = Object.freeze({kind: 'captured-effect-source-artifact'});
    effectSourceTokens.set(value, source);
    return value;
  };
  const effectSourceToken = (value: unknown) => {
    const result = effectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Effect source artifact');
    }
    return result;
  };
  const localEffectSourceToken = (value: unknown) => {
    const result = localEffectSourceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign local Effect source evidence');
    }
    return result;
  };
  const inspectSourceAdvance = (advance: unknown) => {
    const value = Object.freeze({kind: 'pending-source-state-advance'});
    sourceAdvanceTokens.set(value, advance);
    return value;
  };
  const sourceAdvanceToken = (value: unknown) => {
    const result = sourceAdvanceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign pending source-state advance');
    }
    return result;
  };
  const issuanceLimits = (limits: WireLimits, label: string) => {
    if (limits === null || typeof limits !== 'object' ||
        !Number.isSafeInteger(limits.maxWireBytes) ||
        !Number.isSafeInteger(limits.maxNodes) ||
        !Number.isSafeInteger(limits.maxDepth) ||
        limits.maxWireBytes < 0 || limits.maxNodes < 0 ||
        limits.maxDepth < 0) {
      throw new TypeError(`Invalid ${label} issuance limits`);
    }
    return limits;
  };
  const captureContractLimits = (limits: WireLimits, label: string) => issuanceLimits(Object.freeze({
    maxWireBytes: limits?.maxWireBytes,
    maxNodes: limits?.maxNodes,
    maxDepth: limits?.maxDepth,
  }), label);
  const {resultReadControls, resultRetentionControls, resultDeliveryControls} =
    createResultDeliveryControls(moon, {token, inspect, issuanceLimits, captureContractLimits,
      issuedDeliveryGrants, issuedDeliveryAttempts, originalDeliveryAttempts});
  const {effectRunStateControls, runIdentityControls, publicationStateControls} =
    createRunStateControls(moon, {token, issuanceLimits,
      computationPreviewTokens, modelOriginalDocumentTokens});
  const {transitionControls, contractControls} = createPublicationContractControls(moon, {
    token, admissionToken, evidenceToken, inspect, captureContractLimits,
  });
  const contentPublicationControls = createContentPublicationControls(moon, {
    compiledRunTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
    inspectEvidence, inspect, captureContractLimits,
    serializationPlanTokens, serializationInputEvidenceTokens, inspectAdmission, evidenceToken, issuanceLimits,
  });
  const queryTimeControls = createQueryTimeControls(moon, {
    compiledRunTokens, token, currentControl: () => control!,
  });
  const contentInferenceControls = createContentInferenceControls(moon, {
    serializationPlanTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
  });
  const {captureControls, sourceControls, inventoryControls} = createEffectCaptureControls(moon, {
    computationPreviewTokens, recoveredEffectCaptures, localEffectArtifactTokens,
    token, inspect, inspectSnapshot, inspectEffectSource, inspectPreparedEffectCapturedRun,
    effectSourceToken, localEffectSourceToken, issuanceLimits,
  });
  const {capturedPreparationLimits, snapshotControls, effectFreeCaptureControls, effectfulCaptureControls} =
    createCapturedPublicationControls(moon, {
      capturedComputationPreparations, computationPreviewTokens, token, evidenceToken, snapshotToken,
      sourceAdvanceToken, contentCaptures, effectSourceToken, localEffectSourceToken,
      inspect, inspectSnapshot, inspectPreparedEffectCapturedRun, captureContractLimits,
    });
  const publicationValidationControls = createPublicationValidationControls(moon, {
    capturedComputationPreparations, recoveredEffectCaptures, computationPreviewTokens,
    token, issuanceLimits, capturedPreparationLimits,
  });
  const inferOriginalReadControls = createInferOriginalReadControls(moon, {
    compiledRunTokens, modelOriginalDocumentTokens, token, evidenceToken, inspectEvidence, issuanceLimits,
  });
  const modelPreparationControls = createModelPreparationControls(moon, {
    compiledRunTokens, serializationPlanTokens, token, compiledRunResult, currentControl: () => control!,
  });
  const effectPreparationControls = createEffectPreparationControls(moon, {
    admissionToken, token, evidenceToken, inspectAdmission, inspect, inspectEvidence,
    issuanceLimits, captureContractLimits, localEffectDependencyTokens, inferInvocationTokens,
    compiledRunTokens, serializationGenerationTokens, inspectAcquiredEffectEvidence,
  });
  const effectUnitResultControls = createEffectUnitResultControls(moon, {
    compiledRunTokens, localEffectDependencyTokens, localEffectArtifactTokens, localEffectManifestTokens,
    issuanceLimits, token, admissionToken, inspectLocalEffectArtifact, localEffectContext,
  });
  const {effectDependencyControls, effectArtifactControls} =
    createEffectArtifactControls(moon, {
      localEffectDependencyTokens, localEffectManifestTokens, localEffectArtifactTokens, localEffectArtifactSources,
      localEffectImportTokens, localEffectImportSources, localEffectSourceTokens, localEffectIdentityTokens,
      issuanceLimits, token, admissionToken, evidenceToken, effectSourceToken, inspectLocalEffectArtifact,
      localEffectContext, currentControl: () => control!,
    });
  const effectRecoveryControls = createEffectRecoveryControls(moon, {
    computationPreviewTokens, localEffectArtifactTokens, localEffectIdentityTokens,
    tableInputTokens, tablePreviewTokens, recoveredTablePreviewTokens,
    compiledContent, issuanceLimits, token, effectSourceToken, currentControl: () => control!,
  });
  const {pendingSourceAdvanceControls, effectPreviewControls} =
    createEffectPreviewControls(moon, {
      computationPreviewTokens, computationPreviewWires, issuanceLimits, token,
      evidenceToken, inspectEvidence, inspectSourceAdvance,
    });
  const effectPublicationControls = createEffectPublicationControls(moon, {
    localEffectArtifactTokens, computationPreviewTokens, recoveredEffectCaptures,
    issuanceLimits, captureContractLimits, token, inspect,
  });
  const runPlanControls = createRunPlanControls(moon, {
    compiledRunTokens, originalRunPlanTokens, compiledRunResult, issuanceLimits, token, evidenceToken,
    captureRequestExplanation, originalExplanationPlanWire, originalExplanationFactsWire, returnExplanationCapture,
    acknowledgeExplanationCapture, observeOriginalDispatchFailure, prepareLogicalObservation, currentControl: () => control!,
  });
  const inferAdmissionControls = createInferAdmissionControls(moon, {
    originalInferRunTokens, compiledRunTokens, restoredInferRuns, issuanceLimits,
    compiledRunResult, token, inspect, inspectEvidence, inspectAdmission, currentControl: () => control!,
  });
  const assembled = control = Object.freeze({
    executionFailureExplanation(cause: unknown) {
      if (typeof cause !== 'string' || cause.length > 96 ||
          typeof describeExecutionFailure !== 'function') return undefined;
      // Reuse the original Common export captured with this control. This is
      // inert catalogue DATA, never an original failure or read permission.
      const value = Reflect.apply(describeExecutionFailure, moon, [cause]);
      return typeof value === 'string' ? value : undefined;
    },
    seal(name: string, bodyWire: string, limits: WireLimits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    // Data-only private retention parser; no resource/custody/current grant.
    privateContinuationRetentionShape: moon.clientProgramPrivateContinuationRetentionShape,
    admit(name: string, completeWire: string, limits: WireLimits) {
      limits = captureContractLimits(limits, 'publication contract');
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    // SAME private opaque contract and original READ capacity. These are
    // representation observations, not copied DATA admission or authority.
    retainResultReadMetadata(parent: unknown, input: unknown, slot: number, original: unknown, mode: number) {
      const value = tokens.get(original);
      if (value === undefined) throw new TypeError('Foreign publication contract');
      return checked(moon.clientProgramRetainRequestResultMetadataContract(parent, input, slot, value, mode));
    },
    admitOriginal(original: Contract, limits: WireLimits) {
      const retained = contractBounds.get(original);
      if (retained === undefined || !tokens.has(original)) return undefined;
      const required = captureContractLimits(limits, 'publication contract');
      return retained.maxWireBytes <= required.maxWireBytes &&
        retained.maxNodes <= required.maxNodes &&
        retained.maxDepth <= required.maxDepth ? original : undefined;
    },
    preparedClientNormalizationEvidence(prepared: unknown, limits: WireLimits) {
      issuanceLimits(limits, 'Run evidence');
      // The same original already owns its measured journal. No Source read,
      // wire admission or fresh normalization occurs at publication time.
      return inspectEvidence(checked(moon.clientProgramPreparedLocalNormalizationEvidence(
        prepared, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    preparedClientAuthoringContextEvidence(prepared: unknown, original: unknown, limits: WireLimits) {
      issuanceLimits(limits, 'Run evidence');
      if (original === undefined) throw new TypeError('OriginalClientAuthoringContextRequired');
      return inspectEvidence(checked(moon.clientProgramPreparedAuthoringContextEvidence(
        prepared, original, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    sealRunEvidence(name: string, bodyWire: string, limits: WireLimits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunEvidence(name: string, completeWire: string, limits: WireLimits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueRunInvocation(template: unknown, observation: unknown, limits: WireLimits) {
      limits = captureContractLimits(limits, 'Run Invocation');
      return inspect(checked(moon.strategyIssueRunInvocation(
        evidenceToken(template),
        evidenceToken(observation),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    admitRunPublication(template: unknown, prepared: unknown, authorization: unknown, compiledPlan: unknown) {
      return inspectAdmission(checked(moon.strategyRunPublicationAdmit(
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      )));
    },
    admitCheckedClientRunPublication(
      checkedProgram: unknown, template: unknown, prepared: unknown, authorization: unknown, compiledPlan: unknown,
    ) {
      if (typeof moon.clientProgramAdmitPublication !== 'function') {
        throw new TypeError('Client Program admission is unavailable');
      }
      const admission = moon.clientProgramAdmitPublication(
        checkedProgram,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Program');
      }
      return inspectAdmission(admission);
    },
    ...contentInferenceControls,
    ...runPlanControls,
    ...inferAdmissionControls,
    prepareCheckedClientCompiledRun(checkedProgram: unknown, kind: string, policy: CompilationPolicy, inferGraph?: unknown, compilationOriginal?: unknown) {
      if (!['values', 'tasks', 'infer', 'serialization'].includes(kind)) {
        throw new TypeError('Invalid Client compilation profile');
      }
      if ((kind === 'infer' || kind === 'serialization') !== (inferGraph !== undefined)) {
        throw new TypeError(kind === 'serialization'
          ? 'Content compilation requires its checked graph'
          : 'Infer compilation requires its checked graph');
      }
      const serializationGraph = kind === 'serialization'
        ? serializationPlanTokens.get(inferGraph) : undefined;
      if (kind === 'serialization' && serializationGraph === undefined) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // The existing typed issuer below binds this artifact to the SAME
      // checked Program. A refused original never falls back to compilation.
      const compilation = compilationOriginal !== undefined ? compilationOriginal : compiledRunResult(kind === 'values'
        ? moon.clientProgramCompileLocalValues(checkedProgram)
        : kind === 'serialization'
          ? moon.clientProgramCompileLocalSerialization(checkedProgram, serializationGraph)
        : kind === 'infer'
          ? Array.isArray(inferGraph)
            ? moon.clientProgramCompileLocalInfers(checkedProgram, inferGraph)
            : moon.clientProgramCompileLocalInfer(checkedProgram, inferGraph)
          : moon.clientProgramCompileLocalTasks(checkedProgram),
      kind === 'values' ? 'RunHostCompilationRejected'
        : 'RunHostTaskCompilationRejected');
      // Pure staged originals use the existing Values/Tasks sum. The Request
      // Model compiler instead returns the original raw TaskCompilation;
      // its existing typed issuer validates that original and owner directly.
      // Unmigrated explicit compilation keeps its separate raw artifact entry.
      let value = compiledRunResult(compilationOriginal !== undefined
        ? kind === 'values'
          ? moon.clientProgramIssueOriginalValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : kind === 'infer' || kind === 'serialization'
            ? moon.clientProgramIssueTaskCompiledRun(checkedProgram,
              compilation, policy.executionContextCid, policy.hostPolicyCid,
              policy.expiresAt)
          : moon.clientProgramIssueOriginalTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
        : kind === 'values'
          ? moon.clientProgramIssueValuesCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt)
          : moon.clientProgramIssueTaskCompiledRun(checkedProgram,
            compilation, policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt), 'RunHostAdmissionRejected');
      if (kind === 'serialization' && compilationOriginal !== undefined &&
          moon.clientProgramCompiledRunSerializationGraph(value) !== serializationGraph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      if (kind === 'infer') {
        const original = policy.resultDataPolicy;
        if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
            typeof original.wire !== 'string') throw new TypeError('InvalidHostResultDataPolicy');
        value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(
          value, original.cid, original.wire, 1000000, 100000, 64),
        'RunHostResultPolicyRejected');
      }
      const result = Object.freeze({
        kind: kind as ClientCompilationKind,
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(
          moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(
          moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(
          moon.clientProgramCompiledRunAdmission(value)),
      });
      compiledRunTokens.set(result, value);
      return result;
    },
    admitSourceFreeResultPolicy(resultPolicy: ResultPolicy, limits: WireLimits): SourceFreeResultPolicy {
      if (resultPolicy?.kind !== 'data_policy' ||
          typeof resultPolicy.cid !== 'string' ||
          typeof resultPolicy.wire !== 'string' ||
          !Number.isSafeInteger(limits?.maxWireBytes) ||
          !Number.isSafeInteger(limits?.maxNodes) ||
          !Number.isSafeInteger(limits?.maxDepth)) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const original = checked(moon.clientProgramAdmitSourceFreeResultPolicyBody(
        resultPolicy.cid, resultPolicy.wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Common admits a captured dependency body tagged data_policy and supplies its CID and wire.
      return Object.freeze({kind: runtimeField(original, 0), cid: runtimeField(original, 1),
        wire: runtimeField(original, 2)}) as SourceFreeResultPolicy;
    },
    adoptCheckedClientEffectInferRun(allowed: unknown, definition: unknown, resultPolicy?: ResultPolicy | undefined, limits?: WireLimits) {
      if (resultPolicy !== undefined &&
          (resultPolicy?.kind !== 'data_policy' ||
           typeof resultPolicy.cid !== 'string' ||
           typeof resultPolicy.wire !== 'string' ||
           !Number.isSafeInteger(limits?.maxWireBytes) ||
           !Number.isSafeInteger(limits?.maxNodes) ||
           !Number.isSafeInteger(limits?.maxDepth))) {
        throw new TypeError('InvalidHostResultDataPolicy');
      }
      const value = checked(resultPolicy === undefined
        ? moon.clientProgramEffectAllowedInferRun(allowed)
        : moon.clientProgramEffectAllowedInferRunWithPolicyBody(
          allowed, resultPolicy.cid, resultPolicy.wire,
          limits!.maxWireBytes, limits!.maxNodes, limits!.maxDepth));
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Infer Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    compiledSourceFreeResultPolicy,
    // Borrow the checked Source-only Effect component from this exact keyed
    // plan and admitted Definition. A Model graph or an equal wire cannot
    // supply this nominal association, and this projection issues no Run.
    adoptCheckedClientEffectKeyedRun(allowed: unknown, definition: unknown, keyedPlan: unknown) {
      const value = compiledRunResult(moon.clientProgramEffectAllowedKeyedRun(
        allowed, keyedPlan, token(definition)), 'RunHostEffectKeyedAdmissionRejected');
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect keyed Run Definition differs from admission');
      }
      // The original acquired tuple already retains all publication bodies.
      // This private adapter token only borrows the nominal component; avoid
      // decoding those same immutable bodies to manufacture another tuple.
      const result = Object.freeze({kind: 'effect-keyed'});
      compiledRunTokens.set(result, value);
      return result;
    },
    bindCheckedClientRequestEffectKeyedOriginal(parent: unknown, input: unknown, operationPlan: unknown, compilation: unknown,
      compiled: CompiledRun, definition: unknown, keyedPlan: unknown, keyed: unknown, construct: (...args: unknown[]) => unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'effect-keyed' || typeof construct !== 'function') {
        throw new TypeError('Foreign Client compiled keyed Effect preparation');
      }
      return checked(construct(parent, input, operationPlan, compilation,
        value, token(definition), keyedPlan, keyed));
    },
    startInstalledEffectKeyedCaptureInput(managedRun: unknown, prepared: unknown, request: unknown, compiled: CompiledRun,
      definition: unknown, keyedPlan: unknown, keyed: unknown, captures: readonly SourceCapture[], limits: KeyedCaptureLimits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'effect-keyed' ||
          !Array.isArray(captures) || captures.some(value =>
            typeof (value.inputKind === 'whole-input'
              ? value.capture?.originalWholeInput : value.capture?.originalRowCapture) !== 'function')) {
        throw new TypeError('Foreign original keyed Effect capture');
      }
      return checked(moon.clientProgramStartInstalledEffectKeyedCaptureInput(
        managedRun, prepared, request, value, token(definition), keyedPlan, keyed,
        captures.map(value => value.inputKind === 'whole-input'
          ? value.capture.originalWholeInput() : value.capture.originalRowCapture()),
        limits.maxEntries, limits.maxNameBytes, limits.maxBytes, limits.maxWork));
    },
    // Borrow the original admitted Effect compilation. No fresh Program,
    // authorization, Source observation or Command approval is issued here.
    ...contentPublicationControls,
    compiledInferSourceFreeResultPolicy: compiledSourceFreeResultPolicy,
    compiledInferEvaluationPolicy(compiled: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      const original = moon.clientProgramCompiledRunEvaluationPolicy(value);
      return original === undefined ? undefined : Object.freeze({
        kind: runtimeField(original, 0) as string, cid: runtimeField(original, 1) as string, wire: runtimeField(original, 2) as string,
      });
    },
    checkClientCompiledRunOwner(compiled: unknown, checkedProgram: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram)) {
        throw new TypeError('Foreign Client compiled Run');
      }
    },
    checkClientCompiledEffectRunOwner(compiled: unknown, prepared: unknown, compilation: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          moon.clientProgramCompiledRunEffectMatches(value, prepared, compilation) !== true) {
        throw new TypeError('Foreign Client compiled Run');
      }
    },
    checkClientCompiledRunDefinition(compiled: unknown, definition: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client compiled Run Definition');
      }
    },
    checkClientCompiledLocalExecutionOwner(compiled: unknown, definition: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          moon.clientProgramCheckCompiledLocalExecutionOwner(value, token(definition)) !== true) {
        throw new TypeError('Foreign Client local execution owner');
      }
    },
    checkedClientRunCapturedContentCandidate(compiled: unknown, definition: unknown, acquisition: unknown, request: unknown,
      bindingWire: string, mediaType: string, contentCid: string, sizeBytes: number, limits: Tail<BindingParameters<'clientProgramRunCapturedContentCandidate'>, 8>) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramRunCapturedContentCandidate(value, token(definition),
        acquisition, request, bindingWire, mediaType, contentCid, sizeBytes, ...limits)) as CommonObject;
    },
    checkedClientStoredRunCapturedContentCandidate(compiled: unknown, definition: unknown, acquisition: unknown,
      originalWire: string, bindingWire: string, limits: Tail<BindingParameters<'clientProgramStoredRunCapturedContentCandidate'>, 5>) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) throw new TypeError('Foreign Client compiled Run');
      return checked(moon.clientProgramStoredRunCapturedContentCandidate(value,
        token(definition), acquisition, originalWire, bindingWire, ...limits)) as CommonObject;
    },
    recoveredContentIssuerKind(wire: string, limits: ContentLimits) {
      if (typeof wire !== 'string' || !(['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'] as const)
        .every(key => Number.isInteger(limits?.[key]) && limits[key] > 0 && limits[key] <= 2147483647)) {
        throw new TypeError('Invalid recovered Content reference limits');
      }
      return checked(moon.clientProgramRecoveredContentIssuerKind(wire,
        limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits));
    },
    recoveredSourceContentConstructionCapacity(wire: string, bindingWire: string, limits: ContentLimits, role: string = 'metadata') {
      if (typeof wire !== 'string' || typeof bindingWire !== 'string' ||
          typeof role !== 'string' ||
          !(['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'] as const).every(key =>
            Number.isInteger(limits?.[key]) && limits[key] > 0 && limits[key] <= 2147483647)) {
        throw new TypeError('Invalid recovered Source Content construction limits');
      }
      const capacity = moon.clientProgramRecoveredSourceContentConstructionCapacity(
        wire, bindingWire, limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits, role);
      if (capacity === undefined) throw new TypeError('Recovered Source Content construction unavailable');
      return capacity;
    },
    installedEffectKeyedOriginal(managedContext: InstalledEffectOriginal | undefined, prepared: unknown) {
      if (managedContext?.runtime !== moon || managedContext.closed ||
          managedContext.prepared !== prepared || managedContext.value === undefined ||
          managedContext.request === undefined) {
        throw new TypeError('Foreign recovered Effect Source original');
      }
      return checked(moon.clientProgramInstalledEffectKeyedOriginal(
        managedContext.value, prepared, managedContext.request));
    },
    effectKeyedOriginalSourceEvidenceFacts(original: unknown, prepared: unknown, request: unknown) {
      const facts = checked(moon.clientProgramEffectKeyedOriginalSourceEvidenceFacts(
        original, prepared, request));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(value => typeof value === 'string')) {
        throw new TypeError('Invalid recovered Effect Source facts');
      }
      return facts as unknown as readonly [string, string, string, string, string, string];
    },
    checkedRecoveredSourceContentCandidate(original: unknown, prepared: unknown, request: unknown,
      referenceWire: string, bindingWire: string, limits: Tail<BindingParameters<'clientProgramRecoveredSourceContentCandidate'>, 5>) {
      return checked(moon.clientProgramRecoveredSourceContentCandidate(original,
        prepared, request, referenceWire, bindingWire, ...limits)) as CommonObject;
    },
    compiledRunResultTransformation(compiled: unknown, checkedProgram: unknown, result: number) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || !Number.isSafeInteger(result) || result < 0) {
        throw new TypeError('Foreign Client compiled Result');
      }
      return compiledRunResult(
        moon.clientProgramCompiledRunResultTransformation(
          value, checkedProgram, result), 'RunHostResultSelectionRejected');
    },
    ...queryTimeControls,
    defineCheckedClientCompiledRun(compiled: CompiledRun, {namespaceId, runId,
      createdAt, validUntil, retainedDefinitionWire}: DefinitionOptions) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      return inspect(compiledRunResult(retainedDefinitionWire === undefined
        ? moon.clientProgramIssueCompiledRunDefinition(value,
          namespaceId, runId, createdAt, validUntil)
        : moon.clientProgramAdmitCompiledRunDefinition(value,
          retainedDefinitionWire), compiled.kind !== 'values'
        ? 'RunHostTaskDefinitionRejected'
        : retainedDefinitionWire === undefined
          ? 'RunHostSourceFreeDefinitionRejected'
          : 'RunHostSourceFreeAdmissionRejected'));
    },
    issueCheckedClientCompiledInvocation(compiled: CompiledRun, definition: unknown,
      {dataPolicyCid, source}: InvocationOptions, limits: WireLimits, publicationPreparation?: unknown, preparedProgram?: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) {
        throw new TypeError('Foreign Client compiled Run');
      }
      limits = captureContractLimits(limits, 'Client Run Invocation');
      if (source !== undefined) {
        const sources = source.sources ?? [{captured: source.captured, sourceEvidence: source.sourceEvidence}];
        if (publicationPreparation === undefined || preparedProgram === undefined || compiled.kind !== 'tasks' ||
            !Array.isArray(sources) || sources.length < 1 ||
            sources.some(({captured}) => captured?.capture === undefined || captured?.identity === undefined ||
              captured?.logicalInput === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        // The adopted original Plan selects the semantic input boundary.
        // A missing/copy/foreign capture cannot fall back to a Query ABI.
        const kind = checked(moon.clientProgramInstalledManagedPublicationSourceKind(
          publicationPreparation, preparedProgram));
        if (kind === 'whole-input') {
          if (source.keyedObservation !== undefined) throw new TypeError('Invalid original publication invocation profile');
          const originals = sources.map(({captured}) => {
            if (captured.inputKind !== 'whole-input') throw new TypeError('Invalid original whole Source capture');
            const capture = captured.capture;
            const original = Object.getOwnPropertyDescriptor(capture, 'originalWholeInput');
            if (original === undefined || !Object.hasOwn(original, 'value') || typeof original.value !== 'function') {
              throw new TypeError('Invalid original whole Source capture');
            }
            return Reflect.apply(original.value, capture, []);
          });
          const originalArguments = sources.length === 1
            ? [originals[0], sources[0].captured.identity, evidenceToken(sources[0].sourceEvidence), sources[0].captured.logicalInput]
            : [originals, sources.map(({captured}) => captured.identity), sources.map(({sourceEvidence}) => evidenceToken(sourceEvidence)),
              sources.map(({captured}) => captured.logicalInput)];
          const issue = moon[sources.length === 1 ? 'clientProgramIssueWholeSourcePublicationInvocation'
            : 'clientProgramIssueWholeSourcesPublicationInvocation'];
          const issued = compiledRunResult(Reflect.apply(issue, moon, [
            publicationPreparation, preparedProgram, value, token(definition), ...originalArguments,
            source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth]), 'RunHostTaskInvocationRejected');
          return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
            invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
        }
        if (kind !== 'query' || sources.some(({captured}) => captured.requirement === undefined)) {
          throw new TypeError('Invalid original publication invocation profile');
        }
        const issued = compiledRunResult(moon.clientProgramIssueCapturedPublicationInvocation(
          publicationPreparation, preparedProgram, value, token(definition),
          sources.map(({captured}) => captured.capture.source()), sources.map(({captured}) => captured.identity),
          sources.map(({captured}) => captured.requirement), sources.map(({sourceEvidence}) => evidenceToken(sourceEvidence)),
          sources.map(({captured}) => captured.logicalInput), source.keyedObservation,
          source.authorityScopeCid, dataPolicyCid, source.captureStartedAt, source.captureCompletedAt,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostTaskInvocationRejected');
        return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
          invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
      }
      if (publicationPreparation !== undefined && compiled.kind !== 'values' && compiled.kind !== 'tasks') {
        throw new TypeError('Invalid original publication invocation profile');
      }
      const issued = compiledRunResult(publicationPreparation !== undefined
        ? moon.clientProgramIssuePublicationInvocation(publicationPreparation,
          preparedProgram, value, token(definition), dataPolicyCid,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : (compiled.kind !== 'values'
          ? moon.clientProgramIssueCompiledSourceFreeTaskInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
          : moon.clientProgramIssueCompiledValuesInvocation(value,
            token(definition), dataPolicyCid,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth))
      , 'RunHostInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    admitInferCapturedInput(prepared: unknown, captured: CapturedInput, sourceEvidence: unknown, authorityScopeCid: string,
      dataPolicyCid: string, startedAt: string, completedAt: string) {
      return checked(moon.clientProgramAdmitInferCapturedInput(prepared,
        captured.inferStep, captured.capturedSource, captured.identity, captured.requirement,
        captured.logicalInput, evidenceToken(sourceEvidence), authorityScopeCid,
        dataPolicyCid, startedAt, completedAt));
    },
    admitComposedInferSources(occurrence: unknown, captures: readonly ComposedSourceCapture[], sourceEvidence: readonly unknown[], authorityScopeCid: string,
      startedAt: string, completedAt: string, keyed?: unknown) {
      if (captures.some(value => value.inputKind === 'whole-input')) {
        if (captures.some(value => value.inputKind !== 'whole-input' || value.wholeCapacity === undefined)) {
          throw new TypeError('Unsupported mixed original Model Source inputs');
        }
        return checked(moon.clientProgramAdmitComposedInferWholeSources(occurrence,
          captures.map(value => value.capture.source()), captures.map(value => value.identity),
          captures.map(value => value.wholeCapacity), captures.map(value => value.logicalInput),
          sourceEvidence.map(evidenceToken), authorityScopeCid, startedAt, completedAt, keyed));
      }
      return checked(moon.clientProgramAdmitComposedInferSources(occurrence,
        captures.map(value => value.capture.source()), captures.map(value => value.identity),
        captures.map(value => value.requirement), captures.map(value => value.logicalInput),
        sourceEvidence.map(evidenceToken), authorityScopeCid, startedAt, completedAt, keyed));
    },
    composedInferSourcesFor(occurrence: unknown, original: unknown) {
      return moon.clientProgramComposedInferSourcesMatch(original, occurrence) === true ? original : undefined;
    },
    startOriginalComposedKeyedPrefix(compiled: CompiledRun, definition: unknown, graph: unknown, scope: unknown, keyed: unknown, captures: readonly SourceCapture[], prefix: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalComposedKeyedPrefix(scope,
        value, token(definition), graph, keyed,
        captures.map(value => value.capture.originalRowCapture()), prefix));
    },
    startInstalledOriginalComposedKeyedPrefix(managedRun: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, scope: unknown, keyed: unknown, captures: readonly SourceCapture[]) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (captures.some(value => value.inputKind === 'whole-input')) {
        if (captures.some(value => value.inputKind !== 'whole-input' ||
            typeof value.capture.originalCapturedInput !== 'function')) {
          throw new TypeError('Unsupported mixed original keyed Source inputs');
        }
        return checked(moon.clientProgramStartInstalledOriginalComposedKeyedInputPrefix(managedRun,
          scope, value, token(definition), graph, keyed,
          captures.map(value => value.capture.originalCapturedInput())));
      }
      return checked(moon.clientProgramStartInstalledOriginalComposedKeyedPrefix(managedRun,
        scope, value, token(definition), graph, keyed,
        captures.map(value => value.capture.originalRowCapture())));
    },
    prepareInstalledOriginalComposedKeyedHostInput(managedRun: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, scope: unknown, keyed: unknown, captures: readonly SourceCapture[], host: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || host === undefined ||
          captures.some(value => value.inputKind !== 'whole-input' ||
            typeof value.capture.originalCapturedInput !== 'function')) {
        throw new TypeError('Foreign original keyed Host prefix');
      }
      const originals = captures.map(value => value.capture.originalCapturedInput());
      const originalDefinition = token(definition);
      const left = checked(moon.clientProgramInstalledOriginalComposedKeyedHostInputLeft(
        managedRun, scope, value, originalDefinition, graph, keyed, originals, host));
      if (left !== undefined) return Object.freeze({left});
      return Object.freeze({prefix: checked(moon.clientProgramStartInstalledOriginalComposedKeyedHostPrefix(
        managedRun, scope, value, originalDefinition, graph, keyed, originals, host))});
    },
    prepareGenericEffectKeyedLookupSourceMetadata(parent: unknown, lookup: unknown, captures: readonly SourceCapture[], sources: readonly SourceInput[], selection: RetentionSelection, limits: WireLimits) {
      limits = captureContractLimits(limits, 'generic keyed Source metadata');
      if (parent === undefined || !Array.isArray(captures) || captures.length !== 1 ||
          !Array.isArray(sources) || sources.length !== 1 || sources[0]?.captured !== captures[0] ||
          captures[0].identity === undefined || captures[0].logicalInput === undefined ||
          sources[0].sourceEvidence === undefined) {
        throw new TypeError('ForeignOriginalGenericKeyedSourceMetadata');
      }
      // Borrow these SAME typed capture/observation originals. The generic
      // Owner checks their complete retained bodies before dispatch starts.
      return checked(moon.clientProgramEffectKeyedGenericSourceMetadata(parent, lookup,
        captures[0].identity, captures[0].logicalInput, evidenceToken(sources[0].sourceEvidence),
        selection.retentionContractCid, selection.availableUntil, selection.deleteBy,
        selection.metadataDeleteBy, selection.metadataRetentionPolicyCid,
        selection.clockContractCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    finishGenericEffectKeyedLookupPublicationInput(parent: unknown, lookup: unknown, observedAt: string, limits: WireLimits) {
      limits = captureContractLimits(limits, 'generic keyed Source completion');
      return checked(moon.clientProgramEffectKeyedGenericPublicationInput(parent, lookup, observedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    prepareKeyedLookupSourceMetadata(lookup: unknown, request: unknown, captures: readonly SourceCapture[], sources: readonly SourceInput[],
      retentionSelection: RetentionSelection, outputLimits: unknown, maxWork: number, limits: WireLimits, fileReadDeclarations: readonly unknown[]) {
      limits = captureContractLimits(limits, 'keyed Source metadata');
      if (!Array.isArray(captures) || !Array.isArray(sources) || !Array.isArray(fileReadDeclarations) ||
          !Object.isFrozen(fileReadDeclarations) || captures.length < 1 ||
          captures.length !== sources.length || !validResultOutputLimits(outputLimits) ||
          !Number.isSafeInteger(maxWork) || maxWork < 1 ||
          captures.some((captured, index) => sources[index]?.captured !== captured ||
            sources[index]?.sourceEvidence === undefined)) {
        throw new TypeError('ForeignOriginalKeyedSourceMetadata');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => outputLimits[name]) as BindingParameters<'clientProgramEffectInputExportLimits'>);
      if (exported === undefined) throw new TypeError('Invalid original keyed input limits');
      const selected = retentionSelection;
      const retention = checked(moon.clientProgramKeyedLookupPrepareRetention(lookup,
        request, selected.retentionContractCid, selected.availableUntil, selected.deleteBy,
        selected.metadataDeleteBy, selected.metadataRetentionPolicyCid,
        selected.clockContractCid, limits.maxWireBytes));
      checked(moon.clientProgramKeyedLookupPrepareLeftIdentity(lookup, exported, maxWork));
      for (let index = 0; index < captures.length; index++) {
        const captured = captures[index], observation = evidenceToken(sources[index].sourceEvidence);
        if (captured.inputKind === 'whole-input') {
          checked(moon.clientProgramKeyedLookupBindWholeSourceMetadata(lookup, index,
            captured.identity, captured.logicalInput, observation, request, retention,
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        } else {
          checked(moon.clientProgramKeyedLookupBindQuerySourceMetadata(lookup, index,
            captured.requirement, captured.identity, captured.logicalInput, observation,
            request, retention, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        }
      }
      checked(moon.clientProgramKeyedLookupPrepareLeftRelation(lookup, request, retention,
        moon.clientRequestAuthorityScopeCid(request),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      checked(moon.clientProgramKeyedLookupBindDeclaredFilePhysicalSource(lookup, fileReadDeclarations));
      return inspect(retention, limits);
    },
    keyedLookupActivationJournalRecord(original: unknown, request: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, limits: WireLimits, sourceOriginal?: unknown) {
      limits = captureContractLimits(limits, 'keyed lookup activation');
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' &&
          (compiled.kind !== 'effect-keyed' || sourceOriginal === undefined))) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const wire = checked(compiled.kind === 'effect-keyed'
        ? moon.clientProgramEffectKeyedDeclaredFileActivationRecord(
          original, request, sourceOriginal, limits.maxWireBytes)
        : moon.clientProgramKeyedLookupDeclaredFileActivationRecord(
          original, request, value, token(definition), graph, limits.maxWireBytes));
      const fields = moon.clientProgramKeyedLookupActivationFields(original);
      return Object.freeze({wire, batchCid: runtimeField(fields, 0),
        slotCid: runtimeField(fields, 1), batchIndex: runtimeField(fields, 2),
        batchCount: runtimeField(fields, 3)});
    },
    keyedLookupActivationJournalCurrent(original: unknown, request: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, sourceOriginal?: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) return false;
      return compiled.kind === 'effect-keyed'
        ? sourceOriginal !== undefined && moon.clientProgramEffectKeyedNativeActivationMatches(
          original, request, sourceOriginal) === true
        : compiled.kind === 'infer' && moon.clientProgramKeyedLookupActivationMatches(
          original, request, value, token(definition), graph) === true;
    },
    prepareKeyedLookupRawCapture(keyedRequest: unknown, compiled: CompiledRun, definition: unknown, retention: unknown,
      storage: PrivateStorage, contentCid: string, bytes: number, at: string, nowMs: bigint, limits: ContentLimits) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' && compiled.kind !== 'effect-keyed')) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const raw = checked(moon.clientProgramKeyedLookupPrepareDeclaredFileRawCapture(
        value, token(definition), keyedRequest, token(retention), storage.namespaceId,
        storage.storeAuthorityCid, storage.availabilityEvidenceCid, storage.issuerContractCid,
        contentCid, bytes, at, nowMs, limits.maxBytes, limits.maxNodes,
        limits.maxDepth, limits.maxTextUnits));
      const fields = checked(moon.clientProgramKeyedLookupRawStoreBinding(raw));
      return Object.freeze({original:raw, binding:Object.freeze({name:'lookup_raw_response',
        semanticCid:runtimeField(fields,0), holdingCid:runtimeField(fields,1),
        wire:runtimeField(fields,2), contentCid:runtimeField(fields,3),
        byteCount:Number(runtimeField(fields,4))})});
    },
    prepareKeyedLookupCapturedPage(keyedRequest: unknown, capture: unknown, raw: unknown, at: string, outputLimits: unknown, maxWork: number, limits: WireLimits) {
      limits = captureContractLimits(limits, 'keyed captured page');
      if (!validResultOutputLimits(outputLimits)) throw new TypeError('Invalid keyed page limits');
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => outputLimits[name]) as BindingParameters<'clientProgramEffectInputExportLimits'>);
      if (exported === undefined) throw new TypeError('Invalid keyed page limits');
      return checked(moon.clientProgramKeyedLookupPrepareCapturedPage(keyedRequest, capture,
        raw, at, exported, maxWork, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    keyedLookupPageJournalRecord(page: unknown, keyedRequest: unknown, request: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, limits: WireLimits, sourceOriginal?: unknown) {
      limits = captureContractLimits(limits, 'keyed lookup page');
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || (compiled.kind !== 'infer' &&
          (compiled.kind !== 'effect-keyed' || sourceOriginal === undefined))) {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const wire = checked(compiled.kind === 'effect-keyed'
        ? moon.clientProgramEffectKeyedDeclaredFilePageRecord(
          page, keyedRequest, request, sourceOriginal, limits.maxWireBytes)
        : moon.clientProgramKeyedLookupDeclaredFilePageRecord(
          page, keyedRequest, request, value, token(definition), graph, limits.maxWireBytes));
      const fields = moon.clientProgramKeyedLookupCapturedPageFields(page);
      return Object.freeze({wire, batchCid: runtimeField(fields, 0),
        slotCid: runtimeField(fields, 1), activationCid: runtimeField(fields, 2),
        batchIndex: runtimeField(fields, 3)});
    },
    keyedLookupPageJournalCurrent(page: unknown, keyedRequest: unknown, request: unknown, compiled: CompiledRun, definition: unknown, graph: unknown, sourceOriginal?: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined) return false;
      return compiled.kind === 'effect-keyed'
        ? sourceOriginal !== undefined && moon.clientProgramEffectKeyedNativeCapturedPageMatches(
          page, keyedRequest, request, sourceOriginal) === true
        : compiled.kind === 'infer' && moon.clientProgramKeyedLookupCapturedPageMatches(
          page, keyedRequest, request, value, token(definition), graph) === true;
    },
    takeSourceEvidenceOriginal(capture: unknown) {
      const take = Object.getOwnPropertyDescriptor(capture ?? {}, 'takeSourceEvidenceOriginal')?.value;
      if (typeof take !== 'function') throw new TypeError('InstalledSourceEvidenceUnavailable');
      const evidence = inspectEvidence(Reflect.apply(take, capture, []));
      if (evidence.name !== 'source_evidence') throw new TypeError('InvalidInstalledSourceEvidence');
      return evidence;
    },
    keyedLookupPublicationEvidence(original: unknown) {
      const value = moon.clientProgramKeyedLookupObservationOriginals(original);
      if (value === undefined) throw new TypeError('Foreign keyed lookup observation');
      return Object.freeze({source: inspectEvidence(runtimeField(value, 1)),
        logicalRelationCid: runtimeField(value, 2)});
    },
    // Reuse the compiled owner retained at Run admission. The physical
    // adapter supplies its opaque execution and bounded verification owner;
    // this does not adopt external attempts or grant publication authority.
    modelPrivateHoldingCid(definition: unknown, storeAuthorityCid: string, role: string, slot: number) {
      const identity = moon.clientProgramModelPrivateHoldingCid(
        token(definition), storeAuthorityCid, role, slot);
      if (identity === undefined) throw new TypeError('InvalidModelPrivateHolding');
      return identity;
    },
    modelScopedPrivateHoldingCid(definition: unknown, storeAuthorityCid: string, entry: HoldingEntry, role: string, phase: string = 'settled') {
      const identity = moon.clientProgramModelScopedPrivateHoldingCid(token(definition),
        storeAuthorityCid, entry.scopeCid, entry.slotCid, entry.attemptCid,
        entry.attemptIndex, phase, role);
      if (identity === undefined) throw new TypeError('InvalidModelScopedPrivateHolding');
      return identity;
    },
    bindCheckedClientInferRun(compiled: CompiledRun, execution: unknown, definition: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferRun(execution,
        value, token(definition)));
    },
    // Inspect only the original Core execution's issued value. Wire admission
    // remains a separate path; this view does not issue Store or send authority.
    inspectInferInvocationEvidence(originalMoon: unknown, execution: unknown, slot: number) {
      if (originalMoon !== moon || !Number.isSafeInteger(slot) || slot < 0 ||
          slot > 2147483647 ||
          typeof moon.clientProgramInferInvocationEvidence !== 'function') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      const evidence = moon.clientProgramInferInvocationEvidence(execution, slot);
      if (evidence === undefined) return undefined;
      if (moon.strategyRunEvidenceName(evidence) !== 'model_invocation_evidence') {
        throw new TypeError('Foreign Infer invocation evidence');
      }
      return inspectEvidence(evidence);
    },
    bindCheckedClientInferDispatch(compiled: CompiledRun, execution: unknown, definition: unknown,
      {account, principalId, at, delegated, observeAccount, observeAt}: DispatchOptions) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      if (typeof observeAccount !== 'function' ||
          typeof observeAt !== 'function') {
        throw new TypeError('Missing current Infer dispatch observations');
      }
      const admitted = checked(moon.clientProgramIssueInferDispatchAdmission(
        value, token(definition), account, principalId, at, delegated,
        observeAccount, observeAt));
      return checked(moon.clientProgramBindInferDispatchAdmission(execution,
        admitted));
    },
    readCheckedClientComposedInferSavedInputScope(compiled: CompiledRun, definition: unknown, occurrence: unknown,
      graph: unknown, snapshotWire: string, authorityScopeCid: string, custodyAvailable: () => boolean) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedComposedInferInputScope(value, token(definition),
        occurrence, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    readCheckedClientInferSavedInputScope(compiled: CompiledRun, definition: unknown, preparedProgram: unknown,
      step: number, graph: unknown, snapshotWire: string, authorityScopeCid: string, custodyAvailable: () => boolean) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' || typeof custodyAvailable !== 'function') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadSavedInferInputScope(value, token(definition),
        preparedProgram, step, graph, snapshotWire, authorityScopeCid, custodyAvailable));
    },
    bindCheckedClientInferModelScope(compiled: CompiledRun, execution: unknown, definition: unknown,
      preparedCallSet: unknown, {scope, provider, expectedBoundary}: ModelScopeOptions) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      // bindInferRun already retained this exact compilation in the active
      // owner. The portable binder compares actual input and every fixed call.
      checked(moon.clientProgramBindInferRun(execution, value, token(definition)));
      return checked(moon.clientProgramBindInferModelScope(execution,
        preparedCallSet, evidenceToken(scope), evidenceToken(provider), {...expectedBoundary,
          task_index: BigInt(expectedBoundary.task_index),
          strategy_revision: BigInt(expectedBoundary.strategy_revision)}));
    },
    bindCheckedClientInferModelDispatch(compiled: CompiledRun, execution: unknown, definition: unknown,
      preparedCallSet: unknown, scope: unknown, {account, principalId, at, delegated,
        observeAccount, observeAt, enterCall}: DispatchOptions & {enterCall: BindingParameters<'clientProgramBindInferModelDispatch'>[3]}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof enterCall !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelDispatch(execution, preparedCallSet,
        admitted, enterCall));
      return admitted;
    },
    // Installation-only async port. It uses the same original scoped
    // admission issuer; a persistence observation is never a fresh permit.
    bindCheckedClientInferModelEntryPersistence(compiled: CompiledRun, execution: unknown, definition: unknown,
      preparedCallSet: unknown, scope: unknown, {account, principalId, at, delegated,
        observeAccount, observeAt, beginEntry}: DispatchOptions & {beginEntry: BindingParameters<'clientProgramBindInferModelEntryPersistence'>[3]}) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function' ||
          typeof beginEntry !== 'function') {
        throw new TypeError('Foreign Client compiled Infer dispatch');
      }
      const admitted = checked(moon.clientProgramIssueScopedInferDispatchAdmission(
        value, token(definition), scope, account, principalId, at, delegated,
        observeAccount, observeAt));
      checked(moon.clientProgramBindInferModelEntryPersistence(execution,
        preparedCallSet, admitted, beginEntry));
      return admitted;
    },
    ...modelPreparationControls,
    ...inferOriginalReadControls,
    // Private installed Node inputs only. Canonical/body admission does not
    // issue capture authority, funded capacity or public async support.
    selectInstalledInitialJevDecisionProfile() {
      // Preserve the original Common value from THIS installed runtime. This
      // is the already registered physical precision selection, not a JS
      // reconstruction, provider capability, numerical loan or dispatch grant.
      if (typeof moon.clientProgramInitialJevDecisionProfile !== 'function') {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      const profile = moon.clientProgramInitialJevDecisionProfile();
      if (profile === undefined || profile === null) {
        throw new TypeError('Installed native Decision probability profile unavailable');
      }
      return profile;
    },
    readInstalledModelResponseProfile(wire: string, expectedCid: string, limits: WireLimits & Readonly<{maxMembers: number; maxWork: number}>) {
      issuanceLimits(limits, 'Model response profile');
      if ((['maxWireBytes', 'maxNodes', 'maxDepth', 'maxMembers', 'maxWork'] as const)
          .some(key => !Number.isSafeInteger(limits[key]) || limits[key] < 0 ||
            limits[key] > 2147483647) ||
          typeof wire !== 'string' || wire.length > limits.maxWireBytes) {
        throw new TypeError('Invalid Model response profile limits');
      }
      return checked(moon.clientProgramReadModelResponseProfile(wire, expectedCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        limits.maxMembers, limits.maxWork));
    },
    bindInstalledModelRawCapturePolicy(policy: unknown, retention: unknown, metadata: unknown, clock: unknown, data: unknown) {
      return checked(moon.clientProgramBindModelRawCapturePolicy(
        evidenceToken(policy), retention, metadata, clock, data));
    },
    installedModelRawSelectionOriginals({retention, metadata, clock, data}: RawSelection) {
      // Existing Common bodies remain the authority for exact kind/CID/wire.
      // This projection cannot issue policy adoption, raw custody or sending.
      return moon.clientProgramModelRawSelectionOriginals(retention, metadata,
        clock, data).map(value => Object.freeze({kind: runtimeField(value, 0) as string,
          cid: runtimeField(value, 1) as string, wire: runtimeField(value, 2) as string}));
    },
    issueCheckedClientInferRawCapturePolicy(compiled: CompiledRun, definition: unknown, dispatch: unknown, scope: unknown,
      {profile, installation, probability, storeAuthorityCid, retention, metadata,
        clock, data, selectedAt, availableUntil, deleteBy, extensionCeilingAt,
        metadataDeleteBy}: RawCaptureOptions) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer raw policy');
      }
      return checked(moon.clientProgramIssueInferRawCapturePolicy(value,
        token(definition), dispatch, scope, profile, installation, probability,
        storeAuthorityCid, retention, metadata, clock, data, selectedAt,
        availableUntil, deleteBy, extensionCeilingAt, metadataDeleteBy));
    },
    registerCheckedClientInferRawCapture(compiled: CompiledRun, definition: unknown, dispatch: unknown, scope: unknown,
      {policy, profile, installation, probability, account, at, storeAuthorityCid,
        selectionAvailable, observeAccount, observeAt, delegated}: RawCaptureRegistration) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          typeof selectionAvailable !== 'function' ||
          typeof observeAccount !== 'function' || typeof observeAt !== 'function') {
        throw new TypeError('Foreign Client compiled Infer raw capture');
      }
      return checked(moon.clientProgramRegisterInferRawCapture(value,
        token(definition), dispatch, scope, policy, profile, installation,
        probability, account, at, storeAuthorityCid, selectionAvailable,
        observeAccount, observeAt, delegated));
    },
    bindCheckedClientInferInvocation(compiled: CompiledRun, execution: unknown, definition: unknown,
      verified: unknown, invocation: unknown, dataPolicyCid: string) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramBindInferInvocation(execution,
        value, token(definition), verified, token(invocation), dataPolicyCid));
    },
    bindIssuedClientInferInvocation(compiled: CompiledRun, execution: unknown, definition: Contract, issued: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      const binding = checked(moon.clientProgramBindIssuedInferInvocation(
        execution, value, token(definition), issued));
      const result = Object.freeze({binding,
        observation: inspectEvidence(
          moon.clientProgramInferInvocationBindingObservation(binding)),
        invocation: inspect(
          moon.clientProgramInferInvocationBindingInvocation(binding))});
      inferInvocationTokens.set(result, {compiled: value, definition});
      return result;
    },
    checkedClientEffectInferInvocation(checkedEffect: unknown, compilation: unknown, definition: Contract, issued: IssuedInvocation) {
      const retained = inferInvocationTokens.get(issued);
      if (retained === undefined || retained.definition.identity !== definition.identity ||
          !moon.clientProgramCompiledRunEffectMatches(retained.compiled, checkedEffect, compilation) ||
          !moon.clientProgramCheckCompiledRunDefinition(retained.compiled, token(definition)) ||
          moon.clientProgramInferInvocationBindingObservation(issued.binding) === undefined) {
        throw new TypeError('Foreign Effect Infer Invocation');
      }
      return Object.freeze({observation: issued.observation, invocation: issued.invocation,
        owner: token(issued.invocation)});
    },
    captureCheckedClientInferModelObservation(issued: IssuedInvocation, scan: unknown, receipt: unknown, limits: WireLimits, preconsumer?: unknown) {
      issuanceLimits(limits, 'Original Model observation');
      if (!inferInvocationTokens.has(issued)) {
        throw new TypeError('Foreign Model observation Invocation');
      }
      const prior = preconsumer === undefined ? undefined : localEffectDependencyTokens.get(preconsumer);
      if (preconsumer !== undefined && prior?.kind !== 'preconsumer_model') {
        throw new TypeError('ForeignPreconsumerModelOriginal');
      }
      const original = prior === undefined
        ? moon.clientProgramIssueInferInvocationBindingOriginalModelObservation(
          issued.binding, receipt, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : checked(moon.clientProgramBindPreconsumerModelUnitObservation(issued.binding, (prior as ModelEffectDependency).original));
      if (original === undefined) throw new TypeError('Foreign Model outcome receipt');
      const body = moon.clientProgramOriginalModelObservationBody(original);
      const coordinates = moon.clientProgramOriginalModelObservationCoordinates(original);
      // This exported Array Option is boxed by the pinned compiler. The
      // adjacent tuple/String projections retain their own unboxed layouts.
      const inputBodies = moon.clientProgramOriginalModelObservationInputBodies(original);
      const inputs = runtimeIsBoxedSome(inputBodies) ? runtimeField(inputBodies, 0) : undefined;
      const outcomes = moon.clientProgramInferModelIdentityBody(scan, receipt);
      if (typeof runtimeOptionalField(body, 0) !== 'string' ||
          typeof runtimeOptionalField(body, 1) !== 'string' || coordinates === undefined ||
          !Array.isArray(inputs) || typeof outcomes !== 'string') {
        throw new TypeError('Original Model dependency bodies unavailable');
      }
      const task = runtimeField(coordinates, 0) as number, unit = runtimeField(coordinates, 1) as number,
        step = runtimeField(coordinates, 2) as number;
      if (!Number.isSafeInteger(task) || task < 0 ||
          !Number.isSafeInteger(unit) || unit < 0 ||
          !Number.isSafeInteger(step) || step < 0) {
        throw new TypeError('Foreign Model Unit coordinate');
      }
      const value = Object.freeze({task, unit, step,
        bodies: Object.freeze([
          Object.freeze({kind: 'local_model_observation', cid: runtimeField(body, 0) as string,
            wire: runtimeField(body, 1) as string}),
          ...inputs.map(entry => Object.freeze({kind: runtimeField(entry, 0) as string,
            cid: runtimeField(entry, 1) as string, wire: runtimeField(entry, 2) as string})),
          Object.freeze({kind: 'relation_value',
            cid: moon.clientProgramEffectInputExportLogicalCid(receipt), wire: outcomes}),
          Object.freeze({kind: 'relation_schema',
            cid: moon.clientProgramEffectInputExportSchemaCid(receipt),
            wire: moon.clientProgramEffectInputExportSchemaWire(receipt)}),
        ])});
      inferModelObservationTokens.set(value, {original, issued});
      return value;
    },
    issueOriginalModelEffectEvidence(model: ModelObservation, retention: unknown, imports: Readonly<{bodies: readonly EvidenceBody[]}> | undefined, limits: WireLimits, deferCatalogs = false) {
      issuanceLimits(limits, 'Original Model Effect dependency');
      const retained = inferModelObservationTokens.get(model);
      const imported = imports === undefined ? undefined : localEffectDependencyTokens.get(imports);
      if (retained === undefined || !inferInvocationTokens.has(retained.issued) ||
          imports !== undefined && imported?.kind !== 'imported') {
        throw new TypeError('Foreign Model Effect originals');
      }
      const result = moon.clientProgramOriginalModelAcquiredEffectEvidence(
        retained.original, token(retention), limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth, imported?.issued, (imported as ImportedEffectDependency | undefined)?.originalSources ?? []);
      let acquired;
      try { acquired = checked(result); }
      catch (cause) {
        try {
          const kind = moon.clientProgramOriginalModelAcquiredEffectEvidenceIssueKind?.(result);
          if (typeof kind === 'string') Object.defineProperty(cause, 'primaryDiagnostic', {
            value: Object.freeze({code: 'MoonBitHostFailure',
              phase: 'original_model_acquired_effect_evidence', kind,
              task: model.task, unit: model.unit, step: model.step}),
          });
        } catch { /* Optional DATA projection cannot replace the original failure. */ }
        throw cause;
      }
      const direct = moon.clientProgramOriginalModelAcquiredEffectSources(acquired)
        .map(source => inspectAcquiredEffectEvidence(source, retention, limits, deferCatalogs));
      const barrier = moon.clientProgramOriginalModelAcquiredEffectLookupBarrier(acquired);
      const lookupBodies = (checked(moon.clientProgramOriginalModelAcquiredLookupDependencyBodies(acquired)) as readonly unknown[])
        .map(body => Object.freeze({kind:runtimeField(body,0) as string, cid:runtimeField(body,1) as string,
          wire:runtimeField(body,2) as string}));
      const value = Object.freeze({
        invocation: moon.clientProgramOriginalModelAcquiredEffectInvocation(acquired),
        bodies: Object.freeze([
          ...model.bodies,
          ...direct.flatMap(source => source.bodies),
          ...lookupBodies,
          ...moon.clientProgramOriginalModelAcquiredScopeImportBodies(acquired)
            .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string,
              wire: runtimeField(body, 2) as string})),
          ...(imports?.bodies ?? []),
          Object.freeze({kind: 'acquisition_scope',
            wire: moon.clientProgramOriginalModelAcquiredEffectScope(acquired)}),
          ...(barrier === undefined || lookupBodies.length !== 0 ? [] : [Object.freeze({kind: 'lookup_barrier',
            cid: runtimeField(barrier, 0) as string, wire: runtimeField(barrier, 1) as string})]),
        ]),
        ...(deferCatalogs ? {catalogDeferred: true} : {}),
        catalogBodies: Object.freeze([...direct.flatMap(source => source.catalogBodies),
          ...lookupBodies.filter(body => ['source_contract', 'source_view_contract', 'data_policy',
            'request_schema', 'carrier_schema', 'schema_evidence', 'capability_evidence'].includes(body.kind))]),
      });
      localEffectDependencyTokens.set(value, {kind: 'model', issued: acquired,
        original: retained.original});
      return value;
    },
    readCheckedClientInferSlotReplay(compiled: CompiledRun, definition: unknown, observation: unknown,
      records: unknown, bundle: unknown, proofs: unknown, {maxSlots, maxSlotWireUnits}: Readonly<{maxSlots: number; maxSlotWireUnits: number}>) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer Run');
      }
      return checked(moon.clientProgramReadVerifiedInferSlotReplay(
        evidenceToken(observation), records, bundle, proofs, value, token(definition),
        maxSlots, maxSlotWireUnits));
    },
    ...effectPreparationControls,
    ...effectUnitResultControls,
    ...effectDependencyControls,
    bindCheckedClientEffectRun(checkedEffect: unknown, admission: unknown, runDefinition: unknown) {
      if (typeof moon.clientProgramBindEffectRun !== 'function') {
        throw new TypeError('Client Effect Run binding is unavailable');
      }
      const bound = moon.clientProgramBindEffectRun(
        checkedEffect, admissionToken(admission), token(runDefinition));
      if (bound === undefined) {
        throw new TypeError('Run Definition differs from checked Effect');
      }
      return bound;
    },
    issueRunDefinition(admission: unknown, definition: RunDefinitionRequest, limits: WireLimits) {
      limits = captureContractLimits(limits, 'Run Definition');
      if (definition === null || typeof definition !== 'object') {
        throw new TypeError('Invalid Run Definition request');
      }
      return inspect(checked(moon.strategyIssueRunDefinition(
        admissionToken(admission),
        definition.scopeId,
        definition.runId,
        definition.inputArtifactSetCid,
        definition.createdAt,
        definition.validUntil,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueEffectFreeRunReceipt(chain: ReceiptChain, provenance: ReceiptProvenance, limits: WireLimits) {
      limits = captureContractLimits(limits, 'Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          provenance === null || typeof provenance !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(provenance.bindings) ||
          !Array.isArray(provenance.sourceEvidence) ||
          !Array.isArray(provenance.modelEvidence) ||
          !Array.isArray(provenance.barrierAttemptReceiptCids)) {
        throw new TypeError('Invalid Run Receipt request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeRunReceipt(
        admissionToken(chain.admission),
        token(chain.runDefinition),
        token(chain.invocation),
        evidenceToken(chain.observation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        evidenceToken(provenance.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken),
        provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        contentCaptures(provenance.contentGenerations),
      )), limits);
    },
    ...captureControls,
    ...effectArtifactControls,
    ...effectRecoveryControls,
    ...sourceControls,
    ...snapshotControls,
    ...pendingSourceAdvanceControls,
    ...effectFreeCaptureControls,
    ...effectPreviewControls,
    ...inventoryControls,
    ...effectfulCaptureControls,
    ...effectPublicationControls,
    ...effectRunStateControls,
    ...transitionControls,
    ...publicationProgressControl(moon, token),
    ...contractControls,
    ...publicationValidationControls,
    issueResultArtifact(exportHandle: unknown, invocation: unknown, retention: unknown, limits: WireLimits) {
      limits = captureContractLimits(limits, 'Result Artifact');
      return inspect(checked(
        moon.strategyHostOutputExportIssueResultArtifact(
          exportHandle,
          token(invocation),
          token(retention),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ), limits);
    },
    ...resultReadControls,
    ...runIdentityControls,
    ...resultRetentionControls,
    ...publicationStateControls,
    ...resultDeliveryControls,
  });
  publicationControls.set(moon, control);
  return assembled;
}

type RuntimeFacade = Readonly<{
  siteControl: ReturnType<typeof siteControl>;
  managedExecutionProfileCid: RuntimeBindings['strategyHostManagedExecutionProfileCid'];
  remoteSiteControl: ReturnType<typeof remoteSiteControl>;
  remoteTransferControl: ReturnType<typeof remoteTransferControl>;
  remoteStandardSourceControl: ReturnType<typeof remoteStandardSourceControl>;
  remoteCredentialControl: ReturnType<typeof remoteCredentialControl>;
  localSigningMetadata: () => ReturnType<typeof createLocalSigningMetadata>;
  installationPreparationMetadata: () => ReturnType<typeof createInstallationPreparationMetadata>;
  effectApplicationControl: ReturnType<typeof effectApplicationControl>;
  remoteBundleControl: ReturnType<typeof remoteBundleControl>;
  publicationControl: ReturnType<typeof publicationControl>;
  outputExportControl: ReturnType<typeof outputExportControl>;
  contentGenerationControl: ReturnType<typeof contentGenerationControl>;
  contentCaptureControl: ReturnType<typeof contentCaptureControl>;
}> & ReturnType<typeof createRuntimeExecutionControls>;

export function runtimeCore(moon: unknown): RuntimeFacade {
  const runtime = moon as RuntimeBindings;
  const publications = publicationControl(runtime);
  return Object.freeze({
    siteControl: siteControl(runtime),
    managedExecutionProfileCid: runtime.strategyHostManagedExecutionProfileCid,
    remoteSiteControl: remoteSiteControl(runtime),
    remoteTransferControl: remoteTransferControl(runtime),
    remoteStandardSourceControl: remoteStandardSourceControl(runtime),
    remoteCredentialControl: remoteCredentialControl(runtime),
    // Explicit private DATA view, not an installed issuer or signing permit.
    // Keep older unused runtime routes lazy; actual callers require this ABI.
    localSigningMetadata: () => createLocalSigningMetadata(runtime),
    installationPreparationMetadata: () => createInstallationPreparationMetadata(runtime),
    effectApplicationControl: effectApplicationControl(runtime),
    remoteBundleControl: remoteBundleControl(runtime),
    publicationControl: publications,
    outputExportControl: outputExportControl(runtime, publications),
    contentGenerationControl: contentGenerationControl(runtime, publications),
    contentCaptureControl: contentCaptureControl(runtime, publications),
    ...createRuntimeExecutionControls(runtime, publications),
  });
}
