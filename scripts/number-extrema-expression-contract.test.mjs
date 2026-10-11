import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {googleScalarLaws} from './google-scalar-expression-contract.mjs';

// Independently authored canonical bodies and Python hashlib SHA-256 vectors.
// These are scalar body preimages; complete Program/Run pins are separate.
const vectors = [
  [
    "{\"body\":[{\"body\":7,\"op\":\"literal\"}],\"op\":\"greatest\"}",
    "sha256:1a53d5e80501f9a4acaf62e230c3b5e7ec4a8872b6dbb03b60ce0cb27e9bd7ad"
  ],
  [
    "{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"greatest\"}",
    "sha256:8516e0004b400a5189e6f42125d7fe69518720fb20f982a54d4d7692cfaa8c3d"
  ],
  [
    "{\"body\":[{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"greatest\"}",
    "sha256:7c9dfd80b386905f5d81102f89296566e598db99d9cc45064c65f7b29e9fd6f6"
  ],
  [
    "{\"body\":[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":3,\"op\":\"literal\"}],\"op\":\"greatest\"}",
    "sha256:57f9509bc2aa141cd5129a870e37554efe62f2e7600be6a84c7bd0d5f36f43d7"
  ],
  [
    "{\"body\":[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"}],\"op\":\"greatest\"}",
    "sha256:97b5ba3b0d95bcc812abcc4efdaf41e0b1f6bba52e0731a694a98e17ecd0ba9e"
  ],
  [
    "{\"body\":[{\"body\":7,\"op\":\"literal\"}],\"op\":\"least\"}",
    "sha256:ebee9bd26bba7bd28acfab41f68d386c7f048239cc0f3a3fac0837e7733a400d"
  ],
  [
    "{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"least\"}",
    "sha256:2599c32896d40d53b18ea885d4a9b45d606483bb238f9fb993a550686f202751"
  ],
  [
    "{\"body\":[{\"body\":3,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"least\"}",
    "sha256:420bb250c22549d5a71b3cf28214ea854db78508d37ec43cd46ad3dfc90941e6"
  ],
  [
    "{\"body\":[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":3,\"op\":\"literal\"}],\"op\":\"least\"}",
    "sha256:467c7e108e039746fe354ee4f06a1ab02237728a052019e271ccdad84b1f14c1"
  ],
  [
    "{\"body\":[{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"}],\"op\":\"least\"}",
    "sha256:2b25be34fcdc7940c7b2e08c8504f91cb103260d14c0f7f17d239617f0bd09ff"
  ]
];

test('number extrema retain distinct ordered singleton repeated and typed-NULL preimages', () => {
  const seen = new Set();
  for (const [canonical, expected] of vectors) {
    assert.equal(machineCid(JSON.parse(canonical)), expected);
    assert.ok(!seen.has(expected));
    seen.add(expected);
  }
  assert.equal(vectors.length, 10);
});

test('number extrema law keeps finite Number demand and existing common owners explicit', () => {
  for (const name of ['greatest', 'least']) {
    const law = googleScalarLaws[name];
    assert.match(law.signature, /^One or more finite binary64 number operands/);
    assert.match(law.signature, /including an all-NULL argument list/);
    assert.match(law.signature, /No implicit conversion, STRING, BOOLEAN/);
    assert.match(law.value, /canonical positive zero/);
    assert.match(law.evaluation, /all later children after NULL/);
    assert.match(law.evaluation, /common expression continuation/);
    assert.match(law.evaluation, /Fold accumulators are not additional semantic expression results/);
    assert.match(law.identity, /argument order, repetitions and singleton node/);
  }
});

const extremaRequirementIds = [
  'scalar-expressions.number-extrema',
  'scalar-expressions.number-extrema-null',
  'scalar-expressions.number-extrema-demand',
  'scalar-expressions.number-extrema-order',
  'scalar-expressions.number-extrema-subset',
  'scalar-expressions.number-extrema-identity',
];

function extremaRequirements(source) {
  const markers = [...source.matchAll(/^<!-- requirement-block: ([^\n]+) -->$/gmu)];
  const index = markers.findIndex(marker => marker[1].split(' ').includes(extremaRequirementIds[0]));
  assert.ok(index >= 0, 'missing extrema requirement block');
  const marker = markers[index];
  assert.deepEqual(marker[1].split(' '), extremaRequirementIds);
  const allIds = markers.flatMap(item => item[1].split(' '));
  for (const id of extremaRequirementIds) assert.equal(allIds.filter(item => item === id).length, 1, id);
  const clauses = normalizedParagraphs(source.slice(marker.index + marker[0].length,
    markers[index + 1]?.index ?? source.length));
  assert.equal(clauses.length, extremaRequirementIds.length, 'extrema marker/obligation count');
  return clauses;
}

test('number extrema expose six uniquely identified normative clauses', () => {
  const clauses = extremaRequirements(readFileSync('docs/spec/language.md', 'utf8'));
  for (const clause of clauses) assert.equal(clause.keyword, 'MUST');
  assert.match(clauses[0].text, /one or more finite binary64 `number` expressions/);
  assert.match(clauses[1].text, /nullable exactly when any operand is nullable/);
  assert.match(clauses[1].text, /all-NULL list.*only after all demanded child evaluations succeed/);
  assert.match(clauses[2].text, /^ActQL's common expression continuation MUST/);
  assert.match(clauses[2].text, /exactly once in authored left-to-right order/);
  assert.match(clauses[2].text, /first child failure.*lazy IF\/CASE\/COALESCE demand/);
  assert.match(clauses[2].text, /entry\/operand\/result charges.*fold accumulators as extra semantic results/);
  assert.match(clauses[3].text, /exact binary64 value with canonical positive zero for either zero sign/);
  assert.match(clauses[3].text, /singleton calls.*without arithmetic overflow or precision reduction/);
  assert.match(clauses[4].text, /MUST reject STRING, BOOLEAN, temporal, decimal, BYTES, non-finite and mixed-type/);
  assert.match(clauses[4].text, /without adding a private STRING comparator or changing shared global comparison or canonical-key ordering/);
  assert.match(clauses[5].text, /ordered nonempty machine `body` array/);
  assert.match(clauses[5].text, /singleton calls.*repetitions.*without sorting, deduplication or constant folding/);
  assert.match(clauses[5].text, /earlier contract bodies or CIDs/);
});

test('number extrema normative audit refuses omitted obligations and duplicate IDs', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const clauses = extremaRequirements(source);
  const markers = [...source.matchAll(/^<!-- requirement-block: ([^\n]+) -->$/gmu)];
  const marker = markers.find(item => item[1].split(' ').includes(extremaRequirementIds[0]));
  const start = marker.index + marker[0].length;
  const next = source.indexOf('<!-- requirement-block:', start);
  const block = source.slice(start, next < 0 ? source.length : next);
  for (let index = 0; index < clauses.length; index++) {
    let occurrence = 0;
    const weakened = block.replace(/\bMUST\b/gu, match => occurrence++ === index ? 'should' : match);
    assert.throws(() => extremaRequirements(source.slice(0, start) + weakened + source.slice(start + block.length)));
  }
  const duplicate = marker[0].replace(extremaRequirementIds[1], extremaRequirementIds[0]);
  assert.throws(() => extremaRequirements(source.replace(marker[0], duplicate)));
});
