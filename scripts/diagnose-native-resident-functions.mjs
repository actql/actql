// Failure-only, fresh-state diagnostic. This does not replace the failed
// Native case, its 60-second assertions, or the preparation's original checks.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {linkSync, mkdirSync, mkdtempSync, readFileSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const sourceUrl = new URL('./test-native-resident-site.mjs', import.meta.url).href;
const sourceSha = '04d451edbc6041f6452d7f0ae424ae355a9fee7cda7a6512fa804900ca00d890';
const conditions = new Set(['debugger-unavailable', 'permission-denied',
  'debugger-platform-unsupported', 'trace-unavailable', 'registers-unavailable',
  'no-stack', 'stage-not-observed', 'report-unavailable']);

export function rewriteResidentControlSpawn(source, {python, wrapper, report}) {
  assert.equal(createHash('sha256').update(source).digest('hex'), sourceSha,
    'Native diagnostic Source hash differs');
  const original = "const child = spawn(executable, ['run', ...configured,";
  assert.equal(source.split(original).length, 2, 'Native diagnostic spawn differs');
  return source.replace(original, `const child = spawn(${JSON.stringify(python)}, ` +
    `[${JSON.stringify(wrapper)}, ${JSON.stringify(report)}, executable, 'run', ...configured,`);
}

export function functionDiagnosticSummary(result, report) {
  const selected = report && typeof report === 'object' ? report : {};
  const functions = Array.isArray(selected.functions) ? selected.functions
    .filter(name => typeof name === 'string' && /^[A-Za-z_][A-Za-z_0-9:.$~]{0,179}$/u.test(name))
    .slice(0, 64) : [];
  return {version: 1, diagnosticOnly: true,
    sampleTarget: selected.sampleTarget === 'holder-descendant'
      ? 'holder-descendant' : 'unrecorded',
    caseExit: Number.isInteger(result.status) ? result.status : null,
    caseSignal: ['SIGTERM', 'SIGKILL', 'SIGABRT', 'SIGSEGV', 'SIGINT'].includes(result.signal)
      ? result.signal : null,
    timedOut: result.error?.code === 'ETIMEDOUT',
    consumerExecutorEntered: selected.consumerExecutorEntered === true,
    sampleRequested: selected.sampleRequested === true,
    functions,
    conditions: Array.isArray(selected.conditions) ? [...new Set(selected.conditions
      .filter(value => conditions.has(value)))] : ['report-unavailable']};
}

export function runFunctionDiagnosticCase(report, {execute = spawnSync, env = process.env} = {}) {
  assert(env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION && env.ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT,
    'Same-job Native preparation is required; there is no producer fallback');
  const data = {sourceUrl, python: '/usr/bin/python3',
    wrapper: fileURLToPath(new URL('./fixtures/native-resident-function-debugger.py', import.meta.url)), report};
  const registration = `import {register} from 'node:module';register(${JSON.stringify(
    new URL('./fixtures/native-resident-function-loader.mjs', import.meta.url).href)},` +
    `{data:${JSON.stringify(data)}});`;
  // GDB chatter and the original fixture's private errors never enter CI logs
  // or the uploaded JSON. The wrapper still forwards target stdout to its
  // original caller, so the Coordinator protocol is not replaced by a mock.
  return execute(process.execPath, ['--import', 'data:text/javascript,' + encodeURIComponent(registration),
    fileURLToPath(sourceUrl), '--effect-computation-only'], {
    cwd: root, env, stdio: 'ignore', timeout: 285000, killSignal: 'SIGTERM'});
}

function readReport(path) {
  try {
    const wire = readFileSync(path);
    assert(wire.length <= 65536);
    return JSON.parse(wire.toString('utf8'));
  } catch { /* Closed unavailable metadata; never forward raw exceptions. */ }
}

export function publishFunctionDiagnostic(output, report, supervisorExit) {
  const result = readReport(report + '.case') ?? {status: null};
  if (supervisorExit === 124) result.error = {code: 'ETIMEDOUT'};
  const summary = {...functionDiagnosticSummary(result, readReport(report)), supervisorExit};
  mkdirSync(dirname(output), {recursive: true});
  const temporary = output + '.tmp';
  writeFileSync(temporary, JSON.stringify(summary, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  // Publish a complete file without overwriting a previous diagnostic.
  linkSync(temporary, output);
  unlinkSync(temporary);
  return summary;
}

function executeChild(report) {
  let result;
  try { result = runFunctionDiagnosticCase(report); }
  catch { result = {status: 1}; }
  // The outer parent owns final publication. If this child is killed, the
  // already published Python snapshot still survives; caseExit stays unknown.
  writeFileSync(report + '.case', JSON.stringify({status: result.status ?? null,
    signal: result.signal ?? null, error: result.error?.code === 'ETIMEDOUT'
      ? {code: 'ETIMEDOUT'} : undefined}), {flag: 'wx', mode: 0o600});
  return result.error?.code === 'ETIMEDOUT' ? 124 : result.status ?? 1;
}

async function main() {
  assert.equal(process.platform, 'linux');
  assert.equal(process.arch, 'x64');
  assert(['--output', '--child'].includes(process.argv[2]) && process.argv.length === 4);
  const output = resolve(process.argv[3]);
  if (process.argv[2] === '--child') return executeChild(output);
  const report = join(mkdtempSync(join(tmpdir(), 'actql-native-functions-')), 'control.json');
  // Include cleanup in the finite 300-second diagnostic envelope. The real
  // fixture retains its existing watchdog and every original assertion.
  let code = 1;
  try {
    code = await runLocalCheck({root, heavy: false, timeoutSeconds: 295, graceSeconds: 5,
      steps: [{name: 'Failure-only Native consumer function availability', command: process.execPath,
        args: [fileURLToPath(import.meta.url), '--child', report]}]});
  } finally {
    publishFunctionDiagnostic(output, report, code);
  }
  return code;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().then(code => { process.exitCode = code; }).catch(() => {
    console.error('NativeFunctionDiagnosticUnavailable'); process.exitCode = 1;
  });
}
