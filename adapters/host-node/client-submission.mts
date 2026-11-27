// Public submission facts live in the existing request journal. This adapter
// neither dispatches tasks nor infers nonexecution from a missing Run record.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {requestProgramPreparationProblemCode, requestProgramPreparationRefusalCode} from './client-program-preparation.mjs';
import {validSubmissionRef, validSubmissionOutcome, validSubmissionLookup,
  isClientSubmitRejection, validCheckOutcome, validOperationAttemptRef,
  validSubmissionName, validNamedSubmissionAttempt} from '../../packages/client-wire/index.mjs';

import type {WireCheckOutcome, WireClientBodyByOperation, WireConnection, WireNamedSubmissionAttempt, WireOperationAttemptRef,
  WireRequestLookup, WireRunRef, WireSubmissionAttempt, WireSubmissionLookup, WireSubmissionOutcome, WireSubmissionRef,
  WireSubmissionRestart, WireSubmitReply} from '../../packages/client-wire/index.js';
import {originalModelPlanReplayRefusal, rejectModelPlanReplay} from './installed-model-originals.mjs';
import type {openClientRequestJournal} from './client-request-journal.mjs';
import type {installLocalPreparationRegistry} from './local-preparation-registry.mjs';

type RequestJournal = ReturnType<typeof openClientRequestJournal>;
type Journal = Pick<RequestJournal, 'issueSubmissionEpoch' | 'retainSubmissionOperation' | 'prepareSubmittedIntent' |
  'lookup' | 'checkSubmittedIntent' | 'recordSubmittedIntent' | 'lookupSubmittedIntent' | 'completeSubmittedIntent' |
  'verifySubmissionEpoch' | 'submissionIdentity' | 'checkSubmissionAttempt' | 'recordSubmissionAttempt' |
  'resolveNamedSubmissionAttempt'>;
type Core = Parameters<Journal['recordSubmittedIntent']>[3] & Parameters<Journal['lookup']>[1] &
  Parameters<Journal['prepareSubmittedIntent']>[2] & Parameters<Journal['retainSubmissionOperation']>[1];
type Retained = NonNullable<ReturnType<Journal['lookupSubmittedIntent']>>;
type Scope = Readonly<{authorityScopeCid: string; namespaceId: string; currentAuthorization: true}>;
type ScopeCandidate = Readonly<{authorityScopeCid?: unknown; namespaceId?: unknown}> | undefined;
type Actor = Readonly<{principalId: string; connection: WireConnection}>;
type LookupRequest = Readonly<Actor & WireClientBodyByOperation['lookup-submission']>;
type Intent = WireClientBodyByOperation['submit-intent'];
type SubmitRequest = Readonly<Actor & Intent & Partial<Pick<WireClientBodyByOperation['submit-named-intent'],
  'stopBefore' | 'readOnly'>> & Partial<Pick<WireClientBodyByOperation['restart-intent'], 'unresolvedHistory'>>>;
type AttemptRequest = SubmitRequest & Readonly<{attemptRef: WireOperationAttemptRef}>;
type NamedRequest = Readonly<Actor & WireClientBodyByOperation['submit-named-intent']>;
type PrepareRequest = SubmitRequest & Readonly<{requestId: string}>;
type Submission = PrepareRequest & Readonly<{preparedProgram: unknown;
  submission?: WireSubmissionRef & Readonly<{intentCid: string; currentAuthorization: boolean}>}>;
type MaybePromise<Result> = Result | PromiseLike<Result>;
type SelectedScope = (request: Actor) => MaybePromise<ScopeCandidate>;
type EpochOptions = Readonly<{journal: Pick<Journal, 'issueSubmissionEpoch'>;
  moon: Parameters<Journal['issueSubmissionEpoch']>[1]; authorizedScope: SelectedScope}>;
type Custody = Pick<ReturnType<typeof installLocalPreparationRegistry>,
  'copy' | 'read' | 'attach' | 'capture' | 'adopt' | 'finishHandler'>;
type Prepare = ((request: PrepareRequest) => MaybePromise<object>) &
  Readonly<{assertSubmittedIntent?(prepared: unknown, intent: unknown): unknown}>;
type PreparationCheck = Readonly<Actor & {kind: 'program' | 'text'; scope: 'bound_input';
  input: SubmitRequest['input']; parameters: unknown}>;
type Installation = Readonly<EpochOptions & {journal: Journal; moon: Core; prepareSubmit: Prepare;
  submit(request: Submission, replayRef?: WireRunRef): MaybePromise<WireSubmitReply>;
  retainedModelReplay?(request: Actor, ref: WireRunRef): boolean;
  lookupRequest(request: Actor & Readonly<{requestId: string}>): MaybePromise<WireRequestLookup>;
  checkSubmissionInput?(request: PreparationCheck): MaybePromise<WireCheckOutcome | undefined>;
  observeOriginalPreparationFailure?(failure: unknown, request: SubmitRequest): MaybePromise<unknown>;
  bindOwnedRequest?(parent: object, derived: object): unknown;
  admitPreparedSubmission?(request: Submission | undefined): unknown;
  preparationCustody?: Custody;
  submittedIntentOriginal?(request: Actor): unknown;
}>;
type AttemptFields = Scope & Readonly<{actorId: string; unresolvedHistory?: WireSubmissionRestart}>;
type RecordFields = AttemptFields & Readonly<{phase?: string; outcome?: WireSubmissionOutcome}>;
type Attempt = Readonly<{fields: Scope;
  observe(retained: Retained | undefined): void;
  rejectModelReplay(issue: NonNullable<ReturnType<typeof originalModelPlanReplayRefusal>>): never;
  check(ref: WireSubmissionRef, intent: unknown, options: AttemptFields): void;
  record(ref: WireSubmissionRef, intent: unknown, options: RecordFields): Retained;
}>;
type AttemptResult = ReturnType<Journal['recordSubmissionAttempt']>;
type AttemptWithSubmission = Extract<AttemptResult, {submission: unknown}>;
type RecordedAttempt = AttemptWithSubmission & Readonly<{submission: Retained}>;
type ObservedAttempt = Readonly<{kind: 'recorded' | 'already_satisfied'; attemptRef: WireOperationAttemptRef;
  outcome: WireSubmissionLookup}>;
type RejectedAttempt = Extract<WireSubmissionAttempt, {kind: 'refused' | 'conflict'}>;
type SubmissionService = Readonly<{
  submitIntent(request: SubmitRequest): Promise<WireSubmissionLookup>;
  submitAttempt(request: AttemptRequest): Promise<AttemptResult | ObservedAttempt | RejectedAttempt>;
  submitNamedAttempt(request: NamedRequest): Promise<WireNamedSubmissionAttempt>;
  lookupSubmission(request: LookupRequest): Promise<WireSubmissionLookup>;
  issueEpoch(request: Actor): Promise<ReturnType<Journal['issueSubmissionEpoch']>>;
}>;
type Ready = Extract<WireSubmissionOutcome, {kind: 'ready'}>;
type Disclosed = WireSubmissionLookup & Readonly<{checkObservation?: WireCheckOutcome}>;
type ProblemOutcome = Extract<WireSubmissionOutcome, {kind: 'not_accepted' | 'preparation_failed'}>;
type RunKey = keyof WireRunRef;
type Failure = Readonly<{code?: string; cleanupPending?: unknown; cleanupHandle?: unknown}> | null | undefined;
type Report = Extract<WireCheckOutcome, {outcome: 'completed'}>['report'];
type ReportFields = Readonly<{report?: Report; partial_report?: Report}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const classification = (code?: string): ProblemOutcome['problem']['classification'] => ({
  ClientProgramInvalidInput: 'invalid_input', ClientParametersInvalid: 'invalid_input',
  ClientProgramNeedsInputs: 'requirements', ClientProgramUnsupported: 'implementation_limit',
  ClientParametersTooLarge: 'implementation_limit', ClientProgramAnalysisLimit: 'implementation_limit',
  ClientProgramImplementationLimit: 'implementation_limit', ClientProgramRejected: 'operation_failed',
} as Readonly<Partial<Record<string, ProblemOutcome['problem']['classification']>>>)[code!] ?? 'operation_failed';
const immutable = <Value,>(value: Value): Value => {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) immutable(child);
    Object.freeze(value);
  }
  return value;
};
const scopeFields = (selected: ScopeCandidate): Scope => {
  const authorityScopeCid = selected?.authorityScopeCid;
  const namespaceId = selected?.namespaceId;
  if (typeof authorityScopeCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(authorityScopeCid) ||
      typeof namespaceId !== 'string' || !namespaceId) fail('ClientRequestLookupDenied');
  return {authorityScopeCid, namespaceId, currentAuthorization: true};
};
const snapshot = <Value extends Actor>(value: Value): Value => immutable(JSON.parse(canonicalJson(value, {dataKeys: true})) as Value);

// The same Journal-owned epoch operation is available before optional Result
// and Model services are constructed. This issues no Run, Account or Store
// permission and keeps the original authenticated scope and packet snapshot.
export async function issueNodeClientSubmissionEpoch({journal, moon, authorizedScope}: EpochOptions, request: Actor) {
  return journal.issueSubmissionEpoch(scopeFields(await authorizedScope(snapshot(request))), moon);
}

export function installNodeClientSubmission({journal, moon, authorizedScope,
  prepareSubmit, submit, lookupRequest, checkSubmissionInput, observeOriginalPreparationFailure,
  bindOwnedRequest, admitPreparedSubmission, preparationCustody, submittedIntentOriginal, retainedModelReplay}: Installation): SubmissionService {
  if (typeof journal?.recordSubmittedIntent !== 'function' ||
      typeof journal?.checkSubmittedIntent !== 'function' ||
      typeof moon?.clientSubmittedIntent !== 'function' ||
      [authorizedScope, prepareSubmit, submit, lookupRequest].some(value => typeof value !== 'function') ||
      bindOwnedRequest !== undefined && typeof bindOwnedRequest !== 'function' ||
      admitPreparedSubmission !== undefined && typeof admitPreparedSubmission !== 'function' ||
      checkSubmissionInput !== undefined && typeof checkSubmissionInput !== 'function' ||
      observeOriginalPreparationFailure !== undefined && typeof observeOriginalPreparationFailure !== 'function' ||
      submittedIntentOriginal !== undefined && typeof submittedIntentOriginal !== 'function' ||
      retainedModelReplay !== undefined && typeof retainedModelReplay !== 'function') {
    throw new TypeError('InvalidClientSubmissionInstallation');
  }
  const copyRequest = <Value extends Actor, Changes extends Readonly<Record<string, unknown>>>(value: Value, changes: Changes): Value & Changes => preparationCustody === undefined
    ? {...value, ...changes} : preparationCustody.copy(value, changes) as Value & Changes;
  const preparedValue = (value: unknown) => preparationCustody === undefined ? value : preparationCustody.read(value);
  const preparedSubmission = (value: PrepareRequest, prepared: unknown): Submission => preparationCustody === undefined
    ? {...value, preparedProgram: prepared}
    : preparationCustody.attach(value, prepared);
  const flights = new Map<string, Promise<WireSubmissionLookup>>();
  const ownedSnapshots = new WeakSet<object>();
  // The installed callback and its own original projection are one port.
  // A public-looking code, inherited method or later property replacement is
  // not the Host's retained same-call preparation refusal.
  const refusalProperty = admitPreparedSubmission === undefined ? undefined :
    Object.getOwnPropertyDescriptor(admitPreparedSubmission, 'isOriginalPreparationRefusal');
  const originalPreparationRefusal = refusalProperty !== undefined &&
      Object.hasOwn(refusalProperty, 'value') && typeof refusalProperty.value === 'function'
    ? refusalProperty.value : undefined;
  const authorize = async (value: Actor) => scopeFields(await authorizedScope(value));
  const own = <Value extends object>(parent: object, derived: Value): Value => {
    if (bindOwnedRequest !== undefined && bindOwnedRequest(parent, derived) !== undefined) {
      fail('SourceManagedPreparationUnavailable');
    }
    return derived;
  };
  const captureSnapshot = <Value extends Actor>(value: Value, bind = true): Value => {
    const raw = snapshot(value);
    const selected = preparationCustody === undefined ? raw : preparationCustody.capture(raw);
    const captured = bind ? own(value, selected) : selected;
    ownedSnapshots.add(captured);
    return captured as Value;
  };
  const ownedSnapshot = <Value extends Actor>(value: Value): Value => ownedSnapshots.has(value) ? value : captureSnapshot(value);
  const operation = <Value extends LookupRequest, Result>(action: (value: Value) => MaybePromise<Result>, bind = true) => async (request: Value) => {
    const value = captureSnapshot(request, bind);
    let release;
    try {
      release = validSubmissionRef(value.submissionRef) ?
        journal.retainSubmissionOperation?.(value.submissionRef.epoch, moon,
          bind ? submittedIntentOriginal?.(value) : undefined) : undefined;
      return await action(value);
    }
    finally {
      try {release?.();} finally {preparationCustody?.finishHandler(value);}
    }
  };
  const prepareOwned = (value: SubmitRequest, requestId: string) => {
    const request = own(value, copyRequest(value, {requestId}));
    const prepared = prepareSubmit(request);
    // Preserve the unselected caller's original single await. Only the
    // selected Source retains an additional continuation for its nominal
    // returned handle; that continuation issues no capacity or permission.
    return bindOwnedRequest === undefined ? (preparationCustody === undefined ? prepared :
      Promise.resolve(prepared).then(original => preparationCustody.adopt(original, request))) :
      Promise.resolve(prepared).then(original => {
        own(request, original);
        return preparationCustody === undefined ? original : preparationCustody.adopt(original, request);
      });
  };
  const unresolved = (submissionRef: WireSubmissionRef,
    code: Extract<WireSubmissionLookup, {kind: 'unresolvable'}>['problem']['code'] = 'submission_history_unresolvable') =>
    immutable({kind: 'unresolvable' as const, submissionRef, problem: {code}});
  const withRestart = <Value extends WireSubmissionLookup>(outcome: Value, retained: Retained): Value => retained.unresolvedHistory === undefined ? outcome
    : immutable({...outcome, unresolvedHistory: {
      submissionRef: retained.unresolvedHistory.submissionRef,
      acknowledgement: retained.unresolvedHistory.acknowledgement}});
  const storedOutcome = (retained: Retained): WireSubmissionLookup => withRestart(retained.outcome ?? immutable({kind: 'preparing' as const,
    submissionRef: retained.submissionRef, intentCid: retained.intentCid}), retained);
  // Match the existing SDK observation input contract. Other Source formats
  // retain their actual preparation outcome without an unsupported report.
  const supportsCheckObservation = (intent: Pick<SubmitRequest, 'kind' | 'input'>) => intent.kind === 'program' ||
    intent.kind === 'aql' && ['sql', 'aql', 'aql-text'].includes((intent.input as Extract<WireClientBodyByOperation['submit'], {kind: 'aql'}>['input']).format);
  const discloseOutcome = async (value: Actor, outcome: Disclosed & {problem?: Readonly<{code: string}>},
    fields: Scope, retained: Pick<Retained, 'intentWire'>, originalObservation?: WireCheckOutcome | null): Promise<Disclosed> => {
    if (!['not_accepted', 'preparation_failed'].includes(outcome.kind)) return outcome;
    const projectsProblem = outcome.problem!.code === 'ClientProgramInvalidInput' ||
      outcome.problem!.code === 'ClientProgramParameterUndeclared' ||
      outcome.problem!.code === 'ClientProgramTimestampPatternInvalid' ||
      outcome.problem!.code === 'ClientProgramAggregateOrderRequired' ||
      outcome.problem!.code === 'ClientProgramOrderUnresolved' ||
      outcome.problem!.code === 'ClientSuppliedParameterUndeclared' ||
      outcome.problem!.code === 'ClientProgramAnalysisLimit' ||
      outcome.problem!.code === 'ClientProgramImplementationLimit';
    if (!projectsProblem && originalObservation === undefined) return outcome;
    // The durable problem describes the original preparation, not a new check.
    // Reuse original journal custody and the installed disclosure-aware checker
    // before showing a Source-dependent input classification to this audience.
    const intent = immutable(JSON.parse(retained.intentWire) as Intent);
    if (!supportsCheckObservation(intent)) {
      if (originalObservation !== undefined) {
        const current = await authorize(value);
        if (current.authorityScopeCid !== (fields as Scope).authorityScopeCid ||
            current.namespaceId !== (fields as Scope).namespaceId) fail('ClientRequestLookupDenied');
      }
      return outcome;
    }
    let disclosable = !projectsProblem;
    try {
      // A fresh failed Request still owns its original checked result. Null
      // means its projection is unavailable, never permission to check again.
      // Only a later retained lookup has no such original and uses the existing
      // current-audience check-only boundary; it never prepares or starts a Run.
      const report = originalObservation !== undefined ? originalObservation :
        !projectsProblem ? undefined : await checkSubmissionInput?.({principalId: value.principalId,
        connection: value.connection, kind: intent.kind === 'program' ? 'program' : 'text',
        scope: 'bound_input', input: intent.input, parameters: intent.parameters});
      const observed = (report as ReportFields | null | undefined)?.report ?? (report as ReportFields | null | undefined)?.partial_report;
      disclosable = !projectsProblem || validCheckOutcome(report) && (
        outcome.problem!.code === 'ClientProgramInvalidInput' ||
        outcome.problem!.code === 'ClientProgramParameterUndeclared' ||
        outcome.problem!.code === 'ClientProgramTimestampPatternInvalid' ||
        outcome.problem!.code === 'ClientProgramAggregateOrderRequired' ||
        outcome.problem!.code === 'ClientProgramOrderUnresolved' ||
        outcome.problem!.code === 'ClientSuppliedParameterUndeclared'
        ? observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid'
        : observed?.scope.kind === 'bound_input' && observed.coverage.limits.some(
          limit => limit.code === (outcome.problem!.code === 'ClientProgramAnalysisLimit'
            ? 'analysis_budget_exhausted' : 'implementation_limit')));
      // A protected Program dependency can change preparation's coarse cause.
      // Keep the original operation terminal, but do not reveal that private
      // distinction through its Problem even when independent input facts exist.
      if (projectsProblem && intent.kind === 'program' && observed?.coverage.unresolved.length! > 0) disclosable = false;
    } catch {
      // A failed reporting attempt neither changes acceptance nor establishes
      // disclosure. No error text or HTTP status supplies a check verdict.
    }
    const current = await authorize(value);
    if (current.authorityScopeCid !== fields.authorityScopeCid ||
        current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
    const projected = disclosable ? outcome : {...outcome,
      problem: {code: 'ClientProgramRejected' as const, classification: 'operation_failed' as const}};
    // This separate current disclosure check can gate the stored Problem,
    // but is never the original preparation's transient CheckOutcome.
    return immutable(projected) as Disclosed;
  };
  const refresh = async (value: Actor, retained: Retained, fields: Scope): Promise<WireSubmissionLookup> => {
    if (['not_accepted', 'preparation_failed'].includes(retained.phase)) return storedOutcome(retained);
    const found = await lookupRequest(copyRequest(value, {requestId: retained.requestId}));
    // Revalidate current authority after the async lookup before changing facts.
    const current = await authorize(value);
    if (current.authorityScopeCid !== fields.authorityScopeCid ||
        current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
    let outcome: WireSubmissionOutcome;
    if (found.kind === 'found') {
      // Public request lookup names the Run but carries no control revision.
      // Obtain that fact from the same authorized journal record, never invent
      // a revision while projecting an admission response.
      const admitted = journal.lookup({namespaceId: current.namespaceId,
        authorityScopeCid: current.authorityScopeCid, requestId: retained.requestId}, moon);
      if (admitted === undefined || ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .some(key => admitted.ref[key as RunKey] !== found.ref[key as RunKey])) return unresolved(retained.submissionRef);
      if (retained.phase === 'ready') return storedOutcome(retained);
      outcome = {kind: 'ready', submissionRef: retained.submissionRef,
        intentCid: retained.intentCid, admission: {ref: admitted.ref,
          durability: admitted.durability, revision: admitted.revision}};
    }
    else if (found.kind === 'held') outcome = {kind: 'held', submissionRef: retained.submissionRef,
      intentCid: retained.intentCid, held: {...found, requestId: retained.submissionRef.nonce}};
    else if (found.kind === 'unknown' || retained.phase === 'ready' || retained.phase === 'held') {
      return unresolved(retained.submissionRef);
    } else return storedOutcome(retained);
    const updated = journal.completeSubmittedIntent(retained.submissionRef, outcome,
      {...current, connection: value.connection, expectedRevision: retained.revision}, moon);
    return storedOutcome(updated);
  };
  const lookupSubmission = async (request: LookupRequest): Promise<WireSubmissionLookup> => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = await authorize(value);
    let retained;
    try {retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon);}
    catch (error) {
      if (['ClientSubmittedIntentCorrupt', 'ClientSubmissionEpochCustodyLost',
        'ClientSubmissionRestartCorrupt', 'ClientSubmissionRestartCustodyLost'].includes((error as Failure)?.code!)) {
        return unresolved(value.submissionRef);
      }
      throw error;
    }
    const original = retained === undefined ? unresolved(value.submissionRef) : await refresh(value, retained, fields);
    const result = retained === undefined ? original : withRestart(
      await discloseOutcome(value, original, fields, retained), retained);
    if (!validSubmissionLookup(result, value.connection, value.submissionRef)) fail('InvalidClientHostSubmissionLookup');
    return result;
  };
  const assertOriginalPreparation = (prepared: unknown, input: unknown, value: SubmitRequest) => {
    if (typeof prepareSubmit.assertSubmittedIntent === 'function') {
      prepareSubmit.assertSubmittedIntent(preparedValue(prepared), input);
    } else if (Object.hasOwn(value, 'readOnly') || Object.hasOwn(value, 'executionProfile')) {
      // An installation without the original Common boundary cannot accept
      // this continuation choice. Older unselected installations are unchanged.
      fail('ClientProgramUnsupported');
    }
  };
  const replayReady = async (value: SubmitRequest, retained: Retained, fields: Scope, original: Ready, input: unknown,
    attempt?: Attempt): Promise<Ready> => {
    const requestId = retained.requestId, ref = original.admission.ref;
    const pending = flights.get(requestId);
    if (pending !== undefined && retainedModelReplay?.(value, ref) !== true) return original;
    // A ready receipt establishes acceptance, not physical dispatch. Only
    // explicit replay re-enters the existing Run owner; lookup stays read-only.
    const flight = pending ?? (async () => {
      let preparedProgram;
      try {
        preparedProgram = await prepareOwned(value, requestId);
        assertOriginalPreparation(preparedProgram, input, value);
      }
      catch (error) {
        if (!isClientSubmitRejection((error as Failure)?.code)) throw error;
        if (retainedModelReplay?.(value, ref) === true) {
          rejectModelPlanReplay(ref, 'model_provider_selection_unavailable');
        }
        // Current execution support cannot replace an already accepted intent.
        // Re-read through the same authorized owner after the awaited failure:
        // lost authority or custody is not permission to return a stale receipt.
        const observed = await lookupSubmission(value);
        if (observed.kind !== 'ready') fail('ClientSubmissionUnresolvable');
        if (observed.intentCid !== original.intentCid ||
            ['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].some(
              key => observed.admission.ref[key as RunKey] !== original.admission.ref[key as RunKey])) {
          fail('InvalidClientHostSubmissionOutcome');
        }
        return observed;
      }
      const current = await authorize(value);
      if (current.authorityScopeCid !== fields.authorityScopeCid ||
          current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
      const reply = await submit(own(value, preparedSubmission(copyRequest(value, {requestId,
        submission: {epoch: value.submissionRef.epoch, nonce: value.submissionRef.nonce,
          intentCid: value.intentCid, currentAuthorization: true}}), preparedProgram)), ref);
      const observed = await authorize(value);
      if (observed.authorityScopeCid !== fields.authorityScopeCid ||
          observed.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
      if ((reply as Partial<Extract<WireSubmitReply, {kind: 'held'}>>).kind === 'held' || ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .some(key => (reply as Partial<WireSubmitReply & {ref: WireRunRef}>).ref?.[key as RunKey] !== original.admission.ref[key as RunKey])) {
        fail('InvalidClientHostSubmissionOutcome');
      }
      // Dispatch revalidation cannot replace an immutable acceptance receipt,
      // including when the existing owner refuses a changed Source binding.
      return original;
    })().finally(() => {if (flights.get(requestId) === flight) flights.delete(requestId);});
    if (pending === undefined) flights.set(requestId, flight);
    try {
      const observed = await flight;
      if (observed.kind !== 'ready' ||
          observed.admission.ref.runDefinitionCid !== ref.runDefinitionCid ||
          observed.admission.ref.namespaceId !== ref.namespaceId ||
          observed.admission.ref.authorityScopeCid !== ref.authorityScopeCid) fail('InvalidClientHostSubmissionOutcome');
      return observed;
    } catch (error) {
      const issue = originalModelPlanReplayRefusal(error, ref);
      if (issue === undefined || attempt === undefined) throw error;
      const authorized = await authorize(value);
      if (authorized.authorityScopeCid !== fields.authorityScopeCid ||
          authorized.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
      return attempt.rejectModelReplay(issue);
    }
  };
  const submittedInput = (value: SubmitRequest) => {
    const original = submittedIntentOriginal?.(value);
    if (original !== undefined) {
      if (moon.clientSubmittedIntentCid(original) !== value.intentCid) fail('InvalidClientSubmittedIntent');
      return original;
    }
    const wire = canonicalJson({kind: value.kind, input: value.input,
      parameters: value.parameters,
      ...(Object.hasOwn(value, 'stopBefore') ? {stopBefore: value.stopBefore} : {}),
      ...(Object.hasOwn(value, 'readOnly') ? {readOnly: value.readOnly} : {}),
      ...(Object.hasOwn(value, 'executionProfile') ? {executionProfile: value.executionProfile} : {})},
    {dataKeys: true});
    let input;
    if (typeof journal.prepareSubmittedIntent === 'function') {
      input = journal.prepareSubmittedIntent(value.submissionRef.epoch, wire, moon);
    } else {
      // This same canonical wire is already retained. Its UTF16 length bounds
      // UTF8 by three bytes per code unit and each JSON node by one code unit.
      // Keep the original recursion guard and Core's +128-byte Int headroom;
      // do not rescan/snapshot caller DATA or impose a second size policy.
      const units = wire.length;
      const bytes = 3 * units;
      if (units < 1 || bytes > 2147483519) fail('ClientSubmittedIntentCapacity');
      input = moon.clientSubmittedIntent(wire, bytes, units, 64);
    }
    if (input === undefined || moon.clientSubmittedIntentCid(input) !== value.intentCid) {
      fail('InvalidClientSubmittedIntent');
    }
    return input;
  };
  const submitIntent = async (request: SubmitRequest, attempt?: Attempt): Promise<WireSubmissionLookup> => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = attempt?.fields ?? await authorize(value);
    const input = submittedInput(value);
    // The Host supplies principalId after authentication. Client data cannot
    // substitute another actor for this explicit decision. Check through the
    // same journal owner before preparation and at atomic receipt acceptance.
    const restartFields = (current: Scope): AttemptFields => ({...current, actorId: value.principalId,
      unresolvedHistory: value.unresolvedHistory});
    if (attempt === undefined) journal.checkSubmittedIntent(value.submissionRef, input, restartFields(fields), moon);
    else attempt.check(value.submissionRef, input, restartFields(fields));
    let retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon, input);
    attempt?.observe(retained);
    if (retained !== undefined) {
      if (!['conflict', 'recorded', 'already_satisfied'].includes(retained.observation!)) {
        fail('ClientSubmittedIntentCorrupt');
      }
      if (retained.observation === 'conflict') fail('ClientSubmittedIntentConflict');
      const result = await refresh(value, retained, fields);
      if (result.kind === 'unresolvable') fail('ClientSubmissionUnresolvable');
      if (result.kind === 'ready') return await replayReady(value, retained, fields, result, input, attempt);
      if (result.kind !== 'preparing') return await discloseOutcome(value, result, fields, retained);
    }
    if (retained === undefined) {
      const verified = journal.verifySubmissionEpoch(value.submissionRef.epoch,
        {...fields, purpose: 'admit'}, moon);
      if (verified.validity !== 'admissible') fail(verified.validity === 'expired'
        ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid');
    }
    const requestId = journal.submissionIdentity(value.submissionRef.epoch, value.submissionRef.nonce,
      {...fields, purpose: 'lookup'}, moon).requestId;
    if (flights.has(requestId)) {
      // The original in-process operation owns preparation. Observation never
      // starts another preparation merely to wait for its response.
      return storedOutcome(journal.lookupSubmittedIntent(value.submissionRef, fields, moon)!);
    }
    const retainPreparationRefusal = async (error: unknown, issuedCode?: string): Promise<WireSubmissionLookup> => {
      const originalCode = requestProgramPreparationProblemCode(error);
      const originalRefusalCode = requestProgramPreparationRefusalCode(error) ?? (error as Failure)?.code;
      if (!isClientSubmitRejection(issuedCode ?? originalRefusalCode)) throw error;
      const kind = retained === undefined ? 'not_accepted' : 'preparation_failed';
      const current = await authorize(value);
      // Preserve the actual typed exception. The same failed Request may also
      // supply a completed audience-bound Source violation before this first
      // durable outcome; neither a later check nor a Source marker supplies it.
      const code = issuedCode ?? originalRefusalCode;
      const originalObservation = async () => {
        if (observeOriginalPreparationFailure !== undefined) {
          try {
            const report = await observeOriginalPreparationFailure(error, value);
            // Keep the same original callback and its current/lifetime fences
            // even when this input format has no public observation binding.
            if (validCheckOutcome(report) && supportsCheckObservation(value)) return report;
          } catch {
            // Reporting cannot replace the primary failure or acknowledge its
            // original Request/physical cleanup. Missing is not a recheck port.
          }
        }
        return null;
      };
      let checkObservation = await originalObservation();
      const problemCode = issuedCode === undefined && code === 'ClientProgramRejected' &&
          value.kind === 'aql' && checkObservation?.outcome === 'completed' &&
          checkObservation.report.scope.kind === 'bound_input' &&
          checkObservation.report.verdict === 'invalid'
        ? 'ClientProgramInvalidInput' : code;
      const candidate: ProblemOutcome = {kind, submissionRef: value.submissionRef, intentCid: value.intentCid,
        problem: {code: (originalCode ?? problemCode)! as ProblemOutcome['problem']['code'],
          classification: classification(originalCode === undefined ? problemCode : originalRefusalCode)}};
      const projected = await discloseOutcome(value, candidate, current,
        {intentWire: moon.clientSubmittedIntentWire(input)}, checkObservation);
      const {checkObservation: transientObservation, ...outcome} = projected;
      void transientObservation;
      const result = retained === undefined
        ? (attempt === undefined ? journal.recordSubmittedIntent(value.submissionRef, input,
          {...restartFields(current), phase: kind, outcome: outcome as WireSubmissionOutcome}, moon)
          : attempt.record(value.submissionRef, input, {...restartFields(current), phase: kind, outcome: outcome as WireSubmissionOutcome}))
        : journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...current, connection: value.connection, expectedRevision: retained.revision}, moon);
      // The durable write is an actual external boundary. Re-project the SAME
      // original result for its current audience after it; do not parse/check
      // the Program again. Each projection retains the existing current fence.
      checkObservation = await originalObservation();
      const disclosed = await discloseOutcome(value, storedOutcome(result), current, result, checkObservation);
      return immutable({...disclosed, ...(checkObservation === null ? {} : {checkObservation})});
    };
    let preparedProgram;
    try {
      preparedProgram = await prepareOwned(value, requestId);
      assertOriginalPreparation(preparedProgram, input, value);
    }
    catch (error) {return await retainPreparationRefusal(error);}
    const current = await authorize(value);
    // The actual selected Host validates its same finite business candidate
    // before this first durable business admission. This callback cannot
    // issue the service or replace authorization; unselected callers retain
    // their original path, and Promise/Bool is not synchronous acceptance.
    const admissionCandidate = admitPreparedSubmission === undefined ? undefined :
      Object.freeze(own(value, preparedSubmission(copyRequest(value, {requestId}), preparedProgram)));
    try {
      if (admitPreparedSubmission !== undefined && admitPreparedSubmission(
        admissionCandidate) !== undefined) fail('ClientPreparedSubmissionUnavailable');
    } catch (error) {
      if (originalPreparationRefusal === undefined ||
          Reflect.apply(originalPreparationRefusal, admitPreparedSubmission,
            [error, admissionCandidate]) !== true ||
          (error as Failure)?.cleanupPending === true || (error as Failure)?.cleanupHandle !== undefined) throw error;
      // The installed holder recognizes only its original pure Unsupported,
      // before any Resource/start duty. Do not re-read a mutable error code to
      // replace that issued fact; the old preparation catch remains unchanged.
      return await retainPreparationRefusal(error, 'ClientProgramUnsupported');
    }
    retained = attempt === undefined
      ? journal.recordSubmittedIntent(value.submissionRef, input, restartFields(current), moon)
      : attempt.record(value.submissionRef, input, restartFields(current));
    if (retained.phase !== 'preparing') {
      return await discloseOutcome(value, await refresh(value, retained, current), current, retained);
    }
    // A concurrent caller may have completed preflight while the first caller
    // was awaiting authorization. Only one local flight enters the Run owner.
    if (flights.has(requestId)) return storedOutcome(retained);
    const flight = (async () => {
      try {
        const reply = await submit(own(value, preparedSubmission(copyRequest(value, {requestId,
          submission: {epoch: value.submissionRef.epoch, nonce: value.submissionRef.nonce,
            intentCid: value.intentCid, currentAuthorization: true}}), preparedProgram)));
        const outcome: WireSubmissionOutcome = (reply as Partial<Extract<WireSubmitReply, {kind: 'held'}>>).kind === 'held'
          ? {kind: 'held', submissionRef: value.submissionRef, intentCid: value.intentCid,
            held: {...reply as Extract<WireSubmitReply, {kind: 'held'}>, requestId: value.submissionRef.nonce}}
          : {kind: 'ready', submissionRef: value.submissionRef, intentCid: value.intentCid, admission: reply as Ready['admission']};
        const current = await authorize(value);
        return storedOutcome(journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...current, connection: value.connection, expectedRevision: retained!.revision}, moon));
      } catch (error) {
        // A throw may follow a successful Run COMMIT. Look up that original
        // record before considering a typed preparation refusal.
        const found = await refresh(value, retained!, current);
        if (found.kind !== 'preparing') return found;
        const originalCode = requestProgramPreparationProblemCode(error);
        const refusalCode = requestProgramPreparationRefusalCode(error) ?? (error as Failure)?.code;
        if (!isClientSubmitRejection(refusalCode)) throw error;
        const outcome: ProblemOutcome = {kind: 'preparation_failed', submissionRef: value.submissionRef,
          intentCid: value.intentCid, problem: {code: (originalCode ?? refusalCode)! as ProblemOutcome['problem']['code'], classification: classification(refusalCode)}};
        return storedOutcome(journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...await authorize(value), connection: value.connection, expectedRevision: retained!.revision}, moon));
      }
    })().finally(() => {if (flights.get(requestId) === flight) flights.delete(requestId);});
    flights.set(requestId, flight);
    const result = await flight;
    if (result.kind === 'unresolvable') fail('ClientSubmissionUnresolvable');
    if (!validSubmissionOutcome(result, value.connection, value.submissionRef, value.intentCid)) {
      fail('InvalidClientHostSubmissionOutcome');
    }
    return await discloseOutcome(value, result, current, retained);
  };
  const submitAttempt = async (request: AttemptRequest) => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef) || !validOperationAttemptRef(value.attemptRef) ||
        value.attemptRef.operation !== 'submit') fail('InvalidClientSubmissionAttempt');
    const selected = await authorizedScope(value);
    if (selected === undefined) return journal.checkSubmissionAttempt(value.submissionRef,
      undefined, {attemptRef: value.attemptRef, currentAuthorization: false}, moon);
    const fields = scopeFields(selected);
    const rejections = new WeakMap<Error, AttemptResult | RejectedAttempt>();
    let attemptKind: ObservedAttempt['kind'] = 'recorded';
    const project = (result: AttemptResult): AttemptResult => {
      if (['refused', 'conflict'].includes(result.kind)) {
        const interruption = new Error('SubmissionAttemptRejected');
        rejections.set(interruption, result);
        throw interruption;
      }
      return result;
    };
    try {
      const outcome = await submitIntent(value, {fields,
        observe(retained) {
          if (retained?.observation === 'already_satisfied') attemptKind = retained.observation;
        },
        rejectModelReplay(issue) {
          const attemptRef = {operation: 'submit' as const, attemptId: value.attemptRef.attemptId};
          const input = {attemptRef, submissionRef: value.submissionRef, intentCid: value.intentCid};
          const interruption = new Error('SubmissionAttemptRejected');
          rejections.set(interruption, issue === 'model_provider_selection'
            ? {...input, kind: 'conflict', reason: issue}
            : {...input, kind: 'refused', reason: issue, guarantee: 'attempt_uncommitted_unconsumed'});
          throw interruption;
        },
        check(ref, input, options) {
          project(journal.checkSubmissionAttempt(ref, input,
            {...options, attemptRef: value.attemptRef}, moon));
        },
        record(ref, input, options) {
          const result = project(journal.recordSubmissionAttempt(ref, input,
            {...options, attemptRef: value.attemptRef}, moon)) as RecordedAttempt;
          if (!['recorded', 'already_satisfied'].includes(result.attemptKind as string)) {
            fail('ClientSubmittedIntentCorrupt');
          }
          if (result.attemptKind === 'already_satisfied') attemptKind = result.attemptKind;
          return result.submission;
        },
      });
      return immutable({kind: attemptKind,
        attemptRef: value.attemptRef, outcome});
    } catch (error) {
      // Only the exact private Owner projection can terminate this invocation
      // as Refused or Conflict. Preparation, dispatch and COMMIT exceptions
      // retain their unknown-outcome handling, whatever their error code.
      const rejected = rejections.get(error as Error);
      if (rejected === undefined) throw error;
      return immutable(rejected);
    }
  };
  const submitNamedAttempt = async (request: NamedRequest) => {
    const value = ownedSnapshot(request);
    if (!validSubmissionName(value.requestName) || !validSubmissionRef(value.submissionRef) ||
        !validOperationAttemptRef(value.attemptRef) || value.attemptRef.operation !== 'submit') {
      fail('InvalidClientSubmissionAttempt');
    }
    if (typeof journal.resolveNamedSubmissionAttempt !== 'function') fail('ClientOperationUnavailable');
    const selected = await authorizedScope(value);
    const fields = selected === undefined ? {currentAuthorization: false as const} : scopeFields(selected);
    const input = selected === undefined ? undefined : submittedInput(value);
    const resolution = journal.resolveNamedSubmissionAttempt(value.requestName, input,
      {...fields, actorId: value.principalId, submissionRef: value.submissionRef,
        attemptRef: value.attemptRef}, moon);
    const original = {requestName: value.requestName, intentCid: value.intentCid,
      attemptRef: value.attemptRef};
    let answer;
    if (resolution.kind === 'refused' || resolution.kind === 'conflict') {
      // Only the same Journal's nominal, confirmed rollback/initial refusal
      // path can issue this projection. Error text never certifies nonacceptance.
      answer = {...original, kind: resolution.kind, reason: resolution.reason,
        ...(resolution.kind === 'refused' ? {guarantee: (resolution as {guarantee: string}).guarantee} : {})};
    } else {
      const retained = (resolution as RecordedAttempt & Readonly<{submission: {inserted: boolean}}>).submission;
      const bound = Object.freeze(own(value, copyRequest(value, {submissionRef: retained.submissionRef})));
      ownedSnapshots.add(bound);
      // The original name and intent are already committed before preparation.
      // Another connection may only observe this original, never replay it or
      // replace its epoch because its first outcome is still preparing/unknown.
      const release = retained.submissionRef.epoch === value.submissionRef.epoch ? undefined :
        journal.retainSubmissionOperation?.(retained.submissionRef.epoch, moon,
          submittedIntentOriginal?.(value));
      try {
        const lookup = Object.freeze({principalId: value.principalId, connection: value.connection,
          submissionRef: retained.submissionRef});
        ownedSnapshots.add(lookup);
        const outcome = retained.inserted ? await submitIntent(bound) : await lookupSubmission(lookup);
        const current = await authorize(value);
        if (current.authorityScopeCid !== (fields as Scope).authorityScopeCid ||
            current.namespaceId !== (fields as Scope).namespaceId) fail('ClientRequestLookupDenied');
        answer = {...original, kind: 'observed', outcome};
      } finally {release?.();}
    }
    if (!validNamedSubmissionAttempt(answer, value.connection, value.requestName,
      value.submissionRef, value.intentCid, value.attemptRef)) fail('InvalidClientHostSubmissionOutcome');
    return immutable(answer);
  };
  return Object.freeze({submitIntent: operation(submitIntent), submitAttempt: operation(submitAttempt),
    submitNamedAttempt: operation(submitNamedAttempt), lookupSubmission: operation(lookupSubmission, false),
    issueEpoch(request: Actor) {return issueNodeClientSubmissionEpoch({journal,moon,authorizedScope},request);}});
}
