import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const count = {type: 'integer', minimum: 0, maximum: 2147483647};
const nullableText = {anyOf: [{type: 'string'}, {type: 'null'}]};
export const fileListingReportsSchema = Object.freeze({
  type: 'object', additionalProperties: false, required: ['row_count', 'rows'],
  properties: {row_count: count, rows: {type: 'array', items: {
    type: 'object', additionalProperties: false,
    required: ['row_ordinal', 'resource_ref_cid', 'version', 'reported_media_type', 'media_type'],
    properties: {row_ordinal: count, resource_ref_cid: cid, version: nullableText,
      reported_media_type: nullableText, media_type: nullableText},
  }}},
});

// Current protocol schema occurrences only. No fixture, stored body, signed
// receipt or historical hash is rewritten. Core/Row Owners separately enforce
// cardinality, ordinal, projection and original capture/custody binding.
export function applyFileListingReportsSchema(original) {
  const next = structuredClone(original);
  let occurrences = 0;
  function visit(value) {
    if (value === null || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-source-evidence/0.1') {
      assert.equal(value.type, 'object');
      assert.equal(value.additionalProperties, false);
      assert.ok(!value.required.includes('file_listing_reports'),
        'The generic schema cannot infer listing kind or rewrite non-listing bodies');
      if (Object.hasOwn(value.properties, 'file_listing_reports')) {
        assert.deepEqual(value.properties.file_listing_reports, fileListingReportsSchema);
      } else value.properties.file_listing_reports = structuredClone(fileListingReportsSchema);
      occurrences++;
    }
    for (const child of Object.values(value)) visit(child);
  }
  visit(next.artifact_schemas);
  assert.ok(occurrences > 0);
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schema_cids[name] = machineCid(schema);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return next;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.ok(process.argv.length === 2 || process.argv.length === 3 && process.argv[2] === '--write');
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const original = JSON.parse(readFileSync(path, 'utf8'));
  const next = applyFileListingReportsSchema(original);
  if (process.argv[2] === '--write') writeFileSync(path, JSON.stringify(next, null, 2) + '\n');
  else assert.deepEqual(original, next, 'Stale file-listing report schema or embedding');
}
