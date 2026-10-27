import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';

// Actual enclosing row-stage loop/callees. Core inventory, checked Preview,
// driver request/claim, Resource and physical ports are explicit here.
const source=await readFile(new URL('./installed-row-effect.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function walk(node,parents=[]){
  if(!node||typeof node!=='object')return;
  if(typeof node.type==='string')nodes.push({node,parents});
  for(const value of Object.values(node))if(Array.isArray(value))value.forEach(n=>walk(n,[...parents,node]));else if(value&&typeof value==='object')walk(value,[...parents,node]);
}
walk(ast);
const variable=name=>{
  const found=nodes.filter(({node})=>node.type==='VariableDeclarator'&&node.id.name===name);
  assert.equal(found.length,1,name);return found[0].node.init;
};
const expression=(name,ports)=>Function(...Object.keys(ports),`return (${source.slice(variable(name).start,variable(name).end)});`)(...Object.values(ports));
const capture=nodes.find(({node})=>node.type==='FunctionDeclaration'&&node.id.name==='captureStage').node;
const loops=capture.body.body.filter(n=>n.type==='ForOfStatement'&&n.body.body.some(statement=>statement.type==='VariableDeclaration'&&statement.declarations.some(d=>d.id.name==='description')));
assert.equal(loops.length,1);
const loop=loops[0];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const checked=value=>{if(value.error)throw value.error;return value.ok;};
const cid=character=>`sha256:${character.repeat(64)}`;
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const member=Object.freeze({kind:'create',effectId:'create',memberIndex:0});
const input=[{label:'b'},{label:'a'},{label:'a'}];
const issued=[{content_cid:cid('a'),occurrence:0},{content_cid:cid('a'),occurrence:1},{content_cid:cid('b'),occurrence:0}];
function fixture({child=false,inventoryError}={}){
  const events=[],contexts=[],requests=[],requestChildren=[],runOriginal=Object.freeze({}),description=Object.freeze({original:true});
  let inventoryCalls=0;
  const moon={clientProgramEffectCreateRowInventory(wires,count,bytes,nodes,depth){
    inventoryCalls++;events.push('inventory');
    assert.deepEqual(wires,input.map(value=>JSON.stringify({state:'present',value})));
    assert.deepEqual([count,bytes,nodes,depth],[3,10000,100,10]);
    if(inventoryError)throw inventoryError;
    return {ok:[1,2,0].map((index,i)=>runtimeTupleFromFields({0:index,1:JSON.stringify(issued[i])}))};
  }};
  const prepare=context=>{
    assert.equal(inventoryCalls,1,'Common original identity must exist before provider preparation');
    assert.strictEqual(context.runOriginal,runOriginal);
    assert.strictEqual(context.current,description);
    assert.deepEqual(context.createRowIdentity,issued[contexts.length]);
    assert(Object.isFrozen(context.createRowIdentity));
    contexts.push(context);events.push('prepare');
    const request=Object.freeze({value:context.value}),requestCid=cid(String(contexts.length));
    requests.push(request);return {request,requestCid};
  };
  const owned={describe(){return description;},requestFacts:request=>({value:request.value,target:undefined}),
    prepareRequest:prepare,
    ...(child?{prepareRequestChild(context){
      const result=prepare(context);let pending=true;
      return {async prepare(){events.push('child prepare');assert.equal(requestChildren.length,contexts.length);return result;},
        release(){pending=false;},retry(){pending=false;},status(){return {pending};}};
    }}:{})};
  const ownerOf=value=>{assert.strictEqual(value,member);return {owned};};
  const limits={preview:{maxWireBytes:10000,maxNodes:100,maxDepth:10},maxRows:3};
  const canonicalRows=expression('canonicalRows',{limits,moon,checked,runtimeField,fail,parseExactJson:JSON.parse});
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const requestEntry=expression('requestEntry',{entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),targeted:()=>false,fail});
  const resourceFields=value=>{assert.strictEqual(value,member);return {runOriginal};};
  const commandContentRow=()=>undefined;
  const requestsOf=expression('requestsOf',{ownerOf,requestEntry,resourceFields,commandContentRow});
  const ports={members:[member],ownerOf,assertCurrent(){events.push('current');},
    proposals:[input.map(value=>({changesWire:JSON.stringify({value})}))],
    runInvocationCid:cid('c'),dispatches:[cid('d')],reads:[undefined],signal:undefined,
    resourceFields,currents:[],rowsOf:[],observations:[],commandContentBorrower:()=>assert.fail('No Command borrow'),
    control:{},prepared:{},inputs:{},sourceSet:{members:[{payload:{}}]},limits,
    contentBorrowers:[],targeted:()=>false,guarded:()=>false,contentOwner:undefined,
    requestChildren,prepareInstalledRowCaptureChild,commandContentRow,requestEntry,requestsOf,canonicalRows,fail};
  const run=()=>Function(...Object.keys(ports),`return (async()=>{${source.slice(loop.start,loop.end)};return {rowsOf,observations,currents};})();`)(...Object.values(ports));
  return {run,contexts,events,requestChildren,inventoryCalls:()=>inventoryCalls,entryOf,ownerOf,owned,runOriginal};
}

test('create original occurrence reaches synchronous provider before request and stays in canonical Preview frame',async()=>{
  const f=fixture();const result=await f.run();
  assert.equal(f.inventoryCalls(),1);assert.deepEqual(f.contexts.map(value=>value.value),[input[1],input[2],input[0]]);
  assert.equal(result.rowsOf[0].length,3);assert(Object.isFrozen(result.rowsOf[0]));
  result.rowsOf[0].forEach((row,index)=>{assert(Object.isFrozen(row));assert.strictEqual(row.identity,f.contexts[index].createRowIdentity);assert.strictEqual(row.entry.value,f.contexts[index].value);});
  assert(f.events.indexOf('inventory')<f.events.indexOf('prepare'));
});

test('create original occurrence reaches retained request child before its first await',async()=>{
  const f=fixture({child:true});const result=await f.run();
  assert.equal(f.inventoryCalls(),1);assert.equal(f.requestChildren.length,3);
  assert.deepEqual(result.rowsOf[0].map(row=>row.identity),issued);
  for(const child of f.requestChildren){assert.equal(child.prepared.status().pending,true);await child.prepared.release();assert.equal(child.prepared.status().pending,false);}
});

test('create original inventory failure retains exact cause before sync or child provider construction',async()=>{
  const primary=Object.assign(new Error('original inventory refusal'),{cleanupHandle:Object.freeze({original:true})});
  for(const child of [false,true]){
    const f=fixture({child,inventoryError:primary});await assert.rejects(f.run(),error=>error===primary);
    assert.equal(f.inventoryCalls(),1);assert.equal(f.contexts.length,0);assert.equal(f.requestChildren.length,0);
  }
});

test('create cold request preparation receives same admitted Preview identities without issuing another inventory',()=>{
  const identities=issued.map(value=>Object.freeze({...value})),seen=[],claims=identities.map((_,i)=>({canonicalRequestCid:cid(String(i+1))}));
  const changes=identities.map((identity,i)=>({target_row_identity:identity,after:{value:input[[1,2,0][i]]}}));
  const owned={prepareRequest(context){assert.strictEqual(context.createRowIdentity,identities[seen.length]);seen.push(context);
    return {request:{value:context.value},requestCid:claims[seen.length-1].canonicalRequestCid};},requestFacts:request=>({value:request.value,target:undefined})};
  const ownerOf=()=>({owned});
  const entryOf=expression('entryOf',{ownerOf,cidPattern:/^sha256:[0-9a-f]{64}$/,targeted:()=>false,fail});
  const recover=expression('recoveredEntries',{singular:{owned},members:[member],ownerOf,resourceFields:()=>({runOriginal:{}}),
    orderedSourceIndexes:()=>[0,1,2],entryOf,sameEffectValue:(_kind,a,b)=>same(a,b),approvedValue:(_kind,change)=>change.after.value,targeted:()=>false,fail});
  const result=recover({members:[member],body:{effects:[{changes}]},durable:{},recorded:{members:[{claims}]},previewWire:'original approved Preview',runInvocationCid:cid('c'),dispatches:[cid('d')]});
  assert.equal(seen.length,3);assert.equal(result.entries[0].length,3);
});
