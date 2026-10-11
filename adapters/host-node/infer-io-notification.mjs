// A bounded physical wakeup, not an acknowledgement, outcome or send permit.
// One original operation claims it once. Notifications carry no model data.
const notifications = new WeakMap();

export function createInferIoNotification() {
  const state = {claimed: false, closed: false, pending: false, waiter: undefined};
  const notify = () => {
    if (state.closed) return false;
    if (state.waiter === undefined) state.pending = true;
    else {
      const resolve = state.waiter.resolve;
      state.waiter.resolve = undefined;
      resolve?.();
    }
    return true;
  };
  const notification = Object.freeze({notify});
  notifications.set(notification, state);
  return notification;
}

// The private driver claims the nominal notifier before constructing Core.
// A second operation cannot consume another operation's pending notification.
export function claimInferIoNotification(notification) {
  const state = notifications.get(notification);
  if (state === undefined || state.claimed || state.closed) {
    throw new TypeError('InvalidInferIoNotification');
  }
  state.claimed = true;
  return Object.freeze({
    arm() {
      if (state.closed || state.waiter !== undefined) {
        throw new TypeError('InferIoWaitAlreadyOwned');
      }
      const waiter = {resolve: undefined};
      const promise = new Promise(resolve => { waiter.resolve = resolve; });
      state.waiter = waiter;
      if (state.pending) {
        state.pending = false;
        const resolve = waiter.resolve;
        waiter.resolve = undefined;
        resolve();
      }
      return Object.freeze({promise, dispose() {
        if (state.waiter === waiter) state.waiter = undefined;
        const resolve = waiter.resolve;
        waiter.resolve = undefined;
        // Disposing a non-I/O poll also retires its otherwise pending Promise.
        resolve?.();
      }});
    },
    notify: notification.notify,
    close() {
      state.closed = true;
      state.pending = false;
      const waiter = state.waiter;
      state.waiter = undefined;
      const resolve = waiter?.resolve;
      if (waiter !== undefined) waiter.resolve = undefined;
      resolve?.();
    },
  });
}
