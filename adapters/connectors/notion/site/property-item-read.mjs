// Physical sequencing only. Common owns original property/cursor/checked-value
// meaning; Credential owns each original use. Raw aliases retain cleanup debt.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const NOTION_PROPERTY_READ_OPERATION='notion:pages:property:read';
export const NOTION_PROPERTY_READ_API_VERSION='2026-03-11';
const readers=new WeakMap();
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=x=>Number.isSafeInteger(x)&&x>0&&x<=2147483647;
const sharedPorts=['notionPropertyRequestJson','notionProjectPropertyItemPage',
  'notionPropertyItemPageComplete','notionNextPropertyRequest'];
const fields=['maxResponseBytes','maxTotalResponseBytes','maxTargetBytes','maxPages','pageSize',
  'maxValueNodes','maxValueDepth','maxValueTextBytes','maxWireBytes','maxWireNodes','maxWireDepth'];

export class NotionPropertyReadFailure extends Error {
  constructor(cause,observations){
    super('NotionPropertyReadFailed',{cause});this.code='NotionPropertyReadFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
  }
}

// Returned property ids are already URI-encoded. Preserve original percent
// escapes rather than encode them again; encode other original code points.
// A dot-only coordinate is unavailable at this physical path boundary.
function originalPathSegment(text){
  if(typeof text!=='string'||text.length===0||text==='.'||text==='..')fail('InvalidNotionPropertyCoordinate');
  let result='';
  for(let i=0;i<text.length;){
    if(text[i]==='%'&&/^[0-9A-Fa-f]{2}$/u.test(text.slice(i+1,i+3))){result+=text.slice(i,i+3);i+=3;}
    else{const point=String.fromCodePoint(text.codePointAt(i));result+=encodeURIComponent(point);i+=point.length;}
  }
  // Percent-encoded dot segments have the same URL routing hazard. This is
  // physical target validation, not a ban on a logical property name/id.
  if(/^((%2[eE])|\.){1,2}$/u.test(result))fail('InvalidNotionPropertyCoordinate');
  return result;
}

function captureProjection(moon,readContracts,column,pageTitle,title){
  const matchesPort=title?'notionPropertyRequestMatchesPageTitle':'notionPropertyRequestMatchesBinding';
  const completePort=title?'notionCompletedPageTitleJson':'notionCompletedPropertyJson';
  const names=[...sharedPorts,matchesPort,completePort];
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,moon?.[name]])));
  const call=(name,...args)=>Reflect.apply(provider[name],moon,args);
  const matches=request=>title?call(matchesPort,request,pageTitle)===true:
    call(matchesPort,request,readContracts,column)===true;
  const complete=(page,b)=>checked(call(completePort,...(title?[pageTitle,page]:[readContracts,page,column]),
    b.maxValueNodes,b.maxValueDepth,b.maxValueTextBytes,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth));
  return Object.freeze({names,provider,call,matches,complete});
}

function describePropertyRequest(call,request,bounds){
  const target=JSON.parse(checked(call('notionPropertyRequestJson',request,bounds.maxWireBytes,bounds.maxWireNodes,bounds.maxWireDepth)));
  if(Object.keys(target).length!==3||typeof target.pageId!=='string'||typeof target.propertyId!=='string'||
    target.cursor!==null&&typeof target.cursor!=='string')fail('InvalidNotionPropertyRequest');
  const path='/v1/pages/'+originalPathSegment(target.pageId)+'/properties/'+originalPathSegment(target.propertyId);
  const query=[['page_size',String(bounds.pageSize)]];
  if(target.cursor!==null)query.push(['start_cursor',target.cursor]);
  if(Buffer.byteLength(requestTarget(path,query))>bounds.maxTargetBytes)fail('NotionPropertyTargetLimit');
  return {path,query};
}

function projectPropertyPage(call,request,response){
  if(!response.accepted||response.statusCode!==200)fail('NotionPropertyReadRejected');
  return checked(call('notionProjectPropertyItemPage',request,response.body));
}

// Provider meaning for the actual shared read child. The caller retains the
// original response/charge and enforces its total bytes/page bounds. These
// DATA projections issue no use, replace no current check and own no cleanup.
export function prepareNotionPropertyReadProjection({moon,originalRequest,readContracts,column,pageTitle,limits}){
  const title=pageTitle!==undefined;
  if(!originalRequest||(title?(!pageTitle||readContracts!==undefined||column!==undefined):
    (!readContracts||!Number.isSafeInteger(column)||column<0||column>2147483647))||
    !limits||typeof limits!=='object')fail('InvalidNotionPropertyRead');
  const {names,provider,call,matches,complete}=captureProjection(moon,readContracts,column,pageTitle,title);
  const bounds=Object.freeze({...limits});
  if(names.some(name=>typeof provider[name]!=='function')||!fields.every(name=>positive(bounds[name]))||
    bounds.pageSize>100)fail('InvalidNotionPropertyRead');
  if(!matches(originalRequest))fail('ForeignNotionPropertyOriginal');
  return Object.freeze({
    describeRequest(request=originalRequest){
      if(!matches(request))fail('ForeignNotionPropertyOriginal');
      return Object.freeze({method:'GET',...describePropertyRequest(call,request,bounds),
        headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],responseHeaders:[]});
    },
    projectResponse(request,response){
      if(!matches(request))fail('ForeignNotionPropertyOriginal');
      const page=projectPropertyPage(call,request,response);
      if(call('notionPropertyItemPageComplete',page))return Object.freeze({page,done:true,valueWire:complete(page,bounds)});
      // Defer the existing cursor derivation until the parent has consumed
      // this exact prefix charge and checked its original page/current bound.
      return Object.freeze({page,done:false,nextRequest(){
        const next=checked(call('notionNextPropertyRequest',page));
        if(!matches(next))fail('ForeignNotionPropertyOriginal');
        return next;
      }});
    },
  });
}

function prepareRead({moon,originalRequest,readContracts,column,pageTitle,initialAuthorization,
  credential,authorizationFor,current,chargeResponse,consumeObservation,consumeValue,limits,signal},title){
  if(!originalRequest||(title?(!pageTitle||readContracts!==undefined||column!==undefined):
    (!readContracts||pageTitle!==undefined||!Number.isSafeInteger(column)||column<0||column>2147483647))||
    [authorizationFor,current,chargeResponse,consumeObservation,consumeValue].some(x=>typeof x!=='function'))fail('InvalidNotionPropertyRead');
  const {names,provider,call,matches,complete}=captureProjection(moon,readContracts,column,pageTitle,title);
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumeValue}});
  if(names.some(name=>typeof provider[name]!=='function')||!fields.every(name=>positive(context.limits[name]))||
    context.limits.pageSize>100||!context.credential.binding)fail('InvalidNotionPropertyRead');
  if(context.scope.operation!==NOTION_PROPERTY_READ_OPERATION)fail('ForeignNotionPropertyOperation');
  if(!matches(originalRequest))fail('ForeignNotionPropertyOriginal');
  return Object.freeze({call,matches,complete,context,originalRequest,readContracts,column,pageTitle,signal});
}

async function executeRead(prepared,received){
  const {call,matches,complete,context,signal}=prepared,bounds=context.limits;
  const observations=[];let request=prepared.originalRequest,totalBytes=0;
  const verify=async()=>{signal.throwIfAborted();await context.callbacks.current(NOTION_PROPERTY_READ_OPERATION);signal.throwIfAborted();
    if(!matches(request))fail('ForeignNotionPropertyOriginal');};
  try{
    for(let index=0;index<bounds.maxPages;index++){
      await verify();
      const {path,query}=describePropertyRequest(call,request,bounds);
      const authorization=ownInvocationAuthorization(await context.callbacks.authorizationFor(
        Object.freeze({operation:NOTION_PROPERTY_READ_OPERATION,index,originalRequest:request})));
      if(authorization.scope.operation!==NOTION_PROPERTY_READ_OPERATION||
        !invocationBindingsMatch(authorization.scope,context.scope))fail('ForeignNotionPropertyAuthorization');
      await verify();
      const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
        callResource:options=>callHttpsCredentialResource({...options,currentBeforeSend:verify}),
        operation:NOTION_PROPERTY_READ_OPERATION,method:'GET',path,query,
        headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
        responseHeaders:[],maxResponseBytes:bounds.maxResponseBytes,signal});
      observations.push(response);received(response);
      const charge=await context.callbacks.chargeResponse(response.body);
      // A terminal value receives this exact original ticket. Its parent may
      // consume it with the completed row only after assembling/checking every
      // required original field; no synthetic output bytes are transfer input.
      await verify();
      if(response.body.byteLength>bounds.maxTotalResponseBytes-totalBytes)fail('NotionPropertyResponseLimit');
      totalBytes+=response.body.byteLength;
      const page=projectPropertyPage(call,request,response);
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

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionPropertyReader');return state;}

function createPropertyReader(options,title){
  const original=prepareRead(options,title),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state={prepared:Object.freeze({...original,signal}),stop,phase:'ready',receivedResponses:0,receivedBodyBytes:0n};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);
      if(state.phase!=='ready')fail('NotionPropertyReaderAlreadyStarted');
      state.phase='reading';
      try{const result=await executeRead(state.prepared,response=>{state.receivedResponses++;state.receivedBodyBytes+=BigInt(response.body.byteLength);});state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.prepared.signal.aborted,receivedResponses:state.receivedResponses,
      receivedBodyBytes:state.receivedBodyBytes,
      observationCustody:state.receivedResponses===0?'not-observed':'retained',cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}

// The title mode consumes the same original Page selected by Common, with a
// separately authorized property operation. A page GET grant is not reused.
export function createNotionPageTitleReader(options){return createPropertyReader(options,true);}

export function createNotionPropertyReader(options){return createPropertyReader(options,false);}
