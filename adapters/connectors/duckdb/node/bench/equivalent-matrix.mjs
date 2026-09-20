// All registered cases, fresh child per case. Diagnostic only: outstanding
// comparator obligations exclude these reports from formal paired acceptance.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedMatrix} from '../../../../../benchmarks/retained-results/fixtures.mjs';

const root = new URL('../../../../../', import.meta.url), run = promisify(execFile);
const git = async args => (await run('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
if (await git(['status', '--porcelain'])) throw Error('DiagnosticRequiresCleanSource');
const unchanged = async () => {
  if (await git(['rev-parse', 'HEAD']) !== revision || await git(['status', '--porcelain'])) {
    throw Error('DiagnosticSourcesChanged');
  }
};
const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-matrix-'));
console.log(JSON.stringify({event: 'started', revision, directory}));
const outcomes = [];
for (const [index, fixture] of retainedMatrix().entries()) {
  await unchanged();
  const database = join(directory, `source-${index}.duckdb`);
  let outcome;
  try {
    await run(process.execPath, [fileURLToPath(new URL('./create-retained-source.mjs', import.meta.url)),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
    {timeout: fixture.limits.timeoutMs});
    const start = performance.now();
    const args = [fileURLToPath(new URL('./equivalent-case.mjs', import.meta.url)),
      database, directory, fixture.workload, fixture.layout, String(fixture.rows)];
    try {
      const result = await run(process.execPath, args, {
        timeout: fixture.limits.timeoutMs + fixture.limits.cleanupTimeoutMs, maxBuffer: 1048576,
      });
      outcome = {...JSON.parse(result.stdout), processCycleMs: performance.now() - start};
    } catch (error) {
      // Preserve typed child diagnostics when present, including cleanup causes.
      let child;
      try { child = JSON.parse(error.stdout); } catch {}
      outcome = {caseId: fixture.id, status: 'failed', acceptanceEligible: false,
        child, error: {message: error.message, code: error.code, signal: error.signal,
          killed: error.killed, stderr: error.stderr}, processCycleMs: performance.now() - start};
    }
  } catch (error) {
    outcome = {caseId: fixture.id, status: 'failed', acceptanceEligible: false,
      error: {message: error.message, phase: 'source-setup'}};
  }
  await writeFile(join(directory, `case-${index}.json`), JSON.stringify(outcome, null, 2));
  outcomes.push(outcome);
  console.log(JSON.stringify({event: 'case', index, caseId: fixture.id,
    status: outcome.status, executionMs: outcome.executionMs, error: outcome.child?.error ?? outcome.error}));
  // Delete only this runner's generated source after successful child teardown.
  // Failed cases and their possible holdings remain available for inspection.
  if (outcome.status === 'diagnostic-completed') await rm(database);
  await unchanged();
}
const summary = {revision, acceptanceEligible: false, scope: 'independent-prototype-diagnostic',
  completed: outcomes.filter(value => value.status === 'diagnostic-completed').length,
  total: outcomes.length, outcomes};
await writeFile(join(directory, 'summary.json'), JSON.stringify(summary, null, 2));
console.log(JSON.stringify({event: 'finished', directory, completed: summary.completed, total: summary.total}));
if (summary.completed !== summary.total) process.exitCode = 1;
