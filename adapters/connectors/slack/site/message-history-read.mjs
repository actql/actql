// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const SLACK_MESSAGE_HISTORY_OPERATION = 'slack:messages:history';
export const SLACK_WORKSPACE_IDENTITY_OPERATION = 'slack:workspace:identity';
const readers = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const arrayIsArray = Array.isArray, safeInteger = Number.isSafeInteger;
const defineOwned = Object.defineProperty, freezeOwned = Object.freeze;

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
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

export class SlackMessageHistoryReadFailure extends Error {
  constructor(cause, observations) {
    super('SlackMessageHistoryReadFailed', {cause});
    this.code = 'SlackMessageHistoryReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepareRead({moon, workspaceId, channel, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumeObservation, consumePage, signal}) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(fn=>typeof fn !== 'function') ||
      typeof workspaceId !== 'string' || !workspaceId.length ||
      typeof channel !== 'string' || !channel.length || !channel.isWellFormed() ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidSlackMessageHistoryRead');
  }
  if (!moon || typeof moon !== 'object' || types.isProxy(moon)) fail('InvalidSlackMessageHistoryRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(moon,name);
    if (!descriptor || !Object.hasOwn(descriptor,'value') || typeof descriptor.value !== 'function') fail('InvalidSlackMessageHistoryRead');
    const callback=descriptor.value;
    return [name,(...args)=>Reflect.apply(callback,moon,args)];
  })));
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
  return Object.freeze({provider,context,workspaceId,channel,names:selected,signal});
}

async function executeRead(prepared, received) {
  const {provider,context,workspaceId,channel,names,signal} = prepared, bound = context.limits;
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
    // The same opaque binding retains the actual original token across identity
    // and page calls. Each declared operation still claims its own grant/use;
    // an identity observation never grants conversations.history or channel-history access.
    const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json']],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal});
    observations.push(response); received(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(operation);
    if (response.body.byteLength > bound.maxTotalResponseBytes - bytes) fail('SlackMessageHistoryResponseLimit');
    bytes += response.body.byteLength;
    if (!response.accepted || response.statusCode !== 200) fail('SlackMessageHistoryReadRejected');
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
    await verify(SLACK_MESSAGE_HISTORY_OPERATION);
    history=checked(provider.slackPrepareMessageHistory(channel,bound.maxResponseBytes,
      bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
      bound.maxValueNodes,bound.maxValueTextBytes,bound.maxPages));
    let pending=checked(provider.slackBeginMessageHistory(history));
    for (let index=0; index<bound.maxPages; index++) {
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
      if (!provider.slackMessageHistoryRequestMatches(history,pending)) fail('ForeignSlackMessageHistoryRequest');
      const original=JSON.parse(provider.slackMessageHistoryRequestJson(pending));
      if (original.channel!==channel || original.ordinal!==index) fail('ForeignSlackMessageHistoryRequest');
      const query=[['channel',original.channel],['limit',String(bound.pageSize)]];
      if (original.cursor!==null) query.push(['cursor',original.cursor]);
      if (original.latest!==null) query.push(['latest',original.latest],['inclusive','false']);
      const {response,charge}=await request(SLACK_MESSAGE_HISTORY_OPERATION,index,'GET','/api/conversations.history',query);
      const page=checked(provider.slackAdmitMessageHistoryPage(history,pending,response.body));
      const rowCount=provider.slackMessagePageRowCount(page);
      if (rowCount>bound.maxTotalRows-totalRows) fail('SlackMessageHistoryRowLimit');
      const rows=JSON.parse(checked(provider.slackMessagePageRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
      await context.callbacks.consumePage(rows,Object.freeze({charge}));
      // The consumer may revoke currentness or request stop while awaiting.
      // Verify the same original before constructing the next Common request.
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
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
    receivedResponses:0,receivedBodyBytes:0n};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('SlackMessageHistoryReaderAlreadyStarted');
      state.phase = 'reading';
      try {
        const result = await executeRead(state.prepared,response=>{
          state.receivedResponses++; state.receivedBodyBytes += BigInt(response.body.byteLength);
        });
        state.phase = 'succeeded'; return result;
      } catch (cause) {state.phase = 'failed'; throw cause;}
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
