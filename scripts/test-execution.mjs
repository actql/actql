// Nonzero-execution checks for the supported focused wrappers. See development.md.
import {spawnSync} from 'node:child_process';
import {constants} from 'node:os';

const fields = ['tests', 'passed', 'failed', 'cancelled', 'skipped', 'todo'];
const empty = () => Object.fromEntries(fields.map(field => [field, 0]));
const marker = 'ACTQL_TEST_SUMMARY ';

export function nodeTestArguments(args) {
  if (args.some(arg => /^--(?:test-reporter(?:-destination)?|test-isolation|watch|test-only)(?:=|$)/u.test(arg))) {
    throw new Error('Focused verification owns the reporter and requires normal process-isolated test execution');
  }
  return ['--test', '--test-reporter=' + new URL('./test-execution-reporter.mjs', import.meta.url).href,
    ...args.filter(arg => arg !== '--test')];
}

export function parseTestExecution(kind, output) {
  const groups = [];
  let success = true;
  if (kind === 'node') {
    let final = 0;
    const files = new Set();
    for (const line of output.split(/\r?\n/u).filter(line => line.startsWith(marker))) {
      const summary = JSON.parse(line.slice(marker.length));
      const counts = summary?.counts;
      if (typeof summary?.success !== 'boolean' || !counts ||
          fields.some(field => !Number.isSafeInteger(counts[field]) || counts[field] < 0) ||
          counts.tests !== fields.slice(1).reduce((sum, field) => sum + counts[field], 0)) {
        throw new Error('Malformed Node test summary');
      }
      success &&= summary.success;
      if (summary.file === undefined) {
        final++;
      } else {
        if (typeof summary.file !== 'string' || files.has(summary.file)) {
          throw new Error('Malformed or duplicate Node file summary');
        }
        files.add(summary.file);
        groups.push(Object.fromEntries(fields.map(field => [field, counts[field]])));
      }
    }
    if (final !== 1 || groups.length === 0) throw new Error('Missing or duplicate Node test summaries');
  } else if (kind === 'moon') {
    // Pinned moon 0.1.20260904: --output-json only structures diagnostics,
    // not test totals. Omitted/skipped cases are not included in these totals.
    for (const line of output.split(/\r?\n/u).filter(line => line.startsWith('Total tests:'))) {
      const match = /^Total tests: (\d+), passed: (\d+), failed: (\d+)\.$/u.exec(line);
      if (!match) throw new Error('Malformed MoonBit test summary');
      const [tests, passed, failed] = match.slice(1).map(Number);
      if (![tests, passed, failed].every(Number.isSafeInteger) || tests !== passed + failed) {
        throw new Error('Inconsistent MoonBit test counts');
      }
      groups.push({tests, passed, failed, cancelled: null, skipped: null, todo: null});
    }
    if (groups.length === 0) throw new Error('Missing MoonBit test summary');
  } else {
    throw new Error(`Unknown test kind: ${kind}`);
  }
  const counts = empty();
  for (const group of groups) for (const field of fields) {
    counts[field] = group[field] === null ? null : counts[field] + group[field];
  }
  return {counts, groups, success};
}

export function testExecutionResult(kind, command, args, result) {
  let evidence;
  let problem;
  try { evidence = parseTestExecution(kind, result.stdout ?? ''); }
  catch (error) { problem = error.message; }
  const signalStatus = result.signal ? 128 + (constants.signals[result.signal] ?? 0) : 1;
  // A failed process never becomes successful because its output looks green.
  let status = result.status ?? signalStatus;
  if (result.error || result.signal || status !== 0) {
    if (status === 0) status = 1;
    problem = `process failed (${result.error?.code ?? result.signal ?? status})` +
      (problem ? `; ${problem}` : '');
  } else if (!problem) {
    if (!evidence.success || evidence.counts.failed > 0 || evidence.counts.cancelled > 0) {
      problem = 'failed or cancelled test cases';
    } else if (evidence.counts.passed === 0 ||
        (kind === 'moon' && evidence.groups.some(group => group.passed === 0))) {
      problem = 'no successfully executed test cases';
    }
  }
  if (problem && status === 0) status = 1;
  const counts = evidence?.counts ?? null;
  const diagnostic = `${JSON.stringify([command, ...args])}: ${problem ?? 'executed'}; ` +
    `counts=${JSON.stringify(counts)}${counts === null ? ' (summary unavailable)' : ''}`;
  return {status, counts, diagnostic};
}

export function assertTestExecution(kind, command, args, result) {
  const checked = testExecutionResult(kind, command, args, result);
  if (checked.status !== 0) {
    throw Object.assign(new Error(`${checked.diagnostic}\n${result.stdout ?? ''}${result.stderr ?? ''}`), {status: checked.status, signal: result.signal});
  }
  return checked;
}

export function runFocusedTests(kind, args, options = {}) {
  const command = kind === 'node' ? process.execPath : 'moon';
  const selected = kind === 'node' ? nodeTestArguments(args) : ['test', ...args];
  const result = spawnSync(command, selected, {...options, encoding: 'utf8',
    stdio: 'pipe', maxBuffer: 64 * 1024 * 1024});
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  const checked = testExecutionResult(kind, command, selected, result);
  (checked.status === 0 ? process.stdout : process.stderr).write(checked.diagnostic + '\n');
  return checked.status;
}
