// Execute the actual recovery statement body with explicit Journal/Core/driver
// ports and stop before dispatch routing. No actual Run, FD or grant exists.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

const source=readFileSync(new URL('./installed-row-effect.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),found=[];
function visit(value){
  if(value===null||typeof value!=='object')return;
  if(value.type==='FunctionDeclaration'&&value.id.name==='prepareRecovered')found.push(value);
  for(const child of Object.values(value)){
    if(Array.isArray(child))child.forEach(visit);else visit(child);
  }
}
visit(ast);assert.equal(found.length,1);

function fixture(selected=true){
  const moon={},events=[],preview={},scope={},identity={},stop=new Error('ReachedOriginalCapabilityBoundary');
  let retained,pending=true,ack=false,prepare;
  const child={async prepare(){assert(retained,'parent retained before child prepare');events.push('prepare child');
    await prepare?.();},
    async release(){events.push('release child');if(ack)pending=false;return !pending;},
    status:()=>({pending})};
  const owner={owned:selected?{prepareRecoveredContentChild(){
    assert(retained,'parent retained before factory');events.push('construct child');return child;}}:{}};
  const members=[{memberIndex:0}],body={invocation_cid:'invocation',run_identity_cid:'run',
    authoring_context:{authoring_context_cid:'author'},effects:[{capability_evidence_cid:'capability',changes:[]}]};
  const effect={recoveredPreviewKeys:()=>({}),admitPreviewIdentity:()=>({})};
  const ledger={close(){events.push('close ledger');},recoverClaimFacts:()=>({})};
  const bindings={moon,owners:[owner],singular:undefined,limits:{maxRows:10,maxWork:100,
    key:{maxBytes:100,maxNodes:10,maxDepth:5},
    preview:{maxWireBytes:1000,maxNodes:100,maxDepth:10}},localContractLimits:{},ROUTING_VERSION:'original',
    fail:code=>{throw Object.assign(new Error(code),{code});},text:value=>typeof value==='string'&&value.length>0,
    recoveredMembers:()=>members,bindRunResources(){events.push('bind resources');},
    selectionFence:()=>()=>events.push('current'),memberDispatch:()=> 'dispatch',effect,
    openLedger:()=>ledger,recoveredEntries:()=>({entries:[[]],currents:[]}),ownerOf:()=>owner,
    resourceFields:()=>({}),orderedSourceIndexes:()=>[],
    physicalRoute(){assert.fail('No route is created before the exact terminal marker');},
    admitCapability(){events.push('capability');return{identity:'capability'};}};
  const fn=Function(...Object.keys(bindings),`return (${source.slice(found[0].start,found[0].end)});`)(
    ...Object.values(bindings));
  const facts={moon,control:{effectComputationPreviewWire:value=>{
    assert.strictEqual(value,preview);return JSON.stringify(body);},effectComputationPreviewLedgerIdentity:()=>({}),
    effectComputationPreviewSemanticCid(){events.push('exact terminal');throw stop;}},
    recovered:{requestIdentity:identity,requestScope:scope,computation:{computation:{},preview,storedResults:{}}},
    continuation:{version:'original',program_id:'program',stage_id:'stage',
      members:[{dispatch_request_cid:'dispatch'}]},
    retainRecoveryOwner(value){assert.equal(retained,undefined);retained=value;events.push('retain parent');}};
  return{fn,facts,events,stop,parent:()=>retained,ack(){ack=true;},prepare(value){prepare=value;}};
}

test('selected recovered Content stays in the original parent across await and pending cleanup',async()=>{
  const f=fixture();let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  f.prepare(()=>{enter();return barrier;});
  const observed=f.fn(f.facts).catch(error=>error);
  await entered;
  assert(f.events.indexOf('retain parent')<f.events.indexOf('construct child'));
  assert.equal(f.events.includes('capability'),false);
  assert.equal(f.parent().cleanupPending(),true);
  await assert.rejects(f.parent().close(),{code:'InstalledRowEffectContentCleanupPending'});
  assert.equal(f.events.includes('close ledger'),false);
  release();assert.strictEqual(await observed,f.stop);
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
