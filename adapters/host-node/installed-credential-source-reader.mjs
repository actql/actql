// Same RowRun reader custody for installed Credential Sources. The service
// supplies an original Site/issuer and a selected reader capacity declaration;
// Core still admits it on the original acquisition before prepare/read.
const fail = code => {throw Object.assign(new Error(code), {code});};
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
const ownMethod = (value, name) => {
  const field = Object.getOwnPropertyDescriptor(value ?? {}, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
    fail('InstalledSourceReaderMethodUnavailable');
  }
  return field.value;
};

export function createInstalledCredentialSourceReader({capacity, originalSite,
  createReader, readPages, assertCurrent, maxResponses}) {
  if (capacity === undefined ||
      (createReader === undefined ? typeof readPages !== 'function' :
        typeof createReader !== 'function' || readPages !== undefined) ||
      typeof assertCurrent !== 'function' || !Number.isSafeInteger(maxResponses) ||
      maxResponses < 1 || maxResponses > 2147483647) fail('InvalidInstalledCredentialSourceReader');
  let bind = ownMethod(originalSite, 'bindRunAcquisition');
  let purpose = ownMethod(originalSite, 'authorizationPurpose');
  let callResource = ownMethod(originalSite, 'callResource');
  let referenceCurrent = ownMethod(originalSite, 'referenceCurrent');
  let factory, activeReaders = 0, preparing = 0, retiring = false, factoryRetired = false;
  factory = Object.freeze({capacity, prepare(options) {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    if (retiring || factoryRetired) fail('InstalledSourceReaderFactoryClosed');
    if (activeReaders >= Number.MAX_SAFE_INTEGER || preparing >= Number.MAX_SAFE_INTEGER) {
      fail('InstalledSourceReaderInventoryUnavailable');
    }
    preparing++;
    let handed = false, unreturnedStop;
    try {
      let verifyRead = ownMethod(options, 'verifyRead');
      let authorizationFor = ownMethod(options, 'authorizationFor');
      let selected = options, site = originalSite, constructor = createReader, sequence = readPages;
      let stop = new AbortController();
      unreturnedStop = stop;
      let signal = options.signal === undefined ? stop.signal : AbortSignal.any([options.signal, stop.signal]);
      let phase = 'ready', readPending = false, stopped = false, retired = false;
      let stopPending = false, escapedResponseGraph = false;
      let acquisition, closeBinding, child, childRead, childStop, childRetire;
      let childObserve, stopIssued = false, childRetired = false, bindingClosed = false;
      let transportFailure, hadTransportFailure = false, cleanupRunning = false, primary, responses = [];
      let responseCount = 0, responseBytes = 0n;
      const check = () => {
        if (retired || stopped) fail('InstalledSourceReaderClosed');
        if (Reflect.apply(assertCurrent, undefined, []) !== undefined ||
            Reflect.apply(referenceCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
      };
      const verify = async () => {
        check(); signal.throwIfAborted();
        await Reflect.apply(verifyRead, selected, []);
        check(); signal.throwIfAborted();
      };
      function cleanup() {
        if (retired) return true;
        if (cleanupRunning) return false;
        cleanupRunning = true;
        try {
          if (acquisition !== undefined && !bindingClosed) {
            bindingClosed = Reflect.apply(closeBinding, acquisition, []) === 'closed';
          }
          if (readPending || stopPending || escapedResponseGraph) return false;
          if (child !== undefined && !childRetired) {
            childRetired = Reflect.apply(childRetire, child, []) === true &&
              Reflect.apply(childObserve, child, []).cleanupConfirmed === true;
          }
          if (child !== undefined && !childRetired || acquisition !== undefined && !bindingClosed) return false;
          // Only these private reader-owned originals are cleared. The provider's
          // normal mode never exports raw result/error aliases to another owner.
          responses.length = 0;
          responses = child = childRead = childStop = childRetire = childObserve = undefined;
          acquisition = closeBinding = selected = site = constructor = sequence = signal = stop = primary = undefined;
          verifyRead = authorizationFor = transportFailure = undefined;
          retired = true;
          activeReaders--;
          return true;
        } finally { cleanupRunning = false; }
      }
      const responseCustody = Object.freeze({retain(response) {
        if (!readPending || retired || !Buffer.isBuffer(response?.body)) fail('ForeignInstalledSourceResponse');
        // Keep even the first offending response before refusing. A selected
        // reader stops on this throw; the inventory includes this one overlap.
        responses.push(response); responseCount++; responseBytes += BigInt(response.body.byteLength);
        if (responseCount > maxResponses) fail('InstalledSourceResponseCountLimit');
      }});
      let handle;
      handle = Object.freeze({
        async read() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (phase !== 'ready' || retired || stopped) fail('InstalledSourceReaderAlreadyStarted');
          phase = 'reading'; readPending = true;
          try {
            await verify();
            const authorization = selected.originalAuthorization;
            const admitted = Reflect.apply(purpose, site, [authorization]);
            if (admitted.kind !== 'read') fail('InstalledSourceReaderPurposeUnavailable');
            acquisition = Reflect.apply(bind, site, [authorization,
              Object.freeze({assertCurrent: check, observeCurrent: verify})]);
            closeBinding = ownMethod(acquisition, 'close');
            const initialAuthorization = await Reflect.apply(authorizationFor, selected, [0]);
            await verify();
            let result;
            if (sequence !== undefined) {
              // The existing reader owns this complete joined sequence. A
              // provider needs no second lifecycle handle or cleanup owner.
              result = await Reflect.apply(sequence, undefined, [Object.freeze({...selected,
                initialAuthorization, credential: acquisition.credential, signal, responseCustody,
                callResource: input => Reflect.apply(callResource, site.site, [input])})]);
            } else {
              child = Reflect.apply(constructor, undefined, [Object.freeze({...selected,
                initialAuthorization, credential: acquisition.credential, signal, responseCustody,
                callResource: input => Reflect.apply(callResource, site.site, [input])})]);
              if (typeof child?.then === 'function') {
                // A rejected asynchronous constructor never leaves an unjoined
                // borrow. Its returned child is retained for the same cleanup.
                child = await child;
                childRetire = ownMethod(child, 'retire'); childObserve = ownMethod(child, 'observe');
                fail('InstalledSourceReaderConstructorNotSynchronous');
              }
              childRead = ownMethod(child, 'read'); childStop = ownMethod(child, 'requestStop');
              childRetire = ownMethod(child, 'retire'); childObserve = ownMethod(child, 'observe');
              // Results remain private to this reader. No response or provider
              // Promise graph is returned by the RowRun read callback.
              result = await Reflect.apply(childRead, child, []);
            }
            if (Object.hasOwn(result ?? {}, 'observations')) fail('InstalledSourceReaderResponseEscape');
            await verify(); phase = 'succeeded';
          } catch (cause) {
            escapedResponseGraph = Array.isArray(cause?.observations) && cause.observations.length > 0;
            phase = 'failed'; primary = cause; throw cause;
          }
          finally {
            readPending = false;
            if (stopped) {
              try {cleanup();} catch (cause) {transportFailure ??= cause; hadTransportFailure = true; if (primary === undefined) throw cause;}
            }
          }
        },
        requestStop(reason) {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (retired) return;
          stopped = true; stop.abort(reason);
          if (child !== undefined && childStop !== undefined && !stopIssued) {
            stopIssued = true;
            const stopping = Reflect.apply(childStop, child, [reason]);
            if (stopping !== undefined) {
              stopPending = true;
              return Promise.resolve(stopping).finally(() => {stopPending = false; cleanup();});
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
          return Object.freeze({phase, stopRequested: stopped, readPending,
            responseCount, receivedBodyBytes: responseBytes,
            transportFailure: hadTransportFailure, cleanupConfirmed: retired});
        },
      });
      if (retiring || factoryRetired) fail('InstalledSourceReaderFactoryClosed');
      activeReaders++;
      handed = true;
      options = undefined;
      return handle;
    } finally {
      // Construction is I/O-free and no handle escaped on this branch. Abort
      // its private composite signal before releasing the construction slot.
      if (!handed) unreturnedStop?.abort();
      preparing--;
    }
  }, retire() {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    retiring = true;
    if (factoryRetired) return true;
    if (preparing !== 0 || activeReaders !== 0) return false;
    // Factory-only managed alias retirement, never Site/native/Run ACK.
    originalSite = createReader = readPages = assertCurrent = undefined;
    bind = purpose = callResource = referenceCurrent = undefined;
    factoryRetired = true;
    return true;
  }});
  return factory;
}
