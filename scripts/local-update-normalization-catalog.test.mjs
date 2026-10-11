import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent frozen preimages: never derive expectations from the issuer.
const catalogPreimage = "{\"applicability\":{\"audit_work_limit\":10000,\"change_sources\":[\"field\",\"scalar_literal\"],\"checked_operations\":[\"filter\",\"select\",\"values\"],\"effect_kind\":\"mapped_update\",\"expression_nodes\":[\"$param\",\"and\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"neq\",\"not\",\"or\",\"typed_literal\"],\"mapping_conversions\":\"none\",\"max_source_inputs\":1,\"max_stages\":2,\"proof\":\"original-checked-computation-and-update-owners-audit\",\"selector_classes\":[\"id\"],\"source_selection\":\"explicit\"},\"profile\":\"actql-local-update-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}";
const catalogCid = "sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468";
const journalPreimage = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468\",\"version\":\"actql-normalization-journal/0.1\"}";
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('published scoped catalog preserves independent preimage and both identities', () => {
  const expected = JSON.parse(catalogPreimage);
  assert.deepEqual(load('actql-local-update-completion-free-catalog.json'), expected);
  assert.equal(cid(catalogPreimage), catalogCid);
  assert.equal(cid(journalPreimage), 'sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d');
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + catalogCid + '"'));
});

test('closed artifact schema freezes the audited profile and rejects broader catalogs', () => {
  const schema = load('actql-local-update-completion-free-catalog.schema.json');
  const expected = JSON.parse(catalogPreimage);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
  for (const field of ['applicability', 'profile', 'version']) {
    assert.deepEqual(schema.properties[field], {const: expected[field]});
  }
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
});

test('fixture records independent canonical bytes without product issuance', () => {
  assert.deepEqual(load('actql-local-update-completion-free-fixture.json'), {
    catalog_preimage: catalogPreimage, catalog_cid: catalogCid,
    journal_preimage: journalPreimage, journal_cid: "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
  });
});
