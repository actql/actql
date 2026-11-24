// Local Connector declaration DATA. The original installed Host must retain
// the checked Mapping/Command pair and issue the collection Reference under
// its actual installation/current authority. None of these strings grants I/O.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

type Data = Record<string, unknown>;
type DeclarationInput = Readonly<{connectorId: unknown; rootPath: unknown; maxBytes: number}>;
type ContractReference = Readonly<{id: string; version: string; cid: string}>;

const canonical = (value: unknown) => canonicalJson(value,{dataKeys:true});
const cid = (value: unknown) => 'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const fail: () => never = () => {throw Object.assign(new Error('InvalidLocalFileStoreDeclaration'),
  {code:'InvalidLocalFileStoreDeclaration'});};
const text = (value: unknown,max: number): value is string => typeof value==='string'&&value.length>0&&value.isWellFormed()&&
  !value.includes('\0')&&Buffer.byteLength(value)<=max;
const sealed = <Body extends Data, Field extends string>(body: Body,field: Field) =>
  ({...body,[field]:cid(body)}) as Body & Record<Field,string>;
const sorted = (members: readonly Data[],key: string) =>
  [...members].sort((a,b)=>(a[key] as string)<(b[key] as string)?-1:(a[key] as string)>(b[key] as string)?1:0);
const keys = (value: unknown,names: readonly string[]): value is Data => value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...names].sort().join('\0');

export function localFileStoreDeclaration(declaredWire: unknown,{connectorId,rootPath,maxBytes}: DeclarationInput) {
  if(!text(connectorId,128)||!text(rootPath,4096)||!isAbsolute(rootPath)||
      !Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>1048576||
      typeof declaredWire!=='string'||Buffer.byteLength(declaredWire)>maxBytes)fail();
  const read = (wire: unknown): unknown => {
    if(typeof wire!=='string'||Buffer.byteLength(wire)>maxBytes)fail();
    let body: unknown;try{body=JSON.parse(wire);}catch{fail();}
    // The existing Common declaration wrapper preserves its own field order;
    // it is not required to be canonical text. Catalog/member CIDs below and
    // the eventual Common environment admission check the actual bodies.
    return body;
  };
  const record = (value: unknown): value is Data => value!==null&&typeof value==='object'&&!Array.isArray(value);
  const declared=read(declaredWire);
  if(!record(declared))fail();
  const catalog=read(declared.catalog);
  if(!record(catalog))fail();
  const {catalog_cid:oldCid,...oldBody}=catalog;
  if(declared.connector_id!==connectorId||declared.connector_registration!=='local'||
      declared.connector_version!=='local/0.1'||declared.catalog_cid!==oldCid||cid(oldBody)!==oldCid||
      !keys(catalog,['schema','catalog_cid','connector_id','connector_version','source_views','commands','contracts'])||
      catalog.schema!=='actql.connector_catalog/0.1'||catalog.connector_id!==connectorId||
      catalog.connector_version!=='local/0.1'||!Array.isArray(catalog.source_views)||
      !Array.isArray(catalog.commands)||!Array.isArray(catalog.contracts)||!Array.isArray(declared.contracts)||
      !catalog.commands.every(record)||!catalog.contracts.every(record)||
      canonical(declared.contracts.map(read))!==canonical(catalog.contracts))fail();
  if(Object.hasOwn(declared,'command_bodies')&&(!Array.isArray(declared.command_bodies)||
      canonical(declared.command_bodies.map(read))!==canonical(catalog.commands)))fail();
  const manifest=read(declared.manifest_entry);
  if(!keys(manifest,['connector','connector_id','connector_version'])||manifest.connector!=='local'||
      manifest.connector_id!==connectorId||manifest.connector_version!=='local/0.1'||
      cid(manifest)!==declared.manifest_entry_cid)fail();
  const fields={content:{type:'content_ref',nullable:false},overwrite:{type:'boolean',nullable:false},
    path:{type:'string',nullable:false}};
  const required=['content','path'];
  const inputBody={additional_properties:false,fields,required_fields:required};
  const role=(kind: string,body: Data)=>sealed({schema:'actql.contract/0.1',
    id:`${connectorId}.local.files.store.${kind}`,version:'local/0.1',kind,body},'cid');
  const input=role('command_input',inputBody);
  const output=role('command_output',{type:'object',nullable:false,additional_properties:false,fields:{}});
  const reference=({id,version,cid}: ContractReference)=>({id,version,cid});
  const permissions=['files.write'];
  const command=sealed({schema:'actql.command_contract/0.1',
    command_id:`command:${connectorId}.local.files.store.v1`,connector_id:connectorId,version:'local/0.1',
    target:{resource_kind:'file_collection',cardinality:'single'},input_schema:reference(input),
    input_contract:inputBody,output_schema:reference(output),permissions,
    preview:{strength:'exact'},outcome:'synchronous',idempotency:{support:'unsupported'},
    reversibility:'unknown',atomicity:'single_target'},'contract_cid');
  const merge=(original: readonly Data[],additional: readonly Data[],key: string,selector: (member: Data) => unknown)=>{
    const result=[...original];
    for(const member of additional){
      const old=result.find(candidate=>selector(candidate)===selector(member));
      if(old!==undefined){if(canonical(old)!==canonical(member))fail();}
      else result.push(member);
    }
    if(new Set(result.map(member=>member[key])).size!==result.length)fail();
    return sorted(result,key);
  };
  const contracts=merge(catalog.contracts,[input,output],'cid',body=>canonical([body.id,body.version]));
  const commands=merge(catalog.commands,[command],'contract_cid',body=>body.command_id);
  const completed=sealed({...oldBody,contracts,commands},'catalog_cid');
  const declaration={...declared,catalog:canonical(completed),catalog_cid:completed.catalog_cid,
    contracts:contracts.map(canonical),command_bodies:commands.map(canonical)};
  const targetRef=`connector://${connectorId}/files`;
  const identity={version:'actql.collection_resource_identity/0.1',provider_namespace:'local',
    resource_kind:'file_collection',target_ref:targetRef,collection_identity:{root:rootPath},
    boundary_topology:'connector_connection'};
  const schema={type:'object',nullable:false,additional_properties:false,fields};
  const writable=['content','overwrite','path'];
  const mapping=sealed({schema:'actql.mapping_contract/0.1',
    mapping_ref:`mapping:${connectorId}.local.files.store.v1`,version:'local/0.1',target_ref:targetRef,
    connector_manifest_cid:declared.manifest_entry_cid,resource_identity_cid:cid(identity),
    target_schema_identity:cid(schema),target_schema:schema,primary_identity:null,writable_fields:writable,
    required_fields:required,conversions:[],permission_rules:[required,writable].map(write_fields=>({
      effect_kind:'create',selector_class:'none',write_fields,permissions})),required_permissions:permissions,
    minimum_approval:'required',row_mapping:Object.fromEntries(writable.map(field=>[field,{field,null_behavior:'reject'}])),
    store_command:{catalog_cid:completed.catalog_cid,command_ref:command.command_id,
      command_contract_cid:command.contract_cid}},'mapping_contract_cid');
  const outputWires={declarationWire:canonical(declaration),commandWire:canonical(command),
    mappingWire:canonical(mapping),identityWire:canonical(identity)};
  if(Object.values(outputWires).some(wire=>Buffer.byteLength(wire)>maxBytes))fail();
  return Object.freeze(outputWires);
}

type DeclarationCalls = Readonly<{
  clientProgramRowSourceRestoreRelationDeclaration(connection: string, registration: string, revision: string,
    viewsWire: string, expectedCatalogCid: undefined): unknown;
  clientProgramRowSourceDeclarationJson(declaration: unknown): string;
}>;
type DeclarationCall = <Name extends keyof DeclarationCalls>(name: Name, ...args: Parameters<DeclarationCalls[Name]>) =>
  ReturnType<DeclarationCalls[Name]>;
type LocalFileDeclarationLimits = Readonly<Record<'maxFiles' | 'maxEntries' | 'maxPages' | 'maxAttempts' |
  'maxListingBytes' | 'maxDurationMs' | 'maxPathBytes' | 'maxPageBytes', number>>;
type DeclarationViews = Readonly<{views: readonly Readonly<{resource: unknown; carrier_schema_cid: unknown}>[]}>;

export function restoreDeclaration(call: DeclarationCall, connection: string, rootPath: string,
  versionMode: 'content' | 'metadata', limits: LocalFileDeclarationLimits,
  canonical: (value: unknown) => string, cid: (value: unknown) => string) {
  const string = (nullable: boolean) => ({type:'string',nullable});
  const resource = {type:'resource_ref',resource_kind:'file',nullable:false};
  const timestamp = (nullable: boolean) => ({type:'timestamp',nullable});
  const request = (fields: Data) => ({type:'object',nullable:false,additional_properties:false,fields});
  const fileSchema = {resource,version:string(false),name:string(false),path:string(false),
    size:{type:'int64',nullable:false},modified_time:timestamp(false),media_type:string(true),
    size_bytes:{type:'number',nullable:true},modified_at:timestamp(true)};
  const contentSchema = {resource,version:string(false),path:string(false),
    media_type:string(false),content:{type:'content_ref',nullable:false}};
  const view = (name: string,schema: Data,fields: Data,acquisition: Data) => ({resource:name,resource_kind:'file',
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
  const initial = JSON.parse(call('clientProgramRowSourceDeclarationJson',restore())) as DeclarationViews;
  // Catalog declarations describe the selected physical scope. They never
  // admit a Root, Account decision, original reader or cleanup observation.
  const scopeCid = cid({connector:'local',connection,root:rootPath});
  const versionCid = cid({connector:'local',version_mode:versionMode,
    representation:'exact_stored_bytes',metadata_fields:['size','modified_seconds','modified_nanos']});
  views[0].facts_wire = canonical({file_listing:{version:'actql-file-list/0.1',kind:'file_listing',
    selectable:['paths','glob'],allow_unfiltered_listing:true,admitted_scope_contract_cid:scopeCid,
    listing_schema_contract_cid:initial.views.find(view=>view.resource==='files')!.carrier_schema_cid,
    version_capability:{contract_cid:versionCid,required_nonnull:true},
    max_listing_items:limits.maxFiles,max_examined_items:limits.maxEntries,
    max_listing_pages:limits.maxPages,max_request_attempts:limits.maxAttempts,
    max_listing_bytes:limits.maxListingBytes,max_listing_duration_ms:limits.maxDurationMs,
    maximum_path_length:limits.maxPathBytes}});
  views[1].facts_wire = canonical({file_content:{version:'actql-file-content/0.1',kind:'file_content',
    admitted_scope_contract_cid:scopeCid,
    content_schema_contract_cid:initial.views.find(view=>view.resource==='contents')!.carrier_schema_cid,
    version_capability:{contract_cid:versionCid,required_nonnull:true},representation:'exact_stored_bytes'},
  lookup_capacity:{version:'actql-lookup-capacity/0.1',completeness:'complete_per_requested_key',
    max_rows_per_key:1,max_pages_per_request:limits.maxPages,max_response_bytes_per_page:limits.maxPageBytes}});
  const declaration = restore();
  const store=localFileStoreDeclaration(call('clientProgramRowSourceDeclarationJson',declaration),
    {connectorId:connection,rootPath,maxBytes:131072});
  return Object.freeze({declaration,wire:store.declarationWire,scopeCid,versionCid});
}
