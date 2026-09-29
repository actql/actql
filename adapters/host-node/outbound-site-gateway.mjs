import {createHash} from 'node:crypto';
import {createServer} from 'node:https';
import {projectRemoteDispatchResponse} from './remote-site-client.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const genericResponseOperations = new Set(['dispatch', 'query', 'release']);

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
  siteAuthorities = new Map(),
  bearerAuthorities = new Map(),
  control,
  maxRequestBytes = 65_536,
  maxPendingDispatches = 1024,
  idlePollMilliseconds = 1000,
} = {}) {
  if (!text(host) || !Number.isSafeInteger(port) || port < 0 ||
      key === undefined || cert === undefined || ca === undefined ||
      !(siteAuthorities instanceof Map) ||
      !(bearerAuthorities instanceof Map) ||
      siteAuthorities.size + bearerAuthorities.size === 0 ||
      control === null || typeof control !== 'object' ||
      typeof control.identity !== 'function' ||
      typeof control.journalKey !== 'function' ||
      typeof control.prepareInputBinding !== 'function' ||
      typeof control.pollJson !== 'function' ||
      typeof control.pollOutputJson !== 'function' ||
      typeof control.pollQueryJson !== 'function' ||
      typeof control.pollReleaseJson !== 'function' ||
      typeof control.admitPollOutput !== 'function' ||
      typeof control.admitOutputResult !== 'function' ||
      typeof control.outputResultProjection !== 'function' ||
      typeof control.outputExpectedIdentity !== 'function' ||
      typeof control.admitPollNotSeen !== 'function' ||
      typeof control.admitResponseJson !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0 ||
      !Number.isSafeInteger(maxPendingDispatches) ||
      maxPendingDispatches <= 0 ||
      !Number.isSafeInteger(idlePollMilliseconds) ||
      idlePollMilliseconds < 1 || idlePollMilliseconds > 60_000) {
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
  // A Site may instead authenticate with a bearer credential; only the
  // SHA-256 of each accepted credential is held here.
  const bearers = new Map();
  for (const [digest, raw] of bearerAuthorities) {
    if (!/^[0-9a-f]{64}$/u.test(digest)) fail('InvalidOutboundSiteBinding');
    const binding = checkedBinding(raw);
    const key = bindingKey(binding.siteKey, binding.siteGeneration);
    if (bindings.has(key)) fail('DuplicateOutboundSiteBinding');
    bindings.set(key, binding);
    bearers.set(digest, binding);
  }
  const pending = new Map();
  // Dispatch envelopes that also carry run materials, by dispatch identity.
  const materialsEnvelopes = new Map();
  const pollWaiters = new Map();
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
  const wakePolls = binding => {
    const key = bindingKey(binding.siteKey, binding.siteGeneration);
    const waiters = pollWaiters.get(key);
    if (waiters === undefined) return;
    pollWaiters.delete(key);
    for (const finish of waiters) finish();
  };
  const waitForPoll = binding => new Promise(resolve => {
    const key = bindingKey(binding.siteKey, binding.siteGeneration);
    let waiters = pollWaiters.get(key);
    if (waiters === undefined) {
      waiters = new Set();
      pollWaiters.set(key, waiters);
    }
    let timer;
    const finish = () => {
      clearTimeout(timer);
      waiters.delete(finish);
      if (waiters.size === 0 && pollWaiters.get(key) === waiters) {
        pollWaiters.delete(key);
      }
      resolve();
    };
    waiters.add(finish);
    timer = setTimeout(finish, idlePollMilliseconds);
  });
  const entryFor = (
    dispatch,
    operation,
    inputBindingBody,
    outputIntent,
    payloadRequest,
    transferRequest,
    subject,
    planLimits,
  ) => {
    const identity = control.identity(dispatch);
    const key = `${operation}:${identity}`;
    const outputEnvelope = operation === 'output'
      ? control.pollOutputJson(dispatch, outputIntent)
      : operation === 'plan'
        ? control.pollOutputPlanJson(dispatch, outputIntent)
        : undefined;
    const outputExpected = operation === 'output'
      ? control.outputExpectedIdentity(payloadRequest, transferRequest)
      : undefined;
    let entry = pending.get(key);
    if (entry !== undefined) {
      if (operation === 'dispatch' &&
          entry.inputBindingBody !== inputBindingBody) {
        fail('OutboundDispatchBindingCollision');
      }
      if (operation === 'output' &&
          (entry.envelope !== outputEnvelope ||
          entry.outputExpected[0] !== outputExpected[0] ||
          entry.outputExpected[1] !== outputExpected[1])) {
        fail('OutboundOutputBindingCollision');
      }
      if (operation === 'plan' &&
          (entry.envelope !== outputEnvelope ||
          entry.subjectCid !== control.managedOutputSubjectIdentity(subject) ||
          entry.planLimits.maxChunks !== planLimits.maxChunks ||
          entry.planLimits.maxManifestBytes !== planLimits.maxManifestBytes ||
          entry.planLimits.maxReferencedBytes !==
            planLimits.maxReferencedBytes)) {
        fail('OutboundOutputPlanBindingCollision');
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
      output: operation === 'output'
        ? control.admitPollOutput(outputEnvelope)
        : operation === 'plan'
          ? control.admitPollOutputPlan(outputEnvelope)
          : undefined,
      outputExpected,
      payloadRequest,
      transferRequest,
      subject,
      subjectCid: operation === 'plan'
        ? control.managedOutputSubjectIdentity(subject)
        : undefined,
      planLimits,
      key,
      operation,
      acceptanceObserved: false,
      envelope: operation === 'query'
        ? control.pollQueryJson(dispatch)
        : operation === 'release'
          ? control.pollReleaseJson(dispatch)
          : operation === 'output'
            ? outputEnvelope
          : operation === 'plan'
            ? outputEnvelope
          : materialsEnvelopes.get(identity) ??
            control.pollJson(dispatch, inputBinding),
      sequence: sequence++,
      waiters: new Set(),
    };
    pending.set(key, entry);
    wakePolls(siteBinding);
    return entry;
  };
  const waitFor = (
    dispatch,
    signal,
    operation,
    inputBindingBody,
    outputIntent,
    payloadRequest,
    transferRequest,
    subject,
    planLimits,
  ) => {
    if (signal?.aborted) return Promise.reject(signal.reason);
    const entry = entryFor(
      dispatch,
      operation,
      inputBindingBody,
      outputIntent,
      payloadRequest,
      transferRequest,
      subject,
      planLimits,
    );
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
    rejectUnauthorized: bearers.size === 0,
    minVersion: 'TLSv1.3',
  }, async (request, response) => {
    try {
      const peer = request.socket.getPeerCertificate();
      const authorization = request.headers.authorization;
      const bearer = typeof authorization === 'string' &&
        authorization.startsWith('Bearer ')
        ? bearers.get(createHash('sha256')
          .update(authorization.slice('Bearer '.length)).digest('hex'))
        : undefined;
      const binding = bearer ?? (request.socket.authorized
        ? fingerprints.get(peer.fingerprint256) : undefined);
      if (binding === undefined) {
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
        let entry = nextEntry(binding);
        if (entry === undefined && !admissionClosed) {
          await waitForPoll(binding);
          entry = nextEntry(binding);
        }
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
      let statusReply = false;
      for (const entry of pending.values()) {
        if (entry.binding !== binding || entry.operation !== 'plan') {
          continue;
        }
        try {
          admitted = control.admitOutputPlan(
            body,
            entry.output,
            entry.subject,
            entry.planLimits.maxChunks,
            entry.planLimits.maxManifestBytes,
            entry.planLimits.maxReferencedBytes,
          );
          matched = entry;
          break;
        } catch {}
      }
      if (matched !== undefined) {
        settle(matched, 'resolve', Object.freeze({
          plan: admitted,
          planWire: body,
          payloadRequest: control.outputPlanPayloadRequest(admitted),
          transferRequest: control.outputPlanTransferRequest(admitted),
        }));
        replyJson(response, 200, {accepted: true});
        return;
      }
      for (const entry of pending.values()) {
        if (entry.binding !== binding || entry.operation !== 'output') {
          continue;
        }
        try {
          admitted = control.admitOutputResult(
            body,
            entry.output,
            entry.payloadRequest,
            entry.transferRequest,
          );
          matched = entry;
          break;
        } catch {}
      }
      if (matched !== undefined) {
        const projection = control.outputResultProjection(
          admitted,
          matched.transferRequest,
        );
        settle(matched, 'resolve', Object.freeze({
          result: admitted,
          resultWire: body,
          resultCid: projection[0],
          payloadRequestCid: projection[1],
          payloadDigest: projection[2],
          transferRequestCid: projection[3],
          transferRevision: Number(projection[4]),
        }));
        replyJson(response, 200, {accepted: true});
        return;
      }
      for (const entry of pending.values()) {
        if (entry.binding !== binding ||
            !genericResponseOperations.has(entry.operation)) {
          continue;
        }
        try {
          statusReply = entry.operation === 'query' ||
            entry.operation === 'release' || entry.acceptanceObserved;
          admitted = control.admitResponseJson(
            body,
            entry.dispatch,
            statusReply,
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
        {statusReply},
      );
      if (matched.operation === 'dispatch' && !statusReply &&
          projected.state.every(value => value === 0)) {
        matched.acceptanceObserved = true;
        replyJson(response, 200, {accepted: true});
        return;
      }
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
    dispatch({dispatch, inputBindingBody, dispatchEnvelope, signal} = {}) {
      if (dispatch === undefined || typeof inputBindingBody !== 'string' ||
          (dispatchEnvelope !== undefined &&
          (typeof dispatchEnvelope !== 'string' ||
          control.identity(control.pollDispatchRequest(
            control.admitPollDispatch(dispatchEnvelope))) !==
            control.identity(dispatch) ||
          control.pollDispatchBindingBody(
            control.admitPollDispatch(dispatchEnvelope)) !==
            inputBindingBody))) {
        fail('InvalidOutboundDispatch');
      }
      if (dispatchEnvelope !== undefined) {
        materialsEnvelopes.set(control.identity(dispatch), dispatchEnvelope);
      }
      return waitFor(dispatch, signal, 'dispatch', inputBindingBody);
    },
    output({
      dispatch,
      intent,
      payloadRequest,
      transferRequest,
      signal,
    } = {}) {
      if (dispatch === undefined || intent === undefined ||
          payloadRequest === undefined || transferRequest === undefined) {
        fail('InvalidOutboundOutput');
      }
      return waitFor(
        dispatch,
        signal,
        'output',
        undefined,
        intent,
        payloadRequest,
        transferRequest,
      );
    },
    plan({
      dispatch,
      intent,
      subject,
      maxChunks,
      maxManifestBytes,
      maxReferencedBytes,
      signal,
    } = {}) {
      if (typeof control.pollOutputPlanJson !== 'function' ||
          typeof control.admitPollOutputPlan !== 'function' ||
          typeof control.admitOutputPlan !== 'function' ||
          typeof control.outputPlanPayloadRequest !== 'function' ||
          typeof control.outputPlanTransferRequest !== 'function' ||
          typeof control.managedOutputSubjectIdentity !== 'function' ||
          dispatch === undefined || intent === undefined ||
          subject === undefined || !Number.isSafeInteger(maxChunks) ||
          maxChunks < 1 || !Number.isSafeInteger(maxManifestBytes) ||
          maxManifestBytes < 1 ||
          typeof maxReferencedBytes !== 'bigint' ||
          maxReferencedBytes < 0n) {
        fail('InvalidOutboundOutputPlan');
      }
      return waitFor(
        dispatch,
        signal,
        'plan',
        undefined,
        intent,
        undefined,
        undefined,
        subject,
        Object.freeze({
          maxChunks,
          maxManifestBytes,
          maxReferencedBytes,
        }),
      );
    },
    query({dispatch, signal} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      return waitFor(dispatch, signal, 'query', undefined);
    },
    release({dispatch, signal} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      return waitFor(dispatch, signal, 'release', undefined);
    },
    // Stop offering a dispatch the Site has not accepted; its waiters are
    // rejected. The Coordinator then learns the outcome by query.
    withdraw({dispatch} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      const identity = control.identity(dispatch);
      const entry = pending.get(`dispatch:${identity}`);
      materialsEnvelopes.delete(identity);
      if (entry === undefined) return false;
      settle(entry, 'reject', Object.assign(
        new Error('RemoteDispatchWithdrawn'),
        {code: 'RemoteDispatchWithdrawn'},
      ));
      return true;
    },
    pending() {
      return pending.size;
    },
    async close() {
      if (listenerClosed && admissionClosed) return false;
      admissionClosed = true;
      for (const binding of bindings.values()) wakePolls(binding);
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
