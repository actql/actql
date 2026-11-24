// Client-Host HTTP ingress. Authentication and connection consent are installed
// by the Host; Run meaning and read admission stay with the existing services.
import {observeClientRunState} from './client-run-state.mjs';
import {performClientSubmit} from './client-submit.mjs';
import {projectClientCheckUnavailable} from './client-check.mjs';
import {isLoopbackHttpRequest} from './loopback-http.mjs';
import {observeClientAuthorizationFailure} from
  './client-authentication-observation.mjs';
import {deliverAuthorizedResult,
  describeAuthorizedResult, inspectAuthorizedDeliveryAttempt} from './result-access.mjs';
import {clientHostOperations, clientWorkspaceMatches, validCheckpointPage, validCheckpointLookup, validCheckpointReview,
  validClientAdmission, prepareClientHostRequest, validClientProfile, validCancellationAttempt, validCancellationLookup,
  validDeliveryAttemptLookup, validRequestLookup, validResolveResults,
  validRequestCancellation, validResourceInspection, validResourceListing,
  validResourcePeek, validRunState, validResultDescription, validOwnerObservations,
  validCheckOutcome,
  validSubmissionAttempt, validNamedSubmissionAttempt, validSubmissionLookup} from
  '../../packages/client-wire/index.mjs';
import {validWireEffectfulStaticPlanViewShape, validWirePlanViewShape, validWireRunViewShape,
  validWireRunPlanViewShape, validWireRunExplanationViewShape, validWireRunExplanationContextViewShape, validWireStaticExplanationViewShape} from '../../packages/client-wire/index.mjs';

import type {IncomingMessage, ServerResponse} from 'node:http';
import type {ClientHostOperation, WireClientBodyByOperation, WireConnection, WireRunRef} from '../../packages/client-wire/index.js';
import type {DispatchedHandler, ExplanationConsumer, Handler, HandlerPorts, HostInstallation, RoutedBody}
  from './in-process-client.mjs';

type Delivery = Parameters<typeof deliverAuthorizedResult>;
type DeliveryFormat = Delivery[1]['format'];
type ErrorCode = Readonly<{code?: unknown}>;
type Terminal = 'failed' | 'returned';
type RequestFields = Readonly<Record<string, unknown>>;
type RequestLifetime = Readonly<{
  body: unknown;
  beforeReply(): unknown;
  bindRequest(request: unknown): unknown;
  finish(terminal: Terminal): unknown;
}>;
type BodyLifetime = Readonly<{
  beforeRead(bytes: number, chunks: number, quantum: number): unknown;
  beforeJson(wire: string): unknown;
  prepareRequest(request: RequestFields): RequestLifetime | PromiseLike<RequestLifetime>;
  finish(terminal: Terminal): unknown;
}>;
type HttpInstallation = Omit<HostInstallation, 'authenticate' | 'negotiate' | 'maxRowBytes' |
  'bindOwnedRequest' | 'performInstalledRequest' | 'captureResultObservation' | 'captureResultOperation'> & Readonly<{
  authenticate(authorization: string | undefined): unknown;
  negotiate?: Handler<'connect'>;
  deliveryAttempt?: Handler<'delivery-attempt'>;
  maxRequestBytes?: number;
  loopbackHttp?: boolean;
  prepareRequest(operation: ClientHostOperation, request: RequestFields):
    RequestLifetime | null | undefined | PromiseLike<RequestLifetime | null | undefined>;
}>;

const operations = new Set(clientHostOperations);

function invalid(code: string): never {
  const error = new Error(code) as Error & {code: string};
  error.code = code;
  throw error;
}

async function boundedJson(request: IncomingMessage, maxBytes: number): Promise<unknown> {
  let size = 0;
  const chunks: Uint8Array[] = [];
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

// Own bounded copies only. IncomingMessage/socket producer allocations remain
// supplied by the transport owner, not by highWaterMark or this Request quote.
async function preparedJson(request: IncomingMessage, maxBytes: number, prepared: BodyLifetime): Promise<unknown> {
  if (typeof request.read !== 'function' || typeof request.once !== 'function' ||
      typeof request.off !== 'function' || request.readableObjectMode === true ||
      request.readableEncoding !== null && request.readableEncoding !== undefined) {
    invalid('InvalidClientRequest');
  }
  // Admit the empty copy/control inventory before constructing its chunk list.
  prepared.beforeRead(0, 1, 1);
  const chunks: Uint8Array[] = [];
  let size = 0, reservedBytes = 0, reservedChunks = 1, reservedQuantum = 1;
  const reserve = (bytes: number, count: number, read: number) => {
    reservedBytes = Math.max(reservedBytes, bytes);
    reservedChunks = Math.max(reservedChunks, count);
    reservedQuantum = Math.max(reservedQuantum, read);
    prepared.beforeRead(reservedBytes, reservedChunks, reservedQuantum);
  };
  const quantum = 65536;
  const disconnected = () => request.errored ?? new Error('ClientDisconnected');
  for (;;) {
    const available = request.readableLength;
    if (!Number.isSafeInteger(available) || available < 0) invalid('InvalidClientRequest');
    const count = Math.min(quantum, maxBytes - size + 1, available || quantum);
    // The one-byte probe can detect a body beyond the installed attack limit
    // without retaining it. Fresh currentness precedes each read after a wait.
    reserve(size + count, chunks.length + 1, count);
    if (request.aborted || request.destroyed && !request.readableEnded) throw disconnected();
    const chunk = request.read(count);
    if (chunk === null) {
      if (request.readableEnded) break;
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const finish = (error?: unknown) => {
          if (settled) return;
          settled = true;
          request.off('readable', ready); request.off('end', ready);
          request.off('error', failed); request.off('aborted', closed);
          request.off('close', closed);
          error === undefined ? resolve() : reject(error);
        };
        const ready = () => finish();
        const failed = (error: unknown) => finish(error);
        const closed = () => request.readableEnded ? finish() : finish(disconnected());
        request.once('readable', ready); request.once('end', ready);
        request.once('error', failed); request.once('aborted', closed);
        request.once('close', closed);
        if (request.errored) failed(request.errored);
        else if (request.aborted || request.destroyed) closed();
        else if (request.readableEnded) ready();
      });
      continue;
    }
    if (!Buffer.isBuffer(chunk) || chunk.byteLength < 1 || chunk.byteLength > count) {
      invalid('InvalidClientRequest');
    }
    if (chunk.byteLength > maxBytes - size) invalid('ClientRequestTooLarge');
    // read(n) may execute the original stream's callbacks. Recheck before our
    // own retained copy; do not retain a borrowed transport chunk instead.
    reserve(size + count, chunks.length + 1, count);
    chunks.push(Buffer.from(chunk));
    size += chunk.byteLength;
  }
  reserve(size + 1, chunks.length + 1, 1);
  let wire;
  try { wire = new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks, size)); }
  catch { invalid('InvalidClientRequest'); }
  // Resource/current/preflight failures keep their original primary. Only the
  // native decoder's own malformed JSON is an InvalidClientRequest here.
  prepared.beforeJson(wire);
  try { return JSON.parse(wire); }
  catch { invalid('InvalidClientRequest'); }
}

function responseCode(error: ErrorCode | null | undefined) {
  if (error?.code === 'RunStateAccessDenied' ||
      error?.code === 'RunObservationAccessDenied' ||
      error?.code === 'StaticExplanationAccessDenied' ||
      error?.code === 'ResultAccessDenied' ||
      error?.code === 'ResultDeliveryDenied' ||
      error?.code === 'ClientAuthenticationDenied' ||
      error?.code === 'ClientConnectionDenied' ||
      error?.code === 'ClientRequestLookupDenied' ||
      error?.code === 'ClientRunStartDenied' ||
      error?.code === 'ClientRunCancellationDenied' ||
      error?.code === 'ClientCancellationDenied' ||
      error?.code === 'ClientRunAttachDenied' ||
      error?.code === 'CheckpointListDenied' ||
      error?.code === 'CheckpointReviewDenied' ||
      error?.code === 'CheckpointAnswerDenied' ||
      error?.code === 'ClientRequestCancellationDenied' ||
      error?.code === 'ResourceDiscoveryDenied' ||
      error?.code === 'ResourcePeekDenied' ||
      /^ACTQL_E_(ACCOUNT_[A-Z_]+|DELEGATION_[A-Z_]+)$/u
        .test((error?.code ?? '') as string)) return 403;
  if (error?.code === 'CheckpointReviewUnavailable') return 410;
  if (error?.code === 'WaitAborted' || error?.code === 'WaitTimeout') return 408;
  if (error?.code === 'ClientRequestNotFound' ||
      error?.code === 'ResourceConnectionNotFound') return 404;
  if (error?.code === 'ResourceCatalogUnavailable') return 503;
  if (error?.code === 'HeldRequestEvidenceUnavailable') return 503;
  if (error?.code === 'RunExplanationReadLimit' || error?.code === 'StaticExplanationReadLimit') return 413;
  if (error?.code === 'RunExplanationReadCapacity' ||
      error?.code === 'RunExplanationReadUnavailable' ||
      error?.code === 'RunExplanationReadCapacityUnavailable' ||
      error?.code === 'StaticExplanationOriginalUnavailable') return 503;
  if (error?.code === 'RunExplanationEncodingRejected' ||
      error?.code === 'StaticExplanationEncodingRejected') return 422;
  if (error?.code === 'CheckpointReviewTooLarge') return 413;
  if (error?.code === 'ClientRequestIntentConflict' ||
      error?.code === 'ClientSubmittedIntentConflict' ||
      error?.code === 'ClientCancellationIntentConflict' ||
      error?.code === 'ClientCancellationRevisionConflict') return 409;
  if (error?.code === 'ResultUnavailable') return 410;
  if (error?.code === 'ResultDescriptionUnavailable') return 410;
  if (error?.code === 'ResultDescriptionTooLarge') return 413;
  if (error?.code === 'ClientRequestTooLarge' ||
      error?.code === 'ClientOwnerObservationLimit' ||
      error?.code === 'ClientParametersTooLarge') return 413;
  if (error?.code === 'InvalidClientRequest' ||
      error?.code === 'ClientSubmissionReferenceRequired' ||
      error?.code === 'InvalidClientCancellationOperation' ||
      error?.code === 'InvalidClientCancellationLookup' ||
      error?.code === 'ClientProgramInvalidInput' ||
      error?.code === 'ClientParametersInvalid' ||
      error?.code === 'InvalidRunStateRequest' ||
      error?.code === 'InvalidWaitCondition' ||
      error?.code === 'InvalidWaitRevision' ||
      error?.code === 'InvalidResultAccessRequest' ||
      error?.code === 'InvalidCheckpointPage') return 400;
  if (error?.code === 'ClientProgramNeedsInputs' ||
      error?.code === 'ClientProgramRejected' ||
      error?.code === 'ClientProgramUnsupported' ||
      error?.code === 'ClientProgramAnalysisLimit' ||
      error?.code === 'ClientProgramImplementationLimit') return 422;
  if (error?.code === 'UnknownClientOperation') return 404;
  if (error?.code === 'ClientOperationUnavailable') return 501;
  if (error?.code === 'ResultAttemptLookupUnavailable') return 501;
  return 500;
}

// The public code HTTP ingress answers for `error`; in-process ingress uses
// the same classification for operations both serve.
export function publicClientErrorCode(error: unknown): unknown {
  return responseCode(error as ErrorCode | null | undefined) === 500 ? 'ClientHostFailure' : (error as ErrorCode).code;
}

// In-process errors retain the same refusal/unknown-outcome classification.
export function publicClientErrorStatus(error: unknown) {
  return responseCode(error as ErrorCode | null | undefined);
}

function sendError(response: ServerResponse, error: unknown) {
  if (response.headersSent) {
    response.destroy(error as Error);
    return;
  }
  const status = responseCode(error as ErrorCode | null | undefined);
  response.writeHead(status, {'content-type': 'application/json'});
  response.end(JSON.stringify({
    code: status === 500 ? 'ClientHostFailure' : (error as ErrorCode).code,
  }));
}

function write(response: ServerResponse, bytes: Uint8Array) {
  return new Promise<Readonly<{confirmedBytes: number}>>((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    response.write(bytes, error => error ? reject(error) :
      resolve({confirmedBytes: bytes.byteLength}));
  });
}

function finish(response: ServerResponse, format: DeliveryFormat) {
  return new Promise<Readonly<{confirmed: true}>>((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    // Confirm the explicit payload end without closing HTTP. A raw record
    // separator cannot occur unescaped in JSON and is outside the payload
    // digest. EOF is withheld until the owner durably commits its receipt.
    response.write(format === 'jsonl' ? Buffer.from([0x1e]) : Buffer.alloc(0),
      error => error ? reject(error) :
      resolve({confirmed: true}));
  });
}

function observationAttempt(response: ServerResponse) {
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
  authenticate, authorizeConnection, workspaceForPrincipal, stateService, runStateObservation, resultService,
  negotiate, submit, submitIntent, submitNamedIntent, lookupSubmission, attach, lookupRequest, observeRun, observeOwners, wait, cancel, lookupCancellation,
  reconcile, deliveryAttempt, prepareSubmit, checkpoints, checkpointReview,
  resolve, cancelRequest, resources, inspectResource, peekResource,
  check, plan, staticEffectExplanation, inspectRun, runPlan, runExplanation, runExplanationContext,
  maxRequestBytes = 65536, observe, loopbackHttp = false,
  prepareRequest,
}: HttpInstallation) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      typeof loopbackHttp !== 'boolean' ||
      typeof prepareRequest !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    throw new TypeError('InvalidClientHostInstallation');
  }
  const rawPort = Object.getOwnPropertyDescriptor(prepareRequest, 'beforeBody');
  if (rawPort !== undefined && (!Object.hasOwn(rawPort, 'value') ||
      typeof rawPort.value !== 'function')) throw new TypeError('InvalidClientHostInstallation');
  return async (request: IncomingMessage, response: ServerResponse) => {
    let requestLifetime: RequestLifetime | null | undefined, bodyLifetime: BodyLifetime | undefined, terminal: Terminal = 'failed';
    try {
      try {
      if (loopbackHttp && !isLoopbackHttpRequest(request)) {
        invalid('ClientConnectionDenied');
      }
      if (request.method !== 'POST' ||
          !request.url?.startsWith('/actql/client/0.1/')) {
        invalid('UnknownClientOperation');
      }
      const operation = request.url.slice('/actql/client/0.1/'.length) as ClientHostOperation;
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
      if (rawPort !== undefined) {
        const original = Reflect.apply(rawPort.value, prepareRequest, [operation, maxRequestBytes]) as
          Partial<Record<keyof BodyLifetime, unknown>> | undefined;
        const methods = ['beforeRead', 'beforeJson', 'prepareRequest', 'finish']
          .map(name => original?.[name as keyof BodyLifetime]);
        if (methods.some(method => typeof method !== 'function')) invalid('InvalidClientHostPreparation');
        bodyLifetime = Object.freeze(Object.fromEntries(
          ['beforeRead', 'beforeJson', 'prepareRequest', 'finish'].map((name, index) =>
            [name, (...args: unknown[]) => Reflect.apply(methods[index] as (...args: unknown[]) => unknown, original, args)]))) as BodyLifetime;
      }
      const decoded = bodyLifetime === undefined ? await boundedJson(request, maxRequestBytes)
        : await preparedJson(request, maxRequestBytes, bodyLifetime);
      const prepared = prepareClientHostRequest(operation, decoded);
      if (prepared === undefined) invalid('InvalidClientRequest');
      const {body, connection} = prepared as Readonly<{body: RoutedBody; connection: WireConnection}>;
      const ref = body.ref === undefined ? undefined :
        Object.freeze({...body.ref});
      // Widening the structural wire schema must not let an old boolean
      // authorizer silently ignore a new Workspace assertion. Resolve only
      // from the authenticated principal and trusted installation context.
      if (connection.workspaceId !== undefined) {
        let workspaceId;
        try {
          workspaceId = typeof workspaceForPrincipal === 'function'
            ? await workspaceForPrincipal(principal) : undefined;
        } catch { invalid('ClientConnectionDenied'); }
        if (!clientWorkspaceMatches(connection, workspaceId)) {
          invalid('ClientConnectionDenied');
        }
      }
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
      const sendJson = (value: unknown) => {
        requestLifetime?.beforeReply();
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(value));
      };
      if (authorized !== true) {
        if (operation === 'check') {
          sendJson(await projectClientCheckUnavailable(check));
          return;
        }
        invalid('ClientConnectionDenied');
      }
      const originalRequest = Object.freeze({principalId: principal, connection,
        ...Object.fromEntries(Object.entries(body)
          .filter(([key]) => key !== 'connection' && key !== 'ref')),
        ...(ref === undefined ? {} : {ref})});
      requestLifetime = bodyLifetime === undefined ? await prepareRequest(operation, originalRequest)
        : await bodyLifetime.prepareRequest(originalRequest);
      if (requestLifetime === undefined || requestLifetime === null ||
          typeof requestLifetime !== 'object' || requestLifetime.body === null ||
          typeof requestLifetime.body !== 'object' ||
          typeof requestLifetime.beforeReply !== 'function' ||
          typeof requestLifetime.bindRequest !== 'function' ||
          typeof requestLifetime.finish !== 'function') invalid('InvalidClientHostPreparation');
      const admittedRequest = requestLifetime.body;
      const invoke = async (handler: HandlerPorts[keyof HandlerPorts] | Handler<'delivery-attempt'>,
        signal?: AbortSignal, preparedProgram?: unknown, consume?: ExplanationConsumer) => {
        if (typeof handler !== 'function') invalid('ClientOperationUnavailable');
        const original = Object.freeze({...admittedRequest,
          ...(signal === undefined ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        });
        requestLifetime!.bindRequest(original);
        return consume === undefined ? (handler as DispatchedHandler)(original)
          : (handler as DispatchedHandler)(original, consume);
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
          executionProfile: body.executionProfile,
          prepare: prepareSubmit === undefined ? undefined :
            () => invoke(prepareSubmit),
          submit: prepared => invoke(submit, undefined, prepared)});
        sendJson(admission);
      } else if (operation === 'submit-named-intent') {
        const answer = await invoke(submitNamedIntent);
        if (!validNamedSubmissionAttempt(answer, connection, body.requestName,
          body.submissionRef, body.intentCid, body.attemptRef)) invalid('InvalidClientHostSubmissionOutcome');
        sendJson(answer);
      } else if (['submit-intent', 'restart-intent', 'lookup-submission'].includes(operation)) {
        const submitting = operation !== 'lookup-submission';
        const answer = await invoke(submitting ? submitIntent : lookupSubmission);
        const valid = submitting
          ? validSubmissionAttempt(answer, connection, body.submissionRef, body.intentCid, body.attemptRef, body.unresolvedHistory)
          : validSubmissionLookup(answer, connection, body.submissionRef);
        if (!valid) invalid('InvalidClientHostSubmissionOutcome');
        sendJson(answer);
      } else if (operation === 'result-describe') {
        const observation = observationAttempt(response);
        try {
          const resultRequest: Parameters<typeof describeAuthorizedResult>[1] = {
            indexKey: ref!, principalId: principal, purpose: 'inspect',
            resultName: body.resultName, format: body.format as DeliveryFormat,
            attemptId: body.attemptId, maxWireBytes: body.maxWireBytes,
            maxNodes: body.maxNodes, maxDepth: body.maxDepth,
          };
          requestLifetime.bindRequest(resultRequest);
          const answer = await describeAuthorizedResult(resultService!, resultRequest,
            observation.signal);
          if (!validResultDescription(answer, body as WireClientBodyByOperation['result-describe'], body)) {
            invalid('InvalidClientHostResultDescription');
          }
          sendJson(answer);
        } finally { observation.release(); }
      } else if (operation === 'attach') {
        const admission = await invoke(attach);
        if (!validClientAdmission(admission, connection) ||
            admission.ref.namespaceId !== ref!.namespaceId ||
            admission.ref.authorityScopeCid !== ref!.authorityScopeCid ||
            admission.ref.runDefinitionCid !== ref!.runDefinitionCid) {
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
        let state;
        if (observeRun === undefined) {
          const stateRequest: Parameters<typeof observeClientRunState>[2] = {
            indexKey: body.ref!,
            principalId: principal,
            purpose: 'inspect',
          };
          requestLifetime.bindRequest(stateRequest);
          state = await observeClientRunState(runStateObservation, stateService!, stateRequest);
        } else state = await invoke(observeRun);
        if (!validRunState(state)) {
          invalid('InvalidClientHostRunState');
        }
        sendJson(state);
      } else if (operation === 'plan') {
        const observer = observationAttempt(response);
        try {
          const view = await invoke(plan, observer.signal);
          if (!validWirePlanViewShape(view) && !validWireEffectfulStaticPlanViewShape(view)) invalid('InvalidClientHostPlanView');
          sendJson(view);
        } finally { observer.release(); }
      } else if (operation === 'run-plan') {
        const observer = observationAttempt(response);
        try {
          const view = await invoke(runPlan, observer.signal);
          if (!validWireRunPlanViewShape(view) ||
              (Object.keys(ref!) as (keyof WireRunRef)[]).some(key => view.run_ref[key] !== ref![key])) invalid('InvalidClientHostRunPlanView');
          sendJson(view);
        } finally { observer.release(); }
      } else if (operation === 'run-explanation' || operation === 'run-explanation-context' ||
            operation === 'static-explanation') {
        const staticRead = operation === 'static-explanation';
        const contextRead = operation === 'run-explanation-context';
        const reader = staticRead ? staticEffectExplanation : contextRead ? runExplanationContext : runExplanation;
        const validateRun = contextRead ? validWireRunExplanationContextViewShape : validWireRunExplanationViewShape;
        const observer = observationAttempt(response);
        try {
          await invoke(reader, observer.signal, undefined, async view => {
            if (staticRead) {
              if (!validWireStaticExplanationViewShape(view)) invalid('InvalidClientHostStaticExplanationView');
            } else if (!validateRun(view) ||
                (Object.keys(ref!) as (keyof WireRunRef)[]).some(key => view.run_ref[key] !== ref![key])) invalid('InvalidClientHostRunExplanationView');
            const wire = JSON.stringify(view);
            if (wire.length > body.maxWireBytes || Buffer.byteLength(wire) > body.maxWireBytes) {
              invalid(staticRead ? 'StaticExplanationReadLimit' : 'RunExplanationReadLimit');
            }
            const bytes = Buffer.from(wire);
            requestLifetime!.beforeReply();
            // The SAME read owns wire/buffer/view until the native end callback
            // confirms consumption. On error, retain it through actual close;
            // neither starting end nor a failed callback is a physical ACK.
            await new Promise<void>((resolve, reject) => {
              let settled = false, primary: unknown;
              const complete = () => {
                if (settled) return;
                settled = true;
                response.off('close', closed);
                response.off('error', failed);
                if (primary !== undefined) reject(primary);
                else resolve();
              };
              const closed = () => {
                primary ??= new Error('ClientDisconnected');
                complete();
              };
              const failed = (error: unknown) => {
                primary ??= error;
                if (response.closed) complete();
                else response.destroy();
              };
              response.once('close', closed);
              response.once('error', failed);
              if (response.closed) {closed(); return;}
              if (response.destroyed) return;
              try {
                response.writeHead(200, {'content-type': 'application/json'});
                response.end(bytes, (error?: Error) => {
                  if (error) failed(error);
                  else if (primary === undefined) complete();
                });
              } catch (error) {failed(error);}
            });
          });
        } finally { observer.release(); }
      } else if (operation === 'inspect-run') {
        const observer = observationAttempt(response);
        try {
          const view = await invoke(inspectRun, observer.signal);
          if (!validWireRunViewShape(view)) invalid('InvalidClientHostRunView');
          sendJson(view);
        } finally { observer.release(); }
      } else if (operation === 'owner-observations') {
        const views = await invoke(observeOwners);
        if (!validOwnerObservations(views,ref!,body)) invalid('InvalidClientHostOwnerObservations');
        sendJson(views);
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
        if (!(Object.hasOwn(body, 'checkpointId')
          ? validCheckpointLookup(page, body.checkpointId!)
          : validCheckpointPage(page, body.limit))) {
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
      } else if (operation === 'check') {
        // Every valid check outcome uses the same transport status; it
        // establishes neither a verified report nor execution success.
        const observer = observationAttempt(response);
        try {
          const outcome = await invoke(check, observer.signal);
          if (!validCheckOutcome(outcome)) {
            invalid('InvalidClientHostCheckOutcome');
          }
          sendJson(outcome);
        } finally { observer.release(); }
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
        const expected = {...ref!, cancelId: body.cancelId, expectedRevision: body.expectedRevision};
        const cancelled = await invoke(cancel);
        if (!validCancellationAttempt(cancelled, expected, body.attemptRef)) invalid('InvalidClientHostCancellation');
        sendJson(cancelled);
      } else if (operation === 'lookup-cancellation') {
        const expected = {...ref!, cancelId: body.cancelId, expectedRevision: body.expectedRevision};
        const found = await invoke(lookupCancellation);
        if (!validCancellationLookup(found, expected)) invalid('InvalidClientHostCancellationLookup');
        sendJson(found);
      } else if (operation === 'reconcile') {
        // The reply is the Run's current state after the Host's
        // reconciliation attempt; an unknown outcome stays unknown.
        const state = await invoke(reconcile);
        if (!validRunState(state)) invalid('InvalidClientHostRunState');
        sendJson(state);
      } else if (operation === 'delivery-attempt') {
        let lookup;
        if (deliveryAttempt === undefined) {
          const resultRequest: Parameters<typeof inspectAuthorizedDeliveryAttempt>[1] = {
            indexKey: body.ref!,
            principalId: principal,
            purpose: 'download',
            resultName: body.resultName,
            attemptId: body.attemptId,
          };
          requestLifetime.bindRequest(resultRequest);
          lookup = await inspectAuthorizedDeliveryAttempt(resultService!, resultRequest);
        } else lookup = await invoke(deliveryAttempt);
        if (!validDeliveryAttemptLookup(lookup, {
          attemptId: body.attemptId,
          runDefinitionCid: body.ref!.runDefinitionCid,
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
        }[body.format as DeliveryFormat];
        const begin = () => {
          requestLifetime?.beforeReply();
          if (!response.headersSent) {
            response.writeHead(200, {'content-type': contentType});
          }
        };
        const observer = observationAttempt(response);
        try {
          const resultRequest: Delivery[1] = {
            indexKey: body.ref!,
            principalId: principal,
            purpose: 'download',
            resultName: body.resultName,
            format: body.format as DeliveryFormat,
            attemptId: body.attemptId,
          };
          requestLifetime.bindRequest(resultRequest);
          await deliverAuthorizedResult(resultService!, resultRequest, {
            write: bytes => { begin(); return write(response, bytes); },
            finish: () => { begin(); return finish(response, body.format as DeliveryFormat); },
          }, observer.signal);
          // The shared owner confirms sink completion before issuing and
          // persisting its receipt and succeeded record. Only their successful
          // return authorizes HTTP EOF; failure destroys the partial response.
          requestLifetime?.beforeReply();
          // A closed response cannot acknowledge the original native end.
          // Settle its transport failure so the same Request can finish.
          await new Promise<void>((resolve, reject) => {
            let settled = false;
            const complete = (failure: boolean, error: unknown) => {
              if (settled) return;
              settled = true;
              response.off('close', disconnected);
              response.off('error', failed);
              if (failure) reject(error);
              else resolve();
            };
            const disconnected = () => complete(true, new Error('ClientDisconnected'));
            const failed = (error: unknown) => complete(true, error);
            response.once('close', disconnected);
            response.once('error', failed);
            if (response.destroyed) { disconnected(); return; }
            try { response.end((error?: Error) => complete(Boolean(error), error)); }
            catch (error) { complete(true, error); }
          });
        } finally { observer.release(); }
      }
      terminal = 'returned';
      } finally {
        if (typeof requestLifetime?.finish === 'function') await requestLifetime.finish(terminal);
        else if (bodyLifetime !== undefined) {
          try { await bodyLifetime.finish(terminal); }
          catch (cause) { if (terminal !== 'failed') throw cause; }
        }
      }
    } catch (error) {
      sendError(response, error);
    }
  };
}
