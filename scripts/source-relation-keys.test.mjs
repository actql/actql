import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {vectorScalarFactsWire, vectorScalarFactsCid, vectorScalarSchemaWire,
  vectorScalarSchemaCid} from './fixtures/vector-scalar-installed-source.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('adopted Source key component is closed inside extensible original facts', () => {
  const facts = read('spec/contracts/actql-check-environment.json').contract_bodies.carrier_facts;
  assert.equal(facts.additionalProperties, true);
  assert.deepEqual(facts.properties.relation_keys, {
    type: 'object', additionalProperties: false, required: ['candidate_keys'],
    properties: {candidate_keys: {type: 'array', minItems: 1, uniqueItems: true,
      items: {type: 'array', minItems: 1, uniqueItems: true,
        items: {type: 'string', minLength: 1}}}},
  });
  const old = read('reviews/2026-10-13-vector-source-evidence-design/preimages/check-environment-before-relation-keys.json');
  const retained = {...facts.properties}; delete retained.relation_keys;
  assert.deepEqual(retained, old.contract_bodies.carrier_facts.properties);
  assert.equal('sha256:' + digest(canonical(old)),
    'sha256:dc3baf9c4e85a0331b767665f92717a1330aabb357b207ccc7f1cc4ad7300a76');
  assert.equal('sha256:' + digest(canonical(read('spec/contracts/actql-check-environment.json'))),
    'sha256:b513c6a3f6746e20822c51f3fc7dab2327e5ecfe339549b50e98976c11d21804');
});

test('independent declaration preimages retain historical no-key facts', () => {
  const vectors = read('portability/corpus/source-relation-keys.json');
  assert.equal(vectors.cases.length, 8);
  for (const item of vectors.cases) {
    assert.equal(canonical(item.body), item.canonical_preimage);
    assert.equal('sha256:' + digest(item.canonical_preimage), item.bare_body_cid);
  }
  assert.equal(vectors.cases[0].canonical_preimage, '{}');
  assert.equal(vectors.cases[0].bare_body_cid,
    'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a');
  const original = vectors.cases.find(item => item.id === 'declared_original_id');
  assert.equal(original.canonical_preimage, vectorScalarFactsWire);
  assert.equal(original.bare_body_cid, vectorScalarFactsCid);
});

test('trusted Source declaration adds real guarantee without rewriting original oracle or schema', () => {
  assert.equal(digest(readFileSync('scripts/fixtures/vector-scalar-source-input.mjs')),
    '9717e6a803428dadf392562f891687bad8ddbb88691cfbbe6e37137e0fff804f');
  assert.equal('sha256:' + digest(vectorScalarSchemaWire), vectorScalarSchemaCid);
  assert.deepEqual(JSON.parse(vectorScalarFactsWire), {relation_keys: {candidate_keys: [['id']]}});
});
