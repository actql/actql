// Existing Notion originals projected for the same installed publication's
// credential Site. These targets/facts are DATA, not Account decisions,
// issuer/material membership, resource funding, egress or permission.
import {types} from 'node:util';
import {NOTION_DATABASE_RETRIEVE_OPERATION,NOTION_DATA_SOURCE_RETRIEVE_OPERATION}
  from '../site/database-discovery.mjs';

const fail=code=>{throw Object.assign(new TypeError(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed();
const selectedNames=['selection','declaration','database','operation','origin','method','path','bodyBytes'];
function selectedData(value){
  if(value===null||typeof value!=='object'||types.isProxy(value)||
      Object.getPrototypeOf(value)!==Object.prototype)fail('InvalidNotionMetadataSelection');
  const descriptors=Object.getOwnPropertyDescriptors(value),names=Reflect.ownKeys(descriptors);
  if(names.length!==selectedNames.length||names.some(name=>!selectedNames.includes(name)))fail('InvalidNotionMetadataSelection');
  return Object.fromEntries(selectedNames.map(name=>{
    const d=descriptors[name];
    if(!d?.enumerable||!Object.hasOwn(d,'value'))fail('InvalidNotionMetadataSelection');
    return[name,d.value];
  }));
}

// Only this trusted installer chooses the declaration, endpoint and resource.
// A selected wrapper carries opaque originals; its JSON fields or CID alone
// cannot supply those originals or independently authorize a metadata use.
export function prepareNotionDatabaseMetadataTargets({moon,declaration,origin,resource,maxTargetBytes,maxResourceBytes}){
  if(!positive(maxTargetBytes)||!positive(maxResourceBytes)||!text(origin)||!text(resource)||
      origin.length>maxTargetBytes||resource.length>maxResourceBytes||
      Buffer.byteLength(origin)>maxTargetBytes||Buffer.byteLength(resource)>maxResourceBytes||
      declaration===null||typeof declaration!=='object'||types.isProxy(declaration))fail('InvalidNotionMetadataTargets');
  let url;
  try{url=new URL(origin);}catch{/* Closed refusal below. */}
  if(url?.protocol!=='https:'||url.origin!==origin)fail('InvalidNotionMetadataTargets');
  const names=['notionReadDatabaseId','notionReadSourceSelectionMatches','notionReadSourceSelectionId'];
  const ports=Object.freeze(Object.fromEntries(names.map(name=>{
    const d=Object.getOwnPropertyDescriptor(moon??{},name);
    if(!d||!Object.hasOwn(d,'value')||typeof d.value!=='function')fail('InvalidNotionMetadataTargets');
    return[name,d.value];
  })));
  const call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  const coordinate=(id,section)=>{
    if(!text(id)||id==='.'||id==='..')fail('InvalidNotionMetadataCoordinate');
    // Bound the UTF16 lower bound before URI output allocation. The exact
    // encoded target and its UTF8 bytes have their own independent bound.
    if(id.length>maxTargetBytes)fail('NotionMetadataTargetLimit');
    const path='/v1/'+section+'/'+encodeURIComponent(id);
    if(Buffer.byteLength(path)>maxTargetBytes)fail('NotionMetadataTargetLimit');
    return path;
  };
  const databasePath=coordinate(call('notionReadDatabaseId',declaration),'databases');
  let selected;
  const targetAuthority=Object.freeze({
    project(target,originalDeclaration){
      if(this!==targetAuthority||originalDeclaration!==declaration)fail('ForeignNotionMetadataTarget');
      let operation,path;
      if(target===declaration){operation=NOTION_DATABASE_RETRIEVE_OPERATION;path=databasePath;}
      else if(selected!==undefined&&target===selected.selection){
        if(call('notionReadSourceSelectionMatches',target,declaration,selected.database)!==true||
            coordinate(call('notionReadSourceSelectionId',target),'data_sources')!==selected.path)fail('ForeignNotionMetadataTarget');
        operation=NOTION_DATA_SOURCE_RETRIEVE_OPERATION;path=selected.path;
      }else fail('ForeignNotionMetadataTarget');
      return Object.freeze({resource,operation,origin,method:'GET',path,bodyBytes:0});
    },
  });
  const targets=Object.freeze({
    databaseTarget:declaration,targetAuthority,
    selectSource(original){
      if(this!==targets)fail('ForeignNotionMetadataTargets');
      if(selected!==undefined)fail('NotionMetadataSourceAlreadySelected');
      const value=selectedData(original);
      if(value.declaration!==declaration||value.operation!==NOTION_DATA_SOURCE_RETRIEVE_OPERATION||
          value.origin!==origin||value.method!=='GET'||value.bodyBytes!==0||
          call('notionReadSourceSelectionMatches',value.selection,declaration,value.database)!==true)fail('ForeignNotionMetadataSelection');
      const path=coordinate(call('notionReadSourceSelectionId',value.selection),'data_sources');
      if(value.path!==path)fail('ForeignNotionMetadataSelection');
      // Keep the exact selected occurrence/database before the Site can await
      // Account/current/sign/claim. Failure does not permit another selection.
      selected=Object.freeze({...value,path});
      return value.selection;
    },
  });
  return targets;
}
