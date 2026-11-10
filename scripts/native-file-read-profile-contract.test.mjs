import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyNativeFileReadProfile} from './native-file-read-profile-contract.mjs';

test('Native file Content profile has its own closed implementation binding', () => {
  const {schema, cid} = verifyNativeFileReadProfile();
  assert.equal(schema.properties.version.const, 'actql-native-file-content-read/0.1');
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.properties.projection.additionalProperties, false);
  assert.deepEqual(schema.required, ['version', 'source_view_contract_cid',
    'physical_source_view_contract_cid', 'request_schema_cid',
    'response_schema_cid', 'projection', 'transport_cid']);
  for (const http of ['origin', 'method', 'headers', 'network_policy']) {
    assert.ok(!Object.hasOwn(schema.properties, http));
  }
  const registry = JSON.parse(readFileSync(
    'spec/contracts/actql-production-profile-schemas.json', 'utf8'));
  assert.equal(machineCid(registry.schemas.http_read_transport),
    'sha256:9d1b94d787b76a5e9ef6714bf9d44bc9c5edd42e3f9f60ffa106c9bc4ecb525c');
  assert.notEqual(cid, registry.schema_cids.http_read_transport);
  const lookup = JSON.parse(readFileSync('spec/contracts/actql-lookup-identities.json', 'utf8'));
  const binding = lookup.external_contracts['checked-read-profile'];
  assert.equal(binding.pointer, '/schemas/http_read_transport');
  assert.equal(binding.self_field, 'transport_cid');
  assert.equal(binding.implementations['actql-native-file-content-read/0.1'].schema_cid, cid);
  assert.equal(binding.implementations['unknown/0.1'], undefined);
});
