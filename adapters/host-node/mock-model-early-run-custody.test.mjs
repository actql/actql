import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual retained initialization functions with explicit ports.
// This checks ordering/partial custody, not a Core issuer or physical grant.
// Execute the unchanged shared retirement body with the existing explicit
// completion-observer port; the private runtime marker is not manufactured.
const retirementSource = readFileSync(new URL('./infer-operation.mjs', import.meta.url), 'utf8');
const retirementNode = parse(retirementSource, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.declaration?.id?.name === 'retireNodeInferOriginalRead').declaration;
const retirementFor = observer => Function('inferOriginalReadCleanupComplete',
  'return ' + retirementSource.slice(retirementNode.start, retirementNode.end))(observer);
const source=readFileSync(new URL('../local-node/installed-project-mock.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const outer=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&
  node.declaration?.id?.name==='installPreparedProjectMockSources').declaration;
const functions=['sameRun','prepareManagedRun','prepareManagedMockModelRun','modelPreparation','retireModelRead',
  'closeSource','closeRead','closePhysicalRead','close','retireRunRecord'];
const slices=outer.body.body.flatMap(node=>{
  if(node.type==='FunctionDeclaration'&&functions.includes(node.id.name))return[source.slice(node.start,node.end)];
  if(node.type==='VariableDeclaration'&&['sameRun','close'].includes(node.declarations[0].id.name))return[source.slice(node.start,node.end)];
  return[];
}).join('\n');
assert.equal(slices.match(/(?:function |const )(?:sameRun|prepareManagedRun|prepareManagedMockModelRun|modelPreparation|retireModelRead)\b/gu).length,5);

function fixture({afterFactoryFailure,readFailure,settleFailure,acquisitionCount=2}={}){
  const calls=[],prepared={},request={},compiled={},compilation={},runDefinition={},graph={},occurrence={};
  const records=new Map(),original={},value={},scope={},read={};
  const sources=[],closedSources=new Set(),sourceReady=[true,true],sourceCloseCalls=[0,0];
  const cleanedModelReads=new WeakSet(),settledReads=new WeakSet();
  const cleanup={settleFailure};
  let issued=false,readIssued=false;
  const current=()=>{calls.push('current');if(issued&&afterFactoryFailure)throw afterFactoryFailure;};
  const fail=code=>{throw Object.assign(new Error(code),{code});};
  const checked=value=>value;
  const prepareOwnedModel=(p,model)=>{
    assert.strictEqual(p,prepared);calls.push('original');issued=true;
    model.budget={bootstrapRetainedBytes:10n,bootstrapExecutionBytes:10n,
      readRetainedBytes:10n,readExecutionBytes:10n,modelRetainedBytes:10n,modelExecutionBytes:10n};
    return original;
  };
  const sourceManaged={assertCurrent:current};
  const setup={},providers=[{}];
  const moon={clientProgramAcquisitionCount:p=>{assert.strictEqual(p,prepared);return acquisitionCount;},
    clientProgramOpenInstalledManagedSourceFreeComposedInferHost(v,p,r,registry,values,fragment,ordered,actualProviders){
      assert.strictEqual(v,value);assert.strictEqual(p,prepared);assert.strictEqual(r,request);
      assert.deepEqual([registry,values,fragment,ordered],['registry','values','fragment','ordered']);
      assert.strictEqual(actualProviders,providers);calls.push('open-source-free');return setup;
    },clientProgramInstalledManagedRunCheck(v,p,r){
    assert.strictEqual(v,value);assert.strictEqual(p,prepared);assert.strictEqual(r,request);calls.push('check');
  },clientProgramInstalledSourceReadRetire(){calls.push('retire-source');},
  clientProgramInstalledManagedRunRetire(v){assert.strictEqual(v,value);calls.push('retire-parent');}};
  const control={prepareCheckedClientInferOriginalRead(c,d,g,s){
    assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);
    assert.strictEqual(g,graph);assert.strictEqual(s,scope);calls.push('read');
    if(readFailure)throw readFailure;readIssued=true;return read;
  },stopCheckedClientInferOriginalReadPreparation(){
    if(settledReads.has(read))throw new Error('SpentClaim');
    calls.push('stop-read');
  },
  settleCheckedClientInferOriginalReadPreparation(c,d,g,original,complete){
    assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);assert.strictEqual(g,graph);
    assert.strictEqual(original,read);assert.equal(complete,true);
    if(settledReads.has(read))throw new Error('SpentClaim');
    calls.push('settle-read');
    if(cleanup.settleFailure!==undefined)throw cleanup.settleFailure;
    settledReads.add(read);
  },
  finishCheckedClientInferOriginalReadScope(){calls.push('finish-scope');return !readIssued||settledReads.has(read);}};

  let releaseRequestAliases;
  const prepareRequestModel=(p,r,model)=>{
    assert.strictEqual(p,prepared);assert.strictEqual(r,request);
    assert.strictEqual(records.get(prepared).model,model);
    // Existing trusted Host port, not the removed Local standalone issuer.
    prepareOwnedModel(p,model);
    model.scope=scope;calls.push('scope');
    releaseRequestAliases=()=>Reflect.apply(model.releaseAliases,model,[]);
    return{original,value};
  };
  const api=new Function('current','records','fail','checked','sourceManaged','moon','runtimeField','sources','closedSources','retireNodeInferOriginalRead','prepareRequestModel',
    'let closing=false;const effectRuns=new WeakMap(),effectReads=new Set();'+slices+';return {prepareManagedRun,prepareManagedMockModelRun,modelPreparation,close,closeSource};')(
      current,records,fail,checked,sourceManaged,moon,(value,index)=>value[index],sources,closedSources,
      retirementFor(value=>cleanedModelReads.has(value)),prepareRequestModel);
  sources.push(...[0,1].map(index=>({close:()=>api.closeSource(index)})));
  const plan={compiled,runDefinition},selection={graph,occurrence};
  return{...api,calls,records,prepared,request,plan,selection,compilation,control,original,value,scope,
    sourceReady,sourceCloseCalls,cleanup,setup,providers,
    releaseRequestAliases:()=>releaseRequestAliases(),
    loseCurrent(error){afterFactoryFailure=error;},originalModelCleaned:()=>cleanedModelReads.add(read),
    begin(){api.prepareManagedMockModelRun(prepared,request,control,plan,selection);},
    attachSources(){
      records.get(prepared).reads=[0,1].map(index=>({source:index,raw:{index},value:{index},closed:false,
        close(){sourceCloseCalls[index]++;return{pending:!sourceReady[index]};}}));
    }};
}

test('source-free Mock opens its Local driver on the same original Run and Scope exactly once',()=>{
  const f=fixture({acquisitionCount:0});f.begin();
  const preparation=f.modelPreparation(f.prepared,f.plan);
  assert.throws(()=>preparation.openSourceFreeHost('registry','values','fragment','ordered',f.providers),
    {code:'ForeignInstalledModelPreparation'});
  preparation.retain();
  assert.strictEqual(preparation.openSourceFreeHost('registry','values','fragment','ordered',f.providers),f.setup);
  assert(f.calls.indexOf('scope')<f.calls.indexOf('open-source-free'));
  assert.equal(f.calls.includes('read'),false);
  assert.throws(()=>preparation.openSourceFreeHost('registry','values','fragment','ordered',f.providers),
    {code:'ForeignInstalledModelPreparation'});
  assert.equal(f.calls.filter(value=>value==='open-source-free').length,1);
});

test('source-free Mock driver entry does not replace a captured or Effect Run',()=>{
  for(const acquisitionCount of [2,0]){
    const f=fixture({acquisitionCount});f.begin();if(acquisitionCount===0)f.records.get(f.prepared).effectful=true;
    const preparation=f.modelPreparation(f.prepared,f.plan);
    preparation.retain();
    assert.throws(()=>preparation.openSourceFreeHost('registry','values','fragment','ordered',f.providers),
      {code:'ForeignInstalledModelPreparation'});
    assert.equal(f.calls.includes('open-source-free'),false);
  }
});

test('source-free Mock retains its original Scope when currentness refuses before Local open',()=>{
  const f=fixture({acquisitionCount:0});f.begin();const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();const failure=new Error('OriginalHostChanged');f.loseCurrent(failure);
  assert.throws(()=>preparation.openSourceFreeHost('registry','values','fragment','ordered',f.providers),error=>error===failure);
  assert.strictEqual(f.records.get(f.prepared).model.scope,f.scope);
  assert.equal(f.calls.includes('open-source-free'),false);
});

test('Mock installs its same original Run Scope before returning any Source preparation',()=>{
  const f=fixture();f.begin();
  assert(f.calls.indexOf('original')<f.calls.indexOf('scope'));
  assert.equal(f.calls.includes('admission'),false);
  assert.equal(f.calls.includes('read'),false);
  const held=f.records.get(f.prepared);
  assert.strictEqual(held.original,f.original);assert.equal(held.admission,undefined);
  assert.strictEqual(held.value,f.value);assert.strictEqual(held.model.scope,f.scope);
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();
  const read=preparation.prepareRead();
  assert.strictEqual(read.scope,f.scope);
  assert(f.calls.indexOf('scope')<f.calls.indexOf('read'));
  assert.throws(()=>preparation.prepareRead(),{code:'ForeignInstalledModelPreparation'});
  f.begin();assert.equal(f.calls.filter(call=>call==='scope').length,1);
  assert.throws(()=>f.prepareManagedMockModelRun(f.prepared,f.request,f.control,
    {...f.plan,compiled:{}},f.selection),{code:'ForeignInstalledModelPreparation'});
});

test('legacy Effect Mock refuses before any independent admission or Scope',()=>{
 const f=fixture();
 assert.throws(()=>f.prepareManagedRun(f.prepared,f.request,undefined,true),{code:'InvalidInstalledManagedRunRequest'});
 assert.equal(f.records.size,0);assert.equal(f.calls.includes('original'),false);assert.equal(f.calls.includes('scope'),false);
});

test('Request Mock current failure retains the adopted original and Scope without reissuing',()=>{
  const failure=new Error('post-factory-current'),f=fixture({afterFactoryFailure:failure});
  assert.throws(()=>f.begin(),error=>error===failure);
  assert.strictEqual(f.records.get(f.prepared).original,f.original);
  assert.strictEqual(f.records.get(f.prepared).failure,failure);
  assert.throws(()=>f.begin(),error=>error===failure);
  assert.equal(f.calls.filter(call=>call==='original').length,1);
  assert.equal(f.calls.filter(x=>x==='scope').length,1);
});

test('Mock read refusal retains the already issued Scope and its original admission',()=>{
  const failure=new Error('read-refused'),f=fixture({readFailure:failure});
  f.begin();
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();
  assert.throws(()=>preparation.prepareRead(),error=>error===failure);
  const held=f.records.get(f.prepared);
  assert.strictEqual(held.model.scope,f.scope);assert.strictEqual(held.value,f.value);
  assert.equal(held.admission,undefined);assert.equal(held.model.read,undefined);
  assert.strictEqual(held.model.readFailure,failure);
  assert.throws(()=>preparation.prepareRead(),error=>error===failure);
  assert.equal(f.calls.filter(call=>call==='scope').length,1);
});

test('Mock close keeps both originals until Source and Model cleanup acknowledge separately',async()=>{
  const f=fixture();f.begin();f.attachSources();
  const record=f.records.get(f.prepared),model=record.model;
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();preparation.prepareRead();
  f.sourceReady[0]=false;
  await assert.rejects(f.close(),{message:'InstalledMockSourceCleanupPending'});
  assert.deepEqual(f.sourceCloseCalls,[1,1]);
  assert.strictEqual(record.original,f.original);assert.strictEqual(model.scope,f.scope);
  assert.equal(f.calls.includes('settle-read'),false);
  assert.equal(f.calls.includes('retire-parent'),false);
  f.sourceReady[0]=true;
  await assert.rejects(f.close(),{message:'InstalledMockSourceCleanupPending'});
  assert.deepEqual(f.sourceCloseCalls,[2,1]);
  assert.strictEqual(record.original,f.original);
  assert.equal(f.calls.includes('settle-read'),false);
  // This port models the SAME Model child's completed cleanup, not primary
  // Source close, currentness, a copied Boolean or a new resource original.
  assert.equal(await preparation.retire(),true);
  await f.close();
  assert.equal(f.records.size,0);
  assert.strictEqual(record.original,f.original);assert.strictEqual(model.scope,f.scope);
  // Only the later Host payload-sever continuation retires these aliases.
  f.releaseRequestAliases();
  assert.equal(record.original,undefined);assert.equal(model.scope,undefined);
  assert.equal(model.closed,true);
  assert.throws(()=>preparation.retain(),{code:'ForeignInstalledModelPreparation'});
  assert.throws(()=>preparation.prepareRead(),{code:'ForeignInstalledModelPreparation'});
  await f.close();
  assert.deepEqual(f.sourceCloseCalls,[2,1]);
  assert.equal(f.calls.filter(call=>call==='retire-parent').length,0);
});

test('Mock retirement settles its separate original read after Model cleanup exactly once',async()=>{
  const f=fixture();f.begin();f.attachSources();
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();preparation.prepareRead();
  // This explicit port models the fixed operation Owner's observation after
  // its actual Core cleanup. It is not a public setter or a new physical ACK.
  f.originalModelCleaned();
  assert.equal(await preparation.retire(),true);
  assert.equal(f.calls.includes('stop-read'),false);
  assert.equal(f.calls.filter(value=>value==='settle-read').length,1);
  assert.equal(f.calls.filter(value=>value==='finish-scope').length,1);
  assert.equal(f.calls.filter(value=>value==='retire-parent').length,0);
  assert.equal(await preparation.retire(),true);
  assert.equal(f.calls.filter(value=>value==='settle-read').length,1);
  await f.close();
  assert.deepEqual(f.sourceCloseCalls,[1,1]);
});

test('Mock read settlement refusal retains its same descriptor until original retry succeeds',async()=>{
  const issue=new Error('OriginalReadSettlementPending'),f=fixture({settleFailure:issue});
  f.begin();f.attachSources();
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();preparation.prepareRead();f.originalModelCleaned();
  const record=f.records.get(f.prepared),originalRead=record.model.read;
  await assert.rejects(preparation.retire(),error=>error===issue);
  assert.strictEqual(record.model.read,originalRead);
  assert.equal(f.calls.includes('finish-scope'),false);
  assert.equal(f.calls.includes('retire-parent'),false);
  f.cleanup.settleFailure=undefined;
  assert.equal(await preparation.retire(),true);
  assert.equal(record.model.read,undefined);
  assert.equal(f.calls.filter(value=>value==='settle-read').length,2);
  assert.equal(f.calls.filter(value=>value==='retire-parent').length,0);
});

test('Mock pending Source custody prevents settlement of the separate original read',async()=>{
  const f=fixture();f.begin();f.attachSources();
  const preparation=f.modelPreparation(f.prepared,f.plan);
  preparation.retain();preparation.prepareRead();f.originalModelCleaned();
  const originalRead=f.records.get(f.prepared).model.read;
  f.sourceReady[0]=false;
  await assert.rejects(preparation.retire(),{code:'InstalledMockSourceCleanupPending'});
  assert.strictEqual(f.records.get(f.prepared).model.read,originalRead);
  assert.equal(f.calls.includes('settle-read'),false);
  f.sourceReady[0]=true;
  assert.equal(await preparation.retire(),true);
  assert.equal(f.calls.filter(value=>value==='settle-read').length,1);
  assert.deepEqual(f.sourceCloseCalls,[2,1]);
});
