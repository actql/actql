import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

function method(file, name, context) {
 const source=readFileSync(new URL(file,import.meta.url),'utf8');
 const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let found;
 function walk(node){if(!node||typeof node!=='object')return;if(node.type==='Property'&&node.key?.name===name){assert.equal(found,undefined);found=node.value;}for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}}
 walk(ast);assert(found,name);
 return new Function(...Object.keys(context),`return function(${found.params.map(p=>source.slice(p.start,p.end)).join(',')})${source.slice(found.body.start,found.body.end)}`)(...Object.values(context));
}
const failure=code=>Object.assign(new Error(code),{code});

test('funded compilation getter borrows exact live driver original and never reconstructs missing artifacts',()=>{
 const prepared={},parent={},value={},holder={},compilation={};
 const state={prepared,parent,holder,adopting:true,context:{runtime:{clientProgramInstalledManagedRunCompilationOriginal(run,p){assert.equal(run,value);assert.equal(p,prepared);return compilation;}}}};
 const run={value,producer:{preparation:state}};
 const get=method('./ordinary-source-managed.mjs','compilationOriginal',{runFor:p=>{assert.equal(p,prepared);return run;},fail:code=>{throw failure(code);}});
 assert.equal(get(prepared),compilation);
 state.holder=undefined;assert.throws(()=>get(prepared),{code:'ForeignInstalledSourceProducer'});state.holder=holder;
 run.value=undefined;assert.throws(()=>get(prepared),{code:'NodeManagedRunAdmissionUnavailable'});run.value=value;
 state.context.runtime.clientProgramInstalledManagedRunCompilationOriginal=()=>undefined;
 assert.throws(()=>get(prepared),{code:'NodeManagedRunCompilationUnavailable'});
});

test('installed compilation relay rejects foreign runtime, closed Run and missing funded original',()=>{
 const runtime={},prepared={},compilation={};let reads=0;
 const run={runtime,prepared,preparationFunded:true,closed:false,manager:{compilationOriginal(p){assert.equal(p,prepared);reads++;return compilation;}}};
 const record={computeRuns:new WeakMap([[prepared,run]])};
 const get=method('./embedded-local.mjs','managedComputeCompilationOriginal',{record,clientOperationError:failure});
 assert.equal(get(runtime,prepared),compilation);assert.equal(reads,1);
 assert.throws(()=>get({},prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 run.closed=true;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});run.closed=false;
 run.manager.compilationOriginal=()=>undefined;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunCompilationUnavailable'});
 assert.equal(get(runtime,{}),undefined);
});

test('Values admission consumes staged nominal compilation without invoking the compiler again',()=>{
 const prepared={},compilation={},issued={};let compiles=0,issues=0;
 const moon={clientProgramCompileLocalValues(){compiles++;return compilation;},
  clientProgramIssueValuesCompiledRun(p,c){issues++;assert.equal(p,prepared);if(c!==compilation)throw failure('ForeignOwner');return issued;},
  clientProgramIssueTaskCompiledRun(){throw failure('ForeignOwner');},
  clientProgramIssueOriginalValuesCompiledRun(p,c){return this.clientProgramIssueValuesCompiledRun(p,c);},
  clientProgramIssueOriginalTaskCompiledRun(){throw failure('ForeignOwner');}};
 for(const key of ['Template','Plan','Prepared','Authorization','Admission'])moon['clientProgramCompiledRun'+key]=()=>({});
 const compiledRunTokens=new WeakMap();
 const get=method('../host-common/runtime-core.mjs','prepareCheckedClientCompiledRun',{moon,compiledRunTokens,serializationPlanTokens:new WeakMap(),compiledRunResult:x=>x,inspectEvidence:x=>x,inspect:x=>x,inspectAdmission:x=>x});
 const policy={executionContextCid:'context',hostPolicyCid:'policy',expiresAt:'time'};
 const result=get(prepared,'values',policy,undefined,compilation);
 assert.equal(compiledRunTokens.get(result),issued);assert.equal(compiles,0);assert.equal(issues,1);
 assert.throws(()=>get(prepared,'values',policy,undefined,{}),{code:'ForeignOwner'});assert.equal(compiles,0);
 assert.throws(()=>get(prepared,'tasks',policy,undefined,compilation),{code:'ForeignOwner'});assert.equal(compiles,0);
 get(prepared,'values',policy);assert.equal(compiles,1); // Unmigrated caller stays explicit, never rescues missing funded originals.
});

test('source-free Values passes its original and fixed installation warms compiler manifests',()=>{
 const plan=readFileSync(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
 assert.match(plan,/hostPolicyCid, expiresAt: validUntil\}, undefined, compilationOriginal\)/u);
 const installed=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
 const start=installed.indexOf('export function prepareInstalledSequenceContractOriginal');
 const end=installed.indexOf('\n}\n',start);
 const body=installed.slice(start,end);
 assert.ok(body.indexOf('clientPrepareInstalledCompilationManifests());')<body.indexOf('const admission = checked('));
});

test('staged Task admission uses the original artifact and leaves foreign refusal with its issuer',()=>{
 const prepared={},compilation={},issued={};let compiles=0,issues=0;
 const moon={clientProgramCompileLocalTasks(p){assert.equal(p,prepared);compiles++;return compilation;},
  clientProgramIssueTaskCompiledRun(p,c){issues++;if(p!==prepared||c!==compilation)throw failure('ForeignTaskCompilation');return issued;},
  clientProgramIssueOriginalTaskCompiledRun(p,c){return this.clientProgramIssueTaskCompiledRun(p,c);}};
 for(const key of ['Template','Plan','Prepared','Authorization','Admission'])moon['clientProgramCompiledRun'+key]=()=>({});
 const compiledRunTokens=new WeakMap();
 const get=method('../host-common/runtime-core.mjs','prepareCheckedClientCompiledRun',{moon,compiledRunTokens,serializationPlanTokens:new WeakMap(),compiledRunResult:x=>x,inspectEvidence:x=>x,inspect:x=>x,inspectAdmission:x=>x});
 const policy={executionContextCid:'context',hostPolicyCid:'policy',expiresAt:'time'};
 assert.equal(compiledRunTokens.get(get(prepared,'tasks',policy,undefined,compilation)),issued);
 assert.equal(compiles,0);assert.equal(issues,1);
 assert.throws(()=>get(prepared,'tasks',policy,undefined,{}),{code:'ForeignTaskCompilation'});
 assert.throws(()=>get({},'tasks',policy,undefined,compilation),{code:'ForeignTaskCompilation'});
 assert.equal(compiles,0);assert.equal(issues,3);
 get(prepared,'tasks',policy);assert.equal(compiles,1);assert.equal(issues,4);
});

test('staged Task plan passes the same artifact through the existing admission function',()=>{
 const source=readFileSync(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
 const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
 const selected=ast.body.find(node=>node.type==='FunctionDeclaration'&&node.id?.name==='checkedTaskRunAdmission');
 assert(selected);
 const preparedProgram={},compilationOriginal={},compiled={admission:{},compiledPlan:{}};
 let calls=0;
 const control={prepareCheckedClientCompiledRun(prepared,kind,policy,graph,compilation){
  calls++;assert.equal(prepared,preparedProgram);assert.equal(kind,'tasks');assert.equal(graph,undefined);assert.equal(compilation,compilationOriginal);return compiled;
 },defineCheckedClientCompiledRun(actual){assert.equal(actual,compiled);return {};}};
 const context={prepareQueryInvocation:()=>undefined,instant:ms=>new Date(ms).toISOString(),cid:()=> 'context',policyCid:()=> 'policy',randomUUID:()=> 'run',bindQueryInvocation:()=>({}),retainOriginalPlan:value=>value};
 const invoke=new Function(...Object.keys(context),`return (${source.slice(selected.start,selected.end)})`)(...Object.values(context));
 const value=invoke({control,preparedProgram,compilationOriginal,now:()=> '2026-10-29T00:00:00.000Z'},'tasks');
 assert.equal(value.compiled,compiled);assert.equal(calls,1);
});

test('barrier profiles retain their original graph requirements without an artifact fallback',()=>{
 let compiles=0,issues=0;
 const moon=new Proxy({}, {get(){return ()=>{compiles++;throw new Error('UnexpectedCompiler');};}});
 const get=method('../host-common/runtime-core.mjs','prepareCheckedClientCompiledRun',{moon,compiledRunTokens:new WeakMap(),serializationPlanTokens:new WeakMap(),compiledRunResult:x=>{issues++;return x;},inspectEvidence:x=>x,inspect:x=>x,inspectAdmission:x=>x});
 for(const kind of ['infer','serialization']) {
  assert.throws(()=>get({},kind,{},undefined,{}),/requires its checked graph/);
  if(kind==='serialization') assert.throws(()=>get({},kind,{},{},{}),/Foreign Content compilation graph/);
 }
 assert.equal(compiles,0);assert.equal(issues,0);
});

test('Request Serialization consumes its original TaskCompilation and rejects copied graphs without compiling again', () => {
 const prepared={},graph={},rawGraph={},compilation={},issued={},tokens=new WeakMap();let issues=0;
 const moon={clientProgramCompileLocalSerialization(){assert.fail('Do not recompile original Request Serialization');},
  clientProgramIssueOriginalTaskCompiledRun(){assert.fail('Serialization artifact is not a compilation sum');},
  clientProgramIssueTaskCompiledRun(p,c){issues++;if(p!==prepared||c!==compilation)throw failure('ForeignSerializationCompilation');return issued;},
  clientProgramCompiledRunSerializationGraph:()=>rawGraph};
 for(const name of ['Template','Plan','Prepared','Authorization','Admission'])moon['clientProgramCompiledRun'+name]=()=>({});
 const invoke=method('../host-common/runtime-core.mjs','prepareCheckedClientCompiledRun',{moon,compiledRunTokens:tokens,
  serializationPlanTokens:new WeakMap([[graph,rawGraph]]),compiledRunResult:value=>value,
  inspectEvidence:value=>value,inspect:value=>value,inspectAdmission:value=>value});
 const result=invoke(prepared,'serialization',{},graph,compilation);
 assert.equal(tokens.get(result),issued);assert.equal(issues,1);
 assert.throws(()=>invoke(prepared,'serialization',{},graph,{}),{code:'ForeignSerializationCompilation'});
 assert.throws(()=>invoke({},'serialization',{},graph,compilation),{code:'ForeignSerializationCompilation'});
 assert.throws(()=>invoke(prepared,'serialization',{}, {...graph},compilation),/Foreign Content compilation graph/);
 assert.equal(issues,3);
});


test('timed original projection forwards the Core Option without a JavaScript tuple constructor',()=>{
 const q={},prepared={},opaque=new Proxy({}, {get(){assert.fail('opaque Option inspected');}});
 const moon={clientProgramQueryTimeInvocationOriginal:function(...args){assert.equal(this,moon);assert.deepEqual(args,[q,prepared]);return opaque;}};
 const project=method('../host-common/runtime-core.mjs','clientQueryTimeInvocationOriginal',{moon});
 assert.equal(project(q,prepared),opaque);moon.clientProgramQueryTimeInvocationOriginal=undefined;assert.throws(()=>project(q,prepared),/unavailable/);
});

test('timed original adopted getter checks all first tokens and refuses retired or foreign projections',()=>{
 const run={},prepared={},request={},q={},context={},compiled={},compiledToken={},definition={},definitionToken={},compiledRunTokens=new WeakMap([[compiled,compiledToken]]);
 const expected={preparedProgram:prepared,requestIdentity:request,queryTimePreparation:q,queryTime:context,compiled,runDefinition:definition};
 let output={_0:q,_1:request,_2:compiledToken,_3:definitionToken},checks=0;
 const moon={clientProgramInstalledManagedRunInvocationOriginal:function(r,p){assert.equal(this,moon);assert.equal(r,run);assert.equal(p,prepared);return output;},clientProgramQueryTimeContext:actual=>{assert.equal(actual,q);return context;}};
 const control={checkClientCompiledRunOwner(c,p){assert.equal(c,compiled);assert.equal(p,prepared);checks++;}};
 const get=method('../host-common/runtime-core.mjs','checkedClientManagedQueryInvocationOriginal',{moon,compiledRunTokens,token:d=>{assert.equal(d,definition);return definitionToken;},runtimeOptionalField:(v,i)=>v?.['_'+i],control});
 assert.equal(get(run,prepared,expected),expected);assert.equal(checks,1);
 const valid=output;
 for(let i=0;i<4;i++){output={...valid,['_'+i]:{}};assert.throws(()=>get(run,prepared,expected),/Foreign Client original/);}
 for(const value of [undefined,{$tag:0},{$tag:1,_0:valid}]){output=value;assert.throws(()=>get(run,prepared,expected),/Foreign Client original/);}
 output=valid;assert.throws(()=>get(run,prepared,{...expected,queryTime:{}}),/Foreign Client original/);assert.equal(checks,1);
});


// Import the whole product module. The extracted tests above intentionally
// isolate methods and cannot establish their module-level lexical bindings.
const {runtimeCore: actualRuntimeCore} = await import('../host-common/runtime-core.mjs');

test('actual timed invocation module resolves its canonical projection with registered original compilation',()=>{
 const prepared={},request={},run={},compiledToken={},definitionToken={},artifact={},q={},context={};
 const projectedRead=Error('original projection read boundary'),primary=Error('original getter failure');
 let mode='read',reads=0,issuers=0,definitions=0,projections=0;
 // Existing pinned Result ports only. No opaque Option or tuple layout is
 // manufactured here: the read probe refuses on any property access.
 const ok=value=>({$tag:1,_0:value});
 const readProbe=new Proxy(Object.create(null),{get(){reads++;throw projectedRead;}});
 const moon={
  strategyRemoteManagedOutputEvidenceKind:()=> 'unused-component-remote-kind',
  clientProgramIssueOriginalValuesCompiledRun(p,a){assert.equal(p,prepared);assert.equal(a,artifact);issuers++;return ok(compiledToken);},
  clientProgramCompiledRunTemplate:()=>({}),clientProgramCompiledRunPlan:()=>({}),
  clientProgramCompiledRunPrepared:()=>({}),clientProgramCompiledRunAuthorization:()=>({}),clientProgramCompiledRunAdmission:()=>({}),
  strategyRunEvidenceName:()=> 'component-evidence',strategyRunEvidenceIdentity:()=> 'component-identity',strategyRunEvidenceJson:()=> '{}',
  strategyPublicationContractName:()=> 'run_definition',strategyPublicationContractIdentityField:()=> 'run_id',
  strategyPublicationContractIdentity:()=> 'component-run',strategyPublicationContractJson:()=> '{}',
  clientProgramIssueCompiledRunDefinition(value){assert.equal(value,compiledToken);definitions++;return ok(definitionToken);},
  clientProgramInstalledManagedRunInvocationOriginal(r,p){assert.equal(r,run);assert.equal(p,prepared);projections++;if(mode==='failure')throw primary;return mode==='none'?undefined:readProbe;},
  clientProgramQueryTimeContext:()=>context,
  clientProgramCompiledRunMatches(value,p){assert.equal(value,compiledToken);return p===prepared;},
 };
 const control=actualRuntimeCore(moon).publicationControl;
 const compiled=control.prepareCheckedClientCompiledRun(prepared,'values',{},undefined,artifact);
 const runDefinition=control.defineCheckedClientCompiledRun(compiled,{});
 const original={preparedProgram:prepared,requestIdentity:request,queryTimePreparation:q,queryTime:context,compiled,runDefinition};
 assert.throws(()=>control.checkedClientManagedQueryInvocationOriginal(run,prepared,original),e=>e===projectedRead);
 assert.equal(reads,1);assert.equal(issuers,1);assert.equal(definitions,1);
 // Retired/missing and copied originals refuse through the same real module;
 // no injected helper, recompilation or inferred valid new Common ABI.
 mode='none';assert.throws(()=>control.checkedClientManagedQueryInvocationOriginal(run,prepared,original),/Foreign Client original/);
 mode='read';assert.throws(()=>control.checkedClientManagedQueryInvocationOriginal(run,prepared,{...original,compiled:{...compiled}}),/Foreign Client original/);
 assert.equal(reads,1);
 mode='failure';assert.throws(()=>control.checkedClientManagedQueryInvocationOriginal(run,prepared,original),e=>e===primary);
 assert.equal(projections,4);assert.equal(issuers,1);assert.equal(definitions,1);
});


test('actual Model admission uses the Request raw TaskCompilation without a compiler or sum conversion', async () => {
 const {runtimeCore}=await import('../host-common/runtime-core.mjs');
 const prepared={},graph={},artifact={},compiledToken={},calls=[];
 const ok=value=>({$tag:1,_0:value});
 const moon={strategyRemoteManagedOutputEvidenceKind:()=> 'fixture',
  clientProgramCompileLocalInfer(){assert.fail('Request Model must not compile again');},
  clientProgramCompileLocalInfers(){assert.fail('Request Model must not compile again');},
  clientProgramIssueOriginalTaskCompiledRun(){assert.fail('A raw Model artifact is not a Values/Tasks sum');},
  clientProgramIssueTaskCompiledRun(p,a,...policy){
   calls.push([p,a,...policy]);
   return p===prepared&&a===artifact?ok(compiledToken):{$tag:0,_0:'ForeignModelCompilation'};
  },
  clientProgramBindCompiledInferResultPolicy(value,cid,wire){assert.equal(value,compiledToken);assert.equal(cid,'policy');assert.equal(wire,'{}');return ok(value);},
  strategyRunEvidenceName:()=> 'component',strategyRunEvidenceIdentity:()=> 'identity',strategyRunEvidenceJson:()=> '{}',
  strategyPublicationContractName:()=> 'compiled_plan',strategyPublicationContractIdentityField:()=> 'compiled_plan_cid',
  strategyPublicationContractIdentity:()=> 'plan',strategyPublicationContractJson:()=> '{}',
 };
 for(const name of ['Template','Plan','Prepared','Authorization','Admission'])moon['clientProgramCompiledRun'+name]=()=>({});
 const control=runtimeCore(moon).publicationControl;
 const policy={executionContextCid:'context',hostPolicyCid:'host',expiresAt:'expiry',resultDataPolicy:{kind:'data_policy',cid:'policy',wire:'{}'}};
 const result=control.prepareCheckedClientCompiledRun(prepared,'infer',policy,[graph],artifact);
 assert.equal(result.kind,'infer');
 assert.deepEqual(calls,[[prepared,artifact,'context','host','expiry']]);
 assert.throws(()=>control.prepareCheckedClientCompiledRun(prepared,'infer',policy,[graph],{}),{code:'RunHostAdmissionRejected'});
 assert.throws(()=>control.prepareCheckedClientCompiledRun({},'infer',policy,[graph],artifact),{code:'RunHostAdmissionRejected'});
 assert.throws(()=>control.prepareCheckedClientCompiledRun(prepared,'infer',policy,undefined,artifact),/requires its checked graph/);
 assert.equal(calls.length,3);
});


test('actual Model Plan bindings retain module, Request, selected bounds and registered Run originals', async () => {
 const {runtimeCore}=await import('../host-common/runtime-core.mjs');
 const opaque=label=>new Proxy({}, {get(){assert.fail(label+' must remain opaque');}});
 const prepared={},artifact={},compiledToken={},definitionToken={},occurrence={};
 const graph=opaque('original Graph'),selected=opaque('original selected Limits'),request=opaque('original Request');
 const sourceFree=opaque('original source-free module'),captured=opaque('original capture Plan');
 const parent={},input={},freePlan={},capturePlan={},calls=[];let refusal;
 const ok=value=>({$tag:1,_0:value});
 const moon={strategyRemoteManagedOutputEvidenceKind:()=> 'fixture',
  clientProgramIssueTaskCompiledRun(p,a){assert.equal(p,prepared);assert.equal(a,artifact);return ok(compiledToken);},
  clientProgramBindCompiledInferResultPolicy:value=>ok(value),
  clientProgramIssueCompiledRunDefinition(value){assert.equal(value,compiledToken);return ok(definitionToken);},
  strategyRunEvidenceName:()=> 'evidence',strategyRunEvidenceIdentity:()=> 'identity',strategyRunEvidenceJson:()=> '{}',
  strategyPublicationContractName:()=> 'run_definition',strategyPublicationContractIdentityField:()=> 'run_id',
  strategyPublicationContractIdentity:()=> 'definition',strategyPublicationContractJson:()=> '{}',
  clientProgramPrepareRequestModelSourceFreePlan(...args){
   assert.equal(this,moon);assert.deepEqual(args,[parent,input,sourceFree,request,compiledToken,definitionToken,occurrence,graph,selected]);
   calls.push('source-free');return refusal===undefined?ok(freePlan):{$tag:0,_0:refusal};
  },
  clientProgramInstalledMockModelCapturePlanBind(...args){
   assert.equal(this,moon);assert.deepEqual(args,[captured,compiledToken,definitionToken,occurrence,graph,selected]);
   calls.push('captured');return refusal===undefined?ok(capturePlan):{$tag:0,_0:refusal};
  },
  clientProgramInstalledMockModelManagedRunBegin(){assert.fail('A Plan binding cannot issue a legacy Run');},
  clientProgramCompileLocalInfers(){assert.fail('A Plan binding cannot compile again');},
 };
 for(const name of ['Template','Plan','Prepared','Authorization','Admission'])moon['clientProgramCompiledRun'+name]=()=>({});
 const control=runtimeCore(moon).publicationControl;
 const compiled=control.prepareCheckedClientCompiledRun(prepared,'infer',{
  resultDataPolicy:{kind:'data_policy',cid:'policy',wire:'{}'}},[graph],artifact);
 const definition=control.defineCheckedClientCompiledRun(compiled,{});
 assert.equal(control.prepareCheckedClientRequestModelSourceFreePlan(parent,input,sourceFree,request,compiled,definition,occurrence,graph,selected),freePlan);
 assert.equal(control.bindCheckedClientMockModelCapturePlan(captured,compiled,definition,occurrence,graph,selected),capturePlan);
 assert.deepEqual(calls,['source-free','captured']);
 for(const original of [{...compiled},Object.freeze({kind:'infer'}),{}]) {
  assert.throws(()=>control.prepareCheckedClientRequestModelSourceFreePlan(parent,input,sourceFree,request,original,definition,occurrence,graph,selected),/Foreign Client compiled Infer preparation/);
  assert.throws(()=>control.bindCheckedClientMockModelCapturePlan(captured,original,definition,occurrence,graph,selected),/Foreign Client compiled Infer preparation/);
 }
 assert.throws(()=>control.prepareCheckedClientRequestModelSourceFreePlan(parent,input,sourceFree,request,compiled,{...definition},occurrence,graph,selected),/Foreign publication contract/);
 assert.deepEqual(calls,['source-free','captured']);
 refusal={original:'typed Model Plan refusal'};
 assert.throws(()=>control.bindCheckedClientMockModelCapturePlan(captured,compiled,definition,occurrence,graph,selected),error=>error.cause===refusal);
 assert.deepEqual(calls,['source-free','captured','captured']);
});


test('actual Request Model prefix binding unwraps only registered compiler and Definition while retaining original QueryTime', async () => {
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const opaque = label => new Proxy({}, {get() {assert.fail(label + ' must remain opaque');}});
  const prepared = {}, artifact = {}, token = {}, definitionToken = {}, graph = {}, selected = {};
  const parent = opaque('Request parent'), input = opaque('Request input'), request = opaque('Request identity');
  const workspace = opaque('original workspace'), queryTime = opaque('original QueryTime');
  const limits = Object.freeze({maxRows: 1, maxWork: 2, maxEntries: 3, maxValueBytes: 4,
    maxValueNodes: 5, maxValueDepth: 6, maxFrames: 7});
  let calls = 0, primary;
  const ok = value => ({$tag: 1, _0: value});
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'fixture',
    clientProgramIssueTaskCompiledRun(p, value) {assert.equal(p, prepared); assert.equal(value, artifact); return ok(token);},
    clientProgramBindCompiledInferResultPolicy: value => ok(value),
    clientProgramIssueCompiledRunDefinition: value => {assert.equal(value, token); return ok(definitionToken);},
    strategyRunEvidenceName: () => 'evidence', strategyRunEvidenceIdentity: () => 'identity', strategyRunEvidenceJson: () => '{}',
    strategyPublicationContractName: () => 'run_definition', strategyPublicationContractIdentityField: () => 'run_id',
    strategyPublicationContractIdentity: () => 'definition', strategyPublicationContractJson: () => '{}',
    clientProgramPrepareRequestModelSerializationPlan(...args) {
      assert.equal(this, moon);
      assert.deepEqual(args, [parent, input, request, token, definitionToken, 1, 2, 3, 4, 5, 6, 7, workspace, queryTime]);
      calls++;
      if (primary) return {$tag: 0, _0: primary};
      return ok(selected);
    },
    clientProgramPrepareRequestSerializationPlan() {assert.fail('Model cannot select terminal Content constructor');},
  };
  for (const name of ['Template', 'Plan', 'Prepared', 'Authorization', 'Admission']) moon['clientProgramCompiledRun' + name] = () => ({});
  const control = runtimeCore(moon).publicationControl;
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    resultDataPolicy: {kind: 'data_policy', cid: 'policy', wire: '{}'}}, [graph], artifact);
  const definition = control.defineCheckedClientCompiledRun(compiled, {});
  const invoke = (c = compiled, d = definition) => control.prepareCheckedClientRequestModelSerializationPlan(
    parent, input, request, c, d, limits, workspace, queryTime);
  assert.equal(invoke(), selected);
  assert.throws(() => invoke({...compiled}), /Foreign Client compiled Infer preparation/);
  assert.throws(() => invoke(compiled, {...definition}), /Foreign publication contract/);
  assert.equal(calls, 1);
  primary = {original: 'prefix constructor'};
  assert.throws(invoke, cause => cause.cause === primary);
  assert.equal(calls, 2);
});

test('actual Request Node Model Plan binding forwards original layout and physical demand without replacing opaque bounds', async () => {
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const opaque = label => new Proxy({}, {get() {assert.fail(label + ' must remain opaque');}});
  const prepared = {}, artifact = {}, native = {}, definitionToken = {}, graph = opaque('Graph'), occurrence = {};
  const parent = opaque('parent'), input = opaque('input'), request = opaque('request'), module = opaque('module'), bounds = opaque('bounds');
  const layout = opaque('layout'), profile = opaque('response profile'), probability = opaque('probability'), selected = {};
  const original = Object.freeze({nodeInstallation: Object.freeze({layout, installation: profile,
    runtimeArtifactCid: 'runtime-original', layoutArtifactCid: 'layout-original', probability}),
    modelRetainedBytes: 123n, modelExecutionBytes: 456n,
    // Explicit stored fixture DATA for the existing constructor's complete suffix.
    // These values assert forwarding, not actual physical admission or backing.
    bootstrap: Object.freeze({maxReservations: 7, maxHoldings: 8, maxDelegations: 9,
      bootstrapRetainedBytes: 23n, bootstrapExecutionBytes: 31n})});
  let calls = 0, primary;
  const ok = value => ({$tag: 1, _0: value});
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'fixture',
    clientProgramIssueTaskCompiledRun(p, value) {assert.equal(p, prepared); assert.equal(value, artifact); return ok(native);},
    clientProgramBindCompiledInferResultPolicy: value => ok(value),
    clientProgramIssueCompiledRunDefinition: value => {assert.equal(value, native); return ok(definitionToken);},
    strategyRunEvidenceName: () => 'evidence', strategyRunEvidenceIdentity: () => 'identity', strategyRunEvidenceJson: () => '{}',
    strategyPublicationContractName: () => 'run_definition', strategyPublicationContractIdentityField: () => 'run_id',
    strategyPublicationContractIdentity: () => 'definition', strategyPublicationContractJson: () => '{}',
    clientProgramPrepareRequestNodeModelSourceFreePlan(...args) {
      assert.equal(this, moon);
      assert.deepEqual(args, [parent, input, module, request, native, definitionToken, occurrence, graph, bounds,
        layout, profile, 'runtime-original', 'layout-original', probability, 123n, 456n, 7, 8, 9, 23n, 31n]);
      calls++; return primary === undefined ? ok(selected) : {$tag: 0, _0: primary};
    },
    clientProgramPrepareRequestModelSourceFreePlan() {assert.fail('No physical Node fallback to generic Model Plan');},
  };
  for (const name of ['Template', 'Plan', 'Prepared', 'Authorization', 'Admission']) moon['clientProgramCompiledRun' + name] = () => ({});
  const control = runtimeCore(moon).publicationControl;
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    resultDataPolicy: {kind: 'data_policy', cid: 'policy', wire: '{}'}}, [graph], artifact);
  const definition = control.defineCheckedClientCompiledRun(compiled, {});
  const invoke = (c = compiled, d = definition) => control.prepareCheckedClientRequestNodeModelSourceFreePlan(
    parent, input, module, request, c, d, occurrence, graph, bounds, original);
  assert.equal(invoke(), selected);
  assert.throws(() => invoke({...compiled}), /Foreign Client compiled Infer preparation/);
  assert.throws(() => invoke(compiled, {...definition}), /Foreign publication contract/); assert.equal(calls, 1);
  primary = {original: 'typed layout refusal'}; assert.throws(invoke, cause => cause.cause === primary); assert.equal(calls, 2);
  delete moon.clientProgramPrepareRequestNodeModelSourceFreePlan;
  assert.throws(invoke, /Installed Node Model Plan unavailable/); assert.equal(calls, 2);
});
