// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const SLACK_USER_LIST_OPERATION = 'slack:users:list';
export const SLACK_WORKSPACE_IDENTITY_OPERATION = 'slack:workspace:identity';
export type SlackListResponse = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
export type SlackListTransportOptions = Parameters<typeof callHttpsCredentialResource>[0];
export type SlackListPageMetadata = Readonly<{rowCount: number; nextCursor: string | null}>;
export type SlackListResult = Readonly<{pages: number; rowCount: number; observations: readonly SlackListResponse[]}>;
export type SlackListPhase = 'ready' | 'reading' | 'succeeded' | 'failed';
export type ListPageProjection = (body: Uint8Array, maxBytes: number, maxNodes: number, maxDepth: number,
  maxRows: number, maxCursorBytes: number, maxValueNodes: number, maxValueTextBytes: number) => unknown;
export type WorkspaceIdentityProvider = {
  slackProjectWorkspaceIdentity(body: Uint8Array, maxBytes: number, maxNodes: number, maxDepth: number,
    maxIdentityBytes: number): unknown;
  slackWorkspaceIdentityMatches(identity: unknown, workspaceId: string): boolean;
};
export type SlackListLimits = Readonly<Record<(typeof limitFields)[number], number>>;
type ListCallbacks<Operation extends string> = {
  authorizationFor(original: Readonly<{operation: Operation; index: number}>): unknown;
  current(operation: Operation): unknown;
  chargeResponse(body: SlackListResponse['body']): unknown;
  consumeObservation(charge: unknown): unknown;
  consumePage(rows: readonly unknown[], original: Readonly<{charge: unknown; originalPage?: object}>): unknown;
};
export type SlackListOptions<Provider, Operation extends string> = ListCallbacks<Operation> & Readonly<{
  moon: Provider; workspaceId: string; names: readonly string[]; initialAuthorization: unknown;
  credential: object; limits: SlackListLimits; signal?: AbortSignal;
}>;
export type SlackListContext<Operation extends string> = Omit<ReturnType<typeof ownInvocationContext>,
  'callbacks' | 'limits'> & Readonly<{callbacks: ListCallbacks<Operation>; limits: SlackListLimits}>;
type Provider = WorkspaceIdentityProvider & {
  slackProjectUserList: ListPageProjection;
  slackUserListIds(page: unknown): string[];
  slackUserListRowsWire(page: unknown, names: readonly string[], maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  slackUserListMetadataJson(page: unknown): string;
  slackUserListColumnNames(): string[];
};
type Operation = typeof SLACK_USER_LIST_OPERATION | typeof SLACK_WORKSPACE_IDENTITY_OPERATION;
type ReadOptions = SlackListOptions<Provider, Operation>;
type Prepared = ReturnType<typeof prepareRead> & {signal: AbortSignal};
type ReaderState = {prepared: Prepared; stop: AbortController; phase: SlackListPhase;
  receivedResponses: number; receivedBodyBytes: bigint};

const readers = new WeakMap<object, ReaderState>();
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['slackProjectUserList','slackUserListIds','slackUserListRowsWire',
  'slackUserListMetadataJson','slackUserListColumnNames',
  'slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches'] as const;
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;

export class SlackUserListReadFailure extends Error {
  declare readonly code: 'SlackUserListReadFailed';
  declare readonly observations: readonly SlackListResponse[];

  constructor(cause: unknown, observations: readonly SlackListResponse[]) {
    super('SlackUserListReadFailed', {cause});
    this.code = 'SlackUserListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepareRead({moon, workspaceId, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumeObservation, consumePage, signal}: ReadOptions) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(fn=>typeof fn !== 'function') ||
      typeof workspaceId !== 'string' || !workspaceId.length ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidSlackUserListRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name=>[name,moon?.[name]]))) as Provider;
  const context = ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumePage}}) as SlackListContext<Operation>;
  if (providerExports.some(name=>typeof provider[name] !== 'function') ||
      !limitFields.every(name=>positive(context.limits[name])) || context.limits.pageSize >= 1000 ||
      !context.credential.binding || typeof context.credential.binding !== 'object' ||
      workspaceId.length > context.limits.maxIdentityBytes || !workspaceId.isWellFormed() ||
      Buffer.byteLength(workspaceId) > context.limits.maxIdentityBytes) fail('InvalidSlackUserListRead');
  if ((context.scope as {operation?: unknown}).operation !== SLACK_USER_LIST_OPERATION) fail('ForeignSlackUserListOperation');
  const columns = Object.freeze(provider.slackUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name=>!columns.includes(name))) fail('InvalidSlackUserListRead');
  return Object.freeze({provider,context,workspaceId,names:Object.freeze(names.slice()),signal});
}

async function executeRead(prepared: Prepared, received: (response: SlackListResponse) => void) {
  const {provider,context,workspaceId,names,signal} = prepared, bound = context.limits;
  const observations: SlackListResponse[] = [], cursors = new Set<string>(), ids = new Set<string>();
  let bytes = 0, totalRows = 0;
  const verify = async (operation: Operation) => {
    signal.throwIfAborted();
    await context.callbacks.current(operation);
    signal.throwIfAborted();
  };
  const request = async (operation: Operation, index: number, method: 'POST' | 'GET', path: string,
    query: readonly (readonly [string, string])[], body?: string) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation,index})));
    if ((authorization.scope as {operation?: unknown}).operation !== operation ||
        !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignSlackUserListAuthorization');
    if (Buffer.byteLength(requestTarget(path,query)) > bound.maxTargetBytes) fail('SlackUserListTargetLimit');
    await verify(operation);
    // The same opaque binding retains the actual original token across identity
    // and page calls. Each declared operation still claims its own grant/use;
    // an identity observation never grants users.list or users:read.email.
    const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:(options: SlackListTransportOptions)=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json']],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal}) as SlackListResponse;
    observations.push(response); received(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(operation);
    if (response.body.byteLength > bound.maxTotalResponseBytes - bytes) fail('SlackUserListResponseLimit');
    bytes += response.body.byteLength;
    if (!response.accepted || response.statusCode !== 200) fail('SlackUserListReadRejected');
    return {response,charge};
  };
  try {
    const observed = await request(SLACK_WORKSPACE_IDENTITY_OPERATION,0,'POST','/api/auth.test',[],'{}');
    const identity = checked(provider.slackProjectWorkspaceIdentity(observed.response.body,
      bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,bound.maxIdentityBytes));
    if (!provider.slackWorkspaceIdentityMatches(identity,workspaceId)) fail('ForeignSlackWorkspace');
    await context.callbacks.consumeObservation(observed.charge);
    await verify(SLACK_WORKSPACE_IDENTITY_OPERATION);
    // No team_id argument is used as an identity proof: Slack ignores it for
    // workspace tokens. The actual auth.test response and same retained token
    // must agree with the originally selected workspace before any data call.
    let cursor: string | undefined;
    for (let index=0; index<bound.maxPages; index++) {
      const remaining = bound.maxTotalRows - totalRows;
      if (remaining <= 0) fail('SlackUserListRowLimit');
      const query: [string, string][] = [['limit',String(Math.min(bound.pageSize,remaining))]];
      if (cursor !== undefined) query.push(['cursor',cursor]);
      const {response,charge} = await request(SLACK_USER_LIST_OPERATION,index,'GET','/api/users.list',query);
      const page = checked(provider.slackProjectUserList(response.body,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
        bound.maxValueNodes,bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.slackUserListMetadataJson(page)) as SlackListPageMetadata;
      if (metadata.rowCount > bound.maxTotalRows-totalRows) fail('SlackUserListRowLimit');
      const pageIds = provider.slackUserListIds(page);
      for (const id of pageIds) {
        if (ids.has(id)) fail('SlackUserListDuplicateUser');
        ids.add(id);
      }
      if (metadata.nextCursor !== null) {
        if (cursors.has(metadata.nextCursor)) fail('SlackUserListRepeatedCursor');
        cursors.add(metadata.nextCursor);
        if (index+1 === bound.maxPages) fail('SlackUserListPageLimit');
      }
      const rows = JSON.parse(checked(provider.slackUserListRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)) as string) as readonly unknown[];
      await context.callbacks.consumePage(rows,Object.freeze({charge}));
      totalRows += metadata.rowCount;
      await verify(SLACK_USER_LIST_OPERATION);
      if (metadata.nextCursor === null) return Object.freeze({pages:index+1,rowCount:totalRows,
        observations:Object.freeze(observations.slice())});
      cursor = metadata.nextCursor;
    }
    fail('SlackUserListPageLimit');
  } catch (cause) {
    throw new SlackUserListReadFailure(cause,observations);
  }
}

function originalReader(value: object) {
  const state = readers.get(value);
  if (!state) fail('ForeignSlackUserListReader');
  return state;
}

export function createSlackUserListReader(options: ReadOptions) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal,stop.signal]);
  const state: ReaderState = {prepared:Object.freeze({...original,signal}),stop,phase:'ready',
    receivedResponses:0,receivedBodyBytes:0n};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('SlackUserListReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared,response=>{
          state.receivedResponses++; state.receivedBodyBytes += BigInt(response.body.byteLength);
        });
        state.phase = 'succeeded'; return result;
      } catch (cause) {state.phase = 'failed'; throw cause;}
    },
    requestStop(reason?: unknown) {originalReader(this).stop.abort(reason);},
    observe() {
      const state = originalReader(this);
      return Object.freeze({phase:state.phase,stopRequested:state.prepared.signal.aborted,
        receivedResponses:state.receivedResponses,receivedBodyBytes:state.receivedBodyBytes,
        observationCustody:state.receivedResponses===0?'not-observed':'retained',cleanupConfirmed:false});
    },
  });
  readers.set(handle,state);
  return handle;
}
