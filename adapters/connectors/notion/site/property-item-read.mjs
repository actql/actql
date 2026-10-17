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
const exports=['notionPropertyRequestMatchesBinding','notionPropertyRequestJson',
  'notionProjectPropertyItemPage','notionPropertyItemPageComplete',
  'notionNextPropertyRequest','notionCompletedPropertyJson'];
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

function prepareRead({moon,originalRequest,readContracts,column,initialAuthorization,
  credential,authorizationFor,current,chargeResponse,consumeObservation,consumeValue,limits,signal}){
  if(!originalRequest||!readContracts||!Number.isSafeInteger(column)||column<0||column>2147483647||
    [authorizationFor,current,chargeResponse,consumeObservation,consumeValue].some(x=>typeof x!=='function'))fail('InvalidNotionPropertyRead');
  const provider=Object.freeze(Object.fromEntries(exports.map(name=>[name,moon?.[name]])));
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumeValue}});
  if(exports.some(name=>typeof provider[name]!=='function')||!fields.every(name=>positive(context.limits[name]))||
    context.limits.pageSize>100||!context.credential.binding)fail('InvalidNotionPropertyRead');
  if(context.scope.operation!==NOTION_PROPERTY_READ_OPERATION)fail('ForeignNotionPropertyOperation');
  if(!provider.notionPropertyRequestMatchesBinding(originalRequest,readContracts,column))fail('ForeignNotionPropertyOriginal');
  return Object.freeze({provider,context,originalRequest,readContracts,column,signal});
}

async function executeRead(prepared,received){
  const {provider,context,readContracts,column,signal}=prepared,bounds=context.limits;
  const observations=[];let request=prepared.originalRequest,totalBytes=0;
  const verify=async()=>{signal.throwIfAborted();await context.callbacks.current(NOTION_PROPERTY_READ_OPERATION);signal.throwIfAborted();};
  try{
    for(let index=0;index<bounds.maxPages;index++){
      await verify();
      const target=JSON.parse(checked(provider.notionPropertyRequestJson(request,bounds.maxWireBytes,bounds.maxWireNodes,bounds.maxWireDepth)));
      if(Object.keys(target).length!==3||typeof target.pageId!=='string'||typeof target.propertyId!=='string'||
        target.cursor!==null&&typeof target.cursor!=='string')fail('InvalidNotionPropertyRequest');
      const path='/v1/pages/'+originalPathSegment(target.pageId)+'/properties/'+originalPathSegment(target.propertyId);
      const query=[['page_size',String(bounds.pageSize)]];
      if(target.cursor!==null)query.push(['start_cursor',target.cursor]);
      if(Buffer.byteLength(requestTarget(path,query))>bounds.maxTargetBytes)fail('NotionPropertyTargetLimit');
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
      if(!response.accepted||response.statusCode!==200)fail('NotionPropertyReadRejected');
      const page=checked(provider.notionProjectPropertyItemPage(request,response.body));
      if(provider.notionPropertyItemPageComplete(page)){
        const valueWire=checked(provider.notionCompletedPropertyJson(readContracts,page,column,
          bounds.maxValueNodes,bounds.maxValueDepth,bounds.maxValueTextBytes,
          bounds.maxWireBytes,bounds.maxWireNodes,bounds.maxWireDepth));
        await verify();
        await context.callbacks.consumeValue(valueWire,Object.freeze({charge,originalRequest:request}));
        await verify();
        return Object.freeze({valueWire,pages:index+1,observations:Object.freeze(observations.slice())});
      }
      await context.callbacks.consumeObservation(charge);
      if(index+1===bounds.maxPages)fail('NotionPropertyPageLimit');
      request=checked(provider.notionNextPropertyRequest(page));
    }
    fail('NotionPropertyPageLimit');
  }catch(cause){throw new NotionPropertyReadFailure(cause,observations);}
}

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionPropertyReader');return state;}

export function createNotionPropertyReader(options){
  const original=prepareRead(options),stop=new AbortController();
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
