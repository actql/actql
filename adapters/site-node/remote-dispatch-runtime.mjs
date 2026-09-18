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
    execute,
  });
}

function checkedOutput(value) {
  if (!exactKeys(value, [
    'close',
    'evidenceSubjectCid',
    'holdingEvidenceCid',
    'materialGeneration',
  ]) || !text(value.materialGeneration) ||
      !text(value.holdingEvidenceCid) || !text(value.evidenceSubjectCid) ||
      typeof value.close !== 'function') {
    fail('InvalidRemoteExecutionOutput');
  }
  return value;
}

export function createRemoteDispatchRuntime({control, store, registrations} = {}) {
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
      store === null || typeof store !== 'object' ||
      typeof store.advance !== 'function' ||
      typeof store.advanceEvidence !== 'function' ||
      !Array.isArray(registrations)) {
    fail('InvalidRemoteDispatchRuntime');
  }
  const installed = new Map();
  for (const registration of registrations) {
    if (!exactKeys(registration, [
      'capability',
      'execute',
      'issuer',
      'key',
    ]) || !text(registration.key) ||
        typeof registration.execute !== 'function' ||
        installed.has(registration.key)) {
      fail('InvalidRemoteRuntimeRegistration');
    }
    installed.set(registration.key, registration);
  }
  const active = new Map();
  const owners = new Map();
  const pendingCleanup = new Map();
  let closed = false;

  const registrationFor = dispatch => {
    const key = keyOf(control.executionScope(dispatch));
    return installed.get(key);
  };
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
    let recordState = control.status(entry.record);
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
  const releaseOwner = async (identity, record, owner) => {
    const state = control.status(record);
    if (state[2] === 2 || state[2] === 5) {
      owners.delete(identity);
      return false;
    }
    if (state[2] !== 1) {
      store.advance(control.prepareRelease(record), record, control);
    }
    try {
      await owner.close();
    } catch (error) {
      markUnknown(record, error);
      throw error;
    }
    store.advance(control.prepareReleased(record), record, control);
    owners.delete(identity);
    return true;
  };
  const failExecution = async (identity, record, output, error, signal) => {
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
        });
        markUnknown(record, error);
      } else {
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
      owners.set(identity, {record, output});
      try {
        await releaseOwner(identity, record, output);
      } catch (cleanupError) {
        throw new AggregateError(
          [error, cleanupError],
          'Remote execution and cleanup failed',
        );
      }
    }
    throw error;
  };
  const run = async (registration, dispatch, record, signal) => {
    const identity = control.identity(dispatch);
    let output;
    try {
      signal?.throwIfAborted();
      store.advance(
        control.prepareProvisioning(record, registration.capability),
        record,
        control,
      );
      signal?.throwIfAborted();
      store.advance(control.prepareExecution(record), record, control);
      output = await registration.execute(Object.freeze({dispatch, signal}));
      checkedOutput(output);
      store.advance(control.prepareSettled(record), record, control);
      owners.set(identity, {record, output});
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
      return failExecution(identity, record, output, error, signal);
    }
  };

  return Object.freeze({
    supports(dispatch) {
      if (closed) return false;
      return registrationFor(dispatch) !== undefined;
    },
    start(dispatch, record, signal) {
      if (closed) fail('RemoteDispatchRuntimeClosed');
      const registration = registrationFor(dispatch);
      if (registration === undefined) fail('RemoteRuntimeUnsupported');
      const identity = control.identity(dispatch);
      const prior = active.get(identity);
      if (prior !== undefined) return prior;
      if (control.status(record)[0] !== 0) {
        fail('RemoteDispatchAlreadyStarted');
      }
      const operation = run(registration, dispatch, record, signal)
        .finally(() => active.delete(identity));
      operation.catch(() => {});
      active.set(identity, operation);
      return operation;
    },
    active(dispatch) {
      return active.get(control.identity(dispatch));
    },
    async release(dispatch) {
      const identity = control.identity(dispatch);
      const owner = owners.get(identity);
      if (owner === undefined) return false;
      return releaseOwner(identity, owner.record, owner.output);
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
      if (!wasClosed) await Promise.allSettled([...active.values()]);
      const failures = [];
      for (const [identity, owner] of [...owners]) {
        try {
          await releaseOwner(identity, owner.record, owner.output);
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
