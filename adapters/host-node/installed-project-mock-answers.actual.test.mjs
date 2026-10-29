import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,rm,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField,runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {loadInstalledProjectMockAnswers} from '../local-node/installed-project-mock-answers.mjs';

assert.ok(process.env.ACTQL_TEST_MOCK_ANSWER_RUNTIME,'Matching original mock-answer Common runtime required');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_MOCK_ANSWER_RUNTIME));
const limits=Object.freeze({maxTasks:4,maxBytes:10000,maxNodes:1000,maxDepth:32,maxMembers:100,
  contractNodes:100,contractDepth:16,contractTextBytes:1000,maxWork:100000,
  valueNodes:100,valueDepth:16,valueTextBytes:1000,maxEntries:10});
const declaration=name=>`task: ${name}\ninput: {notes: string}\noutput: {enabled: boolean}\ninstructions: original\n`;
const answer='task: model-task:mock.v1\nanswers:\n  default: {enabled: false}\n  by_key:\n    "001": {enabled: true}\n';

async function fixture(t,{answerWire=answer,taskName='model-task:mock.v1',answers=true,profile='mock'}={}){
  const directory=await mkdtemp(join(tmpdir(),'actql-mock-answer-originals-'));
  const views=[],pending=new Set();let current=true,reads=0;
  await mkdir(join(directory,'registry','tasks'),{recursive:true});
  await writeFile(join(directory,'actql.config.json'),JSON.stringify({version:'actql-config/0.1',
    model_tasks:'./registry/models.json',profile,mock:{answers:answers?{'model-task:mock.v1':'./answers.yaml'}:{}}}));
  await writeFile(join(directory,'registry','models.json'),JSON.stringify({version:'actql-model-tasks/0.1',
    tasks:{'model-task:mock.v1':'./tasks/task.yaml'},providers:{}}));
  await writeFile(join(directory,'registry','tasks','task.yaml'),declaration(taskName));
  await writeFile(join(directory,'answers.yaml'),answerWire);
  const project=await loadInstalledProjectConfiguration(moon,{directory});
  const selected=selectInstalledProjectProfile(moon,project,undefined,65536);
  t.after(async()=>{
    for(const view of views)view.retire(moon);
    selected.retire(moon);
    assert.equal(pending.size,0,'A cleanup refusal keeps its original FD/root, not a false teardown ACK');
    await rm(directory,{recursive:true});
  });
  const assertCurrent=()=>{if(!current)throw Object.assign(new Error('OriginalMockInstallationLost'),{code:'OriginalMockInstallationLost'});};
  const openFile=async(...args)=>{
    reads++;const original=await open(...args);pending.add(original);
    return {read:original.read.bind(original),close:async()=>{await original.close();pending.delete(original);}};
  };
  const load=async options=>{
    const view=await loadInstalledProjectMockAnswers(moon,project,selected,{limits,assertCurrent,openFile,...options});
    views.push(view);return view;
  };
  return {directory,project,selected,load,assertCurrent,openFile,pending,
    loseCurrent:()=>{current=false;},reads:()=>reads};
}

test('actual original project loads exact nested Task and mock answer without Provider selection',async t=>{
  const f=await fixture(t),view=await f.load(),entries=view.originalsForRuntime(moon);
  assert.equal(entries.length,1);assert.ok(Object.isFrozen(entries)&&Object.isFrozen(entries[0]));
  const original=entries[0];assert.equal(original.name,'model-task:mock.v1');
  assert.equal(original.taskPath,join(f.directory,'registry','tasks','task.yaml'));
  assert.equal(original.answerPath,join(f.directory,'answers.yaml'));
  assert.equal(original.taskWire,declaration('model-task:mock.v1'));assert.equal(original.answerWire,answer);
  assert.equal(checked(moon.clientProgramMockAnswerCount(original.answers,original.task)),1);
  assert.ok(runtimeUnboxedReferenceOption(checked(moon.clientProgramMockAnswerDefault(original.answers,original.task))));
  const keyed=runtimeUnboxedReferenceOption(checked(moon.clientProgramMockAnswerAt(original.answers,original.task,0)));
  assert.equal(runtimeField(keyed,0),'001');assert.ok(runtimeField(keyed,1));
  assert.equal(f.reads(),2);assert.equal(f.pending.size,0);
  await writeFile(original.answerPath,'task: replacement\nanswers: {}');
  assert.strictEqual(view.originalsForRuntime(moon),entries);
  assert.equal(entries[0].answerWire,answer,'Retained originals are never rediscovered from current configuration');
  assert.throws(()=>view.originalsForRuntime({...moon}),{code:'ForeignInstalledMockAnswerOriginal'});
  assert.throws(()=>({...view}).retire(moon),{code:'ForeignInstalledMockAnswerOriginal'});
  view.retire(moon);view.retire(moon);
  assert.throws(()=>view.originalsForRuntime(moon),{code:'InstalledMockAnswersRetired'});
  assert.throws(()=>checked(moon.clientProgramMockAnswerCount(original.answers,original.task)),{code:'MoonBitHostFailure'});
});

test('actual mock loader rejects copied project and profile and foreign runtime before answer acquisition',async t=>{
  const f=await fixture(t);
  for(const [runtime,project,profile] of [[moon,{...f.project},f.selected],[{...moon},f.project,f.selected],[moon,f.project,{...f.selected}]]){
    await assert.rejects(loadInstalledProjectMockAnswers(runtime,project,profile,
      {limits,assertCurrent:f.assertCurrent,openFile:f.openFile}));
  }
  assert.equal(f.reads(),0);
});

test('actual nonmock profile refuses before any task or answer read',async t=>{
  const f=await fixture(t,{profile:'production'});
  await assert.rejects(f.load(),{code:'ForeignInstalledMockAnswerOriginal'});
  assert.equal(f.reads(),0);
});

test('actual missing answer locators remain empty rather than discovering files or defaults',async t=>{
  const f=await fixture(t,{answers:false}),view=await f.load();
  assert.deepEqual(view.originalsForRuntime(moon),[]);assert.equal(f.reads(),0);
});

test('actual installation currentness is rechecked after the same original file closes',async t=>{
  const f=await fixture(t);
  await assert.rejects(f.load({openFile:async(...args)=>{
    const handle=await f.openFile(...args);
    return {read:handle.read,close:async()=>{await handle.close();f.loseCurrent();}};
  }}),{code:'OriginalMockInstallationLost'});
  assert.equal(f.reads(),1);assert.equal(f.pending.size,0);
});

for(const [name,options,code] of[
  ['wrong Task occurrence',{taskName:'model-task:foreign.v1'},'InstalledMockAnswerTaskMismatch'],
  ['wrong answer Task',{answerWire:answer.replace('mock.v1','foreign.v1')},'MoonBitHostFailure'],
  ['unused ill-typed answer',{answerWire:answer+'    unused: {enabled: 1}\n'},'MoonBitHostFailure'],
])test(`actual mock loader refuses ${name} without accepting a replacement original`,async t=>{
  const f=await fixture(t,options);await assert.rejects(f.load(),{code});assert.equal(f.pending.size,0);
});

test('actual original answer FD close refusal survives loader failure and retries only the same close',async t=>{
  const f=await fixture(t);let closes=0,held;
  await assert.rejects(f.load({openFile:async(...args)=>{
    const original=await f.openFile(...args);
    if(args[0]!==join(f.directory,'answers.yaml'))return original;
    return {read:original.read,close:async()=>{
      closes++;if(closes===1)throw Object.assign(new Error('OriginalAnswerClosePending'),{code:'OriginalAnswerClosePending'});
      await original.close();
    }};
  }}),error=>{held=error;return error.code==='OriginalAnswerClosePending'&&error.cleanupPending===true;});
  assert.equal(f.pending.size,1);assert.equal(f.reads(),2);assert.equal(closes,1);
  assert.equal((await held.cleanupHandle.retry()).pending,false);
  assert.equal(f.pending.size,0);assert.equal(f.reads(),2);assert.equal(closes,2);
});
