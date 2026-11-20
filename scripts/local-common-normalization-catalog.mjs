import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const stem = 'spec/contracts/actql-effect-free-local-common-normalization-';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');

export function verifyCommonLocalNormalizationCatalog() {
  const catalog = read(stem + 'catalog.json'), schema = read(stem + 'catalog.schema.json');
  const fixture = read(stem + 'fixture.json');
  assert.equal(canonical(catalog), fixture.catalog_preimage);
  assert.equal(hash(fixture.catalog_preimage), fixture.catalog_cid);
  assert.equal(hash(fixture.journal_preimage), fixture.journal_cid);
  assert.deepEqual(JSON.parse(fixture.journal_preimage), {
    version: 'actql-normalization-journal/0.1', rule_catalog_cid: fixture.catalog_cid, entries: [],
  });
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.applicability, {const: catalog.applicability});
  assert.deepEqual(schema.properties.rules, {const: catalog.rules});
  for (const key of ['checked_operations', 'expression_nodes', 'aggregate_functions']) assert(!(key in catalog.applicability));
  const host = readFileSync('src/run_publication_host/client_local_normalization.mbt', 'utf8');
  assert(host.includes(JSON.stringify(fixture.catalog_cid)), 'fresh Host identity differs from its frozen catalogue');
  verifySourceLocalNormalizationCatalog();
  return {catalogCid: fixture.catalog_cid, journalCid: fixture.journal_cid};
}

export function verifySourceLocalNormalizationCatalog() {
  const sourceStem = 'spec/contracts/actql-effect-free-local-source-normalization-';
  const catalog = read(sourceStem + 'catalog.json'), schema = read(sourceStem + 'catalog.schema.json');
  const fixture = read(sourceStem + 'fixture.json'), prior = read(stem + 'catalog.json');
  assert.equal(canonical(catalog), fixture.catalog_preimage);
  assert.equal(hash(fixture.catalog_preimage), fixture.catalog_cid);
  assert.deepEqual(catalog.rules.filter(rule => rule.id !== 'actql.source.sole-view-completion'), prior.rules);
  assert.equal(catalog.rules.filter(rule => rule.id === 'actql.source.sole-view-completion').length, 1);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.applicability, {const: catalog.applicability});
  assert.deepEqual(schema.properties.rules, {const: catalog.rules});
  for (const [preimage, identity, wire] of [
    [fixture.journal_preimage, fixture.journal_cid, fixture.journal_wire],
    [fixture.three_stage_preimage, fixture.three_stage_journal_cid, fixture.three_stage_wire],
  ]) {
    const value = JSON.parse(preimage);
    assert.equal(canonical(value), preimage);
    assert.equal(value.rule_catalog_cid, fixture.catalog_cid);
    assert.equal(value.entries.length, 1);
    assert.match(value.entries[0].path, /^\$\.stages\[0\]\.inputs\["(?:remote|table)"\]\.view$/u);
    assert.equal(value.entries[0].rule, 'actql.source.sole-view-completion');
    assert.equal(hash(preimage), identity);
    assert.equal(canonical({...value, journal_cid: identity}), wire);
  }
  const host = readFileSync('src/run_publication_host/client_local_source_normalization_catalog.mbt', 'utf8');
  assert(host.includes(JSON.stringify(fixture.catalog_cid)), 'Source successor identity differs from its frozen catalogue');
  return {catalogCid: fixture.catalog_cid, journalCid: fixture.journal_cid};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log('Common Local normalization catalogue verified:', verifyCommonLocalNormalizationCatalog());
}
