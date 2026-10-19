import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {updateDecimalDivisionContracts} from './decimal-division-exact-contract.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const before = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/decimal-division-exact/predecessor.json.gz')));
const expressionPath = 'spec/contracts/actql-expressions.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
function removeExact(value) {
  if (!value || typeof value !== 'object') return;
  const schema = value.properties?.decimal_divide ??
    (value.properties?.op?.const === 'decimal_divide' ? value.properties?.body : undefined);
  if (schema) {
    assert.deepEqual(schema.required, ['left', 'right', 'precision', 'scale', 'rounding']);
    assert.deepEqual(schema.properties.rounding.enum, ['half_even', 'half_up', 'toward_zero', 'floor', 'ceiling', 'exact']);
    schema.properties.rounding.enum.pop();
  }
  if (value.properties?.quantize) assert.deepEqual(value.properties.quantize.properties.rounding.enum,
    ['half_even', 'half_up', 'toward_zero', 'floor', 'ceiling']);
  for (const child of Object.values(value)) removeExact(child);
}

test('exact division restores the complete original expression/protocol/scalar bodies and five-mode bytes', () => {
  assert.equal(before.source, '2d59f72f7ef3d288415e93db445146b1a2d48847');
  const expression = read(expressionPath), protocol = read(protocolPath), scalar = read(scalarPath);
  assert.ok(updateDecimalDivisionContracts(expression, protocol, scalar).source > 0);
  removeExact(expression); delete expression.laws.decimal_divide;
  assert.deepEqual(expression, before.bodies[expressionPath]);
  removeExact(protocol);
  const changed = Object.keys(protocol.artifact_schemas).filter(key =>
    cid(protocol.artifact_schemas[key]) !== protocol.artifact_schema_cids[key]).sort();
  assert.deepEqual(changed, ['executable_plan', 'plan_document']);
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) protocol.artifact_schema_cids[name] = cid(schema);
  protocol.artifact_registry_cid = cid(protocol.artifact_schemas);
  assert.deepEqual(protocol, before.bodies[protocolPath]);
  delete scalar.decimal.division;
  assert.deepEqual(scalar, before.bodies[scalarPath]);
  for (const record of read('scripts/fixtures/decimal-division-source/expressions.json')) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(cid(record.value), record.cid);
  }
});

test('exact division has independently authored complete preimages and exact-rational vectors', () => {
  const vectors = read('scripts/fixtures/decimal-division-exact/expressions.json');
  for (const entry of vectors) {
    assert.equal(canonical(entry.value), entry.preimage);
    assert.equal(cid(entry.value), entry.cid);
    assert.deepEqual(Object.keys(entry.value.decimal_divide).sort(), ['left', 'precision', 'right', 'rounding', 'scale']);
    assert.equal(entry.value.decimal_divide.precision, 38);
    assert.equal(entry.value.decimal_divide.rounding, 'exact');
  }
  const ratios = read('scripts/fixtures/decimal-division-exact/ratios.json');
  for (const {left, right, scale, coefficient} of ratios) {
    const n = BigInt(left) * 10n ** BigInt(scale), d = BigInt(right);
    const q = d === 0n ? null : n / d;
    const expected = d === 0n || n % d !== 0n || q >= 10n ** 38n || q <= -(10n ** 38n) ? null : String(q);
    assert.equal(coefficient, expected);
  }
});

test('literal NULL exception changes only the two contradicted vectors and explicit new context cases', () => {
  const old = before.bodies['portability/corpus/actql-expression-typing-v0.1.json'];
  const current = read('portability/corpus/actql-expression-typing-v0.1.json');
  const resolved = ["decimal_divide(NULL,n,8,2,'half_even')", "decimal_divide(d,NULL,8,2,'half_even')"];
  assert.deepEqual(old.negative.filter(entry => resolved.includes(entry.source)), resolved.map(source => ({source, issue: 'NullTypeUnresolved'})));
  assert.deepEqual(current, {...old,
    types: {...old.types, decimal38_3: {type:'decimal',nullable:false,precision:38,scale:3},
      'decimal38_3?': {type:'decimal',nullable:true,precision:38,scale:3}},
    positive: [...old.positive, ...resolved.map(source => ({source, type:'decimal8_2?'})),
      {source:'decimal_divide(d,n,3)',type:'decimal38_3'}, {source:'decimal_divide(NULL,NULL,3)',type:'decimal38_3?'}],
    negative: [...old.negative.filter(entry => !resolved.includes(entry.source)),
      {source:'decimal_divide(unknown_division,n,3)',issue:'UnknownField'},
      {source:'decimal_divide(d,$missing_division,3)',issue:'UnknownParameter'},
      {source:'decimal_divide(n,d,3)',issue:'TypeMismatch'},
      {source:"decimal_divide(d,'8',3)",issue:'TypeMismatch'}]});
});
