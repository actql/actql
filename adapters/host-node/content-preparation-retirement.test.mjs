import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';
import {finishInstalledEffectModelScope} from './installed-effect-managed-run.mjs';

// Actual Content service and extracted Host retirement, with explicit Core
// payload/input witnesses. No Common Runtime, Resource stop or physical ACK is
// inferred from these ports or from the implementation's live-slot count.
const host=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
let selected;const walk=n=>{if(!n||typeof n!=='object')return;
  if(n.type==='Property'&&n.key?.name==='retireManagedComputeRun')selected=n;
  for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
walk(parse(host,{ecmaVersion:'latest',sourceType:'module'}));assert(selected);
function fixture({prefixFailure,constructFailure,retainFailure}={}) {
  const record={computeRuns:new WeakMap(),computeLiveRuns:new Set()},origins=new WeakMap(),held=[],captured=[],retained=[];
  const moon={clientProgramAcquisitionCount:p=>p.keyed?2:0,
    clientProgramKeyedAcquisitionMatchesProgram:(k,p)=>k===p.key,
    clientProgramInstalledPreparationPayloadSevered:(v,r)=>{const o=origins.get(v);o.observations=(o.observations??0)+1;
      if(o.observe)return o.observe();return o.request===r&&o.severed===true;},
    clientProgramPreparationBorrowRead:h=>h.prepared,
    clientProgramPreparationBorrowRetirementStarted:h=>h.retiring===true};
  const keep=(p,preparation)=>{if(retainFailure)throw retainFailure;preparation.inputHolder={prepared:p,retiring:false};retained.push(preparation);};
  function prepare(p,r,graph,recipe,preparation,keyed) {
    const value={},origin={request:r,severed:false,allowed:true};origins.set(value,origin);
    const run={runtime:moon,prepared:p,request:r,value,preparationFunded:true,preparationKind:keyed?'keyed-content-plan':'serialization-plan',
      serialization:{},serializationCleaned:false,content:{},manager:{severPreparation(){}},original:{},closed:false,
      selectedKeyed:{},contentCompilation:{},contentGraph:graph,contentRecipe:recipe};
    run.cleanupSerialization=()=>true;
    run.retire=()=>{origin.retireCalls=(origin.retireCalls??0)+1;if(origin.before)origin.before();if(!origin.allowed)return{$tag:0,_0:Object.assign(new Error('same cleanup pending'),{code:'OriginalCleanupPending'})};origin.severed=true;return{$tag:1,_0:undefined};};
    if(preparation!==undefined){preparation.managed=run;run.contentPreparation=preparation;
      run.releaseContentAliases=preparation.releaseAliases;captured.push(preparation);}
    record.computeRuns.set(p,run);record.computeLiveRuns.add(run);if(constructFailure){run.value=undefined;throw constructFailure;}return run;
  }
  const content=installNodeContentRun({moon,preparedRunRequired:true,assertRunCurrent(){},retainPreparation:keep,
    registry:'{}',values:'{}',ownerPrincipal:'fixture',
    prepareKeyedManagedRun:(p,r,g,recipe,preparation)=>prepare(p,r,g,recipe,preparation,true),borrowKeyedManagedLedger:()=>assert.fail('No physical Ledger'),
    prepareSerializationManagedRun:(p,r,plan,limits,workspace,preparation)=>prepare(p,r,plan.serializationGraph,undefined,preparation,false),
    core:{contentGenerationControl:{workspaceCapacity:()=>({retainedBytes:0n,executionBytes:0n}),
      prefixCapacity:()=>{if(prefixFailure)throw prefixFailure;return{retainedBytes:1n,executionBytes:1n};},requestPrefixCapacity:()=>({retainedBytes:1n,executionBytes:1n})},
      publicationControl:{checkClientCompiledRunOwner(c,p){assert.equal(c.owner,p);}}}});
  const ports={record,moon,checked,finishInstalledEffectModelScope,
    clientOperationError:code=>Object.assign(new Error(code),{code}),
    managedPreparationRetirementContinuation:run=>()=>{record.computeLiveRuns.delete(run);}};
  const retire=Function(...Object.keys(ports),`return ({${host.slice(selected.start,selected.end)}}).retireManagedComputeRun;`)(...Object.values(ports));
  const open=(keyed=true)=>{const p={keyed,key:{}},request={},graph={task:0,step:1},plan={kind:'serialization',serializationGraph:graph,compiled:{owner:p}};held.push(p);
    if(keyed)content.prepareManagedKeyedCompilation({preparedProgram:p,serializationGraph:graph,request,keyedAcquisition:p.key});
    else content.prepareRun({preparedProgram:p,plan,request});
    return{p,request,graph,plan,run:record.computeRuns.get(p),retire(){const finish=retire(p);finish?.();}};};
  return{open,content,record,captured,origins,held,retained,moon};
}

test('retired keyed Content does not exhaust the unchanged 4096 live-preparation limit',()=>{
  const f=fixture();for(let i=0;i<4097;i++){const current=f.open();current.retire();}
  assert.equal(f.held.length,4097,'Prepared originals remain held; GC cannot explain slot reuse');
  assert.equal(f.record.computeLiveRuns.size,0);
});


test('Content live limit stays bounded through pending cleanup and releases exactly one acknowledged slot',()=>{
  const f=fixture(),live=Array.from({length:4096},()=>f.open());
  assert.throws(()=>f.open(),{message:'InstalledContentRunLimit'});
  const first=live[0],o=f.origins.get(first.run.value);o.allowed=false;
  assert.throws(first.retire,e=>e.code==='MoonBitHostFailure'&&e.cause.code==='OriginalCleanupPending');
  assert.equal(f.retained[0].retired,false);assert.equal(o.observations,1);
  assert.throws(()=>f.open(),{message:'InstalledContentRunLimit'});
  o.allowed=true;first.retire();assert.equal(f.retained[0].retired,true);
  assert.equal(o.observations,1,'Unit success does not add a payload probe');
  f.retained[0].releaseAliases.call(f.retained[0]);
  f.open();assert.throws(()=>f.open(),{message:'InstalledContentRunLimit'});
});

test('source-free Content leaves only a spent record and cannot reissue for its held original key',()=>{
  const f=fixture(),current=f.open(false),original=f.retained[0],value=current.run.value;
  current.retire();assert.equal(original.retired,true);
  for(const [key,v]of Object.entries(original))if(key!=='retired')assert.equal(v,undefined,key);
  assert.equal(f.origins.get(value).observations,undefined);
  assert.throws(()=>f.content.prepareRun({preparedProgram:current.p,plan:current.plan,request:current.request}),{message:'ForeignInstalledContentRun'});
  assert.throws(()=>Reflect.apply(original.releaseAliases,{...original,retired:false},[current.run]),{message:'ForeignInstalledContentRun'});
});

test('Content uses one callbackful fallback observation and refuses retirement reentry or changed original bags',()=>{
  const f=fixture(),current=f.open(),original=f.retained[0],o=f.origins.get(current.run.value);
  o.allowed=false;const primary=new Error('same callback failure');o.observe=()=>{assert.throws(current.retire,{code:'InstalledContentRunCleanupPending'});throw primary;};
  assert.throws(current.retire,e=>e===primary);assert.equal(o.observations,1);assert.equal(original.retired,false);
  o.observe=()=>{assert.throws(current.retire,{code:'InstalledContentRunCleanupPending'});return true;};
  current.retire();assert.equal(o.observations,2);assert.equal(original.retired,true);
  const g=fixture(),second=g.open(),record=g.retained[0],origin=g.origins.get(second.run.value);
  origin.before=()=>{g.record.computeRuns.set(second.p,{});};
  assert.throws(second.retire,{code:'ForeignInstalledContentRun'});assert.equal(record.retired,false);
  assert.equal(origin.observations,undefined);
});

test('failed Content construction keeps its aliases until the same Request abort and consumes its borrow once',()=>{
  for(const phase of ['quote','constructor']){
    const failure=new Error('same '+phase),f=fixture(phase==='quote'?{prefixFailure:failure}:{constructFailure:failure});
    assert.throws(()=>f.open(),e=>e===failure);const original=f.retained[0],holder=original.inputHolder,parent={};
    let ready=false,returns=0,aborts=0,initialRetirements=0,returned=false;
    const returnFailure=new Error('same consumed return');
    f.moon.clientProgramAbortRequestPreparation=p=>{assert.equal(p,parent);aborts++;if(!ready)return{$tag:0,_0:failure};holder.retiring=true;return{$tag:1};};
    f.moon.clientProgramPreparationBorrowReturn=h=>{assert.equal(h,holder);assert.equal(returned,false);returned=true;returns++;throw returnFailure;};
    const state={context:{runtime:f.moon},parent,prepared:original.prepared,holder,contentPreparation:original};
    const retire=p=>{initialRetirements++;assert.equal(p,holder.prepared);
      if(phase==='constructor'){const run=f.record.computeRuns.get(p);assert.notEqual(run,undefined);
        // The actual pre-adoption Host retirement removes only its bag. The
        // same Request still retains this original until its own abort fence.
        const value=f.record.computeRuns.get(p);const ports={record:f.record,moon:f.moon,checked,finishInstalledEffectModelScope,
          clientOperationError:code=>Object.assign(new Error(code),{code})};
        Function(...Object.keys(ports),`return ({${host.slice(selected.start,selected.end)}}).retireManagedComputeRun;`)(...Object.values(ports))(p);
        assert.equal(value.closed,true);
      }};
    assert.throws(()=>cleanupRequestInput(state,retire),e=>e.code==='MoonBitHostFailure'&&e.cause===failure);
    assert.equal(original.retired,false);assert.equal(initialRetirements,0);assert.equal(returns,0);
    ready=true;assert.throws(()=>cleanupRequestInput(state,retire),e=>e===returnFailure);
    assert.equal(original.retired,true);assert.equal(state.contentPreparation,undefined);assert.equal(state.holder,undefined);
    assert.equal(returns,1);cleanupRequestInput(state,retire);assert.equal(returns,1);assert.equal(state.parent,undefined);assert(aborts>=3);
  }
});
