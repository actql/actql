import {request as httpsRequest} from 'node:https';

const fail = (code, cause, details = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...details});
};
const text = value => typeof value === 'string' && value.length > 0;

export async function sendRemoteDispatch({
  origin,
  ca,
  cert,
  key,
  servername = 'localhost',
  control,
  dispatch,
  signal,
  maxResponseBytes = 16_384,
} = {}) {
  if (!text(origin) || ca === undefined || cert === undefined ||
      key === undefined || !text(servername) ||
      control === null || typeof control !== 'object' ||
      typeof control.requestJson !== 'function' ||
      typeof control.journalKey !== 'function' ||
      typeof control.identity !== 'function' ||
      dispatch === undefined || !Number.isSafeInteger(maxResponseBytes) ||
      maxResponseBytes <= 0) {
    fail('InvalidRemoteSiteClientConfiguration');
  }
  const body = control.requestJson(dispatch);
  const bodyBytes = Buffer.from(body, 'utf8');
  const parts = control.journalKey(dispatch);
  const path = `/v1/sites/${encodeURIComponent(parts[1])}/generations/` +
    `${parts[2]}/dispatches`;
  return await new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(path, origin), {
      method: 'POST',
      ca,
      cert,
      key,
      servername,
      minVersion: 'TLSv1.3',
      signal,
      headers: {
        'content-type': 'application/json',
        'content-length': String(bodyBytes.byteLength),
        'actql-dispatch-cid': control.identity(dispatch),
      },
    }, response => {
      const chunks = [];
      let length = 0;
      response.on('data', chunk => {
        length += chunk.byteLength;
        if (length > maxResponseBytes) {
          response.destroy(Object.assign(
            new Error('RemoteSiteResponseTooLarge'),
            {code: 'RemoteSiteResponseTooLarge'},
          ));
          return;
        }
        chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        let payload;
        try { payload = JSON.parse(Buffer.concat(chunks, length)); }
        catch (error) {
          reject(Object.assign(new Error('InvalidRemoteSiteResponse', {
            cause: error,
          }), {code: 'InvalidRemoteSiteResponse'}));
          return;
        }
        if (response.statusCode !== 200) {
          reject(Object.assign(new Error('RemoteSiteRejected'), {
            code: 'RemoteSiteRejected',
            status: response.statusCode,
          }));
          return;
        }
        if (payload?.version !== 'actql-remote-dispatch-response/0.1' ||
            payload.dispatch_request_cid !== control.identity(dispatch) ||
            !Number.isSafeInteger(payload.revision) ||
            !Array.isArray(payload.state) || payload.state.length !== 5) {
          reject(Object.assign(new Error('InvalidRemoteSiteResponse'), {
            code: 'InvalidRemoteSiteResponse',
          }));
          return;
        }
        resolve(Object.freeze({
          dispatchRequestCid: payload.dispatch_request_cid,
          revision: payload.revision,
          state: Object.freeze([...payload.state]),
        }));
      });
    });
    request.on('error', reject);
    request.end(bodyBytes);
  });
}
