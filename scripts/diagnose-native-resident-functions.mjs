// Failure-only, fresh-state diagnostic. This does not replace the failed
// Native case, its 60-second assertions, or the preparation's original checks.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const sourceUrl = new URL('./test-native-resident-site.mjs', import.meta.url).href;
const sourceSha = '17125265da686474b09ab73b95f8af09b3b904efee12bfcd27408c968b77bdba';
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

function executeChild(output) {
  const privateDirectory = mkdtempSync(join(tmpdir(), 'actql-native-functions-'));
  const report = join(privateDirectory, 'control.json');
  let result;
  try { result = runFunctionDiagnosticCase(report); }
  catch { result = {status: 1}; }
  let value;
  try {
    const wire = readFileSync(report);
    assert(wire.length <= 65536);
    value = JSON.parse(wire.toString('utf8'));
  } catch { /* Closed unavailable metadata; never forward raw exceptions. */ }
  mkdirSync(dirname(output), {recursive: true});
  writeFileSync(output, JSON.stringify(functionDiagnosticSummary(result, value), null, 2) + '\n',
    {flag: 'wx', mode: 0o600});
  return result.error?.code === 'ETIMEDOUT' ? 124 : result.status ?? 1;
}

async function main() {
  assert.equal(process.platform, 'linux');
  assert.equal(process.arch, 'x64');
  assert(['--output', '--child'].includes(process.argv[2]) && process.argv.length === 4);
  const output = resolve(process.argv[3]);
  if (process.argv[2] === '--child') return executeChild(output);
  // Include cleanup in the finite 300-second diagnostic envelope. The real
  // fixture retains its existing watchdog and every original assertion.
  return runLocalCheck({root, heavy: false, timeoutSeconds: 295, graceSeconds: 5,
    steps: [{name: 'Failure-only Native consumer function availability', command: process.execPath,
      args: [fileURLToPath(import.meta.url), '--child', output]}]});
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().then(code => { process.exitCode = code; }).catch(() => {
    console.error('NativeFunctionDiagnosticUnavailable'); process.exitCode = 1;
  });
}
