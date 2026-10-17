import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {originalFieldCommandKeyFixture} from './fixtures/command-original-field-key.fixture.mjs';
import {moon} from './fixtures/command-original-key.fixture.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
const cid=d=>'sha256:'+d.repeat(64);
// Same original two local Results and two keyed members as the existing
// positive, with no public Named Result to publish. This keeps real Common
// inputs, key validation, proposals, evidence and ordinary capture, while the
// Store is an explicit sequencing double. No target/current/send is granted.
const outputLimits=Object.freeze({maxResultFields:10,maxResultMappingWork:1000,
  maxResultOrderWork:10000,maxResultWorkspaceEntries:100,maxRows:100,
  maxValueNodes:10000,maxValueTextBytes:100000,maxValueDepth:64,maxValueWork:100000,
  maxWireBytes:100000,maxWireNodes:10000,maxWireDepth:64,maxColumns:10,
  maxOrderWork:10000,maxLogicalWireBytes:100000,maxLogicalWireNodes:10003,
  maxLogicalWireDepth:66,maxSchemaFields:10,maxSchemaBytes:100000,
  maxSchemaNodes:10000,maxSchemaDepth:64,maxBatchBytes:4096});

for(const maxWork of [8,10000]) test(`ordinary capture uses finite Host grouping work ${maxWork}`,async()=>{
  const f=await originalFieldCommandKeyFixture({secondMember:true,published:false});
  let factory;
  const events={writers:[],descriptions:0};
  const control=runtimeCore(moon).publicationControl;
  const stop=new Error('ReachedOrdinaryCommandDescription');
  try {
    assert.equal(moon.clientProgramEffectInputCount(f.inputs),2);
    assert.equal(moon.clientProgramEffectLocalResultCount(f.inputs),2);
    assert.equal(f.execution.resultInventory.length,0,'this genuine Program declares no public Named Result');
    // Hand the original outputs back before the ordinary caller pins them.
    // Keeping the fixture's observation pins would test overlapping holdings.
    assert.equal(moon.clientProgramReleaseEffectInputs(f.inputs),true);
    const c=f.publicationContext(control),unexpected=()=>assert.fail('No provider grant or send');
    const store={storeAuthorityCid:cid('a'),createPreparedObjectWriter(){
      const chunks=[];events.writers.push(chunks);let bytes=0,pending=true;
      const release=async()=>{pending=false;};
      return {async append(chunk){chunks.push(chunk);bytes+=Buffer.byteLength(chunk);},
        async seal(cid){return {cid,bytes,prepared:{release,retry:release,status:()=>({pending})}};},
        async cancel(){pending=false;},status:()=>({reservationHeld:pending})};
    }};
    const driver={kinds:['command'],prepareRequest:unexpected,requestFacts:unexpected,
      writeOperation:unexpected,send:unexpected,project:unexpected,footprint:unexpected,
      recheckRequests:unexpected,recoveryEntry:unexpected,recoverRequests:unexpected,
      requestCid:unexpected,describe(){events.descriptions++;throw stop;}};
    factory=await createInstalledRowEffect({moon,commands:[{resource:'archive',
      commandRef:f.command.command_id,commandCid:f.command.contract_cid,body:JSON.stringify(f.command)}],
      environmentWire:f.environmentWire,connectorId:'storage',connectorRegistration:'fixture',
      connectorRevision:'fixture-1',connection:'fixture',site:{issueEffectGrant:unexpected,
        issueReadGrant:unexpected,close(){}},authorization:{authorize:unexpected},
      runtimeBundleCid:cid('7'),bindingCid:cid('8'),ledgerRoot:await mkdtemp(join(tmpdir(),'actql-command-grouping-')),
      driver,limits:{maxMembers:2,maxPinnedResults:2,maxWork}});
    let failure;
    try {await factory.prepareCaptured({moon,control,store,execution:f.execution,
      checkedHost:f.owned,prepared:f.prepared,
      identity:moon.clientProgramEffectRequestIdentity(f.prepared,cid('a'),'key-fixture',cid('b')),
      publicationPlan:{...c,effectInputRetention:c.retention,runDefinition:c.localEvidenceContext.runDefinition,
        results:[],outputLimits,contractLimits:{maxWireBytes:100000,maxNodes:10000,maxDepth:64}},
      previewContext:{},unit:f.unit});} catch(error){failure=error;}
    if(maxWork===8){
      assert.equal((failure?.primaryFailure??failure)?.message,'EffectSourceGroupingLimit');
      assert.equal(events.descriptions,0);
      assert.equal(events.writers.length,0,'exhaustion refuses before any Store writer');
    }else{
      assert.equal(failure?.primaryFailure??failure,stop,failure?.stack);
      assert.equal(events.descriptions,1,'actual ordinary caller reaches its next physical boundary');
      assert.equal(events.writers.length,3,'original producer plus two distinct keyed member exports');
      for(const chunks of events.writers)assert.deepEqual(JSON.parse(chunks.join('')),f.rows);
    }
    assert.equal(f.execution.cleanupPending(),false,'ordinary failure releases its own pins/phase borrowers');
  } finally {await factory?.close();await f.close();}
});
