import {
  cancelRemoteDispatch,
  queryRemoteDispatch,
  releaseRemoteDispatch,
  sendRemoteDispatch,
} from './remote-site-client.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
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
  transferControl,
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
  if (planOutput !== undefined && typeof planOutput !== 'function') {
    fail('InvalidRemoteSiteCoordinatorOutputPlan');
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
      typeof control.prepareCoordinatorOutputSuccess !== 'function')) {
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
  return Object.freeze({
    recovered,
    recoveredOutputs,
    async dispatch(value) {
      const request = options(value);
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
      try {
        const response = await executeOutput(Object.freeze({
          ...request,
          payloadRequest,
          transferRequest,
        }));
        if (response === null || typeof response !== 'object' ||
            response.result === undefined) {
          fail('InvalidRemoteCoordinatorOutputResult');
        }
        if (store.inspectOutput(record, control)?.progress === 2) {
          return projectOutputRecord(record);
        }
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
        return projectOutputRecord(record);
      } catch (error) {
        const state = store.inspectOutput(record, control);
        if (state?.progress === 2) return projectOutputRecord(record);
        const transition = control.prepareCoordinatorOutputUnknown(record);
        store.advanceOutputUnknown(transition, record, control);
        throw error;
      }
    },
    completionEvidenceAvailable(value) {
      const request = requireIntent(value);
      return control.coordinatorCompletionEvidenceAvailable(
        recordFor(request.dispatch),
      );
    },
  });
}
