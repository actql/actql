import {captureReadOptions, captureResultRead} from './result-schema.mjs';

// A query composes existing admission, observation and Result owners. It never
// resubmits, reconciles a Run, answers a Checkpoint, or retries a Result read.
const queryOptionNames = new Set(['requestId', 'signal', 'result',
  'parameterDeclarations', 'submissionRef']);

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

function collectAfterQuery(query, retainInput, capture, read) {
  let captured, captureError, captureFailed = false;
  try { captured = capture(); }
  catch (cause) { captureFailed = true; captureError = cause; }
  // Capture arguments immediately, but always observe the eager query. Its
  // admission/held/observation failure takes precedence and keeps its identity;
  // a local argument failure must not leave that query rejection orphaned.
  const collected = query.then(result => {
    if (captureFailed) throw captureError;
    return read(result, captured);
  });
  retainInput(query, collected);
  return collected;
}

export function sourceQuery(startSource, ClientError, retainResult,
  format, text, parameters, options = {}, submissionOwner) {
  let requestId, admission, signal, selectedResult;
  try {
    const requestedId = options?.requestId;
    const original = options?.submissionRef;
    requestId = requestedId ?? original?.nonce ?? crypto.randomUUID();
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
    if (original === undefined && requestedId !== undefined) {
      throw new ClientError('SubmissionReferenceRequired');
    }
    const submissionRef = original ?? submissionOwner.newSubmission({nonce: requestId});
    // startSource captures JSON source/declarations/parameters synchronously,
    // before credentials or I/O. Do not serialize caller-owned inputs twice.
    admission = startSource(text, {format, parameters, requestId, signal, submissionRef,
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
      const error = executionError(ClientError, 'QueryObservationUnknown', execution,
        requestId, undefined, cause);
      retainResult(execution, error);
      throw error;
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
      const error = executionError(ClientError, code, execution, requestId, state);
      retainResult(execution, error);
      throw error;
    }
    const names = Object.keys(state.result_availability);
    const name = selectedResult ?? (names.length === 1 ? names[0] : undefined);
    if (name === undefined || !Object.hasOwn(state.result_availability, name)) {
      const error = executionError(ClientError, name === undefined
        ? 'ResultSelectionRequired' : 'UnknownResultName', execution,
      requestId, state);
      retainResult(execution, error);
      throw error;
    }
    if (state.result_availability[name].state !== 'available') {
      const error = executionError(ClientError, 'ResultUnavailable', execution,
        requestId, state);
      retainResult(execution, error);
      throw error;
    }
    const result = execution.result(name);
    retainResult(execution, result);
    return result;
  });
  submissionOwner.retainInput(admission, query);
  // Keep one native Promise. Native chaining/assimilation and repeated awaits
  // share this operation; each explicitly requested collection opens a read.
  Object.defineProperties(query, {
    requestId: {value: requestId, enumerable: true},
    all: {value: (schemaOrOptions, options) => collectAfterQuery(query, submissionOwner.retainInput,
      () => captureResultRead(ClientError, schemaOrOptions, options),
      (result, captured) => captured.validate === undefined
        ? result.all(captured.options)
        : result.all({'~standard': {version: 1, vendor: 'actql-captured',
          validate: captured.validate}}, captured.options))},
    one: {value: options => collectAfterQuery(query, submissionOwner.retainInput,
      () => captureReadOptions(options), (result, captured) => result.one(captured))},
    scalar: {value: options => collectAfterQuery(query, submissionOwner.retainInput,
      () => captureReadOptions(options), (result, captured) => result.scalar(captured))},
  });
  return Object.freeze(query);
}
