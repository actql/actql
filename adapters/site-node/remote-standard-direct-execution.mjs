import {prepareInstalledRemoteRuntimeRegistration} from
  './remote-dispatch-runtime.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const method = (value, name) => value !== null &&
  typeof value === 'object' && typeof value[name] === 'function';

const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

const cleanupState = (handle, required) => {
  if (!required) return {pending: false, errors: []};
  if (!method(handle, 'status')) return {pending: true, errors: []};
  try {
    const state = handle.status();
    return state !== null && typeof state === 'object' &&
      typeof state.pending === 'boolean'
      ? {pending: state.pending,
        errors: Array.isArray(state.errors) ? [...state.errors] : []}
      : {pending: true, errors: []};
  } catch (error) {
    return {pending: true, errors: [error]};
  }
};

function outputCleanupFailure(primary, output) {
  const diagnostics = [];
  let closed = false;
  const close = async () => {
    if (closed) return;
    if (!method(output, 'close')) {
      diagnostics.push(new Error('RemoteStandardOutputCleanupUnavailable'));
      return;
    }
    try {
      await output.close();
      closed = true;
    } catch (error) {
      diagnostics.push(error);
    }
  };
  const failure = Object.assign(
    new Error('RemoteStandardInputReleasePending', {cause: primary}),
    {code: 'RemoteStandardInputReleasePending'},
  );
  const status = () => Object.freeze({
    pending: !closed,
    errors: Object.freeze([...diagnostics]),
  });
  const handle = Object.freeze({
    status,
    async retry() {
      await close();
      failure.cleanupPending = !closed;
      failure.cleanupErrors = status().errors;
      return status();
    },
  });
  failure.cleanupPending = true;
  failure.cleanupErrors = Object.freeze([]);
  failure.cleanupHandle = handle;
  return failure;
}

async function failureEnvelope(primary, session, control) {
  const diagnostics = [];
  const upstreamRequired = member(primary, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(primary, 'cleanupHandle') : undefined;
  let inputFailure;
  let inputOwned = true;
  let envelope;
  const upstreamState = () => cleanupState(upstream, upstreamRequired);
  const inputState = () => {
    if (inputOwned) return {pending: true, errors: []};
    try {
      return {
        pending: control.failureCleanupPending(inputFailure) === true,
        errors: [],
      };
    } catch (error) {
      return {pending: true, errors: [error]};
    }
  };
  const status = () => {
    const execution = upstreamState();
    const input = inputState();
    return Object.freeze({
      pending: execution.pending || input.pending,
      errors: Object.freeze([
        ...execution.errors,
        ...input.errors,
        ...diagnostics,
      ]),
    });
  };
  const retry = async () => {
    let execution = upstreamState();
    if (execution.pending && method(upstream, 'retry')) {
      try { await upstream.retry(); }
      catch (error) { diagnostics.push(error); }
      execution = upstreamState();
    }
    if (!execution.pending && inputOwned) {
      try {
        inputFailure = control.cancel(session);
        inputOwned = false;
      } catch (error) {
        diagnostics.push(error);
      }
    }
    if (!inputOwned && inputState().pending) {
      try { control.retryFailureCleanup(inputFailure); }
      catch (error) { diagnostics.push(error); }
    }
    const state = status();
    if (envelope !== undefined) {
      envelope.cleanupPending = state.pending;
      envelope.cleanupErrors = state.errors;
    }
    return state;
  };
  await retry();
  let code = typeof member(primary, 'code') === 'string'
    ? member(primary, 'code') : 'RemoteStandardExecutionFailed';
  if (!inputOwned) {
    try { code = control.failureCode(inputFailure); }
    catch (error) { diagnostics.push(error); }
  }
  envelope = Object.assign(
    new Error(code, {cause: primary}),
    {code, primaryFailure: primary},
  );
  const handle = Object.freeze({
    status,
    retry,
  });
  envelope.cleanupHandle = handle;
  envelope.cleanupPending = status().pending;
  envelope.cleanupErrors = status().errors;
  return envelope;
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
      let releaseFailure;
      try {
        if (portable.release(source) !== true) {
          releaseFailure = new Error('RemoteStandardInputReleasePending');
        }
      } catch (error) {
        releaseFailure = error;
      }
      if (releaseFailure !== undefined) {
        throw outputCleanupFailure(releaseFailure, output);
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
      throw await failureEnvelope(primary, session, control);
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
