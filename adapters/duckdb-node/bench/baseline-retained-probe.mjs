// Capability diagnostic for an unchanged, separately built baseline checkout.
// All attempted cases are reported, including unsupported limits. This is not
// paired timing acceptance or a substitute baseline with new runtime behavior.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {retainedMatrix} from '../../../benchmarks/retained-results/fixtures.mjs';
import {benchmarkEnvironment} from '../../../benchmarks/retained-results/environment.mjs';
import {selectReadinessCases} from '../../../benchmarks/retained-results/selection.mjs';
import {baselinePublicEntry} from './baseline-public-entry.mjs';

const baselineRoot = process.env.ACTQL_RETAINED_BASELINE_ROOT;
if (!baselineRoot) throw Error('ACTQL_RETAINED_BASELINE_ROOT must name an independently verified baseline build');
const profile = process.env.ACTQL_BASELINE_PROFILE ?? 'unchanged-example';
if (!['unchanged-example', 'received-row-envelope'].includes(profile)) throw Error('InvalidBaselineProfile');
const runExample = profile === 'received-row-envelope' ? await baselinePublicEntry(baselineRoot)
  : (await import(pathToFileURL(resolve(baselineRoot,
    'adapters/duckdb-node/examples/physical-strategy.mjs')).href)).runExample;
const {cases, scope} = selectReadinessCases(retainedMatrix(), process.env.ACTQL_RETAINED_CASE);
console.log(JSON.stringify({kind: 'baseline-capability-diagnostic', scope, profile,
  baselineRoot: resolve(baselineRoot), caseCount: cases.length, performanceAcceptance: false,
  provenance: 'caller must verify the source tree and build against experiment.baselineRevision'}));
let incomplete = 0;
for (const fixture of cases) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-baseline-case-'));
  let result, error, failed = false;
  const cleanupErrors = [];
  const environment = benchmarkEnvironment(fixture);
  const database = join(directory, 'source.duckdb');
  try {
    await promisify(execFile)(process.execPath,
      [fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)), database,
        fixture.workload, fixture.layout, String(fixture.rows)],
      {timeout: fixture.limits.timeoutMs, maxBuffer: 65536});
    const program = join(directory, 'program.json');
    const environmentFile = join(directory, 'environment.json');
    const parameters = join(directory, 'parameters.json');
    await Promise.all([
      writeFile(program, JSON.stringify(fixture.program())),
      writeFile(environmentFile, environment.text),
      writeFile(parameters, JSON.stringify({minimum: fixture.minimum})),
    ]);
    result = await runExample({database, program, environment: environmentFile,
      environmentCid: environment.cid, parameters, nativeMilliseconds: '1',
      receivedRows: Math.max(100, fixture.fields.length + fixture.rows + fixture.cardinalities.capture,
        3 * fixture.limits.intermediateRows),
      signal: AbortSignal.timeout(fixture.limits.timeoutMs)});
    assert.equal(result.report.status, 'host-tasks-completed');
    assert.equal(result.report.internal_output_cids.at(-1)?.cid, fixture.identity().rowsCid);
  } catch (cause) { failed = true; error = cause; }
  finally {
    for (const release of [() => result?.close(),
      () => result?.execution?.cleanup(),
      () => result?.capture?.cleanupHandle?.retry(),
      () => error?.cleanupHandle?.retry()]) {
      try { await release(); } catch (cause) { cleanupErrors.push(String(cause)); }
    }
    const pending = result?.execution?.cleanupPending() ||
      result?.capture?.cleanupHandle?.status().pending || error?.cleanupHandle?.status().pending;
    if (pending) cleanupErrors.push('CleanupStillPending');
    // Do not delete a fixture that still belongs to unconfirmed execution.
    if (!cleanupErrors.length) await rm(directory, {recursive: true, force: true});
  }
  const status = failed || cleanupErrors.length ? 'incomplete' : 'verified';
  if (status === 'incomplete') incomplete++;
  console.log(JSON.stringify({caseId: fixture.id, status,
    ...(failed ? {error: String(error), cause: error?.cause} : {}),
    ...(result ? {taskStatus: result.report.status, failure: result.report.failure,
      completedTasks: result.report.completed.length} : {}),
    ...(cleanupErrors.length ? {cleanupErrors, retainedDiagnosticDirectory: directory} : {})}));
}
console.log(JSON.stringify({kind: 'baseline-capability-summary', profile,
  attempted: cases.length, verified: cases.length - incomplete, incomplete}));
if (incomplete) process.exitCode = 1;
