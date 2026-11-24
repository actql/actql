// Common owns the original schema, property completion and full checked row.
// This caller sequences scoped I/O and original charge custody, not admission
// authority or a numerical capacity/retirement supplier.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {createNotionPropertyReader,NOTION_PROPERTY_READ_OPERATION,
  NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';
import type {NotionPropertyBindings,NotionPropertyReadFailure,NotionPropertySelection,NotionReadObservation,
  NotionReadPhase,NotionReadScope} from './property-item-read.mjs';

export const NOTION_DATA_SOURCE_READ_OPERATION='notion:data-sources:query';
const readers=new WeakMap<object,ReaderState>();
const fail:(code:string)=>never=code=>{throw Object.assign(new Error(code),{code});};
const positive=(x:number)=>Number.isSafeInteger(x)&&x>0&&x<=2147483647;
const required=['notionDataSourceReadMatches','notionDataSourceMetadataJson','notionDataSourceReadSchemaJson',
  'notionProjectQueryPage','notionQueryPageMetadataJson','notionStartReadRow','notionReadRowPendingJson',
  'notionStartColumnPropertyRequest','notionCompleteReadRowProperty','notionReadPageRowsJson'] as const;
const fields=['maxResponseBytes','maxTotalResponseBytes','maxRequestBytes','maxTargetBytes',
  'maxPages','pageSize','maxTotalRows','maxNodes','maxDepth','maxDataSources','maxProperties',
  'maxIdentityBytes','maxNameBytes','maxCursorBytes','maxRowNodes','maxRowDepth','maxRowTextBytes',
  'maxColumns','maxRowWork','maxPageWork','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth',
  'maxPropertyPages','maxPropertyItems','maxPropertyBytes','maxPropertyNodes','maxPropertyTextBytes','maxPropertyWork'] as const;

type Limits = Readonly<Record<typeof fields[number],number>>;
type Operation = typeof NOTION_DATA_SOURCE_READ_OPERATION | typeof NOTION_PROPERTY_READ_OPERATION;
type ResourceOptions = Parameters<typeof callHttpsCredentialResource>[0];
type PropertyReader = ReturnType<typeof createNotionPropertyReader>;
type PageProperty = {reader:PropertyReader;result:Awaited<ReturnType<PropertyReader['read']>>|undefined};
type MetadataLimits = readonly [bytes:number,nodes:number,depth:number,dataSources:number,
  properties:number,identityBytes:number,nameBytes:number];
type AuthorizationInput = Readonly<{operation:typeof NOTION_DATA_SOURCE_READ_OPERATION;index:number}> |
  (NotionPropertySelection & Readonly<{queryIndex:number;rowIndex:number;column:number}>);
type Callbacks = Readonly<{
  authorizationFor(input:AuthorizationInput & Readonly<{ordinal:number}>):unknown;
  current(operation:Operation):unknown;
  chargeResponse(body:NotionReadObservation['body']):unknown;
  consumeObservation(charge:unknown):unknown;
  consumePage(rows:readonly unknown[],original:Readonly<{
    charge:unknown; originalPage:unknown; originalRows:readonly unknown[]; readContracts:unknown;
  }>):unknown;
}>;
type Bindings = Omit<NotionPropertyBindings,'notionPropertyRequestMatchesPageTitle'|'notionCompletedPageTitleJson'> & Readonly<{
  notionDataSourceReadMatches(contracts:unknown,declaration:unknown,source:unknown):boolean;
  notionDataSourceMetadataJson(source:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionDataSourceReadSchemaJson(contracts:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionProjectQueryPage(source:unknown,body:NotionReadObservation['body'],
    ...bounds:[...MetadataLimits,rows:number,cursorBytes:number]):unknown;
  notionQueryPageMetadataJson(page:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionStartReadRow(contracts:unknown,page:unknown,row:number,nodes:number,depth:number,textBytes:number,columns:number,work:number):unknown;
  notionReadRowPendingJson(row:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionStartColumnPropertyRequest(contracts:unknown,page:unknown,row:number,column:number,
    ...bounds:[...MetadataLimits,pages:number,items:number,totalBytes:number,totalNodes:number,totalTextBytes:number,
      cursorBytes:number,work:number]):unknown;
  notionCompleteReadRowProperty(row:unknown,column:number,page:unknown):unknown;
  notionReadPageRowsJson(contracts:unknown,page:unknown,rows:readonly unknown[],valueNodes:number,valueDepth:number,
    valueTextBytes:number,work:number,bytes:number,nodes:number,depth:number):unknown;
}>;
type Options = Callbacks & Readonly<{
  moon:Partial<Bindings>|undefined; declaration:unknown; source:unknown; readContracts:unknown;
  initialAuthorization:unknown; propertyAuthorization?:unknown;
  propertyAuthorizationFor?(selection:Readonly<{
    originalRequest:unknown; declaration:unknown; source:unknown; readContracts:unknown; column:number;
    queryIndex:number; rowIndex:number; operation:typeof NOTION_PROPERTY_READ_OPERATION; origin:unknown;
  }>):unknown;
  credential:unknown; limits:Limits; signal?:AbortSignal;
}>;
type Invocation = ReturnType<typeof ownInvocationContext> & Readonly<{
  scope:NotionReadScope; limits:Limits; callbacks:Callbacks;
}>;
type Prepared = ReturnType<typeof prepareRead> & Readonly<{signal:AbortSignal}>;
type ReaderState = {
  prepared:Prepared; stop:AbortController; phase:NotionReadPhase;
  children:PropertyReader[]; responseCharges:unknown[]; queryResponses:number; queryBytes:bigint;
};

export class NotionDataSourceReadFailure extends Error {
  declare readonly code:'NotionDataSourceReadFailed';
  declare readonly observations:readonly NotionReadObservation[];
  declare readonly children:readonly PageProperty[];
  declare readonly responseCharges:readonly unknown[];

  constructor(cause:unknown,observations:readonly NotionReadObservation[],children:readonly PageProperty[],
    responseCharges:readonly unknown[]){
    super('NotionDataSourceReadFailed',{cause});this.code='NotionDataSourceReadFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
    Object.defineProperty(this,'children',{value:Object.freeze(children.slice())});
    Object.defineProperty(this,'responseCharges',{value:Object.freeze(responseCharges.slice())});
  }
}

function prepareRead({moon,declaration,source,readContracts,initialAuthorization,propertyAuthorization,propertyAuthorizationFor,
  credential,authorizationFor,current,chargeResponse,consumeObservation,consumePage,limits,signal}:Options){
  if(!declaration||!source||!readContracts||
    [authorizationFor,current,chargeResponse,consumeObservation,consumePage].some(x=>typeof x!=='function'))fail('InvalidNotionDataSourceRead');
  if(propertyAuthorizationFor!==undefined&&(typeof propertyAuthorizationFor!=='function'||propertyAuthorization!==undefined))fail('InvalidNotionDataSourceRead');
  // Include the existing property reader's actual functions in the same
  // read-once snapshot, so later getters/config cannot replace its port.
  const names=[...required,'notionPropertyRequestMatchesBinding','notionPropertyRequestJson',
    'notionProjectPropertyItemPage','notionPropertyItemPageComplete','notionNextPropertyRequest','notionCompletedPropertyJson'] as const;
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,moon?.[name]]))) as Bindings;
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation,consumePage}}) as Invocation;
  if(names.some(name=>typeof provider[name]!=='function')||!fields.every(name=>positive(context.limits[name]))||
    context.limits.pageSize>100||!context.credential.binding)fail('InvalidNotionDataSourceRead');
  if(context.scope.operation!==NOTION_DATA_SOURCE_READ_OPERATION)fail('ForeignNotionDataSourceOperation');
  if(!provider.notionDataSourceReadMatches(readContracts,declaration,source))fail('ForeignNotionReadContracts');
  const property=propertyAuthorization===undefined?undefined:ownInvocationAuthorization(propertyAuthorization);
  if(property&&((property.scope as NotionReadScope).operation!==NOTION_PROPERTY_READ_OPERATION||
    !invocationBindingsMatch(property.scope,context.scope)))fail('ForeignNotionPropertyAuthorization');
  const b=context.limits;
  const metadata=JSON.parse(checked(provider.notionDataSourceMetadataJson(source,b.maxRowsWireBytes,b.maxRowsWireNodes,b.maxRowsWireDepth)) as string);
  const id:unknown=metadata.dataSourceId;
  if(typeof id!=='string'||id.length===0||id==='.'||id==='..')fail('InvalidNotionDataSourceCoordinate');
  const path='/v1/data_sources/'+encodeURIComponent(id)+'/query';
  if(Buffer.byteLength(path)>b.maxTargetBytes)fail('NotionDataSourceTargetLimit');
  const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxRowsWireBytes,b.maxRowsWireNodes,b.maxRowsWireDepth)) as string;
  return Object.freeze({provider,context,declaration,source,readContracts,property,propertyAuthorizationFor,path,schemaWire,signal});
}

async function executeRead(prepared:Prepared,state:ReaderState){
  const {provider,context,source,readContracts,property,propertyAuthorizationFor,path,schemaWire,signal}=prepared,b=context.limits;
  const observations:NotionReadObservation[]=[],children:PageProperty[]=[],ids=new Set<string>(),cursors=new Set<string>();
  let totalBytes=0,totalRows=0,cursor:string|undefined,ordinal=0;
  const verify=async (operation:Operation)=>{signal.throwIfAborted();await context.callbacks.current(operation);signal.throwIfAborted();};
  const authorizationFor=async (input:AuthorizationInput)=>{
    const a=ownInvocationAuthorization(await context.callbacks.authorizationFor(Object.freeze({...input,ordinal:ordinal++})));
    if((a.scope as NotionReadScope).operation!==input.operation||!invocationBindingsMatch(a.scope,context.scope))fail('ForeignNotionDataSourceAuthorization');
    return a;
  };
  const chargeResponse=async (body:NotionReadObservation['body'])=>{
    const charge=await context.callbacks.chargeResponse(body);
    // Retain every actually returned original ticket, including when later
    // current/admission/output/callback fails. This is not a consumption or
    // cleanup ACK; the original RowRun/Ledger knows its actual disposition.
    state.responseCharges.push(charge);
    if(body.byteLength>b.maxTotalResponseBytes-totalBytes)fail('NotionDataSourceResponseLimit');
    totalBytes+=body.byteLength;return charge;
  };
  try{
    for(let index=0;index<b.maxPages;index++){
      await verify(NOTION_DATA_SOURCE_READ_OPERATION);
      const remaining=b.maxTotalRows-totalRows;
      if(remaining<=0)fail('NotionDataSourceRowLimit');
      const body=JSON.stringify({page_size:Math.min(b.pageSize,remaining),...(cursor===undefined?{}:{start_cursor:cursor})});
      if(Buffer.byteLength(body)>b.maxRequestBytes)fail('NotionDataSourceRequestLimit');
      const authorization=await authorizationFor({operation:NOTION_DATA_SOURCE_READ_OPERATION,index});
      await verify(NOTION_DATA_SOURCE_READ_OPERATION);
      const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
        callResource:(options:ResourceOptions)=>callHttpsCredentialResource({...options,currentBeforeSend:()=>verify(NOTION_DATA_SOURCE_READ_OPERATION)}),
        operation:NOTION_DATA_SOURCE_READ_OPERATION,method:'POST',path,body,
        headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
        responseHeaders:[],maxRequestBytes:b.maxRequestBytes,maxResponseBytes:b.maxResponseBytes,signal}) as NotionReadObservation;
      observations.push(response);state.queryResponses++;state.queryBytes+=BigInt(response.body.byteLength);
      let pendingCharge=await chargeResponse(response.body);
      await verify(NOTION_DATA_SOURCE_READ_OPERATION);
      if(!response.accepted||response.statusCode!==200)fail('NotionDataSourceReadRejected');
      const metadataLimits:MetadataLimits=[b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,b.maxIdentityBytes,b.maxNameBytes];
      // The original Common response Owner refuses provider-declared incomplete
      // or malformed status before any row/property work. Cursor exhaustion
      // below only ends an already admitted, non-capped query response.
      const page=checked(provider.notionProjectQueryPage(source,response.body,...metadataLimits,b.pageSize,b.maxCursorBytes));
      const metadata=JSON.parse(checked(provider.notionQueryPageMetadataJson(page,b.maxRowsWireBytes,b.maxRowsWireNodes,b.maxRowsWireDepth)) as string) as {ids:string[];nextCursor:string|null};
      if(metadata.ids.length>b.maxTotalRows-totalRows)fail('NotionDataSourceRowLimit');
      for(const id of metadata.ids){if(ids.has(id))fail('NotionDataSourceDuplicatePage');ids.add(id);}
      if(metadata.nextCursor!==null){
        if(cursors.has(metadata.nextCursor))fail('NotionDataSourceRepeatedCursor');
        cursors.add(metadata.nextCursor);
        if(index+1===b.maxPages)fail('NotionDataSourcePageLimit');
      }
      const originalRows:unknown[]=[];
      for(let rowIndex=0;rowIndex<metadata.ids.length;rowIndex++){
        const row=checked(provider.notionStartReadRow(readContracts,page,rowIndex,
          b.maxRowNodes,b.maxRowDepth,b.maxRowTextBytes,b.maxColumns,b.maxRowWork));
        originalRows.push(row);
        const pending=JSON.parse(checked(provider.notionReadRowPendingJson(row,b.maxRowsWireBytes,b.maxRowsWireNodes,b.maxRowsWireDepth)) as string) as number[];
        for(const column of pending){
          if(property===undefined&&propertyAuthorizationFor===undefined)fail('NotionPropertyAuthorizationUnavailable');
          const request=checked(provider.notionStartColumnPropertyRequest(readContracts,page,rowIndex,column,...metadataLimits,
            b.maxPropertyPages,b.maxPropertyItems,b.maxPropertyBytes,b.maxPropertyNodes,b.maxPropertyTextBytes,b.maxCursorBytes,b.maxPropertyWork));
          let selectedProperty=property;
          if(propertyAuthorizationFor!==undefined){
            // Select only after Common found this actual pending original. A
            // query grant or equal DATA cannot stand in for its property use.
            await verify(NOTION_PROPERTY_READ_OPERATION);
            selectedProperty=ownInvocationAuthorization(await propertyAuthorizationFor(Object.freeze({
              originalRequest:request,declaration:prepared.declaration,source,readContracts,
              column,queryIndex:index,rowIndex,operation:NOTION_PROPERTY_READ_OPERATION,
              origin:context.scope.resourceOrigin})));
            if(provider.notionPropertyRequestMatchesBinding(request,readContracts,column)!==true||
                (selectedProperty.scope as NotionReadScope).operation!==NOTION_PROPERTY_READ_OPERATION||
                !invocationBindingsMatch(selectedProperty.scope,context.scope))fail('ForeignNotionPropertyAuthorization');
            await verify(NOTION_PROPERTY_READ_OPERATION);
          }
          // Every earlier raw charge is consumed as an observation. Exactly the
          // last actual response ticket is held for complete-row delivery; it
          // is never replaced by a ticket for synthetic canonical output bytes.
          await context.callbacks.consumeObservation(pendingCharge);pendingCharge=undefined;
          const child=createNotionPropertyReader({moon:provider,originalRequest:request,readContracts,column,
            initialAuthorization:selectedProperty,credential:context.credential,signal,
            authorizationFor:input=>authorizationFor({...input,queryIndex:index,rowIndex,column}),
            current:verify,chargeResponse,consumeObservation:context.callbacks.consumeObservation,
            consumeValue:(_wire,{charge,completedPage})=>{
              checked(provider.notionCompleteReadRowProperty(row,column,completedPage));pendingCharge=charge;
            },
            limits:{maxResponseBytes:b.maxResponseBytes,maxTotalResponseBytes:b.maxPropertyBytes,
              maxTargetBytes:b.maxTargetBytes,maxPages:b.maxPropertyPages,pageSize:b.pageSize,
              maxValueNodes:b.maxRowNodes,maxValueDepth:b.maxRowDepth,maxValueTextBytes:b.maxRowTextBytes,
              maxWireBytes:b.maxRowsWireBytes,maxWireNodes:b.maxRowsWireNodes,maxWireDepth:b.maxRowsWireDepth}});
          // Hold the actual child before awaiting it; stop/current/failure must
          // retain the same reader, raw aliases and unconfirmed cleanup debt.
          const record:PageProperty={reader:child,result:undefined};children.push(record);state.children.push(child);
          const result=await child.read();record.result=result;observations.push(...result.observations);
        }
      }
      const wire=checked(provider.notionReadPageRowsJson(readContracts,page,Object.freeze(originalRows),
        b.maxRowsWireNodes,b.maxRowsWireDepth,b.maxRowsWireBytes,b.maxPageWork,
        b.maxRowsWireBytes,b.maxRowsWireNodes,b.maxRowsWireDepth));
      const rows=JSON.parse(wire as string) as unknown[];
      if(pendingCharge===undefined)fail('NotionDataSourceObservationUnbound');
      await verify(NOTION_DATA_SOURCE_READ_OPERATION);
      await context.callbacks.consumePage(rows,Object.freeze({charge:pendingCharge,originalPage:page,
        originalRows,readContracts}));
      totalRows+=rows.length;
      await verify(NOTION_DATA_SOURCE_READ_OPERATION);
      if(metadata.nextCursor===null)return Object.freeze({pages:index+1,rowCount:totalRows,schemaWire,
        observations:Object.freeze(observations.slice()),children:Object.freeze(children.slice()),
        responseCharges:Object.freeze(state.responseCharges.slice())});
      cursor=metadata.nextCursor;
    }
    fail('NotionDataSourcePageLimit');
  }catch(cause){
    for(const response of (cause as NotionPropertyReadFailure).observations??[])if(!observations.includes(response))observations.push(response);
    throw new NotionDataSourceReadFailure(cause,observations,children,state.responseCharges);
  }
}

function originalReader(handle:object){const state=readers.get(handle);if(!state)fail('ForeignNotionDataSourceReader');return state;}

export function createNotionDataSourceReader(options:Options){
  const original=prepareRead(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state:ReaderState={prepared:Object.freeze({...original,signal}),stop,phase:'ready',children:[],responseCharges:[],queryResponses:0,queryBytes:0n};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);if(state.phase!=='ready')fail('NotionDataSourceReaderAlreadyStarted');state.phase='reading';
      try{const result=await executeRead(state.prepared,state);state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason?:unknown){originalReader(this).stop.abort(reason);},
    observe(){
      const state=originalReader(this);let receivedResponses=state.queryResponses,receivedBodyBytes=state.queryBytes;
      for(const child of state.children){const observed=child.observe();receivedResponses+=observed.receivedResponses;receivedBodyBytes+=observed.receivedBodyBytes;}
      return Object.freeze({phase:state.phase,stopRequested:state.prepared.signal.aborted,receivedResponses,receivedBodyBytes,
        observationCustody:receivedResponses===0?'not-observed':'retained',cleanupConfirmed:false});
    },
  });readers.set(handle,state);return handle;
}
