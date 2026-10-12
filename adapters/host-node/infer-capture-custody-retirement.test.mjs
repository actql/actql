import test from 'node:test';
import assert from 'node:assert/strict';
const {openNodeInferCaptureCustody}=await import(process.env.ACTQL_CAPTURE_CUSTODY_RETIREMENT_MODULE ??
  new URL('./infer-capture-custody.mjs',import.meta.url).href);

// Actual Node custody/holding code with explicit Core, Model and Store port
// doubles. This does not prove actual Store ACK, heap funding or public INFER.
function fixture() {
  const capture={}, output={}, exporter={};
  const evidence={wire:'{"raw":"é\\r\\n"}'};
  const settlement={}, entry={ordinal:0,attemptCid:'original-attempt'};
  const bundleWire='{"capture":"original é\\r\\n"}';
  const stored=new Map();
  const counters={stop:0,cleanup:0,acquire:0,ack:0,commit:0};
  const flags={stopped:true,exportCleanup:true,modelCleanup:true};
  let cleanupCallback, beforeCommit;
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramInferCaptureCallCount:()=>1,
    strategyRunEvidenceJson:value=>value.wire,
    strategyRunEvidenceIdentity:()=> 'original-slot-cid',
    clientProgramStartInferCallSettlementExport:()=>ok(exporter),
    clientProgramStartInferCaptureExport:()=>ok(exporter),
    clientProgramAdvanceInferCaptureExport:()=>ok({_0:true,_1:bundleWire}),
    clientProgramInferCaptureExportIdentity:()=> 'bundle-cid',
    clientProgramCancelInferCaptureExport:()=>false,
    clientProgramCleanupInferCaptureExport:()=>ok(flags.exportCleanup),
    clientProgramReleaseInferCapture:value=>assert.equal(value,capture),
    clientProgramReleaseInferOutput:value=>assert.equal(value,output),
    clientProgramInferCaptureCall:()=>({wire:'{"slot":"original"}'}),
    clientProgramInferCaptureOutcome:()=> 'ok',
  };
  const operation={
    physicalStopped:()=>flags.stopped,
    async stop(){counters.stop++;},
    cleanup(){counters.cleanup++;return flags.modelCleanup;},
    cleanupProgress:()=>0,
    acquireOutput(){counters.acquire++;return output;},
    acquireCapture:()=>capture,
    settlementSlot:value=>{assert.equal(value,settlement);return 0;},
    attemptEvidence:()=>({}),
    issuedAttachmentAdmission:()=>undefined,
    issuedSlotCapture:()=>evidence,
    invocationEvidence:()=>evidence,
    acknowledgeSettlement(){counters.ack++;},
    installSettlementCleanup(value){cleanupCallback=value;},
    stoppedAttemptCount:()=>0,
  };
  moon.clientProgramInferAttemptLeaf=()=>evidence;
  const control={
    admitRunEvidence:(name,wire)=>({name,wire,identity:`cid-${name}`}),
    modelScopedPrivateHoldingCid:(_run,_store,_entry,name)=>name,
    modelPrivateHoldingCid:(_run,_store,name)=>name,
  };
  const store={
    confirmPrivateEvidence:async binding=>stored.get(binding.holdingCid),
    async preparePrivateEvidence(name,wire){
      return {physicalCid:`physical-${name}`,bytes:Buffer.byteLength(wire),
        prepared:{status:()=>({pending:false}),async release(){}}};
    },
    async commitPhysicalHolding(record){
      counters.commit++;await beforeCommit?.();stored.set(record.holding_cid,record);
    },
  };
  const owner=openNodeInferCaptureCustody({moon,control,operation,
    plan:{runDefinition:{}},store,storeAuthorityCid:'original-store',
    captureOnly:true,durableCalls:true});
  owner.configureModelJournal({observe:async()=>({state:'SavedSuccess'}),entry:()=>entry});
  return {owner,flags,counters,stored,bundleWire,
    async complete(){
      await owner.persistSettlement(settlement,entry);
      owner.retainCompleted();await owner.persist();
    },
    async settling(){await cleanupCallback(settlement);},
    deferCommit(callback){beforeCommit=callback;}};
}

test('capture retirement denies new owned views and preserves an escaped immutable original',async()=>{
  const f=fixture();await f.complete();
  const bundle=f.owner.evaluationBundle();
  const evidence=f.owner.modelEvidence();
  assert.ok(Object.isFrozen(bundle)&&Object.isFrozen(evidence));
  assert.equal(await f.owner.custody.cleanup(),true);
  const retiredCounts={...f.counters};
  assert.equal(f.owner.evaluationBundle(),undefined);
  assert.equal(f.owner.modelEvidence(),undefined);
  assert.throws(()=>f.owner.retainCompleted(),/InstalledInferCaptureUnavailable/);
  await assert.rejects(f.owner.persist(),/InstalledInferCaptureUnavailable/);
  assert.equal(bundle.wire,f.bundleWire);
  assert.equal(bundle.calls.length,1);
  assert.equal(evidence[0].wire,'{"raw":"é\\r\\n"}');
  await f.owner.custody.close();await f.owner.custody.close();
  assert.deepEqual(f.counters,retiredCounts,'retired access performs no new Model/Store work');
  assert.ok(f.stored.size>0,'retirement does not delete durable originals');
});

test('same pending Core cleanup retains original evidence until successful retry',async()=>{
  const f=fixture();await f.complete();f.flags.modelCleanup=false;
  const evidence=f.owner.modelEvidence();
  assert.equal(await f.owner.custody.cleanup(),false);
  assert.equal(f.owner.custody.cleanupPending(),true);
  assert.deepEqual(f.owner.modelEvidence(),evidence);
  const commits=f.counters.commit;f.flags.modelCleanup=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.commit,commits);
  assert.equal(f.owner.modelEvidence(),undefined);
});

test('unfinished physical stop cannot retire the capture view or its Store responsibility',async()=>{
  const f=fixture();await f.complete();f.flags.stopped=false;
  const bundle=f.owner.evaluationBundle();
  assert.equal(await f.owner.custody.cleanup(),false);
  assert.deepEqual(f.owner.evaluationBundle(),bundle);
  assert.equal(f.counters.cleanup,0);
  f.flags.stopped=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(bundle.wire,f.bundleWire);
});

test('same failed Store commit keeps the original cleanup retry and immutable evidence',async()=>{
  const f=fixture();let fail=true;
  f.deferCommit(()=>{if(fail)throw Error('FixtureStoreCommitPending');});
  await assert.rejects(f.settling(),/FixtureStoreCommitPending/);
  assert.equal(f.owner.custody.cleanupPending(),true);
  await assert.rejects(f.owner.custody.cleanup(),/FixtureStoreCommitPending/);
  assert.equal(f.counters.cleanup,0);
  fail=false;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.ack,1);
  assert.equal(f.owner.modelEvidence(),undefined);
});

test('concurrent cleanup shares one original flight through persistence and final retirement',async()=>{
  const f=fixture();let release,announced;
  const waiting=new Promise(resolve=>{release=resolve;});
  const entered=new Promise(resolve=>{announced=resolve;});
  // Stopped empty capture cleanup has no Store commit; create an original
  // failed settlement first so both cleanup observers reuse its pending hold.
  f.deferCommit(()=>{throw Error('FixtureOriginalPending');});
  await assert.rejects(f.settling(),/FixtureOriginalPending/);
  f.deferCommit(async()=>{announced();await waiting;});
  const first=f.owner.custody.cleanup();await entered;
  const second=f.owner.custody.cleanup();
  assert.equal(second,first);
  release();assert.equal(await first,true);assert.equal(await second,true);
  assert.equal(f.counters.cleanup,1);
  assert.equal(f.owner.custody.cleanup(),first,'successful cleanup flight remains stable');
  assert.equal(f.counters.ack,1);
});
