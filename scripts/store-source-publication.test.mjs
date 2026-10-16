import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
const fixture=JSON.parse(readFileSync(new URL('./fixtures/store-source-targets/identities.json',import.meta.url),'utf8'));
const moon=readFileSync(new URL('../src/query_program/store_source_publication_test.mbt',import.meta.url),'utf8');
const bridge=readFileSync(new URL('../src/connectors_builtin_node/client_store_target_publication_wbtest.mbt',import.meta.url),'utf8');
const without=(body,key)=>Object.fromEntries(Object.entries(body).filter(([name])=>name!==key));
for(const [name,value] of Object.entries(fixture.cases)) {
  test(`independent complete Source STORE ${name} preimage`,()=>{
    const environment=value.environment;
    verifyIdentity(without(environment,'evidence_bundle_cid'),value.expected_environment_cid);
    assert.ok(moon.includes(canonicalText(environment)),'exact authored Moon caller preimage');
    if(['collection','collectionForeignCatalog'].includes(name)) assert.ok(bridge.includes(canonicalText(environment)),'actual Node bridge uses the same independent original preimage');
    for(const contract of environment.contract_registry) verifyIdentity(without(contract,'cid'),contract.cid);
    for(const mapping of environment.mapping_contracts) {
      verifyIdentity(without(mapping,'mapping_contract_cid'),value.expected_mapping_cid);
      verifyIdentity(mapping.target_schema,mapping.target_schema_identity);
      verifyIdentity(environment.connector_manifest.connectors[0],mapping.connector_manifest_cid);
      if(value.collection_identity_body) {
        verifyIdentity(value.collection_identity_body,value.collection_identity_cid);
        assert.equal(mapping.resource_identity_cid,value.collection_identity_cid);
        assert.equal(mapping.primary_identity,null);
        assert.deepEqual(mapping.permission_rules.map(rule=>[rule.effect_kind,rule.selector_class]),[['create','none']]);
      }
    }
    for(const catalog of environment.connector_catalogs) {
      verifyIdentity(without(catalog,'catalog_cid'),value.catalog_cid);
      for(const command of catalog.commands) {
        verifyIdentity(without(command,'contract_cid'),value.command_cid);
        assert.deepEqual(environment.command_contracts.find(item=>item.contract_cid===command.contract_cid),command);
        for(const [field,kind]of [['input_schema','command_input'],['output_schema','command_output']]) {
          const ref=command[field], contract=environment.contract_registry.find(item=>item.cid===ref.cid);
          assert.ok(contract,'complete original Command reference');
          assert.equal(contract.kind,kind);
          assert.equal(contract.id,ref.id);
          assert.equal(contract.version,ref.version);
          assert.deepEqual(catalog.contracts.find(item=>item.cid===ref.cid),contract);
        }
      }
    }
  });
}
