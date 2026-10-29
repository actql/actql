// The installed RowRun's one managed HTTP reader. Provider callbacks describe
// requests and decode charged responses; they never receive a credential,
// authorization, transport, stop handle or a second accounting owner.
import {types} from 'node:util';
import {ownHttpRequest, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from
  '../site-node/https-credential-resource.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
function method(value, name) {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const field = Object.getOwnPropertyDescriptor(value, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
    fail('InstalledSourceReaderMethodUnavailable');
  }
  return field.value;
}

export function createInstalledCredentialSourceReader({capacity, site, operation,
  maxResponses, maxResponseBytes, maxSecretBytes, preparePageReader}) {
  if (capacity === undefined || capacity === null || typeof operation !== 'string' ||
      operation.length === 0 || ![maxResponses, maxResponseBytes, maxSecretBytes].every(positive) ||
      typeof preparePageReader !== 'function') fail('InvalidInstalledCredentialSourceReader');
  const callResource = method(site, 'callResource');
  const referenceCurrent = method(site, 'referenceCurrent');
  const credential = Object.freeze({...site.credential});
  const factory = Object.freeze({capacity, prepare(options) {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    const verifyRead = method(options, 'verifyRead');
    const authorize = method(options, 'authorizationFor');
    const chargePage = method(options, 'chargePage');
    const consumePage = method(options, 'consumePage');
    const consumePageWire = options.consumePageWire === undefined ? undefined : method(options, 'consumePageWire');
    const columns = Object.freeze([...options.columns]);
    const pendingCallbacks = new Set();
    function sync(value) {
      const then = value?.then;
      if (typeof then === 'function') {
        // Capture the SAME returned computation and selected then receiver.
        // Refusal does not cancel its existing borrow of response/input DATA.
        const pending = new Promise((resolve, reject) => Reflect.apply(then, value, [resolve, reject]));
        pendingCallbacks.add(pending);
        const settled = () => {
          pendingCallbacks.delete(pending);
          if (stopped) {
            try {cleanup();} catch (cause) {cleanupFailure = cause;}
          }
        };
        void pending.then(settled, settled);
        fail('InstalledSourcePageCallbackNotSynchronous');
      }
      return value;
    }
    // Provider construction is synchronous and I/O-free, after the original
    // RowRun reservation and response-cleanup association have been installed.
    let provider, fetchPage, decodePage, onError, setupFailure, setupFailed = false;
    try {
      provider = sync(preparePageReader(Object.freeze({resource: options.resource,
        columns, requestWire: options.requestWire})));
      fetchPage = method(provider, 'fetchPage'); decodePage = method(provider, 'decodePage');
      const errorField = Object.getOwnPropertyDescriptor(provider, 'onError');
      if (errorField !== undefined) {
        if (!Object.hasOwn(errorField, 'value') || typeof errorField.value !== 'function') {
          fail('InstalledSourceReaderMethodUnavailable');
        }
        onError = errorField.value;
      }
    } catch (cause) {setupFailed = true; setupFailure = cause;}
    const stop = new AbortController();
    const signal = options.signal === undefined ? stop.signal
      : AbortSignal.any([options.signal, stop.signal]);
    let phase = 'ready', readPending = false, stopped = false, retired = false;
    let binding, bindingClosed = false, cleanupFailure, primary;
    let responses = [], responseCount = 0, responseBytes = 0n, rowCount = 0;
    const verify = async () => {
      signal.throwIfAborted();
      if (Reflect.apply(referenceCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
      await Reflect.apply(verifyRead, options, []);
      signal.throwIfAborted();
      if (Reflect.apply(referenceCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
    };
    function closeTransport() {
      if (binding !== undefined && !bindingClosed) {
        bindingClosed = closeHttpsCredentialBinding(binding) === 'closed';
      }
      return binding === undefined || bindingClosed;
    }
    function cleanup() {
      if (retired) return;
      const closed = closeTransport();
      if (!stopped || readPending || pendingCallbacks.size !== 0 || !closed) return;
      // Native close and the joined read, rather than Promise settlement alone,
      // authorize retirement of this reader's original response aliases.
      responses.length = 0;
      responses = provider = fetchPage = decodePage = onError = binding = primary = setupFailure = undefined;
      retired = true;
    }
    let handle;
    handle = Object.freeze({
      async read() {
        if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
        if (phase !== 'ready' || stopped || retired) fail('InstalledSourceReaderAlreadyStarted');
        phase = 'reading'; readPending = true;
        try {
          // Even a pure provider construction failure returns this same cleanup
          // handle to the RowRun; no unreturned child can strand its borrow.
          if (setupFailed) throw setupFailure;
          await verify();
          const initial = ownInvocationAuthorization(await Reflect.apply(authorize, options, [0]));
          if (initial.scope.operation !== operation) fail('ForeignInstalledSourceReaderAuthorization');
          await verify();
          binding = openHttpsCredentialBinding({...credential, scope: initial.scope, maxSecretBytes});
          const boundCredential = Object.freeze({...credential, binding});
          for (let index = 0; index < maxResponses; index++) {
            await verify();
            const context = Object.freeze({pageIndex: index, rowCount,
              receivedBodyBytes: responseBytes});
            const described = sync(Reflect.apply(fetchPage, provider, [context]));
            const request = described === null || typeof described !== 'object' || types.isProxy(described)
              ? undefined : ownHttpRequest(described);
            const responseHeaders = ownResponseHeaderNames(described?.responseHeaders ?? []);
            if (request === undefined || request.method !== 'GET' || request.body !== undefined) {
              fail('InvalidInstalledSourcePageRequest');
            }
            const authorization = index === 0 ? initial
              : ownInvocationAuthorization(await Reflect.apply(authorize, options, [index]));
            if (authorization.scope.operation !== operation ||
                !invocationBindingsMatch(authorization.scope, initial.scope)) {
              fail('ForeignInstalledSourceReaderAuthorization');
            }
            await verify();
            const response = await invokeScopedCredentialOperation({authorization,
              credential: boundCredential,
              callResource: input => Reflect.apply(callResource, site, [{...input, currentBeforeSend: verify}]),
              operation, method: request.method, path: request.target,
              headers: request.headers, responseHeaders,
              maxResponseBytes, signal});
            // Retain BEFORE fallible accounting, current, status or decoding.
            responses.push(response); responseCount++;
            responseBytes += BigInt(response.body.byteLength);
            const charge = await Reflect.apply(chargePage, options, [response.body]);
            await verify();
            const page = sync(Reflect.apply(decodePage, provider, [response,
              Object.freeze({pageIndex: index, rowCount, receivedBodyBytes: responseBytes})]));
            if (page === null || typeof page !== 'object' || typeof page.done !== 'boolean' ||
                (Object.hasOwn(page, 'rows') === Object.hasOwn(page, 'rowsWire'))) {
              fail('InvalidInstalledSourceDecodedPage');
            }
            const rowsWire = Object.hasOwn(page, 'rowsWire');
            if (rowsWire ? typeof page.rowsWire !== 'string' || consumePageWire === undefined ||
                !Number.isSafeInteger(page.rowCount) || page.rowCount < 0 : !Array.isArray(page.rows)) {
              fail('InvalidInstalledSourceDecodedPage');
            }
            await Reflect.apply(rowsWire ? consumePageWire : consumePage, options,
              [rowsWire ? page.rowsWire : page.rows, Object.freeze({charge})]);
            rowCount += rowsWire ? page.rowCount : page.rows.length;
            await verify();
            if (page.done) {phase = 'succeeded'; return Object.freeze({pages: responseCount, rowCount});}
          }
          fail('InstalledSourceReaderResponseCountLimit');
        } catch (cause) {
          phase = 'failed'; primary = cause;
          if (onError !== undefined) throw sync(Reflect.apply(onError, provider, [cause]));
          throw cause;
        } finally {
          readPending = false;
          try {if (stopped) cleanup(); else closeTransport();}
          catch (cause) {cleanupFailure = cause; if (primary === undefined) {phase = 'failed'; throw cause;}}
        }
      },
      requestStop(reason) {
        if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
        if (retired) return;
        stopped = true; stop.abort(reason);
        try {cleanup();} catch (cause) {cleanupFailure = cause; throw cause;}
      },
      retry() {
        if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
        if (!stopped) fail('InstalledSourceReaderStopRequired');
        cleanup();
      },
      observe() {
        if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
        return Object.freeze({phase, stopRequested: stopped, readPending,
          pendingCallbacks: pendingCallbacks.size,
          responseCount, receivedBodyBytes: responseBytes,
          transportClosed: binding === undefined || bindingClosed,
          transportFailure: cleanupFailure !== undefined, cleanupConfirmed: retired});
      },
    });
    return handle;
  }});
  return factory;
}
