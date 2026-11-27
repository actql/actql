import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {verifyUnaryTimestampContracts, unaryTimestampProfileException} from './try-timestamp-unary-contract.mjs';

const root = new URL('../', import.meta.url);
const read = <Value,>(path: string): Value => JSON.parse(readFileSync(new URL(path, root), 'utf8'));
const fixtureDirectory = new URL('scripts/fixtures/try-timestamp-unary/', root);
const previous: {source: string; bodies: Record<string, unknown>} =
  JSON.parse(gunzipSync(readFileSync(new URL('predecessor.json.gz', fixtureDirectory))).toString('utf8'));
const accepted: {source: string; originalBytes: Record<string, string>} =
  JSON.parse(gunzipSync(readFileSync(new URL('accepted-transition.json.gz', fixtureDirectory))).toString('utf8'));

// Pin the accepted source of the transition independently of later changes to
// the current contracts. Keep the original UTF-8 bytes available without Git.
const transitionPins = {
  'spec/contracts/actql-expressions.json':
    '43a3fd3ae4e53efcf495c8defe36223a283c03d785739efba25eb9e58c078199',
  'spec/contracts/actql-protocol-schemas.json':
    '6b268a83e4203d363a8bf9aee67916b5b487bda10e03c37d334b49f023a8103c',
  'spec/contracts/actql-production-profile-schemas.json':
    '113b71249cc1b878a0593b8adc2d36f0623d339df81420969154cc6f28079e7e',
};
function historicalAccepted<Value>(path: keyof typeof transitionPins): Value {
  assert.equal(previous.source, '8e2effe8c0e99f08a69a7734ed64638a54b42f89');
  assert.equal(accepted.source, '5d8ee527f8cf47330e78424fad8cb449d1c8e588');
  const raw = accepted.originalBytes[path];
  assert.ok(typeof raw === 'string', path);
  assert.equal(createHash('sha256').update(raw).digest('hex'), transitionPins[path], path);
  return JSON.parse(raw);
}
const canonical = (value: unknown): string => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
    canonical((value as Record<string, unknown>)[key])).join(',') + '}';
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

type Schema = {oneOf?: Schema[]; required?: string[]; additionalProperties?: boolean;
  properties?: Record<string, Schema>; const?: unknown};
type HistoricalExpression = {laws: {pure_profile_admission: string; profile_binding: string; try_timestamp_unary?: unknown}};
type Protocol = {artifact_schemas: Record<string, unknown>; artifact_schema_cids: Record<string, string>;
  artifact_registry_cid: string};
type Catalog = {applicability: {expression_nodes: string[]; [name: string]: unknown}};
type CatalogSchema = {properties: {applicability: unknown}};
type IdentityVector = {name: string; body: {try_timestamp: object}; preimage: string; cid: string};

test('independent complete expression preimages keep unary and explicit pattern identities distinct', () => {
  const vectors = read<IdentityVector[]>('scripts/fixtures/try-timestamp-unary/expression-identities.json');
  assert.deepEqual(vectors.map(value => value.name), ['string', 'parameter', 'null', 'explicit-pattern']);
  for (const vector of vectors) {
    assert.equal(canonical(vector.body), vector.preimage);
    assert.equal(cid(vector.body), vector.cid);
  }
  assert.equal(new Set(vectors.map(value => value.cid)).size, 4);
  assert.deepEqual(Object.keys(vectors[3]!.body.try_timestamp).sort(), ['pattern', 'value']);
});
function removeUnary(value: unknown, counts = {source: 0, node: 0}) {
  if (!value || typeof value !== 'object') return counts;
  const schema = value as Schema;
  if (Array.isArray(schema.oneOf)) {
    schema.oneOf = schema.oneOf.filter(choice => {
      const source = choice.properties?.try_timestamp;
      const node = choice.properties?.op?.const === 'try_timestamp' ? choice.properties.body : undefined;
      const body = source ?? node;
      if (body?.required?.join(',') !== 'value') return true;
      assert.equal(body.additionalProperties, false);
      assert.ok(body.properties);
      assert.deepEqual(Object.keys(body.properties), ['value']);
      counts[source ? 'source' : 'node']++;
      return false;
    });
  }
  for (const child of Object.values(value)) removeUnary(child, counts);
  return counts;
}

test('unary conversion adds only its closed schema alternatives and law to the full predecessor', () => {
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const expression = historicalAccepted<HistoricalExpression>(expressionPath);
  const counts = removeUnary(expression);
  delete expression.laws.try_timestamp_unary;
  for (const name of ['pure_profile_admission', 'profile_binding'] as const) {
    assert.equal(expression.laws[name].split(unaryTimestampProfileException).length, 2);
    expression.laws[name] = expression.laws[name].replace(unaryTimestampProfileException, '');
  }
  assert.deepEqual(counts, {source: 3, node: 3});
  assert.deepEqual(expression, previous.bodies[expressionPath]);
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const scalar = read<{conversion_truth_table: Record<string, unknown>}>(scalarPath);
  delete scalar.conversion_truth_table.try_timestamp_unary;
  assert.deepEqual(scalar, previous.bodies[scalarPath]);
  const profilePath = 'spec/contracts/actql-production-profile-schemas.json';
  assert.deepEqual(historicalAccepted(profilePath), previous.bodies[profilePath]);
});

test('only the two actual embedded Program artifact schemas change and all identities close', () => {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const current = historicalAccepted<Protocol>(path), old = previous.bodies[path] as Protocol;
  const changed = Object.keys(current.artifact_schemas).filter(name => canonical(current.artifact_schemas[name]) !== canonical(old.artifact_schemas[name]));
  assert.deepEqual(changed.sort(), ['executable_plan', 'plan_document']);
  assert.deepEqual(removeUnary(current), {source: 4, node: 0});
  current.artifact_schema_cids = structuredClone(old.artifact_schema_cids);
  current.artifact_registry_cid = old.artifact_registry_cid;
  assert.deepEqual(current, old);
  const actual = read<Protocol>(path);
  for (const [name, schema] of Object.entries(actual.artifact_schemas)) assert.equal(actual.artifact_schema_cids[name], cid(schema));
  assert.equal(actual.artifact_registry_cid, cid(actual.artifact_schemas));
  assert.deepEqual(verifyUnaryTimestampContracts(), {source: 7, node: 3});
});

test('new Local capability retains complete Decimal-sum predecessor and original journal laws', () => {
  const stem = 'spec/contracts/actql-effect-free-local-bounded-relation-completion-free-';
  const current = read<Catalog>(stem + 'catalog.json'), old = read<Catalog>(stem + 'pre-unary-timestamp-catalog.json');
  const schema = read<CatalogSchema>(stem + 'catalog.schema.json'), oldSchema = read<CatalogSchema>(stem + 'pre-unary-timestamp-catalog.schema.json');
  type NormalizationIdentity = {catalog_preimage: string; catalog_cid: string; journal_preimage: string; journal_cid: string};
  const fixed = read<Record<'current' | 'previous', NormalizationIdentity>>('scripts/fixtures/try-timestamp-unary/normalization-identities.json');
  for (const [name, body] of [['current', current], ['previous', old]] as const) {
    assert.equal(canonical(body), fixed[name].catalog_preimage);
    assert.equal(cid(body), fixed[name].catalog_cid);
    const journal = JSON.parse(fixed[name].journal_preimage);
    assert.equal(cid(journal), fixed[name].journal_cid);
    assert.equal(journal.rule_catalog_cid, cid(body));
  }
  assert.deepEqual(read(stem + 'fixture.json'), fixed.current);
  assert.deepEqual(read(stem + 'pre-unary-timestamp-fixture.json'), fixed.previous);
  assert.deepEqual(schema.properties.applicability, {const: current.applicability});
  const restored = structuredClone(current);
  restored.applicability.expression_nodes = restored.applicability.expression_nodes.filter(name => name !== 'try_timestamp');
  const added = Object.keys(restored.applicability).filter(name => !(name in old.applicability));
  assert.equal(added.length, 3);
  assert(added.every(name => name.startsWith('unary_timestamp_')));
  for (const name of added) delete restored.applicability[name];
  assert.deepEqual(restored, old);
  schema.properties.applicability = {const: old.applicability};
  assert.deepEqual(schema, oldSchema);
});

test('managed retention changes only the actual fixed-compute fragment dependency', () => {
  const capacityPath = 'spec/contracts/actql-fixed-compute-capacity.json';
  const managedPath = 'spec/contracts/actql-managed-retained-execution.json';
  type Capacity = {dependencies: {fragment: {cid: string}}};
  type Managed = {dependencies: {fixed_compute_capacity: {cid: string}}};
  const capacity = read<Capacity>(capacityPath), oldCapacity = previous.bodies[capacityPath] as Capacity;
  const managed = read<Managed>(managedPath), oldManaged = previous.bodies[managedPath] as Managed;
  const current = read<{schemas: {fragment: unknown}}>('spec/contracts/actql-expressions.json');
  assert.equal(capacity.dependencies.fragment.cid, cid(current.schemas.fragment));
  capacity.dependencies.fragment.cid = oldCapacity.dependencies.fragment.cid;
  assert.deepEqual(capacity, oldCapacity);
  assert.equal(managed.dependencies.fixed_compute_capacity.cid, cid(read(capacityPath)));
  managed.dependencies.fixed_compute_capacity.cid = oldManaged.dependencies.fixed_compute_capacity.cid;
  assert.deepEqual(managed, oldManaged);
});
