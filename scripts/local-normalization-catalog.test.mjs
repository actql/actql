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
