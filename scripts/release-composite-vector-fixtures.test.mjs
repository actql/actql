import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {releaseCompositeVectorFixturePaths, releaseCompositeVectorEnvironment}
  from './release-composite-vector-fixtures.mjs';
import {compositeVectorSuccesses as successes, compositeVectorRefusals as refusals}
  from './fixtures/composite-vector-source-input.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {auditCompositeVectorTransport} from '../reviews/2026-10-14-composite-vector-release-matrix/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
function closure(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-composite-vector-worker.mjs')];
  const seen = new Set(), missing = [];
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    if (!delivered.has(path)) {missing.push(path); continue;}
    for (const match of readFileSync(path, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) pending.push(resolve(dirname(path), match[2]));
  }
  return {seen, missing};
}
test('composite release delivery closes over all eight actual modules and detects omission', () => {
  const all = closure(releaseCompositeVectorFixturePaths);
  assert.deepEqual(all.missing, []); assert.equal(all.seen.size, 8);
  for (const omitted of ['composite-vector-installed-source.mjs', 'composite-vector-source-input.mjs']) {
    assert.deepEqual(closure(releaseCompositeVectorFixturePaths.filter(path => !path.endsWith(omitted))).missing,
      [resolve(root, 'scripts/fixtures', omitted)]);
  }
});
test('consumer and bounded public recipe parse and resolve their direct imports without product execution', () => {
  for (const path of ['scripts/test-package-release-composite-vector.mjs',
    'scripts/fixtures/packed-composite-vector.mjs', 'scripts/fixtures/release-composite-vector-worker.mjs',
    'reviews/2026-10-14-composite-vector-release-matrix/prepared-release-public.mjs']) {
    const absolute = resolve(root, path);
    execFileSync(process.execPath, ['--check', absolute], {timeout: 10000});
    for (const match of readFileSync(absolute, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
      assert.ok(existsSync(resolve(dirname(absolute), match[2])), match[2]);
    }
  }
});
test('the existing release environment excludes checkout overlays and foreign selectors', () => {
  const env = releaseCompositeVectorEnvironment({NODE_PATH: '/checkout', NODE_OPTIONS: '--import=/overlay',
    MOON_HOME: '/toolchain', ACTQL_TEST_QUERY_TRANSPORT: 'foreign'},
  {registry: 'http://127.0.0.1:1/', root: '/private/tmp/control', node: '/pinned/node'});
  for (const key of ['NODE_PATH', 'NODE_OPTIONS', 'MOON_HOME', 'ACTQL_TEST_QUERY_TRANSPORT']) {
    assert.equal(Object.hasOwn(env, key), false);
  }
});
function synthetic() {
  // Audit controls only; no Run, Catalog, Source or Host has executed here.
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['composite-vector', kind, index, item.name,
      createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
  const count = acceptedRuns => ({acceptedRuns, sourceIo: 2 * acceptedRuns,
    sourceReads: 2 * acceptedRuns, sourceReadSessions: 2 * acceptedRuns});
  return {report: {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
    actualNormal: 5, actualRefusal: 2, observations: {...count(5), acceptedPages: 10, issuedGrants: 10, closedSites: 1}},
  receipt: {version: 'actql-composite-vector-acceptance/0.1', mode: 'local', complete: true,
    cases: successes.map((item, index) => ({mode: 'local', name: item.name,
      ref: {unitOnly: index}, submissionRef: {unitOnlySubmission: index}, results: structuredClone(item.results),
      beforeSubmit: count(index), beforeRead: count(index + 1), afterReplay: count(index + 1)})),
    refusals: refusals.map((item, index) => ({mode: 'local', name: item.name,
      submissionRef: {unitOnlyRefusal: index}, outcome: {kind: 'not_accepted',
        problem: {code: item.expectedCode}, submissionRef: {unitOnlyRefusal: index}},
      beforeSubmit: count(5), afterRefusal: count(5)}))}};
}
test('independent composite audit requires original key types values schema order and no reacquisition', () => {
  const good = synthetic(); assert.equal(auditCompositeVectorTransport('local', good.report, good.receipt).actualRows, 10);
  for (const change of [r => {r.receipt.cases[0].results.answer.rows.reverse();},
    r => {r.receipt.cases[0].results.answer.rows[0].hit.query_key.b = '1';},
    r => {delete r.receipt.cases[0].results.answer.rows[0].hit.candidate_key.a;},
    r => {r.receipt.cases[0].results.answer.columns[0].contract.fields.query_key.fields.b.nullable = true;},
    r => {r.receipt.cases[0].afterReplay.sourceReads++;},
    r => {delete r.receipt.cases[0].submissionRef;},
    r => {r.report.observations.closedSites = 0;},
    r => {r.receipt.refusals[0].afterRefusal.acceptedRuns++;}]) {
    const r = synthetic(); change(r); assert.throws(() => auditCompositeVectorTransport('local', r.report, r.receipt));
  }
});
test('missing incomplete or reordered actual inventory cannot establish a complete cohort', () => {
  for (const change of [r => {r.report.complete = false;}, r => {r.report.completedInventory.reverse();},
    r => {r.receipt.cases.pop();}, r => {r.receipt.refusals.pop();},
    r => {r.receipt.refusals[0].outcome.problem.code = 'Other';}]) {
    const r = synthetic(); change(r); assert.throws(() => auditCompositeVectorTransport('local', r.report, r.receipt));
  }
});
