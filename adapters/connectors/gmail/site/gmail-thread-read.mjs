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

// One list/get protocol for both the explicit Credential caller and the
// installed managed reader. Only the original consumer supplies IO/current,
// response custody and charge consumption. Provider callbacks stay synchronous
// under that consumer's invalid-async borrowing fence.
export function prepareGmailThreadReadSequence({moon, mailbox, names, limits}, applySynchronousProjection) {
  if (typeof applySynchronousProjection !== 'function' || !Array.isArray(names)) fail('InvalidGmailThreadRead');
  let provider = Object.freeze(Object.fromEntries(providerNames.map(name => {
    const field = Object.getOwnPropertyDescriptor(moon ?? {}, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail('InvalidGmailThreadRead');
    return [name, (...args) => applySynchronousProjection(field.value, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  if (!positiveLimits.every(name => integer(bound[name]) && bound[name] > 0) ||
      !nonnegativeLimits.every(name => integer(bound[name])) || bound.pageSize > 500 ||
      bound.maxPages > 2147483647 - bound.maxThreads || typeof mailbox !== 'string' ||
      mailbox.length === 0 || !mailbox.isWellFormed() || !mailbox.includes('@') ||
      /[\s\u0000-\u001f\u007f]/u.test(mailbox) || Buffer.byteLength(mailbox) > bound.maxMailboxBytes) {
    fail('InvalidGmailThreadRead');
  }
  const basePath = `/gmail/v1/users/${component(mailbox)}/threads`;
  let started = false, pending = false, retired = false, control;
  return Object.freeze({async read(context) {
    if (started || retired) fail('GmailThreadReaderAlreadyStarted');
    started = true;pending = true;
    try {
      context.project(() => {
        const columns = provider.gmailThreadColumnNames();
        if (new Set(names).size !== names.length || names.some(name => !columns.includes(name))) fail('InvalidGmailThreadRead');
        // Complete declared rows retain key evidence, independently of SELECT.
        names = Object.freeze(columns.slice());
        control = checked(provider.gmailPrepareThreadRead(mailbox, bound.maxResponseBytes,
          bound.maxNodes, bound.maxDepth, bound.pageSize, bound.maxIdBytes, bound.maxTokenBytes,
          bound.maxMessages, bound.maxLabels, bound.maxHeaders, bound.maxHeaderUnits,
          bound.maxCommentDepth, bound.maxValueNodes, bound.maxValueTextBytes, bound.maxPages, bound.maxThreads));
      }, undefined, []);
      for (let index = 0; index <= bound.maxPages + bound.maxThreads; index++) {
        const selected = context.project(() => {
          const next = checked(provider.gmailNextThreadRequest(control));
          if (next.length === 0) {
            if (!provider.gmailThreadReadCompleted(control)) fail('IncompleteGmailThreadRead');
            return undefined;
          }
          if (next.length !== 1 || !provider.gmailThreadRequestMatches(control, next[0])) fail('ForeignGmailThreadRequest');
          const original = next[0], fields = JSON.parse(provider.gmailThreadRequestJson(original));
          if (fields.mailbox !== mailbox || fields.ordinal !== index) fail('ForeignGmailThreadRequest');
          return {original, fields};
        }, undefined, []);
        if (selected === undefined) return;
        const {original, fields} = selected;
        const operation = fields.isList ? GMAIL_THREAD_LIST_OPERATION : GMAIL_THREAD_GET_OPERATION;
        const value = await context.readChild({operation, prepare() {
          const path = fields.isList ? basePath : `${basePath}/${component(fields.threadId)}`;
          const query = fields.isList
            ? [['maxResults', String(bound.pageSize)], ['fields', 'threads(id,snippet,historyId),nextPageToken,resultSizeEstimate']]
            : [['format', 'metadata'], ['metadataHeaders', 'Subject'], ['metadataHeaders', 'Date'],
              ['fields', 'id,messages(id,threadId,labelIds,internalDate,payload(headers(name,value)))']];
          if (fields.isList && fields.pageToken !== null) query.push(['pageToken', fields.pageToken]);
          if (Buffer.byteLength(requestTarget(path, query)) > bound.maxTargetBytes) fail('GmailThreadTargetLimit');
          return {original, request: {method:'GET', path, query, headers:[['accept','application/json']], responseHeaders:[]},
            project(response) {
              if (!provider.gmailThreadRequestMatches(control, original)) fail('ForeignGmailThreadRequest');
              if (!response.accepted || response.statusCode !== 200) fail('GmailThreadReadRejected');
              if (fields.isList) return {page: checked(provider.gmailAcceptThreadList(control, original, response.body))};
              const thread = checked(provider.gmailAcceptThread(control, original, response.body));
              if (!provider.gmailThreadProjectionMatchesRequest(thread, original)) fail('ForeignGmailThreadProjection');
              const rows = JSON.parse(checked(provider.gmailThreadRowsWire(thread, names,
                bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
              return {thread, rows};
            }};
        }});
        if (fields.isList) await context.consumeObservation();
        else await context.consumePage(value.rows);
        // Consume each actual charge before the next nominal request, not
        // merely before sending it. No retry or early next occurs.
      }
      fail('GmailThreadRequestLimit');
    } finally {pending = false;}
  },retire() {
    if (pending) return false;
    if (retired) return true;
    if (control !== undefined) provider.gmailCloseThreadRead(control);
    control = provider = names = undefined;retired = true;
    return true;
  }});
}

async function executeRead(prepared, received, retainControl) {
  const {provider, context, mailbox, names, signal} = prepared;
  const bound = context.limits, observations = [], exchanges = [];
  let totalBytes = 0, rowCount = 0, pageCount = 0, lastCharge;
  const verify = async operation => {
    signal.throwIfAborted();
    await context.callbacks.current(operation);
    signal.throwIfAborted();
  };
  const originalPrepare = provider.gmailPrepareThreadRead;
  const selectedProvider = Object.freeze({...provider, gmailPrepareThreadRead(...args) {
    const value = originalPrepare(...args);
    retainControl(checked(value));
    return value;
  }});
  const sequence = prepareGmailThreadReadSequence({moon:selectedProvider, mailbox, names, limits:bound},
    (method, receiver, args) => Reflect.apply(method, receiver, args));
  try {
    await verify(GMAIL_THREAD_LIST_OPERATION);
    await sequence.read({project:(method,receiver,args) => Reflect.apply(method,receiver,args),
      async readChild(input) {
        if (lastCharge !== undefined) {
          await context.callbacks.consumeObservation(lastCharge);lastCharge = undefined;
        }
        await verify(input.operation);
        const selected = input.prepare(), originalRequest = selected.original;
        const fields = JSON.parse(provider.gmailThreadRequestJson(originalRequest));
        const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
          Object.freeze({operation:input.operation,index:fields.ordinal,originalRequest})));
        if (authorization.scope.operation !== input.operation ||
            !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignGmailThreadAuthorization');
        await verify(input.operation);
        const {path,query} = selected.request;
        const exchange = {originalRequest,authorization,operation:input.operation,path,
          query:Object.freeze(query.map(pair=>Object.freeze(pair.slice())))};
        exchanges.push(exchange);
        const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
          callResource:options=>context.callbacks.callResource({...options,currentBeforeSend:()=>verify(input.operation)}),
          operation:input.operation,...selected.request,maxResponseBytes:bound.maxResponseBytes,signal});
        exchange.response=response;observations.push(response);received(response);
        lastCharge=await context.callbacks.chargeResponse(response.body);exchange.charge=lastCharge;
        await verify(input.operation);
        if(response.body.byteLength>bound.maxTotalResponseBytes-totalBytes)fail('GmailThreadResponseLimit');
        totalBytes+=response.body.byteLength;
        const projected=selected.project(response);Object.assign(exchange,projected);
        if(fields.isList)pageCount++;
        await verify(input.operation);return projected;
      },async consumeObservation() {
        await context.callbacks.consumeObservation(lastCharge);lastCharge=undefined;
        await verify(GMAIL_THREAD_LIST_OPERATION);
      },async consumePage(rows) {
        const exchange=exchanges[exchanges.length-1];
        await context.callbacks.consumePage(rows,Object.freeze({charge:lastCharge,
          originalRequest:exchange.originalRequest,originalThread:exchange.thread}));
        lastCharge=undefined;rowCount++;await verify(exchange.operation);
      }});
    return Object.freeze({pages:pageCount,rowCount,observations:Object.freeze(observations.slice())});
  } catch(cause) {throw new GmailThreadReadFailure(cause,observations,exchanges);}
  finally {sequence.retire();}
}

export function createGmailThreadReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal, stop.signal]);
  const state = {prepared: Object.freeze({...original, signal}), stop, phase: 'ready',
    receivedResponses: 0, receivedBodyBytes: 0n, control: undefined};
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
        }, control => {state.control = control;});
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

// Private installed caller membership assertion only. It exposes no control,
// issues no grant and substitutes neither current Account nor response custody.
export function assertOriginalGmailThreadRequest(reader, request) {
  const state = readers.get(reader);
  if (state === undefined || state.phase !== 'reading' || state.control === undefined ||
      state.prepared.provider.gmailThreadRequestMatches(state.control, request) !== true) {
    fail('ForeignGmailThreadReaderRequest');
  }
}

export async function readGmailThreads(options) {
  return createGmailThreadReader(options).read();
}
