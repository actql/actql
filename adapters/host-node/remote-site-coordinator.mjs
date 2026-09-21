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
      if (request.intent === undefined ||
          request.payloadRequest === undefined ||
          request.transferRequest === undefined) {
        fail('InvalidRemoteCoordinatorOutput');
      }
      const output = control.admitPollOutput(
        control.pollOutputJson(request.dispatch, request.intent),
      );
      const admission = control.prepareCoordinatorOutput(
        journal,
        output,
        request.payloadRequest,
        request.transferRequest,
      );
      const record = store.acceptOutput(
        admission,
        request.payloadRequest,
        request.transferRequest,
        control,
        transferControl,
      );
      const current = store.inspectOutput(record, control);
      if (current?.progress === 2) return projectOutputRecord(record);
      try {
        const response = await executeOutput(request);
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
