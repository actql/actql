import test from 'node:test';
import assert from 'node:assert/strict';
import {openNodeInferOperation,startCompleteInferObservation} from './infer-operation.mjs';
import {retainInferOriginalReadInstallation} from './infer-original-installation.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// Actual operation code, explicit Common/Resource ports. These DATA amounts
// and mocked terminal Model are not a physical profile or actual reservation.
function fixture({missing=false,reserveIssue,releaseIssue}={}) {
  const active={},consumer={},borrow={},issued={},compiled={},definition={},graph={};
  const calls=[];
  const configuration={bootstrap:{bootstrapRetainedBytes:1n,bootstrapExecutionBytes:0n,
    maxReservations:1,maxHoldings:1,maxDelegations:1},
    modelRetainedBytes:1n,modelExecutionBytes:0n,
    ...(missing?{}:{publicationCapacity:{retainedBytes:123n,workspaceBytes:456n}}),
    nodeInstallation:{layout:{barrier_cid:'barrier',execution_bytes:1n,
      layout_artifact_cid:'layout',parameter_values_cid:'parameters',prepared_rows:1n,
      program_definition_cid:'program',response_profile:{},retained_bytes:1n,
      runtime_artifact_cid:'runtime'},installation:{},layoutArtifactCid:'layout',
      probability:undefined,runtimeArtifactCid:'runtime'}};
  const original=retainInferOriginalReadInstallation(configuration);
  let released=false,releaseComplete=true,stopped=true;
  const ok=_0=>({$tag:1,_0});
  const control={
    claimCheckedClientInferNodePreparationLayout(run,wire,selected,read,node) {
      assert.equal(run,compiled);assert.equal(wire,definition);assert.equal(selected,graph);
      assert.equal(node,original.nodeInstallation);calls.push('claim');return consumer;
    },
    startCheckedClientInferOriginalPreparation(...args) {
      assert.equal(args[8],consumer);calls.push('start');return active;
    },
  };
  const moon={
    clientProgramReserveOriginalInferPublicationCapacity(owner,r,w) {
      assert.equal(owner,active);assert.equal(r,123n);assert.equal(w,456n);
      calls.push('reserve');return reserveIssue===undefined?ok(borrow):{$tag:0,_0:reserveIssue};
    },
    clientProgramStartOriginalInferObservationIssuance(owner,capacity,n,bytes,work,generations) {
      assert.equal(owner,active);assert.equal(capacity,borrow);assert.equal(released,false);
      assert.deepEqual([n,bytes,work],[1,4096,3]);assert.deepEqual(generations,[]);
      calls.push('issue');return ok(issued);
    },
    clientProgramReleaseOriginalInferPublicationCapacity(value) {
      assert.equal(value,borrow);calls.push('release');
      if(releaseIssue!==undefined)return {$tag:0,_0:releaseIssue};
      if(releaseComplete)released=true;
      return ok(releaseComplete);
    },
    clientProgramInferPublicationLedger(){assert.fail('no separate Ledger fallback');},
    clientProgramStartInferObservationIssuance(){assert.fail('no legacy issuer fallback');},
    clientProgramCancelInferExecution(value){assert.equal(value,active);calls.push('stop');stopped=true;},
    clientProgramInferExecutionStopped:()=>stopped,
    clientProgramCleanupInferExecution(value){assert.equal(value,active);calls.push('cleanup');return ok(true);},
  };
  const operation=openNodeInferOperation({moon,preparedProgram:{},graph,provider:{},
    originalPreparation:{compiled,runDefinition:definition,control,scope:{},read:{},
      nodeInstallation:original.nodeInstallation,metadataInstallation:original,
      readRetainedBytes:1n,readExecutionBytes:1n,modelRetainedBytes:1n,modelExecutionBytes:0n}});
  return {operation,calls,borrow,issued,moon,active,
    releaseComplete(value){releaseComplete=value;},
    releaseIssue(value){releaseIssue=value;}};
}
const limits={maxSlots:1,maxWireBytes:4096,maxWork:3};

test('original publication grows same borrower only for new simultaneous construction demand',()=>{
  const f=fixture(),grows=[];
  f.moon.clientProgramGrowOriginalInferPublicationCapacity=(active,borrow,r,e)=>{
    assert.strictEqual(active,f.active);
    assert.strictEqual(borrow,f.borrow);grows.push([r,e]);return {$tag:1,_0:undefined};
  };
  assert.throws(()=>f.operation.growOriginalPublicationCapacity(1n,2n),
    /InferOriginalPublicationCapacityUnavailable/);
  f.operation.reserveOriginalPublicationCapacity();
  f.operation.growOriginalPublicationCapacity(10n,20n);
  f.operation.growOriginalPublicationCapacity(10n,20n);
  f.operation.growOriginalPublicationCapacity(4n,8n);
  assert.deepEqual(grows,[[133n,476n]],'covered bounded steps make no Resource call');
  const issue={kind:'OriginalPublicationExhausted'};
  f.moon.clientProgramGrowOriginalInferPublicationCapacity=()=>({$tag:0,_0:issue});
  assert.throws(()=>f.operation.growOriginalPublicationCapacity(30n,40n),error=>error.cause===issue);
  assert.equal(f.operation.publicationCapacityPending(),true);
  f.moon.clientProgramGrowOriginalInferPublicationCapacity=(active,borrow,r,e)=>{
    assert.strictEqual(active,f.active);
    assert.strictEqual(borrow,f.borrow);grows.push([r,e]);return {$tag:1,_0:undefined};
  };
  f.operation.growOriginalPublicationCapacity(30n,40n);
  assert.deepEqual(grows,[[133n,476n],[153n,496n]],'refusal cannot record unfunded coverage');
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.throws(()=>f.operation.growOriginalPublicationCapacity(1n,2n),
    /InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.operation.cleanup(),true);
});

test('publication grow preserves actual debt but stops construction after a reentrant original close',async()=>{
  const f=fixture();let stopped;
  f.operation.reserveOriginalPublicationCapacity();
  f.moon.clientProgramGrowOriginalInferPublicationCapacity=(active,borrow)=>{
    assert.strictEqual(active,f.active);assert.strictEqual(borrow,f.borrow);
    stopped=f.operation.stop();return {$tag:1,_0:undefined};
  };
  assert.throws(()=>f.operation.growOriginalPublicationCapacity(10n,20n),
    /InferOriginalPublicationCapacityUnavailable/);
  await stopped;
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.cleanup(),false);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.operation.cleanup(),true);
});

test('original publication reserves once and reuses its nominal borrower without exporting a Ledger',()=>{
  const f=fixture();
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.reserveOriginalPublicationCapacity(),undefined);
  assert.equal(f.operation.reserveOriginalPublicationCapacity(),undefined);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.startObservation(limits),f.issued);
  assert.throws(()=>f.operation.startObservation({...limits,ledger:{}}),
    /InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.calls.filter(x=>x==='issue').length,1);
  assert.equal(f.operation.cleanup(),false);
  assert.equal(f.calls.includes('cleanup'),false,'a retained borrower pins parent cleanup');
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.calls.filter(x=>x==='release').length,1);
  assert.equal(f.operation.cleanup(),true);
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
});

test('missing original publication declaration cannot invoke reserve or the legacy issuer',()=>{
  const f=fixture({missing:true});
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),
    {code:'InferOriginalPublicationCapacityUnavailable'});
  assert.throws(()=>f.operation.startObservation(limits),/InferOriginalPublicationCapacityUnavailable/);
  assert.deepEqual(f.calls,['claim','start']);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.cleanup(),true);
});

test('Common reservation refusal retains original cleanup with no invented borrower',()=>{
  const issue={kind:'OriginalCapacityExhausted'},f=fixture({reserveIssue:issue});
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),error=>error.cause===issue);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.throws(()=>f.operation.startObservation(limits),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.calls.includes('issue'),false);
  assert.equal(f.operation.cleanup(),true);
});

test('failed and pending release retain the same borrower until exact settlement succeeds',()=>{
  const issue={kind:'OriginalParked'},f=fixture({releaseIssue:issue});
  f.operation.reserveOriginalPublicationCapacity();
  assert.throws(()=>f.operation.releaseOriginalPublicationCapacity(),error=>error.cause===issue);
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.cleanup(),false);
  f.releaseIssue(undefined);f.releaseComplete(false);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),false);
  assert.equal(f.operation.publicationCapacityPending(),true);
  f.releaseComplete(true);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.operation.cleanup(),true);
});

test('stop retains the original borrower and cleanup release does not request a send grant',async()=>{
  const f=fixture();f.operation.reserveOriginalPublicationCapacity();
  await f.operation.stop();
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.cleanup(),false);
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.operation.cleanup(),true);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.calls.filter(x=>x==='release').length,1);
  assert.equal(f.calls.includes('issue'),false);
});

// Actual adapter with explicit Common ports. This original ordinary composed
// preparation has no legacy Node installation. The callback selects bounds;
// only the existing same-Model Common reservation can issue its opaque borrow.
function ordinaryFixture({select, reserveIssue}={}) {
  const active={},consumer={},borrow={},issued={},compiled={},runDefinition={},graph={};
  const calls=[];
  const ok=_0=>({$tag:1,_0});
  let current=true,releaseComplete=true;
  const control={
    claimCheckedClientInferOriginalComposedPreparation(c,d,g,read,r,w) {
      assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);
      assert.strictEqual(g,graph);assert.strictEqual(read,preparation.read);
      assert.deepEqual([r,w],[7n,5n]);calls.push('claim');return consumer;
    },
    startCheckedClientOriginalComposedInferExecution(c,d,occurrence,g,prefix,inputs,
      provider,original,r,w,mr,mw,sources) {
      assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);
      assert.strictEqual(g,graph);assert.strictEqual(original,consumer);
      assert.deepEqual([r,w,mr,mw],[7n,5n,1000n,500n]);
      assert.strictEqual(sources,composedInput.sources);calls.push('start');return active;
    },
  };
  const preparation={compiled,runDefinition,control,scope:{},read:{},
    readRetainedBytes:7n,readExecutionBytes:5n,modelRetainedBytes:1000n,modelExecutionBytes:500n,
    publicationCapacity() {
      assert.strictEqual(this,preparation,'retain the original callback receiver');
      calls.push('select');
      if(!current)throw Object.assign(new Error('ForeignInstalledModelPreparation'),{code:'OriginalCurrentRefused'});
      return select===undefined?{retainedBytes:123n,workspaceBytes:456n}:select();
    }};
  const composedInput={occurrence:{},prefix:{},inputs:[],sources:[]};
  const moon={
    clientProgramReserveOriginalInferPublicationCapacity(owner,r,w) {
      assert.strictEqual(owner,active);assert.deepEqual([r,w],[123n,456n]);calls.push('reserve');
      return reserveIssue===undefined?ok(borrow):{$tag:0,_0:reserveIssue};
    },
    clientProgramStartOriginalInferObservationIssuance(owner,capacity,n,bytes,work,generations) {
      assert.strictEqual(owner,active);assert.strictEqual(capacity,borrow);
      assert.deepEqual([n,bytes,work],[1,4096,3]);assert.deepEqual(generations,[]);
      calls.push('issue');return ok(issued);
    },
    clientProgramReleaseOriginalInferPublicationCapacity(value) {
      assert.strictEqual(value,borrow);calls.push('release');return ok(releaseComplete);
    },
    clientProgramInferPublicationLedger(){assert.fail('never create a replacement Ledger');},
    clientProgramStartInferObservationIssuance(){assert.fail('never fall back to the legacy issuer');},
    clientProgramInferExecutionStopped:()=>true,
    clientProgramCleanupInferExecution(owner){assert.strictEqual(owner,active);calls.push('cleanup');return ok(true);},
  };
  // Match openNodeComposedInferProvider's Local-scheduled caller. A separate
  // preparedProgram would select the distinct installed one-Unit entrance.
  const options={moon,graph,provider:{},composedInput,originalPreparation:preparation};
  return {options,preparation,calls,issued,
    current(value){current=value;},releaseComplete(value){releaseComplete=value;}};
}

test('ordinary original publication selects same-Run capacity without a legacy Node installation',()=>{
  const f=ordinaryFixture(),operation=openNodeInferOperation(f.options);
  assert.equal(Object.hasOwn(f.preparation,'nodeInstallation'),false);
  assert.equal(Object.hasOwn(f.preparation,'metadataInstallation'),false);
  operation.reserveOriginalPublicationCapacity();
  operation.reserveOriginalPublicationCapacity();
  assert.deepEqual(f.calls,['claim','start','select','reserve']);
  assert.strictEqual(operation.startObservation(limits),f.issued);
  assert.equal(operation.cleanup(),false);
  f.releaseComplete(false);
  assert.equal(operation.releaseOriginalPublicationCapacity(),false);
  assert.equal(operation.cleanup(),false);
  f.releaseComplete(true);
  assert.equal(operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(operation.cleanup(),true);
});

test('ordinary original publication retains its original callback and receiver before completion',()=>{
  const f=ordinaryFixture(),operation=openNodeInferOperation(f.options);
  f.preparation.publicationCapacity=()=>assert.fail('a replacement is not the installing original');
  operation.reserveOriginalPublicationCapacity();
  assert.deepEqual(f.calls,['claim','start','select','reserve']);
  assert.equal(operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(operation.cleanup(),true);
  assert.throws(()=>operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.calls.filter(x=>x==='select').length,1);
});

test('ordinary original publication current refusal cannot invoke reservation or another issuer',()=>{
  const f=ordinaryFixture(),operation=openNodeInferOperation(f.options);
  f.current(false);
  assert.throws(()=>operation.reserveOriginalPublicationCapacity(),{code:'OriginalCurrentRefused'});
  assert.deepEqual(f.calls,['claim','start','select']);
  assert.equal(operation.publicationCapacityPending(),false);
  assert.throws(()=>operation.startObservation(limits),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(operation.cleanup(),true);
});

test('ordinary original publication refuses malformed amounts without reading getters or reserving',()=>{
  for(const value of [undefined,null,{},[],{retainedBytes:0n,workspaceBytes:0n},
    {retainedBytes:123n,workspaceBytes:-1n},{retainedBytes:123,workspaceBytes:456n},
    {retainedBytes:123n,workspaceBytes:9223372036854775808n},
    {retainedBytes:123n,workspaceBytes:456n,extra:true},
    {get retainedBytes(){assert.fail('do not invoke an unowned selection getter');},workspaceBytes:456n}]) {
    const f=ordinaryFixture({select:()=>value}),operation=openNodeInferOperation(f.options);
    assert.throws(()=>operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
    assert.equal(f.calls.includes('reserve'),false);
    assert.equal(operation.publicationCapacityPending(),false);
    assert.equal(operation.cleanup(),true);
  }
});

test('ordinary original publication preserves Common refusal without issuing a replacement borrower',()=>{
  const issue={},f=ordinaryFixture({reserveIssue:issue}),operation=openNodeInferOperation(f.options);
  assert.throws(()=>operation.reserveOriginalPublicationCapacity(),error=>error.cause===issue);
  assert.deepEqual(f.calls,['claim','start','select','reserve']);
  assert.equal(operation.publicationCapacityPending(),false);
  assert.equal(operation.cleanup(),true);
});

test('ordinary original publication captures only an own data callback before claiming the read',()=>{
  for(const value of [undefined,null,{},true]) {
    const f=ordinaryFixture();f.preparation.publicationCapacity=value;
    assert.throws(()=>openNodeInferOperation(f.options),/InferOriginalPublicationCapacityUnavailable/);
    assert.deepEqual(f.calls,[]);
  }
  const f=ordinaryFixture();
  Object.defineProperty(f.preparation,'publicationCapacity',{get(){assert.fail('not an original data callback');}});
  assert.throws(()=>openNodeInferOperation(f.options),/InferOriginalPublicationCapacityUnavailable/);
  assert.deepEqual(f.calls,[]);
});

test('complete original observation consumes the same single Model publication borrow without a Ledger',()=>{
  const f=ordinaryFixture(),operation=openNodeInferOperation(f.options);
  operation.reserveOriginalPublicationCapacity();
  assert.strictEqual(startCompleteInferObservation({moon:f.options.moon,operations:[operation],...limits}),f.issued);
  assert.equal(f.calls.filter(x=>x==='issue').length,1);
  assert.equal(operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(operation.cleanup(),true);
});

test('complete original observation rejects foreign copied missing mixed and alternate Ledger owners',()=>{
  const f=ordinaryFixture(),operation=openNodeInferOperation(f.options),other=ordinaryFixture();
  const sibling=openNodeInferOperation(other.options);
  f.options.moon.clientProgramStartCompleteInferObservationIssuance=()=>assert.fail('not the original issuer');
  assert.throws(()=>startCompleteInferObservation({moon:f.options.moon,operations:[operation],...limits}),
    /InferOriginalPublicationCapacityUnavailable/);
  operation.reserveOriginalPublicationCapacity();
  for(const options of [{operations:[operation],ledger:{}},{operations:[operation,sibling]},
    {operations:[operation],content:{}},{operations:[{...operation}]},{operations:[{}]}]) {
    assert.throws(()=>startCompleteInferObservation({moon:f.options.moon,...limits,...options}),
      /InferOriginalPublicationCapacityUnavailable|ForeignInferOperation/);
  }
  assert.equal(f.calls.includes('issue'),false);
  operation.releaseOriginalPublicationCapacity();
  assert.equal(operation.cleanup(),true);assert.equal(sibling.cleanup(),true);
});

test('complete legacy observation preserves its explicit metadata Ledger and issuer',()=>{
  const active={},ledger={},issued={};let calls=0;
  const moon={
    clientProgramStartComposedInferExecution:()=>({$tag:1,_0:active}),
    clientProgramStartCompleteInferObservationIssuance(owners,original,n,bytes,work) {
      assert.deepEqual(owners,[active]);assert.strictEqual(original,ledger);
      assert.deepEqual([n,bytes,work],[1,4096,3]);calls++;return {$tag:1,_0:issued};
    },
    clientProgramInferExecutionStopped:()=>true,
    clientProgramCleanupInferExecution:()=>({$tag:1,_0:true}),
  };
  const operation=openNodeInferOperation({moon,graph:{},provider:{},composedInput:{}});
  assert.strictEqual(startCompleteInferObservation({moon,operations:[operation],ledger,...limits}),issued);
  assert.equal(calls,1);assert.equal(operation.cleanup(),true);
});

// Actual original-operation adapter with explicit Core ports: aggregate
// identity/current/Plan/Ledger validation remains the typed Core obligation.
test('complete multi original observation forwards original ordered owners to one existing borrow',()=>{
  const first=ordinaryFixture(),second=ordinaryFixture();
  const a=openNodeInferOperation(first.options),b=openNodeInferOperation(second.options);
  b.reserveOriginalPublicationCapacity();
  let calls=0;
  second.options.moon.clientProgramStartCompleteOriginalInferObservationIssuance=(owners,capacity,n,bytes,work,generations)=>{
    assert.equal(owners.length,2);assert.notStrictEqual(owners[0],owners[1]);
    assert.ok(capacity);assert.deepEqual([n,bytes,work],[2,4096,4]);
    assert.deepEqual(generations,[]);calls++;return {$tag:1,_0:second.issued};
  };
  assert.strictEqual(startCompleteInferObservation({moon:first.options.moon,operations:[a,b],
    maxSlots:2,maxWireBytes:4096,maxWork:4}),second.issued);
  assert.equal(calls,1);
  assert.equal(a.releaseOriginalPublicationCapacity(),true);
  assert.equal(b.releaseOriginalPublicationCapacity(),true);
  assert.equal(a.cleanup(),true);assert.equal(b.cleanup(),true);
});

test('multi original observation preserves original issuer refusal and never falls back',()=>{
  const first=ordinaryFixture(),second=ordinaryFixture(),issue={kind:'same-parent-refused'};
  const a=openNodeInferOperation(first.options),b=openNodeInferOperation(second.options);
  a.reserveOriginalPublicationCapacity();
  let calls=0;
  first.options.moon.clientProgramStartCompleteOriginalInferObservationIssuance=()=>{calls++;return {$tag:0,_0:issue};};
  assert.throws(()=>startCompleteInferObservation({moon:first.options.moon,operations:[a,b],...limits}),
    error=>error.cause===issue);
  assert.equal(calls,1);assert.equal(a.publicationCapacityPending(),true);
  assert.equal(b.publicationCapacityPending(),false);
  assert.throws(()=>startCompleteInferObservation({moon:first.options.moon,operations:[a,a],...limits}),
    /InferOriginalPublicationCapacityUnavailable/);
  assert.equal(calls,1,'duplicate cannot invoke the typed constructor');
  a.releaseOriginalPublicationCapacity();b.releaseOriginalPublicationCapacity();
  assert.equal(a.cleanup(),true);assert.equal(b.cleanup(),true);
});


test('complete original observation refuses two publication funders before invoking any typed issuer',()=>{
  const first=ordinaryFixture(),second=ordinaryFixture();
  const a=openNodeInferOperation(first.options),b=openNodeInferOperation(second.options);
  a.reserveOriginalPublicationCapacity();b.reserveOriginalPublicationCapacity();
  first.options.moon.clientProgramStartCompleteOriginalInferObservationIssuance=()=>assert.fail('Two funders do not choose a first issuer');
  second.options.moon.clientProgramStartCompleteOriginalInferObservationIssuance=()=>assert.fail('Two funders do not choose a second issuer');
  assert.throws(()=>startCompleteInferObservation({moon:first.options.moon,operations:[a,b],...limits}),
    /InferOriginalPublicationCapacityUnavailable/);
  assert.equal(a.publicationCapacityPending(),true);assert.equal(b.publicationCapacityPending(),true);
  a.releaseOriginalPublicationCapacity();b.releaseOriginalPublicationCapacity();
  assert.equal(a.cleanup(),true);assert.equal(b.cleanup(),true);
});

// Real runtime facade registries and original operation caller; typed Core,
// compilation, Model completion and physical funding remain explicit ports.
function generatedOriginalFixture() {
  const ok = _0 => ({$tag: 1, _0});
  const nativeRun = {}, nativeGeneration = {}, nativeDefinition = {
    name: 'run_definition', identity: 'original definition', wire: '{}',
  };
  const nativePlan = {name: 'plan', identity: 'original plan', wire: '{}'};
  const nativeEvidence = {name: 'evidence', identity: 'original evidence', wire: '{}'};
  const active = [], calls = [], borrow = {}, issued = {}, graph = {}, consumer = {};
  let refusal;
  const issue = (owners, capacity, n, bytes, work, generations) => {
    assert.strictEqual(capacity, borrow);
    assert.deepEqual(owners, active);
    assert.deepEqual([n, bytes, work], [1, 4096, 3]);
    assert.equal(generations.length, 1);
    assert.strictEqual(generations[0], nativeGeneration,
      'the original Core receives its SAME native generation, never the public facade');
    calls.push('issue');
    return refusal === undefined ? ok(issued) : {$tag: 0, _0: refusal};
  };
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'explicit fixture metadata',
    strategyPublicationAdmit: () => ok(nativeDefinition),
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    clientProgramEffectAllowedSerializationRun: () => ok(nativeRun),
    clientProgramCheckCompiledRunDefinition: (run, definition) =>
      run === nativeRun && definition === nativeDefinition,
    clientProgramCompiledRunHasSerialization: run => run === nativeRun,
    clientProgramCompiledRunTemplate: () => nativeEvidence,
    clientProgramCompiledRunPlan: () => nativePlan,
    clientProgramCompiledRunPrepared: () => nativeEvidence,
    clientProgramCompiledRunAuthorization: () => nativeEvidence,
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramSerializationInputIdentityBind: () => ok(nativeEvidence),
    clientProgramSerializationInputArtifact: () => nativeEvidence,
    clientProgramCompleteContentStep: () => ok(nativeGeneration),
    clientProgramStartOriginalGeneratedInferInputs(run, generation, selected, inputs,
      provider, definition, originalConsumer) {
      assert.strictEqual(run, nativeRun); assert.strictEqual(generation, nativeGeneration);
      assert.strictEqual(selected, graph); assert.strictEqual(definition, nativeDefinition);
      assert.strictEqual(originalConsumer, consumer);
      const original = {}; active.push(original); return ok(original);
    },
    clientProgramReserveOriginalInferPublicationCapacity(owner) {
      assert.ok(active.includes(owner)); calls.push('reserve'); return ok(borrow);
    },
    clientProgramStartOriginalInferObservationIssuance(owner, ...args) {
      return issue([owner], ...args);
    },
    clientProgramStartCompleteOriginalInferObservationIssuance: issue,
    clientProgramSerializationGenerationEvidence() {
      assert.fail('projection must not add a second callbackful evidence validation');
    },
    clientProgramInferPublicationLedger() {assert.fail('no replacement Ledger');},
    clientProgramStartInferObservationIssuance() {assert.fail('no legacy fallback');},
    clientProgramReleaseOriginalInferPublicationCapacity: () => ok(true),
    clientProgramInferExecutionStopped: () => true,
    clientProgramCleanupInferExecution: () => ok(true),
  };
  const control = runtimeCore(moon).publicationControl;
  const definition = control.admit('run_definition', '{}',
    {maxWireBytes: 4096, maxNodes: 256, maxDepth: 16});
  const compiled = control.adoptCheckedClientEffectSerializationRun({}, definition);
  const inputEvidence = control.bindCheckedClientSerializationInputIdentity(
    compiled, {}, {}, {maxWireBytes: 4096, maxNodes: 256, maxDepth: 16});
  const generation = control.completeCheckedClientContentStep(compiled, definition,
    {}, inputEvidence, {}, {}, () => true,
    {maxNodes: 1, maxTextBytes: 0, maxDepth: 1, maxWork: 1, maxNameBytes: 1});
  const nodeInstallation = {installation: {}, layout: {},
    layoutArtifactCid: 'layout', runtimeArtifactCid: 'runtime', probability: undefined};
  const createOperation = () => openNodeInferOperation({moon, preparedProgram: {}, graph, provider: {},
    serializedInput: {control, compiled, generation, inputs: []},
    originalPreparation: {compiled, runDefinition: definition, scope: {}, read: {},
      readRetainedBytes: 7n, readExecutionBytes: 5n,
      modelRetainedBytes: 1000n, modelExecutionBytes: 500n, nodeInstallation,
      control: {claimCheckedClientInferNodePreparationLayout(run, selectedDefinition, selected) {
        assert.strictEqual(run, compiled); assert.strictEqual(selectedDefinition, definition);
        assert.strictEqual(selected, graph); return consumer;
      }, startCheckedClientInferOriginalPreparation() {
        assert.fail('serialized input must use its original generated input constructor');
      }},
      publicationCapacity() {return {retainedBytes: 123n, workspaceBytes: 456n};},
    }});
  return {moon, control, generation, nativeGeneration, calls, issued, borrow, createOperation,
    refuse(value) {refusal = value;}};
}

test('original generated publication unwraps the SAME Content facade for its native issuer', () => {
  const f = generatedOriginalFixture(), operation = f.createOperation();
  assert.notStrictEqual(f.generation, f.nativeGeneration);
  operation.reserveOriginalPublicationCapacity();
  assert.strictEqual(operation.startObservation(limits), f.issued);
  assert.deepEqual(f.calls, ['reserve', 'issue']);
  assert.equal(operation.releaseOriginalPublicationCapacity(), true);
  assert.equal(operation.cleanup(), true);
});

test('complete original generated publication unwraps Content once for its ordered owners', () => {
  const f = generatedOriginalFixture(), first = f.createOperation(), second = f.createOperation();
  second.reserveOriginalPublicationCapacity();
  assert.strictEqual(startCompleteInferObservation({moon: f.moon,
    operations: [first, second], ...limits}), f.issued);
  assert.deepEqual(f.calls, ['reserve', 'issue']);
  assert.equal(first.releaseOriginalPublicationCapacity(), true);
  assert.equal(second.releaseOriginalPublicationCapacity(), true);
  assert.equal(first.cleanup(), true); assert.equal(second.cleanup(), true);
});

test('original generated publication refuses copied foreign facades before the native issuer', () => {
  const f = generatedOriginalFixture(), foreign = generatedOriginalFixture();
  for (const generation of [{...f.generation}, f.nativeGeneration, foreign.generation]) {
    assert.throws(() => f.control.startCheckedClientOriginalContentInferObservation(
      [{}], [generation], f.borrow, limits), /Foreign Client Content generation/);
  }
  assert.deepEqual(f.calls, []);
});

test('original generated publication keeps the same native refusal and retained borrower', () => {
  const f = generatedOriginalFixture(), operation = f.createOperation();
  const original = Object.freeze({kind: 'original Core current refusal'});
  f.refuse(original); operation.reserveOriginalPublicationCapacity();
  assert.throws(() => operation.startObservation(limits), error =>
    error.code === 'RunHostContentInferObservationRejected' && error.cause === original);
  assert.equal(operation.publicationCapacityPending(), true);
  assert.deepEqual(f.calls, ['reserve', 'issue']);
  assert.equal(operation.releaseOriginalPublicationCapacity(), true);
  assert.equal(operation.cleanup(), true);
});
