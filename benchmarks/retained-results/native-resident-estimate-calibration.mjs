// One predeclared Native experiment: 1,000-row training, held-out 100-row
// selection. Forced training choices are never paired performance acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join, sep} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {retainedCase, workloads} from './fixtures.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {nativeResidentCalibrationBasis, deriveNativeResidentRates,
  admitNativeResidentEstimateProfile} from './native-resident-estimate-profile.mjs';

const exec = promisify(execFile);
const calibrationStart = performance.now();
const root = fileURLToPath(new URL('../../', import.meta.url));
const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const [outputPath, ...extra] = process.argv.slice(2);
assert(outputPath && !extra.length, 'ExpectedNativeResidentCalibrationOutput');
const destination = resolve(outputPath);
assert(destination !== root && !destination.startsWith(root + sep), 'CalibrationOutputInsideCheckout');
const training = retainedCase(workloads[0], 'narrow', 1000);
const target = retainedCase(workloads[0], 'narrow', 100);
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision, 'CalibrationRevisionChanged');
  assert.equal(await git(['status', '--porcelain']), '', 'CalibrationRequiresCleanCheckout');
};
await unchanged();
const binary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest = digest(await readFile(binary));
const directory = await mkdtemp(join(tmpdir(), 'actql-resident-calibration-'));
const observations = [];
const basis = nativeResidentCalibrationBasis({trainingFixture: training, targetFixture: target,
  revision, binaryDigest});
const expected = {
  local: ['local', 'local', 'local'], fresh: ['duckdb', 'duckdb', 'duckdb'],
  resident: ['resident', 'resident', 'resident'], mixed: ['local', 'resident', 'resident'],
};
const high = '1000000';
const residentEstimates = {preparationMilliseconds: '1', cleanupMilliseconds: '1',
  taskMilliseconds: ['1', '1', '1'], importMilliseconds: ['1', '1', null, null]};
const runProbe = async (fixture, leg, round, rates, resident) => {
  await unchanged();
  assert.equal(digest(await readFile(binary)), binaryDigest, 'CalibrationBinaryChanged');
  const profilePath = join(directory, 'resident.json');
  if (resident) await writeFile(profilePath, JSON.stringify(resident));
  const args = [join(root, 'benchmarks/retained-results/native-case-probe.mjs'), fixture.id,
    '--phase-observer=true', '--resident-policy=' + Boolean(resident),
    '--local-task-ms=' + rates.local.join(','), '--native-task-ms=' + rates.fresh.join(','),
    ...(resident ? ['--resident-estimates=' + profilePath] : [])];
  const probeStart = performance.now();
  const {stdout} = await exec(process.execPath, args, {cwd: root,
    timeout: fixture.limits.timeoutMs + 30000, maxBuffer: 2 * 1024 * 1024});
  const observation = JSON.parse(stdout.trim().split('\n').at(-1));
  assert.equal(observation.case, fixture.id);
  assert.equal(observation.result.rows_cid, fixture.identity().rowsCid);
  assert.equal(observation.result.task_count, 3);
  const cost = nativeCostObservation(observation);
  if (leg !== 'ordinary') assert.deepEqual(cost.tasks.map(item => item.realization), expected[leg],
    'ResidentCalibrationTrainingChoiceMismatch');
  await unchanged();
  return {round, leg, command: [process.execPath, ...args], observation, cost,
    probeProcessCycleMilliseconds: performance.now() - probeStart};
};
try {
  for (let round = 0; round < 3; round++) {
    const order = round % 2 ? ['mixed', 'resident', 'fresh', 'local'] : ['local', 'fresh', 'resident', 'mixed'];
    for (const leg of order) {
      const rates = {local: Array(3).fill(leg === 'local' ? '1' : high),
        fresh: Array(3).fill(leg === 'fresh' ? '1' : high)};
      if (leg === 'mixed') rates.local[0] = '1';
      const resident = leg === 'resident' ? residentEstimates : leg === 'mixed'
        ? {...residentEstimates, taskMilliseconds: [high, '1', '1']} : undefined;
      const item = await runProbe(training, leg, round, rates, resident);
      observations.push(item);
      await writeFile(destination, JSON.stringify({...basis, status: 'training', observations}, null, 2));
      console.log(JSON.stringify({event: 'training', round, leg, cost: item.cost}));
    }
  }
  const {rates, residentEstimates: measuredResident} = deriveNativeResidentRates(observations, training);
  const estimateSource = digest(JSON.stringify({...basis, observations}));
  const ordinary = await runProbe(target, 'ordinary', 3, rates, measuredResident);
  const profile = {...basis, status: 'completed', observations,
    rates, residentEstimates: measuredResident, estimateSource, ordinary,
    calibrationProcessMilliseconds: performance.now() - calibrationStart};
  admitNativeResidentEstimateProfile({profile, trainingFixture: training, targetFixture: target,
    revision, binaryDigest});
  await writeFile(destination, JSON.stringify(profile, null, 2));
  console.log(JSON.stringify({event: 'finished', revision, binaryDigest, estimateSource,
    rates, residentEstimates: measuredResident, selected: ordinary.cost.tasks.map(item => item.realization),
    outputPath: destination}));
} catch (error) {
  await writeFile(destination, JSON.stringify({...basis, status: 'failed', observations,
    error: {name: error.name, message: error.message, code: error.code}}, null, 2));
  throw error;
} finally {await rm(directory, {recursive: true, force: true});}
