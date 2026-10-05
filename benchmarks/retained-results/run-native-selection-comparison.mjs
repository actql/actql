// One predeclared case, never a full matrix or a relabeled historical baseline.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, writeFile, mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join, sep} from 'node:path';
import {performance} from 'node:perf_hooks';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {admitNativeResidentEstimateProfile} from './native-resident-estimate-profile.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct, admitNativeDirectProduct} from './native-direct-product.mjs';
import {runNativeDirectPair} from './native-direct-pair.mjs';
import {assessEquivalentSeries} from './equivalent-series-assessment.mjs';
import {assessPairedTiming} from './paired-assessment.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exec = promisify(execFile);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const [profilePath, outputPath, ...extra] = process.argv.slice(2);
assert(profilePath && outputPath && !extra.length, 'ExpectedNativeSelectionProfileAndOutput');
const destination = resolve(outputPath);
assert(destination !== root && !destination.startsWith(root + sep), 'NativeComparisonOutputInsideCheckout');
const profileBytes = await readFile(resolve(profilePath));
const profile = JSON.parse(profileBytes);
const fixture = retainedCase(workloads[0], 'narrow', 100);
const binary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest = digest(await readFile(binary));
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision);
  assert.equal(await git(['status', '--porcelain']), '', 'NativeComparisonRequiresCleanCheckout');
  assert.equal(digest(await readFile(binary)), binaryDigest, 'NativeComparisonBinaryChanged');
};
await unchanged();
const qualificationStart = performance.now();
admitNativeResidentEstimateProfile({profile, trainingFixture: retainedCase(workloads[0], 'narrow', 1000),
  targetFixture: fixture, revision, binaryDigest: 'sha256:' + binaryDigest});
const initialQualificationMilliseconds = performance.now() - qualificationStart;
const directory = await mkdtemp(join(tmpdir(), 'actql-native-selection-'));
const database = join(directory, 'source.duckdb');
const pairs = [], calibratedPairs = [];
let sourceContentSha256, sourcePreparationMilliseconds;
const basis = {revision, binaryDigest, profileDigest: digest(profileBytes), caseId: fixture.id,
  profileEstimateSource: profile.estimateSource, initialQualificationMilliseconds,
  offlineCalibrationMilliseconds: profile.calibrationProcessMilliseconds ?? null,
  method: 'seven predeclared alternating Native before/after pairs; same immutable source, Host, binary and registered limits; OS cache warmth uncontrolled',
  processLifecycle: 'new Native process and resident environment per leg; within-Run reuse is not a reused process',
  scopes: {before: 'old explicit resident experiment: Local/fresh 1000 ms and resident 1 ms',
    after: 'ordinary planner with measured realization rates',
    cycle: 'input preparation through process exit including physical cleanup; profile qualification separately and included in adjusted cycle',
    calibration: 'offline experiment preparation, reported separately; not first-request speedup'},
  limits: fixture.limits};
const save = value => writeFile(destination, JSON.stringify({...basis,
  sourceContentSha256, sourcePreparationMilliseconds, pairs, calibratedPairs, ...value}, null, 2));
try {
  const sourceStart = performance.now();
  await exec(process.execPath, [join(root,
    'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'), database,
  fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
  sourcePreparationMilliseconds = performance.now() - sourceStart;
  sourceContentSha256 = digest(await readFile(database));
  for (let index = 0; index < 7; index++) {
    await unchanged();
    const observations = {};
    for (const leg of index % 2 ? ['after', 'before'] : ['before', 'after']) {
      if (leg === 'after') {
        const after = await runNativeDirectPair({checkout: root, fixture, database, directory,
          index, nativeResidentEstimateProfile: profile});
        assert.equal(after.acceptanceEligible, true);
        calibratedPairs.push(after);
        observations.after = after;
      } else {
        const child = join(directory, 'before-' + index); await mkdir(child);
        const started = performance.now();
        const invocation = await prepareNativeDirectProduct({root, fixture, database, directory: child,
          residentPolicy: true, localRates: ['1000', '1000', '1000'], nativeRates: ['1000', '1000', '1000']});
        // Match the after leg's exact binary check inside its cycle rather
        // than attributing that shared inspection cost only to the new input.
        assert.equal(digest(await readFile(invocation.binary)), binaryDigest);
        const execution = await executeNativeDirectProduct(invocation, {root, timeoutMs: fixture.limits.timeoutMs});
        const cycleMs = performance.now() - started;
        const product = admitNativeDirectProduct(fixture, invocation, execution);
        assert.deepEqual(product.ownerCorrespondence.observations.choices.map(choice => choice.resident), [true, true, true]);
        observations.before = {cycleMs, product};
      }
      await unchanged();
      assert.equal(digest(await readFile(database)), sourceContentSha256, 'NativeComparisonSourceChanged');
    }
    const before = observations.before.product, after = observations.after.native;
    assert.deepEqual(before.taskHoldings.map(item => [item.rowsCid, item.bytes]),
      after.taskHoldings.map(item => [item.rowsCid, item.bytes]));
    assert.deepEqual(before.acquisitionEvidenceMetadata, after.acquisitionEvidenceMetadata);
    // The pair has already checked exact acquisition metadata with its
    // independent assembly. The before leg also uses the same bounded fixture.
    const afterCycle = after.coldMs + after.cleanupMs;
    pairs.push({index, caseId: fixture.id,
      order: index % 2 ? ['retained-actql', 'uncalibrated-native-selection'] : ['uncalibrated-native-selection', 'retained-actql'],
      samples: {
        'uncalibrated-native-selection': {status: 'completed', processCycleMs: observations.before.cycleMs,
          executionMs: before.executionMs, warmMs: before.warmMs,
          coldMs: observations.before.cycleMs - before.cleanupMs, cleanupMs: before.cleanupMs},
        'retained-actql': {status: 'completed', processCycleMs: afterCycle,
          executionMs: after.executionMs, warmMs: after.warmMs, coldMs: after.coldMs, cleanupMs: after.cleanupMs},
      }, residentProfileAdmissionMs: observations.after.residentProfileAdmissionMs,
      before: observations.before});
    await save({status: 'measuring'});
  }
  const timing = field => assessPairedTiming(pairs, {comparator: 'uncalibrated-native-selection',
    field, mode: 'difference', threshold: 0});
  const adjusted = pairs.map(pair => ({...pair, samples: {...pair.samples,
    'retained-actql': {...pair.samples['retained-actql'], processCycleMs:
      pair.samples['retained-actql'].processCycleMs + pair.residentProfileAdmissionMs}}}));
  const adjustedTiming = assessPairedTiming(adjusted, {comparator: 'uncalibrated-native-selection',
    field: 'processCycleMs', mode: 'difference', threshold: 0});
  const equivalentGate = assessEquivalentSeries(fixture, calibratedPairs);
  const improvement = adjustedTiming.status === 'pass' && adjustedTiming.upper < 0 &&
    equivalentGate.status === 'pass';
  const offline = profile.calibrationProcessMilliseconds;
  const oneTimePreparationMilliseconds = Number.isFinite(offline) && offline >= 0
    ? offline + initialQualificationMilliseconds : null;
  const breakEvenExecutions = improvement && oneTimePreparationMilliseconds !== null
    ? Math.ceil(oneTimePreparationMilliseconds / -adjustedTiming.estimate) : null;
  await save({status: 'completed', timing: Object.fromEntries(['processCycleMs', 'executionMs', 'warmMs', 'coldMs', 'cleanupMs']
    .map(field => [field, timing(field)])), adjustedTiming, equivalentGate,
    improvement, oneTimePreparationMilliseconds, breakEvenExecutions,
    improvementScope: 'already trained configuration; no first-use speedup asserted'});
  console.log(JSON.stringify({revision, outputPath: destination,
    adjustedTiming, equivalentGate, improvement, oneTimePreparationMilliseconds, breakEvenExecutions}));
} catch (error) {
  await save({status: 'failed', error: {name: error.name, message: error.message, code: error.code}});
  throw error;
} finally {await rm(directory, {recursive: true, force: true});}
