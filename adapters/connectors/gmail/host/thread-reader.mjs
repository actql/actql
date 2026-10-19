// Trusted installed RowRun caller only. Existing Host supplies the original
// acquisition/current callbacks and complete transfer/retained capacity; this
// Connector binds the same pending get to the Site's separate operation use.
import {types} from 'node:util';
import {ownInvocationAuthorization, invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createGmailThreadReader, assertOriginalGmailThreadRequest,
  GMAIL_THREAD_LIST_OPERATION as listOperation, GMAIL_THREAD_GET_OPERATION as getOperation} from '../site/gmail-thread-read.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed();
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const providerNames = ['gmailPrepareThreadRead', 'gmailNextThreadRequest', 'gmailThreadRequestJson',
  'gmailThreadRequestMatches', 'gmailAcceptThreadList', 'gmailAcceptThread',
  'gmailThreadProjectionMatchesRequest', 'gmailThreadReadCompleted', 'gmailCloseThreadRead',
  'gmailThreadRowsWire', 'gmailThreadColumnNames'];
const positiveLimits = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth',
  'pageSize', 'maxPages', 'maxMailboxBytes', 'maxTargetBytes', 'maxIdBytes', 'maxTokenBytes',
  'maxValueNodes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const nonnegativeLimits = ['maxThreads', 'maxMessages', 'maxLabels', 'maxHeaders',
  'maxHeaderUnits', 'maxCommentDepth', 'maxValueTextBytes'];
function data(value, name) {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) fail('InvalidGmailThreadReaderFactory');
  const property = Object.getOwnPropertyDescriptor(value, name);
  if (!property || !Object.hasOwn(property, 'value')) fail('InvalidGmailThreadReaderFactory');
  return property.value;
}
function methods(value, names) {
  return Object.freeze(Object.fromEntries(names.map(name => {
    const method = data(value, name);
    if (typeof method !== 'function') fail('InvalidGmailThreadReaderFactory');
    return [name, method];
  })));
}

// Shared by the trusted installed selector and the original reader factory.
// These bounds constrain work; they do not supply retained/workspace capacity.
export function checkGmailThreadReaderLimits(limits) {
  const bounded = Object.freeze({...limits});
  if (!positiveLimits.every(name => integer(bounded[name]) && bounded[name] > 0) ||
      !nonnegativeLimits.every(name => integer(bounded[name])) || bounded.pageSize > 500 ||
      bounded.maxPages > 2147483647 - bounded.maxThreads) fail('InvalidGmailThreadReaderFactory');
  return bounded;
}

export function createGmailThreadReaderFactory({moon, site, capacity, mailbox, limits, maxSecretBytes}) {
  if (capacity === undefined || capacity === null) fail('GmailReaderCapacityUnavailable');
  if (!text(mailbox) || !integer(maxSecretBytes) || maxSecretBytes === 0) fail('InvalidGmailThreadReaderFactory');
  const bounded = checkGmailThreadReaderLimits(limits);
  if (!mailbox.includes('@') ||
      /[\s\u0000-\u001f\u007f]/u.test(mailbox) || mailbox.length > bounded.maxMailboxBytes ||
      Buffer.byteLength(mailbox) > bounded.maxMailboxBytes) fail('InvalidGmailThreadReaderFactory');
  const credential = Object.freeze({...data(site, 'credential')}), sitePorts = methods(site, ['issueReadGrant', 'callResource']);
  const providerPorts = methods(moon, providerNames);
  const provider = Object.freeze(Object.fromEntries(providerNames.map(name =>
    [name, (...args) => Reflect.apply(providerPorts[name], moon, args)])));
  const requestJson = request => provider.gmailThreadRequestJson(request);
  const preparations = new WeakSet();
  const factory = Object.freeze({capacity, prepare(options) {
    if (this !== factory) fail('ForeignGmailThreadReaderFactory');
    const owner = data(options, 'rowRun'), acquisition = data(owner, 'acquisition');
    if (!acquisition || typeof acquisition !== 'object' || preparations.has(acquisition)) fail('GmailThreadReaderAlreadyPrepared');
    if (data(options, 'resource') !== 'threads' || data(options, 'operation') !== listOperation) fail('ForeignInstalledGmailThreadReader');
    const run = data(owner, 'run'), requestId = data(owner, 'requestId'),
      runInvocationCid = data(owner, 'runInvocationCid'), dispatchRequestCid = data(owner, 'dispatchRequestCid');
    if (!run || !text(requestId) || !text(runInvocationCid) || !text(dispatchRequestCid)) fail('InvalidGmailThreadReaderFactory');
    const callbacks = methods(options, ['verifyRead', 'authorizationFor', 'chargePage', 'consumeObservation', 'consumePage']);
    const invoke = (name, ...args) => Reflect.apply(callbacks[name], options, args);
    const originalSignal = data(options, 'signal'), stop = new AbortController();
    const signal = originalSignal === undefined ? stop.signal : AbortSignal.any([originalSignal, stop.signal]);
    const columns = data(options, 'columns');
    if (!Array.isArray(columns)) fail('InvalidGmailThreadReaderFactory');
    const names = Object.freeze(columns.slice());
    preparations.add(acquisition);
    const gets = new WeakSet();
    let phase = 'ready', child, initial, getAuthorization, getCount = 0, binding,
      transportClosed = false, originalFailure, transportFailure;
    const sameOwner = () => {
      if (data(options, 'rowRun') !== owner || data(owner, 'acquisition') !== acquisition ||
          data(owner, 'run') !== run || data(owner, 'requestId') !== requestId ||
          data(owner, 'runInvocationCid') !== runInvocationCid ||
          data(owner, 'dispatchRequestCid') !== dispatchRequestCid) fail('ForeignInstalledGmailThreadRun');
    };
    const verify = async operation => {
      if (operation !== listOperation && operation !== getOperation) fail('ForeignInstalledGmailThreadOperation');
      signal.throwIfAborted();
      sameOwner();
      const decision = await invoke('verifyRead');
      signal.throwIfAborted();
      sameOwner();
      return decision;
    };
    const closeTransport = () => {
      if (binding !== undefined && !transportClosed) {
        try {transportClosed = closeHttpsCredentialBinding(binding) === 'closed';}
        catch (cause) {transportFailure ??= cause; throw cause;}
      }
    };
    const authorizationFor = async input => {
      assertOriginalGmailThreadRequest(child, input.originalRequest);
      const selected = JSON.parse(requestJson(input.originalRequest));
      if (selected.mailbox !== mailbox || selected.ordinal !== input.index ||
          !integer(input.index) || input.operation !== (selected.isList ? listOperation : getOperation)) {
        fail('ForeignInstalledGmailThreadRequest');
      }
      if (selected.isList) return input.index === 0 ? initial : invoke('authorizationFor', input.index);
      if (gets.has(input.originalRequest) || getCount >= bounded.maxThreads) fail('GmailThreadGetAlreadyPrepared');
      // Retain the exact pending occurrence before the Account await. No equal
      // thread ID or copied request can cause a second grant/use preparation.
      gets.add(input.originalRequest);
      const ordinal = getCount++;
      const decision = await verify(getOperation);
      assertOriginalGmailThreadRequest(child, input.originalRequest);
      if (getAuthorization === undefined) {
        const grant = Reflect.apply(sitePorts.issueReadGrant, site, [{operation: getOperation,
          decision, resource: 'threads', runInvocationCid, dispatchRequestCid, maxUses: bounded.maxThreads}]);
        getAuthorization = ownInvocationAuthorization({...grant, useId: requestId + '-thread-get-' + ordinal});
        if (getAuthorization.scope.operation !== getOperation ||
            !invocationBindingsMatch(getAuthorization.scope, initial.scope)) fail('ForeignInstalledGmailThreadGrant');
      }
      await verify(getOperation);
      assertOriginalGmailThreadRequest(child, input.originalRequest);
      return Object.freeze({...getAuthorization, useId: requestId + '-thread-get-' + ordinal});
    };
    const handle = Object.freeze({
      async read() {
        if (this !== handle) fail('ForeignInstalledGmailThreadReader');
        if (phase !== 'ready') fail('InstalledGmailThreadReaderAlreadyStarted');
        phase = 'reading';
        try {
          await verify(listOperation);
          initial = ownInvocationAuthorization(await invoke('authorizationFor', 0));
          if (initial.scope.operation !== listOperation || initial.scope.runInvocationCid !== runInvocationCid ||
              initial.scope.dispatchRequestCid !== dispatchRequestCid) fail('ForeignInstalledGmailThreadRun');
          await verify(listOperation);
          binding = openHttpsCredentialBinding({...credential, scope: initial.scope, maxSecretBytes});
          child = createGmailThreadReader({moon: provider, mailbox, names, limits: bounded,
            initialAuthorization: initial, credential: {...credential, binding}, authorizationFor,
            current: verify, chargeResponse: body => invoke('chargePage', body),
            consumeObservation: charge => invoke('consumeObservation', charge),
            consumePage: (rows, ticket) => invoke('consumePage', rows, ticket),
            callResource: options => Reflect.apply(sitePorts.callResource, site, [options]), signal});
          const result = await child.read();
          phase = 'succeeded';return result;
        } catch (cause) {phase = 'failed';originalFailure = cause;throw cause;}
        finally {
          try {closeTransport();} catch (cause) {
            phase = 'failed';if (originalFailure === undefined) {originalFailure = cause;throw cause;}
          }
        }
      },
      requestStop(reason) {
        if (this !== handle) fail('ForeignInstalledGmailThreadReader');
        stop.abort(reason);child?.requestStop(reason);closeTransport();
      },
      observe() {
        if (this !== handle) fail('ForeignInstalledGmailThreadReader');
        return Object.freeze({phase, transportClosed, transportFailure: transportFailure !== undefined,
          child: child?.observe(), cleanupConfirmed: false});
      },
    });
    return handle;
  }});
  return factory;
}
