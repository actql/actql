import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
function get(file,name,context,property=false){const source=readFileSync(new URL(file,import.meta.url),'utf8'),ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let n;function walk(x){if(!x||typeof x!=='object')return;if(property?x.type==='Property'&&x.key?.name===name:x.type==='FunctionDeclaration'&&x.id?.name===name)n=property?x.value:x;for(const v of Object.values(x)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}}walk(ast);assert(n,name);const code=property?`${n.async?'async ':''}function(${n.params.map(p=>source.slice(p.start,p.end)).join(',')})${source.slice(n.body.start,n.body.end)}`:source.slice(n.start,n.end);return new Function(...Object.keys(context),`return ${code}`)(...Object.values(context));}
const fail=code=>{throw Object.assign(new Error(code),{code});};
test('publication phase manager relays the actual original Run without caller quote or holder',()=>{
 const prepared={},phase={},holder={},runOriginal={},seen=[];const state={prepared,phase,holder,adopting:true,context:{runtime:{clientProgramReservePublication(...args){seen.push(args);return 'result';}}}};
 const invoke=get('./ordinary-source-managed.mjs','reservePublication',{publicationRunFor:p=>{assert.equal(p,prepared);return {producer:{preparation:state},value:runOriginal};},fail,checkedPreparation:(moon,result)=>{assert.equal(result,'result');return 'original-resource';}},true);
 assert.equal(invoke(prepared),'original-resource');assert.deepEqual(seen,[[runOriginal,prepared]]);
 state.holder=undefined;assert.throws(()=>invoke(prepared),{code:'ForeignInstalledSourceProducer'});assert.equal(seen.length,1);
});
test('publication invocation selects the same admitted Run for generic and legacy preparation',()=>{
 const prepared={},runOriginal={},state={prepared,holder:{},adopting:true};
 const run={producer:{preparation:state},value:runOriginal};
 const invoke=get('./ordinary-source-managed.mjs','publicationPreparation',{runFor:p=>{assert.equal(p,prepared);return run;},fail},true);
 assert.equal(invoke(prepared),runOriginal);
 state.phase={};assert.equal(invoke(prepared),runOriginal);
 run.value=undefined;assert.throws(()=>invoke(prepared),{code:'NodeManagedRunAdmissionUnavailable'});
 run.value=runOriginal;state.adopting=false;assert.throws(()=>invoke(prepared),{code:'ForeignInstalledSourceProducer'});
});
test('installed publication phase refuses foreign runtime, missing funding and closed originals',()=>{
 const runtime={},prepared={},seen=[];const run={runtime,prepared,preparationFunded:true,manager:{reservePublication:p=>seen.push(p)}};
 const invoke=get('./embedded-local.mjs','managedComputeReservePublication',{record:{computeRuns:new WeakMap([[prepared,run]])},clientOperationError:code=>Object.assign(new Error(code),{code})},true);
 invoke(runtime,prepared);assert.deepEqual(seen,[prepared]);
 for(const mutate of [()=>{run.closed=true;},()=>{run.closed=false;run.preparationFunded=false;},()=>{run.preparationFunded=true;run.runtime={};}]){mutate();assert.throws(()=>invoke(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});}assert.equal(seen.length,1);
});
test('fixed Node entry forwards its original Host holder and publication callback instead of dropping extra arguments',()=>{
 const holder={},callback=()=>{},setup={},calls=[];
 const create=get('./entry.mjs','createNodeHostEntry',{runPublishedCapturedStrategyTarget:input=>{calls.push(input);return input;}});
 const entry=create(()=>{},()=>{});entry.runPublishedCapturedStrategy(setup,{plan:{},store:{}},{},undefined,undefined,undefined,undefined,holder,callback);
 assert.equal(calls[0].cleanup.preparationHolder,holder);assert.equal(calls[0].control.beforePublication,callback);
});
function target(callback,holder={}){
 const publicationResource={},order=[],execution={status:'host-tasks-completed',publicationPreflight:{plan:{}},async publishEffectFreeRun(store,plan,signal,resource){assert.equal(resource,publicationResource);order.push('construct-publication');return {};}};
 class PublicationError extends Error{constructor(cause,original){super('publication',{cause});this.execution=original;}}
 class ExecutionError extends PublicationError{}
 const invoke=get('./entry.mjs','runPublishedCapturedStrategyTarget',{runCapturedStrategyTarget:async input=>{assert.equal(input.cleanup.preparationHolder,holder);order.push('compute-complete');return execution;},CapturedRunExecutionError:ExecutionError,CapturedRunPublicationError:PublicationError});
 return {order,execution,run:()=>invoke({setup:{},publication:{plan:{},store:{}},options:{},composition:{},control:{beforePublication:callback&&(()=>{callback(order);return publicationResource;})},cleanup:{preparationHolder:holder,retainExecution:original=>{assert.equal(original,execution);order.push('cleanup-owner-retained');}}})};
}
test('same-owner publication growth occurs after Compute and before any publication constructor',async()=>{
 const h=target(order=>order.push('reserve-original'));await h.run();assert.deepEqual(h.order,['compute-complete','cleanup-owner-retained','reserve-original','construct-publication']);
});
test('publication resource refusal retains exact execution cleanup and never begins material construction',async()=>{
 const issue=new Error('original resource refusal'),h=target(()=>{throw issue;});await assert.rejects(h.run(),error=>error.cause===issue&&error.execution===h.execution);assert.deepEqual(h.order,['compute-complete','cleanup-owner-retained']);
});
test('funded entry cannot silently omit its fixed publication growth callback',async()=>{
 const h=target(undefined);await assert.rejects(h.run(),error=>error.cause?.message==='PreparationPublicationUnavailable'&&error.execution===h.execution);assert.equal(h.order.includes('construct-publication'),false);
});

test('publication invocation issues and binds through one Core original engine, never accepts arbitrary invocation',()=>{
 const owner={},prepared={},compiled={kind:'values'},compiledOriginal={},definition={},definitionOriginal={},observation={},invocation={},calls=[];
 const invoke=get('../host-common/runtime-core.mjs','issueCheckedClientCompiledInvocation',{compiledRunTokens:new WeakMap([[compiled,compiledOriginal]]),token:value=>{assert.equal(value,definition);return definitionOriginal;},captureContractLimits:x=>x,compiledRunResult:x=>x,inspectEvidence:x=>x,inspect:x=>x,runtimeField:(value,index)=>value[`_${index}`],moon:{clientProgramIssuePublicationInvocation(...args){calls.push(args);return {_0:observation,_1:invocation};},clientProgramIssueCompiledValuesInvocation(){assert.fail('second invocation engine');}}},true);
 const limits={maxWireBytes:11,maxNodes:13,maxDepth:17};
 const issued=invoke(compiled,definition,{dataPolicyCid:'policy'},limits,owner,prepared);
 assert.equal(issued.invocation,invocation);assert.deepEqual(calls,[[owner,prepared,compiledOriginal,definitionOriginal,'policy',11,13,17]]);
 assert.throws(()=>invoke({},definition,{dataPolicyCid:'policy'},limits,owner,prepared),/Foreign Client compiled Run/);
 compiled.kind='infer';assert.throws(()=>invoke(compiled,definition,{dataPolicyCid:'policy'},limits,owner,prepared),/Invalid original publication invocation profile/);assert.equal(calls.length,1);
});

test('funded Values plan passes its borrowed owner and Prepared to the single invocation issuance call',()=>{
 const source=readFileSync(new URL('./local-values-plan.mjs',import.meta.url),'utf8'),ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let fn;for(const node of ast.body){if(node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name==='sourceFreeValuesPlan')fn=node.declaration;}assert(fn);
 const calls=[];function walk(n){if(!n||typeof n!=='object')return;if(n.type==='CallExpression'&&n.callee.type==='MemberExpression'&&n.callee.property.name==='issueCheckedClientCompiledInvocation')calls.push(n);for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(walk);else if(x&&typeof x==='object')walk(x);}}walk(fn);assert.equal(calls.length,1);assert.deepEqual(calls[0].arguments.slice(4).map(x=>x.name),['publicationPreparation','preparedProgram']);
 assert.equal(source.includes('bindPreparedPublicationCompiledOriginal'),false);
});

test('funded source-free Tasks plan forwards its original publication owner and Prepared once',()=>{
 const prepared={},owner={},compiled={kind:'tasks'},definition={},observation={},invocation={},original={};
 let issues=0;
 const acquired={compiled,runDefinition:definition,admission:{},compiledPlan:{identity:'compiled'},
   preparedEvidence:{wire:'prepared'},authorization:{wire:'authorization'},createdAt:'created'};
 const control={issueCheckedClientCompiledInvocation(actual,run,policy,limits,publication,body){
   assert.equal(actual,compiled);assert.equal(run,definition);assert.equal(policy.dataPolicyCid,'policy');
   assert.equal(publication,owner);assert.equal(body,prepared);assert.equal(issues++,0);
   return {observation,invocation};}};
 const invoke=get('./local-values-plan.mjs','sourceFreeTaskPlan',{
   acquiredTaskRunAdmission:options=>{assert.equal(options.preparedProgram,prepared);return acquired;},
   policyCid:()=> 'policy',limits:{},
   localPublicationPlan:input=>{assert.equal(input.invocation,invocation);assert.equal(input.observation,observation);return {};},
   checkedLocalOutputLimits:()=>({}),valuesAdmissions:new WeakMap(),originalPlans:new WeakMap(),
   sourceFreePlanOriginal:actual=>{assert.equal(actual,acquired);return original;}});
 invoke({moon:{clientProgramDefinitionCid:()=> 'program',clientProgramResultCount:()=>1},
   control,preparedProgram:prepared,publicationPreparation:owner});
 assert.equal(issues,1);
});

test('funded source-free Tasks invocation uses the same Core owner without a legacy issuer',()=>{
 const owner={},prepared={},compiled={kind:'tasks'},compiledOriginal={},definition={},definitionOriginal={},
   observation={},invocation={},calls=[];
 const invoke=get('../host-common/runtime-core.mjs','issueCheckedClientCompiledInvocation',{
   compiledRunTokens:new WeakMap([[compiled,compiledOriginal]]),
   token:actual=>{assert.equal(actual,definition);return definitionOriginal;},
   captureContractLimits:x=>x,compiledRunResult:x=>x,inspectEvidence:x=>x,inspect:x=>x,
   runtimeField:(x,index)=>x[`_${index}`],moon:{
     clientProgramIssuePublicationInvocation(...args){calls.push(args);return {_0:observation,_1:invocation};},
     clientProgramIssueCompiledSourceFreeTaskInvocation(){assert.fail('legacy issuer cannot bind the funded owner');}}},true);
 const issued=invoke(compiled,definition,{dataPolicyCid:'policy'},
   {maxWireBytes:11,maxNodes:13,maxDepth:17},owner,prepared);
 assert.equal(issued.invocation,invocation);
 assert.deepEqual(calls,[[owner,prepared,compiledOriginal,definitionOriginal,'policy',11,13,17]]);
});

test('funded invocation refuses Source evidence and every non Values Tasks profile before Core',()=>{
 const owner={},prepared={},compiled={kind:'tasks'},definition={};let calls=0;
 const invoke=get('../host-common/runtime-core.mjs','issueCheckedClientCompiledInvocation',{
   compiledRunTokens:new WeakMap([[compiled,{}]]),token:x=>x,captureContractLimits:x=>x,
   moon:{clientProgramIssuePublicationInvocation(){calls++;assert.fail('invalid profile reached Core');}}},true);
 for(const kind of ['values','tasks']){
   compiled.kind=kind;
   assert.throws(()=>invoke(compiled,definition,{source:{},dataPolicyCid:'policy'},{},owner,prepared),
     /Invalid original publication invocation profile/);
 }
 for(const kind of ['infer','serialization','effects',undefined]){
   compiled.kind=kind;
   assert.throws(()=>invoke(compiled,definition,{dataPolicyCid:'policy'},{},owner,prepared),
     /Invalid original publication invocation profile/);
 }
 assert.equal(calls,0);
 assert.throws(()=>invoke({},definition,{dataPolicyCid:'policy'},{},owner,prepared),
   /Foreign Client compiled Run/);
});

test('unfunded source-free Tasks invocation retains its original legacy issuer',()=>{
 const compiled={kind:'tasks'},compiledOriginal={},definition={},definitionOriginal={},
   observation={},invocation={},calls=[];
 const invoke=get('../host-common/runtime-core.mjs','issueCheckedClientCompiledInvocation',{
   compiledRunTokens:new WeakMap([[compiled,compiledOriginal]]),
   token:actual=>{assert.equal(actual,definition);return definitionOriginal;},
   captureContractLimits:x=>x,compiledRunResult:x=>x,inspectEvidence:x=>x,inspect:x=>x,
   runtimeField:(x,index)=>x[`_${index}`],moon:{
     clientProgramIssueCompiledSourceFreeTaskInvocation(...args){calls.push(args);return {_0:observation,_1:invocation};},
     clientProgramIssuePublicationInvocation(){assert.fail('no admitted publication owner was supplied');}}},true);
 const issued=invoke(compiled,definition,{dataPolicyCid:'policy'},
   {maxWireBytes:11,maxNodes:13,maxDepth:17});
 assert.equal(issued.invocation,invocation);
 assert.deepEqual(calls,[[compiledOriginal,definitionOriginal,'policy',11,13,17]]);
});

function captureFinisher(context,name='finishProgramCapture') {
 const source=readFileSync(new URL('../host-common/runtime-core.mjs',import.meta.url),'utf8');
 const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let initializer;
 function walk(n){if(!n||typeof n!=='object')return;if(n.type==='VariableDeclarator'&&n.id.name===name)initializer=n.init;for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}}walk(ast);assert(initializer);
 return new Function(...Object.keys(context),`return (${source.slice(initializer.start,initializer.end)})`)(...Object.values(context));
}
test('typed capture retains one Host handle through start advance finish and existing publication custody',async()=>{
 const capture={},captured={},limits={},seen=[],map=new WeakMap();
 const same=(name,result)=>(original,...args)=>{assert.equal(original,capture);seen.push([name,...args]);return result;};
 const finish=captureFinisher({checked:x=>x,tuplePair:x=>x,programCaptureLimits:same('limits',limits),inspect:(value,bounds)=>{assert.equal(bounds,limits);return value;},capturedComputationPreparations:map,moon:{clientProgramStartCapture:same('start',capture),clientProgramAdvanceCapture:same('advance',[true,17]),clientProgramFinishCapture:same('finish',captured),clientProgramCancelCapture:same('cancel')}});
 assert.equal(await finish(capture),captured);assert.deepEqual(seen,[['start'],['limits'],['advance',256],['finish']]);assert.equal(map.get(captured).program,capture);
});
test('typed capture cancellation on stale start keeps original cancellation receipt and never advances',async()=>{
 const capture={},issue=new Error('stale manager'),seen=[];
 const finish=captureFinisher({checked:x=>x,moon:{clientProgramStartCapture:original=>{assert.equal(original,capture);throw issue;},clientProgramCancelCapture:original=>seen.push(original)}});
 await assert.rejects(finish(capture),error=>error===issue);assert.deepEqual(seen,[capture]);
});
test('typed capture rejects malformed generated progress and cancels the same handle',async()=>{
 const capture={},seen=[];
 const finish=captureFinisher({checked:x=>x,tuplePair:x=>x,programCaptureLimits:()=>({}),moon:{clientProgramStartCapture:()=>capture,clientProgramAdvanceCapture:()=>[1,0],clientProgramCancelCapture:x=>seen.push(x)}});
 await assert.rejects(finish(capture),/Invalid original capture progress/);assert.deepEqual(seen,[capture]);
});

test('funded capture maps original inventory once and never invokes raw-limit issuer',async()=>{
 const owner={},capture={},definition={},invocation={},artifact={},snapshot={},authoring={},manifest={},receipt={},calls=[];
 const invoke=get('../host-common/runtime-core.mjs','issueEffectFreeCapturedRun',{captureContractLimits:x=>x,checked:x=>x,token:x=>x,snapshotToken:x=>x,evidenceToken:x=>x,finishProgramCapture:(original,signal)=>{assert.equal(original,capture);return 'captured';},moon:{clientProgramPrepareCapture(...args){calls.push(args);return capture;},strategyBeginOriginalEffectFreeCapturedRun(){assert.fail('raw issuer bypass');}}},true);
 const chain={runDefinition:definition,invocation,definitions:[definition],artifacts:[artifact],manifest,receipt};
 const evidence={snapshots:[snapshot],pendingSourceStateAdvances:[],authoringContext:authoring,modelEvidence:[]};
 assert.equal(await invoke(chain,evidence,{maxWireBytes:1,maxNodes:2,maxDepth:3},undefined,owner),'captured');
 assert.deepEqual(calls,[[owner,definition,invocation,[definition],[artifact],manifest,receipt,[snapshot],authoring,[]]]);
 evidence.modelEvidence=[{}];await assert.rejects(invoke(chain,evidence,{},undefined,owner),/Invalid original program capture profile/);assert.equal(calls.length,1);
});
test('captured publication retirement cancels the tracked typed handle rather than its private issuer',()=>{
 const captured={},handle={},map=new WeakMap([[captured,{program:handle}]]),seen=[];
 const retire=get('../host-common/runtime-core.mjs','retireCapturedComputation',{token:x=>x,capturedComputationPreparations:map,moon:{clientProgramCancelCapture:x=>seen.push(x),strategyCapturedRunCancel:()=>assert.fail('raw cancellation')}},true);
 retire(captured);retire(captured);assert.deepEqual(seen,[handle]);assert.equal(map.has(captured),false);
});


test('typed capture extent uses generated tuple fields with distinct dimensional sentinels',()=>{
 const capture={},calls=[];let returned={_0:101,_1:211,_2:17};
 const read=captureFinisher({checked:x=>x,runtimeField:(x,i)=>x[`_${i}`],moon:{clientProgramCaptureLimits:original=>{assert.equal(original,capture);calls.push(original);return returned;}}},'programCaptureLimits');
 assert.deepEqual(read(capture),{maxWireBytes:101,maxNodes:211,maxDepth:17});
 for(const value of [{_0:1,_1:2,_2:3,_3:4},{_0:1,_1:-1,_2:3},{_0:1,_1:2,_2:2147483648},{_0:1,_1:2},{_0:1,_1:2,_2:NaN}]) {returned=value;assert.throws(()=>read(capture),/Invalid original capture extent/);}
 assert.equal(calls.length,6);
});

test('typed retained chain and commit consume original contracts without numeric limit relay',async()=>{
 const capture={},captured={},handle={},seen=[],map=new WeakMap([[captured,{program:capture}]]);
 const context={issuanceLimits:()=>{},capturedComputationPreparations:map,checked:x=>x,token:x=>x,finishProgramValidation:(value,signal)=>{assert.equal(value,handle);seen.push(['run',signal]);return true;},moon:{clientProgramPrepareChainValidation:(...args)=>{seen.push(['chain',...args]);return handle;},clientProgramPrepareCommitValidation:(...args)=>{seen.push(['commit',...args]);return handle;}}};
 const definition={},invocation={},definitions=[{}],artifacts=[{}],manifest={},receipt={},signal={throwIfAborted(){}};
 const chain=get('../host-common/runtime-core.mjs','effectFreeChainValid',context,true);
 assert.equal(await chain(definition,invocation,definitions,artifacts,manifest,receipt,captured,{maxNodes:1},signal),true);
 assert.deepEqual(seen[0],['chain',capture,definition,invocation,definitions,artifacts,manifest,receipt,captured]);
 const commit=get('../host-common/runtime-core.mjs','effectFreeCommitValid',context,true);const derivations=[{}],orderings=[{}],retentions=[{}],bindings=[{}],request={},attempt={},index={};
 assert.equal(await commit(definition,invocation,definitions,artifacts,derivations,orderings,retentions,bindings,manifest,receipt,captured,request,attempt,index,{maxNodes:1}),true);
 assert.deepEqual(seen[2],['commit',capture,definition,invocation,definitions,artifacts,derivations,orderings,retentions,bindings,manifest,receipt,captured,request,attempt,index]);assert.deepEqual(seen[3],['run',undefined]);
});
test('typed validation always cancels its tracked continuation after finish or failed start',async()=>{
 const handle={},seen=[];let failure;
 const run=captureFinisher({checked:x=>x,tuplePair:x=>x,moon:{clientProgramStartValidation:x=>{assert.equal(x,handle);if(failure)throw failure;seen.push('start');return x;},clientProgramAdvanceValidation:(x,q)=>{assert.equal(x,handle);assert.equal(q,256);return [true,1];},clientProgramFinishValidation:x=>{assert.equal(x,handle);seen.push('finish');},clientProgramCancelValidation:x=>{assert.equal(x,handle);seen.push('cancel');}}},'finishProgramValidation');
 assert.equal(await run(handle),true);assert.deepEqual(seen,['start','finish','cancel']);failure=new Error('foreign');await assert.rejects(run(handle),x=>x===failure);assert.deepEqual(seen,['start','finish','cancel','cancel']);
});

test('typed snapshot begins from original publication and export, never caller BND',async()=>{
 const publication={},output={},snapshot={},captured={},seen=[];
 const run=captureFinisher({checked:x=>x,tuplePair:x=>x,inspectSnapshot:x=>x,moon:{clientProgramBeginSnapshot:(p,o)=>{assert.equal(p,publication);assert.equal(o,output);seen.push('begin');return snapshot;},clientProgramAdvanceSnapshot:(s,q)=>{assert.equal(s,snapshot);assert.equal(q,256);return [true,2];},clientProgramFinishSnapshot:s=>{assert.equal(s,snapshot);seen.push('finish');return captured;},clientProgramCancelSnapshot:()=>assert.fail('successful snapshot cancelled')}},'finishProgramSnapshot');
 assert.equal(await run(publication,output),captured);assert.deepEqual(seen,['begin','finish']);
 const invoke=get('../host-common/runtime-core.mjs','admitCompletedResultSnapshot',{finishProgramSnapshot:(p,o,signal)=>{assert.equal(p,publication);assert.equal(o,output);return captured;}},true);
 assert.equal(await invoke(output,{maxLogicalWireBytes:-1},undefined,publication),captured);
});
test('snapshot failure cancels exact typed continuation without clearing unrelated holders',async()=>{
 const snapshot={},seen=[],failure=new Error('output retired');
 const run=captureFinisher({checked:x=>x,tuplePair:x=>x,moon:{clientProgramBeginSnapshot:()=>snapshot,clientProgramAdvanceSnapshot:()=>{throw failure;},clientProgramCancelSnapshot:x=>seen.push(x)}},'finishProgramSnapshot');
 await assert.rejects(run({},{}),x=>x===failure);assert.deepEqual(seen,[snapshot]);
});

test('Store validator checks selected currentness after every yield and cancels before rejection',async()=>{
 const handle={},events=[];let current=true,advanced=0;
 const run=captureFinisher({checked:x=>x,tuplePair:x=>x,setImmediate:resolve=>{current=false;resolve();},moon:{clientStoreAdvanceOriginalValidation:(h,q)=>{assert.equal(h,handle);assert.equal(q,256);advanced++;return [false,1];},clientStoreFinishOriginalValidation:()=>assert.fail('late valid result'),clientStoreCancelOriginalValidation:h=>{assert.equal(h,handle);events.push('cancel');}}},'finishStoreValidation');
 await assert.rejects(run(handle,()=>{events.push('current');if(!current)throw new Error('Store closed');}),/Store closed/);
 assert.equal(advanced,1);assert.deepEqual(events,['current','current','cancel']);
});
test('Store original commit validation requires selected read owner and ignores numeric metadata ceilings',async()=>{
 const values=Array.from({length:14},()=>({}));for(const i of [2,3,4,5,6,7])values[i]=[{}];const handle={},calls=[],requireCurrent=()=>calls.push('current');
 const invoke=get('../host-common/runtime-core.mjs','effectFreeStoredCommitValid',{checked:x=>x,token:x=>x,capturedComputationPreparations:new WeakMap(),finishStoreValidation:(h,guard)=>{assert.equal(h,handle);assert.equal(guard,requireCurrent);return true;},moon:{clientStoreBeginOriginalCommitValidation:(...args)=>{calls.push(args);return handle;}}},true);
 assert.equal(await invoke(...values,requireCurrent),true);assert.deepEqual(calls,['current',values]);await assert.rejects(invoke(...values,{maxNodes:1}),/Store publication validation owner unavailable/);
});


test('original Source publication consumes retained observation tokens on its same managed Run', () => {
  const owner = {}, prepared = {}, compiled = {kind: 'tasks'}, original = {}, definition = {},
    contract = {}, evidence = {}, evidenceOriginal = {}, logicalInput = {}, capture = {},
    identity = {}, requirement = {}, observation = {}, invocation = {}, calls = [];
  const captured = {logicalInput, identity, requirement, capture: {source: () => capture}};
  const invoke = get('../host-common/runtime-core.mjs', 'issueCheckedClientCompiledInvocation', {
    compiledRunTokens: new WeakMap([[compiled, original]]), token: value => {assert.equal(value, definition); return contract;},
    evidenceToken: value => {assert.equal(value, evidence); return evidenceOriginal;},
    captureContractLimits: value => value, compiledRunResult: value => value, checked: value => value,
    inspectEvidence: value => value, inspect: value => value, runtimeField: (value, index) => value[`_${index}`],
    moon: {clientProgramInstalledManagedPublicationSourceKind: () => 'query',
      clientProgramIssueCapturedPublicationInvocation(...args) {calls.push(args); return {_0: observation, _1: invocation};},
      clientProgramIssueCompiledTaskInvocation() {assert.fail('raw Source issuer bypassed the original Run');}},
  }, true);
  const bounds = {maxWireBytes: 11, maxNodes: 13, maxDepth: 17};
  const issued = invoke(compiled, definition, {dataPolicyCid: 'policy', source: {
    captured, sourceEvidence: evidence, authorityScopeCid: 'authority', captureStartedAt: 'start', captureCompletedAt: 'end',
  }}, bounds, owner, prepared);
  assert.equal(issued.invocation, invocation);
  assert.deepEqual(calls, [[owner, prepared, original, contract, [capture], [identity], [requirement],
    [evidenceOriginal], [logicalInput], undefined, 'authority', 'policy', 'start', 'end', 11, 13, 17]]);
});


test('all original Source publication callers retain original evidence without wire admission', () => {
  for (const kind of ['single', 'multi', 'keyed']) {
    const owner = {}, prepared = {}, compiled = {}, definition = {}, rightOriginal = {}, right = {}, observations = [];
    const evidence = [{}, {}];
    const captures = [0, 1].map(index => ({logicalInput: {}, identity: {}, requirement: {},
      checkedSource: {}, capture: {source: () => `source-${index}`}}));
    const issued = [];
    const control = {
      checkClientCompiledRunOwner: (run, program) => {assert.equal(run, compiled); assert.equal(program, prepared);},
      admitRunEvidence: () => assert.fail('live original Source evidence admitted again'),
      issueCheckedClientCompiledInvocation: (...args) => {issued.push(args); return {observation: observations, invocation: {}};},
      keyedLookupPublicationEvidence: value => {assert.equal(value, rightOriginal); return {source: right, logicalRelationCid: 'right-logical'};},
    };
    const moon = {clientProgramCapturedSourceMatches: () => true, clientProgramCapturedTaskSourceMatches: () => true,
      clientProgramPublicationDataPolicyCid: () => 'policy', clientProgramDefinitionCid: () => 'program',
      clientProgramCapturedSourceLogicalCid: identity => `logical-${captures.findIndex(x => x.identity === identity)}`,
      clientProgramResultCount: () => 1, strategyRunEvidenceJson: () => assert.fail('retained input serialized again')};
    const name = kind === 'single' ? 'acquiredTaskPublicationPlan' : kind === 'multi'
      ? 'acquiredMultiTaskPublicationPlan' : 'acquiredKeyedTaskPublicationPlan';
    const invoke = get('./local-values-plan.mjs', name, {limits: {}, localPublicationPlan: value => value,
      JSON: {parse: () => assert.fail('retained keyed input parsed again')}});
    const acquired = {compiled, runDefinition: definition, compiledPlan: {identity: 'plan'}, publicationPreparation: owner};
    const input = {moon, control, acquired, preparedProgram: prepared, captured: captures[0], sourceEvidence: evidence[0],
      sources: captures.map((captured, i) => ({captured, sourceEvidence: evidence[i]})),
      keyedObservation: {observation: rightOriginal}, effectiveDataPolicyCid: 'policy', authorityScopeCid: 'authority',
      captureStartedAt: 'start', captureCompletedAt: 'end'};
    const plan = invoke(input);
    assert.equal(issued.length, 1); assert.equal(issued[0][4], owner); assert.equal(issued[0][5], prepared);
    assert.deepEqual(plan.sourceEvidence, kind === 'keyed' ? [evidence[0], right]
      : kind === 'multi' ? evidence : [evidence[0]]);
    assert.equal(issued[0][2].source.sourceEvidence ?? issued[0][2].source.sources[0].sourceEvidence, evidence[0]);
    assert.equal(plan.observation, observations);
  }
});

test('captured invocation refuses missing owner and copied evidence before portable issuance', () => {
  const owner = {}, prepared = {}, compiled = {kind: 'tasks'}, source = {}, evidence = {}, calls = [];
  const context = {compiledRunTokens: new WeakMap([[compiled, {}]]), token: value => value,
    evidenceToken: value => {if (value !== evidence) throw new TypeError('Foreign Run evidence'); return source;},
    captureContractLimits: value => value, compiledRunResult: value => value, checked: value => value, inspectEvidence: value => value,
    inspect: value => value, runtimeField: (value, index) => value[`_${index}`],
    moon: {clientProgramInstalledManagedPublicationSourceKind: () => 'query',
      clientProgramIssueCapturedPublicationInvocation(...args) {calls.push(args); return {_0: {}, _1: {}};}}};
  const invoke = get('../host-common/runtime-core.mjs', 'issueCheckedClientCompiledInvocation', context, true);
  const captured = {logicalInput: {}, identity: {}, requirement: {}, capture: {source: () => ({})}};
  const input = {dataPolicyCid: 'policy', source: {sources: [{captured, sourceEvidence: evidence}, {captured, sourceEvidence: {}}]}};
  assert.throws(() => invoke(compiled, {}, input, {}, undefined, prepared), /Invalid original publication invocation profile/);
  assert.throws(() => invoke(compiled, {}, input, {}, owner, prepared), /Foreign Run evidence/);
  assert.equal(calls.length, 0);
});


test('whole Source publication forwards the same native capture and never a Query requirement', () => {
  const owner = {}, prepared = {}, compiled = {kind: 'tasks'}, compiledOriginal = {}, definition = {},
    nativeCapture = {}, identity = {}, logical = {}, evidence = {}, evidenceOriginal = {},
    observation = {}, invocation = {}, calls = [], foreign = new Error('foreign original');
  let available = true, kind = 'whole-input';
  const capture = Object.freeze({source() {assert.equal(this, capture); return {};},
    originalWholeInput() {
      assert.equal(this, capture);
      if (!available) throw foreign;
      return nativeCapture;
    }});
  const captured = {capture, identity, logicalInput: logical};
  Object.defineProperty(captured, 'requirement', {get() {assert.fail('whole Source queried a Query requirement');}});
  const invoke = get('../host-common/runtime-core.mjs', 'issueCheckedClientCompiledInvocation', {
    compiledRunTokens: new WeakMap([[compiled, compiledOriginal]]), token: value => {
      assert.equal(value, definition); return definition;
    }, evidenceToken: value => {assert.equal(value, evidence); return evidenceOriginal;},
    captureContractLimits: value => value, compiledRunResult: value => value, checked: value => value,
    inspectEvidence: value => value, inspect: value => value, runtimeField: (value, index) => value[`_${index}`],
    moon: {clientProgramInstalledManagedPublicationSourceKind(actual, body) {
      assert.equal(actual, owner); assert.equal(body, prepared); return kind;
    }, clientProgramIssueWholeSourcePublicationInvocation(...args) {
      calls.push(args); return {_0: observation, _1: invocation};
    }, clientProgramIssueCapturedPublicationInvocation() {assert.fail('whole Source entered Query issuance');}},
  }, true);
  const bounds = {maxWireBytes: 11, maxNodes: 13, maxDepth: 17};
  const source = {captured, sourceEvidence: evidence, authorityScopeCid: 'authority',
    captureStartedAt: 'start', captureCompletedAt: 'end'};
  const issue = () => invoke(compiled, definition, {dataPolicyCid: 'policy', source}, bounds, owner, prepared);
  assert.equal(issue().invocation, invocation);
  assert.deepEqual(calls, [[owner, prepared, compiledOriginal, definition, nativeCapture, identity,
    evidenceOriginal, logical, 'authority', 'policy', 'start', 'end', 11, 13, 17]]);
  available = false;
  assert.throws(issue, error => error === foreign);
  available = true;
  source.captured = {identity, logicalInput: logical, capture: {...capture}};
  assert.throws(issue, {code: 'ERR_ASSERTION'});
  source.captured = {identity, logicalInput: logical, capture: {source: capture.source}};
  assert.throws(issue, /Invalid original whole Source capture/);
  source.captured = captured;
  kind = 'unknown';
  assert.throws(issue, /Invalid original publication invocation profile/);
  assert.equal(calls.length, 1);
});

test('live Source dispatch awaits original preparation and transfers the same capture once without wire fallback', async () => {
  const prepared = {}, preparedSource = {checkedSource: {sourceRef: 'source'}}, sourceAccess = {},
    original = {}, nominal = {name: 'source_evidence'}, events = [];
  const take = get('../host-common/runtime-core.mjs', 'takeSourceEvidenceOriginal', {
    inspectEvidence: value => {assert.equal(value, original); events.push('project'); return nominal;},
  }, true);
  let available = false;
  const capture = Object.freeze({takeSourceEvidenceOriginal() {
    assert.equal(this, capture); assert.equal(available, true); available = false;
    events.push('take'); return original;
  }});
  const captured = {capture, checkedSource: {sourceDataPolicyCid: 'policy'},
    async prepareSourceEvidenceOriginal(options) {
      assert.equal(this, captured);
      assert.deepEqual(options, {authorityScopeCid: 'authority', effectiveDataPolicyCid: 'policy'});
      await Promise.resolve(); events.push('prepared'); available = true;
    }, issueSourceEvidence() {assert.fail('live Source converted to wire');}};
  const invoke = get('./client-dispatch-owner.mjs', 'acquireSource', {
    installedSourceFor: () => ({async open(input) {
      assert.equal(input.preparedProgram, prepared); assert.equal(input.sourceAccess, sourceAccess);
      events.push('open'); return captured;
    }}), sourceProfile: {}, now: () => 'time', step: async () => {},
    acquisitionEndHandoff: () => ({retain() {}, outcome() {assert.fail('no acquisition failure');}}),
    observation: undefined, registry: {}, values: {}, fragment: {}, ordered: {},
    retainedRelationOutput: false, authorityScopeCid: 'authority', control: {takeSourceEvidenceOriginal: take},
  });
  const entry = {abort: new AbortController()};
  const result = await invoke(entry, prepared, preparedSource, sourceAccess, {originalEvidence: true});
  assert.equal(result.sourceEvidence, nominal); assert.equal(result.sourceEvidenceWire, undefined);
  assert.equal(entry.sourceCapture, captured); assert.equal(available, false);
  assert.deepEqual(events, ['open', 'prepared', 'take', 'project']);
  await assert.rejects(invoke(entry, prepared, preparedSource, sourceAccess, {originalEvidence: true}),
    /ClientSourceCaptureAlreadyRetained/);
});

test('Source original transfer refuses missing or accessor ports without invoking a wire issuer', async () => {
  const take = get('../host-common/runtime-core.mjs', 'takeSourceEvidenceOriginal', {
    inspectEvidence: value => value,
  }, true);
  let getters = 0;
  const accessor = {get takeSourceEvidenceOriginal() {getters++; return () => ({});}};
  for (const capture of [{}, accessor, Object.create({takeSourceEvidenceOriginal() {assert.fail('inherited port');}})]) {
    assert.throws(() => take(capture), /InstalledSourceEvidenceUnavailable/);
  }
  assert.equal(getters, 0);
  assert.throws(() => take({takeSourceEvidenceOriginal() {return {name: 'logical_input'};}}),
    /InvalidInstalledSourceEvidence/);
});


test('Source evidence preparation failure preserves the exact capture cleanup owner and original error', async () => {
  for (const issue of [new Error('original current failed'), undefined]) {
    const captured = {checkedSource: {sourceDataPolicyCid: 'policy'},
      async prepareSourceEvidenceOriginal() {throw issue;},
      issueSourceEvidence() {assert.fail('failed original selected wire fallback');}};
    const invoke = get('./client-dispatch-owner.mjs', 'acquireSource', {
      installedSourceFor: () => ({open: async () => captured}), sourceProfile: {}, now: () => 'time',
      step: async () => {}, acquisitionEndHandoff: () => ({retain() {}}), observation: undefined,
      registry: {}, values: {}, fragment: {}, ordered: {}, retainedRelationOutput: false,
      authorityScopeCid: 'authority', control: {takeSourceEvidenceOriginal() {assert.fail('preparation did not finish');}},
    });
    const entry = {abort: new AbortController()};
    let failed = false;
    try {await invoke(entry, {}, {checkedSource: {sourceRef: 'source'}}, {}, {originalEvidence: true});}
    catch (actual) {failed = true; assert.equal(actual, issue);}
    assert.equal(failed, true); assert.equal(entry.sourceCapture, captured);
    assert.equal(entry.physicalWorkMayHaveStarted, true);
  }
});


function originalSourceSnapshotEntry(context) {
  // Keep the extracted entry connected to its actual lexical producer helper.
  const beginProducer = get('./ordinary-source-managed.mjs', 'beginProducer', context);
  return get('./ordinary-source-managed.mjs', 'beforeSourceSnapshot',
    {...context, beginProducer}, true);
}

function originalSourcePreparationCallbacks(entry, readContext, retire, originals) {
  const callbacks = {explicitStartup: false, assertSourceManagedHostPreparation: value => assert.equal(value, originals),
    assertRetainedSourceManagedHost: value => assert.equal(value, originals),
    prepareInstalledMockSourcePreparation() {}, readInstalledMockPreparation() {},
    readInstalledProjectSourcePreparation() {}, originalSourceManagedHostRequest() {},
    sourceManagedSubmittedIntentCid() {}, readSourceManagedRunRequirements() {},
    readSourceManagedEffectRunRequirements() {}, readLocalMockModelRunRequirements() {},
    readLocalContentRunRequirements() {}, readLocalPreparationContext: readContext,
    retireSourceManagedInitialPreparation: retire,
    prepareOrdinarySourceManagedInstallation(value, bag, source) {
      assert.equal(value, originals); assert.equal(source, true); return bag;
    }, prepareOrdinaryProjectSourceManagedInstallation(value, bag) {
      assert.equal(value, originals); return bag;
    }};
  // Capture the actual same-owner borrow helper as well as its consumer.
  // The explicit constructor port is exercised only if the selected manager
  // borrows it; this fixture never substitutes an unfunded initialization.
  callbacks.apply = Reflect.apply;
  callbacks.unavailable = () => fail('SourceManagedPreparationUnavailable');
  callbacks.borrowSourceInitializationMaterial = get('./node-source-managed-installation.mjs',
    'borrowSourceInitializationMaterial', callbacks);
  return get('./node-source-managed-installation.mjs', entry, callbacks)(originals);
}

test('both actual Source entries open the same Request before snapshot and retain its original retirement', () => {
  for (const entry of ['prepareSourceManagedInstallation', 'prepareProjectSourceManagedInstallation']) {
    for (const kind of ['program', 'aql']) {
      const originals = {}, context = {runtime: {}}, connection = {}, parent = {}, prepared = {}, holder = {}, events = [];
      const callbacks = originalSourcePreparationCallbacks(entry, value => {
        assert.equal(value, originals); events.push('context'); return context;
      }, (value, body) => {assert.equal(value, originals); assert.equal(body, prepared); events.push('retire');}, originals);
      const receipts = new WeakMap(), producers = new Set();
      const retainSourceInitializationMaterial = get('./ordinary-source-managed.mjs',
        'retainSourceInitializationMaterial', {
          closing: false, closed: false, receipts, fail,
          // This Request-order fixture has no installed Source material.
          // Use the actual helper's unselected branch, not a replacement.
          borrowSourceInitialization: undefined,
        });
      const before = originalSourceSnapshotEntry({
        current() {}, callbacks, originals, receipts, producers, closed: false, fail,
        retainSourceInitializationMaterial,
        requestPreparationAvailable: value => {assert.equal(value, context); return true;},
        assertRequestPreparationControl: value => {assert.equal(value, context); events.push('control');},
        beginRequestInput(state, receipt, actualConnection) {
          assert.equal(state.context, context); assert.equal(receipts.get(receipt).preparation, state);
          assert.equal(actualConnection, connection); assert.equal(producers.size, 1);
          state.parent = parent; events.push('begin'); return true;
        }, cleanupRequestInput() {assert.fail('successful opening has no early cleanup');},
      });
      const receipt = before(kind, kind === 'program' ? {} : 'SELECT @original AS n',
        {parameters: {original: 9}}, connection);
      const producer = receipts.get(receipt);
      assert.equal(producer.preparation?.parent, parent);
      assert.deepEqual(events, ['context', 'control', 'begin']);
      producer.preparation.prepared = prepared; producer.preparation.holder = holder;
      context.runtime = {
        clientProgramAbortRequestPreparation(value) {assert.equal(value, parent); events.push('abort');},
        clientProgramPreparationBorrowRetirementStarted(value) {assert.equal(value, holder); return true;},
        clientProgramPreparationBorrowReturn(value) {assert.equal(value, holder); events.push('return');},
      };
      const cleanup = get('../local-node/request-preparation-adapter.mjs', 'cleanupRequestInput', {
        checked: value => value, invalid() {assert.fail('valid original retirement');},
      });
      const finish = get('./ordinary-source-managed.mjs', 'finishSourceProducer', {
        producerFor: value => {assert.equal(value, receipt); return producer;}, fail, producers,
        cleanupRequestInput: cleanup, retireInitialPreparation: body => callbacks.retireInitialPreparation(originals, body),
        releaseFinishedProducer() {},
      }, true);
      finish(receipt, 'failed');
      assert.equal(producer.preparation, undefined); assert.equal(producers.size, 0);
      assert.deepEqual(events, ['context', 'control', 'begin', 'abort', 'retire', 'return', 'abort']);
    }
  }
});

test('Source context refuses unavailable original capability before producer allocation', () => {
  for (const entry of ['prepareSourceManagedInstallation', 'prepareProjectSourceManagedInstallation']) {
    const originals = {}, context = {}, receipts = new WeakMap(), producers = new Set();
    const callbacks = originalSourcePreparationCallbacks(entry, () => context,
      () => assert.fail('no prepared input to retire'), originals);
    const before = originalSourceSnapshotEntry({
      current() {}, callbacks, originals, receipts, producers, fail,
      requestPreparationAvailable: value => {assert.equal(value, context); return false;},
      assertRequestPreparationControl() {assert.fail('no available original');},
      beginRequestInput() {assert.fail('no allocation after original refusal');},
    });
    assert.throws(() => before('aql', 'SELECT 9 AS n', {}, {}),
      {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.equal(producers.size, 0);
  }
});


test('Source context original refusal cannot allocate or select an unfunded snapshot', () => {
  for (const entry of ['prepareSourceManagedInstallation', 'prepareProjectSourceManagedInstallation']) {
    for (const issue of [new Error('original context current refused'), undefined]) {
      const originals = {}, receipts = new WeakMap(), producers = new Set();
      const callbacks = originalSourcePreparationCallbacks(entry, () => {throw issue;},
        () => assert.fail('no preparation was acquired'), originals);
      const before = originalSourceSnapshotEntry({
        current() {}, callbacks, originals, receipts, producers,
        requestPreparationAvailable() {assert.fail('no returned context');},
        beginRequestInput() {assert.fail('no allocation after original refusal');},
      });
      let failed = false;
      try {before('program', {}, {}, {});}
      catch (actual) {failed = true; assert.equal(actual, issue);}
      assert.equal(failed, true); assert.equal(producers.size, 0);
    }
  }
});


test('composed INFER consumes original captured evidence without serializing or readmitting it', async () => {
  const occurrence = {}, source = {}, logical = {}, evidence = {}, original = {}, failure = new Error('BeforeProviderConstruction');
  const captured = {capture: {source: () => source}, logicalInput: logical, identity: {}, requirement: {}};
  let held, calls = 0;
  const run = get('./installed-composed-infer-run.mjs', 'runInstalledComposedInfers', {
    runtimeField: (value, index) => value[index], checked: value => value,
  });
  await assert.rejects(run({
    moon: {clientProgramResultCount: () => 0, clientProgramInferPlanBoundary: () => [0],
      strategyRunEvidenceJson() {assert.fail('live logical input projected back to wire for readmission');},
      clientProgramAdmitComposedInferSources() {assert.fail('raw wire admission');}},
    control: {admitComposedInferSources(actual, captures, evidenceValues, authority, start, end) {
      assert.equal(actual, occurrence); assert.deepEqual(captures, [captured]);
      assert.deepEqual(evidenceValues, [evidence]); assert.equal(authority, 'authority');
      assert.equal(start, 'start'); assert.equal(end, 'end'); calls++; throw failure;
    }}, preparedProgram: original, plan: {runDefinition: {wire: '{"run_id":"fixture"}'}},
    selected: {components: [{occurrence, graph: {}}]},
    acquiredInfer: {captured, sourceEvidence: evidence, captureStartedAt: 'start', captureCompletedAt: 'end'},
    modelController: {discover: () => []}, signal: new AbortController().signal,
    retainExecution(value) {assert.equal(held, undefined); held = value;}, authorityScopeCid: 'authority',
  }), actual => actual === failure);
  assert.equal(calls, 1); assert.equal(typeof held.cleanup, 'function');
});


test('INFER control forwards the same logical and Source evidence tokens without a wire issuer', () => {
  const prepared = {}, occurrence = {}, source = {}, logical = {}, identity = {}, requirement = {}, evidence = {}, original = {}, calls = [];
  const captured = {inferStep: 4, capturedSource: source, identity, requirement, logicalInput: logical,
    capture: {source: () => source}};
  const context = {checked: value => value,
    evidenceToken: value => {if (value !== evidence) throw new TypeError('Foreign Run evidence'); return original;},
    moon: {clientProgramAdmitInferCapturedInput(...args) {calls.push(args); return 'single';},
      clientProgramAdmitComposedInferSources(...args) {calls.push(args); return 'composed';},
      strategyRunEvidenceJson() {assert.fail('original logical wire');},
      strategyRunEvidenceAdmit() {assert.fail('original evidence readmission');}}};
  const single = get('../host-common/runtime-core.mjs', 'admitInferCapturedInput', context, true);
  const composed = get('../host-common/runtime-core.mjs', 'admitComposedInferSources', context, true);
  assert.equal(single(prepared, captured, evidence, 'authority', 'policy', 'start', 'end'), 'single');
  assert.equal(composed(occurrence, [captured], [evidence], 'authority', 'start', 'end'), 'composed');
  assert.deepEqual(calls, [[prepared, 4, source, identity, requirement, logical, original, 'authority', 'policy', 'start', 'end'],
    [occurrence, [source], [identity], [requirement], [logical], [original], 'authority', 'start', 'end', undefined]]);
  assert.throws(() => single(prepared, captured, {...evidence}, 'authority', 'policy', 'start', 'end'), /Foreign Run evidence/);
  assert.throws(() => composed(occurrence, [captured], [{...evidence}], 'authority', 'start', 'end'), /Foreign Run evidence/);
  assert.equal(calls.length, 2);
});


test('saved INFER reacquisition forwards the original captured token without another evidence admission', async () => {
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}); let selected;
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'run' &&
        node.value.params?.[0]?.properties?.some(field => field.key?.name === 'acquireSource')) {
      assert.equal(selected, undefined); selected = node.value;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  }
  walk(ast); assert(selected);
  const prepared = {}, captured = {checkedSource: {sourceDataPolicyCid: 'policy'}}, evidence = {}, input = {}, plan = {},
    ref = {}, sourceAccess = {}, preparedSource = {}, signal = {}, retainExecution = () => {}, beginPhysicalWork = () => {};
  let cancelled = false, reads = 0, admissions = 0, executions = 0;
  const context = {journal: {lookupRunDefinition: value => {assert.equal(value, ref); return {
    cancellationRequested: cancelled, observedTerminalOutcome: null, runDefinition: {wire: 'definition'},
  };}}, accepted: {ref}, moon: {clientProgramAdmitInferCapturedInput() {assert.fail('wire path');}},
    control: {admitInferCapturedInput(body, acquisition, original, authority, policy, start, end) {
      assert.equal(body, prepared); assert.equal(acquisition, captured); assert.equal(original, evidence);
      assert.deepEqual([authority, policy, start, end], ['authority', 'policy', 'start', 'end']); admissions++; return input;
    }, admitRunEvidence() {assert.fail('original evidence admitted again');}},
    planFor: () => plan, submission: {preparedProgram: prepared}, requested: {}, acquired: true,
    checkpoints: undefined, sourceProfile: {sourceAccess}, prepareAcquisition: async (body, access) => {
      assert.equal(body, prepared); assert.equal(access, sourceAccess); return preparedSource;
    }, authorityScopeCid: 'authority', store: {}, actual: 'actor',
    runInfer: async options => {executions++; assert.equal(options.plan, plan); assert.equal(options.replay, true);
      assert.equal(options.acquiredInfer.input, input); assert.equal(options.acquiredInfer.sourceEvidence, evidence);
      assert.equal(options.signal, signal); assert.equal(options.retainExecution, retainExecution);
      assert.equal(options.beginPhysicalWork, beginPhysicalWork);},
  };
  const code = `async function(${selected.params.map(param => text.slice(param.start, param.end)).join(',')})${text.slice(selected.body.start, selected.body.end)}`;
  const run = new Function(...Object.keys(context), `return (${code});`)(...Object.values(context));
  const ports = {signal, retainExecution, beginPhysicalWork, acquireSource: async options => {
    reads++; assert.equal(options.preparedProgram, prepared); assert.equal(options.preparedSource, preparedSource);
    assert.equal(options.sourceAccess, sourceAccess); return {captured, sourceEvidence: evidence,
      captureStartedAt: 'start', captureCompletedAt: 'end'};
  }};
  await run(ports); assert.deepEqual([reads, admissions, executions], [1, 1, 1]);
  cancelled = true; await run(ports); assert.deepEqual([reads, admissions, executions], [1, 1, 1]);
});

// Execute the original thin caller bodies with explicit typed-selection and
// adapter ports. These cases issue no real Core/Account/Run or physical read.
function sourceRouteBinding(name, context, optional = false) {
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  let found;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === name) found = node.init;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(ast);
  if (optional && found === undefined) return undefined;
  assert(found, name);
  return new Function(...Object.keys(context), `return (${text.slice(found.start, found.end)});`)(...Object.values(context));
}

function sourceRouteCallerFixture({kind = 'whole-input', queryFailure, wrapAdapter} = {}) {
  const prepared = {}, requested = {}, sourceSelection = {}, preparedSource = {};
  const sourceAccess = {}, sourceProfile = {}, reference = 'connector://fixture/rows#original';
  const events = [], identities = new WeakMap();
  let identityCalls = 0, queryCalls = 0;
  const ok = value => ({$tag: 1, _0: value});
  const checked = result => {
    if (result?.$tag === 1) return result._0;
    throw Object.assign(new Error('MoonBitHostFailure', {cause: result?._0}), {code: 'MoonBitHostFailure'});
  };
  const originalAdapter = {sourceAccess, managedWholeSourceCapacity() {}, async prepare(facts) {
    assert.equal(facts.preparedProgram, prepared);
    assert.equal(facts.requestIdentity, requested);
    assert.equal(facts.sourceAccess, sourceAccess);
    assert.deepEqual(facts.occurrence, {stage: 0, input: 0, task: 0});
    assert.equal(facts.requireImmediateReadAuthorization, true);
    events.push('same-adapter'); return preparedSource;
  }};
  const adapter = wrapAdapter === undefined ? originalAdapter : wrapAdapter(originalAdapter, prepared);
  const moon = {
    clientProgramAcquisitionCount(body) {assert.equal(body, prepared); return 1;},
    clientProgramSelectSingleKeyedAcquisition(body) {assert.equal(body, prepared); return ok(undefined);},
    clientProgramRequestIdentity(body, authority, id, intent) {
      assert.equal(body, prepared); assert.equal(authority, 'authority');
      assert.equal(id, 'original-request'); assert.equal(intent, 'original-input-intent');
      identityCalls++; return requested;
    },
    clientProgramSourceFreeInputIntentCid() {return 'original-input-intent';},
    clientProgramSelectInstalledSourceInput(body, request, stage, input) {
      assert.equal(body, prepared); assert.equal(request, requested);
      assert.deepEqual([stage, input], [0, 0]); events.push('typed-selection'); return ok(sourceSelection);
    },
    clientProgramSelectedSourceInputKind(selection) {assert.equal(selection, sourceSelection); return kind;},
    clientProgramSelectedSourceInputRef(selection) {assert.equal(selection, sourceSelection); return reference;},
    clientProgramPrepareLocalQueryRequirement() {
      queryCalls++;
      return {$tag: 0, _0: queryFailure ?? 'WholeInputIsNotQuery'};
    },
    clientProgramComposedInferOccurrences(body) {assert.equal(body, prepared); return ok([]);},
    clientProgramResultCount(body) {assert.equal(body, prepared); return 1;},
    clientProgramResultName(body, index) {assert.equal(body, prepared); assert.equal(index, 0); return 'rows';},
  };
  const context = {moon, preparation: undefined, prepareSubmit: {assertOwned(body) {assert.equal(body, prepared);}, kindOf() {return 'effect_free';}},
    sourceProfile, sourceFreeRequestIdentities: identities, earlyContentPlans: new WeakMap(),
    inferSelections: new WeakMap(), prepareInferSelection(body, occurrence) {assert.equal(body, prepared); assert.equal(occurrence, undefined);},
    installedSourceFor(profile, ref) {assert.equal(profile, sourceProfile); assert.equal(ref, reference); return adapter;},
    installedSourceReadBindings: () => [reference], checked, authorityScopeCid: 'authority',
    runtimeIsOkRequired: value => value?.$tag === 1, runtimeField: (value, index) => value?.[`_${index}`],
    runtimeOptionalField: (value, index) => value?.[`_${index}`],
    runtimeTag: value => value?.$tag,
    clientOperationError: (code, cause) => Object.assign(new Error(code, {cause}), {code}),
    diagnostic() {}, registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered',
    checkpoints: undefined, ExecutionAuthorizationError: class extends Error {},
  };
  context.originalSourceFreeRequest = sourceRouteBinding('originalSourceFreeRequest', context, true);
  const requestOf = sourceRouteBinding('requestOf', context);
  const prepareAcquisition = sourceRouteBinding('prepareAcquisition', context);
  return {prepared, requested, preparedSource, events, identities,
    request: id => requestOf({preparedProgram: prepared, requestId: id ?? 'original-request'}),
    prepare: () => prepareAcquisition(prepared),
    counts: () => ({identityCalls, queryCalls})};
}

test('whole-input Host request and acquisition keep one original identity without a Query substitute', async () => {
  const f = sourceRouteCallerFixture();
  const first = f.request();
  assert.equal(first.requested, f.requested);
  assert.equal(f.request().requested, f.requested);
  assert.equal(await f.prepare(), f.preparedSource);
  assert.deepEqual(f.counts(), {identityCalls: 1, queryCalls: 0});
  assert.deepEqual(f.events, ['typed-selection', 'typed-selection', 'typed-selection', 'same-adapter']);
});

test('whole-input caller controls preserve Query refusal and reject a changed request identity', () => {
  const original = new Error('Original Query refusal');
  const query = sourceRouteCallerFixture({kind: 'query', queryFailure: original});
  assert.throws(() => query.request(), error => error.code === 'ClientProgramUnsupported' && error.cause.cause === original);
  assert.deepEqual(query.counts(), {identityCalls: 1, queryCalls: 1});
  assert.equal(query.events.includes('same-adapter'), false);
  const whole = sourceRouteCallerFixture();
  assert.equal(whole.request().requested, whole.requested);
  assert.throws(() => whole.request('different-request'), {code: 'ForeignInstalledComputeRun'});
  assert.deepEqual(whole.counts(), {identityCalls: 1, queryCalls: 0});
  assert.deepEqual(whole.events, ['typed-selection']);
});

test('whole-input acquisition uses the actual managed-source wrapper and preserves its current refusal', async () => {
  for (const retireDuringPrepare of [false, true]) {
    const parent = {}, refusal = new Error('Original managed Source current refusal');
    let live = true, entered = 0, currentChecks = 0;
    const f = sourceRouteCallerFixture({wrapAdapter(adapter, prepared) {
      const originalPrepare = adapter.prepare;
      adapter.managedCaptureCapacity = () => assert.fail('No Query-capacity substitute');
      adapter.ledgerCapacity = () => assert.fail('No Ledger construction');
      adapter.prepare = async facts => {
        assert.equal(facts.managedRun, parent); entered++;
        const result = await Reflect.apply(originalPrepare, adapter, [facts]);
        if (retireDuringPrepare) live = false;
        return result;
      };
      return bindInstalledManagedSources(adapter, body => {
        assert.equal(body, prepared); currentChecks++;
        if (!live) throw refusal;
        return parent;
      });
    }});
    assert.equal(f.request().requested, f.requested);
    if (retireDuringPrepare) await assert.rejects(f.prepare(), error => error === refusal);
    else assert.equal(await f.prepare(), f.preparedSource);
    assert.equal(entered, 1); assert.equal(currentChecks, 2);
    assert.deepEqual(f.counts(), {identityCalls: 1, queryCalls: 0});
  }
});

test('graceful drain retains the original Host identity without reopening preparation', async () => {
  const options = {mode: 'local', owner: 'local'};
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'durable', scopeRef: 'scope', capabilities: [], limits: {maxReadWireBytes: 65536,
      maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
      maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
  const deferred = () => {let resolve; const promise = new Promise(done => {resolve = done;}); return {promise, resolve};};
  const registry = createEmbeddedHostRegistry(() => true), host = {}, installation = {};
  registry.registerPreparation(host, installation, host);
  const entered = deferred(), released = deferred();
  let closed = false;
  Object.assign(host, {port: {async perform(operation) {
    assert.equal(operation, 'connect'); return profile;
  }}, dispatchOwner: {async drain() {entered.resolve(); await released.promise;
    registry.assertRetainedPreparation(host, installation, host);
  }}, retireTerminalEffects() {}, journal: {close() {}}, store: {close() {}}});
  const connect = () => registry.connect('/retained-original', 'same', () => host,
    options, host);
  const client = await connect();
  const closing = client.close().then(() => {closed = true;});
  await entered.promise;
  assert.equal(closed, false);
  registry.assertRetainedPreparation(host, installation, host);
  assert.throws(() => registry.assertPreparation(host, installation, host),
    /InstalledHostPreparationChanged/);
  for (const [actualHost, actualInstallation, generation] of [
    [{}, installation, host], [host, {}, host], [host, installation, {}],
  ]) assert.throws(() => registry.assertRetainedPreparation(actualHost, actualInstallation, generation),
    /InstalledHostPreparationChanged/);
  await assert.rejects(connect(), /InstalledHostPreparationChanged|ClientHostClosing/);
  released.resolve(); await closing;
  assert.throws(() => registry.assertRetainedPreparation(host, installation, host),
    /InstalledHostPreparationChanged/);
});


test('failed Host initialization cannot lend retained publication identity while cleanup is pending', async () => {
  const registry = createEmbeddedHostRegistry(() => true), host = {}, installation = {};
  registry.registerPreparation(host, installation, host);
  let pending = true;
  const primary = Object.assign(new Error('OriginalInitializationFailure'), {cleanupPending: true,
    cleanupHandle: {status: () => ({pending}), async retry() {pending = false;}}});
  let failure;
  await assert.rejects(registry.connect('/failed-original', 'same', () => {throw primary;},
    {mode: 'local', owner: 'local'}, host), error => {failure = error; return error.cleanupPending === true;});
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.throws(() => registry.assertRetainedPreparation(host, installation, host),
    /InstalledHostPreparationChanged/);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.throws(() => registry.assertRetainedPreparation(host, installation, host),
    /InstalledHostPreparationChanged/);
});


test('DuckDB original evidence transfer retains the same issuer value and rejects pending or retired access', async () => {
  const original = {}, options = {}, seen = [];
  let live = true, complete;
  class Failure extends Error {constructor(code) {super(code); this.code = code;}}
  const create = get('../connectors/duckdb/node/host.mjs', 'sourceEvidenceOriginalAccess', {
    DuckDBTransportError: Failure,
  });
  const access = create(() => {if (!live) throw new Failure('ClosedSourceCapture');}, value => {
    assert.equal(value, options); seen.push(value);
    return new Promise(resolve => {complete = resolve;});
  });
  const preparing = access.prepare(options);
  assert.throws(() => access.take(), {code: 'SourceEvidenceUnavailable'});
  await assert.rejects(access.prepare(options), {code: 'SourceEvidencePending'});
  complete(original); await preparing;
  assert.equal(access.take(), original);
  assert.throws(() => access.take(), {code: 'SourceEvidenceUnavailable'});
  const next = access.prepare(options);
  live = false; complete(original);
  await assert.rejects(next, {code: 'ClosedSourceCapture'});
  assert.throws(() => access.take(), {code: 'ClosedSourceCapture'});
  // No successful physical retirement was inferred from the failed prepare.
  live = true;
  const retained = access.prepare(options); complete(original); await retained;
  access.retire();
  assert.throws(() => access.take(), {code: 'SourceEvidenceUnavailable'});
  assert.equal(seen.length, 3);
});

test('DuckDB captured Source prepares evidence on the same original physical capture without wire fallback', async () => {
  for (const broad of [false, true]) {
    const preparedProgram = {}, preparedSource = {checkedSource: {sourceRef: 'original'}},
      registry = {}, sourceAccess = {}, requirement = {}, evidenceContext = {}, identity = {},
      logicalInput = {}, capturedSource = {}, acquisition = {}, ledger = {}, options = {};
    const capture = Object.freeze({source: () => capturedSource, close() {},
      document() {assert.fail('No observation wire required for evidence preparation');}});
    const owner = {moon: undefined, checkedOwner: preparedProgram, effectful: false,
      occurrence: {stage: 0, input: 0, task: 0}, registry, values: 'values', fragment: 'fragment',
      ordered: 'ordered', database: 'unopened', schema: 'main', table: 'records', sourceAccess,
      transportLimits: {}, acquisitionPlanning: undefined, acquisition, broad,
      requirement, evidenceContext, selection: undefined};
    const moon = owner.moon = {
      clientProgramCapturedTaskSourceMatches: (actual, source, task) => {
        assert.equal(actual, preparedProgram); assert.equal(source, capturedSource); assert.equal(task, 0); return true;
      },
      clientProgramIdentifyCapturedSourceRelation: source => {assert.equal(source, capturedSource); return identity;},
      clientProgramIssueCapturedTaskSourceLogical: (...values) => {
        assert.deepEqual(values, [preparedProgram, capturedSource, identity, requirement, 0]); return logicalInput;
      },
    };
    const prepareNativeSourceEvidenceOriginal = async (original, selected) => {
      assert.equal(original, capture);
      assert.deepEqual(selected, {...options, context: evidenceContext, identity, logicalInput});
    };
    const native = {session: {authorizeLocalDatabase: async () => ({})}, host: {
      runNativeHostQuery() {assert.fail('The original parent Ledger must be retained');},
      runStrategyNativeHostQuery: async () => {assert.equal(broad, false); return capture;},
      runBroadHostQuery: async () => {assert.equal(broad, true); return capture;},
      nativeSourceIdentityMatches: (actual, selected) => actual === capture && selected === identity,
      prepareNativeSourceEvidenceOriginal,
      issueNativeSourceEvidence() {assert.fail('No evidence wire or readmission');},
    }};
    const open = get('./captured-duckdb-source.mjs', 'openCapturedDuckDBSource', {
      preparations: new WeakMap([[preparedSource, owner]]), admittedTransportPolicy: () => ({}),
      transportLimitKeys: [], currentReadDecision: async () => ({action: 'dispatch'}),
      loadDuckDBNativeRuntime: async () => native, checked: value => value,
      runtimeIsOk: () => false, runtimeField() {assert.fail('No synthetic runtime tuple');},
      acquisitionFailure() {assert.fail('Unexpected physical failure');},
      ExecutionAuthorizationError: class extends Error {},
    });
    const result = await open({moon, preparedProgram, registry, values: 'values', fragment: 'fragment',
      ordered: 'ordered', database: 'unopened', schema: 'main', table: 'records', sourceAccess,
      preparedSource, transportLimits: {}, ledger});
    assert.equal(result.capture, capture);
    await result.prepareSourceEvidenceOriginal(options);
    await result.close();
  }
});
