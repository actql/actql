import {request as httpsRequest} from 'node:https';
import {credentialInvocationBindingKeys} from
  '../host-common/credential-scope-fields.generated.mjs';
import {checkHttpRequestMethodBody, observeResponseHeaders, ownHttpByteRequest, ownRequestHeaders,
  ownResponseHeaderNames} from '../host-common/http-exchange.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

// Acquisition custody stays in the Credential Owner, not in Connector-visible
// fields. Scope equality is only identity; each operation still claims and
// authorizes its own nominal use in the original journal.
const bindings = new WeakMap();

export function openHttpsCredentialBinding({scope, control, journal,
  resolveSecret, maxSecretBytes}) {
  if (!scope || typeof scope !== 'object' ||
      typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' || !count(maxSecretBytes) ||
      maxSecretBytes === 0 || credentialInvocationBindingKeys.some(key =>
        !['string', 'number', 'bigint'].includes(typeof scope[key]))) {
    fail('InvalidRemoteCredentialBinding');
  }
  const original = Object.freeze(Object.fromEntries(
    credentialInvocationBindingKeys.map(key => [key, scope[key]])));
  const binding = Object.freeze(Object.create(null));
  bindings.set(binding, {original, control, journal, resolveSecret,
    maxSecretBytes, secret: undefined, active: false, retiring: false,
    closed: false, changed: false, request: undefined});
  return binding;
}

function retireBinding(state) {
  if (state.retiring && !state.active && state.request === undefined) {
    state.secret = undefined;
    state.closed = true;
  }
}

// Pending is the same original custody, never a close ACK. No timer, resolver
// lookup or new nominal use is started by cleanup. The active call observes
// request/socket retirement before relinquishing its original material.
export function closeHttpsCredentialBinding(binding) {
  const state = bindings.get(binding);
  if (!state) fail('InvalidRemoteCredentialBinding');
  state.retiring = true;
  state.request?.destroy(Object.assign(
    new Error('RemoteCredentialBindingRetiring'),
    {code: 'RemoteCredentialBindingRetiring'}));
  retireBinding(state);
  return state.closed ? 'closed' : 'pending';
}

function acquireBinding(binding, {scope, control, journal, resolveSecret}) {
  if (binding === undefined) return undefined;
  const state = bindings.get(binding);
  if (!state || state.control !== control || state.journal !== journal ||
      state.resolveSecret !== resolveSecret ||
      credentialInvocationBindingKeys.some(key =>
        scope?.[key] !== state.original[key])) {
    fail('ForeignRemoteCredentialBinding');
  }
  if (state.retiring) fail('RemoteCredentialBindingRetiring');
  if (state.changed) fail('RemoteCredentialBindingChanged');
  if (state.active) fail('RemoteCredentialBindingBusy');
  state.active = true;
  return state;
}

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
      !text(operation.path)) {
    fail('UnsupportedRemoteCredentialOperation');
  }
  const {method} = operation;
  const binary = operation.bodyBytes !== undefined || operation.bodyMediaType !== undefined ||
    operation.maxBodyBytes !== undefined;
  let body = operation.body, bodyMediaType = 'application/json';
  try {
    if (binary) {
      // Reject the outer call mismatch before allocating the physical copy.
      // This is an independent transport ceiling, not proof of funding.
      if (!Number.isSafeInteger(operation.maxBodyBytes) ||
          operation.maxBodyBytes > maxRequestBytes) fail('InvalidRemoteCredentialOperation');
      const request = ownHttpByteRequest({method, path: operation.path,
        body, bodyBytes: operation.bodyBytes, bodyMediaType: operation.bodyMediaType,
        maxBodyBytes: operation.maxBodyBytes});
      body = request.bodyBytes;
      bodyMediaType = request.bodyMediaType;
    } else {
      checkHttpRequestMethodBody(method, body, {requireBody: true});
    }
  } catch (error) {
    fail(error?.code === 'InvalidHttpRequestMethod'
      ? 'UnsupportedRemoteCredentialOperation'
      : 'InvalidRemoteCredentialOperation', error);
  }
  const requestBytes = body === undefined ? 0 : Buffer.byteLength(body);
  if (requestBytes > maxRequestBytes) {
    fail('InvalidRemoteCredentialOperation');
  }
  // Allowed non-secret request headers and the declared response header
  // names travel with the registered operation; the typed exchange refuses
  // reserved names and over-long values before anything is sent.
  const headers = ownRequestHeaders(operation.headers);
  const responseHeaders = ownResponseHeaderNames(operation.responseHeaders);
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
    method,
    hostname: origin.hostname,
    port: origin.port || undefined,
    path: exactRequestTarget(operation.path),
    body,
    bodyMediaType,
    requestBytes,
    headers,
    responseHeaders,
  });
}

function receive({hostname, port, path, method, body, bodyMediaType, requestBytes, secret,
  headers, ca, cert, key, signal, maxResponseBytes, binding}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let socket;
    let socketClosed = false;
    let requestClosed = false;
    let complete;
    const release = () => {
      if (!binding || !requestClosed || (socket && !socketClosed)) return;
      binding.request = undefined;
      complete?.();
    };
    const finish = (handler, value) => {
      if (settled) return;
      settled = true;
      if (!binding) {
        handler(value);
        return;
      }
      complete = () => handler(value);
      // Only this new acquisition port owns a one-request connection. A full
      // response is retained until its actual request and socket close events.
      socket?.destroy();
      release();
    };
    const request = httpsRequest({
      protocol: 'https:',
      ...(binding ? {agent: false} : {}),
      hostname,
      port,
      path,
      method,
      ca,
      cert,
      key,
      // A provider may replace `accept`; the credential and body framing
      // headers are this adapter's own.
      headers: Object.freeze({
        accept: 'application/json',
        ...Object.fromEntries(headers),
        authorization: `Bearer ${secret}`,
        ...(body === undefined ? {} : {
          'content-type': bodyMediaType,
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
    if (binding) {
      binding.request = request;
      request.once('socket', original => {
        socket = original;
        socket.once('close', () => {
          socketClosed = true;
          release();
        });
      });
      request.once('close', () => {
        requestClosed = true;
        release();
      });
    }
    request.once('error', error => finish(reject, error));
    request.end(body);
  });
}

/// Execute one pre-registered HTTPS operation. Credential material is resolved
/// and applied inside this adapter and is never returned to Connector code.
/// An operation is `{method, path, body?, headers?, responseHeaders?}`: the
/// optional entries are the typed exchange's allowed request headers and the
/// declared response header names (`adapters/host-common/http-exchange.mjs`).
async function callCredentialResource({
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
  currentBeforeSend,
  signal,
}, binding) {
  if (typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' || typeof now !== 'function' ||
      !text(useId) || !count(maxRequestBytes) || maxRequestBytes === 0 ||
      !count(maxResponseBytes) || maxResponseBytes === 0 ||
      typeof returnRejectedResponse !== 'boolean' ||
      (currentBeforeSend !== undefined && typeof currentBeforeSend !== 'function')) {
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
    const currentSecret = await resolveSecret(Object.freeze({
      grantCid: claimed.record.grantCid,
      principal: scope.principal,
      namespaceId: scope.namespaceId,
      environment: scope.environment,
      operation: scope.operation,
      resourceOrigin: scope.resourceOrigin,
      siteKey: scope.siteKey,
      siteGeneration: scope.siteGeneration,
      connectorRegistration: scope.connectorRegistration,
    }), signal);
    if (!text(currentSecret)) fail('RemoteCredentialSecretUnavailable');
    if (binding && (currentSecret.length > binding.maxSecretBytes ||
        Buffer.byteLength(currentSecret) > binding.maxSecretBytes)) {
      fail('RemoteCredentialSecretLimitExceeded');
    }
    // The original Host's current read check may require an asynchronous
    // configuration read. Run it after the resolver await, without passing
    // credential material or manufacturing a grant from its return value.
    // Recheck the original binding and journal after this await as well.
    if (currentBeforeSend !== undefined) {
      // Preserve the original refusal before starting another Host read when
      // retirement, cancellation or a replacement credential is already known.
      if (binding?.retiring) fail('RemoteCredentialBindingRetiring');
      if (binding?.secret !== undefined && binding.secret !== currentSecret) {
        binding.changed = true;
        fail('RemoteCredentialBindingChanged');
      }
      signal?.throwIfAborted();
      await currentBeforeSend();
    }
    if (binding?.retiring) fail('RemoteCredentialBindingRetiring');
    if (binding?.secret !== undefined && binding.secret !== currentSecret) {
      binding.changed = true;
      fail('RemoteCredentialBindingChanged');
    }
    signal?.throwIfAborted();
    journal.authorize(
      claimed.use,
      BigInt(now()),
      scope,
      control,
    );
    // No await separates the current authority fence, retained-material
    // selection and physical request construction. A later resolver result
    // cannot replace the original acquisition's privately retained secret.
    if (binding && binding.secret === undefined) binding.secret = currentSecret;
    const secret = binding ? binding.secret : currentSecret;
    requestStarted = true;
    const response = await receive({
      ...operation,
      secret,
      ca,
      cert,
      key,
      signal,
      maxResponseBytes,
      binding,
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
    // Only the declared response headers are observed, as bounded pairs; an
    // observation beyond the caps is a refusal of this exchange, recorded
    // below like any other failure after the request started.
    const headers = observeResponseHeaders(response.headers,
      operation.responseHeaders);
    journal.finish(claimed.record.useCid, accepted ? 'succeeded' : 'failed');
    return Object.freeze({
      useCid: claimed.record.useCid,
      accepted,
      statusCode: response.statusCode,
      headers,
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

export async function callHttpsCredentialResource(options) {
  const binding = acquireBinding(options.binding, options);
  try {
    return await callCredentialResource(options, binding);
  } finally {
    if (binding) {
      binding.active = false;
      retireBinding(binding);
    }
  }
}
