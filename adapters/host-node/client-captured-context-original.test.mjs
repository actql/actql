import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
const source=readFileSync(process.env.CAPTURE_RELAY_SOURCE_ROOT?`${process.env.CAPTURE_RELAY_SOURCE_ROOT}/adapters/host-common/runtime-core.mjs`:new URL('../host-common/runtime-core.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});let selected,projectionNode;
function walk(n){if(!n||typeof n!=='object')return;if(n.type==='VariableDeclarator'&&n.id?.name==='finishCapturedPreparation')selected=n.init;if(n.type==='VariableDeclarator'&&n.id?.name==='capturedPreparationLimits')projectionNode=n.init;for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(walk);else if(x&&typeof x==='object')walk(x);}}walk(ast);assert(selected);
function harness(vector=[2000003,300007,73]){
 const original={},contract={},captured={},calls=[],retained=new WeakMap();
 const moon={strategyCapturedRunPreparationLimits(value){assert.equal(value,original);calls.push('limits');return {$tag:1,_0:vector};},strategyCapturedRunAdvance(value,q){assert.equal(value,original);assert.equal(q,256);calls.push('advance');return {$tag:1,_0:true};},strategyCapturedRunFinish(value){assert.equal(value,original);calls.push('finish');return {$tag:1,_0:contract};},strategyCapturedRunFinishRetained(value){assert.equal(value,original);calls.push('finishRetained');return {$tag:1,_0:contract};},strategyCapturedRunCancel(value){assert.equal(value,original);calls.push('cancel');}};
 const projection=projectionNode===undefined?undefined:new Function('moon','runtimeIsBoxedSome','runtimeField',`return ${source.slice(projectionNode.start,projectionNode.end)}`)(moon,value=>value?.$tag===1,(value,index)=>value[`_${index}`]);
 const run=new Function('moon','checked','inspect','capturedComputationPreparations','runtimeIsBoxedSome','runtimeField','capturedPreparationLimits',`return ${source.slice(selected.start,selected.end)}`)(moon,r=>{if(r.$tag===0)throw r._0;return r._0;},(value,limits)=>{assert.equal(value,contract);assert.deepEqual(limits,{maxWireBytes:2000003,maxNodes:300007,maxDepth:73});assert(Object.isFrozen(limits));calls.push('inspect');return captured;},retained,value=>value?.$tag===1,(value,index)=>value[`_${index}`],projection);
 return {run,original,captured,calls,retained,moon};
}
test('captured finish consumes required original preparation envelope, retaining the same nominal owner',async()=>{
 const h=harness();assert.equal(await h.run(h.original,undefined,true),h.captured);assert.deepEqual(h.calls,['limits','advance','finishRetained','inspect']);assert.equal(h.retained.get(h.captured),h.original);
});
test('non-retained captured finish uses the same required projection without a second executor',async()=>{
 const h=harness();assert.equal(await h.run(h.original),h.captured);assert.deepEqual(h.calls,['limits','advance','finish','inspect']);assert.equal(h.retained.has(h.captured),false);
});
test('missing, malformed and unrepresentable original envelope cancels exactly the existing preparation',async()=>{
 for(const vector of [undefined,[],[1,2],[1,2,3,4],[1,-1,2],[1,2,2147483648],[1,2,NaN]]){const h=harness(vector);if(vector===undefined)h.moon.strategyCapturedRunPreparationLimits=()=>undefined;await assert.rejects(h.run(h.original),TypeError);assert.equal(h.calls.filter(x=>x==='cancel').length,1);assert.equal(h.calls.includes('advance'),false);}
});
test('captured advance failure and abort preserve cancellation and do not retain a false completed original',async()=>{
 const h=harness(),failure=new Error('original failure');h.moon.strategyCapturedRunAdvance=()=>({$tag:0,_0:failure});await assert.rejects(h.run(h.original),error=>error===failure);assert.equal(h.calls.at(-1),'cancel');assert.equal(h.retained.has(h.captured),false);
 const aborted=harness(),controller=new AbortController();controller.abort();await assert.rejects(aborted.run(aborted.original,controller.signal));assert.equal(aborted.calls.at(-1),'cancel');assert.equal(aborted.calls.includes('advance'),false);
});

test('captured projection requires the actual boxed Option array ABI and rejects unboxed lookalikes',async()=>{
 for(const value of [{$tag:0},[2000003,300007,73],{_0:[2000003,300007,73]}]){
  const h=harness();h.moon.strategyCapturedRunPreparationLimits=()=>value;
  await assert.rejects(h.run(h.original),TypeError);assert.equal(h.calls.includes('advance'),false);assert.equal(h.calls.at(-1),'cancel');
 }
});

test('ordinary captured issuance requires the Node original-owned entry, never the explicit low-level budget entry',()=>{
 let method;function select(n){if(!n||typeof n!=='object')return;if(n.type==='Property'&&n.key?.name==='issueEffectFreeCapturedRun')method=n.value;for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(select);else if(x&&typeof x==='object')select(x);}}select(ast);assert(method);
 const calls=[];function visit(n){if(!n||typeof n!=='object')return;if(n.type==='CallExpression'&&n.callee.type==='MemberExpression'&&n.callee.object.name==='moon')calls.push(n.callee.property.name);for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(visit);else if(x&&typeof x==='object')visit(x);}}visit(method);
 assert.equal(calls.filter(x=>x==='strategyBeginOriginalEffectFreeCapturedRun').length,1);
 assert.equal(calls.includes('strategyBeginEffectFreeCapturedRun'),false);
});

test('retained chain and commit verification project the same completed original extent, not metadata limits',async()=>{
 for(const methodName of ['effectFreeChainValid','effectFreeCommitValid']){
  let method;function find(n){if(!n||typeof n!=='object')return;if(n.type==='Property'&&n.key?.name===methodName)method=n.value;for(const x of Object.values(n)){if(Array.isArray(x))x.forEach(find);else if(x&&typeof x==='object')find(x);}}find(ast);assert(method);
  const captured={},original={},next={},metadata={maxWireBytes:11,maxNodes:13,maxDepth:17},derived={maxWireBytes:2000003,maxNodes:300007,maxDepth:73},seen=[];
  const originals=new WeakMap([[captured,original]]);
  const moon={strategyPublicationEvidenceWorkspace(n){seen.push(['workspace',n]);return n+1;},strategyBeginEffectFreeChainCheckRetained(owner,...args){assert.equal(owner,original);assert.deepEqual(args.slice(-4),[2000003,300007,73,300008]);return next;},strategyBeginEffectFreeCommitCheckRetained(owner,...args){assert.equal(owner,original);assert.deepEqual(args.slice(-4),[2000003,300007,73,300008]);return next;}};
  const fn=new Function('issuanceLimits','capturedComputationPreparations','capturedPreparationLimits','token','moon','finishPublicationValidation',`return async function(${method.params.map(p=>p.name).join(',')})${source.slice(method.body.start,method.body.end)}`)(()=>{},originals,owner=>{assert.equal(owner,original);seen.push(['original']);return derived;},x=>x,moon,async p=>{assert.equal(p,next);return true;});
  const args=methodName==='effectFreeChainValid'?[{},{},[],[],{},{},captured,metadata]:[{},{},[],[],[],[],[],[],{},{},captured,{},{},{},metadata];
  assert.equal(await fn(...args),true);assert.deepEqual(seen,[['original'],['workspace',300007]]);assert.deepEqual(metadata,{maxWireBytes:11,maxNodes:13,maxDepth:17});
 }
});
