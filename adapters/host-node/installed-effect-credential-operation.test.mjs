import assert from 'node:assert/strict';
import test from 'node:test';
import {maxHeaderSize} from 'node:http';
import {openHttpsExchangeFixture} from '../site-node/https-exchange-fixture.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding,callHttpsCredentialResource} from '../site-node/https-credential-resource.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import * as implementation from './installed-effect-plan.mjs';

// Native Plan/Account issuer/Journal ports are explicit. The shared operation,
// capture retainer, scoped invocation, Credential binding and TLS are real.
// This is not native capacity/normal installation or provider outcome evidence.
test('same original Effect operation reserves before binding and accounts exact TLS frames until original cleanup',async t=>{
  assert.equal(typeof implementation.prepareInstalledEffectCredentialChild,'function');
  const server=await openHttpsExchangeFixture(t,{routes:[{method:'POST',pathname:'/create',handle:()=>({body:'{"ok":true}'})}]});
  const parent={},prepared={},identity={},plan={},token={},grant={},events=[],charges=[],children=[];
  const scope=Object.freeze({issuerAuthority:'authority',principal:'principal',namespaceId:'namespace',environment:'fixture',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',
    resourceOrigin:server.origin,runInvocationCid:'run',taskAttempt:1,dispatchRequestCid:'dispatch',operation:'create'});
  const raw=Object.freeze({grant,scope}),purpose=Object.freeze({kind:'effect',resource:'rows'});
  const control={identity:()=> 'original-grant'},journal={
    claim(){return {replayed:false,grant,use:{},record:{useCid:'use',grantCid:'original-grant'}};},authorize(){},finish(){}};
  const resolveSecret=async()=> 'fixture-secret';
  let aliasesRetired=false,retired=false;
  const extent={};
  const runtime={clientProgramInstalledEffectManagedPlanOperation:()=>({$tag:1,_0:extent}),
    clientProgramInstalledEffectOperationExtentPhysical:original=>{assert.equal(original,extent);return true;},
    clientProgramInstalledEffectOperationExtentTransfer:original=>{assert.equal(original,extent);return 1089n;},
    clientProgramInstalledEffectOperationResponseBackingFits(original,bytes){assert.equal(this,runtime);assert.equal(original,extent);assert.equal(bytes,64);return true;},
    clientProgramInstalledEffectManagedOperationPlan(owner,p,r){assert.equal(owner,parent);assert.equal(p,prepared);assert.equal(r,identity);return {$tag:1,_0:plan};},
    clientProgramInstalledEffectOperationBorrow(owner,p,r,original,member,perRow,index,row,operation){
      assert.equal(owner,parent);assert.equal(p,prepared);assert.equal(r,identity);assert.equal(original,plan);
      assert.deepEqual([member,perRow,index,row,operation],[0,true,2,0,'create']);events.push('borrow');return {$tag:1,_0:token};},
    clientProgramInstalledEffectOperationStart(original){assert.equal(original,token);events.push('start');return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationCharge(original,bytes){assert.equal(original,token);assert.equal(typeof bytes,'bigint');charges.push(bytes);return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationRetire(original,ack){assert.equal(original,token);assert.equal(ack,true);assert(aliasesRetired);retired=true;return {$tag:1,_0:true};}};
  const run={runtime,value:parent,prepared,request:identity,operationPlan:plan,readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan};
  const site=Object.freeze({runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',referenceCurrent:()=>true,
    authorizationPurpose(original){assert.equal(original,raw);return purpose;},
    bindRunAcquisition(original,current){
      assert.equal(original,raw);assert.equal(children.length,1);assert.deepEqual(events,['borrow']);events.push('bind');
      const binding=openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:64,assertCurrent:current.assertCurrent});
      return Object.freeze({credential:Object.freeze({binding,control,journal,resolveSecret,ca:server.ca,currentBeforeSend:current.observeCurrent}),
        close(){return closeHttpsCredentialBinding(binding);}});
    },callResource(options){events.push('call');assert.equal(options.grant,grant);return callHttpsCredentialResource(options);}});
  const child=implementation.prepareInstalledEffectCredentialChild({run,memberIndex:0,rowIndex:0,operationIndex:2,operation:'create',
    originalSite:site,originalAuthorization:raw,useId:'use',resource:'rows',purpose:'effect',runInvocationCid:'run',dispatchRequestCid:'dispatch',
    maxRequestBytes:1024,maxResponseBytes:64,assertCurrent(){},observeCurrent:async()=>{},requestsRetired:()=>aliasesRetired,
    invoke({authorization,credential,callResource}){assert.equal(authorization.grant,grant);assert.equal(authorization.useId,'use');
      return invokeScopedCredentialOperation({authorization,credential,callResource,operation:'create',method:'POST',path:'/create',body:'{}',
        maxRequestBytes:1024,maxResponseBytes:64});}});
  assert.deepEqual(events,['borrow']);
  let output=await prepareInstalledRowCaptureChild({children,create:()=>child});
  assert.equal(output.body.toString(),'{"ok":true}');assert.deepEqual(charges,[2n,11n]);
  assert.deepEqual(events,['borrow','bind','start','call']);assert.equal(server.seen().length,1);
  assert.equal(await child.release(),false);assert.equal(retired,false);
  output=undefined;aliasesRetired=true;
  await children[0].prepared.retry();
  assert.equal(child.status().pending,false);assert.equal(retired,true);
});

async function operationFixture(t,{reply=()=>({body:'{}'})}={}){
  const server=await openHttpsExchangeFixture(t,{routes:[{method:'POST',pathname:'/create',handle:reply}]});
  const parent={},prepared={},identity={},plan={},token={},extent={},grant={};
  const scope=Object.freeze({issuerAuthority:'authority',principal:'principal',namespaceId:'namespace',environment:'fixture',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',
    resourceOrigin:server.origin,runInvocationCid:'run',taskAttempt:1,dispatchRequestCid:'dispatch',operation:'create'});
  const raw=Object.freeze({grant,scope}),controls={borrows:0,bindings:0,starts:0,settles:0,charges:[],retiredAliases:false,physical:true,transfer:1089n,responseBacking:true,responseChecks:0};
  const runtime={clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:plan}),
    clientProgramInstalledEffectManagedPlanOperation:()=>({$tag:1,_0:extent}),clientProgramInstalledEffectOperationExtentPhysical:()=>controls.physical,
    clientProgramInstalledEffectOperationExtentTransfer:()=>controls.transfer,
    clientProgramInstalledEffectOperationResponseBackingFits(original,bytes){assert.equal(this,runtime);assert.equal(original,extent);assert.equal(bytes,64);controls.responseChecks++;return controls.responseBacking;},
    clientProgramInstalledEffectOperationBorrow(){controls.borrows++;return {$tag:1,_0:token};},
    clientProgramInstalledEffectOperationStart(){controls.starts++;return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationCharge(original,bytes){assert.equal(original,token);controls.charges.push(bytes);return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationRetire(original,ack){assert.equal(original,token);assert.equal(ack,true);controls.settles++;return {$tag:1,_0:true};}};
  const run={runtime,value:parent,prepared,request:identity,operationPlan:plan,readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan};
  const control={identity:()=> 'original-grant'},journal={claim:()=>({replayed:false,grant,use:{},record:{useCid:'use',grantCid:'original-grant'}}),authorize(){},finish(){}};
  const resolveSecret=async()=> 'fixture-secret',bindings=[];
  const site=Object.freeze({runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',referenceCurrent:()=>true,
    authorizationPurpose(original){if(original!==raw)throw Object.assign(new Error('foreign original'),{code:'ForeignIssuerOriginal'});return {kind:'effect',resource:'rows'};},
    bindRunAcquisition(original,current){assert.equal(original,raw);controls.bindings++;
      const binding=openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:64,assertCurrent:current.assertCurrent});bindings.push(binding);
      return Object.freeze({credential:Object.freeze({binding,control,journal,resolveSecret,ca:server.ca,currentBeforeSend:current.observeCurrent}),close:()=>closeHttpsCredentialBinding(binding)});
    },callResource:callHttpsCredentialResource});
  t.after(()=>{for(const binding of bindings)assert.equal(closeHttpsCredentialBinding(binding),'closed');});
  const send=({authorization,credential,callResource})=>invokeScopedCredentialOperation({authorization,credential,callResource,operation:'create',
    method:'POST',path:'/create',body:'{}',maxRequestBytes:1024,maxResponseBytes:64});
  const create=(invoke=send,overrides={})=>implementation.prepareInstalledEffectCredentialChild({run,memberIndex:0,rowIndex:0,operationIndex:2,operation:'create',
    originalSite:site,originalAuthorization:raw,useId:'use',resource:'rows',purpose:'effect',runInvocationCid:'run',dispatchRequestCid:'dispatch',
    maxRequestBytes:1024,maxResponseBytes:64,assertCurrent(){},observeCurrent:async()=>{},requestsRetired:()=>controls.retiredAliases,invoke,...overrides});
  return {server,run,raw,runtime,controls,create,send,site,token};
}

test('physical atomic borrow owns current without a preceding callbackful Plan getter', async t => {
  const f = await operationFixture(t);
  let reads = 0;
  const original = f.run.readPlan;
  f.run.readPlan = function (...args) {reads++; return Reflect.apply(original, this, args);};
  const child = f.create();
  try {
    assert.equal(reads, 0);
    assert.equal(f.controls.borrows, 1);
    assert.equal(f.controls.bindings, 0);
    assert.equal(f.controls.starts, 0);
    assert.equal(f.server.seen().length, 0);
  } finally {
    f.controls.retiredAliases = true;
    assert.equal(await child.release(), true);
  }
});

test('refused physical metadata retains current failure precedence without borrowing or binding', async t => {
  for (const mode of ['current', 'foreign', 'undefined', 'extent']) {
    const f = await operationFixture(t), cause = new Error('original current refused');
    let reads = 0;
    f.controls.responseBacking = false;
    f.run.readPlan = () => {
      reads++;
      if (mode === 'current') return {$tag: 0, _0: cause};
      if (mode === 'undefined') {f.run.failure = undefined; return {$tag: 1, _0: f.run.operationPlan};}
      return {$tag: 1, _0: mode === 'foreign' ? {} : f.run.operationPlan};
    };
    let caught = false;
    try {f.create();} catch (error) {
      caught = true;
      if (mode === 'current') assert.strictEqual(error.cause, cause);
      else if (mode === 'undefined') assert.strictEqual(error, undefined);
      else assert.equal(error.code, mode === 'foreign'
        ? 'ForeignInstalledEffectManagedRun' : 'InsufficientInstalledEffectResponseBacking');
    }
    assert(caught);
    assert.equal(reads, 1);
    assert.equal(f.controls.borrows, 0);
    assert.equal(f.controls.bindings, 0);
    assert.equal(f.controls.starts, 0);
    assert.equal(f.server.seen().length, 0);
  }
});

test('a provider that omits its physical await cannot detach the same operation from capture',async t=>{
  let entered,finish;
  const observed=new Promise(yes=>{entered=yes;}),gate=new Promise(yes=>{finish=yes;});
  const f=await operationFixture(t,{reply:()=>{entered();return gate;}});
  const child=f.create(context=>{void f.send(context);return {notAResponse:true};});
  let completed=false;
  const preparing=child.prepare().then(value=>{completed=true;return value;});
  try{
    await observed;
    assert.equal(completed,false,'the original Resource call must still be inside this child');
    assert.equal(f.controls.settles,0);
  }finally{finish({body:'{}'});await preparing;f.controls.retiredAliases=true;await child.release();}
  assert.equal(f.server.seen().length,1);
});

test('physical original boundaries refuse an unfunded extent or foreign issued purpose before transport',async t=>{
  for(const mode of ['pure','short','foreign','read-purpose']){
    const f=await operationFixture(t);
    if(mode==='pure')f.controls.physical=false;
    if(mode==='short')f.controls.transfer=1088n;
    if(mode==='pure'||mode==='short'){
      assert.throws(()=>f.create(),{code:'InsufficientInstalledEffectOperationTransfer'});
      assert.equal(f.controls.borrows,0);
    }else{
      const child=f.create(undefined,mode==='foreign'?{originalAuthorization:{...f.raw}}:{purpose:'read'});
      await assert.rejects(child.prepare(),{code:mode==='foreign'?'ForeignIssuerOriginal':'ForeignInstalledEffectAuthorizationPurpose'});
      f.controls.retiredAliases=true;assert.equal(await child.release(),true);
    }
    assert.equal(f.controls.bindings,0);assert.equal(f.controls.starts,0);assert.equal(f.server.seen().length,0);
  }
});

test('failed physical charge remains pending after the same actual binding has stopped',async t=>{
  const f=await operationFixture(t),primary=new Error('original response charge refused');
  let calls=0;
  f.runtime.clientProgramInstalledEffectOperationCharge=(original,bytes)=>{
    if(++calls===1){f.controls.charges.push(bytes);return {$tag:1,_0:undefined};}
    return {$tag:0,_0:primary};
  };
  const child=f.create();
  await assert.rejects(child.prepare(),error=>error.code==='MoonBitHostFailure'&&error.cause===primary);
  assert.deepEqual(f.controls.charges,[2n]);assert.equal(f.server.seen().length,1);
  f.controls.retiredAliases=true;
  assert.equal(await child.release(),false);assert.equal(child.status().pending,true);assert.equal(f.controls.settles,0);
});

test('a second physical call refuses while the original call stays joined through failure',async t=>{
  let entered,finish;
  const observed=new Promise(yes=>{entered=yes;}),gate=new Promise(yes=>{finish=yes;});
  const f=await operationFixture(t,{reply:()=>{entered();return gate;}});
  const child=f.create(context=>{f.send(context);return f.send(context);});
  let completed=false;
  const preparing=assert.rejects(child.prepare(),{code:'InstalledEffectOperationAlreadyUsed'}).then(()=>{completed=true;});
  try{
    await observed;assert.equal(completed,false);assert.equal(f.controls.starts,1);assert.equal(f.server.seen().length,1);
  }finally{finish({body:'{}'});await preparing;f.controls.retiredAliases=true;await child.release();}
});

test('an asynchronous current fence remains joined before binding or physical start',async t=>{
  const f=await operationFixture(t);let finish;
  const original=new Promise(yes=>{finish=yes;});
  const child=f.create(undefined,{assertCurrent:()=>original});
  let completed=false;
  const preparing=assert.rejects(child.prepare(),{code:'InvalidInstalledEffectCurrentFence'}).then(()=>{completed=true;});
  await new Promise(setImmediate);
  assert.equal(completed,false);assert.equal(f.controls.bindings,0);assert.equal(f.controls.starts,0);
  f.controls.retiredAliases=true;assert.equal(await child.release(),false);
  finish();await preparing;
  assert.equal(await child.retry(),true);assert.equal(f.controls.settles,1);assert.equal(f.server.seen().length,0);
});

test('native current fence ignores hostile public then and retains the same capture until settlement', async t => {
  for (const kind of ['getter', 'method']) {
    const f = await operationFixture(t);
    let finish, publicCalls = 0;
    const original = new Promise(resolve => {finish = resolve;});
    const hostile = () => {publicCalls++; throw new Error('not the original current task');};
    Object.defineProperty(original, 'then', kind === 'getter' ? {get: hostile} : {value: hostile});
    const child = f.create(undefined, {assertCurrent: () => original}), children = [];
    const observed = prepareInstalledRowCaptureChild({children, create: () => child})
      .then(value => ({value}), error => ({error}));
    try {
      await new Promise(setImmediate);
      f.controls.retiredAliases = true;
      assert.equal(await child.release(), false, kind);
      await children[0].prepared.release();
      assert.equal(children[0].prepared.status().pending, true);
      assert.equal(f.controls.settles, 0); assert.equal(publicCalls, 0);
    } finally {finish(); await observed;}
    assert.equal((await observed).error?.code, 'InvalidInstalledEffectCurrentFence');
    await children[0].prepared.retry();
    assert.equal(children[0].prepared.status().pending, false);
    assert.equal(f.controls.settles, 1); assert.equal(f.controls.bindings, 0);
    assert.equal(f.server.seen().length, 0);
  }
});

test('native binding close ignores hostile public then and cannot repeat or retire before its original settles', async t => {
  for (const kind of ['getter', 'method']) {
    const f = await operationFixture(t);
    let finish, publicCalls = 0, closes = 0, settled = false;
    const original = new Promise(resolve => {finish = () => {settled = true; resolve();};});
    const hostile = () => {publicCalls++; throw new Error('not the original close task');};
    Object.defineProperty(original, 'then', kind === 'getter' ? {get: hostile} : {value: hostile});
    const primary = new Error('original provider prefix');
    const site = Object.freeze({...f.site, bindRunAcquisition(...args) {
      const binding = Reflect.apply(f.site.bindRunAcquisition, f.site, args);
      return Object.freeze({credential: binding.credential, close() {
        closes++; return settled ? binding.close() : original;
      }});
    }});
    const child = f.create(() => {throw primary;}, {originalSite: site});
    await assert.rejects(child.prepare(), error => error === primary);
    f.controls.retiredAliases = true;
    const observed = Promise.resolve().then(() => child.release()).then(value => ({value}), error => ({error}));
    try {
      await new Promise(setImmediate);
      assert.equal(f.controls.settles, 0);
      assert.equal(publicCalls, 0);
      assert.equal(child.status().pending, true);
      assert.equal(closes, 1);
    } finally {finish(); await observed;}
    assert.deepEqual(await observed, {value: false});
    assert.equal(await child.retry(), true);
    assert.equal(closes, 2); assert.equal(f.controls.settles, 1);
    assert.equal(f.server.seen().length, 0);
  }
});

test('unobservable native current and close tasks remain in the same original child custody', async t => {
  for (const phase of ['current', 'close']) {
    const f = await operationFixture(t);
    let finish, closes = 0;
    const original = new Promise(resolve => {finish = resolve;});
    Object.defineProperty(original, 'constructor', {get() {throw new Error('unavailable original species');}});
    const primary = new Error('original provider prefix');
    const site = Object.freeze({...f.site, bindRunAcquisition(...args) {
      const binding = Reflect.apply(f.site.bindRunAcquisition, f.site, args);
      return Object.freeze({credential: binding.credential, close() {closes++; return original;}});
    }});
    const child = phase === 'current' ? f.create(undefined, {assertCurrent: () => original})
      : f.create(() => {throw primary;}, {originalSite: site});
    try {
      await assert.rejects(child.prepare(), error => phase === 'current'
        ? error.code === 'InvalidInstalledEffectCurrentFence' : error === primary);
      f.controls.retiredAliases = true;
      assert.equal(await child.release(), false);
    } finally {finish();}
    await new Promise(setImmediate);
    assert.equal(await child.retry(), false);
    assert.equal(child.status().pending, true); assert.equal(f.controls.settles, 0);
    assert.equal(closes, phase === 'close' ? 1 : 0);
    assert.equal(f.server.seen().length, 0);
  }
});


// Capacity fit is an explicit native port here. The shared original child must
// consume that exact extent check before any borrow, binding or physical use.
test('response backing shortage refuses the original physical extent before borrow or binding',async t=>{
  const f=await operationFixture(t);f.controls.responseBacking=false;
  let child;
  try{
    assert.throws(()=>{child=f.create();},{code:'InsufficientInstalledEffectResponseBacking'});
    assert.equal(f.controls.responseChecks,1);assert.equal(f.controls.borrows,0);
    assert.equal(f.controls.bindings,0);assert.equal(f.controls.starts,0);
    assert.equal(f.controls.settles,0);assert.equal(f.server.seen().length,0);
  }finally{if(child!==undefined){f.controls.retiredAliases=true;await child.release();}}
});

test('response backing checks the same installed HTTP header bound before borrowing its original occurrence', async t => {
  const f = await operationFixture(t);
  let checks = 0;
  f.runtime.clientProgramInstalledEffectOperationResponseBackingFits = (original, bytes, headerBytes, readQuantum) => {
    assert.equal(readQuantum, 16384);
    assert.strictEqual(original, f.runtime.clientProgramInstalledEffectManagedPlanOperation()._0);
    assert.equal(bytes, 64); assert.equal(headerBytes, maxHeaderSize); checks++;
    return true;
  };
  const child = f.create();
  assert.equal(checks, 1); assert.equal(f.controls.borrows, 1);
  assert.equal(f.controls.bindings, 0); assert.equal(f.controls.starts, 0);
  f.controls.retiredAliases = true;
  assert.equal(await child.release(), true);
});

// A Describe is a member occurrence, even when a member contains many rows.
// Its original Plan selector and atomic borrower must select the SAME domain.
test('member credential occurrence selects and borrows its original member slot before TLS', async t => {
  const f = await operationFixture(t), selections = [], borrows = [];
  const select = f.runtime.clientProgramInstalledEffectManagedPlanOperation;
  const borrow = f.runtime.clientProgramInstalledEffectOperationBorrow;
  f.runtime.clientProgramInstalledEffectManagedPlanOperation = function (...args) {
    assert.equal(this, f.runtime);
    selections.push(args);
    assert.deepEqual(args.slice(1), [2, false, 3, 'create']);
    return Reflect.apply(select, this, args);
  };
  f.runtime.clientProgramInstalledEffectOperationBorrow = function (...args) {
    assert.equal(this, f.runtime);
    borrows.push(args);
    assert.deepEqual(args.slice(4), [2, false, 3, 0, 'create']);
    return Reflect.apply(borrow, this, args);
  };
  const children = [];
  let child;
  try {
    const response = await prepareInstalledRowCaptureChild({children, create() {
      child = f.create(f.send, {memberIndex: 2, perRow: false, operationIndex: 3});
      return child;
    }});
    assert.equal(response.body.toString(), '{}');
    assert.equal(selections.length, 1);
    assert.equal(borrows.length, 1);
    assert.equal(f.controls.bindings, 1);
    assert.equal(f.controls.starts, 1);
    assert.equal(f.server.seen().length, 1);
    assert.equal(await child.release(), false);
    assert.equal(f.controls.settles, 0);
  } finally {
    f.controls.retiredAliases = true;
    if (child !== undefined) assert.equal(await child.retry(), true);
  }
  assert.equal(f.controls.settles, 1);
  assert.equal(child.status().pending, false);
});

test('invalid credential occurrence domain refuses before selection, borrow or binding', async t => {
  const f = await operationFixture(t);
  let selections = 0;
  f.runtime.clientProgramInstalledEffectManagedPlanOperation = () => {selections++; throw new Error('must not select');};
  for (const perRow of [undefined, null, 0, 'member', {}]) {
    // Omission preserves the existing row default; explicit undefined shares
    // the JS default and is covered by the old row operation tests instead.
    if (perRow === undefined) continue;
    assert.throws(() => f.create(f.send, {perRow}), {code: 'InvalidInstalledEffectCredentialOperation'});
  }
  assert.equal(selections, 0);
  assert.equal(f.controls.borrows, 0);
  assert.equal(f.controls.bindings, 0);
  assert.equal(f.server.seen().length, 0);
});

test('same original TLS response grows before decoding and keeps its failed child until original retirement',async t=>{
  for(const refused of [false,true]){
    const f=await operationFixture(t,{reply:()=>({body:'{"ok":true}'})}),extent={},events=[],failure=new Error('actual body capacity refused');
    f.runtime.clientProgramInstalledEffectOperationInputBegin=function(token,input){
      assert.equal(this,f.runtime);assert.equal(input,extent);events.push('grow');
      if(refused)throw failure;return {$tag:1,_0:undefined};
    };
    f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
      assert.strictEqual(this,f.runtime);assert.strictEqual(original,f.token);
      assert.equal(f.controls.settles,0);events.push('projection-complete');return {$tag:1,_0:undefined};
    };
    const child=f.create(async context=>{
      const response=await f.send(context);events.push('decode');return response;
    },{responseExtent(bytes,originalBody){assert.equal(bytes,11);assert(Buffer.isBuffer(originalBody));assert.equal(originalBody.toString(),'{"ok":true}');events.push('input');return extent;}});
    if(refused)await assert.rejects(child.prepare(),error=>error===failure);
    else assert.equal((await child.prepare()).body.toString(),'{"ok":true}');
    assert.deepEqual(events,refused?['input','grow']:['input','grow','decode','projection-complete']);
    assert.equal(f.controls.starts,1);assert.equal(f.controls.borrows,1);
    assert.deepEqual(f.controls.charges,[2n,11n]);assert.equal(f.server.seen().length,1);
    assert.equal(await child.release(),false);
    f.controls.retiredAliases=true;assert.equal(await child.release(),true);
    assert.equal(f.controls.settles,1);
  }
});


test('physical projection workspace waits for same flight and refuses failed output without cleanup ACK',async t=>{
  for(const mode of ['unjoined','refused','completion-refused']){
    let releaseResponse,observedResponse;
    const seen=new Promise(yes=>{observedResponse=yes;});
    const f=await operationFixture(t,{reply:async()=>{observedResponse();await new Promise(yes=>{releaseResponse=yes;});return {body:'{}'};}});
    const failure=new Error('original projection failure');let completions=0;
    f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1,_0:undefined});
    f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
      assert.equal(this,f.runtime);assert.equal(original,f.token);completions++;
      if(mode==='completion-refused')throw failure;return {$tag:1,_0:undefined};
    };
    const child=f.create(async context=>{
      if(mode==='unjoined'){void f.send(context);await seen;return {sameFlightPending:true};}
      const response=await f.send(context);if(mode==='refused')throw failure;return response;
    },{responseExtent:()=>({})});
    let terminal=false;
    const prepared=child.prepare().then(value=>({value}),error=>({error})).finally(()=>{terminal=true;});
    try{await seen;await new Promise(setImmediate);assert.equal(terminal,false);assert.equal(completions,0);
      assert.equal(child.status().pending,true);assert.equal(f.controls.settles,0);
    }finally{releaseResponse();}
    const result=await prepared;
    if(mode==='unjoined'){assert.ifError(result.error);assert.equal(result.value.sameFlightPending,true);}
    else assert.strictEqual(result.error,failure);
    assert.equal(completions,mode==='refused'?0:1);
    assert.equal(child.status().pending,true);assert.equal(f.controls.settles,0);
    assert.equal(await child.release(),false);
    f.controls.retiredAliases=true;assert.equal(await child.retry(),true);
    assert.equal(f.controls.settles,1);
  }
});


test('response projection completion keeps the original preparing latch through reentrant release',async t=>{
  const f=await operationFixture(t);let child,returned,completions=0;
  f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1,_0:undefined});
  f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
    assert.equal(this,f.runtime);assert.equal(original,f.token);completions++;
    f.controls.retiredAliases=true;returned=child.release();assert.equal(returned,false);
    assert.equal(f.controls.settles,0);return {$tag:1,_0:undefined};
  };
  child=f.create(undefined,{responseExtent:()=>({})});
  await child.prepare();assert.equal(completions,1);assert.equal(returned,false);
  assert.equal(f.controls.settles,0);assert.equal(child.status().pending,true);
  assert.equal(await child.retry(),true);assert.equal(f.controls.settles,1);
});

test('same response Source staging precedes grow and stays on the original child through every failure',async t=>{
  for(const mode of ['success','preflight','grow','consumer']){
    const f=await operationFixture(t,{reply:()=>({body:'{"ok":true}'})});
    const events=[],failure=new Error('original '+mode),geometry=Object.freeze([11]),extent={};
    let originalBody;
    const responsePreparation=Object.freeze({
      prepare(body){originalBody=body;events.push('preflight');if(mode==='preflight')throw failure;return geometry;},
      retire(){events.push('retire-source');},
    });
    f.runtime.clientProgramInstalledEffectOperationInputBegin=function(original,input){
      assert.strictEqual(original,f.token);assert.strictEqual(input,extent);events.push('grow');
      if(mode==='grow')throw failure;return {$tag:1,_0:undefined};
    };
    f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
      assert.strictEqual(original,f.token);events.push('complete');return {$tag:1,_0:undefined};
    };
    const child=f.create(async context=>{
      const response=await f.send(context);assert.strictEqual(response.body,originalBody);
      events.push('consumer');if(mode==='consumer')throw failure;return response;
    },{responsePreparation,responseExtent(bytes,body,data){
      assert.equal(bytes,11);assert.strictEqual(body,originalBody);assert.strictEqual(data,geometry);
      events.push('extent');return extent;
    }});
    if(mode==='success')await child.prepare();else await assert.rejects(child.prepare(),error=>error===failure);
    assert.deepEqual(events,mode==='preflight'?['preflight']:mode==='grow'?['preflight','extent','grow']:
      mode==='consumer'?['preflight','extent','grow','consumer']:['preflight','extent','grow','consumer','complete']);
    assert.equal(await child.release(),false);assert.equal(events.includes('retire-source'),false);
    assert.equal(f.controls.settles,0);assert.equal(f.controls.borrows,1);assert.equal(f.controls.starts,1);
    f.controls.retiredAliases=true;assert.equal(await child.retry(),true);
    assert.equal(events.at(-1),'retire-source');assert.equal(f.controls.settles,1);
    assert.equal(await child.retry(),true);assert.equal(events.filter(e=>e==='retire-source').length,1);
  }
});

test('response Source hooks require the original extent and synchronous own methods before borrowing',async t=>{
  const f=await operationFixture(t);
  for(const overrides of [
    {responsePreparation:{prepare(){},retire(){}}},
    {responseExtent:()=>({}),responsePreparation:{async prepare(){},retire(){}}},
    {responseExtent:()=>({}),responsePreparation:new Proxy({prepare(){},retire(){}},{})},
  ])assert.throws(()=>f.create(undefined,overrides));
  assert.equal(f.controls.borrows,0);assert.equal(f.controls.bindings,0);assert.equal(f.server.seen().length,0);
});

// Same real TLS/Credential/child, explicit Core ports. Core reservation behavior
// is separately checked against the real Ledger; these assert disposal order.
test('Unit schema projection retires its Reader before the same admitted remainder while raw cleanup stays pending', async t => {
  const f=await operationFixture(t), events=[];
  f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1});
  f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=()=>assert.fail('Not the full-output completion');
  f.runtime.clientProgramInstalledEffectOperationDiscardedResponseProjectionComplete=original=>{
    assert.equal(original,f.token);assert.deepEqual(events,['prepare','project','retire']);
    assert.equal(f.controls.settles,0);events.push('reduce');return {$tag:1};
  };
  const child=f.create(async context=>{await f.send(context);events.push('project');return undefined;},{
    discardResponseProjection:true,responseExtent:()=>({}),
    responsePreparation:{prepare(){events.push('prepare');return [];},retire(){events.push('retire');}},
  });
  assert.equal(await child.prepare(),undefined);
  assert.deepEqual(events,['prepare','project','retire','reduce']);
  assert.equal(child.status().pending,true);assert.equal(await child.release(),false);
  f.controls.retiredAliases=true;assert.equal(await child.retry(),true);
  assert.deepEqual(events,['prepare','project','retire','reduce']);
  assert.equal(f.controls.settles,1);assert.deepEqual(f.controls.charges,[2n,2n]);
});
test('failed non-Unit or unretired Reader projection cannot return its retained backing', async t => {
  for(const mode of ['result','project','retire']){
    const f=await operationFixture(t), cause=new Error('original failure');let retired=0,reduced=0;
    f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1});
    f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=()=>assert.fail();
    f.runtime.clientProgramInstalledEffectOperationDiscardedResponseProjectionComplete=()=>{reduced++;return {$tag:1};};
    const child=f.create(async context=>{await f.send(context);if(mode==='project')throw cause;return mode==='result'?{}:undefined;},{
      discardResponseProjection:true,responseExtent:()=>({}),responsePreparation:{prepare:()=>[],retire(){retired++;if(mode==='retire')throw cause;}},
    });
    await assert.rejects(child.prepare(),mode==='result'?{code:'InvalidInstalledEffectDiscardedProjection'}:error=>error===cause);
    assert.equal(reduced,0);assert.equal(retired,mode==='retire'?1:0);
    assert.equal(child.status().pending,true);assert.equal(f.controls.settles,0);
    f.controls.retiredAliases=true;
    if(mode==='retire')assert.throws(()=>child.release(),error=>error===cause);
    else assert.equal(await child.release(),true);
  }
});
test('Unit projector disposal followed by changed current keeps the original full reservation and physical child', async t => {
  const f=await operationFixture(t),cause=new Error('current changed');let disposed=false,reduced=0;
  f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1});
  f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=()=>assert.fail();
  f.runtime.clientProgramInstalledEffectOperationDiscardedResponseProjectionComplete=()=>{reduced++;return {$tag:1};};
  const child=f.create(async context=>{await f.send(context);},{discardResponseProjection:true,responseExtent:()=>({}),
    assertCurrent(){if(disposed)throw cause;},responsePreparation:{prepare:()=>[],retire(){disposed=true;}}});
  await assert.rejects(child.prepare(),error=>error===cause);
  assert.equal(reduced,0);assert.equal(f.controls.settles,0);assert.equal(child.status().pending,true);
  disposed=false;f.controls.retiredAliases=true;assert.equal(await child.release(),true);
});


test('empty header original is checked before actual TLS and success keeps body through same completion and cleanup',async t=>{
  const f=await operationFixture(t,{reply:()=>({headers:{etag:'"original"','x-fixture':'received'},body:'{"ok":true}'})});
  const events=[],extent={};
  f.runtime.clientProgramInstalledEffectOperationResponseHeadersRequire=function(original,names,limit){
    assert.equal(this,f.runtime);assert.equal(original,f.token);assert.deepEqual(names,[]);
    assert(Object.isFrozen(names));assert.equal(limit,maxHeaderSize);assert.equal(f.server.seen().length,0);
    events.push('empty-before-request');return {$tag:1,_0:undefined};
  };
  f.runtime.clientProgramInstalledEffectOperationInputBegin=function(original,input){
    assert.equal(original,f.token);assert.equal(input,extent);events.push('grow');return {$tag:1,_0:undefined};
  };
  f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
    assert.equal(original,f.token);assert.equal(f.controls.settles,0);
    events.push('complete-original');return {$tag:1,_0:undefined};
  };
  const child=f.create(async context=>{
    const response=await f.send(context);assert.deepEqual(response.headers,[]);
    assert.equal(response.body.toString(),'{"ok":true}');events.push('consumer');return response;
  },{responseExtent:()=>extent});
  const response=await child.prepare();
  assert.deepEqual(events,['empty-before-request','grow','consumer','complete-original']);
  assert.equal(f.server.seen().length,1);assert.equal(response.body.toString(),'{"ok":true}');
  assert.equal(await child.release(),false);assert.equal(f.controls.settles,0);
  f.controls.retiredAliases=true;assert.equal(await child.retry(),true);assert.equal(f.controls.settles,1);
});

test('empty header mismatch current and failed consumers preserve full original duty without success completion',async t=>{
  for(const mode of ['foreign','current','consumer','completion']){
    const f=await operationFixture(t),cause=new Error('original '+mode),extent={};
    let checks=0,completions=0;
    f.runtime.clientProgramInstalledEffectOperationResponseHeadersRequire=function(original,names){
      assert.equal(original,f.token);checks++;assert.equal(f.server.seen().length,0);
      if(mode==='foreign'){assert.deepEqual(names,['etag']);throw cause;}
      assert.deepEqual(names,[]);if(mode==='current')throw cause;return {$tag:1,_0:undefined};
    };
    f.runtime.clientProgramInstalledEffectOperationInputBegin=()=>({$tag:1,_0:undefined});
    f.runtime.clientProgramInstalledEffectOperationResponseProjectionComplete=function(original){
      assert.equal(original,f.token);completions++;throw cause;
    };
    const child=f.create(async context=>{
      const response=mode==='foreign'?await invokeScopedCredentialOperation({...context,operation:'create',
        method:'POST',path:'/create',body:'{}',responseHeaders:['etag'],maxRequestBytes:1024,maxResponseBytes:64}):await f.send(context);
      if(mode==='consumer')throw cause;return response;
    },{responseExtent:()=>extent});
    await assert.rejects(child.prepare(),error=>error===cause);
    assert.equal(checks,1);assert.equal(completions,mode==='completion'?1:0);
    assert.equal(f.server.seen().length,['foreign','current'].includes(mode)?0:1);
    assert.equal(await child.release(),false);assert.equal(f.controls.settles,0);
    f.controls.retiredAliases=true;assert.equal(await child.retry(),true);assert.equal(f.controls.settles,1);
  }
});
