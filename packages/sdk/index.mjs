// The transport Client delegates admission, state and delivery to the Host.
import {validClientAdmission, validClientConnection, validClientProfile,
  validDeliveryAttemptLookup, validRequestLookup, validRunRef,
  validRunState} from
  '@actql/client-wire';
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

async function boundedHostJson(response) {
  const declared = response.headers.get('content-length');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('InvalidHostControlResponse');
  let complete = false;
  try {
    if (declared !== null && Number(declared) > maxControlResponseBytes) {
      throw new Error('HostControlResponseLimit');
    }
    const chunks = [];
    let size = 0;
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxControlResponseBytes) {
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
  const selected = connectionOptions(options);
  let closed = false;
  const exchange = async (operation, body = {}, signal, submitContext) => {
    if (closed) fail('ClientClosed');
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
        throw new ClientError('SubmissionUnknown', {...submitContext, cause});
      }
      throw new ClientError('ClientTransportUnknown', {cause});
    }
    if (!response.ok) {
      let error;
      try { error = await boundedHostJson(response); } catch {}
      const code = typeof error?.code === 'string' &&
        /^[A-Za-z][A-Za-z0-9_]{0,79}$/u.test(error.code)
        ? error.code : `HostHTTP${response.status}`;
      if (operation === 'submit' && response.status >= 500) {
        throw new ClientError('SubmissionUnknown', {...submitContext,
          cause: new ClientError(code)});
      }
      throw new ClientError(code);
    }
    return response;
  };
  const profileResponse = await exchange('connect');
  let profile;
  try { profile = await boundedHostJson(profileResponse); }
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
      try { return await boundedHostJson(response); }
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
        const controller = new AbortController();
        const iterate = async function* () {
          if (state !== 'not_started') fail('ReadAttemptAlreadyStarted');
          state = 'prefix';
          const abort = () => controller.abort();
          options.signal?.addEventListener('abort', abort, {once: true});
          if (options.signal?.aborted) controller.abort();
          let wireBytes = 0, line = '';
          try {
            const response = await runRequest('read', {
              resultName: name, format: 'jsonl', attemptId,
            }, controller.signal);
            const stream = response.body?.getReader();
            if (!stream) fail('InvalidResultStream');
            const decoder = new TextDecoder('utf-8', {fatal: true});
            const acceptText = function* (text) {
              line += text;
              let newline;
              while ((newline = line.indexOf('\n')) >= 0) {
                const item = line.slice(0, newline);
                line = line.slice(newline + 1);
                if (!item) fail('InvalidResultStream');
                if (new TextEncoder().encode(item).byteLength >
                    maxRowWireBytes) {
                  fail('ResultRowWireLimit');
                }
                const row = JSON.parse(item);
                if (retainedValueBytes(row) > maxRowRetainedValueBytes) {
                  fail('ResultRowRetainedLimit');
                }
                yield row;
              }
              if (new TextEncoder().encode(line).byteLength >
                  maxRowWireBytes) {
                fail('ResultRowWireLimit');
              }
            };
            while (true) {
              const {done, value} = await stream.read();
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
          } catch (cause) {
            throw new ClientError(cause.code ?? 'ResultReadUnknown',
              {attemptId, cause});
          } finally {
            options.signal?.removeEventListener('abort', abort);
            if (state !== 'complete') controller.abort();
          }
        };
        return Object.freeze({attemptId, state: () => state,
          [Symbol.asyncIterator]: iterate});
      };

      const batches = (options = {}) => {
        const reader = rows(options);
        const maxRows = tighter(options.maxBatchRows,
          confirmed.limits.maxBatchRows);
        const maxBytes = tighter(options.maxBatchRetainedValueBytes,
          confirmed.limits.maxBatchRetainedValueBytes);
        return Object.freeze({attemptId: reader.attemptId,
          state: reader.state,
          async *[Symbol.asyncIterator]() {
            let batch = [], bytes = 0;
            try {
              for await (const row of reader) {
                const size = retainedValueBytes(row);
                if (size > maxBytes) fail('ResultBatchLimit');
                if (batch.length === maxRows || bytes + size > maxBytes) {
                  yield batch; batch = []; bytes = 0;
                }
                batch.push(row); bytes += size;
              }
              if (batch.length) yield batch;
            } catch (cause) {
              throw new ClientError(cause.code ?? 'ResultReadUnknown',
                {attemptId: reader.attemptId, cause});
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
          throw new ClientError(cause.code ?? 'ResultReadUnknown',
            {attemptId: reader.attemptId, cause});
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
        deliveryAttempt: async (attemptId, {signal} = {}) => {
          if (typeof attemptId !== 'string' || !attemptId) {
            fail('InvalidReadAttempt');
          }
          const response = await runRequest('delivery-attempt', {
            resultName: name, attemptId,
          }, signal);
          let answer;
          try { answer = await boundedHostJson(response); }
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
        return readControl('cancel', {}, signal);
      },
      reconcile: async ({signal} = {}) => {
        return readControl('reconcile', {}, signal);
      },
    });
  };

  const submit = async (kind, input, options = {}) => {
    const requestId = options.requestId ?? crypto.randomUUID();
    if (typeof requestId !== 'string' || !requestId) fail('InvalidRequestId');
    const context = {requestId, lookupContext: Object.freeze({
      endpoint: selected.endpoint, scopeRef: confirmed.scopeRef,
    })};
    const response = await exchange('submit', {requestId, kind, input,
      parameters: options.parameters ?? null}, options.signal, context);
    let admitted;
    try { admitted = await boundedHostJson(response); }
    catch (cause) {
      throw new ClientError('SubmissionUnknown', {...context, cause});
    }
    try { return execution(admitted); }
    catch (cause) {
      throw new ClientError('SubmissionUnknown', {...context, cause});
    }
  };
  return Object.freeze({
    profile: confirmed,
    requestedDurability: selected.wire.durability ?? null,
    aql: (text, options = {}) => {
      if (typeof text !== 'string' || !text ||
          !['json', 'yaml'].includes(options.format)) {
        return Promise.reject(new ClientError('InvalidAqlDocument'));
      }
      return submit('aql', {text, format: options.format}, options);
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
      try { admitted = await boundedHostJson(response); }
      catch (cause) { throw new ClientError('InvalidHostAdmission', {cause}); }
      if (!validRunRef(admitted?.ref)) fail('InvalidHostAdmission');
      if (admitted.ref.tenantId !== requested.tenantId ||
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
      try { answer = await boundedHostJson(response); }
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
    close() { closed = true; },
  });
}
