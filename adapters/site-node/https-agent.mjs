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
  maxRequestBytes = 65_536,
} = {}) {
  if (!text(host) || !Number.isSafeInteger(port) || port < 0 ||
      key === undefined || cert === undefined || ca === undefined ||
      !(coordinatorAuthorities instanceof Map) ||
      !text(siteKey) || !Number.isSafeInteger(siteGeneration) ||
      siteGeneration < 0 || journal === undefined || store === undefined ||
      control === null || typeof control !== 'object' ||
      typeof admitDispatchJson !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    fail('InvalidRemoteSiteAgentConfiguration');
  }
  const endpoint = `/v1/sites/${encodeURIComponent(siteKey)}/generations/` +
    `${siteGeneration}/dispatches`;
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
      if (request.method !== 'POST' || request.url !== endpoint ||
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
      const admission = control.prepareAdmission(journal, dispatch);
      const record = store.accept(admission, dispatch, control);
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
  let closed = false;
  return Object.freeze({
    origin: `https://${host}:${address.port}`,
    port: address.port,
    async close() {
      if (closed) return false;
      closed = true;
      await new Promise((resolve, reject) => server.close(error => {
        if (error) reject(error);
        else resolve();
      }));
      return true;
    },
  });
}
