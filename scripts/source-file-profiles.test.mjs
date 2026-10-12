import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {fileListingProfile, fileContentProfile} from './source-file-profiles.mjs';

const contract = JSON.parse(readFileSync('spec/contracts/actql-check-environment.json', 'utf8'));

test('the authoritative Catalog generator retains both distinct closed file profiles', () => {
  const profiles = contract.contract_bodies.carrier_facts.properties;
  assert.deepEqual(profiles.file_listing, fileListingProfile());
  assert.deepEqual(profiles.file_content, fileContentProfile());
  assert.equal(profiles.file_listing.additionalProperties, false);
  assert.equal(profiles.file_content.additionalProperties, false);
  assert.equal(profiles.file_listing.properties.version.const, 'actql-file-list/0.1');
  assert.equal(profiles.file_content.properties.version.const, 'actql-file-content/0.1');
});

test('strict capture declares exact bytes and required version ability, not a count or permission', () => {
  const profile = contract.contract_bodies.carrier_facts.properties.file_content;
  assert.deepEqual(profile.required, ['version', 'kind', 'admitted_scope_contract_cid',
    'content_schema_contract_cid', 'version_capability', 'representation']);
  assert.deepEqual(Object.keys(profile.properties).sort(), [...profile.required].sort());
  assert.deepEqual(profile.properties.version_capability.required, ['contract_cid', 'required_nonnull']);
  assert.equal(profile.properties.version_capability.additionalProperties, false);
  assert.deepEqual(profile.properties.version_capability.properties.required_nonnull, {const: true});
  assert.deepEqual(profile.properties.representation, {const: 'exact_stored_bytes'});
  for (const name of ['admitted_scope_contract_cid', 'content_schema_contract_cid']) {
    assert.equal(profile.properties[name].pattern, '^sha256:[0-9a-f]{64}$');
  }
  // Metadata-only listings can still declare a nullable version. That is not
  // an implicit strict content capability.
  assert.deepEqual(contract.contract_bodies.carrier_facts.properties.file_listing
    .properties.version_capability.properties.required_nonnull, {type: 'boolean'});
});
