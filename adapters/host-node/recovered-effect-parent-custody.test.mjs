// Execute the actual recovery statement body with explicit Journal/Core/driver
// ports and stop before dispatch routing. No actual Run, FD or grant exists.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledRowEffectRunLimits} from './installed-row-effect-run-controls.mjs';
import {createInstalledRowEffectRecoveryBacking} from './installed-row-effect-recovery-backing.mjs';
import {createInstalledRowEffectRecovery} from './installed-row-effect-recovery.mjs';

function fixture(selected=true,{complete=false,requestChild}={}){
  const moon={},events=[],preview={},scope={},identity={},stop=new Error('ReachedOriginalCapabilityBoundary');
  let retained,pending=true,ack=false,prepare;
  const child={async prepare(){assert(retained,'parent retained before child prepare');events.push('prepare child');
    await prepare?.();},
    async release(){events.push(complete?'close original writer':'release child');if(ack)pending=false;return !pending;},
    status:()=>({pending})};
  const owner={owned:selected?{prepareRecoveredContentChild(){
    assert(retained,'parent retained before factory');events.push('construct child');return child;}}:{}};
  const members=[{memberIndex:0}],body={invocation_cid:'invocation',run_identity_cid:'run',
    authoring_context:{authoring_context_cid:'author'},effects:[{capability_evidence_cid:'capability',changes:[]}]};
  const keys=[[]];let keyConstructions=0;
  const effect={recoveredPreviewKeys:()=>{keyConstructions++;return keys;},admitPreviewIdentity:()=>({})};
  const ledger={close(){events.push('close ledger');},recoverClaimFacts(_options,originalKeys){
    assert.strictEqual(originalKeys,keys);events.push('borrow original keys');
    return{members:members.map(()=>({claims:[]}))};}};
  const bindings={moon,owners:[owner],singular:undefined,limits:{maxMembers:1,maxRows:10,maxWork:100,
    key:{maxBytes:100,maxNodes:10,maxDepth:5},
    preview:{maxWireBytes:1000,maxNodes:100,maxDepth:10}},localContractLimits:{},ROUTING_VERSION:'original',
    fail:code=>{throw Object.assign(new Error(code),{code});},text:value=>typeof value==='string'&&value.length>0,
    recoveredMembers:()=>members,bindRunResources(){events.push('bind resources');},
    selectionFence:()=>()=>events.push('current'),memberDispatch:()=> 'dispatch',effect,
    openLedger:()=>ledger,recoveredEntries:()=>({entries:[[]],currents:[]}),ownerOf:()=>owner,
    resourceFields:()=>({}),orderedSourceIndexes:()=>[],
    scopes:()=>[],
    physicalRoute(){
      if(!complete)assert.fail('No route is created before the exact terminal marker');
      return {retire(){events.push('retire aliases');return true;}};
    },
    admitCapability(){events.push('capability');return{identity:'capability'};}};
  const runLimits=createInstalledRowEffectRunLimits({moon, limits:bindings.limits,
    owners:bindings.owners, readManagedShape:moon.clientProgramInstalledEffectManagedPlanShape, fail:bindings.fail});
  const prepareRecoveredEntries=createInstalledRowEffectRecoveryBacking({
    moon, recoveredEntries:bindings.recoveredEntries, fail:bindings.fail,
    prepareInstalledEffectRequestChild:()=>assert.fail('No Native request construction in this fixture'),
  });
  const fn=createInstalledRowEffectRecovery({...bindings,runLimits,
    prepareRecoveredEntries(options){
      if(requestChild!==undefined)options.requestChildren.push(requestChild);
      return prepareRecoveredEntries(options);
    },
  });
  const facts={moon,control:{effectComputationPreviewWire:value=>{
    assert.strictEqual(value,preview);return JSON.stringify(body);},effectComputationPreviewLedgerIdentity:()=>({}),
    effectComputationPreviewSemanticCid(){events.push('exact terminal');if(!complete)throw stop;return 'original preview';}},
    recovered:{requestIdentity:identity,requestScope:scope,computation:{computation:{},preview,storedResults:{}}},
    continuation:{version:'original',program_id:'program',stage_id:'stage',
      members:[{dispatch_request_cid:'dispatch'}]},
    retainRecoveryOwner(value){assert.equal(retained,undefined);retained=value;events.push('retain parent');}};
  return{fn,facts,events,stop,parent:()=>retained,keyConstructions:()=>keyConstructions,
    ack(){ack=true;},prepare(value){prepare=value;},pending:()=>pending};
}

test('cold claim recovery borrows its single original key cohort before capability admission',()=>{
  const f=fixture(false);
  assert.throws(()=>f.fn(f.facts),error=>error===f.stop);
  assert.equal(f.keyConstructions(),1);
  assert.equal(f.events.filter(value=>value==='borrow original keys').length,1);
  assert(f.events.indexOf('borrow original keys')<f.events.indexOf('capability'));
});

test('selected recovered Content stays in the original parent across await and pending cleanup',async()=>{
  const f=fixture();let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  f.prepare(()=>{enter();return barrier;});
  const observed=f.fn(f.facts).catch(error=>error);
  await entered;
  assert(f.events.indexOf('retain parent')<f.events.indexOf('construct child'));
  assert.equal(f.events.includes('capability'),false);
  assert.equal(f.parent().cleanupPending(),true);
  // The original opening owner reports pending without rejecting. Closing
  // also fences publication when its already-retained child finishes opening.
  assert.equal(await f.parent().close(),false);
  assert.equal(f.events.includes('close ledger'),false);
  release();assert.equal((await observed).code,'InstalledRowEffectRouteRetired');
  assert.equal(f.events.includes('capability'),false);
  assert.equal(f.events.includes('exact terminal'),false);
  f.ack();assert.equal(await f.parent().cleanup(),true);
  assert.equal(f.parent().cleanupPending(),false);
  assert.equal(f.events.filter(value=>value==='close ledger').length,1);
});

test('failed recovered Content retains its exact failure and child without reaching capability',async()=>{
  const f=fixture(),failure=new Error('original private reader failed');
  f.prepare(()=>{throw failure;});
  await assert.rejects(f.fn(f.facts),error=>error===failure);
  assert.equal(f.events.includes('capability'),false);assert.equal(f.parent().cleanupPending(),true);
  f.ack();assert.equal(await f.parent().cleanup(),true);
});

test('unselected recovery keeps synchronous validation and creates no Content child',()=>{
  const f=fixture(false);
  assert.throws(()=>f.fn(f.facts),error=>error===f.stop);
  assert.equal(f.events.includes('construct child'),false);assert.equal(f.events.includes('prepare child'),false);
});

// The actual recovery owner holds both children. The writer's pending state
// is an explicit port so this verifies close order and retry without file I/O.
test('recovered physical operation waits for its original Content writer close without blocking that close', async () => {
  let operationPending=true;
  const prepared={release(){f.events.push('release operation');if(!f.pending())operationPending=false;
    return !operationPending;},retry(){f.events.push('retry operation');return this.release();},
    status:()=>({pending:operationPending})};
  const f=fixture(true,{complete:true,requestChild:{prepared}});
  const stage=await f.fn(f.facts);
  assert.strictEqual(stage.cleanupOwner,f.parent());
  const openingEvents=f.events.length;
  const close=stage.dispose;
  assert.equal(await close(),false);assert.equal(f.events.includes('close ledger'),false);
  f.ack();assert.equal(await close(),true);
  assert.deepEqual(f.events.slice(openingEvents),['retire aliases','close original writer','release operation',
    'retire aliases','close original writer','retry operation','release operation','close ledger']);
  assert.equal(await close(),true);assert.equal(f.events.filter(event=>event==='close ledger').length,1);
});
