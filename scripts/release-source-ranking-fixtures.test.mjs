import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {releaseSourceRankingFixturePaths, releaseSourceRankingEnvironment} from './release-source-ranking-fixtures.mjs';
import {sourceRankingPublicSuccesses as successes, sourceRankingPublicRefusals as refusals}
  from './fixtures/source-ranking-public-input.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {auditSourceRankingTransport} from '../reviews/2026-10-14-source-ranking-public-controls/public-audit.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
function closure(paths) {
  const delivered = new Set(paths.map(path => resolve(root, path)));
  const pending = [resolve(root, 'scripts/fixtures/release-source-ranking-worker.mjs')];
  const seen = new Set(), missing = [];
  while (pending.length) {
    const path = pending.pop(); if (seen.has(path)) continue; seen.add(path);
    if (!delivered.has(path)) { missing.push(path); continue; }
    for (const match of readFileSync(path, 'utf8').matchAll(
      /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) pending.push(resolve(dirname(path), match[2]));
  }
  return {seen, missing};
}
test('normal Source ranking delivery includes the actual relative import closure', () => {
  const actual = closure(releaseSourceRankingFixturePaths);
  assert.deepEqual(actual.missing, []); assert.equal(actual.seen.size, 8);
  assert.ok(actual.seen.has(resolve(root, 'scripts/fixtures/source-ranking-installed-source.mjs')));
});
test('missing score supplier is detected before a consumer can run', () => {
  const actual = closure(releaseSourceRankingFixturePaths.filter(path => !path.endsWith('source-ranking-installed-source.mjs')));
  assert.deepEqual(actual.missing, [resolve(root, 'scripts/fixtures/source-ranking-installed-source.mjs')]);
});
test('prepared normal four-package entry parses without any product or worker execution', () => {
  for (const path of ['scripts/test-package-release-source-ranking.mjs',
    'scripts/fixtures/release-source-ranking-worker.mjs', 'scripts/fixtures/packed-source-ranking.mjs',
    'reviews/2026-10-14-source-ranking-public-controls/prepared-release-public.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});
test('shared release environment excludes checkout paths and foreign fixture selectors', () => {
  const env = releaseSourceRankingEnvironment({NODE_PATH: '/checkout', NODE_OPTIONS: '--import=/overlay',
    ACTQL_TEST_QUERY_TRANSPORT: 'foreign', MOON_HOME: '/toolchain'},
  {registry: 'http://127.0.0.1:1/', root: '/private/tmp/control', node: '/pinned/node'});
  for (const key of ['NODE_PATH', 'NODE_OPTIONS', 'ACTQL_TEST_QUERY_TRANSPORT', 'MOON_HOME']) assert.equal(Object.hasOwn(env, key), false);
  assert.equal(env.npm_config_registry, 'http://127.0.0.1:1/');
});
function syntheticRecords() {
  // Audit-unit inputs only, deliberately not actual Run or Host evidence.
  const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
    JSON.stringify(['source-ranking', kind, index, item.name,
      createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
  const report = {mode: 'local', complete: true, expectedInventory: inventory, completedInventory: inventory,
    actualNormal: 6, actualRefusal: 4, observations: {sourceIo: 12, sourceReads: 12,
      sourceReadSessions: 12, acceptedPages: 12, issuedGrants: 12, closedSites: 1}};
  const receipt = {version: 'actql-source-ranking-acceptance/0.1', mode: 'local', complete: true,
    cases: successes.map((item, index) => {
      const beforeSubmit = {acceptedRuns: index, sourceIo: 2 * index, sourceReads: 2 * index, sourceReadSessions: 2 * index};
      const beforeRead = {acceptedRuns: index + 1, sourceIo: 2 * (index + 1), sourceReads: 2 * (index + 1), sourceReadSessions: 2 * (index + 1)};
      return {name: item.name, mode: 'local', ref: {unit_test_only: index}, results: structuredClone(item.results),
        beforeSubmit, beforeRead, afterReplay: structuredClone(beforeRead)};
    }), refusals: refusals.map((item, index) => ({name: item.name, mode: 'local', submissionRef: `unit-only-${index}`,
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: `unit-only-${index}`},
      beforeSubmit: {acceptedRuns: 6}, afterRefusal: {acceptedRuns: 6}}))};
  return {report, receipt};
}
test('independent audit requires values full ordered schema source counts and replay equality', () => {
  const original = syntheticRecords();
  assert.equal(auditSourceRankingTransport('local', original.report, original.receipt).actualRows, 12);
  for (const mutate of [
    record => record.receipt.cases[0].results.answer.rows.reverse(),
    record => record.receipt.cases[0].results.answer.columns[1].contract.nullable = true,
    record => record.receipt.cases[0].afterReplay.sourceReads++,
    record => record.report.observations.closedSites = 0,
    record => record.receipt.refusals[0].afterRefusal.acceptedRuns++,
  ]) {
    const record = syntheticRecords(); mutate(record);
    assert.throws(() => auditSourceRankingTransport('local', record.report, record.receipt));
  }
});
test('independent audit refuses an incomplete inventory or omitted case', () => {
  for (const mutate of [record => record.report.complete = false,
    record => record.report.completedInventory = record.report.completedInventory.slice(1),
    record => record.receipt.cases.pop(), record => record.receipt.refusals.pop()]) {
    const record = syntheticRecords(); mutate(record);
    assert.throws(() => auditSourceRankingTransport('local', record.report, record.receipt));
  }
});
