// Installed Local Client Host ingress. It shares public validation and Host
// services with HTTP ingress while keeping control and Result rows in process.
import {ClientError} from '../../packages/sdk/index.mjs';
import {performClientSubmit} from './client-submit.mjs';
import {observeClientAuthorizationFailure} from
  './client-authentication-observation.mjs';
import {validCheckpointPage, validCheckpointReview, validClientAdmission,
  validClientBody, validClientProfile, validDeliveryAttemptLookup,
  validRequestCancellation, validRequestLookup, validResolveResults,
  validResourceInspection, validResourceListing, validResourcePeek,
  validRunState} from
  '../../packages/client-wire/index.mjs';
import {inspectAuthorizedRunState} from
  '../host-common/run-state-access.mjs';
import {inspectAuthorizedDeliveryAttempt} from './result-access.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';
import {publicClientErrorCode} from './client-http.mjs';

const localErrors = new WeakSet();
const fail = code => {
  const error = new ClientError(code);
  localErrors.add(error);
  throw error;
};

export function createNodeInProcessClientHost({
  authenticate, authorizeConnection, negotiate, prepareSubmit, submit,
  attach, lookupRequest, stateService, resultService, observeRun, wait,
  cancel, cancelRequest, reconcile, checkpoints, checkpointReview, resolve,
  resources, inspectResource, peekResource, maxRowBytes, observe,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      typeof negotiate !== 'function' ||
      !Number.isSafeInteger(maxRowBytes) || maxRowBytes < 1) {
    throw new TypeError('InvalidInProcessClientHostInstallation');
  }
  return Object.freeze({async perform(operation, body, signal) {
    try {
      const validationBody = operation === 'read'
        ? {...body, format: 'jsonl'} : body;
      if (!validClientBody(operation, validationBody)) {
        fail('InvalidClientRequest');
      }
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
      const connection = body.connection;
      const ref = body.ref;
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
      if (authorized !== true) fail('ClientConnectionDenied');
      const invoke = async (handler, preparedProgram) => {
        if (typeof handler !== 'function') fail('ClientOperationUnavailable');
        return handler(Object.freeze({principalId, connection,
          ...Object.fromEntries(Object.entries(body).filter(([key]) =>
            key !== 'connection')),
          ...(signal === undefined || operation === 'submit'
            ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        }));
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
      if (operation === 'cancel') return await invoke(cancel);
      if (operation === 'reconcile') return await invoke(reconcile);
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
        return authorizedLocalResultFrames(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        }, signal, {maxRowBytes});
      }
      fail('UnknownClientOperation');
    } catch (error) {
      // Input and reply diagnostics created by this ingress are already
      // public Client errors. A handler-supplied ClientError is not proof
      // that its code is public; classify it like any other Host failure.
      if (localErrors.has(error)) throw error;
      throw new ClientError(publicClientErrorCode(error), {cause: error});
    }
  }});
}
