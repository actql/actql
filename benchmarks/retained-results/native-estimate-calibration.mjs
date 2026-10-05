// Calibrate the Native product entry separately from the Node Host profile.
// Forced training never contributes a paired acceptance timing.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve, join, sep} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {retainedCase, retainedMatrix, workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';
import {admitNativeEstimateProfile} from './native-estimate-profile.mjs';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const sha256 = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const parseCase = id => {
  const [workload, layout, rowText, ...remaining] = id.split('/');
  if (remaining.length || !/^[1-9][0-9]*$/.test(rowText ?? '')) {
    throw new TypeError('InvalidNativeCalibrationCase');
  }
  return retainedCase(workload, layout, Number(rowText));
};
const [trainingId, targetId, outputPath, ...extra] = process.argv.slice(2);
if (!trainingId || !targetId || !outputPath || extra.length) {
  throw new TypeError('Expected training case, registered target case and output path');
}
const destination = resolve(outputPath);
if (destination === root || destination.startsWith(root + sep)) {
  throw new TypeError('NativeCalibrationOutputInsideCheckout');
}
const training = parseCase(trainingId);
const target = retainedMatrix().find(value => value.id === targetId);
// The smallest registered target has no smaller valid fixture. Use the next
// registered size as a disjoint training source, as the Node profile does.
if (!target || training.id === target.id || training.workload !== target.workload ||
    training.layout !== target.layout ||
    !(training.rows < target.rows ||
      target.rows === 100 && training.rows === 1000)) {
  throw new TypeError('InvalidNativeHeldOutCalibrationPair');
}
const localEligible = registeredLocalEligibility(training).eligible;
assert.equal(localEligible, registeredLocalEligibility(target).eligible,
  'NativeCalibrationEligibilityMismatch');
const taskCount = target.workload === workloads[1] ? 4 : 3;
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
if (await git(['status', '--porcelain'])) {
  throw new Error('NativeCalibrationRequiresCleanCheckout');
}
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision,
    'NativeCalibrationRevisionChanged');
  assert.equal(await git(['status', '--porcelain']), '',
    'NativeCalibrationSourcesChanged');
};
const binary = join(root,
  '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest = sha256(await readFile(binary));
const probeScript = join(root, 'benchmarks/retained-results/native-case-probe.mjs');
const observations = [];
const runProbe = async (fixture, candidate, round, flags) => {
  await unchanged();
  const args = [probeScript, fixture.id,
    ...(retainedMatrix().some(item => item.id === fixture.id) ? [] : ['--training']),
    ...flags];
  const {stdout} = await exec(process.execPath, args, {
    cwd: root,
    timeout: fixture.limits.timeoutMs + 30000,
    maxBuffer: 1024 * 1024,
  });
  const observation = JSON.parse(stdout.trim().split('\n').at(-1));
  assert.equal(observation.status, 'verified-diagnostic');
  assert.equal(observation.case, fixture.id);
  assert.equal(observation.result.rows_cid, fixture.identity().rowsCid);
  assert.deepEqual(observation.taskIntervals.map(item => item.task),
    Array.from({length: taskCount}, (_, index) => index + 1));
  const selected = new Map(observation.selections.map(line => {
    const match = /^selection:([1-9][0-9]*):(local|duckdb)$/.exec(line);
    assert(match, 'InvalidNativeSelectionObservation');
    return [Number(match[1]), match[2]];
  }));
  assert.equal(selected.size, taskCount);
  if (candidate !== 'ordinary') {
    assert([...selected.values()].every(value => value === candidate),
      'NativeForcedCandidateNotSelected');
  }
  await unchanged();
  return {round, candidate, ...observation,
    selected: Array.from({length: taskCount}, (_, index) => selected.get(index + 1))};
};

try {
  for (let round = 0; round < 3; round++) {
    const candidates = localEligible
      ? round % 2 ? ['duckdb', 'local'] : ['local', 'duckdb']
      : ['duckdb'];
    for (const candidate of candidates) {
      const observation = await runProbe(training, candidate, round,
        // This calibration measures fresh DuckDB, never the resident offer
        // sharing its registration name. Keep both training legs explicit.
        candidate === 'local'
          ? ['--native-ms=2147483647', '--resident-policy=false']
          : ['--native-ms=1', '--resident-policy=false']);
      observations.push(observation);
      await writeFile(destination, JSON.stringify({status: 'training', revision,
        trainingCaseId: training.id, targetCaseId: target.id, observations}, null, 2));
      console.log(JSON.stringify({event: 'training', round, candidate,
        taskElapsedMilliseconds: observation.taskIntervals.map(item =>
          item.elapsedMilliseconds)}));
    }
  }
  const median = values => [...values].sort((left, right) => left - right)[1];
  const rates = candidate => Array.from({length: taskCount}, (_, task) => {
    const values = observations.filter(item => item.candidate === candidate)
      .map(item => item.taskIntervals[task].elapsedMilliseconds);
    assert.equal(values.length, 3);
    return String(Math.max(1, Math.ceil(median(values))));
  });
  const localTaskMilliseconds = localEligible ? rates('local') : null;
  const nativeTaskMilliseconds = rates('duckdb');
  const trainingBytes = JSON.stringify({revision, trainingCaseId: training.id,
    targetCaseId: target.id, binaryDigest, observations});
  const estimateSource = sha256(trainingBytes);
  const flags = [
    '--resident-policy=false',
    '--native-ms=' + nativeTaskMilliseconds[0],
    ...(localEligible ? ['--local-task-ms=' + localTaskMilliseconds.join(',')] : []),
    '--native-task-ms=' + nativeTaskMilliseconds.join(','),
  ];
  const ordinary = await runProbe(target, 'ordinary', 3, flags);
  const profile = {version: 'actql-native-retained-estimate-profile/0.1',
    revision, trainingCaseId: training.id, targetCaseId: target.id,
    trainingSourceDefinitionSha256: sha256(training.createSourceSql),
    targetSourceDefinitionSha256: sha256(target.createSourceSql),
    trainingProgramSha256: sha256(JSON.stringify(training.program())),
    targetProgramSha256: sha256(JSON.stringify(target.program())),
    binaryDigest, estimateSource, localEligible,
    localTaskMilliseconds, nativeTaskMilliseconds,
    method: 'three alternating forced-choice Native rounds; median task interval rounded up to milliseconds',
    acceptanceEligible: false, observations, ordinary};
  admitNativeEstimateProfile({profile, trainingFixture: training,
    targetFixture: target, revision, binaryDigest});
  await writeFile(destination, JSON.stringify({status: 'completed', ...profile}, null, 2));
  console.log(JSON.stringify({event: 'finished', revision,
    trainingCaseId: training.id, targetCaseId: target.id,
    estimateSource, ordinarySelection: ordinary.selected, outputPath: destination}));
} catch (error) {
  await writeFile(destination, JSON.stringify({status: 'failed', revision,
    trainingCaseId: training.id, targetCaseId: target.id, observations,
    error: {name: error.name, message: error.message, code: error.code}}, null, 2));
  throw error;
}
