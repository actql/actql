import test from 'node:test';
import assert from 'node:assert/strict';
import {retainInferOriginalReadInstallation,
  selectedInferOriginalPublicationCapacity} from './infer-original-installation.mjs';

// Independent physical declaration DATA, not a Common profile or reservation.
const configuration=publicationCapacity=>({
  bootstrap:{bootstrapRetainedBytes:1n,bootstrapExecutionBytes:0n,
    maxReservations:1,maxHoldings:1,maxDelegations:1},
  modelRetainedBytes:1n,modelExecutionBytes:0n,
  nodeInstallation:{layout:{barrier_cid:'barrier',execution_bytes:0n,
    layout_artifact_cid:'layout',parameter_values_cid:'parameters',prepared_rows:0n,
    program_definition_cid:'program',response_profile:{},retained_bytes:1n,
    runtime_artifact_cid:'runtime'},installation:{},layoutArtifactCid:'layout',
    probability:undefined,runtimeArtifactCid:'runtime'},
  ...(publicationCapacity===undefined?{}:{publicationCapacity}),
});

test('publication declaration is immutable and selected only from the same retained original',()=>{
  const amounts={retainedBytes:101n,workspaceBytes:203n};
  const supplied=configuration(amounts);
  const original=retainInferOriginalReadInstallation(supplied);
  const selected=selectedInferOriginalPublicationCapacity(original,original.nodeInstallation);
  amounts.retainedBytes=1n;amounts.workspaceBytes=2n;
  assert.deepEqual(selected,{retainedBytes:101n,workspaceBytes:203n});
  assert.ok(Object.isFrozen(selected));
  assert.strictEqual(selectedInferOriginalPublicationCapacity(original,original.nodeInstallation),selected);
  assert.throws(()=>selectedInferOriginalPublicationCapacity(supplied,supplied.nodeInstallation),
    {code:'InferOriginalPublicationCapacityUnavailable'});
});

test('copied original and independently matching node selections cannot select publication amounts',()=>{
  const original=retainInferOriginalReadInstallation(configuration({retainedBytes:17n,workspaceBytes:19n}));
  const foreign=retainInferOriginalReadInstallation(configuration({retainedBytes:17n,workspaceBytes:19n}));
  for(const [owner,node] of [[{...original},original.nodeInstallation],
    [original,{...original.nodeInstallation}],[original,foreign.nodeInstallation],
    [undefined,original.nodeInstallation]]) {
    assert.throws(()=>selectedInferOriginalPublicationCapacity(owner,node),
      {code:'InferOriginalPublicationCapacityUnavailable'});
  }
});

test('missing publication supply remains unavailable without changing existing read amounts',()=>{
  const original=retainInferOriginalReadInstallation(configuration());
  assert.equal(original.publicationCapacity,undefined);
  assert.equal(original.modelRetainedBytes,1n);assert.equal(original.modelExecutionBytes,0n);
  assert.throws(()=>selectedInferOriginalPublicationCapacity(original,original.nodeInstallation),
    {code:'InferOriginalPublicationCapacityUnavailable'});
});

test('publication amounts reject malformed, numeric, negative, overflow and accessor declarations',()=>{
  let getterCalls=0;
  const getter={workspaceBytes:1n};
  Object.defineProperty(getter,'retainedBytes',{enumerable:true,get(){getterCalls++;return 1n;}});
  for(const amounts of [null,[],{}, {retainedBytes:1n}, {workspaceBytes:1n},
    {retainedBytes:0n,workspaceBytes:1n},{retainedBytes:-1n,workspaceBytes:1n},
    {retainedBytes:1n,workspaceBytes:-1n},{retainedBytes:1,workspaceBytes:1n},
    {retainedBytes:1n,workspaceBytes:1},{retainedBytes:9223372036854775808n,workspaceBytes:0n},
    {retainedBytes:1n,workspaceBytes:9223372036854775808n},
    {retainedBytes:1n,workspaceBytes:1n,allow:true},getter]) {
    assert.throws(()=>retainInferOriginalReadInstallation(configuration(amounts)),
      /InvalidInstalledInferPublicationCapacity/);
  }
  assert.equal(getterCalls,0);
});

test('exact Int64 amounts and explicit zero scratch remain DATA, not adequate funding',()=>{
  const amounts={retainedBytes:9223372036854775807n,workspaceBytes:0n};
  const original=retainInferOriginalReadInstallation(configuration(amounts));
  assert.deepEqual(selectedInferOriginalPublicationCapacity(original,original.nodeInstallation),amounts);
  assert.deepEqual(Object.keys(original.nodeInstallation).sort(),
    ['installation','layout','layoutArtifactCid','probability','runtimeArtifactCid']);
  // No Core/Resource/Model/Store/SDK port is invoked by declaration selection.
  // In particular this case is not a physical zero-workspace installation.
});


test('publication snapshot uses checked descriptor values once',()=>{
  const data={retainedBytes:101n,workspaceBytes:203n};
  const reads={retainedBytes:0,workspaceBytes:0};
  const supplied=new Proxy(data,{get(target,key,receiver){
    if(key==='retainedBytes')return ++reads.retainedBytes===1?101n:9223372036854775808n;
    if(key==='workspaceBytes')return ++reads.workspaceBytes===1?203n:-1n;
    return Reflect.get(target,key,receiver);
  }});
  const original=retainInferOriginalReadInstallation(configuration(supplied));
  const selected=selectedInferOriginalPublicationCapacity(original,original.nodeInstallation);
  assert.deepEqual(selected,data,'the same validated descriptor DATA is retained');
  assert.deepEqual(reads,{retainedBytes:0,workspaceBytes:0},'property callbacks cannot replace validated DATA');
  assert.ok(Object.isFrozen(selected));
});
