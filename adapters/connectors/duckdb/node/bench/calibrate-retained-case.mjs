// Separate training observations for a registered retained-results case.
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
import {runRetainedComparator} from './retained-comparator.mjs';

const run = promisify(execFile);
const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const [workload, layout, rowsText, ...extra] = process.argv.slice(2);
if (!workload || !layout || !/^(0|[1-9][0-9]*)$/.test(rowsText ?? '') ||
    extra.length) {
  throw new TypeError('InvalidCalibrationCaseArguments');
}
const fixture = retainedCase(workload, layout, Number(rowsText));
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
const directory = await mkdtemp(join(tmpdir(), 'actql-retained-calibration-'));
const database = join(directory, 'source.duckdb');
console.log(JSON.stringify({event: 'started', revision, caseId: fixture.id,
  directory, scope: 'forced-training-not-acceptance'}));
await run(process.execPath, [
  fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
  database, workload, layout, rowsText,
], {timeout: fixture.limits.timeoutMs});
const sourceSha256 = await fileHash(database);
const taskCount = workload === workloads[1] ? 4 : 3;
const expensive = '2147483647';
const plan = candidate => ({
  resident: true,
  nativeMilliseconds: candidate === 'duckdb' ? '1' : expensive,
  localTaskMilliseconds: Array(taskCount).fill(candidate === 'local' ? '1' : expensive),
  nativeTaskMilliseconds: Array(taskCount).fill(candidate === 'duckdb' ? '1' : expensive),
  estimateSource: `sha256:${sha256(`calibration:${candidate}:${fixture.id}:${revision}`)}`,
});
const observations = [];
const expectedCid = fixture.identity().rowsCid;
try {
  for (let round = 0; round < 3; round++) {
    for (const candidate of round % 2 === 0 ? ['local', 'duckdb'] : ['duckdb', 'local']) {
      await unchanged();
      const report = await runRetainedComparator(
        fixture, contracts, database, directory, plan(candidate),
      );
      assert.equal(report.status, 'completed');
      assert.equal(report.expectedRowsCid, expectedCid);
      assert.equal(report.tasks.length, taskCount);
      assert(report.tasks.every(task => task.realization === candidate),
        `CalibrationCandidateMismatch:${candidate}`);
      const elapsed = report.tasks.map(task => task.taskElapsedMilliseconds);
      assert(elapsed.every(value => Number.isFinite(value) && value >= 0),
        'CalibrationMissingTaskInterval');
      assert.equal(await fileHash(database), sourceSha256,
        'CalibrationSourceChanged');
      const observation = {round, candidate, taskElapsedMilliseconds: elapsed,
        executionMs: report.executionMs, warmMs: report.warmMs,
        cleanupMs: report.cleanupMs, selectionHash: report.selectionHash,
        outputCid: report.expectedRowsCid,
        taskRealizations: report.tasks.map(task => task.realization),
        terminalUsage: report.usage, storageUsage: report.storage};
      observations.push(observation);
      await writeFile(join(directory, `training-${round}-${candidate}.json`),
        JSON.stringify(observation, null, 2));
      console.log(JSON.stringify({event: 'training', round, candidate,
        elapsed, cleanupMs: report.cleanupMs}));
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
  const trainingBytes = JSON.stringify(training, null, 2);
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
  await writeFile(join(directory, 'profile.json'), JSON.stringify(profile, null, 2));
  console.log(JSON.stringify({event: 'finished', directory, caseId: fixture.id,
    trainingSha256, localTaskMilliseconds: profile.localTaskMilliseconds,
    nativeTaskMilliseconds: profile.nativeTaskMilliseconds}));
} catch (error) {
  await writeFile(join(directory, 'failure.json'), JSON.stringify({caseId: fixture.id,
    revision, sourceSha256, observations,
    error: {name: error.name, message: error.message, code: error.code}}, null, 2));
  throw error;
}
