import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const vector = read('scripts/fixtures/contains-source/identities.json');
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;

test('CONTAINS preserves its complete prior manifest and advances only source rules', () => {
  assert.deepEqual(vector.before, read('scripts/fixtures/typed-null-array/grammar-identity.json').after);
  for (const value of [vector.before, vector.after]) {
    const {grammar_manifest_cid: cid, ...body} = value;
    assert.equal(hash(canonical(body)), cid);
  }
  assert.deepEqual(read('scripts/fixtures/number-conversion-source/identities.json').before, vector.after);
  const restored = {...vector.after,
    grammar_manifest_cid: vector.before.grammar_manifest_cid,
    query_text_rules_sha256: vector.before.query_text_rules_sha256};
  assert.deepEqual(restored, vector.before);
  assert.notEqual(vector.after.grammar_manifest_cid, vector.before.grammar_manifest_cid);
});

test('CONTAINS source and existing checked-machine nodes have independent exact preimages', () => {
  for (const record of vector.expressions) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(hash(record.preimage), record.cid);
  }
  assert.notEqual(vector.expressions[0].cid, vector.expressions[1].cid);
  assert.equal(vector.after.expression_contract_cid, vector.before.expression_contract_cid);
  assert.equal(vector.after.source_grammar_cid, vector.before.source_grammar_cid);
});
