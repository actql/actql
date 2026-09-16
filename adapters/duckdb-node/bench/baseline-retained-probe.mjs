// Capability diagnostic for an unchanged, separately built baseline checkout.
// All attempted cases are reported, including unsupported limits. This is not
// paired timing acceptance or a substitute baseline with new runtime behavior.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify, inspect} from 'node:util';
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
if (!['unchanged-example', 'received-row-envelope', 'received-transport-envelope', 'small-join-envelope'].includes(profile)) throw Error('InvalidBaselineProfile');
const runExample = profile !== 'unchanged-example' ? await baselinePublicEntry(baselineRoot)
  : (await import(pathToFileURL(resolve(baselineRoot,
    'adapters/duckdb-node/examples/physical-strategy.mjs')).href)).runExample;
const {cases, scope} = selectReadinessCases(retainedMatrix(), process.env.ACTQL_RETAINED_CASE);
if (profile === 'small-join-envelope' && (cases.length !== 1 ||
    cases[0].id !== 'fixed-join-count-shrinking-intermediate/narrow/100')) {
  throw Error('UnsupportedBaselineSmallJoinCase');
}
console.log(JSON.stringify({kind: 'baseline-capability-diagnostic', scope, profile,
  baselineRoot: resolve(baselineRoot), caseCount: cases.length, performanceAcceptance: false,
  provenance: 'caller must verify the source tree and build against experiment.baselineRevision'}));
let incomplete = 0;
for (const fixture of cases) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-baseline-case-'));
  let result, error, failed = false, executionMs, cleanupMs;
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
    const expected = fixture.identity(); // Independent oracle is not timed work.
    const started = performance.now();
    result = await runExample({database, program, environment: environmentFile,
      environmentCid: environment.cid, parameters, nativeMilliseconds: '1',
      smallJoin: profile === 'small-join-envelope',
      receivedRows: Math.max(100, fixture.fields.length + fixture.rows + fixture.cardinalities.capture,
        3 * fixture.limits.intermediateRows),
      ...(profile === 'received-transport-envelope' ? {
        receivedCells: Math.max(1000, fixture.fields.length *
          (fixture.fields.length + fixture.rows + 3 * fixture.limits.intermediateRows)),
        receivedBytes: Math.max(100000, fixture.limits.representationBytes * 4),
        receivedColumns: fixture.fields.length,
      } : {}),
      signal: AbortSignal.timeout(fixture.limits.timeoutMs)});
    executionMs = performance.now() - started;
    assert.equal(result.report.status, 'host-tasks-completed');
    assert.equal(result.report.internal_output_cids.at(-1)?.cid, expected.rowsCid);
  } catch (cause) { failed = true; error = cause; }
  finally {
    const cleanupStarted = performance.now();
    for (const release of [() => result?.close(),
      () => result?.execution?.cleanup(),
      () => result?.capture?.cleanupHandle?.retry(),
      () => error?.cleanupHandle?.retry()]) {
      try { await release(); } catch (cause) { cleanupErrors.push(String(cause)); }
    }
    const pending = result?.execution?.cleanupPending() ||
      result?.capture?.cleanupHandle?.status().pending || error?.cleanupHandle?.status().pending;
    if (pending) cleanupErrors.push('CleanupStillPending');
    cleanupMs = performance.now() - cleanupStarted;
    // Do not delete a fixture that still belongs to unconfirmed execution.
    if (!cleanupErrors.length) await rm(directory, {recursive: true, force: true});
  }
  const status = failed || cleanupErrors.length ? 'incomplete' : 'verified';
  if (status === 'incomplete') incomplete++;
  console.log(JSON.stringify({caseId: fixture.id, status,
    ...(status === 'verified' ? {timing: {
      scope: 'baseline-public-entry-diagnostic', executionMs, cleanupMs,
      includes: ['public-entry-preparation', 'acquisition', 'validation', 'Compute',
        'required-identities', 'memory-holding'],
      excludes: ['build', 'source-setup', 'independent-oracle', 'fixture-file-removal'],
      pairedAcceptance: false,
    }} : {}),
    ...(failed ? {error: String(error), cause: inspect(error?.cause, {depth: 8, breakLength: Infinity})} : {}),
    ...(result ? {taskStatus: result.report.status, failure: result.report.failure,
      completedTasks: result.report.completed.length,
      ...(result.report.status !== 'host-tasks-completed' ? {
        taskFailure: inspect(result.execution?.failure, {depth: 12, breakLength: Infinity}),
      } : {})} : {}),
    ...(cleanupErrors.length ? {cleanupErrors, retainedDiagnosticDirectory: directory} : {})}));
}
console.log(JSON.stringify({kind: 'baseline-capability-summary', profile,
  attempted: cases.length, verified: cases.length - incomplete, incomplete}));
if (incomplete) process.exitCode = 1;
