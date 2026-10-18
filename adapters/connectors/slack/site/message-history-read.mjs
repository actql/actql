// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const SLACK_MESSAGE_HISTORY_OPERATION = 'slack:messages:history';
export const SLACK_MESSAGE_REPLIES_OPERATION = 'slack:messages:replies';
export const SLACK_WORKSPACE_IDENTITY_OPERATION = 'slack:workspace:identity';
const readers = new WeakMap();
const replyReaders = new WeakMap();
// Escaped success/failure objects keep their original prefix and custody graph.
// Weak reachability and eventual collection are not physical cleanup evidence.
const outcomes = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const arrayIsArray = Array.isArray, safeInteger = Number.isSafeInteger;
const defineOwned = Object.defineProperty, freezeOwned = Object.freeze;

function retainOutcome(value,state) {
  if (value!==null && (typeof value==='object' || typeof value==='function')) outcomes.set(value,state);
}

// Capture each original indexed value once, including permitted index getters.
// Caller methods, iterators and Array species never choose the retained fields.
function ownColumnArray(value, maximum) {
  if (!arrayIsArray(value)) fail('InvalidSlackMessageHistoryRead');
  const length = value.length;
  if (!safeInteger(length) || length < 0 || length > maximum) fail('InvalidSlackMessageHistoryRead');
  const owned = [];
  for (let index=0; index<length; index++) {
    defineOwned(owned,index,{value:value[index],enumerable:true});
  }
  return freezeOwned(owned);
}

const providerExports = ['slackAdmitMessageHistoryPage','slackMessageHistoryRequestMatches','slackMessagePageRowsWire',
  'slackMessagePageRowCount','slackMessageColumnNames',
  'slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches',
  'slackPrepareMessageHistory','slackBeginMessageHistory','slackMessageHistoryRequestJson',
  'slackMessageHistoryPageHasNext','slackNextMessageHistoryRequest','slackFinishMessageHistory','slackCloseMessageHistory'];
const windowProviderExports = ['slackPrepareMessageHistoryWindow'];
const replyProviderExports = ['slackPrepareMessageReplies','slackMessageRepliesMatchesOriginal',
  'slackBeginMessageReplies','slackMessageRepliesRequestMatches','slackMessageRepliesRequestJson',
  'slackAdmitMessageRepliesPage','slackMessageRepliesPageHasNext','slackNextMessageRepliesRequest',
  'slackFinishMessageReplies','slackMessageRepliesPageRowCount','slackMessageRepliesPageRowsWire',
  'slackCloseMessageReplies'];
const projectionProviderExports = ['slackCoalesceMessageOriginals','slackMessageProjectionRowCount',
  'slackMessageProjectionRowsWire'];
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

function captureProvider(moon,names,optional=false,code='SlackMessageOriginalRuntimeUnavailable') {
  if (optional && names.every(name=>!Object.hasOwn(moon,name))) return undefined;
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(moon,name);
    if (!descriptor || !Object.hasOwn(descriptor,'value') || typeof descriptor.value!=='function') {
      fail(code);
    }
    const callback=descriptor.value;
    return [name,(...args)=>Reflect.apply(callback,moon,args)];
  })));
}

export class SlackMessageHistoryReadFailure extends Error {
  constructor(cause, observations) {
    super('SlackMessageHistoryReadFailed', {cause});
    this.code = 'SlackMessageHistoryReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// Exact request DATA supplied by the original caller, never a WHERE-derived
// coverage claim. Common alone validates timestamp syntax and interval order.
function ownHistoryWindow(value) {
  if (value === undefined) return undefined;
  if (!value || typeof value !== 'object' || types.isProxy(value)) fail('InvalidSlackMessageHistoryWindow');
  const keys = Reflect.ownKeys(value);
  if (keys.length !== 2 || !keys.includes('oldest') || !keys.includes('latest')) fail('InvalidSlackMessageHistoryWindow');
  const fields = {};
  for (const name of ['oldest','latest']) {
    const descriptor = Object.getOwnPropertyDescriptor(value,name);
    if (!descriptor || !Object.hasOwn(descriptor,'value') ||
        (descriptor.value !== null && typeof descriptor.value !== 'string')) fail('InvalidSlackMessageHistoryWindow');
    fields[name] = descriptor.value;
  }
  return Object.freeze(fields);
}

function prepareRead({moon, workspaceId, channel, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumeObservation, consumePage, signal, requestWindow}) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(fn=>typeof fn !== 'function') ||
      typeof workspaceId !== 'string' || !workspaceId.length ||
      typeof channel !== 'string' || !channel.length || !channel.isWellFormed() ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidSlackMessageHistoryRead');
  }
  if (!moon || typeof moon !== 'object' || types.isProxy(moon)) fail('InvalidSlackMessageHistoryRead');
  const provider = captureProvider(moon,providerExports,false,'InvalidSlackMessageHistoryRead');
  const timeWindow = ownHistoryWindow(requestWindow);
  const windowProvider = timeWindow === undefined ? undefined
    : captureProvider(moon,windowProviderExports,false,'SlackMessageHistoryWindowRuntimeUnavailable');
  const replyProvider = captureProvider(moon,replyProviderExports,true);
  const projectionProvider = captureProvider(moon,projectionProviderExports,true);
  const context = ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumePage}});
  if (providerExports.some(name=>typeof provider[name] !== 'function') ||
      !limitFields.every(name=>positive(context.limits[name])) || context.limits.pageSize > 1000 ||
      !context.credential.binding || typeof context.credential.binding !== 'object' ||
      workspaceId.length > context.limits.maxIdentityBytes || !workspaceId.isWellFormed() ||
      Buffer.byteLength(workspaceId) > context.limits.maxIdentityBytes ||
      Buffer.byteLength(channel) > context.limits.maxIdentityBytes) fail('InvalidSlackMessageHistoryRead');
  if (context.scope.operation !== SLACK_MESSAGE_HISTORY_OPERATION) fail('ForeignSlackMessageHistoryOperation');
  const columns = ownColumnArray(provider.slackMessageColumnNames(),2147483647);
  const selected = ownColumnArray(names,columns.length);
  for (let index=0; index<selected.length; index++) {
    const name = selected[index];
    if (typeof name !== 'string') fail('InvalidSlackMessageHistoryRead');
    let found = false;
    for (let column=0; column<columns.length; column++) {
      if (columns[column] === name) {found=true;break;}
    }
    if (!found) fail('InvalidSlackMessageHistoryRead');
    for (let previous=0; previous<index; previous++) {
      if (selected[previous] === name) fail('InvalidSlackMessageHistoryRead');
    }
  }
  return Object.freeze({provider,windowProvider,timeWindow,replyProvider,projectionProvider,context,workspaceId,channel,names:selected,signal});
}

async function executeRead(prepared, received, retainPage, retainIdentity, retainExchange, retainControl) {
  const {provider,windowProvider,timeWindow,context,workspaceId,channel,names,signal} = prepared, bound = context.limits;
  // Vendor dispatch limit, independent of the admitted Host/Program ceilings.
  const historyPageSize = Math.min(bound.pageSize,999);
  const observations = [];
  let history;
  let bytes = 0, totalRows = 0;
  const verify = async operation => {
    signal.throwIfAborted();
    await context.callbacks.current(operation);
    signal.throwIfAborted();
  };
  const request = async (operation,index,method,path,query,body) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation,index})));
    if (authorization.scope.operation !== operation ||
        !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignSlackMessageHistoryAuthorization');
    if (Buffer.byteLength(requestTarget(path,query)) > bound.maxTargetBytes) fail('SlackMessageHistoryTargetLimit');
    await verify(operation);
    const exchange=retainExchange({authorization,operation,index,method,path,query,body});
    // The same opaque binding retains the actual original token across identity
    // and page calls. Each declared operation still claims its own grant/use;
    // an identity observation never grants conversations.history or channel-history access.
    const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json']],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal});
    exchange.response=response;
    observations.push(response); received(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    exchange.charge=charge;
    await verify(operation);
    if (response.body.byteLength > bound.maxTotalResponseBytes - bytes) fail('SlackMessageHistoryResponseLimit');
    bytes += response.body.byteLength;
    if (!response.accepted || response.statusCode !== 200) fail('SlackMessageHistoryReadRejected');
    return {response,charge,exchange};
  };
  try {
    if (timeWindow !== undefined) {
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
      history=checked(windowProvider.slackPrepareMessageHistoryWindow(channel,timeWindow.oldest??undefined,timeWindow.latest??undefined,
        bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,historyPageSize),
        bound.maxCursorBytes,bound.maxValueNodes,bound.maxValueTextBytes,bound.maxPages));
      retainControl(history);
    }
    const observed = await request(SLACK_WORKSPACE_IDENTITY_OPERATION,0,'POST','/api/auth.test',[],'{}');
    const identity = checked(provider.slackProjectWorkspaceIdentity(observed.response.body,
      bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,bound.maxIdentityBytes));
    if (!provider.slackWorkspaceIdentityMatches(identity,workspaceId)) fail('ForeignSlackWorkspace');
    await context.callbacks.consumeObservation(observed.charge);
    await verify(SLACK_WORKSPACE_IDENTITY_OPERATION);
    retainIdentity(identity);
    // No team_id argument is used as an identity proof: Slack ignores it for
    // workspace tokens. The actual auth.test response and same retained token
    // must agree with the originally selected workspace before any data call.
    await verify(SLACK_MESSAGE_HISTORY_OPERATION);
    if (history === undefined) {
      history=checked(provider.slackPrepareMessageHistory(channel,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,historyPageSize),bound.maxCursorBytes,
        bound.maxValueNodes,bound.maxValueTextBytes,bound.maxPages));
      retainControl(history);
    }
    let pending=checked(provider.slackBeginMessageHistory(history));
    for (let index=0; index<bound.maxPages; index++) {
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
      if (!provider.slackMessageHistoryRequestMatches(history,pending)) fail('ForeignSlackMessageHistoryRequest');
      const original=JSON.parse(provider.slackMessageHistoryRequestJson(pending));
      if (original.channel!==channel || original.ordinal!==index) fail('ForeignSlackMessageHistoryRequest');
      const query=[['channel',original.channel],['limit',String(historyPageSize)]];
      if (original.cursor!==null) query.push(['cursor',original.cursor]);
      const oldest=Object.hasOwn(original,'oldest')?original.oldest:null;
      if (oldest!==(timeWindow?.oldest??null)) fail('ForeignSlackMessageHistoryRequest');
      if (oldest!==null) query.push(['oldest',oldest]);
      if (original.latest!==null) query.push(['latest',original.latest]);
      if (oldest!==null || original.latest!==null) query.push(['inclusive','false']);
      const {response,charge,exchange}=await request(SLACK_MESSAGE_HISTORY_OPERATION,index,'GET','/api/conversations.history',query);
      const page=checked(provider.slackAdmitMessageHistoryPage(history,pending,response.body));
      const rowCount=provider.slackMessagePageRowCount(page);
      if (rowCount>bound.maxTotalRows-totalRows) fail('SlackMessageHistoryRowLimit');
      const rows=JSON.parse(checked(provider.slackMessagePageRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
      const retained=retainPage({page,pending,response,charge,rowCount,exchange});
      await context.callbacks.consumePage(rows,Object.freeze({charge,originalPage:retained.token}));
      // The consumer may revoke currentness or request stop while awaiting.
      // Verify the same original before constructing the next Common request.
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
      retained.consumed=true;
      totalRows+=rowCount;
      if (!provider.slackMessageHistoryPageHasNext(page)) {
        checked(provider.slackFinishMessageHistory(history,page));
        return Object.freeze({pages:index+1,rowCount:totalRows,observations:Object.freeze(observations.slice())});
      }
      pending=checked(provider.slackNextMessageHistoryRequest(history,page));
    }
    fail('SlackMessageHistoryPageLimit');
  } catch (cause) {
    throw new SlackMessageHistoryReadFailure(cause,observations);
  } finally {
    // Closing the Catalog control stops admission, not physical cleanup or the
    // retirement of escaped response, charge, error and Promise references.
    if (history!==undefined) provider.slackCloseMessageHistory(history);
  }
}

function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignSlackMessageHistoryReader');
  return state;
}

export function createSlackMessageHistoryReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal,stop.signal]);
  const state = {prepared:Object.freeze({...original,signal}),stop,phase:'ready',
    receivedResponses:0,receivedBodyBytes:0n,observations:[],exchanges:[],pages:new Map(),workspaceIdentity:undefined,control:undefined};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('SlackMessageHistoryReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared,response=>{
          state.receivedResponses++; state.receivedBodyBytes += BigInt(response.body.byteLength);
          state.observations.push(response);
        },record=>{
          const retained={...record,token:Object.freeze({}),consumed:false,selections:new Set()};
          state.pages.set(retained.token,retained);return retained;
        },identity=>{state.workspaceIdentity=identity;},exchange=>{
          state.exchanges.push(exchange);return exchange;
        },control=>{state.control=control;});
        state.phase = 'succeeded';retainOutcome(result,state);return result;
      } catch (cause) {state.phase = 'failed';retainOutcome(cause,state);throw cause;}
    },
    requestStop(reason) {originalReader(this).stop.abort(reason);},
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

export class SlackMessageRepliesReadFailure extends Error {
  constructor(cause,observations) {
    super('SlackMessageRepliesReadFailed',{cause});
    this.code='SlackMessageRepliesReadFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
  }
}

function originalReplyReader(handle) {
  const state=replyReaders.get(handle);
  if (!state) fail('ForeignSlackMessageRepliesReader');
  return state;
}

function prepareReplyRead({historyReader,originalPage,index,names,initialAuthorization,credential,
  authorizationFor,limits,current,chargeResponse,consumePage,signal}) {
  const source=originalReader(historyReader),record=source.pages.get(originalPage);
  if (source.phase!=='succeeded' || source.prepared.signal.aborted || !source.workspaceIdentity ||
      !record?.consumed || !safeInteger(index) || index<0 || index>=record.rowCount ||
      record.selections.has(index)) fail('ForeignSlackMessageRepliesSelection');
  const provider=source.prepared.replyProvider;
  if (!provider) fail('SlackMessageOriginalRuntimeUnavailable');
  if ([authorizationFor,current,chargeResponse,consumePage].some(fn=>typeof fn!=='function')) {
    fail('InvalidSlackMessageRepliesRead');
  }
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumePage}});
  if (context.scope.operation!==SLACK_MESSAGE_REPLIES_OPERATION ||
      !invocationBindingsMatch(context.scope,source.prepared.context.scope)) {
    fail('ForeignSlackMessageRepliesAuthorization');
  }
  const old=source.prepared.context.credential,keys=Object.keys(old);
  if (Object.keys(context.credential).length!==keys.length ||
      keys.some(key=>context.credential[key]!==old[key])) fail('ForeignSlackMessageRepliesCredential');
  const bound=context.limits;
  if (![...limitFields,'maxComparisonNodes','maxComparisonDepth','maxComparisonTextBytes','maxWork']
      .every(name=>positive(bound[name])) || bound.pageSize>1000) fail('InvalidSlackMessageRepliesRead');
  const columns=ownColumnArray(source.prepared.provider.slackMessageColumnNames(),2147483647);
  const selected=ownColumnArray(names,columns.length);
  for (let i=0;i<selected.length;i++) {
    let found=false;
    for (let column=0;column<columns.length;column++) if (columns[column]===selected[i]) {found=true;break;}
    if (typeof selected[i]!=='string' || !found) fail('InvalidSlackMessageRepliesRead');
    for (let previous=0;previous<i;previous++) if (selected[i]===selected[previous]) fail('InvalidSlackMessageRepliesRead');
  }
  // This selection retains the original page/request/response/charge and reader.
  // Neither its token nor the previous identity observation grants replies.
  return Object.freeze({historyReader,source,record,index,provider,context,names:selected,signal});
}

async function executeReplyRead(prepared,received,retainControl,retainExchange) {
  const {source,record,index,provider,context,names,signal}=prepared,bound=context.limits;
  const observations=[];
  let replies,totalRows=0,bytes=0;
  const verify=async()=>{
    signal.throwIfAborted();
    await source.prepared.context.callbacks.current(SLACK_MESSAGE_REPLIES_OPERATION);
    signal.throwIfAborted();
    if (context.callbacks.current!==source.prepared.context.callbacks.current) {
      await context.callbacks.current(SLACK_MESSAGE_REPLIES_OPERATION);
      signal.throwIfAborted();
    }
  };
  try {
    await verify();
    replies=checked(provider.slackPrepareMessageReplies(record.page,index,bound.maxResponseBytes,
      bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
      bound.maxValueNodes,bound.maxValueTextBytes,bound.maxComparisonNodes,bound.maxComparisonDepth,
      bound.maxComparisonTextBytes,bound.maxPages,bound.maxTotalRows,bound.maxTotalResponseBytes,bound.maxWork));
    retainControl(replies);
    if (!provider.slackMessageRepliesMatchesOriginal(replies,record.page,index)) {
      fail('ForeignSlackMessageRepliesSelection');
    }
    let pending=checked(provider.slackBeginMessageReplies(replies)),target;
    for (let ordinal=0;ordinal<bound.maxPages;ordinal++) {
      await verify();
      if (!provider.slackMessageRepliesRequestMatches(replies,pending)) fail('ForeignSlackMessageRepliesRequest');
      const request=JSON.parse(provider.slackMessageRepliesRequestJson(pending));
      if (target===undefined) target=request.ts;
      if (request.channel!==source.prepared.channel || request.ts!==target || request.ordinal!==ordinal) {
        fail('ForeignSlackMessageRepliesRequest');
      }
      const query=[['channel',request.channel],['ts',request.ts],['limit',String(bound.pageSize)]];
      if (request.cursor!==null) query.push(['cursor',request.cursor]);
      if (request.oldest!==null) query.push(['oldest',request.oldest],['inclusive','false']);
      if (Buffer.byteLength(requestTarget('/api/conversations.replies',query))>bound.maxTargetBytes) {
        fail('SlackMessageRepliesTargetLimit');
      }
      const authorization=ownInvocationAuthorization(await context.callbacks.authorizationFor(
        Object.freeze({operation:SLACK_MESSAGE_REPLIES_OPERATION,index:ordinal})));
      if (authorization.scope.operation!==SLACK_MESSAGE_REPLIES_OPERATION ||
          !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignSlackMessageRepliesAuthorization');
      await verify();
      const exchange=retainExchange({pending,authorization,request});
      const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
        callResource:options=>callHttpsCredentialResource({...options,currentBeforeSend:verify}),
        operation:SLACK_MESSAGE_REPLIES_OPERATION,method:'GET',path:'/api/conversations.replies',query,
        headers:[['accept','application/json']],responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal});
      exchange.response=response;
      observations.push(response);received(response);
      const charge=await context.callbacks.chargeResponse(response.body);
      exchange.charge=charge;
      await verify();
      if (response.body.byteLength>bound.maxTotalResponseBytes-bytes) fail('SlackMessageRepliesResponseLimit');
      bytes+=response.body.byteLength;
      if (!response.accepted || response.statusCode!==200) fail('SlackMessageRepliesReadRejected');
      const page=checked(provider.slackAdmitMessageRepliesPage(replies,pending,response.body));
      exchange.page=page;
      const rowCount=provider.slackMessageRepliesPageRowCount(page);
      if (rowCount>bound.maxTotalRows-totalRows) fail('SlackMessageRepliesRowLimit');
      const rows=JSON.parse(checked(provider.slackMessageRepliesPageRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
      await context.callbacks.consumePage(rows,Object.freeze({charge}));
      await verify();
      totalRows+=rowCount;
      if (!provider.slackMessageRepliesPageHasNext(page)) {
        checked(provider.slackFinishMessageReplies(replies,page));
        return Object.freeze({pages:ordinal+1,rowCount:totalRows,observations:Object.freeze(observations.slice())});
      }
      pending=checked(provider.slackNextMessageRepliesRequest(replies,page));
    }
    fail('SlackMessageRepliesPageLimit');
  } catch (cause) {
    throw new SlackMessageRepliesReadFailure(cause,observations);
  } finally {
    if (replies!==undefined) provider.slackCloseMessageReplies(replies);
  }
}

export function createSlackMessageRepliesReader(options) {
  const original=prepareReplyRead(options),stop=new AbortController();
  const signals=[stop.signal,original.source.prepared.signal];
  if (original.signal!==undefined) signals.push(original.signal);
  const signal=AbortSignal.any(signals);
  const state={prepared:Object.freeze({...original,signal}),stop,phase:'ready',observations:[],
    exchanges:[],control:undefined,receivedBodyBytes:0n};
  const handle=Object.freeze({
    async read() {
      const state=originalReplyReader(this);
      if (state.phase!=='ready') fail('SlackMessageRepliesReaderAlreadyStarted');
      state.phase='reading';
      try {
        const result=await executeReplyRead(state.prepared,response=>{
          state.observations.push(response);state.receivedBodyBytes+=BigInt(response.body.byteLength);
        },control=>{state.control=control;},exchange=>{
          state.exchanges.push(exchange);return exchange;
        });
        state.phase='succeeded';retainOutcome(result,state);return result;
      } catch (cause) {state.phase='failed';retainOutcome(cause,state);throw cause;}
    },
    requestStop(reason) {originalReplyReader(this).stop.abort(reason);},
    observe() {
      const state=originalReplyReader(this);
      return Object.freeze({phase:state.phase,stopRequested:state.prepared.signal.aborted,
        receivedResponses:state.observations.length,receivedBodyBytes:state.receivedBodyBytes,
        observationCustody:state.observations.length===0?'not-observed':'retained',cleanupConfirmed:false});
    },
  });
  original.record.selections.add(original.index);
  replyReaders.set(handle,state);
  return handle;
}

const projectionLimitFields=['maxRows','maxOccurrences','maxWork','maxComparisonNodes',
  'maxComparisonDepth','maxComparisonTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

function projectionRecord(value,required,optional=[]) {
  if (value===null || typeof value!=='object' || arrayIsArray(value) || types.isProxy(value)) {
    fail('InvalidSlackMessageProjection');
  }
  const keys=Reflect.ownKeys(value);
  if (required.some(key=>!keys.includes(key)) || keys.some(key=>!required.includes(key)&&!optional.includes(key))) {
    fail('InvalidSlackMessageProjection');
  }
  const result={};
  for (const key of keys) {
    const descriptor=Object.getOwnPropertyDescriptor(value,key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor,'value')) fail('InvalidSlackMessageProjection');
    defineOwned(result,key,{value:descriptor.value,enumerable:true});
  }
  return freezeOwned(result);
}

function projectionArray(value,maximum) {
  if (!arrayIsArray(value) || types.isProxy(value)) fail('InvalidSlackMessageProjection');
  const length=value.length;
  if (!safeInteger(length) || length<0 || length>maximum) fail('InvalidSlackMessageProjection');
  const result=[];
  for (let index=0;index<length;index++) defineOwned(result,index,{value:value[index],enumerable:true});
  return freezeOwned(result);
}

export class SlackMessageProjectionFailure extends Error {
  constructor(cause) {
    super('SlackMessageProjectionFailed',{cause});
    this.code='SlackMessageProjectionFailed';
  }
}

// Completed original observations only. This neither sends another request nor
// issues a complete Source, new grant, response ticket or cleanup receipt.
export async function coalesceSlackMessageReaders(options) {
  const original=projectionRecord(options,['historyReader','replyReaders','names','limits'],['signal']);
  const source=originalReader(original.historyReader),provider=source.prepared.projectionProvider;
  if (source.phase!=='succeeded' || source.control===undefined) fail('ForeignSlackMessageProjectionSelection');
  if (!provider) fail('SlackMessageOriginalRuntimeUnavailable');
  const bound=projectionRecord(original.limits,projectionLimitFields);
  if (!projectionLimitFields.every(name=>positive(bound[name]))) fail('InvalidSlackMessageProjection');
  const handles=projectionArray(original.replyReaders,bound.maxOccurrences),states=[],controls=[];
  const signals=[source.prepared.signal];
  if (original.signal!==undefined) defineOwned(signals,signals.length,{value:original.signal,enumerable:true});
  for (let index=0;index<handles.length;index++) {
    const reply=originalReplyReader(handles[index]);
    if (reply.prepared.source!==source || reply.phase!=='succeeded' || reply.control===undefined) {
      fail('ForeignSlackMessageProjectionSelection');
    }
    defineOwned(states,index,{value:reply,enumerable:true});
    defineOwned(controls,index,{value:reply.control,enumerable:true});
    defineOwned(signals,signals.length,{value:reply.prepared.signal,enumerable:true});
  }
  freezeOwned(states);freezeOwned(controls);freezeOwned(signals);
  const signal=AbortSignal.any(signals);
  const columns=projectionArray(source.prepared.provider.slackMessageColumnNames(),2147483647);
  const names=projectionArray(original.names,columns.length);
  for (let index=0;index<names.length;index++) {
    let found=false;
    for (let column=0;column<columns.length;column++) if (columns[column]===names[index]) {found=true;break;}
    if (typeof names[index]!=='string' || !found) fail('InvalidSlackMessageProjection');
    for (let before=0;before<index;before++) if (names[index]===names[before]) fail('InvalidSlackMessageProjection');
  }
  const state={historyReader:original.historyReader,handles,source,states,controls,signal,names,bound,
    projection:undefined,wire:undefined,rows:undefined};
  const current=async(callbacks,operation)=>{
    signal.throwIfAborted();
    await callbacks.current(operation);
    signal.throwIfAborted();
  };
  try {
    await current(source.prepared.context.callbacks,SLACK_MESSAGE_HISTORY_OPERATION);
    if (states.length) {
      await current(source.prepared.context.callbacks,SLACK_MESSAGE_REPLIES_OPERATION);
      for (let index=0;index<states.length;index++) {
        const reply=states[index];
        if (reply.prepared.context.callbacks.current!==source.prepared.context.callbacks.current) {
          await current(reply.prepared.context.callbacks,SLACK_MESSAGE_REPLIES_OPERATION);
        }
      }
    }
    signal.throwIfAborted();
    state.projection=checked(provider.slackCoalesceMessageOriginals(source.control,controls,
      bound.maxRows,bound.maxOccurrences,bound.maxWork,bound.maxComparisonNodes,
      bound.maxComparisonDepth,bound.maxComparisonTextBytes));
    const rowCount=provider.slackMessageProjectionRowCount(state.projection);
    if (!safeInteger(rowCount) || rowCount<0 || rowCount>bound.maxRows) fail('SlackMessageProjectionRowLimit');
    state.wire=checked(provider.slackMessageProjectionRowsWire(state.projection,names,
      bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth));
    state.rows=JSON.parse(state.wire);
    const result=freezeOwned({rowCount,rows:state.rows,cleanupConfirmed:false});
    retainOutcome(result,state);
    return result;
  } catch (cause) {
    const failure=new SlackMessageProjectionFailure(cause);
    retainOutcome(failure,state);
    throw failure;
  }
}
