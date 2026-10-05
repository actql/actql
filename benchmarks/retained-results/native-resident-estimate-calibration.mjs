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
import {retainedCase, workloads} from './fixtures.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {nativeResidentEstimateArguments} from './native-resident-estimates.mjs';

const exec = promisify(execFile);
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
const basis = {version: 'actql-native-resident-estimate-observation/0.1', revision, binaryDigest,
  trainingCaseId: training.id, targetCaseId: target.id,
  trainingSourceDefinitionSha256: digest(training.createSourceSql),
  targetSourceDefinitionSha256: digest(target.createSourceSql),
  trainingProgramSha256: digest(JSON.stringify(training.program())),
  targetProgramSha256: digest(JSON.stringify(target.program())),
  acceptanceEligible: false,
  method: 'three predeclared alternating Native training rounds; median matched task/release cost rounded up to milliseconds'};
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
  return {round, leg, command: [process.execPath, ...args], observation, cost};
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
  const rate = values => {
    assert.equal(values.length, 3, 'IncompleteResidentCalibrationRounds');
    assert(values.every(value => Number.isSafeInteger(value) && value >= 0), 'InvalidCalibrationDuration');
    const value = String(Math.max(1, Math.ceil([...values].sort((a, b) => a - b)[1] / 1000)));
    assert(BigInt(value) <= 2147483647n, 'CalibrationDurationOverflow');
    return value;
  };
  const samples = leg => observations.filter(item => item.leg === leg).map(item => item.cost);
  const tasks = leg => Array.from({length: 3}, (_, index) => rate(samples(leg)
    .map(item => item.tasks[index].estimatedMicroseconds)));
  // This fixture's checked stage references use only producers 0 and 1.
  // Verify the independent Program structure instead of filling unobserved
  // producer slots with zero or a convenient invented import duration.
  const stages = training.program().stages;
  const producers = [...new Set(stages.slice(1).flatMap(stage => Object.values(stage.inputs)
    .map(input => stages.findIndex(candidate => candidate.id === input.result.stage))))].sort();
  assert.deepEqual(producers, [0, 1], 'ResidentCalibrationProducerDomainChanged');
  const measuredResident = {
    preparationMilliseconds: rate(samples('resident').map(item => item.preparationMicroseconds)),
    cleanupMilliseconds: rate(samples('resident').map(item => item.sharedCleanupMicroseconds)),
    taskMilliseconds: tasks('resident'),
    importMilliseconds: [0, 1, 2, 3].map(producer => producers.includes(producer)
      ? rate(samples(producer === 0 ? 'resident' : 'mixed').map(item => {
        const imports = item.imports.filter(value => value.producer === producer);
        assert.equal(imports.length, 1, 'MissingActualCalibrationImport');
        return imports[0].microseconds;
      })) : null),
  };
  nativeResidentEstimateArguments(measuredResident, 3);
  const rates = {local: tasks('local'), fresh: tasks('fresh')};
  const estimateSource = digest(JSON.stringify({...basis, observations}));
  const ordinary = await runProbe(target, 'ordinary', 3, rates, measuredResident);
  const offers = ordinary.observation.ownerCorrespondence.observations.candidates[0].body[5]
    .flatMap(candidate => candidate[5].filter(Boolean));
  for (const offer of offers) {
    const expectedTaskRate = offer[9] !== null ? measuredResident.taskMilliseconds :
      offer[1] === 'local' ? rates.local : rates.fresh;
    assert.equal(offer[8][0][1], expectedTaskRate[offer[0] - 1], 'MeasuredRateNotInActualOffer');
    if (offer[9] !== null) {
      assert.equal(offer[9][1].lines[0].milliseconds, measuredResident.preparationMilliseconds);
      assert.equal(offer[9][2].lines[0].milliseconds, measuredResident.cleanupMilliseconds);
      assert.deepEqual(offer[9][3].map(item => item[0].lines[0].milliseconds), measuredResident.importMilliseconds);
    }
  }
  await writeFile(destination, JSON.stringify({...basis, status: 'completed', observations,
    rates, residentEstimates: measuredResident, estimateSource, ordinary}, null, 2));
  console.log(JSON.stringify({event: 'finished', revision, binaryDigest, estimateSource,
    rates, residentEstimates: measuredResident, selected: ordinary.cost.tasks.map(item => item.realization),
    outputPath: destination}));
} catch (error) {
  await writeFile(destination, JSON.stringify({...basis, status: 'failed', observations,
    error: {name: error.name, message: error.message, code: error.code}}, null, 2));
  throw error;
} finally {await rm(directory, {recursive: true, force: true});}
