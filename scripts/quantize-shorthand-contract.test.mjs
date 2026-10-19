import {gunzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const bytes = path => readFileSync(path);
const read = path => JSON.parse(bytes(path));
const divisionPredecessor = JSON.parse(gunzipSync(bytes('scripts/fixtures/decimal-division-exact/predecessor.json.gz')));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);

test('quantize shorthand retains the complete preceding grammar and every machine field', () => {
  const before = read('scripts/fixtures/quantize-shorthand/predecessor.json');
  const current = divisionPredecessor.bodies['spec/manifests/actql-grammar-0.1.json'];
  for (const value of [before, current]) {
    const {grammar_manifest_cid, ...body} = value;
    assert.equal(grammar_manifest_cid, 'sha256:' + digest(canonical(body)));
  }
  assert.deepEqual({...current, grammar_manifest_cid: before.grammar_manifest_cid,
    expression_text_rules_sha256: before.expression_text_rules_sha256,
    query_text_rules_sha256: before.query_text_rules_sha256}, before);
  assert.notEqual(current.grammar_manifest_cid, before.grammar_manifest_cid);
  const compatibility = read('scripts/fixtures/quantize-shorthand/compatibility.json');
  assert.equal(digest(Buffer.from(JSON.stringify(divisionPredecessor.bodies['spec/contracts/actql-expressions.json'], null, 2) + '\n')), compatibility.expression_contract_sha256);
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

test('quantize NULL exception preserves every other original typing vector and environment', () => {
  const before = read('scripts/fixtures/quantize-shorthand/predecessor-typing.json');
  const current = divisionPredecessor.bodies['portability/corpus/actql-expression-typing-v0.1.json'];
  const oldNull = {source: "quantize(NULL,8,2,'half_even')", issue: 'NullTypeUnresolved'};
  assert.deepEqual(before.negative.filter(value => value.source === oldNull.source), [oldNull]);
  assert.deepEqual(current, {...before,
    types: {...before.types, 'decimal38_2?': {type: 'decimal', nullable: true, precision: 38, scale: 2}},
    positive: [...before.positive, {source: oldNull.source, type: 'decimal8_2?'},
      {source: 'quantize(NULL,2)', type: 'decimal38_2?'}],
    negative: [...before.negative.filter(value => value.source !== oldNull.source),
      {source: 'quantize(unknown_quantize_value,2)', issue: 'UnknownField'},
      {source: 'quantize($missing_quantize,2)', issue: 'UnknownParameter'}]});
  assert.ok(current.negative.some(value => value.source === "decimal_divide(NULL,n,8,2,'half_even')" &&
    value.issue === 'NullTypeUnresolved'));
});
