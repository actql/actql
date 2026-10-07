// Public submission facts live in the existing request journal. This adapter
// neither dispatches tasks nor infers nonexecution from a missing Run record.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {validSubmissionRef, validSubmissionOutcome, validSubmissionLookup,
  isClientSubmitRejection, validCheckOutcome} from '../../packages/client-wire/index.mjs';

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

export function installNodeClientSubmission({journal, moon, authorizedScope,
  prepareSubmit, submit, lookupRequest, checkSubmissionInput}) {
  if (typeof journal?.recordSubmittedIntent !== 'function' ||
      typeof moon?.clientSubmittedIntent !== 'function' ||
      [authorizedScope, prepareSubmit, submit, lookupRequest].some(value => typeof value !== 'function') ||
      checkSubmissionInput !== undefined && typeof checkSubmissionInput !== 'function') {
    throw new TypeError('InvalidClientSubmissionInstallation');
  }
  const flights = new Map();
  const authorize = async value => {
    const selected = await authorizedScope(value);
    const authorityScopeCid = selected?.authorityScopeCid;
    const namespaceId = selected?.namespaceId;
    if (typeof authorityScopeCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(authorityScopeCid) ||
        typeof namespaceId !== 'string' || !namespaceId) fail('ClientRequestLookupDenied');
    return {authorityScopeCid, namespaceId, currentAuthorization: true};
  };
  const snapshot = value => immutable(JSON.parse(canonicalJson(value, {dataKeys: true})));
  const unresolved = (submissionRef, code = 'submission_history_unresolvable') =>
    immutable({kind: 'unresolvable', submissionRef, problem: {code}});
  const storedOutcome = retained => retained.outcome ?? immutable({kind: 'preparing',
    submissionRef: retained.submissionRef, intentCid: retained.intentCid});
  const discloseOutcome = async (value, outcome, fields, retained) => {
    if (!['not_accepted', 'preparation_failed'].includes(outcome.kind) ||
        !['ClientProgramInvalidInput', 'ClientProgramAnalysisLimit', 'ClientProgramImplementationLimit'].includes(outcome.problem.code)) return outcome;
    // The durable problem describes the original preparation, not a new check.
    // Reuse original journal custody and the installed disclosure-aware checker
    // before showing a Source-dependent input classification to this audience.
    const intent = immutable(JSON.parse(retained.intentWire));
    if (intent.kind !== 'aql' || !['sql', 'aql-text'].includes(intent.input.format)) return outcome;
    let disclosable = false;
    try {
      const report = await checkSubmissionInput?.({principalId: value.principalId,
        connection: value.connection, input: intent.input, parameters: intent.parameters});
      const observed = report?.report ?? report?.partial_report;
      disclosable = validCheckOutcome(report) && (outcome.problem.code === 'ClientProgramInvalidInput'
        ? observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid'
        : observed?.scope.kind === 'bound_input' && observed.coverage.limits.some(
          limit => limit.code === (outcome.problem.code === 'ClientProgramAnalysisLimit'
            ? 'analysis_budget_exhausted' : 'implementation_limit')));
    } catch {
      // A failed reporting attempt neither changes acceptance nor establishes
      // disclosure. No error text or HTTP status supplies a check verdict.
    }
    const current = await authorize(value);
    if (current.authorityScopeCid !== fields.authorityScopeCid ||
        current.namespaceId !== fields.namespaceId) fail('ClientRequestLookupDenied');
    if (disclosable) return outcome;
    // Do not rewrite the journal: authorization loss affects this response,
    // while the same original intent and acceptance phase remain retained.
    return immutable({...outcome, problem: {code: 'ClientProgramRejected',
      classification: 'operation_failed'}});
  };
  const refresh = async (value, retained, fields) => {
    if (['not_accepted', 'preparation_failed'].includes(retained.phase)) return storedOutcome(retained);
    const found = await lookupRequest({...value, requestId: retained.requestId});
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
    const value = snapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = await authorize(value);
    let retained;
    try {retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon);}
    catch (error) {
      if (['ClientSubmittedIntentCorrupt', 'ClientSubmissionEpochCustodyLost'].includes(error?.code)) {
        return unresolved(value.submissionRef);
      }
      throw error;
    }
    const original = retained === undefined ? unresolved(value.submissionRef) : await refresh(value, retained, fields);
    const result = retained === undefined ? original : await discloseOutcome(value, original, fields, retained);
    if (!validSubmissionLookup(result, value.connection, value.submissionRef)) fail('InvalidClientHostSubmissionLookup');
    return result;
  };
  const submitIntent = async request => {
    const value = snapshot(request);
    if (!validSubmissionRef(value.submissionRef)) fail('InvalidClientRequest');
    const fields = await authorize(value);
    const input = moon.clientSubmittedIntent(canonicalJson({kind: value.kind, input: value.input,
      parameters: value.parameters}, {dataKeys: true}), 1048576, 65536, 64);
    if (input === undefined || moon.clientSubmittedIntentCid(input) !== value.intentCid) {
      fail('InvalidClientSubmittedIntent');
    }
    let retained = journal.lookupSubmittedIntent(value.submissionRef, fields, moon);
    if (retained !== undefined) {
      if (retained.intentCid !== value.intentCid) fail('ClientSubmittedIntentConflict');
      const result = await refresh(value, retained, fields);
      if (result.kind === 'unresolvable') fail('ClientSubmissionUnresolvable');
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
    let preparedProgram;
    try {preparedProgram = await prepareSubmit({...value, requestId});}
    catch (error) {
      if (!isClientSubmitRejection(error?.code)) throw error;
      const kind = retained === undefined ? 'not_accepted' : 'preparation_failed';
      const current = await authorize(value);
      // A protected resolution failure may coexist with an independently
      // invalid supplied value. Ask the same installed public checker before
      // storing a reason; do not let private resolution order choose its code.
      const code = prepareSubmit.sourceCheckFailure?.(error) === true
        ? 'ClientProgramInvalidInput' : error.code;
      const candidate = {kind, submissionRef: value.submissionRef, intentCid: value.intentCid,
        problem: {code, classification: classification(code)}};
      const outcome = await discloseOutcome(value, candidate, current,
        {intentWire: moon.clientSubmittedIntentWire(input)});
      const result = retained === undefined
        ? journal.recordSubmittedIntent(value.submissionRef, input,
          {...current, phase: kind, outcome}, moon)
        : journal.completeSubmittedIntent(value.submissionRef, outcome,
          {...current, connection: value.connection, expectedRevision: retained.revision}, moon);
      return await discloseOutcome(value, storedOutcome(result), current, result);
    }
    const current = await authorize(value);
    retained = journal.recordSubmittedIntent(value.submissionRef, input, current, moon);
    if (retained.phase !== 'preparing') {
      return await discloseOutcome(value, await refresh(value, retained, current), current, retained);
    }
    // A concurrent caller may have completed preflight while the first caller
    // was awaiting authorization. Only one local flight enters the Run owner.
    if (flights.has(requestId)) return storedOutcome(retained);
    const flight = (async () => {
      try {
        const reply = await submit({...value, requestId, preparedProgram,
          submission: {epoch: value.submissionRef.epoch, nonce: value.submissionRef.nonce,
            intentCid: value.intentCid, currentAuthorization: true}});
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
  return Object.freeze({submitIntent, lookupSubmission,
    async issueEpoch(request) {return journal.issueSubmissionEpoch(await authorize(snapshot(request)), moon);}});
}
