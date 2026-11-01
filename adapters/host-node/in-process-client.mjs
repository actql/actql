// Installed Local Client Host ingress. It shares public validation and Host
// services with HTTP ingress while keeping control and Result rows in process.
import {ClientError} from '../../packages/sdk/index.mjs';
import {performClientSubmit} from './client-submit.mjs';
import {projectClientCheckUnavailable} from './client-check.mjs';
import {observeClientAuthorizationFailure} from
  './client-authentication-observation.mjs';
import {clientWorkspaceMatches, validCheckpointPage, validCheckpointReview, validClientAdmission,
  prepareClientHostRequest, validClientProfile, validDeliveryAttemptLookup, validCancellationAttempt, validCancellationLookup,
  validRequestCancellation, validRequestLookup, validResolveResults,
  validResourceInspection, validResourceListing, validResourcePeek,
  validRunState, validResultDescription, validCheckOutcome, validOwnerObservations,
  validSubmissionAttempt, validNamedSubmissionAttempt, validSubmissionLookup} from
  '../../packages/client-wire/index.mjs';
import {validWireEffectfulStaticPlanViewShape, validWirePlanViewShape, validWireRunViewShape, validWireRunPlanViewShape} from '../../packages/client-wire/index.mjs';
import {observeClientRunState} from './client-run-state.mjs';
import {inspectAuthorizedDeliveryAttempt, describeAuthorizedResult} from './result-access.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';
import {publicClientErrorCode, publicClientErrorStatus} from './client-http.mjs';

const localErrors = new WeakSet();
// Only packets captured here before deferred service construction carry this
// original operation's immutable shape facts into the activated ingress.
// Authentication and authorization are never retained in this association.
const deferredRequests = new WeakMap();
const publicError = (code, status) => {
  const error = new ClientError(code, {status});
  delete error.stack;
  return error;
};
const fail = code => {
  const error = publicError(code, publicClientErrorStatus({code}));
  localErrors.add(error);
  throw error;
};
const publicFailure = error => localErrors.has(error) ? error
  : publicError(publicClientErrorCode(error), publicClientErrorStatus(error));

function publicResultRows(response, observeConsumed, observeOperation) {
  // Keep a failed delivery record's exact retry owner off public errors. The
  // SDK may release this response only after that owner confirms settlement.
  let cleanupFailure;
  let original = observeOperation, resume, retire;
  try {resume = original?.run; retire = original?.release;}
  catch { /* An optional observation cannot replace the Result response. */ }
  const inContext = work => {
    if (typeof resume !== 'function') return work();
    let called = false, value, failure, threw = false;
    const once = () => {
      if (called) {if (threw) throw failure; return value;}
      called = true;
      try {value = work(); return value;}
      catch (error) {threw = true; failure = error; throw error;}
    };
    try {Reflect.apply(resume, original, [once]);}
    catch { /* Preserve the original work's own value or error below. */ }
    return once();
  };
  const releaseObservation = () => {
    const held = original, release = retire;
    original = resume = retire = undefined;
    try {if (typeof release === 'function') Reflect.apply(release, held, []);}
    catch { /* Observation release is not the delivery owner's cleanup ACK. */ }
  };
  const contextualFrames = frames => ({[Symbol.asyncIterator]() {
    const iterator = inContext(() => frames[Symbol.asyncIterator]());
    const next = inContext(() => iterator.next);
    const method = name => {
      const operation = inContext(() => iterator[name]);
      return typeof operation === 'function'
        ? (...args) => inContext(() => Reflect.apply(operation, iterator, args)) : operation;
    };
    return {next(...args) {return inContext(() => Reflect.apply(next, iterator, args));},
      get return() {return method('return');}, get throw() {return method('throw');},
      [Symbol.asyncIterator]() {return this;}};
  }});
  return Object.freeze({kind: 'rows', frames: Object.freeze({
    async *[Symbol.asyncIterator]() {
      let consumed = false;
      try { yield* (original === undefined ? response.frames : contextualFrames(response.frames)); consumed = true; }
      catch (error) {
        if (error?.cleanupPending === true) cleanupFailure = error;
        throw publicFailure(error);
      }
      finally {
        if (consumed) try {observeConsumed?.();}
        catch { /* Optional observation cannot replace rows or their real cleanup. */ }
        if (cleanupFailure === undefined) releaseObservation();
      }
    },
  }), async close() {
    if (cleanupFailure === undefined) {releaseObservation(); return;}
    const handle = cleanupFailure.cleanupHandle;
    try {
      if (typeof handle?.retry !== 'function' ||
          typeof handle?.status !== 'function') throw cleanupFailure;
      if (inContext(() => handle.status()).pending !== false) await inContext(() => handle.retry());
      if (inContext(() => handle.status()).pending !== false) throw cleanupFailure;
      cleanupFailure = undefined;
      releaseObservation();
    } catch { throw publicError('ResultReadCleanupUnknown', 500); }
  }});
}

export function createNodeInProcessClientHost({
  authenticate, authorizeConnection, workspaceForPrincipal, negotiate, prepareSubmit, submit, submitIntent, submitNamedIntent, lookupSubmission,
  bindOwnedRequest,
  attach, lookupRequest, stateService, runStateObservation, resultService, observeRun, observeOwners, wait,
  cancel, lookupCancellation, cancelRequest, reconcile, checkpoints, checkpointReview, resolve,
  resources, inspectResource, peekResource, check, plan, inspectRun, runPlan, maxRowBytes, observe,
  performInstalledRequest,
  captureResultObservation,
  captureResultOperation,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      typeof negotiate !== 'function' ||
      performInstalledRequest !== undefined && typeof performInstalledRequest !== 'function' ||
      bindOwnedRequest !== undefined && typeof bindOwnedRequest !== 'function' ||
      captureResultObservation !== undefined && typeof captureResultObservation !== 'function' ||
      captureResultOperation !== undefined && typeof captureResultOperation !== 'function' ||
      !Number.isSafeInteger(maxRowBytes) || maxRowBytes < 1) {
    throw new TypeError('InvalidInProcessClientHostInstallation');
  }
  return Object.freeze({async perform(operation, body, signal) {
    try {
      if (operation === 'lookup-submission') signal?.throwIfAborted();
      // Static preparation probes the same funded-original lookup, even
      // though a plan read has no submission producer or execution grant.
      const tracksSource = bindOwnedRequest !== undefined &&
        ['plan', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation);
      const own = (parent, derived) => {
        if (tracksSource && bindOwnedRequest(parent, derived) !== undefined) {
          fail('SourceManagedPreparationUnavailable');
        }
        return derived;
      };
      // Local rows use the existing JSONL request shape for wire admission.
      const captured = deferredRequests.get(body);
      const retainSnapshot = performInstalledRequest !== undefined && operation !== 'connect';
      const prepared = captured?.operation === operation ? captured.prepared
        : prepareClientHostRequest(operation,
          operation === 'read' ? {...body, format: 'jsonl'} : body, retainSnapshot);
      if (prepared === undefined) fail('InvalidClientRequest');
      if (retainSnapshot) {
        deferredRequests.set(prepared.body, Object.freeze({operation, prepared}));
      }
      // A deferred constructor retains the wire Owner's one immutable capture.
      // The activated ingress consumes those same shape facts, but still
      // performs its own current authentication and connection authorization.
      body = own(body, prepared.body);
      const {connection} = prepared;
      let principalId;
      try { principalId = await authenticate(); }
      catch (cause) {
        await observeClientAuthorizationFailure(observe, operation,
          'authenticate', cause);
        fail('ClientAuthenticationDenied');
      }
      if (typeof principalId !== 'string' || !principalId) {
        fail('ClientAuthenticationDenied');
      }
      const ref = body.ref;
      if (connection.workspaceId !== undefined) {
        let workspaceId;
        try {
          workspaceId = typeof workspaceForPrincipal === 'function'
            ? await workspaceForPrincipal(principalId) : undefined;
        } catch { fail('ClientConnectionDenied'); }
        if (!clientWorkspaceMatches(connection, workspaceId)) {
          fail('ClientConnectionDenied');
        }
      }
      let authorized;
      try {
        authorized = await authorizeConnection(Object.freeze({
          principalId, connection, ref, operation,
        }));
      } catch (cause) {
        await observeClientAuthorizationFailure(observe, operation,
          'authorize_connection', cause);
        authorized = false;
      }
      if (authorized !== true) {
        if (operation === 'check') return await projectClientCheckUnavailable(check);
        fail('ClientConnectionDenied');
      }
      if (performInstalledRequest !== undefined && operation !== 'connect') {
        // Validation and current connection authorization precede optional
        // service construction. Keep this admitted immutable snapshot and its
        // original Source lineage across the wait; never reread a mutable
        // caller packet or replace the prepared Program/permission.
        return await performInstalledRequest(operation,body,signal);
      }
      const invoke = async (handler, preparedProgram) => {
        if (typeof handler !== 'function') fail('ClientOperationUnavailable');
        return handler(own(body, Object.freeze({principalId, connection,
          ...Object.fromEntries(Object.entries(body).filter(([key]) =>
            key !== 'connection')),
          ...(signal === undefined || ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent', 'lookup-submission'].includes(operation)
            ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        })));
      };
      if (operation === 'connect') {
        const profile = await invoke(negotiate);
        if (!validClientProfile(profile, connection)) {
          fail('InvalidClientHostProfile');
        }
        return profile;
      }
      if (operation === 'submit') {
        return await performClientSubmit({connection, requestId: body.requestId,
          prepare: prepareSubmit === undefined ? undefined :
            () => invoke(prepareSubmit),
          submit: prepared => invoke(submit, prepared)});
      }
      if (operation === 'submit-named-intent') {
        const answer = await invoke(submitNamedIntent);
        if (!validNamedSubmissionAttempt(answer, connection, body.requestName,
          body.submissionRef, body.intentCid, body.attemptRef)) fail('InvalidClientHostSubmissionOutcome');
        return answer;
      }
      if (['submit-intent', 'restart-intent', 'lookup-submission'].includes(operation)) {
        const submitting = operation !== 'lookup-submission';
        // Lookup control is transport-only, not part of the journal's canonical
        // request snapshot. Keep its handler alive until settlement; an abort
        // ends this observation, never the original submitted Run.
        if (!submitting) signal?.throwIfAborted();
        const answer = await invoke(submitting ? submitIntent : lookupSubmission);
        if (!submitting) signal?.throwIfAborted();
        const valid = submitting
          ? validSubmissionAttempt(answer, connection, body.submissionRef, body.intentCid, body.attemptRef, body.unresolvedHistory)
          : validSubmissionLookup(answer, connection, body.submissionRef);
        if (!valid) fail('InvalidClientHostSubmissionOutcome');
        return answer;
      }
      if (operation === 'attach') {
        const admitted = await invoke(attach);
        if (!validClientAdmission(admitted, connection) ||
            admitted.ref.namespaceId !== ref.namespaceId ||
            admitted.ref.authorityScopeCid !== ref.authorityScopeCid ||
            admitted.ref.runDefinitionCid !== ref.runDefinitionCid) {
          fail('InvalidClientHostAdmission');
        }
        return admitted;
      }
      if (operation === 'lookup-request') {
        const found = await invoke(lookupRequest);
        if (!validRequestLookup(found, body.requestId)) {
          fail('InvalidClientHostLookupResponse');
        }
        return found;
      }
      if (operation === 'status' || operation === 'wait') {
        const state = operation === 'status' && observeRun === undefined
          ? await observeClientRunState(runStateObservation, stateService, {
            indexKey: ref, principalId, purpose: 'inspect',
          }) : await invoke(operation === 'status' ? observeRun : wait);
        if (!validRunState(state)) fail('InvalidClientHostRunState');
        return state;
      }
      if (operation === 'plan') {
        const view = await invoke(plan);
        if (!validWirePlanViewShape(view) && !validWireEffectfulStaticPlanViewShape(view)) fail('InvalidClientHostPlanView');
        return view;
      }
      if (operation === 'run-plan') {
        const view = await invoke(runPlan);
        if (!validWireRunPlanViewShape(view) ||
            Object.keys(ref).some(key => view.run_ref[key] !== ref[key])) fail('InvalidClientHostRunPlanView');
        return view;
      }
      if (operation === 'inspect-run') {
        const view = await invoke(inspectRun);
        if (!validWireRunViewShape(view)) fail('InvalidClientHostRunView');
        return view;
      }
      if (operation === 'owner-observations') {
        const views = await invoke(observeOwners);
        if (!validOwnerObservations(views,ref,body)) fail('InvalidClientHostOwnerObservations');
        return views;
      }
      if (operation === 'checkpoints') {
        const page = await invoke(checkpoints);
        if (!validCheckpointPage(page, body.limit)) {
          fail('InvalidClientHostCheckpointPage');
        }
        return page;
      }
      if (operation === 'checkpoint-review') {
        const review = await invoke(checkpointReview);
        if (!validCheckpointReview(review, {
          checkpointCid: body.checkpointCid, maxBytes: body.maxBytes,
        })) fail('InvalidClientHostCheckpointReview');
        return review;
      }
      if (operation === 'resolve') {
        const answered = await invoke(resolve);
        if (!validResolveResults(answered, body.items)) {
          fail('InvalidClientHostResolveReply');
        }
        return answered;
      }
      if (operation === 'cancel-request') {
        const cancelled = await invoke(cancelRequest);
        if (!validRequestCancellation(cancelled, body.requestId)) {
          fail('InvalidClientHostRequestCancellation');
        }
        return cancelled;
      }
      // The same Host check owner and outcome validation as HTTP ingress.
      if (operation === 'check') {
        const outcome = await invoke(check);
        if (!validCheckOutcome(outcome)) fail('InvalidClientHostCheckOutcome');
        return outcome;
      }
      // Discovery shares the HTTP ingress's handlers and reply validation.
      if (operation === 'resources' || operation === 'resource-inspect' ||
          operation === 'resource-peek') {
        const answer = await invoke(operation === 'resources' ? resources
          : operation === 'resource-inspect' ? inspectResource
            : peekResource);
        const {connection: _connection, ...expected} = body;
        if (!(operation === 'resources'
          ? validResourceListing(answer, {
            resourceConnection: body.resourceConnection, limit: body.limit})
          : operation === 'resource-inspect'
            ? validResourceInspection(answer, expected)
            : validResourcePeek(answer, expected))) {
          fail('InvalidClientHostResourceReply');
        }
        return answer;
      }
      if (operation === 'cancel') {
        const answer = await invoke(cancel);
        if (!validCancellationAttempt(answer, {...ref, cancelId: body.cancelId,
          expectedRevision: body.expectedRevision}, body.attemptRef)) fail('InvalidClientHostCancellation');
        return answer;
      }
      if (operation === 'lookup-cancellation') {
        const answer = await invoke(lookupCancellation);
        if (!validCancellationLookup(answer, {...ref, cancelId: body.cancelId,
          expectedRevision: body.expectedRevision})) fail('InvalidClientHostCancellationLookup');
        return answer;
      }
      if (operation === 'result-describe') {
        const answer = await describeAuthorizedResult(resultService, {
          indexKey: ref, principalId, purpose: 'inspect',
          resultName: body.resultName, format: body.format,
          attemptId: body.attemptId, maxWireBytes: body.maxWireBytes,
          maxNodes: body.maxNodes, maxDepth: body.maxDepth,
        }, signal);
        if (!validResultDescription(answer, body, body)) {
          fail('InvalidClientHostResultDescription');
        }
        return answer;
      }
      if (operation === 'reconcile') {
        const state = await invoke(reconcile);
        if (!validRunState(state)) fail('InvalidClientHostRunState');
        return state;
      }
      if (operation === 'delivery-attempt') {
        const found = await inspectAuthorizedDeliveryAttempt(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        });
        if (!validDeliveryAttemptLookup(found, {
          attemptId: body.attemptId,
          runDefinitionCid: ref.runDefinitionCid,
          resultName: body.resultName,
        })) fail('InvalidClientHostAttemptLookup');
        return found;
      }
      if (operation === 'read') {
        let consumed, observation;
        try {consumed = captureResultObservation?.(ref);}
        catch { /* An unavailable observation is not a Result permission or failure. */ }
        try {observation = captureResultOperation?.();}
        catch { /* Keep the same Result request even if observation is unavailable. */ }
        return publicResultRows(authorizedLocalResultFrames(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        }, signal, {maxRowBytes}), consumed, observation);
      }
      fail('UnknownClientOperation');
    } catch (error) {
      // Input and reply diagnostics created by this ingress are already
      // public Client errors. A handler-supplied ClientError is not proof
      // that its code is public; classify it like any other Host failure.
      throw publicFailure(error);
    }
  }});
}
