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
      journal === undefined || store === null || typeof store !== 'object' ||
      typeof store.accept !== 'function' ||
      typeof store.contains !== 'function' ||
      typeof store.recoverJournal !== 'function' ||
      typeof send !== 'function' || typeof query !== 'function' ||
      typeof cancel !== 'function') {
    fail('InvalidRemoteSiteCoordinator');
  }
  const recovered = store.recoverJournal(journal, control);
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
  return Object.freeze({
    recovered,
    async dispatch(value) {
      const request = options(value);
      const admission = control.prepareCoordinatorIntent(
        journal,
        request.dispatch,
      );
      store.accept(admission, request.dispatch, control);
      return send(request);
    },
    query(value) {
      return query(requireIntent(value));
    },
    cancel(value) {
      return cancel(requireIntent(value));
    },
  });
}
