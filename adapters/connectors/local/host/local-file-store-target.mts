// Installation-private collection Reference wiring. Declaration bytes select
// no permission: the same installed current callback and original issuer own
// availability; Common retains the nominal checked Mapping/Command pair.
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';

type Runtime = Readonly<{
  clientProgramResourceReferenceIssuer(validate: (kind: string, wire: string) => boolean,
    authorize: (wire: string) => boolean): unknown;
  clientProgramEffectStoreCommandSelection(pair: unknown): unknown;
  clientProgramIssueStoreCollectionReference(pair: unknown, issuer: unknown, resourceWire: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;
type TargetInput = Readonly<{declaredWire: unknown; connectorId: string; rootPath: string;
  scopeCid: unknown; authorityScopeCid: unknown; assertCurrent(): undefined;
  maxBytes: number; maxNodes: number; maxDepth: number}>;
type Declaration = Readonly<{catalog: string; catalog_cid: string}>;
type Mapping = Readonly<{target_ref: string; mapping_ref: string; mapping_contract_cid: string}>;
type Command = Readonly<{command_id: string; contract_cid: string}>;

const canonical = (value: unknown) => canonicalJson(value,{dataKeys:true});
const cid = (value: unknown) => 'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const isCid = (value: unknown): value is string => typeof value==='string'&&/^sha256:[0-9a-f]{64}$/u.test(value);
const positive = (value: number) => Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code),{code});};

export function prepareLocalFileStoreTarget(moon: Partial<Runtime> | null | undefined,{declaredWire,connectorId,rootPath,
  scopeCid,authorityScopeCid,assertCurrent,maxBytes,maxNodes,maxDepth}: TargetInput) {
  if(!isCid(scopeCid)||!isCid(authorityScopeCid)||typeof assertCurrent!=='function'||
      ![maxBytes,maxNodes,maxDepth].every(positive)) fail('InvalidLocalStoreTarget');
  const ports=Object.freeze(Object.fromEntries((['clientProgramResourceReferenceIssuer',
    'clientProgramEffectStoreCommandSelection','clientProgramIssueStoreCollectionReference'] as const).map(name=>{
    const method=moon?.[name];
    if(typeof method!=='function')fail('LocalStoreReferenceRuntimeUnavailable');
    return[name,method];
  })) as Runtime);
  const call=<Name extends keyof Runtime>(name: Name,...args: Parameters<Runtime[Name]>)=>
    Reflect.apply(ports[name] as (...args: Parameters<Runtime[Name]>) => unknown,moon,args);
  const current=()=>{
    const result: unknown=assertCurrent();
    if(result!==undefined){
      if(result instanceof Promise)void result.catch(()=>{});
      fail('InvalidLocalStoreCurrentFence');
    }
  };
  current();
  const data=localFileStoreDeclaration(declaredWire,{connectorId,rootPath,maxBytes});
  const declared=JSON.parse(data.declarationWire) as Declaration,mapping=JSON.parse(data.mappingWire) as Mapping,
    command=JSON.parse(data.commandWire) as Command;
  const catalogMemberCid='sha256:'+createHash('sha256').update(declared.catalog).digest('hex');
  const selection=Object.freeze([mapping.target_ref,mapping.mapping_ref,mapping.mapping_contract_cid,
    command.command_id,command.contract_cid,catalogMemberCid,'file_collection',cid(JSON.parse(data.identityWire))] as const);
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
    issueOriginalCollectionReference(pair: unknown,maxWork: number){
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
