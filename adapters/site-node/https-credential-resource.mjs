import {request as httpsRequest} from 'node:https';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

function exactRequestTarget(path) {
  if (!text(path) || !path.startsWith('/') || path.startsWith('//') ||
      path.includes('\\') || path.includes('#')) {
    fail('InvalidRemoteCredentialOperation');
  }
  for (let index = 0; index < path.length; index++) {
    const code = path.charCodeAt(index);
    if (code < 0x21 || code > 0x7e) {
      fail('InvalidRemoteCredentialOperation');
    }
    if (code === 0x25) {
      if (index + 2 >= path.length ||
          !/^[0-9A-Fa-f]{2}$/.test(path.slice(index + 1, index + 3))) {
        fail('InvalidRemoteCredentialOperation');
      }
      index += 2;
    }
  }
  return path;
}

function operationFor(operations, scope, maxRequestBytes) {
  if (!(operations instanceof Map) || !text(scope?.operation) ||
      !text(scope?.resourceOrigin)) {
    fail('InvalidRemoteCredentialOperation');
  }
  const operation = operations.get(scope.operation);
  if (operation === undefined || operation === null ||
      typeof operation !== 'object' ||
      !['GET', 'POST', 'PATCH'].includes(operation.method) ||
      !text(operation.path)) {
    fail('UnsupportedRemoteCredentialOperation');
  }
  const mutation = operation.method !== 'GET';
  if ((mutation && (typeof operation.body !== 'string' ||
      Buffer.byteLength(operation.body) > maxRequestBytes)) ||
      (!mutation && operation.body !== undefined)) {
    fail('InvalidRemoteCredentialOperation');
  }
  let origin;
  try {
    origin = new URL(scope.resourceOrigin);
  } catch (error) {
    fail('InvalidRemoteCredentialOperation', error);
  }
  if (origin.protocol !== 'https:' || origin.origin !== scope.resourceOrigin ||
      origin.username !== '' || origin.password !== '') {
    fail('InvalidRemoteCredentialOperation');
  }
  return Object.freeze({
    method: operation.method,
    hostname: origin.hostname,
    port: origin.port || undefined,
    path: exactRequestTarget(operation.path),
    body: mutation ? operation.body : undefined,
    requestBytes: mutation ? Buffer.byteLength(operation.body) : 0,
  });
}

function receive({hostname, port, path, method, body, requestBytes, secret,
  ca, cert, key, signal, maxResponseBytes}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (handler, value) => {
      if (settled) return;
      settled = true;
      handler(value);
    };
    const request = httpsRequest({
      protocol: 'https:',
      hostname,
      port,
      path,
      method,
      ca,
      cert,
      key,
      headers: Object.freeze({
        accept: 'application/json',
        authorization: `Bearer ${secret}`,
        ...(body === undefined ? {} : {
          'content-type': 'application/json',
          'content-length': requestBytes,
        }),
      }),
      signal,
    }, response => {
      const chunks = [];
      let received = 0;
      response.on('data', chunk => {
        received += chunk.byteLength;
        if (received > maxResponseBytes) {
          response.destroy(Object.assign(
            new Error('RemoteCredentialResponseLimitExceeded'),
            {code: 'RemoteCredentialResponseLimitExceeded'},
          ));
          return;
        }
        chunks.push(Buffer.from(chunk));
      });
      response.once('error', error => finish(reject, error));
      response.once('end', () => finish(resolve, Object.freeze({
        statusCode: response.statusCode,
        headers: response.headers,
        body: Buffer.concat(chunks, received),
      })));
    });
    request.once('error', error => finish(reject, error));
    request.end(body);
  });
}

/// Execute one pre-registered HTTPS operation. Credential material is resolved
/// and applied inside this adapter and is never returned to Connector code.
export async function callHttpsCredentialResource({
  grant,
  useId,
  scope,
  control,
  journal,
  operations,
  resolveSecret,
  ca,
  cert,
  key,
  now = Date.now,
  maxRequestBytes = 1_048_576,
  maxResponseBytes = 1_048_576,
  returnRejectedResponse = false,
  signal,
}) {
  if (typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' || typeof now !== 'function' ||
      !text(useId) || !count(maxRequestBytes) || maxRequestBytes === 0 ||
      !count(maxResponseBytes) || maxResponseBytes === 0 ||
      typeof returnRejectedResponse !== 'boolean') {
    fail('InvalidRemoteCredentialCall');
  }
  const operation = operationFor(operations, scope, maxRequestBytes);
  signal?.throwIfAborted();
  const claimed = journal.claim(
    control.identity(grant),
    useId,
    BigInt(now()),
    scope,
    control,
  );
  if (claimed.replayed) fail('RemoteCredentialUseAlreadyClaimed');
  let requestStarted = false;
  try {
    const secret = await resolveSecret(Object.freeze({
      grantCid: claimed.record.grantCid,
      principal: scope.principal,
      tenant: scope.tenant,
      environment: scope.environment,
      operation: scope.operation,
      resourceOrigin: scope.resourceOrigin,
      siteKey: scope.siteKey,
      siteGeneration: scope.siteGeneration,
      connectorRegistration: scope.connectorRegistration,
    }), signal);
    if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
    signal?.throwIfAborted();
    journal.authorize(
      claimed.use,
      BigInt(now()),
      scope,
      control,
    );
    requestStarted = true;
    const response = await receive({
      ...operation,
      secret,
      ca,
      cert,
      key,
      signal,
      maxResponseBytes,
    });
    if (response.statusCode === 401 &&
        typeof resolveSecret.invalidate === 'function') {
      resolveSecret.invalidate(secret);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      fail('RemoteCredentialRedirectRejected');
    }
    const accepted = response.statusCode >= 200 && response.statusCode < 300;
    if (!accepted && !returnRejectedResponse) {
      fail('RemoteCredentialResourceRejected');
    }
    journal.finish(claimed.record.useCid, accepted ? 'succeeded' : 'failed');
    return Object.freeze({
      useCid: claimed.record.useCid,
      accepted,
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
    });
  } catch (error) {
    journal.finish(
      claimed.record.useCid,
      requestStarted &&
        (operation.method !== 'GET' ||
          error?.code !== 'RemoteCredentialRedirectRejected') &&
        error?.code !== 'RemoteCredentialResourceRejected'
        ? 'unknown'
        : 'failed',
    );
    throw error;
  }
}
