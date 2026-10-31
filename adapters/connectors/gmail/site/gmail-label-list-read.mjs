// Gmail sequencing only: the compiled Catalog owns row meaning and schema;
// existing Account, Credential, RowRun and physical custody owners are separate.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const GMAIL_LABEL_LIST_OPERATION = 'gmail:labels:list';
const readers = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['gmailProjectLabelList', 'gmailLabelListRowsWire',
  'gmailLabelListMetadataJson', 'gmailLabelListColumnNames'];
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows',
  'maxMailboxBytes', 'maxTargetBytes', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const query = Object.freeze([Object.freeze(['fields', 'labels(id,name,type)'])]);

export class GmailLabelListReadFailure extends Error {
  constructor(cause, observations) {
    super('GmailLabelListReadFailed', {cause});
    this.code = 'GmailLabelListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// Both the installed shared reader and the original explicit physical reader
// consume this SAME request and Catalog projection. No transport or grant is
// available here; applySynchronousProjection belongs to the retaining caller.
export function prepareGmailLabelListPages({moon, mailbox, names, limits}, applySynchronousProjection) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      !limits || typeof limits !== 'object' || typeof applySynchronousProjection !== 'function') {
    fail('InvalidGmailLabelListRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidGmailLabelListRead');
    return [name, (...args) => applySynchronousProjection(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  if (!limitFields.every(name => positive(bound[name])) ||
      typeof mailbox !== 'string' || mailbox.length === 0 || !mailbox.isWellFormed() ||
      !mailbox.includes('@') || /[\s\u0000-\u001f\u007f]/u.test(mailbox) ||
      Buffer.byteLength(mailbox) > bound.maxMailboxBytes) fail('InvalidGmailLabelListRead');
  const selected = Object.freeze(provider.gmailLabelListColumnNames().slice());
  if (names.some(name => !selected.includes(name))) fail('InvalidGmailLabelListRead');
  // One original explicit mailbox component, never a default `me` or a
  // credential-derived identity. This endpoint has exactly one complete page.
  const component = encodeURIComponent(mailbox).replace(/[!'()*]/gu, value =>
    `%${value.charCodeAt(0).toString(16).toUpperCase()}`);
  const path = `/gmail/v1/users/${component}/labels`;
  if (Buffer.byteLength(requestTarget(path, query)) > bound.maxTargetBytes) fail('GmailLabelListTargetLimit');
  return Object.freeze({
    fetchPage({pageIndex}) {
      if (pageIndex !== 0) fail('GmailLabelListReadAlreadyCompleted');
      return {method: 'GET', path, query, headers: [['accept', 'application/json']], responseHeaders: []};
    },
    decodePage(response) {
      if (!response.accepted || response.statusCode !== 200) fail('GmailLabelListReadRejected');
      const page = checked(provider.gmailProjectLabelList(response.body, bound.maxResponseBytes,
        bound.maxNodes, bound.maxDepth, bound.maxRows, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.gmailLabelListMetadataJson(page));
      const rows = JSON.parse(checked(provider.gmailLabelListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      return {rows, rowCount: metadata.rowCount, done: true};
    },
    onError(cause) {return new GmailLabelListReadFailure(cause, []);},
  });
}

function prepareRead({moon, mailbox, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumePage, signal,
  callResource = callHttpsCredentialResource}) {
  if ([authorizationFor, current, chargeResponse, consumePage, callResource].some(value => typeof value !== 'function') ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidGmailLabelListRead');
  }
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumePage, callResource}});
  if (!context.credential.binding || typeof context.credential.binding !== 'object') fail('InvalidGmailLabelListRead');
  if (context.scope.operation !== GMAIL_LABEL_LIST_OPERATION) fail('ForeignGmailLabelListOperation');
  const pages = prepareGmailLabelListPages({moon, mailbox, names, limits: context.limits},
    (method, receiver, args) => Reflect.apply(method, receiver, args));
  return Object.freeze({context, pages, signal});
}

async function executeRead({context, pages, signal}, received) {
  const observations = [], bound = context.limits;
  const verify = async () => {
    signal?.throwIfAborted();
    await context.callbacks.current(GMAIL_LABEL_LIST_OPERATION);
    signal?.throwIfAborted();
  };
  try {
    await verify();
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: GMAIL_LABEL_LIST_OPERATION, index: 0})));
    if (authorization.scope.operation !== GMAIL_LABEL_LIST_OPERATION ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignGmailLabelListAuthorization');
    await verify();
    const request = pages.fetchPage({pageIndex: 0});
    const response = await invokeScopedCredentialOperation({authorization, credential: context.credential,
      callResource: options => context.callbacks.callResource({...options, currentBeforeSend: verify}),
      operation: GMAIL_LABEL_LIST_OPERATION, ...request, maxResponseBytes: bound.maxResponseBytes, signal});
    observations.push(response);
    received?.(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify();
    const {rows, rowCount} = pages.decodePage(response);
    await context.callbacks.consumePage(rows, Object.freeze({charge}));
    await verify();
    // Only the original RowRun caller owns finish/capture. This complete
    // endpoint has no pagination, continuation, retry or inferred row limit.
    return Object.freeze({pages: 1, rowCount,
      observations: Object.freeze(observations.slice())});
  } catch (cause) {
    throw new GmailLabelListReadFailure(cause, observations);
  }
}

export async function readGmailLabelList(options) {
  return executeRead(prepareRead(options));
}

function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignGmailLabelListReader');
  return state;
}

export function createGmailLabelListReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal, stop.signal]);
  const state = {prepared: Object.freeze({...original, signal}), stop, phase: 'ready',
    receivedResponses: 0, receivedBodyBytes: 0n};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('GmailLabelListReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared, response => {
          state.receivedResponses++; state.receivedBodyBytes += BigInt(response.body.byteLength);
        });
        state.phase = 'succeeded'; return result;
      } catch (cause) {state.phase = 'failed'; throw cause;}
    },
    requestStop(reason) {originalReader(this).stop.abort(reason);},
    observe() {
      const state = originalReader(this);
      return Object.freeze({phase: state.phase, stopRequested: state.prepared.signal.aborted,
        receivedResponses: state.receivedResponses, receivedBodyBytes: state.receivedBodyBytes,
        observationCustody: state.receivedResponses === 0 ? 'not-observed' : 'retained',
        cleanupConfirmed: false});
    },
  });
  readers.set(handle, state);
  return handle;
}
