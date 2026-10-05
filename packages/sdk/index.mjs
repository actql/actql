// The transport Client delegates admission, state and delivery to the Host.
import {checkpointLimits, clientSourceFormats, isClientSubmitRejection, validCancellation, validCheckpointPage,
  validCheckpointReview, validClientAdmission, validClientConnection,
  validClientProfile, validDeliveryAttemptLookup, validRequestCancellation,
  validRequestLookup,
  validResolveItem, validResolveResults, validRunRef, validRunState,
  validSubmitReply, validClientBody, validResourceInspection,
  validResourceListing, validResourcePeek, resultDescriptionLimits,
  validResultDescription, validCheckOutcome} from
  '@actql/client-wire';
import {bytesCid, contentCid, checkedSigner, signedAnswer} from './checkpoints.mjs';
// The response owns only a weak association to this call's immutable inputs.
// A parsed/copied report has no such association and cannot resolve a location.
const checkInputs = new WeakMap();
// Original request data is available only through explicit SDK access, never
// by serializing an error or Run handle. It does not establish acceptance.
const submissionInputs = new WeakMap();
const submissionContexts = new WeakMap();
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

export function getSubmissionInput(result) {
  return submissionInputs.get(result);
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
    return Object.freeze({...location, input});
  }
  const bytes = utf8.encode(original.text);
  const boundary = at => Number.isSafeInteger(at) && at >= 0 && at <= bytes.length &&
    (at === bytes.length || (bytes[at] & 0xc0) !== 0x80);
  if (!boundary(location.start_byte) || !boundary(location.end_byte) ||
      location.start_byte > location.end_byte) return undefined;
  return Object.freeze({...location, input,
    text: new TextDecoder('utf-8', {fatal: true, ignoreBOM: true})
      .decode(bytes.subarray(location.start_byte, location.end_byte))});
}

// Coordinates describe this submitted revision, never a newer editor buffer.
export function resolveCheckTextRange(outcome, location, currentInput) {
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
    else character += units;
    byte += width;
    at += units;
  }
  return start && Object.freeze({...resolved, positionEncoding: 'utf-16',
    range: Object.freeze({start, end})});
}

// Presentation never participates in verdicts, admission or retry decisions.
export function explainCheckReason(reason) {
  const explanations = {
    query_syntax_invalid: ['The query syntax is invalid.', 'Correct the query syntax at the reported location when available.'],
    query_lexical_invalid: ['A query token violates its lexical syntax.', 'Correct the token at the reported location when available.'],
    parameter_undeclared: ['The query refers to an undeclared parameter.', 'Declare the parameter or correct its reference; a value alone cannot declare it.'],
    query_invalid: ['The query violates its language or name-resolution contract.', 'Correct the query using its declared names and visible context.'],
    parameter_declarations_invalid: ['The parameter declarations are invalid.', 'Correct the supplied declarations.'],
    supplied_parameters_invalid: ['The supplied parameter input is invalid.', 'Correct the supplied parameter map.'],
    supplied_value_invalid: ['A supplied value violates its declaration.', 'Correct the value to satisfy its declared contract.'],
    supplied_value_constraint_violation: ['A supplied value violates a declared constraint.', 'Correct the value to satisfy the declared constraint family.'],
    supplied_value_type_mismatch: ['A supplied value has the wrong type.', 'Supply a value of the declared type.'],
    parameter_value_required: ['A declared parameter value is missing.', 'Supply the declared value and check the complete bound input again.'],
    program_invalid: ['The input violates the checked Program contract.', 'Correct the input under the selected contract.'],
    bound_values_missing: ['Required bound inputs are missing.', 'Supply the declared inputs and check again.'],
    implementation_limit: ['This checking implementation cannot discharge an obligation.', 'Use a checking implementation that supports the allowed construct.'],
    analysis_budget_exhausted: ['The analysis budget was exhausted.', 'Ask the checking-context owner to review the analysis budget.'],
    check_unclassified: ['The checker could not establish a classified conclusion.', 'Ask the checking-context owner to investigate.'],
    unresolved_protected: ['Source resolution cannot be established from the disclosed context.', 'Ask the Source or checking-context owner to review the published context.'],
  };
  const known = Object.hasOwn(explanations, reason?.code) ? explanations[reason.code] : undefined;
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
  if (reason?.code === 'query_lexical_invalid' && typeof issue === 'string' &&
      Object.hasOwn(lexicalExplanations, issue)) {
    const [summary, hint] = lexicalExplanations[issue];
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
    return Object.freeze({kind: 'known', summary: known[0],
      hint: constraintHints[constraint]});
  }
  return Object.freeze(known ? {kind: 'known', summary: known[0], hint: known[1]}
    : {kind: 'unknown', summary: 'No supported explanation is available for this reason.'});
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
  return result;
};
const readFailure = (cause, attemptId, rowsYielded) => new ClientError(
  typeof cause?.code === 'string' ? cause.code : 'ResultReadUnknown',
  {attemptId, rowsYielded, cause,
    ...(cause?.cleanupError === undefined ? {} : {cleanupError: cause.cleanupError})});

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
  const exchange = async (operation, body = {}, signal, submitContext) => {
    if (closed) fail('ClientClosed');
    if (port !== undefined) {
      let request;
      try { request = structuredClone({connection: selected.wire, ...body}); }
      catch { fail('InvalidClientPayload'); }
      try {
        const value = await port.perform(operation, request, signal);
        if (value instanceof Response) fail('InvalidLocalHostPortResponse');
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
        throw new ClientError('ClientTransportUnknown', {cause});
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
      throw new ClientError('ClientTransportUnknown', {cause});
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
    const runRequest = (operation, body = {}, signal) =>
      exchange(operation, {ref, ...body}, signal);
    const readControl = async (operation, body, signal) => {
      const response = await runRequest(operation, body, signal);
      try { return await controlValue(response); }
      catch (cause) { throw new ClientError('InvalidHostResponse', {cause}); }
    };

    const result = name => {
      if (typeof name !== 'string' || !name) fail('InvalidResultName');
      const rows = (options = {}) => {
        const attemptId = crypto.randomUUID();
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
            failure = readFailure(cause, attemptId, rowsYielded);
          } finally {
            options.signal?.removeEventListener('abort', abort);
            if (stream) {
              try {
                if (state !== 'complete') await stream.cancel();
              } catch (cause) {
                if (failure) failure.cleanupError = cause;
                else failure = new ClientError('ResultReadCleanupUnknown',
                  {attemptId, rowsYielded, cause});
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
        return Object.freeze({attemptId, state: () => state,
          rowsYielded: () => rowsYielded,
          [Symbol.asyncIterator]: iterate});
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
              throw readFailure(cause, reader.attemptId, rowsYielded);
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
          throw readFailure(cause, reader.attemptId, 0);
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
              await contentCid({version: answer.serialization.version}) !==
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
        return state;
      },
      wait: async ({until, signal} = {}) => {
        const state = await readControl('wait', {until: until ?? null}, signal);
        if (!validRunState(state)) fail('InvalidHostRunState');
        return state;
      },
      cancel: async ({signal} = {}) => {
        const response = await readControl('cancel', {}, signal);
        if (!validCancellation(response) ||
            response.ref.namespaceId !== ref.namespaceId ||
            response.ref.authorityScopeCid !== ref.authorityScopeCid ||
            response.ref.runDefinitionCid !== ref.runDefinitionCid) {
          fail('InvalidHostCancellation');
        }
        return response;
      },
      // The Run's current state after the Host's reconciliation attempt. An
      // unknown Effect outcome stays `needs_reconciliation` until the Host
      // has provider evidence; nothing is resent to find out.
      reconcile: async ({signal} = {}) => {
        const state = await readControl('reconcile', {}, signal);
        if (!validRunState(state)) fail('InvalidHostRunState');
        return state;
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
      throw held;
    }
    let result;
    try { result = execution(admitted); }
    catch (cause) {
      throw submissionUnknown(context, cause);
    }
    submissionInputs.set(result, snapshot);
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
        body = freezeInput(JSON.parse(JSON.stringify({input: {text, format: options.format,
          ...(options.parameterDeclarations === undefined ? {} :
            {parameterDeclarations: options.parameterDeclarations})},
          parameters: options.parameters ?? null})));
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
          await bytesCid(bytes) !== review.artifactCid ||
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
