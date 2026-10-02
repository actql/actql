import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyIdentity } from './check-canonical-json.mjs';
import { machineCid } from './actql-spec-family.mjs';

const marker = '$actql_value';
const version = 'actql-parameter-values/0.1';
const decimalVersion = 'aoa-decimal-value/0.1';
const fieldPattern = '^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$';
const valueRef = { $ref: '#/$defs/projected_value' };
const tuple = prefixItems => ({ type: 'array', prefixItems, items: false, minItems: prefixItems.length, maxItems: prefixItems.length });
const tagged = (kind, value) => ({ type: 'object', additionalProperties: false, required: [marker], properties: { [marker]: tuple([{ const: kind }, value]) } });

export function identityDefinitions() {
  const decimal = {
    type: 'object', additionalProperties: false,
    required: ['version', 'precision', 'scale', 'coefficient'],
    properties: {
      version: { const: decimalVersion },
      precision: { type: 'integer', minimum: 1, maximum: 38 },
      scale: { type: 'integer', minimum: 0, maximum: 38 },
      coefficient: { type: 'string', pattern: '^(?:0|-?[1-9][0-9]*)(?![\\s\\S])' },
    },
    allOf: Array.from({ length: 38 }, (_, i) => ({
      if: { properties: { precision: { const: i + 1 } }, required: ['precision'] },
      then: { properties: { scale: { maximum: i + 1 }, coefficient: { pattern: `^(?:0|-?[1-9][0-9]{0,${i}})(?![\\s\\S])` } } },
    })),
  };
  const escapedPairs = {
    type: 'array', minItems: 1,
    items: tuple([{ type: 'string', pattern: fieldPattern }, valueRef]),
    contains: tuple([{ const: marker }, valueRef]),
    minContains: 1, maxContains: 1,
    description: 'Pairs have unique names in strictly increasing UTF-16 order and include $actql_value. Values are recursively projected; pair arrays are structural, not projected business arrays.',
  };
  return { projected_value: { oneOf: [
    { type: 'null' }, { type: 'boolean' }, { type: 'number' }, { type: 'string' },
    { type: 'array', items: valueRef },
    { type: 'object', propertyNames: { allOf: [{ pattern: fieldPattern }, { not: { const: marker } }] }, additionalProperties: valueRef },
    tagged('decimal', decimal),
    tagged('duration', { type: 'integer', minimum: 1, maximum: 9007199254740991 }),
    tagged('object', escapedPairs),
  ] } };
}

export function valuesSchema() {
  return { type: 'object', propertyNames: { pattern: '^[A-Za-z_][A-Za-z0-9_]*$' }, additionalProperties: valueRef };
}

export function checkIdentitySchema(registry) {
  const schema = registry.artifact_schemas.parameter_values;
  assert.deepEqual(schema.$defs, identityDefinitions());
  assert.deepEqual(schema.properties.values, valuesSchema());
  assert.equal(registry.artifact_schema_cids.parameter_values, machineCid(schema));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

const normalize = s => { assert.ok(s.isWellFormed()); return s.normalize('NFC').replace(/\r\n?/g, '\n'); };

// Independent small-fixture projection. This is not a Parameter admission engine.
// BigInt checks decimal/duration semantics without invoking product code.
export function project(type, value) {
  if (value === null) return null;
  if (type.type === 'decimal') {
    assert.equal(typeof value, 'string');
    const p = type.precision, s = type.scale;
    assert.ok(Number.isInteger(p) && p >= 1 && p <= 38 && Number.isInteger(s) && s >= 0 && s <= p);
    assert.match(value, new RegExp(`^-?(?:0|[1-9][0-9]*)${s ? `\\.[0-9]{${s}}` : ''}(?![\\s\\S])`));
    const coefficient = BigInt(value.replace('.', '')).toString();
    assert.ok(!(coefficient === '0' && value.startsWith('-')));
    assert.ok(coefficient.replace('-', '').length <= p);
    return { [marker]: ['decimal', { version: decimalVersion, precision: p, scale: s, coefficient }] };
  }
  if (type.type === 'string' && type.format === 'duration') {
    assert.equal(typeof value, 'string');
    const match = /^([0-9]+)(ms|s|m|h|d)(?![\s\S])/i.exec(value);
    assert.ok(match);
    const ms = BigInt(match[1]) * { ms: 1n, s: 1000n, m: 60000n, h: 3600000n, d: 86400000n }[match[2].toLowerCase()];
    assert.ok(ms > 0n && ms <= 9007199254740991n);
    return { [marker]: ['duration', Number(ms)] };
  }
  if (type.type === 'array') return value.map(v => project(type.items, v));
  if (type.type === 'object') {
    const fields = new Map(Object.entries(type.fields).map(([k, v]) => [normalize(k), v]));
    const pairs = Object.entries(value).map(([k, v]) => {
      const name = normalize(k); assert.ok(fields.has(name));
      return [name, project(fields.get(name), v)];
    }).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    assert.equal(new Set(pairs.map(([k]) => k)).size, pairs.length);
    assert.equal(pairs.length, fields.size);
    return pairs.some(([k]) => k === marker) ? { [marker]: ['object', pairs] } : Object.fromEntries(pairs);
  }
  if (typeof value === 'string') assert.ok(value.isWellFormed());
  return value;
}

export function projectedBody(declarations, supplied) {
  const entries = Object.entries(declarations).map(([name, type]) => {
    assert.match(name, /^[A-Za-z_][A-Za-z0-9_]*$/);
    assert.ok(Object.hasOwn(supplied, name) || Object.hasOwn(type, 'default'));
    return [name, project(type, Object.hasOwn(supplied, name) ? supplied[name] : type.default)];
  });
  assert.ok(Object.keys(supplied).every(k => Object.hasOwn(declarations, k)));
  return { version, values: Object.fromEntries(entries) };
}

const literal = s => '"' + [...s].map(c => c.codePointAt(0) < 32 || c.codePointAt(0) > 126 ? `\\u{${c.codePointAt(0).toString(16)}}` : c === '"' || c === '\\' ? '\\' + c : c).join('') + '"';
function budget(value, depth = 0) {
  if (value === null || typeof value !== 'object') return { nodes: 1, depth };
  let nodes = 1, peak = depth + 1;
  for (const child of Object.values(value)) { const b = budget(child, depth + 1); nodes += b.nodes; peak = Math.max(peak, b.depth); }
  return { nodes, depth: peak };
}

export function generateIdentityTests(corpus) {
  assert.equal(corpus.version, 'actql-parameter-identity-vectors/0.1');
  assert.ok(Array.isArray(corpus.cases) && corpus.cases.length > 0);
  const ids = new Set();
  const lines = ['// Generated by scripts/parameter-identity.mjs --write. Do not edit.'];
  for (const c of corpus.cases) {
    assert.ok(typeof c.id === 'string' && c.id.length > 0 && !ids.has(c.id)); ids.add(c.id);
    assert.ok(c.declarations && Object.keys(c.declarations).length > 0 && !Array.isArray(c.declarations));
    assert.ok(c.supplied && !Array.isArray(c.supplied));
    assert.equal(typeof c.expected_canonical_json, 'string');
    const body = projectedBody(c.declarations, c.supplied);
    verifyIdentity(body, c.expected_cid, c.expected_canonical_json);
    const b = budget(body), bytes = Buffer.byteLength(c.expected_canonical_json);
    lines.push('', '///|', `test ${literal('parameter identity: ' + c.id)} {`,
      `  let value = identity_ready(${literal(JSON.stringify(c.declarations))}, ${literal(JSON.stringify(c.supplied))})`,
      `  assert_eq(@parameter_binding.stringify_values(value, ${bytes}, ${b.nodes}, ${b.depth}), ${literal(c.expected_canonical_json)})`,
      `  assert_eq(@parameter_binding.parameter_values_cid(value, ${bytes}, ${b.nodes}, ${b.depth}), ${literal(c.expected_cid)})`,
      `  assert_eq(@parameter_binding.measure_values(value, ${bytes}, ${b.nodes}, ${b.depth}), ${bytes})`,
      ...[[bytes - 1, b.nodes, b.depth], [bytes, b.nodes - 1, b.depth], [bytes, b.nodes, b.depth - 1]].map(([x,y,z]) => `  assert_true(try { ignore(@parameter_binding.parameter_values_cid(value, ${x}, ${y}, ${z})); false } catch { @encode.OutputLimit => true; _ => false })`),
      '}');
  }
  return lines.join('\n') + '\n';
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write-schema')) {
    registry.artifact_schemas.parameter_values.properties.values = valuesSchema();
    registry.artifact_schemas.parameter_values.$defs = identityDefinitions();
    registry.artifact_schema_cids.parameter_values = machineCid(registry.artifact_schemas.parameter_values);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkIdentitySchema(registry);
  if (!process.argv.includes('--write-schema')) {
    const corpus = JSON.parse(readFileSync('portability/corpus/parameter-identities.json', 'utf8'));
    const generated = generateIdentityTests(corpus);
    const target = 'src/parameter_binding/identity.generated_test.mbt';
    if (process.argv.includes('--write')) writeFileSync(target, generated);
    else assert.equal(readFileSync(target, 'utf8'), generated, 'Parameter identity tests are stale');
    console.log(`${corpus.cases.length} fixed Parameter identities verified.`);
  }
}
