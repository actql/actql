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
  return {catalogCid: fixture.catalog_cid, journalCid: fixture.journal_cid};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log('Common Local normalization catalogue verified:', verifyCommonLocalNormalizationCatalog());
}
