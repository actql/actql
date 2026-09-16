// Diagnostic coverage runner, not formal alternating-pair acceptance. Each
// case gets its own source generated from the registered fixture in a separate
// process. Persist each outcome before moving on, including failed cases.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedMatrix} from '../../../benchmarks/retained-results/fixtures.mjs';
import {runRetainedComparator} from './retained-comparator.mjs';

const root = new URL('../../../', import.meta.url);
const read = path => readFile(new URL(path, root), 'utf8');
const run = promisify(execFile);
const revision = (await run('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout.trim();
const dirty = (await run('git', ['status', '--porcelain'], {cwd: root})).stdout;
const sourceStamp = async () => {
  const hash = createHash('sha256');
  hash.update((await run('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout);
  hash.update((await run('git', ['diff', 'HEAD', '--binary'], {cwd: root, maxBuffer: 16777216})).stdout);
  const names = (await run('git', ['ls-files', '--others', '--exclude-standard', '-z'], {cwd: root})).stdout;
  for (const name of names.split('\0').filter(Boolean).sort()) {
    hash.update(name + '\0'); hash.update(await read(name)); hash.update('\0');
  }
  return hash.digest('hex');
};
const initialSourceStamp = await sourceStamp();
const registration = JSON.parse(await read('benchmarks/retained-results/direct-path-registration.json'));
const contracts = {
  adoptedText: await read('adapters/duckdb-node/contracts/adopted-relation.json'),
  query: await read('spec/contracts/actql-query-acquisition.json'),
  evidence: await read('spec/contracts/actql-query-process-evidence.json'),
  receipts: await read('spec/contracts/actql-query-two-receipt.json'),
};
const directory = await mkdtemp(join(tmpdir(), 'actql-direct-matrix-'));
console.log(JSON.stringify({event: 'started', directory, revision, dirty}));
const outcomes = [];
for (const [index, fixture] of retainedMatrix().entries()) {
  const database = join(directory, `source-${index}.duckdb`);
  let outcome;
  try {
    if (await sourceStamp() !== initialSourceStamp) throw Error('DiagnosticSourcesChanged');
    await run(process.execPath, [fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
    {timeout: fixture.limits.timeoutMs});
    const report = await runRetainedComparator(fixture, contracts, database, directory,
      {resident: true});
    if (await sourceStamp() !== initialSourceStamp) throw Error('DiagnosticSourcesChanged');
    const inputs = report.tasks.flatMap(task => task.phases?.inputs ?? []);
    outcome = {caseId: fixture.id, large: registration.largeCaseIds.includes(fixture.id),
      status: 'completed', nativeFileInputs: inputs.length,
      allInputsNative: inputs.length > 0 && inputs.every(input =>
        input.representation === 'verified-file-native-read' && input.parameterInsertRows === 0),
      calibratedSelection: false, performanceAcceptance: 'not-assessed', report};
  } catch (error) {
    outcome = {caseId: fixture.id, large: registration.largeCaseIds.includes(fixture.id),
      status: 'failed', error: {name: error.name, code: error.code, message: error.message,
        stack: error.stack}, performanceAcceptance: 'not-assessed'};
  }
  await writeFile(join(directory, `case-${index}.json`), JSON.stringify(outcome, null, 2));
  outcomes.push(outcome);
  console.log(JSON.stringify({event: 'case', index, caseId: fixture.id, status: outcome.status,
    allInputsNative: outcome.allInputsNative, executionMs: outcome.report?.executionMs,
    error: outcome.error?.message}));
  // Only this runner's generated source; product holdings are released by the
  // timing leg, not deleted here to disguise an unconfirmed cleanup.
  await rm(database, {force: true});
}
await writeFile(join(directory, 'summary.json'), JSON.stringify({revision, dirty, initialSourceStamp,
  scope: 'diagnostic-not-formal-acceptance', selection: {resident: true, nativeMilliseconds: '1'},
  initialPlacement: 'separate fixture database; no preexisting resident copies',
  calibration: 'existing example estimates, not yet evidence-calibrated',
  completed: outcomes.filter(outcome => outcome.status === 'completed').length,
  total: outcomes.length, outcomes}, null, 2));
console.log(JSON.stringify({event: 'finished', directory,
  completed: outcomes.filter(outcome => outcome.status === 'completed').length, total: outcomes.length}));
if (outcomes.some(outcome => outcome.status !== 'completed')) process.exitCode = 1;
