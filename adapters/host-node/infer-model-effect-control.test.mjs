import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// Actual private-map publication control with explicit Core issuer ports.
// This tests nominal delegation, not Model execution, Core admission or Store.
function fixture() {
  const rawCompiled={},rawDefinition={},rawInvocation={},rawObservation={},binding={},
    rawModel={},rawAcquired={},rawArtifact={},execution={},issuance={},scan={},receipt={},
    owner={},inputs={},exported={},definition={},direct={};
  const calls=[];
  const ok=_0=>({$tag:1,_0});
  const moon={
    strategyRemoteManagedOutputEvidenceKind:()=> 'fixture',
    strategyPublicationAdmit:()=>ok(rawDefinition),
    strategyPublicationContractName:()=> 'fixture-contract',
    strategyPublicationContractIdentityField:()=> 'self_cid',
    strategyPublicationContractIdentity:()=> 'fixture-cid',
    strategyPublicationContractJson:()=> '{}',
    strategyRunEvidenceName:()=> 'fixture-evidence',
    strategyRunEvidenceIdentity:()=> 'fixture-evidence-cid',
    strategyRunEvidenceJson:()=> '{}',
    clientProgramCompileLocalInfer:()=>ok({}),
    clientProgramIssueTaskCompiledRun:()=>ok(rawCompiled),
    clientProgramBindCompiledInferResultPolicy:value=>ok(value),
    clientProgramCompiledRunTemplate:()=>({}),
    clientProgramCompiledRunPlan:()=>({}),
    clientProgramCompiledRunPrepared:()=>({}),
    clientProgramCompiledRunAuthorization:()=>({}),
    clientProgramCompiledRunAdmission:()=>({}),
    clientProgramBindIssuedInferInvocation(active,compiled,run,issued) {
      assert.strictEqual(active,execution);assert.strictEqual(compiled,rawCompiled);
      assert.strictEqual(run,rawDefinition);assert.strictEqual(issued,issuance);
      return ok(binding);
    },
    clientProgramInferInvocationBindingObservation:()=>rawObservation,
    clientProgramInferInvocationBindingInvocation:()=>rawInvocation,
    clientProgramIssueInferInvocationBindingOriginalModelObservation(original,completed) {
      assert.strictEqual(original,binding);assert.strictEqual(completed,receipt);
      calls.push('model-observation');return rawModel;
    },
    clientProgramOriginalModelObservationBody:()=>({_0:'model-cid',_1:'{"model":"original"}'}),
    clientProgramOriginalModelObservationCoordinates:()=>({_0:4,_1:2,_2:5}),
    clientProgramOriginalModelObservationInputBodies:()=>[
      {_0:'relation_value',_1:'input-cid',_2:'{"input":"original"}'},
    ],
    clientProgramInferModelIdentityBody(original,completed) {
      assert.strictEqual(original,scan);assert.strictEqual(completed,receipt);
      return '{"outcomes":"original"}';
    },
    clientProgramEffectInputExportLogicalCid:()=> 'outcome-cid',
    clientProgramEffectInputExportSchemaCid:()=> 'outcome-schema',
    clientProgramEffectInputExportSchemaWire:()=> '{"fields":[]}',
    clientProgramOriginalModelAcquiredEffectEvidence(original,retention,bytes,nodes,depth,imports) {
      assert.strictEqual(original,rawModel);assert.strictEqual(retention,rawDefinition);
      assert.equal(imports,undefined);calls.push('model-acquired');return ok(rawAcquired);
    },
    clientProgramOriginalModelAcquiredEffectSources:()=>[direct],
    clientProgramOriginalModelAcquiredEffectLookupBarrier:()=>undefined,
    clientProgramOriginalModelAcquiredEffectInvocation:()=>rawInvocation,
    clientProgramOriginalModelAcquiredEffectScope:()=> '{"sources":[]}',
    clientProgramAcquiredEffectInvocation:()=>({}),
    clientProgramAcquiredEffectDependencyBodies(original) {
      assert.strictEqual(original,direct);
      return [{_0:'source_evidence',_1:'{"kind":"Whole"}'}];
    },
    clientProgramAcquiredEffectCatalogBodies:()=>ok([]),
    clientProgramOriginalModelEffectResultArtifact(original,prepared,captured,result,acquired,
      resultDefinition,exportReceipt,admission,run,invocation,observation) {
      assert.strictEqual(original,rawModel);assert.strictEqual(prepared,owner);
      assert.strictEqual(captured,inputs);assert.strictEqual(result,exported);
      assert.strictEqual(acquired,rawAcquired);assert.strictEqual(resultDefinition,definition);
      assert.strictEqual(exportReceipt,receipt);assert.strictEqual(run,rawDefinition);
      assert.strictEqual(invocation,rawInvocation);assert.strictEqual(observation,rawObservation);
      calls.push('model-artifact');return ok(rawArtifact);
    },
    clientProgramLocalEffectResultArtifactCid:()=> 'artifact-cid',
    clientProgramLocalEffectResultArtifactJson:()=> '{}',
    clientProgramLocalEffectResultDerivationJson:()=> '{}',
    clientProgramLocalEffectResultOrderingJson:()=> '{}',
    clientProgramIssueAcquiredEffectEvidence(){assert.fail('No Query-only Source issuer for Model contribution');},
    clientProgramIssueAcquiredEffectLocalResultArtifact(){assert.fail('No Source-only Artifact upgrade');},
    clientProgramIssueImportedEffectLocalResultArtifact(){assert.fail('No Model-free imported Artifact');},
  };
  const control=runtimeCore(moon).publicationControl;
  const limits={maxWireBytes:16384,maxNodes:1024,maxDepth:20};
  const run=control.admit('run_definition','{}',limits);
  const compiled=control.prepareCheckedClientCompiledRun({},'infer',{
    resultDataPolicy:{kind:'data_policy',cid:'policy',wire:'{}'},
  },{});
  const issued=control.bindIssuedClientInferInvocation(compiled,execution,run,issuance);
  return {control,moon,limits,run,compiled,issued,scan,receipt,owner,inputs,exported,definition,calls,
    capture:()=>control.captureCheckedClientInferModelObservation(issued,scan,receipt,limits)};
}

test('same Model binding and typed Whole contribution reach complete Model Artifact without Query conversion',()=>{
  const f=fixture(),model=f.capture();
  assert.equal(model.unit,2,'actual Unit coordinate is not Source slot or task4');
  assert.deepEqual(model.bodies.map(value=>value.cid),
    ['model-cid','input-cid','outcome-cid','outcome-schema']);
  const dependency=f.control.issueOriginalModelEffectEvidence(model,f.run,undefined,f.limits);
  assert.equal(dependency.bodies.some(value=>value.wire==='{"kind":"Whole"}'),true);
  const artifact=f.control.issueDependentLocalEffectResultArtifact(f.owner,f.inputs,
    f.exported,dependency,f.definition,f.receipt,f.run,{admission:f.compiled.admission,
      runDefinition:f.run,runInvocation:f.issued.invocation,observation:f.issued.observation},f.limits);
  assert.equal(artifact.identity,'artifact-cid');
  assert.deepEqual(f.calls,['model-observation','model-acquired','model-artifact']);
});

test('copied Model/Invocation/import wrappers refuse before any original Core issuer',()=>{
  const f=fixture();
  assert.throws(()=>f.control.captureCheckedClientInferModelObservation(
    {...f.issued},f.scan,f.receipt,f.limits),TypeError);
  assert.deepEqual(f.calls,[]);
  const model=f.capture();
  assert.throws(()=>f.control.issueOriginalModelEffectEvidence({...model},f.run,undefined,f.limits),TypeError);
  assert.throws(()=>f.control.issueOriginalModelEffectEvidence(model,f.run,{bodies:[]},f.limits),TypeError);
  assert.deepEqual(f.calls,['model-observation']);
});

test('missing original Model receipt/body cannot create a fabricated dependency',()=>{
  for(const mode of ['receipt','input','outcome']) {
    const f=fixture();
    if(mode==='receipt')f.moon.clientProgramIssueInferInvocationBindingOriginalModelObservation=()=>undefined;
    if(mode==='input')f.moon.clientProgramOriginalModelObservationInputBodies=()=>undefined;
    if(mode==='outcome')f.moon.clientProgramInferModelIdentityBody=()=>undefined;
    assert.throws(f.capture,TypeError);
    assert.equal(f.calls.includes('model-acquired'),false);
  }
});
