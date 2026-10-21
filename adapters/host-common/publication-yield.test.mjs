import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the two actual private loops with explicit Common ports. These
// counters establish scheduling and cleanup, not installed Host acceptance.
const source=readFileSync(new URL('./runtime-core.mjs',import.meta.url),'utf8');
const wanted=new Set(['finishCapturedPreparation','finishPublicationValidation']);
const declarations=new Map();
function visit(node){
  if(node===null||typeof node!=='object')return;
  if(node.type==='VariableDeclaration')for(const d of node.declarations){
    if(d.id.type==='Identifier'&&wanted.has(d.id.name)){
      assert(!declarations.has(d.id.name));declarations.set(d.id.name,source.slice(node.start,node.end));
    }
  }
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  }
}
visit(parse(source,{ecmaVersion:'latest',sourceType:'module'}));
assert.equal(declarations.size,2);
const compile=new Function('moon','checked','inspect','setTimeout','setImmediate',
  [...declarations.values()].join('\n')+';return {finishCapturedPreparation,finishPublicationValidation};');
function fixture({pending=3,advance,finish,inspect=x=>x,onYield}={}){
  const preparation=Object.freeze({original:'preparation'}),result=Object.freeze({original:'captured'});
  const counts={advance:0,finish:0,cancel:0,yields:0,timers:0};
  const moon={
    strategyCapturedRunAdvance(value,quantum){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);assert.equal(quantum,256);counts.advance++;return advance?advance(counts.advance):counts.advance>pending;},
    strategyCapturedRunFinish(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.finish++;return finish?finish():result;},
    strategyCapturedRunCancel(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.cancel++;},
  };
  const loops=compile(moon,x=>x,inspect,()=>{counts.timers++;assert.fail('A bounded serialization yield must not start a delay timer');},callback=>{
    counts.yields++;return setImmediate(()=>{onYield?.(counts.yields);callback();});
  });
  return{preparation,result,counts,moon,...loops};
}

test('captured issuance yields by event-loop turns without delay timers',async()=>{
  let anotherTurn=false;setImmediate(()=>{anotherTurn=true;});
  const f=fixture({advance:n=>{if(n>1)assert(anotherTurn,'Other queued turns must run between bounded quanta');return n===4;}});
  assert.strictEqual(await f.finishCapturedPreparation(f.preparation),f.result);
  assert.deepEqual(f.counts,{advance:4,finish:1,cancel:0,yields:3,timers:0});
});

test('publication validation yields by event-loop turns without delay timers',async()=>{
  const f=fixture();let steps=0,finished=0,cancelled=0;
  const result=Object.freeze({original:'validation'});
  assert.strictEqual(await f.finishPublicationValidation(f.preparation,(value,quantum)=>{
    assert.strictEqual(value,f.preparation);assert.equal(quantum,256);return ++steps===4?1:0;
  },value=>{assert.strictEqual(value,f.preparation);finished++;return result;},value=>{assert.strictEqual(value,f.preparation);cancelled++;}),result);
  assert.equal(steps,4);assert.equal(finished,1);assert.equal(cancelled,1);assert.equal(f.counts.yields,3);assert.equal(f.counts.timers,0);
});

test('already complete captured issuance does not yield or cancel',async()=>{
  const f=fixture({pending:0});assert.strictEqual(await f.finishCapturedPreparation(f.preparation),f.result);
  assert.deepEqual(f.counts,{advance:1,finish:1,cancel:0,yields:0,timers:0});
});

test('captured issuance abort after a yielded turn retains original reason and cancels once',async()=>{
  const abort=new AbortController(),reason=new Error('original stop');
  const f=fixture({onYield:()=>abort.abort(reason)});
  await assert.rejects(f.finishCapturedPreparation(f.preparation,abort.signal),error=>error===reason);
  assert.deepEqual(f.counts,{advance:1,finish:0,cancel:1,yields:1,timers:0});
});

test('captured issuance advance and inspection failures cancel the same preparation',async()=>{
  const reason=new Error('original failure');
  for(const options of[{advance:()=>{throw reason;}},{pending:0,inspect:()=>{throw reason;}}]){
    const f=fixture(options);await assert.rejects(f.finishCapturedPreparation(f.preparation),error=>error===reason);assert.equal(f.counts.cancel,1);
  }
});

test('publication refusal and invalid progress cancel without a yield or finish',async()=>{
  for(const progress of[-1,2]){const f=fixture();let cancellations=0;
    const run=f.finishPublicationValidation(f.preparation,()=>progress,()=>assert.fail('No finish for non-success'),value=>{assert.strictEqual(value,f.preparation);cancellations++;});
    if(progress===-1)assert.strictEqual(await run,false);else await assert.rejects(run,/Invalid publication validation progress/);
    assert.equal(cancellations,1);assert.equal(f.counts.yields,0);assert.equal(f.counts.timers,0);
  }
});

test('publication abort after a yielded turn cancels once without another quantum',async()=>{
  const abort=new AbortController(),reason=new Error('original validation stop');
  const f=fixture({onYield:()=>abort.abort(reason)});let steps=0,cancellations=0;
  await assert.rejects(f.finishPublicationValidation(f.preparation,()=>{steps++;return 0;},()=>assert.fail('No finish after abort'),()=>{cancellations++;},abort.signal),error=>error===reason);
  assert.equal(steps,1);assert.equal(cancellations,1);assert.equal(f.counts.yields,1);assert.equal(f.counts.timers,0);
});

test('publication finish failure preserves its original error and cancellation',async()=>{
  const f=fixture(),reason=new Error('original finish failure');let cancelled=0;
  await assert.rejects(f.finishPublicationValidation(f.preparation,()=>1,()=>{throw reason;},()=>{cancelled++;}),error=>error===reason);
  assert.equal(cancelled,1);assert.equal(f.counts.yields,0);
});
