import {prepareInstalledRemoteRuntimeRegistration} from
  './remote-dispatch-runtime.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const method = (value, name) => value !== null &&
  typeof value === 'object' && typeof value[name] === 'function';

function failureEnvelope(primary, failure, control) {
  let pending = true;
  const diagnostics = [];
  const retry = async () => {
    try {
      pending = control.retryFailureCleanup(failure) !== true;
    } catch (error) {
      diagnostics.push(error);
      pending = true;
    }
    return Object.freeze({
      pending,
      errors: Object.freeze([...diagnostics]),
    });
  };
  const envelope = Object.assign(
    new Error(control.failureCode(failure), {cause: primary}),
    {code: control.failureCode(failure)},
  );
  envelope.cleanupPending = true;
  envelope.cleanupHandle = Object.freeze({
    status: () => Object.freeze({
      pending,
      errors: Object.freeze([...diagnostics]),
    }),
    retry,
  });
  envelope.cleanupErrors = Object.freeze([]);
  return Object.freeze({envelope, retry});
}

/**
 * Connect a retained direct-Transfer receiver to a registered MoonBit task
 * session. JavaScript owns only asynchronous physical streaming. The supplied
 * control owns binding admission, framing, row verification, Run creation,
 * execution, output facts, and cleanup eligibility.
 */
export function createRemoteStandardDirectExecution({receiver, control} = {}) {
  if (!method(receiver, 'claim') || !method(receiver, 'consume') ||
      control === null || typeof control !== 'object' ||
      typeof control.requestCid !== 'function' ||
      typeof control.prepare !== 'function' ||
      typeof control.authorize !== 'function' ||
      typeof control.feed !== 'function' ||
      typeof control.finish !== 'function' ||
      typeof control.cancel !== 'function' ||
      typeof control.failureCode !== 'function' ||
      typeof control.retryFailureCleanup !== 'function') {
    fail('InvalidRemoteStandardDirectExecution');
  }
  return async function execute({dispatch, inputBinding, signal} = {}) {
    if (dispatch === undefined || inputBinding === undefined) {
      fail('RemoteStandardInputBindingMissing');
    }
    signal?.throwIfAborted();
    const requestCid = control.requestCid(dispatch, inputBinding);
    if (typeof requestCid !== 'string' || requestCid.length === 0) {
      fail('RemoteStandardTransferRequestMissing');
    }
    const claimed = receiver.claim(requestCid);
    let physicalAvailable = true;
    let terminal = false;
    let session;
    try {
      session = control.prepare(
        dispatch,
        inputBinding,
        claimed,
        () => physicalAvailable,
        () => {
          physicalAvailable = false;
          return true;
        },
      );
      await receiver.consume(
        requestCid,
        current => control.authorize(session, current) === true,
        async (index, frame) => {
          signal?.throwIfAborted();
          if (control.feed(session, index, frame) !== true) {
            fail('RemoteStandardInputRejected');
          }
        },
        signal,
      );
      signal?.throwIfAborted();
      const output = control.finish(session);
      terminal = true;
      return output;
    } catch (primary) {
      if (session === undefined || terminal) throw primary;
      let failure;
      try {
        failure = control.cancel(session);
      } catch (cancelError) {
        throw new AggregateError(
          [primary, cancelError],
          'Remote standard input cancellation failed',
        );
      }
      const owned = failureEnvelope(primary, failure, control);
      const state = await owned.retry();
      owned.envelope.cleanupPending = state.pending;
      owned.envelope.cleanupErrors = state.errors;
      throw owned.envelope;
    }
  };
}

/**
 * Register one direct-input task from the exact verified active component.
 * The component loader returns only a MoonBit session control; it cannot
 * replace the common runtime registration or install an arbitrary executor.
 */
export async function prepareInstalledRemoteStandardDirectRegistration({
  receiver,
  loadSessionControl,
  ...registration
} = {}) {
  if (typeof loadSessionControl !== 'function') {
    fail('InvalidRemoteStandardSessionLoader');
  }
  return await prepareInstalledRemoteRuntimeRegistration({
    ...registration,
    load: async bundle => createRemoteStandardDirectExecution({
      receiver,
      control: await loadSessionControl(bundle),
    }),
  });
}
