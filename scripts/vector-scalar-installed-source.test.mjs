import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createVectorScalarPageDriver, vectorScalarSchemaCid,
  vectorScalarSchemaWire, vectorScalarViewSpecification}
  from './fixtures/vector-scalar-installed-source.mjs';
import {vectorScalarSourceSchema, vectorScalarSourceRows,
  vectorScalarSourceSuccesses, vectorScalarSourceRefusals}
  from './fixtures/vector-scalar-source-input.mjs';

const observations = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
const options = overrides => ({resource: 'vectors', columns: ['id', 'left_vector', 'right_vector'],
  requestWire: '{}', operation: 'vector_fixture:vectors:read', ...overrides});

test('full Relation declaration retains the independent original Vector schema/CID', () => {
  assert.deepEqual(JSON.parse(vectorScalarSchemaWire), vectorScalarSourceSchema);
  assert.equal('sha256:' + createHash('sha256').update(vectorScalarSchemaWire).digest('hex'), vectorScalarSchemaCid);
  assert.deepEqual(vectorScalarViewSpecification.views[0], {resource: 'vectors', resource_kind: 'table',
    schema_wire: vectorScalarSchemaWire, schema_cid: vectorScalarSchemaCid});
  assert.equal(vectorScalarSourceSuccesses.length, 12);
  assert.equal(vectorScalarSourceRefusals.length, 8);
  assert.equal(vectorScalarSourceSuccesses.filter(item => item.sourceReadSessionCount === 1).length, 8);
  assert.ok(vectorScalarSourceSuccesses.filter(item => item.format === 'json').every(item =>
    item.sourceReadCount === 0 && item.sourceReadSessionCount === 0));
});

test('physical page driver supplies original rows once with the exact charged ticket', async () => {
  const counts = observations(), calls = [];
  const ticket = {};
  await createVectorScalarPageDriver(counts)(options({
    async authorizationFor(index) { calls.push(['authorization', index]); },
    chargePage(bytes) {
      assert.deepEqual(JSON.parse(bytes), vectorScalarSourceRows);
      calls.push(['charged']); return ticket;
    },
    async consumePage(rows, {charge}) {
      assert.equal(charge, ticket); assert.deepEqual(rows, vectorScalarSourceRows);
      calls.push(['admitted']);
      rows[0].left_vector[0] = 999;
    },
  }));
  assert.deepEqual(calls, [['authorization', 0], ['charged'], ['admitted']]);
  assert.equal(vectorScalarSourceRows[0].left_vector[0], 3);
  assert.equal(counts.sourceReads, 1); assert.equal(counts.sourceReadSessions, 1);
  assert.equal(counts.acceptedPages, 1);
});

test('page driver preserves nullable Vector and checked projection without inventing values', async () => {
  await createVectorScalarPageDriver(observations())(options({columns: ['right_vector', 'id'],
    authorizationFor: async () => {}, chargePage: () => ({}),
    consumePage(rows) {
      assert.deepEqual(rows, [{right_vector: [0,0], id: 1}, {right_vector: [0,1], id: 2},
        {right_vector: null, id: 3}]);
      assert.deepEqual(Object.keys(rows[0]), ['right_vector', 'id']);
    },
  }));
});

test('driver refuses undeclared Resource/Request/column before a grant or read', async () => {
  const counts = observations(); let grants = 0;
  const hooks = {authorizationFor() { grants++; }, chargePage() { throw new Error('unexpected charge'); }};
  for (const invalid of [{resource: 'records'}, {columns: ['score']},
    {columns: ['id', 'id']}, {requestWire: '{"id":1}'}]) {
    await assert.rejects(createVectorScalarPageDriver(counts)(options({...hooks, ...invalid})));
  }
  const controller = new AbortController(); controller.abort(new Error('cancelled before read'));
  await assert.rejects(createVectorScalarPageDriver(counts)(options({...hooks,
    signal: controller.signal})), /cancelled before read/u);
  assert.equal(grants, 0); assert.equal(counts.sourceIo, 0);
});

test('common admission refusal is preserved and does not become a completed page', async () => {
  const counts = observations(), refusal = new Error('independent admission control');
  await assert.rejects(createVectorScalarPageDriver(counts)(options({authorizationFor: async () => {},
    chargePage: () => ({}), consumePage() { throw refusal; }})), error => error === refusal);
  assert.equal(counts.sourceIo, 1); assert.equal(counts.acceptedPages, 0);
});

test('actual installed fixture import closure is delivered and detects a missing supplier', () => {
  const copies = new Map([...readFileSync('scripts/test-packed-public-query.mjs', 'utf8')
    .matchAll(/\['([^']+)', '([^']+\.mjs)'\]/gu)].map(match => [match[2], match[1]]));
  function closure(map) {
    const pending = ['packed-query-worker.mjs'], seen = new Set(), absent = [];
    while (pending.length) {
      const name = pending.pop(); if (seen.has(name)) continue; seen.add(name);
      const source = map.get(name); if (!source) { absent.push(name); continue; }
      for (const match of readFileSync(source, 'utf8').matchAll(
        /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
        assert.match(match[2], /^\.\/[^/]+\.mjs$/u);
        pending.push(match[2].slice(2));
      }
    }
    return {seen, absent};
  }
  const actual = closure(copies);
  assert.deepEqual(actual.absent, []);
  for (const name of ['packed-vector-scalar-source.mjs', 'vector-scalar-installed-source.mjs',
    'vector-scalar-source-input.mjs']) assert.ok(actual.seen.has(name));
  const omitted = new Map(copies); omitted.delete('vector-scalar-installed-source.mjs');
  assert.deepEqual(closure(omitted).absent, ['vector-scalar-installed-source.mjs']);
});
