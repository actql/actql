// The existing Catalog selects the original occurrence and checks Contracts.
// This reader only obtains those originals through separately scoped Site uses.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {assertInstalledSourcePublicationRequest,installedSourcePublicationRequestId}
  from '../../../host-node/installed-source.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invocationScopeFields,invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';

export const NOTION_DATABASE_RETRIEVE_OPERATION='notion:databases:retrieve';
export const NOTION_DATA_SOURCE_RETRIEVE_OPERATION='notion:data-sources:retrieve';
const readers=new WeakMap(),publications=new WeakMap();
const hash=value=>'sha256:'+createHash('sha256').update(value).digest('hex');
const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const ports=['notionReadDatabaseId','notionProjectDatabase','notionReadSourceIndex',
  'notionDatabaseMetadataJson','notionProjectDataSource','notionBindDataSourceReadContracts',
  'notionDataSourceReadSchemaJson'];
const selectedPorts=['notionSelectReadSource','notionReadSourceSelectionMatches',
  'notionReadSourceSelectionId','notionProjectSelectedReadSource','notionBindSelectedReadContracts'];
const publicationPorts=['notionCaptureDatabaseReadSnapshot','notionDatabaseReadSnapshotMatches',
  'notionDatabaseReadSnapshotWire','notionDatabaseReadSnapshotSourceCid',
  'notionDatabaseReadDeclarationOriginalJson','notionReadDatabaseDeclarationSourceCid',
  'notionDatabaseOriginalJson','notionDataSourceOriginalJson'];
function ownData(value,names,code){
  if(value===null||typeof value!=='object'||types.isProxy(value)||Object.getPrototypeOf(value)!==Object.prototype)fail(code);
  const descriptors=Object.getOwnPropertyDescriptors(value),keys=Reflect.ownKeys(descriptors);
  if(keys.length!==names.length||keys.some(key=>!names.includes(key)))fail(code);
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const d=descriptors[name];if(!d?.enumerable||!Object.hasOwn(d,'value'))fail(code);return[name,d.value];
  })));
}
function ownPublication(value,moon,declaration,context){
  if(value===undefined)return undefined;
  const {request,originals}=ownData(value,['request','originals'],'InvalidNotionDiscoveryPublication');
  if(types.isProxy(originals))fail('InvalidNotionDiscoveryPublication');
  assertInstalledSourcePublicationRequest(request,originals);
  // The Host validates all eight original descriptors before this own copy.
  const retained=Object.freeze({...originals});
  assertInstalledSourcePublicationRequest(request,retained);
  const control=context.credential.control;
  if(control?.kind!=='installation-metadata'||typeof control.projection!=='function')fail('ForeignNotionDiscoveryPublication');
  const ports=Object.freeze(Object.fromEntries(publicationPorts.map(name=>{
    const d=Object.getOwnPropertyDescriptor(moon??{},name);
    if(!d||!Object.hasOwn(d,'value')||typeof d.value!=='function')fail('InvalidNotionDiscoveryPublication');
    return[name,d.value];
  })));
  const call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  const grant=control.projection(context.authorization.grant),fields=control.subjectFields();
  if(grant.scope!==context.scope||fields.installationRequestId!==installedSourcePublicationRequestId(request)||
      fields.declarationSourceCid!==call('notionReadDatabaseDeclarationSourceCid',declaration)||
      fields.principal!==retained.principalId||fields.runtimeBundleCid!==retained.runtimeBundleCid||
      fields.connectorRegistration!==retained.installation.registration||
      fields.connectorRevision!==retained.installation.revision||
      (Object.hasOwn(retained,'providerMoon')&&retained.providerMoon!==moon))fail('ForeignNotionDiscoveryPublication');
  return Object.freeze({request,originals:retained,subject:grant.subject,control,call,
    assertCurrent:()=>assertInstalledSourcePublicationRequest(request,retained)});
}
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

function prepare({moon,declaration,initialAuthorization,sourceAuthorization,sourceAuthorizationFor,credential,
  authorizationFor,current,chargeResponse,consumeObservation,limits,signal,systemColumns=false,publication}){
  if(!declaration||[authorizationFor,current,chargeResponse,consumeObservation].some(x=>typeof x!=='function'))fail('InvalidNotionDiscovery');
  if(typeof systemColumns!=='boolean')fail('InvalidNotionDiscovery');
  const lazy=sourceAuthorizationFor!==undefined;
  if(lazy&&(typeof sourceAuthorizationFor!=='function'||sourceAuthorization!==undefined))fail('InvalidNotionDiscovery');
  const names=[...ports,...(lazy?selectedPorts:[]),...(systemColumns?['notionSourceSystemReadContracts']:[])];
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,moon?.[name]])));
  if(names.some(name=>typeof provider[name]!=='function'))fail('InvalidNotionDiscovery');
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation}});
  const control=context.credential.control;
  const scope=invocationScopeFields(context.scope,control);
  // A pre-schema operation has no Program Run. Keep its opaque Subject/Scope
  // and select the schema grant only after the original database observation;
  // the old Run-bound early-authorized path remains unchanged.
  if(control?.kind==='installation-metadata'&&!lazy)fail('NotionMetadataSelectionRequired');
  const source=lazy?undefined:ownInvocationAuthorization(sourceAuthorization,control);
  const sourceScope=source===undefined?undefined:invocationScopeFields(source.scope,control);
  if(!fields.every(name=>positive(context.limits[name]))||!context.credential.binding)fail('InvalidNotionDiscovery');
  if(scope.operation!==NOTION_DATABASE_RETRIEVE_OPERATION||(!lazy&&(
    sourceScope.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||sourceScope.resourceOrigin!==scope.resourceOrigin||
    !invocationBindingsMatch(source.scope,context.scope,control))))fail('ForeignNotionDiscoveryAuthorization');
  const path=coordinate(provider.notionReadDatabaseId(declaration),'databases',context.limits.maxTargetBytes);
  const originalPublication=ownPublication(publication,moon,declaration,context);
  return Object.freeze({provider,declaration,context,scope,source,sourceAuthorizationFor,path,signal,systemColumns,publication:originalPublication});
}

async function discover(original,state){
  const {provider,declaration,context,path,signal}=original,b=context.limits;
  const observations=state.observations,charges=state.charges;
  const verify=async operation=>{signal.throwIfAborted();original.publication?.assertCurrent();
    await context.callbacks.current(operation);signal.throwIfAborted();original.publication?.assertCurrent();};
  const request=async(operation,index,path,selectedAuthorization)=>{
    await verify(operation);
    const authorization=ownInvocationAuthorization(selectedAuthorization??
      await context.callbacks.authorizationFor(Object.freeze({operation,index})),context.credential.control);
    const scope=invocationScopeFields(authorization.scope,context.credential.control);
    if(scope.operation!==operation||scope.resourceOrigin!==original.scope.resourceOrigin||
        !invocationBindingsMatch(authorization.scope,context.scope,context.credential.control))fail('ForeignNotionDiscoveryAuthorization');
    await verify(operation);
    const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:options=>callHttpsCredentialResource({...options,currentBeforeSend:()=>verify(operation)}),
      operation,method:'GET',path,headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
      responseHeaders:[],maxResponseBytes:b.maxResponseBytes,signal});
    observations.push(response);state.observedBytes+=BigInt(response.body.byteLength);
    if(original.publication!==undefined){
      const projection=context.credential.control.projection(authorization.grant);
      if(projection.subject!==original.publication.subject||projection.scope!==authorization.scope||
          typeof response.useCid!=='string'||response.useCid.length===0)fail('ForeignNotionDiscoveryPublication');
      // Capture the actual returned bytes before an awaited charge/current
      // callback can mutate its escaped raw alias. Common keeps its own parsed
      // original; capture below requires those exact retained bytes to match.
      state.operationRecords.push(Object.freeze({index,operation,method:'GET',path,
        origin:scope.resourceOrigin,metadataOccurrenceId:scope.metadataOccurrenceId,
        grant:authorization.grant,scope:authorization.scope,useId:authorization.useId,
        useCid:response.useCid,response,bodyCid:hash(response.body),bodyBytes:response.body.byteLength}));
    }
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
    let selection,index,sourcePath,selectedAuthorization;
    if(original.sourceAuthorizationFor!==undefined){
      // The grant supplier sees the actual Common-selected occurrence only
      // after the database response. This opaque DATA is not itself a permit.
      selection=checked(provider.notionSelectReadSource(declaration,database,b.maxWork));
      sourcePath=coordinate(provider.notionReadSourceSelectionId(selection),'data_sources',b.maxTargetBytes);
      await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
      selectedAuthorization=ownInvocationAuthorization(await original.sourceAuthorizationFor(Object.freeze({
        selection,declaration,database,operation:NOTION_DATA_SOURCE_RETRIEVE_OPERATION,
        origin:original.scope.resourceOrigin,method:'GET',path:sourcePath,bodyBytes:0})),context.credential.control);
      const selectedScope=invocationScopeFields(selectedAuthorization.scope,context.credential.control);
      if(provider.notionReadSourceSelectionMatches(selection,declaration,database)!==true||
          selectedScope.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||selectedScope.resourceOrigin!==original.scope.resourceOrigin||
          !invocationBindingsMatch(selectedAuthorization.scope,context.scope,context.credential.control))fail('ForeignNotionDiscoveryAuthorization');
      await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    }else{
      // Existing early-authorized path retains its original contract/behavior.
      index=checked(provider.notionReadSourceIndex(declaration,database));
      const inventory=JSON.parse(checked(provider.notionDatabaseMetadataJson(database,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)));
      sourcePath=coordinate(inventory.dataSources[index]?.id,'data_sources',b.maxTargetBytes);
    }
    await context.callbacks.consumeObservation(charges[0]);
    const schemaResponse=await request(NOTION_DATA_SOURCE_RETRIEVE_OPERATION,1,sourcePath,selectedAuthorization);
    const source=selection===undefined?checked(provider.notionProjectDataSource(database,index,schemaResponse.body,...metadata)):
      checked(provider.notionProjectSelectedReadSource(selection,schemaResponse.body,...metadata));
    const propertyContracts=selection===undefined?checked(provider.notionBindDataSourceReadContracts(declaration,source,...metadata,
      b.maxContractNodes,b.maxContractDepth,b.maxContractTextBytes,b.maxColumns,b.maxWork)):
      checked(provider.notionBindSelectedReadContracts(selection,source,...metadata,
        b.maxContractNodes,b.maxContractDepth,b.maxContractTextBytes,b.maxColumns,b.maxWork));
    // Public Source rows keep the same original property pair and add only
    // Common's fixed system metadata contracts. No JS type/value interpreter.
    const readContracts=original.systemColumns?checked(provider.notionSourceSystemReadContracts(
      propertyContracts,...metadata,b.maxContractNodes,b.maxContractDepth,
      b.maxContractTextBytes,b.maxColumns,b.maxWork)):propertyContracts;
    const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth));
    await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    await context.callbacks.consumeObservation(charges[1]);
    return Object.freeze({declaration,database,source,readContracts,schemaWire,
      ...(selection===undefined?{}:{selection}),
      observations:Object.freeze(observations.slice()),responseCharges:Object.freeze(charges.slice())});
  }catch(cause){throw new NotionDatabaseDiscoveryFailure(cause,observations,charges);}
}

function originalReader(handle){const state=readers.get(handle);if(!state)fail('ForeignNotionDiscoveryReader');return state;}

export function createNotionDatabaseDiscovery(options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state={original:Object.freeze({...original,signal}),stop,phase:'ready',observations:[],charges:[],bytes:0,observedBytes:0n,
    result:undefined,operationRecords:[],capturePhase:'ready',captureFailure:undefined};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);if(state.phase!=='ready')fail('NotionDiscoveryAlreadyStarted');state.phase='reading';
      try{const result=await discover(state.original,state);state.result=result;state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.original.signal.aborted,receivedResponses:state.observations.length,
      receivedBodyBytes:state.observedBytes,cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}


// This live nominal capture is not cold authentication, issuer membership,
// permission, funding or a cleanup ACK. Only the same original reader/result
// can issue it, under the publication request retained before any metadata I/O.
export async function captureNotionDatabaseDiscoveryPublication(reader,result,limits){
  const state=originalReader(reader),original=state.original,p=original.publication;
  if(p===undefined)fail('NotionDiscoveryPublicationUnavailable');
  if(state.phase!=='succeeded'||state.result!==result)fail('ForeignNotionDiscoveryPublicationResult');
  if(state.capturePhase!=='ready')fail('NotionDiscoveryPublicationAlreadyCaptured');
  const bound=ownData(limits,['maxBytes','maxNodes','maxDepth'],'InvalidNotionDiscoveryPublicationLimits');
  if(!Object.values(bound).every(positive))fail('InvalidNotionDiscoveryPublicationLimits');
  original.signal.throwIfAborted();p.assertCurrent();state.capturePhase='pending';
  try{
    await original.context.callbacks.current(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    original.signal.throwIfAborted();p.assertCurrent();
    if(state.operationRecords.length!==2||state.operationRecords.some((x,index)=>
      x.index!==index||x.response!==result.observations[index]||x.operation!==
        [NOTION_DATABASE_RETRIEVE_OPERATION,NOTION_DATA_SOURCE_RETRIEVE_OPERATION][index]))fail('ForeignNotionDiscoveryPublication');
    const databaseWire=checked(p.call('notionDatabaseOriginalJson',result.database,bound.maxBytes));
    const sourceWire=checked(p.call('notionDataSourceOriginalJson',result.source,bound.maxBytes));
    for(const[index,wire]of[databaseWire,sourceWire].entries()){
      const observed=state.operationRecords[index];
      if(hash(wire)!==observed.bodyCid||Buffer.byteLength(wire)!==observed.bodyBytes)fail('NotionDiscoveryPublicationObservationMismatch');
    }
    const snapshot=checked(p.call('notionCaptureDatabaseReadSnapshot',result.selection,result.source,result.readContracts,
      bound.maxBytes,bound.maxNodes,bound.maxDepth));
    if(p.call('notionDatabaseReadSnapshotMatches',snapshot,result.selection,result.source,result.readContracts)!==true)fail('ForeignNotionDiscoveryPublication');
    const snapshotWire=checked(p.call('notionDatabaseReadSnapshotWire',snapshot));
    const snapshotSourceCid=checked(p.call('notionDatabaseReadSnapshotSourceCid',snapshot));
    const declarationWire=checked(p.call('notionDatabaseReadDeclarationOriginalJson',result.declaration,bound.maxBytes));
    const declarationSourceCid=p.call('notionReadDatabaseDeclarationSourceCid',result.declaration);
    p.assertCurrent();original.signal.throwIfAborted();
    const view=Object.freeze({publicationRequest:p.request,publicationOriginals:p.originals,
      subject:p.subject,control:p.control,credentialBinding:original.context.credential.binding,
      credentialJournal:original.context.credential.journal,declaration:result.declaration,database:result.database,
      selection:result.selection,source:result.source,readContracts:result.readContracts,schemaWire:result.schemaWire,
      snapshot,snapshotWire,snapshotSourceCid,declarationWire,declarationSourceCid,databaseWire,sourceWire,
      observations:result.observations,responseCharges:result.responseCharges,
      operations:Object.freeze(state.operationRecords.slice())});
    const capture=Object.freeze(Object.create(null));publications.set(capture,view);state.capturePhase='captured';return capture;
  }catch(cause){state.capturePhase='failed';state.captureFailure=cause;throw cause;}
}

// Retrieval preserves provenance DATA after retirement for the owning cleanup
// or durable lookup. It does not re-admit currentness or issue another capture.
export function notionDatabaseDiscoveryPublicationOriginals(capture){
  const view=publications.get(capture);if(view===undefined)fail('ForeignNotionDiscoveryPublication');return view;
}
