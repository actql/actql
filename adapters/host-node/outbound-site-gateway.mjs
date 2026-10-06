import {createHash} from 'node:crypto';
import {createServer} from 'node:https';
import {projectRemoteDispatchResponse} from './remote-site-client.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const genericResponseOperations = new Set(['dispatch', 'query', 'cancel', 'release']);

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

// An installed durable receiver returns an owner-backed synchronous
// canRetireCancellationDelivery() projection for Cancel. Missing confirmation
// retains the waiter. Without a receiver this is only a transport gateway.
export async function startHttpsOutboundSiteGateway({
  host = '127.0.0.1',
  port = 0,
  key,
  cert,
  ca,
  siteAuthorities = new Map(),
  bearerAuthorities = new Map(),
  control,
  receiveObservation,
  retainedInput,
  receiveRetainedInput,
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
      typeof control.pollCancelJson !== 'function' ||
      typeof control.pollReleaseJson !== 'function' ||
      typeof control.admitPollOutput !== 'function' ||
      typeof control.admitOutputResult !== 'function' ||
      typeof control.outputResultProjection !== 'function' ||
      typeof control.outputExpectedIdentity !== 'function' ||
      typeof control.admitPollNotSeen !== 'function' ||
      typeof control.admitResponseJson !== 'function' ||
      (receiveObservation !== undefined && typeof receiveObservation !== 'function') ||
      (retainedInput !== undefined &&
        (retainedInput === null || typeof retainedInput !== 'object' ||
          ['retainedInputIntentFacts', 'retainedInputPlanEnvelope',
            'admitRetainedInputPlan', 'retainedInputPlanFacts',
            'retainedInputTransferEnvelope', 'admitRetainedInputResult']
            .some(name => typeof retainedInput[name] !== 'function') ||
          typeof receiveRetainedInput !== 'function')) ||
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
    retained,
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
    const retainedEnvelope = operation === 'retained-plan'
      ? retainedInput.retainedInputPlanEnvelope(retained.intent)
      : operation === 'retained-transfer'
        ? retainedInput.retainedInputTransferEnvelope(retained.plan)
        : undefined;
    let entry = pending.get(key);
    if (entry !== undefined) {
      if (retainedEnvelope !== undefined && entry.envelope !== retainedEnvelope) {
        fail('OutboundRetainedInputBindingCollision');
      }
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
      retained,
      key,
      operation,
      acceptanceObserved: false,
      envelope: operation === 'query'
        ? control.pollQueryJson(dispatch)
        : operation === 'cancel'
          ? control.pollCancelJson(dispatch)
        : operation === 'release'
          ? control.pollReleaseJson(dispatch)
          : operation === 'output'
            ? outputEnvelope
          : operation === 'plan'
            ? outputEnvelope
          : retainedEnvelope !== undefined
            ? retainedEnvelope
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
    retained,
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
      retained,
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
  const queryPreemptsDispatch = entry => entry.operation === 'dispatch' &&
    (pending.has(`query:${entry.identity}`) || pending.has(`cancel:${entry.identity}`));
  // These are transport waiters, not execution or redelivery permission.
  // An explicit query or cancellation of the same exact dispatch must not
  // sit behind its unresolved send (for example, after a lost acceptance).
  // Keep FIFO ordering for unrelated work and for release/output custody.
  const nextEntry = binding => [...pending.values()]
    .filter(entry => entry.binding === binding && !queryPreemptsDispatch(entry))
    .sort((left, right) => left.sequence - right.sequence)[0];

  const server = createServer({
    key,
    cert,
    ca,
    requestCert: true,
    rejectUnauthorized: bearers.size === 0,
    minVersion: 'TLSv1.3',
  }, async (request, response) => {
    let observationAdmissionAttempted = false;
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
        if (entry.binding !== binding ||
            !['retained-plan', 'retained-transfer'].includes(entry.operation)) {
          continue;
        }
        const saved = Object.freeze({wire: body,
          cid: `sha256:${createHash('sha256').update(body).digest('hex')}`});
        try {
          admitted = entry.operation === 'retained-plan'
            ? retainedInput.admitRetainedInputPlan(entry.retained.intent,
              saved, entry.retained.current, entry.retained.limits)
            : retainedInput.admitRetainedInputResult(entry.retained.plan, saved);
        } catch { continue; }
        // The common owner admits the exact report. The Host must confirm its
        // custody before we ACK or discard this transport delivery obligation.
        observationAdmissionAttempted = true;
        await receiveRetainedInput(Object.freeze({operation: entry.operation,
          dispatch: entry.dispatch, binding, saved, admitted}));
        settle(entry, 'resolve', admitted);
        replyJson(response, 200, {accepted: true});
        return;
      }
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
        observationAdmissionAttempted = true;
        if (receiveObservation === undefined) fail('RemoteCoordinatorOutputDurableReceiverMissing');
        const receipt = await receiveObservation(Object.freeze({body, binding}));
        if (typeof receipt?.outputAckWire !== 'string' ||
            control.admitOutputReportReply(receipt.outputAckWire, admitted) !== true) {
          fail('RemoteCoordinatorOutputAcceptanceUnconfirmed');
        }
        settle(matched, 'resolve', Object.freeze({
          result: admitted,
          resultWire: body,
          resultCid: projection[0],
          payloadRequestCid: projection[1],
          payloadDigest: projection[2],
          transferRequestCid: projection[3],
          transferRevision: Number(projection[4]),
        }));
        replyCanonical(response, receipt.outputAckWire);
        return;
      }
      // Defer only dispatch waiters with an explicit query for that exact
      // request. Preserve registration order among queries and releases: a
      // later, unoffered query must not steal an earlier release's status.
      // If query admission rejects an acceptance reply, the deferred dispatch
      // still gets its ordinary exact-request/reply-kind admission attempt.
      const candidates = [...pending.values()];
      const responseEntries = [
        ...candidates.filter(entry => !queryPreemptsDispatch(entry)),
        ...candidates.filter(queryPreemptsDispatch),
      ];
      for (const entry of responseEntries) {
        if (entry.binding !== binding ||
            !genericResponseOperations.has(entry.operation)) {
          continue;
        }
        try {
          statusReply = entry.operation === 'query' ||
            entry.operation === 'cancel' ||
            entry.operation === 'release' || entry.acceptanceObserved;
          try {
            admitted = control.admitResponseJson(body, entry.dispatch, statusReply);
          } catch (error) {
            // A native Site reports the same dispatch again after acceptance,
            // including its later execution state. Acceptance does not change
            // that reply's typed wire kind into a query/status response.
            if (entry.operation !== 'dispatch' || !entry.acceptanceObserved) {
              throw error;
            }
            admitted = control.admitResponseJson(body, entry.dispatch, false);
            statusReply = false;
          }
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
            {code: 'RemoteDispatchNotSeen', notSeenBody: body},
          );
          settle(matched, 'reject', error);
          replyJson(response, 200, {accepted: true});
          return;
        }
      }
      if (matched === undefined) {
        if (receiveObservation !== undefined) {
          // No pending waiter is needed for a durably admitted replay or an
          // allowed evidence supplement. The existing Coordinator owns both.
          observationAdmissionAttempted = true;
          const receipt = await receiveObservation(Object.freeze({body, binding}));
          let noWaiterHint;
          try { noWaiterHint = JSON.parse(body); } catch {}
          if (typeof receipt?.outputAckWire === 'string') {
            replyCanonical(response, receipt.outputAckWire);
          } else if (noWaiterHint?.version === 'actql-remote-output-result/0.1') {
            // Output reports have a typed, report-bound acknowledgement.  A
            // legacy {accepted:true} body is never evidence that the durable
            // report was accepted, including after Coordinator recovery.
            fail('RemoteCoordinatorOutputAcceptanceUnconfirmed');
          } else {
            replyJson(response, 200, {accepted: true});
          }
          return;
        }
        replyJson(response, 404, {error: 'not_found'});
        return;
      }
      const projected = projectRemoteDispatchResponse(
        control,
        matched.dispatch,
        admitted,
        {statusReply},
      );
      let observationReceipt;
      if (receiveObservation !== undefined) {
        // Commit admission and replay history before resolving a waiter or
        // sending ACK. A failed/unknown commit leaves the waiter pending.
        observationAdmissionAttempted = true;
        observationReceipt = await receiveObservation(Object.freeze({body, binding}));
      }
      if (matched.operation === 'dispatch' && !statusReply &&
          projected.state.every(value => value === 0)) {
        matched.acceptanceObserved = true;
        replyJson(response, 200, {accepted: true});
        return;
      }
      if (matched.operation === 'cancel' &&
          !(receiveObservation === undefined
            ? control.responseCanRetireCancellationDelivery(admitted)
            : typeof observationReceipt?.canRetireCancellationDelivery === 'function' &&
              observationReceipt.canRetireCancellationDelivery() === true)) {
        // With a durable receiver, only its latest committed projection may
        // retire delivery; a known old released reply is not current evidence.
        // The receiver-free gateway retains its transport-only contract.
        // Ordinary status (even after an offer) cannot prove that the Site
        // saved Cancel. Admit the observation, but keep offering the exact
        // cancellation until the common owner admits terminal execution and
        // released cleanup with no retained material or quarantine obligation.
        // Unknown execution is not terminal cancellation evidence.
        replyJson(response, 200, {accepted: true});
        return;
      }
      settle(matched, 'resolve', projected);
      replyJson(response, 200, {accepted: true});
    } catch (error) {
      if (!response.headersSent) {
        if (error?.code === 'RemoteDispatchIntentMissing') {
          replyJson(response, 404, {error: 'not_found'});
        } else if (error?.code === 'RemoteCoordinatorObservationRejected' ||
            error?.code === 'RemoteCoordinatorObservationScopeMismatch') {
          replyJson(response, 409, {error: error.code, issue: error.issueCode});
        } else if (observationAdmissionAttempted) {
          replyJson(response, 503, {error: 'OutboundObservationRetry'});
        } else {
          replyJson(response, 400, {error: 'invalid_request'});
        }
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
        const retained = materialsEnvelopes.get(control.identity(dispatch));
        if (retained !== undefined && retained !== dispatchEnvelope) {
          fail('OutboundDispatchMaterialsCollision');
        }
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
    retainedPlan({dispatch, intent, current, limits, signal} = {}) {
      if (retainedInput === undefined || dispatch === undefined ||
          intent === undefined || current === undefined || limits === undefined) {
        fail('InvalidOutboundRetainedInputPlan');
      }
      const facts = retainedInput.retainedInputIntentFacts(intent);
      if (JSON.parse(facts.wire).dispatch_request_cid !== control.identity(dispatch)) {
        fail('OutboundRetainedInputDispatchMismatch');
      }
      return waitFor(dispatch, signal, 'retained-plan', undefined, undefined,
        undefined, undefined, undefined, undefined, {intent, current, limits});
    },
    retainedTransfer({dispatch, plan, signal} = {}) {
      if (retainedInput === undefined || dispatch === undefined || plan === undefined) {
        fail('InvalidOutboundRetainedInputTransfer');
      }
      const facts = retainedInput.retainedInputPlanFacts(plan);
      if (JSON.parse(facts.wire).dispatch_request_cid !== control.identity(dispatch)) {
        fail('OutboundRetainedInputDispatchMismatch');
      }
      return waitFor(dispatch, signal, 'retained-transfer', undefined, undefined,
        undefined, undefined, undefined, undefined, {plan});
    },
    release({dispatch, signal} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      return waitFor(dispatch, signal, 'release', undefined);
    },
    cancel({dispatch, signal} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      return waitFor(dispatch, signal, 'cancel', undefined);
    },
    // Stop offering a dispatch the Site has not accepted; its waiters are
    // rejected. The Coordinator then learns the outcome by query.
    withdraw({dispatch} = {}) {
      if (dispatch === undefined) fail('InvalidOutboundDispatch');
      const identity = control.identity(dispatch);
      materialsEnvelopes.delete(identity);
      // Every operation still pending for the dispatch is withdrawn, so an
      // abandoned one is not served ahead of later work.
      const entries = [...pending.values()]
        .filter(entry => entry.identity === identity);
      for (const entry of entries) {
        settle(entry, 'reject', Object.assign(
          new Error('RemoteDispatchWithdrawn'),
          {code: 'RemoteDispatchWithdrawn'},
        ));
      }
      return entries.length > 0;
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
