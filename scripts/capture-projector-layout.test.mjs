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
 assert.deepEqual(fixture.fixed_sites,{record:0,some:0,array:0});
 let records=fixture.fixed_sites.record,options=fixture.fixed_sites.some,arrays=fixture.fixed_sites.array;
 const bodies=new Map();
 for(const entry of fixture.items){
  const value=body(entry.path,entry.function);
  assert.equal(hash(value),entry.body_sha256,`${entry.function}: re-establish constructor/call multiplicity proof`);
  assert.ok(!bodies.has(entry.function),`duplicate ${entry.function}`);
  bodies.set(entry.function,value);
  const r=(value.match(/\{/g)||[]).length;
  const s=(value.match(/\bSome\s*\(/g)||[]).length;
  const a=(value.match(/\[/g)||[]).length;
  assert.equal(r,entry.record_sites);assert.equal(s,entry.some_sites);assert.equal(a,entry.array_sites);
  records+=r*entry.multiplicity;options+=s*entry.multiplicity;arrays+=a*entry.multiplicity;
 }
 const calls=(name,callee)=>(bodies.get(name).match(new RegExp(`\\b${callee}\\s*\\(`,'g'))||[]).length;
 const literals=name=>[...bodies.get(name).matchAll(/\bcompose_preparation_representation\s*\(\s*\[([^\]]*)\]/g)]
  .map(match=>match[1].split(',').filter(item=>item.trim()).length);
 assert.deepEqual(literals('publication_capture_constructor_layout'),[7]);
 const writers=calls('publication_capture_constructor_layout','hash_writer_live_key_inventory');
 const frames=writers*calls('hash_writer_live_key_inventory','writer_frame_construction_extent');
 const collections=writers*calls('hash_writer_live_key_inventory','collection_construction_extent')+
  frames*calls('writer_frame_construction_extent','collection_construction_extent');
 const maps=collections*calls('collection_construction_extent','map_construction_extent');
 const additions=writers*calls('hash_writer_live_key_inventory','add_collection_construction_extents');
 const compositions=calls('publication_capture_constructor_layout','compose_preparation_representation');
 const prices=calls('publication_capture_constructor_layout','preparation_representation_cost')+
  compositions*calls('compose_preparation_representation','preparation_representation_cost');
 const executionAdds=7*calls('compose_preparation_representation','checked_preparation_add_product')+
  prices*calls('preparation_representation_cost','checked_preparation_add_product');
 const sharedAdds=executionAdds*calls('checked_preparation_add_product','checked_nonnegative_add_product')+
  collections*calls('collection_construction_extent','checked_nonnegative_add_product')+
  maps*calls('map_construction_extent','checked_nonnegative_add_product')+
  additions*calls('add_collection_construction_extents','checked_nonnegative_add_product');
 const multiplicities={capture_construction_layout_facts:1,publication_capture_constructor_layout:1,
  hash_writer_live_key_inventory:writers,
  closed_values_append_capacity:calls('publication_capture_constructor_layout','closed_values_append_capacity'),
  compose_preparation_representation:compositions,preparation_representation_cost:prices,
  checked_preparation_add_product:executionAdds,writer_frame_construction_extent:frames,
  collection_construction_extent:collections,map_construction_extent:maps,
  add_collection_construction_extents:additions,checked_nonnegative_add_product:sharedAdds};
 assert.deepEqual(multiplicities,{capture_construction_layout_facts:1,publication_capture_constructor_layout:1,
  hash_writer_live_key_inventory:1,closed_values_append_capacity:4,compose_preparation_representation:1,
  preparation_representation_cost:2,checked_preparation_add_product:45,writer_frame_construction_extent:1,
  collection_construction_extent:2,map_construction_extent:2,add_collection_construction_extents:1,
  checked_nonnegative_add_product:82});
 assert.deepEqual(Object.fromEntries(fixture.items.map(entry=>[entry.function,entry.multiplicity])),multiplicities);
 // Append's loop changes integers only; composition allocates through the
 // separately counted arithmetic helper. Pure delegate braces are harmless
 // conservative slack, not new per-call product accounting.
 assert.deepEqual({record:records,some:options,array:arrays},fixture.weighted_sites);
 const units={record_headers:records+options+2*arrays,reference_slots:11*records+options+43*arrays,
  scalar_words:11*records+2*options+2*arrays,owned_utf16_units:0,owned_wire_bytes:0};
 assert.deepEqual(units,fixture.census_units);
 const price=value=>16*value.record_headers+8*value.reference_slots+8*value.scalar_words;
 assert.equal(price(units),76296);
 assert.equal(price(units),fixture.census_logical_bytes);
 assert.equal(price(fixture.units),153456);
 assert.equal(fixture.logical_bytes,153456);
 assert.ok(price(units)<=fixture.logical_bytes,'current constructor census exceeds the unchanged allowance');
 // The static amount is specific to the authoritative v1 logical tariff.
 const tariff=fixture.items.find(entry=>entry.function==='preparation_representation_cost');
 assert.equal(hash(readFileSync(new URL(tariff.path,root))),tariff.source_sha256);
});
