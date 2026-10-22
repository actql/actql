// Original Check input/response associations and checking operations. Copies
// never acquire these private input, frontier or editor-session associations.
import {presentCheckFailure, renderCheckOutcome} from '../check-presentation.mjs';
import {captureResponse, freezeInput, structuralKey, utf8} from './data.mjs';
import {ClientError, fail} from './errors.mjs';
import {checkOutcomeProtocol, snapshotClientRequest, validCheckOutcome, validClientBody} from '@actql/client-wire';

const checkInputs = new WeakMap();
// Rejected transport observations retain only a safe classification and this
// call's own input. No unvalidated reply, revision or location gains custody.
const checkFailures = new WeakMap();

const checkRequests = new WeakMap();

const checkFrontiers = new WeakMap();

export function bindCheckObservation(outcome, body) {
  try {
    const report = outcome.report ?? outcome.partial_report;
    if (report) {
      if (report.scope.kind !== (body.scope ?? 'bound_input')) throw new TypeError('InvalidCheckScopeBinding');
      const received = body.kind === 'program'
        ? new Map([['program', {kind: 'structured', value: body.input}]])
        : new Map([['source', {kind: 'text', text: body.input.text}]]);
      if (body.kind !== 'program' && body.input.parameterDeclarations !== undefined) received.set('parameter_declarations',
        {kind: 'structured', value: body.input.parameterDeclarations});
      if (body.parameters !== undefined && body.parameters !== null) received.set('parameters', {kind: 'structured', value: body.parameters});
      if (report.inputs.length !== received.size) throw new TypeError('InvalidCheckInputBinding');
      const snapshots = new Map();
      for (const document of report.inputs) {
        const original = received.get(document.document_id);
        if (!original || document.kind !== original.kind || document.byte_length !==
            utf8.encode(original.kind === 'text' ? original.text : JSON.stringify(original.value)).length) {
          throw new TypeError('InvalidCheckInputBinding');
        }
        snapshots.set(document.document_id, Object.freeze({...original,
          documentId: document.document_id, revision: document.revision}));
      }
      checkInputs.set(outcome, snapshots);
      for (const reason of [...report.reasons, ...(report.requirements ?? []), ...report.coverage.limits]) {
        if (reason.location && !resolveCheckLocation(outcome, reason.location)) {
          checkInputs.delete(outcome);
          throw new TypeError('InvalidCheckInputBinding');
        }
      }
    }
    checkRequests.set(outcome, body);
    return true;
  } catch {
    checkInputs.delete(outcome);
    checkRequests.delete(outcome);
    return false;
  }
}

/** Return only the original SDK submission's transient checking observation. */

export function getCheckFailureInput(error) {
  return checkFailures.get(error)?.input;
}

export function explainCheckFailure(error, options) {
  const failure = checkFailures.get(error);
  return failure === undefined ? undefined : presentCheckFailure(failure, options);
}

export function getCheckInput(outcome, documentId, revision) {
  const input = checkInputs.get(outcome)?.get(documentId);
  return input && (revision === undefined || input.revision === revision)
    ? input : undefined;
}

// Proposals require the original SDK response, not a copied wire value.
export function getCheckFixes(outcome) {
  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed') return undefined;
  return Object.freeze(outcome.report.reasons.flatMap(reason => reason.fixes ?? []));
}

const unordered = values => [...new Map(values.map(value =>
  [structuralKey(value), value])).entries()].sort(([left], [right]) =>
  left < right ? -1 : left > right ? 1 : 0).map(([, value]) => value);

// Admitted declaration conditions from this call's public Requirement only.
// This is neither supplied-value admission nor proof of the remaining Program.
export function getCheckParameterAdmission(outcome, parameter) {
  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed' ||
      typeof parameter !== 'string') return undefined;
  return outcome.report.requirements.find(reason => reason.code === 'parameter_value_required' &&
    reason.facts.parameter === parameter)?.facts.admission;
}

// Existing caller-owned response custody; this advice grants no configuration write.
export function getCheckContextRequirements(outcome) {
  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed') return undefined;
  return Object.freeze(outcome.report.requirements.filter(reason => ['host_capacity_policy_required', 'numeric_reduction_profile_required'].includes(reason.code)));
}

export function getCheckRequirementFrontier(outcome) {
  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed') return undefined;
  if (checkFrontiers.has(outcome)) return checkFrontiers.get(outcome);
  const report = outcome.report;
  // These are the currently exposed typed Requirements. Unknown obligations
  // cannot supply a structural admission condition for supplementation.
  if (report.omissions?.requirements || report.requirements.some(reason => reason.code !== 'parameter_value_required')) return undefined;
  const frontier = freezeInput({contextRef: report.context_ref,
    reasonSchemaCid: outcome.reason_schema_cid,
    scope: {...report.scope}, requirements: unordered(report.requirements.map(({code, facts}) =>
      ({code, facts: facts.admission === undefined ? facts : {...facts,
        admission: {...facts.admission, constraints: unordered(facts.admission.constraints)}}}))),
    coverage: {limits: unordered(report.coverage.limits),
      unresolved: unordered(report.coverage.unresolved)}});
  checkFrontiers.set(outcome, frontier);
  return frontier;
}

export function equalCheckRequirementFrontiers(first, second) {
  const left = getCheckRequirementFrontier(first);
  const right = getCheckRequirementFrontier(second);
  if (!left || !right) return undefined;
  return structuralKey(left) === structuralKey(right);
}

// This bounds read-only checking, not an authoritative supplement write.
export function createCheckSupplementationSession(client, {maxAttempts} = {}) {
  if (typeof client?.check !== 'function' || !Number.isSafeInteger(maxAttempts) || maxAttempts < 1) {
    fail('InvalidCheckSupplementationSession');
  }
  let attempts = 0, checking = false, previous, stopped;
  return Object.freeze({
    async check(text, options) {
      if (checking) fail('CheckSupplementationBusy');
      if (stopped || attempts >= maxAttempts) {
        throw new ClientError('CheckSupplementationStopped', {
          decision: stopped ?? Object.freeze({kind: 'stop', reason: 'attempt_budget'}),
          attempts, maxAttempts});
      }
      checking = true;
      attempts++;
      try {
        const outcome = await client.check(text, options);
        const frontier = getCheckRequirementFrontier(outcome);
        let reason;
        if (!frontier) reason = 'frontier_unavailable';
        else if ((outcome.report.verdict !== 'undetermined' &&
            !(outcome.report.scope.kind === 'template_only' && outcome.report.verdict === 'verified')) ||
            frontier.requirements.length === 0) {
          reason = 'no_known_supplement';
        } else if (previous && structuralKey(previous) === structuralKey(frontier)) {
          reason = 'unchanged_frontier';
        } else if (attempts >= maxAttempts) reason = 'attempt_budget';
        const decision = Object.freeze(reason === undefined
          ? {kind: 'more_checks'} : {kind: 'stop', reason});
        if (decision.kind === 'stop') stopped = decision;
        previous = frontier;
        return Object.freeze({outcome, attempts, decision});
      } finally {
        checking = false;
      }
    },
  });
}

const structuredNodeExists = (value, pointer) => {
  if (typeof pointer !== 'string' || pointer.length > 4096 ||
      !/^(?:\/(?:[^~]|~[01])*)*$/u.test(pointer)) return false;
  if (pointer === '') return true;
  for (const token of pointer.slice(1).split('/')) {
    // Decode slash first so a literal ~1 encoded as ~01 stays a member name.
    const key = token.replaceAll('~1', '/').replaceAll('~0', '~');
    if (value === null || typeof value !== 'object') return false;
    if (Array.isArray(value)) {
      if (!/^(?:0|[1-9][0-9]*)$/u.test(key)) return false;
      const index = Number(key);
      if (!Number.isSafeInteger(index) || index >= value.length) return false;
    }
    if (!Object.hasOwn(value, key)) return false;
    value = value[key];
  }
  return true;
};

// Reading original bytes and converting offsets is not parsing the language.
export function resolveCheckLocation(outcome, location, currentInput) {
  const original = getCheckInput(outcome, location?.document_id, location?.revision);
  const input = currentInput ?? original;
  if (!original || !input || location.revision !== original.revision ||
      input.documentId !== original.documentId ||
      input.revision !== original.revision || input.kind !== original.kind ||
      location.kind !== original.kind ||
      (input.kind === 'text' ? input.text !== original.text :
        JSON.stringify(input.value) !== JSON.stringify(original.value))) return undefined;
  if (location.kind === 'structured') {
    if (!structuredNodeExists(original.value, location.pointer)) return undefined;
    return Object.freeze({...location, input: original});
  }
  const bytes = utf8.encode(original.text);
  const boundary = at => Number.isSafeInteger(at) && at >= 0 && at <= bytes.length &&
    (at === bytes.length || (bytes[at] & 0xc0) !== 0x80);
  if (!boundary(location.start_byte) || !boundary(location.end_byte) ||
      location.start_byte > location.end_byte) return undefined;
  return Object.freeze({...location, input: original,
    text: new TextDecoder('utf-8', {fatal: true, ignoreBOM: true})
      .decode(bytes.subarray(location.start_byte, location.end_byte))});
}

// Coordinates describe this submitted revision, never a newer editor buffer.
export function resolveCheckTextRange(outcome, location, currentInput) {
  return resolveCheckTextRangeEncoding(outcome, location, 'utf-16', currentInput);
}

export function resolveCheckTextRangeEncoding(outcome, location, encoding, currentInput) {
  if (!['utf-8', 'utf-16', 'utf-32'].includes(encoding)) return undefined;
  const resolved = resolveCheckLocation(outcome, location, currentInput);
  if (resolved?.kind !== 'text' || !resolved.input.text.isWellFormed()) return undefined;
  const text = resolved.input.text;
  let byte = 0, line = 0, character = 0, start, end;
  for (let at = 0; ; ) {
    if (byte === resolved.start_byte) start = Object.freeze({line, character});
    if (byte === resolved.end_byte) {
      end = Object.freeze({line, character});
      break;
    }
    if (at === text.length) return undefined;
    const scalar = text.codePointAt(at);
    const units = scalar > 0xffff ? 2 : 1;
    let width = scalar <= 0x7f ? 1 : scalar <= 0x7ff ? 2 : scalar <= 0xffff ? 3 : 4;
    if (scalar === 13 && text[at + 1] === '\n') {
      // There is no exact editor position between the two CRLF bytes.
      if (resolved.start_byte === byte + 1 || resolved.end_byte === byte + 1) return undefined;
      at++;
      width++;
    }
    if (scalar === 13 || scalar === 10) { line++; character = 0; }
    else character += encoding === 'utf-8' ? width : encoding === 'utf-16' ? units : 1;
    byte += width;
    at += units;
  }
  return start && Object.freeze({...resolved, positionEncoding: encoding,
    range: Object.freeze({start, end})});
}

// A session owns one current unsaved buffer; replies retain their SDK input custody.
export function createCheckDocumentSession(client, options) {
  const {text, version, positionEncoding = 'utf-16'} = options ?? {};
  const validDocument = (text, version) => typeof text === 'string' && text.isWellFormed() &&
    Number.isInteger(version) && version >= -2147483648 && version <= 2147483647;
  if (typeof client?.check !== 'function' || !validDocument(text, version) ||
      !['utf-8', 'utf-16', 'utf-32'].includes(positionEncoding)) fail('InvalidCheckDocument');
  let current = {text, version}, checker = client, issued = 0n;
  const observations = new WeakMap();
  const currentRecord = observation => {
    const record = observations.get(observation);
    return current && record?.input && record.ticket === issued &&
      observation.version === current.version && record.input.text === current.text ? record : undefined;
  };
  return Object.freeze({
    update(text, version) {
      if (!current) fail('CheckDocumentClosed');
      if (!validDocument(text, version) || version <= current.version) fail('InvalidCheckDocument');
      current = {text, version};
    },
    async check(options) {
      if (!current) fail('CheckDocumentClosed');
      const submitted = current, ticket = ++issued;
      // Call the existing SDK before yielding so it also detaches supplied bindings.
      const outcome = await checker.check(submitted.text, {...options, kind: 'text'});
      const input = getCheckInput(outcome, 'source');
      const observation = Object.freeze({outcome, version: submitted.version, positionEncoding});
      observations.set(observation, {ticket, input: input?.kind === 'text' &&
        input.text === submitted.text ? input : undefined, request: checkRequests.get(outcome)});
      return observation;
    },
    async applyFixes(observation, fixes, options) {
      // Read application accessors before checking the current observation.
      const version = options?.version, reviewed = options?.reviewed;
      const selected = Array.isArray(fixes) ? [...fixes] : undefined;
      const record = currentRecord(observation);
      if (!record?.request) fail('CheckFixStale');
      if (reviewed !== true) fail('CheckFixReviewRequired');
      if (!validDocument(current.text, version) || version <= current.version ||
          !selected?.length || selected.length > 32) fail('InvalidCheckFixes');
      const offered = getCheckFixes(observation.outcome);
      if (selected.some(fix => !offered.includes(fix))) fail('InvalidCheckFixes');
      const edits = selected.flatMap(fix => {
        if (fix.target.document_id !== 'source' ||
            fix.target.revision !== record.input.revision) fail('InvalidCheckFixes');
        return fix.edits;
      }).sort((a, b) => a.start_byte - b.start_byte || a.end_byte - b.end_byte);
      const bytes = utf8.encode(record.input.text);
      const boundary = at => Number.isSafeInteger(at) && at >= 0 && at <= bytes.length &&
        (at === bytes.length || (bytes[at] & 0xc0) !== 0x80);
      for (let i = 0; i < edits.length; i++) {
        const edit = edits[i], previous = edits[i - 1];
        if (!boundary(edit.start_byte) || !boundary(edit.end_byte) ||
            edit.end_byte < edit.start_byte || !edit.replacement.isWellFormed() ||
            (previous && (previous.end_byte > edit.start_byte ||
              previous.start_byte === edit.start_byte))) fail('InvalidCheckFixes');
      }
      const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
      let cursor = 0, text = '';
      for (const edit of edits) {
        text += decoder.decode(bytes.subarray(cursor, edit.start_byte)) + edit.replacement;
        cursor = edit.end_byte;
      }
      text += decoder.decode(bytes.subarray(cursor));
      const checkOptions = {kind: 'text', scope: record.request.scope, format: record.request.input.format,
        parameterDeclarations: record.request.input.parameterDeclarations,
        ...(Object.hasOwn(record.request, 'parameters') ? {parameters: record.request.parameters} : {})};
      const originalClient = checker;
      const assertCurrent = () => {
        if (currentRecord(observation) !== record) fail('CheckFixStale');
      };
      const assertContext = outcome => {
        if (outcome.outcome !== 'completed' ||
            outcome.report.context_ref !== observation.outcome.report.context_ref ||
            getCheckInput(outcome, 'source')?.revision !== record.input.revision ||
            selected.some(fix => !getCheckFixes(outcome)?.some(candidate =>
              structuralKey(candidate) === structuralKey(fix)))) fail('CheckFixContextChanged');
      };
      // Bracket the candidate check with current-context checks of the original
      // request. These are observations, not an authorization lease or execution.
      const before = await originalClient.check(record.input.text, checkOptions);
      assertCurrent(); assertContext(before);
      const outcome = await originalClient.check(text, checkOptions);
      assertCurrent();
      const input = getCheckInput(outcome, 'source');
      if (outcome.outcome !== 'completed' || input?.kind !== 'text' || input.text !== text) {
        fail('CheckFixRecheckUnavailable');
      }
      const after = await originalClient.check(record.input.text, checkOptions);
      assertCurrent(); assertContext(after);
      // Commit the one-document edit and its rechecked observation together,
      // without yielding. No partial update survives a failed check.
      current = {text, version};
      const ticket = ++issued;
      const updated = Object.freeze({outcome, version, positionEncoding});
      observations.set(updated, {ticket, input, request: checkRequests.get(outcome)});
      return updated;
    },
    resolveTextRange(observation, location) {
      const record = currentRecord(observation);
      if (!record ||
          location?.document_id !== 'source' || location?.kind !== 'text') return undefined;
      const range = resolveCheckTextRangeEncoding(observation.outcome, location,
        positionEncoding, record.input);
      // Location accessors can edit, close or issue a newer check while resolving.
      return currentRecord(observation) === record ? range : undefined;
    },
    format(observation, options) {
      let outcome, selected;
      try {
        outcome = observation?.outcome;
        selected = {format: options?.format, maxBytes: options?.maxBytes,
          currentInputs: options?.currentInputs, positionEncoding};
      } catch { return undefined; }
      try { selected.locale = options?.locale; } catch { selected.locale = 'en'; }
      // Read application options before deciding whether editor positions are current.
      const record = currentRecord(observation);
      if (!record) selected.currentInputs = [];
      else if (selected.currentInputs === undefined) selected.currentInputs = [...checkInputs.get(outcome).values()];
      const rendered = formatCheckOutcome(outcome, selected);
      // Input accessors can edit, close or issue a newer check while rendering.
      return record && currentRecord(observation) !== record
        ? formatCheckOutcome(outcome, {...selected, currentInputs: []}) : rendered;
    },
    close() {
      current = undefined;
      checker = undefined;
    },
  });
}

const rejectedCheckHeader = value => {
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
    return Object.fromEntries(['version', 'reason_schema_cid', 'outcome_schema_cid', 'outcome']
      .map(key => [key, Object.getOwnPropertyDescriptor(value, key)?.value]));
  } catch { return undefined; }
};

const rejectedCheckProblem = header => {
  if (!header || !['version', 'reason_schema_cid', 'outcome_schema_cid', 'outcome']
    .every(key => typeof header[key] === 'string' && header[key].length > 0)) return 'malformed_response';
  if (header.version !== checkOutcomeProtocol.version ||
      header.reason_schema_cid !== checkOutcomeProtocol.reasonSchemaCid ||
      header.outcome_schema_cid !== checkOutcomeProtocol.outcomeSchemaCid) return 'contract_mismatch';
  return checkOutcomeProtocol.outcomes.includes(header.outcome)
    ? 'malformed_response' : 'unknown_outcome';
};

const rejectedCheck = (body, problem) => {
  const error = new ClientError('InvalidHostCheckOutcome');
  checkFailures.set(error, freezeInput({problem,
    kind: problem === 'unknown_outcome' ? 'uninterpretable' : 'protocol_failure',
    input: {kind: body.kind, scope: body.scope,
      ...(body.kind === 'program' ? {program: body.input} : {text: body.input.text, format: body.input.format,
      ...(body.input.parameterDeclarations === undefined ? {} :
        {parameterDeclarations: body.input.parameterDeclarations})}),
      ...(Object.hasOwn(body, 'parameters') ? {parameters: body.parameters} : {})}}));
  return error;
};

export function formatCheckOutcome(outcome, options) {
  return renderCheckOutcome(outcome, options, resolveCheckLocation, resolveCheckTextRangeEncoding);
}

// Read-only checking; admission and input custody use the existing wire contract.
export function createCheckOperation(connection, exchange, responseValue) {
  const selected = {wire: connection};
  return {
    check: async (input, options) => {
      if (options === null || typeof options !== 'object' || Array.isArray(options)) fail('InvalidCheckRequest');
      const kind = options.kind, scope = options.scope;
      if (!['text', 'program'].includes(kind) ||
          !['template_only', 'bound_input'].includes(scope) ||
          (kind === 'text' ? typeof input !== 'string' :
            input === null || typeof input !== 'object' || Array.isArray(input)) ||
          (kind === 'program' && (Object.hasOwn(options, 'format') ||
            Object.hasOwn(options, 'parameterDeclarations'))) ||
          (scope === 'template_only' && Object.hasOwn(options, 'parameters'))) fail('InvalidCheckRequest');
      const signal = options.signal;
      let body;
      try {
        // Detach caller-owned objects synchronously, before credentials or I/O.
        body = freezeInput(snapshotClientRequest({kind, scope,
          input: kind === 'program' ? input : {text: input, format: options.format,
            ...(options.parameterDeclarations === undefined ? {} :
              {parameterDeclarations: options.parameterDeclarations})},
          ...(scope === 'bound_input' ? {parameters: options.parameters ?? null} : {})}));
      } catch { fail('InvalidCheckRequest'); }
      if (!validClientBody('check', {connection: selected.wire, ...body})) {
        fail('InvalidCheckRequest');
      }
      const response = await exchange('check', body, signal);
      let outcome;
      try { outcome = await responseValue(response); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw rejectedCheck(body, 'malformed_response');
      }
      try { outcome = captureResponse(outcome); }
      catch { throw rejectedCheck(body, 'malformed_response'); }
      const header = rejectedCheckHeader(outcome);
      const reject = () => { throw rejectedCheck(body, rejectedCheckProblem(header)); };
      try {
        if (!validCheckOutcome(outcome)) reject();
        if (!bindCheckObservation(outcome, body)) reject();
      } catch (cause) {
        checkInputs.delete(outcome);
        if (checkFailures.has(cause)) throw cause;
        throw rejectedCheck(body, 'malformed_response');
      }
      checkRequests.set(outcome, body);
      return freezeInput(outcome);
    },
      }.check;
}
