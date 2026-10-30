// Vendor sequencing only. The Catalog owns response meaning; Credential owns
// original token custody/uses. The caller owns RowRun, funding and final capture.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const NOTION_USER_LIST_OPERATION = 'notion:users:list';
// Reviewed vendor request version; not an ActQL identity/version authority.
export const NOTION_USER_LIST_API_VERSION = '2026-03-11';
const readers = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['notionProjectUserList','notionUserListIds','notionUserListRowsWire',
  'notionUserListMetadataJson','notionUserListColumnNames'];
const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

export class NotionUserListReadFailure extends Error {
  constructor(cause, observations) {
    super('NotionUserListReadFailed', {cause});
    this.code = 'NotionUserListReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

function prepareRead({moon, names, initialAuthorization, credential,
  authorizationFor, limits, current, chargeResponse, consumePage, signal}) {
  if (!Array.isArray(names) ||
      [authorizationFor,current,chargeResponse,consumePage].some(fn=>typeof fn !== 'function') ||
      !credential || typeof credential !== 'object' || !limits || typeof limits !== 'object') {
    fail('InvalidNotionUserListRead');
  }
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name=>[name,moon?.[name]])));
  const context = ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumePage}});
  if (providerExports.some(name=>typeof provider[name] !== 'function') ||
      !limitFields.every(name=>positive(context.limits[name])) || context.limits.pageSize > 100 ||
      !context.credential.binding || typeof context.credential.binding !== 'object') fail('InvalidNotionUserListRead');
  if (context.scope.operation !== NOTION_USER_LIST_OPERATION) fail('ForeignNotionUserListOperation');
  const columns = Object.freeze(provider.notionUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name=>!columns.includes(name))) fail('InvalidNotionUserListRead');
  return Object.freeze({provider,context,names:Object.freeze(names.slice()),signal});
}

async function executeRead(prepared, received) {
  const {provider,context,names,signal} = prepared, bound = context.limits;
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
        !invocationBindingsMatch(authorization.scope,context.scope)) fail('ForeignNotionUserListAuthorization');
    if (Buffer.byteLength(requestTarget(path,query)) > bound.maxTargetBytes) fail('NotionUserListTargetLimit');
    await verify(operation);
    // The original installed token binding selects its workspace. A user-list
    // response supplies no workspace issuer or extra information capability.
    // Every page still claims its own current original grant/use.
    const response = await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,
        currentBeforeSend:()=>verify(operation)}),
      operation,method,path,query,body,headers:[['accept','application/json'],
        ['notion-version',NOTION_USER_LIST_API_VERSION]],
      responseHeaders:[],maxResponseBytes:bound.maxResponseBytes,signal});
    observations.push(response); received(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(operation);
    if (response.body.byteLength > bound.maxTotalResponseBytes - bytes) fail('NotionUserListResponseLimit');
    bytes += response.body.byteLength;
    if (!response.accepted || response.statusCode !== 200) fail('NotionUserListReadRejected');
    return {response,charge};
  };
  try {
    let cursor;
    for (let index=0; index<bound.maxPages; index++) {
      const remaining = bound.maxTotalRows - totalRows;
      if (remaining <= 0) fail('NotionUserListRowLimit');
      const query = [['page_size',String(Math.min(bound.pageSize,remaining))]];
      if (cursor !== undefined) query.push(['start_cursor',cursor]);
      const {response,charge} = await request(NOTION_USER_LIST_OPERATION,index,'GET','/v1/users',query);
      const page = checked(provider.notionProjectUserList(response.body,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
        bound.maxIdentityBytes,bound.maxValueNodes,bound.maxValueTextBytes));
      const metadata = JSON.parse(checked(provider.notionUserListMetadataJson(page,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
      if (metadata.rowCount > bound.maxTotalRows-totalRows) fail('NotionUserListRowLimit');
      const pageIds = provider.notionUserListIds(page);
      for (const id of pageIds) {
        if (ids.has(id)) fail('NotionUserListDuplicateUser');
        ids.add(id);
      }
      if (metadata.nextCursor !== null) {
        if (cursors.has(metadata.nextCursor)) fail('NotionUserListRepeatedCursor');
        cursors.add(metadata.nextCursor);
        if (index+1 === bound.maxPages) fail('NotionUserListPageLimit');
      }
      const rows = JSON.parse(checked(provider.notionUserListRowsWire(page,names,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)));
      await context.callbacks.consumePage(rows,Object.freeze({charge}));
      totalRows += metadata.rowCount;
      await verify(NOTION_USER_LIST_OPERATION);
      if (metadata.nextCursor === null) return Object.freeze({pages:index+1,rowCount:totalRows,
        observations:Object.freeze(observations.slice())});
      cursor = metadata.nextCursor;
    }
    fail('NotionUserListPageLimit');
  } catch (cause) {
    throw new NotionUserListReadFailure(cause,observations);
  }
}

function originalReader(value) {
  const state = readers.get(value);
  if (!state) fail('ForeignNotionUserListReader');
  return state;
}

export function createNotionUserListReader(options) {
  const original = prepareRead(options), stop = new AbortController();
  const signal = original.signal === undefined ? stop.signal : AbortSignal.any([original.signal,stop.signal]);
  const state = {prepared:Object.freeze({...original,signal}),stop,phase:'ready',
    receivedResponses:0,receivedBodyBytes:0n};
  const handle = Object.freeze({
    async read() {
      const state = originalReader(this);
      if (state.phase !== 'ready') fail('NotionUserListReaderAlreadyStarted');
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
