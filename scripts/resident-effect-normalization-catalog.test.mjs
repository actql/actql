import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent frozen preimages: never derive expectations from the issuer.
const catalogPreimage = "{\"applicability\":{\"checked_operations\":[\"filter\",\"select\",\"values\"],\"effect_kind\":\"mapped_create\",\"expression_nodes\":[\"$param\",\"and\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"neq\",\"not\",\"or\",\"typed_literal\"],\"max_source_inputs\":1,\"max_stages\":2,\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-resident-effect-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}";
const catalogCid = 'sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38';
const journalPreimage = '{"entries":[],"rule_catalog_cid":"sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38","version":"actql-normalization-journal/0.1"}';
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));

test('published scoped catalog preserves independent preimage and both identities', () => {
  const expected = JSON.parse(catalogPreimage);
  assert.deepEqual(load('actql-resident-effect-completion-free-catalog.json'), expected);
  assert.equal(cid(catalogPreimage), catalogCid);
  assert.equal(cid(journalPreimage), 'sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087');
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + catalogCid + '"'));
});

test('closed artifact schema freezes the audited profile and rejects broader catalogs', () => {
  const schema = load('actql-resident-effect-completion-free-catalog.schema.json');
  const expected = JSON.parse(catalogPreimage);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
  for (const field of ['applicability', 'profile', 'version']) {
    assert.deepEqual(schema.properties[field], {const: expected[field]});
  }
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
});
