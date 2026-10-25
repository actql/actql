import assert from 'node:assert/strict';
import {before,test} from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(process.env.ACTQL_CORE??fileURLToPath(new URL('../../',import.meta.url)));
let open,coherence,assertCurrent;
before(async()=>{
 const verifier=await import(pathToFileURL(join(root,'scripts/verify-local-source-runtime.mjs')));
 assertCurrent=verifier.assertSourceRuntimeReceiptCurrent;
 coherence=process.env.COHERENCE_RECEIPT?JSON.parse(readFileSync(process.env.COHERENCE_RECEIPT,'utf8')):await verifier.verifyLocalSourceRuntime(root);
 assert.equal(resolve(coherence.root),root);assertCurrent(coherence);
 ({open}=await import(pathToFileURL(join(root,'packages/node/index.mjs'))));
});
const type={type:'number',nullable:false};
function fixture(n,duplicate=false,composed=false,unguarded=false){
 const left=Array.from({length:n},(_,i)=>({k:duplicate?Math.floor(i/2):i,v:i+1}));
 const right=Array.from({length:n},(_,i)=>({k:duplicate?Math.floor(i/2):i,v:i*2+3}));
 const steps=[{as:'l',values:{schema:{k:type,v:type},rows:left}}, {as:'r',values:{schema:{k:type,v:type},rows:right}},
  {as:'j',from:'l',join:{with:'r',kind:'inner',on:[{left:'k',right:'k'}],max_output_rows:duplicate?2*n:n,select:{k:'left.k',lv:'left.v',rv:'right.v'}}}];
 if(unguarded)delete steps[2].join.max_output_rows;
 const index=new Map();for(const r of right){const bucket=index.get(r.k)??[];bucket.push(r);index.set(r.k,bucket);}
 let expected=[];for(const l of left)for(const r of index.get(l.k)??[])expected.push({k:l.k,lv:l.v,rv:r.v});
 if(composed){steps.push({as:'f',from:'j',filter:'k % 3 = 0'},{as:'d',from:'f',derive:{g:'k % 7',total:'lv + rv'}},{as:'a',from:'d',group:{by:['g'],aggregates:{n:{fn:'count'},s:{fn:'sum',field:'total'}}}},{as:'o',from:'a',sort:[{field:'s',dir:'desc',nulls:'last'},{field:'g',dir:'asc',nulls:'last'}]});
 const groups=new Map();for(const row of expected)if(row.k%3===0){const g=row.k%7;const a=groups.get(g)??{g,n:0,s:0};a.n++;a.s+=row.lv+row.rv;groups.set(g,a);}expected=[...groups.values()].sort((a,b)=>b.s-a.s||a.g-b.g);
 } else {steps.push({as:'o',from:'j',sort:[{field:'k',dir:'asc',nulls:'last'},{field:'lv',dir:'asc',nulls:'last'},{field:'rv',dir:'asc',nulls:'last'}]});expected.sort((a,b)=>a.k-b.k||a.lv-b.lv||a.rv-b.rv);}
 return {expected,program:{version:'actql/0.1',id:'join-scale',stages:[{id:'main',inputs:{},steps,results:{rows:{from:'o',fields:Object.keys(expected[0]??{k:0,lv:0,rv:0})}}}],results:{answer:{from:{stage:'main',result:'rows'}}}}};
}

for(const [count,duplicate,composed] of [[51,false,false],[1000,false,false],[1000,true,true]]){
 test(`ordinary public JOIN ${count}x${count} duplicate=${duplicate} composed=${composed} streams exact rows and reopens`,async()=>{
  const {program,expected}=fixture(count,duplicate,composed);
  const directory=await mkdtemp(join(tmpdir(),'actql-public-join-scale-'));let db,completed=false;
  async function compareRows(result){let index=0;for await(const row of result.rows()){assert.ok(index<expected.length);assert.deepEqual(row,expected[index],`row ${index}`);index++;}assert.equal(index,expected.length);}
  try{
   db=await open({stateDir:directory});const run=await db.start(program);
   const observed=await run.wait({signal:AbortSignal.timeout(120000)});assert.equal(observed.status,'succeeded',JSON.stringify(observed));
   await compareRows(run.result('answer'));const ref=run.ref;
   await db.close();db=undefined;db=await open({stateDir:directory});const restored=await db.attach(ref);
   assert.equal((await restored.status()).control.physical_stop,'confirmed');await compareRows(restored.result('answer'));completed=true;
  }finally{if(db)await db.close();assertCurrent(coherence);if(completed)await rm(directory,{recursive:true,force:true});else console.error(JSON.stringify({failedJoinStateDir:directory,count,duplicate,composed}));}
 });
}
