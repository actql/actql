import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientEffectRun} from './client-effect-run.mjs';

const ok = value => ({$tag:1,_0:value});
const cid = 'sha256:'+'a'.repeat(64);

// The real installed Run adapter, explicit Common/Journal ports and actual
// retained wall-clock sampler. These are ordering/custody counters, not a
// Common compiler, physical COMMIT, installed Host or resource admission.
function fixture({required=true,legacy=false,race,commitFailure}={}) {
  const prepared={},compilation={},allowed={},identity={};
  const state={samples:[],issued:[],contexts:[],executions:[],preparations:[],events:[],claims:0};
  const request={prepared,authorityScopeCid:cid,requestId:'query',namespaceId:'namespace',
    principalId:'principal',connection:{mode:'local',owner:'local'}};
  const ref={namespaceId:'namespace',authorityScopeCid:cid,runDefinitionCid:cid};
  const policy={executionContextCid:cid,hostPolicyCid:cid,
    createdAt:'2001-01-01T00:00:00.000Z',expiresAt:'2099-01-01T00:00:00.000Z'};
  const retained = () => ({ref,durability:'durable',revision:0,lookupExpiresAt:policy.expiresAt,
    runDefinition:state.saved.runDefinition,runAdmissionEvidence:state.saved.runAdmissionEvidence,
    physicalStartReserved:state.claims!==0,preDispatchFailureConfirmed:false,
    cancellationRequested:false,observedTerminalOutcome:null});
  const moon={
    clientProgramEffectCompilationIssueCode:()=>undefined,
    clientProgramCompileLocalEffects(value){assert.strictEqual(value,prepared);state.events.push('compile');return ok(compilation);},
    clientProgramEffectRequestIdentity(value){assert.strictEqual(value,prepared);return identity;},
    clientProgramSourceFreeInputIntentCid:()=>cid,
    clientProgramIssueAllowedEffectRun(value){assert.strictEqual(value,compilation);return ok(allowed);},
    clientProgramIssueEffectRunDefinition(value,namespace,runId,createdAt,until){
      assert.strictEqual(value,allowed);assert.equal(namespace,'namespace');assert.equal(until,policy.expiresAt);
      const definition={run_id:runId,created_at:createdAt,valid_until:until};state.issued.push(definition);return ok(definition);},
    clientProgramEffectRunStartCurrent:()=>true,
    strategyPublicationContractJson:value=>JSON.stringify(value),
    strategyRunEvidenceJson:()=>'{"original":true}',
    clientProgramAllowedEffectRunPrepared:()=>({}),
    clientProgramAllowedEffectRunAuthorization:()=>({}),
    clientProgramEffectCompilationResultNames:()=>['result'],
    strategyRunEvidenceAdmit:()=>ok({}),
    clientProgramAdmitAllowedEffectRun:()=>ok(allowed),
    strategyPublicationAdmit:(_name,wire)=>ok(JSON.parse(wire)),
    clientProgramBindCompiledEffectRun:()=>ok({}),
    clientRunStartAction:()=>0,
    clientRequestAuthorityScopeCid:()=>cid,
    clientRequestCallerId:()=>request.requestId,
  };
  if(!legacy)Object.assign(moon,{
    clientProgramEffectRequiresQueryTime(value){assert.strictEqual(value,prepared);return ok(required);},
    clientProgramPrepareEffectQueryTime(value,originalRequest,createdAt){
      assert.strictEqual(value,prepared);assert.strictEqual(originalRequest,identity);
      state.samples.push(createdAt);state.events.push('sample');return ok({createdAt,originalRequest});},
    clientProgramQueryTimeCreatedAt:value=>value.createdAt,
    clientProgramBindEffectQueryTime(value,owner,grant,definition,originalRequest){
      assert.strictEqual(owner,prepared);assert.strictEqual(grant,allowed);
      assert.strictEqual(originalRequest,identity);assert.equal(value.createdAt,definition.created_at);
      state.events.push('bind');return ok({createdAt:definition.created_at});},
    clientProgramRestoreEffectQueryTimePreparation(owner,grant,definition,originalRequest){
      assert.strictEqual(owner,prepared);assert.strictEqual(grant,allowed);assert.strictEqual(originalRequest,identity);
      const context=Object.freeze({createdAt:definition.created_at});state.contexts.push(context);
      state.events.push('restore');return ok({context});},
    clientProgramQueryTimeContext:value=>value.context,
  });
  const control={admit:(_name,wire)=>({wire,identity:cid})};
  const journal={
    async admitOrLookupDefinition(original,options){assert.strictEqual(original,identity);
      if(state.saved)return retained();
      const issued=await options.issueDefinition();state.saved=issued;
      if(race)state.saved={...issued,runDefinition:{wire:JSON.stringify({...state.issued[0],created_at:race}),identity:cid}};
      if(commitFailure)throw commitFailure;
      return retained();},
    lookupDefinition(){return state.saved&&retained();},
    resolveDefinition(original){assert.strictEqual(original,identity);return state.saved&&retained();},
    reserveDispatch(){return {ref};},
    reservePhysicalStart(){state.events.push('claim');state.claims++;return true;},
    originalSubmittedIntent:()=>undefined,
  };
  const install=({prepareDefinition}={})=>installNodeClientEffectRun({moon,publicationControl:control,journal,
    prepareDefinition,
    authorizeRequest:async()=>policy,authorizeRunStart:async()=>true,
    now:()=> '2026-10-19T00:00:00.000Z',
    prepareExecution(facts){state.events.push('prepare');state.preparations.push(facts);return {};},
    execute:async facts=>{state.events.push('execute');state.executions.push(facts);return {};}});
  return {state,request,moon,install,policy,ref};
}

test('new query-time Run samples once after lookup and before compilation instead of reusing policy creation',async()=>{
  const f=fixture(),run=f.install();run.checkSupported(f.request.prepared);
  assert.equal(f.state.samples.length,0);
  f.state.events.length=0;
  const before=Date.now(),handle=await run.accept(f.request),after=Date.now();
  assert.equal(f.state.samples.length,1);const sample=f.state.samples[0];
  assert(Date.parse(sample)>=before&&Date.parse(sample)<=after);
  assert.notEqual(sample,f.policy.createdAt);assert.equal(f.state.issued[0].created_at,sample);
  assert(f.state.events.indexOf('sample')<f.state.events.indexOf('bind'));
  assert.deepEqual(handle.ref,f.ref);assert.equal(f.state.claims,0);
});

test('lookup and re-admission restore the winning saved time without a second sample',async()=>{
  const f=fixture(),first=f.install();await first.accept(f.request);
  const sample=f.state.samples[0],second=f.install(),handle=await second.accept(f.request);
  assert.equal(f.state.samples.length,1);assert.equal(f.state.issued.length,1);
  await second.start(handle);
  assert.equal(f.state.samples.length,1);assert.equal(f.state.contexts[0].createdAt,sample);
  assert.strictEqual(f.state.preparations[0].queryTime,f.state.executions[0].queryTime);
  assert.strictEqual(f.state.preparations[0].queryTimePreparation,f.state.executions[0].queryTimePreparation);
  assert(f.state.events.indexOf('restore')<f.state.events.indexOf('prepare'));
  assert(f.state.events.indexOf('claim')<f.state.events.indexOf('execute'));
  const restored=await second.restoreComputation(handle);
  assert.equal(restored.queryTime.createdAt,sample);assert.equal(f.state.samples.length,1);
});

test('a racing issuer consumes only the saved winning definition at preparation and execution',async()=>{
  const winning='2025-01-01T00:00:00.000Z',f=fixture({race:winning}),run=f.install();
  const handle=await run.accept(f.request);assert.notEqual(f.state.samples[0],winning);
  await run.start(handle);
  assert.equal(f.state.samples.length,1);assert.equal(f.state.executions[0].queryTime.createdAt,winning);
});

test('unknown admission preserves its failure and does not reach preparation or physical dispatch',async()=>{
  const failure=Object.assign(new Error('OriginalCommitUnknown'),{code:'ClientRequestAdmissionUnknown'});
  const f=fixture({commitFailure:failure}),run=f.install();
  await assert.rejects(run.accept(f.request),error=>error===failure);
  assert.equal(f.state.samples.length,1);assert.equal(f.state.preparations.length,0);
  assert.equal(f.state.executions.length,0);assert.equal(f.state.claims,0);
});

test('legacy and explicitly absent query-time requirements preserve old Run creation bytes',async()=>{
  for(const options of [{legacy:true},{required:false}]){
    const f=fixture(options),run=f.install();await run.accept(f.request);
    assert.equal(f.state.samples.length,0);assert.equal(f.state.issued[0].created_at,f.policy.createdAt);
  }
});

test('query-time adapter captures original Common receivers and refuses incomplete installations',async()=>{
  const f=fixture(),run=f.install();
  f.moon.clientProgramPrepareEffectQueryTime=()=>assert.fail('Replacement is not original');
  await run.accept(f.request);assert.equal(f.state.samples.length,1);
  const missing=fixture();delete missing.moon.clientProgramQueryTimeContext;
  assert.throws(()=>missing.install(),{message:'InvalidClientEffectRunInstallation'});
});

// Actual acceptance and original issuer await; Common/Journal authority and
// backing remain explicit ports. No Run is saved or physical claim issued.
test('Effect definition refuses async preparation only after the SAME original borrow settles',async()=>{
  for(const rejected of [false,true]){
    let settle,seen;
    const pending=new Promise((resolve,reject)=>{settle=()=>rejected?reject(new Error('original rejected borrow')):resolve();});
    const f=fixture({legacy:true}),run=f.install({prepareDefinition(facts){seen=facts;return pending;}});
    let state='pending',failure;
    const flight=run.accept(f.request).then(()=>{state='accepted';},error=>{state='refused';failure=error;});
    await new Promise(setImmediate);
    try{
      assert.equal(state,'pending','same original preparation must settle before acceptance refusal');
      assert.equal(f.state.saved,undefined);
      assert.equal(seen.prepared,f.request.prepared);
      assert.equal(seen.runDefinition.wire,JSON.stringify(f.state.issued[0]));
      assert.equal(f.state.issued.length,1);
      assert.equal(f.state.claims,0);assert.equal(f.state.executions.length,0);
    }finally{settle();await flight;}
    assert.equal(state,'refused');assert.equal(failure?.message,'AsyncClientEffectDefinitionPreparation');
    assert.equal(f.state.saved,undefined);assert.equal(f.state.claims,0);
  }
});

test('Effect definition captures original then once and does not assimilate its opaque fulfillment DATA',async()=>{
  let finish,reads=0,opaqueReads=0,invocations=0;
  const opaque=Object.freeze({get then(){opaqueReads++;throw new Error('opaque DATA must not be assimilated');}});
  const thenable=Object.freeze({get then(){reads++;return function(yes){assert.equal(this,thenable);finish=()=>yes(opaque);};}});
  const f=fixture({legacy:true}),run=f.install({prepareDefinition(){invocations++;return thenable;}});
  let failure;
  const flight=run.accept(f.request).catch(error=>{failure=error;});
  await new Promise(setImmediate);
  assert.equal(reads,1);assert.equal(invocations,1);assert.equal(f.state.saved,undefined);
  finish();await flight;
  assert.equal(reads,1);assert.equal(opaqueReads,0);
  assert.equal(failure?.message,'AsyncClientEffectDefinitionPreparation');
  assert.equal(f.state.saved,undefined);assert.equal(f.state.claims,0);
});

test('Effect definition preserves original synchronous failure and existing synchronous preparation',async()=>{
  for(const failure of [undefined,new Error('original synchronous construction failure')]){
    const f=fixture({legacy:true}),run=f.install({prepareDefinition(){throw failure;}});
    let refused=false,actual;
    await run.accept(f.request).catch(error=>{refused=true;actual=error;});
    assert.equal(refused,true);assert.equal(actual,failure);
    assert.equal(f.state.saved,undefined);assert.equal(f.state.claims,0);
  }
  const f=fixture({legacy:true});let seen;
  const original=Object.freeze({then:17});
  const run=f.install({prepareDefinition(facts){seen=facts;return original;}}),handle=await run.accept(f.request);
  assert.equal(seen.prepared,f.request.prepared);assert.equal(f.state.events.filter(event=>event==='compile').length,1);assert(Object.isFrozen(seen));
  assert.deepEqual(handle.ref,f.ref);assert.equal(f.state.issued.length,1);
  assert.equal(f.state.claims,0);assert.equal(f.state.executions.length,0);
});
