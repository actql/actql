import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareInstalledMockRegistrySelection, loadInstalledProjectMockAnswers}
  from '../local-node/installed-project-mock-answers.mjs';
import {createDeclaredFileInstallationInventory} from '../local-node/declared-file-installation.mjs';
import {admitInstalledProjectConfiguration, loadInstalledProjectConfiguration, installedProjectOriginalsForRuntime}
  from './installed-project-configuration.mjs';
import {createInstalledHostServices, retireInstalledSourceInitialization} from './installed-host-services.mjs';

// Actual JS nominal Project/inventory/Source material and constructor order.
// Core Resource/semantic ports below are explicit component doubles, not an
// actual compiled-Core byte reservation or ordinary packed acceptance.
const ok = value => ({$tag: 1, _0: value});
const limits = Object.freeze({contractDepth:64,contractNodes:4096,contractTextBytes:65536,
  maxBytes:65536,maxDepth:64,maxEntries:128,maxMembers:256,maxNodes:4096,
  maxTasks:128,maxWork:2097152,valueDepth:64,valueNodes:4096,valueTextBytes:65536});
async function fixture(t,{tasks=129,answers=0}={}) {
  const root=await mkdtemp(join(tmpdir(),'actql-mock-registry-original-'));
  t.after(()=>rm(root,{recursive:true,force:true}));
  await writeFile(join(root,'actql.config.json'),'{}');
  await writeFile(join(root,'model-tasks.json'),'{}');
  const configuration={}, registry={}, initial={}, input={}, unit={}, capacity={};
  const selected={}, events=[], refusal=new Error('OriginalSourceReservationRefused');
  let current=true, refuse=false, loseOnReserve=false, closes=0;
  const check=()=>{if(!current)throw Object.assign(new Error('OriginalCurrentLost'),{code:'OriginalCurrentLost'});};
  const unused=()=>assert.fail('No unused Task decode, answer read or Model invocation');
  const moon={
    clientProjectConfigurationAdmit:()=>ok(configuration),
    clientProjectConfigurationModelTasksFile:()=> 'model-tasks.json',
    clientProjectConfigurationStateDirectory:()=> '.actql',
    clientProjectModelRegistryAdmit:()=>ok(registry),
    clientProjectConnectionsCount:unused,clientProjectConnectionsName:unused,clientProjectConnectionsConnector:unused,
    clientProjectModelRegistryTaskCount(value){assert.equal(value,registry);events.push('count');return tasks;},
    clientProjectModelRegistryTaskName:unused,clientProjectModelRegistryTaskFile:unused,
    clientProgramReadPublicModelTask:unused,clientProgramPublicModelTaskName:unused,
    clientProgramReadMockAnswers:unused,clientProgramRetireMockAnswers:unused,
    clientProgramTakeHostInitializationSourceCapacity(value){assert.equal(value,initial);return ok({_0:input,_1:unit});},
    clientProgramContinueInstalledSourceMaterial(value,original){assert.equal(value,unit);assert.equal(original,input);return ok(capacity);},
    clientProgramInstalledSourceConstructionCapacity(...values){events.push('quote');return ok({values});},
    clientProgramComposeInstalledSourceConstructionCapacity(base,providers){return ok({base,providers});},
    clientProgramInstalledSourceRetainedConstructionCapacity(peak){return ok(peak);},
    clientProgramReserveInstalledSourceConstruction(value,original,quote){
      assert.equal(value,capacity);assert.equal(original,input);assert(quote);
      events.push('reserve');if(refuse)throw refusal;if(loseOnReserve)current=false;return ok();
    },
    clientProgramReconcileInstalledSourceConstruction:()=>ok(),
    clientProgramCompleteInstalledSourceMaterial:()=>ok(),clientProgramBorrowInstalledSourceMaterial:()=>ok(),
    clientProgramBorrowedInstalledSourceEnvironment:()=>ok(),clientProgramReturnInstalledSourceMaterial:()=>ok(),
    clientProgramRetireInstalledSourceMaterial(value,original){assert.equal(value,capacity);assert.equal(original,input);closes++;return ok(true);},
    clientProgramAbortUncontinuedSourceMaterial:()=>ok(),
    clientProgramBeginInstalledSourceIo:unused,clientProgramChargeInstalledSourceIo:unused,
    clientProgramMarkInstalledSourceIoTransferUncertain:unused,clientProgramFinishInstalledSourceIoAfterCleanup:unused,
    clientProgramRowSourceRestoreRelationDeclaration:unused,clientProgramRowSourceDeclarationJson:unused,
  };
  const project=await loadInstalledProjectConfiguration(moon,{directory:root});
  const original=installedProjectOriginalsForRuntime(project,moon);
  const services=createInstalledHostServices({root:join(root,'.actql'),principalId:'fixture',moon,
    initialPreparation:initial,assertCurrent:check});
  const inventory=createDeclaredFileInstallationInventory({moon,project,services,baseEnvironmentWire:'{}',
    runtimeUrl:new URL('file:///original/runtime.mjs'),assertCurrent:check});
  const profile={originalsForRuntime(actual){assert.equal(actual,moon);return{
    configuration,selection:selected,selected:'mock'};},
  mockLocatorsForRuntime:()=>({answerCount:answers}),mockAnswerForRuntime:unused};
  return {moon,project,original,services,inventory,events,refusal,profile,
    loseCurrent:()=>{current=false;},refuse:()=>{refuse=true;},loseOnReserve:()=>{loseOnReserve=true;},
    retire:()=>retireInstalledSourceInitialization(services),closes:()=>closes,
    select:()=>prepareInstalledMockRegistrySelection(moon,project,inventory),
    load:managed=>loadInstalledProjectMockAnswers(moon,project,profile,{limits,assertCurrent:check,
      deferAnswers:true,...(managed?{installationInventory:inventory}:{})})};
}

test('same original Source reservation precedes registry129 projection without unused Task allocation', async t => {
  const f=await fixture(t);
  const selected=f.select();assert.equal(selected.registry,f.original.modelRegistry);assert.equal(selected.count,129);
  assert(f.events.indexOf('reserve')<f.events.indexOf('count'));
  assert.equal(f.events.filter(value=>value==='count').length,1);
  const view=await f.load(true);view.retire(f.moon);
  assert.equal(f.retire(),true);assert.equal(f.closes(),1);
});

test('standalone explicit128 registry guard remains and no managed projection supplies it funds', async t => {
  const f=await fixture(t);
  await assert.rejects(f.load(false),{code:'InstalledMockAnswerCountLimit'});
  assert.deepEqual(f.events,['count']);assert.equal(f.retire(),true);
});

test('foreign copied inventory or equal-wire Project cannot borrow the original metadata holding', async t => {
  const f=await fixture(t), other=await fixture(t);
  assert.throws(()=>prepareInstalledMockRegistrySelection(f.moon,f.project,{...f.inventory}),{code:'ForeignDeclaredFileInstallation'});
  assert.throws(()=>prepareInstalledMockRegistrySelection(f.moon,f.project,other.inventory),{code:'ForeignDeclaredFileInstallation'});
  const copied=admitInstalledProjectConfiguration(f.moon,'{}','{}');
  assert.throws(()=>prepareInstalledMockRegistrySelection(f.moon,copied,f.inventory),{code:'ForeignDeclaredFileInstallation'});
  assert.deepEqual(f.events,[]);assert.equal(f.retire(),true);assert.equal(other.retire(),true);
});

test('current or numerical Source refusal precedes count and survives unchanged as primary', async t => {
  const stale=await fixture(t);stale.loseCurrent();
  assert.throws(stale.select,{code:'OriginalCurrentLost'});assert.deepEqual(stale.events,[]);
  assert.equal(stale.retire(),true);assert.equal(stale.closes(),1);
  const small=await fixture(t);small.refuse();
  assert.throws(small.select,error=>error===small.refusal);assert(!small.events.includes('count'));
  assert.equal(small.retire(),true);
  const changed=await fixture(t);changed.loseOnReserve();
  assert.throws(changed.select,{code:'OriginalCurrentLost'});assert(!changed.events.includes('count'));
  assert.equal(changed.retire(),true);assert.equal(changed.closes(),1);
});

test('managed total metadata does not lift selected answer128 policy or decode a next Task', async t => {
  const f=await fixture(t,{tasks:129,answers:129});
  await assert.rejects(f.load(true),{code:'InstalledMockAnswerCountLimit'});
  assert(f.events.includes('reserve'));assert(f.events.includes('count'));
  assert.equal(f.retire(),true);
});

test('retired same Source inventory cannot project a later registry count', async t => {
  const f=await fixture(t);assert.equal(f.retire(),true);const before=f.events.length;
  assert.throws(f.select);assert(!f.events.slice(before).includes('count'));
});
