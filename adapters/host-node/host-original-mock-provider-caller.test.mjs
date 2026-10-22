import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;
  nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const selected=nodes.filter(node=>node.type==='TryStatement'&&
  node.block.body[0]?.type==='IfStatement'&&
  source.slice(node.block.body[0].test.start,node.block.body[0].test.end)==='mockModels === undefined'&&
  source.slice(node.block.start,node.block.end).includes('clientProgramAdmitOriginalMockProvider'));
assert.equal(selected.length,1);
const make=compileFunction('let admittedProvider;'+source.slice(selected[0].start,selected[0].end)+
  ';return admittedProvider;',
  ['moon','execution','dependencies','mockModels','modelProviders','preparedProgram',
    'selectedStep','occurrence','admitInstalledModelProvider','checked','diagnostic','clientOperationError']);
const fail=code=>Object.assign(new Error(code),{code});

// Exact Host caller, with explicit stopping Model ports. Common's prompt,
// nominal installation and execution/dependency checks are tested separately
// by their real Owner; this test cannot issue a Provider or physical admission.
test('Host passes only the same original Mock installation execution and dependencies to its typed Owner',()=>{
  const installation={},execution={},dependencies={},prepared={},admitted={},models={};
  let calls=0,currents=0;
  models.forTaskCid=(runtime,cid)=>{assert.strictEqual(runtime,moon);
    assert.equal(cid,'original-task');return {installation};};
  models.originalsForRuntime=runtime=>{assert.strictEqual(runtime,moon);currents++;};
  const moon={clientProgramInferModelTaskCid(value,step){
    assert.strictEqual(value,prepared);assert.equal(step,7);return 'original-task';},
    clientProgramAdmitOriginalMockProvider(...args){
      assert.deepEqual(args,[installation,execution,dependencies]);calls++;return admitted;}};
  const value=make(moon,execution,dependencies,models,new Map(),prepared,7,undefined,
    ()=>assert.fail('No configured physical Provider admission'),value=>value,
    ()=>assert.fail('No rejection'),fail);
  assert.strictEqual(value,admitted);assert.equal(calls,1);assert.equal(currents,1);
});

test('Host refuses a missing original Task without substituting a configured Provider or validator',()=>{
  let typed=0,physical=0;
  const moon={clientProgramInferModelTaskCid:()=> 'foreign-task',
    clientProgramAdmitOriginalMockProvider(){typed++;assert.fail('No original installation');}};
  const models={forTaskCid:()=>undefined};
  assert.throws(()=>make(moon,{}, {},models,new Map(),{},0,undefined,
    ()=>{physical++;},value=>value,()=>{},fail),{code:'ClientProgramUnsupported'});
  assert.equal(typed,0);assert.equal(physical,0);
});

test('ordinary physical Provider caller remains unchanged and never reads the Mock port',()=>{
  const execution={},dependencies={},providers=new Map(),admitted={};let calls=0;
  const moon={get clientProgramAdmitOriginalMockProvider(){assert.fail('No Mock selection');}};
  assert.strictEqual(make(moon,execution,dependencies,undefined,providers,{},0,undefined,
    (...args)=>{assert.deepEqual(args,[moon,execution,dependencies,providers]);calls++;return admitted;},
    ()=>assert.fail('No additional result decoding'),()=>assert.fail('No rejection'),fail),admitted);
  assert.equal(calls,1);
});
