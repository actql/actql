import assert from 'node:assert/strict';
import test from 'node:test';
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
  return {server,run,raw,runtime,controls,create,send};
}

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
