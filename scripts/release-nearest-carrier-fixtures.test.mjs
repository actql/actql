import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {copyFile, mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {nearestCarrierFixtureDirectory, nearestCarrierSourceRows, nearestCarrierSourceSchemas}
  from './fixtures/nearest-carrier-source-data.mjs';
import {nearestCarrierPublicFixtures} from './fixtures/nearest-carrier-public-input.mjs';
import {selectReleaseNearestCarrierCases} from './release-nearest-carrier-query-cases.mjs';
import {releaseNearestCarrierFixturePaths} from './release-nearest-carrier-fixtures.mjs';
import {createNearestCarrierPageDriver, installNearestCarrierFixture,
  nearestCarrierSchemaWires, nearestCarrierSchemaCids, nearestCarrierFactsWires,
  nearestCarrierFactsCids, nearestCarrierReadOperations}
  from './fixtures/nearest-carrier-installed-source.mjs';
import {auditNearestCarrierTransport} from '../reviews/2026-10-14-nearest-carrier-release-matrix/public-audit.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const observations = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
const request = changes => ({resource: 'queries', columns: ['request_id', 'embedding', 'note'],
  requestWire: '{}', operation: nearestCarrierReadOperations.queries, ...changes});

test('NEAREST supplier preserves original rows, checked f32 schema and declared key facts', () => {
  const program = JSON.parse(readFileSync(join(nearestCarrierFixtureDirectory, 'common-minimal.program.json')));
  const values = program.stages[0].steps.filter(step => step.values).map(step => step.values);
  for (const [index, resource] of ['queries', 'candidates'].entries()) {
    assert.deepEqual(nearestCarrierSourceRows[resource], values[index].rows);
    const schema = structuredClone(values[index].schema);
    schema.embedding.element_type = 'f32';
    assert.deepEqual(nearestCarrierSourceSchemas[resource], schema);
    assert.deepEqual(JSON.parse(nearestCarrierSchemaWires[resource]), schema);
    assert.equal(hash(nearestCarrierSchemaWires[resource]), nearestCarrierSchemaCids[resource]);
    assert.equal(hash(nearestCarrierFactsWires[resource]), nearestCarrierFactsCids[resource]);
    assert.deepEqual(JSON.parse(nearestCarrierFactsWires[resource]),
      {relation_keys: {candidate_keys: [[index === 0 ? 'request_id' : 'item_id']]}});
  }
  assert.equal(nearestCarrierSourceRows.queries[0].note, null);
  assert.deepEqual(nearestCarrierSourceRows.candidates.map(item => item.item_id), ['b', 'a']);
});
test('all original ten text cases and five refusals retain roles, KEEP, rows and full schema', async () => {
  const original = await nearestCarrierPublicFixtures(nearestCarrierFixtureDirectory);
  const selected = await selectReleaseNearestCarrierCases(nearestCarrierFixtureDirectory);
  assert.equal(selected.successes.length, 10); assert.equal(selected.refusals.length, 5);
  const expectedRows = JSON.parse(await readFile(join(nearestCarrierFixtureDirectory, 'expected-rows.json')));
  const {columns} = JSON.parse(await readFile(join(nearestCarrierFixtureDirectory, 'expected-schema.json')));
  for (const [index, item] of selected.successes.entries()) {
    const {sourceReadCount, sourceReadSessionCount, ...input} = item;
    assert.deepEqual(input, original.successes[index]);
    assert.equal(sourceReadCount, 2); assert.equal(sourceReadSessionCount, 2);
    assert.deepEqual(item.results.answer, {rows: expectedRows, columns, unordered: false});
    assert.ok(item.text.includes('METRIC dot K 2'));
    assert.ok(item.text.includes('AS neighbor'));
    assert.ok(item.text.includes('ORDER BY neighbor.rank'));
  }
  assert.deepEqual(selected.refusals, original.refusals);
});
test('raw supplier retains requested field order and exact charged page without computing scores', async () => {
  for (const resource of ['queries', 'candidates']) {
    const observed = observations(), calls = [], ticket = {};
    const columns = resource === 'queries' ? ['note', 'embedding', 'request_id'] : ['label', 'embedding', 'item_id'];
    const raw = nearestCarrierSourceRows[resource].map(row => Object.fromEntries(columns.map(name => [name, row[name]])));
    await createNearestCarrierPageDriver(observed)(request({resource, columns,
      operation: nearestCarrierReadOperations[resource],
      authorizationFor(index) {calls.push(['grant', index]);},
      chargePage(bytes) {assert.deepEqual(JSON.parse(bytes), raw); calls.push(['charge']); return ticket;},
      consumePage(rows, {charge}) {
        assert.equal(charge, ticket); assert.deepEqual(rows, raw);
        assert.deepEqual(Object.keys(rows[0]), columns);
        rows[0].embedding[0] = 99; calls.push(['consume']);
      }}));
    assert.deepEqual(calls, [['grant', 0], ['charge'], ['consume']]);
    assert.equal(observed.sourceReadSessions, 1); assert.equal(observed.sourceReads, 1);
    assert.equal(observed.acceptedPages, 1);
    assert.notEqual(nearestCarrierSourceRows[resource][0].embedding[0], 99);
    assert.ok(!Object.hasOwn(nearestCarrierSourceRows[resource][0], 'score'));
  }
});
test('foreign operation, malformed projection, request and pre-read cancellation issue no grant', async () => {
  const observed = observations(); let grants = 0;
  const hooks = {authorizationFor() {grants++;}, chargePage() {throw new Error('unexpected charge');}};
  for (const wrong of [{resource: 'foreign'}, {columns: []}, {columns: ['embedding', 'embedding']},
    {columns: ['score']}, {operation: nearestCarrierReadOperations.candidates}, {requestWire: '{"limit":1}'}]) {
    await assert.rejects(createNearestCarrierPageDriver(observed)(request({...hooks, ...wrong})));
  }
  const controller = new AbortController(); controller.abort(new Error('original cancel'));
  await assert.rejects(createNearestCarrierPageDriver(observed)(request({...hooks, signal: controller.signal})), /original cancel/u);
  assert.equal(grants, 0); assert.equal(observed.sourceIo, 0);
  const refusal = new Error('common typed page refusal');
  await assert.rejects(createNearestCarrierPageDriver(observed)(request({authorizationFor() {},
    chargePage: () => ({}), consumePage() {throw refusal;}})), error => error === refusal);
  assert.equal(observed.sourceIo, 1); assert.equal(observed.acceptedPages, 0);
});
test('query aliases bind exact declared view CIDs even when Catalog view bodies are reversed', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-nearest-profile-unit-'));
  const declared = {catalog_cid: 'synthetic-catalog', views: [
    {resource: 'queries', source_ref: 'connector://nearest_fixture/queries#records', view_cid: 'q-cid'},
    {resource: 'candidates', source_ref: 'connector://nearest_fixture/candidates#records', view_cid: 'c-cid'},
  ], view_bodies: [JSON.stringify({contract_cid: 'c-cid', output: {schema: {cid: 'c-schema'}}}),
    JSON.stringify({contract_cid: 'q-cid', output: {schema: {cid: 'q-schema'}}})]};
  try {
    // Mock projection only: no Catalog/Host/runtime admission is claimed.
    const installed = await installNearestCarrierFixture({directory,
      moon: {clientProgramRowSourceRestoreRelationDeclaration() {return {};},
        clientProgramRowSourceDeclarationJson() {return JSON.stringify(declared);}},
      helpers: {checked: item => item}, createInstalledConnectorTable: rows => rows});
    const profile = JSON.parse(await readFile(installed.sourceProfilePath, 'utf8'));
    assert.deepEqual(profile.queryAliases, [
      {name: 'queries', sourceRef: declared.views[0].source_ref, sourceViewContractCid: 'q-cid', schemaContractCid: 'q-schema'},
      {name: 'candidates', sourceRef: declared.views[1].source_ref, sourceViewContractCid: 'c-cid', schemaContractCid: 'c-schema'}]);
    assert.equal(installed.observations.sourceIo, 0);
  } finally {await rm(directory, {recursive: true});}
});
test('normal release delivery includes eleven modules and all four untouched independent originals', async () => {
  const delivered = new Set(releaseNearestCarrierFixturePaths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-nearest-carrier-worker.mjs')], seen = new Set();
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    assert.ok(delivered.has(path), `missing relative import: ${path}`);
    for (const match of readFileSync(path, 'utf8').matchAll(/(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      pending.push(resolve(dirname(path), match[2]));
    }
  }
  assert.equal(seen.size, 11); assert.equal(delivered.size, 15);
  const directory = await mkdtemp(join(tmpdir(), 'actql-nearest-originals-unit-'));
  try {
    for (const path of releaseNearestCarrierFixturePaths.filter(path => path.startsWith('spec/'))) {
      await copyFile(resolve(root, path), join(directory, path.split('/').at(-1)));
    }
    assert.equal((await nearestCarrierPublicFixtures(directory)).successes.length, 10);
    await rm(join(directory, 'expected-schema.json'));
    await assert.rejects(nearestCarrierPublicFixtures(directory), {code: 'ENOENT'});
  } finally {await rm(directory, {recursive: true});}
});
test('independent audit rejects wrong rank, lost NULL/schema, extra Source reuse and incomplete cleanup', async () => {
  const {successes, refusals} = await selectReleaseNearestCarrierCases(nearestCarrierFixtureDirectory);
  const make = () => {
    const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
      JSON.stringify(['nearest-carrier', kind, index, item.name, createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
    const report = {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
      actualNormal: 10, actualRefusal: 5, observations: {sourceIo: 20, sourceReads: 20, sourceReadSessions: 20,
        acceptedPages: 20, issuedGrants: 20, closedSites: 1}};
    const count = index => ({acceptedRuns: index, sourceIo: index * 2, sourceReads: index * 2, sourceReadSessions: index * 2});
    const receipt = {version: 'actql-nearest-carrier-acceptance/0.1', mode: 'local', complete: true,
      cases: successes.map((item, index) => ({name: item.name, mode: 'local', ref: {synthetic: index},
        results: {answer: {rows: structuredClone(item.results.answer.rows),
          columns: structuredClone(item.results.answer.columns)}},
        beforeSubmit: count(index), beforeRead: count(index + 1), afterReplay: count(index + 1)})),
      refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: {synthetic: index},
        outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: {synthetic: index}},
        beforeSubmit: count(10), afterRefusal: count(10)}))};
    return {report, receipt};
  };
  const original = make(); assert.equal(auditNearestCarrierTransport('local', original.report, original.receipt).actualRows, 20);
  for (const mutate of [r => {r.receipt.cases[0].results.answer.rows.reverse();},
    r => {r.receipt.cases[0].results.answer.rows[0].note = '';},
    r => {r.receipt.cases[0].results.answer.columns.reverse();},
    r => {r.receipt.cases[0].afterReplay.sourceReadSessions++;},
    r => {r.receipt.refusals[0].outcome.problem.code = 'Other';},
    r => {r.report.observations.closedSites = 0;}, r => {r.report.completedInventory.pop();}]) {
    const altered = make(); mutate(altered);
    assert.throws(() => auditNearestCarrierTransport('local', altered.report, altered.receipt));
  }
});
test('normal release consumer and bounded recipes parse without loading the installed product', () => {
  for (const path of ['scripts/test-package-release-nearest-carrier.mjs',
    'scripts/fixtures/packed-nearest-carrier.mjs',
    'reviews/2026-10-14-nearest-carrier-release-matrix/prepared-checks.mjs',
    'reviews/2026-10-14-nearest-carrier-release-matrix/prepared-release-public.mjs']) {
    const file = resolve(root, path);
    for (const match of readFileSync(file, 'utf8').matchAll(/(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      assert.doesNotThrow(() => readFileSync(resolve(dirname(file), match[2])),
        `missing relative import: ${path} -> ${match[2]}`);
    }
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
