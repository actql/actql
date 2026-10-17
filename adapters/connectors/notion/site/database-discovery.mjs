// The existing Catalog selects the original occurrence and checks Contracts.
// This reader only obtains those originals through separately scoped Site uses.
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';

export const NOTION_DATABASE_RETRIEVE_OPERATION='notion:databases:retrieve';
export const NOTION_DATA_SOURCE_RETRIEVE_OPERATION='notion:data-sources:retrieve';
const readers=new WeakMap();
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const ports=['notionReadDatabaseId','notionProjectDatabase','notionReadSourceIndex',
  'notionDatabaseMetadataJson','notionProjectDataSource','notionBindDataSourceReadContracts',
  'notionDataSourceReadSchemaJson'];
const fields=['maxResponseBytes','maxTotalResponseBytes','maxTargetBytes','maxNodes','maxDepth',
  'maxDataSources','maxProperties','maxIdentityBytes','maxNameBytes','maxContractNodes',
  'maxContractDepth','maxContractTextBytes','maxColumns','maxWork',
  'maxWireBytes','maxWireNodes','maxWireDepth'];
const coordinate=(id,kind,bound)=>{
  if(typeof id!=='string'||!id.isWellFormed()||id.length===0||id==='.'||id==='..')fail('InvalidNotionDiscoveryCoordinate');
  const path='/v1/'+kind+'/'+encodeURIComponent(id);
  if(Buffer.byteLength(path)>bound)fail('NotionDiscoveryTargetLimit');
  return path;
};

export class NotionDatabaseDiscoveryFailure extends Error{
  constructor(cause,observations,responseCharges){
    super('NotionDatabaseDiscoveryFailed',{cause});this.code='NotionDatabaseDiscoveryFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
    Object.defineProperty(this,'responseCharges',{value:Object.freeze(responseCharges.slice())});
  }
}

function prepare({moon,declaration,initialAuthorization,sourceAuthorization,credential,
  authorizationFor,current,chargeResponse,consumeObservation,limits,signal}){
  if(!declaration||[authorizationFor,current,chargeResponse,consumeObservation].some(x=>typeof x!=='function'))fail('InvalidNotionDiscovery');
  const provider=Object.freeze(Object.fromEntries(ports.map(name=>[name,moon?.[name]])));
  if(ports.some(name=>typeof provider[name]!=='function'))fail('InvalidNotionDiscovery');
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation}});
  const source=ownInvocationAuthorization(sourceAuthorization);
  if(!fields.every(name=>positive(context.limits[name]))||!context.credential.binding)fail('InvalidNotionDiscovery');
  if(context.scope.operation!==NOTION_DATABASE_RETRIEVE_OPERATION||
    source.scope.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||
    !invocationBindingsMatch(source.scope,context.scope))fail('ForeignNotionDiscoveryAuthorization');
  const path=coordinate(provider.notionReadDatabaseId(declaration),'databases',context.limits.maxTargetBytes);
  return Object.freeze({provider,declaration,context,source,path,signal});
}

async function discover(original,state){
  const {provider,declaration,context,path,signal}=original,b=context.limits;
  const observations=state.observations,charges=state.charges;
  const verify=async operation=>{signal.throwIfAborted();await context.callbacks.current(operation);signal.throwIfAborted();};
  const request=async(operation,index,path)=>{
    await verify(operation);
    const authorization=ownInvocationAuthorization(await context.callbacks.authorizationFor(Object.freeze({operation,index})));
    if(authorization.scope.operation!==operation||!invocationBindingsMatch(authorization.scope,context.scope))fail('ForeignNotionDiscoveryAuthorization');
    await verify(operation);
    const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,currentBeforeSend:()=>verify(operation)}),
      operation,method:'GET',path,headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
      responseHeaders:[],maxResponseBytes:b.maxResponseBytes,signal});
    observations.push(response);state.observedBytes+=BigInt(response.body.byteLength);
    // Even an aggregate/current/admission failure retains this actual ticket.
    const charge=await context.callbacks.chargeResponse(response.body);charges.push(charge);
    if(response.body.byteLength>b.maxTotalResponseBytes-state.bytes)fail('NotionDiscoveryResponseLimit');
    state.bytes+=response.body.byteLength;
    await verify(operation);
    if(!response.accepted||response.statusCode!==200)fail('NotionDiscoveryRejected');
    return response;
  };
  try{
    const metadata=[b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,b.maxIdentityBytes,b.maxNameBytes];
    const response=await request(NOTION_DATABASE_RETRIEVE_OPERATION,0,path);
    const database=checked(provider.notionProjectDatabase(response.body,...metadata));
    // Only Common selects a singleton or the declaration's exact original id.
    // The metadata below provides coordinates, never name/first/schema inference.
    const index=checked(provider.notionReadSourceIndex(declaration,database));
    const inventory=JSON.parse(checked(provider.notionDatabaseMetadataJson(database,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)));
    const sourcePath=coordinate(inventory.dataSources[index]?.id,'data_sources',b.maxTargetBytes);
    await context.callbacks.consumeObservation(charges[0]);
    const schemaResponse=await request(NOTION_DATA_SOURCE_RETRIEVE_OPERATION,1,sourcePath);
    const source=checked(provider.notionProjectDataSource(database,index,schemaResponse.body,...metadata));
    const readContracts=checked(provider.notionBindDataSourceReadContracts(declaration,source,...metadata,
      b.maxContractNodes,b.maxContractDepth,b.maxContractTextBytes,b.maxColumns,b.maxWork));
    const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth));
    await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    await context.callbacks.consumeObservation(charges[1]);
    return Object.freeze({declaration,database,source,readContracts,schemaWire,
      observations:Object.freeze(observations.slice()),responseCharges:Object.freeze(charges.slice())});
  }catch(cause){throw new NotionDatabaseDiscoveryFailure(cause,observations,charges);}
}

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionDiscoveryReader');return state;}

export function createNotionDatabaseDiscovery(options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state={original:Object.freeze({...original,signal}),stop,phase:'ready',observations:[],charges:[],bytes:0,observedBytes:0n};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);if(state.phase!=='ready')fail('NotionDiscoveryAlreadyStarted');state.phase='reading';
      try{const result=await discover(state.original,state);state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.original.signal.aborted,receivedResponses:state.observations.length,
      receivedBodyBytes:state.observedBytes,cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}
