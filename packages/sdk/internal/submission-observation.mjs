// Original Submission/Request inputs, invocation outcomes and lookup custody.
// Transport dispatch facts and Host certificates remain separate.
import {projectRequestCancellationExplanation, projectRequestLookupExplanation,
  projectRequestLookupFailure, projectSubmissionAttemptExplanation, projectSubmissionExplanation,
  projectSubmissionLookupFailure, projectSubmissionNotSent, submissionLookupExplanation,
  localizeOperation} from '../operation-presentation.mjs';
import {bytesCid, canonicalJson} from '../checkpoints.mjs';
import {sourceQuery} from '../source-query.mjs';
import {bindCheckObservation} from './check-observation.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {ClientError, RequestHeld, fail, requestCancellationCause} from './errors.mjs';
import {copyRunObservationFailure} from './run-observation.mjs';
import {controlValue} from './transport-response.mjs';
import {clientSourceFormats, snapshotClientRequest, validClientAdmission, validOperationAttemptRef,
  validRequestCancellation, validRequestLookup, validRunRef, validSubmissionAttempt,
  validNamedSubmissionAttempt, validSubmissionName,
  validSubmissionLookup, validSubmissionRef, validSubmissionRestart} from '@actql/client-wire';

// Original request data is available only through explicit SDK access, never
// by serializing an error or Run handle. It does not establish acceptance.
const submissionInputs = new WeakMap();
// A private receipt records publication of an immutable caller-facing value.
// It owns no Host, Ledger, Prepared, or destination Promise reference. Host
// aliases remain separately funded until their actual retirement.
const snapshotPublications = new WeakMap();
export function matchesPublishedSubmissionSnapshot(receipt, body) {
  return snapshotPublications.get(receipt)?.body === body && body !== undefined;
}
const publishSnapshot = (destination, body) => {
  const snapshot = submissionInputs.get(destination);
  if (snapshot === undefined || snapshot.input !== body.input ||
      snapshot.submissionRef !== body.submissionRef) return undefined;
  const receipt = Object.freeze({});
  snapshotPublications.set(receipt, {body, snapshot});
  return receipt;
};

const submissionOutcomes = new WeakMap();

const submissionAttempts = new WeakMap();

const submissionCheckObservations = new WeakMap();

const submissionContexts = new WeakMap();
// Presentation is bound by the validated submit branch, never an error string.
const submissionExplanations = new WeakMap();

const requestLookupExplanations = new WeakMap();
// Keep this call's lookup target even when a found observation explains the
// Run instead. This association is not an admission record or replay grant.
const requestLookupContexts = new WeakMap();

const requestCancellationExplanations = new WeakMap();

export function getSubmissionCheckObservation(result) {
  return submissionCheckObservations.get(result);
}

export function getSubmissionInput(result) {
  return submissionInputs.get(result);
}

// Only an admitted response for this exact SDK operation supplies Owner facts.
export function getSubmissionOutcome(result) {
  return submissionOutcomes.get(result);
}

export function getSubmissionAttempt(result) {
  return submissionAttempts.get(result);
}

export function explainSubmission(result, options) {
  return localizeOperation(submissionExplanations.get(result), 'submission', options);
}

// Only this call's admitted lookup supplies Owner facts. A rejected observation
// retains its original lookup target, never unvalidated response fields.
export function explainRequestLookup(result, options) {
  return localizeOperation(requestLookupExplanations.get(result), 'request', options);
}

export function explainRequestCancellation(result, options) {
  return localizeOperation(requestCancellationExplanations.get(result), 'requestCancellation', options);
}

const retainSubmissionAttemptExplanation = (result, attempt, snapshot) => {
  requestLookupContexts.set(result, snapshot);
  submissionExplanations.set(result, projectSubmissionAttemptExplanation(result, attempt, snapshot));
  return result;
};

const retainSubmissionExplanation = (result, outcome, context) => {
  requestLookupContexts.set(result, context);
  submissionExplanations.set(result, projectSubmissionExplanation(result, outcome, context));
  return result;
};

const retainSubmissionLookupFailure = (cause, context, observation) => {
  let error;
  try {error = requestCancellationCause(cause);}
  catch {error = new ClientError('ClientTransportUnknown');}
  requestLookupContexts.set(error, context);
  submissionExplanations.set(error, projectSubmissionLookupFailure(context, observation));
  return error;
};

const retainRequestLookupExplanation = (answer, context) => {
  requestLookupContexts.set(answer, context);
  requestLookupExplanations.set(answer, projectRequestLookupExplanation(answer, context));
  return answer;
};

const retainRequestLookupFailure = (error, context, observation) => {
  // Borrowed exceptions may be reused by credentials or a Local port. Each
  // call owns its error; code/status are metadata, never outcome evidence.
  const code = error instanceof ClientError ? error.code : 'ClientTransportUnknown';
  const status = error instanceof ClientError ? error.status : undefined;
  const retained = new ClientError(code,
    Number.isInteger(status) && status >= 100 && status <= 599 ? {status} : {});
  requestLookupContexts.set(retained, context);
  requestLookupExplanations.set(retained, projectRequestLookupFailure(context, observation));
  return retained;
};

const retainRequestCancellationExplanation = (result, context, observation, problem) => {
  requestCancellationExplanations.set(result, projectRequestCancellationExplanation(result, context, observation, problem));
  return result;
};

const uninterpretableRequestCancellation = context => retainRequestCancellationExplanation(
  new ClientError('CancellationUnknown', {requestId: context.requestId,
    cause: new ClientError('InvalidHostRequestCancellation')}),
  context, 'outcome_unknown', 'response_uninterpretable');

const recoveryData = (value, keys) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) return undefined;
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== keys.length ||
      keys.some(key => !Object.hasOwn(fields, key) ||
        !Object.hasOwn(fields[key], 'value'))) return undefined;
  return Object.fromEntries(keys.map(key => [key, fields[key].value]));
};

const requestRecoveryTarget = value => {
  const retained = submissionInputs.get(value) ?? requestLookupContexts.get(value);
  if (retained) return retained.submissionRef === undefined
    ? {operation: 'lookupRequest', requestId: retained.requestId, lookupContext: retained.lookupContext}
    : {operation: 'lookupSubmission', submissionRef: retained.submissionRef,
      lookupContext: retained.lookupContext};
  try {
    const submitted = recoveryData(value, ['operation', 'submissionRef', 'lookupContext']);
    const target = submitted ?? recoveryData(value, ['operation', 'requestId', 'lookupContext']);
    const context = recoveryData(target?.lookupContext, ['endpoint', 'scopeRef']);
    if (!context) return undefined;
    if (submitted?.operation === 'lookupSubmission') {
      const ref = recoveryData(submitted.submissionRef, ['epoch', 'nonce']);
      const epoch = recoveryData(ref?.epoch, ['version', 'authorityScopeCid', 'epochNonce',
        'notBefore', 'expiresAt', 'authenticator']);
      if (!epoch || !validSubmissionRef({...ref, epoch})) return undefined;
      return {...submitted, submissionRef: {...ref, epoch}, lookupContext: context};
    }
    if (target?.operation !== 'lookupRequest') return undefined;
    return {...target, lookupContext: context};
  } catch { return undefined; }
};

export const submissionUnknown = (context, cause) => {
  const result = new ClientError('SubmissionUnknown', {...context, cause});
  const input = submissionContexts.get(context);
  if (input) submissionInputs.set(result, input);
  if (input) submissionExplanations.set(result,
    submissionLookupExplanation('acceptance_unknown', input));
  return result;
};

export const submissionNotSent = (context, cause) => {
  const result = new ClientError('SubmissionNotSent', {...context, cause});
  const input = submissionContexts.get(context);
  if (input) submissionInputs.set(result, input);
  if (input) submissionExplanations.set(result, projectSubmissionNotSent(input));
  return result;
};

// The Host accepted and durably holds the request, but no Run exists yet:
// it waits on a `prepare_attempt` Checkpoint, is resuming, or ended without
// a Run. This is a control result, not a failure and not an unknown
// submission: submitting again is never needed. Follow it with
// `lookupRequest(requestId)`; once the Run exists the lookup is `found`.
export {RequestHeld};

export function createSubmissionOperations(selected, confirmed, transport, execution, lifecycle) {
  const {exchange, responseValue, wasSubmissionDispatched, sourcePreparation} = transport;
  const {isClosed} = lifecycle;
  const withSourceProducer = (kind, originalInput, originalOptions, run, acquire) => {
    // A closed SDK connection owns its local refusal. Do not reacquire a
    // producer from the already retired Host merely to reject this call.
    // The ordinary submit path retains its original identity/NotSent handling.
    if (sourcePreparation === undefined || isClosed()) return run(undefined);
    let producer;
    try {
      // Synchronous admission precedes the first SDK capture, option getter,
      // serialization, hash or Promise workspace of this submitted original.
      const receipt = acquire === undefined
        ? sourcePreparation.beforeSourceSnapshot(kind, originalInput, originalOptions, selected.wire)
        : acquire();
      producer = {receipt, body: undefined};
    } catch (cause) {return Promise.reject(cause);}
    const finish = (terminal, primary, originalResult) => {
      // The caller-facing snapshot has its own SDK value association. This
      // private producer keeps only its original cleanup receipt from now on.
      producer.body = undefined;
      try {sourcePreparation.finishSourceProducer(producer.receipt, terminal);}
      catch (cause) {
        // Reuse this connection's existing cleanup owner. A retry cuts only
        // the same producer aliases, never snapshots, sends or issues again.
        const retry = () => sourcePreparation.finishSourceProducer(producer.receipt, terminal);
        lifecycle.readerCleanups.add(retry);
        // A thrown undefined is still the original failed operation. Keep its
        // presence separate from a successful result with no primary error.
        if (terminal === 'failed') return primary;
        const error = new ClientError('ClientCleanupPending', {cause, cleanupPending: true});
        Object.defineProperty(error, 'execution', {value: originalResult});
        retainQueryResult(originalResult, error);
        return error;
      }
      return primary;
    };
    let original;
    try {original = run(producer);}
    catch (cause) {return Promise.reject(finish('failed', cause));}
    const pending = original.then(result => {
      const failure = finish('returned', undefined, result);
      if (failure !== undefined) throw failure;
      return result;
    }, cause => {throw finish('failed', cause);});
    retainQueryResult(original, pending);
    if (producer.body !== undefined) {
      const publication = publishSnapshot(pending, producer.body);
      if (publication !== undefined) {
        try {sourcePreparation.publishSourceSnapshot(producer.receipt, producer.body, publication);}
        catch (cause) {
          retainQueryResult(pending, cause);
          const failed = pending.then(() => {throw cause;}, () => {throw cause;});
          retainQueryResult(pending, failed);
          return failed;
        }
      }
    }
    return pending;
  };
  const submitIntent = (kind, input, options, sourceProducer, requestName) => {
    let body, captured, original;
    // Trusted Source failures retain their exact original carrier, outside
    // the catch which classifies ordinary native serialization failures.
    if (sourceProducer !== undefined) sourcePreparation.assertSourceSnapshotCurrent(sourceProducer.receipt);
    try {
      const stopBefore = options.stopBefore;
      const readOnly = options.readOnly;
      if (stopBefore !== undefined && stopBefore !== 'commit') fail('InvalidClientPayload');
      if (Object.hasOwn(options, 'readOnly') && readOnly !== true) fail('InvalidClientPayload');
      original = {submissionRef: options.submissionRef,
        attemptRef: {operation: 'submit', attemptId: options.attemptId ?? crypto.randomUUID()},
        ...(requestName === undefined ? {} : {requestName}),
        kind, input, parameters: options.parameters ?? null,
        ...(stopBefore === undefined ? {} : {stopBefore}),
        ...(readOnly === undefined ? {} : {readOnly}),
        ...(options.unresolvedHistory === undefined ? {} : {unresolvedHistory: options.unresolvedHistory})};
    } catch {fail('InvalidClientPayload');}
    let snapshotCalled = false, originalSnapshot;
    const captureSnapshot = (value, observe) => {
      if (snapshotCalled || value !== original) fail('InvalidHostSourceSnapshot');
      snapshotCalled = true;
      let resourceFailed = false, resourceCause;
      try {
        originalSnapshot = snapshotClientRequest(value, observe === undefined ? undefined : (...args) => {
          try {observe(...args);}
          catch (cause) {resourceFailed = true; resourceCause = cause; throw cause;}
        });
        return originalSnapshot;
      } catch (cause) {
        // Only the actual original observer supplies a resource failure.
        // Native getters/toJSON/number errors keep the existing local refusal.
        if (resourceFailed && Object.is(cause, resourceCause)) throw cause;
        fail('InvalidClientPayload');
      }
    };
    captured = sourceProducer === undefined ? captureSnapshot(original)
      : sourcePreparation.captureSourceSnapshot(sourceProducer.receipt, original, captureSnapshot);
    if (!snapshotCalled || captured !== originalSnapshot) fail('InvalidHostSourceSnapshot');
    // Native getters/toJSON/coercion may retire the original installation or
    // producer while the one snapshot is built. Stop before freeze arrays or
    // publication; do not bind an unfrozen body to bypass the original check.
    if (sourceProducer !== undefined) sourcePreparation.assertSourceSnapshotCurrent(sourceProducer.receipt);
    try {body = freezeInput(captured);} catch {fail('InvalidClientPayload');}
    if (sourceProducer !== undefined) {
      sourcePreparation.bindSourceSnapshot(sourceProducer.receipt, body);
      sourceProducer.body = body;
    }
    if (!validSubmissionRef(body.submissionRef) || requestName === undefined && options.requestId !== undefined &&
        options.requestId !== body.submissionRef.nonce) fail('InvalidSubmissionRef');
    if (!validOperationAttemptRef(body.attemptRef)) fail('InvalidOperationAttemptRef');
    if (body.unresolvedHistory !== undefined &&
        !validSubmissionRestart(body.unresolvedHistory, body.submissionRef)) fail('InvalidSubmissionRestart');
    const requestId = requestName ?? body.submissionRef.nonce;
    const context = {requestId, submissionRef: body.submissionRef, attemptRef: body.attemptRef,
      ...(requestName === undefined ? {} : {requestName}),
      lookupContext: Object.freeze({endpoint: selected.endpoint, scopeRef: confirmed.scopeRef})};
    // The body is already SDK-deep-frozen. The connection owner freezes its
    // captured wire and arrays; lookupContext is frozen above. Share those
    // originals without walking the submitted input and Parameters again.
    const snapshot = Object.freeze({...body, requestId, connection: selected.wire,
      lookupContext: context.lookupContext});
    submissionContexts.set(context, snapshot);
    const pending = (async () => {
      let intentCid;
      try {intentCid = sourceProducer === undefined ? await bytesCid(new TextEncoder().encode(canonicalJson({
        intent: {kind, input: body.input, parameters: body.parameters,
          ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
          ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {})},
        version: 'actql-submitted-intent/0.1'}, {dataKeys: true}))) :
        await sourcePreparation.intentCid(sourceProducer.receipt, body);}
      catch (cause) {throw submissionNotSent(context, cause);}
      let outcome;
      let attempt;
      let typedRejection;
      let checkObservation;
      try {
        const operation = requestName !== undefined ? 'submit-named-intent'
          : body.unresolvedHistory === undefined ? 'submit-intent' : 'restart-intent';
        const response = await exchange(operation,
          {...body, intentCid}, options.signal, context, undefined, sourceProducer);
        attempt = captureResponse(await controlValue(response));
        if (!(requestName === undefined
          ? validSubmissionAttempt(attempt, selected.wire, body.submissionRef, intentCid,
            body.attemptRef, body.unresolvedHistory)
          : validNamedSubmissionAttempt(attempt, selected.wire, requestName,
            body.submissionRef, intentCid, body.attemptRef))) {
          fail('InvalidHostSubmissionOutcome');
        }
        attempt = freezeInput(attempt);
        outcome = attempt.outcome;
        if (outcome === undefined) {
          // A typed initial refusal or conflict is not the durable original's
          // receipt and supplies no automatic retry or new-submission grant.
          typedRejection = new ClientError(attempt.kind === 'refused' ? 'SubmissionRefused'
            : requestName === undefined ? 'SubmissionConflict' : 'RequestConflict',
            {...context, outcome: attempt});
          submissionInputs.set(typedRejection, snapshot);
          submissionAttempts.set(typedRejection, attempt);
          retainSubmissionAttemptExplanation(typedRejection, attempt, snapshot);
          throw typedRejection;
        }
        // The submitted candidate remains the exact captured input. Only this
        // correlated original reply supplies a durable reference for lookup;
        // a scoped name may legitimately resolve an earlier epoch.
        context.submissionRef = outcome.submissionRef;
        if (outcome.checkObservation !== undefined) {
          checkObservation = outcome.checkObservation;
          if (!(body.kind === 'program' || body.kind === 'aql' && ['sql', 'aql', 'aql-text'].includes(body.input.format)) ||
              !bindCheckObservation(checkObservation, {kind: body.kind, input: body.input, parameters: body.parameters})) {
            fail('InvalidHostSubmissionCheckObservation');
          }
          // The validated attempt retains its complete original observation;
          // the public outcome omits only this separately held presentation.
          const {checkObservation: _checkObservation, ...publicOutcome} = outcome;
          outcome = Object.freeze(publicOutcome);
        }
      } catch (cause) {
        if (typedRejection !== undefined && cause === typedRejection) throw cause;
        if (cause?.code === 'SubmissionUnknown' || cause?.code === 'SubmissionNotSent') throw cause;
        throw wasSubmissionDispatched(context) ? submissionUnknown(context, cause) : submissionNotSent(context, cause);
      }
      if (outcome.kind === 'ready') {
        let run;
        try {run = execution(outcome.admission);}
        catch (cause) {throw submissionUnknown(context, cause);}
        submissionInputs.set(run, snapshot);
        submissionOutcomes.set(run, outcome);
        submissionAttempts.set(run, attempt);
        retainSubmissionExplanation(run, outcome, snapshot);
        return run;
      }
      const error = outcome.kind === 'held'
        ? new RequestHeld(outcome.held, context.lookupContext)
        : new ClientError(outcome.kind === 'not_accepted' ? 'SubmissionNotAccepted'
          : outcome.kind === 'preparation_failed' ? 'SubmissionPreparationFailed'
          : outcome.kind === 'unresolvable' ? 'SubmissionUnresolvable' : 'SubmissionPreparing',
        {requestId, submissionRef: context.submissionRef, outcome});
      if (requestName !== undefined) error.requestName = requestName;
      submissionInputs.set(error, snapshot);
      submissionOutcomes.set(error, outcome);
      submissionAttempts.set(error, attempt);
      if (checkObservation !== undefined) submissionCheckObservations.set(error, freezeInput(checkObservation));
      retainSubmissionExplanation(error, outcome, snapshot);
      throw error;
    })();
    submissionInputs.set(pending, snapshot);
    return pending;
  };
  const newSubmission = ({nonce = crypto.randomUUID()} = {}) => {
    if (confirmed.submissionEpoch === undefined) fail('SubmissionEpochUnavailable');
    const ref = freezeInput(snapshotClientRequest({epoch: confirmed.submissionEpoch, nonce}));
    if (!validSubmissionRef(ref)) fail('InvalidSubmissionRef');
    return ref;
  };
  const submit = (kind, input, options = {}, sourceProducer) => {
    try {
      // Risk restart remains reference-bound. A public name is a separate
      // existing Owner domain, never a relabelled historical epoch nonce.
      if (options.submissionRef === undefined && options.unresolvedHistory !== undefined) {
        fail('SubmissionReferenceRequired');
      }
      const requestName = options.submissionRef === undefined ? options.requestId : undefined;
      if (requestName !== undefined && !validSubmissionName(requestName)) fail('InvalidRequestId');
      return submitIntent(kind, input, {...options,
        submissionRef: options.submissionRef ?? newSubmission()}, sourceProducer, requestName);
    } catch (cause) {return Promise.reject(cause);}
  };
  const submitSource = (text, options, sourceProducer) => {
    // Preserve omission at the actual before-copy boundary. This SDK-owned
    // default belongs after the selected original admission, not before it.
    if (options === undefined) options = {};
    if (typeof text !== 'string' || !text ||
        !clientSourceFormats.includes(options.format)) {
      return Promise.reject(new ClientError('InvalidAqlDocument'));
    }
    if (options.parameterDeclarations !== undefined &&
        !['aql', 'aql-text', 'sql'].includes(options.format)) {
      return Promise.reject(new ClientError('InvalidAqlDocument'));
    }
    return submit('aql', {text, format: options.format,
      ...(options.parameterDeclarations === undefined ? {} :
        {parameterDeclarations: options.parameterDeclarations})}, options, sourceProducer);
  };
  const startSource = (text, options) => withSourceProducer('aql', text, options,
    producer => submitSource(text, options, producer));
  const captureQueryAdmission = sourcePreparation === undefined ? undefined
    : (format, text, parameters, options, capture) => withSourceProducer('aql', text, options,
      producer => capture((originalText, sourceOptions) => submitSource(originalText, sourceOptions, producer)),
      () => sourcePreparation.beforeSourceQuery(format, text, parameters, options, selected.wire));
  const retainQueryResult = (execution, result) => {
    const input = submissionInputs.get(execution);
    if (input && result !== undefined) submissionInputs.set(result, input);
    const outcome = submissionOutcomes.get(execution);
    if (outcome && result !== undefined) submissionOutcomes.set(result, outcome);
    const attempt = submissionAttempts.get(execution);
    if (attempt && result !== undefined) submissionAttempts.set(result, attempt);
    return input;
  };
  const retainQueryFailure = (execution, error, cause) => {
    retainQueryResult(execution, error);
    // Only an existing SDK-owned observation supplies explanatory facts.
    // Error codes, copied causes and validated failed states supply none.
    copyRunObservationFailure(cause, error);
  };
  let client;
  client = Object.freeze({
    startSource, newSubmission,
    sql: (text, parameters, options) => sourceQuery(startSource, ClientError,
      retainQueryResult, retainQueryFailure, 'sql', text, parameters, options,
      sourcePreparation?.beforeResultRead, sourcePreparation?.assertResultReadCurrent,
      captureQueryAdmission),
    aql: (text, parameters, options) => sourceQuery(startSource, ClientError,
      retainQueryResult, retainQueryFailure, 'aql-text', text, parameters, options,
      sourcePreparation?.beforeResultRead, sourcePreparation?.assertResultReadCurrent,
      captureQueryAdmission),
    lookupSubmission: async (submissionRef, {signal} = {}) => {
      let owned;
      try {owned = freezeInput(snapshotClientRequest(submissionRef));}
      catch {fail('InvalidSubmissionRef');}
      if (!validSubmissionRef(owned)) fail('InvalidSubmissionRef');
      const context = freezeInput({submissionRef: owned,
        lookupContext: {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef}});
      let response;
      try {response = await exchange('lookup-submission', {submissionRef: owned}, signal);}
      catch (cause) {throw retainSubmissionLookupFailure(cause, context, 'lookup_unavailable');}
      let answer;
      try {
        answer = captureResponse(await controlValue(response));
        if (!validSubmissionLookup(answer, selected.wire, owned)) fail('InvalidHostSubmissionLookup');
      } catch {
        throw retainSubmissionLookupFailure(new ClientError('InvalidHostSubmissionLookup'),
          context, 'lookup_uninterpretable');
      }
      return retainSubmissionExplanation(freezeInput(answer), answer, context);
    },
    start: (program, options) => withSourceProducer('program', program, options, sourceProducer => {
      if (options === undefined) options = {};
      if (program === null || typeof program !== 'object' ||
          Array.isArray(program)) {
        return Promise.reject(new ClientError('InvalidProgramDocument'));
      }
      return submit('program', program, options, sourceProducer);
    }),
    attach: async (ref, {signal} = {}) => {
      const requested = Object.freeze({...ref});
      if (!validRunRef(requested)) fail('InvalidRunReference');
      const response = await exchange('attach', {ref: requested}, signal);
      let admitted;
      try { admitted = await responseValue(response); }
      catch (cause) { throw new ClientError('InvalidHostAdmission', {cause}); }
      try { admitted = captureResponse(admitted); }
      catch { fail('InvalidHostAdmission'); }
      if (!validClientAdmission(admitted, selected.wire)) fail('InvalidHostAdmission');
      if (admitted.ref.namespaceId !== requested.namespaceId ||
          admitted.ref.authorityScopeCid !== requested.authorityScopeCid ||
          admitted.ref.runDefinitionCid !== requested.runDefinitionCid) {
        fail('ForeignHostAdmission');
      }
      return execution(freezeInput(admitted));
    },
    lookupRequest: async (requestId, {signal} = {}) => {
      if (typeof requestId !== 'string' || !requestId) fail('InvalidRequestId');
      const context = freezeInput({requestId,
        lookupContext: {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef}});
      let response;
      try { response = await exchange('lookup-request', {requestId}, signal); }
      catch (cause) { throw retainRequestLookupFailure(cause, context, 'lookup_unavailable'); }
      let answer;
      try { answer = await responseValue(response); }
      catch (cause) {
        throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable');
      }
      try { answer = captureResponse(answer); }
      catch { throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable'); }
      if (!validRequestLookup(answer, requestId)) {
        throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable');
      }
      return retainRequestLookupExplanation(freezeInput(answer), context);
    },
    // One explicit lookup target across pre-Run and Run observations. Creating
    // or restoring this handle performs no I/O and grants no retry authority.
    recoverRequest: observationOrTarget => {
      if (isClosed()) fail('ClientClosed');
      const captured = requestRecoveryTarget(observationOrTarget);
      if (isClosed()) fail('ClientClosed');
      if (!captured || (captured.operation === 'lookupRequest' &&
          (typeof captured.requestId !== 'string' || captured.requestId.length < 1 ||
          captured.requestId.length > 256 || /[\u0000-\u001f\u007f]/u.test(captured.requestId))) ||
          typeof captured.lookupContext.endpoint !== 'string' ||
          typeof captured.lookupContext.scopeRef !== 'string') {
        fail('InvalidRequestRecoveryTarget');
      }
      if (captured.lookupContext.endpoint !== selected.endpoint ||
          captured.lookupContext.scopeRef !== confirmed.scopeRef) {
        fail('RequestRecoveryScopeMismatch');
      }
      const target = freezeInput(captured);
      const found = new WeakSet();
      return Object.freeze({target,
        lookup: async options => {
          const observation = target.operation === 'lookupSubmission'
            ? await client.lookupSubmission(target.submissionRef, options)
            : await client.lookupRequest(target.requestId, options);
          if (observation.kind === 'found' || observation.kind === 'ready') found.add(observation);
          return observation;
        },
        attach: async (observation, options) => {
          if (isClosed()) fail('ClientClosed');
          if (!found.has(observation)) fail('InvalidRequestRecoveryObservation');
          // Custody of a lookup is not authority: attach rechecks the Host now.
          return client.attach(observation.kind === 'ready' ? observation.admission.ref : observation.ref, options);
        },
      });
    },
    // Cancel a request by its ID, before or after its Run exists; a Run is
    // cancelled through its own cancellation. `accepted` means the Host
    // durably recorded it, not that anything stopped or was cleaned up
    // (follow lookupRequest, or status() once there is a Run). When the
    // reply is lost or the Host fails, the error is CancellationUnknown with
    // the requestId: call cancelRequest again with the same ID; it is
    // matched to the existing cancellation. Aborting the call never
    // withdraws a cancellation the Host already recorded.
    cancelRequest: async (requestId, {signal} = {}) => {
      if (typeof requestId !== 'string' || !requestId) fail('InvalidRequestId');
      const context = freezeInput({requestId,
        lookupContext: {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef}});
      let response, answer;
      try {
        response = await exchange('cancel-request', {requestId}, signal);
      } catch (cause) {
        // Preserve the existing Client error contract in a per-call wrapper.
        // Code/status select no Owner outcome or explanation permission.
        const error = cause instanceof ClientError &&
            cause.code !== 'ClientTransportUnknown' && !(cause.status >= 500)
          ? new ClientError(cause.code, {
            ...(cause.status === undefined ? {} : {status: cause.status}),
            ...(cause.cause === undefined ? {} : {cause: requestCancellationCause(cause.cause)}),
          }) : new ClientError('CancellationUnknown', {requestId, cause: requestCancellationCause(cause)});
        throw retainRequestCancellationExplanation(error, context,
          'outcome_unknown', 'exchange_failed');
      }
      try { answer = await responseValue(response); }
      catch { throw uninterpretableRequestCancellation(context); }
      try { answer = captureResponse(answer); }
      catch { throw uninterpretableRequestCancellation(context); }
      if (!validRequestCancellation(answer, requestId)) {
        throw uninterpretableRequestCancellation(context);
      }
      return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);
    },
      });
  return client;
}
