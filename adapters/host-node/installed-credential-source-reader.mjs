// Same RowRun reader custody for installed Credential Sources. The service
// supplies an original Site/issuer and a selected reader capacity declaration;
// Core still admits it on the original acquisition before prepare/read.
// One installed RowRun reader owner. Standard providers describe/decode pages;
// advanced drivers retain their existing protocol under this same custody.
import {types} from 'node:util';
import {ownHttpRequest, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from
  '../site-node/https-credential-resource.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
export const installedJsonSourceReaderLimitNames = Object.freeze([
  'maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth', 'maxRows',
  'maxTotalRows', 'maxPages', 'pageSize', 'maxCursorBytes', 'maxIdentityBytes',
  'maxTargetBytes', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth',
]);
export const installedJsonSourceReaderProfileLimitNames = Object.freeze([
  ...installedJsonSourceReaderLimitNames, 'maxColumns', 'maxProperties', 'maxNameUnits',
  'maxObjects', 'maxDeclarationBytes', 'maxDeclarationNodes', 'maxSecretBytes',
]);
function ownMethod(value, name) {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const field = Object.getOwnPropertyDescriptor(value, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
    fail('InstalledSourceReaderMethodUnavailable');
  }
  return field.value;
}

export function createInstalledCredentialSourceReader({capacity, originalSite, site,
  createReader, readPages, preparePageReader, operation, assertCurrent,
  maxResponses, maxResponseBytes, maxSecretBytes}) {
  const standard = preparePageReader !== undefined, hosted = originalSite !== undefined;
  if (capacity === undefined || capacity === null || !positive(maxResponses) ||
      (standard ? typeof preparePageReader !== 'function' || createReader !== undefined ||
        readPages !== undefined || typeof operation !== 'string' || operation.length === 0 ||
        !positive(maxResponseBytes) || !positive(maxSecretBytes)
        : !hosted || (createReader === undefined ? typeof readPages !== 'function'
          : typeof createReader !== 'function' || readPages !== undefined)) ||
      (hosted ? site !== undefined || typeof assertCurrent !== 'function' : !standard)) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  let sourceSite = hosted ? originalSite : site;
  let bind = hosted ? ownMethod(sourceSite, 'bindRunAcquisition') : undefined;
  let purpose = hosted ? ownMethod(sourceSite, 'authorizationPurpose') : undefined;
  let callResource = ownMethod(sourceSite, 'callResource');
  let referenceCurrent = ownMethod(sourceSite, 'referenceCurrent');
  let rawCredential = hosted ? undefined : Object.freeze({...sourceSite.credential});
  let factory, preparing = 0, retiring = false, factoryRetired = false;
  const readers = new Set();
  factory = Object.freeze({capacity, prepare(options, retainPreparation) {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    if (retainPreparation !== undefined && typeof retainPreparation !== 'function') {
      fail('InvalidInstalledSourcePreparationRetention');
    }
    if (preparing === Number.MAX_SAFE_INTEGER || readers.size === Number.MAX_SAFE_INTEGER) {
      fail('InstalledSourceReaderInventoryUnavailable');
    }
    preparing++;
    let handed = false, unreturnedStop, preparedReader, preparationPending = true;
    let preparationRetired = false;
    const preparation = retainPreparation === undefined ? undefined : Object.freeze({retire() {
      if (this !== preparation) fail('ForeignInstalledSourcePreparation');
      if (preparationRetired) return true;
      if (preparationPending) return false;
      if (preparedReader !== undefined) {
        const pending = preparedReader.requestStop();
        if (pending !== undefined) void Promise.resolve(pending).catch(() => {});
        if (preparedReader.observe().cleanupConfirmed !== true) return false;
      }
      preparedReader = undefined; preparationRetired = true;
      return true;
    }});
    try {
      // This is a view of ONE invocation within this same factory. A failed
      // prepare cannot retire other requests sharing the installation.
      if (preparation !== undefined) Reflect.apply(retainPreparation, undefined, [preparation]);
      retainPreparation = undefined;
      if (retiring || factoryRetired) fail('InstalledSourceReaderFactoryClosed');
      let verifyRead = ownMethod(options, 'verifyRead');
      let authorizationFor = ownMethod(options, 'authorizationFor');
      let chargePage = standard ? ownMethod(options, 'chargePage') : undefined;
      let consumePage = standard ? ownMethod(options, 'consumePage') : undefined;
      let consumePageWire = standard && options.consumePageWire !== undefined
        ? ownMethod(options, 'consumePageWire') : undefined;
      let selected = options, selectedSite = sourceSite;
      let constructor = createReader, sequence = readPages;
      let stop = new AbortController(); unreturnedStop = stop;
      let signal = options.signal === undefined ? stop.signal : AbortSignal.any([options.signal, stop.signal]);
      let phase = 'ready', readPending = false, stopped = false, retired = false;
      let stopPending = false, escapedResponseGraph = false, callbackDepth = 0;
      let acquisition, closeBinding, bindingClosed = false;
      let child, childRead, childStop, childRetire, childObserve, stopIssued = false, childRetired = false;
      let transportFailure, hadTransportFailure = false, cleanupRunning = false, primary;
      let responses = [], responseCount = 0, responseBytes = 0n, rowCount = 0;
      let provider, fetchPage, decodePage, onError, setupFailure, setupFailed = false;
      const pendingCallbacks = new Set();
      const check = () => {
        if (retired || stopped) fail('InstalledSourceReaderClosed');
        if ((hosted && Reflect.apply(assertCurrent, undefined, []) !== undefined) ||
            Reflect.apply(referenceCurrent, selectedSite, []) !== true) fail('InstalledSourceReaderNotCurrent');
      };
      const verify = async () => {
        signal.throwIfAborted(); check();
        await Reflect.apply(verifyRead, selected, []);
        signal.throwIfAborted(); check();
      };
      function closeTransport() {
        if (acquisition !== undefined && !bindingClosed) {
          bindingClosed = Reflect.apply(closeBinding, acquisition, []) === 'closed';
        }
        return acquisition === undefined || bindingClosed;
      }
      function cleanup() {
        if (retired) return true;
        if (cleanupRunning) return false;
        cleanupRunning = true;
        try {
          const closed = closeTransport();
          if (!stopped || readPending || stopPending || pendingCallbacks.size !== 0 || escapedResponseGraph) return false;
          if (child !== undefined && !childRetired) {
            childRetired = Reflect.apply(childRetire, child, []) === true &&
              Reflect.apply(childObserve, child, []).cleanupConfirmed === true;
          }
          if (!closed || child !== undefined && !childRetired) return false;
          responses.length = 0;
          responses = child = childRead = childStop = childRetire = childObserve = undefined;
          acquisition = closeBinding = selected = selectedSite = constructor = sequence = signal = stop = primary = undefined;
          provider = fetchPage = decodePage = onError = setupFailure = undefined;
          verifyRead = authorizationFor = chargePage = consumePage = consumePageWire = transportFailure = undefined;
          retired = true; readers.delete(handle);
          return true;
        } finally {cleanupRunning = false;}
      }
      function sync(value) {
        const native = types.isPromise(value);
        const then = native ? undefined : value?.then;
        if (native || typeof then === 'function') {
          // Retain the actual native computation before observing its public
          // then property. A throwing getter cannot acknowledge its stop.
          const pending = native ? value
            : new Promise((resolve, reject) => Reflect.apply(then, value, [resolve, reject]));
          pendingCallbacks.add(pending);
          const settled = () => {
            pendingCallbacks.delete(pending);
            if (stopped) {
              try {cleanup();} catch (cause) {transportFailure = cause; hadTransportFailure = true;}
            }
          };
          if (native) {
            Reflect.apply(Promise.prototype.then, value, [settled, settled]);
            // Preserve the original observation failure after the native join.
            // If joining itself throws, the original remains pending/owned.
            void value.then;
          } else void pending.then(settled, settled);
          fail('InstalledSourcePageCallbackNotSynchronous');
        }
        return value;
      }
      function callProjection(fn, receiver, args) {
        callbackDepth++;
        try {return sync(Reflect.apply(fn, receiver, args));}
        finally {callbackDepth--;}
      }
      const applySynchronousProjection = (fn, receiver, args) => {
        if (callbackDepth === 0 || typeof fn !== 'function' || !Array.isArray(args) || types.isProxy(args)) {
          fail('ForeignInstalledSourceProjection');
        }
        return callProjection(fn, receiver, args);
      };
      if (standard) {
        try {
          provider = callProjection(preparePageReader, undefined, [Object.freeze({resource: options.resource,
            columns: Object.freeze([...options.columns]), requestWire: options.requestWire}), applySynchronousProjection]);
          fetchPage = ownMethod(provider, 'fetchPage'); decodePage = ownMethod(provider, 'decodePage');
          const field = Object.getOwnPropertyDescriptor(provider, 'onError');
          if (field !== undefined) {
            if (!Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail('InstalledSourceReaderMethodUnavailable');
            onError = field.value;
          }
        } catch (cause) {setupFailed = true; setupFailure = cause;}
      }
      const responseCustody = Object.freeze({retain(response) {
        if (!readPending || retired || (standard ? !ArrayBuffer.isView(response?.body)
          : !Buffer.isBuffer(response?.body))) fail('ForeignInstalledSourceResponse');
        responses.push(response); responseCount++; responseBytes += BigInt(response.body.byteLength);
        if (responseCount > maxResponses) fail('InstalledSourceResponseCountLimit');
      }});
      async function readStandard(initialAuthorization, credential) {
        const initial = ownInvocationAuthorization(initialAuthorization);
        if (initial.scope.operation !== operation || selected.operation !== undefined && selected.operation !== operation) {
          fail('ForeignInstalledSourceReaderAuthorization');
        }
        for (let index = 0; index < maxResponses; index++) {
          await verify();
          const described = callProjection(fetchPage, provider, [Object.freeze({pageIndex:index,rowCount,receivedBodyBytes:responseBytes})]);
          const request = described === null || typeof described !== 'object' || types.isProxy(described)
            ? undefined : ownHttpRequest(described);
          const responseHeaders = ownResponseHeaderNames(described?.responseHeaders ?? []);
          if (request === undefined || request.method !== 'GET' || request.body !== undefined) fail('InvalidInstalledSourcePageRequest');
          const authorization = index === 0 ? initial : ownInvocationAuthorization(await Reflect.apply(authorizationFor, selected, [index]));
          if (authorization.scope.operation !== operation || !invocationBindingsMatch(authorization.scope, initial.scope)) {
            fail('ForeignInstalledSourceReaderAuthorization');
          }
          await verify();
          const response = await invokeScopedCredentialOperation({authorization,credential,
            callResource: input => Reflect.apply(callResource, hosted ? selectedSite.site : selectedSite,
              [{...input,currentBeforeSend:verify}]),
            operation,method:request.method,path:request.target,headers:request.headers,responseHeaders,maxResponseBytes,signal});
          responseCustody.retain(response);
          const charge = await Reflect.apply(chargePage, selected, [response.body]);
          await verify();
          const page = callProjection(decodePage, provider, [response,
            Object.freeze({pageIndex:index,rowCount,receivedBodyBytes:responseBytes})]);
          if (page === null || typeof page !== 'object' || typeof page.done !== 'boolean' ||
              Object.hasOwn(page,'rows') === Object.hasOwn(page,'rowsWire')) fail('InvalidInstalledSourceDecodedPage');
          const wire = Object.hasOwn(page,'rowsWire');
          if (wire ? typeof page.rowsWire !== 'string' || consumePageWire === undefined ||
              !Number.isSafeInteger(page.rowCount) || page.rowCount < 0 : !Array.isArray(page.rows)) fail('InvalidInstalledSourceDecodedPage');
          await Reflect.apply(wire ? consumePageWire : consumePage, selected,
            [wire ? page.rowsWire : page.rows,Object.freeze({charge})]);
          rowCount += wire ? page.rowCount : page.rows.length;
          await verify();
          if (page.done) return Object.freeze({pages:responseCount,rowCount});
        }
        fail('InstalledSourceReaderResponseCountLimit');
      }
      let handle;
      handle = Object.freeze({
        async read() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (phase !== 'ready' || retired || stopped) fail('InstalledSourceReaderAlreadyStarted');
          phase = 'reading'; readPending = true;
          try {
            if (setupFailed) throw setupFailure;
            await verify();
            if (hosted) {
              const original = selected.originalAuthorization;
              if (Reflect.apply(purpose, selectedSite, [original]).kind !== 'read') fail('InstalledSourceReaderPurposeUnavailable');
              acquisition = Reflect.apply(bind, selectedSite, [original,Object.freeze({assertCurrent:check,observeCurrent:verify})]);
            }
            const initialAuthorization = await Reflect.apply(authorizationFor, selected, [0]);
            await verify();
            if (!hosted) {
              const initial = ownInvocationAuthorization(initialAuthorization);
              if (initial.scope.operation !== operation) fail('ForeignInstalledSourceReaderAuthorization');
              const original = openHttpsCredentialBinding({...rawCredential,scope:initial.scope,maxSecretBytes});
              acquisition = Object.freeze({credential:Object.freeze({...rawCredential,binding:original}),
                close:() => closeHttpsCredentialBinding(original)});
            }
            closeBinding = ownMethod(acquisition,'close');
            let result;
            if (standard) result = await readStandard(initialAuthorization, acquisition.credential);
            else if (sequence !== undefined) {
              result = await Reflect.apply(sequence, undefined, [Object.freeze({...selected,
                initialAuthorization,credential:acquisition.credential,signal,responseCustody,
                callResource:input => Reflect.apply(callResource,selectedSite.site,[input])})]);
            } else {
              child = Reflect.apply(constructor, undefined, [Object.freeze({...selected,
                initialAuthorization,credential:acquisition.credential,signal,responseCustody,
                callResource:input => Reflect.apply(callResource,selectedSite.site,[input])})]);
              if (typeof child?.then === 'function') {
                child = await child;
                childRetire = ownMethod(child,'retire'); childObserve = ownMethod(child,'observe');
                fail('InstalledSourceReaderConstructorNotSynchronous');
              }
              childRead = ownMethod(child,'read'); childStop = ownMethod(child,'requestStop');
              childRetire = ownMethod(child,'retire'); childObserve = ownMethod(child,'observe');
              result = await Reflect.apply(childRead,child,[]);
            }
            if (Object.hasOwn(result ?? {},'observations')) fail('InstalledSourceReaderResponseEscape');
            await verify(); phase = 'succeeded';
            if (standard) return result;
          } catch (cause) {
            escapedResponseGraph = Array.isArray(cause?.observations) && cause.observations.length > 0;
            phase = 'failed'; primary = cause;
            if (standard && onError !== undefined) throw callProjection(onError,provider,[cause]);
            throw cause;
          } finally {
            readPending = false;
            try {if (stopped) cleanup(); else if (!hosted) closeTransport();}
            catch (cause) {transportFailure ??= cause;hadTransportFailure = true;if (primary === undefined) throw cause;}
          }
        },
        requestStop(reason) {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (retired) return;
          stopped = true; stop.abort(reason);
          if (child !== undefined && childStop !== undefined && !stopIssued) {
            stopIssued = true;
            const pending = Reflect.apply(childStop,child,[reason]);
            if (pending !== undefined) {
              stopPending = true;
              return Promise.resolve(pending).then(() => {stopPending = false;cleanup();}, cause => {
                transportFailure = cause; hadTransportFailure = true;
                stopPending = false; cleanup(); throw cause;
              });
            }
          }
          cleanup();
        },
        retry() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (!stopped) fail('InstalledSourceReaderStopRequired');
          cleanup();
        },
        observe() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          return Object.freeze({phase,stopRequested:stopped,readPending,pendingCallbacks:pendingCallbacks.size,
            responseCount,receivedBodyBytes:responseBytes,transportClosed:acquisition === undefined || bindingClosed,
            transportFailure:hadTransportFailure,cleanupConfirmed:retired});
        },
      });
      // An in-flight pure callback may have reentered factory retirement.
      // Keep its SAME handle in this owner even when no caller can receive it.
      preparedReader = handle;
      readers.add(handle);
      if (retiring || factoryRetired) {
        handle.requestStop();
        fail('InstalledSourceReaderFactoryClosed');
      }
      handed = true;options = undefined;
      return handle;
    } finally {
      if (!handed) {unreturnedStop?.abort();options = undefined;}
      preparationPending = false;preparing--;
    }
  }, retire() {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    retiring = true;
    if (factoryRetired) return true;
    for (const reader of readers) {
      const pending = reader.requestStop();
      if (pending !== undefined) void Promise.resolve(pending).catch(() => {});
    }
    if (preparing !== 0 || readers.size !== 0) return false;
    originalSite = site = sourceSite = rawCredential = createReader = readPages = preparePageReader = assertCurrent = undefined;
    bind = purpose = callResource = referenceCurrent = undefined;
    factoryRetired = true;
    return true;
  }});
  return factory;
}
