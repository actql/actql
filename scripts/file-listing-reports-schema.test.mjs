import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {applyFileListingReportsSchema, fileListingReportsSchema} from './file-listing-reports-schema.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const vectors = read('portability/corpus/file-listing-report-identities.json');

test('listing schema contribution is closed, non-mutating and idempotent across current embeddings', () => {
  const original = read('spec/contracts/actql-protocol-schemas.json');
  const before = canonical(original);
  const next = applyFileListingReportsSchema(original);
  assert.equal(canonical(original), before);
  assert.deepEqual(applyFileListingReportsSchema(next), next);
  assert.deepEqual(next.schemas, original.schemas);
  assert.deepEqual(next.schema_cids, original.schema_cids);
  assert.equal(next.registry_cid, original.registry_cid);
  assert.equal(fileListingReportsSchema.additionalProperties, false);
  assert.deepEqual(fileListingReportsSchema.required, ['row_count', 'rows']);
  const row = fileListingReportsSchema.properties.rows.items;
  assert.equal(row.additionalProperties, false);
  assert.deepEqual(row.required,
    ['row_ordinal', 'resource_ref_cid', 'version', 'reported_media_type', 'media_type']);
  assert.deepEqual(Object.keys(row.properties), row.required);
  assert.equal(Object.hasOwn(row, 'uniqueItems'), false, 'no new duplicate law');
  let count = 0;
  function visit(value) {
    if (value === null || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-source-evidence/0.1') {
      assert.deepEqual(value.properties.file_listing_reports, fileListingReportsSchema);
      assert.equal(value.required.includes('file_listing_reports'), false,
        'only the actual selected listing Owner can require listing correlation');
      count++;
    }
    Object.values(value).forEach(visit);
  }
  visit(next.artifact_schemas);
  assert.ok(count > 1, 'the standalone schema and captured embeddings agree');
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    assert.equal(next.artifact_schema_cids[name], cid(schema));
  }
  assert.equal(next.artifact_registry_cid, cid(next.artifact_schemas));
});

test('independently fixed bodies preserve NULL, exact large version and original/projected Unicode', () => {
  assert.equal(cid(JSON.parse(vectors.input.body)), vectors.input.cid);
  for (const vector of vectors.vectors) {
    const body = JSON.parse(vector.body);
    assert.equal(canonical(body), vector.body);
    assert.equal(cid(body), vector.cid);
    assert.equal(Buffer.byteLength(vector.body), vector.utf8_bytes);
    assert.deepEqual(body.ordering_evidence, {stable: false, keys: []});
    assert.ok(vector.utf8_bytes < 16384, 'the existing writer ceiling is not enlarged');
  }
  const [, empty, nullable, nfd, nfc] = vectors.vectors.map(v => JSON.parse(v.body));
  assert.deepEqual(empty.file_listing_reports, {row_count: 0, rows: []});
  assert.equal(nullable.file_listing_reports.rows[0].reported_media_type, null);
  assert.equal(nullable.file_listing_reports.rows[0].media_type, null);
  for (const body of [nullable, nfd, nfc]) {
    assert.equal(body.file_listing_reports.rows[0].version, '9007199254740993');
    assert.equal(body.file_listing_reports.rows[0].resource_ref_cid, 'sha256:' + 'a'.repeat(64));
  }
  assert.equal(nfd.file_listing_reports.rows[0].reported_media_type, 'Text/Plain;Label="e\u0301"');
  assert.equal(nfd.file_listing_reports.rows[0].media_type, 'text/plain;label="e\u0301"');
  assert.equal(nfc.file_listing_reports.rows[0].reported_media_type, 'Text/Plain;Label="é"');
  assert.notEqual(vectors.vectors[3].cid, vectors.vectors[4].cid);
});

test('report occurrence, Resource, version and nullable presence are identity-bearing', () => {
  const original = JSON.parse(vectors.vectors[3].body);
  const variants = [];
  for (const [name, value] of [['row_ordinal', 1], ['resource_ref_cid', 'sha256:' + 'f'.repeat(64)],
    ['version', '9007199254740994'], ['reported_media_type', null], ['media_type', null]]) {
    const next = structuredClone(original);
    next.file_listing_reports.rows[0][name] = value;
    variants.push(next);
  }
  const missing = structuredClone(original);
  delete missing.file_listing_reports.rows[0].reported_media_type;
  variants.push(missing);
  const repeated = structuredClone(original);
  repeated.file_listing_reports.rows.push({...repeated.file_listing_reports.rows[0], row_ordinal: 1});
  repeated.file_listing_reports.row_count = 2;
  variants.push(repeated);
  for (const next of variants) assert.notEqual(cid(next), vectors.vectors[3].cid);
  // Identity sensitivity is not an Owner admission or authorization test.
});

test('historical listing field set and non-listing bytes remain fixed without report repair', () => {
  const historical = vectors.historical;
  assert.equal(historical.source, 'd71d9c3667bf7cb12a501f491b1f5d418d44746b');
  assert.equal(historical.cid, 'sha256:ed2d9c1f60c98dd19859dec5740562a6f26bb1edec1e614c39c8e76ce4f466b4');
  const old = JSON.parse(historical.body);
  assert.equal(Object.hasOwn(old, 'file_listing_reports'), false);
  assert.equal(cid(old), historical.cid);
  const nonListing = JSON.parse(vectors.vectors[0].body);
  assert.equal(nonListing.source_ref, 'connector://crm/main/r#v');
  assert.equal(Object.hasOwn(nonListing, 'file_listing_reports'), false);
  assert.equal(cid(nonListing), vectors.vectors[0].cid);
  const repaired = {...old, file_listing_reports: {row_count: 0, rows: []}};
  assert.notEqual(cid(repaired), historical.cid, 'no relabeling an old listing as corrected evidence');
});
