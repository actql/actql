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

import type {Client, CheckOutcome, ConfirmedProfile, Execution, OperationExplanationOptions,
  RequestLookup, RequestLookupTarget, RequestRecovery, SubmissionAttempt, SubmissionInput, SubmissionOptions, SubmissionOutcome,
  SubmissionReference} from '../index.d.ts';
import type {ClientHostOperation, ClientSourceFormat, WireClientAdmission, WireOperationAttemptRef} from '@actql/client-wire';
import type {SelectedConnection} from './connection-options.mjs';
import type {captureSourcePreparation} from './private-source-preparation.mjs';
import type {createClientLifecycle} from './client-lifecycle.mjs';

type SourcePreparation = NonNullable<ReturnType<typeof captureSourcePreparation>>;
interface Producer {receipt: unknown; body?: CapturedBody}
type CallOptions = Partial<SubmissionOptions> & {format?: ClientSourceFormat; parameterDeclarations?: Record<string, unknown>};
// These are unchecked snapshot fields until the original guards below run.
interface CapturedBody {
  kind: 'program' | 'aql'; input: Record<string, unknown> & {format?: ClientSourceFormat}; parameters: unknown;
  submissionRef: SubmissionReference; attemptRef: WireOperationAttemptRef & {operation: 'submit'};
  requestName?: string; stopBefore?: 'commit'; readOnly?: true; executionProfile?: 'debug';
  unresolvedHistory?: SubmissionOptions['unresolvedHistory'];
}
type LookupInput = Parameters<typeof submissionLookupExplanation>[1];
type SubmissionContext = Parameters<typeof projectSubmissionExplanation>[2];
type RequestContext = Parameters<typeof projectRequestLookupExplanation>[1];
type Invocation = SubmissionContext & {requestId: string; attemptRef: WireOperationAttemptRef & {operation: 'submit'}; requestName?: string};
type SubmissionSnapshot = SubmissionInput & CapturedBody;
type SubmissionOperations = Pick<Client, 'start' | 'startSource' | 'sql' | 'aql' | 'newSubmission' |
  'lookupSubmission' | 'attach' | 'lookupRequest' | 'recoverRequest' | 'cancelRequest'> & {
    withStaticPreparation<T>(kind: 'aql' | 'program', input: unknown, options: unknown,
      read: (producer?: Producer) => Promise<T>): Promise<T>;
  };
interface SubmissionTransport {
  exchange(operation: ClientHostOperation, body: Record<string, unknown>, signal?: AbortSignal,
    submitContext?: object, cancellationContext?: undefined, producer?: Producer): Promise<unknown>;
  responseValue(response: unknown, maxWireBytes?: number): unknown | Promise<unknown>;
  wasSubmissionDispatched(context: object): boolean;
  sourcePreparation?: SourcePreparation;
}
type AttemptWithoutOutcome = Extract<SubmissionAttempt, {kind: 'refused' | 'conflict'}>;

// Original request data is available only through explicit SDK access, never
// by serializing an error or Run handle. It does not establish acceptance.
const submissionInputs = new WeakMap<object, SubmissionSnapshot>();
// A private receipt records publication of an immutable caller-facing value.
// It owns no Host, Ledger, Prepared, or destination Promise reference. Host
// aliases remain separately funded until their actual retirement.
const snapshotPublications = new WeakMap<object, {body: CapturedBody; snapshot: SubmissionSnapshot}>();
export function matchesPublishedSubmissionSnapshot(receipt: unknown, body: unknown) {
  return snapshotPublications.get(receipt as object)?.body === body && body !== undefined;
}
const publishSnapshot = (destination: unknown, body: CapturedBody) => {
  const snapshot = submissionInputs.get(destination as object);
  if (snapshot === undefined || snapshot.input !== body.input ||
      snapshot.submissionRef !== body.submissionRef) return undefined;
  const receipt = Object.freeze({});
  snapshotPublications.set(receipt, {body, snapshot});
  return receipt;
};

const submissionOutcomes = new WeakMap<object, SubmissionOutcome>();

const submissionAttempts = new WeakMap<object, SubmissionAttempt>();

const submissionCheckObservations = new WeakMap<object, CheckOutcome>();

const submissionContexts = new WeakMap<object, SubmissionSnapshot>();
// Presentation is bound by the validated submit branch, never an error string.
const submissionExplanations = new WeakMap<object, ReturnType<typeof projectSubmissionExplanation> | ReturnType<typeof projectSubmissionAttemptExplanation> | ReturnType<typeof projectSubmissionLookupFailure> | ReturnType<typeof projectSubmissionNotSent> | ReturnType<typeof submissionLookupExplanation>>();

const requestLookupExplanations = new WeakMap<object, ReturnType<typeof projectRequestLookupExplanation> | ReturnType<typeof projectRequestLookupFailure>>();
// Keep this call's lookup target even when a found observation explains the
// Run instead. This association is not an admission record or replay grant.
const requestLookupContexts = new WeakMap<object, LookupInput>();

const requestCancellationExplanations = new WeakMap<object, ReturnType<typeof projectRequestCancellationExplanation>>();

export function getSubmissionCheckObservation(result: unknown): CheckOutcome | undefined {
  return submissionCheckObservations.get(result as object);
}

export function getSubmissionInput(result: unknown): SubmissionInput | undefined {
  return submissionInputs.get(result as object);
}

// Only an admitted response for this exact SDK operation supplies Owner facts.
export function getSubmissionOutcome(result: unknown): SubmissionOutcome | undefined {
  return submissionOutcomes.get(result as object);
}

export function getSubmissionAttempt(result: unknown): SubmissionAttempt | undefined {
  return submissionAttempts.get(result as object);
}

export function explainSubmission(result: unknown, options?: OperationExplanationOptions) {
  return localizeOperation(submissionExplanations.get(result as object), 'submission', options);
}

// Only this call's admitted lookup supplies Owner facts. A rejected observation
// retains its original lookup target, never unvalidated response fields.
export function explainRequestLookup(result: unknown, options?: OperationExplanationOptions) {
  return localizeOperation(requestLookupExplanations.get(result as object), 'request', options);
}

export function explainRequestCancellation(result: unknown, options?: OperationExplanationOptions) {
  return localizeOperation(requestCancellationExplanations.get(result as object), 'requestCancellation', options);
}

const retainSubmissionAttemptExplanation = <T extends object,>(result: T, attempt: AttemptWithoutOutcome, snapshot: Invocation): T => {
  requestLookupContexts.set(result, snapshot);
  submissionExplanations.set(result, projectSubmissionAttemptExplanation(result, attempt, snapshot));
  return result;
};

const retainSubmissionExplanation = <T extends object,>(result: T, outcome: SubmissionOutcome, context: SubmissionContext): T => {
  requestLookupContexts.set(result, context);
  submissionExplanations.set(result, projectSubmissionExplanation(result, outcome, context));
  return result;
};

const retainSubmissionLookupFailure = (cause: unknown, context: SubmissionContext, observation: Parameters<typeof projectSubmissionLookupFailure>[1]) => {
  let error;
  try {error = requestCancellationCause(cause);}
  catch {error = new ClientError('ClientTransportUnknown');}
  requestLookupContexts.set(error, context);
  submissionExplanations.set(error, projectSubmissionLookupFailure(context, observation));
  return error;
};

const retainRequestLookupExplanation = <T extends RequestLookup,>(answer: T, context: RequestContext): T => {
  requestLookupContexts.set(answer, context);
  requestLookupExplanations.set(answer, projectRequestLookupExplanation(answer, context));
  return answer;
};

const retainRequestLookupFailure = (error: unknown, context: RequestContext, observation: Parameters<typeof projectRequestLookupFailure>[1]) => {
  // Borrowed exceptions may be reused by credentials or a Local port. Each
  // call owns its error; code/status are metadata, never outcome evidence.
  const code = error instanceof ClientError ? error.code : 'ClientTransportUnknown';
  const status = error instanceof ClientError ? error.status : undefined;
  const retained = new ClientError(code,
    Number.isInteger(status) && (status as number) >= 100 && (status as number) <= 599 ? {status} : {});
  requestLookupContexts.set(retained, context);
  requestLookupExplanations.set(retained, projectRequestLookupFailure(context, observation));
  return retained;
};

const retainRequestCancellationExplanation = <T extends object,>(result: T, context: RequestContext,
  observation: Parameters<typeof projectRequestCancellationExplanation>[2], problem?: Parameters<typeof projectRequestCancellationExplanation>[3]): T => {
  requestCancellationExplanations.set(result, projectRequestCancellationExplanation(result as Parameters<typeof projectRequestCancellationExplanation>[0], context, observation, problem));
  return result;
};

const uninterpretableRequestCancellation = (context: RequestContext) => retainRequestCancellationExplanation(
  new ClientError('CancellationUnknown', {requestId: context.requestId,
    cause: new ClientError('InvalidHostRequestCancellation')}),
  context, 'outcome_unknown', 'response_uninterpretable');

const recoveryData = (value: unknown, keys: readonly string[]): Record<string, unknown> | undefined => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) return undefined;
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== keys.length ||
      keys.some(key => !Object.hasOwn(fields, key) ||
        !Object.hasOwn(fields[key], 'value'))) return undefined;
  return Object.fromEntries(keys.map(key => [key, fields[key].value]));
};

const requestRecoveryTarget = (value: unknown) => {
  const retained = submissionInputs.get(value as object) ?? requestLookupContexts.get(value as object);
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

export const submissionUnknown = (context: object | undefined, cause: unknown) => {
  const result = new ClientError('SubmissionUnknown', {...context, cause});
  const input = submissionContexts.get(context as object);
  if (input) submissionInputs.set(result as object, input);
  if (input) submissionExplanations.set(result,
    submissionLookupExplanation('acceptance_unknown', input));
  return result;
};

export const submissionNotSent = (context: object | undefined, cause: unknown) => {
  const result = new ClientError('SubmissionNotSent', {...context, cause});
  const input = submissionContexts.get(context as object);
  if (input) submissionInputs.set(result as object, input);
  if (input) submissionExplanations.set(result, projectSubmissionNotSent(input));
  return result;
};

// The Host accepted and durably holds the request, but no Run exists yet:
// it waits on a `prepare_attempt` Checkpoint, is resuming, or ended without
// a Run. This is a control result, not a failure and not an unknown
// submission: submitting again is never needed. Follow it with
// `lookupRequest(requestId)`; once the Run exists the lookup is `found`.
export {RequestHeld};

export function createSubmissionOperations(selected: SelectedConnection, confirmed: ConfirmedProfile,
  transport: SubmissionTransport, execution: (admission: WireClientAdmission) => Execution,
  lifecycle: ReturnType<typeof createClientLifecycle>): SubmissionOperations {
  const {exchange, responseValue, wasSubmissionDispatched, sourcePreparation} = transport;
  const {isClosed} = lifecycle;
  const withSourceProducer = <T,>(kind: 'aql' | 'program', originalInput: unknown, originalOptions: unknown,
    run: (producer?: Producer) => Promise<T>, acquire?: () => unknown, staticRead = false): Promise<T> => {
    // A closed SDK connection owns its local refusal. Do not reacquire a
    // producer from the already retired Host merely to reject this call.
    // The ordinary submit path retains its original identity/NotSent handling.
    if (sourcePreparation === undefined || isClosed()) return run(undefined);
    let producer: Producer;
    try {
      // Synchronous admission precedes the first SDK capture, option getter,
      // serialization, hash or Promise workspace of this submitted original.
      const receipt = acquire === undefined
        ? sourcePreparation!.beforeSourceSnapshot(kind, originalInput, originalOptions, selected.wire)
        : acquire();
      producer = {receipt, body: undefined};
    } catch (cause) {return Promise.reject(cause);}
    const finish = (terminal: 'returned' | 'failed', primary: unknown, originalResult?: T) => {
      // The caller-facing snapshot has its own SDK value association. This
      // private producer keeps only its original cleanup receipt from now on.
      producer.body = undefined;
      try {sourcePreparation!.finishSourceProducer(producer.receipt, terminal);}
      catch (cause) {
        // Reuse this connection's existing cleanup owner. A retry cuts only
        // the same producer aliases, never snapshots, sends or issues again.
        const retry = () => sourcePreparation!.finishSourceProducer(producer.receipt, terminal);
        lifecycle.readerCleanups.add(retry);
        // A thrown undefined is still the original failed operation. Keep its
        // presence separate from a successful result with no primary error.
        if (terminal === 'failed') return primary;
        const error = new ClientError('ClientCleanupPending', {cause, cleanupPending: true});
        if (!staticRead) Object.defineProperty(error, 'execution', {value: originalResult});
        retainQueryResult(originalResult, error);
        return error;
      }
      return primary;
    };
    let original: Promise<T>;
    try {original = run(producer);}
    catch (cause) {return Promise.reject(finish('failed', cause));}
    const pending = original.then(result => {
      const failure = finish('returned', undefined, result);
      if (failure !== undefined) throw failure;
      return result;
    }, cause => {throw finish('failed', cause);});
    retainQueryResult(original, pending);
    if (!staticRead && producer.body !== undefined) {
      const publication = publishSnapshot(pending, producer.body);
      if (publication !== undefined) {
        try {sourcePreparation!.publishSourceSnapshot(producer.receipt, producer.body, publication);}
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
  const submitIntent = (kind: 'aql' | 'program', input: CapturedBody['input'], options: CallOptions,
    sourceProducer?: Producer, requestName?: string): Promise<Execution> => {
    let body: CapturedBody, captured: unknown, original: unknown;
    // Trusted Source failures retain their exact original carrier, outside
    // the catch which classifies ordinary native serialization failures.
    if (sourceProducer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(sourceProducer.receipt);
    try {
      const stopBefore = options.stopBefore;
      const readOnly = options.readOnly;
      const executionProfile = options.executionProfile;
      if (stopBefore !== undefined && stopBefore !== 'commit') fail('InvalidClientPayload');
      if (Object.hasOwn(options, 'readOnly') && readOnly !== true) fail('InvalidClientPayload');
      if (Object.hasOwn(options, 'executionProfile') && executionProfile !== 'debug') fail('InvalidClientPayload');
      original = {submissionRef: options.submissionRef,
        attemptRef: {operation: 'submit', attemptId: options.attemptId ?? crypto.randomUUID()},
        ...(requestName === undefined ? {} : {requestName}),
        kind, input, parameters: options.parameters ?? null,
        ...(stopBefore === undefined ? {} : {stopBefore}),
        ...(readOnly === undefined ? {} : {readOnly}),
        ...(executionProfile === undefined ? {} : {executionProfile}),
        ...(options.unresolvedHistory === undefined ? {} : {unresolvedHistory: options.unresolvedHistory})};
    } catch {fail('InvalidClientPayload');}
    let snapshotCalled = false, originalSnapshot: unknown;
    const captureSnapshot = (value: unknown, observe?: Parameters<typeof snapshotClientRequest>[1]) => {
      if (snapshotCalled || value !== original) fail('InvalidHostSourceSnapshot');
      snapshotCalled = true;
      let resourceFailed = false, resourceCause: unknown;
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
      : sourcePreparation!.captureSourceSnapshot(sourceProducer.receipt, original, captureSnapshot);
    if (!snapshotCalled || captured !== originalSnapshot) fail('InvalidHostSourceSnapshot');
    // Native getters/toJSON/coercion may retire the original installation or
    // producer while the one snapshot is built. Stop before freeze arrays or
    // publication; do not bind an unfrozen body to bypass the original check.
    if (sourceProducer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(sourceProducer.receipt);
    try {body = freezeInput(captured) as CapturedBody;} catch {fail('InvalidClientPayload');}
    if (sourceProducer !== undefined) {
      sourcePreparation!.bindSourceSnapshot(sourceProducer.receipt, body);
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
      if (body.executionProfile === 'debug' &&
          !confirmed.capabilities.includes('debug-operation-boundaries')) {
        // The original input remains observable. This local negotiated
        // capability refusal sends nothing and claims no Host acceptance.
        throw submissionNotSent(context, new ClientError('ClientExecutionProfileUnsupported'));
      }
      let intentCid;
      try {intentCid = sourceProducer === undefined ? await bytesCid(new TextEncoder().encode(canonicalJson({
        intent: {kind, input: body.input, parameters: body.parameters,
          ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
          ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {}),
          ...(Object.hasOwn(body, 'executionProfile') ? {executionProfile: body.executionProfile} : {})},
        version: 'actql-submitted-intent/0.1'}, {dataKeys: true}))) :
        await sourcePreparation!.intentCid(sourceProducer.receipt, body);}
      catch (cause) {throw submissionNotSent(context, cause);}
      let outcome: (SubmissionOutcome & {checkObservation?: CheckOutcome}) | undefined;
      let attempt: SubmissionAttempt;
      let typedRejection;
      let checkObservation;
      try {
        const operation = requestName !== undefined ? 'submit-named-intent'
          : body.unresolvedHistory === undefined ? 'submit-intent' : 'restart-intent';
        const response = await exchange(operation,
          {...body, intentCid}, options.signal, context, undefined, sourceProducer);
        attempt = captureResponse(await controlValue(response)) as SubmissionAttempt;
        if (!(requestName === undefined
          ? validSubmissionAttempt(attempt, selected.wire, body.submissionRef, intentCid,
            body.attemptRef, body.unresolvedHistory)
          : validNamedSubmissionAttempt(attempt, selected.wire, requestName,
            body.submissionRef, intentCid, body.attemptRef))) {
          fail('InvalidHostSubmissionOutcome');
        }
        attempt = freezeInput(attempt);
        outcome = (attempt as SubmissionAttempt & {outcome?: SubmissionOutcome}).outcome;
        if (outcome === undefined) {
          // A typed initial refusal or conflict is not the durable original's
          // receipt and supplies no automatic retry or new-submission grant.
          typedRejection = new ClientError(attempt.kind === 'refused' ? 'SubmissionRefused'
            : requestName === undefined ? 'SubmissionConflict' : 'RequestConflict',
            {...context, outcome: attempt});
          submissionInputs.set(typedRejection, snapshot);
          submissionAttempts.set(typedRejection, attempt);
          retainSubmissionAttemptExplanation(typedRejection, attempt as AttemptWithoutOutcome, snapshot);
          throw typedRejection;
        }
        // The submitted candidate remains the exact captured input. Only this
        // correlated original reply supplies a durable reference for lookup;
        // a scoped name may legitimately resolve an earlier epoch.
        context.submissionRef = outcome.submissionRef;
        if (outcome.checkObservation !== undefined) {
          checkObservation = outcome.checkObservation;
          if (!(body.kind === 'program' || body.kind === 'aql' && ['sql', 'aql', 'aql-text'].includes(body.input.format as string)) ||
              !bindCheckObservation(checkObservation as Parameters<typeof bindCheckObservation>[0], {kind: body.kind, input: body.input, parameters: body.parameters} as Parameters<typeof bindCheckObservation>[1])) {
            fail('InvalidHostSubmissionCheckObservation');
          }
          // The validated attempt retains its complete original observation;
          // the public outcome omits only this separately held presentation.
          const {checkObservation: _checkObservation, ...publicOutcome} = outcome;
          outcome = Object.freeze(publicOutcome);
        }
      } catch (cause) {
        if (typedRejection !== undefined && cause === typedRejection) throw cause;
        if ((cause as {code?: unknown} | null | undefined)?.code === 'SubmissionUnknown' || (cause as {code?: unknown} | null | undefined)?.code === 'SubmissionNotSent') throw cause;
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
      if (requestName !== undefined) (error as ClientError & {requestName?: string}).requestName = requestName;
      submissionInputs.set(error, snapshot);
      submissionOutcomes.set(error, outcome);
      submissionAttempts.set(error, attempt);
      if (checkObservation !== undefined) {
        submissionCheckObservations.set(error, freezeInput(checkObservation));
        // Point to this SAME already-bound report. Do not serialize original
        // Source, invent a cause from an error code, or issue another check.
        const problem = (outcome as {problem?: {code: string}}).problem?.code;
        error.message = `${error.code}: phase=${outcome.kind}` +
          (problem === undefined ? '' : `; problem=${problem}`) +
          '. Inspect formatCheckOutcome(getSubmissionCheckObservation(error)) for the original check diagnostics.';
      } else if ((outcome as {problem?: {code: string}}).problem?.code !== undefined) {
        // Display the already-admitted DATA only. Neither the phase nor the
        // code's spelling authorizes retry or changes the typed observation.
        error.message = `${error.code}: phase=${outcome.kind}; problem=${(outcome as {problem: {code: string}}).problem.code}`;
      }
      retainSubmissionExplanation(error, outcome, snapshot);
      throw error;
    })();
    submissionInputs.set(pending, snapshot);
    return pending;
  };
  const newSubmission: Client['newSubmission'] = ({nonce = crypto.randomUUID()} = {}) => {
    if (confirmed.submissionEpoch === undefined) fail('SubmissionEpochUnavailable');
    const ref = freezeInput(snapshotClientRequest({epoch: confirmed.submissionEpoch, nonce}));
    if (!validSubmissionRef(ref)) fail('InvalidSubmissionRef');
    return ref;
  };
  const submit = (kind: 'aql' | 'program', input: CapturedBody['input'], options: CallOptions = {}, sourceProducer?: Producer) => {
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
  const submitSource = (text: string, options: CallOptions | undefined, sourceProducer?: Producer) => {
    // Preserve omission at the actual before-copy boundary. This SDK-owned
    // default belongs after the selected original admission, not before it.
    if (options === undefined) options = {};
    if (typeof text !== 'string' || !text ||
        !clientSourceFormats.includes(options.format as ClientSourceFormat)) {
      return Promise.reject(new ClientError('InvalidAqlDocument'));
    }
    if (options.parameterDeclarations !== undefined &&
        !['aql', 'aql-text', 'sql'].includes(options.format as string)) {
      return Promise.reject(new ClientError('InvalidAqlDocument'));
    }
    return submit('aql', {text, format: options.format,
      ...(options.parameterDeclarations === undefined ? {} :
        {parameterDeclarations: options.parameterDeclarations})}, options, sourceProducer);
  };
  const startSource: Client['startSource'] = (text, options) => withSourceProducer('aql', text, options,
    producer => submitSource(text, options, producer));
  const captureQueryAdmission = sourcePreparation === undefined ? undefined
    : (format: Parameters<typeof sourceQuery>[4], text: string, parameters: unknown, options: Parameters<typeof sourceQuery>[7],
      capture: (submit: Client['startSource']) => Promise<Execution>) => withSourceProducer('aql', text, options,
      producer => capture((originalText, sourceOptions) => submitSource(originalText, sourceOptions, producer)),
      () => sourcePreparation!.beforeSourceQuery(format, text, parameters, options, selected.wire));
  const retainQueryResult = (execution: unknown, result?: unknown) => {
    const input = submissionInputs.get(execution as object);
    if (input && result !== undefined) submissionInputs.set(result as object, input);
    const outcome = submissionOutcomes.get(execution as object);
    if (outcome && result !== undefined) submissionOutcomes.set(result as object, outcome);
    const attempt = submissionAttempts.get(execution as object);
    if (attempt && result !== undefined) submissionAttempts.set(result as object, attempt);
    return input;
  };
  const retainQueryFailure = (execution: Execution, error: ClientError, cause?: unknown) => {
    retainQueryResult(execution, error);
    // Only an existing SDK-owned observation supplies explanatory facts.
    // Error codes, copied causes and validated failed states supply none.
    copyRunObservationFailure(cause, error);
  };
  let client: SubmissionOperations;
  client = Object.freeze<SubmissionOperations>({
    // Private assembly port only. A static read shares original preparation
    // and cleanup, but issues no submission identity/publication or Run.
    withStaticPreparation: (kind, input, options, read) =>
      withSourceProducer(kind, input, options, read, undefined, true),
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
      const target = freezeInput(captured) as RequestLookupTarget;
      const found = new WeakSet();
      return Object.freeze<RequestRecovery>({target,
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
            cause.code !== 'ClientTransportUnknown' && !((cause.status as number) >= 500)
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
