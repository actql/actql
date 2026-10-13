import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {carrierPeerSuccesses as successes, carrierPeerRefusals as refusals,
  carrierPeerProgramWire, carrierPeerOriginalExpectation}
  from './fixtures/carrier-peer-scope-public-input.mjs';
import {selectReleaseCarrierPeerCases} from './release-carrier-peer-scope-query-cases.mjs';
import {releaseCarrierPeerFixturePaths} from './release-carrier-peer-scope-fixtures.mjs';
import {nearestCarrierSourceRows} from './fixtures/nearest-carrier-source-data.mjs';
import {createNearestCarrierPageDriver, nearestCarrierReadOperations}
  from './fixtures/nearest-carrier-installed-source.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {auditCarrierPeerTransport} from '../reviews/2026-10-14-carrier-peer-scope-release-matrix/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));

test('all original F03 texts retain their exact scope and no easier replacement is selected', () => {
  const core = readFileSync(resolve(root, 'src/query_program/carrier_peer_scope_test.mbt'), 'utf8');
  const literals = [...core.matchAll(/"(?:\\.|[^"\\\n])*"/gu)].map(match => JSON.parse(match[0]));
  const prefix = literals.find(text => text.startsWith('WITH v AS') && text.endsWith(' '));
  const suffix = literals.find(text => text.startsWith(' |> NEAREST candidate_rows'));
  assert.ok(prefix && suffix);
  const actual = selectReleaseCarrierPeerCases();
  assert.equal(actual.successes, successes); assert.equal(actual.refusals, refusals);
  const textCases = successes.filter(item => item.format === 'sql');
  assert.equal(textCases[0].text, prefix + 'FROM v |> vectors()' + suffix);
  assert.equal(textCases[1].text, prefix.replace('candidate_rows AS',
    '`rows` AS (FROM v |> vectors()), candidate_rows AS') + 'FROM rows' + suffix);
  assert.equal(textCases[2].text, prefix + literals.find(text =>
    text.startsWith('FROM (WITH candidate_rows AS (SELECT item_id')));
  assert.equal(textCases[3].text, literals.find(text => text.startsWith('WITH v AS') && text.includes("'same'")));
  assert.equal(textCases[4].text, literals.find(text => text.startsWith('WITH v AS') && text.includes('METRIC cosine K 1')));
  assert.equal(refusals[0].text, prefix + literals.find(text => text.startsWith('FROM (WITH candidate_rows AS (SELECT 1')));
  for (const item of textCases) {
    assert.equal(successes.find(other => other.name === item.name.replace('-sql', '-aql-text')).text, item.text);
  }
  for (const changed of [successes.slice(1), [...successes, successes[0]], [...successes].reverse()]) {
    assert.throws(() => selectReleaseCarrierPeerCases({successes: changed}));
  }
  assert.throws(() => selectReleaseCarrierPeerCases({refusals: refusals.slice(1)}));
});

test('cosine JSON and independent rank/key values keep their original schema and Source obligations', () => {
  assert.equal(carrierPeerProgramWire, readFileSync(resolve(root,
    'reviews/2026-10-12-frontend-carrier-peer-scope/independent.program.json'), 'utf8'));
  assert.deepEqual(successes[0].results.answer.rows, carrierPeerOriginalExpectation.rows);
  assert.equal(JSON.parse(carrierPeerProgramWire).stages[0].steps[4].nearest.metric, 'cosine');
  assert.equal(JSON.parse(carrierPeerProgramWire).stages[0].steps[4].nearest.k, 1);
  assert.deepEqual(successes.map(item => item.sourceReadSessionCount), [0, 2, 2, 2, 2, 2, 2, 1, 1, 2, 2]);
  assert.equal(successes.reduce((n, item) => n + item.results.answer.rows.length, 0), 15);
  const shared = successes.find(item => item.name === 'carrier-peer-shared-query-sql');
  assert.deepEqual(shared.results.answer.rows, [{label: 'same', hit: {
    query_key: {request_id: 'q1'}, candidate_key: {item_id: 'q1'}, score: 1, rank: 1}}]);
  assert.equal(shared.results.answer.columns[0].contract.max_utf8_bytes, 4);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('nested WHERE is residual while the original candidate Source still supplies both raw rows', async () => {
  const observed = {sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
    sourceReadCommands: [], acceptedPages: 0};
  let grants = 0;
  await createNearestCarrierPageDriver(observed)({resource: 'candidates',
    columns: ['label', 'item_id', 'embedding'], requestWire: '{}',
    operation: nearestCarrierReadOperations.candidates,
    authorizationFor() {grants++;}, chargePage(bytes) {
      assert.deepEqual(JSON.parse(bytes).map(row => row.item_id), ['b', 'a']); return 1;
    }, consumePage(rows, {charge}) {
      assert.equal(charge, 1); assert.deepEqual(rows.map(row => row.item_id), ['b', 'a']);
      rows[0].embedding[0] = 99;
    }});
  assert.equal(grants, 1); assert.equal(observed.sourceReads, 1);
  assert.deepEqual(nearestCarrierSourceRows.candidates[0].embedding, [0, 1]);
  assert.ok(successes.find(item => item.name === 'carrier-peer-nested-candidate-sql').text.includes("WHERE item_id = 'a'"));
});

test('normal delivery contains the exact ten-module closure and all four original data files', () => {
  const closure = paths => {
    const delivered = new Set(paths.map(path => resolve(root, path)));
    const pending = [resolve(root, 'scripts/fixtures/release-carrier-peer-scope-worker.mjs')], seen = new Set();
    while (pending.length) {
      const file = pending.pop(); if (seen.has(file)) continue; seen.add(file);
      assert.ok(delivered.has(file), `missing relative import: ${file}`);
      for (const match of readFileSync(file, 'utf8').matchAll(
        /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
        pending.push(resolve(dirname(file), match[2]));
      }
    }
    for (const file of [
      'spec/frontend/fixtures/nearest-keep/common-minimal.program.json',
      'spec/frontend/fixtures/nearest-keep/expected-schema.json',
      'reviews/2026-10-12-frontend-carrier-peer-scope/independent.program.json',
      'reviews/2026-10-12-frontend-carrier-peer-scope/expected.json']) {
      assert.ok(delivered.has(resolve(root, file))); assert.doesNotThrow(() => JSON.parse(readFileSync(resolve(root, file), 'utf8')));
    }
    return seen.size;
  };
  assert.equal(closure(releaseCarrierPeerFixturePaths), 10);
  assert.equal(releaseCarrierPeerFixturePaths.length, 14);
  assert.throws(() => closure(releaseCarrierPeerFixturePaths.filter(path =>
    !path.endsWith('carrier-peer-scope-public-input.mjs'))));
  assert.throws(() => closure(releaseCarrierPeerFixturePaths.filter(path =>
    !path.endsWith('independent.program.json'))));
});

function syntheticAudit() {
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['carrier-peer-scope', kind, index, item.name,
      createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
  let reads = 0;
  const cases = successes.map((item, index) => {
    const beforeSubmit = {acceptedRuns: index, sourceIo: reads, sourceReads: reads, sourceReadSessions: reads};
    reads += item.sourceReadSessionCount;
    const beforeRead = {acceptedRuns: index + 1, sourceIo: reads, sourceReads: reads, sourceReadSessions: reads};
    return {name: item.name, mode: 'local', ref: {synthetic: index},
      results: {answer: {rows: structuredClone(item.results.answer.rows), columns: structuredClone(item.results.answer.columns)}},
      beforeSubmit, beforeRead, afterReplay: {...beforeRead}};
  });
  const counters = {acceptedRuns: 11, sourceIo: 18, sourceReads: 18, sourceReadSessions: 18};
  return {report: {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: [...inventory],
    actualNormal: 11, actualRefusal: 2, observations: {sourceIo: 18, sourceReads: 18, sourceReadSessions: 18,
      acceptedPages: 18, issuedGrants: 18, closedSites: 1}},
  receipt: {version: 'actql-carrier-peer-scope-acceptance/0.1', mode: 'local', complete: true, cases,
    refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: {synthetic: index},
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: {synthetic: index}},
      beforeSubmit: {...counters}, afterRefusal: {...counters}}))}};
}
test('independent audit detects incorrect correspondence, lost shadow, duplicate acquisition and incomplete refusal', () => {
  const original = syntheticAudit(); assert.equal(auditCarrierPeerTransport('local', original.report, original.receipt).actualRows, 15);
  // No original text declares ORDER BY; delivery order is not a new guarantee.
  original.receipt.cases[1].results.answer.rows.reverse();
  assert.doesNotThrow(() => auditCarrierPeerTransport('local', original.report, original.receipt));
  for (const mutate of [r => r.receipt.cases[1].results.answer.rows[0].hit.rank++,
    r => r.receipt.cases[5].results.answer.rows[0].hit.candidate_key.item_id = 'b',
    r => r.receipt.cases[7].beforeRead.sourceReads++,
    r => r.receipt.cases[0].results.answer.columns[0].contract.nullable = true,
    r => r.receipt.cases[0].afterReplay.sourceIo++,
    r => r.receipt.refusals[0].outcome.problem.code = 'WrongCode',
    r => r.report.completedInventory.pop(), r => r.report.observations.closedSites = 0]) {
    const record = syntheticAudit(); mutate(record);
    assert.throws(() => auditCarrierPeerTransport('local', record.report, record.receipt));
  }
});

test('normal consumer and recipes parse with all static imports present, without product execution', () => {
  for (const path of ['scripts/test-package-release-carrier-peer-scope.mjs',
    'scripts/fixtures/packed-carrier-peer-scope.mjs',
    'reviews/2026-10-14-carrier-peer-scope-release-matrix/prepared-checks.mjs',
    'reviews/2026-10-14-carrier-peer-scope-release-matrix/prepared-release-public.mjs']) {
    const file = resolve(root, path);
    for (const match of readFileSync(file, 'utf8').matchAll(
      /^\s*(?:import\b[^;\n]*?\bfrom\s*|from\s*|import\s*)(['"])(\.[^'"\n]+\.mjs)\1/gmu)) {
      assert.doesNotThrow(() => readFileSync(resolve(dirname(file), match[2])));
    }
    execFileSync(process.execPath, ['--check', file], {timeout: 10000});
  }
});
