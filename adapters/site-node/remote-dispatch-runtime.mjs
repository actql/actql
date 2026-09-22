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
  if (!Array.isArray(scope) || scope.length !== 8 ||
      scope.some(value => !text(value))) {
    fail('InvalidRemoteExecutionScope');
  }
  return JSON.stringify(scope);
};

const RUNTIME_AWAIT_STOP = 0;
const RUNTIME_PERSIST_TRANSITION = 1;
const RUNTIME_SETTLE_THEN_PERSIST = 2;
const RUNTIME_RECLAIM_RESOURCES = 3;
const RUNTIME_FINISHED = 4;
const RUNTIME_ACQUIRE_BUNDLE = 0;
const RUNTIME_PERSIST_PROVISIONING = 1;
const RUNTIME_ACQUIRE_OPERATION = 2;
const RUNTIME_PERSIST_RUNNING = 3;
const RUNTIME_EXECUTE_PHYSICAL = 4;
const RUNTIME_ACQUIRE_HOLDING = 5;
const RUNTIME_SETTLE_OPERATION = 6;
const RUNTIME_PERSIST_SETTLED = 7;
const RUNTIME_PERSIST_RETAINED = 8;
const RUNTIME_PERSIST_EVIDENCE = 9;
const RUNTIME_SUCCESS_FINISHED = 10;

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
      typeof control.managedRuntimeRegistrationScope !== 'function' ||
      typeof control.registerEvidenceIssuer !== 'function' ||
      typeof control.managedOutputEvidenceKind !== 'string' ||
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
  if (evidenceKind !== control.managedOutputEvidenceKind) {
    fail('UnsupportedRemoteEvidenceKind');
  }
  return Object.freeze({
    key: keyOf(control.managedRuntimeRegistrationScope(capability, issuer)),
    capability,
    issuer,
    runtimeBundleCid,
    site,
    execute,
  });
}

export async function prepareInstalledRemoteRuntimeRegistration({
  bundleStore,
  bundleControl,
  runtimeBundleCid,
  load,
  ...registration
} = {}) {
  if (bundleStore === null || typeof bundleStore !== 'object' ||
      typeof bundleStore.active !== 'function' ||
      typeof bundleStore.verify !== 'function' ||
      bundleControl === null || typeof bundleControl !== 'object' ||
      typeof bundleControl.identity !== 'function' ||
      !text(runtimeBundleCid) || typeof load !== 'function') {
    fail('InvalidInstalledRemoteRuntimeRegistration');
  }
  const active = bundleStore.active(bundleControl);
  if (active === undefined ||
      bundleControl.identity(active.manifest) !== runtimeBundleCid) {
    fail('RemoteRuntimeBundleNotActive');
  }
  const bundle = await bundleStore.verify(runtimeBundleCid, bundleControl);
  const execute = await load(bundle);
  if (typeof execute !== 'function') fail('InvalidRemoteRuntimeBundleLoader');
  return prepareRemoteRuntimeRegistration({
    ...registration,
    runtimeBundleCid,
    execute,
  });
}

function checkedOutput(value) {
  if (!exactKeys(value, [
    'close',
    'logicalViewCid',
    'managedProfileCid',
    'materialGeneration',
    'measurement',
    'physicalManifestCid',
    'representationCodecCid',
    'retainedBytes',
    'resultSchemaCid',
    'rowCount',
  ]) || !text(value.materialGeneration) || !text(value.logicalViewCid) ||
      !text(value.managedProfileCid) || !text(value.physicalManifestCid) ||
      !text(value.representationCodecCid) || !text(value.resultSchemaCid) ||
      !Number.isSafeInteger(value.rowCount) || value.rowCount < 0 ||
      typeof value.retainedBytes !== 'bigint' || value.retainedBytes < 0n ||
      value.measurement === null || typeof value.measurement !== 'object' ||
      typeof value.close !== 'function') {
    fail('InvalidRemoteExecutionOutput');
  }
  return value;
}

const missingOutputDisposal = () => {
  const error = Object.assign(new Error('InvalidRemoteExecutionOutput'), {
    code: 'InvalidRemoteExecutionOutput',
    cleanupPending: true,
  });
  error.cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending: true, errors: Object.freeze([])}),
  });
  return error;
};

export function createRemoteDispatchRuntime({
  control,
  siteControl,
  store,
  bundleStore,
  bundleControl,
  registrations,
  budgets,
} = {}) {
  if (control === null || typeof control !== 'object' ||
      typeof control.executionScope !== 'function' ||
      typeof control.prepareInputBinding !== 'function' ||
      typeof control.inputBindingMatchesDispatch !== 'function' ||
      typeof control.managedRuntimeRegistrationScope !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.status !== 'function' ||
      typeof control.runtimeAdmission !== 'function' ||
      typeof control.runtimeStartable !== 'function' ||
      typeof control.createRuntimeCustody !== 'function' ||
      typeof control.runtimeCustodyAcquireOperation !== 'function' ||
      typeof control.runtimeCustodySettleOperation !== 'function' ||
      typeof control.runtimeCustodyOperationSettled !== 'function' ||
      typeof control.runtimeCustodyAcquireOutput !== 'function' ||
      typeof control.runtimeCustodyReleaseOutput !== 'function' ||
      typeof control.runtimeCustodyOutputReleased !== 'function' ||
      typeof control.runtimeCustodyAcquireHolding !== 'function' ||
      typeof control.runtimeCustodyReleaseHolding !== 'function' ||
      typeof control.runtimeCustodyHoldingReleased !== 'function' ||
      typeof control.runtimeCustodyAcquireBundle !== 'function' ||
      typeof control.runtimeCustodyReleaseBundle !== 'function' ||
      typeof control.runtimeCustodyBundleReleased !== 'function' ||
      typeof control.runtimeCustodyRecordFailure !== 'function' ||
      typeof control.runtimeCustodyConfirmStop !== 'function' ||
      typeof control.runtimeCustodyStopPending !== 'function' ||
      typeof control.runtimeCustodyResourcesReclaimed !== 'function' ||
      typeof control.runtimeSuccessAction !== 'function' ||
      typeof control.prepareOwnedRuntimeFailure !== 'function' ||
      typeof control.prepareOwnedRuntimeCleanup !== 'function' ||
      typeof control.prepareRuntimeReclaimUnknown !== 'function' ||
      typeof control.runtimeStepAction !== 'function' ||
      typeof control.runtimeStepTransition !== 'function' ||
      typeof control.prepareManagedProvisioning !== 'function' ||
      typeof control.prepareExecution !== 'function' ||
      typeof control.prepareSettled !== 'function' ||
      typeof control.prepareRetained !== 'function' ||
      typeof control.prepareManagedOutputMeasurement !== 'function' ||
      typeof control.managedOutputMeasurementIdentity !== 'function' ||
      typeof control.outputHoldingEvidenceIdentity !== 'function' ||
      typeof control.managedOutputSubjectMatchesMeasurement !== 'function' ||
      typeof control.prepareManagedOutputSubject !== 'function' ||
      typeof control.issueManagedOutputEvidence !== 'function' ||
      typeof control.prepareEvidence !== 'function' ||
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
      bundleStore === null || typeof bundleStore !== 'object' ||
      typeof bundleStore.active !== 'function' ||
      typeof bundleStore.verify !== 'function' ||
      typeof bundleStore.retain !== 'function' ||
      typeof bundleStore.release !== 'function' ||
      bundleControl === null || typeof bundleControl !== 'object' ||
      typeof bundleControl.identity !== 'function' ||
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
      'runtimeBundleCid',
      'site',
    ]) || !text(registration.key) || !text(registration.runtimeBundleCid) ||
        typeof registration.execute !== 'function' ||
        registration.key !== keyOf(control.managedRuntimeRegistrationScope(
          registration.capability,
          registration.issuer,
        )) ||
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
  let closeComplete = false;
  let closeFlight;

  const registrationFor = dispatch => {
    const key = keyOf(control.executionScope(dispatch));
    return installed.get(key);
  };
  const budgetFor = dispatch =>
    provisionedBudgets.get(control.dispatchBudgetIdentity(dispatch));
  const bundleActive = registration => {
    if (registration === undefined) return false;
    const value = bundleStore.active(bundleControl);
    return value !== undefined &&
      bundleControl.identity(value.manifest) === registration.runtimeBundleCid;
  };
  const admissionFor = (
    dispatch,
    record,
    registration,
    budget,
    activeDispatch,
  ) => {
    const registered = registration !== undefined;
    const budgeted = budget !== undefined;
    const siteAvailable = registered && siteControl.available(registration.site);
    const capacitySupported = registered && budgeted && siteAvailable &&
      siteControl.capacitySupports(
        registration.site,
        budget.retainedBytes,
        budget.executionBytes,
      );
    return control.runtimeAdmission(
      closed,
      record === undefined || control.recordMatchesDispatch(record, dispatch),
      registered,
      budgeted,
      activeDispatch,
      siteAvailable,
      capacitySupported,
      record === undefined || control.runtimeStartable(record),
    );
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
  const persistRuntimeStep = (step, record) => store.advance(
    control.runtimeStepTransition(step),
    record,
    control,
  );
  const settleOperation = entry => {
    if (entry.operation === undefined ||
        control.runtimeCustodyOperationSettled(entry.custody)) return;
    if (!siteControl.settleOperation(entry.operation)) {
      fail('RemoteSiteOperationSettlementRejected');
    }
    if (!control.runtimeCustodySettleOperation(entry.custody)) {
      fail('RemoteRuntimeCustodyTransitionRejected');
    }
  };
  const reclaimResources = async entry => {
    if (control.runtimeCustodyOutputAcquired(entry.custody) &&
        !control.runtimeCustodyOutputReleased(entry.custody)) {
      if (!entry.physicalOutputClosed) {
        await entry.outputClose();
        entry.physicalOutputClosed = true;
      }
      if (!control.runtimeCustodyReleaseOutput(entry.custody)) {
        fail('RemoteRuntimeCustodyTransitionRejected');
      }
    }
    if (entry.siteHolding !== undefined &&
        !control.runtimeCustodyHoldingReleased(entry.custody)) {
      if (!siteControl.releaseHolding(entry.siteHolding)) {
        fail('RemoteSiteHoldingReleaseRejected');
      }
      if (!control.runtimeCustodyReleaseHolding(entry.custody)) {
        fail('RemoteRuntimeCustodyTransitionRejected');
      }
    }
    if (entry.bundleHoldId !== undefined &&
        !control.runtimeCustodyBundleReleased(entry.custody)) {
      if (!bundleStore.release(entry.bundleHoldId, bundleControl)) {
        fail('RemoteBundleHoldReleaseRejected');
      }
      if (!control.runtimeCustodyReleaseBundle(entry.custody)) {
        fail('RemoteRuntimeCustodyTransitionRejected');
      }
    }
  };
  const observeStop = async (entry, retry) => {
    if (!control.runtimeCustodyStopPending(entry.custody)) return true;
    let state = cleanupState(entry);
    entry.diagnostics.push(...state.errors);
    if (retry && state.pending &&
        typeof member(entry.handle, 'retry') === 'function') {
      try {
        await entry.handle.retry();
      } catch (error) {
        entry.diagnostics.push(error);
      }
      state = cleanupState(entry);
      entry.diagnostics.push(...state.errors);
    }
    if (!state.pending &&
        !control.runtimeCustodyConfirmStop(entry.custody)) {
      fail('RemoteRuntimeCustodyTransitionRejected');
    }
    return !control.runtimeCustodyStopPending(entry.custody);
  };
  const applyFailurePlan = (entry, step) => {
    const action = control.runtimeStepAction(step);
    if (action === RUNTIME_SETTLE_THEN_PERSIST) {
      settleOperation(entry);
      persistRuntimeStep(step, entry.record);
      return;
    }
    if (action === RUNTIME_PERSIST_TRANSITION) {
      persistRuntimeStep(step, entry.record);
      return;
    }
    fail('InvalidRemoteRuntimeFailurePlan');
  };
  const driveCleanup = async (entry, retryStop = false) => {
    await observeStop(entry, retryStop);
    while (true) {
      const step = control.prepareOwnedRuntimeCleanup(
        entry.record,
        entry.custody,
      );
      const action = control.runtimeStepAction(step);
      if (action === RUNTIME_AWAIT_STOP) return false;
      if (action === RUNTIME_FINISHED) return true;
      if (action === RUNTIME_SETTLE_THEN_PERSIST) {
        settleOperation(entry);
        persistRuntimeStep(step, entry.record);
        continue;
      }
      if (action === RUNTIME_PERSIST_TRANSITION) {
        persistRuntimeStep(step, entry.record);
        continue;
      }
      if (action !== RUNTIME_RECLAIM_RESOURCES) {
        fail('InvalidRemoteRuntimeCleanupPlan');
      }
      try {
        await reclaimResources(entry);
      } catch (error) {
        try {
          persistRuntimeStep(
            control.prepareRuntimeReclaimUnknown(entry.record),
            entry.record,
          );
        } catch (transitionError) {
          throw new AggregateError(
            [error, transitionError],
            'Remote cleanup became unknown',
          );
        }
        throw error;
      }
    }
  };
  const runCleanup = (entry, retryStop = false) => {
    if (entry.cleanupFlight !== undefined) return entry.cleanupFlight;
    const flight = driveCleanup(entry, retryStop);
    entry.cleanupFlight = flight;
    flight.then(
      () => {
        if (entry.cleanupFlight === flight) entry.cleanupFlight = undefined;
      },
      () => {
        // A rejected physical cleanup remains retryable. Only concurrent
        // callers join this attempt; a later caller starts a fresh one.
        if (entry.cleanupFlight === flight) entry.cleanupFlight = undefined;
      },
    );
    return flight;
  };
  const reconcileCleanup = async (identity, entry) => {
    if (!await runCleanup(entry, true)) return false;
    pendingCleanup.delete(identity);
    return true;
  };
  const releaseOwner = async (identity, owner) => {
    if (!await runCleanup(owner)) return false;
    owners.delete(identity);
    return true;
  };
  const failExecution = async (
    identity,
    record,
    output,
    operationState,
    currentCustody,
    error,
    signal,
    bundleHoldId,
  ) => {
    const cleanupPending = member(error, 'cleanupPending') === true;
    const retainedOwner = owners.get(identity);
    const custody = retainedOwner?.custody ?? currentCustody;
    if (!control.runtimeCustodyRecordFailure(
      custody,
      signal?.aborted === true,
      cleanupPending,
      false,
    )) {
      fail('RemoteRuntimeCustodyTransitionRejected');
    }
    const entry = retainedOwner ?? {
      record,
      handle: member(error, 'cleanupHandle'),
      custody,
      primary: error,
      diagnostics: [],
      operation: operationState.operation,
      output,
      outputClose: operationState.outputClose,
      physicalOutputClosed: operationState.physicalOutputClosed,
      siteHolding: operationState.siteHolding,
      bundleHoldId,
    };
    if (retainedOwner !== undefined) {
      entry.handle = member(error, 'cleanupHandle');
      entry.primary = error;
      owners.delete(identity);
    }
    pendingCleanup.set(identity, entry);
    try {
      applyFailurePlan(
        entry,
        control.prepareOwnedRuntimeFailure(record, custody),
      );
    } catch (persistenceError) {
      entry.diagnostics.push(persistenceError);
      throw new AggregateError(
        [error, persistenceError],
        `Remote failure journal persistence failed: ${
          member(persistenceError, 'message') ?? 'unknown error'}`,
      );
    } finally {
      operationState.settled =
        control.runtimeCustodyOperationSettled(custody);
    }
    if (cleanupPending) {
      throw error;
    }
    try {
      await runCleanup(entry);
      pendingCleanup.delete(identity);
    } catch (cleanupError) {
      throw new AggregateError(
        [error, cleanupError],
        'Remote execution and cleanup failed',
      );
    }
    throw error;
  };
  const run = async (
    registration,
    budget,
    dispatch,
    record,
    signal,
    bundleHoldId,
    inputBindingBody,
    inputBinding,
  ) => {
    const identity = control.identity(dispatch);
    let output;
    let bundle;
    let evidence;
    let holdingEvidenceCid;
    let measurement;
    let subject;
    const custody = control.createRuntimeCustody();
    const operationState = {
      operation: undefined,
      settled: false,
      siteHolding: undefined,
      bundleRetained: false,
      outputClose: undefined,
      physicalOutputClosed: false,
    };
    try {
      while (true) {
        signal?.throwIfAborted();
        const action = control.runtimeSuccessAction(record, custody);
        if (action === RUNTIME_ACQUIRE_BUNDLE) {
          bundleStore.retain(
            registration.runtimeBundleCid,
            bundleHoldId,
            'dispatch',
            bundleControl,
          );
          operationState.bundleRetained = true;
          if (!control.runtimeCustodyAcquireBundle(custody)) {
            fail('RemoteRuntimeCustodyTransitionRejected');
          }
          bundle = await bundleStore.verify(
            registration.runtimeBundleCid,
            bundleControl,
          );
          continue;
        }
        if (action === RUNTIME_PERSIST_PROVISIONING) {
          store.advance(
            control.prepareManagedProvisioning(
              record,
              registration.capability,
              registration.issuer,
            ),
            record,
            control,
          );
          continue;
        }
        if (action === RUNTIME_ACQUIRE_OPERATION) {
          operationState.operation = siteControl.startOperation(
            registration.site,
            budget.retainedBytes,
            budget.executionBytes,
          );
          if (operationState.operation === undefined ||
              operationState.operation === null) {
            fail('RemoteSiteCapacityRejected');
          }
          if (!control.runtimeCustodyAcquireOperation(custody)) {
            fail('RemoteRuntimeCustodyTransitionRejected');
          }
          continue;
        }
        if (action === RUNTIME_PERSIST_RUNNING) {
          store.advance(control.prepareExecution(record), record, control);
          continue;
        }
        if (action === RUNTIME_EXECUTE_PHYSICAL) {
          output = await registration.execute(Object.freeze({
            bundle,
            dispatch,
            inputBinding,
            inputBindingBody,
            signal,
          }));
          const close = member(output, 'close');
          if (typeof close !== 'function') throw missingOutputDisposal();
          operationState.outputClose = () => close.call(output);
          if (!control.runtimeCustodyAcquireOutput(custody)) {
            fail('RemoteRuntimeCustodyTransitionRejected');
          }
          checkedOutput(output);
          continue;
        }
        if (action === RUNTIME_ACQUIRE_HOLDING) {
          if (!siteControl.operationAvailable(operationState.operation)) {
            fail('RemoteSiteOperationUnavailable');
          }
          operationState.siteHolding = siteControl.retainOperationHolding(
            operationState.operation,
            output.retainedBytes,
          );
          if (operationState.siteHolding === undefined ||
              operationState.siteHolding === null) {
            fail('RemoteSiteHoldingRejected');
          }
          if (!control.runtimeCustodyAcquireHolding(custody)) {
            fail('RemoteRuntimeCustodyTransitionRejected');
          }
          holdingEvidenceCid = control.outputHoldingEvidenceIdentity(
            dispatch,
            output.materialGeneration,
            output.retainedBytes,
          );
          continue;
        }
        if (action === RUNTIME_SETTLE_OPERATION) {
          if (!siteControl.settleOperation(operationState.operation)) {
            fail('RemoteSiteOperationSettlementRejected');
          }
          operationState.settled = true;
          if (!control.runtimeCustodySettleOperation(custody)) {
            fail('RemoteRuntimeCustodyTransitionRejected');
          }
          continue;
        }
        if (action === RUNTIME_PERSIST_SETTLED) {
          store.advance(control.prepareSettled(record), record, control);
          continue;
        }
        if (action === RUNTIME_PERSIST_RETAINED) {
          owners.set(identity, {
            record,
            handle: undefined,
            custody,
            primary: undefined,
            diagnostics: [],
            operation: operationState.operation,
            output,
            outputClose: operationState.outputClose,
            physicalOutputClosed: operationState.physicalOutputClosed,
            siteHolding: operationState.siteHolding,
            bundleHoldId,
          });
          store.advance(control.prepareRetained(
            record,
            output.materialGeneration,
            holdingEvidenceCid,
          ), record, control);
          continue;
        }
        if (action === RUNTIME_PERSIST_EVIDENCE) {
          measurement = control.prepareManagedOutputMeasurement(
            output.measurement,
          );
          subject = control.prepareManagedOutputSubject(
            dispatch,
            output,
            measurement,
            holdingEvidenceCid,
          );
          if (!control.managedOutputSubjectMatchesMeasurement(
            subject,
            measurement,
          )) {
            fail('RemoteManagedOutputMeasurementMismatch');
          }
          evidence = control.issueManagedOutputEvidence(
            registration.issuer,
            record,
            subject,
          );
          store.advanceEvidence(
            control.prepareEvidence(record, evidence),
            evidence,
            subject,
            measurement,
            record,
            control,
          );
          continue;
        }
        if (action !== RUNTIME_SUCCESS_FINISHED) {
          fail('InvalidRemoteRuntimeSuccessPlan');
        }
        return Object.freeze({
          dispatchRequestCid: identity,
          evidence,
          measurement,
          subject,
          revision: control.revision(record),
          state: Object.freeze([...control.status(record)]),
        });
      }
    } catch (error) {
      return failExecution(
        identity,
        record,
        output,
        operationState,
        custody,
        error,
        signal,
        operationState.bundleRetained ? bundleHoldId : undefined,
      );
    }
  };

  return Object.freeze({
    supports(dispatch) {
      const registration = registrationFor(dispatch);
      const budget = budgetFor(dispatch);
      return bundleActive(registration) && admissionFor(
        dispatch,
        undefined,
        registration,
        budget,
        false,
      ) === 0;
    },
    start(dispatch, record, signal, inputBindingBody) {
      if (typeof inputBindingBody !== 'string') {
        fail('RemoteInputBindingMissing');
      }
      const inputBinding = control.prepareInputBinding(inputBindingBody);
      if (!control.inputBindingMatchesDispatch(inputBinding, dispatch)) {
        fail('RemoteInputBindingMismatch');
      }
      const registration = registrationFor(dispatch);
      const budget = budgetFor(dispatch);
      const identity = control.identity(dispatch);
      const prior = active.get(identity);
      const admission = admissionFor(
        dispatch,
        record,
        registration,
        budget,
        prior !== undefined,
      );
      if (admission === 1) return prior.operation;
      const failure = [undefined, undefined, 'RemoteDispatchRuntimeClosed',
        'RemoteDispatchRecordMismatch', 'RemoteRuntimeUnsupported',
        'RemoteDispatchBudgetUnsupported', 'RemoteSiteUnavailable',
        'RemoteDispatchBudgetUnsupported', 'RemoteDispatchAlreadyStarted'][
        admission
      ];
      if (failure !== undefined) fail(failure);
      if (admission !== 0) {
        fail('InvalidRemoteRuntimeAdmission');
      }
      const bundleHoldId = `dispatch:${identity}`;
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
        bundleHoldId,
        inputBindingBody,
        inputBinding,
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
    close() {
      if (closeFlight !== undefined) return closeFlight;
      if (closeComplete) return Promise.resolve(false);
      closed = true;
      const flight = (async () => {
        const activeAtClose = new Set(active.keys());
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
        const failures = [];
        for (const [identity, owner] of [...owners]) {
          try {
            await releaseOwner(identity, owner);
          } catch (error) {
            failures.push(error);
          }
        }
        for (const [identity, entry] of [...pendingCleanup]) {
          // This close already waited for the active attempt's cleanup.
          // A failed physical stop is retried by a later close invocation.
          if (activeAtClose.has(identity)) continue;
          try {
            await reconcileCleanup(identity, entry);
          } catch (error) {
            entry.diagnostics.push(error);
          }
        }
        if (pendingCleanup.size !== 0 || owners.size !== 0) {
          const pending = [...pendingCleanup.values()];
          const failure = new AggregateError(
            [
              ...pending.flatMap(entry => [
                entry.primary,
                ...entry.diagnostics,
              ]),
              ...[...owners.values()].flatMap(entry => entry.diagnostics),
            ].filter(error => error !== undefined),
            'Remote runtime cleanup is not confirmed',
          );
          failure.code = 'RemoteRuntimeCleanupPending';
          failure.cleanupPending = true;
          failure.cleanupHandle = Object.freeze({
            status: () => Object.freeze({
              pending: pendingCleanup.size !== 0 || owners.size !== 0,
              errors: Object.freeze(
                [
                  ...[...pendingCleanup.values()].flatMap(entry =>
                    [...entry.diagnostics, ...cleanupState(entry).errors]),
                  ...[...owners.values()].flatMap(entry =>
                    [...entry.diagnostics, ...cleanupState(entry).errors]),
                ],
              ),
            }),
            async retry() {
              const retryFailures = [];
              for (const [identity, owner] of [...owners]) {
                try { await releaseOwner(identity, owner); }
                catch (error) {
                  owner.diagnostics.push(error);
                  retryFailures.push(error);
                }
              }
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
              failure.cleanupPending =
                pendingCleanup.size !== 0 || owners.size !== 0;
              return this.status();
            },
          });
          failure.cleanupErrors = failure.cleanupHandle.status().errors;
          throw failure;
        }
        if (failures.length !== 0) {
          throw new AggregateError(failures, 'Remote runtime cleanup failed');
        }
        return true;
      })();
      closeFlight = flight;
      flight.then(
        () => {
          closeComplete = true;
          if (closeFlight === flight) closeFlight = undefined;
        },
        () => {
          if (closeFlight === flight) closeFlight = undefined;
        },
      );
      return flight;
    },
  });
}
