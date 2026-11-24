import {request as httpsRequest, type RequestOptions} from 'node:https';
import {maxHeaderSize, type ClientRequest, type IncomingMessage} from 'node:http';
import type {Socket} from 'node:net';
import {types} from 'node:util';

type Refuse = (code: string, cause?: unknown) => never;
type TransportBinding = {
  request: ClientRequest | undefined;
  secretPresentation?: 'bearer' | 'kintone-api-token';
  unjoinedResponseCustody?: {original: Promise<unknown>; cause: unknown};
};
// The existing Credential Owner validates this pair before its claim. The
// observer may supply malformed asynchronous values, which remain addressed
// by the original retirement path rather than treated as a synchronous ACK.
type ResponseReader = {
  binding?: TransportBinding;
  observeResponseBytes?: undefined;
} | {
  binding: TransportBinding;
  observeResponseBytes: (count: number) => unknown;
};
type PhysicalAuthentication =
  | {authenticationForm: true; secret?: undefined}
  | {authenticationForm?: false; secret: string};
type ReceiveOptions = Pick<RequestOptions, 'port' | 'ca' | 'cert' | 'key' | 'signal'> &
    ResponseReader & PhysicalAuthentication & {
  hostname: string;
  path: string;
  method: string;
  body?: string | Uint8Array;
  bodyMediaType?: string;
  requestBytes: number;
  headers: readonly (readonly [string, string])[];
  maxResponseBytes: number;
  retainRunResponseOriginal?: boolean;
};
type PhysicalResponse = Readonly<{
  statusCode: IncomingMessage['statusCode'];
  headers: IncomingMessage['headers'];
  body: Buffer;
  requestRepresentation: Readonly<{
    accept: string | undefined;
    acceptEncoding: string | undefined;
    ifMatch: string | undefined;
  }> | undefined;
  responseRepresentation: Readonly<{etagCount: number; contentEncodingCount: number}> | undefined;
}>;

const nativePromiseThen = Promise.prototype.then;

// The original Node process's existing default, also passed to its actual
// parser below. This is an implementation bound, never a caller allowance.
export const httpsCredentialResponseHeaderByteLimit = maxHeaderSize;

// The actual bearer-header constructor and its logical backing quote use
// the same fixed prefix. No credential material is exposed by this DATA.
export const httpsCredentialAuthorizationPrefix = 'Bearer ';

// Implementation geometry of this original observed binary reader, not a
// configurable body cap, transfer allowance or authority.
export const httpsCredentialResponseReadQuantum = 16_384;

export function receive({hostname, port, path, method, body, bodyMediaType, requestBytes, secret,
  authenticationForm = false,
  headers, ca, cert, key, signal, maxResponseBytes, binding,
  retainRunResponseOriginal = false, observeResponseBytes}: ReceiveOptions, fail: Refuse) {
  return new Promise<PhysicalResponse>((resolve, reject) => {
    let settled = false;
    let socket: Socket | undefined;
    let socketClosed = false;
    let requestClosed = false;
    let complete: (() => void) | undefined, observerPending = false;
    const release = () => {
      if (!binding || !requestClosed || (socket && !socketClosed) || observerPending) return;
      binding.request = undefined;
      complete?.();
    };
    const finish = <Value,>(handler: (value: Value) => void, value: Value) => {
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
    const physicalHeaders: Readonly<Record<string, string | number | undefined>> = Object.freeze({
      accept: 'application/json',
      ...Object.fromEntries(headers),
      ...(authenticationForm ? {} : binding?.secretPresentation === 'kintone-api-token'
        ? {'x-cybozu-api-token': secret}
        : {authorization: httpsCredentialAuthorizationPrefix + secret}),
      ...(body === undefined ? {} : {
        'content-type': bodyMediaType,
        'content-length': requestBytes,
      }),
    });
    // Only these non-secret primitive values describe the original physical
    // representation. Never expose the credential-bearing header dictionary.
    const requestRepresentation = !retainRunResponseOriginal ? undefined :
      Object.freeze({
        accept: typeof physicalHeaders.accept === 'string' ? physicalHeaders.accept : undefined,
        acceptEncoding: typeof physicalHeaders['accept-encoding'] === 'string'
          ? physicalHeaders['accept-encoding'] : undefined,
        ifMatch: typeof physicalHeaders['if-match'] === 'string'
          ? physicalHeaders['if-match'] : undefined,
      });
    const request = httpsRequest({
      protocol: 'https:',
      ...(binding ? {agent: false} : {}),
      hostname,
      port,
      path,
      method,
      maxHeaderSize: httpsCredentialResponseHeaderByteLimit,
      ca,
      cert,
      key,
      // A provider may replace `accept`; the credential and body framing
      // headers are this adapter's own.
      headers: physicalHeaders,
      signal,
    }, response => {
      // Node's normalized header object can discard duplicate singleton
      // headers. Conditional evidence needs the actual received multiplicity,
      // kept only in the existing private original-response projection.
      let etagCount = 0;
      let contentEncodingCount = 0;
      if (retainRunResponseOriginal) {
        for (let index = 0; index < response.rawHeaders.length; index += 2) {
          const name = response.rawHeaders[index].toLowerCase();
          if (name === 'etag') etagCount++;
          if (name === 'content-encoding') contentEncodingCount++;
        }
      }
      const responseRepresentation = !retainRunResponseOriginal ? undefined :
        Object.freeze({etagCount, contentEncodingCount});
      let chunks: Buffer[] | undefined = [];
      let detachReader: (() => void) | undefined;
      let received = 0;
      if (observeResponseBytes === undefined) {
        const readResponseChunk = (chunk: Buffer) => {
          received += chunk.byteLength;
          if (received > maxResponseBytes) {
            response.destroy(Object.assign(
              new Error('RemoteCredentialResponseLimitExceeded'),
              {code: 'RemoteCredentialResponseLimitExceeded'},
            ));
            return;
          }
          chunks!.push(Buffer.from(chunk));
        };
        response.on('data', readResponseChunk);
        detachReader = () => response.off('data', readResponseChunk);
      } else {
        // Capture the original method and receiver before an external observer
        // can replace read. Binary read(size) waits for size bytes until EOF,
        // permitting one final partial copy rather than arbitrary tiny copies.
        let readOriginal: IncomingMessage['read'] | undefined;
        // Bound the SAME
        // reader's selected representation to B+1 even when its protocol body
        // cap is B. Charge each actual read BEFORE limit refusal/copy; the last
        // offending byte is included, never silently counted as zero.
        const readObservedResponse = () => {
          if (settled || observerPending || response.destroyed) return;
          try {
            // Capture once under the SAME original error fence. A throwing
            // getter (including thrown undefined) destroys this response and
            // follows its existing binding/socket retirement path.
            readOriginal ??= response.read;
            let chunk: Buffer | null;
            while ((chunk = Reflect.apply(readOriginal, response, [Math.min(httpsCredentialResponseReadQuantum,
              maxResponseBytes - received + 1)]) as Buffer | null) !== null) {
              const observed = observeResponseBytes(chunk.byteLength);
              if (observed !== undefined) {
                if (types.isPromise(observed)) {
                  // Invalid async borrowing remains joined to this SAME
                  // request/socket promise until settlement. Cleanup cannot
                  // ACK or drop the callback's original child in the meantime.
                  observerPending = true;
                  const finishObserver = () => { observerPending = false; release(); };
                  try {
                    // Register on the native original before observing a
                    // replaceable public getter/method. A rejected wrapper
                    // around that method cannot settle the original task.
                    Reflect.apply(nativePromiseThen, observed, [finishObserver, finishObserver]);
                  } catch (cause) {
                    // Constructor/species can refuse before native registration.
                    // Keep that unresolved original under this existing binding;
                    // a socket close or failed join is not its cleanup ACK.
                    binding.unjoinedResponseCustody ??= {original: observed, cause};
                    observerPending = false;
                    throw cause;
                  }
                  void observed.then;
                } else {
                  const then = observed !== null && (typeof observed === 'object' || typeof observed === 'function')
                    ? (observed as {then?: unknown}).then : undefined;
                  if (typeof then === 'function') {
                    observerPending = true;
                    const joined = new Promise((yes, no) => Reflect.apply(then, observed, [yes, no]));
                    const finishObserver = () => { observerPending = false; release(); };
                    joined.then(finishObserver, finishObserver);
                  }
                }
                fail('InvalidRemoteCredentialResponseByteObserver');
              }
              received += chunk.byteLength;
              if (received > maxResponseBytes) fail('RemoteCredentialResponseLimitExceeded');
              chunks!.push(Buffer.from(chunk));
            }
          } catch (error) {
            // Native destroy(undefined/null/other falsey values) can close
            // without an error event. Enter the SAME completion fence with
            // the original throwable first; it still waits for this binding's
            // actual request/socket close and any borrowed observer task.
            finish(reject, error);
            response.destroy(error as Error);
          }
        };
        response.on('readable', readObservedResponse);
        detachReader = () => response.off('readable', readObservedResponse);
      }
      response.once('error', error => finish(reject, error));
      response.once('end', () => {
        let body;
        try { body = Buffer.concat(chunks!, received); }
        catch (error) { finish(reject, error); return; }
        // Only successful concatenation retires the copied receive prefix.
        // Sever the listener and its original Array, not the response/headers
        // or the request/socket/invalid-observer cleanup responsibilities.
        detachReader!();
        detachReader = undefined;
        chunks!.length = 0;
        chunks = undefined;
        finish(resolve, Object.freeze({
          statusCode: response.statusCode,
          headers: response.headers,
          body,
          requestRepresentation,
          responseRepresentation,
        }));
      });
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
