import test from 'node:test';
import assert from 'node:assert/strict';
const {openNodeInferCaptureCustody}=await import(process.env.ACTQL_CAPTURE_CUSTODY_RETIREMENT_MODULE ??
  new URL('./infer-capture-custody.mjs',import.meta.url).href);

// Actual Node custody/holding code with explicit Core, Model and Store port
// doubles. This does not prove actual Store ACK, heap funding or public INFER.
function fixture({stoppedRaw = false, storeWireLimit = 12192, captureOnly = true,
  rejectInvocationReadmit = false, omitEntryAttempt = false, publicationFailure,
  publicationValue} = {}) {
  const capture={}, output={}, exporter={}, issuance={};
  const evidence={wire:'{"raw":"é\\r\\n"}'};
  const invocationView=Object.freeze({name:'model_invocation_evidence',
    identity:'cid-model_invocation_evidence',wire:evidence.wire});
  const settlement={}, entry=omitEntryAttempt ? {ordinal:0} : {ordinal:0,attemptCid:'original-attempt'};
  const bundleWire='{"capture":"original é\\r\\n"}';
  const stored=new Map();
  const counters={stop:0,cleanup:0,acquire:0,ack:0,commit:0,usage:0,proof:0,limitReads:0,
    publication:0,issuerStart:0,issuerCleanup:0,exports:[]};
  const flags={stopped:true,exportCleanup:true,modelCleanup:true,
    usageRetired:false,usageRefusal:false,journalState:'SavedSuccess',ackFailure:undefined};
  let cleanupCallback, beforeCommit;
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramInferCaptureCallCount:()=>1,
    clientProgramBindInferSlotCapture:()=>ok(undefined),
    strategyRunEvidenceJson:value=>value.wire,
    strategyRunEvidenceIdentity:()=> 'original-slot-cid',
    clientProgramStartInferCallSettlementExport:(original,maxBytes,maxWork)=>{
      assert.strictEqual(original,settlement);
      counters.exports=counters.exports.concat([['settlement',maxBytes,maxWork]]);
      return maxBytes<Buffer.byteLength(bundleWire)?{$tag:0,_0:'FixtureCaptureLimit'}:ok(exporter);
    },
    clientProgramStartInferCaptureExport:(original,maxBytes,maxWork)=>{
      assert.strictEqual(original,capture);
      counters.exports=counters.exports.concat([['whole',maxBytes,maxWork]]);
      return maxBytes<Buffer.byteLength(bundleWire)?{$tag:0,_0:'FixtureCaptureLimit'}:ok(exporter);
    },
    clientProgramAdvanceInferCaptureExport:()=>ok({_0:true,_1:bundleWire}),
    clientProgramInferCaptureExportIdentity:()=> 'bundle-cid',
    clientProgramCancelInferCaptureExport:()=>false,
    clientProgramCleanupInferCaptureExport:()=>ok(flags.exportCleanup),
    clientProgramReleaseInferCapture:value=>assert.equal(value,capture),
    clientProgramReleaseInferOutput:value=>assert.equal(value,output),
    clientProgramInferCaptureCall:()=>({wire:'{"slot":"original"}'}),
    clientProgramInferCaptureOutcome:()=> 'ok',
    clientProgramAdvanceInferObservationIssuance:original=>{
      assert.strictEqual(original,issuance);return ok({_0:true});
    },
    clientProgramCancelInferObservationIssuance:original=>{
      assert.strictEqual(original,issuance);return false;
    },
    clientProgramCleanupInferObservationIssuance:original=>{
      assert.strictEqual(original,issuance);counters.issuerCleanup++;return ok(true);
    },
    clientProgramReleaseInferInvocationBinding:original=>{
      assert.strictEqual(original,publicationValue.binding);
    },
  };
  const operation={
    physicalStopped:()=>flags.stopped,
    async stop(){counters.stop++;},
    cleanup(){counters.cleanup++;return flags.modelCleanup;},
    cleanupProgress:()=>0,
    acquireOutput(){counters.acquire++;return output;},
    acquireCapture:()=>capture,
    startObservation(){counters.issuerStart++;return issuance;},
    settlementSlot:value=>{assert.equal(value,settlement);return 0;},
    attemptEvidence:()=>{
      counters.proof++;
      if(stoppedRaw)assert.equal(flags.usageRetired,true,'original reader must retire before proof');
      return {};
    },
    advanceStoppedAttemptUsage(slot,quantum){
      assert.equal(slot,0);assert.equal(quantum,1);
      assert.equal(counters.cleanup,0,'parent cleanup cannot erase unread observations');
      counters.usage++;
      if(flags.usageRefusal)throw Error('FixtureOriginalRawCurrentLost');
      flags.usageRetired=counters.usage>=3;
      return Object.freeze({complete:flags.usageRetired,work:BigInt(counters.usage),
        issue:flags.usageRetired ? Object.freeze({original:'codec-stop'}) : undefined});
    },
    issuedAttachmentAdmission:()=>undefined,
    issuedSlotCapture:()=>evidence,
    invocationEvidence:()=>evidence,
    invocationEvidenceView:()=>invocationView,
    acknowledgeSettlement(){
      if(flags.ackFailure!==undefined)throw flags.ackFailure;
      counters.ack++;
    },
    installSettlementCleanup(value){cleanupCallback=value;},
    stoppedAttemptCount:()=>stoppedRaw ? 1 : 0,
  };
  moon.clientProgramInferAttemptLeaf=()=>evidence;
  const control={
    admitRunEvidence(name,wire){
      if(rejectInvocationReadmit&&name==='model_invocation_evidence') {
        assert.fail('Core-issued invocation evidence must not be parsed and issued again');
      }
      return {name,wire,identity:`cid-${name}`};
    },
    modelScopedPrivateHoldingCid:(_run,_store,_entry,name)=>name,
    modelPrivateHoldingCid:(_run,_store,name)=>name,
  };
  const store={
    privateEvidenceWireLimit(){
      assert.strictEqual(this,store);
      counters.limitReads++;
      return storeWireLimit;
    },
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
    captureOnly,durableCalls:true,
    publicationFor:captureOnly?undefined:()=>{
      counters.publication++;
      if(publicationFailure!==undefined)throw publicationFailure;
      if(publicationValue!==undefined)return publicationValue;
      assert.fail('No publication before the selected exporter');
    }});
  owner.configureModelJournal({observe:async()=>({state:flags.journalState}),entry:()=>entry});
  return {owner,operation,flags,counters,stored,bundleWire,store,moon,invocationView,
    async complete(){
      await owner.persistSettlement(settlement,entry);
      owner.retainCompleted();await owner.persist();
    },
    async settling(){await cleanupCallback(settlement);},
    deferCommit(callback){beforeCommit=callback;}};
}

test('failed publication releases same persisted capture on first close without reissuing publication',async()=>{
  const primary=Object.assign(new Error('FixturePublicationBindingRejected'),
    {code:'FixturePublicationBindingRejected'});
  const f=fixture({captureOnly:false,publicationFailure:primary});
  await assert.rejects(f.complete(),error=>error===primary);
  assert.ok(f.stored.has('model_capture_bundle'));
  const commits=f.counters.commit;
  assert.equal(f.counters.publication,1);assert.equal(f.counters.issuerStart,1);
  await f.owner.custody.close();
  assert.equal(f.owner.custody.cleanupPending(),false);
  assert.equal(f.counters.publication,1,'cleanup cannot reconstruct the rejected publication');
  assert.equal(f.counters.commit,commits,'the durable capture is not rewritten');
  assert.equal(f.counters.issuerStart,1);assert.equal(f.counters.issuerCleanup,1);
  assert.equal(f.counters.stop,1);assert.equal(f.counters.cleanup,1);
  assert.ok(f.stored.has('model_capture_bundle'),'original durable evidence stays retained');
});

test('failed publication cannot turn unconfirmed Model stop into first-close success',async()=>{
  const primary=new Error('FixturePublicationRejectedBeforeStop');
  const f=fixture({captureOnly:false,publicationFailure:primary});
  await assert.rejects(f.complete(),error=>error===primary);
  f.flags.stopped=false;
  await assert.rejects(f.owner.custody.close(),{code:'ClientDispatchCleanupPending'});
  assert.equal(f.owner.custody.cleanupPending(),true);
  assert.equal(f.counters.publication,1);assert.equal(f.counters.issuerCleanup,0);
  assert.equal(f.counters.cleanup,0);assert.equal(f.counters.stop,1);
  assert.ok(f.stored.has('model_capture_bundle'));
});

test('pending publication write retains its same holding and issuer until actual Store confirmation',async()=>{
  const publicationValue={binding:{},observation:{wire:'{}',identity:'observation-cid'},
    invocation:{wire:'{}',identity:'invocation-cid'}};
  const f=fixture({captureOnly:false,publicationValue});
  const unknown=Object.assign(new Error('FixturePublicationCommitUnknown'),
    {code:'FixturePublicationCommitUnknown'});
  f.deferCommit(()=>{if(f.counters.publication>0)throw unknown;});
  await assert.rejects(f.complete(),error=>error===unknown);
  const originalHolding=unknown.cleanupHandle;
  assert.ok(originalHolding);
  await assert.rejects(f.owner.custody.close(),error=>error===unknown);
  assert.strictEqual(unknown.cleanupHandle,originalHolding);
  assert.equal(f.owner.custody.cleanupPending(),true);
  assert.equal(f.counters.publication,1);assert.equal(f.counters.issuerCleanup,0);
  assert.equal(f.counters.cleanup,0);
  // A changed Store response settles this original duty, not another close,
  // provider execution, publication construction or reconstructed holding.
  f.deferCommit(undefined);
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(originalHolding.status().committed,true);
  assert.equal(f.counters.publication,1);assert.equal(f.counters.issuerCleanup,1);
  assert.equal(f.counters.cleanup,1);assert.equal(f.counters.stop,1);
  assert.ok(f.stored.has('observation_set'));
  assert.equal(f.stored.has('run_invocation'),false,'cleanup does not fabricate remaining publication');
});

// White-box observation, not a production getter or an actually escaped client
// handle. The temporary setter preserves normal own assignment semantics and
// is restored before another test. No product source overlay or GC claim.
async function withSettlementRecord(observe) {
  assert.equal(Object.getOwnPropertyDescriptor(Object.prototype,'exporter'),undefined);
  let record;
  Object.defineProperty(Object.prototype,'exporter',{configurable:true,
    get(){return undefined;},
    set(value){
      Object.defineProperty(this,'exporter',{value,writable:true,enumerable:true,configurable:true});
      if(Object.hasOwn(this,'settlement')&&Object.hasOwn(this,'entry')&&Object.hasOwn(this,'wire')){
        assert.equal(record,undefined,'Retry must reuse the original record/exporter');
        record=this;
      }
    }});
  try{return await observe(()=>record);}
  finally{delete Object.prototype.exporter;}
}

test('settlement record drops only wire/exporter aliases after original cleanup and ACK',async()=>{
  const f=fixture();
  await withSettlementRecord(async read=>{
    const ack=f.operation.acknowledgeSettlement;
    f.operation.acknowledgeSettlement=()=>{
      assert.equal(read().wire,f.bundleWire);
      assert.ok(read().exporter,'The exporter remains borrowed until ACK succeeds');
      ack();
    };
    await f.settling();
    assert.equal(f.counters.ack,1);
    assert.equal(read().wire,'');assert.equal(read().exporter,undefined);
    assert.ok(f.stored.has('model_capture_bundle'),'Durable originals are not deleted');
    f.owner.retainCompleted();await f.owner.persist();
    assert.equal(f.owner.evaluationBundle().wire,f.bundleWire,'Terminal export is a separate wire');
    assert.equal(await f.owner.custody.cleanup(),true);
  });
});

test('settlement record keeps original aliases during incomplete exporter cleanup',async()=>{
  const f=fixture();f.flags.exportCleanup=false;
  await withSettlementRecord(async read=>{
    await assert.rejects(f.settling(),{code:'ClientDispatchCleanupPending'});
    const original=read(),exporter=original.exporter;
    assert.equal(original.wire,f.bundleWire);assert.ok(exporter);
    assert.equal(f.counters.ack,0);assert.equal(f.owner.custody.cleanupPending(),true);
    f.flags.exportCleanup=true;await f.settling();
    assert.strictEqual(read(),original);assert.equal(f.counters.exports.length,1);
    assert.equal(original.wire,'');assert.equal(original.exporter,undefined);
    assert.equal(f.counters.ack,1);assert.equal(await f.owner.custody.cleanup(),true);
  });
});

test('settlement record preserves Unknown journal and ACK rejection until same-duty retry',async()=>{
  for(const mode of ['journal','ack']){
    const f=fixture(),failure=Object.freeze(new Error('OriginalAckRefused'));
    if(mode==='journal')f.flags.journalState='EnteredUnknown';else f.flags.ackFailure=failure;
    await withSettlementRecord(async read=>{
      await assert.rejects(f.settling(),error=>mode==='ack'?error===failure:
        error.message==='InferSettlementNotDurable');
      const original=read(),exporter=original.exporter;
      assert.equal(original.wire,f.bundleWire);assert.ok(exporter);
      assert.equal(f.counters.ack,0);assert.equal(f.counters.cleanup,0);
      f.flags.journalState='SavedSuccess';f.flags.ackFailure=undefined;
      await f.settling();
      assert.strictEqual(read(),original);assert.equal(f.counters.exports.length,1);
      assert.equal(original.wire,'');assert.equal(original.exporter,undefined);
      assert.equal(f.counters.ack,1);assert.equal(await f.owner.custody.cleanup(),true);
    });
  }
});

test('acknowledged settlement cleanup never reopens its stopped raw reader',async()=>{
  const f=fixture();
  f.operation.stoppedAttemptCount=()=>1;
  f.operation.advanceStoppedAttemptUsage=()=>assert.fail('Already acknowledged original attempt');
  await f.settling();
  assert.equal(f.counters.ack,1);
  f.flags.modelCleanup=false;
  assert.equal(await f.owner.custody.cleanup(),false);
  assert.equal(f.owner.custody.cleanupPending(),true);
  f.flags.modelCleanup=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.usage,0);
  assert.equal(f.counters.ack,1,'Cleanup cannot acknowledge another settlement');
});

test('unacknowledged settlement keeps its original stopped usage duty despite Store success',async()=>{
  const f=fixture();
  f.operation.stoppedAttemptCount=()=>1;
  const failure=new Error('OriginalAckRefused');
  f.flags.ackFailure=failure;
  await assert.rejects(f.settling(),error=>error===failure);
  assert.equal(f.flags.usageRetired,false);
  const proof=f.operation.attemptEvidence;
  f.operation.attemptEvidence=()=>{
    assert.equal(f.flags.usageRetired,true,'Original reader precedes immutable stopped proof');
    return proof();
  };
  await f.owner.persistStoppedAttempts();
  assert.equal(f.counters.usage,3);
  assert.equal(f.counters.ack,0);
  assert.equal(f.counters.cleanup,0);
  assert.equal(f.owner.custody.cleanupPending(),true);
});

test('capture retains the same issued invocation view without wire readmission',async()=>{
  const f=fixture({rejectInvocationReadmit:true});
  await f.complete();
  assert.strictEqual(f.owner.modelEvidence()[0],f.invocationView);
  assert.equal(f.stored.get('model_invocation_evidence').manifest_cid,
    f.invocationView.identity);
  f.flags.modelCleanup=false;
  assert.equal(await f.owner.custody.cleanup(),false);
  assert.strictEqual(f.owner.modelEvidence()[0],f.invocationView);
  f.flags.modelCleanup=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.owner.modelEvidence(),undefined);
  assert.equal(f.invocationView.wire,'{"raw":"é\\r\\n"}');
});

test('settlement exporter selects the same Store wire ceiling before Common allocation',async()=>{
  for(const limit of [12192,2*1048576]){
    const f=fixture({storeWireLimit:limit});
    await f.complete();
    assert.deepEqual(f.counters.exports,[['settlement',Math.min(limit,1048576),1000000],
      ['whole',1048576,1000000]],'captureOnly whole bundle is not held in the per-slot Store cell');
    assert.equal(f.counters.limitReads,1);
    assert.equal(await f.owner.custody.cleanup(),true);
  }
});

test('missing or invalid original Store wire extent never defaults to the one-MiB exporter',async()=>{
  for(const limit of [undefined,-1,NaN,Infinity,1.5,'12192']){
    const f=fixture({storeWireLimit:limit});
    if(limit===undefined)delete f.store.privateEvidenceWireLimit;
    await assert.rejects(f.settling(),{code:'InstalledInferCaptureStoreWireLimitUnavailable'});
    assert.deepEqual(f.counters.exports,[]);
    assert.equal(f.counters.ack,0);assert.equal(f.counters.cleanup,0);
    assert.equal(f.owner.custody.cleanupPending(),true,'original pending settlement responsibility remains');
  }
});

test('known zero Store wire extent reaches the existing Common refusal without becoming unknown or free',async()=>{
  const f=fixture({storeWireLimit:0});
  await assert.rejects(f.settling());
  assert.deepEqual(f.counters.exports,[['settlement',0,1000000]]);
  assert.equal(f.counters.limitReads,1);assert.equal(f.counters.ack,0);
  assert.equal(f.counters.cleanup,0);assert.equal(f.owner.custody.cleanupPending(),true);
});

test('whole capture uses the same extent only when its own bundle will be stored there',async()=>{
  const f=fixture({captureOnly:false});
  await f.settling();f.owner.retainCompleted();
  const original=Object.assign(new Error('FixtureStopBeforeWholeExport'),{code:'FixtureStopBeforeWholeExport'});
  f.moon.clientProgramStartInferCaptureExport=(_capture,maxBytes,maxWork)=>{
    assert.equal(maxBytes,12192);assert.equal(maxWork,1000000);
    throw original;
  };
  await assert.rejects(f.owner.persist(),error=>error===original);
  assert.equal(f.counters.limitReads,1,'same immutable original is inspected once');
  assert.equal(f.counters.cleanup,0);assert.equal(f.owner.custody.cleanupPending(),true);
});

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

test('publication-local retirement precedes parent Model cleanup and preserves escaped originals',async()=>{
  const f=fixture();await f.complete();
  const bundle=f.owner.evaluationBundle(),evidence=f.owner.modelEvidence();
  // Model output-use pin is represented by an explicit port double. This is
  // NOT the actual capacity primitive, its settlement or a funded profile.
  f.flags.modelCleanup=false;
  const flight=f.owner.custody.retirePublication();
  assert.equal(await flight,true);
  assert.equal(f.owner.custody.retirePublication(),flight);
  assert.equal(f.counters.cleanup,0,'local retirement does not call parent cleanup');
  assert.equal(f.owner.custody.cleanupPending(),true);
  assert.equal(f.owner.modelEvidence(),undefined);
  assert.equal(f.owner.evaluationBundle(),undefined);
  assert.throws(()=>f.owner.retainCompleted(),/InstalledInferCaptureUnavailable/);
  await assert.rejects(f.owner.persist(),/InstalledInferCaptureUnavailable/);
  await assert.rejects(f.settling(),/ForeignInferSettlement/);
  assert.equal(bundle.wire,f.bundleWire);
  assert.equal(evidence[0].wire,'{"raw":"é\\r\\n"}');
  assert.ok(f.stored.size>0);
  const commits=f.counters.commit,acks=f.counters.ack;
  assert.equal(await f.owner.custody.cleanup(),false,'parent responsibility remains pending');
  // An actual caller must settle its same-Ledger borrow here, not use a Bool
  // from this test or from retirement as permission to settle/send/restore.
  f.flags.modelCleanup=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.commit,commits);assert.equal(f.counters.ack,acks);
});

test('publication-local retirement waits for the original child and physical stop',async()=>{
  const f=fixture();await f.complete();
  const bundle=f.owner.evaluationBundle(),evidence=f.owner.modelEvidence();
  f.flags.stopped=false;
  assert.equal(await f.owner.custody.retirePublication(),false);
  assert.deepEqual(f.owner.evaluationBundle(),bundle);
  f.flags.stopped=true;f.flags.exportCleanup=false;
  assert.equal(await f.owner.custody.retirePublication(),false);
  assert.deepEqual(f.owner.modelEvidence(),evidence);
  assert.deepEqual(f.owner.evaluationBundle(),bundle);
  assert.equal(f.counters.cleanup,0);
  f.flags.exportCleanup=true;
  assert.equal(await f.owner.custody.retirePublication(),true);
  assert.equal(f.owner.modelEvidence(),undefined);
  assert.equal(f.owner.custody.cleanupPending(),true);
  assert.equal(f.counters.cleanup,0);
});

test('publication-local retirement retries the same failed Store responsibility without parent cleanup',async()=>{
  const f=fixture();let fail=true;
  f.deferCommit(()=>{if(fail)throw Error('FixtureSameStorePending');});
  await assert.rejects(f.settling(),/FixtureSameStorePending/);
  await assert.rejects(f.owner.custody.retirePublication(),/FixtureSameStorePending/);
  assert.equal(f.counters.cleanup,0);assert.equal(f.counters.ack,0);
  assert.equal(f.owner.custody.cleanupPending(),true);
  fail=false;
  assert.equal(await f.owner.custody.retirePublication(),true);
  assert.equal(f.counters.ack,1);assert.equal(f.counters.cleanup,0);
  assert.ok(f.stored.size>0);
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.ack,1);
});

test('publication and parent cleanup observers share the original persistence flight',async()=>{
  const f=fixture();let release,announced;
  const waiting=new Promise(resolve=>{release=resolve;});
  const entered=new Promise(resolve=>{announced=resolve;});
  f.deferCommit(()=>{throw Error('FixtureSameOriginalPending');});
  await assert.rejects(f.settling(),/FixtureSameOriginalPending/);
  f.deferCommit(async()=>{announced();await waiting;});
  f.flags.modelCleanup=false;
  const local=f.owner.custody.retirePublication();await entered;
  const parent=f.owner.custody.cleanup();
  assert.equal(f.owner.custody.retirePublication(),local);
  release();assert.equal(await local,true);assert.equal(await parent,false);
  assert.equal(f.counters.ack,1);assert.equal(f.counters.cleanup,1);
  assert.equal(f.owner.modelEvidence(),undefined);
  f.flags.modelCleanup=true;
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.ack,1);
});

test('completed capture count does not imply persistence and retires with its own custody',async()=>{
  const f=fixture();assert.equal(f.owner.completedCallCount(),undefined);
  await f.settling();f.owner.retainCompleted();
  assert.equal(f.owner.completedCallCount(),1);
  assert.equal(f.owner.modelEvidence(),undefined,'a known count is not a stored evidence claim');
  await f.owner.persist();assert.equal(f.owner.completedCallCount(),1);
  assert.equal(await f.owner.custody.retirePublication(),true);
  assert.equal(f.owner.completedCallCount(),undefined);
  assert.equal(await f.owner.custody.cleanup(),true);
});

test('terminal publication reservation precedes capture allocation and refusal creates no capture',async()=>{
  const f=fixture();
  // Use the original settlement from the fixture; no new response/send occurs.
  await f.settling();
  let admitted=false,reserves=0;
  f.operation.reserveOriginalPublicationCapacity=()=>{
    reserves++;assert.equal(f.counters.acquire,0);
    if(!admitted)throw Error('FixturePublicationCapacityUnavailable');
  };
  assert.throws(()=>f.owner.retainCompleted(),/FixturePublicationCapacityUnavailable/);
  assert.equal(f.counters.acquire,0);
  admitted=true;
  assert.equal(f.owner.retainCompleted(),true);
  assert.equal(f.counters.acquire,1);assert.equal(reserves,2);
  assert.equal(f.owner.retainCompleted(),true);assert.equal(reserves,2);
  await f.owner.persist();
  assert.equal(await f.owner.custody.cleanup(),true);
});

test('stopped raw usage drains original Common observation before immutable attempt persistence',async()=>{
  const f=fixture({stoppedRaw:true});
  await f.owner.persistStoppedAttempts();
  assert.equal(f.counters.usage,3);
  assert.equal(f.counters.proof,1);
  assert.equal(f.counters.cleanup,0);
  assert.equal(f.counters.commit,4);
  const counts={...f.counters};
  await f.owner.persistStoppedAttempts();
  assert.deepEqual(f.counters,counts,'same persisted attempt is not reread or rewritten');
  // The Common issue above is opaque diagnostic data. Node does not turn it
  // into response success or create another Entry/physical operation.
  assert.equal(await f.owner.custody.cleanup(),true);
  assert.equal(f.counters.usage,3);
  assert.equal(f.counters.proof,1);
});

test('stopped raw usage current refusal retains same custody and delays immutable evidence',async()=>{
  const f=fixture({stoppedRaw:true});f.flags.usageRefusal=true;
  await assert.rejects(f.owner.persistStoppedAttempts(),/FixtureOriginalRawCurrentLost/);
  assert.equal(f.counters.proof,0);
  assert.equal(f.counters.commit,0);
  assert.equal(f.counters.cleanup,0);
  assert.equal(f.owner.custody.cleanupPending(),true);
  f.flags.usageRefusal=false;
  await f.owner.persistStoppedAttempts();
  assert.equal(f.counters.proof,1);
  assert.equal(f.counters.commit,4);
  assert.equal(await f.owner.custody.cleanup(),true);
});

test('stopped raw usage missing Common observation port refuses before proof and cleanup',async()=>{
  const f=fixture({stoppedRaw:true});
  delete f.operation.advanceStoppedAttemptUsage;
  await assert.rejects(f.owner.persistStoppedAttempts(),/InstalledInferRawUsageUnavailable/);
  assert.equal(f.counters.proof,0);
  assert.equal(f.counters.commit,0);
  assert.equal(f.counters.cleanup,0);
  assert.equal(f.owner.custody.cleanupPending(),true);
});

test('missing attempt identity cannot turn an absent settlement marker into an ACK',async()=>{
  const f=fixture({omitEntryAttempt:true});
  const original=new Error('OriginalStoppedReaderRequired');let reads=0;
  f.operation.stoppedAttemptCount=()=>1;
  f.operation.advanceStoppedAttemptUsage=()=>{reads++;throw original;};
  await assert.rejects(f.owner.persistStoppedAttempts(),error=>error===original);
  assert.equal(reads,1);
  assert.equal(f.counters.ack,0);
  assert.equal(f.counters.cleanup,0);
});
