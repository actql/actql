import {execFile} from 'node:child_process';
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';
import {promisify} from 'node:util';
import {retainedCase, retainedMatrix} from './fixtures.mjs';
import {assessEquivalentMatrix, formatEquivalentMatrix} from
  './equivalent-matrix-assessment.mjs';
import {runMatchedEquivalentPair} from
  '../../adapters/connectors/duckdb/node/bench/matched-equivalent-pair.mjs';

const exec = promisify(execFile);

async function inspectCheckout(checkout) {
  const git = async args => (await exec('git', args, {cwd: checkout})).stdout.trim();
  return {revision: await git(['rev-parse', 'HEAD']),
    dirty: Boolean(await git(['status', '--porcelain']))};
}

function trainingFixtures(target) {
  // Training-only sizes never change the registered evaluation denominator.
  // Prefer the nearest smaller case, then descend only when that candidate
  // cannot be forced under the unchanged physical capacity.
  const sizes = [100, 1000, 10000, 100000, 1000000];
  const lower = sizes.filter(rows => rows < target.rows).sort((a, b) => b - a);
  const higher = sizes.filter(rows => rows > target.rows).sort((a, b) => a - b);
  return (lower.length ? lower : higher.slice(0, 1)).map(rows =>
    retainedCase(target.workload, target.layout, rows));
}

async function defaultCalibrate({checkout, outputDirectory, training, target}) {
  const script = join(checkout,
    'adapters/connectors/duckdb/node/bench/calibrate-retained-case.mjs');
  let stdout;
  try {
    ({stdout} = await exec(process.execPath,
      [script, target.workload, target.layout, String(training.rows), String(target.rows)],
      {cwd: checkout, env: {...process.env, ACTQL_TEST_SCRATCH_ROOT: outputDirectory},
        timeout: 10 * Math.max(training.limits.timeoutMs, target.limits.timeoutMs),
        maxBuffer: 4 * 1024 * 1024}));
  } catch (error) {
    const started = String(error.stdout ?? '').trim().split('\n').map(line => {
      try { return JSON.parse(line); } catch { return undefined; }
    }).find(event => event?.event === 'started');
    const directory = started?.directory;
    if (directory && resolve(directory).startsWith(resolve(outputDirectory) + sep) &&
        started.caseId === training.id && started.heldOutCaseId === target.id) {
      try {
        const failed = JSON.parse(await readFile(join(directory, 'failure.json'), 'utf8'));
        if (failed.revision === (await inspectCheckout(checkout)).revision &&
            failed.caseId === training.id && failed.heldOutCaseId === target.id &&
            ['TrainingCapacityInfeasible', 'TrainingCandidateNotSelected']
              .includes(failed.error?.code)) {
          error.code = failed.error.code;
        }
      } catch { /* Keep the actual child failure when no trusted record exists. */ }
    }
    throw error;
  }
  const events = stdout.trim().split('\n').map(line => JSON.parse(line));
  const finished = events.findLast(event => event.event === 'finished');
  const directory = finished?.directory;
  if (!directory || !resolve(directory).startsWith(resolve(outputDirectory) + sep) ||
      finished.caseId !== training.id || finished.heldOutCaseId !== target.id) {
    throw new Error('InvalidCalibrationResult');
  }
  const profile = JSON.parse(await readFile(join(directory, 'profile.json'), 'utf8'));
  if (profile.trainingCaseId !== training.id || profile.targetCaseId !== target.id) {
    throw new Error('ForeignCalibrationProfile');
  }
  return Object.freeze({directory, database: join(directory, 'held-out-source.duckdb'),
    trainingCaseId: training.id});
}

const failure = error => Object.freeze({
  name: error?.name ?? 'Error',
  code: error?.code,
  message: error?.message ?? String(error),
});

// Persist every registered case and each attempted pair before advancing.
// A missing, failed or unqualified case remains in the matrix denominator.
export async function runEquivalentMatrix({checkout, outputDirectory,
  caseId, calibrate = defaultCalibrate, runPair = runMatchedEquivalentPair,
  inspect = inspectCheckout}) {
  if (typeof checkout !== 'string' || !checkout.length ||
      typeof outputDirectory !== 'string' || !outputDirectory.length ||
      (caseId !== undefined && (typeof caseId !== 'string' || !caseId.length)) ||
      typeof calibrate !== 'function' || typeof runPair !== 'function' ||
      typeof inspect !== 'function') {
    throw new TypeError('InvalidEquivalentMatrixRun');
  }
  const fixtures = retainedMatrix();
  if (caseId !== undefined && !fixtures.some(value => value.id === caseId)) {
    throw new TypeError('UnregisteredEquivalentCase');
  }
  const root = resolve(checkout);
  const destination = resolve(outputDirectory);
  if (destination === root || destination.startsWith(root + sep)) {
    throw new TypeError('EquivalentMatrixOutputInsideCheckout');
  }
  const initial = await inspect(root);
  const revision = initial?.revision;
  if (!/^[0-9a-f]{40}$/.test(revision ?? '') || initial.dirty) {
    throw new Error('EquivalentMatrixRequiresCleanCheckout');
  }
  await mkdir(destination, {recursive: true});
  if ((await readdir(destination)).length) throw new Error('EquivalentMatrixOutputMustBeEmpty');
  const records = [];
  const selected = caseId === undefined ? fixtures : fixtures.filter(value => value.id === caseId);
  for (const [position, fixture] of selected.entries()) {
    const trainings = trainingFixtures(fixture);
    const record = {caseId: fixture.id, trainingCaseId: undefined,
      status: 'incomplete', trainingAttempts: [], pairs: []};
    const path = join(destination, `case-${String(position).padStart(2, '0')}.json`);
    records.push(record);
    try {
      let calibrated;
      for (const training of trainings) {
        try {
          calibrated = await calibrate({checkout: root,
            outputDirectory: destination, training, target: fixture});
          record.trainingCaseId = training.id;
          record.trainingAttempts.push({trainingCaseId: training.id,
            status: 'completed'});
          break;
        } catch (error) {
          record.trainingAttempts.push({trainingCaseId: training.id,
            status: 'failed', error: failure(error)});
          await writeFile(path, JSON.stringify(record, null, 2));
          if (error.code !== 'TrainingCapacityInfeasible' &&
              error.code !== 'TrainingCandidateNotSelected') throw error;
        }
      }
      if (!calibrated) throw new Error('NoFeasibleIndependentTrainingCase');
      record.calibrationDirectory = calibrated.directory;
      for (let index = 0; index < 7; index++) {
        try {
          record.pairs.push(await runPair({fixture, checkout: root,
            database: calibrated.database, directory: calibrated.directory,
            estimateProfileDirectory: calibrated.directory, index}));
        } catch (error) {
          record.pairs.push({index, caseId: fixture.id, status: 'failed',
            acceptanceEligible: false, error: failure(error)});
        }
        await writeFile(path, JSON.stringify(record, null, 2));
      }
    } catch (error) {
      record.error = failure(error);
    }
    const assessment = assessEquivalentMatrix([record], revision).cases.find(
      value => value.caseId === fixture.id);
    record.status = assessment.status;
    record.reason = assessment.reason;
    await writeFile(path, JSON.stringify(record, null, 2));
    await writeFile(join(destination, 'progress.json'), JSON.stringify({revision,
      selectedCases: selected.length, completedCases: records.length,
      records}, null, 2));
    const current = await inspect(root);
    if (current.revision !== revision || current.dirty) {
      throw new Error('EquivalentMatrixSourcesChanged');
    }
  }
  const assessment = assessEquivalentMatrix(records, revision);
  await writeFile(join(destination, 'assessment.json'), JSON.stringify(assessment, null, 2));
  await writeFile(join(destination, 'assessment.md'), formatEquivalentMatrix(assessment));
  return Object.freeze({revision, outputDirectory: destination, assessment});
}
