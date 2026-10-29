// One original page observation for the existing Catalog and current/full-diff
// consumers. It does not enumerate pages, issue a Ref or approve a mutation.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,invocationScopeFields,invokeScopedCredentialOperation}
  from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';

export const NOTION_PAGE_READ_OPERATION='notion:pages:retrieve';
const readers=new WeakMap();
const fail=code=>{throw Object.assign(new Error(code),{code});};
const count=value=>Number.isSafeInteger(value)&&value>=0&&value<=2147483647;
const positive=value=>count(value)&&value>0;
const fields=['maxRequestBytes','maxResponseBytes','maxTargetBytes','maxNodes','maxDepth',
  'maxIdentityBytes','maxTextBytes','maxWireBytes','maxWireNodes','maxWireDepth'];
const ports=['notionProjectPage','notionPageMetadataJson'];

function pagePath(pageId,limits){
  if(typeof pageId!=='string'||!pageId.isWellFormed()||pageId.length===0||pageId==='.'||pageId==='..')fail('InvalidNotionPageCoordinate');
  if(pageId.length>limits.maxTargetBytes)fail('NotionPageTargetLimit');
  const path='/v1/pages/'+encodeURIComponent(pageId);
  if(Buffer.byteLength(path)>limits.maxTargetBytes)fail('NotionPageTargetLimit');
  return path;
}

function projectPage(response,pageId,b,provider,receiver,apply){
  if(!response.accepted||response.statusCode!==200)fail('NotionPageReadRejected');
  const page=checked(apply(provider.notionProjectPage,receiver,[response.body,pageId,
    b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,
    b.maxIdentityBytes,b.maxNameBytes,b.maxTextBytes]));
  const metadataWire=checked(apply(provider.notionPageMetadataJson,receiver,
    [page,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth]));
  return Object.freeze({page,metadataWire});
}

// Standard shared-reader callbacks for one original page observation. The
// consumer retains the typed page and metadata DATA with its actual response
// charge. No transport, Credential, cancellation or cleanup owner is created.
export function prepareNotionPageReadPages({moon,pageId,limits},applySynchronousProjection){
  if(typeof applySynchronousProjection!=='function'||!limits||typeof limits!=='object')fail('InvalidNotionPageRead');
  const provider=Object.freeze(Object.fromEntries(ports.map(name=>[name,moon?.[name]])));
  const bound=Object.freeze({...limits});
  if(ports.some(name=>typeof provider[name]!=='function')||
    !fields.every(name=>positive(bound[name]))||
    !['maxDataSources','maxProperties','maxNameBytes'].every(name=>count(bound[name])))fail('InvalidNotionPageRead');
  const path=pagePath(pageId,bound);
  return Object.freeze({
    fetchPage(){return{method:'GET',path,headers:[['accept','application/json'],
      ['notion-version',NOTION_PROPERTY_READ_API_VERSION]],responseHeaders:[]};},
    decodePage(response){return{rows:[projectPage(response,pageId,bound,provider,moon,applySynchronousProjection)],done:true};},
  });
}

export class NotionPageReadFailure extends Error{
  constructor(cause,observation,responseCharge){
    super('NotionPageReadFailed',{cause});this.code='NotionPageReadFailed';
    Object.defineProperties(this,{observation:{value:observation},responseCharge:{value:responseCharge}});
  }
}

function prepare({moon,pageId,initialAuthorization,credential,current,chargeResponse,
  consumeObservation,limits,signal}){
  if([current,chargeResponse,consumeObservation].some(x=>typeof x!=='function'))fail('InvalidNotionPageRead');
  const provider=Object.freeze(Object.fromEntries(ports.map(name=>[name,moon?.[name]])));
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{current,chargeResponse,consumeObservation}});
  if(ports.some(name=>typeof provider[name]!=='function')||!context.credential.binding||
    !fields.every(name=>positive(context.limits[name]))||
    !['maxDataSources','maxProperties','maxNameBytes'].every(name=>count(context.limits[name])))fail('InvalidNotionPageRead');
  const scope=invocationScopeFields(context.scope,context.credential.control);
  if(scope.operation!==NOTION_PAGE_READ_OPERATION)fail('ForeignNotionPageOperation');
  const path=pagePath(pageId,context.limits);
  const request=Object.freeze({operation:NOTION_PAGE_READ_OPERATION,pageId,path,method:'GET',
    resourceOrigin:scope.resourceOrigin});
  return Object.freeze({provider,providerReceiver:moon,context,request,signal});
}

async function readPage(state){
  const {provider,providerReceiver,context,request,signal}=state.original,b=context.limits;
  const verify=async()=>{signal.throwIfAborted();await context.callbacks.current(request);signal.throwIfAborted();};
  try{
    await verify();
    state.observation=await invokeScopedCredentialOperation({authorization:context.authorization,
      credential:context.credential,callResource:options=>callHttpsCredentialResource({...options,currentBeforeSend:verify}),
      operation:request.operation,method:request.method,path:request.path,
      headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
      responseHeaders:[],maxRequestBytes:b.maxRequestBytes,maxResponseBytes:b.maxResponseBytes,signal});
    state.charge=await context.callbacks.chargeResponse(state.observation.body);
    await verify();
    const {page,metadataWire}=projectPage(state.observation,request.pageId,b,provider,providerReceiver,Reflect.apply);
    await verify();
    await context.callbacks.consumeObservation(state.charge);
    await verify();
    return Object.freeze({page,metadataWire,observation:state.observation,responseCharge:state.charge});
  }catch(cause){
    // The original failure and its transport/current/Unknown custody stay with
    // this same reader. Returning a response or resolving a Promise is no ACK.
    state.failure=new NotionPageReadFailure(cause,state.observation,state.charge);throw state.failure;
  }
}

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionPageReader');return state;}

export function createNotionPageReader(options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state={original:Object.freeze({...original,signal}),stop,phase:'ready',observation:undefined,
    charge:undefined,failure:undefined};
  const handle=Object.freeze({
    async read(){const state=originalReader(this);if(state.phase!=='ready')fail('NotionPageAlreadyStarted');
      state.phase='reading';try{const value=await readPage(state);state.phase='succeeded';return value;}
      catch(cause){state.phase='failed';throw cause;}},
    requestStop(reason){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.original.signal.aborted,receivedResponses:state.observation===undefined?0:1,
      receivedBodyBytes:BigInt(state.observation?.body.byteLength??0),cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}
