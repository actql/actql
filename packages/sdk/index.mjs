// The transport Client delegates admission, state and delivery to the Host.
import {checkpointLimits, clientSourceFormats, isClientSubmitRejection, validCancellation, validCheckpointPage,
  validCheckpointReview, validClientAdmission, validClientConnection,
  validClientProfile, validDeliveryAttemptLookup, validRequestCancellation,
  validRequestLookup,
  validResolveItem, validResolveResults, validRunRef, validRunState,
  validSubmitReply, validClientBody, validResourceInspection,
  validResourceListing, validResourcePeek, resultDescriptionLimits,
  validResultDescription, validCheckOutcome, snapshotCheckRequest} from
  '@actql/client-wire';
import {reviewBytesMatchCid, contentCid, checkedSigner, signedAnswer} from './checkpoints.mjs';
import {jsonValueWireContractCid} from './json-value-wire.generated.mjs';
import {localizeCheck, getCheckPresentationInfo} from './check-presentation.mjs';
export {getCheckPresentationInfo} from './check-presentation.mjs';
import {localizeOperation} from './operation-presentation.mjs';
export {getOperationPresentationInfo} from './operation-presentation.mjs';
// The response owns only a weak association to this call's immutable inputs.
// A parsed/copied report has no such association and cannot resolve a location.
const checkInputs = new WeakMap();
const checkRequests = new WeakMap();
const checkFrontiers = new WeakMap();
// Original request data is available only through explicit SDK access, never
// by serializing an error or Run handle. It does not establish acceptance.
const submissionInputs = new WeakMap();
const submissionContexts = new WeakMap();
// Presentation is bound by the validated submit branch, never an error string.
const submissionExplanations = new WeakMap();
// Validated observations keep only a weak, immutable presentation snapshot.
// This is not an Effect ledger or a certificate joining Owner revisions.
const effectUncertainties = new WeakMap();
// Presentation retains validated Run-control observations, not another owner.
const cancellationExplanations = new WeakMap();
const readExplanations = new WeakMap();
const readerContexts = new WeakMap();
const utf8 = new TextEncoder();
const freezeInput = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeInput(child);
    Object.freeze(value);
  }
  return value;
};

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

// Compare typed public obligations, never translated explanations or severity.
const structuralKey = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(structuralKey).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + structuralKey(value[key])).join(',') + '}'
  : JSON.stringify(value);
const unordered = values => [...new Map(values.map(value =>
  [structuralKey(value), value])).entries()].sort(([left], [right]) =>
  left < right ? -1 : left > right ? 1 : 0).map(([, value]) => value);

export function getCheckRequirementFrontier(outcome) {
  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed') return undefined;
  if (checkFrontiers.has(outcome)) return checkFrontiers.get(outcome);
  const report = outcome.report;
  // These are the currently exposed typed Requirements. Unknown obligations
  // cannot supply a structural admission condition for supplementation.
  if (report.requirements.some(reason => reason.code !== 'parameter_value_required')) return undefined;
  const frontier = freezeInput({contextRef: report.context_ref,
    reasonSchemaCid: outcome.reason_schema_cid,
    scope: {...report.scope}, requirements: unordered(report.requirements.map(({code, facts}) =>
      ({code, facts}))),
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
        else if (outcome.report.verdict !== 'undetermined' || frontier.requirements.length === 0) {
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

export function getSubmissionInput(result) {
  return submissionInputs.get(result);
}

// Local observation of this SDK read only. Lookup rechecks current authority;
// this explanation proves neither publication nor execution nor resource release.
export function explainReadFailure(result, options) {
  return localizeOperation(readExplanations.get(result), 'read', options);
}

export function explainSubmission(result, options) {
  return localizeOperation(submissionExplanations.get(result), 'submission', options);
}

export function explainEffectUncertainty(state, options) {
  return localizeOperation(effectUncertainties.get(state), 'effect', options);
}

const retainEffectUncertainty = (state, ref) => {
  if (state.status === 'needs_reconciliation' &&
      state.next_action.kind === 'reconcile') {
    // A Local port may reuse a cached object for another observation/Run.
    // Each returned SDK response must keep its own original association.
    try { state = structuredClone(state); }
    catch { fail('InvalidHostRunState'); }
    // A Local value can lose fields when copied. Retain only a validated
    // copied reconciliation state, before reading or explaining its facts.
    if (!validRunState(state) || state.status !== 'needs_reconciliation' ||
        state.next_action.kind !== 'reconcile') fail('InvalidHostRunState');
    effectUncertainties.set(state, freezeInput({
      observation: 'effect_outcome_unknown',
      summary: 'External Effect outcomes are unknown. Computation stop does not establish their outcome or resource release.',
      effects: [...state.next_action.effects],
      physicalStop: state.control?.physical_stop ?? 'unknown',
      ...(state.control === undefined ? {} :
        {controlRevision: state.control.revision}),
      next: {operation: 'status', ref: {...ref}},
    }));
  }
  return state;
};

export function explainCancellation(result, options) {
  return localizeOperation(cancellationExplanations.get(result), 'cancellation', options);
}

const retainCancellationExplanation = (result, context, observation, revision) => {
  if (!context) return result;
  const summaries = {
    accepted: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.',
    already_requested: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.',
    already_terminal: 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.',
    outcome_unknown: 'The Run cancellation outcome is unknown. The request may have been recorded.',
  };
  cancellationExplanations.set(result, freezeInput({observation,
    ...(revision === undefined ? {} : {revision}), summary: summaries[observation],
    next: {operation: 'status', ref: context.ref}}));
  return result;
};

const submissionLookupExplanation = (observation, input) => freezeInput({
  observation,
  summary: observation === 'acceptance_unknown'
    ? 'Submission acceptance is unknown. Work may already have started.'
    : 'The Host returned a held-request response. Look up the current request state.',
  next: {operation: 'lookupRequest', requestId: input.requestId,
    lookupContext: input.lookupContext},
});

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
      const outcome = await checker.check(submitted.text, options);
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
      const checkOptions = {format: record.request.input.format,
        parameterDeclarations: record.request.input.parameterDeclarations,
        parameters: record.request.parameters};
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
      return resolveCheckTextRangeEncoding(observation.outcome, location,
        positionEncoding, record.input);
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

// Presentation never participates in verdicts, admission or retry decisions.
export function explainCheckOutcome(outcome, options) {
  if (!validCheckOutcome(outcome)) return undefined;
  const reportExplanation = (report, completeness) => ({completeness,
    verdict: report.verdict, scope: {...report.scope}, contextRef: report.context_ref});
  if (outcome.outcome === 'completed') {
    const explanations = {
      invalid: ['The report establishes an input violation in its checking scope.',
        'Review the disclosed reasons and correct the submitted revision where indicated.'],
      verified: ['The report verifies only its bound checking scope and context.',
        'Use the execution, cancellation and release owners for their respective results.'],
      undetermined: ['The report cannot establish verification or a proven input violation in its checking scope.',
        'Review missing inputs and disclosed checking limits; an outstanding obligation is not an input error.'],
    };
    // Capture observation fields before reading application-owned locale options.
    const report = reportExplanation(outcome.report, 'complete');
    const [summary, hint] = localizeCheck(`completed.${report.verdict}`,
      explanations[report.verdict], options);
    return freezeInput({outcome: 'completed', summary, hint, report});
  }
  if (outcome.outcome === 'failed') {
    const explanations = {
      check_report_unbounded: ['The reporting budget could not produce a complete bound check report.',
        'Ask the checking-context owner to review reporting capacity for the original checking scope.'],
      check_internal: ['An internal checking failure prevented a complete bound check report.',
        'Ask the checking-context owner to investigate the reporting failure.'],
    };
    const known = Object.hasOwn(explanations, outcome.problem.code);
    const problem = {kind: known ? 'known' : 'unknown', code: outcome.problem.code};
    const correlationRef = outcome.correlation_ref;
    const report = outcome.partial_report === undefined ? undefined
      : reportExplanation(outcome.partial_report, 'partial');
    const [summary, hint] = localizeCheck(`failed.${known ? problem.code : 'unknown'}`,
      known ? explanations[problem.code]
      : ['A complete bound check report could not be issued; this problem code has no supported explanation.',
        'Ask the checking-context owner to investigate; a partial report does not verify the input.'], options);
    return freezeInput({outcome: 'failed', summary, hint, correlationRef, problem,
      ...(report === undefined ? {} : {report})});
  }
  const problem = {kind: outcome.problem.code === 'check_unavailable' ? 'known' : 'unknown',
    code: outcome.problem.code};
  const correlationRef = outcome.correlation_ref;
  const [summary, hint] = localizeCheck('unavailable',
    ['The scope and checking context needed for a safe public report are unavailable.',
      'Ask the checking-context owner to review the published context; this response does not establish an input error.'], options);
  return freezeInput({outcome: 'unavailable', summary, hint, problem, correlationRef});
}


// Presentation formats consume the disclosed report, never internal causes.
// Escape untrusted controls and bidi marks without changing source identity.
const checkDisplayString = value => JSON.stringify(value).replace(
  /[\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
const checkHtml = value => value.replace(/[&<>"']/gu, character =>
  ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[character]);
const checkAgentJson = value => JSON.stringify(value).replace(
  /[<>&\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));

/** Format a validated public observation without granting actions or input access. */
export function formatCheckOutcome(outcome, options) {
  let snapshot;
  try {
    if (!validCheckOutcome(outcome)) return undefined;
    snapshot = JSON.parse(JSON.stringify(outcome));
    if (!validCheckOutcome(snapshot)) return undefined;
  } catch { return undefined; }
  let format, maxBytes, currentInputs, locale, positionEncoding;
  try {
    format = options?.format ?? 'text';
    maxBytes = options?.maxBytes ?? 65536;
    currentInputs = options?.currentInputs;
    positionEncoding = options?.positionEncoding ?? 'utf-16';
  } catch { return undefined; }
  try { locale = options?.locale; } catch { locale = 'en'; }
  if (!['text', 'html', 'json'].includes(format) || !['utf-8', 'utf-16', 'utf-32'].includes(positionEncoding) || !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1024 || maxBytes > 1048576) return undefined;
  const presentation = getCheckPresentationInfo({locale});
  const observation = explainCheckOutcome(snapshot, {locale: presentation.locale});
  const report = snapshot.outcome === 'completed' ? snapshot.report : snapshot.partial_report;
  const rows = report === undefined ? [] : [
    ...report.reasons.map(reason => ({kind: 'violation', reason})),
    ...report.requirements.map(reason => ({kind: 'requirement', reason})),
    ...report.coverage.limits.map(reason => ({kind: 'limit', reason})),
    ...report.coverage.unresolved.map(({reason, boundary}) =>
      ({kind: 'unresolved', reason: {code: reason}, boundary})),
  ];
  const entries = [];
  const model = () => ({observation, presentation, entries, omittedEntries: rows.length - entries.length,
    reasonSchemaCid: snapshot.reason_schema_cid, outcomeSchemaCid: snapshot.outcome_schema_cid});
  const line = entry => entry.kind + ': ' + checkDisplayString(entry.code) + ' ' + entry.summary +
    (entry.hint === undefined ? '' : ' ' + entry.hint) +
    (entry.facts === undefined ? '' : ' facts=' + checkDisplayString(entry.facts)) +
    (entry.boundary === undefined ? '' : ' boundary=' + checkDisplayString(entry.boundary)) +
    (entry.location === undefined ? '' : ' location=' + checkDisplayString(entry.location));
  const render = () => {
    if (format === 'json') return checkAgentJson(model());
    const heading = observation.outcome +
      (observation.report === undefined ? '' : '/' + observation.report.verdict +
        ' (' + observation.report.completeness + ')') + ': ' + observation.summary;
    const binding = observation.report === undefined ?
      'Correlation: ' + checkDisplayString(observation.correlationRef) :
      'Scope: ' + observation.report.scope.kind + '; context_ref: ' + checkDisplayString(observation.report.contextRef);
    const omitted = rows.length - entries.length;
    const suffix = omitted ? `Omitted entries: ${omitted}. The observation above is unchanged.` : '';
    if (format === 'html') return '<section><h2>' + checkHtml(heading) + '</h2><p>' +
      checkHtml(observation.hint) + '</p><p>' + checkHtml(binding) + '</p><ol>' + entries.map(entry => '<li>' +
        checkHtml(line(entry)) + '</li>').join('') + '</ol><p>' + checkHtml(suffix) + '</p></section>';
    return [heading, observation.hint, binding, ...entries.map(line), suffix].filter(Boolean).join('\n');
  };
  let output = render();
  if (utf8.encode(output).length > maxBytes) return undefined;
  for (const row of rows) {
    const explanation = explainCheckReason(row.reason, {locale: presentation.locale});
    const {kind: explanationKind, ...display} = explanation;
    const entry = {kind: row.kind, code: row.reason.code, ...display, explanationKind};
    if (explanation.kind === 'known' && row.reason.facts !== undefined) entry.facts = row.reason.facts;
    if (row.boundary !== undefined) entry.boundary = row.boundary;
    try {
      const location = row.reason.location;
      const current = currentInputs === undefined ? undefined :
        Array.isArray(currentInputs) ? currentInputs.find(input => input?.documentId === location?.document_id) : undefined;
      // An explicitly supplied current-input set never silently uses older input.
      const resolved = currentInputs !== undefined && current === undefined ? undefined :
        resolveCheckLocation(outcome, location, current);
      if (resolved) {
        entry.location = {kind: resolved.kind, documentId: resolved.document_id, revision: resolved.revision,
          ...(resolved.kind === 'structured' ? {pointer: resolved.pointer} :
            {startByte: resolved.start_byte, endByte: resolved.end_byte, precision: resolved.precision})};
        const range = resolved.kind === 'text' && resolveCheckTextRangeEncoding(outcome, location, positionEncoding, current);
        if (range) Object.assign(entry.location, {positionEncoding: range.positionEncoding, range: range.range});
      }
    } catch { /* Missing or malformed editor input cannot hide safe explanations. */ }
    entries.push(entry);
    const candidate = render();
    if (utf8.encode(candidate).length > maxBytes) { entries.pop(); break; }
    output = candidate;
  }
  return output;
}

// Reason presentation does not decide the report's verdict or outcome branch.
export function explainCheckReason(reason, options) {
  const explanations = {
    query_syntax_invalid: ['The query syntax is invalid.', 'Correct the query syntax at the reported location when available.'],
    query_expression_invalid: ['An expression violates its reference, argument or numeric contract.', 'Correct the expression under the selected query contract.'],
    query_frame_invalid: ['The analytic ROWS frame boundaries do not form a valid interval.',
      'For two PRECEDING boundaries, the start distance must be at least the end distance; for two FOLLOWING boundaries, it must be at most the end distance.'],
    query_lexical_invalid: ['A query token violates its lexical syntax.', 'Correct the token at the reported location when available.'],
    parameter_undeclared: ['The query refers to an undeclared parameter.', 'Declare the parameter or correct its reference; a value alone cannot declare it.'],
    parameter_unused: ['A declared parameter is not used by the complete Program.',
      'Remove the unused declaration or reference the parameter in the Program, then check again.'],
    query_invalid: ['The query violates its language or name-resolution contract.', 'Correct the query using its declared names and visible context.'],
    parameter_declarations_invalid: ['The parameter declarations are invalid.', 'Correct the supplied declarations.'],
    supplied_parameters_invalid: ['The supplied parameter input is invalid.', 'Correct the supplied parameter map.'],
    supplied_value_invalid: ['A supplied value violates its declaration.', 'Correct the value to satisfy its declared contract.'],
    supplied_value_constraint_violation: ['A supplied value violates a declared constraint.', 'Correct the value to satisfy the declared constraint family.'],
    supplied_value_type_mismatch: ['A supplied value has the wrong type.', 'Supply a value of the declared type.'],
    parameter_value_required: ['A declared parameter value is missing.', 'Supply the declared value and check the complete bound input again.'],
    parameter_default_type_mismatch: ['A parameter default does not match its declared type.',
      'Correct the default to match the declared type, then check again.'],
    expression_type_mismatch: ['An expression violates its required argument type.', 'Use an argument with the required type.'],
    operation_parameter_invalid: ['A parameter violates an operation scalar domain.', 'Correct the supplied value or selected default under the reported operation domain.'],
    program_invalid: ['The input violates the checked Program contract.', 'Correct the input under the selected contract.'],
    bound_values_missing: ['Required bound inputs are missing.', 'Supply the declared inputs and check again.'],
    implementation_limit: ['This checking implementation cannot discharge an obligation.', 'Ask the checking-context owner to review support for the submitted construct.'],
    analysis_budget_exhausted: ['The analysis budget was exhausted.', 'Ask the checking-context owner to review the analysis budget.'],
    check_unclassified: ['The checker could not establish a classified conclusion.', 'Ask the checking-context owner to investigate.'],
    unresolved_protected: ['Source resolution cannot be established from the disclosed context.', 'Ask the Source or checking-context owner to review the published context.'],
  };
  const known = Object.hasOwn(explanations, reason?.code) ? explanations[reason.code] : undefined;
  const expressionTypes = {
    number: ['An expression argument must have number type.', 'Use an expression with number type for the rejected argument.'],
    boolean: ['An expression argument must have boolean type.', 'Use an expression with boolean type for the rejected argument.'],
    string: ['An expression argument must have string type.', 'Use an expression with string type for the rejected argument.'],
  };
  const expectedType = reason?.facts?.expected_type;
  if (reason?.code === 'expression_type_mismatch' && typeof expectedType === 'string' &&
      Object.hasOwn(expressionTypes, expectedType)) {
    const [summary, hint] = localizeCheck(`expression_type.${expectedType}`, expressionTypes[expectedType], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const scalarExplanations = {
    positive_safe_integer: ['An operation parameter must be a positive safe integer.',
      'Supply an integer from 1 through 9007199254740991.'],
    nonnegative_safe_integer: ['An operation parameter must be a nonnegative safe integer.',
      'Supply an integer from 0 through 9007199254740991; negative zero is not admitted.'],
    unit_fraction: ['An operation parameter must be a finite fraction between 0 and 1.',
      'Supply a number from 0 through 1, inclusive; negative zero is not admitted.'],
    finite_number: ['An operation parameter must be a finite number.',
      'Supply a finite number; negative zero is not admitted.'],
    duration: ['An operation parameter must be an admitted duration.',
      'Supply positive ASCII digits followed by ms, s, m, h or d, without whitespace; the milliseconds must fit a safe integer.'],
    positive_milliseconds: ['An operation parameter must be positive safe milliseconds or an admitted duration.',
      'Supply a positive safe integer of milliseconds, or a positive duration string with ms, s, m, h or d.'],
    signed_milliseconds: ['An operation parameter must be signed safe milliseconds or an admitted duration.',
      'Supply integer milliseconds from -9007199254740991 through 9007199254740991 without negative zero, or a positive duration string.'],
    timestamp: ['An operation parameter must be an admitted timestamp value.',
      'Supply a non-null timestamp value admitted by the timestamp declaration contract.'],
  };
  const domain = reason?.facts?.domain;
  if (reason?.code === 'operation_parameter_invalid' && typeof domain === 'string' &&
      Object.hasOwn(scalarExplanations, domain)) {
    const [summary, hint] = localizeCheck(`scalar.${domain}`, scalarExplanations[domain], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const lexicalExplanations = {
    unexpected_end: ['The input ends before a token is complete.', 'Complete the quoted token or escape sequence at the reported position.'],
    unexpected_token: ['A token is not valid in this lexical context.', 'Correct the token spelling or delimiter at the reported position.'],
    invalid_escape: ['An escape sequence is invalid.', 'Use an escape allowed by the selected string or identifier syntax.'],
    invalid_scalar: ['A token contains a scalar forbidden by its lexical context.', 'Correct the scalar escape or quoted identifier under the selected lexical syntax.'],
    empty_identifier: ['A quoted identifier is empty.', 'Provide a non-empty identifier inside the quoting delimiters.'],
    unterminated_comment: ['A block comment is not terminated.', 'Add the closing block-comment delimiter.'],
    invalid_number: ['A numeric token has invalid spelling.', 'Correct the numeric token, including any exponent.'],
    invalid_parameter: ['A parameter reference lacks a valid name.', 'Provide a valid parameter name after @.'],
  };
  const issue = reason?.facts?.issue;
  const jsonExplanations = {
    invalid_unicode: ['The binding JSON contains invalid Unicode text.', 'Use valid Unicode scalar values in member names and string values.'],
    unexpected_end: ['The binding JSON ends before a value is complete.', 'Complete the JSON value and its closing delimiters.'],
    unexpected_token: ['The binding JSON contains an unexpected token.', 'Use a token allowed by JSON at the reported input location.'],
    invalid_string: ['A binding JSON string is invalid.', 'Quote the string and escape control characters using JSON syntax.'],
    invalid_escape: ['A binding JSON escape is invalid.', 'Use an escape sequence allowed by JSON.'],
    invalid_number: ['A binding JSON number has invalid spelling.', 'Use a valid JSON number, including a complete exponent when present.'],
    number_out_of_range: ['A binding JSON number is outside the admitted numeric range.', 'Use a number within the selected input numeric contract.'],
    negative_zero: ['The binding JSON contains inadmissible negative zero.', 'Use an admitted numeric value; negative zero is not admitted.'],
    expected_colon: ['A binding JSON member is missing its colon.', 'Separate the member name and value with a colon.'],
    expected_array_separator: ['Binding JSON array elements are not separated correctly.', 'Use commas between array elements and a closing bracket.'],
    expected_object_separator: ['Binding JSON object members are not separated correctly.', 'Use commas between object members and a closing brace.'],
    duplicate_key: ['Two binding JSON member names compare equal under the admitted key rules.', 'Choose distinct member names under the input normalization rules.'],
    trailing_content: ['Unexpected content follows the binding JSON value.', 'Submit one complete JSON value without trailing content.'],
  };
  if (reason?.code === 'binding_json_invalid' &&
      ['parameters', 'parameter_declarations'].includes(reason?.facts?.document) &&
      typeof issue === 'string' && Object.hasOwn(jsonExplanations, issue)) {
    const [summary, hint] = localizeCheck(`binding_json.${issue}`, jsonExplanations[issue], options);
    return Object.freeze({kind: 'known', summary, hint});
  }

  if (reason?.code === 'query_lexical_invalid' && typeof issue === 'string' &&
      Object.hasOwn(lexicalExplanations, issue)) {
    const [summary, hint] = localizeCheck(`lexical.${issue}`, lexicalExplanations[issue], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const expressionExplanations = {
    expected_boolean: ['A predicate must have Boolean type.', 'Use a Boolean condition, such as a comparison, in the predicate.'],
    unknown_reference: ['An expression reference cannot be resolved in the checked scope.', 'Use a declared reference from the disclosed query context.'],
    invalid_arguments: ['Expression arguments violate the selected operation contract.', 'Correct the argument count or form required by the selected operation.'],
    invalid_number: ['A numeric expression is outside the admitted numeric domain.', 'Use a finite number in the admitted precision and signed-zero domain.'],
  };
  if (reason?.code === 'query_expression_invalid' && typeof issue === 'string' &&
      Object.hasOwn(expressionExplanations, issue)) {
    const [summary, hint] = localizeCheck(`expression.${issue}`, expressionExplanations[issue], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const graphExplanations = {
    invalid_kind: ['The components kind is invalid.', 'Choose weak or strong for components kind.'],
    invalid_output_rows: ['The components output row limit is invalid.', 'Supply a positive safe integer for components max_output_rows.'],
  };
  if (reason?.code === 'graph_operation_invalid' &&
      reason?.facts?.operation === 'components' && typeof issue === 'string' &&
      Object.hasOwn(graphExplanations, issue)) {
    const [summary, hint] = localizeCheck(`components.${issue}`, graphExplanations[issue], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  if (reason?.code === 'graph_operation_invalid' &&
      reason?.facts?.operation === 'subgraph' && issue === 'invalid_node_selector') {
    const [summary, hint] = localizeCheck('subgraph.invalid_node_selector',
      ['The Subgraph node selector is invalid.',
        'Provide one selector: nonempty ids, a named Relation with an id field, or a node where predicate.'], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const constraintHints = {
    numeric: 'Supply a number satisfying the declared integer, minimum and maximum constraints.',
    duration: 'Supply a string in the admitted duration format.',
    array_length: 'Supply an array with the declared exact length.',
    array_size: 'Supply an array within the declared maximum item count.',
  };
  const constraint = reason?.facts?.constraint;
  if (reason?.code === 'supplied_value_constraint_violation' &&
      typeof constraint === 'string' && Object.hasOwn(constraintHints, constraint)) {
    const [summary, hint] = localizeCheck(`constraint.${constraint}`, [known[0], constraintHints[constraint]], options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  if (known) {
    const [summary, hint] = localizeCheck(`reason.${reason.code}`, known, options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const [summary] = localizeCheck('reason.unknown', ['No supported explanation is available for this reason.'], options);
  return Object.freeze({kind: 'unknown', summary});
}

const positive = value => Number.isSafeInteger(value) && value > 0;
const maxControlResponseBytes = 1024 * 1024;

export class ClientError extends Error {
  constructor(code, details = {}) {
    super(code, details.cause === undefined ? undefined : {cause: details.cause});
    this.code = code;
    Object.assign(this, details);
  }
}
const fail = code => { throw new ClientError(code); };
const submissionUnknown = (context, cause) => {
  const result = new ClientError('SubmissionUnknown', {...context, cause});
  const input = submissionContexts.get(context);
  if (input) submissionInputs.set(result, input);
  if (input) submissionExplanations.set(result,
    submissionLookupExplanation('acceptance_unknown', input));
  return result;
};
const retainReadExplanation = (result, context, rowsYielded, observation, cleanupUnknown = false) => {
  const quantity = `${rowsYielded} ${rowsYielded === 1 ? 'row' : 'rows'}`;
  readExplanations.set(result, freezeInput({observation,
    ...(cleanupUnknown ? {cleanup: 'unknown'} : {}),
    attemptId: context.attemptId, rowsYielded,
    summary: observation === 'cleanup_unknown'
      ? `Reader cleanup could not be confirmed after returning ${quantity}.`
      : `This read stopped after returning ${quantity}.`,
    hint: 'Keep this read reference. Look it up before deciding whether to open a new read from the beginning.',
    next: {operation: 'deliveryAttempt', ref: context.ref,
      resultName: context.resultName, attemptId: context.attemptId,
      lookupContext: context.lookupContext},
  }));
  return result;
};
const readFailure = (cause, context, rowsYielded, prior) => retainReadExplanation(new ClientError(
  typeof cause?.code === 'string' ? cause.code : 'ResultReadUnknown',
  {attemptId: context.attemptId, rowsYielded, cause,
    ...(cause?.cleanupError === undefined ? {} : {cleanupError: cause.cleanupError})}),
context, rowsYielded, prior?.observation ?? 'read_incomplete', prior?.cleanup === 'unknown');

// The Host accepted and durably holds the request, but no Run exists yet:
// it waits on a `prepare_attempt` Checkpoint, is resuming, or ended without
// a Run. This is a control result, not a failure and not an unknown
// submission: submitting again is never needed. Follow it with
// `lookupRequest(requestId)`; once the Run exists the lookup is `found`.
export class RequestHeld extends ClientError {
  constructor(held, lookupContext) {
    super('RequestHeld', {requestId: held.requestId, held, lookupContext});
  }
}

// Payload bytes and JSON wire bytes are different budgets. A JSON string
// needs at most six wire bytes per UTF-8 byte (escaped ASCII controls).
// Resource metadata has at most 102 bounded names of 256 characters each;
// six bytes per UTF-16 code unit also bounds escaped surrogate pairs.
const resourceEnvelopeBytes = 102 * (256 * 6 + 3) + 1024;
const reviewEnvelopeBytes = 1024;
const jsonPayloadWireBytes = bytes => 6 * bytes + resourceEnvelopeBytes;

async function boundedHostJson(response,
  maxWireBytes = maxControlResponseBytes) {
  const declared = response.headers.get('content-length');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('InvalidHostControlResponse');
  let complete = false;
  try {
    if (declared !== null && Number(declared) > maxWireBytes) {
      throw new Error('HostControlResponseLimit');
    }
    const chunks = [];
    let size = 0;
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxWireBytes) {
        throw new Error('HostControlResponseLimit');
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const parsed = JSON.parse(new TextDecoder('utf-8', {fatal: true})
      .decode(bytes));
    complete = true;
    return parsed;
  } finally {
    if (!complete) {
      try { await reader.cancel(); } catch {}
    }
    reader.releaseLock();
  }
}

const controlValue = (response, maxWireBytes) => response instanceof Response
  ? boundedHostJson(response, maxWireBytes) : response;

function inProcessOptions(options) {
  if (options === null || typeof options !== 'object' ||
      Array.isArray(options) || options.mode !== 'local' ||
      options.owner !== 'local' || options.endpoint !== undefined ||
      options.token !== undefined ||
      options.runtime !== undefined && options.runtime !== 'embedded' ||
      Object.keys(options).some(key => ![
        'mode', 'owner', 'runtime', 'durability', 'consentRefs',
      ].includes(key)) ||
      options.durability !== undefined &&
        !['volatile', 'durable'].includes(options.durability) ||
      !Array.isArray(options.consentRefs ?? []) ||
      (options.consentRefs ?? []).some(value =>
        typeof value !== 'string' || !value) ||
      new Set(options.consentRefs ?? []).size !==
        (options.consentRefs ?? []).length) {
    fail('InvalidConnectionOptions');
  }
  const wire = Object.freeze({mode: 'local', owner: 'local',
    ...(options.durability === undefined ? {} :
      {durability: options.durability}),
    consentRefs: Object.freeze([...(options.consentRefs ?? [])]),
    runners: Object.freeze([])});
  if (!validClientConnection(wire)) fail('InvalidConnectionOptions');
  return Object.freeze({wire, endpoint: 'actql:embedded'});
}

function connectionOptions(options) {
  if (options === null || typeof options !== 'object' ||
      Array.isArray(options)) fail('InvalidConnectionOptions');
  const {mode, owner, endpoint, token, durability, consentRefs, runners,
    movementPolicyRef, cloudConnectionRef} = options;
  if (endpoint === undefined && (mode === 'local' ||
      mode === 'hybrid' && owner === 'local')) {
    throw new ClientError('LocalProviderNotInstalled', {
      hint: 'Install a Local Host or provide its explicit endpoint.',
    });
  }
  if (!(mode === 'remote' && owner === undefined ||
        mode === 'local' && owner === 'local' ||
        mode === 'hybrid' && ['local', 'cloud'].includes(owner)) ||
      typeof endpoint !== 'string' ||
      typeof token !== 'string' && typeof token !== 'function' ||
      durability !== undefined && !['volatile', 'durable'].includes(durability) ||
      !Array.isArray(consentRefs ?? []) ||
      (consentRefs ?? []).some(value => typeof value !== 'string' || !value) ||
      new Set(consentRefs ?? []).size !== (consentRefs ?? []).length ||
      !Array.isArray(runners ?? []) ||
      (runners ?? []).some(value => typeof value !== 'string' || !value) ||
      new Set(runners ?? []).size !== (runners ?? []).length ||
      movementPolicyRef !== undefined &&
        (typeof movementPolicyRef !== 'string' || !movementPolicyRef) ||
      cloudConnectionRef !== undefined &&
        (typeof cloudConnectionRef !== 'string' || !cloudConnectionRef)) {
    fail('InvalidConnectionOptions');
  }
  if (mode !== 'hybrid' && (runners !== undefined ||
      movementPolicyRef !== undefined || cloudConnectionRef !== undefined) ||
      mode === 'hybrid' && (movementPolicyRef === undefined ||
        owner === 'local' && cloudConnectionRef === undefined ||
        owner === 'cloud' && (cloudConnectionRef !== undefined ||
          runners === undefined || runners.length === 0))) {
    fail('InvalidHybridConnection');
  }
  let url;
  try { url = new URL(endpoint); }
  catch { fail('InvalidConnectionEndpoint'); }
  const loopback = mode === 'local' && url.protocol === 'http:' &&
    ['127.0.0.1', '[::1]'].includes(url.hostname);
  if (!(url.protocol === 'https:' || loopback) ||
      url.username || url.password ||
      url.search || url.hash || url.pathname !== '/') {
    fail('InvalidConnectionEndpoint');
  }
  const wire = Object.freeze({
    mode, owner: owner ?? 'remote',
    ...(durability === undefined ? {} : {durability}),
    consentRefs: Object.freeze([...(consentRefs ?? [])]),
    runners: Object.freeze([...(runners ?? [])]),
    ...(movementPolicyRef === undefined ? {} : {movementPolicyRef}),
    ...(cloudConnectionRef === undefined ? {} : {cloudConnectionRef}),
  });
  if (!validClientConnection(wire)) fail('InvalidConnectionOptions');
  return Object.freeze({endpoint: url.href, token, wire});
}

function tighter(requested, maximum) {
  if (requested === undefined) return maximum;
  if (!positive(requested) || requested > maximum) fail('InvalidReadLimit');
  return requested;
}

// A decoded-value accounting bound, not an operating-system RSS measurement.
function retainedValueBytes(value) {
  let nodes = 0;
  const visit = item => {
    nodes++;
    if (Array.isArray(item)) item.forEach(visit);
    else if (item !== null && typeof item === 'object') {
      for (const [key, entry] of Object.entries(item)) {
        nodes++; visit(key); visit(entry);
      }
    }
  };
  visit(value);
  return new TextEncoder().encode(JSON.stringify(value)).byteLength + nodes * 64;
}

export async function connect(options) {
  return connectSelected(connectionOptions(options));
}

// Only an installed Local provider calls this pure Client facade. The port
// returns typed control values and Result frames; it is never a public URL.
export async function connectInProcess(options, port) {
  if (port === null || typeof port !== 'object' ||
      typeof port.perform !== 'function') fail('InvalidLocalHostPort');
  return connectSelected(inProcessOptions(options), port);
}

async function connectSelected(selected, port) {
  let closed = false;
  const exchange = async (operation, body = {}, signal, submitContext, cancellationContext) => {
    if (closed) fail('ClientClosed');
    if (port !== undefined) {
      let request;
      try { request = structuredClone({connection: selected.wire, ...body}); }
      catch { fail('InvalidClientPayload'); }
      try {
        const value = await port.perform(operation, request, signal);
        if (value instanceof Response) {
          throw retainCancellationExplanation(new ClientError('InvalidLocalHostPortResponse'),
            cancellationContext, 'outcome_unknown');
        }
        return value;
      }
      catch (cause) {
        if (operation === 'submit') {
          if (isClientSubmitRejection(cause?.code)) {
            throw new ClientError(cause.code, {cause});
          }
          throw submissionUnknown(submitContext, cause);
        }
        if (cause instanceof ClientError) {
          throw cause;
        }
        throw retainCancellationExplanation(new ClientError('ClientTransportUnknown', {cause}),
          cancellationContext, 'outcome_unknown');
      }
    }
    let payload;
    try { payload = JSON.stringify({connection: selected.wire, ...body}); }
    catch { fail('InvalidClientPayload'); }
    if (typeof payload !== 'string') fail('InvalidClientPayload');
    const credential = typeof selected.token === 'function'
      ? await selected.token() : selected.token;
    if (typeof credential !== 'string' || !credential ||
        /[\r\n]/u.test(credential)) fail('InvalidConnectionToken');
    let response;
    try {
      response = await fetch(new URL(
        `actql/client/0.1/${operation}`, selected.endpoint,
      ), {
        method: 'POST',
        headers: {authorization: `Bearer ${credential}`,
          'content-type': 'application/json'},
        body: payload,
        signal,
        redirect: 'error',
      });
    } catch (cause) {
      if (operation === 'submit') {
        throw submissionUnknown(submitContext, cause);
      }
      throw retainCancellationExplanation(new ClientError('ClientTransportUnknown', {cause}),
          cancellationContext, 'outcome_unknown');
    }
    if (!response.ok) {
      let error;
      try { error = await boundedHostJson(response); } catch {}
      const code = typeof error?.code === 'string' &&
        /^[A-Za-z][A-Za-z0-9_]{0,79}$/u.test(error.code)
        ? error.code : `HostHTTP${response.status}`;
      if (operation === 'submit' && (response.status >= 500 ||
          !isClientSubmitRejection(code))) {
        throw submissionUnknown(submitContext, new ClientError(code));
      }
      throw new ClientError(code, {status: response.status});
    }
    return response;
  };
  const profileResponse = await exchange('connect');
  let profile;
  try { profile = await controlValue(profileResponse); }
  catch (cause) { throw new ClientError('InvalidHostProfile', {cause}); }
  if (!validClientProfile(profile, selected.wire)) fail('InvalidHostProfile');
  const confirmed = Object.freeze({...profile,
    capabilities: Object.freeze([...profile.capabilities]),
    limits: Object.freeze({...profile.limits})});

  const execution = admission => {
    if (!validClientAdmission(admission, selected.wire)) {
      fail('InvalidHostAdmission');
    }
    const ref = Object.freeze({...admission.ref});
    const runProfile = Object.freeze({...confirmed,
      durability: admission.durability});
    const runRequest = (operation, body = {}, signal, cancellationContext) =>
      exchange(operation, {ref, ...body}, signal, undefined, cancellationContext);
    const readControl = async (operation, body, signal, cancellationContext) => {
      const response = await runRequest(operation, body, signal, cancellationContext);
      try { return await controlValue(response); }
      catch (cause) {
        throw retainCancellationExplanation(new ClientError('InvalidHostResponse', {cause}),
          cancellationContext, 'outcome_unknown');
      }
    };

    const result = name => {
      if (typeof name !== 'string' || !name) fail('InvalidResultName');
      const rows = (options = {}) => {
        const attemptId = crypto.randomUUID();
        const context = freezeInput({ref, resultName: name, attemptId,
          lookupContext: {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef}});
        const maxWireBytes = tighter(options.maxWireBytes,
          confirmed.limits.maxReadWireBytes);
        const maxRowWireBytes = tighter(options.maxRowWireBytes,
          confirmed.limits.maxRowWireBytes);
        const maxRowRetainedValueBytes = tighter(
          options.maxRowRetainedValueBytes,
          confirmed.limits.maxRowRetainedValueBytes);
        let state = 'not_started';
        let rowsYielded = 0;
        const controller = new AbortController();
        const iterate = async function* () {
          if (state !== 'not_started') fail('ReadAttemptAlreadyStarted');
          state = 'prefix';
          const abort = () => controller.abort();
          options.signal?.addEventListener('abort', abort, {once: true});
          if (options.signal?.aborted) controller.abort();
          let wireBytes = 0, line = '';
          let stream, failure;
          try {
            const response = await runRequest('read', {
              resultName: name, format: port === undefined ? 'jsonl' :
                'typed', attemptId,
            }, controller.signal);
            if (port !== undefined) {
              if (response?.kind !== 'rows' ||
                  typeof response.frames?.[Symbol.asyncIterator] !==
                    'function') fail('InvalidResultStream');
              for await (const frame of response.frames) {
                controller.signal.throwIfAborted();
                if (frame === null || typeof frame !== 'object' ||
                    !Number.isSafeInteger(frame.byteLength) ||
                    frame.byteLength < 1 ||
                    frame.value === null ||
                    typeof frame.value !== 'object' ||
                    Array.isArray(frame.value)) fail('InvalidResultFrame');
                if (frame.byteLength > maxRowWireBytes) {
                  fail('ResultRowWireLimit');
                }
                wireBytes += frame.byteLength;
                if (wireBytes > maxWireBytes) fail('ResultWireLimit');
                if (retainedValueBytes(frame.value) >
                    maxRowRetainedValueBytes) fail('ResultRowRetainedLimit');
                const row = structuredClone(frame.value);
                rowsYielded++;
                yield row;
              }
              controller.signal.throwIfAborted();
              state = 'complete';
            } else {
              stream = response.body?.getReader();
              if (!stream) fail('InvalidResultStream');
              const decoder = new TextDecoder('utf-8', {fatal: true});
              const acceptText = function* (text) {
                line += text;
                let newline;
                while ((newline = line.indexOf('\n')) >= 0) {
                  controller.signal.throwIfAborted();
                  const item = line.slice(0, newline);
                  line = line.slice(newline + 1);
                  if (!item) fail('InvalidResultStream');
                  if (new TextEncoder().encode(item).byteLength >
                      maxRowWireBytes) {
                    fail('ResultRowWireLimit');
                  }
                  let row;
                  try { row = JSON.parse(item); }
                  catch { fail('InvalidResultFrame'); }
                  if (row === null || typeof row !== 'object' ||
                      Array.isArray(row)) fail('InvalidResultFrame');
                  if (retainedValueBytes(row) > maxRowRetainedValueBytes) {
                    fail('ResultRowRetainedLimit');
                  }
                  rowsYielded++;
                  yield row;
                }
                if (new TextEncoder().encode(line).byteLength >
                    maxRowWireBytes) {
                  fail('ResultRowWireLimit');
                }
              };
              while (true) {
                controller.signal.throwIfAborted();
                const {done, value} = await stream.read();
                controller.signal.throwIfAborted();
                if (done) break;
                wireBytes += value.byteLength;
                if (wireBytes > maxWireBytes) fail('ResultWireLimit');
                const sliceBytes = Math.min(8192, maxRowWireBytes);
                for (let offset = 0; offset < value.byteLength;
                  offset += sliceBytes) {
                  yield* acceptText(decoder.decode(
                    value.subarray(offset, offset + sliceBytes),
                    {stream: true}));
                }
              }
              yield* acceptText(decoder.decode());
              if (line !== '\x1e') fail('IncompleteResultStream');
              state = 'complete';
            }
          } catch (cause) {
            failure = readFailure(cause, context, rowsYielded);
          } finally {
            options.signal?.removeEventListener('abort', abort);
            if (stream) {
              try {
                if (state !== 'complete') await stream.cancel();
              } catch (cause) {
                if (failure) {
                  failure.cleanupError = cause;
                  retainReadExplanation(failure, context, rowsYielded, 'read_incomplete', true);
                }
                else failure = retainReadExplanation(new ClientError('ResultReadCleanupUnknown',
                  {attemptId, rowsYielded, cause}), context, rowsYielded, 'cleanup_unknown');
              } finally {
                stream.releaseLock();
              }
            }
            // Cancel the reader before aborting its fetch: our own abort
            // must not turn successful early cleanup into an AbortError.
            if (state !== 'complete') controller.abort();
            // A pending iterator.return() skips code after finally.
            if (failure) throw failure;
          }
        };
        const reader = Object.freeze({attemptId, state: () => state,
          rowsYielded: () => rowsYielded,
          [Symbol.asyncIterator]: iterate});
        readerContexts.set(reader, context);
        return reader;
      };

      const batches = (options = {}) => {
        const reader = rows(options);
        let rowsYielded = 0;
        const maxRows = tighter(options.maxBatchRows,
          confirmed.limits.maxBatchRows);
        const maxBytes = tighter(options.maxBatchRetainedValueBytes,
          confirmed.limits.maxBatchRetainedValueBytes);
        return Object.freeze({attemptId: reader.attemptId,
          state: reader.state,
          rowsYielded: () => rowsYielded,
          async *[Symbol.asyncIterator]() {
            let batch = [], bytes = 0;
            try {
              for await (const row of reader) {
                const size = retainedValueBytes(row);
                if (size > maxBytes) fail('ResultBatchLimit');
                if (batch.length === maxRows || bytes + size > maxBytes) {
                  rowsYielded += batch.length;
                  yield batch; batch = []; bytes = 0;
                }
                batch.push(row); bytes += size;
              }
              if (batch.length) {
                rowsYielded += batch.length;
                yield batch;
              }
            } catch (cause) {
              throw readFailure(cause, readerContexts.get(reader), rowsYielded, readExplanations.get(cause));
            }
          }});
      };

      const all = async (options = {}) => {
        const reader = rows(options);
        const maxRows = tighter(options.maxRows, confirmed.limits.maxRows);
        const maxBytes = tighter(options.maxRetainedValueBytes,
          confirmed.limits.maxRetainedValueBytes);
        let bytes = 0;
        const values = [];
        try {
          for await (const row of reader) {
            bytes += retainedValueBytes(row);
            if (values.length >= maxRows || bytes > maxBytes) {
              fail('ResultRetainedLimit');
            }
            values.push(row);
          }
          return values;
        } catch (cause) {
          throw readFailure(cause, readerContexts.get(reader), 0, readExplanations.get(cause));
        }
      };
      return Object.freeze({
        rows, batches, all,
        one: async options => {
          const values = await all({...options,
            maxRows: Math.min(2, confirmed.limits.maxRows)});
          if (values.length !== 1) fail('ExpectedOneRow');
          return values[0];
        },
        scalar: async options => {
          const values = await all({...options,
            maxRows: Math.min(2, confirmed.limits.maxRows)});
          if (values.length !== 1) fail('ExpectedOneRow');
          const row = values[0];
          if (row === null || typeof row !== 'object' ||
              Array.isArray(row) || Object.keys(row).length !== 1) {
            fail('ExpectedOneColumn');
          }
          return Object.values(row)[0];
        },
        describe: async ({signal, format = 'jsonl',
          ...requestedLimits} = {}) => {
          if (!['json', 'jsonl', 'csv'].includes(format)) {
            fail('UnsupportedResultDescriptionFormat');
          }
          if (Object.keys(requestedLimits).some(key =>
            !Object.hasOwn(resultDescriptionLimits, key))) {
            fail('InvalidResultDescriptionOptions');
          }
          const limits = Object.fromEntries(
            Object.entries(resultDescriptionLimits).map(([key, ceiling]) => {
              const value = requestedLimits[key] ?? ceiling;
              if (!positive(value) || value > ceiling) {
                fail('InvalidResultDescriptionOptions');
              }
              return [key, value];
            }));
          const response = await runRequest('result-describe', {
            resultName: name, format, attemptId: crypto.randomUUID(),
            ...limits,
          }, signal);
          let answer;
          try { answer = await controlValue(response, limits.maxWireBytes); }
          catch (cause) {
            throw new ClientError('InvalidHostResultDescription', {cause});
          }
          if (!validResultDescription(answer, {ref, resultName: name, format},
            limits)) fail('InvalidHostResultDescription');
          const schema = Object.fromEntries(answer.columns.map(column =>
            [column.name, column.contract]));
          if (await contentCid(schema) !== answer.resultSchemaCid ||
              await contentCid({json_value_wire_contract_cid: jsonValueWireContractCid,
                version: answer.serialization.version}) !==
                answer.serialization.contractCid ||
              await contentCid({version: 'actql-result-definition/0.1',
                program_definition_cid: answer.programDefinitionCid,
                result_name: name}) !== answer.resultDefinitionCid) {
            fail('InvalidHostResultDescription');
          }
          return Object.freeze(answer);
        },
        deliveryAttempt: async (attemptId, {signal} = {}) => {
          if (typeof attemptId !== 'string' || !attemptId) {
            fail('InvalidReadAttempt');
          }
          const response = await runRequest('delivery-attempt', {
            resultName: name, attemptId,
          }, signal);
          let answer;
          try { answer = await controlValue(response); }
          catch (cause) {
            throw new ClientError('InvalidHostAttemptLookup', {cause});
          }
          if (!validDeliveryAttemptLookup(answer, {
            attemptId, runDefinitionCid: ref.runDefinitionCid,
            resultName: name,
          })) fail('InvalidHostAttemptLookup');
          return Object.freeze(answer);
        },
      });
    };
    return Object.freeze({
      ref, profile: runProfile, result,
      status: async ({signal} = {}) => {
        const state = await readControl('status', {}, signal);
        if (!validRunState(state)) fail('InvalidHostRunState');
        return retainEffectUncertainty(state, ref);
      },
      wait: async ({until, signal} = {}) => {
        const state = await readControl('wait', {until: until ?? null}, signal);
        if (!validRunState(state)) fail('InvalidHostRunState');
        return retainEffectUncertainty(state, ref);
      },
      cancel: async ({signal} = {}) => {
        const context = freezeInput({ref: {...ref}});
        const response = await readControl('cancel', {}, signal, context);
        if (!validCancellation(response) ||
            response.ref.namespaceId !== ref.namespaceId ||
            response.ref.authorityScopeCid !== ref.authorityScopeCid ||
            response.ref.runDefinitionCid !== ref.runDefinitionCid) {
          throw retainCancellationExplanation(new ClientError('InvalidHostCancellation'),
            context, 'outcome_unknown');
        }
        // Local ports may reuse their response object across operations.
        let received;
        try { received = structuredClone(response); }
        catch {
          throw retainCancellationExplanation(new ClientError('InvalidHostCancellation'),
            context, 'outcome_unknown');
        }
        // Cloning may reject a Local value or drop/change its validated fields.
        if (!validCancellation(received) ||
            received.ref.namespaceId !== ref.namespaceId ||
            received.ref.authorityScopeCid !== ref.authorityScopeCid ||
            received.ref.runDefinitionCid !== ref.runDefinitionCid) {
          throw retainCancellationExplanation(new ClientError('InvalidHostCancellation'),
            context, 'outcome_unknown');
        }
        return retainCancellationExplanation(received, context, received.kind, received.revision);
      },
      // The Run's current state after the Host's reconciliation attempt. An
      // unknown Effect outcome stays `needs_reconciliation` until the Host
      // has provider evidence; nothing is resent to find out.
      reconcile: async ({signal} = {}) => {
        const state = await readControl('reconcile', {}, signal);
        if (!validRunState(state)) fail('InvalidHostRunState');
        return retainEffectUncertainty(state, ref);
      },
    });
  };

  const submit = async (kind, input, options = {}) => {
    const requestId = options.requestId ?? crypto.randomUUID();
    if (typeof requestId !== 'string' || !requestId) fail('InvalidRequestId');
    const context = {requestId, lookupContext: Object.freeze({
      endpoint: selected.endpoint, scopeRef: confirmed.scopeRef,
    })};
    let body;
    try {
      body = freezeInput(JSON.parse(JSON.stringify({requestId, kind, input,
        parameters: options.parameters ?? null})));
    } catch { fail('InvalidClientPayload'); }
    const snapshot = freezeInput({...body, connection: selected.wire,
      lookupContext: context.lookupContext});
    submissionContexts.set(context, snapshot);
    const response = await exchange('submit', body, options.signal, context);
    let admitted;
    try { admitted = await controlValue(response); }
    catch (cause) {
      throw submissionUnknown(context, cause);
    }
    if (admitted?.kind === 'held' &&
        validSubmitReply(admitted, selected.wire, requestId)) {
      const held = new RequestHeld(Object.freeze({...admitted,
        ...(admitted.checkpoint === undefined ? {} :
          {checkpoint: Object.freeze({...admitted.checkpoint})})}),
      context.lookupContext);
      submissionInputs.set(held, snapshot);
      submissionExplanations.set(held,
        submissionLookupExplanation('request_held', snapshot));
      throw held;
    }
    let result;
    try { result = execution(admitted); }
    catch (cause) {
      throw submissionUnknown(context, cause);
    }
    submissionInputs.set(result, snapshot);
    submissionExplanations.set(result, freezeInput({
      observation: 'run_reference_received',
      summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
      next: {operation: 'status', ref: result.ref},
    }));
    return result;
  };
  return Object.freeze({
    profile: confirmed,
    requestedDurability: selected.wire.durability ?? null,
    aql: (text, options = {}) => {
      if (typeof text !== 'string' || !text ||
          !clientSourceFormats.includes(options.format)) {
        return Promise.reject(new ClientError('InvalidAqlDocument'));
      }
      if (options.parameterDeclarations !== undefined &&
          !['aql-text', 'sql'].includes(options.format)) {
        return Promise.reject(new ClientError('InvalidAqlDocument'));
      }
      return submit('aql', {text, format: options.format,
        ...(options.parameterDeclarations === undefined ? {} :
          {parameterDeclarations: options.parameterDeclarations})}, options);
    },
    // Check authored source without starting anything. The outcome is the
    // Host's actql-check-outcome/0.1 value: a report bound to its scope and
    // context, a failure, or unavailable. None of them is a thrown error.
    check: async (text, options = {}) => {
      if (typeof text !== 'string') fail('InvalidCheckRequest');
      const signal = options.signal;
      let body;
      try {
        // Detach caller-owned objects synchronously, before credentials or I/O.
        body = freezeInput(snapshotCheckRequest({input: {text, format: options.format,
          ...(options.parameterDeclarations === undefined ? {} :
            {parameterDeclarations: options.parameterDeclarations})},
          parameters: options.parameters ?? null}));
      } catch { fail('InvalidCheckRequest'); }
      if (!validClientBody('check', {connection: selected.wire, ...body})) {
        fail('InvalidCheckRequest');
      }
      let outcome;
      try { outcome = await controlValue(await exchange('check', body,
        signal)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostCheckOutcome', {cause});
      }
      if (!validCheckOutcome(outcome)) fail('InvalidHostCheckOutcome');
      // Own this call's value before binding or freezing it. A Local Host may
      // reuse its response object without replacing a previous SDK observation.
      try { outcome = structuredClone(outcome); }
      catch { fail('InvalidHostCheckOutcome'); }
      if (!validCheckOutcome(outcome)) fail('InvalidHostCheckOutcome');
      const report = outcome.report ?? outcome.partial_report;
      if (report) {
        const received = new Map([['source', {kind: 'text', text: body.input.text}]]);
        if (body.input.parameterDeclarations !== undefined) received.set('parameter_declarations',
          {kind: 'structured', value: body.input.parameterDeclarations});
        if (body.parameters !== null) received.set('parameters', {kind: 'structured', value: body.parameters});
        if (report.inputs.length !== received.size) fail('InvalidHostCheckOutcome');
        const snapshots = new Map();
        for (const document of report.inputs) {
          const original = received.get(document.document_id);
          if (!original || document.kind !== original.kind || document.byte_length !==
              utf8.encode(original.kind === 'text' ? original.text : JSON.stringify(original.value)).length) {
            fail('InvalidHostCheckOutcome');
          }
          snapshots.set(document.document_id, Object.freeze({...original,
            documentId: document.document_id, revision: document.revision}));
        }
        checkInputs.set(outcome, snapshots);
        for (const reason of [...report.reasons, ...(report.requirements ?? [])]) {
          if (reason.location && !resolveCheckLocation(outcome, reason.location)) {
            checkInputs.delete(outcome);
            fail('InvalidHostCheckOutcome');
          }
        }
      }
      checkRequests.set(outcome, body);
      return freezeInput(outcome);
    },
    start: (program, options = {}) => {
      if (program === null || typeof program !== 'object' ||
          Array.isArray(program)) {
        return Promise.reject(new ClientError('InvalidProgramDocument'));
      }
      return submit('program', program, options);
    },
    attach: async (ref, {signal} = {}) => {
      const requested = Object.freeze({...ref});
      if (!validRunRef(requested)) fail('InvalidRunReference');
      const response = await exchange('attach', {ref: requested}, signal);
      let admitted;
      try { admitted = await controlValue(response); }
      catch (cause) { throw new ClientError('InvalidHostAdmission', {cause}); }
      if (!validRunRef(admitted?.ref)) fail('InvalidHostAdmission');
      if (admitted.ref.namespaceId !== requested.namespaceId ||
          admitted.ref.authorityScopeCid !== requested.authorityScopeCid ||
          admitted.ref.runDefinitionCid !== requested.runDefinitionCid) {
        fail('ForeignHostAdmission');
      }
      return execution(admitted);
    },
    lookupRequest: async (requestId, {signal} = {}) => {
      if (typeof requestId !== 'string' || !requestId) fail('InvalidRequestId');
      const response = await exchange('lookup-request', {requestId}, signal);
      let answer;
      try { answer = await controlValue(response); }
      catch (cause) {
        throw new ClientError('InvalidHostRequestLookup', {cause});
      }
      if (!validRequestLookup(answer, requestId)) {
        fail('InvalidHostRequestLookup');
      }
      if (answer.kind === 'found') {
        return Object.freeze({...answer, ref: Object.freeze({...answer.ref})});
      }
      return Object.freeze(answer);
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
      let answer;
      try {
        const response = await exchange('cancel-request', {requestId},
          signal);
        answer = await controlValue(response);
      } catch (cause) {
        if (cause instanceof ClientError &&
            cause.code !== 'ClientTransportUnknown' &&
            !(cause.status >= 500)) throw cause;
        throw new ClientError('CancellationUnknown', {requestId, cause});
      }
      if (!validRequestCancellation(answer, requestId)) {
        throw new ClientError('CancellationUnknown', {requestId,
          cause: new ClientError('InvalidHostRequestCancellation')});
      }
      return Object.freeze({...answer, ...(answer.ref === undefined ? {} :
        {ref: Object.freeze({...answer.ref})})});
    },
    // Resources an installed connection shows to this caller, from the
    // Host's current Catalog observation. A listing is display material:
    // `snapshotComplete` and the truncation flags say whether it is the whole
    // Catalog, and it never grants reading rows or running anything.
    resources: async (resourceConnection, {query = '', limit = 100,
      signal} = {}) => {
      const body = {resourceConnection, query, limit};
      if (!validClientBody('resources', {connection: selected.wire,
        ...body})) fail('InvalidResourceListing');
      let listing;
      try { listing = await controlValue(await exchange('resources', body,
        signal)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourceListing', {cause});
      }
      if (!validResourceListing(listing, {resourceConnection, limit})) {
        fail('InvalidHostResourceListing');
      }
      return Object.freeze({...listing, resources: Object.freeze(
        listing.resources.map(item => Object.freeze({...item})))});
    },
    // Typed metadata of one Resource the caller may see. `catalog_required`
    // with a reason means the Host's Catalog cannot answer yet; it is never
    // evidence that the Resource is absent.
    inspectResource: async (resourceConnection, resource, {
      maxBytes = 64 * 1024, signal} = {}) => {
      const body = {resourceConnection, resource, maxBytes};
      if (!validClientBody('resource-inspect', {connection: selected.wire,
        ...body})) fail('InvalidResourceInspection');
      let inspection;
      try { inspection = await controlValue(await exchange('resource-inspect',
        body, signal), jsonPayloadWireBytes(maxBytes)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourceInspection', {cause});
      }
      if (!validResourceInspection(inspection, body)) {
        fail('InvalidHostResourceInspection');
      }
      const {summaryJson, ...rest} = inspection;
      return Object.freeze({...rest, ...(summaryJson === undefined ? {} :
        {summary: JSON.parse(summaryJson)})});
    },
    // A separately authorized preview of at most `maxRows` rows with exactly
    // `fields`. `limited` marks a prefix; a preview is never a complete read,
    // Acquisition evidence or a Result.
    peekResource: async (resourceConnection, resource, {fields, maxRows = 10,
      maxBytes = 64 * 1024, signal} = {}) => {
      const body = {resourceConnection, resource,
        fields: Array.isArray(fields) ? [...fields] : fields, maxRows,
        maxBytes};
      if (!validClientBody('resource-peek', {connection: selected.wire,
        ...body})) fail('InvalidResourcePeek');
      let peek;
      try { peek = await controlValue(await exchange('resource-peek', body,
        signal), jsonPayloadWireBytes(maxBytes)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourcePeek', {cause});
      }
      if (!validResourcePeek(peek, body)) fail('InvalidHostResourcePeek');
      const {rowsJson, ...rest} = peek;
      return Object.freeze({...rest, fields: Object.freeze([...peek.fields]),
        rows: Object.freeze(JSON.parse(rowsJson).map(row =>
          Object.freeze(row)))});
    },
    // One authorized page of waiting Checkpoints: safe metadata only, never
    // review contents. `next` continues the listing.
    checkpoints: async ({after, limit = 50, signal} = {}) => {
      if (after !== undefined && (typeof after !== 'string' || !after) ||
          !positive(limit) || limit > checkpointLimits.maxPageItems) {
        fail('InvalidCheckpointPage');
      }
      const response = await exchange('checkpoints',
        {after: after ?? '', limit}, signal);
      let page;
      try { page = await controlValue(response); }
      catch (cause) { throw new ClientError('InvalidHostCheckpointPage', {cause}); }
      if (!validCheckpointPage(page, limit)) fail('InvalidHostCheckpointPage');
      return Object.freeze({items: Object.freeze(page.items.map(item =>
        Object.freeze(structuredClone(item)))),
      ...(page.next === undefined ? {} : {next: page.next})});
    },
    // The exact review projection a Checkpoint names, when the caller is
    // authorized to read it. Bounded by `maxBytes` on both sides; the bytes
    // are verified against the named artifact CID before they are returned.
    // Aborting this read never cancels the request or Run.
    reviewCheckpoint: async (checkpoint, {maxBytes = 64 * 1024,
      signal} = {}) => {
      const checkpointCid = typeof checkpoint === 'string' ? checkpoint
        : checkpoint?.checkpointCid;
      if (typeof checkpointCid !== 'string' ||
          !/^sha256:[0-9a-f]{64}$/u.test(checkpointCid)) {
        fail('InvalidCheckpointReference');
      }
      if (!positive(maxBytes) || maxBytes > checkpointLimits.maxReviewBytes) {
        fail('InvalidReviewLimit');
      }
      const response = await exchange('checkpoint-review',
        {checkpointCid, maxBytes}, signal);
      let review;
      try { review = await controlValue(response,
        4 * Math.ceil(maxBytes / 3) + reviewEnvelopeBytes); }
      catch (cause) { throw new ClientError('ReviewReadUnknown', {cause}); }
      if (!validCheckpointReview(review, {checkpointCid, maxBytes})) {
        fail('InvalidHostCheckpointReview');
      }
      const bytes = Uint8Array.from(atob(review.contentBase64),
        character => character.charCodeAt(0));
      if (bytes.byteLength !== review.byteLength ||
          !await reviewBytesMatchCid(bytes, review.artifactCid) ||
          typeof checkpoint === 'object' &&
            checkpoint.reviewProjectionCid !== undefined &&
            checkpoint.reviewProjectionCid !== review.artifactCid) {
        fail('ReviewIntegrityFailed');
      }
      return Object.freeze({checkpointCid, artifactCid: review.artifactCid,
        bytes});
    },
    // Answer one or more Checkpoints. Each item is either {checkpoint,
    // decision} (a listed summary and 'approved' | 'rejected', signed here
    // by `signer`) or a previously signed item returned by an earlier call,
    // which is resent unchanged. Results are per Checkpoint; the batch is not
    // atomic. A stored answer is not a resumed or completed Run: follow the
    // request with lookupRequest, then status()/wait() once the Run exists.
    // When the reply is lost the error carries the exact signed items to
    // resend; they are never re-signed with a new decision time.
    resolveCheckpoints: async (items, {signer, signal} = {}) => {
      if (!Array.isArray(items) || items.length === 0 ||
          items.length > checkpointLimits.maxResolveItems) {
        fail('InvalidCheckpointAnswers');
      }
      const decidedAt = new Date().toISOString();
      const signed = [];
      for (const item of items) {
        if (validResolveItem(item)) {
          signed.push(Object.freeze({...item}));
          continue;
        }
        let key;
        try { key = checkedSigner(signer); }
        catch { fail('InvalidCheckpointSigner'); }
        try {
          signed.push(await signedAnswer(item?.checkpoint, item?.decision,
            key, decidedAt));
        } catch (cause) {
          throw new ClientError(cause.message ?? 'InvalidCheckpointAnswer',
            {cause});
        }
      }
      if (new Set(signed.map(item => item.checkpointCid)).size !==
          signed.length) fail('DuplicateCheckpointAnswer');
      const frozen = Object.freeze(signed);
      let answer;
      try {
        const response = await exchange('resolve', {items: frozen}, signal);
        answer = await controlValue(response);
      } catch (cause) {
        if (cause instanceof ClientError && cause.code !==
            'ClientTransportUnknown' && !(cause.status >= 500)) throw cause;
        throw new ClientError('ResolutionUnknown', {signed: frozen, cause});
      }
      if (!validResolveResults(answer, frozen)) {
        throw new ClientError('ResolutionUnknown', {signed: frozen,
          cause: new ClientError('InvalidHostResolveReply')});
      }
      return Object.freeze({
        results: Object.freeze(answer.results.map(result =>
          Object.freeze({...result}))),
        signed: frozen,
      });
    },
    close() { closed = true; },
  });
}
