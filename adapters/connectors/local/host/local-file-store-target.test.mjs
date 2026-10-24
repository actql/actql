// Actual Local adapter wiring with explicit existing Common ports. These
// controls issue no real Reference, permission, physical Root or file write.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';
import {prepareLocalFileStoreTarget} from './local-file-store-target.mjs';

const wire=value=>canonicalJson(value,{dataKeys:true});
const hash=bytes=>'sha256:'+createHash('sha256').update(bytes).digest('hex');
const cid=value=>hash(wire(value));
const ok=value=>({$tag:1,_0:value});
const fixture=()=>{
  const manifest={connector:'local',connector_id:'local',connector_version:'local/0.1'};
  const body={schema:'actql.connector_catalog/0.1',connector_id:'local',
    connector_version:'local/0.1',source_views:[],commands:[],contracts:[]};
  const catalog={...body,catalog_cid:cid(body)};
  const declaredWire=JSON.stringify({connector_id:'local',connector_registration:'local',
    connector_version:'local/0.1',catalog:wire(catalog),catalog_cid:catalog.catalog_cid,
    contracts:[],command_bodies:[],manifest_entry:wire(manifest),manifest_entry_cid:cid(manifest)});
  const options={connectorId:'local',rootPath:'/owned/root-e\u0301',maxBytes:131072,
    scopeCid:'sha256:'+'a'.repeat(64),authorityScopeCid:'sha256:'+'b'.repeat(64),
    maxNodes:16384,maxDepth:64};
  // The fixture supplies an independently hashed complete installed member,
  // matching the existing bridge's member_cid projection, not its self-CID.
  const data=localFileStoreDeclaration(declaredWire,options),declared=JSON.parse(data.declarationWire);
  const mapping=JSON.parse(data.mappingWire),command=JSON.parse(data.commandWire);
  const memberCid=hash(declared.catalog),semanticCid=declared.catalog_cid;
  assert.notEqual(memberCid,semanticCid);
  const selection=[mapping.target_ref,mapping.mapping_ref,mapping.mapping_contract_cid,
    command.command_id,command.contract_cid,memberCid,'file_collection',cid(JSON.parse(data.identityWire))];
  const pair=Object.freeze({explicitPortPair:true}),issuer=Object.freeze({explicitPortIssuer:true});
  const reference=Object.freeze({explicitPortReference:true}),foreign=new Error('OriginalPairRefused'),retired=new Error('OriginalInstallationRetired');
  let live=true,retireDuringSelection=false,reads=0,issues=0,selected=selection,resourceWire;
  const moon={
    clientProgramResourceReferenceIssuer(admit,current){
      assert.strictEqual(this,moon);assert.equal(typeof admit,'function');assert.equal(typeof current,'function');return issuer;
    },
    clientProgramEffectStoreCommandSelection(original){
      assert.strictEqual(this,moon);reads++;
      if(original!==pair)return{$tag:0,_0:foreign};
      if(retireDuringSelection)live=false;
      return ok(selected);
    },
    clientProgramIssueStoreCollectionReference(original,actualIssuer,body,maxBytes,maxNodes,maxDepth){
      assert.strictEqual(this,moon);assert.strictEqual(original,pair);assert.strictEqual(actualIssuer,issuer);
      assert.deepEqual([maxBytes,maxNodes,maxDepth],[131072,16384,64]);
      issues++;resourceWire=body;return ok(reference);
    },
  };
  const target=prepareLocalFileStoreTarget(moon,{...options,declaredWire,
    assertCurrent(){if(!live)throw retired;}});
  return{moon,target,pair,reference,selection,memberCid,semanticCid,foreign,retired,
    select(value){selected=value;},retireDuringSelection(){retireDuringSelection=true;},
    reads:()=>reads,issues:()=>issues,resource:()=>JSON.parse(resourceWire)};
};

test('Local collection Reference binds the full installed Catalog member identity',()=>{
  const f=fixture();
  assert.strictEqual(f.target.issueOriginalCollectionReference(f.pair,1000),f.reference);
  assert.equal(f.reads(),1);assert.equal(f.issues(),1);
  assert.equal(f.resource().boundary_cid,f.semanticCid,
    'the Resource boundary keeps its original semantic Catalog identity');
  assert.notEqual(f.resource().boundary_cid,f.memberCid);
});

test('Local collection Reference still refuses every changed tuple and foreign original pair',()=>{
  const f=fixture();
  for(let index=0;index<f.selection.length;index++){
    const changed=[...f.selection];changed[index]='foreign';f.select(changed);
    assert.throws(()=>f.target.issueOriginalCollectionReference(f.pair,1000),{code:'ForeignLocalStoreSelection'});
  }
  f.select([...f.selection.slice(0,5),f.semanticCid,...f.selection.slice(6)]);
  assert.throws(()=>f.target.issueOriginalCollectionReference(f.pair,1000),{code:'ForeignLocalStoreSelection'});
  assert.throws(()=>f.target.issueOriginalCollectionReference({...f.pair},1000),error=>error.cause===f.foreign);
  assert.equal(f.issues(),0);
});

test('Local collection Reference retains methods receiver limits and current fence after selection',()=>{
  const f=fixture();
  for(const work of [0,-1,NaN,2147483648])assert.throws(
    ()=>f.target.issueOriginalCollectionReference(f.pair,work),{code:'LocalStoreReferenceInvalidLimits'});
  assert.equal(f.reads(),0);
  f.moon.clientProgramEffectStoreCommandSelection=()=>assert.fail('Do not reacquire a changed method');
  f.retireDuringSelection();
  assert.throws(()=>f.target.issueOriginalCollectionReference(f.pair,1000),error=>error===f.retired);
  assert.equal(f.reads(),1);assert.equal(f.issues(),0);
});
