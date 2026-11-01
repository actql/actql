import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime} from '../../../host-node/installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from '../../../host-node/installed-project-connections.mjs';
import {createInstalledRowSource,rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {openLocalFileRoot} from '../site/root-filesystem.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';
import {defaultFileMediaType as mime} from '../../../host-common/file-media-type.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const text = (value, maximum) => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !value.includes('\0') && Buffer.byteLength(value) <= maximum;
const limitNames = ['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes',
  'maxPages','maxPageBytes','maxPageRows','maxAttempts','maxDurationMs','maxListingBytes'];
// Selected service ceilings only. The Host must still admit the same actual
// Source/Compute parent and retain physical children before covered work.
// These do not select a numerical release profile or authorize file access.
export const LOCAL_FILES_DEFAULT_LIMITS=Object.freeze({maxEntries:10000,maxDepth:32,
  maxPathBytes:4096,maxFiles:1000,maxFileBytes:16777216,maxReadBytes:67108864,
  maxPages:64,maxPageBytes:1048576,maxPageRows:256,maxAttempts:64,
  maxDurationMs:30000,maxListingBytes:16777216});
function ownLimits(input) {
  const fields = input !== null && typeof input === 'object' ? Object.getOwnPropertyDescriptors(input) : {};
  if (Reflect.ownKeys(fields).length !== limitNames.length ||
      limitNames.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('LocalFilesLimitsUnavailable');
  const value = Object.freeze(Object.fromEntries(limitNames.map(name => [name, fields[name].value])));
  if (limitNames.filter(name => name !== 'maxFileBytes').some(name => !positive(value[name])) ||
      !Number.isSafeInteger(value.maxFileBytes) || value.maxFileBytes < 0 ||
      value.maxEntries > 100000 || value.maxDepth > 128 || value.maxPathBytes > 4096 ||
      value.maxFiles > value.maxEntries || value.maxReadBytes < value.maxFileBytes ||
      value.maxAttempts < value.maxPages || value.maxPageRows > value.maxFiles) fail('LocalFilesLimitsUnavailable');
  return value;
}
function restoreDeclaration(call, connection, rootPath, versionMode, limits) {
  const string = nullable => ({type:'string',nullable});
  const resource = {type:'resource_ref',resource_kind:'file',nullable:false};
  const timestamp = nullable => ({type:'timestamp',nullable});
  const request = fields => ({type:'object',nullable:false,additional_properties:false,fields});
  const fileSchema = {resource,version:string(false),name:string(false),path:string(false),
    size:{type:'int64',nullable:false},modified_time:timestamp(false),media_type:string(true),
    size_bytes:{type:'number',nullable:true},modified_at:timestamp(true)};
  const contentSchema = {resource,version:string(false),path:string(false),
    media_type:string(false),content:{type:'content_ref',nullable:false}};
  const view = (name,schema,fields,acquisition) => ({resource:name,resource_kind:'file',
    schema_wire:canonical(schema),schema_cid:cid(schema),request_schema_wire:canonical(request(fields)),
    facts_wire:'{}',acquisition_wire:canonical(acquisition)});
  const views = [view('files',fileSchema,{paths:{type:'array',nullable:true,
    max_items:limits.maxFiles,items:string(false)},glob:string(true)},
    {kind:'scan',authority:'read_metadata'}),
  view('contents',contentSchema,{resource,version:string(false)},
    {kind:'fetch',authority:'read_content',correlation:{request_fields:['resource','version'],
      response_fields:['resource','version'],identity:['resource','version'],cardinality:'one'}})];
  const restore = () => checked(call('clientProgramRowSourceRestoreRelationDeclaration',
    connection,'local','local/0.1',JSON.stringify({views}),undefined));
  const initial = JSON.parse(call('clientProgramRowSourceDeclarationJson',restore()));
  // Catalog declarations describe the selected physical scope. They never
  // admit a Root, Account decision, original reader or cleanup observation.
  const scopeCid = cid({connector:'local',connection,root:rootPath});
  const versionCid = cid({connector:'local',version_mode:versionMode,
    representation:'exact_stored_bytes',metadata_fields:['size','modified_seconds','modified_nanos']});
  views[0].facts_wire = canonical({file_listing:{version:'actql-file-list/0.1',kind:'file_listing',
    selectable:['paths','glob'],allow_unfiltered_listing:true,admitted_scope_contract_cid:scopeCid,
    listing_schema_contract_cid:initial.views.find(view=>view.resource==='files').carrier_schema_cid,
    version_capability:{contract_cid:versionCid,required_nonnull:true},
    max_listing_items:limits.maxFiles,max_examined_items:limits.maxEntries,
    max_listing_pages:limits.maxPages,max_request_attempts:limits.maxAttempts,
    max_listing_bytes:limits.maxListingBytes,max_listing_duration_ms:limits.maxDurationMs,
    maximum_path_length:limits.maxPathBytes}});
  views[1].facts_wire = canonical({file_content:{version:'actql-file-content/0.1',kind:'file_content',
    admitted_scope_contract_cid:scopeCid,
    content_schema_contract_cid:initial.views.find(view=>view.resource==='contents').carrier_schema_cid,
    version_capability:{contract_cid:versionCid,required_nonnull:true},representation:'exact_stored_bytes'},
  lookup_capacity:{version:'actql-lookup-capacity/0.1',completeness:'complete_per_requested_key',
    max_rows_per_key:1,max_pages_per_request:limits.maxPages,max_response_bytes_per_page:limits.maxPageBytes}});
  const declaration = restore();
  const store=localFileStoreDeclaration(call('clientProgramRowSourceDeclarationJson',declaration),
    {connectorId:connection,rootPath,maxBytes:131072});
  return Object.freeze({declaration,wire:store.declarationWire,scopeCid,versionCid});
}

// Same original Project/connection declaration, before Root acquisition.
// Only this existing Connector's files/contents views are prepared here;
// configured table formats retain their original declaration for their Owner.
export async function prepareInstalledProjectLocalFiles(moon, project,
  {assertCurrent, limits, openFile} = {}) {
  if (project === undefined) return undefined;
  if (typeof assertCurrent !== 'function') fail('InvalidLocalFilesPreparation');
  const projectOriginal = installedProjectOriginalsForRuntime(project,moon);
  const ports = Object.freeze(Object.fromEntries(['clientProjectConnectionsCount',
    'clientProjectConnectionsName','clientProjectConnectionsConnector','clientProjectConnectionsEntryOriginalJson',
    'clientProgramRowSourceRestoreRelationDeclaration','clientProgramRowSourceDeclarationJson'].map(name=>{
    const method=moon?.[name];if(typeof method!=='function')fail('LocalFilesRuntimeUnavailable');return[name,method];
  })));
  let retired = false, connections, original, bundle, view;
  const call = (name,...args) => Reflect.apply(ports[name],moon,args);
  const current = () => {
    if(retired)fail('LocalFilesPreparationRetired');
    assertCurrent();
    if(installedProjectOriginalsForRuntime(project,moon)!==projectOriginal) fail('ForeignLocalFilesPreparation');
  };
  current();
  connections=await loadInstalledProjectConnections(moon,project,
    {assertCurrent:current,...(openFile===undefined?{}:{openFile})});
  original=connections.originalsForRuntime(moon);
  current();
  const selected=original.connections;
  if(selected===undefined)return undefined;
  const count=call('clientProjectConnectionsCount',selected);
  if(!Number.isSafeInteger(count)||count<0||count>128)fail('LocalFilesConnectionCountUnavailable');
  const sources=[];
  let selectedLimits;
  for(let index=0;index<count;index++){
    if(call('clientProjectConnectionsConnector',selected,index)!=='local')continue;
    selectedLimits??=ownLimits(limits);
    const connection=call('clientProjectConnectionsName',selected,index);
    const wire=call('clientProjectConnectionsEntryOriginalJson',selected,index);
    if(!text(connection,128)||typeof wire!=='string')fail('InvalidLocalFilesConnection');
    const entry=JSON.parse(wire);
    if(entry?.connector!=='local'||!text(entry.root,4096))fail('InvalidLocalFilesConnection');
    if(entry.version!==undefined&&entry.version!=='content')fail('LocalFilesVersionUnavailable');
    const rootPath=resolve(dirname(original.path),entry.root);
    if(!text(rootPath,4096))fail('InvalidLocalFilesConnection');
    const versionMode=entry.version==='content'?'content':'metadata';
    const declared=restoreDeclaration(call,connection,rootPath,versionMode,selectedLimits);
    sources.push(Object.freeze({connection,connectorId:connection,registration:'local',revision:'local/0.1',
      originalEntryWire:wire,rootPath,versionMode,limits:selectedLimits,
      queryAliases:Object.freeze([{name:connection,resource:'files'},
        {name:connection+'.files',resource:'files'},{name:connection+'.contents',resource:'contents'}]
        .map(value=>Object.freeze(value))),...declared}));
    current();
  }
  if(sources.length===0)return undefined;
  bundle=Object.freeze({project:projectOriginal,connections:original,sources:Object.freeze(sources)});
  const same = (runtime,receiver) => {if(runtime!==moon||receiver!==view)fail('ForeignLocalFilesPreparation');};
  view=Object.freeze({originalsForRuntime(runtime){same(runtime,this);current();
    if(connections.originalsForRuntime(moon)!==original)fail('ForeignLocalFilesPreparation');return bundle;},
    retire(runtime){same(runtime,this);if(retired)return;retired=true;
      // Managed-reference retirement only; Root/Run/reader cleanup stays with
      // its actual physical and Resource owners before this parent retires.
      bundle=connections=original=undefined;
    }});
  return view;
}

const acknowledged = value => value !== null && typeof value === 'object' &&
  Object.getOwnPropertyDescriptor(value,'pending')?.value === false;

function physicalReadChild({namespace,path,assertCurrent}) {
  let filesystem,reader,opening=false,attempted=false,stopping=false,closed=false,initialFailure;
  let cleanup,cleanupCaptured=false,retry,status,retryCaptured=false,statusCaptured=false;
  const child=Object.freeze({
    start(options){
      if(attempted||stopping||closed)fail('LocalFilesSourcePreparationMismatch');
      attempted=true;opening=true;
      try{
        if(namespace===undefined)fail('LocalFilesNativeFilesystemUnavailable');
        const native=namespace;
        filesystem=openLocalFileRoot({native,path,assertCurrent(){
          if(stopping)fail('LocalFileReadClosing');assertCurrent();
        }});
        if(stopping)fail('LocalFileReadClosing');
        reader=filesystem.openReader(options);return reader;
      }catch(cause){initialFailure=cause;throw cause;}
      finally{opening=false;}
    },
    status(){return Object.freeze({pending:!closed});},
    async close(){
      stopping=true;if(closed)return child.status();if(opening)return child.status();
      if(filesystem!==undefined){
        if(!acknowledged(filesystem.close()))return child.status();
        filesystem=reader=undefined;
      }
      if(initialFailure!==undefined){
        if(!cleanupCaptured){cleanup=initialFailure?.cleanupHandle;cleanupCaptured=true;}
        if(cleanup!==undefined){
          if(!retryCaptured){retry=cleanup.retry;retryCaptured=true;}
          if(!statusCaptured){status=cleanup.status;statusCaptured=true;}
          if(typeof retry!=='function'||typeof status!=='function')fail('LocalFileCleanupPending');
          if(!acknowledged(Reflect.apply(status,cleanup,[])))await Reflect.apply(retry,cleanup,[]);
          if(!acknowledged(Reflect.apply(status,cleanup,[])))return child.status();
        }else if(initialFailure?.cleanupPending===true)return child.status();
      }
      closed=true;return child.status();
    },
  });
  return child;
}

// The real Local Source consumer. Common retains original checked preparation,
// Run/Ledger/RowRun and Reference admission; the Source supplier retains the
// same physical reader before any post-acquisition current check.
export async function installPreparedProjectLocalFiles({moon,preparation,sourceManaged,
  baseEnvironmentWire,authorizationFor,nativeFilesystem,prepareManagedRun,prepareManagedContentRun}) {
  if(typeof authorizationFor!=='function'||typeof sourceManaged?.assertCurrent!=='function'||
      typeof sourceManaged?.prepareRead!=='function'||
      typeof moon?.clientProgramLocalFileTimestamp!=='function') fail('LocalFilesManagedReadUnavailable');
  const bundle=preparation.originalsForRuntime(moon),sources=[],reads=new WeakMap();
  // Weak lookup is provenance only. The shared Host owns ordinary Runs; this
  // Connector retains only its actual native children until their close ACK.
  const sharedRuns=new WeakMap(),sharedReads=new Set();
  let profile;
  // The same received file overlaps its native chunk and the Store writer's
  // exact append snapshot. Row decoding has its existing page workspace in
  // addition. These are demand on the original Content Ledger, not an issuer.
  const keyedTransports=new Map(bundle.sources.map(entry=>[entry,Object.freeze({
    transferBytes:BigInt(entry.limits.maxReadBytes)+
      BigInt(entry.limits.maxPages)*BigInt(entry.limits.maxPageBytes),
    executionBytes:2n*BigInt(entry.limits.maxFileBytes)+65536n+BigInt(entry.limits.maxPageBytes),
  })]));
  const [queryContract,evidenceContract]=await Promise.all(
    ['actql-query-acquisition.json','actql-query-process-evidence.json'].map(name=>
      readFile(new URL('../../../../spec/contracts/'+name,import.meta.url),'utf8')));
  let closing=false;
  const current=()=>{
    if(closing)fail('LocalFilesInstallationClosing');
    sourceManaged.assertCurrent();
    if(preparation.originalsForRuntime(moon)!==bundle)fail('ForeignLocalFilesPreparation');
  };
  const sameRun=(prepared,request)=>{
    current();const run=sharedRuns.get(prepared);
    if(run?.retired)fail('LocalFilesPreparationRetired');
    if(run?.failed)throw run.failure;
    if(run===undefined||run.value===undefined)fail('LocalFilesManagedReadUnavailable');
    const value=run.value,originalRequest=run.request,effectful=run.effectful;
    checked((run.effectful?moon.clientProgramInstalledEffectManagedRunCheck:moon.clientProgramInstalledManagedRunCheck)
      (value,prepared,request===undefined?originalRequest:request));
    // The Core current callback may reenter the Host. Keep this original
    // lookup after it without issuing another current observation.
    if(sharedRuns.get(prepared)!==run||run.retired||run.value!==value||run.request!==originalRequest||run.effectful!==effectful)
      fail('ForeignLocalFilesPreparation');
    if(run.failed)throw run.failure;
    return run;
  };
  function prepareRun(prepared,request,prepareInvocation){
    current();
    if(sharedRuns.get(prepared)?.recipe!==undefined||typeof prepareManagedRun!=='function')fail('LocalFilesManagedReadUnavailable');
    // The same Host retains its actual partial/adopted Run before returning.
    // No Connector Root, admission, numeric quote or run-count ceiling exists.
    const value=Reflect.apply(prepareManagedRun,undefined,[prepared,request,profile,prepareInvocation]);
    if(value===undefined)fail('LocalFilesManagedReadUnavailable');
    const prior=sharedRuns.get(prepared);
    if(prior!==undefined&&(prior.value!==value||prior.request!==request))fail('ForeignLocalFilesPreparation');
    if(prior===undefined)sharedRuns.set(prepared,{prepared,request,value,effectful:false,reads:new Map()});
    current();
    return value;
  }
  function releaseContentAliases(managed,inputHolder){
    const run=this;if(run.retired===true)return;
    if(sharedRuns.get(run.prepared)!==run||run.contentPreparation?.localPreparation!==run)
      fail('ForeignLocalFilesContentPreparation');
    if(managed!==undefined){
      if(run.hostRun!==managed||managed.retiringContent!==true||managed.prepared!==run.prepared||managed.request!==run.request)
        fail('LocalFileCleanupPending');
    }else if(run.hostRun?.value!==undefined||inputHolder===undefined||run.inputHolder!==inputHolder||
        moon.clientProgramPreparationBorrowRead(inputHolder)!==run.prepared||
        moon.clientProgramPreparationBorrowRetirementStarted(inputHolder)!==true)fail('LocalFileCleanupPending');
    for(const read of run.reads.values())if(read!==undefined&&!read.closed)fail('LocalFileCleanupPending');
    for(const key of Object.keys(run))run[key]=undefined;
    run.retired=true;
  }
  function contentSourceEntry(resource,reference){
    // These are the SAME declaration aliases captured by installation below.
    // Keep their existing order; do not parse/reconstruct declarations at the
    // Request constructor or select another connection after a refusal.
    const index=sources.findIndex((source,index)=>source.queryAliases.some((alias,slot)=>
      bundle.sources[index].queryAliases[slot].resource===resource&&alias.sourceRef===reference));
    return index<0?undefined:bundle.sources[index];
  }
  function prepareContentRun(prepared,request,recipe,graph,contentPreparation){
    current();
    if(typeof prepareManagedContentRun!=='function')fail('ForeignLocalFilesContentPreparation');
    const prior=sharedRuns.get(prepared);
    if(prior!==undefined){
      if(request===undefined||prior.retired||prior.recipe!==recipe||prior.graph!==graph)fail('ForeignLocalFilesContentPreparation');
      const hostRun=prior.hostRun;
      if(sameRun(prepared,request)!==prior||prior.recipe!==recipe||prior.graph!==graph||prior.hostRun!==hostRun)
        fail('ForeignLocalFilesContentPreparation');
      return hostRun;
    }
    if(contentPreparation?.prepared!==prepared||contentPreparation.inputHolder===undefined||contentPreparation.localPreparation!==undefined)
      fail('ForeignLocalFilesContentPreparation');
    const run={prepared,request,effectful:false,recipe,graph,hostRun:undefined,original:undefined,value:undefined,
      inputHolder:contentPreparation.inputHolder,contentPreparation,reads:new Map(),retired:false,failed:false,failure:undefined};
    Object.defineProperty(run,'releaseAliases',{value:releaseContentAliases});
    contentPreparation.localPreparation=run;
    sharedRuns.set(prepared,run);
    try{
      run.hostRun=Reflect.apply(prepareManagedContentRun,undefined,[prepared,request,graph,recipe,(parent,requestInput)=>{
        const control=Object.getOwnPropertyDescriptor(contentPreparation,'contentControl')?.value;
        const construct=control===undefined?undefined:Object.getOwnPropertyDescriptor(control,'prepareRequestKeyedPlan')?.value;
        if(typeof construct!=='function')fail('LocalFilesContentPreparationUnavailable');
        const keyed=recipe.keyedAcquisition;
        if(keyed===undefined||moon.clientProgramKeyedAcquisitionMatchesProgram(keyed,prepared)!==true)
          fail('ForeignLocalFilesContentPreparation');
        const coordinates=moon.clientProgramKeyedDirectAcquisitionCoordinates(keyed);
        const stage=runtimeOptionalField(coordinates,0),input=runtimeOptionalField(coordinates,1);
        if(!Number.isSafeInteger(stage)||!Number.isSafeInteger(input))fail('LocalFilesContentPreparationUnavailable');
        const source=checked(moon.clientProgramSelectInstalledSourceInput(prepared,request,stage,input));
        if(moon.clientProgramSelectedSourceInputKind(source)!=='query')fail('LocalFilesContentPreparationUnavailable');
        const directRef=moon.clientProgramSelectedSourceInputRef(source);
        if(typeof directRef!=='string')fail('LocalFilesContentPreparationUnavailable');
        const facts=checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyed));
        const direct=contentSourceEntry('files',directRef);
        const content=contentSourceEntry('contents',facts[0]);
        if(direct===undefined||content===undefined)fail('LocalFilesContentPreparationUnavailable');
        run.keyed=keyed;run.contentEntry=content;
        run.selected=Reflect.apply(construct,control,[parent,requestInput,request,keyed,
          direct.declaration,content.declaration,content.limits.maxPageBytes,1000000,queryContract,evidenceContract,
          [BigInt(direct.limits.maxPages)*BigInt(direct.limits.maxPageBytes),keyedTransports.get(content).transferBytes],
          [BigInt(direct.limits.maxPageBytes),keyedTransports.get(content).executionBytes],
          recipe.registry,recipe.task,recipe.step,recipe.prefixLimits,recipe.workspace]);
        return run.selected;
      },contentPreparation]);
      if(run.hostRun===undefined||run.hostRun.selectedKeyed!==run.selected||run.hostRun.value===undefined)
        fail('LocalFilesContentPreparationUnavailable');
      run.original=run.hostRun.original;run.value=run.hostRun.value;
      sameRun(prepared);return run.hostRun;
    }catch(cause){run.failed=true;run.failure=cause;throw cause;}
  }
  function contentLedger(prepared,request,recipe,direct,keyed,capacity){
    const run=sameRun(prepared);
    if(run.recipe!==recipe||run.keyed!==keyed||capacity===undefined)fail('ForeignLocalFilesContentPreparation');
    const transport=keyedTransports.get(run.contentEntry);
    if(capacity.transferBytes!==transport.transferBytes||capacity.executionBytes!==transport.executionBytes||
        capacity.maxBytes!==run.contentEntry.limits.maxPageBytes||capacity.maxWork!==1000000)
      fail('ForeignLocalFilesContentPreparation');
    checked(moon.clientProgramInstalledManagedKeyedContentCheckPreparation(run.selected,prepared));
    return checked(moon.clientProgramInstalledManagedRunPrepareLedger(run.value,prepared,request,
      [direct.capacity],[direct.transferBytes],[direct.executionBytes],
      recipe.registry,recipe.values,recipe.fragment,recipe.ordered));
  }
  function captureClose(read){
    if(!read.closeCaptured){read.close=read.raw.close;read.closeCaptured=true;}
    if(typeof read.close!=='function')fail('LocalFilesManagedReadUnavailable');
  }
  async function closeSharedReadExternal(read){
    if(read.closed||read.externalClosed)return;
    if(read.externalClosing!==undefined)return await read.externalClosing;
    // Retain the same close before entering an original external method.
    // Concurrent/reentrant cleanup awaits it; a pending ACK stays retryable.
    const work=Promise.resolve().then(async()=>{
      if(read.physical!==undefined&&!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
      captureClose(read);
      if(!acknowledged(await Reflect.apply(read.close,read.raw,[])))fail('LocalFileCleanupPending');
      read.externalClosed=true;
    });
    read.externalClosing=work;
    try{await work;}finally{if(read.externalClosing===work)read.externalClosing=undefined;}
  }
  function releaseSharedRead(read){
    if(read.closed)return;
    // The Core session still owns its original read and RowRun retirement.
    // Keep only a weak-key close tombstone and the consumed occurrence, not
    // another strong path to the Prepared graph or closed native controls.
    if(read.value!==undefined)reads.set(read.value,{entry:read.entry,keyed:read.keyed===true,externalClosed:true});
    read.owner.reads.set(read.index,undefined);
    sharedReads.delete(read);read.closed=true;
    read.owner=read.value=read.raw=read.entry=read.reader=read.physical=read.close=read.retain=undefined;
  }
  async function closeSourceRead(original){
    const retained=reads.get(original);
    if(retained===undefined||retained.keyed===true||retained.read?.keyed===true)fail('ForeignLocalFilesSourcePreparation');
    if(retained.externalClosed===true)return Object.freeze({pending:false});
    const read=retained.read;
    if(!sharedReads.has(read))fail('ForeignLocalFilesSourcePreparation');
    await closeSharedReadExternal(read);releaseSharedRead(read);
    return Object.freeze({pending:false});
  }
  async function closeRead(read){
    if(read.closed)return;
    if(sharedReads.has(read)){
      await closeSharedReadExternal(read);
      if(read.closed)return;
      if(read.value!==undefined){
        const retire=read.keyed?moon.clientProgramInstalledKeyedSourceReadRetire:moon.clientProgramInstalledSourceReadRetire;
        checked(Reflect.apply(retire,moon,[read.value]));
      }
      releaseSharedRead(read);return;
    }else{
      if(read.physical!==undefined&&!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
      captureClose(read);
      if(!acknowledged(await Reflect.apply(read.close,read.raw,[])))fail('LocalFileCleanupPending');
      if(read.value!==undefined){
        const retire=read.keyed?moon.clientProgramInstalledKeyedSourceReadRetire:
          moon.clientProgramInstalledSourceReadRetire;
        checked(Reflect.apply(retire,moon,[read.value]));
      }
    }
    read.closed=true;sharedReads.delete(read);
  }
  async function close(){
    closing=true;const errors=[];
    for(const read of sharedReads)try{await closeRead(read);}catch(cause){errors.push(cause);}
    if(errors.length)throw new AggregateError(errors,'LocalFilesCleanupPending');
  }
  try{
    for(const entry of bundle.sources){
      current();
      const authorization=await authorizationFor(entry.connection);current();
      const assertAccountCurrent=authorization.assertAccountCurrent;
      if(typeof assertAccountCurrent!=='function')fail('LocalFilesAuthorizationUnavailable');
      const declared=JSON.parse(entry.wire),environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
      const known=new Set(),preparedRuns=new WeakMap();
      const issuer=moon.clientProgramResourceReferenceIssuer((kind,wire)=>kind==='file'&&known.has(wire),()=>{
        try{current();return true;}catch{return false;}
      });
      const resourceFor=path=>{
        const value=Object.freeze({$actql_ref:'resource',version:'actql-resource-ref/0.1',
          provider_namespace:'local',resource_kind:'file',provider_identity_cid:entry.scopeCid,
          authority_scope_cid:authorization.context.contextCid,boundary_cid:entry.scopeCid,
          identity_cid:cid({root_scope:entry.scopeCid,path})});
        known.add(canonical(value));return value;
      };
      const adapter=await createInstalledRowSource({moon,declaration:entry.declaration,declared,
        environmentWire:environment.wire,connectorId:entry.connectorId,connectorRegistration:'local',
        connectorRevision:'local/0.1',bindingCid:cid({scope:entry.scopeCid,declaration:entry.wire,
          account_context:authorization.context.contextCid}),authorization,readOperation:'read',referenceIssuer:issuer,
        site:Object.freeze({connection:entry.connection,
          issueReadGrant({operation,decision,resource,runInvocationCid,dispatchRequestCid,maxUses}){
            current();
            if(operation!=='read'||!['files','contents'].includes(resource)||
                !/^sha256:[0-9a-f]{64}$/u.test(runInvocationCid)||
                !/^sha256:[0-9a-f]{64}$/u.test(dispatchRequestCid)||!positive(maxUses)||
                decision?.action!=='dispatch'||decision.boundary!=='acquisition'||
                decision.tuple?.connection!==entry.connection||decision.tuple?.resource!==resource||
                decision.tuple?.operation!=='read'||
                decision.contextCid!==authorization.context.contextCid)fail('LocalFilesReadGrantNotAuthorized');
            // The original Account gate verifies its own decision and current
            // configuration; a copied tuple or historical Allow is not a grant.
            Reflect.apply(assertAccountCurrent,authorization,[decision]);
            return Object.freeze({runInvocationCid,dispatchRequestCid});
          },
          async close(){
            for(const read of sharedReads)if(read.entry===entry)await closeRead(read);}}),
        physicalTarget:(resource,fields)=>({connection:entry.connection,root:entry.rootPath,
          resource,fields:[...fields],scope_cid:entry.scopeCid}),
        limits:{maxPages:entry.limits.maxPages,maxPageBytes:entry.limits.maxPageBytes,
          maxPageRows:entry.limits.maxPageRows,maxCaptureRows:entry.limits.maxFiles},
        originalKeyedTransport:keyedTransports.get(entry),
        prepareSourceRead({checkedOwner,effectful,declaration,occurrence,managedRun,originalRead,requestIdentity}){
          current();
          let run=sharedRuns.get(checkedOwner);
          if(run===undefined&&effectful===true&&managedRun!==undefined&&originalRead!==undefined&&requestIdentity!==undefined){
            // The shared Source has already checked this exact Effect
            // Run/Prepared/Request and selected its original read. Retain only
            // local child provenance; the Host still owns admission/lifetime.
            run={prepared:checkedOwner,request:requestIdentity,value:managedRun,effectful:true,reads:new Map()};
            sharedRuns.set(checkedOwner,run);
          }
          const index=occurrence.stage;
          if(run===undefined||run.retired||run.failed||effectful!==run.effectful||
              declaration!==entry.declaration||occurrence.input!==0||
              !Number.isSafeInteger(index)||index<0||run.reads.has(index)||
              managedRun!==run.value||originalRead===undefined||
              requestIdentity!==undefined&&requestIdentity!==run.request)fail('LocalFilesSourcePreparationMismatch');
          // The original Host validates its own adopted parent before it
          // retains the physical child. No second Core current callback is
          // needed between the shared read selection and this same handoff.
          const raw=sourceManaged.prepareRead(checkedOwner,declaration,run.value,occurrence);
          const read={raw,entry,owner:run,index,value:originalRead,reader:undefined,physical:undefined,close:undefined,closeCaptured:false,
            retain:undefined,closed:false,attempted:false};
          run.reads.set(index,read);
          sharedReads.add(read);
          // Retain the same physical child control before callback getters or
          // currentness can reject it. The Host remains the sole Run owner.
          captureClose(read);read.retain=read.raw.retainChild;
          if(typeof read.retain!=='function')fail('LocalFilesManagedReadUnavailable');
          current();
          reads.set(read.value,{run,read});return read.value;
        },
        async closeSourceRead(original){
          const retained=reads.get(original);
          if(retained===undefined||retained.entry!==undefined&&retained.entry!==entry||
              retained.read!==undefined&&retained.read.entry!==entry)fail('ForeignLocalFilesSourcePreparation');
          return closeSourceRead(original);
        },
        prepareKeyedSourceRead({checkedOwner,keyedAcquisition,request,declaration}){
          const run=sameRun(checkedOwner);
          if(run.recipe===undefined||run.keyed!==keyedAcquisition||run.contentEntry!==entry||
              declaration!==entry.declaration||run.reads.has(request))fail('LocalFilesSourcePreparationMismatch');
          const raw=sourceManaged.prepareKeyedRead(checkedOwner,declaration,run.original,request);
          const read={raw,entry,owner:run,index:request,keyed:true,value:undefined,reader:undefined,physical:undefined,
            close:undefined,closeCaptured:false,retain:undefined,closed:false,attempted:false};
          run.reads.set(request,read);sharedReads.add(read);captureClose(read);read.retain=raw.retainChild;
          if(typeof read.retain!=='function')fail('LocalFilesManagedReadUnavailable');
          sameRun(checkedOwner);
          read.value=checked(moon.clientProgramInstalledManagedKeyedSourceRead(
            run.value,keyedAcquisition,request,declaration));
          reads.set(read.value,{run,read});return read.value;
        },
        async closeKeyedSourceRead(original){
          const retained=reads.get(original);
          if(retained?.externalClosed===true){
            if(!retained.keyed||retained.entry!==entry)fail('ForeignLocalFilesContentPreparation');
            return Object.freeze({pending:false});
          }
          if(retained===undefined||!retained.read?.keyed||retained.read.entry!==entry)
            fail('ForeignLocalFilesContentPreparation');
          await closeRead(retained.read);return Object.freeze({pending:false});
        },
        async readPages(options){
          if(options.resource==='contents'){
            const retained=reads.get(options.rowRun.originalKeyedRead);
            if(retained===undefined||!retained.read?.keyed||retained.read.entry!==entry||
                typeof options.capturedResourcePath!=='function'||typeof options.captureContent!=='function')
              fail('LocalFilesSourcePreparationMismatch');
            const {run,read}=retained;sameRun(run.prepared);
            if(read.closed||read.attempted)fail('LocalFilesSourcePreparationMismatch');
            read.attempted=true;
            let entered=false;
            try{
              const path=await options.capturedResourcePath();
              const request=JSON.parse(options.requestWire);
              if(!text(path,entry.limits.maxPathBytes)||
                  canonical(request.resource)!==canonical(resourceFor(path))||
                  typeof request.version!=='string')fail('LocalFilesContentResourceMismatch');
              await options.verifyRead();options.signal?.throwIfAborted();sameRun(run.prepared);
              await options.beginRequest(Buffer.from(options.requestWire));entered=true;
              const checkRead=()=>{sameRun(run.prepared);
                checked(moon.clientProgramInstalledKeyedSourceReadCheckCurrent(read.value));};
              read.physical=physicalReadChild({namespace:nativeFilesystem,path:entry.rootPath,assertCurrent:checkRead});
              Reflect.apply(read.retain,read.raw,[read.physical]);checkRead();
              const limits=Object.fromEntries(['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes']
                .map(name=>[name,entry.limits[name]]));
              read.reader=read.physical.start({limits,signal:options.signal,assertCurrent:checkRead});
              const file=await read.reader.read(path,{expectedVersion:request.version,
                contentVersion:entry.versionMode==='content'});
              checkRead();
              // This is the same native body, not synthetic encoded output.
              // Each bounded slice consumes its own ticket before the next;
              // configured file and aggregate read ceilings remain unchanged.
              for(let offset=0;offset<file.bytes.length;offset+=entry.limits.maxPageBytes){
                const charge=options.chargePage(file.bytes.subarray(offset,offset+entry.limits.maxPageBytes));
                options.consumeObservation(charge);
              }
              const mediaType=mime(path),content=await options.captureContent({bytes:file.bytes,
                mediaType,contentCid:'sha256:'+createHash('sha256').update(file.bytes).digest('hex')});
              await options.consumePage([{resource:request.resource,version:file.version,path,
                media_type:mediaType,content}]);
              if(!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
              return;
            }catch(cause){
              let stopped=false;
              const cleanup=async()=>{stopped=read.physical===undefined||acknowledged(await read.physical.close());return stopped;};
              try{await cleanup();}catch{/* The same native owner remains pending. */}
              throw new AcquisitionOpenError(cause,stopped?(entered?'stopped':'not_started'):'unknown',
                stopped?undefined:Object.freeze({close:cleanup,cleanup,cleanupPending:()=>!stopped}));
            }
          }
          if(options.resource!=='files'||options.listing===undefined)fail('LocalFilesContentReadUnavailable');
          const retained=reads.get(options.rowRun.originalRead);
          if(retained?.read===undefined)fail('LocalFilesSourcePreparationMismatch');
          const {run,read}=retained;sameRun(run.prepared);
          if(read.closed||read.attempted||read.entry!==entry)fail('LocalFilesSourcePreparationMismatch');
          const shared=sharedRuns.get(run.prepared)===run;
          let entered=false;
          try{
            read.attempted=true;
            await options.verifyRead();options.signal?.throwIfAborted();sameRun(run.prepared);
            const fileLimits=Object.fromEntries(['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes']
              .map(name=>[name,entry.limits[name]]));
            const checkRead=()=>{sameRun(run.prepared);checked(moon.clientProgramInstalledSourceReadCheckCurrent(read.value));};
            read.physical=physicalReadChild({namespace:nativeFilesystem,path:entry.rootPath,assertCurrent:checkRead});
            Reflect.apply(read.retain,read.raw,[read.physical]);
            sameRun(run.prepared);
            // The same raw Source child owns the physical constructor BEFORE
            // it opens this Root. Account/current checks above precede the first
            // directory open; initialization is not listing or Content credit.
            entered=true;
            read.reader=read.physical.start({limits:fileLimits,signal:options.signal,assertCurrent:checkRead});
            let items=[],page=0,token;
            const flush=async final=>{
              const next=final?null:String(++page);
              const body=Buffer.from(JSON.stringify({items,request_token:token??null,next_token:next}));
              if(body.length>entry.limits.maxPageBytes)fail('LocalFilesPageBytesLimit');
              const charge=options.chargePage(body);
              await options.listing.consumePage(body,{charge});
              items=[];token=next;
              if(!final)await options.listing.beginRequest(token);
            };
            await options.listing.beginRequest(undefined);
            await read.reader.list({contentVersion:entry.versionMode==='content',async onFile(file){
              const timestamp=moon.clientProgramLocalFileTimestamp(file.metadata.modifiedSeconds,Number(file.metadata.modifiedNanos));
              if(typeof timestamp!=='string')fail('LocalFileTimestampUnavailable');
              const item={resource:resourceFor(file.path),version:file.version,name:file.path,path:file.path,
                size:String(file.metadata.size),modified_time:timestamp,media_type:mime(file.path),
                size_bytes:file.metadata.size<=BigInt(Number.MAX_SAFE_INTEGER)?Number(file.metadata.size):null,
                modified_at:timestamp};
              const candidate=[...items,item];
              if(Buffer.byteLength(JSON.stringify({items:candidate,request_token:token??null,next_token:String(page+1)}))>
                  entry.limits.maxPageBytes){if(items.length===0)fail('LocalFilesPageBytesLimit');await flush(false);}
              items.push(item);
              if(items.length===entry.limits.maxPageRows)await flush(false);
            }});
            await flush(true);sameRun(run.prepared);
            if(shared)await closeSourceRead(read.value);
          }catch(cause){
            if(!shared)throw cause;
            let stopped=false;
            const cleanup=async()=>{if(!read.closed)await closeSourceRead(read.value);stopped=true;return true;};
            try{await cleanup();}catch{/* Same original native/raw child remains pending. */}
            throw new AcquisitionOpenError(cause,stopped?(entered?'stopped':'not_started'):'unknown',
              stopped?undefined:Object.freeze({close:cleanup,cleanup,cleanupPending:()=>!stopped}));
          }
        }});
      const queryAliases=Object.freeze(entry.queryAliases.map(alias=>{
        const view=declared.views.find(view=>view.resource===alias.resource);
        return Object.freeze({name:alias.name,sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,
          schemaContractCid:view.carrier_schema_cid});
      }));
      // Keyed Local contents are captured by the existing Run-owned Store
      // frame. Dispatch must retain that frame before opening file bytes.
      sources.push(Object.freeze({...adapter,queryAliases,requiresRunContentCapture:true,
        managedCaptureCapacity(requirement){
          current();
          // The actual shared Plan retains this one original acquisition.
          // Prepare/ledger projection later consumes that SAME tuple.
          const acquisition=checked(moon.clientProgramRowSourcePrepareAcquisition(
            entry.declaration,requirement,queryContract,evidenceContract));
          const capacity=moon.clientProgramInstalledRowCaptureCapacity(acquisition);
          if(capacity===undefined)fail('LocalFilesManagedReadUnavailable');
          return Object.freeze({capacity,transferBytes:BigInt(entry.limits.maxPages)*BigInt(entry.limits.maxPageBytes),
            executionBytes:BigInt(entry.limits.maxPageBytes)});
        },
        async prepare(facts){
          const owner=facts.preparedEffect??facts.preparedProgram;
          let original=sharedRuns.get(owner);
          if(original===undefined){
            // Only the actual shared Effect selection may establish this
            // local provenance record. Its Core getter and the Host read
            // consumer validate the original tuple before acquiring a child.
            if(facts.preparedEffect===undefined||facts.preparedProgram!==undefined||
                facts.managedRun===undefined||facts.requestIdentity===undefined)
              fail('LocalFilesManagedReadUnavailable');
          }else if(original.failed)throw original.failure;
          if(original!==undefined&&((facts.managedRun!==undefined&&facts.managedRun!==original.value)||
              (facts.requestIdentity!==undefined&&facts.requestIdentity!==original.request)))
            fail('LocalFilesSourcePreparationMismatch');
          // A consumed occurrence keeps its original read and any pending
          // cleanup. Reject before another Core getter can return that same
          // read and a failed second preparation could retire the first.
          if(original?.reads.has(facts.occurrence?.stage))fail('LocalFilesSourcePreparationMismatch');
          const forwarded=original===undefined?facts:Object.freeze({...facts,
            managedRun:original.value,requestIdentity:original.request});
          const prepared=await adapter.prepare(forwarded);
          original??=sharedRuns.get(owner);
          if(sameRun(owner)!==original)fail('LocalFilesSourcePreparationMismatch');
          preparedRuns.set(prepared,original);return prepared;},
        ledgerCapacity(prepared){const run=preparedRuns.get(prepared);
          if(run===undefined||run!==sameRun(run.prepared))fail('LocalFilesSourcePreparationMismatch');
          return Object.freeze({...adapter.ledgerCapacity(prepared),managedRun:run.value});}}));
    }
    let environmentWire;
    for(const source of sources)environmentWire=composeInstalledCheckEnvironment(moon,baseEnvironmentWire,
      environmentWire,source.environmentWire);
    current();
    profile=Object.freeze({realizationKey:'installed-multi-acquired',environmentWire,sources:Object.freeze(sources),
      connectorBindings:Object.freeze(sources.flatMap(source=>source.connectorBindings)),
      queryAliases:Object.freeze(sources.flatMap(source=>source.queryAliases)),
      admitsSource:ref=>sources.some(source=>source.admitsSource(ref)),
      prepareManagedRun:prepareRun,
      prepareManagedContentRun:prepareContentRun,managedContentLedger:contentLedger,close});
    return profile;
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:{close}});}
}
