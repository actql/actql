import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent canonical vectors: no product issuer is invoked to form them.
const catalogPreimage = "{\"applicability\":{\"actual_completions\":\"zero; nonempty-or-unconnected-completion-refuses\",\"audit_work_limit\":10000,\"change_sources\":[\"field\",\"scalar_literal\"],\"compatibility\":\"existing-catalogs-and-saved-original-recipe-bytes-unchanged\",\"computation\":\"existing-common-original-occurrence-normalization-audit; execution-requirements-retained\",\"effect_kind\":\"mapped_update\",\"mapping_conversions\":\"none\",\"parameter_origins\":[\"supplied\",\"default\"],\"proof\":\"same-original-CheckedProgram-complete-requirement-closure-and-static-update-Mapping-owners\",\"scope\":\"fresh-normalization-only; no-operation-support-Model-Effect-approval-resource-or-current-grant\",\"selector_classes\":[\"id\"],\"source_selection\":\"explicit-original-resolver-selection; no-Source-authority\"},\"profile\":\"actql-local-common-update-completion-free/0.1\",\"rules\":[],\"version\":\"actql-normalization-rule-catalog/0.1\"}";
const catalogCid = "sha256:1263116a02d125a0c66f2445a175075d4ec333e56f3d003d35e9d51065fecf8f";
const journalPreimage = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:1263116a02d125a0c66f2445a175075d4ec333e56f3d003d35e9d51065fecf8f\",\"version\":\"actql-normalization-journal/0.1\"}";
const journalCid = "sha256:8b5172ca35db5cd4f35b8e6bbde52243d92b9e9027c2fc4568b8d66a5334ffb1";
const cid = wire => 'sha256:' + createHash('sha256').update(wire, 'utf8').digest('hex');
const load = suffix => JSON.parse(readFileSync(new URL('../spec/contracts/actql-local-common-update-completion-free-' + suffix, import.meta.url), 'utf8'));

test('common update catalogue and journal retain independent canonical identities', () => {
  const expected = JSON.parse(catalogPreimage);
  assert.deepEqual(load('catalog.json'), expected);
  assert.equal(cid(catalogPreimage), catalogCid);
  assert.equal(cid(journalPreimage), journalCid);
  assert.deepEqual(load('fixture.json'), {
    catalog_preimage: catalogPreimage, catalog_cid: catalogCid,
    journal_preimage: journalPreimage, journal_cid: journalCid,
  });
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + catalogCid + '"'));
  assert(issuer.includes('"' + journalCid + '"'));
});

test('common update closed schema preserves zero-completion and separate execution obligations', () => {
  const schema = load('catalog.schema.json'), expected = JSON.parse(catalogPreimage);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(expected).toSorted());
  for (const field of ['applicability', 'profile', 'version']) {
    assert.deepEqual(schema.properties[field], {const: expected[field]});
  }
  assert.deepEqual(schema.properties.rules, {type: 'array', maxItems: 0});
  assert.equal(expected.applicability.actual_completions, 'zero; nonempty-or-unconnected-completion-refuses');
  assert.equal(expected.applicability.mapping_conversions, 'none');
  assert.deepEqual(expected.applicability.selector_classes, ['id']);
});
