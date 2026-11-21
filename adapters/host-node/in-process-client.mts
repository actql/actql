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
import {validWireEffectfulStaticPlanViewShape, validWirePlanViewShape, validWireRunViewShape, validWireRunPlanViewShape, validWireRunExplanationViewShape} from '../../packages/client-wire/index.mjs';
import {observeClientRunState} from './client-run-state.mjs';
import {inspectAuthorizedDeliveryAttempt, describeAuthorizedResult} from './result-access.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';
// @ts-expect-error TS7016: This shared runtime classifier still has its original HTTP JS owner.
import {publicClientErrorCode, publicClientErrorStatus} from './client-http.mjs';

import type {ClientHostOperation, WireClientBody, WireClientBodyByOperation, WireRunRef,
  WireConnection} from '../../packages/client-wire/index.js';
import type {installHostObservation} from '../host-common/observation.mjs';

type BodyByOperation = WireClientBodyByOperation;
type BodyKeys<Body> = Body extends unknown ? keyof Body : never;
type BodyField<Body, Key extends PropertyKey> =
  Body extends unknown ? Key extends keyof Body ? Body[Key] : never : never;
// The selected operation establishes which fields are available. This view
// follows the existing successful wire preparation (or its same retained copy).
type RoutedBody = Readonly<{[Key in Exclude<BodyKeys<WireClientBody>, 'ref'>]: BodyField<WireClientBody, Key>}> &
  Readonly<{ref?: WireRunRef}>;
type PreparedBody = NonNullable<ReturnType<typeof prepareClientHostRequest>>;
type InstalledRequest = (operation: ClientHostOperation, body: WireClientBody, signal?: AbortSignal) => unknown;
type HostBody<Operation extends ClientHostOperation> = BodyByOperation[Operation] & Readonly<{
  principalId: string;
  signal?: AbortSignal;
  preparedProgram?: unknown;
}>;
type Handler<Operation extends ClientHostOperation> = (request: HostBody<Operation>) => unknown;
type CheckHandler = Handler<'check'> & NonNullable<Parameters<typeof projectClientCheckUnavailable>[0]>;
type ExplanationConsumer = (view: unknown) => unknown;
type HandlerPorts = Readonly<{
  negotiate: Handler<'connect'>;
  prepareSubmit?: Handler<'submit'>;
  submit?: Handler<'submit'>;
  submitIntent?: Handler<'submit-intent' | 'restart-intent'>;
  submitNamedIntent?: Handler<'submit-named-intent'>;
  lookupSubmission?: Handler<'lookup-submission'>;
  attach?: Handler<'attach'>;
  lookupRequest?: Handler<'lookup-request'>;
  observeRun?: Handler<'status'>;
  observeOwners?: Handler<'owner-observations'>;
  wait?: Handler<'wait'>;
  cancel?: Handler<'cancel'>;
  lookupCancellation?: Handler<'lookup-cancellation'>;
  cancelRequest?: Handler<'cancel-request'>;
  reconcile?: Handler<'reconcile'>;
  checkpoints?: Handler<'checkpoints'>;
  checkpointReview?: Handler<'checkpoint-review'>;
  resolve?: Handler<'resolve'>;
  resources?: Handler<'resources'>;
  inspectResource?: Handler<'resource-inspect'>;
  peekResource?: Handler<'resource-peek'>;
  check?: CheckHandler;
  plan?: Handler<'plan'>;
  inspectRun?: Handler<'inspect-run'>;
  runPlan?: Handler<'run-plan'>;
  runExplanation?: (request: HostBody<'run-explanation'>, consume: ExplanationConsumer) => unknown;
}>;
type DispatchedHandler = (request: Readonly<Record<string, unknown>>, consume?: ExplanationConsumer) => unknown;
type RunState = Parameters<typeof observeClientRunState>;
type ResultService = Parameters<typeof authorizedLocalResultFrames>[0];
type ResultObservation = ReturnType<NonNullable<ReturnType<typeof installHostObservation>>['captureCurrentOperation']>;
type ResultRows = ReturnType<typeof authorizedLocalResultFrames>;
type ResultIterator = ReturnType<ResultRows['frames'][typeof Symbol.asyncIterator]>;
type ObserveConsumed = (() => unknown) | undefined;
type CleanupFailure = Readonly<{
  cleanupPending?: unknown;
  cleanupHandle?: Readonly<{status?: () => Readonly<{pending?: unknown}>; retry?: () => unknown}>;
}>;
type HostInstallation = HandlerPorts & Readonly<{
  authenticate: () => unknown;
  authorizeConnection: (input: Readonly<{
    principalId: string;
    connection: WireConnection;
    ref: WireRunRef | undefined;
    operation: ClientHostOperation;
  }>) => unknown;
  workspaceForPrincipal?: (principalId: string) => string | undefined | PromiseLike<string | undefined>;
  bindOwnedRequest?: (parent: object, derived: object) => undefined;
  stateService?: RunState[1];
  runStateObservation?: RunState[0];
  resultService?: ResultService;
  maxRowBytes: number;
  observe?: unknown;
  performInstalledRequest?: InstalledRequest;
  captureResultObservation?: (ref: WireRunRef) => ObserveConsumed;
  captureResultOperation?: () => ResultObservation;
}>;

const localErrors = new WeakSet<ClientError>();
// Only packets captured here before deferred service construction carry this
// original operation's immutable shape facts into the activated ingress.
// Authentication and authorization are never retained in this association.
const deferredRequests = new WeakMap<object, Readonly<{operation: ClientHostOperation; prepared: PreparedBody}>>();
const publicError = (code: string, status: number) => {
  const error = new ClientError(code, {status});
  delete error.stack;
  return error;
};
const fail: (code: string) => never = code => {
  const error = publicError(code, publicClientErrorStatus({code}));
  localErrors.add(error);
  throw error;
};
const publicFailure = (error: unknown) => localErrors.has(error as ClientError) ? error as ClientError
  : publicError(publicClientErrorCode(error), publicClientErrorStatus(error));

function publicResultRows(response: ResultRows, observeConsumed: ObserveConsumed, observeOperation: ResultObservation) {
  // Keep a failed delivery record's exact retry owner off public errors. The
  // SDK may release this response only after that owner confirms settlement.
  let cleanupFailure: CleanupFailure | undefined;
  let original = observeOperation, resume: NonNullable<ResultObservation>['run'] | undefined,
    retire: NonNullable<ResultObservation>['release'] | undefined;
  try {resume = original?.run; retire = original?.release;}
  catch { /* An optional observation cannot replace the Result response. */ }
  const inContext = <Result,>(work: () => Result): Result => {
    if (typeof resume !== 'function') return work();
    let called = false, value: Result, failure: unknown, threw = false;
    const once = () => {
      if (called) {if (threw) throw failure; return value!;}
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
  const contextualFrames = (frames: ResultRows['frames']) => ({[Symbol.asyncIterator]() {
    const iterator = inContext(() => frames[Symbol.asyncIterator]());
    const next = inContext(() => iterator.next);
    const method = <Name extends 'return' | 'throw',>(name: Name): ResultIterator[Name] => {
      const operation = inContext(() => iterator[name]);
      return (typeof operation === 'function'
        ? (...args: unknown[]) => inContext(() => Reflect.apply(operation, iterator, args)) : operation) as ResultIterator[Name];
    };
    return {next(...args: Parameters<ResultIterator['next']>) {return inContext(() => Reflect.apply(next, iterator, args));},
      get return() {return method('return');}, get throw() {return method('throw');},
      [Symbol.asyncIterator]() {return this;}};
  }});
  return Object.freeze({kind: 'rows', frames: Object.freeze({
    async *[Symbol.asyncIterator]() {
      let consumed = false;
      try { yield* (original === undefined ? response.frames : contextualFrames(response.frames)); consumed = true; }
      catch (error) {
        if ((error as CleanupFailure | null | undefined)?.cleanupPending === true) cleanupFailure = error as CleanupFailure;
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
      if (inContext(() => handle.status!()).pending !== false) await inContext(() => handle.retry!());
      if (inContext(() => handle.status!()).pending !== false) throw cleanupFailure;
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
  resources, inspectResource, peekResource, check, plan, inspectRun, runPlan, runExplanation, maxRowBytes, observe,
  performInstalledRequest,
  captureResultObservation,
  captureResultOperation,
}: HostInstallation) {
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
  return Object.freeze({async perform(operation: ClientHostOperation, body: unknown, signal?: AbortSignal) {
    try {
      if (operation === 'lookup-submission') signal?.throwIfAborted();
      // Static preparation probes the same funded-original lookup, even
      // though a plan read has no submission producer or execution grant.
      const tracksSource = bindOwnedRequest !== undefined &&
        ['plan', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation);
      const own = <Body,>(parent: unknown, derived: Body): Body => {
        if (tracksSource && bindOwnedRequest(parent as object, derived as object) !== undefined) {
          fail('SourceManagedPreparationUnavailable');
        }
        return derived;
      };
      // Local rows use the existing JSONL request shape for wire admission.
      const captured = deferredRequests.get(body as object);
      const retainSnapshot = performInstalledRequest !== undefined && operation !== 'connect';
      const prepared = captured?.operation === operation ? captured.prepared
        : prepareClientHostRequest(operation,
          operation === 'read' ? {...(body as object), format: 'jsonl'} : body, retainSnapshot);
      if (prepared === undefined) fail('InvalidClientRequest');
      if (retainSnapshot) {
        deferredRequests.set(prepared.body as object, Object.freeze({operation, prepared}));
      }
      // A deferred constructor retains the wire Owner's one immutable capture.
      // The activated ingress consumes those same shape facts, but still
      // performs its own current authentication and connection authorization.
      const admittedBody = own(body, prepared.body) as RoutedBody;
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
      const ref = admittedBody.ref;
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
        return await performInstalledRequest(operation,admittedBody as WireClientBody,signal);
      }
      const invoke = async (handler: HandlerPorts[keyof HandlerPorts], preparedProgram?: unknown, consume?: ExplanationConsumer) => {
        if (typeof handler !== 'function') fail('ClientOperationUnavailable');
        const original = own(admittedBody, Object.freeze({principalId, connection,
          ...Object.fromEntries(Object.entries(admittedBody).filter(([key]) =>
            key !== 'connection')),
          ...(signal === undefined || ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent', 'lookup-submission'].includes(operation)
            ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        }));
        return consume === undefined ? (handler as DispatchedHandler)(original)
          : (handler as DispatchedHandler)(original, consume);
      };
      if (operation === 'connect') {
        const profile = await invoke(negotiate);
        if (!validClientProfile(profile, connection)) {
          fail('InvalidClientHostProfile');
        }
        return profile;
      }
      if (operation === 'submit') {
        return await performClientSubmit({connection, requestId: admittedBody.requestId,
          executionProfile: admittedBody.executionProfile,
          prepare: prepareSubmit === undefined ? undefined :
            () => invoke(prepareSubmit),
          submit: prepared => invoke(submit, prepared)});
      }
      if (operation === 'submit-named-intent') {
        const answer = await invoke(submitNamedIntent);
        if (!validNamedSubmissionAttempt(answer, connection, admittedBody.requestName,
          admittedBody.submissionRef, admittedBody.intentCid, admittedBody.attemptRef)) fail('InvalidClientHostSubmissionOutcome');
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
          ? validSubmissionAttempt(answer, connection, admittedBody.submissionRef, admittedBody.intentCid, admittedBody.attemptRef, admittedBody.unresolvedHistory)
          : validSubmissionLookup(answer, connection, admittedBody.submissionRef);
        if (!valid) fail('InvalidClientHostSubmissionOutcome');
        return answer;
      }
      if (operation === 'attach') {
        const admitted = await invoke(attach);
        if (!validClientAdmission(admitted, connection) ||
            admitted.ref.namespaceId !== ref!.namespaceId ||
            admitted.ref.authorityScopeCid !== ref!.authorityScopeCid ||
            admitted.ref.runDefinitionCid !== ref!.runDefinitionCid) {
          fail('InvalidClientHostAdmission');
        }
        return admitted;
      }
      if (operation === 'lookup-request') {
        const found = await invoke(lookupRequest);
        if (!validRequestLookup(found, admittedBody.requestId)) {
          fail('InvalidClientHostLookupResponse');
        }
        return found;
      }
      if (operation === 'status' || operation === 'wait') {
        const state = operation === 'status' && observeRun === undefined
          ? await observeClientRunState(runStateObservation, stateService!, {
            indexKey: ref!, principalId, purpose: 'inspect',
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
            (Object.keys(ref!) as (keyof WireRunRef)[]).some(key => view.run_ref[key] !== ref![key])) fail('InvalidClientHostRunPlanView');
        return view;
      }
      if (operation === 'run-explanation') {
        return await invoke(runExplanation, undefined, view => {
          if (!validWireRunExplanationViewShape(view) ||
              (Object.keys(ref!) as (keyof WireRunRef)[]).some(key => view.run_ref[key] !== ref![key])) fail('InvalidClientHostRunExplanationView');
          // Consume the Host-owned parsed view while its original read is
          // admitted. Only the independent caller value crosses this boundary.
          const wire = JSON.stringify(view);
          if (wire.length > admittedBody.maxWireBytes || Buffer.byteLength(wire) > admittedBody.maxWireBytes) fail('RunExplanationReadLimit');
          return JSON.parse(wire);
        });
      }
      if (operation === 'inspect-run') {
        const view = await invoke(inspectRun);
        if (!validWireRunViewShape(view)) fail('InvalidClientHostRunView');
        return view;
      }
      if (operation === 'owner-observations') {
        const views = await invoke(observeOwners);
        if (!validOwnerObservations(views,ref!,admittedBody)) fail('InvalidClientHostOwnerObservations');
        return views;
      }
      if (operation === 'checkpoints') {
        const page = await invoke(checkpoints);
        if (!validCheckpointPage(page, admittedBody.limit)) {
          fail('InvalidClientHostCheckpointPage');
        }
        return page;
      }
      if (operation === 'checkpoint-review') {
        const review = await invoke(checkpointReview);
        if (!validCheckpointReview(review, {
          checkpointCid: admittedBody.checkpointCid, maxBytes: admittedBody.maxBytes,
        })) fail('InvalidClientHostCheckpointReview');
        return review;
      }
      if (operation === 'resolve') {
        const answered = await invoke(resolve);
        if (!validResolveResults(answered, admittedBody.items)) {
          fail('InvalidClientHostResolveReply');
        }
        return answered;
      }
      if (operation === 'cancel-request') {
        const cancelled = await invoke(cancelRequest);
        if (!validRequestCancellation(cancelled, admittedBody.requestId)) {
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
        const {connection: _connection, ...expected} = admittedBody;
        if (!(operation === 'resources'
          ? validResourceListing(answer, {
            resourceConnection: admittedBody.resourceConnection, limit: admittedBody.limit})
          : operation === 'resource-inspect'
            ? validResourceInspection(answer, expected)
            : validResourcePeek(answer, expected))) {
          fail('InvalidClientHostResourceReply');
        }
        return answer;
      }
      if (operation === 'cancel') {
        const answer = await invoke(cancel);
        if (!validCancellationAttempt(answer, {...ref!, cancelId: admittedBody.cancelId,
          expectedRevision: admittedBody.expectedRevision}, admittedBody.attemptRef)) fail('InvalidClientHostCancellation');
        return answer;
      }
      if (operation === 'lookup-cancellation') {
        const answer = await invoke(lookupCancellation);
        if (!validCancellationLookup(answer, {...ref!, cancelId: admittedBody.cancelId,
          expectedRevision: admittedBody.expectedRevision})) fail('InvalidClientHostCancellationLookup');
        return answer;
      }
      if (operation === 'result-describe') {
        const answer = await describeAuthorizedResult(resultService!, {
          indexKey: ref!, principalId, purpose: 'inspect',
          resultName: admittedBody.resultName, format: admittedBody.format as BodyByOperation['result-describe']['format'],
          attemptId: admittedBody.attemptId, maxWireBytes: admittedBody.maxWireBytes,
          maxNodes: admittedBody.maxNodes, maxDepth: admittedBody.maxDepth,
        }, signal);
        if (!validResultDescription(answer, admittedBody as BodyByOperation['result-describe'], admittedBody)) {
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
        const found = await inspectAuthorizedDeliveryAttempt(resultService!, {
          indexKey: ref!, principalId, purpose: 'download',
          resultName: admittedBody.resultName, attemptId: admittedBody.attemptId,
        });
        if (!validDeliveryAttemptLookup(found, {
          attemptId: admittedBody.attemptId,
          runDefinitionCid: ref!.runDefinitionCid,
          resultName: admittedBody.resultName,
        })) fail('InvalidClientHostAttemptLookup');
        return found;
      }
      if (operation === 'read') {
        let consumed, observation;
        try {consumed = captureResultObservation?.(ref!);}
        catch { /* An unavailable observation is not a Result permission or failure. */ }
        try {observation = captureResultOperation?.();}
        catch { /* Keep the same Result request even if observation is unavailable. */ }
        return publicResultRows(authorizedLocalResultFrames(resultService!, {
          indexKey: ref!, principalId, purpose: 'download',
          resultName: admittedBody.resultName, attemptId: admittedBody.attemptId,
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
