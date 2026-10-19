import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const bytes = path => readFileSync(path);
const read = path => JSON.parse(bytes(path));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);

test('quantize shorthand retains the complete preceding grammar and every machine field', () => {
  const before = read('scripts/fixtures/quantize-shorthand/predecessor.json');
  const current = read('spec/manifests/actql-grammar-0.1.json');
  for (const value of [before, current]) {
    const {grammar_manifest_cid, ...body} = value;
    assert.equal(grammar_manifest_cid, 'sha256:' + digest(canonical(body)));
  }
  assert.deepEqual({...current, grammar_manifest_cid: before.grammar_manifest_cid,
    expression_text_rules_sha256: before.expression_text_rules_sha256,
    query_text_rules_sha256: before.query_text_rules_sha256}, before);
  assert.notEqual(current.grammar_manifest_cid, before.grammar_manifest_cid);
  const compatibility = read('scripts/fixtures/quantize-shorthand/compatibility.json');
  assert.equal(digest(bytes('spec/contracts/actql-expressions.json')), compatibility.expression_contract_sha256);
  assert.equal(digest(bytes('scripts/fixtures/quantize-source/expressions.json')), compatibility.explicit_preimages_sha256);
  const alternatives = read('spec/contracts/actql-expressions.json').schemas.expression.$defs.expression.oneOf;
  assert.deepEqual(alternatives.find(value => value.properties?.quantize).properties.quantize.required,
    compatibility.structured_quantize_required);
});

test('quantize shorthand independent preimages are complete existing bodies with literal defaults', () => {
  const vectors = read('scripts/fixtures/quantize-shorthand/expressions.json');
  assert.equal(vectors.length, 4);
  for (const record of vectors) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal('sha256:' + digest(record.preimage), record.cid);
    assert.deepEqual(Object.keys(record.value.quantize).sort(), ['precision', 'rounding', 'scale', 'value']);
    assert.equal(record.value.quantize.precision, 38);
    assert.equal(record.value.quantize.rounding, 'half_even');
  }
  assert.equal(vectors[0].value.quantize.scale, 0);
  assert.equal(vectors[2].value.quantize.scale, 38);
});
