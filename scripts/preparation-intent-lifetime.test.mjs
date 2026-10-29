import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import test from 'node:test';
const root=process.env.ACTQL_CORE ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {canonicalJson}=await import(pathToFileURL(path.join(root,'packages/sdk/checkpoints.mjs')));
function input(fields,rows){
  const names=Array.from({length:fields},(_,i)=>`v${i}`);
  return {kind:'program',parameters:null,input:{stages:[{id:'s',steps:[{values:{
    schema:Object.fromEntries(names.map(n=>[n,{type:'number',nullable:false}])),
    rows:Array.from({length:rows},(_,r)=>Object.fromEntries(names.map((n,c)=>[n,r+c]))),
  },as:'v'}],results:{r:{from:'v',fields:names}}}],results:{r:{from:{stage:'s',result:'r'}}}}};
}
// Independent ownership observer, not the Moon arithmetic formula: completed
// children return Strings only; parents keep those until their own join ends.
function observedCanonical(value){
  let liveText=0,peakText=0,depth=0,maxDepth=0,keys=0,maxKeys=0,arrayOwners=0,maxArrays=0,arraySlots=0,maxSlots=0;
  const own=s=>{liveText+=s.length;peakText=Math.max(peakText,liveText);return s;};
  const drop=s=>{liveText-=s.length;assert.ok(liveText>=0);};
  const add=(k,a,s)=>{keys+=k;arrayOwners+=a;arraySlots+=s;maxKeys=Math.max(maxKeys,keys);maxArrays=Math.max(maxArrays,arrayOwners);maxSlots=Math.max(maxSlots,arraySlots);};
  function visit(v){
    depth++;maxDepth=Math.max(maxDepth,depth);
    let result;
    if(v===null || typeof v!=='object')result=own(JSON.stringify(v));
    else if(Array.isArray(v)){
      add(0,1,v.length);
      const children=v.map(visit),joined=own(children.join(','));
      result=own(`[${joined}]`);for(const s of children)drop(s);drop(joined);
      add(0,-1,-v.length);
    }else{
      const names=Object.keys(v).sort(),n=names.length;
      // Keep all five arrays/two pair arrays even where real canonicalJson
      // already discarded an earlier filter/map; this is conservative.
      add(n,5+2*n,9*n);
      const fragments=names.map(key=>{
        const name=own(JSON.stringify(key)),child=visit(v[key]);
        const fragment=own(`${name}:${child}`);drop(name);drop(child);return fragment;
      });
      const joined=own(fragments.join(','));result=own(`{${joined}}`);
      for(const s of fragments)drop(s);drop(joined);add(-n,-5-2*n,-9*n);
    }
    depth--;return result;
  }
  const wire=visit(value);assert.equal(liveText,wire.length);assert.equal(keys,0);assert.equal(arrayOwners,0);assert.equal(arraySlots,0);
  return {wire,peakText,maxDepth,maxKeys,maxArrays,maxSlots};
}
test('canonical intent row temporaries are ancestor-scoped while rendered row strings survive',()=>{
  let cases=0;
  for(const f of [1,2,3,7,16,32])for(const r of [0,1,2,9,100]){
    const value=input(f,r),o=observedCanonical(value),k=Math.max(f,4),d=o.maxDepth,w=Math.max(f,r,4);
    assert.equal(o.wire,canonicalJson(value,{dataKeys:true}));
    assert.ok(o.maxKeys<=d*k);
    assert.ok(o.maxArrays<=d*(6+2*k));
    assert.ok(o.maxSlots<=d*(9*k+w));
    assert.ok(o.peakText<=4*o.wire.length*d);
    cases++;
  }
  assert.equal(cases,30);
});
test('funded Request uses its same native intent owner while explicit raw profiles keep canonical admission',async()=>{
  const manager=await readFile(path.join(root,'adapters/host-node/ordinary-source-managed.mjs'),'utf8');
  const begin=manager.indexOf('    intentCid(receipt, body) {');
  const end=manager.indexOf('    finishSourceProducer(',begin);
  const funded=manager.slice(begin,end);
  assert.match(funded,/clientProgramPrepareRequestSubmittedIntent\(state.parent, receipt, value\)/);
  assert.match(funded,/clientProgramFinishRequestSubmittedIntent\(state.parent, receipt\)/);
  assert.ok(funded.indexOf('clientProgramFinishRequestSubmittedIntent')<funded.indexOf('return cid;'));
  assert.doesNotMatch(funded,/canonicalValueJson|JSON\.stringify|ClosedValues|preparation\?\.phase/);
  const js=await readFile(path.join(root,'adapters/host-node/embedded-local.mjs'),'utf8');
  const start=js.indexOf('export function managedComputeSubmittedIntentCid');
  const body=js.slice(start,js.indexOf('\nconst bytesCid',start));
  assert.match(body,/const wire = canonicalValueJson\(/);
  assert.match(body,/moon\.clientSubmittedIntent\(wire, 1048576, 65536, 64\)/);
  assert.doesNotMatch(body,/\bawait\b|\.then\(|preparationOwner|ClosedValues/);
  const canonical=await readFile(path.join(root,'src/canonical_json/value.mbt'),'utf8');
  assert.match(canonical,/let seen : Map\[String, Unit\] = Map\(\[\]\)/);
  assert.match(canonical,/Object\(\{ values, \}\)/);
  assert.match(canonical,/Array\(\{ values, \}\)/);
});
