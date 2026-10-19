import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const vector = read('scripts/fixtures/typed-null-array/grammar-identity.json');
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;

test('NULL ARRAY grammar preserves the complete previous manifest preimage', () => {
  const {grammar_manifest_cid: cid, ...body} = vector.before;
  assert.equal(cid, 'sha256:c685e77afee0b8b999999d57368cd8cb5656434f5b1e3baa368826e642813de9');
  assert.equal(`sha256:${sha(canonical(body))}`, cid);
});

test('NULL ARRAY grammar remains the complete predecessor of the CONTAINS connection', () => {
  const contains = read('scripts/fixtures/contains-source/identities.json');
  assert.deepEqual(contains.before, vector.after);
  const {grammar_manifest_cid: priorCid, ...priorBody} = vector.after;
  assert.equal(`sha256:${sha(canonical(priorBody))}`, priorCid);
  const number = read('scripts/fixtures/number-conversion-source/identities.json');
  assert.deepEqual(number.before, contains.after);
  assert.deepEqual(read('spec/manifests/actql-grammar-0.1.json'), number.after);
  const {grammar_manifest_cid: cid, ...body} = number.after;
  assert.equal(`sha256:${sha(canonical(body))}`, cid);
  assert.notEqual(cid, vector.before.grammar_manifest_cid);
  const language = readFileSync('docs/spec/language.md', 'utf8');
  const start = language.indexOf('<a id="expression-text"></a>');
  const end = language.indexOf('<a id="predicates"></a>', start);
  assert.ok(start >= 0 && end > start);
  assert.equal(body.expression_text_rules_sha256, sha(language.slice(start, end)));
  assert.equal(body.query_text_grammar_sha256, sha(readFileSync('spec/grammar/actql-query-0.1.ebnf')));
  assert.equal(body.query_text_rules_sha256, sha(readFileSync('docs/spec/query-text.md')));
  const changed = new Set(['grammar_manifest_cid', 'expression_text_rules_sha256',
    'query_text_grammar_sha256', 'query_text_rules_sha256']);
  for (const key of Object.keys(vector.before)) {
    if (!changed.has(key)) assert.deepEqual(vector.after[key], vector.before[key], key);
  }
});
