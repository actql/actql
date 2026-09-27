import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {canonicalText,verifyIdentity} from './check-canonical-json.mjs';
import {checkLookupCapacity} from './check-lookup-capacity.mjs';
import {checkLookupExecution} from './check-lookup-execution.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const contract=read('spec/contracts/actql-check-environment.json');
const corpus=read('portability/corpus/check-environment.json');
test('Calendar selection independently pins transition bytes release and conversion law',()=>{
  const c=contract.policy_components.calendar,s=c.schema;
  assert.equal(c.pointer,'/host_policy_profile/calendar');
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['version','table_bytes_cid','tzdb_version','conversion_law']);
  const valid={version:'actql-calendar-selection/0.1',table_bytes_cid:'sha256:'+'a'.repeat(64),tzdb_version:'2025b',conversion_law:'actql-calendar-boundaries/0.1'};
  function accepts(v){
    if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==4)return false;
    return s.required.every(k=>{
      const p=s.properties[k],x=v[k];
      if(p.const)return x===p.const;
      return typeof x==='string'&&(p.pattern?new RegExp(p.pattern).test(x):x.length>=p.minLength);
    });
  }
  assert.equal(accepts(valid),true);
  for(const k of s.required){const v={...valid};delete v[k];assert.equal(accepts(v),false);assert.equal(accepts({...valid,[k]:null}),false);}
  for(const v of [null,[],{}, {...valid,extra:true},{...valid,tzdb_version:''},{...valid,conversion_law:'other'}, {...valid,table_bytes_cid:'sha256:'+'A'.repeat(64)}])assert.equal(accepts(v),false);
  assert.equal(accepts({...valid,tzdb_version:'external-custom-release'}),true);
  assert.equal(c.present,'validate_even_when_unused_null_is_not_absence');
  assert.match(c.selection,/original_table_bytes_cid_external_release/);
});
test('lexical profile selection is closed and distinguishes selected bytes from component identity',()=>{
  const c=contract.policy_components.text_rank;
  assert.equal(c.pointer,'/host_policy_profile/text_rank');
  assert.equal(c.absent,'unresolved_no_implicit_defaults');
  assert.equal(c.present,'validate_even_when_unused_null_is_not_absence');
  assert.equal(c.schema.additionalProperties,false);
  assert.deepEqual(c.schema.required,['version','profile_bytes_cid']);
  const accepts=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)
    &&Object.keys(v).length===2
    &&v.version===c.schema.properties.version.const
    &&typeof v.profile_bytes_cid==='string'
    &&new RegExp(c.schema.properties.profile_bytes_cid.pattern).test(v.profile_bytes_cid);
  const valid={version:'actql-text-rank-selection/0.1',profile_bytes_cid:'sha256:'+'a'.repeat(64)};
  assert.equal(accepts(valid),true);
  for(const v of [null,[],{}, {...valid,extra:true},{version:valid.version},
    {...valid,version:'actql-text-rank-selection/1.0'},
    ...[null,1,'sha256:'+'A'.repeat(64),'sha256:'+'a'.repeat(63),'sha256:'+'a'.repeat(65)].map(profile_bytes_cid=>({...valid,profile_bytes_cid}))])assert.equal(accepts(v),false);
  assert.equal(c.identity,'full_canonical_component_body_no_exclusions');
  assert.match(c.selection,/match_profile_original_bytes_cid/);
  assert.match(c.selection,/verify_all_profile_dependency_pins/);
});
test('lookup Host policy has separate wire and decoded ceilings without implicit defaults',()=>{
  assert.equal(checkLookupExecution(),22);
  const c=read('portability/corpus/lookup-execution-policy.json');
  const component=contract.policy_components.lookup_execution;
  const s=component.schema;
  assert.equal(c.version,'actql-lookup-execution-policy-vectors/0.1');
  assert.equal(component.pointer,'/host_policy_profile/lookup_execution');
  assert.equal(component.absent,'unresolved_no_implicit_defaults');
  assert.equal(component.present,'validate_even_when_unused_null_is_not_absence');
  assert.equal(component.identity,'full_canonical_component_body_no_exclusions');
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['version','max_network_attempts_per_request','max_request_bytes_per_attempt','max_total_request_bytes','max_total_response_bytes','max_total_decoded_response_bytes','max_total_duration_ms']);
  // Only the explicit closed object/scalar schema subset; not policy selection.
  function accepts(v){
    if(!v||typeof v!=='object'||Array.isArray(v))return false;
    if(s.required.some(k=>!Object.hasOwn(v,k)))return false;
    return Object.entries(v).every(([k,x])=>{
      const p=s.properties[k];if(!p)return false;
      if(Object.hasOwn(p,'const'))return x===p.const;
      assert.equal(p.type,'integer');
      return typeof x==='number'&&Number.isInteger(x)&&x>=p.minimum&&x<=p.maximum;
    });
  }
  for(const v of c.cases)assert.equal(accepts({...c.base,...v.patch}),v.accepted,v.id);
  for(const k of s.required){
    const v={...c.base};delete v[k];assert.equal(accepts(v),false,k);
    if(k==='version')continue;
    assert.deepEqual(s.properties[k],{type:'integer',minimum:1,maximum:9007199254740991});
    for(const x of [0,-1,1.5,9007199254740992,'1',null])assert.equal(accepts({...c.base,[k]:x}),false,k);
  }
  for(const v of [null,[],{},true,1,'lookup'])assert.equal(accepts(v),false);
  const bytes=canonicalText(c.base);
  verifyIdentity(c.base,c.expected_cid,c.expected_canonical);
  assert.notEqual(canonicalText({...c.base,max_total_response_bytes:65536,max_total_decoded_response_bytes:16384}),bytes);
});
test('lookup capacity fixed shapes distinguish completeness from hard limits',()=>{
  assert.equal(checkLookupCapacity(),22);
  const vectors=read('portability/corpus/lookup-capacity.json');
  const schema=contract.contract_bodies.carrier_facts.properties.lookup_capacity;
  assert.equal(vectors.version,'actql-lookup-capacity-vectors/0.1');
  assert.equal(contract.contract_bodies.carrier_facts.additionalProperties,true);
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(schema.required,['version','completeness','max_rows_per_key','max_pages_per_request','max_response_bytes_per_page']);
  // Interpreter only for this closed scalar schema subset, not evidence admission.
  function accepts(v){
    if(!v||typeof v!=='object'||Array.isArray(v))return false;
    if(schema.required.some(k=>!Object.hasOwn(v,k)))return false;
    return Object.entries(v).every(([k,x])=>{
      const p=schema.properties[k];if(!p)return false;
      if(Object.hasOwn(p,'const'))return x===p.const;
      if(p.enum)return p.enum.includes(x);
      assert.equal(p.type,'integer');
      return typeof x==='number'&&Number.isInteger(x)&&x>=p.minimum&&x<=p.maximum;
    });
  }
  for(const c of vectors.cases){
    const v={...vectors.base,...c.patch};
    assert.equal(accepts(v),c.accepted,c.id);
    if(c.accepted)assert.equal(v.completeness==='complete_per_requested_key',c.supports_completeness,c.id);
  }
  for(const key of schema.required){
    const v={...vectors.base};delete v[key];assert.equal(accepts(v),false,key);
  }
  for(const v of [null,[],{},true,1,'complete'])assert.equal(accepts(v),false);
  const factsAccept=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)
    &&(!Object.hasOwn(v,'lookup_capacity')||accepts(v.lookup_capacity));
  for(const v of [{},{completeness:'complete'},{future_facts:{x:1}}]){
    assert.equal(factsAccept(v),true);
    assert.equal(Object.hasOwn(v,'lookup_capacity'),false);
  }
  assert.equal(factsAccept({lookup_capacity:null}),false);
  assert.equal(factsAccept({lookup_capacity:vectors.base,completeness:'unrelated'}),true);
  for(const key of ['max_rows_per_key','max_pages_per_request','max_response_bytes_per_page']){
    assert.deepEqual(schema.properties[key],{type:'integer',minimum:1,maximum:9007199254740991});
    for(const value of [0,-1,0.5,9007199254740992,null,'1']){
      assert.equal(accepts({...vectors.base,[key]:value}),false,key);
    }
  }
});
test('source data policy body is closed and retains unknown classification',()=>{
  assert.deepEqual(contract.contract_bodies.data_policy,{
    type:'object',additionalProperties:false,
    required:['version','source_ref','classification'],
    properties:{
      version:{const:'actql-source-data-policy/0.1'},
      source_ref:{type:'string',minLength:1},
      classification:{enum:['public','internal','confidential','restricted','unknown']},
    },
  });
});
test('Mapping 0.1 body pins the complete resolved target and permission dimensions',()=>{
  const mapping=contract.mapping_contract_bodies;
  const schema=mapping.schema;
  const fixture=read('portability/corpus/mapping-contract.json');
  const body=fixture.body;
  assert.equal(fixture.version,'actql-mapping-contract-vectors/0.1');
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(Object.keys(body).sort(),[...schema.required].sort());
  assert.equal(schema.properties.schema.const,'actql.mapping_contract/0.1');
  assert.equal(schema.required.includes('target_schema_reference'),false);
  assert.deepEqual(schema.properties.target_schema_reference.required,
    ['id','version','cid']);
  assert.equal(schema.properties.mapping_ref.pattern,
    '^mapping:[A-Za-z0-9][A-Za-z0-9._/-]*\\.v[0-9]+$');
  assert.equal(schema.properties.minimum_approval.enum.join(','),'none,required');
  assert.equal(schema.properties.permission_rules.items.additionalProperties,false);
  assert.deepEqual(schema.properties.permission_rules.items.required,
    ['effect_kind','selector_class','write_fields','permissions']);
  assert.equal(schema.properties.permission_rules.items.properties.permissions.minItems,1);
  assert.equal(schema.properties.row_mapping.additionalProperties.oneOf.length,2);
  verifyIdentity(body.target_schema,body.target_schema_identity);
  const {mapping_contract_cid,...preimage}=body;
  verifyIdentity(preimage,mapping_contract_cid);
  assert.equal(mapping.semantics.preimage,'entire_canonical_body_except_mapping_contract_cid');
  assert.equal(mapping.semantics.authority,
    'static_contract_not_current_resource_permission_or_apply_permit');
  // The Mapping names one connector manifest entry by the entry's own CID.
  verifyIdentity(fixture.connector_manifest_entry,
    fixture.connector_manifest_entry_cid);
  assert.equal(body.connector_manifest_cid, fixture.connector_manifest_entry_cid);
  const entrySchema=contract.schema.properties.connector_manifest.properties
    .connectors.items;
  assert.equal(entrySchema.additionalProperties,false);
  assert.deepEqual(Object.keys(fixture.connector_manifest_entry).sort(),
    [...entrySchema.required].sort());
  assert.equal(contract.schema.required.includes('connector_manifest'),false);
  assert.equal(mapping.semantics.connector_manifest,
    'connector_manifest_cid_is_the_entry_cid_of_one_environment_manifest_entry_whose_connector_id_owns_target_ref');
  const changed={...preimage,target_ref:'connector://crm/contact'};
  assert.notEqual(createHash('sha256').update(canonicalText(changed)).digest('hex'),
    mapping_contract_cid.slice('sha256:'.length));
});
// Only the explicit envelope schema subset; component admission is separate.
function shape(value){
  const s=contract.schema;
  if(value===null||typeof value!=='object'||Array.isArray(value))return false;
  if(s.required.some(k=>!Object.hasOwn(value,k)))return false;
  for(const [k,v] of Object.entries(value)){
    if(!Object.hasOwn(s.properties,k))return false;
    const p=s.properties[k];
    if(p.const!==undefined&&v!==p.const)return false;
    if(p.type==='object'&&(!v||typeof v!=='object'||Array.isArray(v)))return false;
    if(p.type==='array'&&(!Array.isArray(v)||v.some(e=>!e||typeof e!=='object'||Array.isArray(e))))return false;
    if(p.type==='string'&&(typeof v!=='string'||!new RegExp(p.pattern,'u').test(v)))return false;
  }
  return true;
}
test('closed envelope shape requires all sections without validating their contents',()=>{
  for(const c of corpus.cases){
    const wire=JSON.parse(c.expected_wire);
    assert.ok(shape(wire));
    for(const key of Object.keys(wire)){
      const copy=structuredClone(wire); delete copy[key]; assert.equal(shape(copy),false,key);
    }
    assert.equal(shape({...wire,check_environment_cid:wire.evidence_bundle_cid}),false);
    assert.equal(shape({...wire,schema_snapshots:null}),false);
    assert.equal(shape({...wire,connector_catalogs:[null]}),false);
  }
});
test('only the root identity member is excluded from the preimage',()=>{
  for(const c of corpus.cases){
    const {evidence_bundle_cid,...preimage}=JSON.parse(c.expected_wire);
    verifyIdentity(preimage,evidence_bundle_cid,c.expected_preimage);
    assert.throws(()=>verifyIdentity({...preimage,version:'wrong'},evidence_bundle_cid));
    assert.throws(()=>verifyIdentity(JSON.parse(c.expected_wire),evidence_bundle_cid));
  }
  const c=corpus.cases.find(c=>c.id==='nested-identity-data');
  const {evidence_bundle_cid,...preimage}=JSON.parse(c.expected_wire);
  delete preimage.host_policy_profile.extension.evidence_bundle_cid;
  assert.notEqual(canonicalText(preimage),c.expected_preimage);
  assert.throws(()=>verifyIdentity(preimage,evidence_bundle_cid));
});
