import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {nearestRequiredSuccesses as successes, nearestRequiredRefusals as refusals,
  createNearestRequiredRows} from './fixtures/nearest-required-public-input.mjs';
import {nearestCarrierSourceRows} from './fixtures/nearest-carrier-source-data.mjs';
import {createNearestCarrierPageDriver, nearestCarrierReadOperations}
  from './fixtures/nearest-carrier-installed-source.mjs';
import {selectReleaseNearestRequiredCases} from './release-nearest-required-query-cases.mjs';
import {releaseNearestRequiredFixturePaths} from './release-nearest-required-fixtures.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {auditNearestRequiredTransport} from '../reviews/2026-10-14-nearest-required-release-matrix/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));

test('F04 required variants have independent whole Programs and the original limits', () => {
  assert.deepEqual(selectReleaseNearestRequiredCases(), {successes, refusals});
  assert.equal(successes.length, 9); assert.equal(refusals.length, 10);
  const tie = successes[0], empty = successes[3], shared = successes[6];
  const program = JSON.parse(tie.text);
  assert.deepEqual(program.stages[0].steps[1].values.rows.map(row => row.item_id), ['z', 'b', 'a']);
  assert.equal(program.stages[0].steps[2].nearest.k, 2);
  assert.deepEqual(tie.results.answer.rows.map(row => [row.neighbor.candidate_key.item_id,
    row.neighbor.score, row.neighbor.rank]), [['a', 1, 1], ['b', 1, 2]]);
  assert.deepEqual(JSON.parse(empty.text).stages[0].steps[0].values.rows, []);
  assert.deepEqual(empty.results.answer.rows, []);
  assert.deepEqual(empty.results.answer.columns, tie.results.answer.columns);
  const sharedProgram = JSON.parse(shared.text);
  assert.equal(sharedProgram.stages[0].steps.filter(step => step.values).length, 1);
  const nearest = sharedProgram.stages[0].steps[1];
  assert.equal(nearest.from, 'queries'); assert.equal(nearest.nearest.queries, 'queries');
  assert.deepEqual(shared.results.answer.rows, [{neighbor: {query_key: {request_id: 'q1'},
    candidate_key: {request_id: 'q1'}, score: 1, rank: 1}, rank: 1}]);
  assert.deepEqual(successes.map(item => item.sourceReadSessionCount), [0, 2, 2, 0, 2, 2, 0, 1, 1]);
  assert.equal(successes.reduce((n, item) => n + item.results.answer.rows.length, 0), 9);
  for (const name of ['ties', 'empty', 'shared-producer']) {
    const pair = successes.filter(item => item.name.startsWith(`nearest-required-${name}-`) && item.format !== 'json');
    assert.equal(pair[0].text, pair[1].text);
    assert.ok(pair[0].text.includes('ORDER BY'));
    assert.deepEqual(pair[0].results, pair[1].results);
  }
});

test('the trusted row controller changes only declared raw data and retains the old default', async () => {
  const controller = createNearestRequiredRows();
  assert.deepEqual(controller.read('queries'), nearestCarrierSourceRows.queries);
  assert.deepEqual(controller.read('candidates'), nearestCarrierSourceRows.candidates);
  const tie = successes[1]; controller.prepare(tie.sourceRows);
  assert.deepEqual(controller.read('candidates').map(row => row.item_id), ['z', 'b', 'a']);
  const copy = controller.read('candidates'); copy[0].embedding[0] = 99;
  assert.deepEqual(controller.read('candidates')[0].embedding, [1, 0]);
  const observed = {sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
    sourceReadCommands: [], acceptedPages: 0};
  await createNearestCarrierPageDriver(observed, resource => controller.read(resource))({resource: 'candidates',
    columns: ['item_id', 'embedding', 'label'], requestWire: '{}', operation: nearestCarrierReadOperations.candidates,
    authorizationFor() {}, chargePage(bytes) {
      assert.deepEqual(JSON.parse(bytes).map(row => row.item_id), ['z', 'b', 'a']); return 1;
    }, consumePage(rows, {charge}) {assert.equal(charge, 1); assert.equal(rows.length, 3);}});
  controller.prepare(successes[4].sourceRows); assert.deepEqual(controller.read('queries'), []);
  controller.prepare(); assert.deepEqual(controller.read('candidates'), nearestCarrierSourceRows.candidates);
  assert.throws(() => controller.prepare({queries: [{request_id: 'foreign'}], candidates: []}));
  assert.throws(() => controller.read('foreign'));
  assert.equal(observed.sourceReadSessions, 1); assert.equal(observed.acceptedPages, 1);
});

test('empty input is an authorized empty page and cancellation does not read or grant', async () => {
  const controller = createNearestRequiredRows(); controller.prepare(successes[4].sourceRows);
  const observed = {sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
    sourceReadCommands: [], acceptedPages: 0};
  let grants = 0, reads = 0;
  const driver = createNearestCarrierPageDriver(observed, resource => {reads++; return controller.read(resource);});
  const request = {resource: 'queries', columns: ['request_id', 'embedding'], requestWire: '{}',
    operation: nearestCarrierReadOperations.queries, authorizationFor() {grants++;},
    chargePage(bytes) {assert.equal(bytes.toString(), '[]'); return 1;},
    consumePage(rows) {assert.deepEqual(rows, []);}};
  await assert.rejects(driver({...request, signal: AbortSignal.abort(new Error('original cancel'))}), /original cancel/u);
  assert.equal(grants, 0); assert.equal(reads, 0);
  await driver(request); assert.equal(grants, 1); assert.equal(reads, 1);
  assert.equal(observed.acceptedPages, 1);
});

test('static refusal texts retain both role-pair, nullable and dimension conditions', () => {
  assert.deepEqual(refusals.filter(item => item.format === 'sql').map(item => item.name),
    ['missing-query-vector', 'missing-candidate-vector', 'relation-roles-omitted', 'nullable-query-key', 'dimension-mismatch']
      .map(name => `nearest-required-${name}-sql`));
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(refusals.find(item => item.name.includes('nullable-query-key')).text.includes('QUERY KEY (q.note)'));
  assert.ok(refusals.find(item => item.name.includes('dimension-mismatch')).text.includes('VECTOR_CONCAT(q.embedding,q.embedding)'));
});

test('normal delivery preserves its ten-module closure, two original files and static imports', () => {
  const closure = paths => {
    const delivered = new Set(paths.map(path => resolve(root, path)));
    const pending = [resolve(root, 'scripts/fixtures/release-nearest-required-worker.mjs')], seen = new Set();
    while (pending.length) {
      const file = pending.pop(); if (seen.has(file)) continue; seen.add(file);
      assert.ok(delivered.has(file), `missing fixture ${file}`);
      for (const match of readFileSync(file, 'utf8').matchAll(/(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
        pending.push(resolve(dirname(file), match[2]));
      }
    }
    return seen.size;
  };
  assert.equal(closure(releaseNearestRequiredFixturePaths), 10);
  assert.equal(releaseNearestRequiredFixturePaths.length, 12);
  assert.throws(() => closure(releaseNearestRequiredFixturePaths.filter(path => !path.endsWith('nearest-required-public-input.mjs'))));
  for (const path of ['spec/frontend/fixtures/nearest-keep/common-minimal.program.json',
    'spec/frontend/fixtures/nearest-keep/expected-schema.json']) {
    assert.ok(releaseNearestRequiredFixturePaths.includes(path));
  }
  for (const path of ['scripts/test-package-release-nearest-required.mjs', 'scripts/fixtures/packed-nearest-required.mjs',
    'reviews/2026-10-14-nearest-required-release-matrix/prepared-checks.mjs',
    'reviews/2026-10-14-nearest-required-release-matrix/prepared-release-public.mjs']) {
    const file = resolve(root, path);
    for (const match of readFileSync(file, 'utf8').matchAll(
      /^\s*(?:import\b[^;\n]*?\bfrom\s*|from\s*|import\s*)(['"])(\.[^'"\n]+\.mjs)\1/gmu)) {
      assert.doesNotThrow(() => readFileSync(resolve(dirname(file), match[2])));
    }
    execFileSync(process.execPath, ['--check', file], {timeout: 10000});
  }
});

function syntheticAudit() {
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['nearest-required', kind, index, item.name,
      createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
  let read = 0;
  const cases = successes.map((item, index) => {
    const beforeSubmit = {acceptedRuns: index, sourceIo: read, sourceReads: read, sourceReadSessions: read};
    read += item.sourceReadSessionCount;
    const beforeRead = {acceptedRuns: index + 1, sourceIo: read, sourceReads: read, sourceReadSessions: read};
    return {name: item.name, mode: 'local', ref: {synthetic: index},
      results: {answer: {rows: structuredClone(item.results.answer.rows), columns: structuredClone(item.results.answer.columns)}},
      beforeSubmit, beforeRead, afterReplay: {...beforeRead}};
  });
  const counters = {acceptedRuns: 9, sourceIo: 10, sourceReads: 10, sourceReadSessions: 10};
  return {report: {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: [...inventory],
    actualNormal: 9, actualRefusal: 10, observations: {sourceIo: 10, sourceReads: 10, sourceReadSessions: 10,
      issuedGrants: 10, acceptedPages: 10, closedSites: 1}}, receipt: {
    version: 'actql-nearest-required-acceptance/0.1', mode: 'local', complete: true, cases,
    refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: {synthetic: index},
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: {synthetic: index}},
      beforeSubmit: {...counters}, afterRefusal: {...counters}}))}};
}
test('independent auditor detects wrong tie selection, empty schema, extra shared acquisition and refusal', () => {
  const original = syntheticAudit(); assert.equal(auditNearestRequiredTransport('local', original.report, original.receipt).actualRows, 9);
  for (const mutate of [r => r.receipt.cases[1].results.answer.rows.reverse(),
    r => r.receipt.cases[0].results.answer.rows[0].neighbor.candidate_key.item_id = 'z',
    r => r.receipt.cases[3].results.answer.columns.pop(),
    r => r.receipt.cases[7].beforeRead.sourceReads++,
    r => r.receipt.cases[0].afterReplay.sourceIo++,
    r => r.receipt.refusals[0].outcome.problem.code = 'WrongCode',
    r => r.report.completedInventory.pop(), r => r.report.observations.closedSites = 0]) {
    const record = syntheticAudit(); mutate(record);
    assert.throws(() => auditNearestRequiredTransport('local', record.report, record.receipt));
  }
});
