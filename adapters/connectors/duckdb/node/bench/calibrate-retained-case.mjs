// Separate training observations for registered retained-results cases.
// These forced-choice runs are never performance acceptance samples.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {createReadStream} from 'node:fs';
import {mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {retainedCase, workloads} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';
import {managedCaseConfiguration} from
  '../../../../../benchmarks/retained-results/managed-configuration.mjs';
import {createManagedExampleHost} from '../examples/managed-host.mjs';

const run = promisify(execFile);
const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const [workload, layout, rowsText, heldOutRowsText, ...extra] = process.argv.slice(2);
if (!workload || !layout || !/^(0|[1-9][0-9]*)$/.test(rowsText ?? '') ||
    (heldOutRowsText !== undefined && !/^(0|[1-9][0-9]*)$/.test(heldOutRowsText)) || extra.length) {
  throw new TypeError('InvalidCalibrationCaseArguments');
}
const fixture = retainedCase(workload, layout, Number(rowsText));
const heldOut = heldOutRowsText === undefined ? fixture :
  retainedCase(workload, layout, Number(heldOutRowsText));
if (heldOutRowsText !== undefined && heldOut.id === fixture.id) {
  throw new TypeError('CalibrationRequiresDistinctHeldOutCase');
}
const git = async args => (await run('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
if (await git(['status', '--porcelain'])) throw Error('CalibrationRequiresCleanCheckout');
const unchanged = async () => {
  if (await git(['rev-parse', 'HEAD']) !== revision ||
      await git(['status', '--porcelain'])) {
    throw Error('CalibrationSourcesChanged');
  }
};
const sha256 = value => createHash('sha256').update(value).digest('hex');
const serialize = value => JSON.stringify(value, (_, item) =>
  typeof item === 'bigint' ? item.toString() : item, 2);
const read = path => readFile(new URL(path,
  new URL('../../../../../', import.meta.url)), 'utf8');
const fileHash = async path => {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
};
const contracts = {
  adoptedText: await read('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
  query: await read('spec/contracts/actql-query-acquisition.json'),
  evidence: await read('spec/contracts/actql-query-process-evidence.json'),
  receipts: await read('spec/contracts/actql-query-two-receipt.json'),
};
const directory = await mkdtemp(join(
  process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir(), 'actql-retained-calibration-'));
const database = join(directory, 'source.duckdb');
console.log(JSON.stringify({event: 'started', revision, caseId: fixture.id,
  heldOutCaseId: heldOut.id, directory, scope: 'forced-training-not-acceptance'}));
await run(process.execPath, [
  fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
  database, workload, layout, rowsText,
], {timeout: fixture.limits.timeoutMs});
const sourceSha256 = await fileHash(database);
const heldOutDatabase = heldOut === fixture ? database : join(directory, 'held-out-source.duckdb');
if (heldOut !== fixture) {
  await run(process.execPath, [
    fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
    heldOutDatabase, workload, layout, heldOutRowsText,
  ], {timeout: heldOut.limits.timeoutMs});
}
const heldOutSourceSha256 = await fileHash(heldOutDatabase);
const taskCount = workload === workloads[1] ? 4 : 3;
const expensive = '2147483647';
const plan = candidate => ({
  resident: true,
  nativeMilliseconds: candidate === 'duckdb' ? '1' : expensive,
  localTaskMilliseconds: Array(taskCount).fill(candidate === 'local' ? '1' : expensive),
  nativeTaskMilliseconds: Array(taskCount).fill(candidate === 'duckdb' ? '1' : expensive),
  estimateSource: `sha256:${sha256(`calibration:${candidate}:${fixture.id}:${revision}`)}`,
});
async function runTrainingCandidate(candidate, round, selectedFixture = fixture,
  selectedDatabase = database, selection = plan(candidate)) {
  const config = managedCaseConfiguration(selectedFixture, contracts, selectedDatabase, directory);
  const host = await createManagedExampleHost(config.limits);
  let result;
  let observation;
  let cleanupMs = 0;
  try {
    const started = performance.now();
    result = await host.run({...config.input, ...selection},
      {run: `calibration-${round}-${candidate}`, childLimits: config.childLimits},
      AbortSignal.timeout(config.timeoutMs));
    const executionMs = performance.now() - started;
    assert.equal(result.report.status, 'host-tasks-completed');
    assert.equal(result.report.completed.length, taskCount);
    const selectedExpectedCid = selectedFixture.identity().rowsCid;
    assert.equal(result.completion(taskCount)?.descriptor.rows_cid, selectedExpectedCid);
    assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
    const tasks = result.report.completed;
    if (candidate !== 'ordinary') {
      assert(tasks.every(task => task.realization === candidate),
        `CalibrationCandidateMismatch:${candidate}`);
    }
    const elapsed = tasks.map(task => task.taskElapsedMilliseconds);
    assert(elapsed.every(value => Number.isFinite(value) && value >= 0),
      'CalibrationMissingTaskInterval');
    observation = {round, candidate, taskElapsedMilliseconds: elapsed,
      executionMs, warmMs: elapsed.reduce((sum, value) => sum + value, 0),
      caseId: selectedFixture.id, selection, outputCid: selectedExpectedCid,
      taskRealizations: tasks.map(task => task.realization),
      tasks, hostPhases: result.phases,
      workerPreparationDetails: result.report.preparation_diagnostics,
      usage: result.usage()};
  } finally {
    if (result) {
      const started = performance.now();
      await result.close();
      cleanupMs = performance.now() - started;
      assert.equal(result.cleanupHandle.status().pending, false);
      for (let task = 1; task <= taskCount; task++) {
        assert.equal(result.completion(task)?.retained, false);
      }
    }
  }
  return {...observation, cleanupMs, releaseConfirmed: true};
}
const observations = [];
const expectedCid = fixture.identity().rowsCid;
try {
  for (let round = 0; round < 3; round++) {
    for (const candidate of round % 2 === 0 ? ['local', 'duckdb'] : ['duckdb', 'local']) {
      await unchanged();
      const observation = await runTrainingCandidate(candidate, round);
      assert.equal(await fileHash(database), sourceSha256,
        'CalibrationSourceChanged');
      observations.push(observation);
      await writeFile(join(directory, `training-${round}-${candidate}.json`),
        serialize(observation));
      console.log(JSON.stringify({event: 'training', round, candidate,
        elapsed: observation.taskElapsedMilliseconds,
        cleanupMs: observation.cleanupMs}));
    }
  }
  await unchanged();
  const median = values => [...values].sort((a, b) => a - b)[1];
  const rates = candidate => Array.from({length: taskCount}, (_, task) => {
    const samples = observations.filter(value => value.candidate === candidate)
      .map(value => value.taskElapsedMilliseconds[task]);
    return String(Math.max(1, Math.ceil(median(samples))));
  });
  const training = {version: 'actql-retained-calibration/0.1', revision,
    caseId: fixture.id, sourceSha256,
    sourceDefinitionSha256: sha256(fixture.createSourceSql),
    programSha256: sha256(JSON.stringify(fixture.program())),
    expectedRowsCid: expectedCid, runtime: process.version,
    method: 'three alternating forced-choice training rounds per registered case; median task interval rounded up to milliseconds',
    acceptanceEligible: false, observations};
  const trainingBytes = serialize(training);
  const trainingSha256 = sha256(trainingBytes);
  const profile = {version: 'actql-retained-estimate-profile/0.1', revision,
    caseId: fixture.id, trainingSha256,
    sourceSha256, sourceDefinitionSha256: training.sourceDefinitionSha256,
    programSha256: training.programSha256,
    localTaskMilliseconds: rates('local'),
    nativeTaskMilliseconds: rates('duckdb'),
    acceptanceEligible: false,
    scope: 'measured training profile requiring held-out selection and obligation admission'};
  await writeFile(join(directory, 'training.json'), trainingBytes);
  await writeFile(join(directory, 'profile.json'), serialize(profile));
  const ordinary = await runTrainingCandidate('ordinary', 3, heldOut, heldOutDatabase, {
    resident: true,
    nativeMilliseconds: '1',
    localTaskMilliseconds: profile.localTaskMilliseconds,
    nativeTaskMilliseconds: profile.nativeTaskMilliseconds,
    estimateSource: `sha256:${trainingSha256}`,
  });
  assert.equal(await fileHash(heldOutDatabase), heldOutSourceSha256,
    'CalibrationHeldOutSourceChanged');
  await writeFile(join(directory, 'ordinary-choice.json'), serialize({
    ...ordinary, scope: heldOut === fixture
      ? 'same-case held-out execution, not held-out workload'
      : 'distinct registered workload size, not formal calibration acceptance',
    trainingCaseId: fixture.id,
    heldOutSourceSha256,
    acceptanceEligible: false,
  }));
  console.log(JSON.stringify({event: 'finished', directory, caseId: fixture.id,
    heldOutCaseId: heldOut.id,
    trainingSha256, localTaskMilliseconds: profile.localTaskMilliseconds,
    nativeTaskMilliseconds: profile.nativeTaskMilliseconds,
    ordinaryTaskRealizations: ordinary.taskRealizations}));
} catch (error) {
  await writeFile(join(directory, 'failure.json'), serialize({caseId: fixture.id,
    heldOutCaseId: heldOut.id, revision, sourceSha256, heldOutSourceSha256, observations,
    error: {name: error.name, message: error.message, code: error.code}}));
  throw error;
}
