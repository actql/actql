// New-profile diagnostic, separate from the old-contract paired acceptance.
// Every case uses the registered fixture, source generator and resource caps.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedMatrix} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';
import {runManagedProfileCase} from './managed-profile-case.mjs';

const root = new URL('../../../../../', import.meta.url);
const run = promisify(execFile);
const read = path => readFile(new URL(path, root), 'utf8');
const revision = (await run('git', ['rev-parse', 'HEAD'], {
  cwd: root,
})).stdout.trim();
const dirty = (await run('git', ['status', '--porcelain'], {
  cwd: root,
})).stdout.trim();
const requested = process.env.ACTQL_MANAGED_PROFILE_CASE;
const requestedWorkload = process.env.ACTQL_MANAGED_PROFILE_WORKLOAD;
if (requested !== undefined && requestedWorkload !== undefined) {
  throw new Error('ConflictingManagedProfileSelection');
}
const cases = requested !== undefined
  ? retainedMatrix().filter(fixture => fixture.id === requested)
  : requestedWorkload !== undefined
    ? retainedMatrix().filter(fixture => fixture.workload === requestedWorkload)
    : retainedMatrix();
if (!cases.length) throw new Error('UnknownManagedProfileCase');
const variantRecord = value => {
  if (value == null || typeof value !== 'object') return value;
  return Object.freeze({
    constructor: value.constructor?.name,
    tag: value.$tag,
    value: '_0' in value ? variantRecord(value._0) : undefined,
  });
};
const errorRecord = error => error == null ? undefined : Object.freeze({
  name: error?.name,
  constructor: error?.constructor?.name,
  tag: error?.$tag,
  code: error?.code,
  message: error?.message ?? String(error),
  cause: errorRecord(error?.cause),
  variant: variantRecord(error),
  details: Object.freeze({...error}),
  stack: error?.stack,
});

for (const target of [
  'connectors/duckdb/host_node',
  'connectors_builtin_node',
  'physical_strategy_example',
  'physical_task_manifest_example',
]) {
  await run('moon', ['build', '--target', 'js', '--release', `src/${target}`], {
    cwd: root,
  });
}

const contracts = {
  adoptedText: await read(
    'adapters/connectors/duckdb/node/contracts/adopted-relation.json',
  ),
  query: await read('spec/contracts/actql-query-acquisition.json'),
  evidence: await read('spec/contracts/actql-query-process-evidence.json'),
  receipts: await read('spec/contracts/actql-query-two-receipt.json'),
};
const directory = await mkdtemp(join(tmpdir(), 'actql-managed-profile-'));
const outcomes = [];
console.log(JSON.stringify({
  event: 'started',
  revision,
  dirty: dirty.length > 0,
  caseCount: cases.length,
  directory,
}));
try {
  for (const [index, fixture] of cases.entries()) {
    const database = join(directory, `source-${index}.duckdb`);
    let outcome;
    try {
      await run(process.execPath, [
        fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
        database,
        fixture.workload,
        fixture.layout,
        String(fixture.rows),
      ], {timeout: fixture.limits.timeoutMs});
      const report = await runManagedProfileCase(
        fixture,
        contracts,
        database,
        directory,
      );
      const counters = report.tasks.reduce((sum, task) => {
        const phase = task.phases ?? {};
        sum.inputPhysicalBytes += phase.inputPhysicalBytes ?? 0;
        sum.inputNativeScanBytes += phase.inputNativeScanBytes ?? 0;
        sum.inputIntegrityPasses += phase.inputIntegrityPasses ?? 0;
        sum.nativeFileImportCommands +=
          phase.nativeFileImportCommands ?? 0;
        sum.nativeFileScanCommands += phase.nativeFileScanCommands ?? 0;
        sum.directOutputCopies += phase.directOutputCopies ?? 0;
        sum.outputJsMaterializedCells +=
          phase.outputJsMaterializedCells ?? 0;
        sum.outputFrameReencodes += phase.outputFrameReencodes ?? 0;
        sum.logicalContentCidComputations +=
          phase.logicalContentCidComputations ?? 0;
        return sum;
      }, {
        inputPhysicalBytes: 0,
        inputNativeScanBytes: 0,
        inputIntegrityPasses: 0,
        nativeFileImportCommands: 0,
        nativeFileScanCommands: 0,
        directOutputCopies: 0,
        outputJsMaterializedCells: 0,
        outputFrameReencodes: 0,
        logicalContentCidComputations: 0,
      });
      outcome = Object.freeze({
        caseId: fixture.id,
        status: 'completed',
        counters,
        report,
      });
    } catch (error) {
      outcome = Object.freeze({
        caseId: fixture.id,
        status: 'failed',
        error: errorRecord(error),
      });
    } finally {
      await rm(database, {force: true});
    }
    outcomes.push(outcome);
    await writeFile(
      join(directory, `case-${index}.json`),
      JSON.stringify(outcome, (_, value) =>
        typeof value === 'bigint' ? value.toString() : value, 2),
    );
    console.log(JSON.stringify({
      event: 'case',
      index,
      caseId: fixture.id,
      status: outcome.status,
      milliseconds: outcome.report?.milliseconds,
      counters: outcome.counters,
      error: outcome.error?.message,
    }));
  }
  const summary = Object.freeze({
    revision,
    dirty: dirty.length > 0,
    profile: 'actql-managed-retained-execution/0.1',
    scope: requested !== undefined
      ? 'single-case-diagnostic'
      : requestedWorkload !== undefined
        ? `registered-workload:${requestedWorkload}`
        : 'registered-27',
    completed: outcomes.filter(value => value.status === 'completed').length,
    total: outcomes.length,
    outcomes,
  });
  await writeFile(
    join(directory, 'summary.json'),
    JSON.stringify(summary, (_, value) =>
      typeof value === 'bigint' ? value.toString() : value, 2),
  );
  console.log(JSON.stringify({
    event: 'finished',
    directory,
    completed: summary.completed,
    total: summary.total,
  }));
  if (summary.completed !== summary.total) process.exitCode = 1;
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
