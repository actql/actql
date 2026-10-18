// Original exact-page GET -> same checked schema/row -> original property
// completion. This sequencing does not issue a target, Run, grant or capacity.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationScopeFields,
  invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {createNotionPageReader,NOTION_PAGE_READ_OPERATION} from './page-read.mjs';
import {createNotionPropertyReader,NOTION_PROPERTY_READ_OPERATION} from './property-item-read.mjs';

const readers=new WeakMap();
const fail=code=>{throw Object.assign(new Error(code),{code});};
const count=x=>Number.isSafeInteger(x)&&x>=0&&x<=2147483647;
const positive=x=>count(x)&&x>0;
const names=['notionProjectPage','notionPageMetadataJson','notionDataSourceReadMatches',
  'notionDataSourceReadSchemaJson','notionStartObservedPageReadRow','notionReadRowMatchesObservedPage',
  'notionReadRowPendingJson','notionStartReadRowPropertyRequest','notionCompleteReadRowProperty','notionReadRowJson',
  'notionPropertyRequestMatchesBinding','notionPropertyRequestJson','notionProjectPropertyItemPage',
  'notionPropertyItemPageComplete','notionNextPropertyRequest','notionCompletedPropertyJson'];
const positiveFields=['maxRequestBytes','maxResponseBytes','maxTotalResponseBytes','maxTargetBytes',
  'maxNodes','maxDepth','maxIdentityBytes','maxTextBytes','maxRowNodes','maxRowDepth','maxRowTextBytes',
  'maxColumns','maxRowWork','maxPropertyPages','maxPropertyBytes','maxPropertyNodes','maxPropertyTextBytes',
  'maxCursorBytes','maxPropertyWork','pageSize','maxWireBytes','maxWireNodes','maxWireDepth'];

export class NotionPagePropertiesReadFailure extends Error{
  constructor(cause,originalPage,originalRow,children,responseCharges){
    super('NotionPagePropertiesReadFailed',{cause});this.code='NotionPagePropertiesReadFailed';
    Object.defineProperties(this,{originalPage:{value:originalPage},originalRow:{value:originalRow},
      children:{value:Object.freeze(children.slice())},responseCharges:{value:Object.freeze(responseCharges.slice())}});
  }
}

function prepare({moon,declaration,source,readContracts,pageId,initialAuthorization,credential,
  propertyAuthorizationFor,current,chargeResponse,consumeObservation,consumeRow,limits,signal}){
  if(!declaration||!source||!readContracts||[current,chargeResponse,consumeObservation,consumeRow]
    .some(x=>typeof x!=='function')||propertyAuthorizationFor!==undefined&&typeof propertyAuthorizationFor!=='function')fail('InvalidNotionPagePropertiesRead');
  // Capture every compiled method and its original receiver once. Child
  // readers receive only this frozen snapshot, never later mutable getters.
  const provider=Object.freeze(Object.fromEntries(names.map(name=>{
    const fn=moon?.[name];if(typeof fn!=='function')fail('InvalidNotionPagePropertiesRead');
    return[name,(...args)=>Reflect.apply(fn,moon,args)];
  })));
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{propertyAuthorizationFor,current,chargeResponse,consumeObservation,consumeRow}}),b=context.limits;
  if(!positiveFields.every(name=>positive(b[name]))||
    !['maxDataSources','maxProperties','maxNameBytes','maxPropertyItems'].every(name=>count(b[name]))||
    b.pageSize>100||!context.credential.binding)fail('InvalidNotionPagePropertiesRead');
  if(invocationScopeFields(context.scope,context.credential.control).operation!==NOTION_PAGE_READ_OPERATION)fail('ForeignNotionPageOperation');
  if(provider.notionDataSourceReadMatches(readContracts,declaration,source)!==true)fail('ForeignNotionReadContracts');
  const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth));
  return Object.freeze({provider,context,declaration,source,readContracts,pageId,schemaWire,signal});
}

async function executeRead(state){
  const {provider,context,declaration,source,readContracts,pageId,schemaWire,signal}=state.original,b=context.limits;
  let totalBytes=0,pendingCharge;
  const verify=async operation=>{signal.throwIfAborted();await context.callbacks.current(operation);signal.throwIfAborted();};
  const chargeResponse=async body=>{
    const charge=await context.callbacks.chargeResponse(body);state.charges.push(charge);
    if(body.byteLength>b.maxTotalResponseBytes-totalBytes)fail('NotionPagePropertiesResponseLimit');
    totalBytes+=body.byteLength;return charge;
  };
  const propertyAuthorization=async input=>{
    if(context.callbacks.propertyAuthorizationFor===undefined)fail('NotionPropertyAuthorizationUnavailable');
    await verify(NOTION_PROPERTY_READ_OPERATION);
    const selected=ownInvocationAuthorization(await context.callbacks.propertyAuthorizationFor(Object.freeze({
      ...input,originalPage:state.page,originalRow:state.row,declaration,source,readContracts,
      operation:NOTION_PROPERTY_READ_OPERATION,origin:invocationScopeFields(context.scope,context.credential.control).resourceOrigin,
    })),context.credential.control);
    if(invocationScopeFields(selected.scope,context.credential.control).operation!==NOTION_PROPERTY_READ_OPERATION||
      !invocationBindingsMatch(selected.scope,context.scope,context.credential.control))fail('ForeignNotionPropertyAuthorization');
    await verify(NOTION_PROPERTY_READ_OPERATION);return selected;
  };
  try{
    const child=createNotionPageReader({moon:provider,pageId,initialAuthorization:context.authorization,
      credential:context.credential,limits:b,signal,current:()=>verify(NOTION_PAGE_READ_OPERATION),chargeResponse,
      // Keep this exact response ticket for the enclosing complete row. It is
      // not consumed or released merely because the metadata child returned.
      consumeObservation:charge=>{pendingCharge=charge;}});
    state.children.push(child);const result=await child.read();state.results.push(result);state.page=result.page;
    state.row=checked(provider.notionStartObservedPageReadRow(readContracts,result.page,b.maxProperties,b.maxIdentityBytes,
      b.maxRowNodes,b.maxRowDepth,b.maxRowTextBytes,b.maxColumns,b.maxRowWork));
    const pending=JSON.parse(checked(provider.notionReadRowPendingJson(state.row,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)));
    for(const column of pending){
      const request=checked(provider.notionStartReadRowPropertyRequest(state.row,column,
        b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,b.maxIdentityBytes,b.maxNameBytes,
        b.maxPropertyPages,b.maxPropertyItems,b.maxPropertyBytes,b.maxPropertyNodes,b.maxPropertyTextBytes,b.maxCursorBytes,b.maxPropertyWork));
      const first=await propertyAuthorization({originalRequest:request,column,index:0});
      await context.callbacks.consumeObservation(pendingCharge);pendingCharge=undefined;
      const property=createNotionPropertyReader({moon:provider,originalRequest:request,readContracts,column,
        initialAuthorization:first,credential:context.credential,signal,current:verify,chargeResponse,
        authorizationFor:input=>input.index===0?first:propertyAuthorization({...input,column}),
        consumeObservation:context.callbacks.consumeObservation,
        consumeValue:(_wire,{charge,completedPage})=>{
          checked(provider.notionCompleteReadRowProperty(state.row,column,completedPage));pendingCharge=charge;
        },limits:{maxResponseBytes:b.maxResponseBytes,maxTotalResponseBytes:b.maxPropertyBytes,maxTargetBytes:b.maxTargetBytes,
          maxPages:b.maxPropertyPages,pageSize:b.pageSize,maxValueNodes:b.maxRowNodes,maxValueDepth:b.maxRowDepth,
          maxValueTextBytes:b.maxRowTextBytes,maxWireBytes:b.maxWireBytes,maxWireNodes:b.maxWireNodes,maxWireDepth:b.maxWireDepth}});
      state.children.push(property);state.results.push(await property.read());
    }
    if(provider.notionReadRowMatchesObservedPage(state.row,readContracts,state.page)!==true)fail('ForeignNotionObservedRow');
    const wire=checked(provider.notionReadRowJson(state.row,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth));
    if(pendingCharge===undefined)fail('NotionPagePropertiesObservationUnbound');
    await verify(NOTION_PAGE_READ_OPERATION);
    await context.callbacks.consumeRow(wire,Object.freeze({charge:pendingCharge,originalPage:state.page,
      originalRow:state.row,readContracts}));
    await verify(NOTION_PAGE_READ_OPERATION);
    return Object.freeze({wire,schemaWire,originalPage:state.page,originalRow:state.row,readContracts,
      children:Object.freeze(state.children.slice()),responseCharges:Object.freeze(state.charges.slice())});
  }catch(cause){
    state.failure=new NotionPagePropertiesReadFailure(cause,state.page,state.row,state.children,state.charges);throw state.failure;
  }
}

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionPagePropertiesReader');return state;}

export function createNotionPagePropertiesReader(options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state={original:Object.freeze({...original,signal}),stop,phase:'ready',page:undefined,row:undefined,
    children:[],results:[],charges:[],failure:undefined};
  const handle=Object.freeze({
    async read(){const state=originalReader(this);if(state.phase!=='ready')fail('NotionPagePropertiesAlreadyStarted');
      state.phase='reading';try{const result=await executeRead(state);state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}},
    requestStop(reason){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);let receivedResponses=0,receivedBodyBytes=0n;
      for(const child of state.children){const observation=child.observe();receivedResponses+=observation.receivedResponses;receivedBodyBytes+=observation.receivedBodyBytes;}
      return Object.freeze({phase:state.phase,stopRequested:state.original.signal.aborted,receivedResponses,receivedBodyBytes,cleanupConfirmed:false});},
  });readers.set(handle,state);return handle;
}
