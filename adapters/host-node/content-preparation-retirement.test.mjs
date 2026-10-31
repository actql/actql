import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {finishInstalledEffectModelScope} from './installed-effect-managed-run.mjs';

// Actual Content service and extracted Host retirement, with explicit Core
// payload/input witnesses. No Common Runtime, Resource stop or physical ACK is
// inferred from these ports or from the implementation's live-slot count.
const host=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
let selected;const walk=n=>{if(!n||typeof n!=='object')return;
  if(n.type==='Property'&&n.key?.name==='retireManagedComputeRun')selected=n;
  for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
walk(parse(host,{ecmaVersion:'latest',sourceType:'module'}));assert(selected);
function fixture() {
  const record={computeRuns:new WeakMap(),computeLiveRuns:new Set()},origins=new WeakMap(),held=[],captured=[];
  const moon={clientProgramAcquisitionCount:p=>p.keyed?2:0,
    clientProgramKeyedAcquisitionMatchesProgram:(k,p)=>k===p.key,
    clientProgramInstalledPreparationPayloadSevered:(v,r)=>origins.get(v)?.request===r&&origins.get(v).severed===true,
    clientProgramPreparationBorrowRead:h=>h.prepared,
    clientProgramPreparationBorrowRetirementStarted:h=>h.retiring===true};
  const keep=(p,preparation)=>{preparation.inputHolder={prepared:p,retiring:false};};
  function prepare(p,r,graph,recipe,preparation,keyed) {
    const value={},origin={request:r,severed:false,allowed:true};origins.set(value,origin);
    const run={runtime:moon,prepared:p,request:r,value,preparationFunded:true,preparationKind:keyed?'keyed-content-plan':'serialization-plan',
      serialization:{},serializationCleaned:false,content:{},manager:{severPreparation(){}},original:{},closed:false,
      selectedKeyed:{},contentCompilation:{},contentGraph:graph,contentRecipe:recipe};
    run.cleanupSerialization=()=>true;
    run.retire=()=>{if(!origin.allowed)return{$tag:0,_0:Object.assign(new Error('same cleanup pending'),{code:'OriginalCleanupPending'})};origin.severed=true;return{$tag:1,_0:undefined};};
    if(preparation!==undefined){preparation.managed=run;run.contentPreparation=preparation;
      run.releaseContentAliases=preparation.releaseAliases;captured.push(preparation);}
    record.computeRuns.set(p,run);record.computeLiveRuns.add(run);return run;
  }
  const content=installNodeContentRun({moon,preparedRunRequired:true,assertRunCurrent(){},retainPreparation:keep,
    registry:'{}',values:'{}',ownerPrincipal:'fixture',
    prepareKeyedManagedRun:(p,r,g,recipe,preparation)=>prepare(p,r,g,recipe,preparation,true),borrowKeyedManagedLedger:()=>assert.fail('No physical Ledger'),
    prepareSerializationManagedRun:(p,r,plan,limits,workspace,preparation)=>prepare(p,r,plan.serializationGraph,undefined,preparation,false),
    core:{contentGenerationControl:{workspaceCapacity:()=>({retainedBytes:0n,executionBytes:0n}),
      prefixCapacity:()=>({retainedBytes:1n,executionBytes:1n}),requestPrefixCapacity:()=>({retainedBytes:1n,executionBytes:1n})},
      publicationControl:{checkClientCompiledRunOwner(c,p){assert.equal(c.owner,p);}}}});
  const ports={record,moon,checked,finishInstalledEffectModelScope,
    clientOperationError:code=>Object.assign(new Error(code),{code}),
    managedPreparationRetirementContinuation:run=>()=>{record.computeLiveRuns.delete(run);}};
  const retire=Function(...Object.keys(ports),`return ({${host.slice(selected.start,selected.end)}}).retireManagedComputeRun;`)(...Object.values(ports));
  const open=(keyed=true)=>{const p={keyed,key:{}},request={},graph={task:0,step:1},plan={kind:'serialization',serializationGraph:graph,compiled:{owner:p}};held.push(p);
    if(keyed)content.prepareManagedKeyedCompilation({preparedProgram:p,serializationGraph:graph,request,keyedAcquisition:p.key});
    else content.prepareRun({preparedProgram:p,plan,request});
    return{p,request,graph,plan,run:record.computeRuns.get(p),retire(){const finish=retire(p);finish?.();}};};
  return{open,content,record,captured,origins,held};
}

test('retired keyed Content does not exhaust the unchanged 4096 live-preparation limit',()=>{
  const f=fixture();for(let i=0;i<4097;i++){const current=f.open();current.retire();}
  assert.equal(f.held.length,4097,'Prepared originals remain held; GC cannot explain slot reuse');
  assert.equal(f.record.computeLiveRuns.size,0);
});
