import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
const root=process.env.SNAPSHOT_RELAY_SOURCE_ROOT;
function source(name){return readFileSync(root?`${root}/adapters/host-common/${name}`:new URL(`../host-common/${name}`,import.meta.url),'utf8');}
function find(source,predicate){const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let found;function walk(n){if(!n||typeof n!=='object')return;if(predicate(n))found=n;for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(walk);else if(x&&typeof x==='object')walk(x);}}walk(ast);assert(found);return found;}
const checked=value=>{if(value.$tag===0)throw value._0;return value._0;};
const ok=value=>({$tag:1,_0:value});
function snapshot(moon){const text=source('runtime-core.mjs'),node=find(text,n=>n.type==='Property'&&n.key?.name==='admitCompletedResultSnapshot');return new Function('moon','checked','inspectSnapshot','issuanceLimits',`return async function(${node.value.params.map(p=>p.name).join(',')})${text.slice(node.value.body.start,node.value.body.end)}`)(moon,checked,x=>x,new Function(`return ${text.slice(find(text,n=>n.type==='VariableDeclarator'&&n.id?.name==='issuanceLimits').init.start,find(text,n=>n.type==='VariableDeclarator'&&n.id?.name==='issuanceLimits').init.end)}`)());}
const policy=()=>({maxWireBytes:101,maxWireNodes:103,maxWireDepth:107,maxNodes:109,maxDepth:113,maxLogicalWireBytes:2000003,maxLogicalWireNodes:300007,maxLogicalWireDepth:73});
test('snapshot writer uses distinct original logical byte/node/depth fields, not payload or contract bounds',async()=>{
 const handle={},prep={},result={},calls=[];const run=snapshot({strategyHostOutputSnapshotBegin(...args){calls.push(args);return ok(prep);},strategyHostOutputSnapshotAdvance(value,q){assert.equal(value,prep);assert.equal(q,256);return ok(true);},strategyHostOutputSnapshotFinish(value){assert.equal(value,prep);return ok(result);},strategyHostOutputSnapshotCancel(){assert.fail('unexpected cancel');}});
 assert.equal(await run(handle,policy()),result);assert.deepEqual(calls,[[handle,2000003,300007,73]]);
});
test('snapshot policy rejects missing, negative and unrepresentable dimensions before Core',async()=>{
 const run=snapshot({strategyHostOutputSnapshotBegin(){assert.fail('invalid policy reached Core');}});
 for(const bad of [null,{}, {maxLogicalWireBytes:1,maxLogicalWireNodes:-1,maxLogicalWireDepth:1},{maxLogicalWireBytes:2147483648,maxLogicalWireNodes:1,maxLogicalWireDepth:1}])await assert.rejects(run({},bad),TypeError);
});
test('snapshot encoding refusal retains the existing exact cancellation path',async()=>{
 const prep={},issue=new Error('original encoding refusal');let cancels=0;
 const run=snapshot({strategyHostOutputSnapshotBegin(){return ok(prep);},strategyHostOutputSnapshotAdvance(){return {$tag:0,_0:issue};},strategyHostOutputSnapshotCancel(value){assert.equal(value,prep);cancels++;}});
 await assert.rejects(run({},policy()),error=>error===issue);assert.equal(cancels,1);
});
test('snapshot abort before begin does not manufacture a preparation or cleanup acknowledgement',async()=>{
 let starts=0;const run=snapshot({strategyHostOutputSnapshotBegin(){starts++;}}),controller=new AbortController();controller.abort();
 await assert.rejects(run({},policy(),controller.signal));assert.equal(starts,0);
});
test('durable publication relays exact original output policy while metadata keeps its distinct contract policy',async()=>{
 const text=source('durable-result-payload.mjs'),node=find(text,n=>n.type==='FunctionDeclaration'&&n.id?.name==='storeCompletedResultPublicationPayload');
 const handle={},output=policy(),contracts={maxWireBytes:11,maxNodes:13,maxDepth:17},seen=[];
 const control={issueResultEvidence(h,context,limits){assert.equal(h,handle);assert.equal(limits,contracts);seen.push('evidence');return {};}};
 const publication={runDefinition:{identity:'sha256:'+'a'.repeat(64)},limits:contracts,control:{issueResultArtifact(h,invocation,retention,limits){assert.equal(h,handle);assert.equal(limits,contracts);seen.push('artifact');return {};},issueDurableResultBinding(){},async admitCompletedResultSnapshot(h,limits){assert.equal(h,handle);assert.equal(limits,output);seen.push('snapshot');return {};}}};
 const store={createPreparedObjectWriter(){},putPreparedResultSchema(){}};
 const fn=new Function('validStore','validResultControl','fail','storeCompletedPayload',`return ${text.slice(node.start,node.end)}`)(()=>true,()=>true,code=>{throw Error(code);},async(...args)=>{assert.equal(args[3],output);return args[5](handle);});
 await fn(store,control,{},0,output,publication);assert.deepEqual(seen,['evidence','artifact','snapshot']);
});
