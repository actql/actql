import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp,writeFile,rm,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {runtimeField,runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

// Execute the actual physical answer-preparation/retirement methods. Common
// ports are explicit identity doubles here; the real Common controls and
// original Model startup are separately executed by Moon tests.
const source=readFileSync(new URL('../local-node/installed-project-mock-answers.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const load=ast.body.map(node=>node.declaration??node).find(node=>node.type==='FunctionDeclaration'&&node.id.name==='loadInstalledProjectMockAnswers');
const start=load.body.body.findIndex(node=>node.type==='VariableDeclaration'&&node.declarations.some(item=>item.id.name==='retired'));
assert(start>=0);
const tail=load.body.body.slice(start).map(node=>source.slice(node.start,node.end)).join('\n');
const install=compileFunction(`let retained=entries;
  let original,selection,project,profile,profilePorts,assertCurrent;
  const deferAnswers=true,bounds={maxBytes:1024},answerBounds=[1024,32,8,16,32,8,1024,8,1000];
  const taskBounds=[1024,32,8,16,32,8,1024,1000];
  const format=()=> 'yaml';
  const call=(name,...args)=>ports[name](...args);
  const checked=value=>value;
  const fail=code=>{throw Object.assign(new Error(code),{code});};
  ${tail}`,['moon','entries','check','runtimeField','ports','openFile','readBoundedConfigurationUtf8']);

async function fixture(t,{missing=false,onOpen,onClose}={}){
  const directory=await mkdtemp(join(tmpdir(),'actql-deferred-mock-input-'));
  const answerPath=join(directory,'answers.yaml'),wire='task: original\nanswers: {default: false}\n';
  if(!missing)await writeFile(answerPath,wire);
  const task={},normalized={},profile={},installation={},provider={},answers={};
  const input=Object.seal({task,name:'original',answerPath,answers:undefined,answerWire:undefined,answerFailure:undefined});
  const counters={opens:0,binds:0,prepares:0,retiredInstallations:0,retiredAnswers:0};
  const handles=new Set();let current=true,bound,view;
  const moon={
    clientProgramNormalizeMockTask(actual,selected){assert.strictEqual(actual,task);assert.strictEqual(selected,profile);return normalized;},
    clientProgramNormalizedPublicModelTaskMaterials(){return runtimeTupleFromFields(['task','task-cid','prompt','prompt-cid']);},
    clientProgramMockExecutionMaterials(){return runtimeTupleFromFields(['execution','execution-cid','retry','retry-cid','backoff','backoff-cid']);},
    clientProgramPrepareOriginalMock(selected,actual,value){counters.prepares++;assert.strictEqual(selected,profile);assert.strictEqual(actual,task);assert.strictEqual(value,normalized);return installation;},
    clientProgramBindOriginalMockAnswers(actual,value){counters.binds++;assert.equal(handles.size,0);assert.strictEqual(actual,installation);assert.strictEqual(value,answers);},
    clientProgramOriginalMockDeclaration(actual){assert.strictEqual(actual,installation);return normalized;},
    clientProgramOriginalMockProvider(actual){assert.strictEqual(actual,installation);return provider;},
    clientProgramRetireOriginalMock(actual){assert.strictEqual(actual,installation);counters.retiredInstallations++;return true;},
    clientProgramProjectPublicModelTaskEnvironment(){return runtimeTupleFromFields(['environment','environment-cid',1]);},
  };
  const ports={readAnswers(actual,text,format){assert.strictEqual(actual,task);assert.equal(text,wire);assert.equal(format,'yaml');return answers;},
    retire(value,actual){assert.strictEqual(value,answers);assert.strictEqual(actual,task);counters.retiredAnswers++;}};
  const check=()=>{if(!current)throw Object.assign(new Error('OriginalCurrentRefused'),{code:'OriginalCurrentRefused'});};
  const openFile=async(...args)=>{
    counters.opens++;onOpen?.({view,bound});const original=await open(...args);handles.add(original);
    return {read:original.read.bind(original),close:async()=>{await onClose?.();await original.close();handles.delete(original);}};
  };
  view=install(moon,Object.freeze([input]),check,runtimeField,ports,openFile,readBoundedConfigurationUtf8);
  bound=view.bindModelsForRuntime(moon,profile,()=> 'original-clock');
  let retired=false;
  const retire=()=>{view.retire(moon);retired=true;};
  t.after(async()=>{if(!retired)retire();assert.equal(handles.size,0);await rm(directory,{recursive:true});});
  return {view,bound,moon,installation,normalized,input,counters,handles,retire,loseCurrent:()=>{current=false;}};
}

test('deferred Mock declaration opens no answers and real missing input refuses only live preparation',async t=>{
  const f=await fixture(t,{missing:true});
  assert.equal(f.counters.prepares,1);assert.equal(f.counters.opens,0);
  assert.equal(f.bound.originalsForRuntime(f.moon).length,1);
  await assert.rejects(f.bound.prepareAnswersForRuntime(f.moon,{}),{code:'ForeignInstalledMockModelOriginal'});
  assert.equal(f.counters.opens,0);
  await assert.rejects(f.bound.prepareAnswersForRuntime(f.moon,f.installation),{code:'ENOENT'});
  assert.equal(f.counters.binds,0);assert.equal(f.handles.size,0);
  assert.equal(f.input.answers,undefined);
  assert.equal(f.bound.originalsForRuntime(f.moon).length,1,'A failed live input does not retire stored-outcome metadata');
  await assert.rejects(f.bound.prepareAnswersForRuntime(f.moon,f.installation),{code:'ENOENT'});
  assert.equal(f.counters.opens,1,'The failed original input is not silently retried');
});

test('physical answer closes before same-owner bind and captured Common methods survive replacement',async t=>{
  let f;
  f=await fixture(t,{onClose:()=>{f.moon.clientProgramBindOriginalMockAnswers=()=>{throw new Error('replacement');};}});
  assert.equal(f.counters.opens,0);
  await f.bound.prepareAnswersForRuntime(f.moon,f.installation);
  assert.equal(f.counters.opens,1);assert.equal(f.handles.size,0);assert.equal(f.counters.binds,1);
  await f.bound.prepareAnswersForRuntime(f.moon,f.installation);
  assert.equal(f.counters.opens,1);assert.equal(f.counters.binds,1);
  f.retire();assert.equal(f.counters.retiredInstallations,1);assert.equal(f.counters.retiredAnswers,1);
});

test('pending original read prevents retirement and same-task preparation does not duplicate IO',async t=>{
  const gate=Promise.withResolvers();
  const opened=Promise.withResolvers();
  const f=await fixture(t,{onOpen:({view})=>{assert.throws(()=>view.retire(f.moon),{code:'InstalledMockModelsCleanupPending'});},
    onClose:async()=>{opened.resolve();await gate.promise;}});
  const first=f.bound.prepareAnswersForRuntime(f.moon,f.installation);
  const second=f.bound.prepareAnswersForRuntime(f.moon,f.installation);
  await opened.promise;assert.equal(f.handles.size,1);
  assert.throws(()=>f.retire(),{code:'InstalledMockModelsCleanupPending'});
  gate.resolve();await Promise.all([first,second]);
  assert.equal(f.counters.opens,1);assert.equal(f.counters.binds,1);assert.equal(f.handles.size,0);
});

test('current revoked during actual file close refuses binding and retains only cleanup',async t=>{
  let f;f=await fixture(t,{onClose:()=>f.loseCurrent()});
  await assert.rejects(f.bound.prepareAnswersForRuntime(f.moon,f.installation),{code:'OriginalCurrentRefused'});
  assert.equal(f.counters.binds,0);assert.equal(f.handles.size,0);assert.equal(f.input.answers,undefined);
});
