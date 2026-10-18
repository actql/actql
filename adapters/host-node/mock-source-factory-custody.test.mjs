import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

const source=readFileSync(new URL('./installed-project-mock.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const select=(type,name)=>{
  const found=nodes.filter(node=>node.type===type&&(node.id?.name??node.key?.name)===name);
  assert.equal(found.length,1);return source.slice(found[0].start,found[0].end);
};
const make=compileFunction(`
  const {sourceManaged,moon,declaration}=input,index=0;
  let record=input.record;
  const current=()=>sourceManaged.assertCurrent();
  const sameRun=()=>{current();return record;};
  ${select('FunctionDeclaration','prepareManagedRun')}
  ${select('FunctionDeclaration','closeSource')}
  const reader={${select('Property','prepareSourceRead')}};
  return {prepareManagedRun,reader,closeSource,held:()=>record};`,['input','checked','fail']);
const fail=code=>{throw Object.assign(new Error(code),{code});};

// Execute actual installed caller statements with explicit stopping Resource,
// Core and physical-close ports. No scalar Ledger or capacity is supplied.
test('same Source child and close are held before post-factory current refusal and Core use stays zero',async()=>{
  const failure=new Error('OriginalGenerationChanged');let current=true,closes=0,core=0;
  const declaration={},prepared={},record={prepared,original:{},value:{},reads:[undefined,undefined]};
  const raw={close(){assert.strictEqual(this,raw);closes++;return {pending:false};},
    readOriginalBytes(){assert.fail('No physical read');}};
  const sourceManaged={assertCurrent(){if(!current)throw failure;},prepareRead(){current=false;return raw;}};
  const f=make({sourceManaged,declaration,record,moon:{
    clientProgramInstalledManagedRunSourceRead(){core++;assert.fail('No stale Core use');}}},value=>value,fail);
  assert.throws(()=>f.reader.prepareSourceRead({checkedOwner:prepared,effectful:false,
    declaration,occurrence:{stage:0,input:0}}),error=>error===failure);
  assert.strictEqual(record.reads[0].raw,raw);assert.equal(core,0);
  raw.close=()=>assert.fail('Replacement close must not run');
  await f.closeSource(0);assert.equal(closes,1);assert.equal(record.reads[0].closed,true);
});

test('same managed Run original is retained before post-factory current refusal and typed start stays zero',()=>{
  const failure=new Error('OriginalRunGenerationChanged'),original={};let current=true,starts=0;
  const sourceManaged={assertCurrent(){if(!current)throw failure;},prepareRun(){current=false;return original;}};
  const f=make({sourceManaged,moon:{clientProgramNodeManagedRunPrepare(){starts++;assert.fail('No stale start');}}},value=>value,fail);
  const prepared={},request={};
  assert.throws(()=>f.prepareManagedRun(prepared,request),error=>error===failure);
  assert.strictEqual(f.held().original,original);assert.strictEqual(f.held().failure,failure);
  assert.equal(f.held().admission,undefined);assert.equal(starts,0);
});

test('foreign Source occurrence still refuses before acquiring any child',()=>{
  let acquisitions=0;const declaration={},prepared={},record={prepared,original:{},value:{},reads:[undefined,undefined]};
  const f=make({declaration,record,sourceManaged:{assertCurrent(){},prepareRead(){acquisitions++;}},moon:{}},value=>value,fail);
  for(const facts of [{declaration:{},occurrence:{stage:0,input:0}},
    {declaration,occurrence:{stage:1,input:0}},{declaration,occurrence:{stage:0,input:1}}]){
    assert.throws(()=>f.reader.prepareSourceRead({checkedOwner:prepared,effectful:false,...facts}),
      {code:'InstalledSourcePreparationMismatch'});
  }
  assert.equal(acquisitions,0);assert.equal(record.reads[0],undefined);
});
