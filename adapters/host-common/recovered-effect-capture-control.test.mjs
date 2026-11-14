// Exact private adapter membership/projection ports. Core admission/funding is
// explicit here; actual Core and Store cases are selected separately.
import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';
const ok=value=>({$tag:1,_0:value});
const cid=i=>'sha256:'+i.toString(16).padStart(64,'0');
function fixture({admissionFailure}={}){
  const parent={},input={},request={},prepared={},calls=[];
  const limits={maxWireBytes:1048576,maxNodes:65536,maxDepth:64};
  const original={name:'captured_run',wire:'opaque original wire',identity:cid(1)};
  const payloads=Array.from({length:4097},(_,i)=>cid(i+10));
  const moon={
    strategyRemoteManagedOutputEvidenceKind:()=> 'fixture metadata',
    strategyPublicationAdmit:(name,wire)=>ok({name,wire,identity:cid(2)}),
    strategyPublicationContractName:v=>v.name,
    strategyPublicationContractIdentityField:()=> 'cid',
    strategyPublicationContractIdentity:v=>v.identity,
    strategyPublicationContractJson:v=>v.wire,
    strategyRunEvidenceAdmit:(name,wire)=>ok({name,wire,identity:cid(3)}),
    strategyRunEvidenceName:v=>v.name,
    strategyRunEvidenceIdentity:v=>v.identity,
    strategyRunEvidenceJson:v=>v.wire,
    strategyAdmitEffectComputationPreview:()=>ok({originalPreview:true}),
    clientProgramAdmitRequestEffectCapturedRun(p,i,r,d,wire){
      assert.equal(p,parent);assert.equal(i,input);assert.equal(r,request);assert.equal(d.name,'run_definition');
      assert.equal(wire,original.wire);calls.push('admit');if(admissionFailure!==undefined)throw admissionFailure;return ok(prepared);
    },
    clientProgramRecoveredEffectCapturedRunContract(p){assert.equal(p,prepared);return original;},
    clientProgramRecoveredEffectCapturedRunLimits(p){assert.equal(p,prepared);return {_0:2000000,_1:100000,_2:64};},
    clientProgramRecoveredEffectCapturedRunSchemas(p){assert.equal(p,prepared);calls.push('schemas');return [{_0:cid(3),_1:'{"original":true}'}];},
    clientProgramRecoveredEffectCapturedRunPayloads(p){assert.equal(p,prepared);calls.push('payloads');return payloads;},
  };
  const control=runtimeCore(moon).publicationControl;
  const definition=control.admit('run_definition','{}',limits);
  return {control,moon,parent,input,request,definition,original,prepared,payloads,calls,limits,
    admit(){return control.admitRecoveredEffectCapturedRun(parent,input,request,definition,original.wire,limits);}};
}

test('recovered schema and4097 payload projections use exact prepared DATA without reparsing wire',()=>{
  const f=fixture(),captured=f.admit();
  assert.equal(f.admit(),captured);
  assert.deepEqual(f.control.capturedEffectDependencySchemas(captured),[{cid:cid(3),wire:'{"original":true}'}]);
  assert.throws(()=>f.control.capturedEffectDependencySchemas({...captured}),/Foreign publication contract/);
  const bindings=f.payloads.map((artifact_cid,i)=>({artifact_cid,physical_cid:cid(i+5000),byte_count:1}));
  assert.equal(f.control.capturedEffectDependencyPayloadBindings(captured,bindings).length,4097);
  assert.throws(()=>f.control.capturedEffectDependencyPayloadBindings(captured,bindings.slice(1)),/IncompleteEffectDependencyPayloadBindings/);
  assert.throws(()=>f.control.capturedEffectDependencyPayloadBindings(captured,[bindings[0],...bindings]),/InvalidEffectDependencyPayloadBindings/);
  f.control.retireRecoveredEffectCapturedRun(captured);
  assert.throws(()=>f.control.retireRecoveredEffectCapturedRun(captured),/Foreign recovered Effect captured Run/);
});

test('prepared Source adapter projects N original handles with one Core call and no legacy member admissions',()=>{
  for(const n of [1,17]){
    const f=fixture(),captured=f.admit();
    const authoring=f.control.admitRunEvidence('authoring_context','{}',f.limits);
    const preview=f.control.admitEffectComputationPreview('{}',f.definition,authoring,f.limits);
    const invocation=f.control.admit('run_invocation','original invocation',f.limits);
    const sources=Array.from({length:n},(_,memberIndex)=>({memberIndex,
      artifact:f.control.admit('effect_source_artifact','original '+memberIndex,f.limits)}));
    const originals=Array.from({length:n},(_,index)=>({index}));let calls=0;
    f.moon.clientProgramRecoveredEffectCapturedRunSources=(run,issued,definitions,results,manifest,receipt,actual,prepared,ownedPreview,indices,artifacts,store,...bounds)=>{
      assert.strictEqual(actual,f.original);assert.strictEqual(prepared,f.prepared);
      assert.equal(ownedPreview.originalPreview,true);assert.equal(issued.wire,'original invocation');
      assert.deepEqual(indices,Array.from({length:n},(_,i)=>i));assert.equal(artifacts.length,n);
      assert.equal(store,cid(4));assert.deepEqual(bounds,[f.limits.maxWireBytes,f.limits.maxNodes,f.limits.maxDepth]);
      calls++;return ok(originals);
    };
    const chain={runDefinition:f.definition,invocation,definitions:[],artifacts:[],manifest:f.definition,computationReceipt:f.definition,capturedRun:captured};
    f.moon.strategyCapturedEffectSourceHoldingCid=original=>cid(original.index+100);
    f.moon.strategyAdmitCapturedEffectSourceFromCapture=assert.fail;
    f.moon.strategyCapturedEffectSourceInventoryFromCaptureValid=assert.fail;
    assert.equal(f.control.hasPreparedCapturedEffectRun(captured),true);
    const projected=f.control.prepareCapturedEffectSourceInventory(chain,preview,sources,cid(4),f.limits);
    assert.equal(projected.length,n);assert.equal(calls,1);
    projected.forEach((source,index)=>assert.equal(f.control.capturedEffectSourceHoldingCid(source),cid(index+100)));
    assert.throws(()=>f.control.prepareCapturedEffectSourceInventory({...chain,capturedRun:{...captured}},preview,sources,cid(4),f.limits),/Foreign publication contract/);
    assert.throws(()=>f.control.prepareCapturedEffectSourceInventory(chain,{...preview},sources,cid(4),f.limits),/Invalid prepared Effect source/);
    const primary=new Error('same original prepared Source refused');
    f.moon.clientProgramRecoveredEffectCapturedRunSources=()=>{throw primary;};
    assert.throws(()=>f.control.prepareCapturedEffectSourceInventory(chain,preview,sources,cid(4),f.limits),e=>e===primary);
    assert.equal(calls,1);
    const legacy=f.control.admit('captured_run','legacy captured',f.limits);
    assert.equal(f.control.prepareCapturedEffectSourceInventory({...chain,capturedRun:legacy},preview,sources,cid(4),f.limits),undefined);
  }
});

test('unprepared legacy captured schema inventory retains4096 guard',()=>{
  const f=fixture();
  const captured=f.control.admit('captured_run',JSON.stringify({effect_context:{effect_dependency_inventory:
    Array.from({length:4097},()=>({kind:'relation_schema',cid:cid(1),body:{}}))}}),f.limits);
  assert.throws(()=>f.control.capturedEffectDependencySchemas(captured),/InvalidEffectDependencySchemas/);
});

test('original cold admission refusal has no legacy parse fallback or prepared projection',()=>{
  const primary=new Error('same original Read capacity/current refused'),f=fixture({admissionFailure:primary});
  assert.throws(()=>f.admit(),e=>e===primary);assert.deepEqual(f.calls,['admit']);
});
