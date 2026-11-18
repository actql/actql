// Nonzero-execution checks for the supported focused wrappers. See development.md.
import {spawnSync} from 'node:child_process';
import {realpathSync} from 'node:fs';
import {constants} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createCommandEvidence, redactCommandEvidence, redactCommandArguments} from './packed-query-evidence.mjs';

// This module has no command runner. Reject direct invocation so a mistaken
// verification command cannot report success without executing any tests.
let directInvocation = false;
const evaluating = process.execArgv.some(arg => /^(?:-e|-p|--eval|--print)(?:=|$)/u.test(arg));
if (process.argv[1] && !evaluating) {
  try { directInvocation = realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); }
  catch { /* Imported callers may use a non-path argument with node -e. */ }
}
if (directInvocation) {
  process.stderr.write('test-execution.mjs is an import-only library; use scripts/local-checks.mjs test or import runFocusedTests.\n');
  process.exitCode = 1;
}

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

// The approved Rust component and its syntax reader use locked library targets. Keep
// metadata-only, doctest, ignored-only and partial selections out of this gate.
export function cargoTestArguments(args) {
  if (!Array.isArray(args) || args.some(value => typeof value !== 'string'))
    throw new Error('Invalid Cargo test arguments');
  const delimiter = args.indexOf('--'), selected = new Set();
  if (delimiter < 0 || args.length !== delimiter + 2 || args.at(-1) !== '--nocapture')
    throw new Error('Cargo gate requires unfiltered --lib execution with -- --nocapture');
  for (let index = 0; index < delimiter; index++) {
    const option = args[index];
    if (selected.has(option)) throw new Error('Duplicate Cargo selection');
    selected.add(option);
    if (option === '--manifest-path') {
      if (!['packages/rust/Cargo.toml', 'packages/rust/tools/source-inventory/Cargo.toml']
        .includes(args[++index])) throw new Error('Unknown Cargo manifest');
    } else if (!['--locked', '--lib'].includes(option)) throw new Error('Unsupported Cargo selection');
  }
  if (!['--locked', '--lib', '--manifest-path'].every(option => selected.has(option)))
    throw new Error('Cargo gate requires the locked original library manifest');
  return ['test', ...args];
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
  } else if (kind === 'cargo') {
    const lines = output.split(/\r?\n/u);
    const summaries = lines.filter(line => line.startsWith('test result:'));
    const running = lines.filter(line => /^running [0-9]+ tests?$/u.test(line));
    if (summaries.length !== 1 || running.length !== 1) throw new Error('Missing or ambiguous Rust test execution');
    const match = /^test result: (ok|FAILED)\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored; ([0-9]+) measured; ([0-9]+) filtered out;(?: finished in .+)?$/u.exec(summaries[0]);
    if (!match) throw new Error('Malformed Rust test summary');
    const [passed, failed, ignored, measured, filtered] = match.slice(2).map(Number);
    const tests = Number(running[0].split(' ')[1]);
    if (![tests, passed, failed, ignored, measured, filtered].every(Number.isSafeInteger) ||
        tests !== passed + failed + ignored + measured || ignored || measured || filtered)
      throw new Error('Incomplete or inconsistent Rust library execution');
    const cases = lines.map(line => /^test (\S+)(?: - should panic)? \.\.\. (ok|FAILED|ignored)(?:, .*)?$/u.exec(line)).filter(Boolean);
    if (cases.length !== tests || new Set(cases.map(value => value[1])).size !== tests ||
        cases.filter(value => value[2] === 'ok').length !== passed ||
        cases.filter(value => value[2] === 'FAILED').length !== failed)
      throw new Error('Rust selected cases do not match execution totals');
    success = match[1] === 'ok' && failed === 0;
    groups.push({tests, passed, failed, cancelled: null, skipped: ignored, todo: null});
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
  const diagnostic = `${JSON.stringify(redactCommandArguments([command, ...args]))}: ${problem ?? 'executed'}; ` +
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
  const command = kind === 'node' ? process.execPath : kind === 'cargo' ? 'cargo' : 'moon';
  const selected = kind === 'node' ? nodeTestArguments(args)
    : kind === 'cargo' ? cargoTestArguments(args) : ['test', ...args];
  const {evidenceScratch = join(options.cwd ?? process.cwd(), '_build', 'focused-evidence'), expectedTests,
    requireAllPassed = false, ...spawnOptions} = options;
  if (expectedTests !== undefined && (!Number.isSafeInteger(expectedTests) || expectedTests < 1)) {
    throw new Error('Expected test count must be a positive safe integer');
  }
  if (typeof requireAllPassed !== 'boolean' || (requireAllPassed && kind !== 'node')) {
    throw new Error('Complete discovered-case execution requires Node tests');
  }
  const env = options.env ?? process.env;
  let evidence, evidenceError, result, checked;
  try {
    evidence = createCommandEvidence({scratch: evidenceScratch,
      cwd: options.cwd ?? process.cwd(), env, prefix: 'focused-test-'});
  } catch (error) { evidenceError = error; }
  const classify = result => {
    const checked = testExecutionResult(kind, command, selected, result);
    if (expectedTests !== undefined && checked.counts?.tests !== expectedTests) {
      return {...checked, status: checked.status || 1,
        diagnostic: checked.diagnostic + `; expected tests=${expectedTests}`};
    }
    if (requireAllPassed && checked.status === 0 &&
        checked.counts.tests !== checked.counts.passed) {
      return {...checked, status: 1,
        diagnostic: checked.diagnostic + '; not every discovered case passed'};
    }
    return checked;
  };
  if (evidence) {
    const capture = evidence.capture(command, selected,
      {killSignal: 'SIGKILL', ...spawnOptions, maxBuffer: 64 * 1024 * 1024}, classify);
    ({result, checked} = capture);
    evidenceError ??= capture.writeFailure;
    try { evidence.finish(checked.status === 0 ? 'passed' : 'failed'); }
    catch (error) { evidenceError ??= error; }
  } else {
    // A broken evidence destination must not replace the primary test result.
    result = spawnSync(command, selected, {killSignal: 'SIGKILL', ...spawnOptions,
      encoding: 'utf8', stdio: 'pipe', maxBuffer: 64 * 1024 * 1024});
    checked = classify(result);
  }
  process.stdout.write(redactCommandEvidence(result.stdout ?? '', env));
  process.stderr.write(redactCommandEvidence(result.stderr ?? '', env));
  (checked.status === 0 ? process.stdout : process.stderr).write(redactCommandEvidence(checked.diagnostic, env) + '\n');
  if (evidence) process.stderr.write(`Focused test evidence: ${evidence.directory}\n`);
  if (evidenceError) process.stderr.write('Focused test evidence write failed; primary test status: ' +
    checked.status + '; evidence is incomplete\n');
  return checked.status || (evidenceError ? 1 : 0);
}
