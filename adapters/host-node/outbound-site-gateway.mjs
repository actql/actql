import {createServer} from 'node:https';
import {projectRemoteDispatchResponse} from './remote-site-client.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

async function readBounded(request, maxBytes) {
  const announced = request.headers['content-length'];
  if (announced !== undefined &&
      (!/^(0|[1-9][0-9]*)$/.test(announced) ||
      Number(announced) > maxBytes)) {
    fail('RemoteControlBodyTooLarge');
  }
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.byteLength;
    if (length > maxBytes) fail('RemoteControlBodyTooLarge');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, length).toString('utf8');
}

function replyJson(response, status, body) {
  const bytes = Buffer.from(JSON.stringify(body), 'utf8');
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'cache-control': 'no-store',
  });
  response.end(bytes);
}

function replyCanonical(response, body) {
  const bytes = Buffer.from(body, 'utf8');
  response.writeHead(200, {
    'content-type': 'application/json',
    'content-length': String(bytes.byteLength),
    'cache-control': 'no-store',
  });
  response.end(bytes);
}

const bindingKey = (siteKey, siteGeneration) =>
  `${siteKey.length}:${siteKey}:${siteGeneration}`;

function checkedBinding(value) {
  if (value === null || typeof value !== 'object' || !text(value.siteKey) ||
      !Number.isSafeInteger(value.siteGeneration) ||
      value.siteGeneration < 0) {
    fail('InvalidOutboundSiteBinding');
  }
  return Object.freeze({
    siteKey: value.siteKey,
    siteGeneration: value.siteGeneration,
  });
}

export async function startHttpsOutboundSiteGateway({
  host = '127.0.0.1',
  port = 0,
  key,
  cert,
  ca,
  siteAuthorities,
  control,
  maxRequestBytes = 65_536,
  maxPendingDispatches = 1024,
} = {}) {
  if (!text(host) || !Number.isSafeInteger(port) || port < 0 ||
      key === undefined || cert === undefined || ca === undefined ||
      !(siteAuthorities instanceof Map) || siteAuthorities.size === 0 ||
      control === null || typeof control !== 'object' ||
      typeof control.identity !== 'function' ||
      typeof control.journalKey !== 'function' ||
      typeof control.prepareInputBinding !== 'function' ||
      typeof control.pollJson !== 'function' ||
      typeof control.pollQueryJson !== 'function' ||
      typeof control.admitPollNotSeen !== 'function' ||
      typeof control.admitResponseJson !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0 ||
      !Number.isSafeInteger(maxPendingDispatches) ||
      maxPendingDispatches <= 0) {
    fail('InvalidOutboundSiteGatewayConfiguration');
  }
  const bindings = new Map();
  const fingerprints = new Map();
  for (const [fingerprint, raw] of siteAuthorities) {
    if (!text(fingerprint)) fail('InvalidOutboundSiteBinding');
    const binding = checkedBinding(raw);
    const key = bindingKey(binding.siteKey, binding.siteGeneration);
    if (bindings.has(key)) fail('DuplicateOutboundSiteBinding');
    bindings.set(key, binding);
    fingerprints.set(fingerprint, binding);
  }
  const pending = new Map();
  let sequence = 0;
  let admissionClosed = false;
  let listenerClosed = false;
  let closeInFlight;

  const exactBinding = dispatch => {
    const parts = control.journalKey(dispatch);
    const key = bindingKey(parts[1], Number(parts[2]));
    const binding = bindings.get(key);
    if (binding === undefined) fail('OutboundSiteBindingUnavailable');
    return binding;
  };
  const entryFor = (dispatch, operation, inputBindingBody) => {
    const identity = control.identity(dispatch);
    const key = `${operation}:${identity}`;
    let entry = pending.get(key);
    if (entry !== undefined) {
      if (operation === 'dispatch' &&
          entry.inputBindingBody !== inputBindingBody) {
        fail('OutboundDispatchBindingCollision');
      }
      return entry;
    }
    if (admissionClosed) fail('OutboundSiteGatewayClosed');
    if (pending.size >= maxPendingDispatches) {
      fail('OutboundSiteGatewayCapacityExceeded');
    }
    const siteBinding = exactBinding(dispatch);
    const inputBinding = operation === 'dispatch'
      ? control.prepareInputBinding(inputBindingBody)
      : undefined;
    entry = {
      binding: siteBinding,
      dispatch,
      identity,
      inputBindingBody,
      key,
      operation,
      envelope: operation === 'query'
        ? control.pollQueryJson(dispatch)
        : control.pollJson(dispatch, inputBinding),
      sequence: sequence++,
      waiters: new Set(),
    };
    pending.set(key, entry);
    return entry;
  };
  const waitFor = (dispatch, signal, operation, inputBindingBody) => {
    if (signal?.aborted) return Promise.reject(signal.reason);
    const entry = entryFor(dispatch, operation, inputBindingBody);
    return new Promise((resolve, reject) => {
      const waiter = {resolve, reject, signal, abort: undefined};
      if (signal !== undefined) {
        waiter.abort = () => {
          entry.waiters.delete(waiter);
          reject(signal.reason);
        };
        signal.addEventListener('abort', waiter.abort, {once: true});
      }
      entry.waiters.add(waiter);
    });
  };
  const settle = (entry, operation, value) => {
    pending.delete(entry.key);
    for (const waiter of entry.waiters) {
      if (waiter.abort !== undefined) {
        waiter.signal.removeEventListener('abort', waiter.abort);
      }
      waiter[operation](value);
    }
    entry.waiters.clear();
  };
  const endpoint = (binding, suffix) =>
    `/v1/sites/${encodeURIComponent(binding.siteKey)}/generations/` +
    `${binding.siteGeneration}/outbound/${suffix}`;
  const nextEntry = binding => [...pending.values()]
    .filter(entry => entry.binding === binding)
    .sort((left, right) => left.sequence - right.sequence)[0];

  const server = createServer({
    key,
    cert,
    ca,
    requestCert: true,
    rejectUnauthorized: true,
    minVersion: 'TLSv1.3',
  }, async (request, response) => {
    try {
      const peer = request.socket.getPeerCertificate();
      const binding = fingerprints.get(peer.fingerprint256);
      if (!request.socket.authorized || binding === undefined) {
        replyJson(response, 404, {error: 'not_found'});
        return;
      }
      const poll = endpoint(binding, 'poll');
      const observation = endpoint(binding, 'observations');
      if (request.method !== 'POST' ||
          (request.url !== poll && request.url !== observation) ||
          request.headers['content-type'] !== 'application/json') {
        replyJson(response, 404, {error: 'not_found'});
        return;
      }
      const body = await readBounded(request, maxRequestBytes);
      if (request.url === poll) {
        if (body !== '{}') {
          replyJson(response, 400, {error: 'invalid_request'});
          return;
        }
        const entry = nextEntry(binding);
        if (entry === undefined) {
          response.writeHead(204, {'cache-control': 'no-store'});
          response.end();
          return;
        }
        replyCanonical(response, entry.envelope);
        return;
      }
      let admitted;
      let matched;
      for (const entry of pending.values()) {
        if (entry.binding !== binding) continue;
        try {
          admitted = control.admitResponseJson(
            body,
            entry.dispatch,
            entry.operation === 'query',
          );
          matched = entry;
          break;
        } catch {}
      }
      if (matched === undefined) {
        for (const entry of pending.values()) {
          if (entry.binding !== binding || entry.operation !== 'query') {
            continue;
          }
          try {
            control.admitPollNotSeen(body, entry.dispatch);
            matched = entry;
            break;
          } catch {}
        }
        if (matched !== undefined) {
          const error = Object.assign(
            new Error('RemoteDispatchNotSeen'),
            {code: 'RemoteDispatchNotSeen'},
          );
          settle(matched, 'reject', error);
          replyJson(response, 200, {accepted: true});
          return;
        }
      }
      if (matched === undefined) {
        replyJson(response, 404, {error: 'not_found'});
        return;
      }
      const projected = projectRemoteDispatchResponse(
        control,
        matched.dispatch,
        admitted,
        {statusReply: matched.operation === 'query'},
      );
      settle(matched, 'resolve', projected);
      replyJson(response, 200, {accepted: true});
    } catch (error) {
      if (!response.headersSent) {
        replyJson(response, 400, {error: 'invalid_request'});
      } else {
        response.destroy(error);
      }
    }
  });
  server.on('clientError', (_error, socket) => socket.destroy());
  server.once('close', () => { listenerClosed = true; });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      resolve();
    });
  });
  const address = server.address();
  if (address === null || typeof address === 'string') {
    server.close();
    fail('OutboundSiteGatewayAddressUnavailable');
  }
  return Object.freeze({
    origin: `https://${host}:${address.port}`,
    port: address.port,
    dispatch({dispatch, inputBindingBody, signal} = {}) {
      if (dispatch === undefined || typeof inputBindingBody !== 'string') {
        fail('InvalidOutboundDispatch');
      }
      return waitFor(dispatch, signal, 'dispatch', inputBindingBody);
    },
    query({dispatch, signal} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      return waitFor(dispatch, signal, 'query', undefined);
    },
    pending() {
      return pending.size;
    },
    async close() {
      if (listenerClosed && admissionClosed) return false;
      admissionClosed = true;
      if (closeInFlight !== undefined) return await closeInFlight;
      const attempt = (async () => {
        if (!listenerClosed) {
          await new Promise((resolve, reject) => server.close(error => {
            if (error) reject(error);
            else resolve();
          }));
          listenerClosed = true;
        }
        const error = Object.assign(
          new Error('OutboundSiteGatewayClosed'),
          {code: 'OutboundSiteGatewayClosed'},
        );
        for (const entry of [...pending.values()]) {
          settle(entry, 'reject', error);
        }
        return true;
      })();
      closeInFlight = attempt;
      try {
        return await attempt;
      } finally {
        if (closeInFlight === attempt) closeInFlight = undefined;
      }
    },
  });
}
