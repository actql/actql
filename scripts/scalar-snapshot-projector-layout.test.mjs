import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const root=new URL('../',import.meta.url);
const fixture=JSON.parse(readFileSync(new URL('./fixtures/scalar-snapshot-projector-sites.json',import.meta.url),'utf8'));
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

test('snapshot fixed projector admission is pinned to its finite constructor callgraph',()=>{
 // The external builtin witness is tied to the existing authenticated portable
 // core pin, with no local installation or absolute Source-path requirement.
 const option=fixture.builtin_option_witness;
 const toolchain=JSON.parse(readFileSync(new URL('toolchain.json',root),'utf8'));
 assert.equal(toolchain.core.sha256,option.core_archive_sha256);
 assert.equal(option.core_archive_sha256,'784a12ce4e204a3a98a0b704a021f747b916412efacd4dfe2f4e5c27ae183ac1');
 assert.equal(option.source_sha256,'059fcefd01f0393fc0ded6456e28d3dc0699dd6c32fdd0ac80aadbb35473184a');
 assert.deepEqual(option.map,{braces:2,some_sites:2});
 assert.deepEqual(option.unwrap_or,{braces:2,some_sites:1});
 assert.equal(option.closure_records,1);
 assert.deepEqual(fixture.fixed_sites,{record:5,some:3,array:0});
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
 assert.deepEqual(literals('scalar_snapshot_layout'),[4,8,17,2,9]);
 assert.deepEqual(literals('compilation_canonical_layout'),[3]);
 assert.deepEqual(literals('compilation_writer_ancestry_layout'),[2]);
 assert.equal(calls('scalar_snapshot_layout','map'),1);
 assert.equal(calls('scalar_snapshot_layout','unwrap_or'),1);
 assert.equal((bodies.get('scalar_snapshot_layout').match(/=>/g)||[]).length,1);
 const canonical=calls('scalar_snapshot_layout','compilation_canonical_layout');
 const writers=calls('scalar_snapshot_layout','compilation_writer_ancestry_layout');
 const hashes=writers*calls('compilation_writer_ancestry_layout','hash_writer_live_key_inventory');
 const frames=hashes*calls('hash_writer_live_key_inventory','writer_frame_construction_extent');
 const collections=hashes*calls('hash_writer_live_key_inventory','collection_construction_extent')+
  frames*calls('writer_frame_construction_extent','collection_construction_extent');
 const maps=collections*calls('collection_construction_extent','map_construction_extent');
 const additions=hashes*calls('hash_writer_live_key_inventory','add_collection_construction_extents');
 const repeats=writers*calls('compilation_writer_ancestry_layout','compilation_metadata_repeat_units');
 const compositions=calls('scalar_snapshot_layout','compose_preparation_representation')+
  canonical*calls('compilation_canonical_layout','compose_preparation_representation')+
  writers*calls('compilation_writer_ancestry_layout','compose_preparation_representation');
 const composeItems=literals('scalar_snapshot_layout').reduce((sum,n)=>sum+n,0)+
  canonical*literals('compilation_canonical_layout')[0]+writers*literals('compilation_writer_ancestry_layout')[0];
 assert.equal(composeItems,47);
 const prices=compositions*calls('compose_preparation_representation','preparation_representation_cost')+
  canonical*calls('compilation_canonical_layout','preparation_representation_cost')+
  repeats*calls('compilation_metadata_repeat_units','preparation_representation_cost');
 const executionAdds=composeItems*calls('compose_preparation_representation','checked_preparation_add_product')+
  prices*calls('preparation_representation_cost','checked_preparation_add_product')+
  repeats*calls('compilation_metadata_repeat_units','checked_preparation_add_product');
 const normalization=calls('scalar_snapshot_layout','scalar_snapshot_name_normalization_layout');
 const nfc=normalization*calls('scalar_snapshot_name_normalization_layout','nfc_lf_construction_extent');
 const output=nfc*calls('nfc_lf_construction_extent','nfc_lf_retained_output_units');
 const programArrays=calls('scalar_snapshot_layout','closed_values_program_arrays');
 const arrayRepresentations=programArrays*calls('closed_values_program_arrays','preparation_array_representation');
 const arraySlots=arrayRepresentations*calls('preparation_array_representation','preparation_array_slots');
 const sharedAdds=executionAdds*calls('checked_preparation_add_product','checked_nonnegative_add_product')+
  collections*calls('collection_construction_extent','checked_nonnegative_add_product')+
  maps*calls('map_construction_extent','checked_nonnegative_add_product')+
  additions*calls('add_collection_construction_extents','checked_nonnegative_add_product')+
  output*calls('nfc_lf_retained_output_units','checked_nonnegative_add_product')+
  arraySlots*calls('preparation_array_slots','checked_nonnegative_add_product');
 const wire=calls('scalar_snapshot_layout','client_local_json_leaf_wire_byte_bound');
 const work=wire*calls('client_local_json_leaf_wire_byte_bound','client_local_schema_proof_work');
 const multiplicities={scalar_snapshot_layout:1,scalar_snapshot_name_normalization_layout:normalization,
  closed_values_source_inventories:calls('scalar_snapshot_layout','closed_values_source_inventories'),
  compilation_canonical_layout:canonical,
  closed_values_sort_scratch_layout:canonical*calls('compilation_canonical_layout','closed_values_sort_scratch_layout'),
  compose_preparation_representation:compositions,
  closed_values_units_subtract:calls('scalar_snapshot_layout','closed_values_units_subtract'),
  closed_values_program_arrays:programArrays,
  preparation_array_representation:arrayRepresentations,preparation_array_slots:arraySlots,
  closed_values_program_maps:calls('scalar_snapshot_layout','closed_values_program_maps'),
  compilation_writer_ancestry_layout:writers,hash_writer_live_key_inventory:hashes,
  compilation_metadata_repeat_units:repeats,client_local_json_leaf_wire_byte_bound:wire,
  preparation_representation_cost:prices,checked_preparation_add_product:executionAdds,
  writer_frame_construction_extent:frames,collection_construction_extent:collections,
  map_construction_extent:maps,add_collection_construction_extents:additions,
  checked_nonnegative_add_product:sharedAdds,nfc_lf_construction_extent:nfc,
  nfc_lf_retained_output_units:output,
  canonical_normalization_preparation_units:normalization*calls('scalar_snapshot_name_normalization_layout','canonical_normalization_preparation_units'),
  client_local_schema_proof_work:work,
  client_standard_program_preparation_limits:work*calls('client_local_schema_proof_work','client_standard_program_preparation_limits')};
 assert.deepEqual(multiplicities,{scalar_snapshot_layout:1,scalar_snapshot_name_normalization_layout:1,
  closed_values_source_inventories:1,compilation_canonical_layout:1,closed_values_sort_scratch_layout:1,
  compose_preparation_representation:8,closed_values_units_subtract:2,closed_values_program_arrays:8,
  preparation_array_representation:8,preparation_array_slots:8,
  closed_values_program_maps:1,compilation_writer_ancestry_layout:2,hash_writer_live_key_inventory:2,
  compilation_metadata_repeat_units:2,client_local_json_leaf_wire_byte_bound:1,preparation_representation_cost:11,
  checked_preparation_add_product:300,writer_frame_construction_extent:2,collection_construction_extent:4,
  map_construction_extent:4,add_collection_construction_extents:2,checked_nonnegative_add_product:408,
  nfc_lf_construction_extent:1,nfc_lf_retained_output_units:2,canonical_normalization_preparation_units:1,
  client_local_schema_proof_work:1,client_standard_program_preparation_limits:1});
 assert.deepEqual(Object.fromEntries(fixture.items.map(entry=>[entry.function,entry.multiplicity])),multiplicities);
 // Sort's halving loop has no constructors. Compose's only per-item allocation
 // is in the separately expanded checked arithmetic. Count all failure prefixes
 // conservatively, without repeating the input-sized writer/NFC DATA they quote.
 assert.deepEqual({record:records,some:options,array:arrays},fixture.weighted_sites);
 const units={record_headers:records+options+2*arrays,reference_slots:11*records+options+43*arrays,
  scalar_words:11*records+2*options+2*arrays,owned_utf16_units:0,owned_wire_bytes:0};
 assert.deepEqual(units,fixture.census_units);
 const price=value=>16*value.record_headers+8*value.reference_slots+8*value.scalar_words;
 assert.equal(price(units),399856);
 assert.equal(price(units),fixture.census_logical_bytes);
 assert.equal(price(fixture.units),399856);
 assert.equal(fixture.logical_bytes,399856);
 assert.ok(price(units)<=fixture.logical_bytes,'current constructor census exceeds its admitted prequote');
 // The same original publication owner admits this fixed construction work
 // before calling the projector, in addition to its existing wrapper controls.
 const owner=readFileSync(new URL('src/client_local_host/preparation_publication_owner.mbt',root),'utf8');
 const prequote=/\blet publication_projection_execution\s*:\s*Int64\s*=\s*(\d+)L\b/.exec(owner);
 assert.ok(prequote,'missing original publication prequote');
 const wrapper=price({record_headers:32,reference_slots:64,scalar_words:64});
 assert.equal(wrapper,1536);
 assert.equal(Number(prequote[1]),fixture.logical_bytes+wrapper);
 // The static amount is specific to the authoritative v1 logical tariff.
 const tariff=fixture.items.find(entry=>entry.function==='preparation_representation_cost');
 assert.equal(hash(readFileSync(new URL(tariff.path,root))),tariff.source_sha256);
});
