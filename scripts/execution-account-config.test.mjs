import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity, canonicalText} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = read('portability/corpus/execution-account-config.json');
const registry = read('spec/contracts/actql-protocol-schemas.json');
const schema = registry.artifact_schemas.execution_account_config;
const dimensions = ['principal', 'connection', 'resource', 'operation'];

const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const keys = (v, required, optional = []) => object(v) &&
  required.every(k => Object.hasOwn(v, k)) &&
  Object.keys(v).every(k => required.includes(k) || optional.includes(k));
const name = v => typeof v === 'string' && v.length > 0;
const ascending = (values, key = v => v) =>
  values.every((v, i) => i === 0 || key(values[i - 1]) < key(v));

// Closed-shape and canonical-spelling oracle written from Run#account-config,
// independent of the registered JSON Schema body and of product code.
function selector(v) {
  if (keys(v, ['all'])) return v.all === true;
  return keys(v, ['any_of']) && Array.isArray(v.any_of) && v.any_of.length > 0 &&
    v.any_of.every(name) && ascending(v.any_of);
}
const tuple = v => keys(v, dimensions) && dimensions.every(d => selector(v[d]));
function entry(v) {
  return keys(v, ['entry_id', 'outcome', ...dimensions, 'exclusions']) && name(v.entry_id) &&
    ['allow', 'deny', 'delegate'].includes(v.outcome) && dimensions.every(d => selector(v[d])) &&
    Array.isArray(v.exclusions) && v.exclusions.every(tuple) &&
    ascending(v.exclusions, canonicalText);
}
export function accepts(v) {
  return keys(v, ['version', 'account_id', 'entries'], ['bootstrap']) &&
    v.version === 'actql-execution-account-config/0.1' && name(v.account_id) &&
    Array.isArray(v.entries) && v.entries.every(entry) && ascending(v.entries, e => e.entry_id) &&
    (v.bootstrap === undefined || (keys(v.bootstrap, ['profile_id', 'profile_version', 'profile_cid']) &&
      name(v.bootstrap.profile_id) && name(v.bootstrap.profile_version) &&
      /^sha256:[0-9a-f]{64}$/.test(v.bootstrap.profile_cid)));
}

// Exact overlap rule from Run#account-config: finite grid per dimension, with one
// fresh identifier standing for every member that no exclusion names.
const FRESH = Symbol('fresh');
const contains = (sel, value) => sel.all === true || (value !== FRESH && sel.any_of.includes(value));
function intersect(a, b) {
  if (a.all && b.all) return {all: true};
  if (a.all) return b;
  if (b.all) return a;
  return {any_of: a.any_of.filter(x => b.any_of.includes(x))};
}
export function conflicts(a, b) {
  if (a.outcome === b.outcome) return false;
  const box = Object.fromEntries(dimensions.map(d => [d, intersect(a[d], b[d])]));
  const exclusions = [...a.exclusions, ...b.exclusions];
  const axes = dimensions.map(d => box[d].all
    ? [...new Set(exclusions.flatMap(e => e[d].any_of ?? [])), FRESH]
    : box[d].any_of);
  const point = [];
  const search = i => {
    if (i === dimensions.length) {
      return !exclusions.some(e => dimensions.every((d, j) => contains(e[d], point[j])));
    }
    for (const value of axes[i]) {
      point[i] = value;
      if (search(i + 1)) return true;
    }
    return false;
  };
  return search(0);
}
const configurationConflicts = c =>
  c.entries.some((a, i) => c.entries.slice(i + 1).some(b => conflicts(a, b)));

function evaluate(c, t) {
  const matches = c.entries.filter(e =>
    dimensions.every(d => contains(e[d], t[d])) &&
    !e.exclusions.some(x => dimensions.every(d => contains(x[d], t[d]))));
  assert.ok(new Set(matches.map(e => e.outcome)).size <= 1, 'admitted configuration has one outcome');
  return matches.length ? {outcome: matches[0].outcome, entry_id: matches[0].entry_id} : {outcome: 'no_match'};
}

test('execution-account configuration schema is registered and pinned by the Run protocol', () => {
  assert.equal(schema.properties.version.const, 'actql-execution-account-config/0.1');
  assert.equal(registry.artifact_schema_cids.execution_account_config, machineCid(schema));
  const run = read('spec/spec-family.json').documents.find(d => d.spec_id === 'actql.protocol.run');
  const ref = run.machine_contracts.find(r => r.pointer === '/artifact_schemas/execution_account_config');
  assert.equal(ref?.cid, machineCid(schema));
  assert.ok(readFileSync(run.path, 'utf8').includes(
    `../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/execution_account_config ${ref.cid}`));
  assert.deepEqual(schema.properties.entries.items, {$ref: '#/$defs/entry'});
  assert.deepEqual(schema.$defs.entry.properties.outcome.enum, ['allow', 'deny', 'delegate']);
  assert.deepEqual(schema.$defs.entry.required, ['entry_id', 'outcome', ...dimensions, 'exclusions']);
  assert.deepEqual(schema.$defs.tuple.required, dimensions);
});

test('fixed configuration identities are independent of member order', () => {
  assert.equal(corpus.version, 'actql-execution-account-config-vectors/0.1');
  const identities = new Set();
  for (const c of corpus.cases) {
    assert.ok(accepts(c.config), c.id);
    verifyIdentity(c.config, c.expected_cid);
    verifyIdentity(Object.fromEntries(Object.entries(c.config).reverse()), c.expected_cid);
    assert.equal(configurationConflicts(c.config), false, c.id);
    identities.add(c.expected_cid);
  }
  assert.equal(identities.size, corpus.cases.length);
});

test('malformed or non-canonical configurations are rejected', () => {
  const base = corpus.cases[0].config;
  for (const r of corpus.rejections) {
    const v = structuredClone(base);
    if (r.remove) delete v[r.remove];
    Object.assign(v, r.changes ?? {});
    if (r.entries) v.entries = r.entries;
    assert.equal(accepts(v), false, r.id);
  }
});

test('overlap conflicts are symbolic tuple-set intersections after exclusions', () => {
  for (const c of corpus.overlap) {
    assert.ok(accepts(c.config), c.id);
    assert.equal(configurationConflicts(c.config) ? 'conflict' : 'valid', c.expected, c.id);
  }
});

test('evaluation distinguishes explicit deny from no-match and includes future members', () => {
  const {config, cases} = corpus.evaluation;
  assert.ok(accepts(config));
  assert.equal(configurationConflicts(config), false);
  for (const c of cases) assert.deepEqual(evaluate(config, c.tuple), c.expected, c.id);
});
