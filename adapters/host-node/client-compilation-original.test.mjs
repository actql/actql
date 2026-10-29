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
 const prepared={},phase={},holder={},compilation={};
 const state={prepared,phase,holder,adopting:true,context:{runtime:{clientProgramClosedValuesCompilationOriginal(owner,p){assert.equal(owner,phase);assert.equal(p,prepared);return compilation;}}}};
 const run={producer:{preparation:state}};
 const get=method('./ordinary-source-managed.mjs','compilationOriginal',{runFor:p=>{assert.equal(p,prepared);return run;},fail:code=>{throw failure(code);}});
 assert.equal(get(prepared),compilation);
 state.holder=undefined;assert.throws(()=>get(prepared),{code:'ForeignInstalledSourceProducer'});state.holder=holder;
 state.context.runtime.clientProgramClosedValuesCompilationOriginal=()=>undefined;
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
  clientProgramIssueTaskCompiledRun(){throw failure('ForeignOwner');}};
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
  clientProgramIssueTaskCompiledRun(p,c){issues++;if(p!==prepared||c!==compilation)throw failure('ForeignTaskCompilation');return issued;}};
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
  assert.throws(()=>get({},kind,{},{},{}),/without its selected barrier/);
 }
 assert.equal(compiles,0);assert.equal(issues,0);
});
