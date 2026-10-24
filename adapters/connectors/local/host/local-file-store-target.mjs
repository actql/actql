// Installation-private collection Reference wiring. Declaration bytes select
// no permission: the same installed current callback and original issuer own
// availability; Common retains the nominal checked Mapping/Command pair.
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';

const canonical = value => canonicalJson(value,{dataKeys:true});
const cid = value => 'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const isCid = value => typeof value==='string'&&/^sha256:[0-9a-f]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const fail = code => {throw Object.assign(new Error(code),{code});};

export function prepareLocalFileStoreTarget(moon,{declaredWire,connectorId,rootPath,
  scopeCid,authorityScopeCid,assertCurrent,maxBytes,maxNodes,maxDepth}) {
  if(!isCid(scopeCid)||!isCid(authorityScopeCid)||typeof assertCurrent!=='function'||
      ![maxBytes,maxNodes,maxDepth].every(positive)) fail('InvalidLocalStoreTarget');
  const ports=Object.freeze(Object.fromEntries(['clientProgramResourceReferenceIssuer',
    'clientProgramEffectStoreCommandSelection','clientProgramIssueStoreCollectionReference'].map(name=>{
    const method=moon?.[name];
    if(typeof method!=='function')fail('LocalStoreReferenceRuntimeUnavailable');
    return[name,method];
  })));
  const call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  const current=()=>{
    const result=assertCurrent();
    if(result!==undefined){
      if(result instanceof Promise)void result.catch(()=>{});
      fail('InvalidLocalStoreCurrentFence');
    }
  };
  current();
  const data=localFileStoreDeclaration(declaredWire,{connectorId,rootPath,maxBytes});
  const declared=JSON.parse(data.declarationWire),mapping=JSON.parse(data.mappingWire),
    command=JSON.parse(data.commandWire);
  const catalogMemberCid='sha256:'+createHash('sha256').update(declared.catalog).digest('hex');
  const selection=Object.freeze([mapping.target_ref,mapping.mapping_ref,mapping.mapping_contract_cid,
    command.command_id,command.contract_cid,catalogMemberCid,'file_collection',cid(JSON.parse(data.identityWire))]);
  const resourceWire=canonical({$actql_ref:'resource',version:'actql-resource-ref/0.1',
    provider_namespace:'local',resource_kind:'file_collection',provider_identity_cid:scopeCid,
    authority_scope_cid:authorityScopeCid,boundary_cid:declared.catalog_cid,identity_cid:selection[7]});
  const issuer=call('clientProgramResourceReferenceIssuer',
    (kind,wire)=>kind==='file_collection'&&wire===resourceWire,
    wire=>{
      if(wire!==resourceWire)return false;
      try{current();return true;}catch{return false;}
    });
  current();
  return Object.freeze({...data,resourceWire,
    targetRef:selection[0],mappingRef:selection[1],commandRef:selection[3],
    issueOriginalCollectionReference(pair,maxWork){
      current();
      if(!positive(maxWork))fail('LocalStoreReferenceInvalidLimits');
      const actual=checked(call('clientProgramEffectStoreCommandSelection',pair));
      if(!Array.isArray(actual)||actual.length!==selection.length||
          actual.some((value,index)=>value!==selection[index]))fail('ForeignLocalStoreSelection');
      current();
      const reference=checked(call('clientProgramIssueStoreCollectionReference',pair,issuer,
        resourceWire,maxBytes,maxNodes,maxDepth));
      current();return reference;
    },
  });
}
