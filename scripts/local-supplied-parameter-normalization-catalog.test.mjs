import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independently authored complete preimages, never product output.
const catalogPreimage = "{\"applicability\":{\"audit_work_limit\":10000,\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"add\",\"and\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"multiply\",\"neq\",\"not\",\"or\",\"subtract\",\"typed_literal\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}";
const catalogCid = "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1";
const journalPreimage = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1\",\"version\":\"actql-normalization-journal/0.1\"}";
const journalCid = "sha256:016cfc9cf2e38145078b53c715472cf6a14415c4d40c5bed219cc526797424aa";
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
const prefix = 'actql-effect-free-local-supplied-parameters-completion-free-';

test('supplied-Parameter applicability has independent complete catalog and journal identities', () => {
  assert.deepEqual(load(prefix + 'catalog.json'), JSON.parse(catalogPreimage));
  assert.equal(cid(catalogPreimage), catalogCid);
  assert.equal(cid(journalPreimage), journalCid);
  assert.deepEqual(load(prefix + 'fixture.json'), {
    catalog_preimage: catalogPreimage, catalog_cid: catalogCid,
    journal_preimage: journalPreimage, journal_cid: journalCid,
  });
});

test('supplied-Parameter catalog is a closed alternative preserving the original parameter-free body', () => {
  const expected = JSON.parse(catalogPreimage);
  const schema = load(prefix + 'catalog.schema.json');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
  for (const field of ['applicability', 'profile', 'version']) {
    assert.deepEqual(schema.properties[field], {const: expected[field]});
  }
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  const prior = load('actql-effect-free-local-completion-free-fixture.json');
  const oldBody = JSON.parse(prior.catalog_preimage);
  const restored = structuredClone(expected);
  restored.applicability.expression_nodes.shift();
  restored.applicability.parameter_declarations = 'none';
  assert.deepEqual(restored, oldBody);
  assert.equal(cid(prior.catalog_preimage), prior.catalog_cid);
  assert.equal(cid(prior.journal_preimage), prior.journal_cid);
  assert.notEqual(catalogCid, prior.catalog_cid);
  assert.notEqual(journalCid, prior.journal_cid);
});
