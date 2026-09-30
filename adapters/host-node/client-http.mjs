// Client-Host HTTP ingress. Authentication and connection consent are installed
// by the Host; Run meaning and read admission stay with the existing services.
import {inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {performClientSubmit} from './client-submit.mjs';
import {observeClientAuthorizationFailure} from
  './client-authentication-observation.mjs';
import {deliverAuthorizedResult,
  describeAuthorizedResult, inspectAuthorizedDeliveryAttempt} from './result-access.mjs';
import {clientHostOperations, validCheckpointPage, validCheckpointReview,
  validClientAdmission, validClientBody, validClientProfile,
  validDeliveryAttemptLookup, validRequestLookup, validResolveResults,
  validRequestCancellation, validResourceInspection, validResourceListing,
  validResourcePeek, validRunState, validResultDescription} from
  '../../packages/client-wire/index.mjs';

const operations = new Set(clientHostOperations);

function invalid(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

async function boundedJson(request, maxBytes) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.byteLength;
    if (size > maxBytes) invalid('ClientRequestTooLarge');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(new TextDecoder('utf-8', {fatal: true})
      .decode(Buffer.concat(chunks)));
  }
  catch { invalid('InvalidClientRequest'); }
}

function responseCode(error) {
  if (error?.code === 'RunStateAccessDenied' ||
      error?.code === 'ResultAccessDenied' ||
      error?.code === 'ResultDeliveryDenied' ||
      error?.code === 'ClientAuthenticationDenied' ||
      error?.code === 'ClientConnectionDenied' ||
      error?.code === 'ClientRequestLookupDenied' ||
      error?.code === 'ClientRunStartDenied' ||
      error?.code === 'ClientRunCancellationDenied' ||
      error?.code === 'ClientRunAttachDenied' ||
      error?.code === 'CheckpointListDenied' ||
      error?.code === 'CheckpointReviewDenied' ||
      error?.code === 'CheckpointAnswerDenied' ||
      error?.code === 'ClientRequestCancellationDenied' ||
      error?.code === 'ResourceDiscoveryDenied' ||
      error?.code === 'ResourcePeekDenied' ||
      /^ACTQL_E_(ACCOUNT_[A-Z_]+|DELEGATION_[A-Z_]+)$/u
        .test(error?.code ?? '')) return 403;
  if (error?.code === 'CheckpointReviewUnavailable') return 410;
  if (error?.code === 'WaitAborted') return 408;
  if (error?.code === 'ClientRequestNotFound' ||
      error?.code === 'ResourceConnectionNotFound') return 404;
  if (error?.code === 'ResourceCatalogUnavailable') return 503;
  if (error?.code === 'HeldRequestEvidenceUnavailable') return 503;
  if (error?.code === 'CheckpointReviewTooLarge') return 413;
  if (error?.code === 'ClientRequestIntentConflict') return 409;
  if (error?.code === 'ResultUnavailable') return 410;
  if (error?.code === 'ResultDescriptionUnavailable') return 410;
  if (error?.code === 'ResultDescriptionTooLarge') return 413;
  if (error?.code === 'ClientRequestTooLarge' ||
      error?.code === 'ClientParametersTooLarge') return 413;
  if (error?.code === 'InvalidClientRequest' ||
      error?.code === 'ClientProgramInvalidInput' ||
      error?.code === 'ClientParametersInvalid' ||
      error?.code === 'InvalidRunStateRequest' ||
      error?.code === 'InvalidWaitCondition' ||
      error?.code === 'InvalidResultAccessRequest' ||
      error?.code === 'InvalidCheckpointPage') return 400;
  if (error?.code === 'ClientProgramNeedsInputs' ||
      error?.code === 'ClientProgramRejected' ||
      error?.code === 'ClientProgramUnsupported') return 422;
  if (error?.code === 'UnknownClientOperation') return 404;
  if (error?.code === 'ClientOperationUnavailable') return 501;
  if (error?.code === 'ResultAttemptLookupUnavailable') return 501;
  return 500;
}

// The public code HTTP ingress answers for `error`; in-process ingress uses
// the same classification for operations both serve.
export function publicClientErrorCode(error) {
  return responseCode(error) === 500 ? 'ClientHostFailure' : error.code;
}

function sendError(response, error) {
  if (response.headersSent) {
    response.destroy(error);
    return;
  }
  const status = responseCode(error);
  response.writeHead(status, {'content-type': 'application/json'});
  response.end(JSON.stringify({
    code: status === 500 ? 'ClientHostFailure' : error.code,
  }));
}

function write(response, bytes) {
  return new Promise((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    response.write(bytes, error => error ? reject(error) :
      resolve({confirmedBytes: bytes.byteLength}));
  });
}

function finish(response, format) {
  return new Promise((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    // A raw record separator cannot occur unescaped in JSON. It marks normal
    // transport completion without altering the MoonBit-owned payload digest.
    response.end(format === 'jsonl' ? Buffer.from([0x1e]) : undefined,
      error => error ? reject(error) :
      resolve({confirmed: true}));
  });
}

function observationAttempt(response) {
  const controller = new AbortController();
  const disconnected = () => {
    if (!response.writableEnded) controller.abort();
  };
  response.on('close', disconnected);
  if (response.destroyed) disconnected();
  return Object.freeze({signal: controller.signal,
    release: () => response.off('close', disconnected)});
}

export function createClientHttpHandler({
  authenticate, authorizeConnection, stateService, resultService,
  negotiate, submit, attach, lookupRequest, observeRun, wait, cancel,
  reconcile, deliveryAttempt, prepareSubmit, checkpoints, checkpointReview,
  resolve, cancelRequest, resources, inspectResource, peekResource,
  maxRequestBytes = 65536, observe,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    throw new TypeError('InvalidClientHostInstallation');
  }
  return async (request, response) => {
    try {
      if (request.method !== 'POST' ||
          !request.url?.startsWith('/actql/client/0.1/')) {
        invalid('UnknownClientOperation');
      }
      const operation = request.url.slice('/actql/client/0.1/'.length);
      if (!operations.has(operation)) invalid('UnknownClientOperation');
      if (request.headers['content-type'] !== 'application/json') {
        invalid('InvalidClientRequest');
      }
      let principal;
      try { principal = await authenticate(request.headers.authorization); }
      catch (cause) {
        await observeClientAuthorizationFailure(observe, operation,
          'authenticate', cause);
        invalid('ClientAuthenticationDenied');
      }
      if (typeof principal !== 'string' || principal.length === 0) {
        invalid('ClientAuthenticationDenied');
      }
      const body = await boundedJson(request, maxRequestBytes);
      if (!validClientBody(operation, body)) invalid('InvalidClientRequest');
      const connection = Object.freeze({...body.connection,
        consentRefs: Object.freeze([...body.connection.consentRefs]),
        runners: Object.freeze([...body.connection.runners])});
      const ref = body.ref === undefined ? undefined :
        Object.freeze({...body.ref});
      let authorized;
      try {
        authorized = await authorizeConnection(Object.freeze({
          principalId: principal,
          connection, ref,
          operation,
        }));
      } catch (cause) {
        await observeClientAuthorizationFailure(observe, operation,
          'authorize_connection', cause);
        authorized = false;
      }
      if (authorized !== true) invalid('ClientConnectionDenied');
      const invoke = async (handler, signal, preparedProgram) => {
        if (typeof handler !== 'function') invalid('ClientOperationUnavailable');
        return handler(Object.freeze({
          principalId: principal,
          connection,
          ...Object.fromEntries(Object.entries(body)
            .filter(([key]) => key !== 'connection' && key !== 'ref')),
          ...(ref === undefined ? {} : {ref}),
          ...(signal === undefined ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        }));
      };
      const sendJson = value => {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(value));
      };
      if (operation === 'connect') {
        const profile = await invoke(negotiate);
        if (!validClientProfile(profile, connection)) {
          invalid('InvalidClientHostProfile');
        }
        sendJson(profile);
      } else if (operation === 'submit') {
        const admission = await performClientSubmit({connection,
          requestId: body.requestId,
          prepare: prepareSubmit === undefined ? undefined :
            () => invoke(prepareSubmit),
          submit: prepared => invoke(submit, undefined, prepared)});
        sendJson(admission);
      } else if (operation === 'result-describe') {
        const observation = observationAttempt(response);
        try {
          const answer = await describeAuthorizedResult(resultService, {
            indexKey: ref, principalId: principal, purpose: 'inspect',
            resultName: body.resultName, format: body.format,
            attemptId: body.attemptId, maxWireBytes: body.maxWireBytes,
            maxNodes: body.maxNodes, maxDepth: body.maxDepth,
          }, observation.signal);
          if (!validResultDescription(answer, body, body)) {
            invalid('InvalidClientHostResultDescription');
          }
          sendJson(answer);
        } finally { observation.release(); }
      } else if (operation === 'attach') {
        const admission = await invoke(attach);
        if (!validClientAdmission(admission, connection) ||
            admission.ref.namespaceId !== ref.namespaceId ||
            admission.ref.authorityScopeCid !== ref.authorityScopeCid ||
            admission.ref.runDefinitionCid !== ref.runDefinitionCid) {
          invalid('InvalidClientHostAdmission');
        }
        sendJson(admission);
      } else if (operation === 'lookup-request') {
        const lookup = await invoke(lookupRequest);
        if (!validRequestLookup(lookup, body.requestId)) {
          invalid('InvalidClientHostLookupResponse');
        }
        sendJson(lookup);
      } else if (operation === 'status') {
        const state = observeRun === undefined
          ? await inspectAuthorizedRunState(stateService, {
          indexKey: body.ref,
          principalId: principal,
          purpose: 'inspect',
        }) : await invoke(observeRun);
        if (!validRunState(state)) {
          invalid('InvalidClientHostRunState');
        }
        sendJson(state);
      } else if (operation === 'wait') {
        const observer = observationAttempt(response);
        try {
          const state = await invoke(wait, observer.signal);
          if (!validRunState(state)) invalid('InvalidClientHostRunState');
          sendJson(state);
        }
        finally { observer.release(); }
      } else if (operation === 'checkpoints') {
        const page = await invoke(checkpoints);
        if (!validCheckpointPage(page, body.limit)) {
          invalid('InvalidClientHostCheckpointPage');
        }
        sendJson(page);
      } else if (operation === 'checkpoint-review') {
        // Aborting this read ends only the read attempt.
        const observer = observationAttempt(response);
        try {
          const review = await invoke(checkpointReview, observer.signal);
          if (!validCheckpointReview(review, {
            checkpointCid: body.checkpointCid, maxBytes: body.maxBytes,
          })) invalid('InvalidClientHostCheckpointReview');
          sendJson(review);
        } finally { observer.release(); }
      } else if (operation === 'resolve') {
        const answered = await invoke(resolve);
        if (!validResolveResults(answered, body.items)) {
          invalid('InvalidClientHostResolveReply');
        }
        sendJson(answered);
      } else if (operation === 'cancel-request') {
        const cancelled = await invoke(cancelRequest);
        if (!validRequestCancellation(cancelled, body.requestId)) {
          invalid('InvalidClientHostRequestCancellation');
        }
        sendJson(cancelled);
      } else if (operation === 'resources' ||
          operation === 'resource-inspect' || operation === 'resource-peek') {
        // Aborting a discovery read ends only that read.
        const observer = observationAttempt(response);
        try {
          const handler = operation === 'resources' ? resources
            : operation === 'resource-inspect' ? inspectResource
              : peekResource;
          const answer = await invoke(handler, observer.signal);
          const {connection: _connection, ...expected} = body;
          if (!(operation === 'resources'
            ? validResourceListing(answer, {
              resourceConnection: body.resourceConnection, limit: body.limit})
            : operation === 'resource-inspect'
              ? validResourceInspection(answer, expected)
              : validResourcePeek(answer, expected))) {
            invalid('InvalidClientHostResourceReply');
          }
          sendJson(answer);
        } finally { observer.release(); }
      } else if (operation === 'cancel') {
        sendJson(await invoke(cancel));
      } else if (operation === 'reconcile') {
        // The reply is the Run's current state after the Host's
        // reconciliation attempt; an unknown outcome stays unknown.
        const state = await invoke(reconcile);
        if (!validRunState(state)) invalid('InvalidClientHostRunState');
        sendJson(state);
      } else if (operation === 'delivery-attempt') {
        const lookup = deliveryAttempt === undefined
          ? await inspectAuthorizedDeliveryAttempt(resultService, {
            indexKey: body.ref,
            principalId: principal,
            purpose: 'download',
            resultName: body.resultName,
            attemptId: body.attemptId,
          }) : await invoke(deliveryAttempt);
        if (!validDeliveryAttemptLookup(lookup, {
          attemptId: body.attemptId,
          runDefinitionCid: body.ref.runDefinitionCid,
          resultName: body.resultName,
        })) invalid('InvalidClientHostAttemptLookup');
        sendJson(lookup);
      } else {
        if (!['json', 'jsonl', 'csv'].includes(body.format)) {
          invalid('InvalidClientRequest');
        }
        const contentType = {
          json: 'application/json',
          jsonl: 'application/x-ndjson',
          csv: 'text/csv',
        }[body.format];
        const begin = () => {
          if (!response.headersSent) {
            response.writeHead(200, {'content-type': contentType});
          }
        };
        const observer = observationAttempt(response);
        try {
          await deliverAuthorizedResult(resultService, {
            indexKey: body.ref,
            principalId: principal,
            purpose: 'download',
            resultName: body.resultName,
            format: body.format,
            attemptId: body.attemptId,
          }, {
            write: bytes => { begin(); return write(response, bytes); },
            finish: () => { begin(); return finish(response, body.format); },
          }, observer.signal);
        } finally { observer.release(); }
      }
    } catch (error) {
      sendError(response, error);
    }
  };
}
