import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { additionalSchedule } from './layout-measurement-support.mjs';

test('report audit rejects missing pairs, changed scopes and mismatched provenance', () => {
  // Synthetic measurement values, not performance evidence. Source identities
  // come from committed files so the test also works with uncommitted edits.
  const hash = input => createHash('sha256').update(input).digest('hex');
  const git = args => execFileSync('git', args, { maxBuffer: 16 * 1024 * 1024 });
  const commit = git(['rev-parse', 'HEAD']).toString().trim();
  const manifestBytes = readFileSync('benchmarks/local-relation/columnar-experiment.json');
  const manifest = JSON.parse(manifestBytes);
  const paths = ['src', 'scripts', 'spec', 'vendor', 'moon.mod', 'moon.mod.json', 'moon.lock',
    'toolchain.json', 'benchmarks/local-relation/columnar-experiment.json'];
  const files = git(['ls-tree', '-r', '--name-only', commit, '--', ...paths]).toString().trim().split('\n').sort();
  // Independent tree hashing via individual blobs; deliberately not the batch
  // framing implementation used by the command under test.
  const tree = createHash('sha256');
  for (const file of files) tree.update(file + '\0').update(git(['show', `${commit}:${file}`]));
  const report = {
    status: 'complete', measured_repetitions: 7, warmups: 1, working_tree_status: '',
    manifest_sha256: hash(manifestBytes), source_commit: commit, source_tree_sha256: tree.digest('hex'),
    script_sha256: hash(git(['show', `${commit}:scripts/measure-layouts.mjs`])),
    targets: ['native', 'js', 'wasm'].map(target => ({
      target, artifact_sha256: 'a'.repeat(64),
      samples: additionalSchedule(manifest, target, false).map(s => ({
        ...s, kind: 'layout-sample', disposal_included: true, phases_us: [1, 2, 3, 4, 5],
        end_to_end_us: s.candidate === 'A' ? 20 : 16, process_wall_ms: 100, peak_rss_bytes: 4096,
      })),
    })),
  };
  mkdirSync('_build', { recursive: true });
  const directory = mkdtempSync(resolve('_build/layout-report-test-'));
  const input = resolve(directory, 'input.json');
  const output = resolve(directory, 'summary.json');
  const command = value => {
    writeFileSync(input, JSON.stringify(value));
    return spawnSync(process.execPath, ['scripts/summarize-layout-report.mjs', 'additional', input, output],
      { encoding: 'utf8' });
  };
  try {
    const accepted = command(report);
    assert.equal(accepted.status, 0, accepted.stderr);
    const summary = JSON.parse(readFileSync(output));
    assert.equal(summary.adoption_eligible, false);
    assert.equal(summary.summaries.length, 78);
    assert.equal(summary.summaries[0].metrics.end_to_end_us.medianRatio, 0.8);
    for (const mutate of [
      r => { r.status = 'running'; },
      r => { r.working_tree_status = ' M src/changed.mbt'; },
      r => { r.source_tree_sha256 = '0'.repeat(64); },
      r => { r.targets[0].samples.pop(); },
      r => { r.targets[0].samples[1] = r.targets[0].samples[0]; },
      r => { r.targets[0].samples[0].disposal_included = false; },
      r => { r.targets[0].samples[0].end_to_end_us = 1; },
      r => { r.targets[0].samples[0].peak_rss_bytes = 0; },
    ]) {
      const invalid = structuredClone(report);
      mutate(invalid);
      assert.notEqual(command(invalid).status, 0);
    }
  } finally {
    rmSync(directory, { recursive: true });
  }
});
