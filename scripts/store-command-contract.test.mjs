import assert from 'node:assert/strict';
import test from 'node:test';
import {mappingContractBody} from './mapping-contract.mjs';

test('the optional STORE relation binds exact original Catalog and Command identities', () => {
  const mapping=mappingContractBody();
  assert.equal(mapping.schema.required.includes('store_command'),false);
  assert.deepEqual(mapping.schema.properties.store_command,{
    type:'object',additionalProperties:false,
    required:['catalog_cid','command_ref','command_contract_cid'],
    properties:{
      catalog_cid:{type:'string',pattern:'^sha256:[0-9a-f]{64}$'},
      command_ref:{type:'string',pattern:'^command:[A-Za-z0-9][A-Za-z0-9._/-]*\\.v[0-9]+$'},
      command_contract_cid:{type:'string',pattern:'^sha256:[0-9a-f]{64}$'},
    },
  });
  assert.equal(mapping.semantics.preimage,'entire_canonical_body_except_mapping_contract_cid');
  assert.equal(mapping.semantics.authority,'static_contract_not_current_resource_permission_or_apply_permit');
});
