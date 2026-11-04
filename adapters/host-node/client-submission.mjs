// Public submission facts live in the existing request journal. This adapter
// neither dispatches tasks nor infers nonexecution from a missing Run record.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {validSubmissionRef, validSubmissionOutcome, validSubmissionLookup,
  isClientSubmitRejection, validCheckOutcome, validOperationAttemptRef,
  validSubmissionName, validNamedSubmissionAttempt} from '../../packages/client-wire/index.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const classification = code => ({
  ClientProgramInvalidInput: 'invalid_input', ClientParametersInvalid: 'invalid_input',
  ClientProgramNeedsInputs: 'requirements', ClientProgramUnsupported: 'implementation_limit',
  ClientParametersTooLarge: 'implementation_limit', ClientProgramAnalysisLimit: 'implementation_limit',
  ClientProgramImplementationLimit: 'implementation_limit', ClientProgramRejected: 'operation_failed',
})[code] ?? 'operation_failed';
const immutable = value => {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) immutable(child);
    Object.freeze(value);
  }
  return value;
};
const scopeFields = selected => {
  const authorityScopeCid = selected?.authorityScopeCid;
  const namespaceId = selected?.namespaceId;
  if (typeof authorityScopeCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(authorityScopeCid) ||
      typeof namespaceId !== 'string' || !namespaceId) fail('ClientRequestLookupDenied');
  return {authorityScopeCid, namespaceId, currentAuthorization: true};
};
const snapshot = value => immutable(JSON.parse(canonicalJson(value, {dataKeys: true})));

// The same Journal-owned epoch operation is available before optional Result
// and Model services are constructed. This issues no Run, Account or Store
// permission and keeps the original authenticated scope and packet snapshot.
export async function issueNodeClientSubmissionEpoch({journal, moon, authorizedScope}, request) {
  return journal.issueSubmissionEpoch(scopeFields(await authorizedScope(snapshot(request))), moon);
}

export function installNodeClientSubmission({journal, moon, authorizedScope,
  prepareSubmit, submit, lookupRequest, checkSubmissionInput, observeOriginalPreparationFailure,
  bindOwnedRequest, admitPreparedSubmission, preparationCustody, submittedIntentOriginal}) {
  if (typeof journal?.recordSubmittedIntent !== 'function' ||
      typeof journal?.checkSubmittedIntent !== 'function' ||
      typeof moon?.clientSubmittedIntent !== 'function' ||
      [authorizedScope, prepareSubmit, submit, lookupRequest].some(value => typeof value !== 'function') ||
      bindOwnedRequest !== undefined && typeof bindOwnedRequest !== 'function' ||
      admitPreparedSubmission !== undefined && typeof admitPreparedSubmission !== 'function' ||
      checkSubmissionInput !== undefined && typeof checkSubmissionInput !== 'function' ||
      observeOriginalPreparationFailure !== undefined && typeof observeOriginalPreparationFailure !== 'function' ||
      submittedIntentOriginal !== undefined && typeof submittedIntentOriginal !== 'function') {
    throw new TypeError('InvalidClientSubmissionInstallation');
  }
  const copyRequest = (value, changes) => preparationCustody === undefined
    ? {...value, ...changes} : preparationCustody.copy(value, changes);
  const preparedValue = value => preparationCustody === undefined ? value : preparationCustody.read(value);
  const preparedSubmission = (value, prepared) => preparationCustody === undefined
    ? {...value, preparedProgram: prepared}
    : preparationCustody.attach(value, prepared);
  const flights = new Map();
  const ownedSnapshots = new WeakSet();
  // The installed callback and its own original projection are one port.
  // A public-looking code, inherited method or later property replacement is
  // not the Host's retained same-call preparation refusal.
  const refusalProperty = admitPreparedSubmission === undefined ? undefined :
    Object.getOwnPropertyDescriptor(admitPreparedSubmission, 'isOriginalPreparationRefusal');
  const originalPreparationRefusal = refusalProperty !== undefined &&
      Object.hasOwn(refusalProperty, 'value') && typeof refusalProperty.value === 'function'
    ? refusalProperty.value : undefined;
  const authorize = async value => scopeFields(await authorizedScope(value));
  const own = (parent, derived) => {
    if (bindOwnedRequest !== undefined && bindOwnedRequest(parent, derived) !== undefined) {
      fail('SourceManagedPreparationUnavailable');
    }
    return derived;
  };
  const captureSnapshot = (value, bind = true) => {
    const raw = snapshot(value);
    const selected = preparationCustody === undefined ? raw : preparationCustody.capture(raw);
    const captured = bind ? own(value, selected) : selected;
    ownedSnapshots.add(captured);
    return captured;
  };
  const ownedSnapshot = value => ownedSnapshots.has(value) ? value : captureSnapshot(value);
  const operation = (action, bind = true) => async request => {
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
  const prepareOwned = (value, requestId) => {
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
  const unresolved = (submissionRef, code = 'submission_history_unresolvable') =>
    immutable({kind: 'unresolvable', submissionRef, problem: {code}});
  const withRestart = (outcome, retained) => retained.unresolvedHistory === undefined ? outcome
    : immutable({...outcome, unresolvedHistory: {
      submissionRef: retained.unresolvedHistory.submissionRef,
      acknowledgement: retained.unresolvedHistory.acknowledgement}});
  const storedOutcome = retained => withRestart(retained.outcome ?? immutable({kind: 'preparing',
    submissionRef: retained.submissionRef, intentCid: retained.intentCid}), retained);
  // Match the existing SDK observation input contract. Other Source formats
  // retain their actual preparation outcome without an unsupported report.
  const supportsCheckObservation = intent => intent.kind === 'program' ||
    intent.kind === 'aql' && ['sql', 'aql', 'aql-text'].includes(intent.input.format);
  const discloseOutcome = async (value, outcome, fields, retained, originalObservation) => {
    if (!['not_accepted', 'preparation_failed'].includes(outcome.kind)) return outcome;
    const projectsProblem = ['ClientProgramInvalidInput', 'ClientProgramAnalysisLimit',
      'ClientProgramImplementationLimit'].includes(outcome.problem.code);
    if (!projectsProblem && originalObservation === undefined) return outcome;
    // The durable problem describes the original preparation, not a new check.
    // Reuse original journal custody and the installed disclosure-aware checker
    // before showing a Source-dependent input classification to this audience.
    const intent = immutable(JSON.parse(retained.intentWire));
    if (!supportsCheckObservation(intent)) {
      if (originalObservation !== undefined) {
        const current = await authorize(value);
        if (current.authorityScopeCid !== fields.authorityScopeCid ||
            current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
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
      const observed = report?.report ?? report?.partial_report;
      disclosable = !projectsProblem || validCheckOutcome(report) && (outcome.problem.code === 'ClientProgramInvalidInput'
        ? observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid'
        : observed?.scope.kind === 'bound_input' && observed.coverage.limits.some(
          limit => limit.code === (outcome.problem.code === 'ClientProgramAnalysisLimit'
            ? 'analysis_budget_exhausted' : 'implementation_limit')));
      // A protected Program dependency can change preparation's coarse cause.
      // Keep the original operation terminal, but do not reveal that private
      // distinction through its Problem even when independent input facts exist.
      if (projectsProblem && intent.kind === 'program' && observed?.coverage.unresolved.length > 0) disclosable = false;
    } catch {
      // A failed reporting attempt neither changes acceptance nor establishes
      // disclosure. No error text or HTTP status supplies a check verdict.
    }
    const current = await authorize(value);
    if (current.authorityScopeCid !== fields.authorityScopeCid ||
        current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
    const projected = disclosable ? outcome : {...outcome,
      problem: {code: 'ClientProgramRejected', classification: 'operation_failed'}};
    // This separate current disclosure check can gate the stored Problem,
    // but is never the original preparation's transient CheckOutcome.
    return immutable(projected);
  };
  const refresh = async (value, retained, fields) => {
    if (['not_accepted', 'preparation_failed'].includes(retained.phase)) return storedOutcome(retained);
    const found = await lookupRequest(copyRequest(value, {requestId: retained.requestId}));
    // Revalidate current authority after the async lookup before changing facts.
    const current = await authorize(value);
    if (current.authorityScopeCid !== fields.authorityScopeCid ||
        current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
    let outcome;
    if (found.kind === 'found') {
      // Public request lookup names the Run but carries no control revision.
      // Obtain that fact from the same authorized journal record, never invent
      // a revision while projecting an admission response.
      const admitted = journal.lookup({namespaceId: current.namespaceId,
        authorityScopeCid: current.authorityScopeCid, requestId: retained.requestId}, moon);
      if (admitted === undefined || ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .some(key => admitted.ref[key] !== found.ref[key])) return unresolved(retained.submissionRef);
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
  const lookupSubmission = async request => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = await authorize(value);
    let retained;
    try {retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon);}
    catch (error) {
      if (['ClientSubmittedIntentCorrupt', 'ClientSubmissionEpochCustodyLost',
        'ClientSubmissionRestartCorrupt', 'ClientSubmissionRestartCustodyLost'].includes(error?.code)) {
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
  const assertOriginalPreparation = (prepared, input, value) => {
    if (typeof prepareSubmit.assertSubmittedIntent === 'function') {
      prepareSubmit.assertSubmittedIntent(preparedValue(prepared), input);
    } else if (Object.hasOwn(value, 'readOnly')) {
      // An installation without the original Common boundary cannot accept
      // this continuation choice. Older unselected installations are unchanged.
      fail('ClientProgramUnsupported');
    }
  };
  const replayReady = async (value, retained, fields, original, input) => {
    const requestId = retained.requestId;
    if (flights.has(requestId)) return original;
    // A ready receipt establishes acceptance, not physical dispatch. Only
    // explicit replay re-enters the existing Run owner; lookup stays read-only.
    const flight = (async () => {
      let preparedProgram;
      try {
        preparedProgram = await prepareOwned(value, requestId);
        assertOriginalPreparation(preparedProgram, input, value);
      }
      catch (error) {
        if (!isClientSubmitRejection(error?.code)) throw error;
        // Current execution support cannot replace an already accepted intent.
        // Re-read through the same authorized owner after the awaited failure:
        // lost authority or custody is not permission to return a stale receipt.
        const observed = await lookupSubmission(value);
        if (observed.kind !== 'ready') fail('ClientSubmissionUnresolvable');
        if (observed.intentCid !== original.intentCid ||
            ['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].some(
              key => observed.admission.ref[key] !== original.admission.ref[key])) {
          fail('InvalidClientHostSubmissionOutcome');
        }
        return observed;
      }
      const current = await authorize(value);
      if (current.authorityScopeCid !== fields.authorityScopeCid ||
          current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
      const reply = await submit(own(value, preparedSubmission(copyRequest(value, {requestId,
        submission: {epoch: value.submissionRef.epoch, nonce: value.submissionRef.nonce,
          intentCid: value.intentCid, currentAuthorization: true}}), preparedProgram)));
      const observed = await authorize(value);
      if (observed.authorityScopeCid !== fields.authorityScopeCid ||
          observed.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
      if (reply.kind === 'held' || ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .some(key => reply.ref?.[key] !== original.admission.ref[key])) {
        fail('InvalidClientHostSubmissionOutcome');
      }
      // Dispatch revalidation cannot replace an immutable acceptance receipt,
      // including when the existing owner refuses a changed Source binding.
      return original;
    })().finally(() => {if (flights.get(requestId) === flight) flights.delete(requestId);});
    flights.set(requestId, flight);
    return await flight;
  };
  const submittedInput = value => {
    const original = submittedIntentOriginal?.(value);
    if (original !== undefined) {
      if (moon.clientSubmittedIntentCid(original) !== value.intentCid) fail('InvalidClientSubmittedIntent');
      return original;
    }
    const wire = canonicalJson({kind: value.kind, input: value.input,
      parameters: value.parameters,
      ...(Object.hasOwn(value, 'stopBefore') ? {stopBefore: value.stopBefore} : {}),
      ...(Object.hasOwn(value, 'readOnly') ? {readOnly: value.readOnly} : {})},
    {dataKeys: true});
    const input = typeof journal.prepareSubmittedIntent === 'function' ?
      journal.prepareSubmittedIntent(value.submissionRef.epoch, wire, moon) :
      moon.clientSubmittedIntent(wire, 1048576, 65536, 64);
    if (input === undefined || moon.clientSubmittedIntentCid(input) !== value.intentCid) {
      fail('InvalidClientSubmittedIntent');
    }
    return input;
  };
  const submitIntent = async (request, attempt) => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = attempt?.fields ?? await authorize(value);
    const input = submittedInput(value);
    // The Host supplies principalId after authentication. Client data cannot
    // substitute another actor for this explicit decision. Check through the
    // same journal owner before preparation and at atomic receipt acceptance.
    const restartFields = current => ({...current, actorId: value.principalId,
      unresolvedHistory: value.unresolvedHistory});
    if (attempt === undefined) journal.checkSubmittedIntent(value.submissionRef, input, restartFields(fields), moon);
    else attempt.check(value.submissionRef, input, restartFields(fields));
    let retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon);
    attempt?.observe(retained);
    if (retained !== undefined) {
      if (retained.intentCid !== value.intentCid) fail('ClientSubmittedIntentConflict');
      const result = await refresh(value, retained, fields);
      if (result.kind === 'unresolvable') fail('ClientSubmissionUnresolvable');
      if (result.kind === 'ready') return await replayReady(value, retained, fields, result, input);
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
      return storedOutcome(journal.lookupSubmittedIntent(value.submissionRef, fields, moon));
    }
    const retainPreparationRefusal = async (error, issuedCode) => {
      if (!isClientSubmitRejection(issuedCode ?? error?.code)) throw error;
      const kind = retained === undefined ? 'not_accepted' : 'preparation_failed';
      const current = await authorize(value);
      // Preserve the actual typed exception. The same failed Request may also
      // supply a completed audience-bound Source violation before this first
      // durable outcome; neither a later check nor a Source marker supplies it.
      const code = issuedCode ?? error.code;
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
      const candidate = {kind, submissionRef: value.submissionRef, intentCid: value.intentCid,
        problem: {code: problemCode, classification: classification(problemCode)}};
      const projected = await discloseOutcome(value, candidate, current,
        {intentWire: moon.clientSubmittedIntentWire(input)}, checkObservation);
      const {checkObservation: transientObservation, ...outcome} = projected;
      void transientObservation;
      const result = retained === undefined
        ? (attempt === undefined ? journal.recordSubmittedIntent(value.submissionRef, input,
          {...restartFields(current), phase: kind, outcome}, moon)
          : attempt.record(value.submissionRef, input, {...restartFields(current), phase: kind, outcome}))
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
          error?.cleanupPending === true || error?.cleanupHandle !== undefined) throw error;
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
        const outcome = reply.kind === 'held'
          ? {kind: 'held', submissionRef: value.submissionRef, intentCid: value.intentCid,
            held: {...reply, requestId: value.submissionRef.nonce}}
          : {kind: 'ready', submissionRef: value.submissionRef, intentCid: value.intentCid, admission: reply};
        const current = await authorize(value);
        return storedOutcome(journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...current, connection: value.connection, expectedRevision: retained.revision}, moon));
      } catch (error) {
        // A throw may follow a successful Run COMMIT. Look up that original
        // record before considering a typed preparation refusal.
        const found = await refresh(value, retained, current);
        if (found.kind !== 'preparing') return found;
        if (!isClientSubmitRejection(error?.code)) throw error;
        const outcome = {kind: 'preparation_failed', submissionRef: value.submissionRef,
          intentCid: value.intentCid, problem: {code: error.code, classification: classification(error.code)}};
        return storedOutcome(journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...await authorize(value), connection: value.connection, expectedRevision: retained.revision}, moon));
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
  const submitAttempt = async request => {
    const value = ownedSnapshot(request);
    if (!validSubmissionRef(value.submissionRef) || !validOperationAttemptRef(value.attemptRef) ||
        value.attemptRef.operation !== 'submit') fail('InvalidClientSubmissionAttempt');
    const selected = await authorizedScope(value);
    if (selected === undefined) return journal.checkSubmissionAttempt(value.submissionRef,
      undefined, {attemptRef: value.attemptRef, currentAuthorization: false}, moon);
    const fields = scopeFields(selected);
    const rejections = new WeakMap();
    let originalSatisfied = false;
    const project = result => {
      if (['refused', 'conflict'].includes(result.kind)) {
        const interruption = new Error('SubmissionAttemptRejected');
        rejections.set(interruption, result);
        throw interruption;
      }
      return result;
    };
    try {
      const outcome = await submitIntent(value, {fields,
        observe(retained) {if (retained !== undefined && retained.phase !== 'preparing') originalSatisfied = true;},
        check(ref, input, options) {
          project(journal.checkSubmissionAttempt(ref, input,
            {...options, attemptRef: value.attemptRef}, moon));
        },
        record(ref, input, options) {
          const result = project(journal.recordSubmissionAttempt(ref, input,
            {...options, attemptRef: value.attemptRef}, moon));
          if (!result.submission.inserted && result.submission.phase !== 'preparing') originalSatisfied = true;
          return result.submission;
        },
      });
      return immutable({kind: originalSatisfied ? 'already_satisfied' : 'recorded',
        attemptRef: value.attemptRef, outcome});
    } catch (error) {
      // Only the exact private Owner projection can terminate this invocation
      // as Refused or Conflict. Preparation, dispatch and COMMIT exceptions
      // retain their unknown-outcome handling, whatever their error code.
      const rejected = rejections.get(error);
      if (rejected === undefined) throw error;
      return immutable(rejected);
    }
  };
  const submitNamedAttempt = async request => {
    const value = ownedSnapshot(request);
    if (!validSubmissionName(value.requestName) || !validSubmissionRef(value.submissionRef) ||
        !validOperationAttemptRef(value.attemptRef) || value.attemptRef.operation !== 'submit') {
      fail('InvalidClientSubmissionAttempt');
    }
    if (typeof journal.resolveNamedSubmissionAttempt !== 'function') fail('ClientOperationUnavailable');
    const selected = await authorizedScope(value);
    const fields = selected === undefined ? {currentAuthorization: false} : scopeFields(selected);
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
        ...(resolution.kind === 'refused' ? {guarantee: resolution.guarantee} : {})};
    } else {
      const retained = resolution.submission;
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
        if (current.authorityScopeCid !== fields.authorityScopeCid ||
            current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
        answer = {...original, kind: 'observed', outcome};
      } finally {release?.();}
    }
    if (!validNamedSubmissionAttempt(answer, value.connection, value.requestName,
      value.submissionRef, value.intentCid, value.attemptRef)) fail('InvalidClientHostSubmissionOutcome');
    return immutable(answer);
  };
  return Object.freeze({submitIntent: operation(submitIntent), submitAttempt: operation(submitAttempt),
    submitNamedAttempt: operation(submitNamedAttempt), lookupSubmission: operation(lookupSubmission, false),
    issueEpoch(request) {return issueNodeClientSubmissionEpoch({journal,moon,authorizedScope},request);}});
}
