import {request as httpsRequest} from 'node:https';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

function operationFor(operations, scope) {
  if (!(operations instanceof Map) || !text(scope?.operation) ||
      !text(scope?.resourceOrigin)) {
    fail('InvalidRemoteCredentialOperation');
  }
  const operation = operations.get(scope.operation);
  if (operation === undefined || operation === null ||
      typeof operation !== 'object' || operation.method !== 'GET' ||
      !text(operation.path) || !operation.path.startsWith('/') ||
      operation.path.startsWith('//')) {
    fail('UnsupportedRemoteCredentialOperation');
  }
  let origin;
  let target;
  try {
    origin = new URL(scope.resourceOrigin);
    target = new URL(operation.path, origin);
  } catch (error) {
    fail('InvalidRemoteCredentialOperation', error);
  }
  if (origin.protocol !== 'https:' || origin.origin !== scope.resourceOrigin ||
      target.origin !== origin.origin || target.username !== '' ||
      target.password !== '') {
    fail('InvalidRemoteCredentialOperation');
  }
  return Object.freeze({method: operation.method, target});
}

function receive({target, method, secret, ca, cert, key, signal,
  maxResponseBytes}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (handler, value) => {
      if (settled) return;
      settled = true;
      handler(value);
    };
    const request = httpsRequest(target, {
      method,
      ca,
      cert,
      key,
      headers: Object.freeze({
        accept: 'application/json',
        authorization: `Bearer ${secret}`,
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
    request.end();
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
  maxResponseBytes = 1_048_576,
  returnRejectedResponse = false,
  signal,
}) {
  if (typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' || typeof now !== 'function' ||
      !text(useId) || !count(maxResponseBytes) || maxResponseBytes === 0 ||
      typeof returnRejectedResponse !== 'boolean') {
    fail('InvalidRemoteCredentialCall');
  }
  const operation = operationFor(operations, scope);
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
      requestStarted && error?.code !== 'RemoteCredentialRedirectRejected' &&
        error?.code !== 'RemoteCredentialResourceRejected'
        ? 'unknown'
        : 'failed',
    );
    throw error;
  }
}
