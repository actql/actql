// The explanation fixtures in spec/fixtures/v01-explanation.json declare, per
// case, whether the value is admitted by actql-explanation/0.1. This test
// checks every case against the pinned schema with a small evaluator of the
// JSON Schema subset the explanation schema uses, so the fixture stays an
// executable consumer of the contract instead of prose.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const schemas = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
const schema = schemas.artifact_schemas.explanation;
const fixture = JSON.parse(readFileSync('spec/fixtures/v01-explanation.json', 'utf8'));

function resolveRef(ref) {
  assert.ok(ref.startsWith('#/'), `only local refs are supported: ${ref}`);
  return ref.slice(2).split('/').reduce((node, key) => node[key], schema);
}

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (typeof value === 'number') return Number.isInteger(value) ? 'integer' : 'number';
  return typeof value;
}

function matchesType(value, type) {
  const actual = typeOf(value);
  const types = Array.isArray(type) ? type : [type];
  return types.some(t => t === actual || (t === 'number' && actual === 'integer'));
}

function valid(value, node) {
  if (node === true) return true;
  if (node === false) return false;
  if (node.$ref) return valid(value, resolveRef(node.$ref));
  if (node.type !== undefined && !matchesType(value, node.type)) return false;
  if (node.const !== undefined && JSON.stringify(value) !== JSON.stringify(node.const)) return false;
  if (node.enum && !node.enum.some(v => JSON.stringify(v) === JSON.stringify(value))) return false;
  if (typeof value === 'string') {
    const length = [...value].length;
    if (node.minLength !== undefined && length < node.minLength) return false;
    if (node.maxLength !== undefined && length > node.maxLength) return false;
    if (node.pattern !== undefined && !new RegExp(node.pattern, 'u').test(value)) return false;
  }
  if (typeof value === 'number') {
    if (node.minimum !== undefined && value < node.minimum) return false;
    if (node.maximum !== undefined && value > node.maximum) return false;
  }
  if (Array.isArray(value)) {
    if (node.minItems !== undefined && value.length < node.minItems) return false;
    if (node.maxItems !== undefined && value.length > node.maxItems) return false;
    if (node.items !== undefined && !value.every(item => valid(item, node.items))) return false;
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    for (const key of node.required ?? []) if (!(key in value)) return false;
    const properties = node.properties ?? {};
    for (const [key, item] of Object.entries(value)) {
      if (key in properties) {
        if (!valid(item, properties[key])) return false;
      } else if (node.additionalProperties === false) return false;
      else if (node.additionalProperties && typeof node.additionalProperties === 'object' &&
        !valid(item, node.additionalProperties)) return false;
    }
  }
  if (node.allOf && !node.allOf.every(sub => valid(value, sub))) return false;
  if (node.anyOf && !node.anyOf.some(sub => valid(value, sub))) return false;
  if (node.oneOf && node.oneOf.filter(sub => valid(value, sub)).length !== 1) return false;
  if (node.not && valid(value, node.not)) return false;
  if (node.if) {
    if (valid(value, node.if)) { if (node.then !== undefined && !valid(value, node.then)) return false; }
    else if (node.else !== undefined && !valid(value, node.else)) return false;
  }
  return true;
}

test('the explanation fixture names the pinned contract', () => {
  assert.equal(fixture.contract, 'actql-explanation/0.1');
  assert.ok(fixture.cases.length >= 1);
  assert.equal(new Set(fixture.cases.map(c => c.id)).size, fixture.cases.length, 'case ids are unique');
});

for (const c of fixture.cases) {
  test(`explanation fixture ${c.id} is ${c.valid ? 'admitted' : 'refused'}`, () => {
    assert.equal(valid(c.value, schema), c.valid);
  });
}

test('an explanation with an unknown pushdown decision is refused', () => {
  const base = fixture.cases.find(c => c.id === 'redacted-condition-has-no-text');
  const value = structuredClone(base.value);
  value.pushdown[0].decision = 'deferred';
  assert.equal(valid(value, schema), false);
});

test('an effect without its policy attribute is refused', () => {
  const base = fixture.cases.find(c => c.id === 'static-effect-has-conditional-checkpoint');
  const value = structuredClone(base.value);
  delete value.effects[0].policy;
  assert.equal(valid(value, schema), false);
});

test('explanation string limits count Unicode code points rather than UTF-16 units', () => {
  const value = structuredClone(fixture.cases.find(c => c.id === 'local-site-fixed-engine-deferred').value);
  value.steps[0].step_id = '\u{1f9ed}'.repeat(256);
  assert.equal(valid(value, schema), true);
  value.steps[0].step_id += '\u{1f9ed}';
  assert.equal(valid(value, schema), false);
});
