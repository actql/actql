// Independent protocol fixture for adapter tests. Product execution never
// imports this file; the portable MoonBit execution_site package is the sole
// product authority for these transitions.
export function createExecutionSiteControlFixture() {
  const available = site => site.accepting && !site.revoked;
  const status = site => [
    available(site) ? 1n : 0n,
    site.revoked ? 1n : 0n,
    BigInt(site.activeOperations),
    BigInt(site.activeTransfers),
    BigInt(site.holdings),
    BigInt(site.cleanup),
    site.held,
    site.reservedRetention,
    site.reservedExecution,
    site.peak,
    !site.accepting && site.activeOperations === 0 &&
      site.activeTransfers === 0 && site.holdings === 0 &&
      site.cleanup === 0 && site.held === 0n &&
      site.reservedRetention === 0n && site.reservedExecution === 0n
      ? 1n : 0n,
  ];
  return Object.freeze({
    create(configuration) {
      return {
        ...configuration,
        accepting: true,
        revoked: false,
        activeOperations: 0,
        activeTransfers: 0,
        holdings: 0,
        cleanup: 0,
        held: 0n,
        reservedRetention: 0n,
        reservedExecution: 0n,
        peak: 0n,
      };
    },
    available,
    revoked: site => site.revoked,
    capacitySupports: (site, retained, execution) =>
      retained >= 0n && execution >= 0n &&
      retained <= site.maxRetainedBytes &&
      execution <= site.maxExecutionBytes,
    bindingCurrent: (site, generation, revision) =>
      available(site) && site.generation === generation &&
      site.runtimeRevision === revision,
    startOperation(site, retained, execution) {
      if (!available(site) ||
          site.activeOperations >= site.maxConcurrentOperations ||
          retained > site.maxRetainedBytes - site.held -
            site.reservedRetention ||
          execution > site.maxExecutionBytes - site.reservedExecution) {
        return undefined;
      }
      site.activeOperations++;
      site.reservedRetention += retained;
      site.reservedExecution += execution;
      site.peak = site.peak > site.held + site.reservedRetention
        ? site.peak : site.held + site.reservedRetention;
      return {site, retained, execution, stopped: false, holding: false};
    },
    operationAvailable: value => !value.stopped && !value.site.revoked,
    settleOperation(value) {
      if (value.stopped) return false;
      value.stopped = true;
      value.site.activeOperations--;
      value.site.reservedRetention -= value.retained;
      value.site.reservedExecution -= value.execution;
      value.retained = 0n;
      value.execution = 0n;
      return true;
    },
    retainOperationHolding(value, bytes) {
      if (value.stopped || value.holding || bytes > value.retained) {
        return undefined;
      }
      value.holding = true;
      value.retained -= bytes;
      value.site.reservedRetention -= bytes;
      value.site.held += bytes;
      value.site.holdings++;
      return {site: value.site, bytes, live: true};
    },
    startTransfer(source, destination, retained, execution) {
      const same = source === destination;
      if (!available(source) || !available(destination) ||
          source.activeTransfers >= source.maxConcurrentTransfers ||
          !same &&
            destination.activeTransfers >= destination.maxConcurrentTransfers ||
          retained > destination.maxRetainedBytes - destination.held -
            destination.reservedRetention ||
          execution > destination.maxExecutionBytes -
            destination.reservedExecution) {
        return undefined;
      }
      source.activeTransfers++;
      if (!same) destination.activeTransfers++;
      destination.reservedRetention += retained;
      destination.reservedExecution += execution;
      destination.peak = destination.peak >
        destination.held + destination.reservedRetention
        ? destination.peak
        : destination.held + destination.reservedRetention;
      return {source, destination, retained, execution,
        sourceStopped: false, destinationStopped: false, holding: false};
    },
    transferAvailable: value => !value.sourceStopped &&
      !value.destinationStopped && !value.source.revoked &&
      !value.destination.revoked,
    settleTransferSource(value) {
      if (value.sourceStopped) return false;
      value.sourceStopped = true;
      if (value.source !== value.destination || value.destinationStopped) {
        value.source.activeTransfers--;
      }
      return true;
    },
    settleTransferDestination(value) {
      if (value.destinationStopped) return false;
      value.destinationStopped = true;
      value.destination.reservedRetention -= value.retained;
      value.destination.reservedExecution -= value.execution;
      value.retained = 0n;
      value.execution = 0n;
      if (value.source !== value.destination || value.sourceStopped) {
        value.destination.activeTransfers--;
      }
      return true;
    },
    retainTransferHolding(value, bytes) {
      if (value.source.revoked || value.destination.revoked ||
          value.destinationStopped || value.holding || bytes > value.retained) {
        return undefined;
      }
      value.holding = true;
      value.retained -= bytes;
      value.destination.reservedRetention -= bytes;
      value.destination.held += bytes;
      value.destination.holdings++;
      return {site: value.destination, bytes, live: true};
    },
    retainHolding(site, bytes) {
      if (site.revoked || bytes > site.maxRetainedBytes - site.held -
          site.reservedRetention) return undefined;
      site.held += bytes;
      site.holdings++;
      site.peak = site.peak > site.held ? site.peak : site.held;
      return {site, bytes, live: true};
    },
    releaseHolding(value) {
      if (!value.live) return false;
      value.live = false;
      value.site.held -= value.bytes;
      value.site.holdings--;
      return true;
    },
    retainCleanup(site) {
      site.cleanup++;
      return {site, live: true};
    },
    releaseCleanup(value) {
      if (!value.live) return false;
      value.live = false;
      value.site.cleanup--;
      return true;
    },
    beginTeardown(site) { site.accepting = false; },
    revoke(site) { site.accepting = false; site.revoked = true; },
    status,
    selectCandidate(durations, keys) {
      if (!Array.isArray(durations) || !Array.isArray(keys) ||
          durations.length !== keys.length) return -2;
      let selected = -1;
      for (let index = 0; index < durations.length; index++) {
        if (typeof durations[index] !== 'bigint' || durations[index] < 0n ||
            typeof keys[index] !== 'string' || keys[index].length === 0) {
          return -2;
        }
        if (keys.indexOf(keys[index]) !== index) return -3;
        if (selected < 0 || durations[index] < durations[selected] ||
            durations[index] === durations[selected] &&
              keys[index] < keys[selected]) {
          selected = index;
        }
      }
      return selected;
    },
    planCandidate(value) {
      const length = value.transferRequired.length;
      if (![value.sharedTransfer, value.sourceRevoked,
        value.estimateAvailable, value.transferBytes, value.retainedBytes,
        value.executionBytes].every(array => array.length === length)) {
        return [7, 0n];
      }
      if (value.durationMilliseconds === null ||
          value.startupMilliseconds === null) return [1, 0n];
      if (!value.capacitySupported) return [2, 0n];
      let duration = value.durationMilliseconds + value.startupMilliseconds;
      for (let index = 0; index < length; index++) {
        if (!value.transferRequired[index]) continue;
        if (!value.acceptsSiteTransfer) return [3, 0n];
        if (!value.transferProviderAvailable) return [4, 0n];
        if (value.sourceRevoked[index]) return [5, 0n];
        if (!value.estimateAvailable[index]) return [6, 0n];
        if (!value.sharedTransfer[index]) {
          if (value.transferMilliseconds === null) return [1, 0n];
          duration += value.transferMilliseconds;
        }
      }
      return [0, duration];
    },
    managedCandidateFallback(retainedInputCount, exclusionCodes) {
      if (!Number.isSafeInteger(retainedInputCount) || retainedInputCount < 0 ||
          !Array.isArray(exclusionCodes)) return 4;
      if (retainedInputCount === 0) return 0;
      if (exclusionCodes.some(code => ![1, 2, 3, 4, 5, 6, 8]
        .includes(code))) return 4;
      if (exclusionCodes.some(code => code === 1 || code === 6)) return 1;
      if (exclusionCodes.some(code => [3, 4, 5].includes(code))) return 2;
      return 3;
    },
    beginFailedOperation(cleanupRequired, alreadySettled) {
      return {
        cleanupRequired,
        cleanupStopped: false,
        operationSettled: alreadySettled,
      };
    },
    recordFailedOperationStop(progress) {
      if (!progress.cleanupRequired) return false;
      progress.cleanupStopped = true;
      return true;
    },
    recordFailedOperationSettlement(progress) {
      if (progress.operationSettled ||
          (progress.cleanupRequired && !progress.cleanupStopped)) return false;
      progress.operationSettled = true;
      return true;
    },
    failedOperationAction(progress) {
      if (progress.operationSettled) return 2;
      if (progress.cleanupRequired && !progress.cleanupStopped) return 0;
      return 1;
    },
    retainedHoldingAction(
      closeStarted,
      closeSucceeded,
      closeFailed,
      cleanupAuthority,
      cleanupStopped,
      holdingReleased,
    ) {
      if ((closeSucceeded && closeFailed) ||
          (cleanupStopped && !cleanupAuthority) ||
          ((closeSucceeded || closeFailed || cleanupAuthority) &&
            !closeStarted) ||
          (holdingReleased && !closeStarted)) return 5;
      if (holdingReleased) return 4;
      if (!closeStarted) return 0;
      if (closeSucceeded ||
          (closeFailed && cleanupAuthority && cleanupStopped)) return 3;
      if (closeFailed) return 2;
      return 1;
    },
    beginHostCleanup() {
      return {
        initialRetryDone: false,
        closesAwaited: false,
        finalRetryDone: false,
      };
    },
    recordHostCleanupRetry(progress) {
      if (!progress.initialRetryDone) {
        progress.initialRetryDone = true;
        return true;
      }
      if (!progress.finalRetryDone) {
        progress.finalRetryDone = true;
        return true;
      }
      return false;
    },
    recordHostCleanupClosesAwaited(progress) {
      if (!progress.initialRetryDone || progress.closesAwaited) return false;
      progress.closesAwaited = true;
      return true;
    },
    hostCleanupAction(
      progress,
      closesPending,
      knownCleanupPending,
      unconfirmedOwnership,
      cleanupFailed,
    ) {
      if (!progress.initialRetryDone) return 0;
      if (closesPending && !progress.closesAwaited) return 1;
      if (!progress.finalRetryDone) return 0;
      if (cleanupFailed) return 3;
      if (closesPending || knownCleanupPending || unconfirmedOwnership) {
        return 2;
      }
      return 4;
    },
    hostCleanupPending: (
      closesPending,
      knownCleanupPending,
      unconfirmedOwnership,
    ) => closesPending || knownCleanupPending || unconfirmedOwnership,
    hostTaskRunOutcome(failed, runFinished) {
      if (failed) return 1;
      if (runFinished) return 0;
      return 2;
    },
    beginHostTaskSuccess(connectorOwnedOutput, managedBindingClaimed) {
      return {
        connectorOwnedOutput,
        managedBindingClaimed,
        siteCompletionChecked: false,
        siteCompletionReady: false,
        commonCompletionChecked: false,
        commonCompleted: false,
        outputRetained: false,
        siteOperationSettled: false,
        managedBindingChecked: false,
        managedBindingValid: false,
      };
    },
    recordHostTaskSiteCompletion(progress, ready) {
      if (progress.siteCompletionChecked) return false;
      progress.siteCompletionChecked = true;
      progress.siteCompletionReady = ready;
      return true;
    },
    recordHostTaskCommonCompletion(progress, completed) {
      if (!progress.siteCompletionChecked ||
          !progress.siteCompletionReady ||
          progress.commonCompletionChecked) return false;
      progress.commonCompletionChecked = true;
      progress.commonCompleted = completed;
      return true;
    },
    recordHostTaskOutputRetained(progress) {
      if (!progress.commonCompletionChecked || !progress.commonCompleted ||
          progress.outputRetained) return false;
      progress.outputRetained = true;
      return true;
    },
    recordHostTaskSiteOperationSettled(progress) {
      if (!progress.outputRetained || progress.siteOperationSettled) {
        return false;
      }
      progress.siteOperationSettled = true;
      return true;
    },
    recordHostTaskManagedBinding(progress, valid) {
      if (!progress.managedBindingClaimed ||
          !progress.siteOperationSettled ||
          progress.managedBindingChecked) return false;
      progress.managedBindingChecked = true;
      progress.managedBindingValid = valid;
      return true;
    },
    hostTaskSiteOperationSettled: progress =>
      progress.siteOperationSettled,
    hostTaskSuccessAction(progress) {
      if (!progress.siteCompletionChecked) return 0;
      if (!progress.siteCompletionReady) return 1;
      if (!progress.commonCompletionChecked) return 2;
      if (!progress.commonCompleted) return 3;
      if (!progress.outputRetained) {
        return progress.connectorOwnedOutput ? 4 : 5;
      }
      if (!progress.siteOperationSettled) return 6;
      if (progress.managedBindingClaimed) {
        if (!progress.managedBindingChecked) return 7;
        if (!progress.managedBindingValid) return 8;
      }
      return 9;
    },
  });
}
