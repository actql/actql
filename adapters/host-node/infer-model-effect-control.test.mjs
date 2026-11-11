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
    // This exported Array Option is boxed by the actual pinned compiler.
    // The tuple/body and String Options beside it remain unboxed.
    clientProgramOriginalModelObservationInputBodies:()=>({$tag:1,_0:[
      {_0:'relation_value',_1:'input-cid',_2:'{"input":"original"}'},
    ]}),
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
  return {control,moon,limits,run,compiled,issued,scan,receipt,owner,inputs,exported,definition,calls,rawCompiled,rawDefinition,
    capture:()=>control.captureCheckedClientInferModelObservation(issued,scan,receipt,limits)};
}

test('same original Effect input body Read crosses only its existing compiled Model bridge',()=>{
  const f=fixture(),occurrence={},graph={},prefix={},inputs=[],provider={},consumer={},sources={},read={},active={};
  const calls=[];
  f.moon.clientProgramStartOriginalComposedInferExecution=(...args)=>{
    assert.deepEqual(args,[occurrence,graph,prefix,inputs,provider,f.rawCompiled,f.rawDefinition,
      consumer,7n,5n,11n,3n,sources,read]);calls.push('start');return {$tag:1,_0:active};
  };
  assert.strictEqual(f.control.startCheckedClientOriginalComposedInferExecution(f.compiled,f.run,
    occurrence,graph,prefix,inputs,provider,consumer,7n,5n,11n,3n,sources,read),active);
  assert.throws(()=>f.control.startCheckedClientOriginalComposedInferExecution({...f.compiled},f.run,
    occurrence,graph,prefix,inputs,provider,consumer,7n,5n,11n,3n,sources,read),TypeError);
  assert.deepEqual(calls,['start']);
});

test('original Model input dependency Array Option keeps its qualified boxed export layout',()=>{
  const f=fixture();
  const model=f.capture();
  assert.equal(model.unit,2);
  assert.deepEqual(model.bodies[1],{kind:'relation_value',cid:'input-cid',wire:'{"input":"original"}'});
  for(const invalid of [{$tag:0},[],{$tag:1,_0:undefined}]) {
    f.moon.clientProgramOriginalModelObservationInputBodies=()=>invalid;
    assert.throws(f.capture,TypeError);
  }
});

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

test('original Model publication failure projects the same failed Result and already-read occurrence once',()=>{
  const f=fixture();let coordinates=0,issued=0,projected=0;
  f.moon.clientProgramOriginalModelObservationCoordinates=()=>{coordinates++;return {_0:4,_1:2,_2:5};};
  const model=f.capture(),original={},result={$tag:0,_0:original};
  f.moon.clientProgramOriginalModelAcquiredEffectEvidence=()=>{issued++;return result;};
  f.moon.clientProgramOriginalModelAcquiredEffectEvidenceIssueKind=actual=>{
    projected++;assert.strictEqual(actual,result);return 'invocation.foreign_captured_input';
  };
  assert.throws(()=>f.control.issueOriginalModelEffectEvidence(model,f.run,undefined,f.limits),cause=>{
    assert.equal(cause.code,'MoonBitHostFailure');assert.strictEqual(cause.cause,original);
    assert.deepEqual(cause.primaryDiagnostic,{code:'MoonBitHostFailure',
      phase:'original_model_acquired_effect_evidence',kind:'invocation.foreign_captured_input',task:4,unit:2,step:5});
    assert(Object.isFrozen(cause.primaryDiagnostic));return true;
  });
  assert.deepEqual([coordinates,issued,projected],[1,1,1]);
});

test('optional Model failure projection cannot replace its actual Core failure or add validation',()=>{
  const f=fixture(),model=f.capture(),original={},result={$tag:0,_0:original};let calls=0;
  f.moon.clientProgramOriginalModelAcquiredEffectEvidence=()=>result;
  f.moon.clientProgramOriginalModelAcquiredEffectEvidenceIssueKind=()=>{calls++;throw new Error('OptionalDiagnosticUnavailable');};
  assert.throws(()=>f.control.issueOriginalModelEffectEvidence(model,f.run,undefined,f.limits),cause=>{
    assert.equal(cause.code,'MoonBitHostFailure');assert.strictEqual(cause.cause,original);
    assert.equal(cause.primaryDiagnostic,undefined);return true;
  });
  assert.equal(calls,1);
});

test('successful Model publication never calls the optional failure projection',()=>{
  const f=fixture(),model=f.capture();
  f.moon.clientProgramOriginalModelAcquiredEffectEvidenceIssueKind=()=>assert.fail('Success must not enter failure projection');
  assert(f.control.issueOriginalModelEffectEvidence(model,f.run,undefined,f.limits));
});

test('restored Model publication forwards the same Source witness through actual artifact and import control owners',()=>{
  const f=fixture(),source={},sourceArtifact={},manifestToken={},importToken={},importsToken={},
    sourceInvocation={},capture={},issue=Object.freeze({issue:'OriginalPublicationRefusal'});
  const ok=_0=>({$tag:1,_0});
  f.moon.clientProgramIssueInstalledWholeEffectSourceUnit=()=>ok(source);
  f.moon.clientProgramAcquiredEffectInvocation=actual=>{
    assert.strictEqual(actual,source);return sourceInvocation;
  };
  f.moon.clientProgramAcquiredEffectDependencyBodies=actual=>{
    assert.strictEqual(actual,source);return [];
  };
  f.moon.clientProgramIssueAcquiredEffectLocalResultArtifact=(...args)=>{
    assert.strictEqual(args[3],source);return ok(sourceArtifact);
  };
  f.moon.clientProgramIssueLocalEffectResultManifest=(owner,invocation,artifacts)=>{
    assert.strictEqual(invocation,sourceInvocation);assert.deepEqual(artifacts,[sourceArtifact]);return ok(manifestToken);
  };
  f.moon.clientProgramLocalEffectResultManifestCid=()=> 'original-manifest';
  f.moon.clientProgramLocalEffectResultManifestJson=()=> '{}';
  f.moon.clientProgramIssueEffectResultImportObservation=(owner,inputs,actual,manifest,artifact)=>{
    assert.strictEqual(actual,capture);assert.strictEqual(manifest,manifestToken);
    assert.strictEqual(artifact,sourceArtifact);return ok(importToken);
  };
  f.moon.clientProgramEffectResultImportObservationJson=()=> '{}';
  f.moon.clientProgramIssueImportedEffectEvidence=(owner,inputs,unit,observations)=>{
    assert.deepEqual(observations,[importToken]);return ok(importsToken);
  };
  f.moon.clientProgramImportedEffectInvocation=()=> ({});
  f.moon.clientProgramImportedEffectScopeJson=()=> '{"sources":["original-source"]}';
  f.moon.clientProgramImportedEffectRelationBodies=()=> [];
  const sourceDependency=f.control.issueCheckedWholeEffectSourceUnit({},f.owner,{},0,{}, {},{}, {},
    f.issued.observation,'authority',f.run,f.limits);
  const artifact=f.control.issueDependentLocalEffectResultArtifact(f.owner,f.inputs,f.exported,
    sourceDependency,f.definition,f.receipt,f.run,{admission:f.compiled.admission,
      runDefinition:f.run,runInvocation:f.issued.invocation,observation:f.issued.observation},f.limits);
  const manifest=f.control.issueLocalEffectResultManifest(f.owner,sourceDependency.invocation,[artifact],f.limits);
  assert.throws(()=>f.control.issueEffectResultImportObservation(f.owner,f.inputs,capture,manifest,
    {...artifact},f.limits),TypeError);
  const observed=f.control.issueEffectResultImportObservation(f.owner,f.inputs,capture,manifest,artifact,f.limits);
  const imports=f.control.issueImportedEffectEvidence(f.owner,f.inputs,2,[observed],f.limits);
  let calls=0;
  f.moon.clientProgramOriginalModelAcquiredEffectEvidence=(original,retention,bytes,nodes,depth,
    originalImports,originalSources)=>{
    calls++;assert.strictEqual(originalImports,importsToken);
    assert.deepEqual(originalSources,[source]);return {$tag:0,_0:issue};
  };
  const model=f.capture();
  assert.throws(()=>f.control.issueOriginalModelEffectEvidence(model,f.run,imports,f.limits),
    error=>error.code==='MoonBitHostFailure' && error.cause===issue);
  assert.equal(calls,1);
});
