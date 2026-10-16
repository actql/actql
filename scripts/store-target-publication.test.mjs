import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

const fixture=JSON.parse(readFileSync(new URL('./fixtures/store-targets/identities.json',import.meta.url),'utf8'));
const moon=readFileSync(new URL('../src/query_program/store_target_binding_test.mbt',import.meta.url),'utf8');
const without=(value,key)=>Object.fromEntries(Object.entries(value).filter(([name])=>name!==key));
for(const [name,value] of Object.entries(fixture.cases)) {
  test(`independent STORE ${name} publication retains every original identity`,()=>{
    const environment=value.environment;
    verifyIdentity(without(environment,'evidence_bundle_cid'),value.expected_environment_cid);
    assert.equal(environment.evidence_bundle_cid,value.expected_environment_cid);
    assert.ok(moon.includes(canonicalText(environment)),'Moon caller uses the identical authored preimage');
    // The normative pin names one manifest entry, not its outer envelope.
    verifyIdentity(environment.connector_manifest.connectors[0],environment.mapping_contracts[0].connector_manifest_cid);
    for(const mapping of environment.mapping_contracts) {
      verifyIdentity(without(mapping,'mapping_contract_cid'),mapping.mapping_contract_cid);
      verifyIdentity(mapping.target_schema,mapping.target_schema_identity);
    }
    assert.ok(environment.mapping_contracts.some(mapping=>mapping.mapping_contract_cid===value.expected_mapping_cid));
    for(const catalog of environment.connector_catalogs) {
      verifyIdentity(without(catalog,'catalog_cid'),catalog.catalog_cid);
      assert.equal(catalog.catalog_cid,value.catalog_cid);
      for(const command of catalog.commands) {
        verifyIdentity(without(command,'contract_cid'),command.contract_cid);
        assert.deepEqual(environment.command_contracts.find(item=>item.contract_cid===command.contract_cid),command);
      }
    }
  });
}
