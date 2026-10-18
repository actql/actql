// Trusted installed RowRun caller only. Catalog owns the saved schema and
// pending property originals; the existing Site owns each operation's grant.
// This adapter supplies neither a capacity declaration nor physical retirement.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationAuthorization,invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createNotionDataSourceReader,NOTION_DATA_SOURCE_READ_OPERATION as queryOperation} from '../site/data-source-read.mjs';
import {NOTION_PROPERTY_READ_OPERATION as propertyOperation} from '../site/property-item-read.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed();
function data(value,name){
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidNotionDatabaseReader');
  const d=Object.getOwnPropertyDescriptor(value,name);
  if(!d||!Object.hasOwn(d,'value'))fail('InvalidNotionDatabaseReader');
  return d.value;
}
function methods(value,names){
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const fn=data(value,name);if(typeof fn!=='function')fail('InvalidNotionDatabaseReader');
    return[name,fn];
  })));
}

// A normal trusted installation must supply the same-runtime capacity and
// authenticate its saved snapshot before selecting this factory. A snapshot's
// public CID/decoded body does not perform either operational admission.
export function createNotionDatabaseReaderFactory({moon,snapshot,site,capacity,resource,limits,maxSecretBytes}){
  if(capacity===undefined||capacity===null)fail('NotionReaderCapacityUnavailable');
  if(!text(resource)||!positive(maxSecretBytes))fail('InvalidNotionDatabaseReader');
  const bounded=Object.freeze({...limits});
  if(!positive(bounded.maxTotalRows)||!positive(bounded.maxColumns)||
      !positive(bounded.maxPropertyPages)||!positive(bounded.maxRowsWireBytes)||
      !positive(bounded.maxRowsWireNodes)||!positive(bounded.maxRowsWireDepth))fail('InvalidNotionDatabaseReader');
  const maxProperties=bounded.maxTotalRows*bounded.maxColumns;
  if(!Number.isSafeInteger(maxProperties)||maxProperties>2147483647)fail('InvalidNotionDatabaseReader');
  const names=['notionDatabaseReadSnapshotDeclaration','notionDatabaseReadSnapshotSource',
    'notionDatabaseReadSnapshotContracts',
    'notionPropertyRequestMatchesBinding','notionPropertyRequestJson',
    'notionDataSourceReadMatches','notionDataSourceMetadataJson','notionDataSourceReadSchemaJson',
    'notionProjectQueryPage','notionQueryPageMetadataJson','notionStartReadRow','notionReadRowPendingJson',
    'notionStartColumnPropertyRequest','notionCompleteReadRowProperty','notionReadPageRowsJson',
    'notionProjectPropertyItemPage','notionPropertyItemPageComplete','notionNextPropertyRequest','notionCompletedPropertyJson'];
  const ports=methods(moon,names),call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,(...args)=>call(name,...args)])));
  const declaration=checked(call('notionDatabaseReadSnapshotDeclaration',snapshot));
  const source=checked(call('notionDatabaseReadSnapshotSource',snapshot));
  const readContracts=checked(call('notionDatabaseReadSnapshotContracts',snapshot));
  if(call('notionDataSourceReadMatches',readContracts,declaration,source)!==true)fail('ForeignNotionDatabaseSnapshot');
  const sitePorts=methods(site,['issueReadGrant']),credential=data(site,'credential');
  if(data(credential,'control')?.kind==='installation-metadata')fail('ForeignNotionDatabaseCredential');
  const preparations=new WeakSet();
  const factory=Object.freeze({capacity,prepare(options){
    if(this!==factory)fail('ForeignNotionDatabaseReaderFactory');
    const owner=data(options,'rowRun'),acquisition=data(owner,'acquisition');
    if(acquisition===null||typeof acquisition!=='object'||preparations.has(acquisition))fail('NotionDatabaseReaderAlreadyPrepared');
    if(data(options,'resource')!==resource||data(options,'operation')!==queryOperation)fail('ForeignNotionDatabaseReader');
    const run=data(owner,'run'),requestId=data(owner,'requestId'),runInvocationCid=data(owner,'runInvocationCid'),
      dispatchRequestCid=data(owner,'dispatchRequestCid');
    if(!run||!text(requestId)||!text(runInvocationCid)||!text(dispatchRequestCid))fail('InvalidNotionDatabaseReader');
    const callbacks=methods(options,['verifyRead','authorizationFor','chargePage','consumeObservation','consumePage']);
    const invoke=(name,...args)=>Reflect.apply(callbacks[name],options,args);
    const stop=new AbortController(),originalSignal=data(options,'signal');
    const signal=originalSignal===undefined?stop.signal:AbortSignal.any([originalSignal,stop.signal]);
    // One original factory invocation per acquisition; failure never reopens it.
    preparations.add(acquisition);
    let phase='ready',child,binding,transportClosed=false,transportFailure,originalFailure;
    const properties=new Map();
    const closeTransport=()=>{
      if(binding!==undefined&&!transportClosed){
        try{transportClosed=closeHttpsCredentialBinding(binding)==='closed';}
        catch(cause){transportFailure??=cause;throw cause;}
      }
    };
    const verify=async operation=>{
      if(operation!==queryOperation&&operation!==propertyOperation)fail('ForeignNotionDatabaseOperation');
      signal.throwIfAborted();const decision=await invoke('verifyRead');signal.throwIfAborted();return decision;
    };
    const coordinates=request=>{
      const wire=checked(call('notionPropertyRequestJson',request,bounded.maxRowsWireBytes,
        bounded.maxRowsWireNodes,bounded.maxRowsWireDepth));
      const value=JSON.parse(wire);
      return Object.freeze({pageId:value.pageId,propertyId:value.propertyId});
    };
    let initial;
    const selectedProperty=async selected=>{
      if(selected.declaration!==declaration||selected.source!==source||selected.readContracts!==readContracts||
          selected.operation!==propertyOperation||!Number.isSafeInteger(selected.column)||selected.column<0||
          !Number.isSafeInteger(selected.queryIndex)||selected.queryIndex<0||
          !Number.isSafeInteger(selected.rowIndex)||selected.rowIndex<0||
          call('notionPropertyRequestMatchesBinding',selected.originalRequest,readContracts,selected.column)!==true)fail('ForeignNotionDatabaseProperty');
      const key=selected.queryIndex+'/'+selected.rowIndex+'/'+selected.column;
      if(properties.has(key)||properties.size>=maxProperties)fail('NotionDatabasePropertyLimit');
      const original=Object.freeze({request:selected.originalRequest,column:selected.column,
        coordinates:coordinates(selected.originalRequest),ordinal:properties.size});
      // Retain the actual pending occurrence before awaiting its Account check.
      const record={original,authorization:undefined};properties.set(key,record);
      const decision=await verify(propertyOperation);
      if(call('notionPropertyRequestMatchesBinding',original.request,readContracts,original.column)!==true)fail('ForeignNotionDatabaseProperty');
      const grant=Reflect.apply(sitePorts.issueReadGrant,site,[{operation:propertyOperation,decision,
        resource,runInvocationCid,dispatchRequestCid,maxUses:bounded.maxPropertyPages}]);
      const authorization=ownInvocationAuthorization({...grant,useId:requestId+'-property-'+original.ordinal+'-0'});
      if(authorization.scope.operation!==propertyOperation||
          !invocationBindingsMatch(authorization.scope,initial.scope))fail('ForeignNotionDatabaseProperty');
      record.authorization=authorization;
      await verify(propertyOperation);return authorization;
    };
    const authorizationFor=async input=>{
      if(input.operation===queryOperation)return invoke('authorizationFor',input.index);
      if(input.operation!==propertyOperation)fail('ForeignNotionDatabaseOperation');
      const record=properties.get(input.queryIndex+'/'+input.rowIndex+'/'+input.column);
      if(record?.authorization===undefined||!Number.isSafeInteger(input.index)||input.index<0||
          input.index>=bounded.maxPropertyPages||
          call('notionPropertyRequestMatchesBinding',input.originalRequest,readContracts,input.column)!==true)fail('ForeignNotionDatabaseProperty');
      const target=coordinates(input.originalRequest);
      if(target.pageId!==record.original.coordinates.pageId||target.propertyId!==record.original.coordinates.propertyId)fail('ForeignNotionDatabaseProperty');
      await verify(propertyOperation);
      return Object.freeze({...record.authorization,useId:requestId+'-property-'+record.original.ordinal+'-'+input.index});
    };
    const handle=Object.freeze({
      async read(){
        if(this!==handle)fail('ForeignNotionDatabaseReader');
        if(phase!=='ready')fail('NotionDatabaseReaderAlreadyStarted');phase='reading';
        try{
          await verify(queryOperation);
          initial=ownInvocationAuthorization(await invoke('authorizationFor',0));
          if(initial.scope.operation!==queryOperation||initial.scope.runInvocationCid!==runInvocationCid||
              initial.scope.dispatchRequestCid!==dispatchRequestCid)fail('ForeignNotionDatabaseRun');
          await verify(queryOperation);
          binding=openHttpsCredentialBinding({...credential,scope:initial.scope,maxSecretBytes});
          child=createNotionDataSourceReader({moon:provider,declaration,source,readContracts,
            initialAuthorization:initial,propertyAuthorizationFor:selectedProperty,
            credential:{...credential,binding},authorizationFor,current:verify,
            chargeResponse:body=>invoke('chargePage',body),
            consumeObservation:charge=>invoke('consumeObservation',charge),
            consumePage:(rows,ticket)=>invoke('consumePage',rows,ticket),limits:bounded,signal});
          const result=await child.read();phase='succeeded';return result;
        }catch(cause){phase='failed';originalFailure=cause;throw cause;}
        finally{
          try{closeTransport();}catch(cause){phase='failed';if(originalFailure===undefined){originalFailure=cause;throw cause;}}
        }
      },
      requestStop(reason){
        if(this!==handle)fail('ForeignNotionDatabaseReader');
        stop.abort(reason);child?.requestStop(reason);closeTransport();
      },
      observe(){
        if(this!==handle)fail('ForeignNotionDatabaseReader');
        // Original raw/error/child/callback/grant aliases remain with this same
        // RowRun. Transport close is not their physical retirement receipt.
        return Object.freeze({phase,transportClosed,transportFailure:transportFailure!==undefined,
          propertyOccurrences:properties.size,child:child?.observe(),cleanupConfirmed:false});
      },
    });return handle;
  }});return factory;
}
