import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export function commandTargetBindingVectors(corpus) {
  const output=['// Generated from independent fixed corpus by scripts/command-target-binding-vectors.mjs.'];
  const expected=['legacy-field','installation','identifier'];
  assert.deepEqual(corpus.cases.map(value=>value.id),expected);
  const identities=new Set();
  const self=(body,field)=>{
    const {[field]:claimed,...preimage}=body;
    assert.equal(machineCid(preimage),claimed,field);
    return claimed;
  };
  for(const vector of corpus.cases){
    const environment=vector.environment,catalog=environment.connector_catalogs[0];
    const command=catalog.commands[0];
    assert.equal(self(environment,'evidence_bundle_cid'),vector.environment_cid);
    assert.equal(self(catalog,'catalog_cid'),vector.catalog_cid);
    assert.equal(self(command,'contract_cid'),vector.command_cid);
    assert.deepEqual(environment.command_contracts,[command]);
    assert.deepEqual(environment.contract_registry,catalog.contracts);
    assert.equal(catalog.connector_id,command.connector_id);
    const {contract_cid,...withoutCid}=command;
    const original=structuredClone(withoutCid);
    delete original.target.binding;
    assert.deepEqual(original,corpus.original_command);
    assert.deepEqual(command.target.binding??null,vector.binding);
    for(const envelope of [corpus.input_envelope,corpus.output_envelope])self(envelope,'cid');
    assert.deepEqual(catalog.contracts,[corpus.input_envelope,corpus.output_envelope].sort((a,b)=>a.cid<b.cid?-1:1));
    for(const identity of [vector.command_cid,vector.catalog_cid,vector.environment_cid]){
      assert(!identities.has(identity));identities.add(identity);
    }
    output.push('','///|',`test ${JSON.stringify('Original Command target fixed identity '+vector.id)} {`,
      '  let environment = read(',
      `    @utf8.encode(${JSON.stringify(JSON.stringify(environment))}),`,
      `    ${JSON.stringify(vector.environment_cid)}, caps(),`,
      '  ).unwrap()',
      '  let contents = check_catalog_contents(check_contract_registry(environment, caps()).unwrap(), caps()).unwrap()');
    if(vector.id==='legacy-field'){
      output.push('  let target = select_command_target(contents, "command:mail.send.v1", 1000).unwrap()',
        '  assert_true(select_published_command_binding(contents, "command:mail.send.v1", published_command_limits(), 1000) is Err(MissingBinding))');
    }else{
      output.push('  let bound = select_published_command_binding(contents, "command:mail.send.v1", published_command_limits(), 1000).unwrap()',
        '  let target = published_command_binding_target(bound)',
        `  assert_eq(published_command_binding_mode(bound), ${vector.id==='installation'?'Installation':'Identifier'})`,
        '  assert_true(select_command_target(contents, "command:mail.send.v1", 1000) is Err(InvalidCommand("command:mail.send.v1")))');
    }
    output.push(`  assert_eq(command_target_cid(target), ${JSON.stringify(vector.command_cid)})`,
      `  assert_eq(catalog_identity(command_target_catalog(target)).2, ${JSON.stringify(vector.catalog_cid)})`,
      `  assert_eq(cid(member_environment(command_target_member(target))), ${JSON.stringify(vector.environment_cid)})`,
      '  assert_true(physical_equal(member_environment(command_target_member(target)), environment))','}');
  }
  return output.join('\n')+'\n';
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const corpus=JSON.parse(readFileSync('portability/corpus/command-target-bindings.json','utf8'));
  const output=commandTargetBindingVectors(corpus);
  const path='src/check_environment/command_target_bindings.generated_test.mbt';
  if(process.argv.includes('--write'))writeFileSync(path,output);
  assert.equal(readFileSync(path,'utf8'),output);
  console.log(`Original Command/Catalog/environment independent identities: ${corpus.cases.length}`);
}
