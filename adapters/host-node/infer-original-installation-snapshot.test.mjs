import test from 'node:test';
import assert from 'node:assert/strict';
import {retainInferOriginalReadInstallation,
  snapshotInferOriginalCurrentStateCodec} from './infer-original-installation.mjs';

// Independent physical declaration DATA. No numerical profile, reservation,
// SDK, Store, Source or Common startup is established by these test values.
function configuration() {
  return {bootstrap:{bootstrapRetainedBytes:101n,bootstrapExecutionBytes:103n,
    maxReservations:3,maxHoldings:5,maxDelegations:7},
    modelRetainedBytes:107n,modelExecutionBytes:109n,
    nodeInstallation:{layout:{barrier_cid:'barrier',execution_bytes:113n,
      layout_artifact_cid:'layout',parameter_values_cid:'parameters',prepared_rows:1n,
      program_definition_cid:'program',response_profile:{},retained_bytes:127n,
      runtime_artifact_cid:'runtime'},installation:{},layoutArtifactCid:'layout',
      probability:undefined,runtimeArtifactCid:'runtime'},
    metadataAcquisition:{metadata:{maxLedgerEntries:11,maxWireBytes:4096},
      directory:{maxDirectoryEntries:13,maxWireBytes:4096},retainedBytes:131n,workspaceBytes:137n},
    storeBootstrap:{maxDirectoryEntries:17,maxWireBytes:4096}};
}
test('original installation snapshots the same inspected Model and bootstrap DATA values',()=>{
  const supplied=configuration();
  const bootstrap=supplied.bootstrap;let gets=0;
  supplied.bootstrap=new Proxy(bootstrap,{get(target,key,receiver){
    if(key==='bootstrapRetainedBytes')return ++gets<3?101n:9223372036854775808n;
    return Reflect.get(target,key,receiver);
  }});
  const expected=configuration();let modelReads=0;
  const source=new Proxy(supplied,{get(target,key,receiver){
    if(key==='modelRetainedBytes')return ++modelReads===1?107n:9223372036854775808n;
    return Reflect.get(target,key,receiver);
  }});
  const original=retainInferOriginalReadInstallation(source);
  assert.equal(original.modelRetainedBytes,expected.modelRetainedBytes);
  assert.deepEqual(original.bootstrap,expected.bootstrap);
  assert.equal(modelReads,0,'snapshot reads inspected DATA descriptors, not property callbacks');
  assert.equal(gets,0);
});
test('original acquisition snapshots cannot replace checked finite limits during copying',()=>{
  const supplied=configuration(),metadata=supplied.metadataAcquisition.metadata;
  let wireReads=0,workspaceReads=0;
  supplied.metadataAcquisition.metadata=new Proxy(metadata,{get(target,key,receiver){
    if(key==='maxWireBytes')return ++wireReads===1?4096:Infinity;
    return Reflect.get(target,key,receiver);
  }});
  supplied.metadataAcquisition=new Proxy(supplied.metadataAcquisition,{get(target,key,receiver){
    if(key==='workspaceBytes')return ++workspaceReads<3?137n:-1n;
    return Reflect.get(target,key,receiver);
  }});
  const original=retainInferOriginalReadInstallation(supplied);
  assert.deepEqual(original.metadataAcquisition,configuration().metadataAcquisition);
  assert.equal(wireReads,0);assert.equal(workspaceReads,0);
});
test('original nested layout and physical installation preserve inspected opaque references',()=>{
  const supplied=configuration(),node=supplied.nodeInstallation;
  const profile=node.layout.response_profile,sdk={version:'4.0.91'};
  node.installation={sdk};let reads=0;
  supplied.nodeInstallation=new Proxy(node,{get(){reads++;throw Error('No property access');}});
  node.layout=new Proxy(node.layout,{get(){reads++;throw Error('No layout access');}});
  node.installation=new Proxy(node.installation,{get(){reads++;throw Error('No installation access');}});
  const original=retainInferOriginalReadInstallation(supplied);
  assert.equal(reads,0);assert.equal(original.nodeInstallation.layout.response_profile,profile);
  assert.deepEqual(original.nodeInstallation.installation.sdk,{version:'4.0.91'});
  sdk.version='changed';assert.equal(original.nodeInstallation.installation.sdk.version,'4.0.91');
});
test('original codec and Store bootstrap keep the exact finite DATA snapshot',()=>{
  const plain={quantum:7,comparisonWork:101,decode:{maxWork:103,
    parse:{max_depth:5,max_input_bytes:4096,max_nodes:41},
    tree:{max_depth:5,max_nodes:41,max_string_bytes:4096,max_total_string_bytes:4096}}};
  let reads=0;
  const codec=new Proxy(plain,{get(){reads++;return -1;}});
  assert.deepEqual(snapshotInferOriginalCurrentStateCodec(codec),plain);
  const supplied=configuration(),bootstrap=supplied.storeBootstrap;
  supplied.storeBootstrap=new Proxy(bootstrap,{get(){reads++;return Infinity;}});
  supplied.currentStateCodec=codec;
  const original=retainInferOriginalReadInstallation(supplied);
  assert.deepEqual(original.storeBootstrap,bootstrap);
  assert.deepEqual(original.currentStateCodec,plain);assert.equal(reads,0);
});
test('accessor, hidden and symbol declaration fields refuse without invoking callbacks',()=>{
  const changes=[v=>[v,'modelRetainedBytes'],v=>[v.bootstrap,'bootstrapRetainedBytes'],
    v=>[v.nodeInstallation,'layout'],v=>[v.nodeInstallation.layout,'retained_bytes'],
    v=>[v.metadataAcquisition,'workspaceBytes'],v=>[v.metadataAcquisition.metadata,'maxWireBytes'],
    v=>[v.metadataAcquisition.directory,'maxDirectoryEntries'],v=>[v.storeBootstrap,'maxWireBytes']];
  for(const select of changes){
    const source=configuration(),[record,name]=select(source);let called=0;
    Object.defineProperty(record,name,{enumerable:true,get(){called++;return 1n;}});
    assert.throws(()=>retainInferOriginalReadInstallation(source),TypeError);
    assert.equal(called,0);
  }
  for(const change of [v=>{v[Symbol('extra')]=true;},
    v=>{Object.defineProperty(v,'modelRetainedBytes',{enumerable:false});},
    v=>{v.bootstrap.extra=true;}]) {
    const source=configuration();change(source);
    assert.throws(()=>retainInferOriginalReadInstallation(source),TypeError);
  }
});
