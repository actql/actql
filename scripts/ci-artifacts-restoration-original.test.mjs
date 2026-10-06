import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {projectCampaign} from './ci-artifacts.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');

test('the retained main original exposes all twelve new-owner restoration receipts and their costs', () => {
  // Lossless historical report; this is read-only replay of its projection,
  // not fresh execution of those MoonBit commands at this candidate revision.
  const original = gunzipSync(readFileSync(new URL('../docs/reviews/evidence/2026-10-06-pipeline-main-37198759659-L-M0-fixed.json.gz', import.meta.url)),
    {maxOutputLength: 4 * 1024 * 1024});
  assert.equal(sha(original), '5ce6b98807105317e43a3496e08045ff403afad2081d9e8dfeca61ea146d9e22');
  const report = JSON.parse(original);
  assert.equal(report.revision, '7c4bcb61b8d7e7c37b4be8eb986e1811842d345b');
  const expected = {fixed: ['handoff-wrong-port', 'stable-tie-reversed', 'rename-nullability-widened', 'rename-type-changed'],
    targets: ['js', 'wasm', 'native']};
  const projection = projectCampaign(report, 'fixed', expected);
  const restored = projection.phases.filter(row => row.phase === 'post-restore');
  assert.equal(restored.length, 12);
  assert.equal(projection.receipts.length, 36);
  assert.equal(new Set(projection.receipts.map(entry => entry.path)).size, 36);
  assert.equal(projection.targetComplete, true);
  assert.equal(restored.flatMap(row => row.receipts).length, 12);
  const totals = Object.fromEntries(projection.aggregates.filter(row => row.phase === 'post-restore').map(row => [row.target, row.actionMilliseconds]));
  assert.deepEqual(totals, {js: 24189.233001999906, wasm: 29196.78731400019, native: 68386.39861999999});
  for (const result of report.results) for (const execution of result.postRestore.executions) {
    assert.equal(sha(JSON.stringify(execution.receipt)), execution.digest);
    assert.equal(execution.receipt.boundary.workspace, report.restorationOwner.id);
    assert.notEqual(execution.receipt.boundary.workspace, report.workspaces.mutable.id);
    assert.equal(execution.receipt.sourceDigest, report.source.digest);
    assert(restored.some(row => row.receipts.some(ref => ref.path === execution.path && ref.digest === execution.digest)));
  }
  assert.equal(sha(original), '5ce6b98807105317e43a3496e08045ff403afad2081d9e8dfeca61ea146d9e22');
});
