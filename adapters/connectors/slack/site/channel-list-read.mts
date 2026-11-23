// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';
import type {ListPageProjection, SlackListContext, SlackListLimits, SlackListOptions, SlackListPageMetadata,
  SlackListPhase, SlackListResponse, SlackListResult, SlackListTransportOptions, WorkspaceIdentityProvider}
  from './user-list-read.mjs';

export const SLACK_CHANNEL_LIST_OPERATION = 'slack:channels:list';
export const SLACK_WORKSPACE_IDENTITY_OPERATION = 'slack:workspace:identity';
type Provider = WorkspaceIdentityProvider & {
  slackProjectChannelList: ListPageProjection;
  slackChannelListIds(page: unknown): string[];
  slackChannelListRowsWire(page: unknown, names: readonly string[], maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  slackChannelListMetadataJson(page: unknown): string;
  slackChannelListColumnNames(): string[];
};
type Operation = typeof SLACK_CHANNEL_LIST_OPERATION | typeof SLACK_WORKSPACE_IDENTITY_OPERATION;
type HistoryProvider = {
  slackProjectHistoryConversationList: ListPageProjection;
  slackPrepareMessageHistoryFromChannel(page: unknown, index: number, maxBytes: number, maxNodes: number,
    maxDepth: number, maxRows: number, maxCursorBytes: number, maxValueNodes: number,
    maxValueTextBytes: number, maxPages: number): unknown;
  slackMessageHistoryMatchesChannel(history: unknown, page: unknown, index: number): boolean;
};
type ReadOptions = SlackListOptions<Provider & Partial<HistoryProvider>, Operation>;
type PageRecord = {page: unknown; response: SlackListResponse; charge: unknown; ids: readonly string[]; consumed: boolean};
type OriginalPage = PageRecord & {token: object; selected: Set<number>};
type Exchange = {authorization: ReturnType<typeof ownInvocationAuthorization>; operation: Operation;
  index: number; method: 'POST' | 'GET'; path: string; query: readonly (readonly [string, string])[];
  body?: string; failure?: unknown; response?: SlackListResponse; charge?: unknown};
type Originals = {pages: Map<object, OriginalPage>; exchanges: Exchange[];
  result?: SlackListResult; failure?: unknown};
type ChannelSelection = {source: ReaderState; page: OriginalPage; index: number; used: boolean; control: unknown};
type Prepared = ReturnType<typeof prepareRead> & {signal: AbortSignal};
type ReaderState = {prepared: Prepared; stop: AbortController; phase: SlackListPhase;
  receivedResponses: number; receivedBodyBytes: bigint; originals?: Originals};

const readers = new WeakMap<object, ReaderState>();
const channelSelections = new WeakMap<object, ChannelSelection>();
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['slackProjectChannelList','slackChannelListIds','slackChannelListRowsWire',
  'slackChannelListMetadataJson','slackChannelListColumnNames',
  'slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches'] as const;
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;

export class SlackChannelListReadFailure extends Error {
  declare readonly code: 'SlackChannelListReadFailed';
  declare readonly observations: readonly SlackListResponse[];

  constructor(cause: unknown, observations: readonly SlackListResponse[]) {
    super('SlackChannelListReadFailed', {cause});
    this.code = 'SlackChannelListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepareRead({moon, workspaceId, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumeObservation, consumePage, signal}: ReadOptions, retainOriginal: boolean, allConversations: boolean) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(fn=>typeof fn !== 'function') ||
      typeof workspaceId !== 'string' || !workspaceId.length ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidSlackChannelListRead');
  }
  if (!moon || typeof moon !== 'object' || types.isProxy(moon)) fail('InvalidSlackChannelListRead');
  const capture = <Name extends keyof (Provider & HistoryProvider),>(name: Name, optional = false) => {
    const descriptor = Object.getOwnPropertyDescriptor(moon,name);
    if (optional && descriptor === undefined) return undefined;
    if (!descriptor || !Object.hasOwn(descriptor,'value') || typeof descriptor.value !== 'function') {
      fail('InvalidSlackChannelListRead');
    }
    const method = descriptor.value;
    return ((...args: unknown[]) => Reflect.apply(method,moon,args)) as (Provider & HistoryProvider)[Name];
  };
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name=>[name,capture(name)]))) as Provider;
  const historyPrepare = retainOriginal ? capture('slackPrepareMessageHistoryFromChannel',true) : undefined;
  const historyMatches = retainOriginal ? capture('slackMessageHistoryMatchesChannel',true) : undefined;
  if ((historyPrepare === undefined) !== (historyMatches === undefined)) fail('InvalidSlackChannelListRead');
  const projectPage = allConversations ? capture('slackProjectHistoryConversationList')! : provider.slackProjectChannelList;
  const context = ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumePage}}) as SlackListContext<Operation>;
  if (providerExports.some(name=>typeof provider[name] !== 'function') ||
      !limitFields.every(name=>positive(context.limits[name])) || context.limits.pageSize >= 1000 ||
      !context.credential.binding || typeof context.credential.binding !== 'object' ||
      workspaceId.length > context.limits.maxIdentityBytes || !workspaceId.isWellFormed() ||
      Buffer.byteLength(workspaceId) > context.limits.maxIdentityBytes) fail('InvalidSlackChannelListRead');
  if ((context.scope as {operation?: unknown}).operation !== SLACK_CHANNEL_LIST_OPERATION) fail('ForeignSlackChannelListOperation');
  const columns = Object.freeze(provider.slackChannelListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name=>!columns.includes(name))) fail('InvalidSlackChannelListRead');
  return Object.freeze({provider,projectPage,allConversations,context,workspaceId,names:Object.freeze(names.slice()),signal,
    ...(retainOriginal ? {moon,historyPrepare,historyMatches} : {})});
}

async function executeRead(prepared: Prepared, received: (response: SlackListResponse) => void,
  retainPage?: (record: PageRecord) => OriginalPage, retainExchange?: (exchange: Exchange) => Exchange) {
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
        !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignSlackChannelListAuthorization');
    if (Buffer.byteLength(requestTarget(path,query)) > bound.maxTargetBytes) fail('SlackChannelListTargetLimit');
    await verify(operation);
    const exchange = retainExchange?.({authorization,operation,index,method,path,query,body});
    // The same opaque binding retains the actual original token across identity
    // and page calls. Each declared operation still claims its own grant/use;
    // an identity observation never grants conversations.list or channels:read/groups:read.
    let response: SlackListResponse;
    try {
      response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:(options: SlackListTransportOptions)=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json']],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal}) as SlackListResponse;
    } catch (cause) {
      if (exchange !== undefined) exchange.failure = cause;
      throw cause;
    }
    if (exchange !== undefined) exchange.response = response;
    observations.push(response); received(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    if (exchange !== undefined) exchange.charge = charge;
    await verify(operation);
    if (response.body.byteLength > bound.maxTotalResponseBytes - bytes) fail('SlackChannelListResponseLimit');
    bytes += response.body.byteLength;
    if (!response.accepted || response.statusCode !== 200) fail('SlackChannelListReadRejected');
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
      if (remaining <= 0) fail('SlackChannelListRowLimit');
      const query: [string, string][] = [['types',prepared.allConversations ? 'public_channel,private_channel,mpim,im' : 'public_channel,private_channel'],
        ['exclude_archived','false'],['limit',String(Math.min(bound.pageSize,remaining))]];
      if (cursor !== undefined) query.push(['cursor',cursor]);
      const {response,charge} = await request(SLACK_CHANNEL_LIST_OPERATION,index,'GET','/api/conversations.list',query);
      const page = checked(prepared.projectPage(response.body,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
        bound.maxValueNodes,bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.slackChannelListMetadataJson(page)) as SlackListPageMetadata;
      if (metadata.rowCount > bound.maxTotalRows-totalRows) fail('SlackChannelListRowLimit');
      const pageIds = provider.slackChannelListIds(page);
      for (const id of pageIds) {
        if (ids.has(id)) fail('SlackChannelListDuplicateChannel');
        ids.add(id);
      }
      if (metadata.nextCursor !== null) {
        if (cursors.has(metadata.nextCursor)) fail('SlackChannelListRepeatedCursor');
        cursors.add(metadata.nextCursor);
        if (index+1 === bound.maxPages) fail('SlackChannelListPageLimit');
      }
      const rows = JSON.parse(checked(provider.slackChannelListRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)) as string) as readonly unknown[];
      const retained = retainPage?.({page,response,charge,ids:Object.freeze(pageIds.slice()),consumed:false});
      await context.callbacks.consumePage(rows,Object.freeze(retained === undefined ? {charge} : {charge,originalPage:retained.token}));
      await verify(SLACK_CHANNEL_LIST_OPERATION);
      if (retained !== undefined) retained.consumed = true;
      totalRows += metadata.rowCount;
      if (metadata.nextCursor === null) return Object.freeze({pages:index+1,rowCount:totalRows,
        observations:Object.freeze(observations.slice())});
      cursor = metadata.nextCursor;
    }
    fail('SlackChannelListPageLimit');
  } catch (cause) {
    throw new SlackChannelListReadFailure(cause,observations);
  }
}

function originalReader(value: object) {
  const state = readers.get(value);
  if (!state) fail('ForeignSlackChannelListReader');
  return state;
}

export function createSlackChannelListReader(options: ReadOptions) {
  return createChannelReader(options,false);
}

// Explicit original-prefix custody for a later history reader. This is not a
// claim that the returned pages cover every conversation in an installation.
export function createSlackChannelListReaderForHistory(options: ReadOptions) {
  return createChannelReader(options,true);
}

// A distinct bound request for history discovery, including direct messages.
// Its broader request does not widen the ordinary channels Source or issue
// access to conversations that the actual token cannot observe.
export function createSlackConversationListReaderForHistory(options: ReadOptions) {
  return createChannelReader(options,true,true);
}

function createChannelReader(options: ReadOptions, retainOriginal: boolean, allConversations=false) {
  const original = prepareRead(options,retainOriginal,allConversations), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal,stop.signal]);
  const state: ReaderState = {prepared:Object.freeze({...original,signal}),stop,phase:'ready',
    receivedResponses:0,receivedBodyBytes:0n,
    ...(retainOriginal ? {originals:{pages:new Map(),exchanges:[],result:undefined,failure:undefined}} : {})};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('SlackChannelListReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared,response=>{
          state.receivedResponses++; state.receivedBodyBytes += BigInt(response.body.byteLength);
        },retainOriginal ? record=>{
          const retained = {...record,token:Object.freeze({}),selected:new Set<number>()};
          state.originals!.pages.set(retained.token,retained);return retained;
        } : undefined,retainOriginal ? exchange=>{state.originals!.exchanges.push(exchange);return exchange;} : undefined);
        if (state.originals !== undefined) state.originals.result = result;
        state.phase = 'succeeded'; return result;
      } catch (cause) {
        if (state.originals !== undefined) state.originals.failure = cause;
        state.phase = 'failed'; throw cause;
      }
    },
    requestStop(reason?: unknown) {originalReader(this).stop.abort(reason);},
    observe() {
      const state = originalReader(this);
      return Object.freeze({phase:state.phase,stopRequested:state.prepared.signal.aborted,
        receivedResponses:state.receivedResponses,receivedBodyBytes:state.receivedBodyBytes,
        observationCustody:state.receivedResponses===0?'not-observed':'retained',cleanupConfirmed:false,
        ...(state.originals === undefined ? {} : {originalChannelPages:state.originals.pages.size,originalExchanges:state.originals.exchanges.length})});
    },
  });
  readers.set(handle,state);
  return handle;
}


// A selection retains the completed reader and its actual response/charge
// prefix. Equal row text, a copied token, or a page from another reader cannot
// create this nominal selection. It does not issue a credential or capacity.
export function selectSlackOriginalChannel(reader: object, originalPage: object, index: number) {
  const source = originalReader(reader), page = source.originals?.pages.get(originalPage);
  if (source.phase !== 'succeeded' || source.prepared.signal.aborted || !page?.consumed ||
      !Number.isSafeInteger(index) || index < 0 || index >= page.ids.length || page.selected.has(index)) {
    fail('ForeignSlackOriginalChannel');
  }
  const token = Object.freeze({});
  page.selected.add(index);
  channelSelections.set(token,{source,page,index,used:false,control:undefined});
  return token;
}

function originalChannel(selection: object, moon: unknown) {
  const selected = channelSelections.get(selection);
  if (!selected || selected.source.prepared.moon !== moon || selected.source.phase !== 'succeeded' ||
      selected.source.prepared.signal.aborted || !selected.page.consumed) fail('ForeignSlackOriginalChannel');
  return selected;
}

// Scalar DATA for validation before preparation. No original page or raw
// compiler representation escapes this receiver.
export function slackOriginalChannelName(selection: object, moon: unknown) {
  const selected = originalChannel(selection,moon);
  return selected.page.ids[selected.index];
}

export function prepareSlackOriginalChannelHistory(selection: object, moon: unknown, workspaceId: string,
  scope: unknown, credential: Readonly<Record<string, unknown>>, bounds: SlackListLimits) {
  const selected = originalChannel(selection,moon), source = selected.source.prepared;
  if (selected.used || source.workspaceId !== workspaceId || !invocationBindingsMatch(scope,source.context.scope)) {
    fail('ForeignSlackOriginalChannel');
  }
  const keys = Object.keys(source.context.credential);
  if (Object.keys(credential).length !== keys.length || keys.some(key=>credential[key] !== source.context.credential[key])) {
    fail('ForeignSlackOriginalChannel');
  }
  if (!source.historyPrepare || !source.historyMatches) fail('SlackChannelHistoryRuntimeUnavailable');
  // A failed preparation retains its original selection and cannot be rebound.
  selected.used = true;
  const control = checked(source.historyPrepare(selected.page.page,selected.index,
    bounds.maxResponseBytes,bounds.maxNodes,bounds.maxDepth,
    Math.min(bounds.maxRows,bounds.pageSize,999),bounds.maxCursorBytes,
    bounds.maxValueNodes,bounds.maxValueTextBytes,bounds.maxPages));
  if (!source.historyMatches(control,selected.page.page,selected.index)) fail('ForeignSlackOriginalChannel');
  selected.control = control;
  const callback = source.context.callbacks.current, receiver = source.context.callbacks;
  return Object.freeze({control,async assertCurrent(){
    originalChannel(selection,moon);
    await Reflect.apply(callback,receiver,[SLACK_CHANNEL_LIST_OPERATION]);
    originalChannel(selection,moon);
  }});
}
