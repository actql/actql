// Original exact-page GET -> same checked schema/row -> original property
// completion. This sequencing does not issue a target, Run, grant or capacity.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationScopeFields,
  invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {createNotionPageReader,NOTION_PAGE_READ_OPERATION} from './page-read.mjs';
import {createNotionPropertyReader,NOTION_PROPERTY_READ_OPERATION} from './property-item-read.mjs';
import type {NotionPageBindings} from './page-read.mjs';
import type {NotionPropertyBindings,NotionPropertySelection,NotionReadObservation,NotionReadPhase,NotionReadScope}
  from './property-item-read.mjs';

const readers=new WeakMap<object,PropertiesState>();
const fail:(code:string)=>never=code=>{throw Object.assign(new Error(code),{code});};
const count=(x:number)=>Number.isSafeInteger(x)&&x>=0&&x<=2147483647;
const positive=(x:number)=>count(x)&&x>0;
const names=['notionProjectPage','notionPageMetadataJson','notionDataSourceReadMatches',
  'notionDataSourceReadSchemaJson','notionStartObservedPageReadRow','notionReadRowMatchesObservedPage',
  'notionReadRowPendingJson','notionStartReadRowPropertyRequest','notionCompleteReadRowProperty','notionReadRowJson',
  'notionPropertyRequestMatchesBinding','notionPropertyRequestJson','notionProjectPropertyItemPage',
  'notionPropertyItemPageComplete','notionNextPropertyRequest','notionCompletedPropertyJson'] as const;
const positiveFields=['maxRequestBytes','maxResponseBytes','maxTotalResponseBytes','maxTargetBytes',
  'maxNodes','maxDepth','maxIdentityBytes','maxTextBytes','maxRowNodes','maxRowDepth','maxRowTextBytes',
  'maxColumns','maxRowWork','maxPropertyPages','maxPropertyBytes','maxPropertyNodes','maxPropertyTextBytes',
  'maxCursorBytes','maxPropertyWork','pageSize','maxWireBytes','maxWireNodes','maxWireDepth'] as const;

type Limits = Readonly<Record<typeof positiveFields[number]|'maxDataSources'|'maxProperties'|'maxNameBytes'|'maxPropertyItems',number>>;
type ReadOperation = typeof NOTION_PAGE_READ_OPERATION | typeof NOTION_PROPERTY_READ_OPERATION;
type Child = ReturnType<typeof createNotionPageReader> | ReturnType<typeof createNotionPropertyReader>;
type ChildResult = Awaited<ReturnType<Child['read']>>;
type PropertyReference = Pick<NotionPropertySelection,'originalRequest'|'index'> & Readonly<{column:number}>;
type RowOriginal = Readonly<{charge:unknown; originalPage:unknown; originalRow:unknown; readContracts:unknown}>;
type Callbacks = Readonly<{
  propertyAuthorizationFor?(selection:PropertyReference & Omit<RowOriginal,'charge'> & Readonly<{
    declaration:unknown;source:unknown;operation:typeof NOTION_PROPERTY_READ_OPERATION;origin:unknown;
  }>):unknown;
  current(operation:ReadOperation):unknown;
  chargeResponse(body:NotionReadObservation['body']):unknown;
  consumeObservation(charge:unknown):unknown;
  consumeRow(wire:string, original:RowOriginal):unknown;
}>;
type Bindings = NotionPageBindings & Omit<NotionPropertyBindings,
  'notionPropertyRequestMatchesPageTitle'|'notionCompletedPageTitleJson'> & Readonly<{
  notionDataSourceReadMatches(binding:unknown,declaration:unknown,source:unknown):boolean;
  notionDataSourceReadSchemaJson(binding:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionStartObservedPageReadRow(binding:unknown,page:unknown,maxProperties:number,maxIdentityBytes:number,
    maxNodes:number,maxDepth:number,maxTextBytes:number,maxColumns:number,maxWork:number):unknown;
  notionReadRowMatchesObservedPage(row:unknown,binding:unknown,page:unknown):boolean;
  notionReadRowPendingJson(row:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionStartReadRowPropertyRequest(row:unknown,column:number,maxBytes:number,maxNodes:number,maxDepth:number,
    maxDataSources:number,maxProperties:number,maxIdentityBytes:number,maxNameBytes:number,maxPages:number,
    maxItems:number,maxTotalBytes:number,maxTotalNodes:number,maxTotalTextBytes:number,maxCursorBytes:number,
    maxWork:number):unknown;
  notionCompleteReadRowProperty(row:unknown,column:number,page:unknown):unknown;
  notionReadRowJson(row:unknown,bytes:number,nodes:number,depth:number):unknown;
}>;
type Options = Callbacks & Readonly<{
  moon:Partial<Bindings>|undefined;declaration:unknown;source:unknown;readContracts:unknown;pageId:string;
  initialAuthorization:unknown;credential:unknown;limits:Limits;signal?:AbortSignal;
}>;
type Invocation = ReturnType<typeof ownInvocationContext> & Readonly<{limits:Limits;callbacks:Callbacks}>;
type PropertiesState = {
  original:ReturnType<typeof prepare> & Readonly<{signal:AbortSignal}>;
  stop:AbortController;phase:NotionReadPhase;page:unknown;row:unknown;
  children:Child[];results:ChildResult[];charges:unknown[];failure:NotionPagePropertiesReadFailure|undefined;
};

export class NotionPagePropertiesReadFailure extends Error{
  declare readonly code:'NotionPagePropertiesReadFailed';
  declare readonly originalPage:unknown;
  declare readonly originalRow:unknown;
  declare readonly children:readonly Child[];
  declare readonly responseCharges:readonly unknown[];

  constructor(cause:unknown,originalPage:unknown,originalRow:unknown,children:readonly Child[],responseCharges:readonly unknown[]){
    super('NotionPagePropertiesReadFailed',{cause});this.code='NotionPagePropertiesReadFailed';
    Object.defineProperties(this,{originalPage:{value:originalPage},originalRow:{value:originalRow},
      children:{value:Object.freeze(children.slice())},responseCharges:{value:Object.freeze(responseCharges.slice())}});
  }
}

function prepare({moon,declaration,source,readContracts,pageId,initialAuthorization,credential,
  propertyAuthorizationFor,current,chargeResponse,consumeObservation,consumeRow,limits,signal}:Options){
  if(!declaration||!source||!readContracts||[current,chargeResponse,consumeObservation,consumeRow]
    .some(x=>typeof x!=='function')||propertyAuthorizationFor!==undefined&&typeof propertyAuthorizationFor!=='function')fail('InvalidNotionPagePropertiesRead');
  // Capture every compiled method and its original receiver once. Child
  // readers receive only this frozen snapshot, never later mutable getters.
  const provider=Object.freeze(Object.fromEntries(names.map(name=>{
    const fn=moon?.[name];if(typeof fn!=='function')fail('InvalidNotionPagePropertiesRead');
    return[name,(...args:unknown[])=>Reflect.apply(fn,moon,args)];
  }))) as Bindings;
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{propertyAuthorizationFor,current,chargeResponse,consumeObservation,consumeRow}}) as Invocation,b=context.limits;
  if(!positiveFields.every(name=>positive(b[name]))||
    !(['maxDataSources','maxProperties','maxNameBytes','maxPropertyItems'] as const).every(name=>count(b[name]))||
    b.pageSize>100||!context.credential.binding)fail('InvalidNotionPagePropertiesRead');
  if((invocationScopeFields(context.scope,context.credential.control) as NotionReadScope).operation!==NOTION_PAGE_READ_OPERATION)fail('ForeignNotionPageOperation');
  if(provider.notionDataSourceReadMatches(readContracts,declaration,source)!==true)fail('ForeignNotionReadContracts');
  const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string;
  return Object.freeze({provider,context,declaration,source,readContracts,pageId,schemaWire,signal});
}

async function executeRead(state:PropertiesState){
  const {provider,context,declaration,source,readContracts,pageId,schemaWire,signal}=state.original,b=context.limits;
  let totalBytes=0,pendingCharge:unknown;
  const verify=async (operation:ReadOperation)=>{signal.throwIfAborted();await context.callbacks.current(operation);signal.throwIfAborted();};
  const chargeResponse=async (body:NotionReadObservation['body'])=>{
    const charge=await context.callbacks.chargeResponse(body);state.charges.push(charge);
    if(body.byteLength>b.maxTotalResponseBytes-totalBytes)fail('NotionPagePropertiesResponseLimit');
    totalBytes+=body.byteLength;return charge;
  };
  const propertyAuthorization=async (input:PropertyReference)=>{
    if(context.callbacks.propertyAuthorizationFor===undefined)fail('NotionPropertyAuthorizationUnavailable');
    await verify(NOTION_PROPERTY_READ_OPERATION);
    const selected=ownInvocationAuthorization(await context.callbacks.propertyAuthorizationFor(Object.freeze({
      ...input,originalPage:state.page,originalRow:state.row,declaration,source,readContracts,
      operation:NOTION_PROPERTY_READ_OPERATION,origin:(invocationScopeFields(context.scope,context.credential.control) as NotionReadScope).resourceOrigin,
    })),context.credential.control);
    if((invocationScopeFields(selected.scope,context.credential.control) as NotionReadScope).operation!==NOTION_PROPERTY_READ_OPERATION||
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
    const pending=JSON.parse(checked(provider.notionReadRowPendingJson(state.row,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string) as number[];
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
    const wire=checked(provider.notionReadRowJson(state.row,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string;
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

function originalReader(handle:object){const state=readers.get(handle);if(!state)fail('ForeignNotionPagePropertiesReader');return state;}

export function createNotionPagePropertiesReader(options:Options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state:PropertiesState={original:Object.freeze({...original,signal}),stop,phase:'ready',page:undefined,row:undefined,
    children:[],results:[],charges:[],failure:undefined};
  const handle=Object.freeze({
    async read(){const state=originalReader(this);if(state.phase!=='ready')fail('NotionPagePropertiesAlreadyStarted');
      state.phase='reading';try{const result=await executeRead(state);state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}},
    requestStop(reason?:unknown){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);let receivedResponses=0,receivedBodyBytes=0n;
      for(const child of state.children){const observation=child.observe();receivedResponses+=observation.receivedResponses;receivedBodyBytes+=observation.receivedBodyBytes;}
      return Object.freeze({phase:state.phase,stopRequested:state.original.signal.aborted,receivedResponses,receivedBodyBytes,cleanupConfirmed:false});},
  });readers.set(handle,state);return handle;
}
