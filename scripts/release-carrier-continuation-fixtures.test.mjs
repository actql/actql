import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {carrierContinuationSuccesses as successes, carrierContinuationRefusals as refusals}
  from './fixtures/carrier-continuation-source-input.mjs';
import {carrierContinuationRecordsRows, carrierContinuationRecordsSchema, selectReleaseCarrierContinuationCases}
  from './release-carrier-continuation-query-cases.mjs';
import {releaseCarrierContinuationFixturePaths} from './release-carrier-continuation-fixtures.mjs';
import {createCarrierContinuationPageDriver, installCarrierContinuationFixture,
  carrierContinuationSchemaWire, carrierContinuationSchemaCid,
  carrierContinuationFactsWire, carrierContinuationFactsCid,
  carrierContinuationViewSpecification}
  from './fixtures/carrier-continuation-installed-source.mjs';
import {createInstalledConnectorTable, installedConnectorForTable,
  loadInstalledConnectorModule} from '../adapters/host-node/installed-connectors.mjs';
import {auditCarrierContinuationTransport} from '../reviews/2026-10-14-carrier-continuation-release-matrix/public-audit.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const observe = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
const request = changes => ({resource: 'r', columns: ['id', 'amount'],
  requestWire: '{}', operation: 'carrier_fixture:r:read', ...changes});

test('normal release keeps all original thirteen cases and fifteen refusals without rewriting them', () => {
  const before = JSON.stringify({successes, refusals}), selected = selectReleaseCarrierContinuationCases();
  assert.equal(selected.successes, successes); assert.equal(selected.refusals, refusals);
  assert.equal(successes.length, 13); assert.equal(refusals.length, 15);
  const rows = [{node_key: 1, occurred_ms: 0}];
  const columns = ['node_key', 'occurred_ms'].map(name => ({name, contract: {type: 'number', nullable: false}}));
  for (const item of successes) {
    assert.deepEqual(item.results, {[item.format === 'json' ? 'answer' : 'main']: {rows, columns}});
    if (item.sourceReadSessionCount === 1) {
      assert.ok(item.text.includes('FROM records WHERE id = 1'));
      assert.deepEqual(item.sourceRows, [{id: 2, amount: 20}, {id: 1, amount: null}, {id: 3, amount: 30}]);
    }
  }
  assert.equal(successes.filter(item => item.sourceReadSessionCount === 1).length, 4);
  assert.equal(JSON.stringify({successes, refusals}), before);
});
test('records schema and complete-extent key facts have independent fixed identities', () => {
  assert.deepEqual(JSON.parse(carrierContinuationSchemaWire), carrierContinuationRecordsSchema);
  assert.equal(hash(carrierContinuationSchemaWire), carrierContinuationSchemaCid);
  assert.equal(hash(carrierContinuationFactsWire), carrierContinuationFactsCid);
  assert.deepEqual(JSON.parse(carrierContinuationFactsWire), {relation_keys: {candidate_keys: [['id']]}});
  assert.deepEqual(carrierContinuationRecordsRows, [{id: 2, amount: 20}, {id: 1, amount: null}, {id: 3, amount: 30}]);
});
test('raw records are charged before consumption and WHERE id=1 is never applied by the supplier', async () => {
  const observed = observe(), calls = [], charge = {};
  await createCarrierContinuationPageDriver(observed)(request({
    authorizationFor(index) {calls.push(['grant', index]);},
    chargePage(bytes) {assert.deepEqual(JSON.parse(bytes), carrierContinuationRecordsRows); calls.push(['charge']); return charge;},
    consumePage(rows, options) {
      assert.equal(options.charge, charge); assert.deepEqual(rows, carrierContinuationRecordsRows);
      assert.deepEqual(rows.map(item => item.id), [2, 1, 3]);
      rows[0].amount = 999; calls.push(['consume']);
    }}));
  assert.deepEqual(calls, [['grant', 0], ['charge'], ['consume']]);
  assert.equal(observed.sourceReadSessions, 1); assert.equal(observed.acceptedPages, 1);
  assert.equal(carrierContinuationRecordsRows[0].amount, 20);
});
test('projection retains raw field order and nullable cells without manufacturing graph rows', async () => {
  await createCarrierContinuationPageDriver(observe())(request({columns: ['amount', 'id'],
    authorizationFor() {}, chargePage: () => ({}), consumePage(rows) {
      assert.deepEqual(Object.keys(rows[0]), ['amount', 'id']);
      assert.equal(rows[1].amount, null); assert.ok(rows.every(row => !Object.hasOwn(row, 'node_key')));
    }}));
  await createCarrierContinuationPageDriver(observe())(request({columns: ['id'],
    authorizationFor() {}, chargePage: () => ({}), consumePage(rows) {
      assert.deepEqual(rows, [{id: 2}, {id: 1}, {id: 3}]);
    }}));
});
test('bad request and cancellation issue no grant; common page refusal remains the original failure', async () => {
  const observed = observe(); let grants = 0;
  const hooks = {authorizationFor() {grants++;}, chargePage() {throw new Error('unexpected charge');}};
  for (const wrong of [{resource: 'foreign'}, {columns: []}, {columns: ['id', 'id']},
    {columns: ['node_key']}, {operation: 'foreign'}, {requestWire: '{"id":1}'}]) {
    await assert.rejects(createCarrierContinuationPageDriver(observed)(request({...hooks, ...wrong})));
  }
  const controller = new AbortController(); controller.abort(new Error('original cancellation'));
  await assert.rejects(createCarrierContinuationPageDriver(observed)(request({...hooks, signal: controller.signal})), /original cancellation/u);
  assert.equal(grants, 0); assert.equal(observed.sourceIo, 0);
  const refusal = new Error('common input admission refusal');
  await assert.rejects(createCarrierContinuationPageDriver(observed)(request({authorizationFor() {},
    chargePage: () => ({}), consumePage() {throw refusal;}})), error => error === refusal);
  assert.equal(observed.sourceIo, 1); assert.equal(observed.acceptedPages, 0);
});
test('ordinary records alias retains declared Source/view/schema identity through profile projection', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-carrier-profile-unit-'));
  const declared = {catalog_cid: 'synthetic-catalog', views: [
    {resource: 'r', source_ref: 'connector://crm/main/r#records', view_cid: 'v-cid'}],
    view_bodies: [JSON.stringify({contract_cid: 'v-cid', output: {schema: {cid: 's-cid'}}})]};
  let restores = 0;
  const moon = {
    clientProgramRowSourceRestoreRelationDeclaration(...args) {
      // The common exported API fixes connector_id before registration.
      // This expectation is independent of the supplier implementation.
      assert.deepEqual(args, ['crm/main', 'carrier_fixture', 'carrier_fixture/0.1',
        JSON.stringify(carrierContinuationViewSpecification),
        restores === 0 ? undefined : declared.catalog_cid]);
      restores++;
      return declared;
    },
    clientProgramRowSourceDeclarationJson: value => JSON.stringify(value),
  };
  const stopAfterDeclaration = new Error('StopBeforeCatalogEnvironmentAdmission');
  try {
    // Declaration projection double only, not Catalog/Common admission.
    // Connector-table/module validation uses the actual existing JS owner.
    const installed = await installCarrierContinuationFixture({directory, moon,
      helpers: {checked: value => value,
        rowSourceCheckEnvironment() {throw stopAfterDeclaration;}}, createInstalledConnectorTable});
    const profile = JSON.parse(await readFile(installed.sourceProfilePath, 'utf8'));
    assert.equal(profile.connectorId, 'crm/main');
    assert.deepEqual(profile.queryAliases, [{name: 'records', sourceRef: declared.views[0].source_ref,
      sourceViewContractCid: 'v-cid', schemaContractCid: 's-cid'}]);
    const entry = installedConnectorForTable(installed.connectorTable, 'source', profile);
    assert.equal(entry.name, 'carrier_fixture');
    assert.equal(entry.registration, 'carrier_fixture');
    const module = await loadInstalledConnectorModule(entry);
    const {queryAliases, ...providerProfile} = profile;
    assert.equal(module.check(providerProfile), providerProfile);
    await assert.rejects(module.load(providerProfile, {moon}),
      error => error === stopAfterDeclaration);
    assert.equal(restores, 2);
    assert.equal(installed.observations.sourceIo, 0);
  } finally {await rm(directory, {recursive: true});}
});
test('carrier normal release delivers its complete nine-module closure and bounded entry syntax', () => {
  const delivered = new Set(releaseCarrierContinuationFixturePaths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-carrier-continuation-worker.mjs')], seen = new Set();
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    assert.ok(delivered.has(path), `missing relative import: ${path}`);
    for (const match of readFileSync(path, 'utf8').matchAll(/(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      pending.push(resolve(dirname(path), match[2]));
    }
  }
  assert.equal(seen.size, 9); assert.equal(delivered.size, 9);
  for (const path of ['scripts/test-package-release-carrier-continuation.mjs',
    'scripts/fixtures/packed-carrier-continuation.mjs',
    'reviews/2026-10-14-carrier-continuation-release-matrix/prepared-checks.mjs',
    'reviews/2026-10-14-carrier-continuation-release-matrix/prepared-release-public.mjs']) {
    const file = resolve(root, path);
    for (const match of readFileSync(file, 'utf8').matchAll(/^import\s+.*?\sfrom\s+(['"])(\.[^'"\r\n]+\.mjs)\1/gmu)) {
      assert.doesNotThrow(() => readFileSync(resolve(dirname(file), match[2])),
        `missing relative import: ${path} -> ${match[2]}`);
    }
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
test('independent carrier audit rejects altered predicate results, schema, scope refusal and acquisition counts', () => {
  const make = () => {
    // Synthetic audit data only, never an actual Run/Result/Source receipt.
    const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
      JSON.stringify(['carrier-continuation', kind, index, item.name,
        createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
    let reads = 0;
    const count = (acceptedRuns, sourceReads) => ({acceptedRuns, sourceReads,
      sourceIo: sourceReads, sourceReadSessions: sourceReads});
    const receipt = {version: 'actql-carrier-continuation-acceptance/0.1', mode: 'local', complete: true,
      cases: successes.map((item, index) => {
        const beforeSubmit = count(index, reads); reads += item.sourceReadSessionCount;
        return {name: item.name, mode: 'local', ref: {synthetic: index}, results: structuredClone(item.results),
          beforeSubmit, beforeRead: count(index + 1, reads), afterReplay: count(index + 1, reads)};
      }), refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: {synthetic: index},
        outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: {synthetic: index}},
        beforeSubmit: count(13, 4), afterRefusal: count(13, 4)}))};
    const report = {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
      actualNormal: 13, actualRefusal: 15, observations: {sourceIo: 4, sourceReads: 4, sourceReadSessions: 4,
        acceptedPages: 4, issuedGrants: 4, closedSites: 1}};
    return {report, receipt};
  };
  const original = make(); assert.equal(auditCarrierContinuationTransport('local', original.report, original.receipt).actualRows, 13);
  for (const change of [r => {r.receipt.cases[9].results.main.rows[0].node_key = 2;},
    r => {r.receipt.cases[0].results.answer.columns.reverse();},
    r => {r.receipt.cases[0].beforeRead.sourceIo++;},
    r => {r.receipt.cases[9].afterReplay.sourceReadSessions++;},
    r => {r.receipt.refusals[0].outcome.problem.code = 'Other';},
    r => {r.report.observations.closedSites = 0;}, r => {r.report.completedInventory.pop();}]) {
    const altered = make(); change(altered);
    assert.throws(() => auditCarrierContinuationTransport('local', altered.report, altered.receipt));
  }
});
