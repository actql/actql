// One original page observation for the existing Catalog and current/full-diff
// consumers. It does not enumerate pages, issue a Ref or approve a mutation.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,invocationScopeFields,invokeScopedCredentialOperation}
  from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';
import type {NotionReadObservation,NotionReadPhase,NotionReadScope} from './property-item-read.mjs';

export const NOTION_PAGE_READ_OPERATION='notion:pages:retrieve';
const readers=new WeakMap<object,PageState>();
const fail:(code:string)=>never=code=>{throw Object.assign(new Error(code),{code});};
const count=(value:number)=>Number.isSafeInteger(value)&&value>=0&&value<=2147483647;
const positive=(value:number)=>count(value)&&value>0;
const fields=['maxRequestBytes','maxResponseBytes','maxTargetBytes','maxNodes','maxDepth',
  'maxIdentityBytes','maxTextBytes','maxWireBytes','maxWireNodes','maxWireDepth'] as const;
const ports=['notionProjectPage','notionPageMetadataJson'] as const;

type Limits = Readonly<Record<typeof fields[number]|'maxDataSources'|'maxProperties'|'maxNameBytes',number>>;
type ResourceOptions = Parameters<typeof callHttpsCredentialResource>[0];
export type NotionPageBindings = Readonly<{
  notionProjectPage(bytes:NotionReadObservation['body'], pageId:string, maxBytes:number, maxNodes:number,
    maxDepth:number, maxDataSources:number, maxProperties:number, maxIdentityBytes:number,
    maxNameBytes:number, maxTextBytes:number):unknown;
  notionPageMetadataJson(page:unknown,maxBytes:number,maxNodes:number,maxDepth:number):unknown;
}>;
type Request = Readonly<{operation:typeof NOTION_PAGE_READ_OPERATION;pageId:string;path:string;method:'GET';resourceOrigin:unknown}>;
type Callbacks = Readonly<{
  current(request:Request):unknown;
  chargeResponse(body:NotionReadObservation['body']):unknown;
  consumeObservation(charge:unknown):unknown;
}>;
type Options = Callbacks & Readonly<{
  moon:Partial<NotionPageBindings>|undefined;pageId:string;initialAuthorization:unknown;
  credential:unknown;limits:Limits;signal?:AbortSignal;
}>;
type Invocation = ReturnType<typeof ownInvocationContext> & Readonly<{limits:Limits;callbacks:Callbacks}>;
type PageState = {
  original:ReturnType<typeof prepare> & Readonly<{signal:AbortSignal}>;
  stop:AbortController;phase:NotionReadPhase;observation:NotionReadObservation|undefined;
  charge:unknown;failure:NotionPageReadFailure|undefined;
};

export class NotionPageReadFailure extends Error{
  declare readonly code:'NotionPageReadFailed';
  declare readonly observation:NotionReadObservation|undefined;
  declare readonly responseCharge:unknown;

  constructor(cause:unknown,observation:NotionReadObservation|undefined,responseCharge:unknown){
    super('NotionPageReadFailed',{cause});this.code='NotionPageReadFailed';
    Object.defineProperties(this,{observation:{value:observation},responseCharge:{value:responseCharge}});
  }
}

function prepare({moon,pageId,initialAuthorization,credential,current,chargeResponse,
  consumeObservation,limits,signal}:Options){
  if([current,chargeResponse,consumeObservation].some(x=>typeof x!=='function'))fail('InvalidNotionPageRead');
  const provider=Object.freeze(Object.fromEntries(ports.map(name=>[name,moon?.[name]]))) as NotionPageBindings;
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{current,chargeResponse,consumeObservation}}) as Invocation;
  if(ports.some(name=>typeof provider[name]!=='function')||!context.credential.binding||
    !fields.every(name=>positive(context.limits[name]))||
    !(['maxDataSources','maxProperties','maxNameBytes'] as const).every(name=>count(context.limits[name])))fail('InvalidNotionPageRead');
  const scope=invocationScopeFields(context.scope,context.credential.control) as NotionReadScope;
  if(scope.operation!==NOTION_PAGE_READ_OPERATION)fail('ForeignNotionPageOperation');
  if(typeof pageId!=='string'||!pageId.isWellFormed()||pageId.length===0||pageId==='.'||pageId==='..')fail('InvalidNotionPageCoordinate');
  if(pageId.length>context.limits.maxTargetBytes)fail('NotionPageTargetLimit');
  const path='/v1/pages/'+encodeURIComponent(pageId);
  if(Buffer.byteLength(path)>context.limits.maxTargetBytes)fail('NotionPageTargetLimit');
  const request:Request=Object.freeze({operation:NOTION_PAGE_READ_OPERATION,pageId,path,method:'GET',
    resourceOrigin:scope.resourceOrigin});
  return Object.freeze({provider,providerReceiver:moon,context,request,signal});
}

async function readPage(state:PageState){
  const {provider,providerReceiver,context,request,signal}=state.original,b=context.limits;
  const verify=async()=>{signal.throwIfAborted();await context.callbacks.current(request);signal.throwIfAborted();};
  try{
    await verify();
    state.observation=await invokeScopedCredentialOperation({authorization:context.authorization,
      credential:context.credential,callResource:(options:ResourceOptions)=>callHttpsCredentialResource({...options,currentBeforeSend:verify}),
      operation:request.operation,method:request.method,path:request.path,
      headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
      responseHeaders:[],maxRequestBytes:b.maxRequestBytes,maxResponseBytes:b.maxResponseBytes,signal}) as NotionReadObservation;
    state.charge=await context.callbacks.chargeResponse(state.observation.body);
    await verify();
    if(!state.observation.accepted||state.observation.statusCode!==200)fail('NotionPageReadRejected');
    const page=checked(Reflect.apply(provider.notionProjectPage,providerReceiver,[state.observation.body,request.pageId,
      b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,
      b.maxIdentityBytes,b.maxNameBytes,b.maxTextBytes]));
    const metadataWire=checked(Reflect.apply(provider.notionPageMetadataJson,providerReceiver,
      [page,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth])) as string;
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

function originalReader(handle:object){const state=readers.get(handle);if(!state)fail('ForeignNotionPageReader');return state;}

export function createNotionPageReader(options:Options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state:PageState={original:Object.freeze({...original,signal}),stop,phase:'ready',observation:undefined,
    charge:undefined,failure:undefined};
  const handle=Object.freeze({
    async read(){const state=originalReader(this);if(state.phase!=='ready')fail('NotionPageAlreadyStarted');
      state.phase='reading';try{const value=await readPage(state);state.phase='succeeded';return value;}
      catch(cause){state.phase='failed';throw cause;}},
    requestStop(reason?:unknown){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.original.signal.aborted,receivedResponses:state.observation===undefined?0:1,
      receivedBodyBytes:BigInt(state.observation?.body.byteLength??0),cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}
