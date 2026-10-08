import {request as httpsRequest} from 'node:https';

const fail = code => { throw Object.assign(new Error(code), {code}); };

// One exact request, no retry or fallback. An I/O error does not establish
// absence of a hold; callers retain the original binding and query its state.
export async function sendRemoteBundleCustody({origin, ca, cert, key,
  servername = 'localhost', control, request: suppliedRequest, signal,
  maxResponseBytes = 65_536} = {}) {
  let target;
  try { target = new URL(origin); }
  catch { fail('InvalidBundleRetentionClient'); }
  if (target.protocol !== 'https:' || target.username || target.password ||
      target.pathname !== '/' || target.search || target.hash ||
      ca === undefined || cert === undefined || key === undefined ||
      typeof servername !== 'string' || !servername ||
      !Number.isSafeInteger(maxResponseBytes) || maxResponseBytes <= 0 || maxResponseBytes > 65_536) {
    fail('InvalidBundleRetentionClient');
  }
  for (const name of ['custodyRequestJson', 'custodyRequestIdentity',
    'admitCustodyRequestJson', 'custodyRequestScope', 'holdScopeProjection',
    'admitCustodyResponseJson']) {
    if (typeof control?.[name] !== 'function') fail('BundleRetentionUnsupported');
  }
  const body = control.custodyRequestJson(suppliedRequest);
  const requestCid = control.custodyRequestIdentity(suppliedRequest);
  const request = control.admitCustodyRequestJson(body, requestCid);
  const parts = control.holdScopeProjection(control.custodyRequestScope(request));
  target.pathname = `/v1/sites/${encodeURIComponent(parts[8])}/generations/` +
    `${parts[9]}/bundle-retention`;
  const bytes = Buffer.from(body, 'utf8');
  return await new Promise((resolve, reject) => {
    const outgoing = httpsRequest(target, {method: 'POST', ca, cert, key, agent: false,
      rejectUnauthorized: true,
      servername, minVersion: 'TLSv1.3', signal,
      headers: {'content-type': 'application/json',
        'content-length': String(bytes.byteLength),
        'actql-bundle-custody-cid': requestCid}}, response => {
      const chunks = [];
      let length = 0;
      response.on('data', chunk => {
        length += chunk.byteLength;
        if (length > maxResponseBytes) {
          response.destroy(Object.assign(new Error('BundleRetentionResponseTooLarge'),
            {code: 'BundleRetentionResponseTooLarge'}));
        } else chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        if (response.statusCode !== 200) {
          reject(Object.assign(new Error('BundleRetentionRejected'),
            {code: 'BundleRetentionRejected', status: response.statusCode}));
          return;
        }
        try {
          const claimed = response.headers['actql-bundle-custody-response-cid'];
          if (typeof claimed !== 'string' || !claimed) fail('InvalidBundleRetentionResponse');
          const wire = new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks, length));
          resolve(control.admitCustodyResponseJson(request, wire, claimed));
        } catch (cause) {
          reject(Object.assign(new Error('InvalidBundleRetentionResponse', {cause}),
            {code: 'InvalidBundleRetentionResponse'}));
        }
      });
    });
    outgoing.on('error', reject);
    outgoing.end(bytes);
  });
}
