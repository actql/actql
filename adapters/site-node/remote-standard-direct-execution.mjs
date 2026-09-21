import {prepareInstalledRemoteRuntimeRegistration} from
  './remote-dispatch-runtime.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const method = (value, name) => value !== null &&
  typeof value === 'object' && typeof value[name] === 'function';

function failureEnvelope(primary, failure, control) {
  const diagnostics = [];
  const status = () => {
    let pending = true;
    try {
      pending = control.failureCleanupPending(failure) === true;
    } catch (error) {
      diagnostics.push(error);
    }
    return Object.freeze({
      pending,
      errors: Object.freeze([...diagnostics]),
    });
  };
  const retry = async () => {
    try {
      control.retryFailureCleanup(failure);
    } catch (error) {
      diagnostics.push(error);
    }
    return status();
  };
  const envelope = Object.assign(
    new Error(control.failureCode(failure), {cause: primary}),
    {code: control.failureCode(failure)},
  );
  envelope.cleanupPending = true;
  envelope.cleanupHandle = Object.freeze({
    status,
    retry,
  });
  envelope.cleanupErrors = Object.freeze([]);
  return Object.freeze({envelope, retry});
}

/**
 * Adapt the generated MoonBit direct-source control to the asynchronous
 * execution hook owned by one verified runtime component. MoonBit keeps the
 * input admission and release owner; the hook only executes the captured
 * source after verification has completed.
 */
export function createRemoteStandardSourceSessionControl({
  portable,
  factory,
  executeCaptured,
} = {}) {
  if (portable === null || typeof portable !== 'object' ||
      typeof portable.requestCid !== 'function' ||
      typeof portable.start !== 'function' ||
      typeof portable.authorize !== 'function' ||
      typeof portable.feed !== 'function' ||
      typeof portable.finish !== 'function' ||
      typeof portable.cancel !== 'function' ||
      typeof portable.captured !== 'function' ||
      typeof portable.release !== 'function' ||
      typeof portable.failureCode !== 'function' ||
      typeof portable.failureCleanupPending !== 'function' ||
      typeof portable.retryFailureCleanup !== 'function' ||
      factory === undefined || typeof executeCaptured !== 'function') {
    fail('InvalidRemoteStandardSourceSessionControl');
  }
  return Object.freeze({
    requestCid(_dispatch, binding) {
      return portable.requestCid(factory, binding);
    },
    prepare(dispatch, binding, claim, available, release) {
      return portable.start(
        factory,
        dispatch,
        binding,
        claim,
        available,
        release,
      );
    },
    authorize: portable.authorize,
    feed: portable.feed,
    async finish(session) {
      const source = portable.finish(session);
      if (source === undefined) fail('RemoteStandardInputRejected');
      const captured = portable.captured(source);
      const output = await executeCaptured(captured);
      if (portable.release(source) !== true) {
        fail('RemoteStandardInputReleasePending');
      }
      return output;
    },
    cancel: portable.cancel,
    failureCode: portable.failureCode,
    failureCleanupPending: portable.failureCleanupPending,
    retryFailureCleanup: portable.retryFailureCleanup,
  });
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
      typeof control.failureCleanupPending !== 'function' ||
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
      const output = await control.finish(session);
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
  portable,
  loadSourceExecution,
  ...registration
} = {}) {
  if (typeof loadSourceExecution !== 'function') {
    fail('InvalidRemoteStandardSourceLoader');
  }
  return await prepareInstalledRemoteRuntimeRegistration({
    ...registration,
    load: async bundle => {
      const selected = await loadSourceExecution(bundle);
      if (selected === null || typeof selected !== 'object') {
        fail('InvalidRemoteStandardSourceExecution');
      }
      const control = createRemoteStandardSourceSessionControl({
        portable,
        factory: selected.factory,
        executeCaptured: selected.executeCaptured,
      });
      return createRemoteStandardDirectExecution({receiver, control});
    },
  });
}
