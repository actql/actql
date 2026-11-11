import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyNativeFileReadProfile, verifyDeclaredFileReadProfile} from './native-file-read-profile-contract.mjs';

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

test('installed Node declared-file profile has a distinct closed binding and retains Native identity', () => {
  const {schema, cid} = verifyDeclaredFileReadProfile();
  const native = verifyNativeFileReadProfile();
  assert.equal(native.cid, 'sha256:087884120840e8d5c74043dfd74af35ccb7b535d9a9e8c01d68a45f9afb76e08');
  assert.equal(schema.properties.version.const, 'actql-declared-file-content-read/0.1');
  assert.equal(schema.$id, 'https://smooth.dev/schemas/actql-declared-file-content-read-0.1.json');
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.properties.projection.additionalProperties, false);
  assert.deepEqual(Object.keys(schema.properties.projection.properties), ['identity_field', 'name_field',
    'version_field', 'media_type_field', 'content_utf8_field', 'path_field', 'items_path', 'key_path']);
  assert.equal(cid, 'sha256:3385e23c7a3046cffb522dea96c81722d3dba3ae688d9007b49e317386da7d0c');
  assert.notEqual(cid, native.cid);
  const lookup = JSON.parse(readFileSync('spec/contracts/actql-lookup-identities.json', 'utf8'));
  const binding = lookup.external_contracts['checked-read-profile'].implementations;
  assert.equal(binding['actql-declared-file-content-read/0.1'].schema_cid, cid);
  assert.equal(binding['actql-native-file-content-read/0.1'].schema_cid, native.cid);
  assert.equal(binding['unknown/0.1'], undefined);
});
