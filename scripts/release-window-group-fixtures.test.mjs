import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {releaseWindowGroupFixturePaths, selectReleaseWindowGroupCases}
  from './release-window-group-fixtures.mjs';
import {windowGroupSourceRows, windowGroupSourceSuccesses as successes,
  windowGroupSourceRefusals as refusals} from './fixtures/window-group-source-input.mjs';
import {createWindowGroupRows, createWindowGroupPageDriver, windowGroupSchemaWire,
  windowGroupSchemaCid, windowGroupViewSpecification, windowGroupReadOperations,
  installWindowGroupFixture}
  from './fixtures/window-group-installed-source.mjs';
import {createInstalledConnectorTable, installedConnectorForTable,
  loadInstalledConnectorModule} from '../adapters/host-node/installed-connectors.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {windowGroupSourceSuccesses as originalSuccesses, windowGroupSourceRefusals as originalRefusals}
  from '../reviews/2026-10-15-window-group-acquisition-control/preimages/window-group-source-input.mjs';
import {auditWindowGroupTransport} from '../reviews/2026-10-14-window-group-release-matrix/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('window installation keeps Host registration separate from the logical Source connector', async () => {
  const directory = await mkdtemp(resolve(tmpdir(), 'actql-window-registration-'));
  // Only the declaration is a test double. The connector table and module
  // validation below use the real Host owner, without starting a runtime.
  const declaration = {
    views: [{resource: 'r', source_ref: 'connector://crm/main/r#records',
      view_cid: 'fixture-view-cid'}],
    view_bodies: [JSON.stringify({contract_cid: 'fixture-view-cid',
      output: {schema: {cid: 'fixture-schema-cid'}}})],
  };
  let restoreCalls = 0;
  const moon = {
    clientProgramRowSourceRestoreRelationDeclaration(...args) {
      assert.deepEqual(args, ['crm/main', 'window_fixture', 'window_fixture/0.1',
        JSON.stringify(windowGroupViewSpecification), undefined]);
      restoreCalls++;
      return declaration;
    },
    clientProgramRowSourceDeclarationJson: value => JSON.stringify(value),
  };
  try {
    const installed = await installWindowGroupFixture({moon,
      helpers: {checked: value => value}, createInstalledConnectorTable, directory});
    const profile = JSON.parse(await readFile(installed.sourceProfilePath, 'utf8'));
    assert.equal(profile.connectorId, 'crm/main');
    assert.deepEqual(profile.queryAliases, [{name: 'records',
      sourceRef: 'connector://crm/main/r#records',
      sourceViewContractCid: 'fixture-view-cid', schemaContractCid: 'fixture-schema-cid'}]);
    const entry = installedConnectorForTable(installed.connectorTable, 'source', profile);
    assert.equal(entry.name, 'window_fixture');
    assert.equal(entry.registration, 'window_fixture');
    assert.equal(entry.revision, 'window_fixture/0.1');
    assert.equal(entry.source.profileVersion, 'actql-installed-window-fixture/0.1');
    const module = await loadInstalledConnectorModule(entry);
    const {queryAliases, ...providerProfile} = profile;
    assert.equal(module.check(providerProfile), providerProfile);
    assert.equal(restoreCalls, 1);
    assert.deepEqual(installed.observations, {...observation(), issuedGrants: 0, closedSites: 0});
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('normal window selection retains all original nine normal and nine refusal cases', () => {
  const selected = selectReleaseWindowGroupCases();
  assert.equal(selected.successes, successes);
  assert.equal(selected.refusals, refusals);
  assert.equal(successes.length, 9); assert.equal(refusals.length, 9);
  for (const changed of [successes.slice(1), [...successes, successes[0]], [...successes].reverse()]) {
    assert.throws(() => selectReleaseWindowGroupCases({successes: changed}));
  }
  for (const changed of [refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse()]) {
    assert.throws(() => selectReleaseWindowGroupCases({refusals: changed}));
  }
});
test('JSON window controls retain the adopted exclusive scan/filter/select capture shape', () => {
  const contract = JSON.parse(readFileSync(resolve(root,
    'spec/contracts/actql-query-acquisition.json'), 'utf8'));
  assert.equal(contract.scope, 'exclusive_finite_relation_scan_filter_select');
  assert.equal(successes.length, originalSuccesses.length);
  assert.deepEqual(refusals, originalRefusals);
  for (const [index, current] of successes.entries()) {
    const original = originalSuccesses[index];
    if (current.format !== 'json') {
      assert.deepEqual(current, {...original, results: {main: original.results.answer}});
      continue;
    }
    const {text, ...expectation} = current;
    const {text: previousText, ...originalExpectation} = original;
    assert.deepEqual(expectation, originalExpectation);
    const program = JSON.parse(text), oldProgram = JSON.parse(previousText);
    assert.deepEqual(program.stages[0].steps, [
      {from: 'remote', filter: {literal: true}, as: 'scanned'},
      {from: 'scanned', select: ['amount', 'id'], as: 'captured'},
    ]);
    // Remove only the explicit identity filter to compare every original
    // window, aggregate, projection, Result and limit with the old Program.
    const restored = structuredClone(program);
    restored.stages[0].steps.shift();
    restored.stages[0].steps[0].from = 'remote';
    assert.deepEqual(restored, oldProgram);
  }
});
test('the original nullable schema has no invented key or score facts', () => {
  assert.deepEqual(JSON.parse(windowGroupSchemaWire), {
    amount: {nullable: true, type: 'number'}, id: {nullable: false, type: 'number'}});
  assert.equal(windowGroupSchemaCid, 'sha256:' + hash(windowGroupSchemaWire));
  assert.equal(Object.hasOwn(windowGroupViewSpecification.views[0], 'facts_wire'), false);
});
test('trusted original rows preserve NULL and duplicates while isolating later cases', () => {
  const rows = createWindowGroupRows();
  assert.deepEqual(rows.read(), windowGroupSourceRows);
  const copy = rows.read(); copy[0].id = 99;
  assert.deepEqual(rows.read(), windowGroupSourceRows);
  assert.equal(rows.read().filter(row => row.id === 3).length, 2);
  assert.equal(rows.read()[1].amount, null);
  rows.prepare([]); assert.deepEqual(rows.read(), []);
  rows.prepare(); assert.deepEqual(rows.read(), windowGroupSourceRows);
  assert.throws(() => rows.prepare([{id: 3, amount: 30}]));
});
const observation = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
function request(extra = {}) {
  return {resource: 'r', columns: ['amount', 'id'], requestWire: '{}',
    operation: windowGroupReadOperations.r, ...extra};
}
test('the page driver sends the complete original extent through charge and consumption once', async () => {
  const observations = observation(), rows = createWindowGroupRows();
  let grants = 0, charges = 0, consumed = 0;
  const driver = createWindowGroupPageDriver(observations, rows);
  await driver(request({authorizationFor: async index => {assert.equal(index, 0); grants++;},
    chargePage: bytes => {assert.deepEqual(JSON.parse(bytes), windowGroupSourceRows); charges++; return 17;},
    consumePage: async (actual, {charge}) => {
      assert.equal(charge, 17); assert.deepEqual(actual, windowGroupSourceRows); consumed++;
    }}));
  assert.deepEqual([grants, charges, consumed], [1, 1, 1]);
  assert.deepEqual([observations.sourceIo, observations.sourceReads,
    observations.sourceReadSessions, observations.acceptedPages], [1, 1, 1, 1]);
});
test('cancel and foreign projection refuse before row read or consumption', async () => {
  for (const extra of [{resource: 'foreign'}, {columns: ['id']},
    {requestWire: '{"predicate":true}'}, {signal: AbortSignal.abort(new Error('cancelled'))}]) {
    const observations = observation(); let calls = 0;
    const driver = createWindowGroupPageDriver(observations, createWindowGroupRows());
    await assert.rejects(driver(request({...extra, authorizationFor: async () => {calls++;},
      chargePage: () => {calls++;}, consumePage: async () => {calls++;}})));
    assert.equal(calls, 0); assert.deepEqual(observations, observation());
  }
});
test('empty extent still has one authorized charged page without manufacturing a row', async () => {
  const rows = createWindowGroupRows(); rows.prepare([]);
  const observations = observation(); let grants = 0, charged = 0, consumed = 0;
  await createWindowGroupPageDriver(observations, rows)(request({
    authorizationFor: async () => {grants++;},
    chargePage: bytes => {assert.equal(bytes.toString(), '[]'); charged++; return 1;},
    consumePage: async actual => {assert.deepEqual(actual, []); consumed++;}}));
  assert.deepEqual([grants, charged, consumed, observations.acceptedPages], [1, 1, 1, 1]);
});
function closure(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-window-group-worker.mjs')];
  const seen = new Set(), missing = [];
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    if (!delivered.has(path)) { missing.push(path); continue; }
    for (const match of readFileSync(path, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      pending.push(resolve(dirname(path), match[2]));
    }
  }
  return {seen, missing};
}
test('normal release delivery includes the eight-module import closure and detects omitted supplier', () => {
  const complete = closure(releaseWindowGroupFixturePaths);
  assert.deepEqual(complete.missing, []); assert.equal(complete.seen.size, 8);
  assert.deepEqual(closure(releaseWindowGroupFixturePaths.filter(path =>
    !path.endsWith('window-group-installed-source.mjs'))).missing,
  [resolve(root, 'scripts/fixtures/window-group-installed-source.mjs')]);
});
function auditInput() {
  // Deliberately synthetic audit inputs, never actual public execution evidence.
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['window-group', kind, index, item.name, hash(encodeRetainedFixture(item))])));
  const report = {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
    actualNormal: 9, actualRefusal: 9, observations: {sourceIo: 9, sourceReads: 9,
      sourceReadSessions: 9, acceptedPages: 9, issuedGrants: 9, closedSites: 1}};
  const receipt = {version: 'actql-window-group-acceptance/0.1', mode: 'local', complete: true,
    cases: successes.map((item, index) => ({name: item.name, mode: 'local', ref: {unit_only: index},
      results: structuredClone(item.results),
      beforeSubmit: {acceptedRuns: index, sourceIo: index, sourceReads: index, sourceReadSessions: index},
      beforeRead: {acceptedRuns: index + 1, sourceIo: index + 1, sourceReads: index + 1, sourceReadSessions: index + 1},
      afterReplay: {acceptedRuns: index + 1, sourceIo: index + 1, sourceReads: index + 1, sourceReadSessions: index + 1}})),
    refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: `unit-${index}`,
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: `unit-${index}`},
      beforeSubmit: {acceptedRuns: 9}, afterRefusal: {acceptedRuns: 9}}))};
  return {report, receipt};
}
test('independent audit detects wrong duplicate sum, schema, replay acquisition and omitted inventory', () => {
  const original = auditInput();
  assert.equal(auditWindowGroupTransport('local', original.report, original.receipt).actualRows, 12);
  for (const mutate of [record => record.receipt.cases[0].results.answer.rows[1].total = 30,
    record => record.receipt.cases[0].results.answer.columns.reverse(),
    record => record.receipt.cases[0].afterReplay.sourceReads++,
    record => record.report.completedInventory.pop(),
    record => record.report.observations.closedSites = 0,
    record => record.receipt.refusals[0].afterRefusal.acceptedRuns++]) {
    const changed = auditInput(); mutate(changed);
    assert.throws(() => auditWindowGroupTransport('local', changed.report, changed.receipt));
  }
});
test('prepared worker and normal release commands parse without starting a product', () => {
  for (const path of ['scripts/fixtures/release-window-group-worker.mjs',
    'scripts/fixtures/packed-window-group-source.mjs', 'scripts/test-package-release-window-group.mjs',
    'reviews/2026-10-14-window-group-release-matrix/prepared-release-public.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
