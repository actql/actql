import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installNodeContentRun} from './installed-content-run.mjs';

// Actual methods with explicit Core/current ports. These are not a compiled
// Common ABI, a physical capacity admission or an ordinary Content receipt.
function method(file, name, ports) {
  const source=readFileSync(new URL(file,import.meta.url),'utf8');let found;
  const walk=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name===name){assert(!found);found=node;}
    for(const value of Object.values(node)){
      if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);
    }};
  walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(found,name);
  return Function(...Object.keys(ports),`return ({${source.slice(found.start,found.end)}}).${name};`)(...Object.values(ports));
}
const fail=code=>{throw Object.assign(new Error(code),{code});};
function managerFixture({compileFailure,completeFailure}={}) {
  const prepared={},request={},identity={},parent={},input={},graph={},artifact={},selected={},value={},original={};
  const holder={},admission={},calls=[],runs=new WeakMap(),liveRuns=new Set(),view={};
  const moon={clientProgramPreparationBorrowRead:h=>{assert.equal(h,holder);return prepared;},
    clientProgramCompleteRequestSerializationPreparation(p,i,s){
      assert.deepEqual([p,i,s],[parent,input,selected]);assert.equal(state.contentPlan,selected);calls.push('complete');
      if(completeFailure)throw completeFailure;
    },
    clientProgramAdoptRequestContentPreparation(p,r){assert.deepEqual([p,r],[parent,identity]);calls.push('adopt');return value;}};
  const state={parent,prepared,holder,compilationFamily:'content',context:{runtime:moon},original};
  const producer={receipt:input,preparation:state,liveRuns:0};
  const ports={current:()=>{},producerForRequest:r=>{assert.equal(r,request);return producer;},
    fail,originals:{installation:{sequenceContractOriginal:{moon,admission}}},view,checked:v=>v,
    callbacks:{request:(_o,p)=>{assert.equal(p,prepared);return request;}},runs,liveRuns};
  for(const name of ['prepareContentCompilation','prepareSerializationRun','adoptContentPreparation']){
    view[name]=method('./ordinary-source-managed.mjs',name,ports);
  }
  const compile=(p,i,g,c)=>{assert.deepEqual([p,i,g,c],[parent,input,graph,admission]);calls.push('compile');
    assert(state.preparing);if(compileFailure)throw compileFailure;return artifact;};
  const construct=(p,i)=>{assert.deepEqual([p,i],[parent,input]);assert.equal(state.contentCompilation,artifact);
    calls.push('construct');assert(state.preparing);
    assert.throws(()=>view.prepareSerializationRun(prepared,request,identity,construct),{code:'ForeignInstalledSourceProducer'});
    return selected;};
  return{calls,state,selected,value,artifact,graph,prepared,runs,
    compile:()=>view.prepareContentCompilation(prepared,request,graph,compile),
    foreign:()=>view.prepareContentCompilation(prepared,request,{},compile),
    adopt:()=>view.prepareSerializationRun(prepared,request,identity,construct)};
}

test('Request Content manager compiles one original graph and completes its same selected prefix before adoption',()=>{
  const f=managerFixture();assert.equal(f.compile(),f.artifact);assert.equal(f.compile(),f.artifact);
  assert.throws(f.foreign,{code:'ForeignInstalledSourceProducer'});
  const run=f.adopt();assert.equal(run.value,f.value);assert.equal(run.content,f.selected);
  assert.equal(f.runs.get(f.prepared),run);assert.equal(f.state.contentCompilation,undefined);
  assert.deepEqual(f.calls,['compile','construct','complete','adopt']);
});

test('Request Content manager retains its original constructor and completion failures without compiling or issuing twice',()=>{
  const primary=new Error('same-original-compiler'),f=managerFixture({compileFailure:primary});
  assert.throws(f.compile,e=>e===primary);assert.throws(f.compile,e=>e===primary);
  assert.equal(f.state.contentGraph,f.graph);assert.deepEqual(f.calls,['compile']);
  const failed=new Error('same-original-completion'),g=managerFixture({completeFailure:failed});
  g.compile();assert.throws(g.adopt,e=>e===failed);assert.throws(g.adopt,e=>e===failed);
  assert.equal(g.state.contentPlan,g.selected);assert.equal(g.state.contentCompilation,g.artifact);
  assert.deepEqual(g.calls,['compile','construct','complete']);
});

function hostFixture({constructFailure}={}) {
  const prepared={},request={},sdkRequest={},parent={},input={},selected={},original={},value={},limits={},workspace={};
  const plan={kind:'serialization',compiled:{},runDefinition:{}},calls=[],record={},originalInstallation={},originals={};
  const primary=new Error('same-consumed-parent-return');let cleanup=true,severFailure;
  const content={prepareRequestPrefix(p,i,r,c,d,l,w){
    assert.deepEqual([p,i,r,c,d,l,w],[parent,input,request,plan.compiled,plan.runDefinition,limits,workspace]);
    assert.equal(record.computeRuns.get(prepared).selecting,true);calls.push('prefix-plan');return selected;
  },cleanupRequestPrefix(v,s){assert.equal(this,content);assert.deepEqual([v,s],[value,selected]);
    calls.push('prefix-cleanup');if(cleanup instanceof Error)throw cleanup;return cleanup;}};
  const moon={clientProgramInstalledManagedRunCheck(v,p,r){assert.equal(this,moon);assert.deepEqual([v,p,r],[value,prepared,request]);},
    clientProgramInstalledManagedRunRetire(v){assert.equal(this,moon);assert.equal(v,value);calls.push('parent-retire');},
    clientProgramInstalledPreparationPayloadSevered:()=>true};
  const manager={prepareSerializationRun(p,r,identity,construct){
    assert.deepEqual([p,r,identity],[prepared,sdkRequest,request]);construct(parent,input);
    if(constructFailure)throw constructFailure;return{original,value};
  },severPreparation(p,o){assert.deepEqual([p,o],[prepared,original]);calls.push('sever');
    if(severFailure){const failure=severFailure;severFailure=undefined;throw failure;}}};
  const ports={sourceManaged:manager,computeManaged:undefined,moon,record,originalInstallation,originals,
    runtimeCore:()=>({contentGenerationControl:content}),clientOperationError:code=>Object.assign(new Error(code),{code}),
    assertSourceManagedInstallationCurrent:()=>{},originalSourceManagedHostRequest:()=>sdkRequest,checked:v=>v,
    managedPreparationRetirementContinuation:run=>{assert(run.serializationCleaned);return()=>calls.push('finish');}};
  const prepare=method('./embedded-local.mjs','prepareManagedSerializationRun',ports),retire=method('./embedded-local.mjs','retireManagedComputeRun',ports);
  return{record,calls,prepared,selected,value,primary,content,
    begin:()=>prepare(moon,prepared,request,plan,limits,workspace),retire:()=>retire(prepared),
    setCleanup:v=>{cleanup=v;},failSever:()=>{severFailure=primary;}};
}

test('Request Content Host spends the same prefix ACK once across a consumed parent-return failure',()=>{
  const f=hostFixture(),run=f.begin();assert.equal(f.begin(),run);assert.equal(run.serialization,f.selected);
  f.setCleanup(false);assert.throws(f.retire,{code:'InstalledContentRunCleanupPending'});
  assert(!f.calls.includes('parent-retire'));assert.equal(run.serializationCleaned,false);
  const primary=new Error('original-child-cleanup');f.setCleanup(primary);assert.throws(f.retire,e=>e===primary);
  f.setCleanup(true);f.failSever();assert.throws(f.retire,e=>e===f.primary);assert.equal(run.serializationCleaned,true);
  f.content.cleanupRequestPrefix=()=>assert.fail('Captured original receiver/method must be retained');
  const finish=f.retire();finish();assert.equal(f.calls.filter(x=>x==='prefix-cleanup').length,3);
  assert.equal(run.prepared,undefined);assert.equal(run.serialization,undefined);
});

test('Request Content Host keeps a refused Plan on its original failed bag without entering prefix execution',()=>{
  const primary=new Error('original-adoption-refused'),f=hostFixture({constructFailure:primary});
  assert.throws(f.begin,e=>e===primary);assert.throws(f.begin,e=>e===primary);
  const run=f.record.computeRuns.get(f.prepared);assert.equal(run.serialization,f.selected);
  assert.equal(run.failure,primary);assert.equal(f.calls.filter(x=>x==='prefix-plan').length,1);
  f.retire();assert.equal(f.record.computeRuns.has(f.prepared),false);
  assert(!f.calls.includes('prefix-cleanup'));assert(!f.calls.includes('parent-retire'));
});

test('terminal Content failed start retries only the same retained managed prefix cleanup without a scalar Ledger',async()=>{
  const preparedProgram={},request={},selected={},managed={value:{},serialization:selected,closed:false},compiled={};
  const plan={kind:'serialization',compiled,serializationGraph:{task:0,step:1},
    runDefinition:{identity:'definition',wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'}};
  const primary=new Error('original-start-after-prefix-retention');let execution,cleanupReady=false,prepares=0,cleanups=0,starts=0;
  const control={workspaceCapacity:()=>({}),requestPrefixCapacity:s=>{assert.equal(s,selected);return{retainedBytes:7n,executionBytes:9n};},
    prefixCapacity(){assert.fail('No provider reconstruction or capacity traversal');},
    prefix(){assert.fail('No scalar-ledger prefix path');},
    startRequestPrefix(run,p,s){assert.deepEqual([run,p,s],[managed.value,preparedProgram,selected]);starts++;throw primary;},
    cleanupRequestPrefix(run,s){assert.deepEqual([run,s],[managed.value,selected]);cleanups++;return cleanupReady;}};
  const run=installNodeContentRun({moon:{clientProgramAcquisitionCount:()=>0,
    clientProgramAcquisitionLedger:()=>assert.fail('Request terminal Content cannot create another Ledger')},
    core:{contentGenerationControl:control,publicationControl:{checkClientCompiledRunOwner:()=>{},
      checkedClientSerializationGenerationLimits:()=>({maxRows:1,maxBytes:16})}},
    preparedRunRequired:true,assertRunCurrent:()=>{},ownerPrincipal:'principal',storeAuthorityCid:'store',
    now:()=> '2026-10-31T00:00:00.000Z',authorize:()=>true,
    prepareSerializationManagedRun(p,r,actual){assert.deepEqual([p,r,actual],[preparedProgram,request,plan]);prepares++;return managed;}});
  run.prepareRun({preparedProgram,request,plan});run.prepareRun({preparedProgram,request,plan});assert.equal(prepares,1);
  const store={storeAuthorityCid:'store',status:()=>({closed:false}),confirmCommittedIndex:async()=>undefined};
  await assert.rejects(run({preparedProgram,plan,store,principalId:'principal',retainExecution:owner=>{execution=owner;}}),e=>e===primary);
  assert.equal(execution.cleanupPending(),true);assert.equal(await execution.cleanup(),false);
  assert.equal(starts,1);cleanupReady=true;assert.equal(await execution.cleanup(),true);assert.equal(cleanups,2);
  assert.equal(await execution.cleanup(),true);assert.equal(cleanups,2);assert.equal(starts,1);
});
