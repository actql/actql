import {tuplePair} from './runtime-tuple.mjs';
import type {SiteControl, SiteHoldingRestoration} from './execution-sites.mjs';

type Facts = Parameters<SiteControl['planCandidate']>[0];

// Directly exported Common functions keep their existing callable view.
// Only the configuration, candidate selection, and tuple projection have
// an adapter call. These types do not issue or unwrap Site custody values.
type CommonSiteBindings = {
  strategySiteCreate(
    key: string, generation: number, runtimeRevision: string, maxConcurrentOperations: number,
    maxConcurrentTransfers: number, maxRetainedBytes: bigint, maxExecutionBytes: bigint,
  ): ReturnType<SiteControl['create']>;
  strategySitePrepareHoldingRestoration(
    site: Parameters<SiteControl['retainHolding']>[0], bytes: bigint,
  ): SiteHoldingRestoration | undefined;
  strategySiteAcquireRestoredHolding(
    restoration: SiteHoldingRestoration,
  ): ReturnType<SiteControl['retainHolding']>;
  strategySiteSelectCandidate(durations: readonly bigint[], keys: readonly string[]): number;
  strategySitePlanCandidate(
    durationMilliseconds: bigint | undefined, startupMilliseconds: Facts['startupMilliseconds'],
    capacitySupported: boolean, acceptsSiteTransfer: boolean, transferProviderAvailable: boolean,
    transferMilliseconds: Facts['transferMilliseconds'], transferRequired: Facts['transferRequired'],
    sharedTransfer: Facts['sharedTransfer'], sourceRevoked: Facts['sourceRevoked'],
    estimateAvailable: Facts['estimateAvailable'], transferBytes: Facts['transferBytes'],
    retainedBytes: Facts['retainedBytes'], executionBytes: Facts['executionBytes'],
  ): unknown;
  strategySiteAvailable: SiteControl['available'];
  strategySiteRevoked: SiteControl['revoked'];
  strategySiteCapacitySupports: SiteControl['capacitySupports'];
  strategySiteBindingCurrent: SiteControl['bindingCurrent'];
  strategySiteStartOperation: SiteControl['startOperation'];
  strategySiteOperationAvailable: SiteControl['operationAvailable'];
  strategySiteSettleOperation: SiteControl['settleOperation'];
  strategySiteRetainOperationHolding: SiteControl['retainOperationHolding'];
  strategySiteStartTransfer: SiteControl['startTransfer'];
  strategySiteTransferAvailable: SiteControl['transferAvailable'];
  strategySiteSettleTransferSource: SiteControl['settleTransferSource'];
  strategySiteSettleTransferDestination: SiteControl['settleTransferDestination'];
  strategySiteRetainTransferHolding: SiteControl['retainTransferHolding'];
  strategySiteRetainHolding: SiteControl['retainHolding'];
  strategySiteReleaseHolding: SiteControl['releaseHolding'];
  strategySiteRetainCleanup: SiteControl['retainCleanup'];
  strategySiteReleaseCleanup: SiteControl['releaseCleanup'];
  strategySiteBeginTeardown: SiteControl['beginTeardown'];
  strategySiteRevoke: SiteControl['revoke'];
  strategySiteStatus: SiteControl['status'];
  strategySiteManagedCandidateFallback: SiteControl['managedCandidateFallback'];
  strategySiteBeginFailedOperationProgress: SiteControl['beginFailedOperation'];
  strategySiteRecordFailedOperationStop: SiteControl['recordFailedOperationStop'];
  strategySiteRecordFailedOperationSettlement: SiteControl['recordFailedOperationSettlement'];
  strategySiteFailedOperationAction: SiteControl['failedOperationAction'];
  strategySiteBeginRetainedCloseProgress: SiteControl['beginRetainedClose'];
  strategySiteBeginRetainedHoldingProgress: SiteControl['beginRetainedHolding'];
  strategySiteRecordRetainedCloseStarted: SiteControl['recordRetainedCloseStarted'];
  strategySiteRecordRetainedCloseSucceeded: SiteControl['recordRetainedCloseSucceeded'];
  strategySiteRecordRetainedCloseFailed: SiteControl['recordRetainedCloseFailed'];
  strategySiteRecordRetainedCleanupAuthority: SiteControl['recordRetainedCleanupAuthority'];
  strategySiteRecordRetainedCleanupStopped: SiteControl['recordRetainedCleanupStopped'];
  strategySiteRecordRetainedHoldingReleased: SiteControl['recordRetainedHoldingReleased'];
  strategySiteRetainedCloseAction: SiteControl['retainedCloseAction'];
  strategySiteRetainedHoldingAction: SiteControl['retainedHoldingAction'];
  strategyHostBeginCleanupProgress: SiteControl['beginHostCleanup'];
  strategyHostRecordCleanupRetry: SiteControl['recordHostCleanupRetry'];
  strategyHostRecordCleanupClosesAwaited: SiteControl['recordHostCleanupClosesAwaited'];
  strategyHostCleanupAction: SiteControl['hostCleanupAction'];
  strategyHostCleanupPending: SiteControl['hostCleanupPending'];
  strategyHostTaskRunOutcome: SiteControl['hostTaskRunOutcome'];
  strategyHostBeginTaskSuccessProgress: SiteControl['beginHostTaskSuccess'];
  strategyHostRecordTaskSiteCompletion: SiteControl['recordHostTaskSiteCompletion'];
  strategyHostRecordTaskCommonCompletion: SiteControl['recordHostTaskCommonCompletion'];
  strategyHostRecordTaskOutputRetained: SiteControl['recordHostTaskOutputRetained'];
  strategyHostRecordTaskSiteOperationSettled: SiteControl['recordHostTaskSiteOperationSettled'];
  strategyHostRecordTaskManagedBinding: SiteControl['recordHostTaskManagedBinding'];
  strategyHostTaskSiteOperationSettled: SiteControl['hostTaskSiteOperationSettled'];
  strategyHostTaskSuccessAction: SiteControl['hostTaskSuccessAction'];
};

type RuntimeSiteControl = SiteControl & Readonly<{
  prepareHoldingRestoration: CommonSiteBindings['strategySitePrepareHoldingRestoration'];
  acquireRestoredHolding: CommonSiteBindings['strategySiteAcquireRestoredHolding'];
}>;

const siteControls = new WeakMap<object, RuntimeSiteControl>();

export function siteControl(moon: CommonSiteBindings): RuntimeSiteControl {
  let control = siteControls.get(moon);
  if (control !== undefined) return control;
  control = createSiteControl(moon);
  siteControls.set(moon, control);
  return control;
}

function createSiteControl(moon: CommonSiteBindings): RuntimeSiteControl {
  return Object.freeze({
    create: (configuration: Parameters<SiteControl['create']>[0]) => moon.strategySiteCreate(
      configuration.key,
      configuration.generation,
      configuration.runtimeRevision,
      configuration.maxConcurrentOperations,
      configuration.maxConcurrentTransfers,
      configuration.maxRetainedBytes,
      configuration.maxExecutionBytes,
    ),
    available: moon.strategySiteAvailable,
    revoked: moon.strategySiteRevoked,
    capacitySupports: moon.strategySiteCapacitySupports,
    bindingCurrent: moon.strategySiteBindingCurrent,
    startOperation: moon.strategySiteStartOperation,
    operationAvailable: moon.strategySiteOperationAvailable,
    settleOperation: moon.strategySiteSettleOperation,
    retainOperationHolding: moon.strategySiteRetainOperationHolding,
    startTransfer: moon.strategySiteStartTransfer,
    transferAvailable: moon.strategySiteTransferAvailable,
    settleTransferSource: moon.strategySiteSettleTransferSource,
    settleTransferDestination: moon.strategySiteSettleTransferDestination,
    retainTransferHolding: moon.strategySiteRetainTransferHolding,
    retainHolding: moon.strategySiteRetainHolding,
    prepareHoldingRestoration: moon.strategySitePrepareHoldingRestoration,
    acquireRestoredHolding: moon.strategySiteAcquireRestoredHolding,
    releaseHolding: moon.strategySiteReleaseHolding,
    retainCleanup: moon.strategySiteRetainCleanup,
    releaseCleanup: moon.strategySiteReleaseCleanup,
    beginTeardown: moon.strategySiteBeginTeardown,
    revoke: moon.strategySiteRevoke,
    status: moon.strategySiteStatus,
    selectCandidate: (
      durations: Parameters<SiteControl['selectCandidate']>[0],
      keys: Parameters<SiteControl['selectCandidate']>[1],
    ) =>
      moon.strategySiteSelectCandidate(
        durations.map(value => value ?? undefined), keys),
    planCandidate: (value: Facts) => tuplePair(
      moon.strategySitePlanCandidate(
        value.durationMilliseconds ?? undefined,
        value.startupMilliseconds,
        value.capacitySupported,
        value.acceptsSiteTransfer,
        value.transferProviderAvailable,
        value.transferMilliseconds,
        value.transferRequired,
        value.sharedTransfer,
        value.sourceRevoked,
        value.estimateAvailable,
        value.transferBytes,
        value.retainedBytes,
        value.executionBytes,
      ),
    ) as ReturnType<SiteControl['planCandidate']>,
    managedCandidateFallback: moon.strategySiteManagedCandidateFallback,
    beginFailedOperation: moon.strategySiteBeginFailedOperationProgress,
    recordFailedOperationStop: moon.strategySiteRecordFailedOperationStop,
    recordFailedOperationSettlement:
      moon.strategySiteRecordFailedOperationSettlement,
    failedOperationAction: moon.strategySiteFailedOperationAction,
    beginRetainedClose: moon.strategySiteBeginRetainedCloseProgress,
    beginRetainedHolding: moon.strategySiteBeginRetainedHoldingProgress,
    recordRetainedCloseStarted:
      moon.strategySiteRecordRetainedCloseStarted,
    recordRetainedCloseSucceeded:
      moon.strategySiteRecordRetainedCloseSucceeded,
    recordRetainedCloseFailed:
      moon.strategySiteRecordRetainedCloseFailed,
    recordRetainedCleanupAuthority:
      moon.strategySiteRecordRetainedCleanupAuthority,
    recordRetainedCleanupStopped:
      moon.strategySiteRecordRetainedCleanupStopped,
    recordRetainedHoldingReleased:
      moon.strategySiteRecordRetainedHoldingReleased,
    retainedCloseAction: moon.strategySiteRetainedCloseAction,
    retainedHoldingAction: moon.strategySiteRetainedHoldingAction,
    beginHostCleanup: moon.strategyHostBeginCleanupProgress,
    recordHostCleanupRetry: moon.strategyHostRecordCleanupRetry,
    recordHostCleanupClosesAwaited:
      moon.strategyHostRecordCleanupClosesAwaited,
    hostCleanupAction: moon.strategyHostCleanupAction,
    hostCleanupPending: moon.strategyHostCleanupPending,
    hostTaskRunOutcome: moon.strategyHostTaskRunOutcome,
    beginHostTaskSuccess: moon.strategyHostBeginTaskSuccessProgress,
    recordHostTaskSiteCompletion:
      moon.strategyHostRecordTaskSiteCompletion,
    recordHostTaskCommonCompletion:
      moon.strategyHostRecordTaskCommonCompletion,
    recordHostTaskOutputRetained:
      moon.strategyHostRecordTaskOutputRetained,
    recordHostTaskSiteOperationSettled:
      moon.strategyHostRecordTaskSiteOperationSettled,
    recordHostTaskManagedBinding:
      moon.strategyHostRecordTaskManagedBinding,
    hostTaskSiteOperationSettled:
      moon.strategyHostTaskSiteOperationSettled,
    hostTaskSuccessAction: moon.strategyHostTaskSuccessAction,
  });
}
