// A query composes existing admission, observation and Result owners. It never
// resubmits, reconciles a Run, answers a Checkpoint, or retries a Result read.
const queryOptionNames = new Set(['requestId', 'signal', 'result',
  'parameterDeclarations']);

// Collection happens later, but its caller-owned options are chosen now.
// AbortSignal remains a live signal; never JSON-clone it or defer this capture.
function captureReadOptions(options) {
  if (options === null || typeof options !== 'object' &&
      typeof options !== 'function' || Array.isArray(options)) return options;
  // Match ordinary ReadOptions property access, including class/inherited or
  // non-enumerable values. Spreading would silently discard a tighter limit.
  return Object.freeze(Object.fromEntries(['signal', 'maxWireBytes',
    'maxRowWireBytes', 'maxRowRetainedValueBytes', 'maxRows',
    'maxRetainedValueBytes', 'maxBatchRows', 'maxBatchRetainedValueBytes']
    .map(name => [name, options[name]])));
}

function executionError(ClientError, code, execution, requestId, state, cause) {
  const error = new ClientError(code, {requestId,
    executionRef: execution.ref});
  // Live handles, observations and underlying failures are explicit inspection
  // material, not part of a default JSON diagnostic.
  Object.defineProperties(error, {
    execution: {value: execution},
    ...(state === undefined ? {} : {observation: {value: state}}),
    ...(cause === undefined ? {} : {cause: {value: cause}}),
  });
  return error;
}

export function sourceQuery(startSource, ClientError, retainResult,
  format, text, parameters, options = {}) {
  let requestId, admission, signal, selectedResult;
  try {
    requestId = options?.requestId ?? crypto.randomUUID();
    if (typeof requestId !== 'string' || !requestId) {
      throw new ClientError('InvalidRequestId');
    }
    if (options === null || typeof options !== 'object' ||
        Array.isArray(options) ||
        Object.keys(options).some(key => !queryOptionNames.has(key))) {
      throw new ClientError('InvalidQueryOptions');
    }
    selectedResult = options.result;
    if (selectedResult !== undefined &&
        (typeof selectedResult !== 'string' || !selectedResult)) {
      throw new ClientError('InvalidResultName');
    }
    if (parameters !== undefined && parameters !== null &&
        (typeof parameters !== 'object' || Array.isArray(parameters))) {
      throw new ClientError('InvalidQueryParameters');
    }
    signal = options.signal;
    // startSource captures JSON source/declarations/parameters synchronously,
    // before credentials or I/O. Do not serialize caller-owned inputs twice.
    admission = startSource(text, {format, parameters, requestId, signal,
      ...(options.parameterDeclarations === undefined ? {} :
        {parameterDeclarations: options.parameterDeclarations})});
  } catch (cause) {
    // An unreadable option has no admission identity; expose one local call ID
    // consistently without evaluating the accessor again or sending anything.
    requestId ??= crypto.randomUUID();
    admission = Promise.reject(cause);
  }
  const query = admission.then(async execution => {
    let state;
    try { state = await execution.wait({until: 'terminal', signal}); }
    catch (cause) {
      throw executionError(ClientError, 'QueryObservationUnknown', execution,
        requestId, undefined, cause);
    }
    if (state.status !== 'succeeded') {
      const code = ['failed', 'cancelled'].includes(state.status)
        ? 'ExecutionUnsuccessful'
        : state.status === 'waiting_checkpoint' ||
          state.status === 'needs_reconciliation' ||
          state.next_action.kind === 'reconcile_run'
        ? 'ExecutionBlocked' : 'ExecutionPending';
      // wait may return a current nonterminal observation. It is neither
      // success nor permission to poll, resume, or submit another request.
      throw executionError(ClientError, code, execution, requestId, state);
    }
    const names = Object.keys(state.result_availability);
    const name = selectedResult ?? (names.length === 1 ? names[0] : undefined);
    if (name === undefined || !Object.hasOwn(state.result_availability, name)) {
      throw executionError(ClientError, name === undefined
        ? 'ResultSelectionRequired' : 'UnknownResultName', execution,
      requestId, state);
    }
    if (state.result_availability[name].state !== 'available') {
      throw executionError(ClientError, 'ResultUnavailable', execution,
        requestId, state);
    }
    const result = execution.result(name);
    retainResult(execution, result);
    return result;
  });
  // Keep one native Promise. Native chaining/assimilation and repeated awaits
  // share this operation; each explicitly requested collection opens a read.
  Object.defineProperties(query, {
    requestId: {value: requestId, enumerable: true},
    all: {value: options => {
      const captured = captureReadOptions(options);
      return query.then(result => result.all(captured));
    }},
    one: {value: options => {
      const captured = captureReadOptions(options);
      return query.then(result => result.one(captured));
    }},
    scalar: {value: options => {
      const captured = captureReadOptions(options);
      return query.then(result => result.scalar(captured));
    }},
  });
  return Object.freeze(query);
}
