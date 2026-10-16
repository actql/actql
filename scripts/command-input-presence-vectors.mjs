import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText,verifyIdentity} from './check-canonical-json.mjs';

const corpus=JSON.parse(readFileSync('portability/corpus/command-input-presence.json','utf8'));
const output=['// Generated from independent fixed corpus by scripts/command-input-presence-vectors.mjs.'];
const all=new Set();
for(const vector of corpus.cases){
  const body={additional_properties:false,fields:corpus.fields,required_fields:vector.required_fields};
  verifyIdentity(body,vector.body_cid);
  const input={body,id:'crm.input',kind:'command_input',schema:'actql.contract/0.1',version:'external'};
  verifyIdentity(input,vector.envelope_cid);
  input.cid=vector.envelope_cid;
  const out={body:corpus.output_role_body,id:'crm.output',kind:'command_output',schema:'actql.contract/0.1',version:'external'};
  const reference=x=>({cid:x.cid,id:x.id,version:x.version});
  // Independent hashing builds fixture inputs, never expected product output.
  const hash=value=>'sha256:'+createHash('sha256').update(canonicalText(value)).digest('hex');
  out.cid=hash(out);
  const command={atomicity:'single_target',command_id:'command:crm.invoke.v1',connector_id:'example',
    idempotency:{support:'unsupported'},input_contract:body,input_schema:reference(input),
    minimum_approval:'required',outcome:'synchronous',output_schema:reference(out),permissions:['crm.write'],
    preview:{strength:'exact'},reversibility:'unknown',schema:'actql.command_contract/0.1',
    target:{cardinality:'single',resource_kind:'crm/account'},version:'external-1'};
  verifyIdentity(command,vector.command_cid);
  command.contract_cid=vector.command_cid;
  const catalog={commands:[command],connector_id:'example',connector_version:'external-7',
    contracts:[input,out].sort((a,b)=>a.cid<b.cid?-1:1),schema:'actql.connector_catalog/0.1',source_views:[]};
  verifyIdentity(catalog,vector.catalog_cid);
  for(const key of ['body_cid','envelope_cid','command_cid','catalog_cid']){
    assert.ok(!all.has(vector[key]),'each complete identity remains distinct');all.add(vector[key]);
  }
  output.push('','///|',`test ${JSON.stringify('Command presence fixed identity '+vector.id)} {`,
    `  let targets = presence_targets(${JSON.stringify('{"name":{"literal":"n"},"overwrite":{"literal":false}}')}, required=${JSON.stringify(JSON.stringify(vector.required_fields))})`,
    '  let target = effect_command_target_contract(effect_command_target_at(targets, 0).unwrap())',
    `  assert_eq(@environment.command_target_cid(target), ${JSON.stringify(vector.command_cid)})`,
    `  assert_eq(@environment.catalog_identity(@environment.command_target_catalog(target)).2, ${JSON.stringify(vector.catalog_cid)})`,
    '  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()',
    '  let reference = @environment.catalog_reference_for_cursor(effect_command_targets_references(targets), @decode.lookup(command, "input_schema").unwrap()).unwrap()',
    `  assert_eq(@environment.contract_identity(@environment.reference_contract(reference)).2, ${JSON.stringify(vector.envelope_cid)})`,
    '  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()',
    '  assert_eq(effect_command_input_field_count(effect_command_input_at(admitted, 0).unwrap()), 2)',
    '}');
}
const path='src/stage_results/command_input_presence.generated_test.mbt';
const text=output.join('\n')+'\n';
if(process.argv.includes('--write'))writeFileSync(path,text);
assert.equal(readFileSync(path,'utf8'),text);
console.log(`Command presence independent body/Envelope/Command/Catalog identities: ${corpus.cases.length}`);
