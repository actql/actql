// Physical stepping and custody for the existing MoonBit inference owner.
// Run admission, model policy and private Store confirmation precede opening;
// this adapter does not authorize dispatch or issue a public Run outcome.
import {runtimeFailure, runtimeField, runtimeTriple} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {types as utilTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {claimInferIoNotification, createInferIoNotification} from './infer-io-notification.mjs';
import {selectedInferOriginalMetadataLimits, selectedInferOriginalStoreBootstrapLimits,
  selectedInferOriginalPublicationCapacity, selectedInferOriginalCurrentStateCodec} from './infer-original-installation.mjs';
import {originalModelRawTransportPersistenceMatches, bindOriginalModelRawTransportPersistence}
  from './infer-raw-capture.mjs';
import {pending, withNodeInferResult} from './infer-result-custody.mjs';
import {inferEvidenceCopyConstruction} from './infer-evidence-copy-geometry.mjs';

export {withNodeInferResult};

// The generated Common Node ABI supplies the scalar signatures. Owner,
// result and tuple values are passed through the existing opaque bindings.
type Runtime = Readonly<{
  clientProgramStartCompleteInferObservationIssuance(executions: unknown, ledger: unknown, maxSlots: number,
    maxWireBytes: number, maxWork: number): unknown;
  clientProgramAcquisitionCount(prepared: unknown): number;
  clientProgramTaskCount(prepared: unknown): number;
  clientProgramBindInferPhysicalPreflightCurrent(active: unknown, prepare: (value: unknown) => unknown,
    current: () => boolean): unknown;
  clientProgramClaimInferOriginalPreparation(read: unknown, compiled: unknown, definition: unknown,
    graph: unknown, retainedBytes: bigint, executionBytes: bigint): unknown;
  clientProgramAdvanceInferRoot(active: unknown, quantum: number): unknown;
  clientProgramStartOriginalInferExecution(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, provider: unknown, compiled: unknown, definition: unknown,
    consumer: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
    modelExecutionBytes: bigint, fragment: string, ordered: string): unknown;
  clientProgramStartRestoredComposedInferInput(occurrence: unknown, graph: unknown, prefix: unknown,
    provider: unknown, binding: string, descriptor: string, rows: unknown, custody: () => boolean,
    savedScope: unknown, referenceIssuer: unknown, rootLedger: unknown, suffix: unknown): unknown;
  clientProgramStartRestoredInferInput(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, provider: unknown, binding: string, descriptor: string,
    rows: unknown, custody: () => boolean, savedScope: unknown, fragment: string, ordered: string,
    referenceIssuer: unknown): unknown;
  clientProgramStartKeyedInferExecution(occurrence: unknown, graph: unknown, prefix: unknown, provider: unknown,
    sources: unknown, suffix: unknown, ledger: unknown): unknown;
  clientProgramStartComposedInferExecution(occurrence: unknown, graph: unknown, prefix: unknown, inputs: unknown,
    provider: unknown, sources: unknown): unknown;
  clientProgramStartRestoredInferSlotReplay(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, read: unknown, fragment: string, ordered: string): unknown;
  clientProgramStartAcquiredInferSlotReplay(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, read: unknown, input: unknown, fragment: string, ordered: string): unknown;
  clientProgramStartScopedInferExecution(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, provider: unknown, fragment: string, ordered: string): unknown;
  clientProgramStartAcquiredInferExecution(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, provider: unknown, input: unknown, fragment: string,
    ordered: string): unknown;
  clientProgramStartRestoredInferReplay(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, capture: unknown, fragment: string, ordered: string): unknown;
  clientProgramCancelInferExecution(active: unknown): boolean;
  clientProgramInferPhysicalObservationFacts(value: unknown): unknown;
  clientProgramBindInferModelObservation(active: unknown, prepared: unknown, observe: (value: unknown) => void): boolean;
  clientProgramInferExecutionStopped(active: unknown): boolean;
  clientProgramCleanupInferExecution(active: unknown): unknown;
  clientProgramAdvanceInferExecution(active: unknown, quantum: number): unknown;
  clientProgramInferExecutionPollKind(value: unknown): string;
  clientProgramInferPreparedCallSet(active: unknown): object | undefined;
  clientProgramInferCallSettlement(active: unknown): unknown;
  clientProgramInferExecutionOutput(value: unknown): unknown;
  clientProgramInferExecutionPollIssue(value: unknown): unknown;
  clientProgramInferCleanupProgress(active: unknown): number;
  clientProgramInferQuantityUsage(active: unknown): unknown;
  clientProgramInferStoppedAttemptCount(active: unknown): number | undefined;
  clientProgramInferStoppedAttemptSlot(active: unknown, index: number): number | undefined;
  clientProgramInferHasUnknownCalls(active: unknown): boolean;
  clientProgramAcquireInferOutput(active: unknown): unknown;
  clientProgramAcquireInferCapture(active: unknown): unknown;
  clientProgramAcquireInferOutcomes(active: unknown): unknown;
  clientProgramInferInvocationEvidence(active: unknown, slot: number): unknown;
  clientProgramInferPreparedRequest(value: unknown, slot: number): unknown;
  clientProgramInferPreparedCallAt(value: unknown, slot: number): unknown;
  strategyRunEvidenceJson(value: unknown): string;
  clientProgramInferEvaluationRequest(active: unknown, slot: number): unknown;
  clientProgramModelRequestInputFrame(request: unknown): string | undefined;
  clientProgramInferPreparedPhysicalRequest(value: unknown, slot: number): unknown;
  clientProgramBindInferOriginalPreparation(active: unknown, read: unknown, retainedBytes: bigint,
    executionBytes: bigint): unknown;
  clientProgramParkInferOriginalModelResources(active: unknown, scope: unknown): unknown;
  clientProgramParkInferOriginalModelResourcesForStateWrite(active: unknown, scope: unknown): unknown;
  clientProgramPrepareInferOriginalCurrentStateWriter(active: unknown, scope: unknown, park: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramAdvanceInferOriginalCurrentStateWriter(active: unknown, scope: unknown, park: unknown,
    value: unknown, quantum: number): unknown;
  clientProgramInferNodeReadStatePoll(poll: unknown): unknown;
  clientProgramFinishInferOriginalCurrentStateWriter(active: unknown, scope: unknown, park: unknown,
    value: unknown): unknown;
  clientProgramCancelInferOriginalCurrentStateWriter(value: unknown): void;
  clientProgramStartInferOriginalCurrentStateDecode(active: unknown, scope: unknown, park: unknown, wire: string,
    parseLimits: unknown, treeLimits: unknown, maxWork: number): unknown;
  clientProgramInferOriginalCurrentStateDecodePoll(poll: unknown): unknown;
  clientProgramAdvanceInferOriginalCurrentStateDecode(active: unknown, scope: unknown, park: unknown,
    value: unknown, quantum: number): unknown;
  clientProgramCancelInferOriginalCurrentStateDecode(value: unknown): void;
  clientProgramRetireInferOriginalCurrentStateDocument(value: unknown): void;
  clientProgramStartInferOriginalCurrentStateComparison(active: unknown, scope: unknown, park: unknown,
    document: unknown, maxWork: number): unknown;
  clientProgramInferOriginalCurrentStateComparisonPoll(poll: unknown): unknown;
  clientProgramAdvanceInferOriginalCurrentStateComparison(active: unknown, scope: unknown, park: unknown,
    value: unknown, quantum: number): unknown;
  clientProgramCancelInferOriginalCurrentStateComparison(value: unknown): void;
  clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch(active: unknown, scope: unknown, park: unknown,
    value: unknown, quantum: number): unknown;
  clientProgramInferOriginalCurrentStateMatchPoll(poll: unknown): unknown;
  clientProgramInferOriginalCurrentStateMatchCurrent(active: unknown, scope: unknown, park: unknown,
    value: unknown): unknown;
  clientProgramRetireInferOriginalCurrentStateMatch(value: unknown): void;
  clientProgramInferOriginalModelResourceParkCurrent(active: unknown, scope: unknown, park: unknown): unknown;
  clientProgramInferOriginalParkedReadCapacityAvailable(active: unknown, scope: unknown, park: unknown,
    retainedBytes: bigint, executionBytes: bigint): boolean;
  clientProgramInferOriginalUnparkedReadCapacityAvailable(active: unknown, scope: unknown, retainedBytes: bigint,
    executionBytes: bigint): boolean;
  clientProgramBeginInferOriginalModelInvalidation(active: unknown, scope: unknown, park: unknown): unknown;
  clientProgramInferOriginalModelInvalidationCurrent(active: unknown, scope: unknown, park: unknown,
    request: unknown): unknown;
  clientProgramCompleteInferOriginalJournalInvalidation(active: unknown, scope: unknown, port: unknown,
    receipt: unknown, reference: unknown, park: unknown, request: unknown): unknown;
  clientProgramExportInferPreparedInput(active: unknown, prepared: unknown, binding: string): unknown;
  clientProgramInferPreparedInputExportDescriptor(value: unknown): string;
  clientProgramInferPreparedInputExportRows(value: unknown): unknown;
  clientProgramInferPreparedInputExportMatches(active: unknown, prepared: unknown, exported: unknown): boolean;
  clientProgramInferPreparedCallCount(value: unknown): number | undefined;
  clientProgramInferPreparedInput(value: unknown): unknown;
  clientProgramInferPreparedInputArtifact(value: unknown): unknown;
  clientProgramInferPreparedIdentities(value: unknown): unknown;
  clientProgramInferCallScopeSnapshot(active: unknown): unknown;
  clientProgramInferCallScopeUnitId(active: unknown): string | undefined;
  clientProgramInferCallEntryOriginals(value: unknown): unknown;
  clientProgramInferCallEntryCurrent(value: unknown, prepared: unknown): boolean;
  clientProgramCheckInferEgressCurrent(admission: unknown): unknown;
  clientProgramRestoreInferPreparedCall(prepared: unknown, slot: number, record: unknown, proof: unknown,
    bundle: unknown, attachmentAdmission: unknown): unknown;
  clientProgramRestoreInferPreparedUnknown(prepared: unknown, slot: number, attempt: unknown, authority: unknown): unknown;
  clientProgramPrepareInferResponseReconciliation(prepared: unknown, slot: number, attempt: unknown,
    authority: unknown): unknown;
  clientProgramAdoptReconciledInferResponse(token: unknown, response: unknown): unknown;
  clientProgramInferCallSettlementSlot(value: unknown): number | undefined;
  clientProgramAcknowledgeInferCallSettlement(value: unknown): boolean;
  clientProgramInferAttemptEvidence(active: unknown, slot: number): unknown;
  clientProgramAdvanceInferStoppedRawUsage(active: unknown, slot: number, quantum: number): unknown;
  clientProgramIssueInferAttachmentAdmission(active: unknown, slot: number): unknown;
  clientProgramIssueInferSlotCapture(active: unknown, slot: number): unknown;
  clientProgramReserveOriginalInferPublicationCapacity(active: unknown, retainedBytes: bigint,
    executionBytes: bigint): unknown;
  clientProgramOriginalInferPublicationRetainedBytes(capacity: unknown): bigint;
  clientProgramOriginalInferPublicationExecutionBytes(capacity: unknown): bigint;
  clientProgramGrowOriginalInferPublicationCapacity(active: unknown, capacity: unknown, retainedBytes: bigint,
    executionBytes: bigint): unknown;
  clientProgramOriginalInferCaptureInventoryCapacity(active: unknown, capacity: unknown): unknown;
  clientProgramInferFundedStoppedAttemptCount(active: unknown): number;
  clientProgramPrepareOriginalInferUsage(active: unknown, capacity: unknown, capture: unknown,
    retainedPrefix: bigint, executionPrefix: bigint): unknown;
  clientProgramBeginOriginalInferUsagePublication(active: unknown, capacity: unknown, capture: unknown,
    retainedPrefix: bigint, executionPrefix: bigint, maxBytes: number): unknown;
  clientProgramReleaseOriginalInferPublicationCapacity(capacity: unknown): unknown;
  clientProgramStartCompleteOriginalInferObservationIssuance(active: unknown, capacity: unknown, maxSlots: number,
    maxWireBytes: number, maxWork: number, generations: unknown): unknown;
  clientProgramStartOriginalInferObservationIssuance(active: unknown, capacity: unknown, maxSlots: number,
    maxWireBytes: number, maxWork: number, generations: unknown): unknown;
  clientProgramInferPublicationLedger(retainedBytes: bigint, planningWork: number): unknown;
  clientProgramStartInferObservationIssuance(active: unknown, ledger: unknown, maxSlots: number,
    maxWireBytes: number, maxWork: number): unknown;
  clientProgramRequireInferCallEntry(active: unknown): unknown;
  clientProgramPrepareOriginalRestoredInferSendMask(active: unknown): unknown;
  clientProgramRestrictInferSendSlots(active: unknown, eligible: unknown): unknown;
  clientProgramBindInferQuantityCapacity(active: unknown, tokens: bigint, costUnits: bigint, durationMs: bigint,
    perAttemptTokens: bigint, perAttemptCostUnits: bigint, perAttemptDurationMs: bigint): unknown;
  clientProgramBindInferComputeSuffix(active: unknown, sequence: unknown): unknown;
  clientProgramBindInferPhysicalPreflight(active: unknown, prepare: (value: unknown) => unknown): unknown;
  clientProgramBindInferEgress(active: unknown, admission: unknown): unknown;
  clientProgramGeneratedInferLocalProvider(occurrence: unknown, open: (value: unknown) => unknown,
    observeIssue: (value: unknown) => void, retainCompleted: (value: unknown) => boolean,
    allowCleanup: (value: unknown) => boolean): unknown;
  clientProgramComposedInferLocalProvider(occurrence: unknown, open: (value: unknown) => unknown,
    observeIssue: (value: unknown) => void, retainCompleted: (value: unknown) => boolean,
    allowCleanup: (value: unknown) => boolean, inputPrefix: unknown): unknown;
  clientProgramInferCallScopeIssueKind(issue: unknown): string | undefined;
  clientProgramComposedInferLocalProviderWithIo(occurrence: unknown, open: (value: unknown) => unknown,
    observeIssue: (value: unknown) => void, retainCompleted: (value: unknown) => boolean,
    allowCleanup: (value: unknown) => boolean, inputPrefix: unknown): unknown;
  clientProgramInferOccurrenceCoordinates(occurrence: unknown): unknown;
  clientProgramModelRequestInputFrameGeometry(request: unknown, maxBytes: number): unknown;
  clientProgramEffectModelEvidenceCopyCapacity(bundleBytes: number, bundleNodes: number, bundleDepth: number,
    input: unknown, otherTextUnits: number, calls: number): unknown;
}> & Parameters<typeof withNodeInferResult>[0]['moon'];

type Awaitable<Value> = Value | PromiseLike<Value>;
type Acknowledge = () => boolean;
type Observe = () => Awaitable<unknown>;
type ObservationBounds = Readonly<{maxSlots: number; maxWireBytes: number; maxWork: number}>;
type RunIdentity = Readonly<{identity: string}>;
type RunPlan = Readonly<{compiled: unknown; runDefinition: RunIdentity}>;
type EvidenceView = Readonly<{wire: string; identity: string}>;
type EvidenceBundle = Parameters<typeof inferEvidenceCopyConstruction>[2];
type EvidenceKind = Parameters<typeof inferEvidenceCopyConstruction>[3];
type EvidenceCopy = (bundle: EvidenceBundle, kind: EvidenceKind) => object | undefined;
type OriginalFunding = Readonly<{
  prepareOriginalCaptureInventory(operation: OriginalFunding): object | undefined;
  fundedStoppedAttemptCount(): number | undefined;
  originalMaterializationCurrent(operation: OriginalFunding, count: number): boolean;
  prepareOriginalEvidenceCopy(operation: OriginalFunding, bundle: EvidenceBundle, kind: EvidenceKind,
    retained: bigint, execution: bigint): object;
}>;
type OriginalLink = Readonly<{operation: WeakRef<OriginalFunding>; funding: WeakRef<OriginalFunding>}>;
type Materialization = OriginalLink & Readonly<{kind: 'capture' | EvidenceKind; count: number; bundle?: EvidenceBundle}>;
type OriginalReadControl = Readonly<{
  stopCheckedClientInferOriginalReadPreparation(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, read: unknown): unknown;
  settleCheckedClientInferOriginalReadPreparation(compiled: unknown, definition: unknown, graph: unknown,
    read: unknown, confirmed: boolean): unknown;
  finishCheckedClientInferOriginalReadScope(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, confirmed: boolean): boolean;
}>;
type OriginalReadGroup = {
  components: readonly OriginalReadMember[];
  scopes: readonly unknown[]; graph: readonly unknown[]; control: OriginalReadControl;
  compiled: unknown; runDefinition: unknown; scope: unknown; closed?: boolean; scopeFinished?: boolean;
};
type OriginalReadMember = {
  group: OriginalReadGroup; control: OriginalReadControl; compiled: unknown; runDefinition: unknown;
  graph: unknown; scope: unknown; read?: unknown; closed?: boolean; scopeFinished?: boolean;
  runtimeBorrow?: unknown;
  selection: Readonly<{finishTrustedRuntimeScope(scope: unknown, borrow: unknown, compiled: unknown,
    definition: unknown, graph: unknown): boolean}>;
};
type OriginalControl = Readonly<{
  checkClientCompiledRunOwner(compiled: unknown, program: unknown): void;
  claimCheckedClientInferNodePreparationLayout(compiled: unknown, definition: unknown, graph: unknown,
    read: unknown, installation: unknown): unknown;
  claimCheckedClientInferOriginalComposedPreparation(compiled: unknown, definition: unknown, graph: unknown,
    read: unknown, retained: bigint, execution: bigint): unknown;
  startCheckedClientOriginalRestoredComposedInferExecution(compiled: unknown, definition: unknown,
    occurrence: unknown, graph: unknown, prefix: unknown, provider: unknown, snapshot: unknown,
    available: Acknowledge, scope: unknown, consumer: unknown, readRetained: bigint, readExecution: bigint,
    modelRetained: bigint, modelExecution: bigint, referenceIssuer: unknown, inputBodyRead: unknown): unknown;
  startCheckedClientOriginalComposedInferExecution(compiled: unknown, definition: unknown, occurrence: unknown,
    graph: unknown, prefix: unknown, inputs: unknown, provider: unknown, consumer: unknown,
    readRetained: bigint, readExecution: bigint, modelRetained: bigint, modelExecution: bigint,
    sources: unknown, inputBodyRead: unknown): unknown;
  startCheckedClientInferOriginalPreparation(compiled: unknown, definition: unknown, program: unknown,
    step: number | undefined, graph: unknown, registry: unknown, values: unknown, provider: unknown,
    consumer: unknown, readRetained: bigint, readExecution: bigint, modelRetained: bigint,
    modelExecution: bigint, fragment: unknown, ordered: unknown): unknown;
  runDefinitionRunId(definition: unknown): string;
}>;
type ContentControl = Readonly<{
  startCheckedClientContentInferObservation(compiled: unknown, owners: readonly unknown[],
    generations: unknown, ledger: unknown, bounds: ObservationBounds): unknown;
  startCheckedClientOriginalContentInferObservation(owners: readonly unknown[],
    generations: readonly unknown[], capacity: unknown, bounds: ObservationBounds): unknown;
  startCheckedClientRestoredGeneratedInferInputs(compiled: unknown, definition: unknown, generation: unknown,
    graph: unknown, inputs: unknown, provider: unknown, snapshot: unknown, available: Acknowledge): unknown;
  startCheckedClientGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
    inputs: unknown, provider: unknown): unknown;
  startCheckedClientOriginalGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
    inputs: unknown, provider: unknown, definition: unknown, consumer: unknown, readRetained: bigint,
    readExecution: bigint, modelRetained: bigint, modelExecution: bigint): unknown;
  startCheckedClientRestoredGeneratedInferExecution(compiled: unknown, definition: unknown, generation: unknown,
    program: unknown, graph: unknown, provider: unknown, environment: unknown, snapshot: unknown,
    available: Acknowledge): unknown;
  startCheckedClientGeneratedInferExecution(compiled: unknown, generation: unknown, program: unknown,
    graph: unknown, provider: unknown): unknown;
  startCheckedClientOriginalGeneratedInferExecution(compiled: unknown, generation: unknown, program: unknown,
    graph: unknown, provider: unknown, definition: unknown, consumer: unknown, readRetained: bigint,
    readExecution: bigint, modelRetained: bigint, modelExecution: bigint): unknown;
}>;
type OriginalPreparation = RunPlan & Readonly<{
  control: OriginalControl; read: unknown; scope: unknown; nodeInstallation?: unknown;
  metadataInstallation?: Parameters<typeof selectedInferOriginalMetadataLimits>[0];
  readRetainedBytes: bigint; readExecutionBytes: bigint; modelRetainedBytes: bigint; modelExecutionBytes: bigint;
}>;
type MetadataLimits = ReturnType<typeof selectedInferOriginalMetadataLimits>;
type StoreBootstrap = ReturnType<typeof selectedInferOriginalStoreBootstrapLimits>;
type ResourceCodec = ReturnType<typeof selectedInferOriginalCurrentStateCodec>;
type MetadataRole = 'store-bootstrap' | 'resource-state-codec';
type MetadataAcquisition = Readonly<{handle: object; park?: unknown; selection?: MetadataLimits;
  current(ownerId?: string, requestCid?: string, role?: MetadataRole): StoreBootstrap | ResourceCodec | undefined}>;
type RawBinder = (registration: unknown, persistence: unknown) => unknown;
type CredentialPreparation = () => void;
type RetainRawBinder = (callback: RawBinder, request: unknown, credential?: CredentialPreparation) => void;
type PhysicalPreflight = (request: unknown, notification?: unknown,
  retain?: (callback: RawBinder, credential?: CredentialPreparation) => void) => unknown;
type SettlementCleanup = (settlement: unknown) => Awaitable<unknown>;
type RestoredInput = Readonly<{
  savedScope?: unknown; token: Readonly<{available: boolean}>;
  snapshot: Readonly<{binding: string; descriptorWire: string; rows: unknown;
    providerInputs?: readonly Readonly<{callWire: string; typedInputWire: string;
      renderedInput: string; contextManifest: string}>[]}>;
  sendMask?: unknown; sendSlots?: () => readonly Readonly<{state: string}>[];
}>;
type CapturedContent = Readonly<{capturedRecovery?: unknown; capturedBinding?: unknown}>;
type ComposedInput = CapturedContent & Readonly<{occurrence: unknown; prefix: unknown; inputs?: unknown; sources?: unknown}>;
type KeyedInput = ComposedInput & Readonly<{ledger: unknown}>;
type SerializedInput = CapturedContent & Readonly<{control: ContentControl; compiled: unknown; definition: unknown;
  generation: unknown; inputs?: readonly unknown[]; recovery?: unknown}>;
type Quantities = Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
type QuantityCapacity = Readonly<{limits: Quantities; perAttempt: Quantities}>;
type RunOutput = Readonly<{status?: string; preparedCallSet?: object; settlement?: unknown}>;
type ObservationInputs = ObservationBounds & Readonly<{ledger?: unknown; operations?: readonly ObservationOperation[]}>;
type ObservationOperation = Readonly<{
  publicationCapacityPending(): boolean;
  startObservation(options: ObservationInputs): unknown;
}>;
type CompleteObservation = ObservationBounds & Readonly<{
  moon: Runtime; operations: readonly ObservationOperation[]; ledger?: unknown;
  content?: Readonly<{control: ContentControl; compiled: unknown; generations: unknown}>;
}>;
type WriterLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type DecodeLimits = Readonly<{parse: unknown; tree: unknown; maxWork: number}>;
type EntryOriginals = Readonly<{entry: unknown; slot: unknown; callWire: unknown;
  attemptWire: unknown; authorityWire: unknown}>;
type EnterCall = (entry: EntryOriginals) => unknown;
type DispatchObservation = Readonly<Record<string, unknown>>;
type ModelObservation = Readonly<{slot: unknown; attemptCid: unknown; event: unknown; outcome: unknown}>;
type ObserveModel = (observation: ModelObservation) => void;
type BindControl = Readonly<{
  inspectInferInvocationEvidence(moon: Runtime, active: unknown, slot: number): EvidenceView | undefined;
  bindCheckedClientInferRun(compiled: unknown, active: unknown, definition: RunIdentity): unknown;
  bindCheckedClientInferDispatch(compiled: unknown, active: unknown, definition: RunIdentity,
    observation: DispatchObservation): unknown;
  bindCheckedClientInferModelScope(compiled: unknown, active: unknown, definition: RunIdentity,
    prepared: unknown, originals: unknown): unknown;
  bindCheckedClientInferModelDispatch(compiled: unknown, active: unknown, definition: RunIdentity,
    prepared: unknown, scope: unknown, observation: Readonly<{enterCall(entry: unknown): boolean}>): unknown;
  bindCheckedClientInferModelEntryPersistence(compiled: unknown, active: unknown, definition: RunIdentity,
    prepared: unknown, scope: unknown, observation: Readonly<{beginEntry(entry: unknown): unknown}>): unknown;
  bindCheckedClientInferInvocation(compiled: unknown, active: unknown, definition: RunIdentity,
    verification: unknown, invocation: unknown, dataPolicyCid: string): unknown;
  bindInferOriginalResultArtifact(active: unknown, index: number, artifact: unknown, manifest: unknown): void;
  bindIssuedClientInferInvocation(compiled: unknown, active: unknown, definition: RunIdentity, issued: unknown): unknown;
}>;
type CopySource = OriginalFunding & Parameters<typeof inferEvidenceCopyConstruction>[1];
type CopyFunder = OriginalFunding & Readonly<{growOriginalPublicationCapacity(retained: bigint, execution: bigint): void}>;
type CopyFundingOptions = Readonly<{moon: Runtime; funding: CopyFunder; operation: CopySource;
  current: () => void; retainedPrefix?: () => bigint; executionPrefix?: () => bigint; legacy?: boolean}>;
type ResultOriginal = Parameters<Parameters<typeof withNodeInferResult>[0]['consume']>[0];
type OperationOptions = Readonly<{
  moon: Runtime; preparedProgram?: unknown; step?: number; graph: unknown; registry?: unknown; values?: string;
  fragment?: string; ordered?: string; provider?: unknown; savedCapture?: unknown; savedSlots?: unknown;
  quantityCapacity?: QuantityCapacity; physicalPreflight?: PhysicalPreflight; egressAdmission?: unknown;
  computeSuffix?: unknown; acquiredInput?: unknown; composedInput?: ComposedInput; keyedInput?: KeyedInput;
  signal?: AbortSignal; quantum?: number; observeProgress?: Observe; durableCalls?: boolean;
  restoredInput?: RestoredInput; retainOperation?: (operation: Operation) => void;
  ioNotification?: unknown; originalPreparation?: OriginalPreparation; restoredPreparation?: OriginalPreparation;
  rawCaptureBinder?: RawBinder; serializedInput?: SerializedInput; restoredReferenceIssuer?: unknown;
  assertRuntimeCurrent?: () => void; bindComputeSuffix?: (active: unknown) => unknown;
  managedIo?: boolean;
}>;

const activeOperations = new WeakMap<object, unknown>();
const originalOperations = new WeakSet<object>();
const materializationReceipts = new WeakMap<object, Materialization>();
const originalCopyFunders = new WeakMap<object, OriginalLink>();
const cleanedOriginalReads = new WeakSet<object>();
const isPromise = utilTypes.isPromise;
const observePromise = Promise.prototype.then;

// Only a refusal from the same prepared physical credential port can end a
// resumed Run through the existing stopped-Model failure path.
class ModelCredentialRefusal extends Error {
  declare code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}
export function isModelCredentialRefusal(error: unknown) {
  return error instanceof ModelCredentialRefusal;
}

// A parent may retire this exact descriptor alias after the consumer's actual
// Core cleanup. This observation issues no ACK and cannot mark another read,
// release a Scope, or turn a stopped/unknown operation into completed cleanup.
export function inferOriginalReadCleanupComplete(read: unknown) {
  return cleanedOriginalReads.has(read as object);
}

// The same original parent's read retirement for Pure and Effect consumers.
// A completed consuming execution does not settle its owning reservation.
export function retireNodeInferOriginalRead({control, compiled, runDefinition, graph, scope, read}: Readonly<{
  control: OriginalReadControl; compiled: unknown; runDefinition: unknown;
  graph: unknown; scope: unknown; read: unknown;
}>) {
  if (read === undefined) return;
  if (!inferOriginalReadCleanupComplete(read)) {
    control.stopCheckedClientInferOriginalReadPreparation(compiled, runDefinition, graph, scope, read);
  }
  control.settleCheckedClientInferOriginalReadPreparation(compiled, runDefinition, graph, read, true);
}
// Finish the native closed group only after all actual read children retired.
// This is a shared caller continuation, not a cleanup ACK or another owner.
export function finishNodeInferOriginalReadScopes(model: OriginalReadGroup) {
  const members = model?.components, scopes = model?.scopes, graph = model?.graph,
    control = model?.control, compiled = model?.compiled, definition = model?.runDefinition;
  const finish = control?.finishCheckedClientInferOriginalReadScope;
  const current = () => {
    if (!Array.isArray(members as unknown) || !Object.isFrozen(members) || members.length < 2 ||
        !Array.isArray(scopes) || !Object.isFrozen(scopes) || scopes.length !== members.length ||
        !Array.isArray(graph) || !Object.isFrozen(graph) || graph.length !== members.length ||
        typeof finish !== 'function' || control.finishCheckedClientInferOriginalReadScope !== finish ||
        model.components !== members || model.scopes !== scopes || model.graph !== graph ||
        model.control !== control || model.compiled !== compiled || model.runDefinition !== definition ||
        model.scope !== scopes[0] || model.closed || model.scopeFinished ||
        members.some((member, index) => member.group !== model || member.control !== control ||
          member.compiled !== compiled || member.runDefinition !== definition || member.graph !== graph[index] ||
          member.scope !== scopes[index] || member.read !== undefined || member.closed || member.scopeFinished)) {
      throw new TypeError('InvalidInstalledRequestModelPreparation');
    }
  };
  function finishMember(index: number) {
    const member = members[index], borrow = member.runtimeBorrow;
    if (borrow === undefined) return Reflect.apply(finish, control, [compiled, definition, graph[index], scopes[index], true]);
    if (member.selection.finishTrustedRuntimeScope(scopes[index], borrow, compiled, definition, graph[index]) !== true) return false;
    current();
    if (member.runtimeBorrow !== borrow) throw new TypeError('InvalidInstalledRequestModelPreparation');
    member.runtimeBorrow = undefined;
    return true;
  }
  current();
  // The last actual Scope can close the group. Earlier pending members must not
  // prevent reaching it. A second closed observation is callback-free in Core.
  for (let index = 0; index < members.length; index++) {
    finishMember(index);
    current();
  }
  for (let index = 0; index < members.length; index++) {
    const closed = finishMember(index);
    current();
    if (closed !== true) return false;
  }
  for (const member of members) {member.scopeFinished = true; member.closed = true;}
  model.scopeFinished = true;
  return true;
}
// This is nominal membership in the existing operation, not a resource Owner.
// Escaped handles weakly borrow its retained record and cannot keep the original
// Model/Scope/Ledger graph alive after actual operation cleanup.
const originalMetadataSources = new WeakMap<object, WeakRef<MetadataAcquisition>>();
const metadataUnavailable: () => never = () => { throw Object.assign(new Error('InferOriginalMetadataAcquisitionUnavailable'),
  {code: 'InferOriginalMetadataAcquisitionUnavailable'}); };

// Keep an escaped per-preflight setter from retaining the installing operation
// after this synchronous constructor. Its mutable port is consumed once and
// cleared even when the original physical factory refuses or throws.
function prepareWithOriginalRawSetter(prepare: PhysicalPreflight, request: unknown,
  notification: unknown, retain: RetainRawBinder | undefined) {
  const set = (callback: RawBinder, credential?: CredentialPreparation) => {
    if (retain === undefined) throw new TypeError('InferRawCaptureBinderUnavailable');
    retain(callback, request, credential);
    retain = undefined;
  };
  try { return prepare(request, notification, set); }
  finally { retain = undefined; }
}

export function selectOriginalInferMetadataAcquisition(handle: unknown, ownerId?: string, requestCid?: string) {
  const original = originalMetadataSources.get(handle as object)?.deref();
  if (original === undefined) metadataUnavailable();
  original.current(ownerId, requestCid);
  return original.selection;
}

// Reuse the SAME nominal handle and current/covers closure, not another issuer
// or a capacity inferred from physical clamps. Missing separate role refuses.
export function selectOriginalInferStoreBootstrapAcquisition(handle: unknown, ownerId?: string, requestCid?: string) {
  const original = originalMetadataSources.get(handle as object)?.deref();
  if (original === undefined) metadataUnavailable();
  return original.current(ownerId, requestCid, 'store-bootstrap');
}

// Same original installation's existing Writer/decoder bound. Metadata wire
// limits are a different role and cannot price or bound this resource body.
export function selectOriginalInferResourceCodecAcquisition(handle: unknown, ownerId?: string, requestCid?: string) {
  const original = originalMetadataSources.get(handle as object)?.deref();
  if (original === undefined) metadataUnavailable();
  return original.current(ownerId, requestCid, 'resource-state-codec');
}

// Validate the Node-to-Int boundary before entering the existing codec. These
// bounds are not physical funding or permission to acquire additional data.
const codecInt = (value: unknown, positive = false): value is number => Number.isSafeInteger(value) &&
  (value as number) >= (positive ? 1 : 0) && (value as number) <= 2147483647;
const codecLimits = (value: unknown, keys: string) => value !== null && typeof value === 'object' &&
  Object.keys(value).sort().join(',') === keys && Object.values(value).every(item => codecInt(item));

// Only this module's actual original operation can grow/issue these receipts.
// A count or a caller-created reserve method is neither a numeric original nor
// evidence that the next constructor has been admitted on its SAME Ledger.
export function fundInferCaptureInventory(operation: unknown, funding = operation) {
  if (!originalOperations.has(operation as object) || !originalOperations.has(funding as object)) return undefined;
  return (funding as OriginalFunding).prepareOriginalCaptureInventory(operation as OriginalFunding);
}
export function fundedInferCaptureInventoryCount(receipt: unknown, operation: unknown) {
  const original = materializationReceipts.get(receipt as object);
  const funding = original?.funding.deref();
  if (original?.kind !== 'capture' || original.operation.deref() !== operation ||
      funding === undefined || !funding.originalMaterializationCurrent(operation as OriginalFunding, original.count)) return undefined;
  return original.count;
}
export function fundedInferStoppedAttemptCount(operation: unknown) {
  if (!originalOperations.has(operation as object)) return undefined;
  const count = (operation as OriginalFunding).fundedStoppedAttemptCount();
  return codecInt(count) ? count : undefined;
}
export function fundInferEvidenceCopy(funding: OriginalFunding, operation: OriginalFunding,
  bundle: EvidenceBundle, kind: EvidenceKind, retained: bigint, execution: bigint) {
  if (!originalOperations.has(operation) || !originalOperations.has(funding)) return undefined;
  return funding.prepareOriginalEvidenceCopy(operation, bundle, kind, retained, execution);
}
export function inferEvidenceCopyFunded(receipt: unknown, bundle: unknown, kind: EvidenceKind) {
  const original = materializationReceipts.get(receipt as object), operation = original?.operation.deref();
  const funding = original?.funding.deref();
  return original !== undefined && original.kind === kind && original.bundle === bundle && operation !== undefined &&
    funding !== undefined && funding.originalMaterializationCurrent(operation, original.count);
}
export function originalInferCopyFunding(funding: OriginalFunding, operation: OriginalFunding, callback: EvidenceCopy) {
  if (!originalOperations.has(operation) || !originalOperations.has(funding)) return callback;
  const bound: EvidenceCopy = (bundle, kind) => callback(bundle, kind);
  originalCopyFunders.set(bound, {operation: new WeakRef(operation), funding: new WeakRef(funding)});
  return bound;
}
export function inferCopyFundingOriginal(callback: unknown) {
  const original = originalCopyFunders.get(callback as object);
  const operation = original?.operation.deref(), funding = original?.funding.deref();
  return operation !== undefined && funding !== undefined &&
    originalOperations.has(operation) && originalOperations.has(funding);
}

// Publication metadata is issued by the same bounded common owner only after
// every original Model component has completed. This does not advance calls.
export function startCompleteInferObservation({moon, operations, ledger, maxSlots, maxWireBytes, maxWork,
  content}: CompleteObservation) {
  const active = operations.map(operation => {
    const value = activeOperations.get(operation);
    if (value === undefined) throw new TypeError('ForeignInferOperation');
    return value;
  });
  if (operations.some(operation => originalOperations.has(operation))) {
    if (ledger !== undefined || content !== undefined ||
        operations.some(operation => !originalOperations.has(operation))) {
      throw new TypeError('InferOriginalPublicationCapacityUnavailable');
    }
    // The actual operation retains its original opaque publication borrow.
    // A Source Ledger or a matching caller object cannot select that issuer.
    const funding = operations.filter(operation => operation.publicationCapacityPending());
    if (funding.length !== 1) throw new TypeError('InferOriginalPublicationCapacityUnavailable');
    return funding[0].startObservation({maxSlots, maxWireBytes, maxWork,
      ...(operations.length === 1 ? {} : {operations})});
  }
  if (content !== undefined) {
    return content.control.startCheckedClientContentInferObservation(content.compiled,
      active, content.generations, ledger, {maxSlots, maxWireBytes, maxWork});
  }
  return checked(moon.clientProgramStartCompleteInferObservationIssuance(active,
    ledger, maxSlots, maxWireBytes, maxWork));
}

// Called by the installed Run's dispatch callback. The caller transfers this
// object to client-dispatch-owner before calling run, hence before any advance.
// Exactly one physical provider or already Store-confirmed saved read is used.
export function openNodeInferOperation({moon, preparedProgram, step, graph,
  registry, values, fragment, ordered, provider, savedCapture, savedSlots, quantityCapacity,
  physicalPreflight, egressAdmission, computeSuffix, acquiredInput, composedInput, keyedInput,
  signal, quantum = 256, observeProgress, durableCalls = false, restoredInput, retainOperation,
  ioNotification, originalPreparation, restoredPreparation, rawCaptureBinder, serializedInput, restoredReferenceIssuer,
  assertRuntimeCurrent, bindComputeSuffix, managedIo = false}: OperationOptions) {
  const restoringOriginal = restoredPreparation !== undefined;
  if (restoringOriginal) {
    if (originalPreparation !== undefined || restoredInput?.savedScope === undefined ||
        composedInput === undefined || serializedInput !== undefined || keyedInput !== undefined) {
      throw new TypeError('InvalidInferOriginalPreparation');
    }
    originalPreparation = restoredPreparation;
  }
  // A composed input is not necessarily a Local-scheduled component: the
  // existing installed one-Unit caller supplies its original checked Program.
  // Bind that choice once to the same opaque compiled Owner before entry;
  // subsequent driving still uses this operation's original current/Run gates.
  const originalComposedRun = composedInput !== undefined &&
    preparedProgram !== undefined && originalPreparation !== undefined;
  if (originalComposedRun) {
    const control = originalPreparation!.control;
    if (typeof control?.checkClientCompiledRunOwner !== 'function' ||
        serializedInput !== undefined ||
        !restoringOriginal && (!Array.isArray(composedInput.inputs) ||
          composedInput.inputs.length !== 0)) {
      throw new TypeError('InvalidInferOriginalComposedRun');
    }
    control.checkClientCompiledRunOwner(originalPreparation!.compiled, preparedProgram);
    const sourceCount = moon.clientProgramAcquisitionCount(preparedProgram);
    if (moon.clientProgramTaskCount(preparedProgram) !== 1 ||
        (sourceCount !== 0 && sourceCount !== 1) ||
        !restoringOriginal && (sourceCount === 1 ? composedInput.sources === undefined
          : composedInput.sources !== undefined)) {
      throw new TypeError('InvalidInferOriginalComposedRun');
    }
  }
  if (rawCaptureBinder !== undefined && typeof rawCaptureBinder !== 'function') {
    throw new TypeError('InvalidInferRawCaptureBinder');
  }
  if (assertRuntimeCurrent !== undefined &&
      (originalPreparation === undefined || typeof assertRuntimeCurrent !== 'function' ||
        typeof moon.clientProgramBindInferPhysicalPreflightCurrent !== 'function')) {
    throw new TypeError('InferTrustedRuntimeScopeUnavailable');
  }
  if (bindComputeSuffix !== undefined && (typeof bindComputeSuffix !== 'function' ||
      originalPreparation === undefined || computeSuffix !== undefined)) {
    throw new TypeError('InvalidInferOriginalSuffixBinding');
  }
  let rawCaptureBound = false;
  let preparedRawCaptureBinders: RawBinder[] | undefined;
  let credentialPreparations: {request: unknown; prepare: CredentialPreparation}[] | undefined,
    credentialFailure: {cause: unknown} | undefined;
  // The original installing Run has already reserved this entire simultaneous
  // envelope, including this adapter's controls. Do not derive it from counts,
  // aggregate headroom or the later Model seal's distinct requirements.
  let originalConsumer: unknown;
  let originalRead: unknown;
  let originalInputBodyRead: unknown;
  let originalScope = originalPreparation?.scope;
  let metadataInstallation = originalPreparation?.metadataInstallation;
  let metadataNodeInstallation = originalPreparation?.nodeInstallation;
  let metadataControl = originalPreparation?.control;
  let metadataDefinition = originalPreparation?.runDefinition;
  let originalMetadata: MetadataAcquisition | undefined;
  let originalStoreBootstrap: MetadataAcquisition | undefined;
  let originalPublicationCapacity: unknown;
  let publicationBaseRetained: bigint | undefined, publicationBaseExecution: bigint | undefined;
  let publicationHeldRetained: bigint | undefined, publicationHeldExecution: bigint | undefined;
  let publicationMaterializationRetained = 0n;
  let originalPublicationSelection: (() => unknown) | undefined;
  let originalPublicationReceiver: OriginalPreparation | undefined;
  if (originalPreparation !== undefined) {
    if (provider === undefined || acquiredInput !== undefined || keyedInput !== undefined ||
        (!restoringOriginal && restoredInput !== undefined) || savedCapture !== undefined || savedSlots !== undefined ||
        originalPreparation === null || typeof originalPreparation !== 'object' ||
        typeof originalPreparation.readRetainedBytes !== 'bigint' ||
        originalPreparation.readRetainedBytes <= 0n ||
        typeof originalPreparation.readExecutionBytes !== 'bigint' ||
        originalPreparation.readExecutionBytes <= 0n ||
        typeof originalPreparation.modelRetainedBytes !== 'bigint' ||
        originalPreparation.modelRetainedBytes <= 0n ||
        typeof originalPreparation.modelExecutionBytes !== 'bigint' ||
        originalPreparation.modelExecutionBytes < 0n) {
      throw new TypeError('InvalidInferOriginalPreparation');
    }
    originalRead = originalPreparation.read;
    const bodyRead = Object.getOwnPropertyDescriptor(originalPreparation, 'inputBodyRead');
    if (bodyRead !== undefined) {
      if (!Object.hasOwn(bodyRead, 'value') || originalRead === undefined || bodyRead.value !== originalRead) {
        throw new TypeError('ForeignInferOriginalInputBodyRead');
      }
      originalInputBodyRead = bodyRead.value;
    }
    const publication = Object.getOwnPropertyDescriptor(originalPreparation, 'publicationCapacity');
    if (publication !== undefined) {
      if (!Object.hasOwn(publication, 'value') || typeof publication.value !== 'function') {
        throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
          {code: 'InferOriginalPublicationCapacityUnavailable'});
      }
      // Keep the same installing callback/receiver across Model execution.
      // Its current same-Run selection is DATA, not a reservation or grant.
      originalPublicationSelection = publication.value;
      originalPublicationReceiver = originalPreparation;
    }
    // The original read owner retains the issued ticket if a later constructor
    // fails. No JS ownership map, claim reset or unowned-start fallback exists.
    if (composedInput !== undefined &&
        typeof originalPreparation.control?.[restoringOriginal
          ? 'startCheckedClientOriginalRestoredComposedInferExecution'
          : 'startCheckedClientOriginalComposedInferExecution'] !== 'function') {
      throw new TypeError('InferOriginalComposedControlUnavailable');
    }
    if (Object.hasOwn(originalPreparation, 'nodeInstallation')) {
      const selected = originalPreparation.nodeInstallation;
      if (selected === null || typeof selected !== 'object' ||
          Object.keys(selected).sort().join(',') !==
            'installation,layout,layoutArtifactCid,probability,runtimeArtifactCid' ||
          typeof originalPreparation.control?.claimCheckedClientInferNodePreparationLayout !== 'function' ||
          composedInput === undefined &&
            typeof originalPreparation.control?.startCheckedClientInferOriginalPreparation !== 'function') {
        throw new TypeError('InvalidInferOriginalPreparationLayout');
      }
      // The same installed layout claim supplies the one original consumer
      // for both single-stage and composed input. A rejected claim never uses
      // the private envelope or an unowned start as a replacement.
      originalConsumer = originalPreparation.control.claimCheckedClientInferNodePreparationLayout(
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalRead, selected);
    } else if (composedInput !== undefined) {
      const control = originalPreparation.control;
      if (typeof control?.claimCheckedClientInferOriginalComposedPreparation !== 'function') {
        throw new TypeError('InferOriginalComposedControlUnavailable');
      }
      originalConsumer = control.claimCheckedClientInferOriginalComposedPreparation(
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalRead, originalPreparation.readRetainedBytes,
        originalPreparation.readExecutionBytes);
    } else {
      // Explicit existing private envelope caller; no production supplier or
      // physical adequacy is implied by this older diagnostic interface.
      originalConsumer = checked(moon.clientProgramClaimInferOriginalPreparation(originalRead,
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes));
    }
  }
  if (retainOperation !== undefined && typeof retainOperation !== 'function') {
    throw new TypeError('InvalidInferOperationCustody');
  }
  if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      [provider, savedCapture, savedSlots].filter(value => value !== undefined)
        .length !== 1) {
    throw new TypeError('InvalidInstalledInferOperation');
  }
  if (physicalPreflight !== undefined &&
      (typeof physicalPreflight !== 'function' || provider === undefined ||
        quantityCapacity === undefined)) {
    throw new TypeError('InvalidInstalledInferPhysicalPreflight');
  }
  if (egressAdmission !== undefined && provider === undefined) {
    throw new TypeError('InvalidInstalledInferEgress');
  }
  if (quantityCapacity !== undefined && (provider === undefined ||
      quantityCapacity === null ||
      typeof quantityCapacity !== 'object' ||
      Object.keys(quantityCapacity).sort().join(',') !== 'limits,perAttempt' ||
      (['limits', 'perAttempt'] as const).some(scope => {
        const value = quantityCapacity[scope];
        return value === null || typeof value !== 'object' ||
          Object.keys(value).sort().join(',') !==
            'costUnits,durationMs,tokens' ||
          Object.values(value).some(amount => typeof amount !== 'bigint' ||
            amount < 0n || amount > BigInt(Number.MAX_SAFE_INTEGER));
      }))) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  signal?.throwIfAborted();
  if (acquiredInput !== undefined && savedCapture !== undefined) {
    throw new TypeError('AcquiredInferReplayNotConnected');
  }
  if (composedInput !== undefined && (provider === undefined ||
      acquiredInput !== undefined || savedSlots !== undefined ||
      savedCapture !== undefined)) {
    throw new TypeError('InvalidComposedInferOperation');
  }
  if (keyedInput !== undefined && (provider === undefined || acquiredInput !== undefined ||
      composedInput !== undefined || savedSlots !== undefined || savedCapture !== undefined ||
      serializedInput !== undefined || keyedInput.occurrence === undefined ||
      keyedInput.prefix === undefined || keyedInput.ledger === undefined ||
      restoredInput === undefined && keyedInput.sources === undefined ||
      typeof moon.clientProgramAdvanceInferRoot !== 'function')) {
    throw new TypeError('InvalidKeyedInferOperation');
  }
  if (restoredInput !== undefined && (provider === undefined || acquiredInput !== undefined ||
      savedCapture !== undefined || savedSlots !== undefined)) {
    throw new TypeError('InvalidRestoredInferInput');
  }
  // This is a Host-owned issuer confirmed against the original Store holding,
  // not authority reconstructed from the saved reference envelope itself.
  if (restoredReferenceIssuer !== undefined &&
      (restoredInput === undefined || serializedInput !== undefined)) {
    throw new TypeError('InvalidRestoredInferReferenceIssuer');
  }
  if (serializedInput !== undefined && (provider === undefined ||
      acquiredInput !== undefined || composedInput !== undefined ||
      savedCapture !== undefined || savedSlots !== undefined ||
      serializedInput.inputs !== undefined && !Array.isArray(serializedInput.inputs) ||
      typeof serializedInput?.control?.[serializedInput.inputs !== undefined
        ? restoredInput === undefined ? 'startCheckedClientGeneratedInferInputs'
          : 'startCheckedClientRestoredGeneratedInferInputs' : restoredInput === undefined
        ? 'startCheckedClientGeneratedInferExecution'
        : 'startCheckedClientRestoredGeneratedInferExecution'] !== 'function')) {
    throw new TypeError('InvalidSerializedInferInput');
  }
  if (typeof managedIo !== 'boolean' || managedIo && (ioNotification === undefined ||
      composedInput === undefined || originalComposedRun || restoringOriginal ||
      originalPreparation?.nodeInstallation === undefined || typeof assertRuntimeCurrent !== 'function') ||
      ioNotification !== undefined && (provider === undefined ||
        composedInput !== undefined && !originalComposedRun && !restoringOriginal && !managedIo)) {
    throw new TypeError('InvalidInferIoNotificationProfile');
  }
  let io = ioNotification === undefined ? undefined : claimInferIoNotification(ioNotification);
  let active: unknown;
  try { active = serializedInput !== undefined
    ? serializedInput.inputs !== undefined
      ? restoredInput !== undefined
        ? serializedInput.control.startCheckedClientRestoredGeneratedInferInputs(
          serializedInput.compiled, serializedInput.definition, serializedInput.generation,
          graph, serializedInput.inputs, provider, restoredInput.snapshot,
          () => restoredInput.token.available)
        : originalPreparation === undefined
          ? serializedInput.control.startCheckedClientGeneratedInferInputs(
            serializedInput.compiled, serializedInput.generation, graph, serializedInput.inputs, provider)
          : serializedInput.control.startCheckedClientOriginalGeneratedInferInputs(
            serializedInput.compiled, serializedInput.generation, graph, serializedInput.inputs, provider,
            originalPreparation.runDefinition, originalConsumer,
            originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
            originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes)
      : restoredInput !== undefined
      ? serializedInput.control.startCheckedClientRestoredGeneratedInferExecution(
        serializedInput.compiled, serializedInput.definition, serializedInput.generation,
        preparedProgram, graph, provider, {registry, values, fragment, ordered},
        restoredInput.snapshot, () => restoredInput.token.available)
      : originalPreparation === undefined
        ? serializedInput.control.startCheckedClientGeneratedInferExecution(
          serializedInput.compiled, serializedInput.generation, preparedProgram, graph, provider)
        : serializedInput.control.startCheckedClientOriginalGeneratedInferExecution(
          serializedInput.compiled, serializedInput.generation, preparedProgram, graph, provider,
          originalPreparation.runDefinition, originalConsumer,
          originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
          originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes)

    : restoringOriginal
    ? originalPreparation!.control.startCheckedClientOriginalRestoredComposedInferExecution(
      originalPreparation!.compiled, originalPreparation!.runDefinition,
      composedInput!.occurrence, graph, composedInput!.prefix, provider,
      restoredInput!.snapshot, () => restoredInput!.token.available, restoredInput!.savedScope,
      originalConsumer, originalPreparation!.readRetainedBytes,
      originalPreparation!.readExecutionBytes, originalPreparation!.modelRetainedBytes,
      originalPreparation!.modelExecutionBytes, restoredReferenceIssuer, originalInputBodyRead)
    : originalPreparation !== undefined && composedInput !== undefined
    ? originalPreparation.control.startCheckedClientOriginalComposedInferExecution(
      originalPreparation.compiled, originalPreparation.runDefinition,
      composedInput.occurrence, graph, composedInput.prefix, composedInput.inputs,
      provider, originalConsumer, originalPreparation.readRetainedBytes,
      originalPreparation.readExecutionBytes, originalPreparation.modelRetainedBytes,
      originalPreparation.modelExecutionBytes, composedInput.sources, originalInputBodyRead)
    : originalPreparation !== undefined && Object.hasOwn(originalPreparation, 'nodeInstallation')
    ? originalPreparation.control.startCheckedClientInferOriginalPreparation(
      originalPreparation.compiled, originalPreparation.runDefinition,
      preparedProgram, step, graph, registry, values, provider, originalConsumer,
      originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
      originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes, fragment, ordered)
    : checked(originalPreparation !== undefined
    ? moon.clientProgramStartOriginalInferExecution(preparedProgram, step!, graph,
      registry, values!, provider, originalPreparation.compiled, originalPreparation.runDefinition,
      originalConsumer, originalPreparation.readRetainedBytes,
      originalPreparation.readExecutionBytes, originalPreparation.modelRetainedBytes,
      originalPreparation.modelExecutionBytes, fragment!, ordered!)
    : restoredInput !== undefined && (composedInput !== undefined || keyedInput !== undefined)
    ? moon.clientProgramStartRestoredComposedInferInput((composedInput ?? keyedInput)!.occurrence, graph,
      (composedInput ?? keyedInput)!.prefix, provider, restoredInput.snapshot.binding,
      restoredInput.snapshot.descriptorWire, restoredInput.snapshot.rows,
      () => restoredInput.token.available, restoredInput.savedScope, restoredReferenceIssuer,
      keyedInput?.ledger, computeSuffix)
    : restoredInput !== undefined
    ? moon.clientProgramStartRestoredInferInput(preparedProgram, step!, graph, registry,
      values!, provider, restoredInput.snapshot.binding, restoredInput.snapshot.descriptorWire,
      restoredInput.snapshot.rows, () => restoredInput.token.available, restoredInput.savedScope,
      fragment!, ordered!, restoredReferenceIssuer)
    : keyedInput !== undefined
    ? moon.clientProgramStartKeyedInferExecution(keyedInput.occurrence, graph,
      keyedInput.prefix, provider, keyedInput.sources, computeSuffix, keyedInput.ledger)
    : composedInput !== undefined
    ? moon.clientProgramStartComposedInferExecution(composedInput.occurrence,
      graph, composedInput.prefix, composedInput.inputs, provider,
      composedInput.sources)
    : savedSlots !== undefined
    ? acquiredInput === undefined
      ? moon.clientProgramStartRestoredInferSlotReplay(preparedProgram, step!,
        graph, registry, values!, savedSlots, fragment!, ordered!)
      : moon.clientProgramStartAcquiredInferSlotReplay(preparedProgram, step!,
        graph, registry, values!, savedSlots, acquiredInput, fragment!, ordered!)
    : savedCapture === undefined
      ? acquiredInput === undefined
        ? moon.clientProgramStartScopedInferExecution(preparedProgram, step!,
          graph, registry, values!, provider, fragment!, ordered!)
        : moon.clientProgramStartAcquiredInferExecution(preparedProgram, step!,
          graph, registry, values!, provider, acquiredInput, fragment!, ordered!)
      : moon.clientProgramStartRestoredInferReplay(preparedProgram, step!,
        graph, registry, values!, savedCapture, fragment!, ordered!)); }
  catch (error) { io?.close(); io = undefined; throw error; }
  let stopNotified = false;
  const requestStop = () => {
    const result = moon.clientProgramCancelInferExecution(active);
    // Deliver a new stop request once. Repeated sticky cancellation cannot
    // turn a still-pending physical save into a zero-work polling loop.
    if (!stopNotified) { stopNotified = true; io?.notify(); }
    return result;
  };
  const runtimeCurrent = () => {
    if (assertRuntimeCurrent === undefined) return true;
    try { assertRuntimeCurrent(); return true; }
    catch {
      // Actual original currentness loss, NEVER Host closing alone. Only the
      // existing Core stop/failure/cleanup paths drive the retained children.
      requestStop();
      return false;
    }
  };
  let runtimeObservedCallSet: unknown;
  let runtimeDiagnostic: ObserveModel | undefined;
  function observeOriginalRuntime(value: unknown) {
    runtimeCurrent();
    try {
      if (runtimeDiagnostic !== undefined) {
        const facts = moon.clientProgramInferPhysicalObservationFacts(value);
        runtimeDiagnostic({slot: runtimeField(facts, 0), attemptCid: runtimeField(facts, 1),
          event: runtimeField(facts, 2), outcome: runtimeField(facts, 3)});
      }
    } catch { /* Optional diagnostics cannot authorize or block cleanup. */ }
    finally { runtimeCurrent(); }
  }
  function bindOriginalRuntimeObservation(preparedCallSet: unknown) {
    if (runtimeObservedCallSet !== undefined) {
      return runtimeObservedCallSet === preparedCallSet;
    }
    const installed = moon.clientProgramBindInferModelObservation(active,
      preparedCallSet, observeOriginalRuntime);
    if (installed === true) runtimeObservedCallSet = preparedCallSet;
    return installed === true;
  }
  signal?.addEventListener('abort', requestStop, {once: true});
  let flight: Promise<RunOutput | undefined> | undefined;
  let closeFlight: Promise<void> | undefined;
  let reclaimed = false;
  let closing = false;
  let cleanupSettlement: SettlementCleanup | undefined;

  function cleanup() {
    if (reclaimed) return true;
    // This same nominal borrower must retire after its actual publication
    // children/aliases and before parent cleanup. Never drop it on stop alone.
    if (originalPublicationCapacity !== undefined) return false;
    // Cancellation delivery alone never permits releasing the execution.
    if (!moon.clientProgramInferExecutionStopped(active)) return false;
    reclaimed = checked(moon.clientProgramCleanupInferExecution(active)) as boolean;
    if (reclaimed) {
      if (reclaimed === true && originalConsumer !== undefined && originalRead !== null &&
          (typeof originalRead === 'object' || typeof originalRead === 'function')) {
        cleanedOriginalReads.add(originalRead);
      }
      originalRead = undefined;
      originalInputBodyRead = undefined;
      signal?.removeEventListener('abort', requestStop);
      originalPreparedCallSet = undefined;
      if (originalMetadata !== undefined) originalMetadataSources.delete(originalMetadata.handle);
      originalMetadata = undefined;
      if (originalStoreBootstrap !== undefined) originalMetadataSources.delete(originalStoreBootstrap.handle);
      originalStoreBootstrap = undefined;
      originalScope = undefined;
      // Escaped metadata methods must not keep the original installation/Run
      // after this same Core Owner acknowledges cleanup. Pending/failed
      // cleanup retains these aliases; independent immutable borrows and
      // external Store/read custody are neither mutated nor settled here.
      metadataInstallation = undefined;
      metadataNodeInstallation = undefined;
      metadataControl = undefined;
      metadataDefinition = undefined;
      originalPublicationSelection = undefined;
      originalPublicationReceiver = undefined;
      rawCaptureBinder = undefined;
      preparedRawCaptureBinders = undefined;
      credentialPreparations = credentialFailure = undefined;
      runtimeObservedCallSet = undefined;
      runtimeDiagnostic = undefined;
      assertRuntimeCurrent = undefined;
      io?.close();
      io = undefined;
    }
    return reclaimed;
  }

  async function drive() {
    for (;;) {
      runtimeCurrent();
      if (closing || signal?.aborted) requestStop();
      // Arm before polling: a completion during the poll must not be lost.
      // Only Core may decide whether the notification has changed its state.
      const ticket = io?.arm();
      let poll, kind;
      try {
        poll = checked((keyedInput === undefined ? moon.clientProgramAdvanceInferExecution
          : moon.clientProgramAdvanceInferRoot)(active, quantum));
        kind = moon.clientProgramInferExecutionPollKind(poll);
        if (kind === 'await_io') {
          if (ticket === undefined) throw new Error('InferIoNotificationUnavailable');
          await ticket.promise;
          continue;
        }
      } finally { ticket?.dispose(); }
      if (kind === 'waiting') {
        const preparedCallSet = moon.clientProgramInferPreparedCallSet(active);
        if (preparedCallSet === undefined) throw new Error('InferPreparedOwnerUnavailable');
        if (assertRuntimeCurrent !== undefined && !bindOriginalRuntimeObservation(preparedCallSet)) {
          requestStop();
          throw new TypeError('InferTrustedRuntimeObservationUnavailable');
        }
        return Object.freeze({status: 'waiting', preparedCallSet});
      }
      if (kind === 'settling') {
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw new Error('InferSettlementOwnerUnavailable');
        return Object.freeze({status: 'settling', settlement});
      }
      if (kind === 'complete') {
        return moon.clientProgramInferExecutionOutput(poll) as RunOutput | undefined;
      }
      if (kind === 'failed') {
        // Preserve the existing typed cause without a new public classifier.
        checked(runtimeFailure(moon.clientProgramInferExecutionPollIssue(poll)));
      }
      if (kind === 'stopped') {
        if (signal?.aborted) signal.throwIfAborted();
        throw Object.assign(new Error('InferExecutionStopped'),
          {code: 'InferExecutionStopped'});
      }
      if (kind !== 'continue') throw new Error('InvalidInferExecutionPoll');
      await observeProgress?.();
      // A macrotask delivers timer/I/O cancellation; a resolved Promise does
      // not. MoonBit owns work, progress, phase changes and safe stop checks.
      await yieldEventLoop();
    }
  }

  function run() {
    if (composedInput !== undefined && !originalComposedRun && !restoringOriginal || serializedInput?.inputs !== undefined) {
      return Promise.reject(new Error('InferComponentDrivenByLocal'));
    }
    if (closing || reclaimed) {
      return Promise.reject(new Error('InferOperationClosed'));
    }
    if (flight === undefined) {
      flight = drive().then(result => {
        if (result?.status === 'waiting' || result?.status === 'settling') flight = undefined;
        return result;
      });
      // The supervisor observes this promise even if its Client disconnects.
      // Retaining the rejection here prevents an unhandled detached failure.
      flight.catch(() => {});
    }
    return flight;
  }

  async function stop() {
    closing = true;
    requestStop();
    if (flight !== undefined) await flight.catch(() => {});
    // Finish only bounded observation/custody already owned by an entered
    // attempt. requestStop is sticky, so this cannot dispatch another slot.
    while (!moon.clientProgramInferExecutionStopped(active)) {
      requestStop();
      const ticket = io?.arm();
      let poll, kind;
      try {
        poll = checked(moon.clientProgramAdvanceInferExecution(active, 1));
        kind = moon.clientProgramInferExecutionPollKind(poll);
        if (kind === 'await_io') {
          if (ticket === undefined) throw pending();
          await ticket.promise;
          continue;
        }
      } finally { ticket?.dispose(); }
      if (kind === 'settling') {
        if (typeof cleanupSettlement !== 'function') throw pending();
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw pending();
        await cleanupSettlement(settlement);
      } else if (kind === 'continue') {
        await yieldEventLoop();
      } else if (!moon.clientProgramInferExecutionStopped(active)) {
        throw pending();
      }
    }
  }

  function close() {
    if (reclaimed) return Promise.resolve();
    if (closeFlight === undefined) {
      closing = true;
      closeFlight = (async () => {
        await stop();
        if (!cleanup()) throw pending();
      })();
      closeFlight.catch(() => {});
    }
    return closeFlight;
  }

  let originalPreparedCallSet: unknown;
  // One setter per original Core preflight, not one per whole execution. Core
  // bounds and owns that finite cursor inventory before issuing its CallSet.
  // The same original preparation envelope must cover this array/reference
  // and setter/callback overlap BEFORE preparation, not at later registration.
  // No provider-global map, slot scheduler or additional physical Call is used.
  const retainRawCaptureBinder: RetainRawBinder = (callback, request, credential) => {
    if (closing || reclaimed || rawCaptureBound || rawCaptureBinder !== undefined ||
        typeof callback !== 'function') {
      throw new TypeError('InferRawCaptureBinderUnavailable');
    }
    if (credential !== undefined) {
      if (typeof credential !== 'function') throw new TypeError('InferCredentialPreparationUnavailable');
      credentialPreparations ??= [];
      credentialPreparations.push({request, prepare: credential});
    }
    preparedRawCaptureBinders ??= [];
    preparedRawCaptureBinders.push(callback);
  };
  const operation = Object.freeze({run, stop, close, cleanup,
    contentGenerationCount: serializedInput === undefined ? 0 : 1,
    // Publication borrows the same opaque generation used by execution and
    // the joint observation issuer, never a JSON reconstruction of its proof.
    contentGenerations: () => serializedInput === undefined ? undefined
      : Object.freeze([serializedInput.generation]),
    contentRecovery: () => serializedInput?.recovery,
    capturedContentRecovery: () => serializedInput?.capturedRecovery ?? keyedInput?.capturedRecovery ?? composedInput?.capturedRecovery,
    capturedContentBinding: () => serializedInput?.capturedBinding ?? keyedInput?.capturedBinding ?? composedInput?.capturedBinding,
    installSettlementCleanup(callback: SettlementCleanup) {
      if (cleanupSettlement !== undefined || typeof callback !== 'function') {
        throw new TypeError('InvalidInferSettlementCleanup');
      }
      cleanupSettlement = callback;
    },
    cleanupPending: () => !reclaimed,
    ...(managedIo ? {async waitForIo() {
      if (closing || reclaimed || io === undefined) throw new Error('InferIoNotificationUnavailable');
      signal?.throwIfAborted();
      assertRuntimeCurrent!();
      // A notification emitted by the just-completed Common poll remains
      // pending on this original wake port until this one wait claims it.
      const ticket = io.arm();
      try { await ticket.promise; }
      finally { ticket.dispose(); }
      signal?.throwIfAborted();
      assertRuntimeCurrent!();
    }} : {}),
    cleanupProgress: () => moon.clientProgramInferCleanupProgress?.(active),
    physicalStopped: () => moon.clientProgramInferExecutionStopped(active),
    quantityUsage: () => moon.clientProgramInferQuantityUsage(active),
    stoppedAttemptCount: () => moon.clientProgramInferStoppedAttemptCount(active),
    stoppedAttemptSlot: (index: number) => moon.clientProgramInferStoppedAttemptSlot(active, index),
    hasUnknownCalls: () => moon.clientProgramInferHasUnknownCalls(active),
    acquireOutput: () => moon.clientProgramAcquireInferOutput(active),
    acquireCapture: () => moon.clientProgramAcquireInferCapture(active),
    acquireOutcomes: () => moon.clientProgramAcquireInferOutcomes(active),
    invocationEvidence: (slot: number) => moon.clientProgramInferInvocationEvidence(active,
      slot),
    invocationEvidenceView: (control: BindControl, slot: number) => {
      if (reclaimed) return undefined;
      return control.inspectInferInvocationEvidence(moon, active, slot);
    },
    evaluationInput: (slot: number) => {
      if (reclaimed || originalPreparedCallSet === undefined ||
          moon.clientProgramInferInvocationEvidence(active, slot) === undefined) return undefined;
      const request = moon.clientProgramInferPreparedRequest(originalPreparedCallSet, slot);
      const call = moon.clientProgramInferPreparedCallAt(originalPreparedCallSet, slot);
      if (request === undefined || call === undefined) return undefined;
      return Object.freeze({request, callWire: moon.strategyRunEvidenceJson(call)});
    },
    evaluationRequest: (slot: number) => {
      if (reclaimed) return undefined;
      const physical = moon.clientProgramInferEvaluationRequest(active, slot);
      if (physical !== undefined) return physical;
      if (restoredInput?.token.available !== true ||
          moon.clientProgramInferInvocationEvidence(active, slot) === undefined) return undefined;
      const prepared = originalPreparedCallSet;
      if (prepared === undefined) return undefined;
      const request = moon.clientProgramInferPreparedRequest(prepared, slot);
      const call = moon.clientProgramInferPreparedCallAt(prepared, slot);
      if (request === undefined || call === undefined) return undefined;
      const callWire = moon.strategyRunEvidenceJson(call);
      const saved = restoredInput.snapshot.providerInputs?.find(item => item.callWire === callWire);
      // This reads authenticated original strings. A current preflight must
      // never rebuild missing historical provider input or context.
      if (saved === undefined || saved.typedInputWire !== moon.clientProgramModelRequestInputFrame(request)) return undefined;
      return runtimeTriple(request, saved.renderedInput, saved.contextManifest);
    },
    preparedPhysicalRequest: (prepared: unknown, slot: number) => moon.clientProgramInferPreparedPhysicalRequest(prepared, slot),
    // The ordinary publication control owns compilation and contract tokens.
    // It passes the original owner to MoonBit, never recompiling this Program.
    bindRun: (control: BindControl, {compiled, runDefinition}: RunPlan) =>
      control.bindCheckedClientInferRun(compiled, active, runDefinition),
    // The original installing Owner retains read custody. Core verifies the
    // original Run and claims its seal after the actual bounded Identity scan.
    // This private seam does not install a normal physical funding profile.
    bindOriginalPreparation: (read: unknown, retainedBytes: bigint, executionBytes: bigint) =>
      checked(moon.clientProgramBindInferOriginalPreparation(active, read,
        retainedBytes, executionBytes)),
    // Installation-owned original references only. The existing Common owner
    // admits its quiescent boundary; no Node snapshot, caller Bool or CID can
    // substitute for the actual scope/token. A missing port is unavailable,
    // not a fallback to a Resource-only park.
    parkOriginalResources() {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramParkInferOriginalModelResources !== 'function') {
        throw new Error('InferOriginalModelParkUnavailable');
      }
      return checked(moon.clientProgramParkInferOriginalModelResources(
        active, originalScope));
    },
    parkOriginalResourcesForStateWrite() {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramParkInferOriginalModelResourcesForStateWrite !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      return checked(moon.clientProgramParkInferOriginalModelResourcesForStateWrite(active, originalScope));
    },
    prepareOriginalCurrentStateWriter(park: unknown, limits: WriterLimits) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramPrepareInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      if (limits === null || typeof limits !== 'object' ||
          Object.keys(limits).sort().join(',') !== 'maxDepth,maxNodes,maxWireBytes' ||
          Object.values(limits).some(value => !Number.isSafeInteger(value) || value < 0 || value > 2147483647) ||
          limits.maxNodes === 0) throw new TypeError('InvalidInferOriginalCurrentWriterLimits');
      return checked(moon.clientProgramPrepareInferOriginalCurrentStateWriter(active, originalScope, park,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    advanceOriginalCurrentStateWriter(park: unknown, writer: unknown, quantum: number) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramAdvanceInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647) {
        throw new TypeError('InvalidInferOriginalCurrentWriterQuantum');
      }
      const poll = moon.clientProgramInferNodeReadStatePoll(
        moon.clientProgramAdvanceInferOriginalCurrentStateWriter(active, originalScope, park, writer, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    finishOriginalCurrentStateWriter(park: unknown, writer: unknown) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramFinishInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      return checked(moon.clientProgramFinishInferOriginalCurrentStateWriter(active, originalScope, park, writer));
    },
    cancelOriginalCurrentStateWriter(writer: unknown) {
      // Codec retirement remains legal during close; it neither frees the
      // Resource park nor substitutes for the original Model/read cleanup.
      moon.clientProgramCancelInferOriginalCurrentStateWriter(writer);
    },
    startOriginalCurrentStateDecode(park: unknown, wire: string, limits: DecodeLimits) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramStartInferOriginalCurrentStateDecode !== 'function') {
        throw new Error('InferOriginalCurrentDecodeUnavailable');
      }
      if (limits === null || typeof limits !== 'object' ||
          Object.keys(limits).sort().join(',') !== 'maxWork,parse,tree' ||
          !codecLimits(limits.parse, 'max_depth,max_input_bytes,max_nodes') ||
          !codecLimits(limits.tree, 'max_depth,max_nodes,max_string_bytes,max_total_string_bytes') ||
          !codecInt(limits.maxWork, true) || typeof wire !== 'string') {
        throw new TypeError('InvalidInferOriginalCurrentDecodeLimits');
      }
      const {parse, tree, maxWork} = limits;
      return checked(moon.clientProgramStartInferOriginalCurrentStateDecode(active, originalScope,
        park, wire, parse, tree, maxWork));
    },
    advanceOriginalCurrentStateDecode(park: unknown, decoder: unknown, quantum: number) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentDecodeQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateDecodePoll(
        moon.clientProgramAdvanceInferOriginalCurrentStateDecode(active, originalScope, park, decoder, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2), document: runtimeField(poll, 3)});
    },
    cancelOriginalCurrentStateDecode: (decoder: unknown) => moon.clientProgramCancelInferOriginalCurrentStateDecode(decoder),
    retireOriginalCurrentStateDocument: (document: unknown) => moon.clientProgramRetireInferOriginalCurrentStateDocument(document),
    startOriginalCurrentStateComparison(park: unknown, document: unknown, maxWork: number) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(maxWork, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonWork');
      return checked(moon.clientProgramStartInferOriginalCurrentStateComparison(active, originalScope, park, document, maxWork));
    },
    advanceOriginalCurrentStateComparison(park: unknown, comparison: unknown, quantum: number) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateComparisonPoll(checked(
        moon.clientProgramAdvanceInferOriginalCurrentStateComparison(active, originalScope, park, comparison, quantum)));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    cancelOriginalCurrentStateComparison: (comparison: unknown) => moon.clientProgramCancelInferOriginalCurrentStateComparison(comparison),
    advanceOriginalCurrentStateComparisonWithMatch(park: unknown, comparison: unknown, quantum: number) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch !== 'function') {
        throw new Error('InferOriginalCurrentMatchUnavailable');
      }
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateMatchPoll(checked(
        moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch(active, originalScope,
          park, comparison, quantum)));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2), matched: runtimeField(poll, 3)});
    },
    originalCurrentStateMatchCurrent(park: unknown, matched: unknown) {
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalCurrentStateMatchCurrent !== 'function') return undefined;
      return moon.clientProgramInferOriginalCurrentStateMatchCurrent(active, originalScope, park, matched);
    },
    retireOriginalCurrentStateMatch: (matched: unknown) => moon.clientProgramRetireInferOriginalCurrentStateMatch(matched),
    originalResourceParkCurrent(park: unknown) {
      // A pending close is not a physical stop or invalidation. Preserve the
      // original observation while Core still owns this same parked scope.
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalModelResourceParkCurrent !== 'function') {
        return undefined;
      }
      return moon.clientProgramInferOriginalModelResourceParkCurrent(
        active, originalScope, park);
    },
    originalParkedReadCapacityAvailable(park: unknown, retainedBytes: bigint, executionBytes: bigint) {
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalParkedReadCapacityAvailable !== 'function') return false;
      if ([retainedBytes, executionBytes].some(value => typeof value !== 'bigint' ||
          value < 0n || value > 9223372036854775807n)) {
        throw new TypeError('InvalidInferOriginalParkedCapacity');
      }
      // Read the same original token only. Caller/installation must still
      // supply the justified simultaneous envelope before any physical I/O.
      return moon.clientProgramInferOriginalParkedReadCapacityAvailable(
        active, originalScope, park, retainedBytes, executionBytes);
    },
    originalStoreBootstrapAcquisition() {
      if (originalStoreBootstrap !== undefined) {
        originalStoreBootstrap.current(undefined, undefined, 'store-bootstrap');
        return originalStoreBootstrap.handle;
      }
      const selection = selectedInferOriginalMetadataLimits(metadataInstallation!, metadataNodeInstallation);
      const current = (ownerId?: string, requestCid?: string, role?: MetadataRole) => {
        // This pre-park borrow is deliberately NOT a metadata/body/codec
        // acquisition or a stable cut. Only the same original read reservation
        // may cover the first Store observation while approval is pending.
        if (role !== 'store-bootstrap' || reclaimed || closing || signal?.aborted ||
            originalScope === undefined ||
            typeof moon.clientProgramInferOriginalUnparkedReadCapacityAvailable !== 'function' ||
            selectedInferOriginalMetadataLimits(metadataInstallation!, metadataNodeInstallation) !== selection ||
            !moon.clientProgramInferOriginalUnparkedReadCapacityAvailable(active, originalScope,
              selection.retainedBytes, selection.workspaceBytes)) metadataUnavailable();
        if (ownerId !== undefined && (typeof metadataControl?.runDefinitionRunId !== 'function' ||
            ownerId !== `model-${metadataControl.runDefinitionRunId(metadataDefinition)}`) ||
            requestCid !== undefined && requestCid !== metadataDefinition?.identity) metadataUnavailable();
        return selectedInferOriginalStoreBootstrapLimits(metadataInstallation!, metadataNodeInstallation);
      };
      // Same full envelope before allocating the extra record/handle. Physical
      // clamps themselves neither reserve bytes nor issue permission.
      current(undefined, undefined, 'store-bootstrap');
      const handle = Object.freeze({kind: 'original-infer-store-bootstrap-acquisition'});
      originalStoreBootstrap = {handle, current};
      originalMetadataSources.set(handle, new WeakRef(originalStoreBootstrap));
      return handle;
    },
    originalMetadataAcquisition(park: unknown) {
      if (originalMetadata !== undefined) {
        if (originalMetadata.park !== park) metadataUnavailable();
        originalMetadata.current();
        return originalMetadata.handle;
      }
      const selection = selectedInferOriginalMetadataLimits(metadataInstallation!, metadataNodeInstallation);
      const current = (ownerId?: string, requestCid?: string, role?: MetadataRole) => {
        if (reclaimed || closing || signal?.aborted || originalScope === undefined ||
            typeof moon.clientProgramInferOriginalModelResourceParkCurrent !== 'function' ||
            typeof moon.clientProgramInferOriginalParkedReadCapacityAvailable !== 'function' ||
            selectedInferOriginalMetadataLimits(metadataInstallation!, metadataNodeInstallation) !== selection ||
            moon.clientProgramInferOriginalModelResourceParkCurrent(active, originalScope, park) !== park ||
            !moon.clientProgramInferOriginalParkedReadCapacityAvailable(active, originalScope, park,
              selection.retainedBytes, selection.workspaceBytes)) metadataUnavailable();
        if (ownerId !== undefined && (typeof metadataControl?.runDefinitionRunId !== 'function' ||
            ownerId !== `model-${metadataControl.runDefinitionRunId(metadataDefinition)}`) ||
            requestCid !== undefined && requestCid !== metadataDefinition?.identity) metadataUnavailable();
        if (role === 'store-bootstrap') {
          return selectedInferOriginalStoreBootstrapLimits(metadataInstallation!, metadataNodeInstallation);
        }
        if (role === 'resource-state-codec') {
          return selectedInferOriginalCurrentStateCodec(metadataInstallation!, metadataNodeInstallation);
        }
      };
      // Inspect the same token BEFORE allocating the retained record/handle or
      // permitting physical metadata I/O. No grant/reset/refund follows.
      current();
      const handle = Object.freeze({kind: 'original-infer-metadata-acquisition'});
      originalMetadata = {park, selection, handle, current};
      originalMetadataSources.set(handle, new WeakRef(originalMetadata));
      return handle;
    },
    // Borrow the opaque scope captured by this actual operation, not a new
    // selection supplied to a later continuation. Successful cleanup retires
    // the alias; its presence alone is not a park, grant or send permission.
    originalResourceScope: () => reclaimed ? undefined : originalScope,
    beginOriginalResourceInvalidation(park: unknown) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramBeginInferOriginalModelInvalidation !== 'function') {
        throw new Error('InferOriginalModelInvalidationUnavailable');
      }
      return checked(moon.clientProgramBeginInferOriginalModelInvalidation(active, originalScope, park));
    },
    originalResourceInvalidationCurrent(park: unknown, request: unknown) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalModelInvalidationCurrent !== 'function') return undefined;
      return moon.clientProgramInferOriginalModelInvalidationCurrent(active, originalScope, park, request);
    },
    completeOriginalJournalInvalidation(port: unknown, receipt: unknown, reference: unknown, park: unknown, request: unknown) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramCompleteInferOriginalJournalInvalidation !== 'function') {
        throw new Error('InferOriginalModelInvalidationUnavailable');
      }
      // This compiled entry authenticates the actual journal module, not a
      // supplied callback or a bare Core consume. Its arguments always borrow
      // this operation's original active/Scope; the caller cannot replace them.
      return checked(moon.clientProgramCompleteInferOriginalJournalInvalidation(
        active, originalScope, port, receipt, reference, park, request));
    },
    bindDispatch: (control: BindControl, {compiled, runDefinition, ...observation}: RunPlan & DispatchObservation) =>
      control.bindCheckedClientInferDispatch(compiled, active, runDefinition,
        observation),
    preparedCallSet: () => reclaimed ? undefined : moon.clientProgramInferPreparedCallSet(active),
    pendingSettlement: () => moon.clientProgramInferCallSettlement(active),
    exportPreparedInput: (preparedCallSet: unknown, binding: string) => {
      const exported = checked(moon.clientProgramExportInferPreparedInput(active, preparedCallSet, binding));
      return Object.freeze({owner: exported,
        descriptorWire: moon.clientProgramInferPreparedInputExportDescriptor(exported),
        rows: Object.freeze(moon.clientProgramInferPreparedInputExportRows(exported)),
        current: () => moon.clientProgramInferPreparedInputExportMatches(active, preparedCallSet, exported)});
    },
    preparedFacts: (preparedCallSet: unknown) => {
      if (reclaimed) throw new Error('InferPreparedOwnerUnavailable');
      originalPreparedCallSet = preparedCallSet;
      const count = moon.clientProgramInferPreparedCallCount(preparedCallSet);
      const input = moon.clientProgramInferPreparedInput(preparedCallSet);
      const artifact = moon.clientProgramInferPreparedInputArtifact(preparedCallSet);
      const ids = moon.clientProgramInferPreparedIdentities(preparedCallSet);
      // The original composed Read funded these actual reference wrappers
      // and prepared its Scope snapshot before handing the Model off. Legacy
      // explicit envelopes retain their separately qualified count ceiling.
      const maxFacts = originalInputBodyRead === undefined ? 128 : 2147483647;
      if (!Number.isSafeInteger(count) || count! < 0 || count! > maxFacts ||
          input === undefined || artifact === undefined || ids === undefined) {
        throw new Error('InferPreparedOwnerUnavailable');
      }
      const callScopeSnapshotWire = checked(moon.clientProgramInferCallScopeSnapshot(active));
      const slotWires = Array.from({length: count!}, (_, slot) => {
        const call = moon.clientProgramInferPreparedCallAt(preparedCallSet, slot);
        if (call === undefined) throw new Error('InferPreparedCallUnavailable');
        return moon.strategyRunEvidenceJson(call);
      });
      return Object.freeze({preparedCallSet, input,
        inputArtifactWire: moon.strategyRunEvidenceJson(artifact),
        slotWires: Object.freeze(slotWires), providerId: runtimeField(ids, 0),
        modelTaskCid: runtimeField(ids, 1), fixedRequestCid: runtimeField(ids, 2),
        unitId: moon.clientProgramInferCallScopeUnitId(active),
        callScopeSnapshotWire});
    },
    bindModelScope: (control: BindControl, plan: RunPlan, preparedCallSet: unknown, originals: unknown) =>
      control.bindCheckedClientInferModelScope(plan.compiled, active,
        plan.runDefinition, preparedCallSet, originals),
    bindModelDispatch: (control: BindControl, plan: RunPlan, preparedCallSet: unknown, scope: unknown, observation: DispatchObservation & Readonly<{enterCall: EnterCall}>) =>
      control.bindCheckedClientInferModelDispatch(plan.compiled, active,
        plan.runDefinition, preparedCallSet, scope, {...observation,
          enterCall: entry => {
            const originals = moon.clientProgramInferCallEntryOriginals(entry);
            if (originals === undefined) return false;
            return observation.enterCall(Object.freeze({entry,
              slot: runtimeField(originals, 0), callWire: runtimeField(originals, 1),
              attemptWire: runtimeField(originals, 2), authorityWire: runtimeField(originals, 3)})) === true;
          }}),
    entryCurrent: (entry: unknown, preparedCallSet: unknown) =>
      moon.clientProgramInferCallEntryCurrent(entry, preparedCallSet),
    // Installation-only wake endpoint of this already claimed operation.
    // It is not an ACK, public capability or permission to begin another call.
    ioNotification: ioNotification as ReturnType<typeof createInferIoNotification> | undefined,
    hasModelCredentialPreparation: () => credentialPreparations !== undefined || credentialFailure !== undefined,
    prepareModelCredentials(preparedCallSet: unknown, entered: Pick<ReadonlySet<number>, "has">, assertCurrent: () => void) {
      if (credentialFailure !== undefined) throw credentialFailure.cause;
      if (credentialPreparations === undefined) return;
      const preparations = credentialPreparations;
      credentialPreparations = undefined;
      try {
        if (closing || reclaimed || rawCaptureBound || preparedCallSet === undefined ||
            moon.clientProgramInferPreparedCallSet(active) !== preparedCallSet ||
            egressAdmission === undefined) throw new TypeError('InferCredentialPreparationUnavailable');
        const count = moon.clientProgramInferPreparedCallCount(preparedCallSet);
        if (!Number.isSafeInteger(count) || count! < preparations.length) {
          throw new TypeError('InferCredentialPreparationUnavailable');
        }
        let next = 0;
        for (let slot = 0; slot < count!; slot++) {
          if (entered.has(slot)) continue;
          const original = preparations[next++];
          if (original === undefined ||
              moon.clientProgramInferPreparedRequest(preparedCallSet, slot) !== original.request) {
            throw new TypeError('ForeignInferCredentialPreparation');
          }
        }
        if (next !== preparations.length) throw new TypeError('ForeignInferCredentialPreparation');
        for (const original of preparations) {
          if (!runtimeCurrent()) throw new TypeError('InferCredentialPreparationUnavailable');
          checked(moon.clientProgramCheckInferEgressCurrent(egressAdmission));
          assertCurrent();
          if (closing || reclaimed || rawCaptureBound ||
              moon.clientProgramInferPreparedCallSet(active) !== preparedCallSet) {
            throw new TypeError('InferCredentialPreparationUnavailable');
          }
          try { original.prepare(); }
          catch (cause) {
            const code = (cause as {code?: unknown} | undefined)?.code;
            if (code === 'OpenAIProjectCredentialUnavailable' || code === 'ModelProjectCredentialUnavailable') {
              throw new ModelCredentialRefusal(code);
            }
            throw cause;
          }
        }
      } catch (cause) {
        credentialFailure = {cause};
        throw cause;
      }
    },
    // Private installation seam of this original physical operation only.
    // Common registration supplies the nominal raw authority; this callback
    // creates neither a send claim nor an alternate cleanup owner.
    bindModelRawCapture(registration: unknown, persistence: object | undefined) {
      if (closing || reclaimed || rawCaptureBound ||
          rawCaptureBinder === undefined && preparedRawCaptureBinders === undefined) {
        throw new TypeError('InferRawCaptureBindingUnavailable');
      }
      if (persistence !== undefined &&
          !originalModelRawTransportPersistenceMatches(persistence, operation, registration)) {
        throw new TypeError('ForeignInferRawCapturePersistence');
      }
      rawCaptureBound = true;
      try {
        const callbacks = preparedRawCaptureBinders ?? [rawCaptureBinder];
        bindOriginalModelRawTransportPersistence(persistence, operation, registration, next => {
          for (const callback of callbacks) {
            if (callback!(registration, next()) !== undefined) {
              throw new TypeError('InvalidInferRawCaptureBinderResult');
            }
          }
        });
      } finally {
        // A partial failure cannot retry any already bound child. Every
        // original cursor still belongs to Common's existing cleanup census;
        // dropping these auxiliary aliases neither retires it nor ACKs raw.
        rawCaptureBinder = undefined;
        preparedRawCaptureBinders = undefined;
      }
    },
    bindModelEntryPersistence: (control: BindControl, plan: RunPlan, preparedCallSet: unknown, scope: unknown, observation: DispatchObservation & Readonly<{beginEntry: EnterCall}>) =>
      control.bindCheckedClientInferModelEntryPersistence(plan.compiled, active,
        plan.runDefinition, preparedCallSet, scope, {...observation,
          beginEntry: entry => {
            const originals = moon.clientProgramInferCallEntryOriginals(entry);
            if (originals === undefined) return undefined;
            return observation.beginEntry(Object.freeze({entry,
              slot: runtimeField(originals, 0), callWire: runtimeField(originals, 1),
              attemptWire: runtimeField(originals, 2), authorityWire: runtimeField(originals, 3)}));
          }}),
    bindModelObservation: (preparedCallSet: unknown, observe: ObserveModel) => {
      if (assertRuntimeCurrent !== undefined) {
        // Currentness is installed even when optional OTel is absent. Attach
        // metadata delivery to that SAME once-bound observer, not another one.
        if (!bindOriginalRuntimeObservation(preparedCallSet)) return false;
        runtimeDiagnostic = observe;
        return true;
      }
      return moon.clientProgramBindInferModelObservation(active, preparedCallSet, value => {
        // Only the installed metadata observer is called here. Its failure
        // must not escape into invoke, admission, accounting, or cleanup.
        try {
          const facts = moon.clientProgramInferPhysicalObservationFacts(value);
          observe({slot: runtimeField(facts, 0), attemptCid: runtimeField(facts, 1), event: runtimeField(facts, 2), outcome: runtimeField(facts, 3)});
        } catch { /* Optional observation has no execution authority. */ }
      });
    },
    restoreCall: (preparedCallSet: unknown, slot: number, record: unknown, proof: unknown, bundle: unknown, attachmentAdmission: unknown) => checked(
      moon.clientProgramRestoreInferPreparedCall(preparedCallSet, slot, record, proof, bundle, attachmentAdmission)),
    restoreUnknown: (preparedCallSet: unknown, slot: number, attempt: unknown, authority: unknown) => checked(
      moon.clientProgramRestoreInferPreparedUnknown(preparedCallSet, slot, attempt, authority)),
    prepareResponseReconciliation: (preparedCallSet: unknown, slot: number, attempt: unknown, authority: unknown) => checked(
      moon.clientProgramPrepareInferResponseReconciliation(preparedCallSet, slot, attempt, authority)),
    adoptReconciledResponse: (token: unknown, response: unknown) => checked(
      moon.clientProgramAdoptReconciledInferResponse(token, response)),
    settlementSlot: (settlement: unknown) => moon.clientProgramInferCallSettlementSlot(settlement),
    acknowledgeSettlement: (settlement: unknown) => {
      if (!moon.clientProgramAcknowledgeInferCallSettlement(settlement)) {
        throw new Error('InferSettlementAcknowledgementRejected');
      }
    },
    attemptEvidence: (slot: number) => checked(moon.clientProgramInferAttemptEvidence(
      active, slot)),
    advanceStoppedAttemptUsage(slot: number, quantum: number) {
      if (reclaimed || typeof moon.clientProgramAdvanceInferStoppedRawUsage !== 'function') {
        throw new Error('InstalledInferRawUsageUnavailable');
      }
      if (!codecInt(slot) || !codecInt(quantum, true)) {
        throw new TypeError('InvalidInferRawUsageQuantum');
      }
      // Common selects the original call/child and accounts its remaining
      // work. Closing/AbortSignal alone cannot erase partial observations or
      // become a new dispatch authorization check for this cleanup duty.
      const progress = checked(moon.clientProgramAdvanceInferStoppedRawUsage(active, slot, quantum));
      return Object.freeze({complete:runtimeField(progress, 0) as boolean,work:runtimeField(progress, 1) as bigint,issue:runtimeField(progress, 2)});
    },
    issuedAttachmentAdmission: (slot: number) => checked(moon.clientProgramIssueInferAttachmentAdmission(active, slot)),
    issuedSlotCapture: (slot: number) => checked(moon.clientProgramIssueInferSlotCapture(
      active, slot)),
    bindInvocation: (control: BindControl, {compiled, runDefinition, verification,
      invocation, dataPolicyCid}: RunPlan & Readonly<{verification: unknown; invocation: unknown; dataPolicyCid: string}>) => control.bindCheckedClientInferInvocation(
      compiled, active, runDefinition, verification, invocation, dataPolicyCid),
    reserveOriginalPublicationCapacity() : void {
      if (originalConsumer === undefined) return;
      if (reclaimed || closing) throw new Error('InferOriginalPublicationCapacityUnavailable');
      if (originalPublicationCapacity !== undefined) return;
      const selection = originalPublicationSelection === undefined
        ? selectedInferOriginalPublicationCapacity(metadataInstallation!, metadataNodeInstallation)
        : Reflect.apply(originalPublicationSelection, originalPublicationReceiver, []);
      const names = selection !== null && typeof selection === 'object' && !Array.isArray(selection)
        ? Reflect.ownKeys(selection) : [];
      const retained = Object.getOwnPropertyDescriptor(selection ?? {}, 'retainedBytes');
      const workspace = Object.getOwnPropertyDescriptor(selection ?? {}, 'workspaceBytes');
      if (names.length !== 2 || !names.includes('retainedBytes') || !names.includes('workspaceBytes') ||
          retained === undefined || workspace === undefined ||
          !Object.hasOwn(retained, 'value') || !Object.hasOwn(workspace, 'value') ||
          typeof retained.value !== 'bigint' || retained.value <= 0n || retained.value > 9223372036854775807n ||
          typeof workspace.value !== 'bigint' || workspace.value < 0n || workspace.value > 9223372036854775807n) {
        throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
          {code: 'InferOriginalPublicationCapacityUnavailable'});
      }
      // Common binds this borrow to the exact terminal Model/Scope and its
      // original Run Ledger. Missing/refused selection never falls back.
      originalPublicationCapacity = checked(moon.clientProgramReserveOriginalInferPublicationCapacity(
        active, retained.value, workspace.value));
      // Common reserves the carrier's structural delta before constructing
      // even its None case. Subsequent absolute grows start at that actual
      // extent, never the supplier's payload-only input or a repeated delta.
      publicationBaseRetained = publicationHeldRetained =
        moon.clientProgramOriginalInferPublicationRetainedBytes(originalPublicationCapacity);
      publicationBaseExecution = publicationHeldExecution =
        moon.clientProgramOriginalInferPublicationExecutionBytes(originalPublicationCapacity);
    },
    // Actual next scan/writer construction, in addition to this same original
    // publication's retained controls. Covered phases make no extra Resource
    // callback. This grows neither an installed limit nor another Ledger.
    growOriginalPublicationCapacity(retained: bigint, execution: bigint) : void {
      if (reclaimed || closing || originalPublicationCapacity === undefined ||
          typeof retained !== 'bigint' || typeof execution !== 'bigint' ||
          retained < 0n || execution < 0n ||
          retained > 9223372036854775807n - publicationBaseRetained! ||
          execution > 9223372036854775807n - publicationBaseExecution!) {
        throw new Error('InferOriginalPublicationCapacityUnavailable');
      }
      const nextRetained = publicationBaseRetained! + publicationMaterializationRetained + retained;
      const nextExecution = publicationBaseExecution! + publicationMaterializationRetained + execution;
      if (nextRetained > 9223372036854775807n || nextExecution > 9223372036854775807n) {
        throw new Error('InferOriginalPublicationCapacityUnavailable');
      }
      if (nextRetained <= publicationHeldRetained! && nextExecution <= publicationHeldExecution!) return;
      checked(moon.clientProgramGrowOriginalInferPublicationCapacity(active,
        originalPublicationCapacity, nextRetained, nextExecution));
      publicationHeldRetained = nextRetained > publicationHeldRetained! ? nextRetained : publicationHeldRetained!;
      publicationHeldExecution = nextExecution > publicationHeldExecution! ? nextExecution : publicationHeldExecution!;
      // Preserve a real grow even if its callback closed this original. No
      // following projection constructor may proceed after that transition.
      if (reclaimed || closing) throw new Error('InferOriginalPublicationCapacityUnavailable');
    },
    originalMaterializationCurrent(source: OriginalFunding, count: number) : boolean {
      if (closing || reclaimed || originalPublicationCapacity === undefined || !originalOperations.has(source) ||
          typeof moon.clientProgramOriginalInferCaptureInventoryCapacity !== 'function') return false;
      const shape = checked(moon.clientProgramOriginalInferCaptureInventoryCapacity(
        activeOperations.get(source), originalPublicationCapacity));
      return runtimeField(shape, 0) === count;
    },
    prepareOriginalCaptureInventory(source: OriginalFunding) : object | undefined {
      if (!originalOperations.has(source) || typeof moon.clientProgramOriginalInferCaptureInventoryCapacity !== 'function') return undefined;
      operation.reserveOriginalPublicationCapacity();
      const shape = checked(moon.clientProgramOriginalInferCaptureInventoryCapacity(
        activeOperations.get(source), originalPublicationCapacity));
      const count = runtimeField(shape, 0), r = runtimeField(shape, 1), e = runtimeField(shape, 2);
      if (!codecInt(count) || typeof r !== 'bigint' || typeof e !== 'bigint' || r < 0n || e < r) {
        throw new Error('InferOriginalPublicationCapacityUnavailable');
      }
      operation.growOriginalPublicationCapacity(r, e);
      publicationMaterializationRetained += r;
      if (!operation.originalMaterializationCurrent(source, count)) throw new Error('InferOriginalPublicationCapacityUnavailable');
      const receipt = Object.freeze({});
      materializationReceipts.set(receipt, {kind: 'capture', count,
        operation: new WeakRef(source), funding: new WeakRef(operation)});
      return receipt;
    },
    fundedStoppedAttemptCount() : number | undefined {
      if (reclaimed || typeof moon.clientProgramInferFundedStoppedAttemptCount !== 'function') return undefined;
      return moon.clientProgramInferFundedStoppedAttemptCount(active);
    },
    prepareOriginalEvidenceCopy(source: CopySource, bundle: EvidenceBundle, kind: EvidenceKind, retained: bigint, execution: bigint) : object {
      if (!originalOperations.has(source) || !codecInt(bundle?.count, true) ||
          !operation.originalMaterializationCurrent(source, bundle.count)) throw new Error('RequiredEvidenceUnavailable');
      const demand = inferEvidenceCopyConstruction(moon, source, bundle, kind);
      operation.growOriginalPublicationCapacity(retained + demand.retained, execution + demand.execution);
      if (!operation.originalMaterializationCurrent(source, bundle.count)) throw new Error('RequiredEvidenceUnavailable');
      const receipt = Object.freeze({});
      materializationReceipts.set(receipt, {kind, bundle, count: bundle.count,
        operation: new WeakRef(source), funding: new WeakRef(operation)});
      return receipt;
    },
    prepareOriginalUsage(source: OriginalFunding, capture: unknown, count: number) : void {
      if (closing || reclaimed || originalPublicationCapacity === undefined ||
          !originalOperations.has(source) || !operation.originalMaterializationCurrent(source, count) ||
          typeof moon.clientProgramPrepareOriginalInferUsage !== 'function') {
        throw new Error('RequiredEvidenceUnavailable');
      }
      assertRuntimeCurrent?.();
      const prepared = checked(moon.clientProgramPrepareOriginalInferUsage(activeOperations.get(source),
        originalPublicationCapacity, capture,
        publicationBaseRetained! + publicationMaterializationRetained,
        publicationBaseExecution! + publicationMaterializationRetained));
      const retained = runtimeField(prepared, 0) as bigint, execution = runtimeField(prepared, 1) as bigint;
      publicationHeldRetained = retained > publicationHeldRetained! ? retained : publicationHeldRetained!;
      publicationHeldExecution = execution > publicationHeldExecution! ? execution : publicationHeldExecution!;
      if (closing || reclaimed || !operation.originalMaterializationCurrent(source, count)) {
        throw new Error('RequiredEvidenceUnavailable');
      }
      assertRuntimeCurrent?.();
    },
    beginOriginalUsage(source: OriginalFunding, capture: unknown, count: number, maxBytes: number) : unknown {
      if (closing || reclaimed || originalPublicationCapacity === undefined ||
          !originalOperations.has(source) || !operation.originalMaterializationCurrent(source, count) ||
          typeof moon.clientProgramBeginOriginalInferUsagePublication !== 'function') {
        throw new Error('RequiredEvidenceUnavailable');
      }
      assertRuntimeCurrent?.();
      const usage = checked(moon.clientProgramBeginOriginalInferUsagePublication(activeOperations.get(source),
        originalPublicationCapacity, capture,
        publicationBaseRetained! + publicationMaterializationRetained,
        publicationBaseExecution! + publicationMaterializationRetained, maxBytes));
      // The actual same-owner continuation now pins this capacity even when
      // a later Host current callback refuses. Its matching child owns cleanup.
      publicationHeldRetained = moon.clientProgramOriginalInferPublicationRetainedBytes(originalPublicationCapacity);
      publicationHeldExecution = moon.clientProgramOriginalInferPublicationExecutionBytes(originalPublicationCapacity);
      return usage;
    },
    publicationCapacityPending: () => originalPublicationCapacity !== undefined,
    releaseOriginalPublicationCapacity() {
      if (originalPublicationCapacity === undefined) return true;
      const released = checked(moon.clientProgramReleaseOriginalInferPublicationCapacity(
        originalPublicationCapacity));
      if (released) {
        originalPublicationCapacity = undefined;
        publicationBaseRetained = publicationBaseExecution = undefined;
        publicationHeldRetained = publicationHeldExecution = undefined;
        publicationMaterializationRetained = 0n;
      }
      return released;
    },
    startObservation: ({ledger, maxSlots, maxWireBytes, maxWork, operations}: ObservationInputs) : unknown => {
      if (originalConsumer !== undefined) {
        if (ledger !== undefined || originalPublicationCapacity === undefined) {
          throw new Error('InferOriginalPublicationCapacityUnavailable');
        }
        if (operations !== undefined) {
          if (!Array.isArray(operations) || operations.length < 2 || !operations.includes(operation) ||
              operations.some(owner => !originalOperations.has(owner) || !activeOperations.has(owner)) ||
              new Set(operations).size !== operations.length ||
              typeof moon.clientProgramStartCompleteOriginalInferObservationIssuance !== 'function') {
            throw new TypeError('InferOriginalPublicationCapacityUnavailable');
          }
          // Core checks every original Run/Plan/current and the SAME parent
          // Ledger against this existing borrow before constructing metadata.
          // No operation's opaque Ledger or capacity is exposed to the caller.
          const owners = operations.map(owner => activeOperations.get(owner));
          return serializedInput !== undefined
            ? serializedInput.control.startCheckedClientOriginalContentInferObservation(
              owners, [serializedInput.generation], originalPublicationCapacity,
              {maxSlots, maxWireBytes, maxWork})
            : checked(moon.clientProgramStartCompleteOriginalInferObservationIssuance(
              owners, originalPublicationCapacity, maxSlots, maxWireBytes, maxWork, []));
        }
        return serializedInput !== undefined
          ? serializedInput.control.startCheckedClientOriginalContentInferObservation(
            [active], [serializedInput.generation], originalPublicationCapacity,
            {maxSlots, maxWireBytes, maxWork})
          : checked(moon.clientProgramStartOriginalInferObservationIssuance(active,
            originalPublicationCapacity, maxSlots, maxWireBytes, maxWork, []));
      }
      // Preserve the explicit legacy diagnostic/publication path. The original
      // installation never creates this separate Ledger as a funding fallback.
      ledger ??= checked(moon.clientProgramInferPublicationLedger(
        BigInt(maxWireBytes) * 16n + BigInt(maxSlots) * 128n +
        BigInt(operation.contentGenerationCount ?? 0) * 256n, maxWork));
      return serializedInput !== undefined
      ? serializedInput.control.startCheckedClientContentInferObservation(
        serializedInput.compiled, [active], [serializedInput.generation], ledger,
        {maxSlots, maxWireBytes, maxWork})
      : checked(moon.clientProgramStartInferObservationIssuance(active, ledger,
        maxSlots, maxWireBytes, maxWork));
    },
    bindOriginalResultArtifact(control: BindControl, index: number, artifact: unknown, manifest: unknown) {
      if (closing || reclaimed || !Number.isSafeInteger(index) || index < 0 ||
          typeof control?.bindInferOriginalResultArtifact !== 'function') {
        throw new TypeError('ForeignInferResultArtifact');
      }
      control.bindInferOriginalResultArtifact(active, index, artifact, manifest);
    },
    bindIssuedInvocation: (control: BindControl, {compiled, runDefinition, issued}: RunPlan & Readonly<{issued: unknown}>) =>
      control.bindIssuedClientInferInvocation(compiled, active, runDefinition,
        issued),
    // Store use is awaited to settlement before releasing the common Result
    // owner. Aborting a writer is not physical stop confirmation.
    withResult: <Result,>(binding: unknown, result: number, consume: (original: ResultOriginal) => Result,
      resultSignal = signal) =>
      withNodeInferResult({moon, binding, result, consume,
        signal: resultSignal, quantum}),
  });
  activeOperations.set(operation, active);
  if (originalConsumer !== undefined) originalOperations.add(operation);
  try {
    // Input construction already owns Core resources. Transfer that exact
    // owner before any fallible binding, without granting permission to run.
    retainOperation?.(operation);
    if (durableCalls) checked(moon.clientProgramRequireInferCallEntry(active));
    if (restoredInput !== undefined) {
      let mask = restoredInput.sendMask;
      if (typeof restoredInput.sendSlots === 'function') {
        // The restored original input now exists on its SAME claimed Read.
        // Admit the exact boolean arrays BEFORE invoking the existing journal
        // read and map. No token/Task maximum or reserve-method presence funds it.
        const count = originalConsumer !== undefined && originalInputBodyRead !== undefined &&
          typeof moon.clientProgramPrepareOriginalRestoredInferSendMask === 'function'
          ? checked(moon.clientProgramPrepareOriginalRestoredInferSendMask(active)) : undefined;
        if (count !== undefined && !codecInt(count)) throw new Error('InferOriginalSendMaskUnavailable');
        const slots = restoredInput.sendSlots();
        if (!Array.isArray(slots) || count === undefined && slots.length > 128 ||
            count !== undefined && slots.length !== count) throw new Error('InferOriginalSendMaskUnavailable');
        mask = slots.map(slot => slot.state === 'Unsent');
      }
      checked(moon.clientProgramRestrictInferSendSlots(active, mask));
    }
    if (quantityCapacity !== undefined) {
      const {limits, perAttempt} = quantityCapacity;
      checked(moon.clientProgramBindInferQuantityCapacity(active,
        limits.tokens, limits.costUnits, limits.durationMs,
        perAttempt.tokens, perAttempt.costUnits, perAttempt.durationMs));
    }
    if (bindComputeSuffix !== undefined) checked(bindComputeSuffix(active));
    else if (computeSuffix !== undefined && keyedInput === undefined) checked(moon.clientProgramBindInferComputeSuffix(active, computeSuffix));
    if (physicalPreflight !== undefined) {
      // Reuse this operation's nominal wake endpoint for SDK preparation and
      // physical I/O. It carries no ACK, outcome, authority or send permission.
      // The original preparation envelope funds this one callback closure and
      // its overlap with Core's retained callback; no per-poll context is made.
      const prepare = ioNotification === undefined ? physicalPreflight
        : (request: unknown) => prepareWithOriginalRawSetter(physicalPreflight, request,
          ioNotification, retainRawCaptureBinder);
      checked(assertRuntimeCurrent === undefined
        ? moon.clientProgramBindInferPhysicalPreflight(active, prepare)
        : moon.clientProgramBindInferPhysicalPreflightCurrent(active, prepare, runtimeCurrent));
    }
    if (egressAdmission !== undefined) checked(moon.clientProgramBindInferEgress(active, egressAdmission));
  } catch (error) {
    // Preserve the admission failure even when stop/cleanup cannot finish.
    // The receiving parent retries this owner, never construction or dispatch.
    closing = true;
    try {
      requestStop();
      const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(stopped) === 'stopped' &&
          retainOperation === undefined) cleanup();
    } catch { /* The original failure and pending owner remain authoritative. */ }
    if (!reclaimed && error !== null && typeof error === 'object' &&
        Object.isExtensible(error) && !Object.hasOwn(error, 'cleanupOwner')) {
      Object.defineProperty(error, 'cleanupOwner', {value: operation});
    }
    throw error;
  }
  return operation;
}

type Operation = ReturnType<typeof openNodeInferOperation>;
type ComposedSelected = Readonly<{
  occurrence?: unknown; graph: unknown; computePrefix?: unknown; computeSuffix?: unknown;
  provider: unknown; quantityCapacity?: QuantityCapacity; physicalPreflight?: PhysicalPreflight;
  egressAdmission?: unknown; account?: unknown; observeAccount?: () => unknown; entryPersistence?: 'async';
  providerBinding?: Readonly<{wire: string; identity: string; originals: unknown}>;
  originalReadInstallation?: unknown;
}>;
type GeneratedInput = Readonly<{generation(): unknown; recovery?(): unknown}>;
type ComposedPreparation = Partial<OriginalPreparation> & Readonly<{
  prepareRead?: (restored?: RestoredInput) => OriginalPreparation;
  restoreRead?: (restored?: RestoredInput) => OriginalPreparation;
}>;
type CapturedInput = Readonly<{recovery?: unknown; binding?: unknown}>;
type PrepareOriginalResults = (inputs: unknown) => readonly Readonly<{index: number; artifact: unknown; manifest: unknown}>[] | undefined;
type PrepareSourceContext = () => Readonly<{sources: unknown; capturedInput?: CapturedInput}>;
type ComposedContext = Readonly<{
  selected: ComposedSelected; sources?: unknown; control?: BindControl & ContentControl; plan?: RunPlan;
  principalId?: string; now?: () => string; signal?: AbortSignal; durableCalls?: boolean;
  retainOperation?: (operation: Operation) => void; retainCompleted?: (operation: Operation) => boolean | void;
  restoredInput?: RestoredInput; generatedInput?: GeneratedInput; originalPreparation?: ComposedPreparation;
  capturedInput?: CapturedInput; assertRuntimeCurrent?: () => void;
  prepareOriginalResults?: PrepareOriginalResults; prepareSourceContext?: PrepareSourceContext;
}>;
type ComposedOptions = ComposedContext & Readonly<{moon: Runtime; deferred?: boolean;
  deferredGeneratedInput?: boolean; inputPrefix?: unknown; bindComputeSuffix?: (active: unknown) => unknown;
  prepareInputSegments?: () => unknown; managedIo?: boolean}>;
type ComposedProvider = (occurrence: unknown, open: (input: unknown) => unknown, observeIssue: (issue: unknown) => void,
  retainCompleted: (active: unknown) => boolean, allowCleanup: (active: unknown) => boolean, inputPrefix?: unknown) => unknown;
type ComposedComponent = Readonly<{
  provider: unknown; operation(): Operation | undefined; failure(): unknown; hasFailure(): boolean;
  startRestored(): Operation; startSourceFreeSingleUnit?(preparedProgram: unknown): Operation;
  bindOriginal?(context: ComposedContext): ComposedComponent;
}>;
type ComponentDiagnostic = Readonly<{code: string; phase: string; kind: string; task: number; unit: number; step: number}>;

// One original Model component is opened by the common Local task driver,
// after it has bound actual producer reads. Local advances fresh components;
// the genuine restored entrance can drive its retained input before Host open.
// The installing Run retains custody before binding current admissions.
export function openNodeComposedInferProvider({moon, selected, sources,
  control, plan, principalId, now, signal, retainOperation, retainCompleted,
  durableCalls = false, restoredInput, generatedInput, originalPreparation, deferred = false,
  deferredGeneratedInput = false, capturedInput,
  inputPrefix = selected?.computePrefix, bindComputeSuffix, assertRuntimeCurrent, prepareInputSegments,
  managedIo = false}: ComposedOptions) {
  if (selected?.occurrence === undefined ||
      typeof deferred !== 'boolean' || typeof deferredGeneratedInput !== 'boolean' ||
      typeof managedIo !== 'boolean' || managedIo && (!deferred || deferredGeneratedInput ||
        selected.originalReadInstallation === undefined || selected.entryPersistence !== 'async' ||
        typeof selected.physicalPreflight !== 'function') ||
      deferredGeneratedInput && !deferred || !deferred && typeof retainOperation !== 'function' ||
      deferred && (generatedInput !== undefined || originalPreparation !== undefined || retainOperation !== undefined)) {
    throw new TypeError('InvalidComposedInferProvider');
  }
  if (bindComputeSuffix !== undefined && typeof bindComputeSuffix !== 'function') {
    throw new TypeError('InvalidInferOriginalSuffixBinding');
  }
  if (prepareInputSegments !== undefined && (typeof prepareInputSegments !== 'function' ||
      originalPreparation === undefined || inputPrefix !== undefined || bindComputeSuffix !== undefined)) {
    throw new TypeError('InvalidComposedInferInputPreparation');
  }
  const selectRead = (preparation?: ComposedPreparation, restored?: RestoredInput) => {
    if (restored !== undefined && preparation !== undefined) {
      if (typeof preparation?.restoreRead !== 'function' || generatedInput !== undefined || deferredGeneratedInput) {
        throw new TypeError('InvalidComposedInferOriginalPreparation');
      }
      return preparation.restoreRead;
    }
    const prepare = preparation?.prepareRead;
    if (prepare !== undefined && typeof prepare !== 'function') {
      throw new TypeError('InvalidComposedInferOriginalPreparation');
    }
    return prepare;
  };
  let prepareRead = selectRead(originalPreparation, restoredInput);
  let deferredRead = prepareRead !== undefined;
  let readAttempted = false;
  let operation: Operation | undefined;
  let prepareOriginalResults: PrepareOriginalResults | undefined, prepareSourceContext: PrepareSourceContext | undefined,
    singleUnitPrepared: unknown;
  let failure: unknown;
  let failureRecorded = false;
  const recordFailure = (cause: unknown) => {
    if (!failureRecorded) {failure = cause; failureRecorded = true;}
  };
  let bound = !deferred, attempted = false;
  // A Request module can supply its already-backed original before this
  // native component selects input-dependent capacity. Never reprepare it.
  let computePrefix = inputPrefix;
  let computeSuffix = selected.computeSuffix;
  const generated = generatedInput !== undefined || deferredGeneratedInput;
  const selectProvider: ComposedProvider = generated
    ? moon.clientProgramGeneratedInferLocalProvider
    : managedIo ? moon.clientProgramComposedInferLocalProviderWithIo
      : moon.clientProgramComposedInferLocalProvider;
  const openOriginal = (inputs: unknown, ioNotification?: unknown) => {
      try {
        if (attempted || operation !== undefined || readAttempted || deferredRead && failure !== undefined) {
          if (failureRecorded) throw failure;
          throw new Error('ComposedInferAlreadyOpened');
        }
        attempted = true;
        if (!bound) throw new Error('ComposedInferOriginalContextUnavailable');
        let preparation = originalPreparation;
        if (deferredRead) {
          // The parent already retains the Scope. Claim its read only after
          // Local has supplied the actual inputs, with no intervening await.
          readAttempted = true;
          try { preparation = Reflect.apply(prepareRead!, originalPreparation,
            restoredInput === undefined ? [] : [restoredInput]); }
          finally {
            // Retire only these callback aliases, never the original parent's
            // read/Scope duty or a failed issuance's pending cleanup.
            prepareRead = undefined;
            originalPreparation = undefined;
          }
          // Do not read an inherited getter on the original view. A native
          // async return is observed only to suppress detached rejection, not
          // awaited or admitted as a synchronous read original.
          const asyncView = isPromise(preparation);
          if (preparation === null || typeof preparation !== 'object' ||
              asyncView || Object.hasOwn(preparation, 'then')) {
            if (asyncView) void Reflect.apply(observePromise, preparation, [undefined, () => {}]);
            throw new TypeError('InvalidComposedInferOriginalPreparation');
          }
        }
        if (prepareInputSegments !== undefined) {
          // The same parent already retains this actual fallible Read. Lower
          // its checked segments once, before the existing consumer claims it;
          // saved rows are never a GeneratedSequence or a new Source read.
          const segments = prepareInputSegments();
          computePrefix = runtimeField(segments, 0);
          computeSuffix = runtimeField(segments, 1);
        }
        if (prepareSourceContext !== undefined) {
          const context = prepareSourceContext();
          sources = context.sources; capturedInput = context.capturedInput;
          prepareSourceContext = undefined;
        }
        const resultArtifacts = restoredInput === undefined ? prepareOriginalResults?.(inputs) : undefined;
        operation = openNodeInferOperation({moon, graph: selected.graph,
          preparedProgram: singleUnitPrepared,
          composedInput: generated ? undefined : {occurrence: selected.occurrence,
            prefix: computePrefix, inputs, sources,
            capturedRecovery: capturedInput?.recovery, capturedBinding: capturedInput?.binding},
          serializedInput: !generated ? undefined : {
            control: control!, compiled: plan!.compiled, definition: plan!.runDefinition,
            generation: generatedInput!.generation(), inputs: inputs as readonly unknown[],
            recovery: generatedInput!.recovery?.()},
          // The Request module's original binder already owns this suffix.
          // An earlier query-selection suffix is not a second issuer for it.
          computeSuffix: !generated && bindComputeSuffix === undefined
            ? computeSuffix : undefined, provider: selected.provider,
          quantityCapacity: selected.quantityCapacity,
          physicalPreflight: managedIo ? (request, notification, retainRawBinder) => {
            try { return selected.physicalPreflight!(request, notification, retainRawBinder); }
            catch (cause) {
              // Keep the original refusal and let Common unwind its own
              // advance and retained startup through the typed None path.
              recordFailure(cause);
              return undefined;
            }
          } : selected.physicalPreflight,
          egressAdmission: selected.egressAdmission, signal, durableCalls, restoredInput,
          ioNotification: managedIo ? createInferIoNotification() : ioNotification, managedIo,
          ...(restoredInput === undefined ? {originalPreparation: preparation as OriginalPreparation | undefined}
            : {restoredPreparation: preparation as OriginalPreparation | undefined}), bindComputeSuffix, assertRuntimeCurrent,
          retainOperation(value) { operation = value; retainOperation!(value); }});
        operation.bindRun(control!, plan!);
        for (const original of resultArtifacts ?? []) {
          operation.bindOriginalResultArtifact(control!, original.index, original.artifact, original.manifest);
        }
        if (!durableCalls) operation.bindDispatch(control!, {...plan!, account: selected.account,
          principalId, at: now!(), observeAccount: selected.observeAccount,
          observeAt: now});
        return activeOperations.get(operation);
      } catch (error) {
        recordFailure(error);
        return undefined;
      }
    };
  const provider = selectProvider(
    selected.occurrence, openOriginal, issue => {
      const error = Object.assign(new Error('ComposedInferComponentFailed'),
        {code: 'MoonBitHostFailure', cause: issue}) as Error & {code: string; primaryDiagnostic?: ComponentDiagnostic};
      try {
        const kind = moon.clientProgramInferCallScopeIssueKind?.(issue);
        const coordinates = moon.clientProgramInferOccurrenceCoordinates?.(selected.occurrence);
        const task = runtimeField(coordinates, 0) as number, unit = runtimeField(coordinates, 1) as number,
          step = runtimeField(coordinates, 2) as number;
        if (typeof kind === 'string' && kind.startsWith('call_scope.') &&
            kind.length <= 96 && /^[a-z_]+(?:\.[a-z_]+)*$/u.test(kind) &&
            [task, unit, step].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647)) {
          error.primaryDiagnostic = Object.freeze({code: 'MoonBitHostFailure',
            phase: 'original_infer_component', kind,
            task, unit, step});
        }
      } catch { /* Optional typed DATA never replaces the original issue. */ }
      recordFailure(error);
    }, active => {
      try {
        if (operation === undefined || activeOperations.get(operation) !== active) {
          throw new Error('ForeignComposedInferCompletion');
        }
        return retainCompleted?.(operation) !== false;
      } catch (error) {
        recordFailure(error);
        return false;
      }
    }, active => operation !== undefined &&
      activeOperations.get(operation) === active &&
      operation.cleanupPending() === false,
    ...(!generated ? [computePrefix] : []));
  const component: ComposedComponent = Object.freeze({provider, operation: () => operation,
    failure: () => failure, hasFailure: () => failureRecorded,
    startRestored() {
      if (failureRecorded) throw failure;
      if (attempted) throw new Error('ComposedInferAlreadyOpened');
      if (!bound || generated || restoredInput?.savedScope === undefined || !deferredRead) {
        throw new Error('RestoredComposedInferOriginalUnavailable');
      }
      // The typed restored entrance uses the original retained input/Saved
      // Scope. No Local input array or second provider read is substituted.
      openOriginal([], selected.entryPersistence === 'async' ? createInferIoNotification() : undefined);
      if (failureRecorded) throw failure;
      if (operation === undefined) throw new Error('RestoredComposedInferOriginalUnavailable');
      return operation;
    },
    ...(deferred ? {startSourceFreeSingleUnit(preparedProgram: unknown) {
      if (failureRecorded) throw failure;
      if (!bound || attempted || generated || restoredInput !== undefined ||
          !deferredRead || sources !== undefined || inputPrefix === undefined ||
          typeof bindComputeSuffix !== 'function' || originalPreparation === undefined ||
          moon.clientProgramTaskCount(preparedProgram) !== 1 ||
          moon.clientProgramAcquisitionCount(preparedProgram) !== 0) {
        throw new TypeError('ComposedInferOriginalSingleUnitUnavailable');
      }
      // The original operation verifies the SAME compiled Program and full
      // prefix/Scope tuple before it claims, binds or starts physical work.
      singleUnitPrepared = preparedProgram;
      openOriginal([], selected.entryPersistence === 'async' ? createInferIoNotification() : undefined);
      singleUnitPrepared = undefined;
      if (failureRecorded) throw failure;
      if (operation === undefined) throw new TypeError('ComposedInferOriginalSingleUnitUnavailable');
      return operation;
    }, bindOriginal(context: ComposedContext) {
      if (bound || attempted) throw new Error('ComposedInferAlreadyBound');
      const read = <Key extends keyof ComposedContext,>(name: Key): ComposedContext[Key] =>
        Object.getOwnPropertyDescriptor(context ?? {}, name)?.value;
      if (read('selected') !== selected || typeof read('retainOperation') !== 'function') {
        throw new TypeError('InvalidComposedInferOriginalContext');
      }
      const generatedOriginal = read('generatedInput');
      if (generated ? generatedOriginal === null || typeof generatedOriginal !== 'object' ||
          typeof Object.getOwnPropertyDescriptor(generatedOriginal, 'generation')?.value !== 'function'
        : generatedOriginal !== undefined) throw new TypeError('InvalidComposedInferOriginalContext');
      const preparation = read('originalPreparation');
      const prepare = selectRead(preparation, read('restoredInput'));
      sources = read('sources'); control = read('control'); plan = read('plan');
      principalId = read('principalId'); now = read('now'); signal = read('signal');
      retainOperation = read('retainOperation'); retainCompleted = read('retainCompleted');
      prepareSourceContext = read('prepareSourceContext');
      if (prepareSourceContext !== undefined && typeof prepareSourceContext !== 'function') throw new TypeError('InvalidComposedInferSourceContext');
      prepareOriginalResults = read('prepareOriginalResults');
      if (prepareOriginalResults !== undefined && typeof prepareOriginalResults !== 'function') {
        throw new TypeError('InvalidComposedInferOriginalResults');
      }
      durableCalls = read('durableCalls') === true; restoredInput = read('restoredInput');
      generatedInput = generatedOriginal;
      capturedInput = read('capturedInput');
      assertRuntimeCurrent = read('assertRuntimeCurrent');
      if (assertRuntimeCurrent !== undefined && typeof assertRuntimeCurrent !== 'function') {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
      originalPreparation = preparation; prepareRead = prepare; deferredRead = prepare !== undefined;
      bound = true;
      return component;
    }} : {})});
  return component;
}

// Share the actual geometry quote and original grow for Pure/Effect copies.
// Required DATA/typed-input policies remain in the existing projection caller.
export function originalInferEvidenceCopyFunding({moon, funding, operation, current,
  retainedPrefix = () => 0n, executionPrefix = () => 0n, legacy = true}: CopyFundingOptions) {
  if (!legacy && (!originalOperations.has(funding) || !originalOperations.has(operation) ||
      typeof moon.clientProgramOriginalInferCaptureInventoryCapacity !== 'function')) return undefined;
  return originalInferCopyFunding(funding, operation, (bundle, kind) => {
    current();
    // The genuine operation derives the SAME actual quote internally. Passing
    // zero or a caller-picked scalar cannot issue an underfunded receipt.
    const receipt = fundInferEvidenceCopy(funding, operation, bundle, kind,
      retainedPrefix(), executionPrefix());
    if (receipt === undefined && bundle.count <= 128) {
      const demand = inferEvidenceCopyConstruction(moon, operation, bundle, kind);
      funding.growOriginalPublicationCapacity(retainedPrefix() + demand.retained,
        executionPrefix() + demand.execution);
    }
    current();
    return receipt;
  });
}
