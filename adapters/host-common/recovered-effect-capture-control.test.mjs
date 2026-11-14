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
  return {control,parent,input,request,definition,original,payloads,calls,limits,
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
