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
import {inspectAuthorizedRunState} from
  '../host-common/run-state-access.mjs';
import {inspectAuthorizedDeliveryAttempt, describeAuthorizedResult} from './result-access.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';
import {publicClientErrorCode, publicClientErrorStatus} from './client-http.mjs';

const localErrors = new WeakSet();
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

function publicResultRows(response) {
  // Keep a failed delivery record's exact retry owner off public errors. The
  // SDK may release this response only after that owner confirms settlement.
  let cleanupFailure;
  return Object.freeze({kind: 'rows', frames: Object.freeze({
    async *[Symbol.asyncIterator]() {
      try { yield* response.frames; }
      catch (error) {
        if (error?.cleanupPending === true) cleanupFailure = error;
        throw publicFailure(error);
      }
    },
  }), async close() {
    if (cleanupFailure === undefined) return;
    const handle = cleanupFailure.cleanupHandle;
    try {
      if (typeof handle?.retry !== 'function' ||
          typeof handle?.status !== 'function') throw cleanupFailure;
      if (handle.status().pending !== false) await handle.retry();
      if (handle.status().pending !== false) throw cleanupFailure;
      cleanupFailure = undefined;
    } catch { throw publicError('ResultReadCleanupUnknown', 500); }
  }});
}

export function createNodeInProcessClientHost({
  authenticate, authorizeConnection, workspaceForPrincipal, negotiate, prepareSubmit, submit, submitIntent, submitNamedIntent, lookupSubmission,
  bindOwnedRequest,
  attach, lookupRequest, stateService, resultService, observeRun, observeOwners, wait,
  cancel, lookupCancellation, cancelRequest, reconcile, checkpoints, checkpointReview, resolve,
  resources, inspectResource, peekResource, check, plan, inspectRun, runPlan, maxRowBytes, observe,
  performInstalledRequest,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      typeof negotiate !== 'function' ||
      performInstalledRequest !== undefined && typeof performInstalledRequest !== 'function' ||
      bindOwnedRequest !== undefined && typeof bindOwnedRequest !== 'function' ||
      !Number.isSafeInteger(maxRowBytes) || maxRowBytes < 1) {
    throw new TypeError('InvalidInProcessClientHostInstallation');
  }
  return Object.freeze({async perform(operation, body, signal) {
    try {
      // Only a selected same-Host deferred installation retains this extra
      // original packet across its constructor wait. Ordinary ingress keeps
      // its existing body/await path and acquires no continuation callback.
      const installedBody = performInstalledRequest === undefined ? undefined : body;
      const tracksSource = bindOwnedRequest !== undefined &&
        ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation);
      const own = (parent, derived) => {
        if (tracksSource && bindOwnedRequest(parent, derived) !== undefined) {
          fail('SourceManagedPreparationUnavailable');
        }
        return derived;
      };
      // Local rows use the existing JSONL request shape for wire admission.
      const prepared = prepareClientHostRequest(operation,
        operation === 'read' ? {...body, format: 'jsonl'} : body);
      if (prepared === undefined) fail('InvalidClientRequest');
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
        // service construction. Continue with the SAME original packet, not
        // a replacement prepared Program, reference or permission.
        return await performInstalledRequest(operation,installedBody,signal);
      }
      const invoke = async (handler, preparedProgram) => {
        if (typeof handler !== 'function') fail('ClientOperationUnavailable');
        return handler(own(body, Object.freeze({principalId, connection,
          ...Object.fromEntries(Object.entries(body).filter(([key]) =>
            key !== 'connection')),
          ...(signal === undefined || ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation)
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
        const answer = await invoke(submitting ? submitIntent : lookupSubmission);
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
          ? await inspectAuthorizedRunState(stateService, {
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
        return publicResultRows(authorizedLocalResultFrames(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        }, signal, {maxRowBytes}));
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
