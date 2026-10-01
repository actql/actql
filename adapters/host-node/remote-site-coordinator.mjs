import {
  cancelRemoteDispatch,
  queryRemoteDispatch,
  releaseRemoteDispatch,
  sendRemoteDispatch,
  projectRemoteDispatchResponse,
} from './remote-site-client.mjs';
import {
  ExecutionAuthorizationError,
  missingAuthorizationGate,
} from '../host-common/authorization-gate.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

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
  // Host-installed synchronous projection through the retained Run owners:
  // verify dispatch/binding/materials against the ORIGINAL Run, then project
  // CURRENT authorization/lifetime, generation and cancellation. Never take
  // this callback or its facts from a received dispatch/query.
  currentDispatchContext,
} = {}) {
  if (control === null || typeof control !== 'object' ||
      typeof control.prepareCoordinatorIntent !== 'function' ||
      typeof control.prepareCoordinatorUnknown !== 'function' ||
      typeof control.prepareCoordinatorObservation !== 'function' ||
      typeof control.coordinatorTransitionIsReplay !== 'function' ||
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
  if (currentDispatchContext !== undefined &&
      (typeof currentDispatchContext !== 'function' ||
      typeof store.deliveryEnvelope !== 'function' ||
      typeof control.coordinatorDeliveryEnvelopeJson !== 'function' ||
      typeof control.coordinatorDeliveryContextCurrent !== 'function' ||
      typeof control.coordinatorRedeliveryEligible !== 'function')) {
    fail('InvalidRemoteCoordinatorRecoveryConfiguration');
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
    Object.freeze({dispatch: value.request, record: value.record}),
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
    return record.record;
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
        ((response.subject === undefined && response.measurement === undefined) ||
        (response.subject !== undefined && response.measurement !== undefined))) {
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
    return Object.freeze({observation: response,
      replay: control.coordinatorTransitionIsReplay(transition)});
  };
  const exchange = async (request, operation) => {
    const record = recordFor(request.dispatch);
    let response;
    try {
      response = await operation(request);
    } catch (error) {
      const transition = control.prepareCoordinatorUnknown(record);
      store.advance(transition, record, control);
      throw error;
    }
    // Semantic rejection and failed/unknown durable admission are not a new
    // transport outcome. In particular, a rejected replay must not revise state.
    return observe(request.dispatch, response).observation;
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
  // Every resumed dispatch must carry its admission, whatever the account
  // outcome: an allow needs no approval for the tuple but still resumes a
  // continuation only through the live claim (called only with a
  // `resumption`). The admission records the durable dispatch identity. When an earlier
  // claim generation already started a protected dispatch (its outcome is
  // unknown here), a fresh start is refused and the only path is physical
  // reconciliation: re-send that exact durable dispatch identity, which the
  // Site deduplicates. Another dispatch identity is refused before any send.
  const enterResumed = (decision, dispatchIdentity) => {
    if (typeof decision.admission?.enter !== 'function') {
      throw new ExecutionAuthorizationError(Object.freeze({...decision,
        action: 'failure', reason: 'adapter_error',
        detail: 'ResumeAdmissionUnavailable'}));
    }
    try {
      try {
        decision.admission.enter(dispatchIdentity);
      } catch (error) {
        if (error?.code !== 'PriorAdmissionUnresolved' ||
            typeof decision.admission.reconcile !== 'function') {
          throw error;
        }
        decision.admission.reconcile(dispatchIdentity);
      }
    } catch (error) {
      throw new ExecutionAuthorizationError(Object.freeze({...decision,
        action: 'failure', reason: 'adapter_error',
        detail: typeof error?.code === 'string' ? error.code
          : 'ResumeAdmissionFailed',
        error}));
    }
  };
  const retainedDelivery = request => {
    const envelope = store.deliveryEnvelope(request.dispatch, control);
    const admitted = control.admitPollDispatch(envelope);
    if ((request.dispatchEnvelope !== undefined && request.dispatchEnvelope !== envelope) ||
        (request.inputBindingBody !== undefined && request.inputBindingBody !==
          control.pollDispatchBindingBody(admitted))) {
      fail('RemoteDispatchDeliveryMaterialsCollision');
    }
    return Object.freeze({...request, dispatchEnvelope: envelope,
      inputBindingBody: control.pollDispatchBindingBody(admitted)});
  };
  const currentContext = (dispatch, envelope) => {
    const context = currentDispatchContext(dispatch, envelope);
    if (context === null || typeof context !== 'object' ||
        !text(context.coordinatorAuthority) || !text(context.siteKey) ||
        !Number.isSafeInteger(context.siteGeneration) ||
        context.siteGeneration < 0 || context.siteGeneration > 2147483647 ||
        typeof context.authorizationCurrent !== 'boolean' ||
        typeof context.cancellationRequested !== 'boolean') {
      fail('InvalidRemoteCoordinatorRecoveryContext');
    }
    return context;
  };
  const recoverDispatch = async value => {
    const request = requireIntent(value);
    if (currentDispatchContext === undefined) fail('RemoteCoordinatorRecoveryUnavailable');
    // A legacy intent still permits query and cleanup, but no materials may be
    // attached afterwards: we cannot prove that its first send never occurred.
    const retained = retainedDelivery(request);
    let notSeenBody = '';
    let response;
    try {
      response = await exchange(request, query);
    } catch (error) {
      if (error?.code !== 'RemoteDispatchNotSeen' ||
          typeof error.notSeenBody !== 'string') throw error;
      // Re-admit the exact authenticated transport reply in the common owner.
      control.admitPollNotSeen(error.notSeenBody, request.dispatch);
      notSeenBody = error.notSeenBody;
    }
    const facts = dispatchFacts(request.dispatch);
    const decision = await requireDispatch('activation', {
      connection: facts.site, resource: facts.registration, operation: 'write',
    }, facts.runDefinitionCid, request.signal, request.resumption);
    if (request.resumption !== undefined) enterResumed(decision, control.identity(request.dispatch));
    // No await from the CURRENT checked Host projection through decision/send.
    const context = currentContext(request.dispatch, retained.dispatchEnvelope);
    if (!control.coordinatorRedeliveryEligible(recordFor(request.dispatch),
        request.dispatch, notSeenBody, context)) {
      if (response !== undefined && context.authorizationCurrent && !context.cancellationRequested) {
        return Object.freeze({action: 'reconciled', observation: response});
      }
      fail('RemoteDispatchRedeliveryDenied');
    }
    const observation = await exchange(retained, send);
    return Object.freeze({action: 'redelivered', observation});
  };
  return Object.freeze({
    recovered,
    recoveredOutputs,
    // The Host supplies its currently authenticated Site/generation binding.
    // Received identity is only a lookup hint; the typed existing admitter
    // checks the whole response against the exact durable request below.
    receiveObservation({body, binding} = {}) {
      if (typeof body !== 'string' || Buffer.byteLength(body) > 65_536 ||
          !text(binding?.siteKey) || !Number.isSafeInteger(binding?.siteGeneration)) {
        fail('InvalidRemoteCoordinatorObservation');
      }
      let hint;
      try { hint = JSON.parse(body); }
      catch (cause) {
        throw Object.assign(new Error('RemoteCoordinatorObservationRejected', {cause}),
          {code: 'RemoteCoordinatorObservationRejected', issueCode: 'InvalidDispatch'});
      }
      const retained = records.get(hint?.dispatch_request_cid);
      if (retained === undefined) fail('RemoteDispatchIntentMissing');
      const key = control.journalKey(retained.dispatch);
      if (key[1] !== binding.siteKey || Number(key[2]) !== binding.siteGeneration) {
        fail('RemoteCoordinatorObservationScopeMismatch');
      }
      if (hint.version === 'actql-remote-output-result/0.1') {
        const output = outputs.get(`${hint.dispatch_request_cid}:${hint.intent_cid}`);
        if (output === undefined) fail('RemoteCoordinatorOutputRecordMissing');
        const result = control.admitOutputResult(body, output.output,
          output.payloadRequest, output.transferRequest);
        const saved = store.inspectOutput(output.record, control);
        if (saved?.progress === 2) {
          if (saved.resultJson !== body || saved.resultCid !== control.outputResultIdentity(result)) {
            fail('RemoteCoordinatorOutputReportConflict');
          }
          // The SQLite commit may have succeeded while the caller lost the
          // response.  Rebuild the in-memory owner from that exact durable
          // fact before issuing an ACK; do not advance it or mint a new
          // revision on replay.
          const local = control.coordinatorOutputRecordStatus(output.record);
          if (Number(local[0]) !== saved.revision ||
              Number(local[1]) !== saved.progress ||
              local[2] !== saved.resultCid) {
            control.restoreCoordinatorOutputRecord(
              output.record,
              saved.revision,
              saved.progress,
              saved.resultJson,
            );
          }
        } else {
          const transition = control.prepareCoordinatorOutputSuccess(output.record, result);
          store.advanceOutputSuccess(transition, result, output.record, control);
        }
        // Recheck durable fact even if the local owner already succeeded.
        const confirmed = store.inspectOutput(output.record, control);
        if (confirmed?.progress !== 2 || confirmed.resultJson !== body) {
          fail('RemoteCoordinatorOutputAcceptanceUnconfirmed');
        }
        return Object.freeze({outputAckWire:
          control.coordinatorOutputReportAckJson(output.record, body)});
      }
      try {
        const statusReply = hint.version === 'actql-remote-dispatch-status/0.1';
        const admitted = control.admitResponseJson(body, retained.dispatch, statusReply);
        return observe(retained.dispatch, projectRemoteDispatchResponse(
          control, retained.dispatch, admitted, {statusReply}));
      } catch (cause) {
        const issueCode = control.coordinatorObservationIssueCode?.(cause);
        if (!issueCode) throw cause;
        throw Object.assign(new Error('RemoteCoordinatorObservationRejected', {cause}),
          {code: 'RemoteCoordinatorObservationRejected', issueCode});
      }
    },
    async dispatch(value) {
      const request = options(value);
      if (currentDispatchContext !== undefined && store.contains(request.dispatch, control)) {
        // Calling dispatch again is recovery, never an unconditional send.
        if (request.dispatchEnvelope !== undefined &&
            request.dispatchEnvelope !== store.deliveryEnvelope(request.dispatch, control)) {
          fail('RemoteDispatchDeliveryMaterialsCollision');
        }
        // Preserve dispatch's existing observation return shape. Only the
        // explicit recovery operation adds its transport action projection.
        return (await recoverDispatch(request)).observation;
      }
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
      if (request.resumption !== undefined) {
        enterResumed(decision, control.identity(request.dispatch));
      }
      const admission = control.prepareCoordinatorIntent(
        journal,
        request.dispatch,
      );
      const envelope = currentDispatchContext === undefined ? undefined
        : control.coordinatorDeliveryEnvelopeJson(request.dispatch,
          request.dispatchEnvelope ?? control.pollJson(request.dispatch,
            control.prepareInputBinding(request.inputBindingBody)));
      if (envelope !== undefined && !control.coordinatorDeliveryContextCurrent(
          request.dispatch, currentContext(request.dispatch, envelope))) {
        fail('RemoteDispatchRedeliveryDenied');
      }
      const record = store.accept(admission, request.dispatch, control, envelope);
      records.set(control.identity(request.dispatch),
        Object.freeze({dispatch: request.dispatch, record}));
      if (envelope !== undefined) {
        const context = currentContext(request.dispatch, envelope);
        if (!control.coordinatorDeliveryContextCurrent(request.dispatch, context)) {
          fail('RemoteDispatchRedeliveryDenied');
        }
      }
      return exchange(envelope === undefined ? request : retainedDelivery(request), send);
    },
    recoverDispatch,
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
