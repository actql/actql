const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const text = value => typeof value === 'string' && value.length > 0;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name]
      : undefined;
  } catch {
    return undefined;
  }
};
const keyOf = scope => {
  if (!Array.isArray(scope) || scope.length !== 7 ||
      scope.some(value => !text(value))) {
    fail('InvalidRemoteExecutionScope');
  }
  return JSON.stringify(scope);
};

export function prepareRemoteRuntimeRegistration({
  control,
  site,
  runtimeBundleCid,
  connectorRegistration,
  connectorRevision,
  strategyRevision,
  operationCapabilityCid,
  evidenceKind,
  issuerCapabilityCid,
  execute,
} = {}) {
  if (control === null || typeof control !== 'object' ||
      typeof control.registerExecutionCapability !== 'function' ||
      typeof control.executionCapabilityScope !== 'function' ||
      typeof control.registerEvidenceIssuer !== 'function' ||
      typeof execute !== 'function') {
    fail('InvalidRemoteRuntimeRegistration');
  }
  const capability = control.registerExecutionCapability({
    site,
    runtimeBundleCid,
    connectorRegistration,
    connectorRevision,
    strategyRevision,
    operationCapabilityCid,
  });
  const issuer = control.registerEvidenceIssuer({
    site,
    runtimeBundleCid,
    connectorRegistration,
    connectorRevision,
    strategyRevision,
    evidenceKind,
    issuerCapabilityCid,
  });
  return Object.freeze({
    key: keyOf(control.executionCapabilityScope(capability)),
    capability,
    issuer,
    site,
    execute,
  });
}

function checkedOutput(value) {
  if (!exactKeys(value, [
    'close',
    'evidenceSubjectCid',
    'holdingEvidenceCid',
    'materialGeneration',
    'retainedBytes',
  ]) || !text(value.materialGeneration) ||
      !text(value.holdingEvidenceCid) || !text(value.evidenceSubjectCid) ||
      typeof value.retainedBytes !== 'bigint' || value.retainedBytes < 0n ||
      typeof value.close !== 'function') {
    fail('InvalidRemoteExecutionOutput');
  }
  return value;
}

export function createRemoteDispatchRuntime({
  control,
  siteControl,
  store,
  registrations,
  budgets,
} = {}) {
  if (control === null || typeof control !== 'object' ||
      typeof control.executionScope !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.status !== 'function' ||
      typeof control.prepareProvisioning !== 'function' ||
      typeof control.prepareExecution !== 'function' ||
      typeof control.prepareSettled !== 'function' ||
      typeof control.prepareFailed !== 'function' ||
      typeof control.prepareCancelled !== 'function' ||
      typeof control.prepareReconciledFailure !== 'function' ||
      typeof control.prepareReconciledCancellation !== 'function' ||
      typeof control.prepareUnknown !== 'function' ||
      typeof control.prepareRetained !== 'function' ||
      typeof control.issueExecutionEvidence !== 'function' ||
      typeof control.prepareEvidence !== 'function' ||
      typeof control.prepareEvidenceRejection !== 'function' ||
      typeof control.prepareRelease !== 'function' ||
      typeof control.prepareReleased !== 'function' ||
      typeof control.budgetIdentity !== 'function' ||
      typeof control.budgetCapacity !== 'function' ||
      typeof control.dispatchBudgetIdentity !== 'function' ||
      typeof control.recordMatchesDispatch !== 'function' ||
      siteControl === null || typeof siteControl !== 'object' ||
      typeof siteControl.available !== 'function' ||
      typeof siteControl.capacitySupports !== 'function' ||
      typeof siteControl.startOperation !== 'function' ||
      typeof siteControl.operationAvailable !== 'function' ||
      typeof siteControl.settleOperation !== 'function' ||
      typeof siteControl.retainOperationHolding !== 'function' ||
      typeof siteControl.releaseHolding !== 'function' ||
      store === null || typeof store !== 'object' ||
      typeof store.advance !== 'function' ||
      typeof store.advanceEvidence !== 'function' ||
      !Array.isArray(registrations) || !Array.isArray(budgets)) {
    fail('InvalidRemoteDispatchRuntime');
  }
  const installed = new Map();
  for (const registration of registrations) {
    if (!exactKeys(registration, [
      'capability',
      'execute',
      'issuer',
      'key',
      'site',
    ]) || !text(registration.key) ||
        typeof registration.execute !== 'function' ||
        installed.has(registration.key)) {
      fail('InvalidRemoteRuntimeRegistration');
    }
    installed.set(registration.key, registration);
  }
  const provisionedBudgets = new Map();
  for (const budget of budgets) {
    const identity = control.budgetIdentity(budget);
    const capacity = control.budgetCapacity(budget);
    if (!text(identity) || !Array.isArray(capacity) || capacity.length !== 2 ||
        capacity.some(value => typeof value !== 'bigint' || value < 0n) ||
        provisionedBudgets.has(identity)) {
      fail('InvalidRemoteDispatchBudget');
    }
    provisionedBudgets.set(identity, Object.freeze({
      retainedBytes: capacity[0],
      executionBytes: capacity[1],
    }));
  }
  const active = new Map();
  const owners = new Map();
  const pendingCleanup = new Map();
  let closed = false;

  const registrationFor = dispatch => {
    const key = keyOf(control.executionScope(dispatch));
    return installed.get(key);
  };
  const budgetFor = dispatch =>
    provisionedBudgets.get(control.dispatchBudgetIdentity(dispatch));
  const markUnknown = (record, primary) => {
    try {
      store.advance(control.prepareUnknown(record), record, control);
    } catch (error) {
      throw new AggregateError([primary, error], 'Remote cleanup became unknown');
    }
  };
  const cleanupState = entry => {
    const handle = entry.handle;
    if (handle === undefined ||
        typeof member(handle, 'status') !== 'function') {
      return Object.freeze({pending: true, errors: Object.freeze([])});
    }
    try {
      const state = handle.status();
      if (state === null || typeof state !== 'object' ||
          typeof state.pending !== 'boolean') {
        return Object.freeze({pending: true, errors: Object.freeze([])});
      }
      return Object.freeze({
        pending: state.pending,
        errors: Object.freeze(
          Array.isArray(state.errors) ? [...state.errors] : [],
        ),
      });
    } catch (error) {
      return Object.freeze({pending: true, errors: Object.freeze([error])});
    }
  };
  const reconcileCleanup = async (identity, entry) => {
    let recordState = control.status(entry.record);
    if (recordState[0] <= 2 && recordState[2] !== 3) {
      store.advance(
        control.prepareUnknown(entry.record),
        entry.record,
        control,
      );
      recordState = control.status(entry.record);
    }
    let state = cleanupState(entry);
    entry.diagnostics.push(...state.errors);
    if (state.pending && typeof member(entry.handle, 'retry') === 'function') {
      try {
        await entry.handle.retry();
      } catch (error) {
        entry.diagnostics.push(error);
      }
      state = cleanupState(entry);
      entry.diagnostics.push(...state.errors);
    }
    if (state.pending) return false;
    if (entry.operation !== undefined && !entry.operationSettled) {
      if (!siteControl.settleOperation(entry.operation)) {
        fail('RemoteSiteOperationSettlementRejected');
      }
      entry.operationSettled = true;
    }
    recordState = control.status(entry.record);
    if (recordState[0] === 6) {
      const transition = entry.cancelled
        ? control.prepareReconciledCancellation(entry.record)
        : control.prepareReconciledFailure(entry.record);
      store.advance(transition, entry.record, control);
      recordState = control.status(entry.record);
    }
    if (recordState[2] === 3) {
      store.advance(
        control.prepareRelease(entry.record),
        entry.record,
        control,
      );
      recordState = control.status(entry.record);
    }
    if (recordState[2] === 1) {
      store.advance(
        control.prepareReleased(entry.record),
        entry.record,
        control,
      );
      recordState = control.status(entry.record);
    }
    if (recordState[2] !== 2 && recordState[2] !== 5) {
      fail('RemoteCleanupReconciliationIncomplete');
    }
    pendingCleanup.delete(identity);
    return true;
  };
  const releaseOwner = async (identity, owner) => {
    const {record} = owner;
    const state = control.status(record);
    if (state[2] === 2 || state[2] === 5) {
      owners.delete(identity);
      return false;
    }
    if (state[2] !== 1) {
      store.advance(control.prepareRelease(record), record, control);
    }
    try {
      if (!owner.outputClosed) {
        await owner.output.close();
        owner.outputClosed = true;
      }
      if (!owner.holdingReleased) {
        if (!siteControl.releaseHolding(owner.siteHolding)) {
          fail('RemoteSiteHoldingReleaseRejected');
        }
        owner.holdingReleased = true;
      }
    } catch (error) {
      markUnknown(record, error);
      throw error;
    }
    store.advance(control.prepareReleased(record), record, control);
    owners.delete(identity);
    return true;
  };
  const releaseEmptyRecord = record => {
    let state = control.status(record);
    if (state[2] === 0 || state[2] === 3) {
      store.advance(control.prepareRelease(record), record, control);
      state = control.status(record);
    }
    if (state[2] === 1) {
      store.advance(control.prepareReleased(record), record, control);
    }
  };
  const failExecution = async (
    identity,
    record,
    output,
    operationState,
    error,
    signal,
  ) => {
    const state = control.status(record);
    if (state[0] === 0 && signal?.aborted) {
      store.advance(control.prepareCancelled(record), record, control);
    } else if (state[0] === 1 || state[0] === 2) {
      const cleanupPending = member(error, 'cleanupPending') === true;
      if (cleanupPending) {
        pendingCleanup.set(identity, {
          record,
          handle: member(error, 'cleanupHandle'),
          cancelled: signal?.aborted === true,
          primary: error,
          diagnostics: [],
          operation: operationState.operation,
          operationSettled: operationState.settled,
        });
        markUnknown(record, error);
      } else {
        if (operationState.operation !== undefined &&
            !operationState.settled) {
          if (!siteControl.settleOperation(operationState.operation)) {
            fail('RemoteSiteOperationSettlementRejected');
          }
          operationState.settled = true;
        }
        const transition = signal?.aborted
          ? control.prepareCancelled(record)
          : control.prepareFailed(record);
        store.advance(transition, record, control);
      }
    } else if (state[0] === 3 && state[1] !== 2 && state[1] !== 3) {
      store.advance(
        control.prepareEvidenceRejection(record),
        record,
        control,
      );
    }
    if (output && typeof output.close === 'function' &&
        member(error, 'cleanupPending') !== true) {
      const owner = {
        record,
        output,
        outputClosed: false,
        siteHolding: operationState.siteHolding,
        holdingReleased: operationState.siteHolding === undefined,
      };
      owners.set(identity, owner);
      try {
        await releaseOwner(identity, owner);
      } catch (cleanupError) {
        throw new AggregateError(
          [error, cleanupError],
          'Remote execution and cleanup failed',
        );
      }
    } else if (member(error, 'cleanupPending') !== true) {
      releaseEmptyRecord(record);
    }
    throw error;
  };
  const run = async (registration, budget, dispatch, record, signal) => {
    const identity = control.identity(dispatch);
    let output;
    const operationState = {
      operation: undefined,
      settled: false,
      siteHolding: undefined,
    };
    try {
      signal?.throwIfAborted();
      store.advance(
        control.prepareProvisioning(record, registration.capability),
        record,
        control,
      );
      operationState.operation = siteControl.startOperation(
        registration.site,
        budget.retainedBytes,
        budget.executionBytes,
      );
      if (operationState.operation === undefined ||
          operationState.operation === null) {
        fail('RemoteSiteCapacityRejected');
      }
      signal?.throwIfAborted();
      store.advance(control.prepareExecution(record), record, control);
      output = await registration.execute(Object.freeze({dispatch, signal}));
      signal?.throwIfAborted();
      checkedOutput(output);
      operationState.siteHolding = siteControl.retainOperationHolding(
        operationState.operation,
        output.retainedBytes,
      );
      if (operationState.siteHolding === undefined ||
          operationState.siteHolding === null) {
        fail('RemoteSiteHoldingRejected');
      }
      if (!siteControl.settleOperation(operationState.operation)) {
        fail('RemoteSiteOperationSettlementRejected');
      }
      operationState.settled = true;
      store.advance(control.prepareSettled(record), record, control);
      owners.set(identity, {
        record,
        output,
        outputClosed: false,
        siteHolding: operationState.siteHolding,
        holdingReleased: false,
      });
      store.advance(control.prepareRetained(
        record,
        output.materialGeneration,
        output.holdingEvidenceCid,
      ), record, control);
      const evidence = control.issueExecutionEvidence(
        registration.issuer,
        record,
        output.evidenceSubjectCid,
      );
      store.advanceEvidence(
        control.prepareEvidence(record, evidence),
        evidence,
        record,
        control,
      );
      return Object.freeze({
        dispatchRequestCid: identity,
        evidence,
        revision: control.revision(record),
        state: Object.freeze([...control.status(record)]),
      });
    } catch (error) {
      return failExecution(
        identity,
        record,
        output,
        operationState,
        error,
        signal,
      );
    }
  };

  return Object.freeze({
    supports(dispatch) {
      if (closed) return false;
      const registration = registrationFor(dispatch);
      const budget = budgetFor(dispatch);
      return registration !== undefined && budget !== undefined &&
        siteControl.available(registration.site) &&
        siteControl.capacitySupports(
          registration.site,
          budget.retainedBytes,
          budget.executionBytes,
        );
    },
    start(dispatch, record, signal) {
      if (closed) fail('RemoteDispatchRuntimeClosed');
      if (!control.recordMatchesDispatch(record, dispatch)) {
        fail('RemoteDispatchRecordMismatch');
      }
      const registration = registrationFor(dispatch);
      if (registration === undefined) fail('RemoteRuntimeUnsupported');
      const budget = budgetFor(dispatch);
      if (budget === undefined || !siteControl.capacitySupports(
        registration.site,
        budget.retainedBytes,
        budget.executionBytes,
      )) {
        fail('RemoteDispatchBudgetUnsupported');
      }
      const identity = control.identity(dispatch);
      const prior = active.get(identity);
      if (prior !== undefined) return prior.operation;
      if (control.status(record)[0] !== 0) {
        fail('RemoteDispatchAlreadyStarted');
      }
      const controller = new AbortController();
      const abort = () => controller.abort(signal?.reason);
      if (signal?.aborted) abort();
      else signal?.addEventListener('abort', abort, {once: true});
      const operation = run(
        registration,
        budget,
        dispatch,
        record,
        controller.signal,
      ).finally(() => {
        signal?.removeEventListener('abort', abort);
        active.delete(identity);
      });
      operation.catch(() => {});
      active.set(identity, {operation, controller});
      return operation;
    },
    active(dispatch) {
      return active.get(control.identity(dispatch))?.operation;
    },
    cancel(dispatch) {
      const running = active.get(control.identity(dispatch));
      if (running === undefined) return false;
      running.controller.abort(
        Object.assign(new Error('RemoteDispatchCancelled'), {
          code: 'RemoteDispatchCancelled',
        }),
      );
      return true;
    },
    async release(dispatch) {
      const identity = control.identity(dispatch);
      const owner = owners.get(identity);
      if (owner === undefined) return false;
      return releaseOwner(identity, owner);
    },
    async cleanup(dispatch) {
      const identity = control.identity(dispatch);
      const entry = pendingCleanup.get(identity);
      if (entry === undefined) return false;
      return reconcileCleanup(identity, entry);
    },
    async close() {
      const wasClosed = closed;
      closed = true;
      if (!wasClosed) {
        for (const entry of active.values()) {
          entry.controller.abort(
            Object.assign(new Error('RemoteDispatchRuntimeClosed'), {
              code: 'RemoteDispatchRuntimeClosed',
            }),
          );
        }
        await Promise.allSettled(
          [...active.values()].map(entry => entry.operation),
        );
      }
      const failures = [];
      for (const [identity, owner] of [...owners]) {
        try {
          await releaseOwner(identity, owner);
        } catch (error) {
          failures.push(error);
        }
      }
      for (const [identity, entry] of [...pendingCleanup]) {
        try {
          await reconcileCleanup(identity, entry);
        } catch (error) {
          entry.diagnostics.push(error);
        }
      }
      if (pendingCleanup.size !== 0) {
        const pending = [...pendingCleanup.values()];
        const failure = new AggregateError(
          pending.flatMap(entry => [
            entry.primary,
            ...entry.diagnostics,
          ]),
          'Remote runtime cleanup is not confirmed',
        );
        failure.code = 'RemoteRuntimeCleanupPending';
        failure.cleanupPending = true;
        failure.cleanupHandle = Object.freeze({
          status: () => Object.freeze({
            pending: pendingCleanup.size !== 0,
            errors: Object.freeze(
              [...pendingCleanup.values()].flatMap(entry =>
                [...entry.diagnostics, ...cleanupState(entry).errors]),
            ),
          }),
          async retry() {
            const retryFailures = [];
            for (const [identity, entry] of [...pendingCleanup]) {
              try { await reconcileCleanup(identity, entry); }
              catch (error) {
                entry.diagnostics.push(error);
                retryFailures.push(error);
              }
            }
            if (retryFailures.length !== 0) {
              failure.cleanupErrors = Object.freeze(retryFailures);
            }
            failure.cleanupPending = pendingCleanup.size !== 0;
            return this.status();
          },
        });
        failure.cleanupErrors = failure.cleanupHandle.status().errors;
        throw failure;
      }
      if (failures.length !== 0) {
        throw new AggregateError(failures, 'Remote runtime cleanup failed');
      }
      return !wasClosed;
    },
  });
}
