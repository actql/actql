import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
const readCurrent = path => JSON.parse(readFileSync(path, 'utf8'));
const beforeUnary = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/try-timestamp-unary/predecessor.json.gz')));
const read = path => Object.hasOwn(beforeUnary.bodies, path) ? structuredClone(beforeUnary.bodies[path]) : readCurrent(path);
const prior = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/try-number-identity/predecessor.json.gz')));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

test('Number identity changes only its real expression/scalar laws, retaining old wire bodies and String history', () => {
  assert.equal(prior.source, '7ec053039a457bd23e77de8ba3591615a8bda24c');
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const expression = read(expressionPath), scalar = read(scalarPath);
  assert.equal(cid(prior.bodies[expressionPath]), 'sha256:6ccd3d3e87cf65610f96b81ce3a11844f1d12a6bee3166df66726a3c11e571f8');
  assert.equal(cid(expression), 'sha256:6ab2396dc413fa604854f6586ec957203ccf23392c52f254dfd7b3c0c6dcbe7f');
  assert.equal(cid(scalar), 'sha256:5848944a3c0fcc7e992ff14cffdd84adf4d3c977440c9cf54ab249acfa862fba');
  assert.deepEqual(expression.laws.try_number, scalar.conversion_truth_table.try_number);
  delete expression.laws.try_number;
  for (const name of ['pure_profile_admission', 'profile_binding']) {
    assert.ok(expression.laws[name].startsWith(prior.bodies[expressionPath].laws[name]));
    expression.laws[name] = prior.bodies[expressionPath].laws[name];
  }
  assert.deepEqual(expression, prior.bodies[expressionPath]);
  delete scalar.conversion_truth_table.try_number;
  assert.deepEqual(scalar, prior.bodies[scalarPath]);
  assert.deepEqual(read('spec/contracts/actql-protocol-schemas.json'), prior.bodies['spec/contracts/actql-protocol-schemas.json']);
});

test('intentional Number acceptance preserves the full old Number-negative and every other typing vector', () => {
  const path = 'portability/corpus/actql-expression-typing-v0.1.json';
  const old = prior.bodies[path], next = read(path);
  const negative = {source: 'try_number(n)', issue: 'TypeMismatch'};
  assert.equal(old.negative.filter(entry => entry.source === negative.source).length, 1);
  assert.deepEqual(old.negative.find(entry => entry.source === negative.source), negative);
  assert.deepEqual(next, {...old,
    positive: [...old.positive, {source: 'try_number(n)', type: 'number?'}],
    negative: old.negative.filter(entry => entry.source !== negative.source)});
});

test('identity retains the authored operation, exact original operand and complete independent preimages', () => {
  const vectors = read('scripts/fixtures/try-number-identity/expressions.json');
  assert.equal(vectors.length, 4);
  for (const record of vectors) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(cid(record.value), record.cid);
    assert.deepEqual(Object.keys(record.value), ['try_number']);
    assert.deepEqual(Object.keys(record.value.try_number), ['value']);
  }
});

test('current unary Timestamp extension preserves the complete Number identity law', () => {
  assert.deepEqual(readCurrent('spec/contracts/actql-expressions.json').laws.try_number, beforeUnary.bodies['spec/contracts/actql-expressions.json'].laws.try_number);
  assert.deepEqual(readCurrent('spec/dependencies/aoa-rela-scalar-laws.json').conversion_truth_table.try_number, beforeUnary.bodies['spec/dependencies/aoa-rela-scalar-laws.json'].conversion_truth_table.try_number);
});
