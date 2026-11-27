import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyNativeFileReadProfile, verifyDeclaredFileReadProfile,
  verifyInstalledRowSourceReadProfile} from './native-file-read-profile-contract.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';

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

test('installed row Source profile has one closed typed-array binding and independent identity', async () => {
  const {schema, cid} = verifyInstalledRowSourceReadProfile();
  assert.equal(cid, 'sha256:3dbdbd48a456fbfc9838dae8eb2f3b9b7577ef9ec8c74b57d5f3f66f475dffbe');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ['version', 'source_view_contract_cid',
    'request_schema_cid', 'response_schema_cid', 'response_encoding', 'transport_cid']);
  assert.deepEqual(Object.keys(schema.properties), schema.required);
  type Vector = {
    id: string;
    input: Record<string, string>;
    expected_cid: string;
    expected_json: string;
  };
  const corpus = JSON.parse(readFileSync('portability/corpus/canonical-json.json', 'utf8')) as {cases: Vector[]};
  const vector = corpus.cases.find(item => item.id === 'installed-row-source-read-profile-preimage')!;
  verifyIdentity(vector.input, vector.expected_cid, vector.expected_json);
  assert.equal(vector.expected_cid, 'sha256:92b44ed3a4f91fc60952e0028330b871325be1f73cad930dcd8f4a6858f6a169');
  const profile = {...vector.input, transport_cid: vector.expected_cid} as Record<string, string>;
  const {project, structuralValidatorSource} = await import('./generate-client-publication-wire.mjs');
  const source = 'const schemas={profile:' + JSON.stringify(project(schema)) + '};\n' +
    structuralValidatorSource({extended: true}) +
    'export const check=value=>valid(value,schemas.profile);';
  const {check} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  assert.equal(check(profile), true);
  for (const field of schema.required) {
    const missing = {...profile}; delete missing[field];
    assert.equal(check(missing), false, field);
  }
  for (const changed of [
    {...profile, version: 'actql-declared-file-content-read/0.1'},
    {...profile, response_encoding: 'utf8'},
    {...profile, response_encoding: 'json'},
    {...profile, response_schema_cid: 'sha256:' + 'x'.repeat(64)},
    {...profile, source_view_contract_cid: profile.source_view_contract_cid.slice(1)},
    {...profile, physical_source_view_contract_cid: profile.source_view_contract_cid},
    {...profile, projection: {}},
    {...profile, content_utf8: 'not the binary Content body'},
  ]) assert.equal(check(changed), false);
  // Shape-valid DATA does not certify its self hash or private physical owner.
  const wrongCid = {...profile, transport_cid: 'sha256:' + '4'.repeat(64)};
  assert.equal(check(wrongCid), true);
  assert.throws(() => verifyIdentity(vector.input, wrongCid.transport_cid));
  for (const field of ['source_view_contract_cid', 'request_schema_cid', 'response_schema_cid']) {
    assert.throws(() => verifyIdentity({...vector.input, [field]: wrongCid.transport_cid},
      vector.expected_cid));
  }
  const lookup = JSON.parse(readFileSync('spec/contracts/actql-lookup-identities.json', 'utf8'));
  const binding = lookup.external_contracts['checked-read-profile'];
  assert.equal(binding.pointer, '/schemas/http_read_transport');
  assert.equal(binding.implementations['actql-installed-row-source-read/0.1'].pointer,
    '/schemas/installed_row_source_read');
  assert.equal(binding.implementations['actql-installed-row-source-read/0.1'].self_field, 'transport_cid');
  assert.equal(binding.implementations['actql-installed-row-source-read/0.1'].schema_cid, cid);
  assert.equal(binding.implementations['unknown/0.1'], undefined);
});
