import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

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

test('mapped UPDATE Source catalogue keeps the original sole-view rule and nonempty journal identity', () => {
  const read = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
  const stem = 'actql-local-common-update-source-normalization-';
  const catalog = read(stem + 'catalog.json');
  const schema = read(stem + 'catalog.schema.json');
  const fixture = read(stem + 'fixture.json');
  const sourceRule = read('actql-effect-free-local-source-normalization-catalog.json').rules[0];
  assert.equal(sourceRule.id, 'actql.source.sole-view-completion');
  assert.deepEqual(catalog.rules, [sourceRule]);
  assert.equal(catalog.applicability.audit_work_limit, 10000);
  assert.deepEqual(catalog.applicability.normalization_journal_limits, {max_depth: 8, max_nodes: 32, max_wire_bytes: 1024});
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required.toSorted(), Object.keys(catalog).toSorted());
  for (const [name, value] of Object.entries(catalog)) {
    assert.deepEqual(schema.properties[name], {const: value});
  }
  assert.deepEqual(JSON.parse(fixture.catalog_preimage), catalog);
  assert.equal(cid(fixture.catalog_preimage), fixture.catalog_cid);
  const journal = JSON.parse(fixture.journal_preimage);
  assert.deepEqual(journal, {entries: [{authored: 'null', canonical: 'v',
    path: '$.stages[0].inputs["table"].view', rule: sourceRule.id}],
    rule_catalog_cid: fixture.catalog_cid, version: 'actql-normalization-journal/0.1'});
  assert.equal(cid(fixture.journal_preimage), fixture.journal_cid);
  assert.deepEqual(JSON.parse(fixture.journal_wire), {...journal, journal_cid: fixture.journal_cid});
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + fixture.catalog_cid + '"'));
});

test('mapped file mutation catalogue keeps the original sole-view rule and its own journal identity', () => {
  const read = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
  const file = read('actql-local-common-file-mutation-normalization-catalog.json');
  const update = read('actql-local-common-update-source-normalization-catalog.json');
  assert.deepEqual(file.rules, update.rules);
  assert.equal(file.applicability.effect_kind, 'mapped_update_or_delete; at-least-one-correlated-delete');
  assert.deepEqual(file.applicability.change_sources, ['update:field', 'update:scalar_literal', 'delete:none']);
  assert.deepEqual(file.applicability.normalization_journal_limits, update.applicability.normalization_journal_limits);
  const catalog = 'sha256:285121175723e4625c80ad55a9603140a83035d4ee2d4a38ff3ea581f61f8523';
  assert.equal(machineCid(file), catalog);
  const journal = JSON.stringify({entries: [], rule_catalog_cid: catalog, version: 'actql-normalization-journal/0.1'});
  assert.equal(cid(journal), 'sha256:7093ad10f844e6858a99c0c42325fcf987c80a1469a1b4732a1bf18f73242813');
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + catalog + '"'));
});

test('ordered File mutation catalogue retains its own tuple profile identity', () => {
  const read = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url), 'utf8'));
  const ordered = read('actql-local-common-ordered-file-mutation-normalization-catalog.json');
  const scalar = read('actql-local-common-file-mutation-normalization-catalog.json');
  assert.deepEqual(ordered.rules, scalar.rules);
  assert.deepEqual(ordered.applicability.selector_classes, ['match_tuple', 'key_tuple']);
  assert.equal(ordered.applicability.effect_kind, 'ordered_file_update_delete_or_upsert');
  assert.equal(ordered.applicability.audit_work_limit, scalar.applicability.audit_work_limit);
  assert.deepEqual(ordered.applicability.normalization_journal_limits, scalar.applicability.normalization_journal_limits);
  const expected = 'sha256:c223b3b669fb28ecb9d3e4f38d88642c93293d37623f775cc41aac79f4ba194b';
  assert.equal(machineCid(ordered), expected);
  const issuer = readFileSync(new URL('../src/run_publication_host/client_effect_normalization.mbt', import.meta.url), 'utf8');
  assert(issuer.includes('"' + expected + '"'));
});
