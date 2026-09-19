import {
  cancelRemoteDispatch,
  queryRemoteDispatch,
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
      typeof send !== 'function' || typeof query !== 'function' ||
      typeof cancel !== 'function') {
    fail('InvalidRemoteSiteCoordinator');
  }
  const recovered = store.recoverJournal(journal, control);
  const records = new Map(recovered.map(value => [
    control.identity(value.request),
    value.record,
  ]));
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
    if (response.evidence === undefined) {
      store.advance(transition, record, control);
    } else {
      store.advanceEvidence(transition, response.evidence, record, control);
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
  return Object.freeze({
    recovered,
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
    completionEvidenceAvailable(value) {
      const request = requireIntent(value);
      return control.coordinatorCompletionEvidenceAvailable(
        recordFor(request.dispatch),
      );
    },
  });
}
