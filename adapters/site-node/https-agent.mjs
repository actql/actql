import {createServer} from 'node:https';

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
      typeof admitDispatchJson !== 'function' ||
      dispatchRuntime === null || typeof dispatchRuntime !== 'object' ||
      typeof dispatchRuntime.supports !== 'function' ||
      typeof dispatchRuntime.start !== 'function' ||
      typeof dispatchRuntime.cancel !== 'function' ||
      typeof dispatchRuntime.close !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    fail('InvalidRemoteSiteAgentConfiguration');
  }
  const endpoint = `/v1/sites/${encodeURIComponent(siteKey)}/generations/` +
    `${siteGeneration}/dispatches`;
  const queryEndpoint = `${endpoint}/query`;
  const cancelEndpoint = `${endpoint}/cancel`;
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
      if ((!admissionRequest && !queryRequest && !cancelRequest) ||
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
      const dispatch = admitDispatchJson(control, body, claimed, maxRequestBytes);
      const keyParts = control.journalKey(dispatch);
      if (keyParts[0] !== authority || keyParts[1] !== siteKey ||
          Number(keyParts[2]) !== siteGeneration) {
        reply(response, 404, {error: 'not_found'});
        return;
      }
      if (queryRequest || cancelRequest) {
        const accepted = store.inspect(dispatch, control);
        const state = store.inspectState(dispatch, control);
        if (accepted === undefined || state === undefined ||
            accepted.dispatch_request_cid !== control.identity(dispatch)) {
          reply(response, 404, {error: 'not_found'});
          return;
        }
        if (cancelRequest) {
          dispatchRuntime.cancel(dispatch);
          reply(response, 200, {
            version: 'actql-remote-dispatch-response/0.1',
            dispatch_request_cid: control.identity(dispatch),
            revision: state[0],
            state: [
              state[1],
              state[2],
              state[3],
              state[4] ? 1 : 0,
              state[5] ? 1 : 0,
            ],
          });
          return;
        }
        const evidence = store.inspectEvidence(dispatch, control);
        reply(response, 200, {
          version: 'actql-remote-dispatch-status/0.1',
          dispatch_request_cid: control.identity(dispatch),
          revision: state[0],
          state: [
            state[1],
            state[2],
            state[3],
            state[4] ? 1 : 0,
            state[5] ? 1 : 0,
          ],
          evidence: evidence === undefined ? null : {
            cid: evidence.execution_evidence_cid,
            wire: evidence.execution_evidence_json,
          },
          subject: evidence === undefined ? null : {
            cid: evidence.managed_output_subject_cid,
            wire: evidence.managed_output_subject_json,
          },
          measurement: evidence === undefined ? null : {
            cid: evidence.managed_output_measurement_cid,
            wire: evidence.managed_output_measurement_json,
          },
        });
        return;
      }
      if (admissionClosed) {
        reply(response, 503, {error: 'site_unavailable'});
        return;
      }
      const admission = control.prepareAdmission(journal, dispatch);
      if (!dispatchRuntime.supports(dispatch)) {
        reply(response, 409, {error: 'dispatch_unsupported'});
        return;
      }
      const record = store.accept(admission, dispatch, control);
      if (control.runtimeStartable(record)) {
        dispatchRuntime.start(dispatch, record);
      }
      reply(response, 200, {
        version: 'actql-remote-dispatch-response/0.1',
        dispatch_request_cid: control.identity(dispatch),
        revision: control.revision(record),
        state: control.status(record),
      });
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
