import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

// Render independently authored preimages without importing or running tests.
// The owning query tests still construct and compare every corpus body.
const profiles = {
  query_time_acquisition: {
    corpus: 'query-time-acquisition-identities', output: 'query_time_acquisition',
    header: 'Generated from independent same-Run query-time preimages; do not edit.',
    label: 'query-time acquisition',
  },
  acquisition: {
    corpus: 'query-acquisition-identities', output: 'query_acquisition',
    header: 'Generated from the independent query-acquisition fixtures; do not edit.',
    label: 'query acquisition',
  },
  process: {
    corpus: 'query-process-evidence', output: 'query_process_evidence',
    header: 'Generated from independent process-evidence preimages; do not edit.',
    label: 'process evidence',
  },
  two_receipt: {
    corpus: 'query-two-receipt', output: 'query_two_receipt',
    header: 'Generated from independent two-receipt preimages; do not edit.',
    label: 'two receipt',
  },
};

export function generateQueryEvidenceVectors(kind, vectors) {
  const profile = profiles[kind];
  assert.ok(profile, 'unknown query evidence profile');
  const selected = kind === 'two_receipt'
    ? [...vectors.receipts, ...vectors.records, vectors.observation] : vectors;
  assert.ok(Array.isArray(selected) && selected.length > 0);
  const moon = [`// ${profile.header}`, ''];
  for (const [i, vector] of selected.entries()) {
    verifyIdentity(vector.body, vector.cid);
    moon.push('///|', `test "${profile.label} preimage ${i}" {`);
    if (kind === 'process' || kind === 'query_time_acquisition') moon.push(
      '  let input = @json.parse(', `    ${JSON.stringify(canonicalText(vector.body))},`, '  )',
      '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
      '  assert_eq(', '    @canonical_json.cid_value(value, 100000, 10000, 100),',
      `    ${JSON.stringify(vector.cid)},`, '  )');
    else moon.push(
      `  let input = @json.parse(${JSON.stringify(canonicalText(vector.body))})`,
      '  let value = @canonical_json.from_json(input, 10000, 100, 100000)',
      `  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), ${JSON.stringify(vector.cid)})`);
    moon.push('}', '');
  }
  return moon.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  for (const [kind, profile] of Object.entries(profiles)) {
    const vectors = JSON.parse(readFileSync(`portability/corpus/${profile.corpus}.json`, 'utf8'));
    const path = `src/canonical_json/${profile.output}.generated_test.mbt`;
    const expected = generateQueryEvidenceVectors(kind, vectors);
    if (process.argv.includes('--write')) writeFileSync(path, expected);
    else assert.equal(readFileSync(path, 'utf8'), expected, `stale ${profile.label} vectors`);
  }
  console.log('Query evidence vectors match independently authored preimages.');
}
