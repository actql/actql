// Physical sequencing only. Common owns original property/cursor/checked-value
// meaning; Credential owns each original use. Raw aliases retain cleanup debt.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const NOTION_PROPERTY_READ_OPERATION='notion:pages:property:read';
export const NOTION_PROPERTY_READ_API_VERSION='2026-03-11';
const readers=new WeakMap<object,PropertyState>();
const fail:(code:string)=>never=code=>{throw Object.assign(new Error(code),{code});};
const positive=(x:number)=>Number.isSafeInteger(x)&&x>0&&x<=2147483647;
const sharedPorts=['notionPropertyRequestJson','notionProjectPropertyItemPage',
  'notionPropertyItemPageComplete','notionNextPropertyRequest'] as const;
const fields=['maxResponseBytes','maxTotalResponseBytes','maxTargetBytes','maxPages','pageSize',
  'maxValueNodes','maxValueDepth','maxValueTextBytes','maxWireBytes','maxWireNodes','maxWireDepth'] as const;

export type NotionReadObservation = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type ResourceOptions = Parameters<typeof callHttpsCredentialResource>[0];
export type NotionReadPhase = 'ready' | 'reading' | 'succeeded' | 'failed';
export type NotionReadScope = Readonly<{operation?: unknown; resourceOrigin?: unknown}>;

type Limits = Readonly<Record<typeof fields[number],number>>;
export type NotionPropertyBindings = Readonly<{
  notionPropertyRequestJson(request:unknown, bytes:number, nodes:number, depth:number):unknown;
  notionProjectPropertyItemPage(request:unknown, bytes:NotionReadObservation['body']):unknown;
  notionPropertyItemPageComplete(page:unknown):boolean;
  notionNextPropertyRequest(page:unknown):unknown;
  notionPropertyRequestMatchesBinding(request:unknown, binding:unknown, column:number):boolean;
  notionPropertyRequestMatchesPageTitle(request:unknown, page:unknown):boolean;
  notionCompletedPageTitleJson(original:unknown, page:unknown, admissionNodes:number, admissionDepth:number,
    admissionTextBytes:number, bytes:number, nodes:number, depth:number):unknown;
  notionCompletedPropertyJson(binding:unknown, page:unknown, column:number, admissionNodes:number,
    admissionDepth:number, admissionTextBytes:number, bytes:number, nodes:number, depth:number):unknown;
}>;
export type NotionPropertySelection = Readonly<{
  operation:typeof NOTION_PROPERTY_READ_OPERATION; index:number; originalRequest:unknown;
}>;
type Callbacks = Readonly<{
  authorizationFor(selection:NotionPropertySelection):unknown;
  current(operation:typeof NOTION_PROPERTY_READ_OPERATION):unknown;
  chargeResponse(body:NotionReadObservation['body']):unknown;
  consumeObservation(charge:unknown):unknown;
  consumeValue(valueWire:string, original:Readonly<{charge:unknown; originalRequest:unknown; completedPage:unknown}>):unknown;
}>;
type Options = Callbacks & Readonly<{
  moon:Partial<NotionPropertyBindings>|undefined; originalRequest:unknown; readContracts?:unknown; column?:number;
  pageTitle?:unknown; initialAuthorization:unknown; credential:unknown; limits:Limits; signal?:AbortSignal;
}>;
type Invocation = ReturnType<typeof ownInvocationContext> & Readonly<{
  scope:NotionReadScope; limits:Limits; callbacks:Callbacks;
}>;
type Prepared = ReturnType<typeof prepareRead> & Readonly<{signal:AbortSignal}>;
type PropertyState = {
  prepared:Prepared; stop:AbortController; phase:NotionReadPhase; receivedResponses:number; receivedBodyBytes:bigint;
};

export class NotionPropertyReadFailure extends Error {
  declare readonly code:'NotionPropertyReadFailed';
  declare readonly observations:readonly NotionReadObservation[];

  constructor(cause:unknown,observations:readonly NotionReadObservation[]){
    super('NotionPropertyReadFailed',{cause});this.code='NotionPropertyReadFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
  }
}

// Returned property ids are already URI-encoded. Preserve original percent
// escapes rather than encode them again; encode other original code points.
// A dot-only coordinate is unavailable at this physical path boundary.
function originalPathSegment(text:string){
  if(typeof text!=='string'||text.length===0||text==='.'||text==='..')fail('InvalidNotionPropertyCoordinate');
  let result='';
  for(let i=0;i<text.length;){
    if(text[i]==='%'&&/^[0-9A-Fa-f]{2}$/u.test(text.slice(i+1,i+3))){result+=text.slice(i,i+3);i+=3;}
    else{const point=String.fromCodePoint(text.codePointAt(i)!);result+=encodeURIComponent(point);i+=point.length;}
  }
  // Percent-encoded dot segments have the same URL routing hazard. This is
  // physical target validation, not a ban on a logical property name/id.
  if(/^((%2[eE])|\.){1,2}$/u.test(result))fail('InvalidNotionPropertyCoordinate');
  return result;
}

function prepareRead({moon,originalRequest,readContracts,column,pageTitle,initialAuthorization,
  credential,authorizationFor,current,chargeResponse,consumeObservation,consumeValue,limits,signal}:Options,title:boolean){
  if(!originalRequest||(title?(!pageTitle||readContracts!==undefined||column!==undefined):
    (!readContracts||pageTitle!==undefined||!Number.isSafeInteger(column)||column!<0||column!>2147483647))||
    [authorizationFor,current,chargeResponse,consumeObservation,consumeValue].some(x=>typeof x!=='function'))fail('InvalidNotionPropertyRead');
  const matchesPort=title?'notionPropertyRequestMatchesPageTitle':'notionPropertyRequestMatchesBinding';
  const completePort=title?'notionCompletedPageTitleJson':'notionCompletedPropertyJson';
  const names=[...sharedPorts,matchesPort,completePort] as const;
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,moon?.[name]]))) as NotionPropertyBindings;
  const call=(name:keyof NotionPropertyBindings,...args:unknown[]):unknown=>Reflect.apply(provider[name],moon,args);
  const matches=(request:unknown)=>title?call(matchesPort,request,pageTitle)===true:
    call(matchesPort,request,readContracts,column)===true;
  const complete=(page:unknown,b:Limits)=>checked(call(completePort,...(title?[pageTitle,page]:[readContracts,page,column]),
    b.maxValueNodes,b.maxValueDepth,b.maxValueTextBytes,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string;
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumeValue}}) as Invocation;
  if(names.some(name=>typeof provider[name]!=='function')||!fields.every(name=>positive(context.limits[name]))||
    context.limits.pageSize>100||!context.credential.binding)fail('InvalidNotionPropertyRead');
  if(context.scope.operation!==NOTION_PROPERTY_READ_OPERATION)fail('ForeignNotionPropertyOperation');
  if(!matches(originalRequest))fail('ForeignNotionPropertyOriginal');
  return Object.freeze({call,matches,complete,context,originalRequest,readContracts,column,pageTitle,signal});
}

async function executeRead(prepared:Prepared,received:(response:NotionReadObservation)=>void){
  const {call,matches,complete,context,signal}=prepared,bounds=context.limits;
  const observations:NotionReadObservation[]=[];let request:unknown=prepared.originalRequest,totalBytes=0;
  const verify=async()=>{signal.throwIfAborted();await context.callbacks.current(NOTION_PROPERTY_READ_OPERATION);signal.throwIfAborted();
    if(!matches(request))fail('ForeignNotionPropertyOriginal');};
  try{
    for(let index=0;index<bounds.maxPages;index++){
      await verify();
      const target=JSON.parse(checked(call('notionPropertyRequestJson',request,bounds.maxWireBytes,bounds.maxWireNodes,bounds.maxWireDepth)) as string) as {pageId:string;propertyId:string;cursor:string|null};
      if(Object.keys(target).length!==3||typeof target.pageId!=='string'||typeof target.propertyId!=='string'||
        target.cursor!==null&&typeof target.cursor!=='string')fail('InvalidNotionPropertyRequest');
      const path='/v1/pages/'+originalPathSegment(target.pageId)+'/properties/'+originalPathSegment(target.propertyId);
      const query:[string,string][]=[['page_size',String(bounds.pageSize)]];
      if(target.cursor!==null)query.push(['start_cursor',target.cursor]);
      if(Buffer.byteLength(requestTarget(path,query))>bounds.maxTargetBytes)fail('NotionPropertyTargetLimit');
      const authorization=ownInvocationAuthorization(await context.callbacks.authorizationFor(
        Object.freeze({operation:NOTION_PROPERTY_READ_OPERATION,index,originalRequest:request})));
      if((authorization.scope as NotionReadScope).operation!==NOTION_PROPERTY_READ_OPERATION||
        !invocationBindingsMatch(authorization.scope,context.scope))fail('ForeignNotionPropertyAuthorization');
      await verify();
      const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
        callResource:(options:ResourceOptions)=>callHttpsCredentialResource({...options,currentBeforeSend:verify}),
        operation:NOTION_PROPERTY_READ_OPERATION,method:'GET',path,query,
        headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
        responseHeaders:[],maxResponseBytes:bounds.maxResponseBytes,signal}) as NotionReadObservation;
      observations.push(response);received(response);
      const charge=await context.callbacks.chargeResponse(response.body);
      // A terminal value receives this exact original ticket. Its parent may
      // consume it with the completed row only after assembling/checking every
      // required original field; no synthetic output bytes are transfer input.
      await verify();
      if(response.body.byteLength>bounds.maxTotalResponseBytes-totalBytes)fail('NotionPropertyResponseLimit');
      totalBytes+=response.body.byteLength;
      if(!response.accepted||response.statusCode!==200)fail('NotionPropertyReadRejected');
      const page=checked(call('notionProjectPropertyItemPage',request,response.body));
      if(call('notionPropertyItemPageComplete',page)){
        const valueWire=complete(page,bounds);
        await verify();
        await context.callbacks.consumeValue(valueWire,Object.freeze({charge,originalRequest:request,completedPage:page}));
        await verify();
        return Object.freeze({valueWire,completedPage:page,pages:index+1,observations:Object.freeze(observations.slice())});
      }
      await context.callbacks.consumeObservation(charge);
      await verify();
      if(index+1===bounds.maxPages)fail('NotionPropertyPageLimit');
      request=checked(call('notionNextPropertyRequest',page));
    }
    fail('NotionPropertyPageLimit');
  }catch(cause){throw new NotionPropertyReadFailure(cause,observations);}
}

function originalReader(handle:object){const state=readers.get(handle);if(!state)fail('ForeignNotionPropertyReader');return state;}

function createPropertyReader(options:Options,title:boolean){
  const original=prepareRead(options,title),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state:PropertyState={prepared:Object.freeze({...original,signal}),stop,phase:'ready',receivedResponses:0,receivedBodyBytes:0n};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);
      if(state.phase!=='ready')fail('NotionPropertyReaderAlreadyStarted');
      state.phase='reading';
      try{const result=await executeRead(state.prepared,response=>{state.receivedResponses++;state.receivedBodyBytes+=BigInt(response.body.byteLength);});state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason?:unknown){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.prepared.signal.aborted,receivedResponses:state.receivedResponses,
      receivedBodyBytes:state.receivedBodyBytes,
      observationCustody:state.receivedResponses===0?'not-observed':'retained',cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}

// The title mode consumes the same original Page selected by Common, with a
// separately authorized property operation. A page GET grant is not reused.
export function createNotionPageTitleReader(options:Omit<Options,'readContracts'|'column'> & Readonly<{pageTitle:unknown}>){return createPropertyReader(options,true);}

export function createNotionPropertyReader(options:Omit<Options,'pageTitle'> & Readonly<{readContracts:unknown;column:number}>){return createPropertyReader(options,false);}
