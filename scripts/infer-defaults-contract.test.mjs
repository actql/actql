import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const vector = JSON.parse(readFileSync(
  new URL('scripts/fixtures/infer-defaults/independent-vector.json', root),
  'utf8',
));

// Independently retained adoption pins. Neither expected identity is read from
// the current generated manifest, compiler output, or a generator implementation.
const BEFORE_CID = 'sha256:20546214b1d002a50ae1ab3bda2d2bb76dacadbdcf79771acd3cf512fa4c504f';
const AFTER_CID = 'sha256:23f43259aa29714c0bc2ecaf0d3a4060826066672f51eb6c0b2aa3678f8dee13';
const SELF_FIELD = 'grammar_manifest_cid';
const MANIFEST_FIELDS = [
  'version',
  'source_grammar_cid',
  'operations',
  'expression_contract_cid',
  'expression_text_grammar_sha256',
  'expression_text_rules_sha256',
  'structural_text_grammar_sha256',
  'structural_text_rules_sha256',
  'query_text_grammar_sha256',
  'query_text_rules_sha256',
  SELF_FIELD,
].sort();

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

// This fixture contains only ASCII strings and arrays/objects. Use direct
// sorted compact JSON and Node crypto, without importing product canonicalizers.
function sortedCompactJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(sortedCompactJson).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(
      key => `${JSON.stringify(key)}:${sortedCompactJson(value[key])}`,
    ).join(',')}}`;
  }
  return JSON.stringify(value);
}

function completeSelfFreePreimage(manifest) {
  assert.deepEqual(Object.keys(manifest).sort(), MANIFEST_FIELDS);
  assert.equal(manifest.version, 'actql-grammar-manifest/0.1');
  assert.ok(Array.isArray(manifest.operations));
  assert.ok(manifest.operations.includes('infer'));
  assert.deepEqual(manifest.operations, [...new Set(manifest.operations)].sort());
  for (const field of MANIFEST_FIELDS) {
    if (field.endsWith('_sha256')) {
      assert.match(manifest[field], /^[0-9a-f]{64}$/);
    } else if (field.endsWith('_cid')) {
      assert.match(manifest[field], /^sha256:[0-9a-f]{64}$/);
    }
  }
  // Remove only the root self field. Every other manifest field participates
  // in the preimage, including the full ordered operation vocabulary.
  const { [SELF_FIELD]: _self, ...body } = manifest;
  assert.equal(Object.hasOwn(body, SELF_FIELD), false);
  assert.equal(Object.keys(body).length, MANIFEST_FIELDS.length - 1);
  const preimage = sortedCompactJson(body);
  assert.match(preimage, /^[\x20-\x7e]*$/);
  return preimage;
}

test('INFER defaults retain independently pinned complete before and after preimages', () => {
  assert.match(vector.parent_source, /^[0-9a-f]{40}$/);
  assert.equal(vector.before[SELF_FIELD], BEFORE_CID);
  assert.equal(vector.after[SELF_FIELD], AFTER_CID);
  assert.equal(`sha256:${sha256(completeSelfFreePreimage(vector.before))}`, BEFORE_CID);
  assert.equal(`sha256:${sha256(completeSelfFreePreimage(vector.after))}`, AFTER_CID);
});

test('INFER defaults change only query grammar, query rules, and the manifest self CID', () => {
  assert.deepEqual(Object.keys(vector.before).sort(), MANIFEST_FIELDS);
  assert.deepEqual(Object.keys(vector.after).sort(), MANIFEST_FIELDS);
  const changed = MANIFEST_FIELDS.filter(
    field => sortedCompactJson(vector.before[field]) !== sortedCompactJson(vector.after[field]),
  );
  assert.deepEqual(changed, [
    SELF_FIELD,
    'query_text_grammar_sha256',
    'query_text_rules_sha256',
  ].sort());
});

test('current normative query bytes and manifest match the independent after vector', () => {
  const grammar = readFileSync(new URL('spec/grammar/actql-query-0.1.ebnf', root));
  const rules = readFileSync(new URL('docs/spec/query-text.md', root));
  assert.equal(sha256(grammar), vector.after.query_text_grammar_sha256);
  assert.equal(sha256(rules), vector.after.query_text_rules_sha256);
  const manifest = JSON.parse(readFileSync(
    new URL('spec/manifests/actql-grammar-0.1.json', root),
    'utf8',
  ));
  assert.deepEqual(manifest, vector.after);
  assert.equal(`sha256:${sha256(completeSelfFreePreimage(manifest))}`, AFTER_CID);
});
