import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
// Independent ASCII JSON ordering and SHA-256; no product canonicalizer or output.
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const corpus = read('portability/corpus/source-relation-scores.json');

test('score component preserves extensible facts and the exact historical key contract', () => {
  const previous = read('reviews/2026-10-14-source-ranking-scores/preimages/check-environment-before-relation-scores.json');
  assert.equal(cid(canonical(previous)), 'sha256:b513c6a3f6746e20822c51f3fc7dab2327e5ecfe339549b50e98976c11d21804');
  const current = read('spec/contracts/actql-check-environment.json');
  const withoutScores = structuredClone(current);
  delete withoutScores.contract_bodies.carrier_facts.properties.relation_scores;
  assert.deepEqual(withoutScores, previous);
  const facts = current.contract_bodies.carrier_facts;
  assert.equal(facts.additionalProperties, true);
  const score = facts.properties.relation_scores.additionalProperties;
  assert.equal(score.additionalProperties, false);
  assert.deepEqual(score.required, ['domain', 'normalization', 'range']);
  assert.deepEqual(score.properties.higher_is_better, {const: true});
});

test('authored score and empty/key-only preimages retain independent identities', () => {
  assert.equal(corpus.cases.length, 8);
  for (const item of corpus.cases) {
    assert.equal(canonical(item.body), item.canonical_preimage);
    assert.equal(cid(item.canonical_preimage), item.bare_body_cid);
  }
  assert.equal(corpus.cases[0].bare_body_cid, 'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a');
  assert.equal(corpus.cases[1].bare_body_cid, 'sha256:38ffc0cad6baa7699f2ed6b40426b522df5bc7dd9dc369024d278f70a1d29209');
});

test('independent Relevance controls fix values and filtered-out refusal', () => {
  const controls = corpus.controls;
  assert.deepEqual(controls.weighted_sum.rows, [{id: 1, score: 0.25, rank: 1}, {id: 2, score: 0.25, rank: 2}]);
  assert.deepEqual(controls.max.rows, [{id: 1, score: 0.5, rank: 1}, {id: 2, score: 0.5, rank: 2}]);
  assert.equal(controls.filtered_out_invalid.rows[1].s, 2);
  assert.equal(controls.filtered_out_invalid.predicate, 'id = 1');
  assert.equal(controls.filtered_out_invalid.expected, 'InputScore(0, InvalidScore(1))');
  assert.equal(createHash('sha256').update(readFileSync('scripts/fixtures/vector-scalar-source-input.mjs')).digest('hex'),
    '9717e6a803428dadf392562f891687bad8ddbb88691cfbbe6e37137e0fff804f');
});
