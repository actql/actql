import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {mappingContractBody} from './mapping-contract.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';

const fixture = JSON.parse(readFileSync('portability/corpus/collection-mapping.json', 'utf8'));

test('collection Mapping pins typed collection facts without inventing row identity', () => {
  assert.equal(fixture.version, 'actql-collection-mapping-vectors/0.1');
  const body = fixture.body;
  assert.equal(body.primary_identity, null);
  assert.deepEqual(Object.keys(body.target_schema.fields), ['text']);
  verifyIdentity(fixture.connector_manifest_entry, body.connector_manifest_cid);
  verifyIdentity(fixture.collection_resource_identity, body.resource_identity_cid);
  assert.equal(body.resource_identity_cid, fixture.collection_resource_identity_cid);
  verifyIdentity(body.target_schema, body.target_schema_identity);
  const {mapping_contract_cid, ...preimage} = body;
  verifyIdentity(preimage, mapping_contract_cid);
  assert.throws(() => verifyIdentity({...preimage, primary_identity: 'text'}, mapping_contract_cid));
  assert.throws(() => verifyIdentity({...preimage, target_ref: 'connector://fixture/other'}, mapping_contract_cid));
  assert.throws(() => verifyIdentity({...fixture.collection_resource_identity,
    collection_identity: {container: 'weekly', partition: 8}}, body.resource_identity_cid));
  const {primary_identity, ...omitted} = preimage;
  assert.throws(() => verifyIdentity(omitted, mapping_contract_cid));
});

test('the closed schema distinguishes explicit null from omission and confines every rule', () => {
  const schema = mappingContractBody().schema;
  assert.ok(schema.required.includes('primary_identity'));
  assert.deepEqual(schema.properties.primary_identity,
    {oneOf: [{type: 'string', minLength: 1}, {type: 'null'}]});
  assert.deepEqual(schema.allOf, [{
    if: {properties: {primary_identity: {type: 'null'}}, required: ['primary_identity']},
    then: {properties: {permission_rules: {items: {properties: {
      effect_kind: {const: 'create'}, selector_class: {const: 'none'},
    }}}}},
  }]);
  const collection = mappingContractBody().collection_resource_identity;
  assert.equal(collection.additionalProperties, false);
  assert.deepEqual(Object.keys(fixture.collection_resource_identity).sort(), collection.required.toSorted());
  assert.equal(collection.properties.collection_identity.minProperties, 1);
});
