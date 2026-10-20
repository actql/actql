import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent frozen preimages: never derive expectations from the issuer.
const catalogPreimage = "{\"applicability\":{\"audit_work_limit\":10000,\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"add\",\"and\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"multiply\",\"neq\",\"not\",\"or\",\"subtract\",\"typed_literal\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}";
const catalogCid = "sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587";
const journalPreimage = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587\",\"version\":\"actql-normalization-journal/0.1\"}";
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('published scoped catalog preserves independent preimage and both identities', () => {
  const expected = JSON.parse(catalogPreimage);
  assert.deepEqual(load('actql-effect-free-local-completion-free-catalog.json'), expected);
  assert.equal(cid(catalogPreimage), catalogCid);
  assert.equal(cid(journalPreimage), 'sha256:068f6d7eefb587836c72426fb4d579406247a97b27120621880cbd4a23874880');
  const issuer = readFileSync(new URL('../src/run_publication_host/client_local_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + catalogCid + '"'));
});

test('closed artifact schema freezes the audited profile and rejects broader catalogs', () => {
  const schema = load('actql-effect-free-local-completion-free-catalog.schema.json');
  const expected = JSON.parse(catalogPreimage);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
  for (const field of ['applicability', 'profile', 'version']) {
    assert.deepEqual(schema.properties[field], {const: expected[field]});
  }
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
});

test('fixture records independent canonical bytes without product issuance', () => {
  assert.deepEqual(load('actql-effect-free-local-completion-free-fixture.json'), {
    catalog_preimage: catalogPreimage, catalog_cid: catalogCid,
    journal_preimage: journalPreimage, journal_cid: cid(journalPreimage),
  });
});

test('local regression fixture preserves members and binds its own ordered Environment', () => {
  const source = readFileSync(new URL('../src/run_publication_host/client_composed_effect_fixture_wbtest.mbt', import.meta.url), 'utf8');
  const originalWire = source.match(/let client_composed_acquired_effect_environment : String =\n  #\|([^\n]+)/u)?.[1];
  assert(originalWire, 'the original composed Environment fixture must be retained');
  const canonical = value => value === null || typeof value !== 'object'
    ? JSON.stringify(value)
    : Array.isArray(value)
      ? '[' + value.map(canonical).join(',') + ']'
      : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  const original = JSON.parse(originalWire);
  assert.equal(canonical(original), originalWire);
  const {evidence_bundle_cid: originalCid, ...originalPreimage} = original;
  const retainedCid = 'sha256:7d396c299e58a85fec0efdfecd0801c94a4cded4b29215a75291428a32aee0aa';
  assert.equal(cid(canonical(originalPreimage)), retainedCid);
  assert.equal(originalCid, retainedCid);
  assert.notEqual(cid(originalWire), retainedCid, 'a full-wire digest is not the self identity');
  assert.notEqual(originalCid, 'sha256:cd4aeacdc39164df2cf7e7cb74faf349a157677a5927d9e84379d0d8df2d91e7');
  const originalHashes = original.connector_capabilities.map(member => cid(canonical(member)));
  assert(originalHashes[0] > originalHashes[1], 'retain the original unsorted-member refusal');
  const expected = structuredClone(originalPreimage);
  expected.connector_capabilities.reverse();
  const expectedCid = 'sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed';
  assert.equal(cid(canonical(expected)), expectedCid);
  const caller = readFileSync(new URL('../src/run_publication_host/client_local_normalization_wbtest.mbt', import.meta.url), 'utf8');
  const localWire = caller.match(/let local_normalization_environment_wire : String =\n  #\|([^\n]+)/u)?.[1];
  assert(localWire);
  const local = JSON.parse(localWire);
  assert.equal(localWire, canonical({...expected, evidence_bundle_cid: expectedCid}));
  assert.deepEqual(local.connector_capabilities.toReversed(), original.connector_capabilities);
  const {evidence_bundle_cid: localCid, ...localPreimage} = local;
  assert.equal(localCid, expectedCid);
  assert.equal(cid(canonical(localPreimage)), expectedCid);
  const originalExpected = caller.match(/admit_client_check_environment\(\s*local_normalization_environment_wire,\s*"([^"]+)"/u)?.[1];
  assert.equal(originalExpected, expectedCid);
});
