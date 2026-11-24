import {publicationAction} from './publication-action.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type CommonObject = Extract<SynchronousRuntimeData, object>;

// Common retains the publication decisions and the opaque Result progress.
type CommonPublicationProgressBindings = {
  strategyBeginResultAccessProgress(): CommonObject;
  strategyCommittedPublicationFinalizationAction(record: unknown): number;
  strategyDeliveryFailureTerminalAction(cancellationObserved: boolean): number;
  strategyDeliveryRecordRetryAction(nextRecord: number, recordCount: number): number;
  strategyExistingDeliveryAttemptAction(record: unknown): number;
  strategyPublicationAttemptAction(record: unknown, activeChecked: boolean, indexIssued: boolean): number;
  strategyPublicationCancellationAction(record: unknown): number;
  strategyPublicationCleanupOwnerAction(
    currentIndex: number, ownerCount: number, statusChecked: boolean,
    pending: boolean, retryAvailable: boolean, retryAttempted: boolean,
  ): number;
  strategyPublicationCommitFailureAction(
    reconciliationAttempted: boolean, reconciliationFailed: boolean,
    committedFound: boolean, unknownAppendAttempted: boolean,
  ): number;
  strategyPublicationPreparedReleaseAction(
    currentIndex: number, ownerCount: number,
    statusChecked: boolean, pending: boolean, releaseAttempted: boolean,
  ): number;
  strategyPublicationSetupAction(
    existingChecked: boolean, existingFound: boolean, existingEvidenceValidated: boolean,
    existingFinalized: boolean, initialActiveChecked: boolean, contractsPersisted: boolean, attemptCreated: boolean,
  ): number;
  strategyPublicationUnknownRetryAction(
    reconciliationResolved: boolean, upstreamPending: boolean,
    upstreamRetryAvailable: boolean, upstreamRetryAttempted: boolean,
  ): number;
  strategyRecordResultAccessGrant(progress: CommonObject, issued: boolean): boolean;
  strategyRecordResultAccessInitialAvailability(progress: CommonObject, available: boolean): boolean;
  strategyRecordResultAccessReadAdmission(progress: CommonObject, admitted: boolean): boolean;
  strategyRecordResultAccessRequestAuthorization(progress: CommonObject, authorized: boolean): boolean;
  strategyRecordResultAccessResolution(progress: CommonObject, resolved: boolean): boolean;
  strategyResultAccessProgressAction(progress: CommonObject): number;
  strategySupersededPublicationFinalizationAction(record: unknown): number;
};

export function publicationProgressControl(
  moon: CommonPublicationProgressBindings, token: (contract: unknown) => unknown,
) {
  return {
    publicationAttemptAction(record: unknown, activeChecked: boolean, indexIssued: boolean) {
      return publicationAction('attempt', moon.strategyPublicationAttemptAction(
        record === undefined ? undefined : token(record),
        activeChecked,
        indexIssued,
      ));
    },
    publicationSetupAction(
      existingChecked: boolean,
      existingFound: boolean,
      existingEvidenceValidated: boolean,
      existingFinalized: boolean,
      initialActiveChecked: boolean,
      contractsPersisted: boolean,
      attemptCreated: boolean,
    ) {
      return publicationAction('setup', moon.strategyPublicationSetupAction(
        existingChecked,
        existingFound,
        existingEvidenceValidated,
        existingFinalized,
        initialActiveChecked,
        contractsPersisted,
        attemptCreated,
      ));
    },
    publicationCancellationAction(record: unknown) {
      return publicationAction('cancellation',
        moon.strategyPublicationCancellationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    committedPublicationFinalizationAction(record: unknown) {
      return publicationAction('finalization',
        moon.strategyCommittedPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    supersededPublicationFinalizationAction(record: unknown) {
      return publicationAction('finalization',
        moon.strategySupersededPublicationFinalizationAction(
          record === undefined ? undefined : token(record),
        ));
    },
    publicationCommitFailureAction(
      reconciliationAttempted: boolean,
      reconciliationFailed: boolean,
      committedFound: boolean,
      unknownAppendAttempted: boolean,
    ) {
      return publicationAction('commitFailure',
        moon.strategyPublicationCommitFailureAction(
          reconciliationAttempted,
          reconciliationFailed,
          committedFound,
          unknownAppendAttempted,
        ));
    },
    publicationUnknownRetryAction(
      reconciliationResolved: boolean,
      upstreamPending: boolean,
      upstreamRetryAvailable: boolean,
      upstreamRetryAttempted: boolean,
    ) {
      return publicationAction('unknownRetry',
        moon.strategyPublicationUnknownRetryAction(
          reconciliationResolved,
          upstreamPending,
          upstreamRetryAvailable,
          upstreamRetryAttempted,
        ));
    },
    existingDeliveryAttemptAction(record: unknown) {
      return publicationAction('existingDelivery',
        moon.strategyExistingDeliveryAttemptAction(
          record === undefined ? undefined : token(record),
        ));
    },
    beginResultAccessProgress() {
      return moon.strategyBeginResultAccessProgress();
    },
    resultAccessProgressAction(progress: CommonObject) {
      return publicationAction('resultAccess',
        moon.strategyResultAccessProgressAction(progress));
    },
    recordResultAccessRequestAuthorization(progress: CommonObject, authorized: boolean) {
      if (!moon.strategyRecordResultAccessRequestAuthorization(
        progress, authorized,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessResolution(progress: CommonObject, resolved: boolean) {
      if (!moon.strategyRecordResultAccessResolution(progress, resolved)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessInitialAvailability(progress: CommonObject, available: boolean) {
      if (!moon.strategyRecordResultAccessInitialAvailability(
        progress, available,
      )) throw new TypeError('Invalid Result access progression');
    },
    recordResultAccessReadAdmission(progress: CommonObject, admitted: boolean) {
      if (!moon.strategyRecordResultAccessReadAdmission(progress, admitted)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    recordResultAccessGrant(progress: CommonObject, issued: boolean) {
      if (!moon.strategyRecordResultAccessGrant(progress, issued)) {
        throw new TypeError('Invalid Result access progression');
      }
    },
    deliveryFailureTerminalAction(cancellationObserved: boolean) {
      return publicationAction('failureTerminal',
        moon.strategyDeliveryFailureTerminalAction(cancellationObserved));
    },
    deliveryRecordRetryAction(nextRecord: number, recordCount: number) {
      return publicationAction('recordRetry',
        moon.strategyDeliveryRecordRetryAction(nextRecord, recordCount));
    },
    publicationPreparedReleaseAction(
      currentIndex: number,
      ownerCount: number,
      statusChecked: boolean,
      pending: boolean,
      releaseAttempted: boolean,
    ) {
      return publicationAction('preparedRelease',
        moon.strategyPublicationPreparedReleaseAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          releaseAttempted,
        ));
    },
    publicationCleanupOwnerAction(
      currentIndex: number,
      ownerCount: number,
      statusChecked: boolean,
      pending: boolean,
      retryAvailable: boolean,
      retryAttempted: boolean,
    ) {
      return publicationAction('cleanupOwner',
        moon.strategyPublicationCleanupOwnerAction(
          currentIndex,
          ownerCount,
          statusChecked,
          pending,
          retryAvailable,
          retryAttempted,
        ));
    },
  };
}
