// Gmail list/get sequencing only. Common owns target membership, complete
// message projection and nominal request occurrences. Account, each operation
// grant, original RowRun tickets and physical custody remain independent.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const GMAIL_THREAD_LIST_OPERATION = 'gmail:threads:list';
export const GMAIL_THREAD_GET_OPERATION = 'gmail:threads:get';
const providerNames = ['gmailPrepareThreadRead', 'gmailNextThreadRequest', 'gmailThreadRequestJson',
  'gmailThreadRequestMatches', 'gmailAcceptThreadList', 'gmailAcceptThread',
  'gmailThreadProjectionMatchesRequest', 'gmailThreadReadCompleted', 'gmailCloseThreadRead',
  'gmailThreadRowsWire', 'gmailThreadColumnNames'];
const positiveLimits = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth',
  'pageSize', 'maxPages', 'maxMailboxBytes', 'maxTargetBytes', 'maxIdBytes', 'maxTokenBytes',
  'maxValueNodes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const nonnegativeLimits = ['maxThreads', 'maxMessages', 'maxLabels', 'maxHeaders',
  'maxHeaderUnits', 'maxCommentDepth', 'maxValueTextBytes'];
const fail = code => {throw Object.assign(new Error(code), {code});};
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const component = value => encodeURIComponent(value).replace(/[!'()*]/gu, char =>
  `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
const readers = new WeakMap();

export class GmailThreadReadFailure extends Error {
  constructor(cause, observations, exchanges) {
    super('GmailThreadReadFailed', {cause});
    this.code = 'GmailThreadReadFailed';
    Object.defineProperties(this, {
      observations: {value: Object.freeze(observations.slice())},
      exchanges: {value: Object.freeze(exchanges.map(value => Object.freeze({...value})))},
    });
  }
}

function prepareRead(options) {
  const {moon, mailbox, names, initialAuthorization, credential, limits, signal} = options;
  const provider = Object.freeze(Object.fromEntries(providerNames.map(name => {
    const method = moon?.[name];
    return [name, typeof method === 'function' ? (...args) => Reflect.apply(method, moon, args) : undefined];
  })));
  const callbacks = {};
  for (const name of ['authorizationFor', 'current', 'chargeResponse', 'consumeObservation', 'consumePage']) {
    const method = options[name];
    if (typeof method !== 'function') fail('InvalidGmailThreadRead');
    callbacks[name] = (...args) => Reflect.apply(method, options, args);
  }
  const callResource = options.callResource ?? callHttpsCredentialResource;
  if (typeof callResource !== 'function') fail('InvalidGmailThreadRead');
  callbacks.callResource = (...args) => Reflect.apply(callResource, options, args);
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits, callbacks});
  const bound = context.limits;
  if (providerNames.some(name => provider[name] === undefined) ||
      !positiveLimits.every(name => integer(bound[name]) && bound[name] > 0) ||
      !nonnegativeLimits.every(name => integer(bound[name])) || bound.pageSize > 500 ||
      bound.maxPages > 2147483647 - bound.maxThreads ||
      !context.credential.binding || typeof context.credential.binding !== 'object' ||
      typeof mailbox !== 'string' || mailbox.length === 0 || !mailbox.isWellFormed() ||
      !mailbox.includes('@') || /[\s\u0000-\u001f\u007f]/u.test(mailbox) ||
      mailbox.length > bound.maxMailboxBytes || Buffer.byteLength(mailbox) > bound.maxMailboxBytes ||
      !Array.isArray(names)) fail('InvalidGmailThreadRead');
  if (context.scope.operation !== GMAIL_THREAD_LIST_OPERATION) fail('ForeignGmailThreadOperation');
  const columns = Object.freeze(provider.gmailThreadColumnNames().slice());
  const selected = Object.freeze(names.slice());
  if (selected.length > columns.length || new Set(selected).size !== selected.length ||
      selected.some(name => typeof name !== 'string' || !columns.includes(name))) fail('InvalidGmailThreadRead');
  // The original RowRun admits the complete declared row (including key
  // evidence). Query projection does not remove Source validation inputs.
  return Object.freeze({provider, context, mailbox, names: columns, signal,
    basePath: `/gmail/v1/users/${component(mailbox)}/threads`});
}

async function executeRead(prepared, received) {
  const {provider, context, mailbox, names, signal, basePath} = prepared;
  const bound = context.limits, observations = [], exchanges = [];
  let control, totalBytes = 0, rowCount = 0, pageCount = 0;
  const verify = async operation => {
    signal.throwIfAborted();
    await context.callbacks.current(operation);
    signal.throwIfAborted();
  };
  try {
    await verify(GMAIL_THREAD_LIST_OPERATION);
    control = checked(provider.gmailPrepareThreadRead(mailbox, bound.maxResponseBytes,
      bound.maxNodes, bound.maxDepth, bound.pageSize, bound.maxIdBytes, bound.maxTokenBytes,
      bound.maxMessages, bound.maxLabels, bound.maxHeaders, bound.maxHeaderUnits,
      bound.maxCommentDepth, bound.maxValueNodes, bound.maxValueTextBytes,
      bound.maxPages, bound.maxThreads));
    // Every transition follows the same original consumer's successful charge
    // consumption and a fresh current fence. No later ticket proves the prefix.
    for (let index = 0; index <= bound.maxPages + bound.maxThreads; index++) {
      await verify(GMAIL_THREAD_LIST_OPERATION);
      const next = checked(provider.gmailNextThreadRequest(control));
      if (next.length === 0) {
        if (!provider.gmailThreadReadCompleted(control)) fail('IncompleteGmailThreadRead');
        return Object.freeze({pages: pageCount, rowCount, observations: Object.freeze(observations.slice())});
      }
      if (next.length !== 1) fail('ForeignGmailThreadRequest');
      const pending = next[0];
      if (!provider.gmailThreadRequestMatches(control, pending)) fail('ForeignGmailThreadRequest');
      const original = JSON.parse(provider.gmailThreadRequestJson(pending));
      if (original.mailbox !== mailbox || original.ordinal !== index) fail('ForeignGmailThreadRequest');
      const operation = original.isList ? GMAIL_THREAD_LIST_OPERATION : GMAIL_THREAD_GET_OPERATION;
      const path = original.isList ? basePath : `${basePath}/${component(original.threadId)}`;
      const query = original.isList
        ? [['maxResults', String(bound.pageSize)], ['fields', 'threads(id,snippet,historyId),nextPageToken,resultSizeEstimate']]
        : [['format', 'metadata'], ['metadataHeaders', 'Subject'], ['metadataHeaders', 'Date'],
          ['fields', 'id,messages(id,threadId,labelIds,internalDate,payload(headers(name,value)))']];
      if (original.isList && original.pageToken !== null) query.push(['pageToken', original.pageToken]);
      if (Buffer.byteLength(requestTarget(path, query)) > bound.maxTargetBytes) fail('GmailThreadTargetLimit');
      await verify(operation);
      const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
        Object.freeze({operation, index, originalRequest: pending})));
      if (authorization.scope.operation !== operation ||
          !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignGmailThreadAuthorization');
      await verify(operation);
      const exchange = {originalRequest: pending, authorization, operation, path,
        query: Object.freeze(query.map(pair => Object.freeze(pair.slice())))};
      exchanges.push(exchange);
      const response = await invokeScopedCredentialOperation({authorization, credential: context.credential,
        callResource: options => context.callbacks.callResource({...options, currentBeforeSend: () => verify(operation)}),
        operation, method: 'GET', path, query: exchange.query, headers: [['accept', 'application/json']],
        responseHeaders: [], maxResponseBytes: bound.maxResponseBytes, signal});
      exchange.response = response;
      observations.push(response);
      received(response);
      const charge = await context.callbacks.chargeResponse(response.body);
      exchange.charge = charge;
      await verify(operation);
      if (response.body.byteLength > bound.maxTotalResponseBytes - totalBytes) fail('GmailThreadResponseLimit');
      totalBytes += response.body.byteLength;
      if (!response.accepted || response.statusCode !== 200) fail('GmailThreadReadRejected');
      if (original.isList) {
        exchange.page = checked(provider.gmailAcceptThreadList(control, pending, response.body));
        pageCount++;
        await context.callbacks.consumeObservation(charge);
      } else {
        const thread = checked(provider.gmailAcceptThread(control, pending, response.body));
        exchange.thread = thread;
        if (!provider.gmailThreadProjectionMatchesRequest(thread, pending)) fail('ForeignGmailThreadProjection');
        const rows = JSON.parse(checked(provider.gmailThreadRowsWire(thread, names,
          bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
        await context.callbacks.consumePage(rows, Object.freeze({charge, originalRequest: pending, originalThread: thread}));
        rowCount++;
      }
      await verify(operation);
    }
    fail('GmailThreadRequestLimit');
  } catch (cause) {
    throw new GmailThreadReadFailure(cause, observations, exchanges);
  } finally {
    if (control !== undefined) provider.gmailCloseThreadRead(control);
  }
}

export function createGmailThreadReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal, stop.signal]);
  const state = {prepared: Object.freeze({...original, signal}), stop, phase: 'ready',
    receivedResponses: 0, receivedBodyBytes: 0n};
  const own = receiver => {
    if (receiver !== handle || readers.get(receiver) !== state) fail('ForeignGmailThreadReader');
    return state;
  };
  const handle = Object.freeze({
    async read() {
      const state = own(this);
      if (state.phase !== 'ready') fail('GmailThreadReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared, response => {
          state.receivedResponses++;
          state.receivedBodyBytes += BigInt(response.body.byteLength);
        });
        state.phase = 'succeeded';
        return result;
      } catch (cause) {state.phase = 'failed'; throw cause;}
    },
    requestStop(reason) {own(this).stop.abort(reason);},
    observe() {
      const state = own(this);
      return Object.freeze({phase: state.phase, stopRequested: signal.aborted,
        receivedResponses: state.receivedResponses, receivedBodyBytes: state.receivedBodyBytes,
        observationCustody: state.receivedResponses === 0 ? 'not-observed' : 'retained', cleanupConfirmed: false});
    },
  });
  readers.set(handle, state);
  return handle;
}

export async function readGmailThreads(options) {
  return createGmailThreadReader(options).read();
}
