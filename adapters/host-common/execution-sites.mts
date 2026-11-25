// Environment-facing handles for portable MoonBit Site control. This module
// binds Connector placements and opaque physical values; it does not decide
// mutable Site lifecycle, capacity, or terminal state.
import type {SynchronousRuntimeData} from './runtime-result.mjs';
import type {createManagedMemoryTransferProvider} from '../store-local/managed-memory-transfer.mjs';
import type {ManagedTransferEstimate} from '../store-local/managed-memory-representations.mjs';

declare const coreBrand: unique symbol;
type CoreHandle<Kind extends string> = Extract<SynchronousRuntimeData, object> &
  Readonly<{[coreBrand]: Kind}>;
type SiteHandle = CoreHandle<'Site'>;
type OperationHandle = CoreHandle<'SiteOperation'>;
type TransferHandle = CoreHandle<'SiteTransfer'>;
type HoldingHandle = CoreHandle<'SiteHolding'>;
export type SiteHoldingRestoration = CoreHandle<'SiteHoldingRestoration'>;
type CleanupHandle = CoreHandle<'SiteCleanup'>;
type FailureProgress = CoreHandle<'SiteFailureProgress'>;
type RetainedCloseProgress = CoreHandle<'RetainedCloseProgress'>;
type RetainedHoldingProgress = CoreHandle<'RetainedHoldingProgress'>;
type HostCleanupProgress = CoreHandle<'HostCleanupProgress'>;
type HostSuccessProgress = CoreHandle<'HostSuccessProgress'>;
type RemoteJournalHandle = CoreHandle<'RemoteJournal'>;
type Optional<Value> = Value | null | undefined;

type Capacity = Readonly<{retainedBytes: bigint; executionBytes: bigint}>;
type SiteConfiguration = Readonly<{
  key: string;
  generation: number;
  runtimeRevision: string;
  maxConcurrentOperations: number;
  maxConcurrentTransfers: number;
  maxRetainedBytes: bigint;
  maxExecutionBytes: bigint;
}>;
type SiteTiming = Readonly<{
  startupMilliseconds: bigint | null;
  transferMilliseconds: bigint | null;
}>;
type SitePlanningFacts = SiteTiming & Readonly<{
  durationMilliseconds: bigint | null;
  capacitySupported: boolean;
  acceptsSiteTransfer: boolean;
  transferProviderAvailable: boolean;
  transferRequired: readonly boolean[];
  sharedTransfer: readonly boolean[];
  sourceRevoked: readonly boolean[];
  estimateAvailable: readonly boolean[];
  transferBytes: readonly bigint[];
  retainedBytes: readonly bigint[];
  executionBytes: readonly bigint[];
}>;

// This is the existing normalized JS control from runtime-core. Opaque views
// carry the original Common values; the runtime callable checks are unchanged.
export type SiteControl = Readonly<{
  create(configuration: SiteConfiguration): Optional<SiteHandle>;
  available(site: SiteHandle): boolean;
  revoked(site: SiteHandle): boolean;
  capacitySupports(site: SiteHandle, retained: bigint, execution: bigint): boolean;
  bindingCurrent(site: SiteHandle, generation: number, revision: string): boolean;
  startOperation(site: SiteHandle, retained: bigint, execution: bigint): Optional<OperationHandle>;
  operationAvailable(operation: OperationHandle): boolean;
  settleOperation(operation: OperationHandle): boolean;
  retainOperationHolding(operation: OperationHandle, bytes: bigint): Optional<HoldingHandle>;
  startTransfer(source: SiteHandle, destination: SiteHandle, retained: bigint, execution: bigint): Optional<TransferHandle>;
  transferAvailable(transfer: TransferHandle): boolean;
  settleTransferSource(transfer: TransferHandle): boolean;
  settleTransferDestination(transfer: TransferHandle): boolean;
  retainTransferHolding(transfer: TransferHandle, bytes: bigint): Optional<HoldingHandle>;
  retainHolding(site: SiteHandle, bytes: bigint): Optional<HoldingHandle>;
  releaseHolding(holding: HoldingHandle): boolean;
  retainCleanup(site: SiteHandle): Optional<CleanupHandle>;
  releaseCleanup(cleanup: CleanupHandle): boolean;
  beginTeardown(site: SiteHandle): undefined;
  revoke(site: SiteHandle): undefined;
  status(site: SiteHandle): readonly bigint[];
  selectCandidate(durations: readonly bigint[], keys: readonly string[]): number;
  planCandidate(facts: SitePlanningFacts): readonly [number, bigint] | undefined;
  managedCandidateFallback(retainedInputCount: number, exclusionCodes: readonly number[]): number;
  beginFailedOperation(cleanupRequired: boolean, alreadySettled: boolean): FailureProgress;
  recordFailedOperationStop(progress: FailureProgress): boolean;
  recordFailedOperationSettlement(progress: FailureProgress): boolean;
  failedOperationAction(progress: FailureProgress): number;
  beginRetainedClose(): RetainedCloseProgress;
  beginRetainedHolding(progress: RetainedCloseProgress): Optional<RetainedHoldingProgress>;
  recordRetainedCloseStarted(progress: RetainedCloseProgress): boolean;
  recordRetainedCloseSucceeded(progress: RetainedCloseProgress): boolean;
  recordRetainedCloseFailed(progress: RetainedCloseProgress): boolean;
  recordRetainedCleanupAuthority(progress: RetainedCloseProgress): boolean;
  recordRetainedCleanupStopped(progress: RetainedCloseProgress): boolean;
  recordRetainedHoldingReleased(progress: RetainedHoldingProgress): boolean;
  retainedCloseAction(progress: RetainedCloseProgress): number;
  retainedHoldingAction(progress: RetainedHoldingProgress): number;
  beginHostCleanup(): HostCleanupProgress;
  recordHostCleanupRetry(progress: HostCleanupProgress): boolean;
  recordHostCleanupClosesAwaited(progress: HostCleanupProgress): boolean;
  hostCleanupAction(progress: HostCleanupProgress, closesPending: boolean, knownCleanupPending: boolean,
    unconfirmedOwnership: boolean, cleanupFailed: boolean): number;
  hostCleanupPending(closesPending: boolean, knownCleanupPending: boolean, unconfirmedOwnership: boolean): boolean;
  hostTaskRunOutcome(failed: boolean, runFinished: boolean): number;
  beginHostTaskSuccess(connectorOwnedOutput: boolean, managedBindingClaimed: boolean): HostSuccessProgress;
  recordHostTaskSiteCompletion(progress: HostSuccessProgress, ready: boolean): boolean;
  recordHostTaskCommonCompletion(progress: HostSuccessProgress, completed: boolean): boolean;
  recordHostTaskOutputRetained(progress: HostSuccessProgress): boolean;
  recordHostTaskSiteOperationSettled(progress: HostSuccessProgress): boolean;
  recordHostTaskManagedBinding(progress: HostSuccessProgress, valid: boolean): boolean;
  hostTaskSiteOperationSettled(progress: HostSuccessProgress): boolean;
  hostTaskSuccessAction(progress: HostSuccessProgress): number;
}>;
type SiteState = SiteConfiguration & SiteTiming & {
  identity: object;
  control: SiteControl | undefined;
  handle: SiteHandle | undefined;
  pendingTeardown: boolean;
  pendingRevocation: boolean;
};
type ControlledSite = SiteState & {control: SiteControl; handle: SiteHandle};
type MemoryTransferProvider = ReturnType<typeof createManagedMemoryTransferProvider>;
type TransferProvider = Readonly<{
  contract: Readonly<Record<keyof MemoryTransferProvider['contract'], string>>;
  estimate(material: object): ManagedTransferEstimate | undefined;
  copy(options: Parameters<MemoryTransferProvider['copy']>[0]): unknown;
}>;
type PlacementContribution = Readonly<{managedSelectionKey?: string; registration?: unknown}>;
type PolicyOptions = Readonly<{
  sites?: readonly object[];
  placements?: ReadonlyMap<string, readonly object[]>;
  defaultSites?: readonly object[];
  transferProvider?: TransferProvider;
  maxSites?: number;
  maxPlacements?: number;
}>;
type SitePolicy = Readonly<{
  sites: readonly object[];
  placements: ReadonlyMap<string, readonly object[]>;
  defaultSites: readonly object[];
  transferProvider: TransferProvider | undefined;
  maxPlacements: number;
}>;
type SiteInstallation = Readonly<{
  policy: SitePolicy;
  placement: ReadonlyMap<PlacementContribution, readonly object[]>;
  control: SiteControl;
}>;
type SiteInput = Readonly<{
  task: number;
  material: object;
  site: object;
  siteMaterial: object;
  materialGeneration: object;
  transferMode?: 'preserve-to-independent-material';
}>;
type InputSite = Readonly<{
  site: object;
  identity: object;
  generation: number;
  runtimeRevision: string;
}>;
type SiteTransfer<Input extends SiteInput> = Readonly<{
  input: Input;
  estimate: ManagedTransferEstimate;
  sharedWith: Input | undefined;
}>;
type CandidateOptions<Input extends SiteInput> = Readonly<{
  installation: object;
  contribution: PlacementContribution;
  site: object;
  task: number;
  registration: unknown;
  inputs: readonly Input[];
  durationMilliseconds: bigint | null;
  acceptsSiteTransfer?: boolean;
  capacity?: Capacity;
}>;
type SiteCandidate = NonNullable<ReturnType<typeof executionSiteCandidate>>;
type AcceptedCandidate = Extract<SiteCandidate, {excluded: undefined}>;
type CandidateSelection = Pick<AcceptedCandidate, 'site' | 'excluded' | 'durationMilliseconds' | 'selectionKey'>;
type SiteBinding = {candidate: AcceptedCandidate; state: ControlledSite; consumed: boolean};
type ControlledHandle<Handle> = Readonly<{control: SiteControl; handle: Handle}>;
type RetainedValue<Handle> = ControlledHandle<Handle> & Readonly<{value: unknown}>;
type ControlledProgress<Progress> = Readonly<{control: SiteControl; progress: Progress}>;
type RetainedCloseMethod = 'recordRetainedCloseStarted' | 'recordRetainedCloseSucceeded' |
  'recordRetainedCloseFailed' | 'recordRetainedCleanupAuthority' | 'recordRetainedCleanupStopped';
type HostSuccessMethod = 'recordHostTaskSiteCompletion' | 'recordHostTaskCommonCompletion' |
  'recordHostTaskOutputRetained' | 'recordHostTaskSiteOperationSettled' | 'recordHostTaskManagedBinding';

const sites = new WeakMap<object, SiteState>();
const policies = new WeakMap<object, SitePolicy>();
const installations = new WeakMap<object, SiteInstallation>();
const bindings = new WeakMap<object, SiteBinding>();
const operations = new WeakMap<object, ControlledHandle<OperationHandle>>();
const transferOperations = new WeakMap<object, ControlledHandle<TransferHandle>>();
const holdings = new WeakMap<object, RetainedValue<HoldingHandle>>();
const cleanupResponsibilities = new WeakMap<object, RetainedValue<CleanupHandle>>();
const retainedCloseProgresses = new WeakMap<object, ControlledProgress<RetainedCloseProgress>>();
const retainedHoldingProgresses = new WeakMap<object, ControlledProgress<RetainedHoldingProgress> & Readonly<{closeOwner: object}>>();

const fail: (code: string, details?: unknown) => never = (code, details) => {
  const error = Object.assign(new Error(code), {code}) as Error & {code: string; details?: unknown};
  if (details !== undefined) error.details = details;
  throw error;
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const count = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const maximumBytes = 9223372036854775807n;
const duration = (value: unknown): value is bigint | null => value === null ||
  (typeof value === 'bigint' && value >= 0n && value <= maximumBytes);
const bytes = (value: unknown): value is bigint => typeof value === 'bigint' &&
  value >= 0n && value <= maximumBytes;
const siteState = (site: unknown) => sites.get(site as object) ?? fail('ForeignExecutionSite');
const sameInputOccurrence = (left: SiteInput, right: SiteInput) =>
  left.task === right.task &&
  left.material === right.material &&
  left.site === right.site &&
  left.siteMaterial === right.siteMaterial &&
  left.materialGeneration === right.materialGeneration;
const controlMethods = [
  'create', 'available', 'revoked', 'capacitySupports', 'bindingCurrent',
  'startOperation', 'operationAvailable', 'settleOperation',
  'retainOperationHolding', 'startTransfer', 'transferAvailable',
  'settleTransferSource', 'settleTransferDestination',
  'retainTransferHolding', 'retainHolding', 'releaseHolding',
  'retainCleanup', 'releaseCleanup', 'beginTeardown', 'revoke', 'status',
  'selectCandidate', 'planCandidate', 'managedCandidateFallback',
  'beginFailedOperation', 'recordFailedOperationStop',
  'recordFailedOperationSettlement', 'failedOperationAction',
  'beginRetainedClose', 'beginRetainedHolding',
  'recordRetainedCloseStarted', 'recordRetainedCloseSucceeded',
  'recordRetainedCloseFailed', 'recordRetainedCleanupAuthority',
  'recordRetainedCleanupStopped', 'recordRetainedHoldingReleased',
  'retainedCloseAction', 'retainedHoldingAction',
  'beginHostCleanup', 'recordHostCleanupRetry',
  'recordHostCleanupClosesAwaited', 'hostCleanupAction',
  'hostCleanupPending',
  'hostTaskRunOutcome', 'beginHostTaskSuccess',
  'recordHostTaskSiteCompletion', 'recordHostTaskCommonCompletion',
  'recordHostTaskOutputRetained',
  'recordHostTaskSiteOperationSettled', 'recordHostTaskManagedBinding',
  'hostTaskSiteOperationSettled',
  'hostTaskSuccessAction',
] as const satisfies readonly (keyof SiteControl)[];

function checkedControl(control: unknown): SiteControl {
  if (control === null || typeof control !== 'object' ||
      controlMethods.some(name => typeof (control as Record<string, unknown>)[name] !== 'function')) {
    fail('MissingExecutionSiteControl');
  }
  return control as SiteControl;
}

function bindSiteControl(state: SiteState, control: SiteControl) {
  if (state.control !== undefined) {
    if (state.control !== control) fail('ForeignExecutionSiteControl');
    return false;
  }
  const handle = control.create(Object.freeze({
    key: state.key,
    generation: state.generation,
    runtimeRevision: state.runtimeRevision,
    maxConcurrentOperations: state.maxConcurrentOperations,
    maxConcurrentTransfers: state.maxConcurrentTransfers,
    maxRetainedBytes: state.maxRetainedBytes,
    maxExecutionBytes: state.maxExecutionBytes,
  }));
  if (handle === undefined || handle === null) fail('InvalidExecutionSite');
  state.control = control;
  state.handle = handle;
  return true;
}

// A failed installation is not a rollback of the original Core handles. Keep
// the bindings and retry only their existing teardown, never create them again.
function installationCleanup(createdSites: readonly object[]) {
  const status = () => {
    const statuses = Object.freeze(createdSites.map(executionSiteStatus));
    return Object.freeze({
      pending: statuses.some(value => !value.teardownComplete), sites: statuses,
    });
  };
  const retry = () => {
    let firstFailure;
    let failed = false;
    for (const site of createdSites) {
      try {
        const state = siteState(site);
        if (state.pendingRevocation) revokeExecutionSite(site);
        else beginExecutionSiteTeardown(site);
      } catch (error) {
        if (!failed) firstFailure = error;
        failed = true;
      }
    }
    if (failed) throw firstFailure;
    return status();
  };
  return Object.freeze({status, retry});
}

function controlled(state: SiteState): ControlledSite {
  if (state.control === undefined || state.handle === undefined) {
    fail('UnboundExecutionSite');
  }
  return state as ControlledSite;
}

export function createInProcessExecutionSite({
  key,
  generation,
  runtimeRevision,
  startupMilliseconds = 0n,
  transferMilliseconds = 0n,
  maxConcurrentOperations = 1,
  maxConcurrentTransfers = 1,
  maxRetainedBytes = maximumBytes,
  maxExecutionBytes = maximumBytes,
}: Partial<SiteConfiguration & SiteTiming> = {}) {
  if (!text(key) || !count(generation) || !text(runtimeRevision) ||
      !duration(startupMilliseconds) || !duration(transferMilliseconds) ||
      !count(maxConcurrentOperations) || maxConcurrentOperations === 0 ||
      !count(maxConcurrentTransfers) || maxConcurrentTransfers === 0 ||
      !bytes(maxRetainedBytes) || !bytes(maxExecutionBytes)) {
    fail('InvalidExecutionSite');
  }
  const site = Object.freeze({});
  sites.set(site, {
    identity: {}, key, generation, runtimeRevision, startupMilliseconds,
    transferMilliseconds, maxConcurrentOperations, maxConcurrentTransfers,
    maxRetainedBytes, maxExecutionBytes, control: undefined,
    handle: undefined, pendingTeardown: false, pendingRevocation: false,
  });
  return site;
}

export function executionSiteDescription(site: unknown) {
  const state = siteState(site);
  const accepting = state.control === undefined
    ? !state.pendingTeardown && !state.pendingRevocation
    : state.control.available(state.handle!);
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    runtimeRevision: state.runtimeRevision,
    accepting,
  });
}

// Policy is Host installation, not Program input. Placement keys are stable
// registration keys assigned by the Host. One implementation may be placed at
// several Sites and one Site may host several implementations.
export function prepareExecutionSitePolicy({
  sites: supplied,
  placements = new Map(),
  defaultSites,
  transferProvider,
  maxSites = 64,
  maxPlacements = 256,
}: PolicyOptions = {}) {
  if (!Array.isArray(supplied) || !count(maxSites) || !count(maxPlacements) ||
      supplied.length === 0 || supplied.length > maxSites ||
      !(placements instanceof Map) ||
      (transferProvider !== undefined &&
        (transferProvider === null ||
         typeof transferProvider.estimate !== 'function' ||
         typeof transferProvider.copy !== 'function' ||
         !text(transferProvider.contract?.version) ||
         !text(transferProvider.contract?.codec) ||
         !text(transferProvider.contract?.preservationRule) ||
         !text(transferProvider.contract?.trustBoundary) ||
         !text(transferProvider.contract?.integrityModel) ||
         !text(transferProvider.contract?.contentDigest) ||
         !text(transferProvider.contract?.logicalIdentity)))) {
    fail('InvalidExecutionSitePolicy');
  }
  const unique = new Set<string>();
  for (const site of supplied) {
    const state = siteState(site);
    const identity = `${state.key}\u0000${state.generation}`;
    if (unique.has(identity)) fail('DuplicateExecutionSiteGeneration');
    unique.add(identity);
  }
  const siteSet = new Set<object>(supplied);
  const selectedDefaults = defaultSites === undefined
    ? [supplied[0]] : [...defaultSites];
  if (selectedDefaults.length === 0 ||
      selectedDefaults.some(site => !siteSet.has(site))) {
    fail('InvalidExecutionSitePolicy');
  }
  const ownedPlacements = new Map<string, readonly object[]>();
  let placementCount = selectedDefaults.length;
  if (placementCount > maxPlacements) fail('ExecutionSitePlacementLimit');
  for (const [key, values] of placements) {
    if (!text(key) || !Array.isArray(values) || values.length === 0 ||
        values.some(site => !siteSet.has(site)) ||
        new Set(values).size !== values.length) {
      fail('InvalidExecutionSitePolicy');
    }
    if (values.length > maxPlacements - placementCount) fail('ExecutionSitePlacementLimit');
    placementCount += values.length;
    ownedPlacements.set(key, Object.freeze([...values]));
  }
  const policy = Object.freeze({});
  policies.set(policy, {
    sites: Object.freeze([...supplied]),
    placements: ownedPlacements,
    defaultSites: Object.freeze(selectedDefaults),
    transferProvider,
    maxPlacements,
  });
  return policy;
}

export function prepareSingleExecutionSitePolicy() {
  const site = createInProcessExecutionSite({
    key: 'in-process-default',
    generation: 0,
    runtimeRevision: 'actql-in-process-site/0.1',
    maxConcurrentOperations: 1,
  });
  return prepareExecutionSitePolicy({sites: [site]});
}

export function installExecutionSites(policy: object, contributions: readonly PlacementContribution[], suppliedControl: unknown) {
  const configured = policies.get(policy) ?? fail('ForeignExecutionSitePolicy');
  const control = checkedControl(suppliedControl);
  if (!Array.isArray(contributions) || contributions.length === 0) {
    fail('InvalidExecutionSiteInstallation');
  }
  const placement = new Map<PlacementContribution, readonly object[]>();
  let total = 0;
  for (const contribution of contributions) {
    const key = contribution?.managedSelectionKey;
    if (placement.has(contribution)) fail('InvalidExecutionSiteInstallation');
    const selected = text(key)
      ? configured.placements.get(key) ?? configured.defaultSites
      : configured.defaultSites;
    if (selected.length > configured.maxPlacements - total) fail('ExecutionSitePlacementLimit');
    total += selected.length;
    placement.set(contribution, selected);
  }
  // Validate every existing binding after reading contribution properties, but
  // before calling the first control.create. A later foreign Site must not
  // partially bind earlier Sites on a statically invalid installation.
  for (const site of configured.sites) {
    const state = siteState(site);
    if (state.control !== undefined && state.control !== control) {
      fail('ForeignExecutionSiteControl');
    }
  }
  const createdSites: object[] = [];
  try {
    for (const site of configured.sites) {
      const state = siteState(site);
      if (bindSiteControl(state, control)) {
        createdSites.push(site);
        // Track the original handle before applying a pending lifecycle action:
        // that action can itself fail and must leave a reachable cleanup duty.
        if (state.pendingRevocation) control.revoke(state.handle!);
        else if (state.pendingTeardown) control.beginTeardown(state.handle!);
      }
    }
  } catch (cause) {
    if (createdSites.length === 0) throw cause;
    const cleanupHandle = installationCleanup(Object.freeze(createdSites));
    const code = typeof (cause as {code?: unknown} | null | undefined)?.code === 'string'
      ? (cause as {code: string}).code : 'ExecutionSiteInstallationFailed';
    const error = Object.assign(new Error(code, {cause}), {code, cleanupHandle}) as Error & {
      code: string; cleanupHandle: typeof cleanupHandle; cleanupPending?: boolean; cleanupFailure?: unknown;
    };
    try {
      error.cleanupPending = cleanupHandle.retry().pending;
    } catch (cleanupFailure) {
      error.cleanupPending = true;
      error.cleanupFailure = cleanupFailure;
    }
    throw error;
  }
  const installation = Object.freeze({});
  installations.set(installation, {policy: configured, placement, control});
  return installation;
}

export function executionSitePlacements(installation: object, contribution: PlacementContribution) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const placed = state.placement.get(contribution);
  if (!placed) fail('ForeignExecutionSiteContribution');
  return placed;
}

export function classifyManagedExecutionSiteFallback(
  installation: object,
  retainedInputCount: number,
  exclusionCodes: readonly number[],
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (!count(retainedInputCount) || !Array.isArray(exclusionCodes) ||
      exclusionCodes.some(code => !Number.isSafeInteger(code))) {
    fail('InvalidManagedCandidateFallback');
  }
  const result = state.control.managedCandidateFallback(
    retainedInputCount,
    exclusionCodes,
  );
  if (!Number.isSafeInteger(result) || result < 0 || result > 3) {
    fail('InvalidManagedCandidateFallback');
  }
  return result;
}

// Candidate facts are produced by environment placement adapters, while the
// portable Site control owns the cost and stable-key decision.
export function selectExecutionSiteCandidateIndex(
  candidates: readonly CandidateSelection[],
  {
    invalid = 'InvalidExecutionSiteCandidateSet',
    duplicate = 'DuplicateExecutionSiteSelectionKey',
  } = {},
) {
  if (!Array.isArray(candidates)) fail(invalid);
  if (candidates.length === 0) return -1;
  let control: SiteControl | undefined;
  for (const candidate of candidates) {
    if (candidate === null || typeof candidate !== 'object' ||
        candidate.excluded !== undefined) {
      fail(invalid);
    }
    const state = controlled(siteState(candidate.site));
    if (control !== undefined && control !== state.control) fail(invalid);
    control = state.control;
  }
  const selected = control!.selectCandidate(
    candidates.map(candidate => candidate.durationMilliseconds),
    candidates.map(candidate => candidate.selectionKey),
  );
  if (selected === -3) fail(duplicate);
  if (!Number.isSafeInteger(selected) || selected < 0 ||
      selected >= candidates.length) {
    fail(invalid);
  }
  return selected;
}

export function executionSiteTransferProvider(installation: object) {
  return (installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation')).policy.transferProvider;
}

// The physical adapter receives only the opaque MoonBit Site authority. Site
// generation, revocation, and capacity remain owned by the portable control.
export function createExecutionSiteRemoteJournal(site: unknown, remoteControl: Readonly<{createJournal(site: SiteHandle): RemoteJournalHandle}>) {
  const state = controlled(siteState(site));
  if (remoteControl === null || typeof remoteControl !== 'object' ||
      typeof remoteControl.createJournal !== 'function') {
    fail('MissingRemoteSiteControl');
  }
  return remoteControl.createJournal(state.handle);
}

export function executionSiteCandidate<Input extends SiteInput>({
  installation,
  contribution,
  site,
  task,
  registration,
  inputs,
  durationMilliseconds,
  acceptsSiteTransfer = false,
  capacity = Object.freeze({retainedBytes: 0n, executionBytes: 0n}),
}: CandidateOptions<Input> = {} as CandidateOptions<Input>) {
  const installed = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (!installed.placement.get(contribution)?.includes(site) ||
      contribution.registration !== registration ||
      !Number.isSafeInteger(task) || task < 0 || registration == null ||
      !Array.isArray(inputs) || !duration(durationMilliseconds) ||
      !bytes(capacity?.retainedBytes) || !bytes(capacity?.executionBytes)) {
    fail('InvalidExecutionSiteCandidate');
  }
  const destination = controlled(siteState(site));
  if (!destination.control.available(destination.handle)) return undefined;
  const capacitySupported = destination.control.capacitySupports(
    destination.handle,
    capacity.retainedBytes,
    capacity.executionBytes,
  );
  const transfers: SiteTransfer<Input>[] = [];
  const inputSites: InputSite[] = [];
  const provider = installed.policy.transferProvider;
  const transferRequired = [];
  const sharedTransfer = [];
  const sourceRevoked = [];
  const estimateAvailable = [];
  const transferBytes = [];
  const retainedBytes = [];
  const executionBytes = [];
  for (const input of inputs as readonly Input[]) {
    if (!input || typeof input !== 'object' ||
        !Number.isSafeInteger(input.task) || input.task < 0 ||
        input.material === null || typeof input.material !== 'object' ||
        input.site == null || input.siteMaterial === null ||
        typeof input.siteMaterial !== 'object' ||
        input.materialGeneration === null ||
        typeof input.materialGeneration !== 'object') {
      fail('InvalidExecutionSiteCandidate');
    }
    const source = controlled(siteState(input.site));
    if (source.control !== installed.control) {
      fail('ForeignExecutionSiteControl');
    }
    inputSites.push(Object.freeze({
      site: input.site,
      identity: source.identity,
      generation: source.generation,
      runtimeRevision: source.runtimeRevision,
    }));
    const independentCopy =
      input.transferMode === 'preserve-to-independent-material';
    if (input.transferMode !== undefined && !independentCopy) {
      fail('InvalidExecutionSiteCandidate');
    }
    if (input.site === site && !independentCopy) {
      transferRequired.push(false);
      sharedTransfer.push(false);
      sourceRevoked.push(false);
      estimateAvailable.push(false);
      transferBytes.push(0n);
      retainedBytes.push(0n);
      executionBytes.push(0n);
      continue;
    }
    if (input.task < 0) fail('InvalidExecutionSiteCandidate');
    const shared = transfers.find(value =>
      sameInputOccurrence(value.input, input));
    const estimate = shared?.estimate ?? provider?.estimate(input.siteMaterial);
    if (estimate !== undefined &&
        ![estimate.transferBytes, estimate.retainedBytes,
          estimate.executionBytes].every(value => bytes(value))) {
      fail('InvalidTransferEstimate');
    }
    transferRequired.push(true);
    sharedTransfer.push(shared !== undefined);
    sourceRevoked.push(source.control.revoked(source.handle));
    estimateAvailable.push(estimate !== undefined);
    transferBytes.push(estimate?.transferBytes ?? 0n);
    retainedBytes.push(estimate?.retainedBytes ?? 0n);
    executionBytes.push(estimate?.executionBytes ?? 0n);
    if (estimate !== undefined) {
      transfers.push(Object.freeze({input, estimate, sharedWith: shared?.input}));
    }
  }
  const plan = destination.control.planCandidate(Object.freeze({
    durationMilliseconds,
    startupMilliseconds: destination.startupMilliseconds,
    capacitySupported,
    acceptsSiteTransfer,
    transferProviderAvailable: provider !== undefined,
    transferMilliseconds: destination.transferMilliseconds,
    transferRequired: Object.freeze(transferRequired),
    sharedTransfer: Object.freeze(sharedTransfer),
    sourceRevoked: Object.freeze(sourceRevoked),
    estimateAvailable: Object.freeze(estimateAvailable),
    transferBytes: Object.freeze(transferBytes),
    retainedBytes: Object.freeze(retainedBytes),
    executionBytes: Object.freeze(executionBytes),
  }));
  if (!Array.isArray(plan) || plan.length !== 2 ||
      !Number.isSafeInteger(plan[0]) || typeof plan[1] !== 'bigint') {
    fail('InvalidExecutionSiteCandidate');
  }
  const exclusions = [undefined, 'MissingDurationEstimate',
    'ExecutionSiteCapacityEstimateExceeded',
    'UnsupportedTransferRepresentation', 'MissingTransferProvider',
    'SourceSiteRevoked', 'MissingTransferEstimate'];
  if (plan[0] !== 0) {
    const excluded = exclusions[plan[0] as number];
    if (excluded === undefined) fail('InvalidExecutionSiteCandidate');
    return Object.freeze({excluded, exclusionCode: plan[0] as number});
  }
  return Object.freeze({
    excluded: undefined,
    exclusionCode: 0,
    installation,
    contribution,
    site,
    siteIdentity: destination.identity,
    siteGeneration: destination.generation,
    runtimeRevision: destination.runtimeRevision,
    task,
    registration,
    inputs: Object.freeze([...inputs] as Input[]),
    inputSites: Object.freeze(inputSites),
    transfers: Object.freeze(transfers),
    capacity: Object.freeze({...capacity}),
    durationMilliseconds: plan[1] as bigint,
    selectionKey: `${contribution.managedSelectionKey}\u0000${destination.key}\u0000${destination.generation}`,
  });
}

// Binding occurs only after common candidate comparison. It rechecks exact
// placement, estimate, and MoonBit-owned Site state without starting I/O.
export function bindExecutionSiteCandidate(candidate: SiteCandidate | undefined) {
  if (!candidate || candidate.excluded !== undefined) {
    fail('ExecutionSiteCandidateExcluded', candidate?.excluded);
  }
  const installed = installations.get(candidate.installation) ??
    fail('ForeignExecutionSiteInstallation');
  const state = controlled(siteState(candidate.site));
  const provider = installed.policy.transferProvider;
  const inputsCurrent = candidate.inputSites.length === candidate.inputs.length &&
    candidate.inputSites.every((fixed, index) => {
      const source = controlled(siteState(candidate.inputs[index].site));
      return source.control === installed.control &&
        fixed.site === candidate.inputs[index].site &&
        source.identity === fixed.identity &&
        source.generation === fixed.generation &&
        source.runtimeRevision === fixed.runtimeRevision &&
        source.control.bindingCurrent(
          source.handle,
          fixed.generation,
          fixed.runtimeRevision,
        );
    });
  const transfersCurrent = candidate.transfers.every(planned => {
    if (!provider) return false;
    const current = provider.estimate(planned.input.siteMaterial);
    return current !== undefined &&
      current.transferBytes === planned.estimate.transferBytes &&
      current.retainedBytes === planned.estimate.retainedBytes &&
      current.executionBytes === planned.estimate.executionBytes;
  });
  if (!installed.placement.get(candidate.contribution)?.includes(candidate.site) ||
      candidate.contribution.registration !== candidate.registration ||
      state.control !== installed.control ||
      state.identity !== candidate.siteIdentity ||
      !state.control.bindingCurrent(
        state.handle,
        candidate.siteGeneration,
        candidate.runtimeRevision,
      ) || !inputsCurrent || !transfersCurrent) {
    fail('StaleExecutionSiteBinding');
  }
  const binding = Object.freeze({});
  bindings.set(binding, {candidate, state, consumed: false});
  return binding;
}

export function startExecutionSiteOperation(binding: object) {
  const bound = bindings.get(binding) ?? fail('ForeignExecutionSiteBinding');
  if (bound.consumed) fail('ExecutionSiteAdmissionRejected');
  const handle = bound.state.control.startOperation(
    bound.state.handle,
    bound.candidate.capacity.retainedBytes,
    bound.candidate.capacity.executionBytes,
  );
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteAdmissionRejected');
  }
  bound.consumed = true;
  const operation = Object.freeze({});
  operations.set(operation, {control: bound.state.control, handle});
  return operation;
}

export function settleExecutionSiteOperation(operation: object) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  return state.control.settleOperation(state.handle);
}

export function failedExecutionSiteOperationAction(
  operation: object,
  progress: FailureProgress,
) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  const action = state.control.failedOperationAction(progress);
  if (!Number.isSafeInteger(action) || action < 0 || action > 2) {
    fail('InvalidExecutionSiteFailureAction');
  }
  return action;
}

export function beginFailedExecutionSiteOperation(
  operation: object,
  cleanupRequired: boolean,
  alreadySettled: boolean,
) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  const progress = state.control.beginFailedOperation(
    cleanupRequired,
    alreadySettled,
  );
  if (progress === undefined || progress === null) {
    fail('InvalidExecutionSiteFailureProgress');
  }
  return progress;
}

export function recordFailedExecutionSiteOperationStop(operation: object, progress: FailureProgress) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (state.control.recordFailedOperationStop(progress) !== true) {
    fail('InvalidExecutionSiteFailureProgress');
  }
}

export function recordFailedExecutionSiteOperationSettlement(
  operation: object,
  progress: FailureProgress,
) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (state.control.recordFailedOperationSettlement(progress) !== true) {
    fail('InvalidExecutionSiteFailureProgress');
  }
}

export function beginRetainedExecutionSiteClose(authority: object) {
  const state = operations.get(authority) ?? installations.get(authority) ??
    fail('ForeignExecutionSiteCloseAuthority');
  const progress = state.control.beginRetainedClose();
  if (progress === undefined || progress === null) {
    fail('InvalidExecutionSiteHoldingProgress');
  }
  const owner = Object.freeze({});
  retainedCloseProgresses.set(owner, {control: state.control, progress});
  return owner;
}

export function beginRetainedExecutionSiteHolding(closeOwner: object, operation: object) {
  const close = retainedCloseProgresses.get(closeOwner) ??
    fail('ForeignExecutionSiteCloseProgress');
  const operationState = operations.get(operation) ??
    fail('ForeignExecutionSiteOperation');
  if (operationState.control !== close.control) {
    fail('ForeignExecutionSiteControl');
  }
  const progress = close.control.beginRetainedHolding(close.progress);
  if (progress === undefined || progress === null) {
    fail('InvalidExecutionSiteHoldingProgress');
  }
  const owner = Object.freeze({});
  retainedHoldingProgresses.set(owner, {closeOwner, control: close.control,
    progress});
  return owner;
}

function retainedClose(closeOwner: object) {
  return retainedCloseProgresses.get(closeOwner) ??
    fail('ForeignExecutionSiteCloseProgress');
}

function recordRetainedClose(closeOwner: object, method: RetainedCloseMethod) {
  const state = retainedClose(closeOwner);
  if (state.control[method](state.progress) !== true) {
    fail('InvalidExecutionSiteHoldingProgress');
  }
}

export function recordRetainedExecutionSiteCloseStarted(closeOwner: object) {
  recordRetainedClose(closeOwner, 'recordRetainedCloseStarted');
}

export function recordRetainedExecutionSiteCloseSucceeded(closeOwner: object) {
  recordRetainedClose(closeOwner, 'recordRetainedCloseSucceeded');
}

export function recordRetainedExecutionSiteCloseFailed(closeOwner: object) {
  recordRetainedClose(closeOwner, 'recordRetainedCloseFailed');
}

export function recordRetainedExecutionSiteCleanupAuthority(closeOwner: object) {
  recordRetainedClose(closeOwner, 'recordRetainedCleanupAuthority');
}

export function recordRetainedExecutionSiteCleanupStopped(closeOwner: object) {
  recordRetainedClose(closeOwner, 'recordRetainedCleanupStopped');
}

export function retainedExecutionSiteHoldingAction(holdingOwner: object) {
  const state = retainedHoldingProgresses.get(holdingOwner) ??
    fail('ForeignExecutionSiteHoldingProgress');
  const action = state.control.retainedHoldingAction(state.progress);
  if (!Number.isSafeInteger(action) || action < 0 || action > 5) {
    fail('InvalidExecutionSiteHoldingAction');
  }
  return action;
}

export function retainedExecutionSiteCloseAction(closeOwner: object) {
  const state = retainedClose(closeOwner);
  const action = state.control.retainedCloseAction(state.progress);
  if (!Number.isSafeInteger(action) || action < 0 || action > 4) {
    fail('InvalidExecutionSiteCloseAction');
  }
  return action;
}

export function recordRetainedExecutionSiteHoldingReleased(holdingOwner: object) {
  const state = retainedHoldingProgresses.get(holdingOwner) ??
    fail('ForeignExecutionSiteHoldingProgress');
  if (state.control.recordRetainedHoldingReleased(state.progress) !== true) {
    fail('InvalidExecutionSiteHoldingProgress');
  }
}

export function executionSiteHostCleanupAction(
  installation: object,
  progress: HostCleanupProgress,
  closesPending: boolean,
  knownCleanupPending: boolean,
  unconfirmedOwnership: boolean,
  cleanupFailed: boolean,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const action = state.control.hostCleanupAction(
    progress,
    closesPending,
    knownCleanupPending,
    unconfirmedOwnership,
    cleanupFailed,
  );
  if (!Number.isSafeInteger(action) || action < 0 || action > 4) {
    fail('InvalidExecutionSiteHostCleanupAction');
  }
  return action;
}

export function beginExecutionSiteHostCleanup(installation: object) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const progress = state.control.beginHostCleanup();
  if (progress === undefined || progress === null) {
    fail('InvalidExecutionSiteHostCleanupProgress');
  }
  return progress;
}

export function recordExecutionSiteHostCleanupRetry(
  installation: object,
  progress: HostCleanupProgress,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (state.control.recordHostCleanupRetry(progress) !== true) {
    fail('InvalidExecutionSiteHostCleanupProgress');
  }
}

export function recordExecutionSiteHostCleanupClosesAwaited(
  installation: object,
  progress: HostCleanupProgress,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (state.control.recordHostCleanupClosesAwaited(progress) !== true) {
    fail('InvalidExecutionSiteHostCleanupProgress');
  }
}

export function executionSiteHostCleanupPending(
  installation: object,
  closesPending: boolean,
  knownCleanupPending: boolean,
  unconfirmedOwnership: boolean,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const pending = state.control.hostCleanupPending(
    closesPending,
    knownCleanupPending,
    unconfirmedOwnership,
  );
  if (typeof pending !== 'boolean') {
    fail('InvalidExecutionSiteHostCleanupStatus');
  }
  return pending;
}

export function executionSiteHostTaskRunOutcome(
  installation: object,
  failed: boolean,
  runFinished: boolean,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const outcome = state.control.hostTaskRunOutcome(failed, runFinished);
  if (!Number.isSafeInteger(outcome) || outcome < 0 || outcome > 2) {
    fail('InvalidExecutionSiteHostTaskRunOutcome');
  }
  return outcome;
}

export function executionSiteHostTaskSuccessAction(
  installation: object,
  progress: HostSuccessProgress,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const action = state.control.hostTaskSuccessAction(progress);
  if (!Number.isSafeInteger(action) || action < 0 || action > 10) {
    fail('InvalidExecutionSiteHostTaskSuccessAction');
  }
  return action;
}

export function beginExecutionSiteHostTaskSuccess(
  installation: object,
  connectorOwnedOutput: boolean,
  managedBindingClaimed: boolean,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const progress = state.control.beginHostTaskSuccess(
    connectorOwnedOutput,
    managedBindingClaimed,
  );
  if (progress === undefined || progress === null) {
    fail('InvalidExecutionSiteHostTaskSuccessProgress');
  }
  return progress;
}

function recordHostTaskSuccessFact(installation: object, method: HostSuccessMethod, progress: HostSuccessProgress, value: readonly [] | readonly [boolean]) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if ((state.control[method] as (progress: HostSuccessProgress, ...value: readonly boolean[]) => boolean)(progress, ...value) !== true) {
    fail('InvalidExecutionSiteHostTaskSuccessProgress');
  }
}

export function recordExecutionSiteHostTaskSiteCompletion(
  installation: object,
  progress: HostSuccessProgress,
  ready: boolean,
) {
  recordHostTaskSuccessFact(
    installation, 'recordHostTaskSiteCompletion', progress, [ready],
  );
}

export function recordExecutionSiteHostTaskCommonCompletion(
  installation: object,
  progress: HostSuccessProgress,
  completed: boolean,
) {
  recordHostTaskSuccessFact(
    installation, 'recordHostTaskCommonCompletion', progress, [completed],
  );
}

export function recordExecutionSiteHostTaskOutputRetained(
  installation: object,
  progress: HostSuccessProgress,
) {
  recordHostTaskSuccessFact(
    installation, 'recordHostTaskOutputRetained', progress, [],
  );
}

export function recordExecutionSiteHostTaskSiteOperationSettled(
  installation: object,
  progress: HostSuccessProgress,
) {
  recordHostTaskSuccessFact(
    installation, 'recordHostTaskSiteOperationSettled', progress, [],
  );
}

export function recordExecutionSiteHostTaskManagedBinding(
  installation: object,
  progress: HostSuccessProgress,
  valid: boolean,
) {
  recordHostTaskSuccessFact(
    installation, 'recordHostTaskManagedBinding', progress, [valid],
  );
}

export function executionSiteHostTaskSiteOperationSettled(
  installation: object,
  progress: HostSuccessProgress,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const settled = state.control.hostTaskSiteOperationSettled(progress);
  if (typeof settled !== 'boolean') {
    fail('InvalidExecutionSiteHostTaskSuccessProgress');
  }
  return settled;
}

export function retainExecutionSiteOperationHolding(operation: object, value: unknown, valueBytes: bigint) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (value == null || !bytes(valueBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainOperationHolding(state.handle, valueBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function executionSiteOperationAvailable(operation: object) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  return state.control.operationAvailable(state.handle);
}

export function startExecutionSiteTransferOperation(
  sourceSite: object,
  destinationSite: object,
  capacity: Capacity = Object.freeze({retainedBytes: 0n, executionBytes: 0n}),
) {
  const source = controlled(siteState(sourceSite));
  const destination = controlled(siteState(destinationSite));
  if (source.control !== destination.control ||
      !bytes(capacity?.retainedBytes) || !bytes(capacity?.executionBytes)) {
    fail(source.control !== destination.control
      ? 'ForeignExecutionSiteControl'
      : 'InvalidExecutionSiteTransferCapacity');
  }
  const handle = source.control.startTransfer(
    source.handle,
    destination.handle,
    capacity.retainedBytes,
    capacity.executionBytes,
  );
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteTransferAdmissionRejected');
  }
  const operation = Object.freeze({});
  transferOperations.set(operation, {control: source.control, handle});
  return operation;
}

export function executionSiteTransferOperationAvailable(operation: object) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.transferAvailable(state.handle);
}

export function settleExecutionSiteTransferSource(operation: object) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.settleTransferSource(state.handle);
}

export function settleExecutionSiteTransferDestination(operation: object) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.settleTransferDestination(state.handle);
}

export function retainExecutionSiteTransferHolding(
  operation: object,
  value: unknown,
  valueBytes: bigint,
) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  if (value == null || !bytes(valueBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainTransferHolding(state.handle, valueBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function retainExecutionSiteHolding(site: object, value: unknown, retainedBytes = 0n) {
  const state = controlled(siteState(site));
  if (value == null || !bytes(retainedBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainHolding(state.handle, retainedBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function releaseExecutionSiteHolding(holding: object) {
  const held = holdings.get(holding) ?? fail('ForeignExecutionSiteHolding');
  return held.control.releaseHolding(held.handle);
}

export function retainExecutionSiteCleanup(site: object, value: unknown) {
  const state = controlled(siteState(site));
  if (value == null) fail('ExecutionSiteCleanupRejected');
  const handle = state.control.retainCleanup(state.handle);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteCleanupRejected');
  }
  const cleanup = Object.freeze({});
  cleanupResponsibilities.set(cleanup, {control: state.control, handle, value});
  return cleanup;
}

export function releaseExecutionSiteCleanup(cleanup: object) {
  const owned = cleanupResponsibilities.get(cleanup) ??
    fail('ForeignExecutionSiteCleanup');
  return owned.control.releaseCleanup(owned.handle);
}

export function beginExecutionSiteTeardown(site: unknown) {
  const state = siteState(site);
  state.pendingTeardown = true;
  if (state.control !== undefined) state.control.beginTeardown(state.handle!);
  return executionSiteStatus(site);
}

export function revokeExecutionSite(site: unknown) {
  const state = siteState(site);
  state.pendingTeardown = true;
  state.pendingRevocation = true;
  if (state.control !== undefined) state.control.revoke(state.handle!);
  return executionSiteStatus(site);
}

export function executionSiteStatus(site: unknown) {
  const state = siteState(site);
  if (state.control === undefined) {
    return Object.freeze({
      key: state.key,
      generation: state.generation,
      accepting: !state.pendingTeardown && !state.pendingRevocation,
      revoked: state.pendingRevocation,
      activeOperations: 0,
      activeTransfers: 0,
      holdings: 0,
      cleanupResponsibilities: 0,
      heldBytes: 0n,
      reservedRetentionBytes: 0n,
      reservedExecutionBytes: 0n,
      peakRetainedBytes: 0n,
      teardownComplete: state.pendingTeardown,
    });
  }
  const values = state.control.status(state.handle!);
  if (!Array.isArray(values) || values.length !== 11 ||
      values.some(value => typeof value !== 'bigint')) {
    fail('InvalidExecutionSiteStatus');
  }
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    accepting: values[0] === 1n,
    revoked: values[1] === 1n,
    activeOperations: Number(values[2]),
    activeTransfers: Number(values[3]),
    holdings: Number(values[4]),
    cleanupResponsibilities: Number(values[5]),
    heldBytes: values[6],
    reservedRetentionBytes: values[7],
    reservedExecutionBytes: values[8],
    peakRetainedBytes: values[9],
    teardownComplete: values[10] === 1n,
  });
}
