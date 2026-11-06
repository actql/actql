import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';

// Actual thin request caller with fixed nominal/Core borrower ports. A Source
// selection is DATA; actual Query/material/module constructors remain inside
// the same backed Request. This component grants no physical Source or Run.
function binding(file,name,ports,{property=false}={}){
  const source=readFileSync(new URL(file,import.meta.url),'utf8');let node;
  const walk=n=>{if(!n||typeof n!=='object')return;
    if(property?n.type==='Property'&&n.key?.name===name:n.type==='VariableDeclarator'&&n.id?.name===name){assert(!node);node=property?n:n.init;}
    for(const v of Object.values(n)){if(Array.isArray(v))v.forEach(walk);else if(v&&typeof v==='object')walk(v);}};
  walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert(node,name);
  const helpers = file === './ordinary-source-managed.mjs' ? source.slice(source.indexOf('  function constructRequestDomain('), source.indexOf('  const view = Object.freeze({')) : '';
  return Function(...Object.keys(ports),property?`const pendingRunRegistrations=new Set();${helpers}return ({${source.slice(node.start,node.end)}}).${name};`:
    `return (${source.slice(node.start,node.end)});`)(...Object.values(ports));
}
const fail=code=>{throw Object.assign(new Error(code),{code});},ok=value=>({$tag:1,_0:value});
function fixture(family){
  const prepared={},identity={},keyed={},occurrence={},calls=[],selections=[],identities=new WeakMap();let issued=0,queries=0;
  const reference='connector://original/rows',adapter={prepareKeyed(){},managedWholeSourceCapacity(){}};
  const moon={clientProgramAcquisitionCount:p=>{assert.equal(p,prepared);return 2;},
    clientProgramSelectSingleKeyedAcquisition:()=>ok(family==='content'?keyed:undefined),
    clientProgramKeyedDirectAcquisitionCoordinates:k=>{assert.equal(k,keyed);return{_0:0,_1:0};},
    clientProgramSourceFreeInputIntentCid:()=> 'intent',clientProgramRequestIdentity(p,a,id,intent){
      assert.deepEqual([p,a,id,intent],[prepared,'authority','request','intent']);issued++;return identity;},
    clientProgramSelectInstalledSourceInput(p,r,stage,input){assert.deepEqual([p,r,input],[prepared,identity,0]);
      const selected={stage};selections.push(selected);return ok(selected);},
    clientProgramSelectedSourceInputKind:s=>{assert(selections.includes(s));return 'query';},
    clientProgramSelectedSourceInputRef:s=>{assert(selections.includes(s));return reference;},
    clientProgramPrepareLocalQueryRequirement(){queries++;return ok({});},clientProgramQueryRequirementSourceRef:()=>reference,
    clientProgramKeyedAcquisitionSourceEvidenceFacts:()=>ok([reference]),
    clientProgramComposedInferOccurrences:()=>ok(family==='model'?[occurrence]:[]),
    clientProgramResultCount:()=>1,clientProgramResultName:()=> 'rows'};
  const sourceCoordinates = Object.freeze([Object.freeze([0,0,0]), Object.freeze([1,0,1])]);
  const preparation={managedModelSourceCoordinates(runtime,p){
    assert.equal(runtime,moon);assert.equal(p,prepared);
    return family==='model'?sourceCoordinates:undefined;
  },selectManagedDomainSourceInput(runtime,p,r,stage,index){assert.equal(runtime,moon);
    calls.push([p,r,stage,index]);return checked(moon.clientProgramSelectInstalledSourceInput(p,r,stage,index));}};
  const ports={moon,preparation,prepareSubmit:{assertOwned:p=>assert.equal(p,prepared),kindOf:()=> 'effect_free'},
    sourceProfile:{},sourceFreeRequestIdentities:identities,earlyContentPlans:new WeakMap(),inferSelections:new WeakMap(),
    authorityScopeCid:'authority',checked,runtimeIsOkRequired:v=>v.$tag===1,runtimeField:(v,n)=>v['_'+n],
    runtimeOptionalField:(v,n)=>v?.['_'+n],runtimeTag:()=>undefined,clientOperationError:(code,cause)=>Object.assign(new Error(code,{cause}),{code}),
    installedSourceFor:()=>adapter,installedSourceReadBindings:()=>[reference],prepareInferSelection(){},diagnostic(){},
    registry:'registry',values:'values',fragment:'fragment',ordered:'ordered'};
  ports.originalSourceFreeRequest=binding('./embedded-local.mjs','originalSourceFreeRequest',ports);
  const request=binding('./embedded-local.mjs','requestOf',ports);
  return{prepared,identity,calls,selections,preparation,moon,request:()=>request({preparedProgram:prepared,requestId:'request'}),
    sourceCoordinates,counts:()=>({issued,queries}),installSelection:fn=>{preparation.selectManagedDomainSourceInput=fn;},
    installCoordinates:fn=>{preparation.managedModelSourceCoordinates=fn;}};
}
for(const family of ['model','content'])test(`same Request ${family} caller uses the backed nominal selection without another unowned Query constructor`,()=>{
  const f=fixture(family),r=f.request();assert.equal(r.requested,f.identity);
  assert.deepEqual(f.counts(),{issued:1,queries:0});assert.equal(f.calls.length,2);
  assert.equal(f.calls[0][0],f.prepared);assert.equal(f.calls[0][1],f.identity);
});

function managedFixture(family){
  const f=fixture(family),sdkRequest={},holder={},parent={},receipt={},events=[];
  const runs=new WeakMap();
  const state={original:{},prepared:f.prepared,compilationKind:'effect_free',compilationFamily:family,
    holder,parent,context:{runtime:f.moon}},producer={receipt,preparation:state};
  let wrongHolder=false,decline=false;
  f.moon.clientProgramPreparationBorrowRead=h=>{assert.equal(h,holder);events.push('read-original-holder');return wrongHolder?{}:f.prepared;};
  const method=binding('./ordinary-source-managed.mjs','selectDomainSourceInput',{
    current(){events.push('current');if(decline)throw decline;},
    producerForRequest:r=>{assert.equal(r,sdkRequest);return producer;},fail,checked,runs,
  },{property:true});
  let coordinateReads=0;
  f.moon.clientProgramRequestModelDirectSourceCoordinates=function(p,r){
    assert.equal(this,f.moon);assert.equal(p,parent);assert.equal(r,receipt);
    coordinateReads++;return ok(f.sourceCoordinates);
  };
  const coordinates=binding('./ordinary-source-managed.mjs','modelSourceCoordinates',{
    current(){events.push('current');if(decline)throw decline;},
    producerForRequest:r=>{assert.equal(r,sdkRequest);return producer;},fail,checked,
  },{property:true});
  const manager={selectDomainSourceInput(...args){assert.equal(this,manager);return method(...args);},
    modelSourceCoordinates(...args){assert.equal(this,manager);return coordinates(...args);}};
  f.installCoordinates(binding('./embedded-local.mjs','managedModelSourceCoordinates',{
    sourceManaged:manager,computeManaged:undefined,moon:f.moon,originals:{},
    originalSourceManagedHostRequest:(_o,p)=>{assert.equal(p,f.prepared);return sdkRequest;},
    clientOperationError:code=>Object.assign(new Error(code),{code}),
  },{property:true}));
  const host=binding('./embedded-local.mjs','selectManagedDomainSourceInput',{
    sourceManaged:manager,computeManaged:undefined,moon:f.moon,originals:{},
    originalSourceManagedHostRequest:(_o,p)=>{assert.equal(p,f.prepared);return sdkRequest;},
    clientOperationError:code=>Object.assign(new Error(code),{code}),
  },{property:true});
  f.installSelection(host);
  return{...f,state,producer,events,holder,parent,runs,coordinateReads:()=>coordinateReads,
    adopt(){state.adopting=true;const run={prepared:f.prepared,request:sdkRequest,producer,original:state.original,value:{}};runs.set(f.prepared,run);return run;},
    foreign(){wrongHolder=true;},decline(cause){decline=cause;}};
}

test('fixed Host and manager select from the same actual Model or Content Core borrower before complete Query construction',()=>{
  for(const family of ['model','content']){
    const f=managedFixture(family),select=f.moon.clientProgramSelectInstalledSourceInput;
    f.moon.clientProgramSelectInstalledSourceInput=function(...args){assert.equal(this,f.moon);
      assert.equal(f.state.preparing,true);assert.equal(f.state.parent,f.parent);
      assert.throws(()=>f.preparation.selectManagedDomainSourceInput(f.moon,f.prepared,f.identity,0,0),{code:'ForeignInstalledSourceProducer'});
      return Reflect.apply(select,this,args);};
    assert.equal(f.request().requested,f.identity);assert.deepEqual(f.counts(),{issued:1,queries:0});
    assert.equal(f.selections.length,2);assert.equal(f.state.holder,f.holder);assert.equal(f.state.preparing,false);
    assert.equal(f.state.preparationFailed,undefined);
    assert.equal(f.coordinateReads(),family==='model'?1:0);
  }
});

test('fixed domain preflight preserves original refusal and pure Query path without a missing-port or foreign-holder fallback',()=>{
  const f=managedFixture('content'),primary=new Error('same original current refusal');
  const select=f.moon.clientProgramSelectInstalledSourceInput;
  f.moon.clientProgramSelectInstalledSourceInput=function(...args){f.decline(primary);return Reflect.apply(select,this,args);};
  assert.throws(f.request,e=>e.code==='ClientProgramUnsupported'&&e.cause===primary);
  assert.equal(f.state.preparationFailure,primary);assert.equal(f.state.preparing,false);
  assert.deepEqual(f.counts(),{issued:1,queries:0});assert.equal(f.selections.length,1);
  const foreign=managedFixture('model');foreign.foreign();
  assert.throws(foreign.request,e=>e.code==='ForeignInstalledSourceProducer'&&e.cause===undefined);assert.equal(foreign.selections.length,0);
  assert.equal(foreign.counts().queries,0);
  const pure=managedFixture('pure');pure.request();assert.equal(pure.counts().queries,2);
  const missing=fixture('content');missing.installSelection(undefined);
  assert.throws(missing.request,e=>e.cause?.code==='NodeManagedRunRuntimeUnavailable');assert.equal(missing.counts().queries,0);
});


test('post-adoption Request source preflight revisits only its same original live Model or Content Run without Query or parent reissue',()=>{
  for(const family of ['model','content']){
    const f=managedFixture(family);f.request();const run=f.adopt();
    f.request();assert.deepEqual(f.counts(),{issued:1,queries:0});assert.equal(f.selections.length,4);
    assert.equal(f.state.adopting,true);assert.equal(f.state.preparing,false);
    assert.equal(f.coordinateReads(),family==='model'?1:0,'same original coordinates are retained across adoption');
    const select=f.moon.clientProgramSelectInstalledSourceInput;
    f.moon.clientProgramSelectInstalledSourceInput=function(...args){const value=Reflect.apply(select,this,args);
      f.runs.set(f.prepared,{...run});return value;};
    assert.throws(f.request,e=>e.cause?.code==='ForeignInstalledSourceProducer');
    assert.equal(f.counts().queries,0);assert.equal(f.state.preparationFailure.code,'ForeignInstalledSourceProducer');
  }
});
