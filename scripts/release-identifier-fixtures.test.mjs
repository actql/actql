import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {releaseIdentifierFixturePaths, selectReleaseIdentifierCases}
  from './release-identifier-fixtures.mjs';
import {sourceRows as identifierSourceRows} from './fixtures/public-query-input.mjs';
import {quotedIdentifierSuccesses as successes, quotedIdentifierRefusals as refusals}
  from './fixtures/quoted-identifier-source-input.mjs';
import {createIdentifierRows, createIdentifierPageDriver, identifierSchemaWire,
  identifierSchemaCid, identifierViewSpecification, identifierReadOperations,
  installIdentifierFixture}
  from './fixtures/identifier-installed-source.mjs';
import {createInstalledConnectorTable, installedConnectorForTable,
  loadInstalledConnectorModule} from '../adapters/host-node/installed-connectors.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {auditIdentifierTransport} from '../reviews/2026-10-14-identifier-release-matrix/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('identifier installation keeps Host registration separate from the logical Source connector', async () => {
  const directory = await mkdtemp(resolve(tmpdir(), 'actql-identifier-registration-'));
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
      assert.deepEqual(args, ['crm/main', 'identifier_fixture', 'identifier_fixture/0.1',
        JSON.stringify(identifierViewSpecification), undefined]);
      restoreCalls++;
      return declaration;
    },
    clientProgramRowSourceDeclarationJson: value => JSON.stringify(value),
  };
  try {
    const installed = await installIdentifierFixture({moon,
      helpers: {checked: value => value}, createInstalledConnectorTable, directory});
    const profile = JSON.parse(await readFile(installed.sourceProfilePath, 'utf8'));
    assert.equal(profile.connectorId, 'crm/main');
    assert.deepEqual(profile.queryAliases, [{name: 'records',
      sourceRef: 'connector://crm/main/r#records',
      sourceViewContractCid: 'fixture-view-cid', schemaContractCid: 'fixture-schema-cid'}]);
    const entry = installedConnectorForTable(installed.connectorTable, 'source', profile);
    assert.equal(entry.name, 'identifier_fixture');
    assert.equal(entry.registration, 'identifier_fixture');
    assert.equal(entry.revision, 'identifier_fixture/0.1');
    assert.equal(entry.source.profileVersion, 'actql-installed-identifier-fixture/0.1');
    const module = await loadInstalledConnectorModule(entry);
    const {queryAliases, ...providerProfile} = profile;
    assert.equal(module.check(providerProfile), providerProfile);
    assert.equal(restoreCalls, 1);
    assert.deepEqual(installed.observations, {...observation(), issuedGrants: 0, closedSites: 0});
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('identifier selection retains all original thirty-eight normal and twenty-eight refusal cases', () => {
  const selected = selectReleaseIdentifierCases();
  assert.equal(selected.successes, successes);
  assert.equal(selected.refusals, refusals);
  assert.equal(successes.length, 38); assert.equal(refusals.length, 28);
  for (const changed of [successes.slice(1), [...successes, successes[0]], [...successes].reverse()]) {
    assert.throws(() => selectReleaseIdentifierCases({successes: changed}));
  }
  for (const changed of [refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse()]) {
    assert.throws(() => selectReleaseIdentifierCases({refusals: changed}));
  }
});
test('public identifier fixtures name text main and retain authored JSON answer', () => {
  const json = successes.filter(item => item.format === 'json');
  const text = successes.filter(item => item.format !== 'json');
  assert.equal(json.length, 5); assert.equal(text.length, 33);
  for (const item of json) {
    assert.deepEqual(Object.keys(JSON.parse(item.text).results), ['answer']);
    assert.equal(item.results, undefined);
  }
  for (const item of text) {
    assert.deepEqual(item.results, {main: {rows: item.expected, columns: item.columns}}, item.name);
  }
});
test('the original nullable schema has no invented key or score facts', () => {
  assert.deepEqual(JSON.parse(identifierSchemaWire), {
    amount: {nullable: true, type: 'number'}, id: {nullable: false, type: 'number'}});
  assert.equal(identifierSchemaCid, 'sha256:' + hash(identifierSchemaWire));
  assert.equal(Object.hasOwn(identifierViewSpecification.views[0], 'facts_wire'), false);
});
test('trusted original rows preserve NULL and duplicates while isolating later cases', () => {
  const rows = createIdentifierRows();
  assert.deepEqual(rows.read(), identifierSourceRows);
  const copy = rows.read(); copy[0].id = 99;
  assert.deepEqual(rows.read(), identifierSourceRows);
  assert.equal(rows.read().filter(row => row.id === 3).length, 2);
  assert.equal(rows.read()[1].amount, null);
  rows.prepare([]); assert.deepEqual(rows.read(), []);
  rows.prepare(); assert.deepEqual(rows.read(), identifierSourceRows);
  assert.throws(() => rows.prepare([{id: 3, amount: 30}]));
});
const observation = () => ({sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
  sourceReadCommands: [], acceptedPages: 0});
function request(extra = {}) {
  return {resource: 'r', columns: ['amount', 'id'], requestWire: '{}',
    operation: identifierReadOperations.r, ...extra};
}
test('the page driver sends the complete original extent through charge and consumption once', async () => {
  const observations = observation(), rows = createIdentifierRows();
  let grants = 0, charges = 0, consumed = 0;
  const driver = createIdentifierPageDriver(observations, rows);
  await driver(request({authorizationFor: async index => {assert.equal(index, 0); grants++;},
    chargePage: bytes => {assert.deepEqual(JSON.parse(bytes), identifierSourceRows); charges++; return 17;},
    consumePage: async (actual, {charge}) => {
      assert.equal(charge, 17); assert.deepEqual(actual, identifierSourceRows); consumed++;
    }}));
  assert.deepEqual([grants, charges, consumed], [1, 1, 1]);
  assert.deepEqual([observations.sourceIo, observations.sourceReads,
    observations.sourceReadSessions, observations.acceptedPages], [1, 1, 1, 1]);
});
test('cancel and foreign projection refuse before row read or consumption', async () => {
  for (const extra of [{resource: 'foreign'}, {columns: ['foreign']},
    {requestWire: '{"predicate":true}'}, {signal: AbortSignal.abort(new Error('cancelled'))}]) {
    const observations = observation(); let calls = 0;
    const driver = createIdentifierPageDriver(observations, createIdentifierRows());
    await assert.rejects(driver(request({...extra, authorizationFor: async () => {calls++;},
      chargePage: () => {calls++;}, consumePage: async () => {calls++;}})));
    assert.equal(calls, 0); assert.deepEqual(observations, observation());
  }
});
test('requested id projection preserves all duplicate rows without adding a key or filtering', async () => {
  const observations = observation();
  await createIdentifierPageDriver(observations, createIdentifierRows())(request({columns: ['id'],
    authorizationFor() {}, chargePage(bytes) {
      assert.deepEqual(JSON.parse(bytes), [{id: 3}, {id: 1}, {id: 2}, {id: 3}]);
      return 1;
    }, consumePage(actual, {charge}) {
      assert.deepEqual(actual, [{id: 3}, {id: 1}, {id: 2}, {id: 3}]);
      assert.equal(charge, 1);
    }}));
  assert.equal(observations.sourceReads, 1);
  assert.equal(observations.acceptedPages, 1);
});
test('empty extent still has one authorized charged page without manufacturing a row', async () => {
  const rows = createIdentifierRows(); rows.prepare([]);
  const observations = observation(); let grants = 0, charged = 0, consumed = 0;
  await createIdentifierPageDriver(observations, rows)(request({
    authorizationFor: async () => {grants++;},
    chargePage: bytes => {assert.equal(bytes.toString(), '[]'); charged++; return 1;},
    consumePage: async actual => {assert.deepEqual(actual, []); consumed++;}}));
  assert.deepEqual([grants, charged, consumed, observations.acceptedPages], [1, 1, 1, 1]);
});
function closure(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-identifier-worker.mjs')];
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
  const complete = closure(releaseIdentifierFixturePaths);
  assert.deepEqual(complete.missing, []); assert.equal(complete.seen.size, 8);
  assert.deepEqual(closure(releaseIdentifierFixturePaths.filter(path =>
    !path.endsWith('identifier-installed-source.mjs'))).missing,
  [resolve(root, 'scripts/fixtures/identifier-installed-source.mjs')]);
});
function auditInput() {
  // Deliberately synthetic audit inputs, never actual public execution evidence.
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['identifier', kind, index, item.name, hash(encodeRetainedFixture(item))])));
  const report = {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
    actualNormal: 38, actualRefusal: 28, observations: {sourceIo: 6, sourceReads: 6,
      sourceReadSessions: 6, acceptedPages: 6, issuedGrants: 6, closedSites: 1}};
  const receipt = {version: 'actql-identifier-acceptance/0.1', mode: 'local', complete: true,
    cases: successes.map((item, index) => {
      const previous = successes.slice(0, index).filter(value => value.sourceReadSessionCount === 1).length;
      const acquired = item.sourceReadSessionCount ?? 0;
      const beforeSubmit = {acceptedRuns: index, sourceIo: previous, sourceReads: previous, sourceReadSessions: previous};
      const beforeRead = {acceptedRuns: index + 1, sourceIo: previous + acquired,
        sourceReads: previous + acquired, sourceReadSessions: previous + acquired};
      return {name: item.name, mode: 'local', ref: {unit_only: index},
        results: {[item.format === 'json' ? 'answer' : 'main']: {
          rows: structuredClone(item.expected), columns: structuredClone(item.columns)}},
        beforeSubmit, beforeRead, afterReplay: {...beforeRead}};
    }),
    refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: `unit-${index}`,
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode ?? 'ClientProgramInvalidInput'}, submissionRef: `unit-${index}`},
      beforeSubmit: {acceptedRuns: 38, sourceIo: 6}, afterRefusal: {acceptedRuns: 38, sourceIo: 6}}))};
  return {report, receipt};
}
test('public identifier audit accepts exact result names and rejects historical text or renamed JSON', () => {
  const current = auditInput();
  for (const [index, fixture] of successes.entries()) {
    const name = fixture.format === 'json' ? 'answer' : 'main';
    current.receipt.cases[index].results = {[name]: {
      rows: structuredClone(fixture.expected), columns: structuredClone(fixture.columns)}};
  }
  assert.equal(auditIdentifierTransport('local', current.report, current.receipt).actualRows, 53);
  const historicalText = structuredClone(current);
  historicalText.receipt.cases[1].results = {answer: historicalText.receipt.cases[1].results.main};
  assert.throws(() => auditIdentifierTransport('local', historicalText.report, historicalText.receipt));
  const renamedJson = structuredClone(current);
  renamedJson.receipt.cases[0].results = {main: renamedJson.receipt.cases[0].results.answer};
  assert.throws(() => auditIdentifierTransport('local', renamedJson.report, renamedJson.receipt));
});
test('independent identifier audit detects altered values, schema, refusal, replay and inventory', () => {
  const original = auditInput();
  assert.equal(auditIdentifierTransport('local', original.report, original.receipt).actualRows, 53);
  for (const mutate of [record => record.receipt.cases[0].results.answer.rows[0]['space name'] = 99,
    record => record.receipt.cases[0].results.answer.columns.reverse(),
    record => record.receipt.cases[0].afterReplay.sourceReads++,
    record => record.report.completedInventory.pop(),
    record => record.report.observations.closedSites = 0,
    record => record.receipt.refusals[0].afterRefusal.acceptedRuns++]) {
    const changed = auditInput(); mutate(changed);
    assert.throws(() => auditIdentifierTransport('local', changed.report, changed.receipt));
  }
});
test('prepared worker and normal release commands parse without starting a product', () => {
  for (const path of ['scripts/fixtures/release-identifier-worker.mjs',
    'scripts/fixtures/packed-identifier-source.mjs', 'scripts/test-package-release-identifier.mjs',
    'reviews/2026-10-14-identifier-release-matrix/prepared-release-public.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
    const entry = resolve(root, path);
    // A producer's -e string resolves relative to its declared cwd. It is
    // not a file-relative static import of the recipe module.
    for (const match of readFileSync(entry, 'utf8').matchAll(
      /^\s*(?:import\b[^;\n]*?\bfrom\s*|from\s*|import\s*)(['"])(\.[^'"\n]+\.mjs)\1/gmu)) {
      assert.doesNotThrow(() => readFileSync(resolve(dirname(entry), match[2])));
    }
  }
});
