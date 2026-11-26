import {dispatchFailureSnapshot, dispatchFailureCodeSite, publicBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {addAbortListener} from 'node:events';
import {types as nodeTypes} from 'node:util';
import {runtimeField, runtimeOptionalField, runtimeTag, runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan,
  localContractLimits, sourceFreePlanExecutionOwner} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {ordinarySourceDescriptors, verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installTaskObservation} from '../host-common/task-observation.mjs';
import {prepareInstalledLogicalObservation} from './logical-task-observation.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';
import {ledgerUsageDiagnostic} from '../host-common/runtime-core.mjs';
import {isModelCredentialRefusal} from './infer-operation.mjs';
import {closeDebugControl, closeSampleAdoption, createClientDispatchCleanup,
  releaseDispatchPreparationHost, retainDispatchPreparationHost, returnSampleProfileObservation}
  from './client-dispatch-cleanup.mjs';
import {createClientDispatchTracking} from './client-dispatch-tracking.mjs';
import {createClientDispatchKeyedAcquisition, createClientDispatchSourceAcquisition} from './client-dispatch-source-acquisition.mjs';
import {confirmNodeRunCancellation, observeNodeRunStop, recordNodeRunPhysicalStop}
  from './client-dispatch-stop.mjs';
export {cancelNodeRunContinuation, confirmNodeRunCancellation, observeNodeRestoredLocalStop,
  observeNodeRestoredModelStop, observeNodeRunCancellation, recordNodeRunPhysicalStop}
  from './client-dispatch-stop.mjs';


import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {WireControlOperationRef} from '../../packages/client-wire/interactive-control.generated.js';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import type {openClientRequestJournal} from './client-request-journal.mjs';
import type {installClientRunSample} from './client-run-plan.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Ref = WireRunRef;
type Journal = ReturnType<typeof openClientRequestJournal>;
type PublicationControl = ReturnType<typeof runtimeCore>['publicationControl'];
type DebugReadScope = Parameters<Journal['lookupDebugResume']>[1];
type NextSampleRead = NonNullable<Parameters<typeof installClientRunSample>[0]['readNextRetained']>;
type DispatchAuthority = Readonly<{principalId: string; connection: object; ref: Ref}>;
type DebugActor = Omit<DispatchAuthority, 'ref'> & Readonly<{authorize(): boolean}>;
type DebugResumeActor = DebugActor & Readonly<{reserve: NonNullable<DebugReadScope['reserve']>}>;
type DebugPark = Parameters<Journal['debugPauseCurrent']>[1]['parked'];
type RetainedDebugEntry = Readonly<{park: Extract<DebugPark, {controlRevision?: undefined}>;
  assertCurrent(): true; ready(): void}>;
type PhysicalStartOptions = Parameters<Journal['reservePhysicalStart']>[1];
type DebugStartSelection = NonNullable<PhysicalStartOptions['debugResume']>;
type DebugStartWitness = Parameters<DebugStartSelection['capture']>[0];
type SampleStartSelection = NonNullable<PhysicalStartOptions['captureSampleStart']>;
type SampleWriter = Parameters<NonNullable<SampleStartSelection['captureAdoption']>>[0];
type SampleProfile = ReturnType<NonNullable<NonNullable<
  ReturnType<Journal['originalSubmittedIntent']>>['checkSampleProfile']>>;
type DebugDefinition = NonNullable<Parameters<Journal['acceptDebugTaskResume']>[1]['receiptOriginal']>['runDefinition'];
type DebugJournal = Pick<Journal, 'parkDebugEntry' | 'parkDebugTask' | 'debugPauseCurrent' |
  'acceptDebugEntryResume' | 'acceptDebugTaskResume' | 'readRetainedRelationSample'>;
type DebugControl = Parameters<Journal['parkDebugEntry']>[3] &
  Parameters<Journal['acceptDebugTaskResume']>[2] & Parameters<Journal['readRetainedRelationSample']>[3];
type DebugBinding = [profile: unknown, owner: unknown, setup: unknown];
type DebugAccountBinding = [...DebugBinding, account: unknown, principal: string, site: string];
type DebugCommand = 'prepare' | 'step' | 'terminal';
type SampleStartMoon = Readonly<{
  clientProgramAdvanceRelationSampleStartControl?(...args: [...DebugAccountBinding, advance: boolean]): unknown;
}>;
type DebugMoon = Parameters<Journal['parkDebugEntry']>[2] & Readonly<{
  clientProgramAdvanceRelationSampleDebugEntry?(...args: [...DebugAccountBinding, command: DebugCommand, revision: number]): unknown;
  clientProgramRelationSampleDebugEntryStep?(...args: DebugBinding): unknown;
  clientProgramRelationSampleDebugEntryRunnable?(...args: [...DebugBinding, startRevision: number]): unknown;
  clientProgramRelationSampleDebugTaskPause?(...args: [...DebugBinding, startRevision: number]): unknown;
  clientProgramRelationSampleDebugNextInput?(...args: [...DebugBinding, startRevision: number,
    controlRevision: number, pauseGeneration: number, nextStepId: string, input: number, maxWork: number]): unknown;
  clientProgramResumeRelationSampleDebugTask?(...args: [...DebugAccountBinding,
    startRevision: number, controlRevision: number, stepId: string, nextStepId: string,
    committedGeneration: number, step: boolean]): unknown;
  clientProgramRelationSampleDebugResumeAllowed?(...args: DebugAccountBinding): unknown;
}>;
type DebugLive = {setup: unknown; owner: unknown; authority: DispatchAuthority; account: unknown; profile: unknown;
  signal: AbortSignal; logicalMapCid?: string; runDefinition?: DebugDefinition; startRevision: number; revision: number};
type DebugWait = {parked: DebugPark; resolve(handoff: string | undefined): void; reject(reason: unknown): void;
  listener: ReturnType<typeof addAbortListener>; timer?: ReturnType<typeof setTimeout>; unresolved?: boolean};
type Stop = Parameters<typeof observeNodeRunStop>[0];
type InferAdmission = PublicationControl['admitInferCapturedInput'];
type CleanupPorts = Parameters<typeof createClientDispatchCleanup<Ref, Accepted>>[0];
type TrackingPorts = Parameters<typeof createClientDispatchTracking<Ref>>[0];
type Acquisition = ReturnType<typeof createClientDispatchSourceAcquisition<Ref>>;
type AcquisitionPorts = Parameters<typeof createClientDispatchSourceAcquisition<Ref>>[0];
type KeyedAcquisition = ReturnType<typeof createClientDispatchKeyedAcquisition<Ref>>;
type KeyedPorts = Parameters<typeof createClientDispatchKeyedAcquisition<Ref>>[0];
type Keyed = Parameters<KeyedAcquisition>[2];
type Direct = Parameters<typeof acquiredTaskPublicationPlan<unknown>>[0];
type Plural = Parameters<typeof acquiredMultiTaskPublicationPlan<unknown>>[0];
type Logical = Parameters<typeof prepareInstalledLogicalObservation>;
type Published = typeof runPublishedCapturedStrategy;
type RelationSampleDriver = NonNullable<Parameters<Published>[9]>;
type TrackedEntry = NonNullable<ReturnType<TrackingPorts['current']>>;
type Execution = NonNullable<TrackedEntry['cleanupOwner']>;
type FailureHandle = Readonly<{status(): Readonly<{pending: boolean}> | undefined; retry(): unknown}>;
type Terminal = 'failed' | 'cancelled' | null;
type Prepared = Parameters<Acquisition>[2] & Readonly<{readTuple: unknown; physicalBinding: unknown}>;
type Occurrence = Keyed['directOccurrence'] & Readonly<{computeTask?: number}>;
type Capture = NonNullable<Parameters<Acquisition>[0]['sourceCapture']> & Direct['captured'] &
  Readonly<{capture: Direct['captured']['capture'] & Readonly<{
    retainTask(dag: unknown, task: number): unknown;
  }>; occurrence: Occurrence; composedInfer?: boolean; setup?: object;
    checkedSource: Readonly<{sourceDataPolicyCid: string}>;
  }>;
type Capacity = Readonly<{capacity: unknown; transferBytes: bigint; executionBytes: bigint;
  managedRun?: unknown; wholeInput?: boolean}>;
type SourceAccess = Keyed['keyedAccess'];
type AcquisitionMember = NonNullable<NonNullable<AcquisitionPorts['sourceProfile']>['sources']>[number];
type SourceInput = Parameters<AcquisitionMember['open']>[0];
type Adapter = Readonly<{
  admitsSource(sourceRef: string): boolean;
  open(input: Omit<SourceInput, 'retainedRelationOutput'> & Readonly<{occurrence?: Occurrence; retainedRelationOutput?: boolean}>): Capture | Promise<Capture>;
  openCapture?: Keyed['directAdapter']['openCapture'] & NonNullable<AcquisitionMember['openCapture']>;
  sourceAccess?: SourceAccess;
  retirePreparedSource?(prepared: unknown): SynchronousRuntimeData;
  ordinaryRecoveryBinding?(prepared: Prepared): unknown;
  supportsRetainedRelationOutput?: boolean;
  connectorBindings: readonly Readonly<{connectorId: string; bindingCid: string}>[];
  connectorRegistration: string;
  connectorRevision: string;
  ledgerCapacity?(prepared: Prepared): Capacity;
  keyedLedgerCapacity?(acquisition: unknown): Capacity & Keyed['capacity'];
  openKeyedLookup?: Keyed['keyedAdapter']['openKeyedLookup'];
  keyedRecoveryBinding?: Keyed['keyedAdapter']['keyedRecoveryBinding'];
  prepareKeyed?(options: Readonly<{preparedProgram: unknown; keyedAcquisition: unknown;
    requestIdentity: unknown; sourceAccess: SourceAccess | undefined}>):
    Awaitable<Readonly<{prepared: Keyed['preparedKeyed']}>>;
  requiresRunContentCapture?: boolean;
}>;
type PreparedMember = Readonly<{adapter: Adapter; prepared: Prepared; occurrence: Occurrence; sourceAccess?: SourceAccess}>;
type SelectedSource = PreparedMember & Readonly<{access: SourceAccess | undefined; preparedSource: Prepared}>;
type PreparedPlan = Direct['acquired'];
type Plan = PreparedPlan | (ReturnType<typeof acquiredTaskPublicationPlan<unknown>> &
  Readonly<{kind?: undefined; serializationGraph?: undefined; compiled?: undefined}>);
type Held = {
  plan?: Plan; preparedSource?: Prepared; preparedSourceAccess?: SourceAccess;
  preparedSources?: readonly PreparedMember[]; managedRun?: unknown;
  sampleProfile?: string;
  prepareSampleStart?: ReturnType<typeof installNodeRelationSampleStart>;
  debugEntryExpiresAt?: number;
  retainedDebugEntry?: RetainedDebugEntry;
  debugResumeCid?: string;
  keyedSource?: Readonly<{acquisition: unknown; prepared: Prepared; occurrence: Occurrence; requestIdentity: unknown}>;
};
type Accepted = NonNullable<ReturnType<Journal['lookupRunDefinition']>>;
type Submission = Readonly<{requestId: string; principalId: string; connection: object; preparedProgram: unknown;
  kind?: unknown; input?: unknown; parameters?: unknown}>;
type RequestGate = Readonly<{beforePhysicalStart(): unknown; started(): unknown}>;
type DispatchStart = 'started' | 'not_started' | Readonly<{refused: unknown}>;
type DispatchAdmission = Pick<Accepted, 'ref'> & Partial<Pick<Accepted,
  'runDefinition' | 'dispatchReserved' | 'physicalStartReserved' | 'preDispatchFailureConfirmed' | 'cancellationRequested'>>;
type Start = (submission: Submission, requested: unknown, accepted: DispatchAdmission,
  held: Held, finished?: () => unknown, gate?: RequestGate) => Promise<DispatchStart>;
type FailureFields = Partial<Record<typeof dispatchFailureFields[number], unknown>>;
type Entry = FailureFields & Parameters<typeof releaseDispatchPreparationHost>[0] & {
  ref: Ref; abort: AbortController; settled: boolean; requestId?: string;
  reserved?: boolean; physicalStarted?: boolean; physicalStartClaimAttempted?: boolean;
  physicalWorkMayHaveStarted?: boolean; computeStartAttempted?: boolean; stopObserved?: boolean;
  stopObservationPending?: boolean; failureObservationPending?: boolean; finishPending?: boolean;
  releasePending?: boolean; unresolvedCleanup?: boolean; borrowedSources?: boolean; publicationCommitted?: boolean;
  promise?: Promise<unknown>; finished?: () => unknown; retirePreparation?: () => void;
  observeStopped?: (outcome: Terminal) => unknown; terminalOutcome?: Terminal;
  cleanupOwner?: Execution; cleanupHandle?: FailureHandle;
  acquisitionLedger?: unknown; pendingSetup?: unknown; sourceCapture?: Readonly<{close(): unknown}> | Capture;
  sampleProfileObservation?: unknown;
  sampleAdoption?: ReturnType<typeof selectedSampleAdoption>;
  debugControl?: ReturnType<NonNullable<ReturnType<typeof installNodeRelationSampleDebugEntry>>>;
  waitingForDebugEntry?: boolean;
  sourceOperationScope?: object;
  sourcePreparations?: Array<Readonly<{source: Adapter; prepared: Prepared;
    retire(prepared: unknown): SynchronousRuntimeData}>>;
  logicalObservation?: ReturnType<typeof prepareInstalledLogicalObservation>;
};
type Failure = Readonly<{cause?: unknown; code?: unknown; message?: unknown;
  cleanupPending?: boolean; cleanupHandle?: FailureHandle}>;
type Step = (name: string, detail: unknown) => unknown;
type JournalPort = Stop['journal'] & CleanupPorts['journal'] & DebugJournal & Pick<Journal,
  'reservePhysicalStart' | 'sourceOperationConfigured' | 'originalSubmittedIntent' | 'lookupDebugResume'>;
type CheckpointPort = NonNullable<Stop['checkpoints']> & NonNullable<CleanupPorts['checkpoints']> & Readonly<{
  heldOrigin(requestId: string): unknown;
  acquisitionAccess(requestId: string, access: SourceAccess | undefined, scope?: unknown): SourceAccess | undefined;
  journal: NonNullable<NonNullable<Stop['checkpoints']>['journal']> & Readonly<{
    inspect(checkpointCid: string | undefined): Readonly<{kind: string; prepareAttemptId: string | null;
      runId: string | null; runDefinitionCid: string | null; checkpointCid: string}> | undefined;
  }>;
}>;
type PhysicalDispatch = Readonly<{preparedProgram: unknown; plan: Plan; store: Options['store'];
  principalId: string; signal: AbortSignal; retainExecution(owner: Execution): void}>;
type InferResult = Readonly<{status: string; checkpoint?: Readonly<{checkpointCid: string}>}>;
type PrepareLedger = (facts: Readonly<{preparedProgram: unknown; plan: Plan; sourceCapacity?: Capacity;
  sourceCapacities?: readonly Capacity[]; direct?: Capacity; acquisition?: unknown;
  capacity?: Capacity & Keyed['capacity']; capturedContent?: boolean}>) => unknown;
type RunInfer = ((facts: PhysicalDispatch & Readonly<{preparationHolder?: unknown;
  acquiredInfer?: unknown; acquiredContent?: unknown; originalPreparation?: unknown;
  submission: Readonly<Record<string, unknown>>}>) => Awaitable<InferResult | undefined>) & {
  prepareKeyedLedger?: PrepareLedger; prepareAcquiredLedger?: PrepareLedger;
  sourceOccurrence?(prepared: unknown, index: number): Occurrence | undefined;
};
type RunContent = ((facts: PhysicalDispatch & Readonly<{acquiredContent?: unknown}>) => Awaitable<unknown>) &
  NonNullable<KeyedPorts['runContent']> & {prepareKeyedLedger?: PrepareLedger; prepareAcquiredLedger?: PrepareLedger;
    prepareOrdinaryAcquiredLedger?: PrepareLedger};
type Control = Parameters<Journal['reservePhysicalStart']>[3] & Stop['control'] & CleanupPorts['control'] &
  Omit<KeyedPorts['control'], 'takeSourceEvidenceOriginal'> & Direct['control'] & Logical[1] &
  Parameters<Journal['lookupDebugResume']>[2] & Parameters<Journal['readRetainedRelationSample']>[3] &
  Pick<PublicationControl, 'reserveClientRelationSampleStart' | 'acknowledgeClientRelationSampleStart'> &
  Readonly<{
    takeSourceEvidenceOriginal(capture: unknown): Readonly<{wire: string; identity: string; name: string}>;
    admitInferCapturedInput: InferAdmission;
  }>;
type Part = KeyedPorts['fragment'];
type Values = KeyedPorts['values'];
type Setup = Parameters<Published>[0];
type Moon = Omit<Parameters<Journal['reservePhysicalStart']>[2], 'clientProgramAcquisitionCount'> &
  Parameters<Journal['originalSubmittedIntent']>[2] & Stop['moon'] & CleanupPorts['moon'] &
  KeyedPorts['moon'] & Direct['moon'] & Logical[0] &
  Parameters<typeof retainDispatchPreparationHost>[1] & Readonly<{
    clientProgramAcquisitionCount(prepared: unknown): number;
    clientProgramMultiCapturedLedgerUsage(ledger: unknown): unknown;
    clientProgramInstalledManagedRequiresAcquisitionResultPublication?(run: unknown, prepared: unknown, request: unknown): unknown;
    clientProgramRequiresAcquisitionResultPublication(prepared: unknown): boolean;
    clientProgramSelectSingleKeyedAcquisition?(prepared: unknown): unknown;
    clientProgramKeyedDirectAcquisitionCoordinates(acquisition: unknown): unknown;
    clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition: unknown): unknown;
    clientProgramInstalledManagedRunPrepareLedger?(run: unknown, prepared: unknown, request: unknown,
      capacities: readonly unknown[], transfer: readonly bigint[], memory: readonly bigint[],
      registry: unknown, values: Values, fragment: Part, ordered: Part): unknown;
    clientProgramInstalledManagedWholeSourceLedger?(run: unknown, prepared: unknown, request: unknown,
      capacity: unknown, transfer: bigint, memory: bigint): unknown;
    clientProgramInstalledManagedWholeSourcesLedger?(run: unknown, prepared: unknown, request: unknown,
      capacities: readonly unknown[], transfer: readonly bigint[], memory: readonly bigint[]): unknown;
    clientProgramPrepareKeyedCapturedLocalInstalledLedger(prepared: unknown, direct: unknown, acquired: unknown,
      capacity: unknown, transfer: readonly bigint[], memory: readonly bigint[], maxBytes: number, maxWork: number,
      registry: unknown, values: Values, fragment: Part, ordered: Part, capturedContent: boolean): unknown;
    clientProgramPrepareMultiCapturedLocalInstalledLedger(prepared: unknown, capacities: readonly unknown[],
      transfer: readonly bigint[], memory: readonly bigint[], registry: unknown, values: Values, fragment: Part, ordered: Part): unknown;
    clientProgramPrepareSingleCapturedLocalInstalledLedger(prepared: unknown, capacity: unknown,
      transfer: bigint, memory: bigint, registry: unknown, values: Values, fragment: Part, ordered: Part): unknown;
    clientProgramOpenInstalledManagedSourceFreeHost?(run: unknown, prepared: unknown, request: unknown,
      registry: unknown, values: Values, fragment: Part, ordered: Part, retained: boolean): unknown;
    clientProgramOpenInstalledManagedCaptureHost?(run: unknown, prepared: unknown, request: unknown, sources: readonly unknown[]): unknown;
    clientProgramOpenMultiCapturedLocalHost(prepared: unknown, sources: readonly unknown[], ledger: unknown,
      registry: unknown, values: Values, fragment: Part, ordered: Part): Setup | undefined;
    clientProgramOpenMultiCapturedLocalRetainedHost: Moon['clientProgramOpenMultiCapturedLocalHost'];
    clientProgramOpenSingleCapturedLocalHost(prepared: unknown, source: unknown, ledger: unknown,
      registry: unknown, values: Values, fragment: Part, ordered: Part, retained: boolean): Setup | undefined;
    clientProgramOpenSourceFreeLocalHost(prepared: unknown, registry: unknown, values: Values,
      slots: bigint, transfer: bigint, retained: bigint, execution: bigint, fragment: Part, ordered: Part): Setup | undefined;
    clientProgramOpenSourceFreeLocalRetainedHost: Moon['clientProgramOpenSourceFreeLocalHost'];
  }>;
type SourceProfile = Parameters<typeof installedSourceFor<Adapter>>[0] & Readonly<{
  modelPreparation?(prepared: unknown, plan: Plan): unknown;
}>;
type Options = Pick<KeyedPorts, 'registry' | 'values' | 'fragment' | 'ordered' | 'namespaceId' | 'authorityScopeCid' | 'storeAuthorityCid' | 'now'> &
  Readonly<{
    moon: Moon; control: Control; journal: JournalPort;
    store: Stop['store'] & Awaited<ReturnType<typeof openLocalPublicationStore>>;
    checkpoints?: CheckpointPort;
    startRun(input: Readonly<{identity: unknown; namespaceId: string; principalId: string; connection: object}>):
      Awaitable<Readonly<{kind: string; ref: Ref; revision?: number}>>;
    hostConnection(input: DispatchAuthority): boolean;
    beforeDispatch?(ref: Ref): unknown; observed?: unknown;
    prepareAcquisition(prepared: unknown, access: SourceAccess | undefined, occurrence?: Occurrence,
      original?: Prepared): Awaitable<Prepared>;
    planFor(submission: Submission, definitionWire: string, requested: unknown): Plan;
    sourceProfile?: SourceProfile; faultInjection?: Step; runInfer?: RunInfer; runContent?: RunContent;
    computeConfigurations?: Readonly<Record<string, unknown>>;
    observation?: AcquisitionPorts['observation'] & CleanupPorts['observation'] & TrackingPorts['observation'] &
      Readonly<{emit(phase: 'compute', event: string, detail: Readonly<{ref: Ref; task?: number}>,
        measurement: Readonly<{durationMs: number | undefined}>): void;
        emit(phase: 'source', event: 'acquisition_interval', detail: Readonly<{ref: Ref; task: number;
          outcome: 'confirmed' | 'failed'}>, measurement: Readonly<{segment: 'source-acquisition'; durationMs: number}>): void}>;
    preparationCustody?: Readonly<{begin(submission: Submission): Readonly<{
      preparedProgram: unknown; retire(): void;
    }> | undefined}>;
    beforePublication?(prepared: unknown): SynchronousRuntimeData;
    authorizeLogicalObservation?(operation: Parameters<Parameters<NonNullable<Entry['logicalObservation']>['attach']>[3]>[0],
      connection: object): boolean;
    authorizeSampleCapture?(authority: DispatchAuthority): unknown;
    prepareSampleStart?: ReturnType<typeof installNodeRelationSampleStart>;
    prepareDebugEntryResume?: ReturnType<typeof installNodeRelationSampleDebugEntry>;
    managedComputeRequired?: boolean; retainedRelationOutput?: boolean; runPublished?: Published;
  }>;

// Diagnostics must not become a second owner of execution/cleanup capabilities.
// Read only inert own data, including one existing primaryFailure diagnostic
// slot. Accessors and error/cause chains are not invoked or traversed, and the
// returned receipt retains no thrown object or cleanup capability.
const dispatchFailureFields = Object.freeze(['primaryFailure', 'closeFailure',
  'cleanupFailure', 'finishFailure', 'releaseFailure', 'preparationRetirementFailure'] as const);


// This message extends the existing failed Run observation, not its status,
// authority or cleanup evidence. Never format arbitrary exception text.


// Only diagnostic custody moves here. An Unknown result keeps its outcome,
// physical owner and current gates; a later cleanup refusal is not its cause.
function retainDispatchPrimaryFailure(entry: Pick<Entry, 'primaryFailure'>, result: unknown) {
  try {
    const primary = Object.getOwnPropertyDescriptor(result as object, 'primaryFailure');
    if (!Object.hasOwn(entry, 'primaryFailure') &&
        primary !== undefined && Object.hasOwn(primary, 'value')) {
      entry.primaryFailure = primary.value;
    }
  } catch { /* Optional failure DATA cannot interrupt the original cleanup. */ }
}

function invalidSampleStartReceiver(value: unknown, code = 'InvalidClientRunSampleStartReceiver'): never {
  if (typeof (value as {then?: unknown} | null | undefined)?.then === 'function') {
    void Promise.resolve(value).catch(() => {});
  }
  throw new TypeError(code);
}

// The installed Host owns the Account and Core port. A selected profile may
// prepare its controller, then cross the acknowledged start boundary once.
export function installNodeRelationSampleStart(moon: SampleStartMoon, observeAccount: () => unknown,
  hostConnection: Options['hostConnection'], site: string) {
  const advance = moon.clientProgramAdvanceRelationSampleStartControl;
  if (typeof advance !== 'function') return undefined;
  return (setup: unknown, owner: unknown, profile: unknown, authority: DispatchAuthority) => {
    const observe = () => {
      if (hostConnection(authority) !== true) throw new Error('ClientRunSampleStartAuthorityLost');
      return observeAccount();
    };
    const original = observe();
    const assertCurrent = () => {
      if (observe() !== original) throw new Error('ClientRunSampleStartAuthorityLost');
    };
    checked(advance.call(moon, profile, owner, setup, original, authority.principalId, site, false));
    assertCurrent();
    let pending = true;
    return () => {
      if (!pending) throw new Error('ClientRunSampleStartOriginalUnavailable');
      pending = false;
      assertCurrent();
      checked(advance.call(moon, profile, owner, setup, original, authority.principalId, site, true));
      assertCurrent();
    };
  };
}

// A drain interrupts the local wait, independently of cancellation or failure.
class DebugPauseHostClosing extends Error {
  readonly code = 'ClientRunDebugEntryHostClosing';

  constructor() {
    super('ClientRunDebugEntryHostClosing');
  }
}

// The installed entry reads its actual Core phase after the shared start ACK.
// Closing this port releases the borrowed aliases and its outstanding wait.
export function installNodeRelationSampleDebugEntry(moon: DebugMoon, observeAccount: () => unknown,
  hostConnection: Options['hostConnection'], site: string,
  {journal, control, now}: Readonly<{journal: DebugJournal | undefined; control: DebugControl; now(): string}>) {
  const advance = moon.clientProgramAdvanceRelationSampleDebugEntry;
  const runnable = moon.clientProgramRelationSampleDebugEntryRunnable;
  const entryStep = moon.clientProgramRelationSampleDebugEntryStep;
  const pause = moon.clientProgramRelationSampleDebugTaskPause;
  const nextInput = moon.clientProgramRelationSampleDebugNextInput;
  const resume = moon.clientProgramResumeRelationSampleDebugTask;
  const resumeAllowed = moon.clientProgramRelationSampleDebugResumeAllowed;
  if (typeof advance !== 'function' || typeof runnable !== 'function' ||
      typeof pause !== 'function' || typeof resume !== 'function' || typeof resumeAllowed !== 'function' ||
      typeof journal?.parkDebugTask !== 'function' || typeof journal.acceptDebugTaskResume !== 'function' ||
      typeof journal.debugPauseCurrent !== 'function') {
    return undefined;
  }
  return (setup: unknown, owner: unknown, authority: DispatchAuthority, profile?: unknown,
    signal?: AbortSignal, logicalMapCid?: string, runDefinition?: DebugDefinition) => {
    if (profile === undefined || signal === undefined || hostConnection(authority) !== true) {
      throw new Error('ClientRunDebugEntryOriginalUnavailable');
    }
    const account = observeAccount();
    let live: DebugLive | undefined = {setup, owner, authority, account, profile, signal, logicalMapCid, runDefinition,
      startRevision: 0, revision: 0};
    let waiting: DebugWait | undefined;
    let activated = false, resuming = false, hostClosing = false;
    const current = () => {
      const original = live;
      return original !== undefined && !original.signal.aborted &&
        hostConnection(original.authority) === true && observeAccount() === original.account &&
        live === original && !original.signal.aborted && hostConnection(original.authority) === true &&
        live === original && !original.signal.aborted;
    };
    const requireCurrent = (original: DebugLive) => {
      if (!current() || live !== original) throw new Error('ClientRunDebugEntryDenied');
    };
    const call = (original: DebugLive, command: DebugCommand, revision: number) => {
      requireCurrent(original);
      checked(advance.call(moon, original.profile, original.owner, original.setup, original.account,
        original.authority.principalId, site, command, revision));
      requireCurrent(original);
    };
    const phase = (actual: unknown) => {
      const original = live;
      if (original === undefined || actual !== original.setup || original.startRevision === 0) {
        throw new Error('ClientRunDebugEntryOriginalUnavailable');
      }
      requireCurrent(original);
      const ready = checked(runnable.call(moon, original.profile, original.owner, original.setup, original.startRevision));
      requireCurrent(original);
      if (typeof ready !== 'boolean') throw new TypeError('InvalidInstalledTaskController');
      return ready ? 'runnable' : 'paused';
    };
    function stopWaiting(wait: DebugWait, failure?: unknown, handoff?: string) {
      if (waiting !== wait) return;
      waiting = undefined;
      wait.listener[Symbol.dispose]();
      clearTimeout(wait.timer);
      if (failure === undefined) wait.resolve(handoff);
      else wait.reject(failure);
    }
    function expireWaiting(wait: DebugWait) {
      if (waiting !== wait) return;
      const left = wait.parked.expiresAt - Date.parse(now());
      if (!Number.isFinite(left) || left <= 0) {
        stopWaiting(wait, new Error('ClientRunDebugEntryExpired'));
      } else {
        wait.timer = setTimeout(expireWaiting, Math.min(left, 2147483647), wait);
      }
    }
    function holdPause(parked: DebugPark, signal: AbortSignal) {
      if (!Number.isSafeInteger(parked.pausedAt) || parked.pausedAt < 0 || parked.pausedAt >= parked.expiresAt) {
        throw new Error('ClientRunDebugEntryOriginalUnavailable');
      }
      if (hostClosing) throw new DebugPauseHostClosing();
      return new Promise<string | undefined>((resolve, reject) => {
        const wait: DebugWait = {parked, resolve, reject,
          listener: addAbortListener(signal, () => stopWaiting(wait, signal.reason))};
        waiting = wait;
        try {expireWaiting(wait);}
        catch (cause) {stopWaiting(wait, cause);}
      });
    }
    const projectEntryStep = (original: DebugLive) => {
      if (typeof entryStep !== 'function' || original.logicalMapCid === undefined) return undefined;
      const stepId = entryStep.call(moon, original.profile, original.owner, original.setup);
      return typeof stepId !== 'string' || stepId === '' ? undefined :
        Object.freeze({stepId, logicalMapCid: original.logicalMapCid});
    };
    call(live, 'prepare', 0);
    return Object.freeze({
      current,
      activate(witness: Pick<DebugStartWitness, 'physicalStartRevision' | 'until'> | undefined) {
        const original = live;
        const revision = witness?.physicalStartRevision;
        const command = witness?.until;
        if (activated || original === undefined || revision === undefined || !Number.isInteger(revision) ||
            revision < 1 || revision > 2147483647 || (command !== 'step' && command !== 'terminal')) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        activated = true;
        call(original, command, revision);
        original.startRevision = original.revision = revision;
      },
      parkEntry(identity: unknown, expectedRevision: number, expiresAt: number) {
        const original = live;
        if (original === undefined || activated || waiting !== undefined ||
            typeof journal.parkDebugEntry !== 'function' || typeof journal.acceptDebugEntryResume !== 'function') {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        requireCurrent(original);
        const projectedStep = projectEntryStep(original);
        requireCurrent(original);
        const parked = journal.parkDebugEntry(identity, {
          ref: original.authority.ref, expectedRevision, expiresAt, current,
          ...(projectedStep === undefined ? {} : {entryStep: projectedStep}),
        }, moon, control);
        requireCurrent(original);
        if (parked?.kind === 'expired') throw new Error('ClientRunDebugEntryExpired');
        if (parked?.kind !== 'parked' || parked.revision !== expectedRevision + 1 || parked.expiresAt !== expiresAt) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        return holdPause(projectedStep === undefined ? parked : {...parked, entryStep: projectedStep}, original.signal);
      },
      reopenEntry(parked: RetainedDebugEntry['park'], currentOriginal: RetainedDebugEntry['assertCurrent']) {
        const original = live;
        if (original === undefined || activated || waiting !== undefined || !current() ||
            currentOriginal() !== true || !journal.debugPauseCurrent(original.authority.ref,
              {parked, startRevision: 0, current}) || !current()) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        const projected = projectEntryStep(original);
        if (parked.entryStep === undefined || projected?.stepId !== parked.entryStep.stepId ||
            projected.logicalMapCid !== parked.entryStep.logicalMapCid ||
            currentOriginal() !== true || !current() || waiting !== undefined) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        return holdPause(parked, original.signal);
      },
      observePause(authorize: DebugActor['authorize'], inspect = false,
        authorizeResume?: DebugActor['authorize']) {
        const original = live, wait = waiting;
        if (original === undefined || wait === undefined) return undefined;
        const local = () => waiting === wait && !hostClosing && !resuming && !wait.unresolved;
        const allowed = () => local() && current() && authorize() === true && current() && local();
        if (!allowed() ||
            !journal.debugPauseCurrent(original.authority.ref, {
              parked: wait.parked, startRevision: original.startRevision, current: allowed, requireEntryDeadline: inspect,
            }) || !local()) return undefined;
        const nextStepId = wait.parked.controlRevision === undefined ?
          wait.parked.entryStep?.stepId : wait.parked.nextStepId;
        const resumeAvailable = authorizeResume === undefined ? undefined :
          authorizeResume() === true && allowed() && resumeAllowed.call(moon, original.profile,
            original.owner, original.setup, original.account, original.authority.principalId, site) === true && allowed();
        if (!allowed()) return undefined;
        return Object.freeze({revision: wait.parked.revision,
          ...(wait.parked.controlRevision === undefined ? {} : {completedStepId: wait.parked.stepId,
            committedGeneration: wait.parked.committedGeneration}),
          ...(nextStepId == null ? {} : {nextStepId}),
          ...(resumeAvailable === undefined ? {} : {resumeAvailable}),
          ...(inspect ? {logicalMapCid: original.logicalMapCid, startRevision: original.startRevision,
            controlRevision: wait.parked.controlRevision, runRef: original.authority.ref,
            ttlPolicy: 'original_debug_entry_deadline'} : {}),
          expiresAt: wait.parked.expiresAt, pausedAt: wait.parked.pausedAt});
      },
      readNextSample(selected: Parameters<NextSampleRead>[1], authorize: DebugActor['authorize'],
        reserve: Parameters<NextSampleRead>[3], bindProducer: Parameters<NextSampleRead>[4]) {
        const original = live, wait = waiting;
        const local = () => wait !== undefined && waiting === wait && !hostClosing && !resuming && !wait.unresolved;
        const denied = () => {throw Object.assign(new Error('ClientRelationSampleDenied'), {code: 'ClientRelationSampleDenied'});};
        const stale = (): never => {throw Object.assign(new Error('ClientRunDebugEntryRevisionConflict'),
          {code: 'ClientRunDebugEntryRevisionConflict'});};
        const allowed = () => local() && live === original && current() && authorize() === true && current() && local();
        if (typeof nextInput !== 'function' || typeof journal.readRetainedRelationSample !== 'function' ||
            typeof reserve !== 'function' || typeof bindProducer !== 'function' || !Object.isFrozen(selected)) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        if (original === undefined || wait?.parked.controlRevision === undefined || !local() ||
            selected.revision !== wait.parked.revision || selected.nextStepId !== wait.parked.nextStepId) return stale();
        if (!allowed()) denied();
        // The fixed Read covers the bridge call, checked edge/port probes
        // and the borrowed producer tuple. It holds no Run payload or pin.
        const quote: unknown = reserve(2048);
        if (quote !== undefined) {
          if (typeof (quote as {then?: unknown} | null)?.then === 'function') void Promise.resolve(quote).catch(() => {});
          throw Object.assign(new Error('ClientRelationSampleCapacity'), {code: 'ClientRelationSampleCapacity'});
        }
        if (!local()) stale();
        if (!allowed()) denied();
        const result = nextInput.call(moon, original.profile, original.owner, original.setup,
          original.startRevision, wait.parked.controlRevision, wait.parked.committedGeneration,
          selected.nextStepId, selected.inputOrdinal, selected.maxWork);
        if (!allowed()) denied();
        if (runtimeIsError(result)) {
          const issue = runtimeField(result, 0);
          if (issue === 'stale') stale();
          if (issue === 'capacity' || issue === 'foreign') {
            const code = issue === 'capacity' ? 'ClientRelationSampleCapacity' : 'ForeignClientRunSampleOutput';
            throw Object.assign(new Error(code), {code});
          }
        }
        const selectedProducer = checked(result);
        if (selectedProducer === undefined) return Object.freeze({kind: 'unobserved'});
        const stepId = runtimeField(selectedProducer, 0), outputPortId = runtimeField(selectedProducer, 1),
          carrierContractCid = runtimeField(selectedProducer, 2), generation = runtimeField(selectedProducer, 3),
          attemptSequence = runtimeField(selectedProducer, 4);
        if (typeof stepId !== 'string' || typeof outputPortId !== 'string' || typeof carrierContractCid !== 'string' ||
            typeof generation !== 'number' || typeof attemptSequence !== 'number') {
          throw Object.assign(new Error('ForeignClientRunSampleOutput'), {code: 'ForeignClientRunSampleOutput'});
        }
        const producer = Object.freeze({stepId, outputPortId, carrierContractCid, generation, attemptSequence});
        const bound: unknown = bindProducer(producer);
        if (bound !== true) {
          if (typeof (bound as {then?: unknown} | null | undefined)?.then === 'function') void Promise.resolve(bound).catch(() => {});
          throw Object.assign(new Error('ForeignClientRunSampleOutput'), {code: 'ForeignClientRunSampleOutput'});
        }
        if (!local()) stale();
        if (!allowed()) denied();
        return journal.readRetainedRelationSample(original.authority.ref, Object.freeze({
          compiledPlanCid: selected.compiledPlanCid, logicalMapCid: selected.logicalMapCid,
          stepId: producer.stepId, outputPortId: producer.outputPortId, carrierContractCid: producer.carrierContractCid,
          nextStepId: selected.nextStepId, maxBytes: selected.maxBytes,
        }), {current: allowed, reserve, debugPause: {parked: wait.parked,
          startRevision: original.startRevision, producer}}, control);
      },
      resumeTask(commandWire: string, authorize: DebugActor['authorize'], reserve?: DebugResumeActor['reserve']) {
        const original = live, wait = waiting;
        if (original === undefined || wait === undefined || hostClosing || resuming) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        const reconciliationRequired = () => Object.assign(new Error('ClientRunDebugEntryReconciliationRequired'),
          {code: 'ClientRunDebugEntryReconciliationRequired'});
        resuming = true;
        const allowed = () => waiting === wait && !hostClosing && current() && authorize() === true &&
          current() && !hostClosing && waiting === wait;
        try {
          if (!allowed() || resumeAllowed.call(moon, original.profile, original.owner, original.setup,
            original.account, original.authority.principalId, site) !== true || !allowed()) {
            throw Object.assign(new Error('ClientRunDebugEntryDenied'), {code: 'ClientRunDebugEntryDenied'});
          }
          if (wait.unresolved) throw reconciliationRequired();
          const {runDefinition, logicalMapCid} = original;
          let receiptOriginal: Parameters<Journal['acceptDebugTaskResume']>[1]['receiptOriginal'];
          if (reserve !== undefined) {
            if (runDefinition === undefined || logicalMapCid === undefined) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
            receiptOriginal = {runDefinition, logicalMapCid, reserve};
          }
          let result;
          if (wait.parked.controlRevision === undefined) {
            result = journal.acceptDebugEntryResume(original.authority.ref, {commandWire, current: allowed, receiptOriginal,
              capture(witness) {
                try {
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  if (witness?.kind !== 'resume_accepted' || witness.revision !== wait.parked.revision + 1 ||
                      typeof witness.commandCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(witness.commandCid) ||
                      (witness.until !== 'step' && witness.until !== 'terminal')) {
                    throw new Error('ClientRunDebugEntryOriginalUnavailable');
                  }
                  stopWaiting(wait, undefined, witness.commandCid);
                } catch (cause) {
                  stopWaiting(wait, cause);
                  // The funded caller's receipt records the committed
                  // acceptance. The original Driver receives this failure.
                  if (receiptOriginal === undefined) throw cause;
                }
              },
            }, control);
          } else {
            result = journal.acceptDebugTaskResume(original.authority.ref, {
              commandWire, startRevision: original.startRevision, stepId: wait.parked.stepId, nextStepId: wait.parked.nextStepId,
              committedGeneration: wait.parked.committedGeneration,
              current: allowed, receiptOriginal, capture(witness) {
                try {
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  if (witness?.kind !== 'resume_accepted' || witness.revision !== wait.parked.revision + 1 ||
                      witness.controlRevision !== wait.parked.controlRevision || witness.stepId !== wait.parked.stepId ||
                      witness.nextStepId !== wait.parked.nextStepId ||
                      witness.committedGeneration !== wait.parked.committedGeneration ||
                      (witness.until !== 'step' && witness.until !== 'terminal')) {
                    throw new Error('ClientRunDebugEntryOriginalUnavailable');
                  }
                  checked(resume.call(moon, original.profile, original.owner, original.setup, original.account,
                    original.authority.principalId, site, original.startRevision,
                    witness.controlRevision, witness.stepId, witness.nextStepId ?? '', witness.committedGeneration,
                    witness.until === 'step'));
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  original.revision = witness.revision;
                  stopWaiting(wait);
                } catch (cause) {
                  stopWaiting(wait, cause);
                  // The funded caller's receipt records the committed
                  // acceptance. The original Driver receives this failure.
                  if (receiptOriginal === undefined) throw cause;
                }
              },
            }, control);
          }
          // An exact retry can read the receipt, but cannot take the live handoff.
          if (waiting === wait && result?.kind === 'resume_accepted') {
            wait.unresolved = true;
            throw reconciliationRequired();
          }
          return result;
        } catch (cause) {
          // A lost reply may have consumed this durable pause. Keep the
          // original wait for cancellation/expiry and allow receipt lookup.
          // Known refusals leave any still-current pause usable.
          if ((cause as {outcome?: unknown} | null | undefined)?.outcome === 'unknown' && waiting === wait) wait.unresolved = true;
          throw cause;
        } finally {resuming = false;}
      },
      taskControl: Object.freeze({
        phase,
        waitForResume(actual: unknown, waitSignal: AbortSignal) {
          const original = live;
          if (original === undefined || waitSignal !== original.signal || waiting !== undefined || phase(actual) !== 'paused') {
            throw new Error('ClientRunDebugEntryOriginalUnavailable');
          }
          const boundary = checked(pause.call(moon, original.profile, original.owner, original.setup, original.startRevision));
          requireCurrent(original);
          const controlRevision = runtimeField(boundary, 0), stepId = runtimeField(boundary, 1),
            nextOriginal = runtimeField(boundary, 2), committedGeneration = runtimeField(boundary, 3);
          if (typeof controlRevision !== 'number' || typeof stepId !== 'string' || typeof nextOriginal !== 'string' ||
              typeof committedGeneration !== 'number') throw new Error('ClientRunDebugEntryOriginalUnavailable');
          const nextStepId = nextOriginal === '' ? null : nextOriginal;
          const parked = journal.parkDebugTask(original.authority.ref, {
            startRevision: original.startRevision, expectedRevision: original.revision, controlRevision, stepId,
            nextStepId, committedGeneration, current,
          }, control);
          requireCurrent(original);
          if (parked?.kind === 'expired') throw new Error('ClientRunDebugEntryExpired');
          if (parked?.kind !== 'parked' || parked.revision !== original.revision + 1 ||
              parked.controlRevision !== controlRevision || parked.stepId !== stepId || parked.nextStepId !== nextStepId ||
              parked.committedGeneration !== committedGeneration || !Number.isSafeInteger(parked.expiresAt)) {
            throw new Error('ClientRunDebugEntryOriginalUnavailable');
          }
          return holdPause(parked, waitSignal);
        },
      }),
      beginDrain() {
        hostClosing = true;
        if (waiting !== undefined) stopWaiting(waiting,
          new DebugPauseHostClosing());
      },
      close() {
        live = undefined;
        if (waiting !== undefined) stopWaiting(waiting, new Error('ClientRunDebugEntryOriginalUnavailable'));
      },
    });
  };
}

// The existing dispatch entry owns the Journal writer until cleanup. A
// prepared Driver only receives a synchronous port to the checked prefix.
function selectedSampleAdoption(entry: Entry | undefined, visit: SampleProfile['withAdoption'] | undefined,
  hostConnection: Options['hostConnection'], authority: DispatchAuthority | undefined,
  authorizeSampleCapture: NonNullable<Options['authorizeSampleCapture']>, owner: object | undefined,
  profile: object | undefined) {
  let writer: SampleWriter | undefined;
  let armed = false;
  const unavailable = (): never => {throw new Error('ClientRunSampleStartOriginalUnavailable');};
  const active = () => armed && entry !== undefined && entry.computeStartAttempted === true &&
    !entry.abort.signal.aborted;
  const driver: RelationSampleDriver = Object.freeze({
    get owner() {return owner;},
    get profile() {return profile;},
    maxWireBytes: localContractLimits.maxWireBytes,
    maxNodes: localContractLimits.maxNodes,
    maxDepth: localContractLimits.maxDepth,
    current() {
      const originalAuthority = authority;
      if (originalAuthority === undefined || !active() ||
          hostConnection(originalAuthority) !== true || !active()) return false;
      const outcome = authorizeSampleCapture(originalAuthority);
      if (typeof (outcome as {then?: unknown} | null | undefined)?.then === 'function') {
        void Promise.resolve(outcome).catch(() => {});
      }
      return outcome === true && active() && hostConnection(originalAuthority) === true && active();
    },
    adopt(prefix: object) {scope.adopt(prefix);},
  });
  const scope = {
    driver,
    captureAdoption(original: SampleWriter) {
      if (entry === undefined || writer !== undefined || typeof original !== 'function') unavailable();
      writer = original;
    },
    requireWriter() {
      if (typeof writer !== 'function' || entry === undefined) unavailable();
    },
    arm() {armed = true;},
    adopt(prefix: object) {
      const current = driver.current;
      if (!current()) unavailable();
      let receipt: ReturnType<SampleWriter>;
      const write = writer;
      if (visit === undefined || write === undefined) return unavailable();
      visit(prefix, current, ticket => {receipt = write(ticket);});
      if (!current() || receipt === undefined) unavailable();
      return receipt;
    },
    close() {
      armed = false;
      writer = visit = authority = entry = undefined;
      owner = profile = undefined;
    },
  };
  return scope;
}

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
  faultInjection, runInfer, runContent, computeConfigurations = {},
  observation, preparationCustody, beforePublication, authorizeLogicalObservation, authorizeSampleCapture, prepareSampleStart,
  prepareDebugEntryResume,
  managedComputeRequired = false,
  retainedRelationOutput = false,
  runPublished = runPublishedCapturedStrategy}: Options) {
  const entries = new Map<string, Entry>();
  let draining = false;
  const capturedRun = moon?.strategyHostRun;
  const diagnostic = diagnosticObserver(observed);
  const diagnosticErrorType = Error;
  const diagnosticStackFormatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace')?.value;
  const step = async (name: string, detail: Parameters<typeof diagnostic>[1]) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };
  const keyOf = (ref: Ref) => ref.runDefinitionCid;
  const current = (ref: Ref) => entries.get(keyOf(ref));
  const resourceUsage = (ledger: unknown) => {
    const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    return ledgerUsageDiagnostic(usage);
  };
  const cancel = (ref: Ref) => current(ref)?.abort.abort(
    new Error('ClientRunCancellationRequested'));
  const live = (ref: Ref) => current(ref)?.settled === false;

  function controlledDebugTask<Result>(ref: Ref, {principalId, connection, authorize}: DebugActor,
    consume: (owner: NonNullable<Entry['debugControl']>, allowed: DebugActor['authorize']) => Result) {
    const entry = current(ref);
    const original = entry?.debugControl;
    const authority = {principalId, connection, ref};
    if (entry === undefined || entry.ref.namespaceId !== ref.namespaceId ||
        entry.ref.authorityScopeCid !== ref.authorityScopeCid || original === undefined ||
        typeof authorize !== 'function') throw new Error('ClientRunDebugEntryOriginalUnavailable');
    const allowed = () => entry.debugControl === original &&
      hostConnection(authority) === true && authorize() === true &&
      entry.debugControl === original && hostConnection(authority) === true;
    return consume(original, allowed);
  }
  const observeDebugTask = (ref: Ref, actor: DebugActor) => controlledDebugTask(ref, actor,
    (owner, allowed) => owner.observePause(allowed));
  const observeDebugInspect = (ref: Ref, actor: DebugActor, authorizeResume?: DebugActor['authorize']) => {
    if (current(ref)?.debugControl === undefined) return undefined;
    const observed = controlledDebugTask(ref, actor, (owner, allowed) => owner.observePause(allowed, true, authorizeResume));
    return observed?.runRef === undefined ? undefined : observed as typeof observed & {runRef: Ref};
  };
  const readDebugNextSample = (ref: Ref, actor: DebugActor, selected: Parameters<NextSampleRead>[1],
    reserve: Parameters<NextSampleRead>[3], bindProducer: Parameters<NextSampleRead>[4]) => controlledDebugTask(ref, actor,
    (owner, allowed) => owner.readNextSample(selected, allowed, reserve, bindProducer));
  const resumeDebugTask = (ref: Ref, actor: DebugResumeActor, commandWire: string) => {
    if (typeof actor.reserve !== 'function' || current(ref)?.debugControl === undefined) {
      throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
    }
    return controlledDebugTask(ref, actor, (owner, allowed) => owner.resumeTask(commandWire, allowed, actor.reserve));
  };
  const lookupDebugResume = ({run_ref: ref, operation_id: operationId, command_cid: commandCid,
    accepted_from_revision: acceptedFromRevision}: WireControlOperationRef,
    {principalId, connection, authorize, reserve, reserveConstruction}: DebugActor &
      Pick<DebugReadScope, 'reserve' | 'reserveConstruction'>) => {
    const authority = {principalId, connection, ref};
    if (typeof authorize !== 'function') throw new Error('ClientRunDebugEntryDenied');
    const current = () => hostConnection(authority) === true &&
      authorize() === true && hostConnection(authority) === true;
    return journal.lookupDebugResume(ref, {operationId, commandCid, acceptedFromRevision, current, reserve, reserveConstruction}, control);
  };
  const operation = (ref: Ref) => current(ref)?.promise;
  const credentialRefusalPending = (ref: Ref) => {
    const entry = current(ref);
    return entry?.requestId !== undefined && entry.settled &&
      entry.ref.namespaceId === ref.namespaceId && entry.ref.authorityScopeCid === ref.authorityScopeCid &&
      !entry.stopObserved && isModelCredentialRefusal(entry.primaryFailure);
  };
  const failureMessage = (ref: Ref) => {
    const entry = current(ref);
    return entry === undefined ? undefined : publicBudgetFailureMessage(
      entry.primaryFailure, control?.executionFailureExplanation);
  };

  const acquireSource = createClientDispatchSourceAcquisition({
    sourceProfile, now, step, observation, registry, values, fragment, ordered, store,
    journal, retainedRelationOutput, authorityScopeCid, control,
  });

  const acquireKeyedSources = createClientDispatchKeyedAcquisition({
    moon, control, runContent, store, registry, values, fragment, ordered,
    step, resourceUsage, now, authorityScopeCid, namespaceId, storeAuthorityCid, retainedRelationOutput,
  });

  async function observeStop(entry: Entry) {
    if (entry.terminalOutcome === 'cancelled' &&
        !await confirmNodeRunCancellation({ref: entry.ref, journal, store,
          checkpoints, moon, control, cleanupConfirmed: true, physicalStopConfirmed: true})) {
      entry.terminalOutcome = null;
    }
    if (entry.observeStopped !== undefined) {
      // An Effect continuation may stop its in-process Compute while its Run
      // waits for approval. Only that common Run owner can publish the
      // observed outcome; absence of a public index does not imply failure.
      await entry.observeStopped(entry.terminalOutcome ?? null);
      entry.stopObservationPending = false;
      entry.stopObserved = true;
      return;
    }
    const primary = entry.primaryFailure instanceof CapturedRunPublicationError
      ? entry.primaryFailure.primaryFailure : entry.primaryFailure;
    await observeNodeRunStop({ref: entry.ref, journal, store, checkpoints,
      moon, control, cleanupConfirmed: true, physicalStopConfirmed: true},
    {failureObserved: !entry.abort.signal.aborted && !(primary instanceof DebugPauseHostClosing)});
    entry.stopObservationPending = false;
    entry.stopObserved = true;
  }

  const {retire, settleCleanup, finishRun, releaseAcquisition, settleRetainedEntry} = createClientDispatchCleanup({
    entries, keyOf, moon, journal, control, now, checkpoints, observation, observeStop: observeStop as CleanupPorts['observeStop'],
    resourceUsage, diagnostic,
  });
  function checkSampleProfile(entry: Entry, requested: unknown, ref: Ref, run: object,
    execution: Parameters<Control['reserveClientRelationSampleStart']>[2], definition: DebugDefinition,
    setup: Setup, profile: string) {
    const cleanup = moon.clientProgramLogicalObservationCleanup;
    if (typeof cleanup !== 'function') throw new Error('ClientRunSampleStartOriginalUnavailable');
    const result = control.prepareClientLogicalObservation(run, execution,
      definition, localContractLimits);
    try {
      entry.sampleProfileObservation = checked(result);
    } catch (error) {
      entry.sampleProfileObservation = cleanup.call(moon, result);
      throw error;
    }
    const original = journal.originalSubmittedIntent(requested,
      {namespaceId, sampleRunRef: ref, reserveSampleRead(bytes, previousBytes) {
        control.reserveClientRelationSampleStart(run, requested, execution, definition, setup,
          bytes, false, previousBytes);
        entry.abort.signal.throwIfAborted();
      }}, moon, control);
    if (typeof original?.checkSampleProfile !== 'function') {
      throw new Error('ClientRunSampleStartOriginalUnavailable');
    }
    const profileCheck = original.checkSampleProfile(run, definition,
      entry.sampleProfileObservation, profile, localContractLimits);
    if (profileCheck?.profile === null || typeof profileCheck?.profile !== 'object' ||
        profileCheck.startTicket === null || typeof profileCheck.startTicket !== 'object' ||
        typeof profileCheck.withAdoption !== 'function' ||
        typeof (profileCheck as {then?: unknown}).then === 'function') invalidSampleStartReceiver(profileCheck);
    return profileCheck as SampleProfile & {profile: object};
  }


  const start: Start = (submission: Submission | undefined, requested: unknown, accepted: DispatchAdmission | undefined,
    held: Held | undefined, finished?: () => unknown, gate?: RequestGate) => {
    const {principalId: actual, connection} = submission!;
    const unstarted = accepted!.dispatchReserved !== true ||
      accepted!.physicalStartReserved === false &&
      !accepted!.preDispatchFailureConfirmed;
    if (entries.has(keyOf(accepted!.ref)) || !unstarted ||
        accepted!.cancellationRequested) {
      return Promise.resolve('not_started');
    }
    // Held requests can start only from the Checkpoint's admitted resume.
    if (gate === undefined && checkpoints?.heldOrigin(submission!.requestId)) {
      return Promise.resolve('not_started');
    }
    let debugResumeCid = held!.debugResumeCid;
    const debugEntryExpiresAt = held!.debugEntryExpiresAt;
    let retainedDebugEntry = held!.retainedDebugEntry;
    delete held!.retainedDebugEntry;
    const parkDebugEntry = debugEntryExpiresAt !== undefined;
    const resumesDebug = parkDebugEntry || debugResumeCid !== undefined;
    let preparationLease = preparationCustody?.begin(submission!);
    let preparedProgram = preparationLease === undefined
      ? submission!.preparedProgram : preparationLease.preparedProgram;
    let reached!: (outcome: DispatchStart) => void;
    const physical = new Promise<DispatchStart>(resolve => { reached = resolve; });
    const entry: Entry = {ref: accepted!.ref, requestId: submission!.requestId,
      finished, promise: undefined,
      reserved: false, settled: false, abort: new AbortController(),
      physicalStarted: false, physicalStartClaimAttempted: false,
      computeStartAttempted: false,
      failureObservationPending: false, stopObservationPending: false,
      stopObserved: false, physicalWorkMayHaveStarted: false,
      finishPending: false, releasePending: checkpoints !== undefined,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, sourceCapture: undefined};
    if (preparationLease !== undefined) {
      entry.retirePreparation = () => {
        // A settled Run is not an observation-delivery ACK. The same original
        // Request stays owned while any queue/callback still holds its loan.
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.close();
          entry.logicalObservation = undefined;
        }
        // The complete retirement predicate has settled callbacks, physical
        // custody and acquisition release. No later drain needs these raw
        // aliases; discard them before the private owner returns its charge.
        preparedProgram = undefined;
        if (held !== undefined) held!.plan = undefined;
        submission = requested = accepted = held = finished = gate = undefined;
        entry.finished = undefined;
        entry.observeStopped = undefined;
        for (const field of dispatchFailureFields) {
          entry[field] = dispatchFailureSnapshot(entry[field]);
        }
        releaseDispatchPreparationHost(entry);
        preparationLease!.retire();
        preparationLease = undefined;
      };
    }
    entries.set(keyOf(accepted!.ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      // Request preparation can already own unentered Source reads. Keep
      // their original retirement ports before a start or authorization
      // refusal; started captures still complete their physical cleanup first.
      const preparedSources = held!.preparedSources ?? (held!.preparedSource === undefined ? [] : [{
        adapter: installedSourceFor(sourceProfile, held!.preparedSource!.checkedSource.sourceRef),
        prepared: held!.preparedSource,
      }]);
      for (const source of preparedSources) {
        const retire = source.adapter.retirePreparedSource;
        if (retire === undefined) continue;
        if (typeof retire !== 'function') throw new TypeError('InstalledSourceCleanupUnavailable');
        entry.sourcePreparations ??= [];
        entry.sourcePreparations.push({source: source.adapter, prepared: source.prepared, retire});
      }
      const claim = await startRun({identity: requested, namespaceId,
        principalId: actual, connection});
      if (claim.kind !== 'reserved' &&
          !(claim.kind === 'reconcile' &&
            accepted!.dispatchReserved === true &&
            accepted!.physicalStartReserved === false &&
            !accepted!.preDispatchFailureConfirmed)) return;
      entry.reserved = true;
      await step('dispatch_reserved', {ref: claim.ref});
      if (beforeDispatch !== undefined) await beforeDispatch(claim.ref);
      if (entry.abort.signal.aborted) return;
      if (held!.plan === undefined) {
        held!.plan = planFor(submission!, accepted!.runDefinition!.wire, requested);
      }
      const acquiring = sourceProfile !== undefined &&
        moon.clientProgramAcquisitionCount(preparedProgram) > 0;
      const inferring = held!.plan!.kind === 'infer';
      const serializing = held!.plan!.kind === 'serialization';
      const generatingContent = held!.plan!.serializationGraph !== undefined;
      const ordinaryContent = serializing && acquiring && held!.managedRun !== undefined;
      // Managed Compute publication cannot publish an acquisition Result.
      // Inspect the common checked graph before reserving physical custody or
      // capturing rows. Content and Infer have their own publication owners.
      if (!inferring && !serializing && !generatingContent) {
        if (held!.managedRun !== undefined &&
            typeof moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication !== 'function') {
          throw new TypeError('InstalledManagedSourcePlanUnavailable');
        }
        const requiresAcquisitionResult = held!.managedRun === undefined
          ? moon.clientProgramRequiresAcquisitionResultPublication(preparedProgram)
          : checked(moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication!(
            held!.managedRun, preparedProgram, requested));
        if (requiresAcquisitionResult) throw new TypeError('InstalledAcquisitionResultPublicationUnsupported');
      }
      // A checked model barrier is not a Values task. The installed Model
      // connection must consume this exact plan and transfer physical custody
      // before advancing; this supervisor still owns the one Run-start claim.
      if (inferring && typeof runInfer !== 'function') {
        throw new Error('InstalledInferDispatchUnavailable');
      }
      if ((serializing || generatingContent) && typeof runContent !== 'function') {
        // Only the Host's installed physical composition may consume this
        // checked Content plan. Never execute it as dense Relation/Values.
        throw new Error('InstalledContentDispatchUnavailable');
      }
      const multiple = held!.preparedSources?.length === 2;
      const keyedAcquisition = held!.keyedSource?.acquisition ?? (typeof moon.clientProgramSelectSingleKeyedAcquisition === 'function'
        ? checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) : undefined);
      if (keyedAcquisition !== undefined && (multiple ||
          inferring && !generatingContent && typeof runInfer!.prepareKeyedLedger !== 'function')) {
        throw new Error('InstalledKeyedSourceRunProfileUnsupported');
      }
      if (keyedAcquisition !== undefined && checkpoints !== undefined && held!.keyedSource === undefined) {
        // A listing-only inventory must not authorize keyed content I/O.
        throw new Error('InstalledKeyedSourceAdmissionInventoryUnavailable');
      }
      if (inferring && multiple && typeof sourceProfile?.modelPreparation !== 'function') {
        throw new Error('InstalledInferMultiSourceUnsupported');
      }
      const installedSource = acquiring && !multiple
        ? installedSourceFor(sourceProfile, held!.preparedSource!.checkedSource.sourceRef) : undefined;
      if (retainedRelationOutput && !inferring && installedSource !== undefined &&
          installedSource.supportsRetainedRelationOutput !== true) {
        throw new TypeError('InstalledSourceRetainedOutputUnsupported');
      }
      let ledger: unknown;
      let keyedSelection: Keyed | undefined;
      const selectedSources: SelectedSource[] = [];
      if (keyedAcquisition !== undefined) {
        const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
        if (coordinates === undefined || installedSource === undefined) {
          throw new Error('InstalledKeyedSourcePreparationUnavailable');
        }
        const directOccurrence = {stage: runtimeField(coordinates, 0) as number, input: runtimeField(coordinates, 1) as number, task: runtimeField(coordinates, 2) as number};
        const directAccess = checkpoints?.acquisitionAccess(submission!.requestId,
          installedSource!.sourceAccess, {...directOccurrence,
            checkedSource: held!.preparedSource!.checkedSource,
            readTuple: held!.preparedSource!.readTuple,
            physicalBinding: held!.preparedSource!.physicalBinding,
            ...(held!.keyedSource === undefined ? {} : {installationBinding: {
              connectorId: installedSource.connectorBindings[0].connectorId,
              connectorRegistration: installedSource.connectorRegistration,
              connectorRevision: installedSource.connectorRevision,
              bindingCid: installedSource.connectorBindings[0].bindingCid}})}) ?? installedSource!.sourceAccess;
        const preparedSource = directAccess === held!.preparedSourceAccess ? held!.preparedSource! :
          await prepareAcquisition(preparedProgram, directAccess, directOccurrence,
            held!.managedRun === undefined ? undefined : held!.preparedSource!);
        const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
        const keyedAdapter = installedSourceFor(sourceProfile, (facts as readonly [string])[0]);
        if (typeof installedSource.openCapture !== 'function' ||
            typeof keyedAdapter.openKeyedLookup !== 'function' ||
            typeof keyedAdapter.keyedLedgerCapacity !== 'function') {
          throw new Error('InstalledKeyedSourceCapacityUnavailable');
        }
        const direct = installedSource!.ledgerCapacity!(preparedSource);
        const capacity = keyedAdapter.keyedLedgerCapacity(keyedAcquisition);
        const capturedContent = keyedAdapter.requiresRunContentCapture === true;
        if (capturedContent && typeof runContent?.captureKeyed !== 'function') {
          throw new Error('InstalledContentCaptureUnavailable');
        }
        const retainedKeyed = held!.keyedSource;
        const keyedAccess = retainedKeyed === undefined ? keyedAdapter.sourceAccess
          : checkpoints?.acquisitionAccess(submission!.requestId, keyedAdapter.sourceAccess,
            {...retainedKeyed.occurrence, checkedSource: retainedKeyed.prepared.checkedSource,
              readTuple: retainedKeyed.prepared.readTuple, physicalBinding: retainedKeyed.prepared.physicalBinding,
              installationBinding: {connectorId: keyedAdapter.connectorBindings[0].connectorId,
                connectorRegistration: keyedAdapter.connectorRegistration, connectorRevision: keyedAdapter.connectorRevision,
                bindingCid: keyedAdapter.connectorBindings[0].bindingCid}}) ?? keyedAdapter.sourceAccess;
        const preparedKeyed = retainedKeyed === undefined ? undefined :
          (await keyedAdapter.prepareKeyed!({preparedProgram, keyedAcquisition,
            requestIdentity: retainedKeyed.requestIdentity, sourceAccess: keyedAccess})).prepared;
        // Captured Content must retain the admitted physical read binding.
        // Refuse missing custody before reserving a start or listing any rows;
        // acquisition rechecks that binding before issuing its Content frame.
        if (capturedContent) {
          if (typeof keyedAdapter.keyedRecoveryBinding !== 'function') {
            throw new Error('InstalledCapturedContentBindingUnavailable');
          }
          keyedAdapter.keyedRecoveryBinding(preparedKeyed!);
        }
        const managedKeyed = !generatingContent && !inferring && direct.managedRun !== undefined;
        if (managedKeyed) {
          if (direct.managedRun !== held!.managedRun ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledKeyedSourceOriginalRunUnavailable');
          }
          retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested,
            preparationLease !== undefined);
          // The retained Plan already owns Direct and Compute. Borrow its
          // SAME Ledger; each actual keyed RowRun/lookup admits and grows its
          // own demand there before use. A full budget is not another cost.
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            held!.managedRun, preparedProgram, requested, [direct.capacity],
            [direct.transferBytes], [direct.executionBytes], registry, values, fragment, ordered));
        } else ledger = generatingContent ? runContent!.prepareKeyedLedger!({preparedProgram, plan: held!.plan!,
          direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          inferring ? runInfer!.prepareKeyedLedger!({preparedProgram, plan: held!.plan!,
            direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          moon.clientProgramPrepareKeyedCapturedLocalInstalledLedger(preparedProgram,
          direct.capacity, keyedAcquisition, capacity.capacity,
          [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
          capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered, capturedContent);
        if (ledger === undefined) throw new Error('InstalledKeyedSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
        keyedSelection = {directAdapter: installedSource as Keyed['directAdapter'], keyedAdapter: keyedAdapter as Keyed['keyedAdapter'], preparedSource,
          directOccurrence, directAccess, keyedAccess: keyedAccess!, preparedKeyed: preparedKeyed!,
          acquisition: keyedAcquisition, capacity, ledger, capturedContent,
          ...(managedKeyed ? {managedRun: held!.managedRun, requestIdentity: requested} : {})};
      }
      if (multiple) {
        // Read approvals retain their occurrence and physical target. Resolve
        // resumed access before selecting configurations and sizing the one
        // ledger; the exact preparations below also own the subsequent reads.
        const descriptors = ordinarySourceDescriptors(held!.preparedSources!);
        for (const [index, source] of held!.preparedSources!.entries()) {
          entry.abort.signal.throwIfAborted();
          const occurrence = descriptors[index];
          const access = checkpoints?.acquisitionAccess(submission!.requestId,
            source.sourceAccess, occurrence) ?? source.sourceAccess;
          const preparedSource = access === source.sourceAccess ? source.prepared :
            await prepareAcquisition(preparedProgram, access, source.occurrence);
          if (occurrence.installationBinding !== undefined) {
            verifyOrdinarySourceBinding(source.adapter, preparedSource, occurrence.installationBinding);
          }
          selectedSources.push({...source, access, preparedSource});
        }
        const capacities = selectedSources.map(source => {
          if (retainedRelationOutput &&
              source.adapter.supportsRetainedRelationOutput !== true) {
            throw new TypeError('InstalledSourceRetainedOutputUnsupported');
          }
          if (typeof source.adapter.ledgerCapacity !== 'function') {
            throw new TypeError('InstalledMultiSourceCapacityUnavailable');
          }
          return source.adapter.ledgerCapacity(source.preparedSource);
        });
        const managedRun = capacities[0]?.managedRun;
        if (ordinaryContent && (managedRun === undefined || held!.managedRun !== managedRun)) {
          throw new Error('InstalledContentAcquiredDispatchUnavailable');
        }
        if (capacities.some(value => value.managedRun !== undefined)) {
          if (managedRun === undefined || capacities.some(value => value.managedRun !== managedRun) ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledMultiSourceOriginalRunUnavailable');
          }
          // The original operational parent was admitted before preparation.
          // Do not replace it with the legacy scalar accounting constructor,
          // even when another Source has equal capacities or matching CIDs.
          if (ordinaryContent) {
            if (typeof runContent!.prepareOrdinaryAcquiredLedger !== 'function') {
              throw new Error('InstalledContentAcquiredDispatchUnavailable');
            }
            retainDispatchPreparationHost(entry, moon, managedRun, preparedProgram, requested, preparationLease !== undefined);
            ledger = runContent!.prepareOrdinaryAcquiredLedger!({preparedProgram, plan: held!.plan!, sourceCapacities: capacities});
            entry.borrowedSources = true;
          } else if (inferring) {
            if (held!.managedRun !== managedRun || typeof runInfer!.prepareAcquiredLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            retainDispatchPreparationHost(entry, moon, managedRun, preparedProgram, requested, preparationLease !== undefined);
            ledger = runInfer!.prepareAcquiredLedger!({preparedProgram, plan: held!.plan!, sourceCapacities: capacities});
            entry.borrowedSources = true;
          } else {
          if (capacities.some(value => value.wholeInput === true)) {
            if (capacities.some(value => value.wholeInput !== true) ||
                typeof moon.clientProgramInstalledManagedWholeSourcesLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourcesLedger(
              managedRun, preparedProgram, requested, capacities.map(value => value.capacity),
              capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes)));
          } else {
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            managedRun, preparedProgram, requested,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered));
          }
          }
        } else {
          ledger = moon.clientProgramPrepareMultiCapturedLocalInstalledLedger(preparedProgram,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      const requestModelAcquired = inferring && !generatingContent && acquiring && !multiple &&
        keyedSelection === undefined && held!.managedRun !== undefined;
      if ((generatingContent || requestModelAcquired) && acquiring && keyedSelection === undefined &&
          !(multiple && ordinaryContent)) {
        if (multiple ||
            (ordinaryContent ? typeof runContent!.prepareOrdinaryAcquiredLedger !== 'function'
              : typeof (requestModelAcquired ? runInfer! : runContent!).prepareAcquiredLedger !== 'function') ||
            typeof installedSource?.ledgerCapacity !== 'function') {
          throw new Error('InstalledContentAcquiredDispatchUnavailable');
        }
        const access = checkpoints?.acquisitionAccess(submission!.requestId,
          installedSource!.sourceAccess) ?? installedSource!.sourceAccess;
        if (held!.preparedSourceAccess !== access) {
          held!.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held!.managedRun === undefined ? undefined : held!.preparedSource!);
          held!.preparedSourceAccess = access;
        }
        if (requestModelAcquired) {
          retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested, preparationLease !== undefined);
          ledger = runInfer!.prepareAcquiredLedger!({preparedProgram, plan: held!.plan!,
            sourceCapacity: installedSource!.ledgerCapacity!(held!.preparedSource!)});
          entry.borrowedSources = true;
        } else if (ordinaryContent) {
          retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested, preparationLease !== undefined);
          ledger = runContent!.prepareOrdinaryAcquiredLedger!({preparedProgram, plan: held!.plan!,
            sourceCapacities: [installedSource!.ledgerCapacity!(held!.preparedSource!)]});
          entry.borrowedSources = true;
        } else ledger = runContent!.prepareAcquiredLedger!({preparedProgram, plan: held!.plan!,
          sourceCapacity: installedSource!.ledgerCapacity!(held!.preparedSource!)});
        entry.acquisitionLedger = ledger;
      }
      const singleAccounted = acquiring && !multiple && keyedSelection === undefined &&
        !inferring && !serializing;
      if (singleAccounted) {
        const access = checkpoints?.acquisitionAccess(submission!.requestId,
          installedSource!.sourceAccess) ?? installedSource!.sourceAccess;
        if (held!.preparedSourceAccess !== access) {
          held!.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held!.managedRun === undefined ? undefined : held!.preparedSource!);
          held!.preparedSourceAccess = access;
        }
        if (typeof installedSource!.ledgerCapacity !== 'function') {
          throw new Error('InstalledSingleSourceCapacityUnavailable');
        }
        const capacity = installedSource!.ledgerCapacity!(held!.preparedSource!);
        if (capacity.managedRun !== undefined) {
          if (capacity.managedRun !== held!.managedRun) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          if (capacity.wholeInput === true) {
            if (typeof moon.clientProgramInstalledManagedWholeSourceLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourceLedger(
              capacity.managedRun, preparedProgram, requested,
              capacity.capacity, capacity.transferBytes, capacity.executionBytes));
          } else {
            if (typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            // One Source uses the same operational parent as the checked
            // capture prefix. Equal scalar capacity is not a replacement Run.
            ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
              capacity.managedRun, preparedProgram, requested,
              [capacity.capacity], [capacity.transferBytes], [capacity.executionBytes],
              registry, values, fragment, ordered));
          }
        } else {
          if (capacity.wholeInput === true || held!.managedRun !== undefined) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          ledger = moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
            capacity.capacity, capacity.transferBytes, capacity.executionBytes,
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledSingleSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      let setup: Setup | undefined;
      let acquiredInfer: Readonly<{sources?: readonly unknown[]; ledger?: unknown; managedRun?: unknown;
        captureStartedAt: string; captureCompletedAt: string; sourceEvidence?: unknown;
        input?: unknown; captured?: Capture; adapter?: Adapter; preparedSource?: Prepared;
        sourceAccess?: SourceAccess; occurrence?: Occurrence; sourceEvidenceWire?: string}> | undefined;
      let acquiredContent: unknown;
      if (!acquiring && !inferring && !serializing) {
        if (managedComputeRequired && held!.managedRun === undefined) {
          throw new Error('InstalledManagedComputeRunUnavailable');
        }
        if (held!.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedSourceFreeHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          if (!generatingContent && !Object.hasOwn(held!, 'sampleProfile') && preparationLease !== undefined &&
              typeof capturedRun === 'function' && typeof authorizeLogicalObservation === 'function') {
            const logical = prepareInstalledLogicalObservation(moon, control,
              held!.managedRun, sourceFreePlanExecutionOwner(held!.plan!), held!.plan!.runDefinition, observation);
            if (logical !== undefined) entry.logicalObservation = logical;
          }
          // This opaque Run already owns the original operational Ledger.
          // Missing/foreign/parked originals cannot fall back to accounting.
          setup = checked(moon.clientProgramOpenInstalledManagedSourceFreeHost(
            held!.managedRun, preparedProgram, requested, registry, values,
            fragment, ordered, retainedRelationOutput)) as Setup | undefined;
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenSourceFreeLocalRetainedHost
            : moon.clientProgramOpenSourceFreeLocalHost;
          setup = open(
            preparedProgram, registry, values, 1n, 0n, 0n, 0n,
            fragment, ordered);
        }
        if (setup === undefined) throw new Error('ClientProgramNeedsInputs');
        // Retain before the reservation/fault boundary: cancellation can
        // arrive there before runPublished transfers execution custody.
        entry.pendingSetup = setup;
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.attach(Reflect.apply(capturedRun!, moon, [setup]),
            accepted!.ref, actual, operation => authorizeLogicalObservation!(operation, connection),
            control.runDefinitionRunId(accepted!.runDefinition!));
        }
      }
      // The resumed admission and physical start reservation are adjacent.
      if (gate !== undefined) {
        try { gate.beforePhysicalStart(); }
        catch (error) {
          reached({refused: error});
          await settleCleanup(entry);
          return;
        }
      }
      let physicalStarted;
      let taskControl: Parameters<Published>[10];
      {
        const originalHeld = held;
        const originalAdmission = accepted;
        if (originalHeld?.plan === undefined || originalAdmission === undefined) {
          throw new Error('ClientDispatchOriginalUnavailable');
        }
        let debugController: Entry['debugControl'];
        let debugStart: DebugStartWitness | undefined;
        let debugResume: DebugStartSelection | undefined;
        if (resumesDebug && (typeof prepareDebugEntryResume !== 'function' ||
            (parkDebugEntry
              ? !Number.isSafeInteger(debugEntryExpiresAt) || debugEntryExpiresAt <= 0 ||
                debugResumeCid !== undefined || !Object.hasOwn(originalHeld, 'sampleProfile')
              : typeof debugResumeCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(debugResumeCid)) ||
            acquiring || inferring || serializing || generatingContent ||
            gate !== undefined || setup === undefined || entry.pendingSetup !== setup ||
            originalHeld.managedRun === undefined || entry.preparationHostBorrow === undefined)) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        // Transfer the selected writer into the original dispatch entry.
        // The remaining synchronous aliases end before the following awaits.
        let sampleReady: (() => void) | undefined;
        let sampleStartSelection: Pick<PhysicalStartOptions, 'captureSampleStart'> | undefined;
        let sampleStartRevision: number | undefined;
        let checkedSampleProfile: object | undefined, debugMapCid: string | undefined;
        let sampleRun: object | undefined, sampleExecution: Parameters<Control['reserveClientRelationSampleStart']>[2] | undefined;
        let sampleDefinition: DebugDefinition | undefined, sampleCaptured: unknown;
        // Only the installed owner can provide this private receiver.
        // The ordinary wire Debug intent does not opt in to unattended resume.
        if (Object.hasOwn(originalHeld, 'sampleProfile')) {
          // The already selected Run transfers its original profile once.
          // Merely installing the shared dispatcher never selects a Normal Run.
          const sampleProfile = originalHeld.sampleProfile;
          delete originalHeld.sampleProfile;
          if ((!resumesDebug && (typeof prepareSampleStart !== 'function' || originalAdmission.dispatchReserved === true)) ||
              sampleProfile === undefined || gate !== undefined || preparationLease === undefined ||
              acquiring || inferring || serializing || generatingContent ||
              originalHeld.managedRun === null || typeof originalHeld.managedRun !== 'object' || setup === undefined ||
              entry.pendingSetup !== setup || entry.preparationHostBorrow === undefined) {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          const execution = sourceFreePlanExecutionOwner(originalHeld.plan);
          if (execution === undefined ||
              typeof capturedRun !== 'function' ||
              typeof journal.originalSubmittedIntent !== 'function' ||
              typeof control.prepareClientLogicalObservation !== 'function' ||
              typeof moon.clientProgramLogicalObservationCleanup !== 'function' ||
              typeof moon.clientProgramReturnLogicalObservation !== 'function' ||
              typeof authorizeSampleCapture !== 'function' ||
              typeof control.reserveClientRelationSampleStart !== 'function' ||
              typeof control.acknowledgeClientRelationSampleStart !== 'function') {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          sampleRun = originalHeld.managedRun;
          // The Journal admits its own copy of the definition. Its ACK must
          // match this Run, while the compiler and setup keep their nominal original.
          const definition = originalHeld.plan.runDefinition;
          if (definition?.identity !== originalAdmission.ref.runDefinitionCid ||
              definition.identity !== originalAdmission.runDefinition?.identity ||
              definition.wire !== originalAdmission.runDefinition.wire) {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          sampleDefinition = definition as DebugDefinition;
          control.reserveClientRelationSampleStart(sampleRun, requested, execution, sampleDefinition, setup, undefined, resumesDebug);
          entry.abort.signal.throwIfAborted();
          const {profile: checkedProfile, startTicket, withAdoption, logicalMapCid} = checkSampleProfile(entry, requested, originalAdmission.ref, sampleRun, execution,
            sampleDefinition, setup, sampleProfile);
          returnSampleProfileObservation(entry, moon);
          entry.abort.signal.throwIfAborted();
          // The temporary profile reader and the optional boundary observer
          // reuse one sibling slot on the same Request. Only the latter may
          // stay live through Compute and observation delivery.
          if (typeof authorizeLogicalObservation === 'function') {
            const logical = prepareInstalledLogicalObservation(moon, control,
              sampleRun, execution, sampleDefinition, observation);
            if (logical !== undefined) {
              entry.logicalObservation = logical;
              logical.attach(Reflect.apply(capturedRun, moon, [setup]),
                accepted!.ref, actual, operation => authorizeLogicalObservation(operation, connection),
                control.runDefinitionRunId(sampleDefinition));
            }
          }
          entry.abort.signal.throwIfAborted();
          const sampleAuthority = {principalId: actual, connection, ref: accepted!.ref};
          if (!resumesDebug) {
            sampleReady = prepareSampleStart?.(setup, sampleRun, checkedProfile, sampleAuthority);
            if (typeof sampleReady !== 'function') invalidSampleStartReceiver(sampleReady);
          }
          checkedSampleProfile = checkedProfile;
          if (typeof logicalMapCid === 'string') debugMapCid = logicalMapCid;
          sampleExecution = execution;
          sampleCaptured = Reflect.apply(capturedRun, moon, [setup]);
          if (sampleCaptured === undefined) throw new Error('ClientRunSampleStartOriginalUnavailable');
          entry.sampleAdoption = selectedSampleAdoption(entry, withAdoption, hostConnection,
            sampleAuthority, authorizeSampleCapture, sampleRun, checkedProfile);
          sampleStartSelection = {captureSampleStart: {program: execution.program, compiled: execution.compiled, startTicket,
            captureAdoption: entry.sampleAdoption.captureAdoption,
            captureRevision(revision) { sampleStartRevision = revision; }}};
          entry.abort.signal.throwIfAborted();
        }
        if (resumesDebug) {
          const authority = Object.freeze({principalId: actual, connection, ref: accepted!.ref});
          debugController = checkedSampleProfile === undefined
            ? prepareDebugEntryResume?.(setup, originalHeld.managedRun, authority)
            : prepareDebugEntryResume?.(setup, originalHeld.managedRun, authority, checkedSampleProfile,
              entry.abort.signal, debugMapCid, sampleDefinition);
          entry.debugControl = debugController;
          taskControl = debugController?.taskControl;
          if (typeof debugController?.activate !== 'function' || typeof debugController.current !== 'function' ||
              typeof taskControl?.phase !== 'function' || typeof taskControl.waitForResume !== 'function') {
            throw new TypeError('InvalidInstalledTaskController');
          }
          const originalController = debugController;
          const current = () => !entry.abort.signal.aborted && hostConnection(authority) === true &&
            originalController.current() === true && hostConnection(authority) === true && !entry.abort.signal.aborted;
          if (parkDebugEntry) {
            if (typeof debugController.parkEntry !== 'function' || claim.revision === undefined ||
                !Number.isInteger(claim.revision)) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
            if (draining) throw new Error('ClientRunDebugEntryHostClosing');
            entry.waitingForDebugEntry = true;
            try {
              if (retainedDebugEntry === undefined) {
                debugResumeCid = await debugController.parkEntry(requested, claim.revision, debugEntryExpiresAt);
              } else {
                if (claim.kind !== 'reconcile' || claim.revision !== retainedDebugEntry.park.revision ||
                    typeof debugController.reopenEntry !== 'function') {
                  throw new Error('ClientRunDebugEntryOriginalUnavailable');
                }
                const waiting = debugController.reopenEntry(retainedDebugEntry.park, retainedDebugEntry.assertCurrent);
                retainedDebugEntry.ready();
                retainedDebugEntry = undefined;
                debugResumeCid = await waiting;
              }
            } finally {entry.waitingForDebugEntry = false;}
            entry.abort.signal.throwIfAborted();
            if (!current()) throw new Error('ClientRunDebugEntryDenied');
            if (draining) throw new Error('ClientRunDebugEntryHostClosing');
          }
          if (debugResumeCid === undefined) throw new Error('ClientRunDebugEntryOriginalUnavailable');
          debugResume = {commandCid: debugResumeCid, current,
            capture(witness) {debugStart = witness;}};
        }
        entry.physicalStartClaimAttempted = true;
        physicalStarted = journal.reservePhysicalStart(requested, {
          namespaceId, ref: accepted!.ref,
          currentAuthorization: hostConnection({principalId: actual,
            connection, ref: accepted!.ref}),
          ...(!acquiring && !inferring && !serializing && !generatingContent ? {
            localExecutionOwner: sourceFreePlanExecutionOwner(originalHeld.plan),
          } : {}),
          ...(acquiring && journal.sourceOperationConfigured === true ? {
            captureSourceOperation: {program: preparedProgram, compiled: originalHeld.plan.compiled, store,
              capture(scope) {entry.sourceOperationScope = scope;}},
          } : {}),
          ...sampleStartSelection,
          ...(debugResume === undefined ? {} : {debugResume}),
        }, moon, control);
        if (physicalStarted) {
          // A refusal in the receiver cannot erase the committed start.
          entry.physicalStarted = true;
          entry.finishPending = true;
          // The Journal can assign this witness only through the synchronous ACK callback.
          const acknowledgedDebugStart = debugStart as DebugStartWitness | undefined;
          if (debugResume !== undefined) {
            if (acknowledgedDebugStart === undefined || acknowledgedDebugStart.commandCid !== debugResumeCid ||
                !['step', 'terminal'].includes(acknowledgedDebugStart.until) ||
                !Number.isInteger(acknowledgedDebugStart.acceptedRevision) || acknowledgedDebugStart.acceptedRevision < 1 ||
                acknowledgedDebugStart.physicalStartRevision !== acknowledgedDebugStart.acceptedRevision + 1 ||
                acknowledgedDebugStart.physicalStartRevision > 2147483647 || debugResume.current() !== true) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
          }
          // The writer and both acknowledged originals must agree before
          // either Core Sample custody or the live Debug task can advance.
          if (sampleStartSelection !== undefined) {
            if (typeof sampleStartRevision !== 'number' || !Number.isInteger(sampleStartRevision) || sampleStartRevision <= 0 ||
                sampleStartRevision > 2147483647 ||
                sampleExecution === undefined || entry.sampleAdoption === undefined ||
                (acknowledgedDebugStart !== undefined && sampleStartRevision !== acknowledgedDebugStart.physicalStartRevision)) {
              throw new Error('ClientRunSampleStartOriginalUnavailable');
            }
            entry.sampleAdoption.requireWriter();
            control.acknowledgeClientRelationSampleStart(sampleRun, requested, sampleExecution,
              sampleDefinition, sampleCaptured, sampleStartRevision);
            entry.abort.signal.throwIfAborted();
          }
          if (debugResume !== undefined) {
            if (debugController === undefined || acknowledgedDebugStart === undefined) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
            if (sampleStartSelection !== undefined && debugResume.current() !== true) {
              throw new Error('ClientRunDebugEntryDenied');
            }
            const result = debugController.activate(acknowledgedDebugStart);
            if (result !== undefined) invalidSampleStartReceiver(result, 'InvalidInstalledTaskController');
            if (debugResume.current() !== true) throw new Error('ClientRunDebugEntryDenied');
          } else if (sampleReady !== undefined) {
            const result = sampleReady();
            if (result !== undefined) invalidSampleStartReceiver(result);
          }
          if (sampleStartSelection !== undefined) {
            entry.abort.signal.throwIfAborted();
            if (entry.sampleAdoption === undefined) throw new Error('ClientRunSampleStartOriginalUnavailable');
            entry.sampleAdoption.arm();
          }
        }
      }
      if (!physicalStarted) {
        await settleCleanup(entry);
        return;
      }
      if (draining) entry.debugControl?.beginDrain?.();
      gate?.started();
      reached('started');
      await step('physical_start_reserved', {ref: accepted!.ref});
      const sourceAccess = checkpoints?.acquisitionAccess(
        submission!.requestId, installedSource?.sourceAccess) ??
        installedSource?.sourceAccess;
      if (keyedSelection !== undefined) {
        const keyed = await acquireKeyedSources(entry, preparedProgram, keyedSelection, held!.plan as PreparedPlan, actual);
        held!.plan = keyed.plan;
        setup = keyed.setup as Setup | undefined;
        acquiredContent = keyed.acquiredContent;
      } else if (multiple) {
        entry.borrowedSources = true;
        const captures: Capture[] = [];
        const closed = new Set();
        entry.sourceCapture = Object.freeze({async close() {
          const failures: unknown[] = [];
          for (const capture of captures) {
            if (closed.has(capture)) continue;
            try {
              await step('acquisition_cleanup_started', {ref: accepted!.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
              await capture.close();
              closed.add(capture);
              diagnostic('acquisition_cleanup_completed', {ref: accepted!.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
            }
            catch (error) { failures.push(error); }
          }
          if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
        }});
        const captureStartedAt = now();
        const sources: Array<SelectedSource & {captured: Capture; sourceEvidence: ReturnType<Control['takeSourceEvidenceOriginal']>; sourceEvidenceWire?: string}> = [];
        for (const source of selectedSources) {
          entry.abort.signal.throwIfAborted();
          const {access, preparedSource} = source;
          await step('acquisition_started', {ref: accepted!.ref, task: source.occurrence.task,
            selection: preparedSource.selection,
            resourceUsage: resourceUsage(ledger)});
          entry.abort.signal.throwIfAborted();
          entry.physicalWorkMayHaveStarted = true;
          const acquisition = acquisitionEndHandoff();
          const measured = observation?.canMeasure('source') ? performance.now() : undefined;
          let captured: Capture;
          let returned = false;
          try {
            captured = await source.adapter.open({preparedProgram, registry, values,
              fragment, ordered, sourceAccess: access, signal: entry.abort.signal,
              preparedSource, occurrence: source.occurrence, ledger,
              reportAcquisitionFailure: acquisition.retain,
              ...(entry.sourceOperationScope === undefined ? {} : {
                originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
                  journal, store, preparedProgram, preparedSource, source.occurrence),
              })});
            returned = true;
          } catch (error) {
            const ended = acquisition.outcome(error);
            if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
              entry.stopObservationPending = true;
            } else if (ended.recovery !== undefined) {
              entry.cleanupOwner = ended.recovery as Execution;
            } else {
              // Earlier captures settling proves nothing about an unknown
              // current acquisition that handed back no physical owner.
              entry.unresolvedCleanup = true;
            }
            throw error;
          } finally {
            if (measured !== undefined) observation!.emit('source', 'acquisition_interval',
              {ref: accepted!.ref, task: source.occurrence.task,
                outcome: returned ? 'confirmed' : 'failed'},
              {segment: 'source-acquisition', durationMs: performance.now() - measured});
          }
          captures.push(captured);
          await step('acquisition_completed', {ref: accepted!.ref, task: source.occurrence.task,
            acquisition: captured.acquisition,
            resourceUsage: resourceUsage(ledger)});
          const evidenceOptions = {authorityScopeCid,
            effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
          await captured.prepareSourceEvidenceOriginal(evidenceOptions);
          const sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
          sources.push({...source, captured, sourceEvidence,
            ...(inferring || ordinaryContent ? {sourceEvidenceWire: sourceEvidence.wire} : {})});
        }
        const captureCompletedAt = now();
        const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
        if (effectiveDataPolicyCid === undefined) throw new Error('InstalledMultiSourcePolicyUnavailable');
        if (ordinaryContent) {
          acquiredContent = {managedSources: sources, ledger, captureStartedAt, captureCompletedAt};
        } else if (inferring) {
          acquiredInfer = {sources, ledger, managedRun: held!.managedRun, captureStartedAt, captureCompletedAt,
            sourceEvidence: sources.map(source => source.sourceEvidence)};
        } else {
        held!.plan = acquiredMultiTaskPublicationPlan({moon, control, acquired: held!.plan as PreparedPlan,
          publicationOriginal: held!.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held!.managedRun},
          preparedProgram, sources, authorityScopeCid, effectiveDataPolicyCid,
          captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now});
        if (held!.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
            held!.managedRun, preparedProgram, requested, captures.map(value => value.capture.source()))) as Setup | undefined;
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenMultiCapturedLocalRetainedHost
            : moon.clientProgramOpenMultiCapturedLocalHost;
          setup = open(preparedProgram,
            captures.map(value => value.capture.source()), ledger, registry, values, fragment, ordered);
        }
        if (setup === undefined) throw new Error('InstalledMultiSourceHostUnavailable');
        entry.pendingSetup = setup;
        const dag = moon.strategyHostRun(setup);
        for (const [slot, captured] of captures.entries()) {
          const occurrence = selectedSources[slot].occurrence;
          captured.capture.retainTask(dag, occurrence.computeTask ?? occurrence.task);
        }
        }
      } else if (acquiring) {
        if (held!.preparedSourceAccess !== sourceAccess) {
          held!.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess, undefined, held!.managedRun === undefined ? undefined : held!.preparedSource!);
          held!.preparedSourceAccess = sourceAccess;
        }
        const {captureStartedAt, captureCompletedAt, sourceEvidence, sourceEvidenceWire} =
          await acquireSource(entry as Parameters<Acquisition>[0], preparedProgram, held!.preparedSource!, sourceAccess,
            {captureOnly: generatingContent || requestModelAcquired, originalEvidence: ordinaryContent || singleAccounted || inferring && !generatingContent,
              ledger: generatingContent || singleAccounted || requestModelAcquired ? ledger : undefined,
              occurrence: inferring ? runInfer!.sourceOccurrence?.(preparedProgram, 0) : undefined});
        if (ordinaryContent) {
          acquiredContent = {managedSources: [{captured: entry.sourceCapture,
            sourceEvidence, sourceEvidenceWire: (sourceEvidence as ReturnType<Control['takeSourceEvidenceOriginal']>).wire}],
            ledger, captureStartedAt, captureCompletedAt};
        } else if (generatingContent) {
          acquiredContent = {captured: entry.sourceCapture, ledger, sourceEvidenceWire,
            authorityScopeCid, captureStartedAt, captureCompletedAt,
            sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire!,
              {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
        } else if (inferring) {
          const captured = entry.sourceCapture as Capture;
          const input = requestModelAcquired || captured.composedInfer ? undefined : control.admitInferCapturedInput(
            preparedProgram, captured as Capture & Parameters<InferAdmission>[1], sourceEvidence, authorityScopeCid,
            captured.checkedSource.sourceDataPolicyCid, captureStartedAt, captureCompletedAt);
          acquiredInfer = {input, captured, adapter: installedSource, preparedSource: held!.preparedSource, sourceAccess,
            occurrence: runInfer!.sourceOccurrence?.(preparedProgram, 0),
            ...(requestModelAcquired ? {ledger, managedRun: held!.managedRun} : {}),
            sourceEvidenceWire: (sourceEvidence as ReturnType<Control['takeSourceEvidenceOriginal']>).wire, captureStartedAt, captureCompletedAt, sourceEvidence};
        } else {
          held!.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held!.plan as PreparedPlan, preparedProgram,
          publicationOriginal: held!.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held!.managedRun},
          captured: entry.sourceCapture as Capture, sourceEvidence,
          authorityScopeCid,
          effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(preparedProgram)!,
          captureStartedAt, captureCompletedAt, namespaceId,
          requestId: submission!.requestId, storeAuthorityCid, now} as Direct & Readonly<{requestId: string}>);
        }
        if (singleAccounted) {
          // Reuse the existing borrowed-input cleanup order: stop Compute,
          // close its original physical input, then reclaim DAG outputs.
          entry.borrowedSources = true;
          const capture = (entry.sourceCapture as Capture).capture;
          if (held!.managedRun !== undefined) {
            retainDispatchPreparationHost(entry, moon, held!.managedRun, preparedProgram, requested, preparationLease !== undefined);
            if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
              throw new Error('InstalledManagedComputeHostUnavailable');
            }
            setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
              held!.managedRun, preparedProgram, requested, [capture.source()])) as Setup | undefined;
          } else {
            setup = moon.clientProgramOpenSingleCapturedLocalHost(preparedProgram,
              capture.source(), ledger, registry, values, fragment, ordered, retainedRelationOutput);
          }
          if (setup === undefined) throw new Error('InstalledSingleSourceHostUnavailable');
          // Retain before binding the borrow: a failed binding still leaves
          // this same Compute owner in child-first cleanup custody.
          entry.pendingSetup = setup;
          capture.retainTask(moon.strategyHostRun(setup), 0);
        } else setup = (entry.sourceCapture as Capture).setup;
      }
      entry.abort.signal.throwIfAborted();
      entry.physicalWorkMayHaveStarted = true;
      entry.computeStartAttempted = true;
      if (serializing) {
        await runContent!({preparedProgram, plan: held!.plan!, store,
          principalId: actual, signal: entry.abort.signal, acquiredContent,
          retainExecution(execution: Execution) {
            if (entry.cleanupOwner !== undefined && entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        // A byte writer or private capture alone is not a public Result. The
        // same committed Store index and physical-close owner govern success.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledContentPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted!.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      if (inferring) {
        const result = await runInfer!({preparedProgram, plan: held!.plan!, store,
          preparationHolder: entry.preparationHostBorrow,
          acquiredInfer, acquiredContent,
          ...(acquiredInfer?.sources === undefined ? {} : {
            originalPreparation: sourceProfile!.modelPreparation!(preparedProgram, held!.plan!)}),
          submission: Object.fromEntries(['requestId', 'principalId', 'connection',
            'kind', 'input', 'parameters'].filter(key => Object.hasOwn(submission!, key))
            .map(key => [key, submission![key as keyof Submission]])),
          principalId: actual, signal: entry.abort.signal,
          retainExecution(execution: Execution) {
            if (entry.cleanupOwner !== undefined &&
                entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        if (result?.status === 'waiting_checkpoint') {
          const checkpoint = checkpoints?.journal.inspect(result.checkpoint?.checkpointCid);
          if (entry.cleanupOwner === undefined || checkpoint?.kind !== 'model_invocation' ||
              checkpoint.prepareAttemptId !== null ||
              checkpoint.runDefinitionCid !== accepted!.ref.runDefinitionCid ||
              checkpoint.runId !== control.runDefinitionRunId(accepted!.runDefinition!)) {
            throw new Error('InstalledInferWaitingNotCommitted');
          }
          // The fixed input and continuation have reached durable custody.
          // Stopping this physical owner is not a failed or cancelled Run;
          // the Checkpoint lifecycle remains authoritative for its next step.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_waiting_checkpoint', {ref: accepted!.ref,
            checkpointCid: checkpoint.checkpointCid});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        if (result?.status === 'needs_reconciliation') {
          const runId = control.runDefinitionRunId(accepted!.runDefinition!);
          if (entry.cleanupOwner === undefined ||
              checkpoints?.journal.hasUnresolvedModelCalls(runId) !== true) {
            throw new Error('InstalledInferUnknownNotRecorded');
          }
          retainDispatchPrimaryFailure(entry, result);
          // The owner made all permitted progress and retained an entered
          // call without a saved response. Physical stop is not an ordinary
          // failure and cannot turn that call into a completed barrier.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_needs_reconciliation', {ref: accepted!.ref});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        // Success is the existing Store's committed index, not merely a
        // returned model value or a completed private capture.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledInferPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted!.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      const published = await runPublished(setup!,
        {store, plan: held!.plan},
        { ...computeConfigurations,
          ...(sourceAccess === undefined ? {} :
            {authorization: sourceAccess.authorization}) },
        entry.abort.signal, undefined, owner => {
          // One synchronous transfer consumes this exact pending setup before
          // either the preflight or completed-execution owner may close it.
          if (entry.cleanupOwner !== undefined ||
              entry.pendingSetup !== undefined && entry.pendingSetup !== setup) {
            throw new Error('ClientDispatchCleanupOwnerAlreadyRetained');
          }
          // The managed driver has returned. Publication may await an
          // independent Store, but it no longer owns a Sample commit visit.
          closeDebugControl(entry);
          closeSampleAdoption(entry);
          entry.cleanupOwner = owner;
          entry.pendingSetup = undefined;
        }, observation === undefined ? undefined : installTaskObservation(({event, task, durationMs}) =>
          observation.emit('compute', event, {ref: accepted!.ref, task}, {durationMs}),
          entry.logicalObservation === undefined ? undefined
            : (phase, task) => entry.logicalObservation!.project(phase, task)), entry.preparationHostBorrow,
        entry.preparationHostBorrow === undefined ? undefined : () => {
          if (typeof beforePublication !== 'function') throw new Error('PreparationPublicationUnavailable');
          return beforePublication(preparedProgram);
        }, entry.sampleAdoption?.driver, taskControl);
      entry.cleanupOwner = published;
      entry.publicationCommitted = true;
      await step('computed', {ref: accepted!.ref,
        outputRepresentations: (published.execution?.completed ?? [])
          .map(task => ({task:task.task,
            representation:task.outputRepresentation})),
        carrierSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.snapshot !== undefined)
          .map(task => ({task:task.task,...(task.snapshot as object)})),
        relationSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.relationSnapshot !== undefined)
          .map(task => ({task:task.task,...(task.relationSnapshot as object)}))});
      await settleCleanup(entry);
      await finishRun(entry);
    }).catch(async cause => {
      if (!Object.hasOwn(entry, 'primaryFailure')) entry.primaryFailure = cause;
      try {
        const original = entry.primaryFailure;
        const primaryFailure = original instanceof CapturedRunPublicationError
          ? original.primaryFailure : original;
        const issue = (primaryFailure as Failure | null | undefined)?.cause;
        const issueTag = runtimeTag(issue);
        const nestedIssue = runtimeOptionalField(issue, 0);
        const nestedTag = runtimeTag(nestedIssue);
        const leafIssue = runtimeOptionalField(nestedIssue, 0);
        const leafTag = runtimeTag(leafIssue);
        diagnostic('dispatch_failed', {ref: accepted!.ref,
          code: (cause as Failure | null | undefined)?.code ?? (cause as Failure | null | undefined)?.message ?? 'ClientDispatchFailed',
          primaryCode: (primaryFailure as Failure | null | undefined)?.code,
          primaryDiagnostic: dispatchFailureSnapshot(primaryFailure)?.primaryDiagnostic ??
            dispatchFailureCodeSite(primaryFailure, diagnosticErrorType, diagnosticStackFormatter),
          cleanupDiagnostic: dispatchFailureSnapshot(primaryFailure)?.cleanupDiagnostic,
          issueTag: issueTag === undefined && Number.isSafeInteger(issue) &&
            (issue as number) >= 0 && (issue as number) <= 65535 ? issue : issueTag,
          nestedIssueTag: nestedTag === undefined && Number.isSafeInteger(nestedIssue) &&
            (nestedIssue as number) >= 0 && (nestedIssue as number) <= 65535 ? nestedIssue : nestedTag,
          leafIssueTag: leafTag === undefined && Number.isSafeInteger(leafIssue) &&
            (leafIssue as number) >= 0 && (leafIssue as number) <= 65535 ? leafIssue
            : Number.isSafeInteger(leafTag) && (leafTag as number) >= 0 && (leafTag as number) <= 65535 ? leafTag : undefined});
      } catch { /* Optional diagnostics cannot interrupt cleanup. */ }
      const failedExecution = cause instanceof CapturedRunPublicationError
        ? cause.execution : undefined;
      if ((cause as Failure | null | undefined)?.cleanupPending === true) {
        if (typeof (cause as Failure).cleanupHandle?.status === 'function' &&
            typeof (cause as Failure).cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = (cause as Failure).cleanupHandle;
        } else if (failedExecution === undefined && entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      if (entry.reserved && !entry.physicalStartClaimAttempted &&
          !resumesDebug && !entry.abort.signal.aborted) {
        entry.failureObservationPending = true;
      }
      if (failedExecution !== undefined) entry.cleanupOwner = failedExecution;
      if (entry.physicalStarted && entry.cleanupOwner !== undefined) {
        entry.stopObservationPending = true;
      }
      try { await settleCleanup(entry); }
      catch (cleanupFailure) { entry.cleanupFailure = cleanupFailure; }
      try { await finishRun(entry); }
      catch (failure) { entry.finishFailure = failure; }
    }).finally(() => {
      retainedDebugEntry = undefined;
      entry.settled = true;
      reached('not_started');
      try { releaseAcquisition(entry); }
      catch (failure) { entry.releaseFailure = failure; }
      retire(entry);
    });
    // Retain only the originating optional observation, not a new operation
    // or a release receipt. The physical-start barrier remains independent.
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return physical;
  };

  const {track, settleCredentialRefusal, drain: drainTracked} = createClientDispatchTracking({
    entries, keyOf, current, beforeDispatch, acquireSource, retainDispatchPrimaryFailure,
    settleCleanup, settleRetainedEntry, retire, credentialRefusalPending, diagnostic,
    diagnosticErrorType, diagnosticStackFormatter, observation,
    beforeDrain(entry) {
      const original = current(entry.ref);
      if (original !== entry) return;
      // Untouched entry parks have no physical start. Started parks still
      // retire through the existing physical Driver and the same cleanup.
      if (original.waitingForDebugEntry) closeDebugControl(original);
      else if (original.physicalStarted) original.debugControl?.beginDrain?.();
    },
  });
  const drain = () => {
    draining = true;
    return drainTracked();
  };
  return Object.freeze({start, track, cancel, live, operation, failureMessage, drain,
    credentialRefusalPending, settleCredentialRefusal, observeDebugTask, resumeDebugTask, lookupDebugResume,
    readDebugNextSample, observeDebugInspect});
}
