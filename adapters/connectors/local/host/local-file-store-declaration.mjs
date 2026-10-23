// Local Connector declaration DATA. The original installed Host must retain
// the checked Mapping/Command pair and issue the collection Reference under
// its actual installation/current authority. None of these strings grants I/O.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';

const canonical = value => canonicalJson(value,{dataKeys:true});
const cid = value => 'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const fail = () => {throw Object.assign(new Error('InvalidLocalFileStoreDeclaration'),
  {code:'InvalidLocalFileStoreDeclaration'});};
const text = (value,max) => typeof value==='string'&&value.length>0&&value.isWellFormed()&&
  !value.includes('\0')&&Buffer.byteLength(value)<=max;
const sealed = (body,field) => ({...body,[field]:cid(body)});
const sorted = (members,key) => [...members].sort((a,b)=>a[key]<b[key]?-1:a[key]>b[key]?1:0);
const keys = (value,names) => value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...names].sort().join('\0');

export function localFileStoreDeclaration(declaredWire,{connectorId,rootPath,maxBytes}) {
  if(!text(connectorId,128)||!text(rootPath,4096)||!isAbsolute(rootPath)||
      !Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>1048576||
      typeof declaredWire!=='string'||Buffer.byteLength(declaredWire)>maxBytes)fail();
  const read = wire => {
    if(typeof wire!=='string'||Buffer.byteLength(wire)>maxBytes)fail();
    let body;try{body=JSON.parse(wire);}catch{fail();}
    // The existing Common declaration wrapper preserves its own field order;
    // it is not required to be canonical text. Catalog/member CIDs below and
    // the eventual Common environment admission check the actual bodies.
    return body;
  };
  const record = value => value!==null&&typeof value==='object'&&!Array.isArray(value);
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
  const role=(kind,body)=>sealed({schema:'actql.contract/0.1',
    id:`${connectorId}.local.files.store.${kind}`,version:'local/0.1',kind,body},'cid');
  const input=role('command_input',inputBody);
  const output=role('command_output',{type:'object',nullable:false,additional_properties:false,fields:{}});
  const reference=({id,version,cid})=>({id,version,cid});
  const permissions=['files.write'];
  const command=sealed({schema:'actql.command_contract/0.1',
    command_id:`command:${connectorId}.local.files.store.v1`,connector_id:connectorId,version:'local/0.1',
    target:{resource_kind:'file_collection',cardinality:'single'},input_schema:reference(input),
    input_contract:inputBody,output_schema:reference(output),permissions,minimum_approval:'required',
    preview:{strength:'exact'},outcome:'synchronous',idempotency:{support:'unsupported'},
    reversibility:'unknown',atomicity:'single_target'},'contract_cid');
  const merge=(original,additional,key,selector)=>{
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
