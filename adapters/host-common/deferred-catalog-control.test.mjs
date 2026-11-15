// Actual private scheduling/projection code with explicit Core ports. Genuine
// 4097-member numeric construction is executed separately by the Core cases.
import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';
import {preparePinnedEffectSourceSet} from '../host-node/effect-input-export.mjs';
const ok=value=>({$tag:1,_0:value});
function fixture() {
  const issued={},source={},calls=[];
  let refusal;
  const moon={
    strategyRemoteManagedOutputEvidenceKind:()=> 'fixture metadata',
    strategyPublicationAdmit:(name,wire)=>ok({name,wire,identity:'sha256:'+'1'.repeat(64)}),
    strategyPublicationContractName:v=>v.name,strategyPublicationContractIdentityField:()=> 'cid',
    strategyPublicationContractIdentity:v=>v.identity,strategyPublicationContractJson:v=>v.wire,
    strategyRunEvidenceAdmit:(name,wire)=>ok({name,wire,identity:'sha256:'+'2'.repeat(64)}),
    strategyRunEvidenceName:v=>v.name,strategyRunEvidenceIdentity:v=>v.identity,strategyRunEvidenceJson:v=>v.wire,
    clientProgramIssueAcquiredEffectEvidence(){calls.push('issuer');return refusal===undefined?ok(issued):{$tag:0,_0:refusal};},
    clientProgramIssueInstalledWholeEffectSourceUnit(){calls.push('whole-issuer');return refusal===undefined?ok(issued):{$tag:0,_0:refusal};},
    clientProgramAcquiredEffectInvocation:()=>({}),clientProgramAcquiredEffectDependencyBodies:()=>[],
    clientProgramAcquiredEffectCatalogBodies(){calls.push('legacy-catalog');return ok([]);},
  };
  const control=runtimeCore(moon).publicationControl;
  const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:64};
  const retention=control.admit('result_retention_policy','{}',limits);
  const observation=control.admitRunEvidence('source_evidence','{}',limits);
  return {calls,refuse(value){refusal=value;},
    query(defer=false){return control.issueCheckedAcquiredEffectEvidence({},source,{},{},{},observation,'scope','policy',retention,limits,0,retention,defer);},
    whole(defer=false){return control.issueCheckedWholeEffectSourceUnit({}, {}, {}, 0, source, {}, {}, {}, observation,'scope',retention,limits,defer);}};
}

test('registered Query and Whole scheduling preserves typed issuers and defers only Catalog wires',()=>{
  const f=fixture();
  for(const value of [f.query(true),f.whole(true)]) {
    assert.equal(value.catalogDeferred,true);assert.deepEqual(value.catalogBodies,[]);
  }
  assert.deepEqual(f.calls,['issuer','whole-issuer']);
  const primary=new Error('OriginalSourceRefused');f.refuse(primary);
  assert.throws(()=>f.query(true),error=>error.code==='MoonBitHostFailure'&&error.cause===primary);
  assert.deepEqual(f.calls,['issuer','whole-issuer','issuer']);
});

test('unmanaged default still performs eager legacy Catalog lookup',()=>{
  const f=fixture();
  assert.equal(f.query().catalogDeferred,undefined);
  assert.deepEqual(f.calls,['issuer','legacy-catalog']);
});

test('deferred Catalog without an actual late provider refuses before inputs or export',async()=>{
  let inspected=0;
  await assert.rejects(preparePinnedEffectSourceSet({moon:{clientProgramEffectInputCount(){inspected++;}},
    localEvidenceContext:{catalogDeferred:true}}),/MissingOriginalCatalogConstruction/);
  assert.equal(inspected,0);
});

// Exercise the actual Content adapter with explicit Core issuer doubles. These
// checks establish tuple routing and call counts, not Core Whole admission.
function serializationCaptureFixture() {
  const compiledOriginal = {}, graphOriginal = {}, effect = {}, source = {},
    identity = {}, capacity = {}, requirement = {}, logical = {}, proof = {}, calls = [];
  const evidence = {name: 'fixture_evidence', identity: 'fixture_evidence', wire: '{}'};
  const contract = {name: 'fixture_contract', identity: 'fixture_contract', wire: '{}'};
  let refusal, sourceReads = 0;
  const issue = port => (...args) => {
    calls.push({port, args}); return refusal === undefined ? ok(proof) : {$tag: 0, _0: refusal};
  };
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture metadata',
    strategyPublicationAdmit: () => ok(contract),
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    clientProgramEffectAllowedSerializationRun: () => ok(compiledOriginal),
    clientProgramCheckCompiledRunDefinition: () => true,
    clientProgramCompiledRunHasSerialization: value => value === compiledOriginal,
    clientProgramCompiledRunTemplate: () => evidence,
    clientProgramCompiledRunPlan: () => contract,
    clientProgramCompiledRunPrepared: () => evidence,
    clientProgramCompiledRunAuthorization: () => evidence,
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramAcquiredSerializationPlanGraph: () => ok(graphOriginal),
    clientProgramSerializationPlanGraphWire: () => '{}',
    clientProgramAdmitEffectSerializationWholeCapturedInput: issue('effect-whole'),
    clientProgramAdmitEffectSerializationCapturedInput: issue('effect-query'),
    clientProgramAdmitSerializationWholeCapturedInput: issue('whole'),
    clientProgramAdmitSerializationCapturedInput: issue('query'),
  };
  const control = runtimeCore(moon).publicationControl;
  const definition = control.admit('run_definition', '{}',
    {maxWireBytes: 4096, maxNodes: 256, maxDepth: 16});
  const compiled = control.adoptCheckedClientEffectSerializationRun({}, definition);
  const graph = control.prepareCheckedClientAcquiredSerializationGraph(effect,
    {task: 1, step: 2, maxRows: 1, maxBytes: 256});
  const captured = {capture: {source() {sourceReads++; return source;}}, identity, logicalInput: logical};
  const observation = {sourceEvidenceWire: 'original evidence', authorityScopeCid: 'scope',
    captureStartedAt: 'started', captureCompletedAt: 'completed'};
  return {control, compiled, compiledOriginal, graph, graphOriginal, effect, captured,
    source, identity, capacity, requirement, logical, proof, calls, observation,
    reads: () => sourceReads, refuse(value) {refusal = value;}};
}

test('Content Whole and Query captures retain their distinct originals with one Core call', () => {
  for (const whole of [false, true]) {
    const f = serializationCaptureFixture();
    const captured = whole ? {...f.captured, inputKind: 'whole-input', wholeCapacity: f.capacity}
      : {...f.captured, requirement: f.requirement};
    assert.strictEqual(f.control.bindCheckedClientEffectSerializationCapture(
      f.compiled, f.effect, captured, f.observation), f.proof);
    assert.equal(f.reads(), 1);
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].port, whole ? 'effect-whole' : 'effect-query');
    assert.deepEqual(f.calls[0].args, [f.compiledOriginal, f.effect, f.source, f.identity,
      whole ? f.capacity : f.requirement, f.logical, 'original evidence', 'scope', 'started', 'completed']);
  }
});

test('plain Content preserves Query lookup evidence and never invents it for Whole', () => {
  const f = serializationCaptureFixture(), keyed = {};
  assert.strictEqual(f.control.bindCheckedClientSerializationCapture(f.effect, f.graph,
    {...f.captured, requirement: f.requirement}, {...f.observation, keyedObservation: {observation: keyed}}), f.proof);
  assert.equal(f.calls[0].port, 'query');
  assert.strictEqual(f.calls[0].args.at(-1), keyed);
  assert.strictEqual(f.control.bindCheckedClientSerializationCapture(f.effect, f.graph,
    {...f.captured, inputKind: 'whole-input', wholeCapacity: f.capacity}, f.observation), f.proof);
  assert.equal(f.calls[1].port, 'whole');
  assert.strictEqual(f.calls[1].args[4], f.capacity);
  const count = f.calls.length, reads = f.reads();
  assert.throws(() => f.control.bindCheckedClientSerializationCapture(f.effect, f.graph,
    {...f.captured, inputKind: 'whole-input'}, f.observation), TypeError);
  assert.throws(() => f.control.bindCheckedClientSerializationCapture(f.effect, f.graph,
    {...f.captured, inputKind: 'whole-input', wholeCapacity: f.capacity},
    {...f.observation, keyedObservation: {observation: keyed}}), TypeError);
  assert.equal(f.calls.length, count); assert.equal(f.reads(), reads);
});

test('Content refusal retains its primary cause without fallback or copied-original admission', () => {
  const f = serializationCaptureFixture(), primary = new Error('original Whole refusal');
  const captured = {...f.captured, inputKind: 'whole-input', wholeCapacity: f.capacity};
  f.refuse(primary);
  assert.throws(() => f.control.bindCheckedClientEffectSerializationCapture(
    f.compiled, f.effect, captured, f.observation),
  error => error.code === 'RunHostEffectContentCaptureRejected' && error.cause === primary);
  assert.deepEqual(f.calls.map(call => call.port), ['effect-whole']); assert.equal(f.reads(), 1);
  assert.throws(() => f.control.bindCheckedClientEffectSerializationCapture(
    {...f.compiled}, f.effect, captured, f.observation), TypeError);
  assert.throws(() => f.control.bindCheckedClientSerializationCapture(
    f.effect, {...f.graph}, captured, f.observation), TypeError);
  assert.equal(f.calls.length, 1); assert.equal(f.reads(), 1);
});
