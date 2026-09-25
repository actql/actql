import {
  cancelRemoteDispatch,
  queryRemoteDispatch,
  releaseRemoteDispatch,
  sendRemoteDispatch,
} from './remote-site-client.mjs';
import {
  ExecutionAuthorizationError,
  missingAuthorizationGate,
} from '../host-common/authorization-gate.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

const cleanupState = (handle, required = false) => {
  if (handle === undefined || typeof member(handle, 'status') !== 'function') {
    return Object.freeze({pending: required, errors: Object.freeze([])});
  }
  try {
    const status = handle.status();
    return Object.freeze({
      pending: status?.pending !== false,
      errors: Object.freeze(Array.isArray(status?.errors)
        ? [...status.errors] : []),
    });
  } catch (error) {
    return Object.freeze({pending: true, errors: Object.freeze([error])});
  }
};

const ownedOutputFailure = reason => {
  const code = typeof member(reason, 'code') === 'string'
    ? member(reason, 'code') : 'RemoteCoordinatorOutputFailed';
  const failure = new Error(code, {cause: reason});
  failure.code = code;
  failure.primaryFailure = reason;
  failure.cleanupErrors = Object.freeze([]);
  return failure;
};

export function createRemoteSiteCoordinator({
  control,
  journal,
  store,
  send = sendRemoteDispatch,
  query = queryRemoteDispatch,
  cancel = cancelRemoteDispatch,
  release = releaseRemoteDispatch,
  plan: planOutput,
  output: executeOutput,
  receiveStoreOutput,
  transferControl,
  authorization = missingAuthorizationGate(),
} = {}) {
  if (control === null || typeof control !== 'object' ||
      typeof control.prepareCoordinatorIntent !== 'function' ||
      typeof control.prepareCoordinatorUnknown !== 'function' ||
      typeof control.prepareCoordinatorObservation !== 'function' ||
      typeof control.coordinatorCompletionEvidenceAvailable !== 'function' ||
      journal === undefined || store === null || typeof store !== 'object' ||
      typeof store.accept !== 'function' ||
      typeof store.advance !== 'function' ||
      typeof store.advanceEvidence !== 'function' ||
      typeof store.contains !== 'function' ||
      typeof store.recoverJournal !== 'function' ||
      typeof store.hasOutputOperations !== 'function' ||
      typeof send !== 'function' || typeof query !== 'function' ||
      typeof cancel !== 'function' || typeof release !== 'function') {
    fail('InvalidRemoteSiteCoordinator');
  }
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function') {
    fail('InvalidRemoteSiteCoordinatorAuthorization');
  }
  if (planOutput !== undefined && typeof planOutput !== 'function') {
    fail('InvalidRemoteSiteCoordinatorOutputPlan');
  }
  if (receiveStoreOutput !== undefined &&
      typeof receiveStoreOutput !== 'function') {
    fail('InvalidRemoteSiteCoordinatorStoreOutput');
  }
  const outputEnabled = executeOutput !== undefined ||
    transferControl !== undefined;
  if (outputEnabled && (typeof executeOutput !== 'function' ||
      transferControl === null || typeof transferControl !== 'object' ||
      typeof store.recoverOutputs !== 'function' ||
      typeof store.acceptOutput !== 'function' ||
      typeof store.advanceOutputUnknown !== 'function' ||
      typeof store.advanceOutputSuccess !== 'function' ||
      typeof control.prepareCoordinatorOutput !== 'function' ||
      typeof control.prepareCoordinatorOutputUnknown !== 'function' ||
      typeof control.prepareCoordinatorOutputSuccess !== 'function' ||
      typeof transferControl.recordRequestIdentity !== 'function')) {
    fail('InvalidRemoteSiteCoordinatorOutput');
  }
  if (!outputEnabled && store.hasOutputOperations()) {
    fail('RemoteCoordinatorOutputRecoveryRequired');
  }
  const recovered = store.recoverJournal(journal, control);
  const records = new Map(recovered.map(value => [
    control.identity(value.request),
    value.record,
  ]));
  const recoveredOutputs = outputEnabled
    ? store.recoverOutputs(journal, control, transferControl)
    : Object.freeze([]);
  const outputKey = (dispatch, intent) =>
    `${control.identity(dispatch)}:${control.outputIntentIdentity(intent)}`;
  const outputs = new Map();
  const outputOwners = new Map();
  for (const recoveredOutput of recoveredOutputs) {
    const key = control.coordinatorOutputRecordKey(recoveredOutput.record);
    outputs.set(`${key[4]}:${key[6]}`, recoveredOutput);
  }
  const options = value => {
    if (value === null || typeof value !== 'object' ||
        value.dispatch === undefined) {
      fail('InvalidRemoteSiteCoordinatorRequest');
    }
    return value;
  };
  const requireIntent = value => {
    const request = options(value);
    if (!store.contains(request.dispatch, control)) {
      fail('RemoteDispatchIntentMissing');
    }
    return request;
  };
  const recordFor = dispatch => {
    const record = records.get(control.identity(dispatch));
    if (record === undefined) fail('RemoteDispatchIntentMissing');
    return record;
  };
  const observe = (dispatch, response) => {
    const record = recordFor(dispatch);
    const transition = control.prepareCoordinatorObservation(
      record,
      response,
    );
    if (response.evidence === undefined && response.subject === undefined &&
        response.measurement === undefined) {
      store.advance(transition, record, control);
    } else if (response.evidence !== undefined &&
        response.subject !== undefined && response.measurement !== undefined) {
      store.advanceEvidence(
        transition,
        response.evidence,
        response.subject,
        response.measurement,
        record,
        control,
      );
    } else {
      fail('RemoteManagedOutputEvidenceIncomplete');
    }
    return response;
  };
  const exchange = async (request, operation) => {
    const record = recordFor(request.dispatch);
    try {
      return observe(request.dispatch, await operation(request));
    } catch (error) {
      const transition = control.prepareCoordinatorUnknown(record);
      store.advance(transition, record, control);
      throw error;
    }
  };
  const projectOutputRecord = record => {
    const projection = control.coordinatorOutputRecordResultProjection(record);
    return Object.freeze({
      resultCid: projection[0],
      payloadRequestCid: projection[1],
      payloadDigest: projection[2],
      transferRequestCid: projection[3],
      transferRevision: Number(projection[4]),
    });
  };
  const startOutputOperation = ({
    key,
    request,
    payloadRequest,
    transferRequest,
    record,
    transferRoute,
  }) => {
    const existing = outputOwners.get(key);
    if (existing !== undefined) return existing.promise;
    const abortController = new AbortController();
    const branches = [];
    const cleanupErrors = [];
    const owner = {
      failed: false,
      promise: undefined,
      failure: undefined,
      abortListener: undefined,
    };
    const refresh = () => {
      const errors = [...cleanupErrors];
      let pending = false;
      for (const branch of branches) {
        if (!branch.settled) pending = true;
        const state = cleanupState(branch.cleanup, branch.cleanupRequired);
        if (state.pending) pending = true;
        errors.push(...state.errors);
      }
      if (owner.failure !== undefined) {
        owner.failure.cleanupPending = pending;
        owner.failure.cleanupErrors = Object.freeze(errors);
      }
      if (!pending && owner.failed && outputOwners.get(key) === owner) {
        outputOwners.delete(key);
      }
      return Object.freeze({pending, errors: Object.freeze(errors)});
    };
    const cleanupHandle = Object.freeze({
      status: refresh,
      async retry() {
        for (const branch of branches) {
          const state = cleanupState(
            branch.cleanup,
            branch.cleanupRequired,
          );
          if (!state.pending ||
              typeof member(branch.cleanup, 'retry') !== 'function') {
            continue;
          }
          try { await branch.cleanup.retry(); }
          catch (error) { cleanupErrors.push(error); }
        }
        await Promise.resolve();
        return refresh();
      },
    });
    const runBranch = operation => {
      const branch = {
        settled: false,
        value: undefined,
        cleanup: undefined,
        cleanupRequired: false,
      };
      branches.push(branch);
      return Promise.resolve().then(operation).then(value => {
        branch.value = value;
        branch.settled = true;
        refresh();
        return value;
      }, reason => {
        branch.settled = true;
        branch.cleanupRequired = member(reason, 'cleanupPending') === true;
        branch.cleanup = branch.cleanupRequired
          ? member(reason, 'cleanupHandle') : undefined;
        if (!abortController.signal.aborted) abortController.abort(reason);
        refresh();
        throw reason;
      });
    };
    if (request.signal !== undefined &&
        typeof request.signal.addEventListener === 'function') {
      if (request.signal.aborted) {
        abortController.abort(request.signal.reason);
      } else {
        owner.abortListener = () => abortController.abort(request.signal.reason);
        request.signal.addEventListener(
          'abort',
          owner.abortListener,
          {once: true},
        );
      }
    }
    const physical = Object.freeze({
      ...request,
      signal: abortController.signal,
      payloadRequest,
      transferRequest,
    });
    const source = runBranch(() => executeOutput(physical));
    const destination = transferRoute === 'store'
      ? runBranch(() => receiveStoreOutput(physical))
      : Promise.resolve(undefined);
    const operations = Promise.all([source, destination]);
    const stopped = new Promise((_, reject) => {
      if (abortController.signal.aborted) {
        reject(abortController.signal.reason);
        return;
      }
      abortController.signal.addEventListener(
        'abort',
        () => reject(abortController.signal.reason),
        {once: true},
      );
    });
    owner.promise = Promise.race([operations, stopped]).then(
      ([response, destinationResult]) => {
        if (response === null || typeof response !== 'object' ||
            response.result === undefined) {
          fail('InvalidRemoteCoordinatorOutputResult');
        }
        if (transferRoute === 'store') {
          if (destinationResult === null ||
              typeof destinationResult !== 'object' ||
              destinationResult.record === undefined ||
              !transferControl.recordIsDestinationCommitted(
                destinationResult.record,
              )) {
            fail('InvalidRemoteCoordinatorStoreOutputResult');
          }
          const sourceResult = control.outputResultProjection(
            response.result,
            transferRequest,
          );
          if (sourceResult[3] !== transferControl.identity(transferRequest) ||
              transferControl.recordRequestIdentity(
                destinationResult.record,
              ) !== transferControl.identity(transferRequest) ||
              Number(sourceResult[4]) !==
              transferControl.revision(destinationResult.record)) {
            fail('RemoteCoordinatorStoreOutputCollision');
          }
        }
        if (store.inspectOutput(record, control)?.progress !== 2) {
          const transition = control.prepareCoordinatorOutputSuccess(
            record,
            response.result,
          );
          store.advanceOutputSuccess(
            transition,
            response.result,
            record,
            control,
          );
        }
        outputOwners.delete(key);
        return projectOutputRecord(record);
      },
    ).catch(reason => {
      owner.failed = true;
      const state = store.inspectOutput(record, control);
      if (state?.progress === 2) {
        outputOwners.delete(key);
        return projectOutputRecord(record);
      }
      let unknownFailure;
      try {
        const transition = control.prepareCoordinatorOutputUnknown(record);
        store.advanceOutputUnknown(transition, record, control);
      } catch (error) {
        unknownFailure = error;
        cleanupErrors.push(error);
      }
      const failure = ownedOutputFailure(reason);
      owner.failure = failure;
      const cleanup = refresh();
      if (cleanup.pending) failure.cleanupHandle = cleanupHandle;
      if (unknownFailure !== undefined) {
        failure.unknownTransitionFailure = unknownFailure;
      }
      throw failure;
    }).finally(() => {
      if (owner.abortListener !== undefined) {
        request.signal.removeEventListener('abort', owner.abortListener);
      }
      refresh();
    });
    outputOwners.set(key, owner);
    return owner.promise;
  };
  // The Run owner decides. Dispatch is the remote Site's activation of the
  // selected registration for this checked Run; the Site keeps its own mTLS
  // and authority checks. A decision is reused only for this exact scope.
  const dispatchFacts = dispatch => {
    const body = JSON.parse(control.requestJson(dispatch));
    return Object.freeze({
      site: body.site_key,
      registration: body.connector_registration,
      runDefinitionCid: body.run_definition_cid,
    });
  };
  // `resumption` continues a deferred dispatch from its committed Resolution
  // (the gate's `resume`); it is still decided for this exact scope.
  const requireDispatch = async (
    boundary,
    scope,
    subjectCid,
    signal,
    resumption,
  ) => {
    if (resumption !== undefined &&
        typeof authorization.resume !== 'function') {
      fail('RemoteCoordinatorResumeUnavailable');
    }
    const decision = resumption === undefined
      ? await authorization.authorize(boundary, scope, {subjectCid, signal})
      : await authorization.resume(boundary, scope, {
        subjectCid,
        signal,
        resumption,
      });
    if (decision.action !== 'dispatch') {
      throw new ExecutionAuthorizationError(decision);
    }
    return decision;
  };
  // A decision taken from a committed approval (basis `resumed`) must carry
  // its admission; an account allow needs no Resolution and has none.
  const enterResumed = decision => {
    if (decision.admission === undefined && decision.basis !== 'resumed') {
      return;
    }
    if (typeof decision.admission?.enter !== 'function') {
      throw new ExecutionAuthorizationError(Object.freeze({...decision,
        action: 'failure', reason: 'adapter_error',
        detail: 'ResumeAdmissionUnavailable'}));
    }
    try {
      decision.admission.enter();
    } catch (error) {
      throw new ExecutionAuthorizationError(Object.freeze({...decision,
        action: 'failure', reason: 'adapter_error',
        detail: typeof error?.code === 'string' ? error.code
          : 'ResumeAdmissionFailed',
        error}));
    }
  };
  return Object.freeze({
    recovered,
    recoveredOutputs,
    async dispatch(value) {
      const request = options(value);
      // Before the durable intent and before any send: a deny, failure,
      // unsupported defer or persisted wait records nothing and sends nothing.
      const facts = dispatchFacts(request.dispatch);
      const decision = await requireDispatch('activation', {
        connection: facts.site,
        resource: facts.registration,
        operation: 'write',
      }, facts.runDefinitionCid, request.signal, request.resumption);
      // A resumed dispatch is fenced again here, synchronously and after
      // every await: the claim must still be the current live claim and the
      // approval still valid at the Host trusted time, and this claim
      // generation must not have started a protected dispatch already. From
      // here to the send nothing awaits. A recorded earlier attempt keeps its
      // durable identity (which the Site deduplicates); a new claimant gets
      // no new physical attempt of the same task.
      if (request.resumption !== undefined) enterResumed(decision);
      const admission = control.prepareCoordinatorIntent(
        journal,
        request.dispatch,
      );
      const record = store.accept(admission, request.dispatch, control);
      records.set(control.identity(request.dispatch), record);
      return exchange(request, send);
    },
    query(value) {
      return exchange(requireIntent(value), query);
    },
    cancel(value) {
      return exchange(requireIntent(value), cancel);
    },
    release(value) {
      return exchange(requireIntent(value), release);
    },
    async output(value) {
      if (!outputEnabled) fail('RemoteCoordinatorOutputUnavailable');
      const request = requireIntent(value);
      if (request.intent === undefined) {
        fail('InvalidRemoteCoordinatorOutput');
      }
      const output = control.admitPollOutput(
        control.pollOutputJson(request.dispatch, request.intent),
      );
      const key = outputKey(request.dispatch, request.intent);
      let currentOutput = outputs.get(key);
      let payloadRequest = currentOutput?.payloadRequest ??
        request.payloadRequest;
      let transferRequest = currentOutput?.transferRequest ??
        request.transferRequest;
      if (currentOutput === undefined &&
          (payloadRequest === undefined || transferRequest === undefined)) {
        if (typeof planOutput !== 'function' || request.subject === undefined ||
            !Number.isSafeInteger(request.maxChunks) ||
            request.maxChunks < 1 ||
            !Number.isSafeInteger(request.maxManifestBytes) ||
            request.maxManifestBytes < 1 ||
            typeof request.maxReferencedBytes !== 'bigint' ||
            request.maxReferencedBytes < 0n) {
          fail('InvalidRemoteCoordinatorOutputPlan');
        }
        const planned = await planOutput(request);
        if (planned === null || typeof planned !== 'object' ||
            planned.plan === undefined ||
            planned.payloadRequest === undefined ||
            planned.transferRequest === undefined) {
          fail('InvalidRemoteCoordinatorOutputPlanResult');
        }
        payloadRequest = planned.payloadRequest;
        transferRequest = planned.transferRequest;
      }
      let record = currentOutput?.record;
      // An already committed output is a recorded fact: replay needs no new
      // decision and performs no I/O.
      if (record !== undefined &&
          store.inspectOutput(record, control)?.progress === 2) {
        return projectOutputRecord(record);
      }
      // Egress boundary: the recipient Site and scope are authorized before
      // durable output admission and before any physical output or receive.
      // A recovered unknown output is re-authorized before it is retried.
      const transferFacts = transferControl.requestProjection(transferRequest);
      await requireDispatch('transfer', {
        connection: transferFacts[4],
        resource: transferFacts[2],
        operation: 'write',
      }, dispatchFacts(request.dispatch).runDefinitionCid, request.signal);
      if (record === undefined) {
        const admission = control.prepareCoordinatorOutput(
          journal,
          output,
          payloadRequest,
          transferRequest,
        );
        record = store.acceptOutput(
          admission,
          payloadRequest,
          transferRequest,
          control,
          transferControl,
        );
        currentOutput = Object.freeze({
          output,
          payloadRequest,
          transferRequest,
          record,
        });
        outputs.set(key, currentOutput);
      }
      const current = store.inspectOutput(record, control);
      if (current?.progress === 2) return projectOutputRecord(record);
      const transferRoute = transferControl.requestProjection(
        transferRequest,
      )[1];
      if (transferRoute !== 'direct' && transferRoute !== 'store') {
        fail('InvalidRemoteCoordinatorOutputRoute');
      }
      if (transferRoute === 'store' &&
          typeof receiveStoreOutput !== 'function') {
        fail('RemoteCoordinatorStoreOutputUnavailable');
      }
      return await startOutputOperation({
        key,
        request,
        payloadRequest,
        transferRequest,
        record,
        transferRoute,
      });
    },
    completionEvidenceAvailable(value) {
      const request = requireIntent(value);
      return control.coordinatorCompletionEvidenceAvailable(
        recordFor(request.dispatch),
      );
    },
  });
}
