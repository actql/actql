import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const root=new URL('../',import.meta.url);
const fixture=JSON.parse(readFileSync(new URL('./fixtures/capture-projector-sites.json',import.meta.url),'utf8'));
const hash=text=>createHash('sha256').update(text).digest('hex');
function body(path,name){
 const source=readFileSync(new URL(path,root),'utf8').replace(/\/\/[^\n]*/g,'').replace(/"(?:\\.|[^"\\])*"/g,'""');
 const match=new RegExp(`\\bfn(?:\\[[^\\]]*\\])?\\s+${name}\\s*\\(`).exec(source);
 assert.ok(match,`missing ${name}`);
 const start=source.indexOf('{',match.index+match[0].length);
 let end=start+1,depth=1;
 while(depth && end<source.length){if(source[end]==='{')depth++;else if(source[end]==='}')depth--;end++;}
 assert.equal(depth,0);
 return source.slice(start,end);
}

test('capture fixed projector admission is pinned to its finite constructor callgraph',()=>{
 let records=0,options=0,arrays=0;
 for(const entry of fixture.items){
  const value=body(entry.path,entry.function);
  assert.equal(hash(value),entry.body_sha256,`${entry.function}: re-establish constructor/call multiplicity proof`);
  const r=(value.match(/\{/g)||[]).length;
  const s=(value.match(/\bSome\s*\(/g)||[]).length;
  const a=(value.match(/\[/g)||[]).length;
  assert.equal(r,entry.record_sites);assert.equal(s,entry.some_sites);assert.equal(a,entry.array_sites);
  records+=r*entry.multiplicity;options+=s*entry.multiplicity;arrays+=a*entry.multiplicity;
 }
 assert.deepEqual({record:records,some:options,array:arrays},fixture.weighted_sites);
 const units={record_headers:records+options+2*arrays,reference_slots:11*records+options+43*arrays,
  scalar_words:11*records+2*options+2*arrays,owned_utf16_units:0,owned_wire_bytes:0};
 assert.deepEqual(units,fixture.units);
 assert.equal(16*units.record_headers+8*units.reference_slots+8*units.scalar_words,153456);
 // The static amount is specific to the authoritative v1 logical tariff.
 const tariff=fixture.items.find(entry=>entry.function==='preparation_representation_cost');
 assert.equal(hash(readFileSync(new URL(tariff.path,root))),tariff.source_sha256);
});
