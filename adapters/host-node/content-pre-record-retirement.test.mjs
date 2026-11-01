import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';

// Actual fixed Host registry constructor/callback and Request cleanup. Core
// original/retiring/consumed-return ports are explicit; no Run, Common runtime,
// physical ACK or public failure cause is manufactured by this component.
const host=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8'),nodes=[];
const walk=n=>{if(!n||typeof n!=='object')return;nodes.push(n);
  for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
walk(parse(host,{ecmaVersion:'latest',sourceType:'module'}));
const initial=nodes.find(n=>n.type==='VariableDeclarator'&&n.id?.name==='localPreparationCustody');
const cuts=nodes.filter(n=>n.type==='FunctionDeclaration'&&['releaseRequestModelAliases','releaseRequestDomainAliases'].includes(n.id?.name));
const retire=nodes.find(n=>n.type==='FunctionDeclaration'&&n.id?.name==='retireSourceManagedInitialPreparation');
assert(initial&&retire&&cuts.length===2);
function fixture(phase){
  const prepared={},other={},inputHolder={},handler={},parent={},calls=[],earlyContentPlans=new WeakMap();
  const primary=new Error('same pre-record '+phase),settlement=new Error('same consumed handler settlement');
  let allowed=false,retiring=false,returned=false,handlerReturns=0,requestReturns=0;
  const state={context:{runtime:undefined},parent,holder:inputHolder,prepared};
  const moon={clientProgramSerializationOccurrences:()=>[{}],clientProgramComposedInferOccurrences:()=>({$tag:1,_0:[]}),
    clientProgramAcquisitionCount:()=>0,clientProgramPreparationBorrowSibling:()=>assert.fail('No dispatch/second borrow'),
    clientProgramPreparationBorrowRead(h){assert.equal(h,handler);assert.equal(returned,false);return prepared;},
    clientProgramPreparationBorrowRetirementStarted:h=>[handler,inputHolder].includes(h)&&retiring,
    clientProgramPreparationBorrowReturn(h){
      assert.equal(earlyContentPlans.has(prepared),false,'Cut original early Plan BEFORE any consumed return');
      if(h===handler){assert.equal(returned,false);returned=true;handlerReturns++;throw settlement;}
      assert.equal(h,inputHolder);requestReturns++;return{$tag:1,_0:false};},
    clientProgramAbortRequestPreparation(p){assert.equal(p,parent);calls.push('abort');
      if(!allowed)return{$tag:0,_0:primary};retiring=true;return{$tag:1,_0:undefined};}};
  state.context.runtime=moon;
  const inferSelections=new WeakMap(),earlyMockInferPlans=new WeakMap();
  const releaseRequestDomainAliases=Function('inferSelections','earlyMockInferPlans','earlyContentPlans',
    cuts.map(n=>host.slice(n.start,n.end)).join('\n')+'\nreturn releaseRequestDomainAliases;')(
    inferSelections,earlyMockInferPlans,earlyContentPlans);
  const preparation={canRetireManagedPreparation:()=>true,borrowManagedPreparation:()=>handler,
    retireManagedComputeRun(p){assert.equal(p,prepared);calls.push('no-adopted-Run');return undefined;}};
  const prepareSubmit={kindOf:()=> 'effect_free',retireOriginal(p){assert.equal(p,prepared);calls.push('retire-original');}};
  const ports={installLocalPreparationRegistry,preparation,prepareSubmit,moon,
    runtimeIsOk:v=>v.$tag===1,runtimeField:(v,n)=>v['_'+n],releaseRequestDomainAliases,
    releaseRequestModelAliases:()=>assert.fail('The pre-record original uses the fixed domain cut')};
  // Keep the old Model-only fallback meaningful: no Model alias exists here.
  ports.releaseRequestModelAliases=()=>{};
  const registry=Function(...Object.keys(ports),'return '+host.slice(initial.init.start,initial.init.end)+';')(...Object.values(ports));
  const request=registry.capture({kind:'program',input:{original:true}});
  registry.adopt(prepared,request);registry.finishHandler(request);
  const originals={installation:{retireInitialPreparation:registry.retireRetiringOriginal}};
  const retireInitial=Function('assertSourceManagedHostPreparation','clientOperationError',
    host.slice(retire.start,retire.end)+'\nreturn retireSourceManagedInitialPreparation;')(
    actual=>assert.equal(actual,originals),code=>Object.assign(new Error(code),{code}));
  const content=installNodeContentRun({moon,preparedRunRequired:true,registry:'{}',values:'{}',
    assertRunCurrent(){if(phase==='current')throw primary;},retainPreparation(){assert.equal(phase,'retainer');throw primary;},
    prepareSerializationManagedRun:()=>assert.fail('No accepted Content record or constructed Run'),
    core:{contentGenerationControl:{workspaceCapacity:()=>({})},publicationControl:{checkClientCompiledRunOwner(){}}}});
  const plan={kind:'serialization',serializationGraph:{task:0,step:0},compiled:{},runDefinition:{}};
  earlyContentPlans.set(prepared,plan);earlyContentPlans.set(other,{});
  assert.throws(()=>content.prepareRun({preparedProgram:prepared,plan,request:{}}),e=>e===primary);
  assert.equal(state.contentPreparation,undefined);
  return{state,earlyContentPlans,prepared,other,calls,primary,settlement,
    cleanup:()=>cleanupRequestInput(state,p=>retireInitial(originals,p)),
    allow(){allowed=true;},counts:()=>({handlerReturns,requestReturns})};
}
for(const phase of ['current','retainer'])test(`pre-record Content ${phase} refusal cuts SAME early Plan only after Request Abort/registry fence before consumed return`,()=>{
  const f=fixture(phase);
  assert.throws(f.cleanup,e=>e.cause===f.primary);assert(f.earlyContentPlans.has(f.prepared));
  assert.deepEqual(f.counts(),{handlerReturns:0,requestReturns:0});
  f.allow();assert.throws(f.cleanup,e=>e===f.settlement);
  assert.equal(f.earlyContentPlans.has(f.prepared),false);assert(f.earlyContentPlans.has(f.other));
  assert.deepEqual(f.counts(),{handlerReturns:1,requestReturns:0});
  f.cleanup();assert.deepEqual(f.counts(),{handlerReturns:1,requestReturns:1});
  assert.equal(f.state.parent,undefined);assert.equal(f.calls.filter(x=>x==='no-adopted-Run').length,1);
});
