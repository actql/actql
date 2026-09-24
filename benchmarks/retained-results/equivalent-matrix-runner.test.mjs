import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {retainedMatrix} from './fixtures.mjs';
import {runEquivalentMatrix} from './equivalent-matrix-runner.mjs';

const checkout = new URL('../../', import.meta.url).pathname;

test('one failed calibration does not drop any of the 27 registered cases', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-matrix-'));
  const outputDirectory = join(directory, 'results');
  const [first] = retainedMatrix();
  let calls = 0;
  try {
    const result = await runEquivalentMatrix({checkout, outputDirectory,
      inspect: async () => ({revision: 'a'.repeat(40), dirty: false}),
      calibrate: async ({target}) => {
        if (target.id === first.id) throw new Error('CalibratorUnavailable');
        return {directory, database: join(directory, 'unused.duckdb')};
      },
      runPair: async ({fixture, index}) => {
        calls++;
        return {index, caseId: fixture.id, status: 'failed',
          acceptanceEligible: false};
      }});
    assert.equal(result.assessment.status, 'incomplete');
    assert.equal(result.assessment.receivedRecords, 27);
    assert.equal(calls, 26 * 7);
    const firstRecord = JSON.parse(await readFile(join(outputDirectory,
      'case-00.json')));
    assert.equal(firstRecord.error.message, 'CalibratorUnavailable');
    const finalRecord = JSON.parse(await readFile(join(outputDirectory,
      'case-26.json')));
    assert.equal(finalRecord.pairs.length, 7);
    const progress = JSON.parse(await readFile(join(outputDirectory,
      'progress.json')));
    assert.equal(progress.completedCases, 27);
    assert.equal(progress.records.length, 27);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('a one-case rehearsal remains incomplete for the full matrix', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-matrix-'));
  const outputDirectory = join(directory, 'results');
  const target = retainedMatrix()[1];
  try {
    const result = await runEquivalentMatrix({checkout, outputDirectory,
      inspect: async () => ({revision: 'a'.repeat(40), dirty: false}),
      caseId: target.id,
      calibrate: async () => ({directory, database: join(directory, 'unused.duckdb')}),
      runPair: async ({fixture, index}) => ({index, caseId: fixture.id,
        status: 'failed', acceptanceEligible: false})});
    assert.equal(result.assessment.status, 'incomplete');
    assert.equal(result.assessment.receivedRecords, 1);
    assert.equal(result.assessment.cases.length, 27);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('capacity-limited training falls back without dropping its failed attempt', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-matrix-'));
  const outputDirectory = join(directory, 'results');
  const target = retainedMatrix().find(value =>
    value.layout === 'text-1024' && value.rows === 10000);
  const trainingSizes = [];
  try {
    const result = await runEquivalentMatrix({checkout, outputDirectory,
      inspect: async () => ({revision: 'a'.repeat(40), dirty: false}),
      caseId: target.id,
      calibrate: async ({training}) => {
        trainingSizes.push(training.rows);
        if (training.rows === 1000) {
          throw Object.assign(new Error('LocalCandidateUnavailable'),
            {code: 'TrainingCandidateNotSelected'});
        }
        return {directory, database: join(directory, 'unused.duckdb')};
      },
      runPair: async ({fixture, index}) => ({index, caseId: fixture.id,
        status: 'failed', acceptanceEligible: false})});
    assert.equal(result.assessment.status, 'incomplete');
    assert.deepEqual(trainingSizes, [1000, 100]);
    const record = JSON.parse(await readFile(join(outputDirectory, 'case-00.json')));
    assert.equal(record.trainingCaseId, `${target.workload}/${target.layout}/100`);
    assert.deepEqual(record.trainingAttempts.map(value => value.status),
      ['failed', 'completed']);
    assert.equal(record.trainingAttempts[0].error.code,
      'TrainingCandidateNotSelected');
    assert.equal(record.pairs.length, 7);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('Native cases prepare a source without running Node candidate calibration', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-matrix-'));
  const outputDirectory = join(directory, 'results');
  const target = retainedMatrix().find(value =>
    value.id === 'native-acquisition-full-validation-low-selectivity/narrow/10000');
  let nativeCalibrations = 0, nativeSources = 0, nativePairs = 0;
  try {
    const result = await runEquivalentMatrix({checkout, outputDirectory,
      inspect: async () => ({revision: 'a'.repeat(40), dirty: false}),
      caseId: target.id, productProfile: 'native-eligible',
      calibrate: async () => { throw new Error('NodeCalibrationMustNotRun'); },
      nativeCalibrate: async () => {
        nativeCalibrations++;
        return {trainingCaseId:
          'native-acquisition-full-validation-low-selectivity/narrow/100',
        estimateSource: 'sha256:' + 'b'.repeat(64)};
      },
      nativeSource: async () => {
        nativeSources++;
        return {directory, database: join(directory, 'held-out.duckdb')};
      },
      runNativePair: async ({fixture, index}) => {
        nativePairs++;
        return {index, caseId: fixture.id, status: 'failed',
          acceptanceEligible: false};
      }});
    assert.equal(result.assessment.status, 'incomplete');
    assert.equal(nativeCalibrations, 1);
    assert.equal(nativeSources, 1);
    assert.equal(nativePairs, 7);
    const record = JSON.parse(await readFile(join(outputDirectory,
      'case-00.json')));
    assert.equal(record.trainingAttempts.length, 1);
    assert.equal(record.trainingAttempts[0].profile, 'native-direct');
    assert.equal(record.pairs.length, 7);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
