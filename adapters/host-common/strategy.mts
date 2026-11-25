// Trusted JavaScript coordination only. Checked readiness, selected ownership,
// reservations and atomic completion are enforced by the common MoonBit core.
// Installed entries are implementation code, not user-supplied success proofs.
import {strategyAction} from './strategy-actions.mjs';
import {bindExecutionSiteCandidate, classifyManagedExecutionSiteFallback,
  beginFailedExecutionSiteOperation,
  beginExecutionSiteHostCleanup,
  beginExecutionSiteHostTaskSuccess,
  beginRetainedExecutionSiteClose,
  beginRetainedExecutionSiteHolding,
  executionSiteCandidate,
  executionSiteDescription, executionSiteHostCleanupAction,
  executionSiteHostCleanupPending, executionSiteHostTaskRunOutcome,
  executionSiteHostTaskSuccessAction,
  executionSiteHostTaskSiteOperationSettled,
  executionSiteOperationAvailable,
  executionSitePlacements, failedExecutionSiteOperationAction,
  installExecutionSites,
  prepareSingleExecutionSitePolicy, releaseExecutionSiteHolding,
  recordExecutionSiteHostCleanupClosesAwaited,
  recordExecutionSiteHostCleanupRetry,
  recordExecutionSiteHostTaskCommonCompletion,
  recordExecutionSiteHostTaskManagedBinding,
  recordExecutionSiteHostTaskOutputRetained,
  recordExecutionSiteHostTaskSiteCompletion,
  recordExecutionSiteHostTaskSiteOperationSettled,
  recordFailedExecutionSiteOperationSettlement,
  recordFailedExecutionSiteOperationStop,
  recordRetainedExecutionSiteCleanupAuthority,
  recordRetainedExecutionSiteCleanupStopped,
  recordRetainedExecutionSiteCloseFailed,
  recordRetainedExecutionSiteCloseStarted,
  recordRetainedExecutionSiteCloseSucceeded,
  recordRetainedExecutionSiteHoldingReleased,
  retainedExecutionSiteCloseAction,
  retainedExecutionSiteHoldingAction,
  retainExecutionSiteOperationHolding, settleExecutionSiteOperation,
  selectExecutionSiteCandidateIndex, startExecutionSiteOperation} from
  './execution-sites.mjs';
import {createManagedSiteTransferCoordinator} from './managed-site-transfer.mjs';
import {storeCompletedResultPublicationPayload} from './durable-result-payload.mjs';
import {publishCompletedEffectFreeRun} from './completed-run-publication.mjs';
import {prepareCompletedEffectFreeRunPublication} from './run-publication-preflight.mjs';
import {ExecutionAuthorizationError, missingAuthorizationGate} from './authorization-gate.mjs';
import {projectTaskObservation, projectTaskLogicalObservation} from './task-observation.mjs';
import {ledgerUsageSnapshotHasPendingResources} from './ledger-usage.mjs';

import type {SynchronousRuntimeData} from './runtime-result.mjs';
import type {withManagedOutputRows} from '../store-local/managed-memory-representations.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type CommonObject = Extract<SynchronousRuntimeData, object>;
type SiteOperation = ReturnType<typeof startExecutionSiteOperation>;
type SiteInstallation = ReturnType<typeof installExecutionSites>;
type SiteInput = NonNullable<Parameters<typeof executionSiteCandidate>[0]>['inputs'][number];
type SiteCandidate = Extract<ReturnType<typeof executionSiteCandidate>, {excluded: undefined}>;
type SiteDescription = ReturnType<typeof executionSiteDescription>;
type SuccessProgress = ReturnType<typeof beginExecutionSiteHostTaskSuccess>;
type CleanupStatus = Readonly<{pending?: unknown; errors?: unknown}>;
type CleanupHandle = Readonly<{status(): CleanupStatus | undefined; retry(): Awaitable<unknown>}>;
type SiteInstallationCleanup = Readonly<{status(): CleanupStatus | undefined; retry(): SynchronousRuntimeData}>;
type RememberCleanup = (error: unknown, releaseOwner?: object) => void;
type CloseOwner = Readonly<{
  close?(): unknown;
  afterFailure?(error: unknown, remember: RememberCleanup): SynchronousRuntimeData;
}>;
type RowConsumer = Parameters<typeof withManagedOutputRows>[1];
type RetainedRead = (accept: RowConsumer, signal?: AbortSignal) => Awaitable<unknown>;
type RetainedRows = <Value>(accept: RowConsumer, signal: AbortSignal | undefined, commit: () => Value) => ReturnType<typeof withManagedOutputRows<Value>>;
type DispatchResult = CloseOwner & Readonly<{
  status?: string;
  checkpoint?: object | null;
  cleanupPending?: unknown;
  completed?: unknown;
  material?: object | null;
  carrierMaterial?: object | null;
  siteMaterial?: object | null;
  materialGeneration?: object | null;
  publicationOutput?: unknown;
  diagnostic?: Readonly<Record<string, unknown>>;
  withRows?: RetainedRows;
  readRetained?: RetainedRead;
  refreshCompletedScratch?(): Awaitable<unknown>;
}>;
type ManagedOutput = SiteInput & Readonly<{
  completed: unknown;
  carrierMaterial?: object | null;
  scratchOwner: DispatchResult;
  withRows?: RetainedRows;
  close?: CloseOwner['close'];
  releaseOwner?: CloseOwner;
}>;
type TransferCore = Parameters<typeof createManagedSiteTransferCoordinator>[1];
type SiteResolution = Pick<Awaited<ReturnType<ReturnType<typeof createManagedSiteTransferCoordinator>['resolve']>>, 'materials'> &
  Readonly<{records: readonly unknown[]}>;
type ResolveSiteInputs = (inputs: readonly unknown[], signal?: AbortSignal) => Promise<SiteResolution>;
type PreparedTask = Readonly<{
  task: number;
  durationMilliseconds: bigint | null;
  acceptsSiteTransfer?: boolean;
  siteCapacity?: SiteCandidate['capacity'];
  inputs?: readonly object[];
  outputs?: ReadonlyMap<number, Partial<ManagedOutput>>;
  releasableProducers?: readonly number[];
}>;
type ReleasingTask = Omit<PreparedTask, 'outputs'> & {outputs?: Map<number, ManagedOutput>};
type SiteTask = Readonly<{
  task: number;
  executionSite?: object;
  resolveSiteInputs?: ResolveSiteInputs;
  siteCompletionReady?(): boolean;
}>;
type CompletionPermit = Readonly<{isAvailable(): boolean; assertAvailable(): undefined}>;
export type RelationSampleControl = Readonly<{
  owner: object | undefined;
  profile: object | undefined;
  maxWireBytes: number;
  maxNodes: number;
  maxDepth: number;
  current(): boolean;
  adopt(prefix: object): void;
}>;
type TaskControl = Readonly<{
  phase(setup: object): unknown;
  waitForResume(setup: object, signal: AbortSignal): Promise<unknown>;
}>;
type PhysicalSource = Pick<ManagedOutput, 'completed' | 'material' | 'withRows'>;
type Contribution = Readonly<{
  registration: CommonObject;
  managedSelectionKey?: string;
  run(task: unknown, signal?: AbortSignal, permit?: CompletionPermit): Awaitable<DispatchResult | null | undefined>;
  prepareNext?(outputs: ReadonlyMap<number, ManagedOutput>): Awaitable<PreparedTask | null | undefined>;
  runPrepared?(task: SiteTask, signal?: AbortSignal, relationSample?: RelationSampleControl): Awaitable<DispatchResult | null | undefined>;
  relationSample?: boolean;
  beforeNext?(physicalSource: (task: number) => PhysicalSource | undefined): Awaitable<unknown>;
  finish?(): Awaitable<unknown>;
}>;
type CompletedTask = Readonly<{
  task: number;
  executionSite: SiteDescription;
  taskElapsedMilliseconds: number;
  plannerObserverMilliseconds?: number;
  [key: string]: unknown;
}>;
type CandidateFact = Readonly<{
  task: number;
  registrationKey?: string;
  site: SiteDescription;
  scope?: string;
}>;
type CandidateComparison = CandidateFact & Readonly<{durationMilliseconds: bigint}>;
type CandidateExclusion = CandidateFact & Readonly<{reason: string}>;
type PublicationDefinition = Readonly<{name: string; identity: string; wire: string}>;
type ResultOccurrence = Readonly<{
  name: string;
  task: number;
  definition: Readonly<{result_definition_cid: string}>;
  definitionContract: unknown;
}>;
type CheckedResultOccurrence = Pick<ResultOccurrence, 'name' | 'task'>;
type PublicationInventory = Readonly<{
  programDefinitionCid: string | undefined;
  occurrences: readonly ResultOccurrence[];
  requestInventory: readonly Readonly<{result_name: string; result_definition_cid: string}>[];
}>;
type PublicationPayloadStore = Parameters<typeof storeCompletedResultPublicationPayload>[0];
type PublicationPayload = Awaited<ReturnType<typeof storeCompletedResultPublicationPayload>>;
type PayloadExportControl = Parameters<typeof storeCompletedResultPublicationPayload>[1];
type PayloadLimits = Parameters<typeof storeCompletedResultPublicationPayload>[4];
type PayloadPublication = Parameters<typeof storeCompletedResultPublicationPayload>[5];
type ExportHandle = Awaited<ReturnType<PayloadExportControl['beginResult']>>;
type OutputExportControl = PayloadExportControl & Readonly<{
  beginManagedResultImport(host: object, result: number, completed: unknown, material: object, limits: unknown): CommonObject;
  appendManagedResultImport(importing: unknown, row: string, limits: unknown): SynchronousRuntimeData;
  finishManagedResultImport(importing: unknown, signal: AbortSignal | undefined, progress: unknown): Awaitable<ExportHandle>;
  transformManagedResultImport(importing: unknown, transformation: unknown, signal: AbortSignal | undefined, progress: unknown): Awaitable<ExportHandle>;
  cancelManagedResultImport(importing: unknown): SynchronousRuntimeData;
}>;
type Core = Readonly<{
  siteControl: unknown;
  requireActivation?(setup: object): SynchronousRuntimeData;
  coverActivation?(setup: object, task: number): boolean;
  authorizeActivation?(setup: object, task: number, decision: unknown): boolean;
  programDefinitionCid?(setup: object): string | undefined;
  programHasEffects?(setup: object): boolean;
  resultInventory?(setup: object): readonly ResultOccurrence[];
  count(setup: object): number;
  next(setup: object, observeFailure: unknown): CommonObject | null | undefined;
  nextTask?(setup: object): number;
  task?(dispatch: unknown): number;
  registration?(dispatch: unknown): CommonObject | null | undefined;
  managedProducers?(setup: object): readonly number[];
  selectManaged?(setup: object, task: number, registration: unknown): boolean;
  taskCapacity(setup: object, task: number): unknown;
  completed(setup: object, task: number): boolean;
  managedMatches?(setup: object, task: number, completed: unknown): boolean;
  managedCarrierMatches?(setup: object, task: number, completed: unknown): boolean;
  finished(setup: object): boolean;
  stop(setup: object): SynchronousRuntimeData;
  closeOutputs(setup: object): SynchronousRuntimeData;
  usage(setup: object): CommonObject;
  explain(setup: object, maxBytes: number, maxNodes: number): SynchronousRuntimeData;
  output(setup: object, task: number): CommonObject | null | undefined;
  preparationUsageIsolated?(setup: object, holder: unknown): boolean;
  outputExportControl?: OutputExportControl;
  publicationControl?: Readonly<{issueResultArtifact?: unknown}>;
}>;
type ActivationScope = Readonly<{connection: string; resource: string; operation: 'write'}>;
type Authorization = Readonly<{
  authorize(boundary: 'activation' | 'transfer', scope: ActivationScope,
    options: Readonly<{subjectCid: string | undefined; signal: AbortSignal | undefined}>):
    Awaitable<Readonly<{action: string; runtimeDecision?: unknown}>>;
  cover(boundary: 'activation' | 'transfer', scope: ActivationScope): SynchronousRuntimeData;
  isProtectedSite(key: string): boolean;
}>;
type CompletionEvent = Readonly<{task: number; output: unknown; readRetained?: RetainedRead}>;
type TaskStartEvent = Readonly<{
  task: number;
  registrationKey: string | undefined;
  managed: boolean;
  executionSite: SiteDescription;
  explanation: unknown;
  usage: object;
}>;
type ResultPublication = Readonly<{
  outputLimits?: unknown;
  contractLimits?: unknown;
  runDefinition?: unknown;
  invocation?: unknown;
  retention?: unknown;
  evidenceContext?: unknown;
  transformation?: unknown;
  resultProgress?: unknown;
}>;
type PreflightOwner = ReturnType<typeof preflightSetupCleanup>;
type PreflightCleanupOptions = Readonly<{
  core: Core;
  setup: object;
  siteCleanup?: SiteInstallationCleanup;
  preparationHolder?: unknown;
}>;
type RetainPreflightCleanup = (owner: PreflightOwner) => SynchronousRuntimeData;
type PreflightEvent = Readonly<{
  programDefinitionCid: string | undefined;
  resultInventory: readonly CheckedResultOccurrence[];
  publicationInventory: PublicationInventory | undefined;
  publicationControl: Core['publicationControl'];
}>;
type StrategyOptions = Readonly<{
  setup: object;
  runtime: Readonly<{
    core: Core;
    contributions: readonly Contribution[];
    sitePolicy?: object;
    observeFailure?: unknown;
    authorization?: Authorization;
  }>;
  control?: Readonly<{
    signal?: AbortSignal;
    observeCompletion?: (event: CompletionEvent) => Awaitable<unknown>;
    observeTaskStart?: (event: TaskStartEvent) => Awaitable<unknown>;
    taskObservation?: object;
    relationSample?: RelationSampleControl;
    taskControl?: TaskControl;
  }>;
  publication?: Readonly<{beforeCompute?: (event: PreflightEvent) => Awaitable<unknown>}>;
  cleanup?: Readonly<{retainPreflightCleanup?: RetainPreflightCleanup; preparationHolder?: unknown}>;
}>;
type InstalledExecution = Readonly<{
  status: 'host-tasks-waiting' | 'host-tasks-failed' | 'host-tasks-completed';
  checkpoint?: object;
  failure: unknown;
  completed: readonly CompletedTask[];
  candidateExclusions: readonly CandidateExclusion[];
  candidateComparisons: readonly CandidateComparison[];
  programDefinitionCid: string | undefined;
  resultInventory: readonly CheckedResultOccurrence[];
  publicationInventory: PublicationInventory | undefined;
  publicationPreflight?: unknown;
  publishEffectFreeRun(store: unknown, publication: unknown, signal?: AbortSignal, resource?: unknown): Promise<unknown>;
  storePublicationResult(result: number, store: unknown, publication: ResultPublication, signal?: AbortSignal, resource?: unknown):
    Promise<PublicationPayload & Readonly<{occurrence: Readonly<{name: string; task: number; definition: unknown}>}>>;
  refreshCompletedScratch(): Promise<void>;
  usage(): object;
  cleanupPending(): boolean;
  cleanup(): Promise<boolean>;
  explain(maxBytes?: number, maxNodes?: number): unknown;
  output(task: number): unknown;
  effectPhysicalSource(task: number): PhysicalSource | undefined;
  close(): Promise<void> | undefined;
}>;

export class StrategyHostError extends Error {
  declare code: string;
  declare primaryFailure?: unknown;
  declare primaryDiagnostic?: unknown;
  declare cleanupErrors: readonly unknown[];
  declare cleanupPending?: boolean;
  declare cleanupHandle?: unknown;

  constructor(code: string) { super(code); this.code = code; }
}

const active = new WeakSet<object>();
const releasedPreflightSetups = new WeakSet<object>();
const publicationContract = (value: unknown): value is PublicationDefinition => value !== null &&
  typeof value === 'object' && typeof (value as PublicationDefinition).name === 'string' &&
  typeof (value as PublicationDefinition).identity === 'string' && typeof (value as PublicationDefinition).wire === 'string';
const failureMember = (value: unknown, name: string): unknown => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? (value as Record<string, unknown>)[name] : undefined;
  } catch { return undefined; }
};

function ownedStrategyFailure(reason: unknown, fallbackCode: string) {
  const code = typeof failureMember(reason, 'code') === 'string'
    ? failureMember(reason, 'code') as string : fallbackCode;
  const failure = new StrategyHostError(code);
  const name = failureMember(reason, 'name');
  if (typeof name === 'string') failure.name = name;
  failure.cause = reason;
  failure.primaryFailure = reason;
  try {
    const diagnostic = Object.getOwnPropertyDescriptor(reason as object, 'primaryDiagnostic');
    if (diagnostic !== undefined && Object.hasOwn(diagnostic, 'value')) {
      failure.primaryDiagnostic = diagnostic.value;
    }
  } catch { /* Optional DATA cannot replace the original thrown value. */ }
  const errors = failureMember(reason, 'cleanupErrors');
  failure.cleanupErrors = Object.freeze(
    Array.isArray(errors) ? [...errors] : [],
  );
  return failure;
}

// A Site holding describes the lifetime of the concrete retained result, not
// merely the JavaScript wrapper returned by a contribution. This adapter
// deliberately preserves the contribution's synchronous/asynchronous close
// behavior and original thrown value. Its separate cleanup observer releases
// the Site holding only after an explicit underlying recovery handle confirms
// physical reclamation.
function retainSiteResult(operation: SiteOperation, result: DispatchResult | null | undefined, retainedBytes: bigint) {
  const closeProgress = beginRetainedExecutionSiteClose(operation);
  const holdingProgress = beginRetainedExecutionSiteHolding(
    closeProgress,
    operation,
  );
  const holding = retainExecutionSiteOperationHolding(
    operation, result?.material ?? result, retainedBytes,
  );
  let closeResult: unknown;
  let closeFailure: unknown;
  let cleanupTracked = false;
  const release = () => {
    releaseExecutionSiteHolding(holding);
    recordRetainedExecutionSiteHoldingReleased(holdingProgress);
  };
  const progress = () => {
    let action = strategyAction.holding(retainedExecutionSiteHoldingAction(holdingProgress));
    if (action === 'RetainedSiteReleaseHolding') {
      release();
      action = strategyAction.holding(retainedExecutionSiteHoldingAction(holdingProgress));
    }
    if (action === 'RetainedSiteHoldingInvalid') {
      throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
    }
    return action;
  };
  return Object.freeze({
    status: () => Object.freeze({released: progress() === 'RetainedSiteHoldingFinished'}),
    close() {
      const action = progress();
      if (action === 'RetainedSiteHoldingFinished' ||
          action === 'RetainedSiteAwaitClose' ||
          action === 'RetainedSiteAwaitCleanup') return closeResult;
      if (action !== 'RetainedSiteStartClose') {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
      recordRetainedExecutionSiteCloseStarted(closeProgress);
      try {
        closeResult = typeof result?.close === 'function'
          ? result.close() : undefined;
      }
      catch (reason) {
        closeFailure = reason;
        recordRetainedExecutionSiteCloseFailed(closeProgress);
        progress();
        throw reason;
      }
      if (closeResult != null && typeof (closeResult as PromiseLike<unknown>).then === 'function') {
        closeResult = Promise.resolve(closeResult).then(
          value => {
            recordRetainedExecutionSiteCloseSucceeded(closeProgress);
            progress();
            return value;
          },
          reason => {
            closeFailure = reason;
            recordRetainedExecutionSiteCloseFailed(closeProgress);
            progress();
            throw reason;
          },
        );
      } else {
        recordRetainedExecutionSiteCloseSucceeded(closeProgress);
        progress();
      }
      return closeResult;
    },
    afterFailure(reason: unknown, remember: RememberCleanup) {
      if (cleanupTracked || progress() === 'RetainedSiteHoldingFinished' ||
          reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle') as CleanupHandle | undefined;
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      recordRetainedExecutionSiteCleanupAuthority(closeProgress);
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream!.status();
          if (value?.pending === false) {
            recordRetainedExecutionSiteCleanupStopped(closeProgress);
          }
          return Object.freeze({
            pending: progress() !== 'RetainedSiteHoldingFinished',
            errors: Object.freeze(Array.isArray(value?.errors)
              ? [...value.errors] : []),
          });
        } catch (error) {
          return Object.freeze({pending: true, errors: Object.freeze([error])});
        }
      };
      const cleanupHandle = Object.freeze({
        status: state,
        async retry() { return state(); },
      });
      remember(Object.assign(new Error('ExecutionSiteCleanupPending'), {
        cleanupPending: true,
        cleanupHandle,
      }), cleanupHandle);
    },
  });
}

// Core-owned synchronous outputs have no connector close callback. Keep their
// Site holdings through the exact common output lifetime and release them only
// after the Core close succeeds or its explicit cleanup handle confirms it.
function coreOutputSiteOwner(core: Core, setup: object, siteInstallation: SiteInstallation) {
  const retained = new Map<ReturnType<typeof retainExecutionSiteOperationHolding>, ReturnType<typeof beginRetainedExecutionSiteHolding>>();
  const closeProgress = beginRetainedExecutionSiteClose(siteInstallation);
  let closeFailure: unknown;
  let cleanupTracked = false;
  const progress = () => {
    for (const [holding, holdingProgress] of retained) {
      const action = strategyAction.holding(retainedExecutionSiteHoldingAction(holdingProgress));
      if (action === 'RetainedSiteReleaseHolding') {
        releaseExecutionSiteHolding(holding);
        recordRetainedExecutionSiteHoldingReleased(holdingProgress);
        retained.delete(holding);
      }
      if (action === 'RetainedSiteHoldingInvalid') {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
    }
  };
  return Object.freeze({
    retain(operation: SiteOperation, value: unknown, retainedBytes: bigint) {
      const holding = retainExecutionSiteOperationHolding(
        operation, value, retainedBytes,
      );
      try {
        retained.set(holding, beginRetainedExecutionSiteHolding(
          closeProgress,
          operation,
        ));
      } catch (error) {
        releaseExecutionSiteHolding(holding);
        throw error;
      }
    },
    close() {
      const action = strategyAction.close(retainedExecutionSiteCloseAction(closeProgress));
      if (action === 'RetainedSiteCloseAwaitPhysical' ||
          action === 'RetainedSiteCloseAwaitCleanup' ||
          action === 'RetainedSiteCloseFinished') return;
      if (action !== 'RetainedSiteCloseStart') {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
      progress();
      recordRetainedExecutionSiteCloseStarted(closeProgress);
      try { core.closeOutputs(setup); }
      catch (reason) {
        closeFailure = reason;
        recordRetainedExecutionSiteCloseFailed(closeProgress);
        progress();
        throw reason;
      }
      recordRetainedExecutionSiteCloseSucceeded(closeProgress);
      progress();
    },
    afterFailure(reason: unknown, remember: RememberCleanup) {
      if (cleanupTracked || retained.size === 0 || reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle') as CleanupHandle | undefined;
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      recordRetainedExecutionSiteCleanupAuthority(closeProgress);
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream!.status();
          if (value?.pending === false) {
            recordRetainedExecutionSiteCleanupStopped(closeProgress);
          }
          progress();
          return Object.freeze({
            pending: retained.size !== 0,
            errors: Object.freeze(Array.isArray(value?.errors)
              ? [...value.errors] : []),
          });
        } catch (error) {
          return Object.freeze({pending: true, errors: Object.freeze([error])});
        }
      };
      const cleanupHandle = Object.freeze({
        status: state,
        async retry() {
          if (state().pending && typeof failureMember(upstream, 'retry') ===
              'function') {
            await upstream!.retry();
          }
          return state();
        },
      });
      remember(Object.assign(new Error('ExecutionSiteCleanupPending'), {
        cleanupPending: true,
        cleanupHandle,
      }), cleanupHandle);
    },
  });
}

// This owner exists only after immutable preflight refuses, before any
// Compute contribution has entered. It owns this exact setup, not an execution
// or a Result. Successful stop/output-close steps are never repeated.
function preflightSetupCleanup({core, setup, siteCleanup, preparationHolder}: PreflightCleanupOptions) {
  let stopped = false, outputsClosed = false, released = false;
  let closeAttempted = false, closeFailed = false, closeFailure: unknown;
  let cleanupFailure: unknown;
  const settle = () => {
    if (released) return true;
    try {
      if (!stopped) { core.stop(setup); stopped = true; }
      if (!outputsClosed) { core.closeOutputs(setup); outputsClosed = true; }
      if (siteCleanup !== undefined && siteCleanup.status()?.pending !== false) {
        // Preserve the same partial-installation carrier. Setup retirement is
        // insufficient while an already-created Site still owns cleanup.
        siteCleanup.retry();
        if (siteCleanup.status()?.pending !== false) {
          throw new StrategyHostError('ExecutionSiteCleanupPending');
        }
      }
      const usage = core.usage(setup);
      if (ledgerUsageSnapshotHasPendingResources(usage) &&
          !(preparationHolder !== undefined && core.preparationUsageIsolated?.(setup, preparationHolder) === true)) {
        throw new StrategyHostError('PublicationPreflightCleanupPending');
      }
      released = true;
      active.delete(setup);
      releasedPreflightSetups.add(setup);
      return true;
    } catch (error) { cleanupFailure = error; throw error; }
  };
  const status = () => Object.freeze({pending: !released,
    errors: Object.freeze(released ? [] : [cleanupFailure])});
  return Object.freeze({
    close() {
      if (released) return;
      if (closeAttempted) {
        if (closeFailed) throw closeFailure;
        return;
      }
      closeAttempted = true;
      try { settle(); }
      catch (error) { closeFailed = true; closeFailure = error; throw error; }
    },
    cleanup: settle,
    cleanupPending: () => !released,
    status,
    retry() { settle(); return status(); },
  });
}

// One installed receiver owns both the refused setup and any partial Site
// installation. Exception wrappers are not the custody transport.
function rejectSetupPreflight({primary, core, setup, retainPreflightCleanup, siteCleanup, preparationHolder}:
  PreflightCleanupOptions & Readonly<{primary: unknown; retainPreflightCleanup?: RetainPreflightCleanup}>): never {
  if (retainPreflightCleanup !== undefined) {
    const owner = preflightSetupCleanup({core, setup, siteCleanup, preparationHolder});
    // The installed receiver consumes its pending setup synchronously, before
    // this owner may stop it. A refused handoff grants no stop observation.
    try { retainPreflightCleanup(owner); }
    catch (handoffFailure) {
      const failure = ownedStrategyFailure(primary, 'PublicationPreflightFailed');
      failure.cleanupPending = true;
      failure.cleanupErrors = Object.freeze([...failure.cleanupErrors, handoffFailure]);
      throw failure;
    }
    try { owner.close(); }
    catch (cleanupFailure) {
      const failure = ownedStrategyFailure(primary, 'PublicationPreflightFailed');
      failure.cleanupPending = true;
      failure.cleanupErrors = Object.freeze([...failure.cleanupErrors, cleanupFailure]);
      failure.cleanupHandle = owner;
      throw failure;
    }
    throw primary;
  }
  let stopFailed = false;
  let stopFailure;
  try { core.stop(setup); }
  catch (error) {
    stopFailed = true;
    stopFailure = error;
  }
  active.delete(setup);
  if (!stopFailed) throw primary;
  const failure = ownedStrategyFailure(
    primary,
    'PublicationPreflightFailed',
  );
  failure.cleanupPending = true;
  failure.cleanupErrors = Object.freeze([
    ...failure.cleanupErrors,
    stopFailure,
  ]);
  const cleanupHandle = failureMember(stopFailure, 'cleanupHandle');
  if (cleanupHandle !== undefined) failure.cleanupHandle = cleanupHandle;
  throw failure;
}

// Trusted internal composition only. Public Node options are separately
// snapshotted; they never supply this runtime or these admission callbacks.
export async function runInstalledStrategy({
  setup,
  runtime: {core, contributions, sitePolicy, observeFailure,
    authorization = missingAuthorizationGate()},
  control: {signal, observeCompletion, observeTaskStart, taskObservation, relationSample, taskControl} = {},
  publication: {beforeCompute} = {},
  cleanup: {retainPreflightCleanup, preparationHolder} = {},
}: StrategyOptions): Promise<InstalledExecution> {
  if (retainPreflightCleanup !== undefined && typeof retainPreflightCleanup !== 'function') {
    throw new StrategyHostError('InvalidPreflightCleanupReceiver');
  }
  if (observeCompletion !== undefined && typeof observeCompletion !== 'function') {
    throw new StrategyHostError('InvalidCompletionObserver');
  }
  if (observeTaskStart !== undefined && typeof observeTaskStart !== 'function') {
    throw new StrategyHostError('InvalidTaskStartObserver');
  }
  if (taskControl !== undefined && (typeof taskControl?.phase !== 'function' ||
      typeof taskControl?.waitForResume !== 'function' || signal === undefined)) {
    throw new StrategyHostError('InvalidInstalledTaskController');
  }
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function' ||
      typeof authorization.cover !== 'function' ||
      typeof authorization.isProtectedSite !== 'function') {
    throw new StrategyHostError('InvalidAuthorizationGate');
  }
  if (active.has(setup)) throw new StrategyHostError('StrategyAlreadyRunning');
  if (releasedPreflightSetups.has(setup)) throw new StrategyHostError('ReleasedStrategy');
  core = Object.freeze({ ...core });
  // Seal the per-task activation requirement before any implementation can
  // start a task. Every start below consumes an exact grant for its task.
  core.requireActivation?.(setup);
  if (beforeCompute !== undefined && typeof beforeCompute !== 'function') {
    throw new StrategyHostError('InvalidBeforeComputeAdmission');
  }
  const programDefinitionCid = core.programDefinitionCid?.(setup);
  const programHasEffects = core.programHasEffects?.(setup) === true;
  const resultInventory = core.resultInventory?.(setup) ?? [];
  if (!Array.isArray(resultInventory) ||
      ((resultInventory.length > 0 || programHasEffects) && programDefinitionCid === undefined)) {
    throw new StrategyHostError('InvalidCheckedResultInventory');
  }
  const checkedResultInventory = Object.freeze(resultInventory.map(result =>
    Object.freeze({name: result.name, task: result.task})));
  const publicationInventory = checkedResultInventory.length === 0 && !programHasEffects
    ? undefined
    : Object.freeze({
      programDefinitionCid,
      occurrences: Object.freeze(resultInventory.map(result =>
        Object.freeze({
          name: result.name,
          task: result.task,
          definition: result.definition,
          definitionContract: result.definitionContract,
        }))),
      requestInventory: Object.freeze(resultInventory.map(result =>
        Object.freeze({
          result_name: result.name,
          result_definition_cid: result.definition.result_definition_cid,
        }))),
    });
  active.add(setup);
  let preflight: unknown;
  try {
    if (beforeCompute !== undefined) {
      signal?.throwIfAborted();
      preflight = await beforeCompute(Object.freeze({
        programDefinitionCid,
        resultInventory: checkedResultInventory,
        publicationInventory,
        publicationControl: core.publicationControl,
      }));
      signal?.throwIfAborted();
    }
  } catch (primary) {
    rejectSetupPreflight({primary, core, setup, retainPreflightCleanup, preparationHolder});
  }
  // Snapshot the implementation set before invoking any implementation. Opaque
  // registration object identity, never a display name, selects the driver.
  const installed = new Map<unknown, Contribution>();
  for (const entry of contributions) {
    if (entry.registration == null || installed.has(entry.registration) ||
        typeof entry.run !== 'function') {
      throw new StrategyHostError('InvalidStrategyInstallation');
    }
    installed.set(entry.registration, Object.freeze({
      registration: entry.registration,
      run: entry.run,
      prepareNext: entry.prepareNext,
      runPrepared: entry.runPrepared,
      relationSample: entry.relationSample,
      managedSelectionKey: entry.managedSelectionKey,
      beforeNext: entry.beforeNext,
      finish: entry.finish,
    }));
  }
  let siteInstallation;
  try {
    siteInstallation = installExecutionSites(
      sitePolicy ?? prepareSingleExecutionSitePolicy(),
      [...installed.values()],
      core.siteControl,
    );
  } catch (primary) {
    const siteCleanup = failureMember(primary, 'cleanupHandle') as SiteInstallationCleanup | undefined;
    if (retainPreflightCleanup === undefined ||
        typeof failureMember(siteCleanup, 'status') !== 'function' ||
        typeof failureMember(siteCleanup, 'retry') !== 'function') throw primary;
    rejectSetupPreflight({primary, core, setup, retainPreflightCleanup, siteCleanup, preparationHolder});
  }
  const transfers = createManagedSiteTransferCoordinator(
    setup, core as Core & TransferCore, siteInstallation, {
      authorization,
      subjectCid: programDefinitionCid,
    },
  );
  // Every activation is proven inside the admitted envelope by a cheap local
  // check: an unprotected in-process Site running pure compute over captured
  // inputs is covered without evaluation; a Host-declared protected Site needs
  // an evaluated dispatch decision for its exact scope (reused per Run, never
  // widened). No per-row callback, bulk pass or extra hashing.
  const authorizeActivation = async (site: object, entry: Contribution, index: number) => {
    const siteKey = executionSiteDescription(site).key;
    const scope = Object.freeze({
      connection: siteKey,
      resource: entry.managedSelectionKey ?? 'installed-strategy',
      operation: 'write',
    });
    if (!authorization.isProtectedSite(siteKey)) {
      authorization.cover('activation', scope);
      if (typeof core.coverActivation === 'function' &&
          core.coverActivation(setup, index) !== true) {
        throw new StrategyHostError('ActivationGrantRejected');
      }
      return;
    }
    const decision = await authorization.authorize('activation', scope, {
      subjectCid: programDefinitionCid,
      signal,
    });
    if (decision.action !== 'dispatch') {
      throw new ExecutionAuthorizationError(decision);
    }
    signal?.throwIfAborted();
    if (typeof core.requireActivation === 'function' &&
        (typeof core.authorizeActivation !== 'function' ||
          core.authorizeActivation(setup, index, decision.runtimeDecision) !==
            true)) {
      throw new StrategyHostError('ActivationGrantRejected');
    }
  };
  const coreSiteOutputs = coreOutputSiteOwner(core, setup, siteInstallation);
  // A contribution that explicitly reports unconfirmed cleanup without a
  // usable status authority cannot release its Site operation. There is no
  // safe retry to invent, but the reservation and teardown responsibility
  // must remain visible.
  const unconfirmedSiteOperations = new Set<SiteOperation>();
  const settleSiteAfterFailure = (
    operation: SiteOperation,
    error: unknown,
    alreadySettled = false,
  ) => {
    const cleanupRequired = failureMember(error, 'cleanupPending') === true;
    const upstream = failureMember(error, 'cleanupHandle') as CleanupHandle | undefined;
    const failureProgress = beginFailedExecutionSiteOperation(
      operation,
      cleanupRequired,
      alreadySettled,
    );
    const drive = (cleanupStopped: boolean) => {
      if (cleanupRequired && cleanupStopped) {
        recordFailedExecutionSiteOperationStop(operation, failureProgress);
      }
      const action = strategyAction.failure(failedExecutionSiteOperationAction(
        operation,
        failureProgress,
      ));
      if (action === 'FailedSiteSettle') {
        settleExecutionSiteOperation(operation);
        recordFailedExecutionSiteOperationSettlement(
          operation,
          failureProgress,
        );
        return strategyAction.failure(failedExecutionSiteOperationAction(
          operation,
          failureProgress,
        ));
      }
      return action;
    };
    if (!cleanupRequired) {
      drive(true);
      return error;
    }
    const failure = ownedStrategyFailure(error, 'StrategyExecutionFailed');
    if (typeof failureMember(upstream, 'status') !== 'function') {
      drive(false);
      unconfirmedSiteOperations.add(operation);
      failure.cleanupPending = true;
      return failure;
    }
    const combined = Object.freeze({
      status() {
        let state;
        try { state = upstream!.status(); }
        catch (failure) {
          return Object.freeze({pending: true, errors: Object.freeze([failure])});
        }
        const errors = Array.isArray(state?.errors) ? [...state.errors] : [];
        let action;
        try { action = drive(state?.pending === false); }
        catch (error) {
          errors.push(error);
          action = 'FailedSiteAwaitStop';
        }
        return Object.freeze({
          pending: action !== 'FailedSiteFinished',
          errors: Object.freeze(errors),
        });
      },
      async retry() {
        if (upstream!.status()?.pending !== false &&
            typeof upstream!.retry === 'function') await upstream!.retry();
        return combined.status();
      },
    });
    failure.cleanupHandle = combined;
    failure.cleanupPending = combined.status().pending;
    return failure;
  };
  const completed: CompletedTask[] = [];
  const candidateExclusions: CandidateExclusion[] = [];
  const candidateComparisons: CandidateComparison[] = [];
  const outputs: ReturnType<typeof retainSiteResult>[] = [];
  const managedOutputs = new Map<number, ManagedOutput>();
  const publicationOutputs = new Map<number, unknown>();
  const pendingCleanup = new Set<CleanupHandle>();
  const pendingCloses = new Set<Promise<unknown>>();
  // A release without a recovery handle has no safe implicit retry contract.
  // Retain its owner and report unknown cleanup rather than forgetting it.
  const unconfirmedRelease = new Set<object>();
  let cleanupInFlight: Promise<boolean> | undefined;
  let refreshingCompletedScratch = false;
  let failed = false;
  let failure: unknown;
  let checkpointPause: object | undefined;
  let closed = false;
  let closeResult: Promise<void> | undefined;
  const rememberCleanup: RememberCleanup = (error, releaseOwner) => {
    const handle = (error as {cleanupHandle?: CleanupHandle} | null | undefined)?.cleanupHandle;
    if (handle && typeof handle.status === 'function' && typeof handle.retry === 'function') {
      pendingCleanup.add(handle);
    } else if (releaseOwner) {
      unconfirmedRelease.add(releaseOwner);
    }
  };
  const rememberFailure: RememberCleanup = (error, releaseOwner) => {
    if (!failed) failure = error;
    failed = true;
    rememberCleanup(error, releaseOwner);
  };
  const rememberOwnedReleaseFailure = (error: unknown, owner?: CloseOwner) => {
    rememberCleanup(error, owner);
    owner?.afterFailure?.(error, rememberCleanup);
  };
  const releaseOwnedResult = (owner?: CloseOwner) => {
    try {
      const result = owner?.close?.();
      return result != null && typeof (result as PromiseLike<unknown>).then === 'function'
        ? Promise.resolve(result).catch(error => {
          rememberOwnedReleaseFailure(error, owner);
          throw error;
        })
        : result;
    } catch (error) {
      rememberOwnedReleaseFailure(error, owner);
      throw error;
    }
  };
  const knownCleanupPending = () => {
    for (const handle of pendingCleanup) {
      try { if (handle.status()!.pending) return true; }
      catch { return true; }
    }
    return false;
  };
  const cleanupPending = () => executionSiteHostCleanupPending(
    siteInstallation,
    pendingCloses.size !== 0,
    knownCleanupPending(),
    unconfirmedRelease.size !== 0 || unconfirmedSiteOperations.size !== 0,
  );
  // Borrow only a completed physical record already retained by this Host.
  // The receiving Core Result pin still checks its exact occurrence/material.
  const managedPhysicalSource = (task: number) => {
    if (closed || failed || !Number.isSafeInteger(task) || task < 0 || task >= core.count(setup)) {
      throw new StrategyHostError('InvalidEffectPhysicalSource');
    }
    const source = managedOutputs.get(task);
    return source === undefined || typeof source.withRows !== 'function' ? undefined
      : Object.freeze({completed: source.completed, material: source.material, withRows: source.withRows});
  };
  // The original controller owns phase and wakes its own paused Driver on
  // a command. Re-read the actual phase after the wake before selecting work.
  const awaitRunnable = taskControl === undefined || signal === undefined ? undefined : async () => {
    signal.throwIfAborted();
    let phase = taskControl.phase(setup);
    if (phase === 'paused') {
      await taskControl.waitForResume(setup, signal);
      signal.throwIfAborted();
      phase = taskControl.phase(setup);
    }
    if (phase !== 'runnable') throw new StrategyHostError('InstalledTaskControllerNotRunnable');
  };
  let firstTask = 1;
  try {
    const count = core.count(setup);
    if (awaitRunnable !== undefined && !core.finished(setup)) await awaitRunnable();
    if (core.nextTask?.(setup) === 0) firstTask = 0;
    // Captured Acquisition starts at task one; a checked source-free root
    // starts at task zero and uses the same managed task lifecycle.
    for (let step = firstTask; step < count; step++) {
      signal?.throwIfAborted();
      if (awaitRunnable !== undefined && step !== firstTask && !core.finished(setup)) await awaitRunnable();
      for (const entry of installed.values()) {
        signal?.throwIfAborted();
        await entry.beforeNext?.(managedPhysicalSource);
        // Even an absent callback yields to the caller. Cancellation during
        // preparation must not authorize another callback or a fresh attempt.
        signal?.throwIfAborted();
      }
      signal?.throwIfAborted();
      const managedInputs = core.managedProducers?.(setup) ?? [];
      const prepared: {entry: Contribution; task: PreparedTask; siteCandidate: SiteCandidate}[] = [];
      const excludedManagedCandidateCodes: number[] = [];
      for (const entry of installed.values()) {
        const task = await entry.prepareNext?.(managedOutputs);
        if (task == null) continue;
        for (const site of executionSitePlacements(siteInstallation, entry)) {
          const siteCandidate = executionSiteCandidate({
            installation: siteInstallation,
            contribution: entry,
            site,
            task: task.task,
            registration: entry.registration,
            inputs: Array.isArray(task.inputs) ? task.inputs as readonly SiteInput[] : [],
            durationMilliseconds: task.durationMilliseconds,
            acceptsSiteTransfer: task.acceptsSiteTransfer === true,
            capacity: task.siteCapacity,
          });
          if (siteCandidate && siteCandidate.excluded === undefined) {
            prepared.push({entry, task, siteCandidate});
            candidateComparisons.push(Object.freeze({
              task: task.task,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              durationMilliseconds: siteCandidate.durationMilliseconds,
            }));
          } else {
            const reason = siteCandidate?.excluded ?? 'ExecutionSiteUnavailable';
            excludedManagedCandidateCodes.push(
              siteCandidate?.exclusionCode ?? 8,
            );
            candidateExclusions.push(Object.freeze({
              task: task.task,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              reason,
            }));
          }
        }
      }
      const managedTask = prepared.length ? core.nextTask!(setup) : -1;
      for (const candidate of prepared) {
        if (candidate.task.task !== managedTask) {
          throw new StrategyHostError('InvalidManagedCandidate');
        }
      }
      const managedCandidate = prepared.length === 0 ? -1
        : selectExecutionSiteCandidateIndex(
          prepared.map(value => value.siteCandidate),
          {
            invalid: 'InvalidManagedCandidate',
            duplicate: 'DuplicateManagedSelectionKey',
          },
        );
      const managed = managedCandidate < 0
        ? undefined : prepared[managedCandidate];
      if (!managed && Array.isArray(managedInputs) && managedInputs.length !== 0) {
        const retainedInputs = managedInputs.filter(producer =>
          managedOutputs.has(producer));
        // A task whose producers are all still legacy follows the existing
        // dispatcher. Once any exact managed producer is selected, silently
        // dropping it or mixing it with a legacy reconstruction is forbidden.
        if (retainedInputs.length !== 0) {
          const outcome = strategyAction.managedFallback(classifyManagedExecutionSiteFallback(
            siteInstallation,
            retainedInputs.length,
            excludedManagedCandidateCodes,
          ));
          const code = ({
            ManagedCandidateEstimateUnavailable: 'ManagedCandidateEstimateUnavailable',
            ManagedCandidateTransferUnavailable: 'ManagedSiteTransferUnavailable',
            ManagedCandidateNoCompatibleStrategy: 'NoCompatibleManagedStrategy',
          } as Partial<Record<typeof outcome, string>>)[outcome];
          if (code === undefined) {
            throw new StrategyHostError('InvalidManagedCandidateFallback');
          }
          throw new StrategyHostError(code);
        }
      }
      const task = managed ? managed.task : core.next(setup, observeFailure);
      if (task == null) break;
      const index = managed ? (task as PreparedTask).task : core.task!(task);
      const entry = managed ? managed.entry : installed.get(core.registration!(task));
      if (!entry || (managed && typeof entry.runPrepared !== 'function')) {
        throw new StrategyHostError('MissingStrategyImplementation');
      }
      if (relationSample !== undefined && (!managed || entry.relationSample !== true)) {
        throw new StrategyHostError('ClientRunSampleDriverUnavailable');
      }
      signal?.throwIfAborted();
      if (managed && !core.selectManaged!(setup, index, managed.entry.registration)) {
        throw new StrategyHostError('ManagedSelectionRejected');
      }
      let siteCandidate = managed?.siteCandidate;
      let legacyExclusions = [];
      if (!siteCandidate) {
        const value = core.taskCapacity(setup, index);
        if (!Array.isArray(value) || value.length !== 2 ||
            value.some(item => typeof item !== 'bigint' || item < 0n)) {
          throw new StrategyHostError('InvalidExecutionSiteCapacity');
        }
        const capacity = Object.freeze({
          retainedBytes: value[0],
          executionBytes: value[1],
        });
        const placementCandidates = [];
        for (const site of executionSitePlacements(siteInstallation, entry)) {
          // The implementation and task are already fixed by the checked
          // legacy dispatcher. Its unknown execution duration is a shared
          // term, not zero work; only the known Site placement cost varies and
          // participates in this comparison.
          const candidate = executionSiteCandidate({
            installation: siteInstallation,
            contribution: entry,
            site,
            task: index,
            registration: entry.registration,
            inputs: [],
            durationMilliseconds: 0n,
            acceptsSiteTransfer: false,
            capacity,
          });
          if (candidate && candidate.excluded === undefined) {
            placementCandidates.push(candidate);
            candidateComparisons.push(Object.freeze({
              task: index,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              durationMilliseconds: candidate.durationMilliseconds,
              scope: 'selected-registration-placement',
            }));
          } else {
            const reason = candidate?.excluded ?? 'ExecutionSiteUnavailable';
            legacyExclusions.push(reason);
            candidateExclusions.push(Object.freeze({
              task: index,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              reason,
              scope: 'selected-registration-placement',
            }));
          }
        }
        const selectedPlacement = placementCandidates.length === 0 ? -1
          : selectExecutionSiteCandidateIndex(placementCandidates);
        siteCandidate = selectedPlacement < 0
          ? undefined : placementCandidates[selectedPlacement];
      }
      if (!siteCandidate || siteCandidate.excluded !== undefined) {
        throw new StrategyHostError(
          siteCandidate?.excluded ??
            [...legacyExclusions].sort()[0] ?? 'ExecutionSiteUnavailable',
        );
      }
      // Protected boundary: nothing below (Site operation, input transfer,
      // implementation start) happens unless this exact activation is
      // authorized. A deny, failure, unsupported defer or persisted wait
      // stops the Run through the existing stop path.
      await authorizeActivation(siteCandidate.site, entry, index);
      // Activation has returned; no callback occurs inside its commit.
      projectTaskObservation(taskObservation, 'task_started', index);
      projectTaskLogicalObservation(taskObservation, 'before', index);
      let plannerObserverMilliseconds;
      if (observeTaskStart) {
        const observationStarted = performance.now();
        // The real dispatcher has selected the task/placement. Snapshot only
        // bounded diagnostics before any Site operation or Compute begins.
        // The callback's return value never replaces the selected task.
        await observeTaskStart(Object.freeze({task: index,
          registrationKey: entry.managedSelectionKey, managed: Boolean(managed),
          executionSite: executionSiteDescription(siteCandidate.site),
          explanation: core.explain(setup, 65536, 10000),
          usage: Object.freeze({...core.usage(setup)}),
        }));
        plannerObserverMilliseconds = performance.now() - observationStarted;
        signal?.throwIfAborted();
      }
      const siteBinding = bindExecutionSiteCandidate(siteCandidate);
      const siteOperation = startExecutionSiteOperation(siteBinding);
      let siteInputsResolved = siteCandidate.transfers.length === 0;
      let siteResolution: Promise<SiteResolution> | undefined;
      const resolveSiteInputs: ResolveSiteInputs = (inputs, transferSignal = signal) => {
        if (!siteResolution) {
          siteResolution = transfers.resolve(
            siteCandidate, inputs, transferSignal,
          ).then(value => {
            siteInputsResolved = true;
            return value;
          });
        }
        return siteResolution;
      };
      const siteCompletionReady = () => siteInputsResolved &&
        executionSiteOperationAvailable(siteOperation);
      const siteCompletionPermit = Object.freeze({
        isAvailable: siteCompletionReady,
        assertAvailable(): undefined {
          if (!siteCompletionReady()) {
            throw new StrategyHostError('ExecutionSiteCompletionNotReady');
          }
        },
      });
      const siteTask = managed ? Object.freeze({
        ...task as PreparedTask,
        executionSite: siteCandidate.site,
        resolveSiteInputs,
        siteCompletionReady,
      }) : task;
      let result: DispatchResult | null | undefined, siteResult: ReturnType<typeof retainSiteResult> | undefined;
      let successProgress: SuccessProgress | undefined;
      // The same physical task boundary is measured for every realization.
      // This is diagnostic timing, never a cost estimate or execution proof.
      const taskStarted = performance.now();
      try {
        result = await (managed
          ? entry.runPrepared!(siteTask as SiteTask, signal, relationSample)
          : entry.run(task, signal, siteCompletionPermit));
        if (result?.status === 'waiting_checkpoint') {
          if (result.checkpoint == null) {
            throw new StrategyHostError('InvalidStrategyCheckpointPause');
          }
          // A persisted wait stops only this physical dispatch. It is not a
          // Run cancellation fence or a successful task/result publication.
          checkpointPause = result.checkpoint;
          try {
            const stopped = settleSiteAfterFailure(siteOperation, result);
            rememberCleanup(stopped, result.cleanupPending ? result : undefined);
          } catch (error) {
            // Cleanup trouble cannot erase an already committed Checkpoint.
            // Keep the physical responsibility visible on this waiting owner.
            rememberCleanup(error, result);
            unconfirmedSiteOperations.add(siteOperation);
          }
          try { core.stop(setup); }
          catch (error) { rememberCleanup(error, core); }
          break;
        }
        const connectorOwnedOutput = Boolean(managed || result?.close);
        const managedBindingClaimed = result?.completed != null ||
          result?.material != null;
        successProgress = beginExecutionSiteHostTaskSuccess(
          siteInstallation,
          connectorOwnedOutput,
          managedBindingClaimed,
        );
        for (let step = 0; step < 12; step++) {
          const action = strategyAction.taskSuccess(executionSiteHostTaskSuccessAction(
            siteInstallation,
            successProgress,
          ));
          if (action === 'HostTaskCheckSiteCompletion') {
            recordExecutionSiteHostTaskSiteCompletion(
              siteInstallation,
              successProgress,
              siteCompletionReady(),
            );
            continue;
          }
          if (action === 'HostTaskRejectSiteCompletion') {
            throw new StrategyHostError('ExecutionSiteCompletionNotReady');
          }
          if (action === 'HostTaskCheckCommonCompletion') {
            recordExecutionSiteHostTaskCommonCompletion(
              siteInstallation,
              successProgress,
              core.completed(setup, index),
            );
            continue;
          }
          if (action === 'HostTaskRejectCommonCompletion') {
            throw new StrategyHostError('TaskNotCompleted');
          }
          if (action === 'HostTaskRetainConnectorOutput') {
            siteResult = retainSiteResult(
              siteOperation, result, siteCandidate.capacity.retainedBytes,
            );
            outputs.push(siteResult);
            recordExecutionSiteHostTaskOutputRetained(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 'HostTaskRetainCoreOutput') {
            const output = core.output(setup, index);
            if (output == null) {
              throw new StrategyHostError('MissingCompletedOutput');
            }
            coreSiteOutputs.retain(
              siteOperation, output, siteCandidate.capacity.retainedBytes,
            );
            recordExecutionSiteHostTaskOutputRetained(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 'HostTaskSettleSiteOperation') {
            if (!settleExecutionSiteOperation(siteOperation)) {
              throw new StrategyHostError(
                'ExecutionSiteOperationSettlementRejected',
              );
            }
            recordExecutionSiteHostTaskSiteOperationSettled(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 'HostTaskValidateManagedBinding') {
            const relationOutput = result?.material != null;
            const carrierOutput = result?.carrierMaterial != null;
            const managedBindingValid = result?.completed != null &&
              relationOutput !== carrierOutput &&
              (carrierOutput
                ? core.managedCarrierMatches?.(
                  setup,
                  index,
                  result.completed,
                ) === true
                : core.managedMatches!(setup, index, result.completed));
            recordExecutionSiteHostTaskManagedBinding(
              siteInstallation,
              successProgress,
              managedBindingValid,
            );
            continue;
          }
          if (action === 'HostTaskRejectManagedBinding') {
            throw new StrategyHostError('InvalidManagedCompletion');
          }
          if (action === 'HostTaskSuccessFinished') {
            successProgress = undefined;
            break;
          }
          throw new StrategyHostError('InvalidHostTaskSuccessProgress');
        }
        if (successProgress !== undefined) {
          throw new StrategyHostError('HostTaskSuccessDidNotConverge');
        }
      } catch (error) {
        throw settleSiteAfterFailure(
          siteOperation,
          error,
          successProgress !== undefined &&
            executionSiteHostTaskSiteOperationSettled(
              siteInstallation,
              successProgress,
            ),
        );
      }
      // A callback's resolved Promise is not a completion proof. The core must
      // already have installed this exact task's retained, verified output.
      if (result?.completed != null || result?.material != null ||
          result?.carrierMaterial != null) {
        const relationOutput = result?.material != null;
        const carrierOutput = result?.carrierMaterial != null;
        const matches = carrierOutput
          ? core.managedCarrierMatches?.(setup, index, result.completed)
          : core.managedMatches?.(setup, index, result.completed);
        if (result?.completed == null || relationOutput === carrierOutput ||
            matches !== true) {
          throw new StrategyHostError('InvalidManagedCompletion');
        }
        managedOutputs.set(index, Object.freeze({
          task: index,
          completed: result.completed,
          material: (result.material ?? result.carrierMaterial)!,
          carrierMaterial: result.carrierMaterial,
          site: siteCandidate.site,
          siteMaterial: (result.siteMaterial ?? result.material ??
            result.carrierMaterial)!,
          materialGeneration: (result.materialGeneration ?? result.material ??
            result.carrierMaterial)!,
          scratchOwner: result,
          withRows: result.withRows,
          close: siteResult?.close,
          releaseOwner: siteResult,
        }));
      }
      if (result?.publicationOutput != null) {
        publicationOutputs.set(index, result.publicationOutput);
      }
      completed.push(Object.freeze({
        ...result?.diagnostic,
        ...(plannerObserverMilliseconds === undefined ? {} : {plannerObserverMilliseconds}),
        taskElapsedMilliseconds: performance.now() - taskStarted,
        task: index,
        executionSite: executionSiteDescription(siteCandidate.site),
      }));
      projectTaskObservation(taskObservation, 'task_completed', index,
        completed.at(-1)!.taskElapsedMilliseconds);
      projectTaskLogicalObservation(taskObservation, 'settled', index);
      if (observeCompletion) {
        const output = result?.completed ?? core.output(setup, index);
        if (output == null) throw new StrategyHostError('MissingCompletedOutput');
        signal?.throwIfAborted();
        // Deliver the core's exact output, never a connector diagnostic/CID or
        // callback-supplied substitute. Failure stops future tasks but cannot
        // undo this already completed task's independent result.
        const readRetained = typeof result?.readRetained === 'function'
          ? async (accept: RowConsumer, readSignal?: AbortSignal) => {
              if (siteResult?.status().released) {
                throw new StrategyHostError('RetainedUnavailable');
              }
              return result.readRetained!(accept, readSignal);
            }
          : undefined;
        try { await observeCompletion(Object.freeze({task: index, output,
          ...(readRetained === undefined ? {} : {readRetained})})); }
        catch (error) { rememberCleanup(error, observeCompletion); throw error; }
        signal?.throwIfAborted();
      }
      if (managed) {
        for (const producer of (task as PreparedTask).releasableProducers ?? []) {
          const output = (task as ReleasingTask).outputs?.get(producer);
          if (output?.siteMaterial) {
            await transfers.releaseSource(output);
          }
          if (output?.releaseOwner) {
            await releaseOwnedResult(output.releaseOwner);
          } else if (output?.close) {
            await output.close();
          }
          (task as ReleasingTask).outputs?.delete(producer);
          managedOutputs.delete(producer);
        }
      }
    }
    if (checkpointPause === undefined && !core.finished(setup)) {
      throw new StrategyHostError('StrategyNotComplete');
    }
  } catch (error) {
    rememberFailure(error);
    try { core.stop(setup); }
    catch (stopError) { rememberCleanup(stopError, core); }
  } finally {
    for (const entry of installed.values()) {
      try { await entry.finish?.(); }
      catch (error) {
        if (checkpointPause !== undefined) rememberCleanup(error, entry);
        else rememberFailure(error, entry);
      }
    }
    active.delete(setup);
  }
  const runFinished = failed || checkpointPause !== undefined ? false : core.finished(setup);
  const outcome = checkpointPause !== undefined && !failed ? undefined
    : strategyAction.outcome(executionSiteHostTaskRunOutcome(siteInstallation, failed, runFinished));
  if (outcome === 'HostTaskRunInvalid') throw new StrategyHostError('InvalidStrategyOutcome');
  let execution: InstalledExecution;
  execution = Object.freeze({
    // Internal task records only, not Program/Run publication or partial success.
    status: checkpointPause !== undefined && !failed ? 'host-tasks-waiting'
      : outcome === 'HostTasksFailed' ? 'host-tasks-failed' : 'host-tasks-completed',
    ...(checkpointPause === undefined ? {} : {checkpoint: checkpointPause}),
    failure,
    completed: Object.freeze(completed),
    candidateExclusions: Object.freeze(candidateExclusions),
    candidateComparisons: Object.freeze(candidateComparisons),
    programDefinitionCid,
    resultInventory: checkedResultInventory,
    publicationInventory,
    ...(preflight === undefined ? {} : {publicationPreflight: preflight}),
    async publishEffectFreeRun(store: unknown, publication: unknown, signal?: AbortSignal, publicationResource?: unknown) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (programHasEffects) {
        throw new StrategyHostError('EffectfulProgramRequiresEffectRun');
      }
      if (failed || !core.finished(setup)) {
        throw new StrategyHostError('StrategyNotComplete');
      }
      if (publication === null || typeof publication !== 'object' ||
          Array.isArray(publication) ||
          ['execution', 'store', 'control', 'signal']
            .some(name => Object.hasOwn(publication, name))) {
        throw new StrategyHostError('InvalidRunPublicationRequest');
      }
      const admitted = prepareCompletedEffectFreeRunPublication({
        store,
        control: core.publicationControl,
        publicationInventory,
        plan: publication,
      });
      return publishCompletedEffectFreeRun({
        ...admitted.plan,
        execution,
        store,
        control: core.publicationControl,
        signal,
      } as unknown as Parameters<typeof publishCompletedEffectFreeRun>[0], publicationResource);
    },
    async storePublicationResult(result: number, store: unknown, publication: ResultPublication, signal?: AbortSignal, publicationResource?: unknown) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (!Number.isSafeInteger(result) || result < 0 ||
          result >= resultInventory.length ||
          publication === null || typeof publication !== 'object' ||
          publication.outputLimits === undefined ||
          publication.contractLimits === undefined ||
          publication.runDefinition === undefined ||
          publication.invocation === undefined ||
          publication.retention === undefined ||
          publication.evidenceContext === undefined ||
          typeof core.outputExportControl?.beginResult !== 'function' ||
          typeof core.publicationControl?.issueResultArtifact !== 'function') {
        throw new StrategyHostError('InvalidResultPublicationExport');
      }
      const occurrence = resultInventory[result];
      if (!publicationContract(occurrence.definitionContract)) {
        throw new StrategyHostError('MissingResultDefinitionContract');
      }
      const managed = managedOutputs.get(occurrence.task);
      const beginManagedResult = managed === undefined ||
          typeof managed.withRows !== 'function'
        ? undefined
        : async (host: object, result: number, limits: unknown) => {
          const importing = core.outputExportControl!.beginManagedResultImport(
            host,
            result,
            managed.completed,
            managed.material,
            limits,
          );
          let finished = false;
          try {
            const exported = await managed.withRows!(
              row => core.outputExportControl!.appendManagedResultImport(
                importing, row, limits,
              ),
              signal,
              () => publication.transformation === undefined
                ? core.outputExportControl!.finishManagedResultImport(importing, signal,
                  publication.resultProgress)
                : core.outputExportControl!.transformManagedResultImport(
                  importing, publication.transformation, signal, publication.resultProgress),
            );
            finished = true;
            return exported;
          } finally {
            if (!finished) {
              core.outputExportControl!.cancelManagedResultImport(importing);
            }
          }
        };
      const beginResult = beginManagedResult ?? ((host: object, result: number, limits: PayloadLimits) =>
        core.outputExportControl!.beginResult(
          host, result, limits, publicationOutputs.get(occurrence.task),
          publication.transformation, signal, publication.resultProgress,
        ));
      const stored = await storeCompletedResultPublicationPayload(
        store as PublicationPayloadStore,
        core.outputExportControl,
        setup,
        result,
        publication.outputLimits as PayloadLimits,
        {
          control: core.publicationControl as PayloadPublication['control'],
          runDefinition: publication.runDefinition as PayloadPublication['runDefinition'],
          definition: occurrence.definitionContract,
          invocation: publication.invocation,
          retention: publication.retention,
          evidenceContext: publication.evidenceContext,
          limits: publication.contractLimits,
        },
        signal,
        beginResult,
        undefined,
        publicationResource,
      );
      return Object.freeze({
        occurrence: Object.freeze({
          name: occurrence.name,
          task: occurrence.task,
          definition: occurrence.definitionContract,
        }),
        ...stored,
      });
    },
    async refreshCompletedScratch() {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (failed || !runFinished) throw new StrategyHostError('StrategyNotComplete');
      if (refreshingCompletedScratch) throw new StrategyHostError('StrategyScratchRefreshReentrant');
      refreshingCompletedScratch = true;
      try {
        for (const result of managedOutputs.values()) {
          const owner = result.scratchOwner;
          const refresh = owner.refreshCompletedScratch;
          if (refresh !== undefined) {
            if (typeof refresh !== 'function') throw new StrategyHostError('InvalidCompletedScratchRefresh');
            await Reflect.apply(refresh, owner, []);
            if (closed) throw new StrategyHostError('ReleasedStrategy');
          }
        }
      } finally { refreshingCompletedScratch = false; }
    },
    usage: () => core.usage(setup),
    cleanupPending,
    cleanup() {
      if (cleanupInFlight) return cleanupInFlight;
      cleanupInFlight = (async () => {
        // Attempt every independent recovery even when an earlier one fails.
        // Only an explicit recovery handle authorizes retry; never run Compute.
        const errors: unknown[] = [];
        const attempted = new Set<CleanupHandle>();
        const cleanupProgress = beginExecutionSiteHostCleanup(siteInstallation);
        const retryKnown = async () => {
          for (const handle of [...pendingCleanup]) {
            if (attempted.has(handle)) continue;
            attempted.add(handle);
            try {
              if (handle.status()!.pending) await handle.retry();
              if (!handle.status()!.pending) pendingCleanup.delete(handle);
            } catch (error) { errors.push(error); }
          }
        };
        for (let step = 0; step < 8; step++) {
          const action = strategyAction.cleanup(executionSiteHostCleanupAction(
            siteInstallation,
            cleanupProgress,
            pendingCloses.size !== 0,
            knownCleanupPending(),
            unconfirmedRelease.size !== 0 ||
              unconfirmedSiteOperations.size !== 0,
            errors.length !== 0,
          ));
          if (action === 'HostCleanupRetryKnown') {
            await retryKnown();
            recordExecutionSiteHostCleanupRetry(
              siteInstallation,
              cleanupProgress,
            );
            continue;
          }
          if (action === 'HostCleanupAwaitCloses') {
            await Promise.all([...pendingCloses]);
            recordExecutionSiteHostCleanupClosesAwaited(
              siteInstallation,
              cleanupProgress,
            );
            continue;
          }
          if (action === 'HostCleanupPending') return false;
          if (action === 'HostCleanupFailed') {
            throw new AggregateError(errors, 'Strategy cleanup failed');
          }
          if (action === 'HostCleanupFinished') return true;
          throw new StrategyHostError('InvalidStrategyCleanupProgress');
        }
        throw new StrategyHostError('StrategyCleanupDidNotConverge');
      })().finally(() => { cleanupInFlight = undefined; });
      return cleanupInFlight;
    },
    explain(maxBytes = 65536, maxNodes = 10000) {
      for (const limit of [maxBytes, maxNodes]) {
        if (!Number.isSafeInteger(limit) || limit < 0 || limit > 2147483647) {
          throw new StrategyHostError('InvalidExplanationLimit');
        }
      }
      return core.explain(setup, maxBytes, maxNodes);
    },
    output(task: number) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (!Number.isSafeInteger(task) ||
          task < (firstTask === 0 ? 0 : 1) || task >= core.count(setup)) {
        throw new StrategyHostError('InvalidStrategyTask');
      }
      return core.output(setup, task);
    },
    // Physical observation for the installed Effect Site adapter. The
    // MoonBit captured-source pin must still verify this exact generation
    // before any row import or Preview use; this handle grants no apply.
    effectPhysicalSource(task: number) {
      if (closed || !programHasEffects || failed || !core.finished(setup) ||
          !Number.isSafeInteger(task) || task < 0 ||
          task >= core.count(setup)) {
        throw new StrategyHostError('InvalidEffectPhysicalSource');
      }
      return managedPhysicalSource(task);
    },
    close() {
      if (closed) return closeResult;
      closed = true;
      let closeFailed = false;
      let closeFailure: unknown;
      const releaseFailed = (error: unknown, owner: object) => {
        if (!closeFailed) closeFailure = error;
        closeFailed = true;
        rememberOwnedReleaseFailure(error, owner);
      };
      // Successful output remains usable until this owner closes. Stop the
      // completed original DAG before returning outputs and observation loans;
      // finishing Compute alone does not close its retained boundary hooks.
      // A checkpoint wait keeps its existing dispatch-stop/resume semantics.
      if (runFinished) {
        try { core.stop(setup); }
        catch (error) { releaseFailed(error, core); }
      }
      try {
        const result = transfers.close();
        if (result != null && typeof (result as PromiseLike<unknown>).then === 'function') {
          const pending = Promise.resolve(result).then(
            () => {}, error => releaseFailed(error, transfers),
          ).finally(() => pendingCloses.delete(pending));
          pendingCloses.add(pending);
        }
      } catch (error) { releaseFailed(error, transfers); }
      for (const output of outputs) {
        try {
          const result = releaseOwnedResult(output);
          if (result != null && typeof (result as PromiseLike<unknown>).then === 'function') {
            const pending = Promise.resolve(result).then(
              () => {}, error => releaseFailed(error, output),
            ).finally(() => pendingCloses.delete(pending));
            pendingCloses.add(pending);
          }
        } catch (error) { releaseFailed(error, output); }
      }
      outputs.length = 0;
      publicationOutputs.clear();
      try { coreSiteOutputs.close(); }
      catch (error) { releaseFailed(error, coreSiteOutputs); }
      if (pendingCloses.size) {
        closeResult = Promise.all([...pendingCloses]).then(() => {
          if (closeFailed) throw closeFailure;
        });
        // Older synchronous callers may ignore the return value. Responsibility
        // still stays in this driver's cleanup state, never an unhandled reject.
        closeResult.catch(() => {});
      }
      if (closeFailed) throw closeFailure;
      return closeResult;
    },
  });
  return execution;
}
