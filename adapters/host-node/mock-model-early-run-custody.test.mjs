import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual retained initialization functions with explicit ports.
// This checks ordering/partial custody, not a Core issuer or physical grant.
const source=readFileSync(new URL('./installed-project-mock.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const outer=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&
  node.declaration?.id?.name==='installPreparedProjectMockSources').declaration;
const functions=['sameRun','prepareManagedRun','prepareManagedMockModelRun','modelPreparation','retireModelRead'];
const slices=outer.body.body.flatMap(node=>{
  if(node.type==='FunctionDeclaration'&&functions.includes(node.id.name))return[source.slice(node.start,node.end)];
  if(node.type==='VariableDeclaration'&&node.declarations[0].id.name==='sameRun')return[source.slice(node.start,node.end)];
  return[];
}).join('\n');
assert.equal(slices.match(/(?:function |const )(?:sameRun|prepareManagedRun|prepareManagedMockModelRun|modelPreparation|retireModelRead)\b/gu).length,5);

function fixture({afterFactoryFailure,readFailure}={}){
  const calls=[],prepared={},request={},compiled={},runDefinition={},graph={},occurrence={};
  const records=new Map(),original={},admission={},value={},scope={},read={};
  let issued=false;
  const current=()=>{calls.push('current');if(issued&&afterFactoryFailure)throw afterFactoryFailure;};
  const fail=code=>{throw Object.assign(new Error(code),{code});};
  const checked=value=>value;
  const sourceManaged={prepareLocalMockModelRun(p,model){
    assert.strictEqual(p,prepared);calls.push('original');issued=true;
    model.budget={bootstrapRetainedBytes:10n,bootstrapExecutionBytes:10n,
      readRetainedBytes:10n,readExecutionBytes:10n,modelRetainedBytes:10n,modelExecutionBytes:10n};
    return original;
  },assertCurrent:current};
  const moon={clientProgramNodeLocalMockModelRunPrepare(o,p){
    assert.strictEqual(o,original);assert.strictEqual(p,prepared);calls.push('admission');return admission;
  },clientProgramInstalledManagedRunCheck(v,p,r){
    assert.strictEqual(v,value);assert.strictEqual(p,prepared);assert.strictEqual(r,request);calls.push('check');
  }};
  const control={beginCheckedClientMockModelManagedRun(a,p,r,c,d,g){
    assert.strictEqual(a,admission);assert.strictEqual(p,prepared);assert.strictEqual(r,request);
    assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);assert.strictEqual(g,graph);
    calls.push('scope');return[value,scope];
  },prepareCheckedClientInferOriginalRead(c,d,g,s){
    assert.strictEqual(c,compiled);assert.strictEqual(d,runDefinition);
    assert.strictEqual(g,graph);assert.strictEqual(s,scope);calls.push('read');
    if(readFailure)throw readFailure;return read;
  },stopCheckedClientInferOriginalReadPreparation(){calls.push('stop-read');},
  settleCheckedClientInferOriginalReadPreparation(){calls.push('settle-read');}};
  const api=new Function('current','records','fail','checked','sourceManaged','moon','runtimeField',
    slices+';return {prepareManagedMockModelRun,modelPreparation};')(
      current,records,fail,checked,sourceManaged,moon,(value,index)=>value[index]);
  const plan={compiled,runDefinition},selection={graph,occurrence};
  return{...api,calls,records,prepared,request,plan,selection,control,original,admission,value,scope,
    begin(){api.prepareManagedMockModelRun(prepared,request,control,plan,selection);}};
}

test('Mock installs its same original Run Scope before returning any Source preparation',()=>{
  const f=fixture();f.begin();
  assert(f.calls.indexOf('original')<f.calls.indexOf('admission'));
  assert(f.calls.indexOf('admission')<f.calls.indexOf('scope'));
  assert(f.calls.indexOf('scope')<f.calls.indexOf('read'));
  const held=f.records.get(f.prepared);
  assert.strictEqual(held.original,f.original);assert.strictEqual(held.admission,f.admission);
  assert.strictEqual(held.value,f.value);assert.strictEqual(held.model.scope,f.scope);
  f.begin();assert.equal(f.calls.filter(call=>call==='scope').length,1);
  assert.throws(()=>f.prepareManagedMockModelRun(f.prepared,f.request,f.control,
    {...f.plan,compiled:{}},f.selection),{code:'ForeignInstalledModelPreparation'});
});

test('Mock current failure retains the returned original and never reissues it',()=>{
  const failure=new Error('post-factory-current'),f=fixture({afterFactoryFailure:failure});
  assert.throws(()=>f.begin(),error=>error===failure);
  assert.strictEqual(f.records.get(f.prepared).original,f.original);
  assert.strictEqual(f.records.get(f.prepared).failure,failure);
  assert.throws(()=>f.begin(),error=>error===failure);
  assert.equal(f.calls.filter(call=>call==='original').length,1);
  assert.equal(f.calls.includes('scope'),false);
});

test('Mock read refusal retains the already issued Scope and its original admission',()=>{
  const failure=new Error('read-refused'),f=fixture({readFailure:failure});
  assert.throws(()=>f.begin(),error=>error===failure);
  const held=f.records.get(f.prepared);
  assert.strictEqual(held.model.scope,f.scope);assert.strictEqual(held.value,f.value);
  assert.strictEqual(held.admission,f.admission);assert.equal(held.model.read,undefined);
  assert.throws(()=>f.begin(),error=>error===failure);
  assert.equal(f.calls.filter(call=>call==='scope').length,1);
});
