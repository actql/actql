// Isolate the artifact-read change: both legs use the same measured profile
// and actual planner. Seven fixed alternating pairs; never retry for a winner.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve, sep} from 'node:path';
import {promisify} from 'node:util';
import {performance} from 'node:perf_hooks';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {sha256File} from './release-artifacts.mjs';
import {runNativeDirectPair} from './native-direct-pair.mjs';
import {assessEquivalentSeries} from './equivalent-series-assessment.mjs';
import {assessPairedTiming} from './paired-assessment.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exec = promisify(execFile);
const [profilePath, outputPath, ...extra] = process.argv.slice(2);
assert(profilePath && outputPath && !extra.length, 'ExpectedArtifactComparisonProfileAndOutput');
const destination = resolve(outputPath);
assert(destination !== root && !destination.startsWith(root + sep), 'ArtifactComparisonOutputInsideCheckout');
const profile = JSON.parse(await readFile(profilePath, 'utf8'));
const fixture = retainedCase(workloads[0], 'narrow', 100);
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
const binary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest = await sha256File(binary);
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision);
  assert.equal(await git(['status', '--porcelain']), '', 'ArtifactComparisonRequiresCleanCheckout');
  assert.equal(await sha256File(binary), binaryDigest, 'ArtifactComparisonBinaryChanged');
};
await unchanged();
const directory = await mkdtemp(join(tmpdir(), 'actql-native-artifact-read-'));
const database = join(directory, 'source.duckdb');
const label = 'artifact-read-buffer-64k', pairs = [], before = [], after = [];
let sourceDigest, sourcePreparationMilliseconds;
const basis = {revision, binaryDigest, caseId: fixture.id, profileDigest: await sha256File(profilePath),
  estimateSource: profile.estimateSource, limits: fixture.limits,
  method: 'seven fixed alternating pairs; only full-byte stream buffer differs; identical measured profile and actual planner',
  scope: 'benchmark evidence-processing cost; not a Native query algorithm improvement',
  processLifecycle: 'new Native and independent Node processes per leg; OS cache warmth uncontrolled',
  offlineCalibrationMilliseconds: profile.calibrationProcessMilliseconds};
const save = value => writeFile(destination, JSON.stringify({...basis,
  sourceDigest, sourcePreparationMilliseconds, pairs, before, after, ...value}, null, 2));
try {
  const start = performance.now();
  await exec(process.execPath, [join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
    database, fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
  sourcePreparationMilliseconds = performance.now() - start;
  sourceDigest = await sha256File(database);
  for (let index = 0; index < 7; index++) {
    const results = {}, times = {};
    for (const leg of index % 2 ? ['after', 'before'] : ['before', 'after']) {
      await unchanged();
      const started = performance.now();
      results[leg] = await runNativeDirectPair({checkout: root, fixture, database, directory,
        index, nativeResidentEstimateProfile: profile,
        artifactReadChunkBytes: leg === 'before' ? 64 * 1024 : 1024 * 1024});
      times[leg] = performance.now() - started;
      assert.equal(results[leg].acceptanceEligible, true);
      assert.equal(await sha256File(database), sourceDigest);
    }
    await unchanged();
    const a = results.before, b = results.after;
    assert.deepEqual(a.native.selected, b.native.selected);
    assert.deepEqual(a.native.taskHoldings, b.native.taskHoldings);
    assert.deepEqual(a.native.acquisitionEvidenceMetadata, b.native.acquisitionEvidenceMetadata);
    assert.equal(a.provenance.releaseArtifactSha256, b.provenance.releaseArtifactSha256);
    assert.deepEqual(a.selectionProfile, b.selectionProfile);
    before.push(a); after.push(b);
    const sample = leg => ({status: 'completed', benchmarkCycleMs: times[leg],
      processCycleMs: results[leg].native.coldMs + results[leg].native.cleanupMs + results[leg].residentProfileAdmissionMs,
      executionMs: results[leg].native.executionMs, warmMs: results[leg].native.warmMs,
      cleanupMs: results[leg].native.cleanupMs});
    pairs.push({index, caseId: fixture.id,
      order: index % 2 ? ['retained-actql', label] : [label, 'retained-actql'],
      samples: {[label]: sample('before'), 'retained-actql': sample('after')}});
    await save({status: 'measuring'});
  }
  const gates = {before: assessEquivalentSeries(fixture, before), after: assessEquivalentSeries(fixture, after)};
  const timing = Object.fromEntries(['benchmarkCycleMs', 'processCycleMs', 'executionMs', 'warmMs', 'cleanupMs']
    .map(field => [field, assessPairedTiming(pairs, {comparator: label, field, mode: 'difference', threshold: 0})]));
  const admitted = gates.before.status === 'pass' && gates.after.status === 'pass';
  await save({status: 'completed', gates, timing,
    evidenceProcessingImprovement: admitted && timing.benchmarkCycleMs.upper < 0,
    nativeCycleImprovement: admitted && timing.processCycleMs.upper < 0,
    queryAlgorithmChanged: false});
  console.log(JSON.stringify({revision, outputPath: destination, gates, timing, queryAlgorithmChanged: false}));
} catch (error) {
  await save({status: 'failed', error: {name: error.name, message: error.message, code: error.code}});
  throw error;
} finally {await rm(directory, {recursive: true, force: true});}
