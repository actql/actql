// One fresh, manual-only Linux x64 channel diagnostic. Original Effect fixture
// assertions, deadlines, installation and Native arguments remain unchanged.
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
const sourceSha = '94024d12359295efbc927b77666304ed5d13f05fa6bf3482f557cfeb39169f63';
const conditions = new Set(['debugger-unavailable', 'registers-unavailable', 'return-unavailable',
  'frame-bounds-unavailable', 'requested-kind-unavailable', 'channel-not-observed', 'report-unavailable']);
const kinds = new Set(['consumer', 'effect-review', 'release', 'retained-plan', 'retained-transfer',
  'retained-current', 'effect-current', 'effect-resume', 'other', 'unobserved']);
const finite = value => Number.isSafeInteger(value) && value >= 0 && value <= 16777216;

export function rewriteChannelControlSpawn(source, {python, wrapper, report}) {
  assert.equal(createHash('sha256').update(source).digest('hex'), sourceSha, 'Native channel diagnostic Source differs');
  const anchor = "const child = spawn(executable, ['run', ...configured,";
  assert.equal(source.split(anchor).length, 2, 'Native channel diagnostic spawn differs');
  return source.replace(anchor, `const child = spawn(${JSON.stringify(python)}, ` +
    `[${JSON.stringify(wrapper)}, ${JSON.stringify(report)}, executable, 'run', ...configured,`);
}

function observation(value) {
  if (!value || !kinds.has(value.selectedKind) || !kinds.has(value.requestedKind) ||
      !finite(value.frameBytes) || value.frameBytes < 1 || !finite(value.offset) || value.offset >= value.frameBytes ||
      value.childWait !== 'running' || !['not-entered', 'failure', 'unavailable', 'empty', 'busy'].includes(value.ioctl) ||
      !['not-entered', 'nonprogress', 'progress'].includes(value.write) ||
      !['busy', 'failure', 'progress'].includes(value.channelReturn)) return;
  return {selectedKind: value.selectedKind, requestedKind: value.requestedKind,
    frameBytes: value.frameBytes, offset: value.offset, childWait: 'running', ioctl: value.ioctl,
    unreadBytes: finite(value.unreadBytes) ? value.unreadBytes : null, write: value.write,
    writeBytes: finite(value.writeBytes) ? value.writeBytes : null, channelReturn: value.channelReturn,
    returnedBytes: finite(value.returnedBytes) ? value.returnedBytes : null,
    consumerExecutorEntered: value.consumerExecutorEntered === true};
}

export function channelDiagnosticSummary(result, report) {
  const value = report && typeof report === 'object' ? report : {};
  const counts = (record, allowed) => Object.fromEntries(Object.entries(record ?? {})
    .filter(([key, count]) => allowed.has(key) && finite(count)));
  return {version: 1, diagnosticOnly: true, sampleTarget: 'original-control',
    caseExit: Number.isInteger(result.status) ? result.status : null,
    caseSignal: ['SIGTERM', 'SIGKILL', 'SIGABRT', 'SIGSEGV', 'SIGINT'].includes(result.signal) ? result.signal : null,
    timedOut: result.error?.code === 'ETIMEDOUT',
    consumerExecutorEntered: value.consumerExecutorEntered === true,
    channelCalls: finite(value.channelCalls) ? value.channelCalls : 0,
    droppedGroups: finite(value.droppedGroups) ? value.droppedGroups : 0,
    observations: Array.isArray(value.observations) ? value.observations.slice(0, 64).flatMap(group => {
      const selected = observation(group?.observation);
      return selected && finite(group.count) && group.count > 0 ? [{observation: selected, count: group.count}] : [];
    }) : [],
    last: observation(value.last) ?? null,
    waitCounts: counts(value.waitCounts, new Set(['running', 'error', 'exited', 'signaled'])),
    sendReturns: counts(value.sendReturns, new Set([...kinds].flatMap(kind =>
      ['true', 'false', 'unavailable'].map(status => kind + '/' + status)))),
    conditions: Array.isArray(value.conditions) ? [...new Set(value.conditions.filter(item => conditions.has(item)))]
      : ['report-unavailable']};
}

export function runChannelDiagnosticCase(report, {execute = spawnSync, env = process.env} = {}) {
  assert(env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION && env.ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT,
    'Same-job Native preparation is required; no producer fallback');
  const data = {sourceUrl, python: '/usr/bin/python3',
    wrapper: fileURLToPath(new URL('./fixtures/native-resident-channel-debugger.py', import.meta.url)), report};
  const registration = `import {register} from 'node:module';register(${JSON.stringify(
    new URL('./fixtures/native-resident-channel-loader.mjs', import.meta.url).href)},` +
    `{data:${JSON.stringify(data)}});`;
  return execute(process.execPath, ['--import', 'data:text/javascript,' + encodeURIComponent(registration),
    fileURLToPath(sourceUrl), '--effect-computation-only'],
  {cwd: root, env, stdio: 'ignore', timeout: 285000, killSignal: 'SIGTERM'});
}

function readReport(path) {
  try { const wire = readFileSync(path); assert(wire.length <= 65536); return JSON.parse(wire.toString('utf8')); }
  catch { /* Original private exception text is not diagnostic DATA. */ }
}

export function publishChannelDiagnostic(output, report, supervisorExit) {
  const result = readReport(report + '.case') ?? {status: null};
  if (supervisorExit === 124) result.error = {code: 'ETIMEDOUT'};
  const summary = {...channelDiagnosticSummary(result, readReport(report)), supervisorExit};
  mkdirSync(dirname(output), {recursive: true});
  const temporary = output + '.tmp';
  writeFileSync(temporary, JSON.stringify(summary, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  linkSync(temporary, output); unlinkSync(temporary);
  return summary;
}

async function main() {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  assert(['--output', '--child'].includes(process.argv[2]) && process.argv.length === 4);
  const output = resolve(process.argv[3]);
  if (process.argv[2] === '--child') {
    let result;
    try { result = runChannelDiagnosticCase(output); } catch { result = {status: 1}; }
    writeFileSync(output + '.case', JSON.stringify({status: result.status ?? null,
      signal: result.signal ?? null, error: result.error?.code === 'ETIMEDOUT' ? {code: 'ETIMEDOUT'} : undefined}),
    {flag: 'wx', mode: 0o600});
    return result.error?.code === 'ETIMEDOUT' ? 124 : result.status ?? 1;
  }
  const report = join(mkdtempSync(join(tmpdir(), 'actql-native-channel-')), 'control.json');
  let code = 1;
  try { code = await runLocalCheck({root, heavy: false, timeoutSeconds: 295, graceSeconds: 5,
    steps: [{name: 'ONE fresh Native Effect channel diagnostic', command: process.execPath,
      args: [fileURLToPath(import.meta.url), '--child', report]}]}); }
  finally { publishChannelDiagnostic(output, report, code); }
  return code;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().then(code => {process.exitCode = code;}).catch(() => {
    console.error('NativeChannelDiagnosticUnavailable'); process.exitCode = 1;
  });
}
