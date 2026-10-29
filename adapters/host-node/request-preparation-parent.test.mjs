import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import resources from './ordinary-node-resource-runtime.cjs';

// Actual normal manager/adapter/Resource originals; Core phase/shape results
// are explicit ports. This does not certify a matching Common or body tariff.
const ok = value => ({$tag:1, _0:value});
const input = () => ({version:'actql/0.1',id:'parent',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{
  schema:{n:{type:'number',nullable:false}},rows:[{n:1}],
}}],results:{rows:{from:'v',fields:['n']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
const connection = Object.freeze({mode:'local',owner:'local',consentRefs:Object.freeze([]),runners:Object.freeze([])});
async function fixture({selectFailure, control=[1024n,0n]}={}) {
  const calls=[],policy={},parent={},phase={},work={};let admission;
  const stop = () => {
    assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0),0);
    assert.equal(admission.ports.status(2),0);
    return ok(undefined);
  };
  const moon={
    clientLocalResourcePolicyOriginal(){assert.equal(this,moon);return policy;},
    clientProgramRequestPreparationControl(actual){assert.equal(this,moon);assert.equal(actual,policy);calls.push('control');return control;},
    clientProgramPrepareLocalPreparationAdmission(original,receipt){
      assert.equal(this,moon);calls.push('admission');
      admission={original,receipt,ports:resources.prepareOriginalLocalPreparationPorts(original,receipt)};return ok(admission);
    },
    clientProgramBeginRequestPreparation(actual,receipt,selectedPolicy){
      assert.equal(this,moon);assert.equal(actual,admission);assert.equal(receipt,admission.receipt);assert.equal(selectedPolicy,policy);
      assert.equal(admission.ports.status(0),0);calls.push('parent');return ok(parent);
    },
    clientProgramSelectClosedValuesPreparation(actual,receipt){
      assert.equal(this,moon);assert.equal(actual,parent);assert.equal(receipt,admission.receipt);calls.push('select');
      if(selectFailure!==undefined) throw selectFailure;return ok(phase);
    },
    clientProgramBeginClosedValuesHeader(actual){assert.equal(actual,phase);calls.push('header');return ok(work);},
    clientProgramSpendPreparationPhaseWork(actual){assert.equal(actual,work);return ok(undefined);},
    clientProgramBeginClosedValuesScan(actual){assert.equal(actual,phase);return ok(work);},
    clientProgramFinishClosedValuesScan(){return ok(undefined);},
    clientProgramBeginClosedValuesTextCheck(){return ok(work);},
    clientProgramFinishClosedValuesTextCheck(){return ok(undefined);},
    clientProgramReserveClosedValuesSnapshot(actual){assert.equal(actual,phase);calls.push('snapshot-reserve');return ok(undefined);},
    clientProgramBindClosedValuesDocument(actual,document){assert.equal(actual,phase);calls.push('snapshot-bind');assert.equal(JSON.parse(document).id,'parent');return ok(undefined);},
    clientProgramAbortRequestPreparation(actual){assert.equal(this,moon);assert.equal(actual,parent);calls.push('abort-parent');return stop();},
    clientProgramAbortClosedValuesPreparationAfterCleanup(actual){assert.equal(this,moon);assert.equal(actual,phase);calls.push('abort-body');return stop();},
    clientProgramPrepareClosedValuesModuleBody(){assert.fail('No body compilation selected');},
    clientProgramCompleteClosedValuesBody(){},clientProgramAdoptClosedValuesPreparation(){},
  };
  const context=Object.freeze({runtime:moon,preparedEnvironment:{},retainedRelationOutput:false});
  const originals={};const view=await prepareOrdinarySourceManagedInstallation(originals,{
    validator(actual){assert.equal(actual,originals);},
    preparationContext(actual){assert.equal(actual,originals);return context;},
    preparationRequirements(){calls.push('requirements');return {planningWork:10000,attempts:10000,holdings:10000,transferBytes:100000n,retainedBytes:100000n,executionBytes:100000n};},
  },false);
  return {view,calls,get original(){return admission?.original;}};
}

test('normal request manager retains one parent before header and original snapshot reservation',async()=>{
  const f=await fixture();const program=input();
  const receipt=f.view.beforeSourceSnapshot('program',program,undefined,connection);
  assert.deepEqual(f.calls.slice(0,6),['control','requirements','admission','parent','select','header']);
  assert.equal(f.calls.filter(x=>x==='parent').length,1);assert.equal(f.calls.filter(x=>x==='snapshot-reserve').length,1);
  const body={kind:'program',input:JSON.parse(JSON.stringify(program)),parameters:null};
  f.view.bindSourceSnapshot(receipt,body);f.view.finishSourceProducer(receipt,'failed');
  assert.equal(f.calls.filter(x=>x==='abort-body').length,1);assert.equal(f.calls.includes('abort-parent'),false);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(await f.view.close(),{pending:false});
});

test('normal selection throw preserves primary and cleans the exact unselected parent once',async()=>{
  const failure=new Error('OriginalSelectionFailure');const f=await fixture({selectFailure:failure});
  assert.throws(()=>f.view.beforeSourceSnapshot('program',input(),undefined,connection),cause=>cause===failure);
  assert.deepEqual(f.calls,['control','requirements','admission','parent','select','abort-parent']);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(await f.view.close(),{pending:false});
});

test('invalid bootstrap quote refuses before producer slots or original input callbacks',async()=>{
  const f=await fixture({control:[0n,0n]});let getters=0;
  const program={get stages(){getters++;throw new Error('NoInputVisit');}};
  for(let index=0;index<33;index++)assert.throws(()=>f.view.beforeSourceSnapshot('program',program,undefined,connection),{code:'NodeLocalPreparationAdmissionUnavailable'});
  assert.equal(getters,0);assert.equal(f.original,undefined);assert.equal(f.calls.every(x=>x==='control'),true);
  assert.deepEqual(await f.view.close(),{pending:false});
});


test('native snapshot fence authenticates the actual ordinary producer receipt and retained Node original', async () => {
  const f = await fixture(), program = input();
  const receipt = f.view.beforeSourceSnapshot('program', program, undefined, connection);
  assert.throws(() => f.view.assertSourceSnapshotCurrent({}), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(f.view.assertSourceSnapshotCurrent(receipt), undefined);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
  f.view.finishSourceProducer(receipt, 'failed');
  assert.throws(() => f.view.assertSourceSnapshotCurrent(receipt), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.deepEqual(await f.view.close(), {pending: false});
});
