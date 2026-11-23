// Gmail sequencing only: the compiled Catalog owns row meaning and schema;
// existing Account, Credential, RowRun and physical custody owners are separate.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

type Response = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type ResourceRequest = Parameters<typeof callHttpsCredentialResource>[0];
type ProviderMethod = (...args: never[]) => unknown;
type Projection = (method: ProviderMethod, receiver: unknown, args: unknown[]) => unknown;
type Scope = Readonly<{operation?: unknown}>;
type Authorization = ReturnType<typeof ownInvocationAuthorization>;
type ReaderPhase = 'ready' | 'reading' | 'succeeded' | 'failed';

type Limits = Readonly<Record<typeof limitFields[number], number>>;
type Provider = Readonly<{
  gmailProjectLabelList(body: Buffer, bytes: number, nodes: number, depth: number,
    rows: number, valueNodes: number, valueTextBytes: number): unknown;
  gmailLabelListRowsWire(page: unknown, columns: readonly string[], bytes: number, nodes: number, depth: number): unknown;
  gmailLabelListMetadataJson(page: unknown): string;
  gmailLabelListColumnNames(): readonly string[];
}>;
type PageOptions = Readonly<{moon: Provider; mailbox: string; names: readonly string[]; limits: Limits}>;
type ReaderOptions = PageOptions & Readonly<{
  initialAuthorization: unknown; credential: unknown; signal?: AbortSignal;
  authorizationFor(input: Readonly<{operation: string; index: number}>): unknown;
  current(operation: string): unknown; chargeResponse(body: Buffer): unknown;
  consumePage(rows: unknown, ticket: Readonly<{charge: unknown}>): unknown;
  callResource?: (request: ResourceRequest) => unknown;
}>;
type CallbackPorts = Required<Pick<ReaderOptions, 'authorizationFor' | 'current' |
  'chargeResponse' | 'consumePage' | 'callResource'>>;
type ReaderState = {prepared: ReturnType<typeof prepareRead> & {signal: AbortSignal};
  stop: AbortController; phase: ReaderPhase; receivedResponses: number; receivedBodyBytes: bigint};

export const GMAIL_LABEL_LIST_OPERATION = 'gmail:labels:list';
const readers = new WeakMap<object, ReaderState>();
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['gmailProjectLabelList', 'gmailLabelListRowsWire',
  'gmailLabelListMetadataJson', 'gmailLabelListColumnNames'] as const;
const limitFields = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows',
  'maxMailboxBytes', 'maxTargetBytes', 'maxValueNodes', 'maxValueTextBytes',
  'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'] as const;
const query = Object.freeze([Object.freeze(['fields', 'labels(id,name,type)'])]);

export class GmailLabelListReadFailure extends Error {
  declare readonly code: 'GmailLabelListReadFailed';
  declare readonly observations: readonly Response[];

  constructor(cause: unknown, observations: readonly Response[]) {
    super('GmailLabelListReadFailed', {cause});
    this.code = 'GmailLabelListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// Both the installed shared reader and the original explicit physical reader
// consume this SAME request and Catalog projection. No transport or grant is
// available here; applySynchronousProjection belongs to the retaining caller.
export function prepareGmailLabelListPages({moon, mailbox, names, limits}: PageOptions, applySynchronousProjection: Projection) {
  if (!Array.isArray(names) || new Set(names).size !== names.length ||
      !limits || typeof limits !== 'object' || typeof applySynchronousProjection !== 'function') {
    fail('InvalidGmailLabelListRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidGmailLabelListRead');
    return [name, (...args: unknown[]) => applySynchronousProjection(original, moon, args)];
  }))) as unknown as Provider;
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
    fetchPage({pageIndex}: Readonly<{pageIndex: number}>) {
      if (pageIndex !== 0) fail('GmailLabelListReadAlreadyCompleted');
      return {method: 'GET', path, query, headers: [['accept', 'application/json']], responseHeaders: []};
    },
    decodePage(response: Pick<Response, 'accepted' | 'statusCode' | 'body'>) {
      if (!response.accepted || response.statusCode !== 200) fail('GmailLabelListReadRejected');
      const page = checked(provider.gmailProjectLabelList(response.body, bound.maxResponseBytes,
        bound.maxNodes, bound.maxDepth, bound.maxRows, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.gmailLabelListMetadataJson(page)) as {rowCount: number};
      const rows: unknown = JSON.parse(checked(provider.gmailLabelListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)) as string);
      return {rows, rowCount: metadata.rowCount, done: true};
    },
    onError(cause: unknown) {return new GmailLabelListReadFailure(cause, []);},
  });
}

function prepareRead({moon, mailbox, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumePage, signal,
  callResource = callHttpsCredentialResource}: ReaderOptions) {
  if ([authorizationFor, current, chargeResponse, consumePage, callResource].some(value => typeof value !== 'function') ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidGmailLabelListRead');
  }
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumePage, callResource}}) as
    ReturnType<typeof ownInvocationContext> & {limits: Limits; scope: Scope; callbacks: CallbackPorts};
  if (!context.credential.binding || typeof context.credential.binding !== 'object') fail('InvalidGmailLabelListRead');
  if (context.scope.operation !== GMAIL_LABEL_LIST_OPERATION) fail('ForeignGmailLabelListOperation');
  const pages = prepareGmailLabelListPages({moon, mailbox, names, limits: context.limits},
    (method, receiver, args) => Reflect.apply(method, receiver, args));
  return Object.freeze({context, pages, signal});
}

async function executeRead({context, pages, signal}: ReturnType<typeof prepareRead>,
  received?: (response: Response) => void) {
  const observations: Response[] = [], bound = context.limits;
  const verify = async () => {
    signal?.throwIfAborted();
    await context.callbacks.current(GMAIL_LABEL_LIST_OPERATION);
    signal?.throwIfAborted();
  };
  try {
    await verify();
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: GMAIL_LABEL_LIST_OPERATION, index: 0}))) as Authorization & {scope: Scope};
    if (authorization.scope.operation !== GMAIL_LABEL_LIST_OPERATION ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignGmailLabelListAuthorization');
    await verify();
    const request = pages.fetchPage({pageIndex: 0});
    const response = await invokeScopedCredentialOperation({authorization, credential: context.credential,
      callResource: (options: ResourceRequest) => context.callbacks.callResource({...options, currentBeforeSend: verify}),
      operation: GMAIL_LABEL_LIST_OPERATION, ...request, maxResponseBytes: bound.maxResponseBytes, signal}) as Response;
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

export async function readGmailLabelList(options: ReaderOptions) {
  return executeRead(prepareRead(options));
}

function originalReader(value: object) {
  const state = readers.get(value);
  if (!state) fail('ForeignGmailLabelListReader');
  return state;
}

export function createGmailLabelListReader(options: ReaderOptions) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal, stop.signal]);
  const state: ReaderState = {prepared: Object.freeze({...original, signal}), stop, phase: 'ready',
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
    requestStop(reason: unknown) {originalReader(this).stop.abort(reason);},
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
