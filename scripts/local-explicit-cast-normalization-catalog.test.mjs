import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Frozen complete preimages authored independently of the Common issuer.
const fixtures = [
  {
    "prefix": "actql-effect-free-local-explicit-cast-completion-free-",
    "catalog_preimage": "{\"applicability\":{\"audit_work_limit\":10000,\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"add\",\"and\",\"cast\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"multiply\",\"neq\",\"not\",\"or\",\"subtract\",\"typed_literal\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"none\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:de7192df9afefaf5006eb57bb62783ae5a7cab8dcb75b5b1cd507799a715efb4"
  },
  {
    "prefix": "actql-effect-free-local-supplied-parameters-explicit-cast-completion-free-",
    "catalog_preimage": "{\"applicability\":{\"audit_work_limit\":10000,\"checked_operations\":[\"derive\",\"filter\",\"select\",\"values\"],\"effect_kind\":\"none\",\"expression_nodes\":[\"$param\",\"add\",\"and\",\"cast\",\"eq\",\"field\",\"gt\",\"gte\",\"literal\",\"lt\",\"lte\",\"multiply\",\"neq\",\"not\",\"or\",\"subtract\",\"typed_literal\"],\"max_source_inputs\":1,\"max_stages\":3,\"parameter_declarations\":\"all-supplied-original-values\",\"proof\":\"original-checked-owner-audit\",\"source_selection\":\"explicit\"},\"profile\":\"actql-effect-free-local-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}",
    "catalog_cid": "sha256:0eebf603b459361c55386c3863c0fc6e3928cdae2def8aeca899272b3ecade47",
    "journal_preimage": "{\"entries\":[],\"rule_catalog_cid\":\"sha256:0eebf603b459361c55386c3863c0fc6e3928cdae2def8aeca899272b3ecade47\",\"version\":\"actql-normalization-journal/0.1\"}",
    "journal_cid": "sha256:3a120cf122225eaf427d4f3223cf0b3019f9d30251524186e56711c0bd0f5ab2"
  }
];
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
for (const {prefix, ...fixture} of fixtures) {
  test(prefix + 'complete identities and closed shape', () => {
    assert.equal(cid(fixture.catalog_preimage), fixture.catalog_cid);
    assert.equal(cid(fixture.journal_preimage), fixture.journal_cid);
    assert.deepEqual(load(prefix + 'fixture.json'), fixture);
    const expected = JSON.parse(fixture.catalog_preimage);
    assert.deepEqual(load(prefix + 'catalog.json'), expected);
    const schema = load(prefix + 'catalog.schema.json');
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
    for (const key of ['applicability', 'profile', 'version']) assert.deepEqual(schema.properties[key], {const: expected[key]});
    assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  });
  test(prefix + 'preserves its entire preceding catalog except explicit cast membership', () => {
    const priorPrefix = prefix.replace('explicit-cast-', '');
    const prior = load(priorPrefix + 'fixture.json');
    const restored = JSON.parse(fixture.catalog_preimage);
    restored.applicability.expression_nodes = restored.applicability.expression_nodes.filter(x => x !== 'cast');
    assert.deepEqual(restored, JSON.parse(prior.catalog_preimage));
    assert.equal(cid(prior.catalog_preimage), prior.catalog_cid);
    assert.equal(cid(prior.journal_preimage), prior.journal_cid);
    assert.notEqual(fixture.catalog_cid, prior.catalog_cid);
    assert.notEqual(fixture.journal_cid, prior.journal_cid);
  });
}
