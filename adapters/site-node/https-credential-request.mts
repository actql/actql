import {checkHttpRequestMethodBody, ownHttpByteRequest, ownRequestHeaders,
  ownResponseHeaderNames} from '../host-common/http-exchange.mjs';

type NonemptyText = (value: unknown) => value is string;
type Refusal = (code: string, cause?: unknown) => never;
type ScopeSelection = Readonly<{operation?: unknown; resourceOrigin?: unknown}>;
type RegisteredOperation = Readonly<{
  method?: unknown;
  path?: unknown;
  body?: unknown;
  bodyBytes?: unknown;
  bodyMediaType?: unknown;
  maxBodyBytes?: unknown;
  headers?: unknown;
  responseHeaders?: unknown;
}>;

// The unchanged default of the original request constructor below. Installed
// recipe assembly consumes this same bound instead of copying its number.
export const httpsCredentialDefaultRequestBytes = 1_048_576;

function exactRequestTarget(path: unknown, text: NonemptyText, fail: Refusal) {
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

export function operationFor(operations: unknown, scope: ScopeSelection | null | undefined,
  maxRequestBytes: number, text: NonemptyText, fail: Refusal) {
  if (!(operations instanceof Map) || !text(scope?.operation) ||
      !text(scope?.resourceOrigin)) {
    fail('InvalidRemoteCredentialOperation');
  }
  const operation = operations.get(scope.operation) as RegisteredOperation | null | undefined;
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
          (operation.maxBodyBytes as number) > maxRequestBytes) fail('InvalidRemoteCredentialOperation');
      const request = ownHttpByteRequest({method, path: operation.path,
        body, bodyBytes: operation.bodyBytes, bodyMediaType: operation.bodyMediaType,
        maxBodyBytes: operation.maxBodyBytes});
      body = request.bodyBytes;
      bodyMediaType = request.bodyMediaType as string;
    } else {
      checkHttpRequestMethodBody(method, body, {requireBody: true});
    }
  } catch (error) {
    fail((error as {code?: unknown} | null | undefined)?.code === 'InvalidHttpRequestMethod'
      ? 'UnsupportedRemoteCredentialOperation'
      : 'InvalidRemoteCredentialOperation', error);
  }
  const requestBytes = body === undefined ? 0 : Buffer.byteLength(body as string | Buffer);
  if (requestBytes > maxRequestBytes) {
    fail('InvalidRemoteCredentialOperation');
  }
  // Allowed non-secret request headers and the declared response header
  // names travel with the registered operation; the typed exchange refuses
  // reserved names and over-long values before anything is sent.
  const headers = ownRequestHeaders(operation.headers);
  const responseHeaders = ownResponseHeaderNames(operation.responseHeaders);
  let origin: URL;
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
    method: method as string,
    hostname: origin.hostname,
    port: origin.port || undefined,
    path: exactRequestTarget(operation.path, text, fail),
    body: body as string | Buffer | undefined,
    bodyMediaType,
    requestBytes,
    headers,
    responseHeaders,
  });
}
