import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';

const read=p=>JSON.parse(readFileSync(p,'utf8'));
const cid={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const cidSet={type:'array',uniqueItems:true,items:cid};
const levels=['public','internal','confidential','restricted'];
const response=read('spec/contracts/actql-source-response-policy.json');
export const contract={version:'actql-effective-data-policy-contract/0.1',
  dependencies:{source_response_policy:machineCid(response)},
  schemas:{policy:{$schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version','classification','source_data_policy_cids','source_response_policy_cids','unknown_provenance'],
    properties:{version:{const:'actql-effective-data-policy/0.1'},
      classification:{enum:[...levels,'unknown']},source_data_policy_cids:cidSet,
      source_response_policy_cids:cidSet,unknown_provenance:{type:'boolean'}}}},
  semantics:{identity:'entire_policy_canonical_json_utf8_sha256_no_exclusions',
    references:'sorted_unique_full_cids_of_exact_admitted_contributing_policies_not_catalog_superset',
    classification:'unknown_if_missing_provenance_or_unknown_contributor_or_empty_otherwise_max',
    provenance:'retain_value_occurrences_and_policy_correspondence_separately_no_owner_or_observation_in_policy',
    authority:'shape_and_hash_do_not_prove_selection_authority_or_egress_permission'}};

// Independent selection model. Inputs represent already admitted policy references;
// synthetic labels below are not an alternative Contract Envelope admission path.
function compose(sources,responses,unknown=false) {
  for(const value of [...sources,...responses]) assert.ok([...levels,'unknown'].includes(value.classification));
  for(const value of responses) assert.ok(sources.some(s=>s.cid===value.source_data_policy_cid),
    'MissingResponseAuthority');
  const unique=xs=>[...new Set(xs.map(x=>x.cid))].sort();
  const all=[...sources,...responses];
  const classification=unknown||all.length===0||all.some(x=>x.classification==='unknown')?
    'unknown':levels[Math.max(...all.map(x=>levels.indexOf(x.classification)))];
  return {version:'actql-effective-data-policy/0.1',classification,
    source_data_policy_cids:unique(sources),source_response_policy_cids:unique(responses),
    unknown_provenance:unknown};
}
const source=levels.concat('unknown').map(classification=>({classification,
  cid:machineCid({fixture_source_policy:classification})}));
const reply={classification:'internal',cid:machineCid({fixture_response_policy:'internal'}),
  source_data_policy_cid:source[0].cid};
const cases=[['empty',[],[],false,'unknown'],
  ['unknown-literal',[],[],true,'unknown'],
  ['known',source.slice(0,3),[],false,'confidential'],
  ['unknown-retains-known',[source[4],source[2]],[],false,'unknown'],
  ['missing-retains-known',[source[2]],[],true,'unknown'],
  ['response-minimum',source.slice(0,1),[reply],false,'internal'],
  ['repeated-reference',[source[2],source[0],source[2]],[],false,'confidential']];
const vectors=cases.map(([name,sources,responses,unknown,expected])=>{
  const body=compose(sources,responses,unknown);
  assert.equal(body.classification,expected);
  assert.deepEqual(body,compose(sources.slice().reverse(),responses.slice().reverse(),unknown));
  return {name,sources,responses,body,cid:machineCid(body)};
});
assert.equal(vectors[2].body.source_data_policy_cids.length,3);
assert.equal(vectors[6].body.source_data_policy_cids.length,2);
assert.notEqual(vectors[0].cid,vectors[1].cid);
assert.notEqual(vectors[3].cid,vectors[4].cid);
assert.throws(()=>compose([], [reply]),/MissingResponseAuthority/);
// A submitted shape and matching hash cannot replace exact selected inputs.
function verify(body,sources,responses,unknown) {
  assert.deepEqual(Object.keys(body).sort(),contract.schemas.policy.required.slice().sort());
  assert.deepEqual(body,compose(sources,responses,unknown));
}
for(const v of vectors){
  verify(v.body,v.sources,v.responses,v.body.unknown_provenance);
  assert.throws(()=>verify({...v.body,validated:true},v.sources,v.responses,v.body.unknown_provenance));
  const changed={...v.body,classification:v.body.classification==='public'?'restricted':'public'};
  assert.throws(()=>verify(changed,v.sources,v.responses,v.body.unknown_provenance));
}
const known=vectors[2];
assert.throws(()=>verify({...known.body,source_data_policy_cids:known.body.source_data_policy_cids.slice().reverse()},
  known.sources,[],false));
assert.throws(()=>verify(known.body,source.slice(0,2),[],false));
const files=[['spec/contracts/actql-effective-data-policy.json',contract],
  ['portability/corpus/effective-data-policy.json',vectors]];
for(const [path,value] of files){
  if(process.argv.includes('--write')) writeFileSync(path,JSON.stringify(value,null,2)+'\n');
  assert.deepEqual(read(path),value);
}
const moon=['// Generated from independent effective-policy preimages; do not edit.',''];
for(const v of vectors) moon.push('///|',`test "effective policy ${v.name}" {`,
  '  let input = @json.parse(',`    ${JSON.stringify(canonicalText(v.body))},`,'  )',
  '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
  '  assert_eq(','    @canonical_json.cid_value(value, 100000, 10000, 100),',
  `    ${JSON.stringify(v.cid)},`,'  )','}','');
const path='src/canonical_json/effective_policy.generated_test.mbt';
if(process.argv.includes('--write')) writeFileSync(path,moon.join('\n'));
assert.equal(readFileSync(path,'utf8'),moon.join('\n'));
assert.ok(readFileSync('src/pipeline_check_context/core_contracts.mbt','utf8').includes(machineCid(contract)),
  'effective-policy interpretation pin is stale');
console.log(machineCid(contract),machineCid(contract.schemas.policy));
