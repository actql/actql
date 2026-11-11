import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
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
    cancellationRequested:state.cancelled === true,observedTerminalOutcome:null});
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
  const install=({prepareDefinition,requestIdentityFor}={})=>installNodeClientEffectRun({moon,publicationControl:control,journal,
    prepareDefinition,requestIdentityFor,
    authorizeRequest:async()=>policy,authorizeRunStart:async()=>true,
    now:()=> '2026-10-19T00:00:00.000Z',
    prepareExecution(facts){state.events.push('prepare');state.preparations.push(facts);return {};},
    execute:async facts=>{state.events.push('execute');state.executions.push(facts);return {};}});
  return {state,request,moon,install,policy,ref,identity};
}

test('ordinary Effect admission and winning issuer consume one original Request identity', async () => {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  let original;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === 'originalSourceFreeRequest') original = node.init;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(original);
  const f = fixture(); let nativeIdentities = 0;
  f.moon.clientProgramEffectRequestIdentity = (prepared, scope, id) => {
    assert.strictEqual(prepared, f.request.prepared); assert.equal(scope, cid); assert.equal(id, f.request.requestId);
    nativeIdentities++; return f.identity;
  };
  const select = Function('moon', 'authorityScopeCid', 'sourceFreeRequestIdentities', 'clientOperationError',
    'return (' + source.slice(original.start, original.end) + ');')(
    f.moon, cid, new WeakMap(), code => Object.assign(new Error(code), {code}));
  assert.strictEqual(select(f.request.prepared, f.request.requestId, true), f.identity);
  const run = f.install({requestIdentityFor({prepared, authorityScopeCid, requestId}) {
    assert.equal(authorityScopeCid, cid); return select(prepared, requestId, true);
  }});
  await run.accept(f.request); await run.accept(f.request);
  assert.equal(nativeIdentities, 1); assert.equal(f.state.issued.length, 1); assert.equal(f.state.samples.length, 1);
});

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


async function restoredDefinitionFixture(prepareDefinition) {
  const f = fixture(), first = f.install();
  const initial = await first.accept(f.request);await first.start(initial);
  const second = f.install({prepareDefinition: facts => prepareDefinition(facts, f)});
  const handle = await second.accept(f.request);
  return {...f, second, handle};
}

test('cold Effect computation prepares its same restored definition before execution preparation', async () => {
  let original;
  const f = await restoredDefinitionFixture((facts, fixture) => {
    assert.equal(original, undefined);original = facts;fixture.state.events.push('definition');
    assert(Object.isFrozen(facts));
    for (const name of ['prepared', 'identity', 'compilation', 'allowed', 'definition',
      'queryTimePreparation', 'modelCompiled']) assert(Object.hasOwn(facts, name), name);
    assert.strictEqual(facts.prepared, fixture.request.prepared);
    assert.strictEqual(facts.identity, fixture.identity);
  });
  const before = f.state.events.filter(value => value === 'compile').length;
  const restored = await f.second.restoreComputation(f.handle);
  assert(original);assert.strictEqual(f.state.preparations.at(-1), original);
  assert.strictEqual(restored.prepared, original.prepared);
  assert.strictEqual(restored.compilation, original.compilation);
  assert(f.state.events.lastIndexOf('definition') < f.state.events.lastIndexOf('prepare'));
  assert.equal(f.state.events.filter(value => value === 'compile').length, before + 1);
  assert.equal(f.state.issued.length, 1);assert.equal(f.state.samples.length, 1);assert.equal(f.state.claims, 1);
});

test('cold Effect computation joins original invalid async definition before refusing', async () => {
  let settle;
  const pending = new Promise(resolve => {settle = resolve;});
  const f = await restoredDefinitionFixture(() => pending);
  const before = f.state.preparations.length;
  let completed = false, failure;
  const flight = f.second.restoreComputation(f.handle).then(
    () => {completed = true;}, cause => {completed = true;failure = cause;});
  await new Promise(setImmediate);
  try {assert.equal(completed, false);assert.equal(f.state.preparations.length, before);}
  finally {settle();await flight;}
  assert.equal(failure?.message, 'AsyncClientEffectDefinitionPreparation');
  assert.equal(f.state.preparations.length, before);assert.equal(f.state.claims, 1);
});

test('cold Effect computation preserves original thrown undefined before execution preparation', async () => {
  const f = await restoredDefinitionFixture(() => {throw undefined;});
  const before = f.state.preparations.length;let rejected = false;
  try {await f.second.restoreComputation(f.handle);}
  catch (cause) {rejected = true;assert.strictEqual(cause, undefined);}
  assert.equal(rejected, true);assert.equal(f.state.preparations.length, before);
  assert.equal(f.state.claims, 1);
});

test('cold Effect computation refuses cancellation reentered by its definition constructor', async () => {
  const f = await restoredDefinitionFixture((_facts, fixture) => {fixture.state.cancelled = true;});
  const before = f.state.preparations.length;
  await assert.rejects(f.second.restoreComputation(f.handle), {code: 'ClientEffectRunDenied'});
  assert.equal(f.state.preparations.length, before);assert.equal(f.state.claims, 1);
});
