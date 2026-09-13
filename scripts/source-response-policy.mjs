import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
const cid={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const levels=['public','internal','confidential','restricted'];
export const contract={version:'actql-source-response-policy-contract/0.1',
  schemas:{policy:{$schema:'https://json-schema.org/draft/2020-12/schema',type:'object',additionalProperties:false,
    required:['version','source_ref','source_view_contract_cid','source_data_policy_cid','minimum_classification','classification'],
    properties:{version:{const:'actql-source-response-policy/0.1'},source_ref:{type:'string',minLength:1},
      source_view_contract_cid:cid,source_data_policy_cid:cid,
      minimum_classification:{anyOf:[{enum:levels},{type:'null'}]},
      classification:{enum:[...levels,'unknown']}}}},
  semantics:{identity:'entire_policy_canonical_json_utf8_sha256_no_self_cid',
    classification:'authoritative_unknown_stays_unknown_otherwise_max_authoritative_and_authored_minimum',
    source:'exact_selected_sourceview_and_its_admitted_data_policy_reference',
    exclusions:'no_request_input_provenance_observation_host_permission_or_capacity',
    authority:'policy_identity_is_not_egress_or_execution_permission'}};
const path='spec/contracts/actql-source-response-policy.json';
if(process.argv.includes('--write')) writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),contract);
if(process.argv.includes('--print-pin')) console.log(machineCid(contract),machineCid(contract.schemas.policy));
// Independent inputs and expected classifications, never product emitter output.
const vectors=[];
for(const authoritative of [...levels,'unknown']) for(const minimum of [null,...levels]) {
  const classification=authoritative==='unknown'?'unknown':levels[Math.max(levels.indexOf(authoritative),levels.indexOf(minimum))];
  const body={version:'actql-source-response-policy/0.1',source_ref:'connector://fixture/records#scan',
    source_view_contract_cid:machineCid({fixture:'selected-view'}),
    source_data_policy_cid:machineCid({version:'actql-source-data-policy/0.1',
      source_ref:'connector://fixture/records#scan',classification:authoritative}),
    minimum_classification:minimum,classification};
  vectors.push({authoritative,body,cid:machineCid(body)});
}
const fixture='portability/corpus/source-response-policy.json';
if(process.argv.includes('--write')) writeFileSync(fixture,JSON.stringify(vectors,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(fixture,'utf8')),vectors);
assert.equal(vectors.length,25);
