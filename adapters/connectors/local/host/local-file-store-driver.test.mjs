// Real Local driver composition with explicit Run/Content/native ports.
// No Account grant, actual FD, Common Reference or physical STORE is supplied.
import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createLocalFileStoreDriver,LOCAL_STORE_LIMITS} from './installed-project-file-effects.mjs';

const cid=digit=>'sha256:'+digit.repeat(64);
const wire=value=>canonicalJson(value,{dataKeys:true});
function fixture(){
  const run=Object.freeze({}),binding=Object.freeze({});
  const resource=Object.freeze({$actql_ref:'resource',version:'actql-resource-ref/0.1',
    provider_namespace:'local',resource_kind:'file_collection',provider_identity_cid:cid('a'),
    authority_scope_cid:cid('b'),boundary_cid:cid('c'),identity_cid:cid('d')});
  const content=Object.freeze({$actql_ref:'content',identity_cid:cid('e')});
  const value={path:'out.jsonl',content:{...content}};
  const command={command_id:'command:local.local.files.store.v1',contract_cid:cid('f')};
  const member={kind:'command',resource:'files',command:{commandRef:command.command_id,
    commandCid:command.contract_cid}};
  const limits={...LOCAL_STORE_LIMITS,maxFileBytes:1024};
  let live=true,nativeCalls=0;
  const nativeFilesystem=Object.freeze(Object.fromEntries(['openFileRoot','openFileDirectory',
    'openRootFileWriter','fileRootCurrent','fileRootWrite','fileRootPublish','fileRootClose']
    .map(name=>[name,()=>{nativeCalls++;assert.fail('No native use before approved send');}])));
  const borrowed=Object.freeze({binding,current:()=>live,wire:()=>wire(content)});
  const contentOwner=Object.freeze({consumeContent(){assert.fail('No byte read before approved send');}});
  const {driver,site}=createLocalFileStoreDriver({entry:{connection:'local',rootPath:'/original/root',
    limits:{maxPathBytes:1024}},target:{resourceWire:wire(resource)},command,bindingCid:cid('1'),
    principalId:'reader',authorization:{configurationCid:cid('2')},assertCurrent(){},
    resources:{assertCurrent(original){assert.strictEqual(original,run);},limits(original){
      assert.strictEqual(original,run);return limits;}},limits,nativeFilesystem});
  const selected=driver.describe({member,runOriginal:run,runInvocationCid:cid('3'),dispatchRequestCid:cid('4')});
  const prepare=(changes={})=>driver.prepareRequestChild({member,runOriginal:run,value,
    selector:resource,current:selected,content:name=>{assert.equal(name,'content');return borrowed;},
    contentOwner,...changes});
  return{driver,site,run,member,selected,resource,value,prepare,contentOwner,
    retire(){live=false;},nativeCalls:()=>nativeCalls};
}

test('Local STORE retains original Content borrower and exact input before approval without I/O',async()=>{
  const f=fixture(),child=f.prepare(),prepared=child.prepare();
  f.value.path='changed';f.value.content.identity_cid=cid('9');
  const facts=f.driver.requestFacts(prepared.request);
  assert.equal(facts.value.path,'out.jsonl');assert.equal(facts.value.content.identity_cid,cid('e'));
  assert.deepEqual(facts.target,f.resource);
  f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run});
  assert.equal(f.nativeCalls(),0);
  f.retire();
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run}),
    {code:'OriginalEffectContentUnavailable'});
  assert.equal(await child.release(),true);assert.equal(child.status().pending,false);
  assert.throws(()=>f.driver.requestFacts(prepared.request),{code:'ForeignLocalStoreRequest'});
  await f.site.close();assert.equal(f.nativeCalls(),0);
});

test('Local STORE rejects changed, missing and foreign originals before native acquisition',async()=>{
  const f=fixture();
  for(const changes of [
    {content:()=>({current:()=>false,wire:()=>''})},
    {content:()=>({current:()=>true,wire:()=>'{"foreign":true}'})},
    {value:{path:'../escape',content:f.value.content}},
    {selector:{...f.resource,identity_cid:cid('9')}},
  ]){
    const child=f.prepare(changes);
    assert.throws(()=>child.prepare());
    assert.equal(await child.release(),true);
  }
  const missing=f.prepare({contentOwner:undefined}),prepared=missing.prepare();
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:f.run}),
    {code:'OriginalEffectContentUnavailable'});
  assert.throws(()=>f.driver.requestFacts({...prepared.request}),{code:'ForeignLocalStoreRequest'});
  assert.throws(()=>f.driver.recheckRequests({member:f.member,entries:[prepared],runOriginal:{}}));
  await missing.release();await f.site.close();assert.equal(f.nativeCalls(),0);
});

test('Local STORE accepts no structural Account or approval substitute',async()=>{
  const f=fixture();
  assert.throws(()=>f.site.issueEffectGrant({operation:'files.write',resource:'files',
    runInvocationCid:cid('3'),dispatchRequestCid:cid('4'),subjectCid:cid('5'),
    decision:{action:'dispatch',boundary:'effect_commit',subjectCid:cid('5'),basis:'resumed',
      checkpointCid:cid('6'),resolutionCid:cid('7'),
      tuple:{connection:'local',resource:'files',operation:'effect'}}}),{code:'LocalStoreNotAuthorized'});
  assert.equal(f.nativeCalls(),0);await f.site.close();
});

test('Local STORE recovered request connects the retained original Content child before any send',async()=>{
  const f=fixture(),capture=f.prepare(),initial=capture.prepare();
  const saved=f.driver.recoveryEntry({entries:[initial]});
  const member={...f.member,memberIndex:0};
  const restored=f.driver.recoverRequests({
    durable:{connectorRecovery:[{memberIndex:0,...saved}]},
    body:{effects:[{changes:[{}]}]},runOriginal:f.run,members:[member],
    runInvocationCid:cid('3'),dispatches:[cid('4')]});
  const request=restored.requests[0][0],entries=[[{request,requestCid:f.driver.requestCid(request)}]];
  const prepared={},allowed={},definition={},source={},events=[];
  let pending=true;
  const borrowed={binding:{},current:()=>pending};
  const contentOwner={consumeContent(){assert.fail('No bytes are sent during recovery preparation');}};
  const recovered={prepared,allowed,runDefinition:definition,computation:{
    effectSources:[{memberIndex:0,source}],preview:{},invocation:{},computation:{capturedRun:{}}}};
  const child=f.driver.prepareRecoveredContentChild({recovered,members:[member],entries,memberIndexes:[0],
    control:{adoptCheckedClientEffectSerializationRun(value,run){
      assert.strictEqual(value,allowed);assert.strictEqual(run,definition);return{};}},
    store:{},principalId:'reader',runOriginal:f.run,limits:{maxFields:10,maxWork:1000,
      body:{maxBytes:10000,maxNodes:1000,maxDepth:64}},
    contentRun:{prepareRecoveredCommandContent(options){
      assert.strictEqual(options.prepared,prepared);assert.strictEqual(options.source,source);
      assert.equal(options.row,0);assert.equal(options.inputName,'content');
      assert.equal(options.referenceWire,wire(f.value.content));
      events.push('construct');return{
        async prepare(){events.push('prepare');return{borrow:borrowed,contentOwner};},
        async release(){events.push('release');pending=false;return true;},status:()=>({pending})};}}});
  assert.deepEqual(events,[]);assert.equal(child.status().pending,true);
  await child.prepare();assert.deepEqual(events,['construct','prepare']);
  f.driver.recheckRequests({member,entries:entries[0],runOriginal:f.run});
  assert.equal(f.nativeCalls(),0);
  assert.equal(await child.release(),true);assert.equal(child.status().pending,false);
  assert.throws(()=>f.driver.requestFacts(request),{code:'ForeignLocalStoreRequest'});
  assert.throws(()=>child.prepare(),{code:'LocalStoreRecoveryAlreadyAttempted'});
  await capture.release();await f.site.close();assert.equal(f.nativeCalls(),0);
});
