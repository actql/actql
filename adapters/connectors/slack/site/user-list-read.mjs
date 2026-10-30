// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const SLACK_USER_LIST_OPERATION = 'slack:users:list';
export const SLACK_WORKSPACE_IDENTITY_OPERATION = 'slack:workspace:identity';
const readers = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['slackProjectUserList','slackUserListIds','slackUserListRowsWire',
  'slackUserListMetadataJson','slackUserListColumnNames',
  'slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches'];
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

export class SlackUserListReadFailure extends Error {
  constructor(cause, observations) {
    super('SlackUserListReadFailed', {cause});
    this.code = 'SlackUserListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepareRead({moon, workspaceId, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumeObservation, consumePage, signal}) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(fn=>typeof fn !== 'function') ||
      typeof workspaceId !== 'string' || !workspaceId.length ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidSlackUserListRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name=>[name,moon?.[name]])));
  const context = ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumePage}});
  if (providerExports.some(name=>typeof provider[name] !== 'function') ||
      !limitFields.every(name=>positive(context.limits[name])) || context.limits.pageSize >= 1000 ||
      !context.credential.binding || typeof context.credential.binding !== 'object' ||
      workspaceId.length > context.limits.maxIdentityBytes || !workspaceId.isWellFormed() ||
      Buffer.byteLength(workspaceId) > context.limits.maxIdentityBytes) fail('InvalidSlackUserListRead');
  if (context.scope.operation !== SLACK_USER_LIST_OPERATION) fail('ForeignSlackUserListOperation');
  const columns = Object.freeze(provider.slackUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name=>!columns.includes(name))) fail('InvalidSlackUserListRead');
  return Object.freeze({provider,context,workspaceId,names:Object.freeze(names.slice()),signal});
}

async function executeRead(prepared, received) {
  const {provider,context,workspaceId,names,signal} = prepared, bound = context.limits;
  const observations = [], cursors = new Set(), ids = new Set();
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
        !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignSlackUserListAuthorization');
    if (Buffer.byteLength(requestTarget(path,query)) > bound.maxTargetBytes) fail('SlackUserListTargetLimit');
    await verify(operation);
    // The same opaque binding retains the actual original token across identity
    // and page calls. Each declared operation still claims its own grant/use;
    // an identity observation never grants users.list or users:read.email.
    const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json']],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal});
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
    let cursor;
    for (let index=0; index<bound.maxPages; index++) {
      const remaining = bound.maxTotalRows - totalRows;
      if (remaining <= 0) fail('SlackUserListRowLimit');
      const query = [['limit',String(Math.min(bound.pageSize,remaining))]];
      if (cursor !== undefined) query.push(['cursor',cursor]);
      const {response,charge} = await request(SLACK_USER_LIST_OPERATION,index,'GET','/api/users.list',query);
      const page = checked(provider.slackProjectUserList(response.body,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
        bound.maxValueNodes,bound.maxValueTextBytes));
      const metadata = JSON.parse(provider.slackUserListMetadataJson(page));
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
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
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

function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignSlackUserListReader');
  return state;
}

export function createSlackUserListReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal,stop.signal]);
  const state = {prepared:Object.freeze({...original,signal}),stop,phase:'ready',
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
