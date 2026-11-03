// Same RowRun reader custody for installed Credential Sources. The service
// supplies an original Site/issuer and a selected reader capacity declaration;
// Core still admits it on the original acquisition before prepare/read.
// One installed RowRun reader owner. Standard providers describe/decode pages;
// advanced drivers retain their existing protocol under this same custody.
import {types} from 'node:util';
import {ownHttpRequest, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {ownInvocationAuthorization, invocationBindingsMatch, invocationScopeFields,
  invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';

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
function ownMethod(value, name, optional = false) {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const field = Object.getOwnPropertyDescriptor(value, name);
  if (optional && (field === undefined || Object.hasOwn(field, 'value') && field.value === undefined)) return undefined;
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
    fail('InstalledSourceReaderMethodUnavailable');
  }
  return field.value;
}

export function createInstalledCredentialSourceReader(options) {
  if (options === null || typeof options !== 'object' || Array.isArray(options) || types.isProxy(options)) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const managedSequence = Object.hasOwn(options, 'prepareReadSequence');
  if (['site', 'createReader', 'readPages'].some(name => Object.hasOwn(options, name)) ||
      managedSequence && Object.hasOwn(options, 'preparePageReader')) fail('InvalidInstalledCredentialSourceReader');
  let {capacity, originalSite, operation, maxResponses, maxResponseBytes, maxSecretBytes} = options;
  const requestBound = Object.getOwnPropertyDescriptor(options, 'maxRequestBytes');
  if (requestBound !== undefined && (!Object.hasOwn(requestBound, 'value') || !positive(requestBound.value))) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const maxRequestBytes = requestBound?.value;
  const totalBound = Object.getOwnPropertyDescriptor(options, 'maxTotalResponseBytes');
  if (totalBound !== undefined && (!Object.hasOwn(totalBound, 'value') || !positive(totalBound.value))) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  const maxTotalResponseBytes = totalBound?.value;
  const resourcesField = Object.getOwnPropertyDescriptor(options, 'resourceChildren');
  if (resourcesField !== undefined && (!Object.hasOwn(resourcesField, 'value') ||
      !Array.isArray(resourcesField.value) || types.isProxy(resourcesField.value) ||
      !Object.isFrozen(resourcesField.value) || resourcesField.value.length > maxResponses)) {
    fail('InvalidInstalledSourceResourceChildren');
  }
  let resourceChildren = resourcesField?.value;
  if (resourceChildren !== undefined) {
    if (!managedSequence) fail('InvalidInstalledSourceResourceChildren');
    for (let index=0;index<resourceChildren.length;index++) {
      const field=Object.getOwnPropertyDescriptor(resourceChildren,String(index));
      if (!field || !Object.hasOwn(field,'value') || typeof field.value!=='string' || field.value.length===0) {
        fail('InvalidInstalledSourceResourceChildren');
      }
      for (let prior=0;prior<index;prior++) if (resourceChildren[prior]===field.value) fail('InvalidInstalledSourceResourceChildren');
    }
  }
  if (capacity === undefined || capacity === null || originalSite === undefined || !positive(maxResponses) ||
      !positive(maxResponseBytes) || !managedSequence &&
        (typeof operation !== 'string' || operation.length === 0 || !positive(maxSecretBytes))) {
    fail('InvalidInstalledCredentialSourceReader');
  }
  // The installation selects one processing protocol and captures its methods
  // once. Per-read callbacks below still belong to each original acquisition.
  let prepareProvider = ownMethod(options, managedSequence ? 'prepareReadSequence' : 'preparePageReader');
  let assertCurrent = ownMethod(options, 'assertCurrent');
  options = undefined;
  let sourceSite = originalSite;
  let bind = ownMethod(sourceSite, 'bindRunAcquisition');
  let purpose = ownMethod(sourceSite, 'authorizationPurpose');
  let childCredential = managedSequence ? ownMethod(sourceSite, 'readChildCredential') : undefined;
  let bindResourceChild = resourceChildren?.length ? ownMethod(sourceSite, 'bindReadResourceChild') : undefined;
  let resourceChildCredential = resourceChildren?.length ? ownMethod(sourceSite, 'readResourceChildCredential') : undefined;
  let callResource = ownMethod(sourceSite, 'callResource');
  let referenceCurrent = ownMethod(sourceSite, 'referenceCurrent');
  let factory, preparing = 0, retiring = false, factoryRetired = false;
  const readers = new Set();
  factory = Object.freeze({capacity, prepare(options, retainPreparation, reserveResponseCapacity, responseBorrow) {
    if (this !== factory) fail('ForeignInstalledCredentialSourceReader');
    if (retainPreparation !== undefined && typeof retainPreparation !== 'function') {
      fail('InvalidInstalledSourcePreparationRetention');
    }
    if (reserveResponseCapacity !== undefined && typeof reserveResponseCapacity !== 'function') {
      fail('InvalidInstalledSourceResponseCapacity');
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
      let authorizeReadChild = managedSequence ? ownMethod(options, 'authorizeReadChild') : undefined;
      let chargePage = ownMethod(options, 'chargePage');
      let consumePage = ownMethod(options, 'consumePage', managedSequence);
      let consumeObservation = managedSequence ? ownMethod(options, 'consumeObservation') : undefined;
      let consumePageWire = ownMethod(options, 'consumePageWire', true);
      let consumeProjectedPage = ownMethod(options, 'consumeProjectedPage', true);
      let consumeValues = managedSequence ? ownMethod(options, 'consumeValues', true) : undefined;
      let selected = options, selectedSite = sourceSite;
      let stop = new AbortController(); unreturnedStop = stop;
      const originalSignal = options.signal;
      let signal = originalSignal === undefined ? stop.signal : AbortSignal.any([originalSignal, stop.signal]);
      let phase = 'ready', readPending = false, stopped = false, retired = false, metadataRead = false;
      let escapedResponseGraph = false, callbackDepth = 0;
      let acquisition, closeBinding, retireBinding, bindingClosed = false;
      const resourceBindings = resourceChildren?.length ? [] : undefined;
      let rootPurpose;
      let transportFailure, hadTransportFailure = false, cleanupRunning = false, primary;
      let unconfirmedCharge;
      let responses = [], responseCount = 0, responseBytes = 0n, rowCount = 0;
      let provider, fetchPage, decodePage, runSequence, providerRetire, responseCapacity, providerRetired = false;
      let nativePrepared = false;
      let onError, setupFailure, setupFailed = false;
      const pendingCallbacks = new Set();
      const check = () => {
        if (retired || stopped) fail('InstalledSourceReaderClosed');
        if (Reflect.apply(assertCurrent, undefined, []) !== undefined ||
            Reflect.apply(referenceCurrent, selectedSite, []) !== true) fail('InstalledSourceReaderNotCurrent');
      };
      const verify = async () => {
        signal.throwIfAborted(); check();
        await Reflect.apply(verifyRead, selected, []);
        signal.throwIfAborted(); check();
      };
      function retainAcquisitionMethods() {
        try {
          closeBinding = ownMethod(acquisition, 'close');
          if (Object.getOwnPropertyDescriptor(acquisition, 'retire') !== undefined) {
            retireBinding = ownMethod(acquisition, 'retire');
          }
        } catch (cause) {escapedResponseGraph = true;throw cause;}
      }
      function closeTransport() {
        let childrenClosed = true;
        if (resourceBindings !== undefined) for (const child of resourceBindings) {
          if (!child.closed && child.close !== undefined) {
            child.closed = Reflect.apply(child.close, child.acquisition, []) === 'closed';
          }
          if (!child.closed) childrenClosed = false;
        }
        if (acquisition !== undefined && !bindingClosed) {
          // An invalid returned original cannot supply a cleanup ACK.
          if (closeBinding === undefined) return false;
          bindingClosed = Reflect.apply(closeBinding, acquisition, []) === 'closed';
        }
        return childrenClosed && (acquisition === undefined || bindingClosed);
      }
      function cleanup() {
        if (retired) return true;
        if (cleanupRunning) return false;
        cleanupRunning = true;
        try {
          const closed = closeTransport();
          if (!stopped || readPending || pendingCallbacks.size !== 0 || escapedResponseGraph ||
              unconfirmedCharge !== undefined) return false;
          if (!closed) return false;
          if (providerRetire !== undefined && !providerRetired) {
            providerRetired = callProjection(providerRetire, provider, []) === true;
            if (!providerRetired) return false;
          }
          // Borrowed metadata binding retirement belongs to this SAME reader,
          // after every callback/response duty, not merely its socket stop.
          if (retireBinding !== undefined && sync(Reflect.apply(retireBinding, acquisition, [])) !== true) return false;
          if (resourceBindings !== undefined) for (const child of resourceBindings) {
            if (child.retire !== undefined && sync(Reflect.apply(child.retire, child.acquisition, [])) !== true) return false;
          }
          if (resourceBindings !== undefined) resourceBindings.length = 0;rootPurpose = undefined;
          responses.length = 0;
          responses = undefined;
          acquisition = closeBinding = retireBinding = selected = selectedSite = signal = stop = primary = undefined;
          provider = fetchPage = decodePage = runSequence = providerRetire = responseCapacity = onError = setupFailure = undefined;
          verifyRead = authorizationFor = authorizeReadChild = chargePage = consumeObservation = consumePage = consumePageWire = consumeProjectedPage = consumeValues = reserveResponseCapacity = transportFailure = undefined;
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
      try {
        const prepared = managedSequence ? Object.getOwnPropertyDescriptor(options, 'preparedRead') : undefined;
        if (prepared !== undefined && !Object.hasOwn(prepared, 'value')) fail('InvalidInstalledSourceReadPreparation');
        nativePrepared = prepared !== undefined && prepared.value !== undefined;
        provider = callProjection(prepareProvider, undefined, [Object.freeze({resource: options.resource,
          columns: Object.freeze([...options.columns]), requestWire: options.requestWire,
          ...(!managedSequence || responseBorrow === undefined ? {} : {responseBorrow}),
          ...(nativePrepared ? {preparedRead: sync(prepared.value)} : {}),
          ...(nativePrepared || managedSequence && responseBorrow !== undefined ? {originalAuthorization: options.originalAuthorization} : {})}), applySynchronousProjection]);
        if (managedSequence) {
          runSequence = ownMethod(provider, 'read');
          providerRetire = ownMethod(provider, 'retire');
          responseCapacity = ownMethod(provider, 'responseCapacity', true);
          if (responseCapacity !== undefined && reserveResponseCapacity === undefined) {
            fail('InstalledSourceResponseCapacityUnavailable');
          }
        }
        else {fetchPage = ownMethod(provider, 'fetchPage'); decodePage = ownMethod(provider, 'decodePage');}
        const field = Object.getOwnPropertyDescriptor(provider, 'onError');
        if (field !== undefined) {
          if (!Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail('InstalledSourceReaderMethodUnavailable');
          onError = field.value;
        }
      } catch (cause) {setupFailed = true; setupFailure = cause;}
      const responseCustody = Object.freeze({retain(response) {
        if (!readPending || retired || !ArrayBuffer.isView(response?.body)) fail('ForeignInstalledSourceResponse');
        responses.push(response); responseCount++; responseBytes += BigInt(response.body.byteLength);
        if (responseCount > maxResponses) fail('InstalledSourceResponseCountLimit');
      }});
      async function receiveSourceResponse(invoke) {
        let received, body, response, failure, failed = false;
        const custody = Object.freeze({retain(original) {
          if (this !== custody || received !== undefined) fail('ForeignInstalledSourceResponse');
          received = original; body = original?.body;
          responseCustody.retain(original);
        }});
        try {response = await invoke(custody);}
        catch (cause) {failure = cause;failed = true;}
        // A selected physical port may return its actual body directly; the
        // normal Credential port retains it before its late current fences.
        // Both use this SAME response custody and charge before projection.
        if (received === undefined && !failed) custody.retain(response);
        let charge;
        if (received !== undefined) {
          try {charge = await Reflect.apply(chargePage, selected, [body]);}
          catch (cause) {
            // A thrown charge supplies no nominal disposition. Keep these
            // SAME bytes and failure on this owner; retrying an ambiguous
            // debit or treating physical close as accounting ACK is unsafe.
            unconfirmedCharge = {body, cause};
            if (!failed) throw cause;
            // Preserve the original physical/current refusal. Keep any later
            // accounting failure with this same reader's cleanup diagnostics.
            transportFailure ??= cause;hadTransportFailure = true;
          }
        }
        if (failed) throw failure;
        if (response?.body !== body) fail('ForeignInstalledSourceResponse');
        return {response, charge};
      }
      async function readStandard(initialAuthorization, credential) {
        const initial = ownInvocationAuthorization(initialAuthorization, credential.control);
        if (invocationScopeFields(initial.scope, credential.control).operation !== operation || selected.operation !== undefined && selected.operation !== operation) {
          fail('ForeignInstalledSourceReaderAuthorization');
        }
        for (let index = 0; index < maxResponses; index++) {
          await verify();
          const described = callProjection(fetchPage, provider, [Object.freeze({pageIndex:index,rowCount,receivedBodyBytes:responseBytes})]);
          const request = described === null || typeof described !== 'object' || types.isProxy(described)
            ? undefined : ownHttpRequest(described);
          const responseHeaders = ownResponseHeaderNames(described?.responseHeaders ?? []);
          const boundedPost = request?.method === 'POST' && maxRequestBytes !== undefined &&
            typeof request.body === 'string' && Buffer.byteLength(request.body) <= maxRequestBytes;
          if (request === undefined || !boundedPost &&
              (request.method !== 'GET' || request.body !== undefined)) fail('InvalidInstalledSourcePageRequest');
          const authorization = index === 0 ? initial : ownInvocationAuthorization(await Reflect.apply(authorizationFor, selected, [index]), credential.control);
          if (invocationScopeFields(authorization.scope, credential.control).operation !== operation || !invocationBindingsMatch(authorization.scope, initial.scope, credential.control)) {
            fail('ForeignInstalledSourceReaderAuthorization');
          }
          await verify();
          const {response, charge} = await receiveSourceResponse(responseCustody => invokeScopedCredentialOperation({authorization,credential,
            callResource: input => Reflect.apply(callResource, selectedSite.site,
              [{...input,currentBeforeSend:verify}]),
            operation,method:request.method,path:request.target,headers:request.headers,
            ...(request.body === undefined ? {} : {body:request.body}),
            ...(maxRequestBytes === undefined ? {} : {maxRequestBytes}),
            responseHeaders,maxResponseBytes,responseCustody,signal}));
          const receivedBodyBytes = responseBytes;
          await verify();
          const page = callProjection(decodePage, provider, [response,
            Object.freeze({pageIndex:index,rowCount,receivedBodyBytes})]);
          if (page === null || typeof page !== 'object') fail('InvalidInstalledSourceDecodedPage');
          // Capture the selected DATA once, before external consumption can
          // change the DTO or a later getter observation can select new data.
          // sync keeps any invalid returned computation with this SAME owner.
          const done = sync(page.done);
          const wire = Object.hasOwn(page,'rowsWire');
          const projected = Object.hasOwn(page,'projectedPage');
          if (typeof done !== 'boolean' ||
              Number(Object.hasOwn(page,'rows')) + Number(wire) + Number(projected) !== 1) fail('InvalidInstalledSourceDecodedPage');
          const rows = sync(projected ? page.projectedPage : wire ? page.rowsWire : page.rows);
          const count = wire || projected ? sync(page.rowCount) : Array.isArray(rows) ? sync(rows.length) : undefined;
          if (projected ? rows === null || typeof rows !== 'object' || consumeProjectedPage === undefined ||
              !Number.isSafeInteger(count) || count < 0
            : wire ? typeof rows !== 'string' || consumePageWire === undefined ||
              !Number.isSafeInteger(count) || count < 0 : !Array.isArray(rows)) fail('InvalidInstalledSourceDecodedPage');
          // The recipe retains the admitted prefix plus one offending body.
          // Preserve a decoder's own refusal; its one-response workspace is
          // already funded. Excess cannot deliver rows or reach another send.
          if (maxTotalResponseBytes !== undefined && receivedBodyBytes > BigInt(maxTotalResponseBytes)) {
            fail('InstalledSourceResponseByteLimit');
          }
          const admitted = await Reflect.apply(projected ? consumeProjectedPage : wire ? consumePageWire : consumePage, selected,
            [rows,Object.freeze({charge})]);
          if (projected && admitted !== count) fail('InvalidInstalledSourceDecodedPage');
          rowCount += count;
          await verify();
          if (done) return Object.freeze({pages:responseCount,rowCount});
        }
        fail('InstalledSourceReaderResponseCountLimit');
      }
      async function readManagedSequence(initialAuthorization) {
        let active = true, pending, failure, failed = false, lastCharge;
        const current = () => {
          if (!active || !readPending) fail('InstalledSourceReadChildClosed');
          signal.throwIfAborted();check();
        };
        const perform = task => {
          current();
          if (failed) throw failure;
          if (pending !== undefined) {failed = true;failure = Object.assign(new Error('InstalledSourceReadChildBusy'),
            {code:'InstalledSourceReadChildBusy'});throw failure;}
          const original = task();
          pending = original;pendingCallbacks.add(original);
          const settled = () => {pendingCallbacks.delete(original);pending = undefined;};
          Reflect.apply(Promise.prototype.then, original, [settled, cause => {
            if (!failed) {failed = true;failure = cause;}settled();
          }]);
          return original;
        };
        const observe = async () => {
          if (lastCharge !== undefined) {
            await Reflect.apply(consumeObservation, selected, [lastCharge]);
            lastCharge = undefined;
          }
        };
        const context = Object.freeze({
          // The SAME combined invocation/reader-stop signal already controls
          // physical calls. A domain's pre-request authorization uses it too;
          // exposing this original does not mint another cancellation owner.
          signal,
          project(method, receiver, args) {
            current();
            if (pending !== undefined || typeof method !== 'function' || !Array.isArray(args) || types.isProxy(args)) {
              fail('InstalledSourceReadChildBusy');
            }
            const value = callProjection(method, receiver, args);
            current();
            return value;
          },
          consumeObservation() {
            return perform(async () => {
              if (lastCharge === undefined) fail('InvalidInstalledSourceReadChildObservation');
              await verify();await observe();await verify();
            });
          },
          readChild(options) {
            return perform(async () => {
              const childOperation = Object.getOwnPropertyDescriptor(options ?? {}, 'operation');
              const prepare = ownMethod(options, 'prepare');
              if (!childOperation || !Object.hasOwn(childOperation, 'value') ||
                  typeof childOperation.value !== 'string' || !childOperation.value) fail('InvalidInstalledSourceReadChild');
              const operation = childOperation.value;
              if (responseCount >= maxResponses) fail('InstalledSourceReaderResponseCountLimit');
              await observe();await verify();
              // Deferred cursors/requests are projected only after the previous
              // original response is consumed and this parent's current holds.
              const prepared = callProjection(prepare, options, []);
              const project = ownMethod(prepared, 'project');
              const described = prepared.request;
              if (described === null || typeof described !== 'object' || types.isProxy(described)) fail('InvalidInstalledSourcePageRequest');
              const request = ownHttpRequest(described);
              const responseHeaders = ownResponseHeaderNames(described.responseHeaders ?? []);
              const post = request.method === 'POST' && maxRequestBytes !== undefined &&
                typeof request.body === 'string' && Buffer.byteLength(request.body) <= maxRequestBytes;
              if (!post && (request.method !== 'GET' || request.body !== undefined)) fail('InvalidInstalledSourcePageRequest');
              const occurrence = Object.getOwnPropertyDescriptor(prepared, 'original');
              if (occurrence !== undefined && (!Object.hasOwn(occurrence, 'value') ||
                  occurrence.value === null || typeof occurrence.value !== 'object' || types.isProxy(occurrence.value))) {
                fail('InvalidInstalledSourceReadChildOriginal');
              }
              const retainedResponse = occurrence === undefined ? undefined
                : Object.getOwnPropertyDescriptor(occurrence.value, 'retainRunResponseOriginal');
              if (retainedResponse !== undefined && (!Object.hasOwn(retainedResponse, 'value') ||
                  typeof retainedResponse.value !== 'boolean')) fail('InvalidInstalledSourceReadChildOriginal');
              const originalField = Object.getOwnPropertyDescriptor(prepared, 'originalAuthorization');
              const authorizationField = Object.getOwnPropertyDescriptor(prepared, 'authorization');
              let supplied;
              if (originalField !== undefined || authorizationField !== undefined) {
                if (!Object.hasOwn(originalField ?? {}, 'value') ||
                    !Object.hasOwn(authorizationField ?? {}, 'value')) fail('InvalidInstalledSourceReadChild');
                // Native protocols keep the SAME Site-issued original. This
                // envelope is DATA, never a grant or a second issuance. Invalid
                // asynchronous fields remain with this reader until settled.
                const verifyCurrent = ownMethod(prepared, 'verifyCurrent', true);
                supplied = Object.freeze({originalAuthorization: sync(originalField.value),
                  authorization: sync(authorizationField.value),
                  ...(verifyCurrent === undefined ? {} : {verifyCurrent})});
              }
              // This original is an occurrence key, not permission or another
              // request issuer. Preserve it unchanged across native cursors.
              const issued = await Reflect.apply(authorizeReadChild, selected,
                supplied !== undefined ? [operation,responseCount,occurrence?.value,supplied]
                  : occurrence === undefined ? [operation,responseCount] : [operation,responseCount,occurrence.value]);
              if (supplied !== undefined && (issued?.originalAuthorization !== supplied.originalAuthorization ||
                  issued?.authorization !== supplied.authorization)) fail('ForeignInstalledSourceReadChild');
              const originalAuthorization = issued?.originalAuthorization;
              if (issued?.authorization?.scope !== originalAuthorization?.scope ||
                  issued?.authorization?.grant !== originalAuthorization?.grant) fail('ForeignInstalledSourceReadChild');
              const issuedPurpose = resourceBindings === undefined ? undefined
                : Reflect.apply(purpose, selectedSite, [originalAuthorization]);
              let credential, verifyChild = verify;
              if (issuedPurpose?.kind === 'read' && rootPurpose.kind === 'read' &&
                  issuedPurpose.resource !== rootPurpose.resource) {
                if (bindResourceChild === undefined || !resourceChildren.includes(issuedPurpose.resource) ||
                    supplied?.verifyCurrent === undefined || issued.verifyCurrent !== supplied.verifyCurrent) {
                  fail('ForeignInstalledSourceReadResourceChild');
                }
                let child = resourceBindings.find(value => value.resource === issuedPurpose.resource);
                if (child === undefined) {
                  if (resourceBindings.length >= resourceChildren.length) fail('InstalledSourceResourceChildLimit');
                  const verifyCurrent = supplied.verifyCurrent;
                  const current = Object.freeze({assertCurrent:check,observeCurrent:async () => {
                    await verify();await Reflect.apply(verifyCurrent, undefined, []);await verify();
                  }});
                  const bound = Reflect.apply(bindResourceChild, selectedSite, [acquisition,originalAuthorization,current]);
                  // Retain the actual returned child before capturing any method.
                  child = {resource:issuedPurpose.resource,originalAuthorization,verifyCurrent,
                    acquisition:bound,observeCurrent:current.observeCurrent,close:undefined,retire:undefined,closed:false};
                  resourceBindings.push(child);
                  try {
                    child.close = ownMethod(bound, 'close');child.retire = ownMethod(bound, 'retire', true);
                  } catch (cause) {escapedResponseGraph = true;throw cause;}
                } else if (child.originalAuthorization !== originalAuthorization || child.verifyCurrent !== supplied.verifyCurrent) {
                  fail('ForeignInstalledSourceReadResourceChild');
                }
                credential = Reflect.apply(resourceChildCredential, selectedSite,
                  [acquisition,child.acquisition,originalAuthorization]);
                if (credential !== child.acquisition.credential) fail('ForeignInstalledSourceReadResourceChild');
                verifyChild = child.observeCurrent;
              } else {
                credential = Reflect.apply(childCredential, selectedSite, [acquisition,originalAuthorization]);
                if (credential !== acquisition.credential) fail('ForeignInstalledSourceReadChild');
              }
              const authorization = ownInvocationAuthorization(issued.authorization, credential.control);
              if (authorization.grant !== originalAuthorization.grant ||
                  invocationScopeFields(authorization.scope, credential.control).operation !== operation ||
                  !invocationBindingsMatch(authorization.scope,originalAuthorization.scope, credential.control)) fail('ForeignInstalledSourceReadChild');
              await verifyChild();
              // Preserve the native protocol's existing response-original
              // request while keeping this SAME bound credential's authority.
              const responseCredential = retainedResponse?.value === true
                ? Object.freeze({...credential, retainRunResponseOriginal: true}) : credential;
              const received = await receiveSourceResponse(responseCustody => invokeScopedCredentialOperation({authorization,credential:responseCredential,
                callResource: input => Reflect.apply(callResource,selectedSite.site,[{...input,currentBeforeSend:verifyChild}]),
                operation,method:request.method,path:request.target,headers:request.headers,
                ...(request.body === undefined ? {} : {body:request.body}),
                ...(maxRequestBytes === undefined ? {} : {maxRequestBytes}),
                responseHeaders,maxResponseBytes,responseCustody,signal}));
              const response = received.response;
              lastCharge = received.charge;
              // Retention and the original physical charge precede aggregate
              // refusal. One offending body stays owned; no later child may
              // construct or send after this same failure is latched.
              if (maxTotalResponseBytes !== undefined && responseBytes > BigInt(maxTotalResponseBytes)) {
                fail('InstalledSourceResponseBytesLimit');
              }
              await verifyChild();
              if (responseCapacity !== undefined) {
                const capacity = callProjection(responseCapacity, provider, [response.body.byteLength]);
                callProjection(reserveResponseCapacity, undefined, [capacity]);
                // Same checked Resource current boundary above; do not repeat
                // its external callback merely to inspect these local fences.
                if (!readPending || stopped || retired) fail('InstalledSourceReaderClosed');
                signal.throwIfAborted();
              }
              return callProjection(project,prepared,[response]);
            });
          },
          consumePage(rows) {
            return perform(async () => {
              if (metadataRead) fail('InstalledSourceMetadataRowsUnavailable');
              if (lastCharge === undefined || !Array.isArray(rows)) fail('InvalidInstalledSourceReadChildPage');
              const count = rows.length;
              await verify();await Reflect.apply(consumePage,selected,[rows,Object.freeze({charge:lastCharge})]);
              lastCharge = undefined;rowCount += count;await verify();
            });
          },
          consumePageWire(wire, count) {
            return perform(async () => {
              if (metadataRead) fail('InstalledSourceMetadataRowsUnavailable');
              if (lastCharge === undefined || consumePageWire === undefined || typeof wire !== 'string' ||
                  !Number.isSafeInteger(count) || count < 0) fail('InvalidInstalledSourceReadChildPage');
              await verify();await Reflect.apply(consumePageWire,selected,[wire,Object.freeze({charge:lastCharge})]);
              lastCharge = undefined;rowCount += count;await verify();
            });
          },
          ...(consumeValues === undefined ? {} : {consumeValues(columns, rows) {
            return perform(async () => {
              if (metadataRead) fail('InstalledSourceMetadataRowsUnavailable');
              if (lastCharge === undefined || !Array.isArray(columns) || !Array.isArray(rows) ||
                  types.isProxy(columns) || types.isProxy(rows)) fail('InvalidInstalledSourceReadChildPage');
              const count = rows.length;
              await verify();
              const admitted = await Reflect.apply(consumeValues, selected,
                [columns,rows,Object.freeze({charge:lastCharge})]);
              if (admitted !== count) fail('InvalidInstalledSourceDecodedPage');
              lastCharge = undefined;rowCount += count;await verify();
            });
          }}),
        });
        try {
          let sequenceFailure, sequenceFailed = false;
          try {await Reflect.apply(runSequence,provider,nativePrepared ? [context,initialAuthorization] : [context]);}
          catch (cause) {
            // A provider may turn its awaited child failure into a status or
            // wrapper. Preserve the earlier original already observed here,
            // including thrown undefined. A later failure while joining an
            // unawaited child still cannot replace this sequence's primary.
            sequenceFailure = failed ? failure : cause;sequenceFailed = true;
          }
          if (pending !== undefined) {
            try {await pending;} catch (cause) {if (!sequenceFailed) {sequenceFailure = cause;sequenceFailed = true;}}
            if (!sequenceFailed && !failed) {sequenceFailure = Object.assign(new Error('InstalledSourceReadChildNotJoined'),
              {code:'InstalledSourceReadChildNotJoined'});sequenceFailed = true;}
          }
          if (sequenceFailed) throw sequenceFailure;
          if (failed) throw failure;
          await observe();await verify();
          return Object.freeze({pages:responseCount,rowCount});
        } finally {active = false;}
      }
      // Mode was fixed at installation; bind the existing processing body to
      // this original reader once, not by probing optional methods at read.
      const readSelected = managedSequence ? readManagedSequence : readStandard;
      let handle;
      handle = Object.freeze({
        async read() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (phase !== 'ready' || retired || stopped) fail('InstalledSourceReaderAlreadyStarted');
          phase = 'reading'; readPending = true;
          try {
            if (setupFailed) throw setupFailure;
            await verify();
            const original = selected.originalAuthorization;
            const selectedPurpose = Reflect.apply(purpose, selectedSite, [original]);
            if (resourceBindings !== undefined) rootPurpose = selectedPurpose;
            if (selectedPurpose.kind !== 'read' && selectedPurpose.kind !== 'installation-metadata' ||
                selectedPurpose.kind === 'installation-metadata' && !managedSequence) {
              fail('InstalledSourceReaderPurposeUnavailable');
            }
            metadataRead = selectedPurpose.kind === 'installation-metadata';
            if (managedSequence && !metadataRead && consumePage === undefined && consumeValues === undefined) fail('InstalledSourceReaderMethodUnavailable');
            acquisition = Reflect.apply(bind, selectedSite, [original,Object.freeze({assertCurrent:check,observeCurrent:verify})]);
            retainAcquisitionMethods();
            if (selectedPurpose.kind === 'installation-metadata' &&
                (selectedPurpose.control !== acquisition.credential.control || selectedPurpose.control.kind !== 'installation-metadata')) {
              fail('InstalledSourceReaderPurposeUnavailable');
            }
            const initialAuthorization = await Reflect.apply(authorizationFor, selected, [0]);
            await verify();
            const result = await readSelected(initialAuthorization, acquisition.credential);
            if (Object.hasOwn(result ?? {},'observations')) fail('InstalledSourceReaderResponseEscape');
            await verify(); phase = 'succeeded';
            return result;
          } catch (cause) {
            // A failed original binding-method capture remains unacknowledged.
            // Socket close cannot erase that separate retirement duty.
            escapedResponseGraph ||= Array.isArray(cause?.observations) && cause.observations.length > 0;
            phase = 'failed'; primary = cause;
            if (onError !== undefined) throw callProjection(onError,provider,[cause]);
            throw cause;
          } finally {
            readPending = false;
            try {
              if (stopped) cleanup();
            }
            catch (cause) {
              transportFailure ??= cause;hadTransportFailure = true;
              // The existing failed phase records rejection PRESENCE. Its
              // original value may be undefined; cleanup cannot replace it.
              if (phase !== 'failed') throw cause;
            }
          }
        },
        requestStop(reason) {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (retired) return;
          stopped = true; stop.abort(reason);
          cleanup();
        },
        retry() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          if (!stopped) fail('InstalledSourceReaderStopRequired');
          // Retry only this SAME reader's pending transport/provider/binding
          // retirement. No new read, child or physical send is issued.
          return handle.requestStop(signal?.reason);
        },
        observe() {
          if (this !== handle) fail('ForeignInstalledCredentialSourceReader');
          return Object.freeze({phase,stopRequested:stopped,readPending,pendingCallbacks:pendingCallbacks.size,
            responseCount,receivedBodyBytes:responseBytes,transportClosed:(acquisition === undefined || bindingClosed) && (resourceBindings === undefined || resourceBindings.every(child => child.closed)),
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
    originalSite = sourceSite = prepareProvider = assertCurrent = undefined;
    bind = purpose = childCredential = bindResourceChild = resourceChildCredential = resourceChildren = callResource = referenceCurrent = undefined;
    factoryRetired = true;
    return true;
  }});
  return factory;
}
