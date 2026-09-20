import {createServer} from 'node:https';
import {
  admitRemoteExecutionEvidenceJson,
  admitRemoteManagedOutputMeasurementJson,
  admitRemoteManagedOutputSubjectJson,
} from '../host-common/remote-dispatch-wire.mjs';

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

function reply(response, status, body) {
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

export async function startHttpsRemoteSiteAgent({
  host = '127.0.0.1',
  port = 0,
  key,
  cert,
  ca,
  coordinatorAuthorities,
  siteKey,
  siteGeneration,
  journal,
  store,
  control,
  admitDispatchJson,
  dispatchRuntime,
  maxRequestBytes = 65_536,
} = {}) {
  if (!text(host) || !Number.isSafeInteger(port) || port < 0 ||
      key === undefined || cert === undefined || ca === undefined ||
      !(coordinatorAuthorities instanceof Map) ||
      !text(siteKey) || !Number.isSafeInteger(siteGeneration) ||
      siteGeneration < 0 || journal === undefined || store === undefined ||
      control === null || typeof control !== 'object' ||
      typeof control.runtimeStartable !== 'function' ||
      typeof control.admitPollDispatch !== 'function' ||
      typeof control.pollDispatchRequest !== 'function' ||
      typeof control.pollDispatchBindingBody !== 'function' ||
      typeof admitDispatchJson !== 'function' ||
      dispatchRuntime === null || typeof dispatchRuntime !== 'object' ||
      typeof dispatchRuntime.supports !== 'function' ||
      typeof dispatchRuntime.start !== 'function' ||
      typeof dispatchRuntime.cancel !== 'function' ||
      typeof dispatchRuntime.release !== 'function' ||
      typeof dispatchRuntime.close !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    fail('InvalidRemoteSiteAgentConfiguration');
  }
  const endpoint = `/v1/sites/${encodeURIComponent(siteKey)}/generations/` +
    `${siteGeneration}/dispatches`;
  const queryEndpoint = `${endpoint}/query`;
  const cancelEndpoint = `${endpoint}/cancel`;
  const releaseEndpoint = `${endpoint}/release`;
  let admissionClosed = false;
  let listenerClosed = false;
  let runtimeClosed = false;
  let closeInFlight;
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
      const authority = coordinatorAuthorities.get(peer.fingerprint256);
      if (!request.socket.authorized || !text(authority)) {
        reply(response, 404, {error: 'not_found'});
        return;
      }
      const admissionRequest = request.method === 'POST' &&
        request.url === endpoint;
      const queryRequest = request.method === 'POST' &&
        request.url === queryEndpoint;
      const cancelRequest = request.method === 'POST' &&
        request.url === cancelEndpoint;
      const releaseRequest = request.method === 'POST' &&
        request.url === releaseEndpoint;
      if ((!admissionRequest && !queryRequest && !cancelRequest &&
          !releaseRequest) ||
          request.headers['content-type'] !== 'application/json') {
        reply(response, 404, {error: 'not_found'});
        return;
      }
      const claimed = request.headers['actql-dispatch-cid'];
      if (!text(claimed)) {
        reply(response, 400, {error: 'invalid_request'});
        return;
      }
      const body = await readBounded(request, maxRequestBytes);
      let inputBindingBody;
      let dispatch;
      if (admissionRequest) {
        const envelope = control.admitPollDispatch(body);
        dispatch = control.pollDispatchRequest(envelope);
        inputBindingBody = control.pollDispatchBindingBody(envelope);
        if (control.identity(dispatch) !== claimed) {
          fail('RemoteDispatchIdentityMismatch');
        }
      } else {
        dispatch = admitDispatchJson(control, body, claimed, maxRequestBytes);
      }
      const keyParts = control.journalKey(dispatch);
      if (keyParts[0] !== authority || keyParts[1] !== siteKey ||
          Number(keyParts[2]) !== siteGeneration) {
        reply(response, 404, {error: 'not_found'});
        return;
      }
      if (queryRequest || cancelRequest || releaseRequest) {
        const accepted = store.inspect(dispatch, control);
        const state = store.inspectState(dispatch, control);
        if (accepted === undefined || state === undefined ||
            accepted.dispatch_request_cid !== control.identity(dispatch)) {
          reply(response, 404, {error: 'not_found'});
          return;
        }
        const record = control.restoreHistorical(journal, dispatch);
        if (cancelRequest) {
          dispatchRuntime.cancel(dispatch);
          replyCanonical(response, control.replyJson(record));
          return;
        }
        if (releaseRequest) {
          await dispatchRuntime.release(dispatch);
        }
        const observed = releaseRequest
          ? control.restoreHistorical(journal, dispatch)
          : record;
        const stored = store.inspectEvidence(dispatch, control);
        const evidence = stored === undefined
          ? undefined
          : admitRemoteExecutionEvidenceJson(
            control,
            stored.execution_evidence_json,
            stored.execution_evidence_cid,
            dispatch,
          );
        const subject = stored === undefined
          ? undefined
          : admitRemoteManagedOutputSubjectJson(
            control,
            stored.managed_output_subject_json,
            stored.managed_output_subject_cid,
            dispatch,
          );
        const measurement = stored === undefined
          ? undefined
          : admitRemoteManagedOutputMeasurementJson(
            control,
            stored.managed_output_measurement_json,
            stored.managed_output_measurement_cid,
          );
        replyCanonical(
          response,
          control.statusJson(observed, evidence, subject, measurement),
        );
        return;
      }
      const existing = store.inspect(dispatch, control);
      if (existing !== undefined) {
        if (existing.dispatch_request_cid !== control.identity(dispatch)) {
          fail('RemoteDispatchCollision');
        }
        const admission = control.prepareAdmission(journal, dispatch);
        const record = store.accept(admission, dispatch, control);
        replyCanonical(response, control.replyJson(record));
        return;
      }
      if (admissionClosed) {
        reply(response, 503, {error: 'site_unavailable'});
        return;
      }
      const admission = control.prepareAdmission(journal, dispatch);
      if (!await dispatchRuntime.supports(dispatch)) {
        reply(response, 409, {error: 'dispatch_unsupported'});
        return;
      }
      const record = store.accept(admission, dispatch, control);
      if (control.runtimeStartable(record)) {
        dispatchRuntime.start(dispatch, record, undefined, inputBindingBody);
      }
      replyCanonical(response, control.replyJson(record));
    } catch (error) {
      if (!response.headersSent) {
        const conflict = error?.code === 'RemoteDispatchCollision' ||
          error?.code === 'RemoteAttemptAlreadyDispatched';
        reply(response, conflict ? 409 : 400, {
          error: conflict ? 'dispatch_conflict' : 'invalid_request',
        });
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
    fail('RemoteSiteAgentAddressUnavailable');
  }
  return Object.freeze({
    origin: `https://${host}:${address.port}`,
    port: address.port,
    stopAdmission() {
      if (admissionClosed) return false;
      admissionClosed = true;
      return true;
    },
    async close() {
      if (listenerClosed && runtimeClosed) return false;
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
        if (!runtimeClosed) {
          await dispatchRuntime.close();
          runtimeClosed = true;
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
