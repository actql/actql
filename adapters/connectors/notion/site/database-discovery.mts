// The existing Catalog selects the original occurrence and checks Contracts.
// This reader only obtains those originals through separately scoped Site uses.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {assertInstalledSourcePublicationRequest,installedSourcePublicationRequestId}
  from '../../../host-node/installed-source.mjs';
import {installationPreparationRequestKeys as requestKeys}
  from '../../../host-common/installation-preparation-fields.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,
  invocationScopeFields,invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {NOTION_PROPERTY_READ_API_VERSION} from './property-item-read.mjs';
import type {NotionReadObservation,NotionReadPhase,NotionReadScope} from './property-item-read.mjs';
import type {OriginalPublication} from '../../../host-node/installed-source-publication.mjs';
import type {createInstallationPreparationMetadata} from '../../../host-common/installation-preparation-metadata.mjs';

export const NOTION_DATABASE_RETRIEVE_OPERATION='notion:databases:retrieve';
export const NOTION_DATA_SOURCE_RETRIEVE_OPERATION='notion:data-sources:retrieve';
const readers=new WeakMap<object,ReaderState>(),publications=new WeakMap<object,PublicationView>();
const hash=(value:string|NodeJS.ArrayBufferView)=>'sha256:'+createHash('sha256').update(value).digest('hex');
const fail:(code:string)=>never=code=>{throw Object.assign(new Error(code),{code});};
const positive=(value:number)=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const ports=['notionReadDatabaseId','notionProjectDatabase','notionReadSourceIndex',
  'notionDatabaseMetadataJson','notionProjectDataSource','notionBindDataSourceReadContracts',
  'notionDataSourceReadSchemaJson'] as const;
const selectedPorts=['notionSelectReadSource','notionReadSourceSelectionMatches',
  'notionReadSourceSelectionId','notionProjectSelectedReadSource','notionBindSelectedReadContracts'] as const;
const publicationPorts=['notionCaptureDatabaseReadSnapshot','notionDatabaseReadSnapshotMatches',
  'notionDatabaseReadSnapshotWire','notionDatabaseReadSnapshotSourceCid',
  'notionDatabaseReadDeclarationOriginalJson','notionReadDatabaseDeclarationSourceCid',
  'notionDatabaseOriginalJson','notionDataSourceOriginalJson'] as const;
function ownData<Key extends string>(value:unknown,names:readonly Key[],code:string){
  if(value===null||typeof value!=='object'||types.isProxy(value)||Object.getPrototypeOf(value)!==Object.prototype)fail(code);
  const descriptors=Object.getOwnPropertyDescriptors(value),keys=Reflect.ownKeys(descriptors);
  if(keys.length!==names.length||keys.some(key=>!names.includes(key as Key)))fail(code);
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const d=descriptors[name];if(!d?.enumerable||!Object.hasOwn(d,'value'))fail(code);return[name,d.value];
  }))) as Readonly<Record<Key,unknown>>;
}
// Journal admission can retain a distinct grant-scope token. Both lookups
// require this control's same original Subject; compare only the generated
// closed request fields and retain both originals, never manufacture equality.
function sameRequestData(control:MetadataControl,left:unknown,right:unknown){
  const a=control.scopeFields(left),b=control.scopeFields(right);
  return requestKeys.every(key=>a[key]===b[key]);
}
function ownPublication(value:unknown,moon:Options['moon'],declaration:unknown,context:Invocation){
  if(value===undefined)return undefined;
  const {request,originals}=ownData(value,['request','originals'],'InvalidNotionDiscoveryPublication');
  if(types.isProxy(originals))fail('InvalidNotionDiscoveryPublication');
  assertInstalledSourcePublicationRequest(request,originals);
  // The Host validates its eight original descriptors. Copy only those DATA
  // slots; unrelated caller properties must never invoke an accessor here.
  const descriptors=Object.getOwnPropertyDescriptors(originals as object);
  const retained=Object.freeze(Object.fromEntries(['root','principalId','moon','installation',
    'profile','resolveSecret','runtimeBundleCid','providerMoon'].filter(name=>Object.hasOwn(descriptors,name))
    .map(name=>[name,descriptors[name].value]))) as PublicationOriginals;
  assertInstalledSourcePublicationRequest(request,retained);
  const control=context.credential.control;
  if(control?.kind!=='installation-metadata'||typeof control.projection!=='function')fail('ForeignNotionDiscoveryPublication');
  const ports=Object.freeze(Object.fromEntries(publicationPorts.map(name=>{
    const d=Object.getOwnPropertyDescriptor(moon??{},name);
    if(!d||!Object.hasOwn(d,'value')||typeof d.value!=='function')fail('InvalidNotionDiscoveryPublication');
    return[name,d.value];
  }))) as PublicationBindings;
  const call=<Name extends keyof PublicationBindings>(name:Name,
    ...args:Parameters<PublicationBindings[Name]>):unknown=>Reflect.apply(ports[name],moon,args);
  const grant=control.projection(context.authorization.grant),fields=control.subjectFields();
  if(!sameRequestData(control,grant.scope,context.scope)||fields.installationRequestId!==installedSourcePublicationRequestId(request)||
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
  'maxWireBytes','maxWireNodes','maxWireDepth'] as const;
type Bounds = Readonly<Record<typeof fields[number],number>>;
type ResourceOptions = Parameters<typeof callHttpsCredentialResource>[0];
type Operation = typeof NOTION_DATABASE_RETRIEVE_OPERATION | typeof NOTION_DATA_SOURCE_RETRIEVE_OPERATION;
type Scope = NotionReadScope & Readonly<{metadataOccurrenceId?:unknown}>;
type Authorization = ReturnType<typeof ownInvocationAuthorization>;
type MetadataControl =
  Pick<ReturnType<ReturnType<typeof createInstallationPreparationMetadata>['forSubject']>,'projection'> &
  Readonly<{
    kind:'installation-metadata';
    scopeFields(token:unknown):Readonly<Record<typeof requestKeys[number],unknown>>;
    subjectFields():Readonly<{installationRequestId:unknown;declarationSourceCid:unknown;principal:unknown;
      runtimeBundleCid:unknown;connectorRegistration:unknown;connectorRevision:unknown}>;
  }>;
type PublicationOriginals = NonNullable<OriginalPublication['bindings']>;
type MetadataBounds = readonly [bytes:number,nodes:number,depth:number,dataSources:number,properties:number,
  identityBytes:number,nameBytes:number];
type ContractBounds = [...MetadataBounds,contractNodes:number,contractDepth:number,contractTextBytes:number,columns:number,work:number];
type ProviderBindings = Readonly<{
  notionReadDatabaseId(declaration:unknown):string;
  notionProjectDatabase(bytes:NotionReadObservation['body'],...bounds:MetadataBounds):unknown;
  notionReadSourceIndex(declaration:unknown,database:unknown):unknown;
  notionDatabaseMetadataJson(database:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionProjectDataSource(database:unknown,index:number,bytes:NotionReadObservation['body'],...bounds:MetadataBounds):unknown;
  notionBindDataSourceReadContracts(declaration:unknown,source:unknown,...bounds:ContractBounds):unknown;
  notionDataSourceReadSchemaJson(contracts:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionSelectReadSource(declaration:unknown,database:unknown,work:number):unknown;
  notionReadSourceSelectionMatches(selection:unknown,declaration:unknown,database:unknown):boolean;
  notionReadSourceSelectionId(selection:unknown):string;
  notionProjectSelectedReadSource(selection:unknown,bytes:NotionReadObservation['body'],...bounds:MetadataBounds):unknown;
  notionBindSelectedReadContracts(selection:unknown,source:unknown,...bounds:ContractBounds):unknown;
  notionSourceSystemReadContracts(contracts:unknown,...bounds:ContractBounds):unknown;
}>;
type PublicationBindings = Readonly<{
  notionCaptureDatabaseReadSnapshot(selection:unknown,source:unknown,contracts:unknown,bytes:number,nodes:number,depth:number):unknown;
  notionDatabaseReadSnapshotMatches(snapshot:unknown,selection:unknown,source:unknown,contracts:unknown):boolean;
  notionDatabaseReadSnapshotWire(snapshot:unknown):unknown;
  notionDatabaseReadSnapshotSourceCid(snapshot:unknown):unknown;
  notionDatabaseReadDeclarationOriginalJson(declaration:unknown,bytes:number):unknown;
  notionReadDatabaseDeclarationSourceCid(declaration:unknown):string;
  notionDatabaseOriginalJson(database:unknown,bytes:number):unknown;
  notionDataSourceOriginalJson(source:unknown,bytes:number):unknown;
}>;
type Callbacks = Readonly<{
  authorizationFor(selection:Readonly<{operation:Operation;index:number}>):unknown;
  current(operation:Operation):unknown;
  chargeResponse(body:NotionReadObservation['body']):unknown;
  consumeObservation(charge:unknown):unknown;
}>;
type Options = Callbacks & Readonly<{
  moon:Partial<ProviderBindings & PublicationBindings>|undefined;declaration:unknown;initialAuthorization:unknown;
  sourceAuthorization?:unknown;
  sourceAuthorizationFor?(selection:Readonly<{selection:unknown;declaration:unknown;database:unknown;
    operation:typeof NOTION_DATA_SOURCE_RETRIEVE_OPERATION;origin:unknown;method:'GET';path:string;bodyBytes:0}>):unknown;
  credential:unknown;limits:Bounds;signal?:AbortSignal;systemColumns?:boolean;publication?:unknown;
}>;
type Invocation = ReturnType<typeof ownInvocationContext> & Readonly<{
  limits:Bounds; callbacks:Callbacks; credential:Readonly<Record<string,unknown> & {control?:MetadataControl | {kind?:never}}>;
}>;
type Original = ReturnType<typeof prepare> & Readonly<{signal:AbortSignal}>;
type DiscoveryResult = Readonly<{declaration:unknown;database:unknown;source:unknown;readContracts:unknown;
  schemaWire:string;selection?:unknown;observations:readonly NotionReadObservation[];responseCharges:readonly unknown[]}>;
type OperationRecord = Readonly<{index:number;operation:Operation;method:'GET';path:string;origin:unknown;
  metadataOccurrenceId:unknown;grant:unknown;scope:unknown;grantScope:unknown;useId:string;
  useCid:string;response:NotionReadObservation;bodyCid:string;bodyBytes:number}>;
type PublicationView = DiscoveryResult & Readonly<{publicationRequest:unknown;publicationOriginals:PublicationOriginals;
  subject:unknown;control:MetadataControl;credentialBinding:unknown;credentialJournal:unknown;
  snapshot:unknown;snapshotWire:string;snapshotSourceCid:string;declarationWire:string;declarationSourceCid:string;
  databaseWire:string;sourceWire:string;operations:readonly OperationRecord[]}>;
type ReaderState = {original:Original;stop:AbortController;phase:NotionReadPhase;observations:NotionReadObservation[];
  charges:unknown[];bytes:number;observedBytes:bigint;result:DiscoveryResult|undefined;operationRecords:OperationRecord[];
  capturePhase:'ready'|'pending'|'captured'|'failed';captureFailure:unknown};

const coordinate=(id:unknown,kind:'databases'|'data_sources',bound:number)=>{
  if(typeof id!=='string'||!id.isWellFormed()||id.length===0||id==='.'||id==='..')fail('InvalidNotionDiscoveryCoordinate');
  const path='/v1/'+kind+'/'+encodeURIComponent(id);
  if(Buffer.byteLength(path)>bound)fail('NotionDiscoveryTargetLimit');
  return path;
};

export class NotionDatabaseDiscoveryFailure extends Error{
  declare readonly code:'NotionDatabaseDiscoveryFailed';
  declare readonly observations:readonly NotionReadObservation[];
  declare readonly responseCharges:readonly unknown[];

  constructor(cause:unknown,observations:readonly NotionReadObservation[],responseCharges:readonly unknown[]){
    super('NotionDatabaseDiscoveryFailed',{cause});this.code='NotionDatabaseDiscoveryFailed';
    Object.defineProperty(this,'observations',{value:Object.freeze(observations.slice())});
    Object.defineProperty(this,'responseCharges',{value:Object.freeze(responseCharges.slice())});
  }
}

function prepare({moon,declaration,initialAuthorization,sourceAuthorization,sourceAuthorizationFor,credential,
  authorizationFor,current,chargeResponse,consumeObservation,limits,signal,systemColumns=false,publication}:Options){
  if(!declaration||[authorizationFor,current,chargeResponse,consumeObservation].some(x=>typeof x!=='function'))fail('InvalidNotionDiscovery');
  if(typeof systemColumns!=='boolean')fail('InvalidNotionDiscovery');
  const lazy=sourceAuthorizationFor!==undefined;
  if(lazy&&(typeof sourceAuthorizationFor!=='function'||sourceAuthorization!==undefined))fail('InvalidNotionDiscovery');
  const names=[...ports,...(lazy?selectedPorts:[]),...(systemColumns?['notionSourceSystemReadContracts' as const]:[])] as const;
  const provider=Object.freeze(Object.fromEntries(names.map(name=>[name,moon?.[name]]))) as ProviderBindings;
  if(names.some(name=>typeof provider[name]!=='function'))fail('InvalidNotionDiscovery');
  const context=ownInvocationContext({authorization:initialAuthorization,credential,limits,
    callbacks:{authorizationFor,current,chargeResponse,consumeObservation}}) as Invocation;
  const control=context.credential.control;
  const scope=invocationScopeFields(context.scope,control) as Scope;
  // A pre-schema operation has no Program Run. Keep its opaque Subject/Scope
  // and select the schema grant only after the original database observation;
  // the old Run-bound early-authorized path remains unchanged.
  if(control?.kind==='installation-metadata'&&!lazy)fail('NotionMetadataSelectionRequired');
  const source=lazy?undefined:ownInvocationAuthorization(sourceAuthorization,control);
  const sourceScope=source===undefined?undefined:invocationScopeFields(source.scope,control) as Scope;
  if(!fields.every(name=>positive(context.limits[name]))||!context.credential.binding)fail('InvalidNotionDiscovery');
  if(scope.operation!==NOTION_DATABASE_RETRIEVE_OPERATION||(!lazy&&(
    sourceScope!.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||sourceScope!.resourceOrigin!==scope.resourceOrigin||
    !invocationBindingsMatch(source!.scope,context.scope,control))))fail('ForeignNotionDiscoveryAuthorization');
  const path=coordinate(provider.notionReadDatabaseId(declaration),'databases',context.limits.maxTargetBytes);
  const originalPublication=ownPublication(publication,moon,declaration,context);
  return Object.freeze({provider,declaration,context,scope,source,sourceAuthorizationFor,path,signal,systemColumns,publication:originalPublication});
}

async function discover(original:Original,state:ReaderState):Promise<DiscoveryResult>{
  const {provider,declaration,context,path,signal}=original,b=context.limits;
  const observations=state.observations,charges=state.charges;
  const verify=async (operation:Operation)=>{signal.throwIfAborted();original.publication?.assertCurrent();
    await context.callbacks.current(operation);signal.throwIfAborted();original.publication?.assertCurrent();};
  const request=async(operation:Operation,index:number,path:string,selectedAuthorization?:Authorization)=>{
    await verify(operation);
    const authorization=ownInvocationAuthorization(selectedAuthorization??
      await context.callbacks.authorizationFor(Object.freeze({operation,index})),context.credential.control);
    const scope=invocationScopeFields(authorization.scope,context.credential.control) as Scope;
    if(scope.operation!==operation||scope.resourceOrigin!==original.scope.resourceOrigin||
        !invocationBindingsMatch(authorization.scope,context.scope,context.credential.control))fail('ForeignNotionDiscoveryAuthorization');
    await verify(operation);
    const response=await invokeScopedCredentialOperation({authorization,credential:context.credential,
      callResource:(options:ResourceOptions)=>callHttpsCredentialResource({...options,currentBeforeSend:()=>verify(operation)}),
      operation,method:'GET',path,headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],
      responseHeaders:[],maxResponseBytes:b.maxResponseBytes,signal}) as NotionReadObservation;
    observations.push(response);state.observedBytes+=BigInt(response.body.byteLength);
    if(original.publication!==undefined){
      const projection=(context.credential.control as MetadataControl).projection(authorization.grant);
      if(projection.subject!==original.publication.subject||!sameRequestData(context.credential.control as MetadataControl,projection.scope,authorization.scope)||
          typeof response.useCid!=='string'||response.useCid.length===0)fail('ForeignNotionDiscoveryPublication');
      // Capture the actual returned bytes before an awaited charge/current
      // callback can mutate its escaped raw alias. Common keeps its own parsed
      // original; capture below requires those exact retained bytes to match.
      state.operationRecords.push(Object.freeze({index,operation,method:'GET',path,
        origin:scope.resourceOrigin,metadataOccurrenceId:scope.metadataOccurrenceId,
        grant:authorization.grant,scope:authorization.scope,grantScope:projection.scope,useId:authorization.useId as string,
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
    const metadata:MetadataBounds=[b.maxResponseBytes,b.maxNodes,b.maxDepth,b.maxDataSources,b.maxProperties,b.maxIdentityBytes,b.maxNameBytes];
    const response=await request(NOTION_DATABASE_RETRIEVE_OPERATION,0,path);
    const database=checked(provider.notionProjectDatabase(response.body,...metadata));
    let selection:unknown,index:number|undefined,sourcePath:string,selectedAuthorization:Authorization|undefined;
    if(original.sourceAuthorizationFor!==undefined){
      // The grant supplier sees the actual Common-selected occurrence only
      // after the database response. This opaque DATA is not itself a permit.
      selection=checked(provider.notionSelectReadSource(declaration,database,b.maxWork));
      sourcePath=coordinate(provider.notionReadSourceSelectionId(selection),'data_sources',b.maxTargetBytes);
      await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
      selectedAuthorization=ownInvocationAuthorization(await original.sourceAuthorizationFor(Object.freeze({
        selection,declaration,database,operation:NOTION_DATA_SOURCE_RETRIEVE_OPERATION,
        origin:original.scope.resourceOrigin,method:'GET',path:sourcePath,bodyBytes:0})),context.credential.control);
      const selectedScope=invocationScopeFields(selectedAuthorization.scope,context.credential.control) as Scope;
      if(provider.notionReadSourceSelectionMatches(selection,declaration,database)!==true||
          selectedScope.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||selectedScope.resourceOrigin!==original.scope.resourceOrigin||
          !invocationBindingsMatch(selectedAuthorization.scope,context.scope,context.credential.control))fail('ForeignNotionDiscoveryAuthorization');
      await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    }else{
      // Existing early-authorized path retains its original contract/behavior.
      index=checked(provider.notionReadSourceIndex(declaration,database)) as number;
      const inventory=JSON.parse(checked(provider.notionDatabaseMetadataJson(database,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string) as
        {dataSources:readonly {id:unknown}[]};
      sourcePath=coordinate(inventory.dataSources[index]?.id,'data_sources',b.maxTargetBytes);
    }
    await context.callbacks.consumeObservation(charges[0]);
    const schemaResponse=await request(NOTION_DATA_SOURCE_RETRIEVE_OPERATION,1,sourcePath,selectedAuthorization);
    const source=selection===undefined?checked(provider.notionProjectDataSource(database,index!,schemaResponse.body,...metadata)):
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
    const schemaWire=checked(provider.notionDataSourceReadSchemaJson(readContracts,b.maxWireBytes,b.maxWireNodes,b.maxWireDepth)) as string;
    await verify(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    await context.callbacks.consumeObservation(charges[1]);
    return Object.freeze({declaration,database,source,readContracts,schemaWire,
      ...(selection===undefined?{}:{selection}),
      observations:Object.freeze(observations.slice()),responseCharges:Object.freeze(charges.slice())});
  }catch(cause){throw new NotionDatabaseDiscoveryFailure(cause,observations,charges);}
}

function originalReader(handle:object){const state=readers.get(handle);if(!state)fail('ForeignNotionDiscoveryReader');return state;}

export function createNotionDatabaseDiscovery(options:Options){
  const original=prepare(options),stop=new AbortController();
  const signal=original.signal===undefined?stop.signal:AbortSignal.any([original.signal,stop.signal]);
  const state:ReaderState={original:Object.freeze({...original,signal}),stop,phase:'ready',observations:[],charges:[],bytes:0,observedBytes:0n,
    result:undefined,operationRecords:[],capturePhase:'ready',captureFailure:undefined};
  const handle=Object.freeze({
    async read(){
      const state=originalReader(this);if(state.phase!=='ready')fail('NotionDiscoveryAlreadyStarted');state.phase='reading';
      try{const result=await discover(state.original,state);state.result=result;state.phase='succeeded';return result;}
      catch(cause){state.phase='failed';throw cause;}
    },
    requestStop(reason?:unknown){originalReader(this).stop.abort(reason);},
    observe(){const state=originalReader(this);return Object.freeze({phase:state.phase,
      stopRequested:state.original.signal.aborted,receivedResponses:state.observations.length,
      receivedBodyBytes:state.observedBytes,cleanupConfirmed:false});},
  });
  readers.set(handle,state);return handle;
}


// This live nominal capture is not cold authentication, issuer membership,
// permission, funding or a cleanup ACK. Only the same original reader/result
// can issue it, under the publication request retained before any metadata I/O.
export async function captureNotionDatabaseDiscoveryPublication(reader:object,result:DiscoveryResult,limits:unknown){
  const state=originalReader(reader),original=state.original,p=original.publication;
  if(p===undefined)fail('NotionDiscoveryPublicationUnavailable');
  if(state.phase!=='succeeded'||state.result!==result)fail('ForeignNotionDiscoveryPublicationResult');
  if(state.capturePhase!=='ready')fail('NotionDiscoveryPublicationAlreadyCaptured');
  const bound=ownData(limits,['maxBytes','maxNodes','maxDepth'],'InvalidNotionDiscoveryPublicationLimits') as Readonly<Record<'maxBytes'|'maxNodes'|'maxDepth',number>>;
  if(!Object.values(bound).every(positive))fail('InvalidNotionDiscoveryPublicationLimits');
  original.signal.throwIfAborted();p.assertCurrent();state.capturePhase='pending';
  try{
    await original.context.callbacks.current(NOTION_DATA_SOURCE_RETRIEVE_OPERATION);
    original.signal.throwIfAborted();p.assertCurrent();
    if(state.operationRecords.length!==2||state.operationRecords.some((x,index)=>
      x.index!==index||x.response!==result.observations[index]||x.operation!==
        [NOTION_DATABASE_RETRIEVE_OPERATION,NOTION_DATA_SOURCE_RETRIEVE_OPERATION][index]))fail('ForeignNotionDiscoveryPublication');
    const databaseWire=checked(p.call('notionDatabaseOriginalJson',result.database,bound.maxBytes)) as string;
    const sourceWire=checked(p.call('notionDataSourceOriginalJson',result.source,bound.maxBytes)) as string;
    for(const[index,wire]of[databaseWire,sourceWire].entries()){
      const observed=state.operationRecords[index];
      if(hash(wire)!==observed.bodyCid||Buffer.byteLength(wire)!==observed.bodyBytes)fail('NotionDiscoveryPublicationObservationMismatch');
    }
    const snapshot=checked(p.call('notionCaptureDatabaseReadSnapshot',result.selection,result.source,result.readContracts,
      bound.maxBytes,bound.maxNodes,bound.maxDepth));
    if(p.call('notionDatabaseReadSnapshotMatches',snapshot,result.selection,result.source,result.readContracts)!==true)fail('ForeignNotionDiscoveryPublication');
    const snapshotWire=checked(p.call('notionDatabaseReadSnapshotWire',snapshot)) as string;
    const snapshotSourceCid=checked(p.call('notionDatabaseReadSnapshotSourceCid',snapshot)) as string;
    const declarationWire=checked(p.call('notionDatabaseReadDeclarationOriginalJson',result.declaration,bound.maxBytes)) as string;
    const declarationSourceCid=p.call('notionReadDatabaseDeclarationSourceCid',result.declaration) as string;
    p.assertCurrent();original.signal.throwIfAborted();
    const view:PublicationView=Object.freeze({publicationRequest:p.request,publicationOriginals:p.originals,
      subject:p.subject,control:p.control,credentialBinding:original.context.credential.binding,
      credentialJournal:original.context.credential.journal,declaration:result.declaration,database:result.database,
      selection:result.selection,source:result.source,readContracts:result.readContracts,schemaWire:result.schemaWire,
      snapshot,snapshotWire,snapshotSourceCid,declarationWire,declarationSourceCid,databaseWire,sourceWire,
      observations:result.observations,responseCharges:result.responseCharges,
      operations:Object.freeze(state.operationRecords.slice())});
    const capture:object=Object.freeze(Object.create(null));publications.set(capture,view);state.capturePhase='captured';return capture;
  }catch(cause){state.capturePhase='failed';state.captureFailure=cause;throw cause;}
}

// Retrieval preserves provenance DATA after retirement for the owning cleanup
// or durable lookup. It does not re-admit currentness or issue another capture.
export function notionDatabaseDiscoveryPublicationOriginals(capture:object){
  const view=publications.get(capture);if(view===undefined)fail('ForeignNotionDiscoveryPublication');return view;
}
