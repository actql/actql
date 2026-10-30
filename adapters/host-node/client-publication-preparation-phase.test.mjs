import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
function get(file,name,context,property=false){const source=readFileSync(new URL(file,import.meta.url),'utf8'),ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let n;function walk(x){if(!x||typeof x!=='object')return;if(property?x.type==='Property'&&x.key?.name===name:x.type==='FunctionDeclaration'&&x.id?.name===name)n=property?x.value:x;for(const v of Object.values(x)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}}walk(ast);assert(n,name);const code=property?`${n.async?'async ':''}function(${n.params.map(p=>source.slice(p.start,p.end)).join(',')})${source.slice(n.body.start,n.body.end)}`:source.slice(n.start,n.end);return new Function(...Object.keys(context),`return ${code}`)(...Object.values(context));}
const fail=code=>{throw Object.assign(new Error(code),{code});};
test('publication phase manager relays the actual original Run without caller quote or holder',()=>{
 const prepared={},phase={},holder={},runOriginal={},seen=[];const state={prepared,phase,holder,adopting:true,context:{runtime:{clientProgramReservePublication(...args){seen.push(args);return 'result';}}}};
 const invoke=get('./ordinary-source-managed.mjs','reservePublication',{runFor:p=>{assert.equal(p,prepared);return {producer:{preparation:state},value:runOriginal};},fail,checkedPreparation:(moon,result)=>{assert.equal(result,'result');return 'original-resource';}},true);
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
 compiled.kind='tasks';assert.throws(()=>invoke(compiled,definition,{dataPolicyCid:'policy'},limits,owner,prepared),/Invalid original publication invocation profile/);assert.equal(calls.length,1);
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
