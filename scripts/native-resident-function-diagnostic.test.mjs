import assert from 'node:assert/strict';
import {spawn, spawnSync, execFileSync} from 'node:child_process';
import {once} from 'node:events';
import {readFileSync} from 'node:fs';
import {chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'yaml';
import {parse as javascript} from 'acorn';
import {functionDiagnosticSummary, rewriteResidentControlSpawn,
  runFunctionDiagnosticCase} from './diagnose-native-resident-functions.mjs';

const source = readFileSync(new URL('./test-native-resident-site.mjs', import.meta.url), 'utf8');
const wrapper = fileURLToPath(new URL('./fixtures/native-resident-function-debugger.py', import.meta.url));
const python = execFileSync('python3', ['-c', 'import sys;print(sys.executable)'], {encoding: 'utf8'}).trim();

async function fixture(t, body) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-function-test-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const bin = join(directory, 'bin');
  await mkdir(bin);
  const entry = join(directory, 'entry.log'), report = join(directory, 'report.json');
  const spy = join(directory, 'private-spy.json');
  await writeFile(entry, 'original-producer\n');
  const debuggerPath = join(bin, 'gdb');
  if (body !== undefined) {
    await writeFile(debuggerPath, `#!${python}\nimport os,sys,time,signal,json\nfrom pathlib import Path\n` +
      `entry=Path(${JSON.stringify(entry)})\nspy=Path(${JSON.stringify(spy)})\n` + body);
    await chmod(debuggerPath, 0o700);
  }
  const target = ['/verified/native-original', 'run', '--executor-entry-log', entry,
    '--private-input', 'private-original-value'];
  return {directory, entry, report, spy, target, start: () => {
    const child = spawn(python, [wrapper, report, ...target], {
      env: {PATH: bin, LANG: 'C'}, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    return {child, closed: once(child, 'close').then(([code, signal]) => ({code, signal, stdout, stderr}))};
  }};
}

test('diagnostic changes only the hash-fenced original control parent, leaving installer/environment/arguments intact', () => {
  const updated = rewriteResidentControlSpawn(source,
    {python: '/usr/bin/python3', wrapper: '/diagnostic/wrapper.py', report: '/private/report.json'});
  const anchor = "const child = spawn(executable, ['run', ...configured,";
  const [before, after] = source.split(anchor);
  assert.equal(updated, before + 'const child = spawn("/usr/bin/python3", ' +
    '["/diagnostic/wrapper.py", "/private/report.json", executable, \'run\', ...configured,' + after);
  assert(updated.includes("const siteProcessEnvironment = Object.freeze({PATH: '/usr/bin:/bin', LANG: 'C'});"));
  assert(!updated.includes('LD_PRELOAD'));
  assert.equal(javascript(updated, {ecmaVersion: 'latest', sourceType: 'module'}).type, 'Program');
  assert.throws(() => rewriteResidentControlSpawn(source + '\n', {}), /Source hash differs/u);
});

test('outer diagnostic suppresses private original output and preserves its nonzero exit', () => {
  let invocation;
  const result = runFunctionDiagnosticCase('/private/report.json', {
    env: {ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: '/same/preparation',
      ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT: '/same/http-receipt'},
    execute: (command, args, options) => {
      invocation = {command, args, options};
      return {status: 17, stderr: 'private-error-and-arguments', stdout: 'private-values'};
    }});
  assert.equal(result.status, 17);
  assert.equal(invocation.options.stdio, 'ignore');
  assert.equal(invocation.options.timeout, 285000);
  assert.equal(invocation.options.killSignal, 'SIGTERM');
  assert.equal(invocation.args.at(-1), '--effect-computation-only');
  assert.throws(() => runFunctionDiagnosticCase('/private/report.json', {env: {},
    execute: () => assert.fail('a missing preparation must not start a producer')}), /Same-job Native preparation/u);
  const summary = functionDiagnosticSummary(result, {consumerExecutorEntered: true,
    sampleRequested: true, functions: ['actual_function', 'private object(value)', '/private/source'],
    conditions: ['permission-denied', 'private-error'], argv: 'private-arguments', values: 'private-values'});
  assert.deepEqual(summary, {version: 1, diagnosticOnly: true, caseExit: 17, caseSignal: null,
    timedOut: false, consumerExecutorEntered: true, sampleRequested: true,
    functions: ['actual_function'], conditions: ['permission-denied']});
  assert.equal(JSON.stringify(summary).includes('private-'), false);
});

test('fake debugger samples only after consumer entry and reports functions without arguments/data', {timeout: 10000}, async t => {
  const f = await fixture(t, `
args=sys.argv[1:]
original=args[args.index('--args')+1:]
tty=next(x[len('set inferior-tty '):] for x in args if x.startswith('set inferior-tty '))
with open(tty,'wb',buffering=0) as output:output.write(b'{"kind":"target-original","private":"native-original"}\\n')
print('private debugger argv '+repr(args),flush=True)
print('#0 must_not_capture_before_entry (private="value")',flush=True)
def interrupted(sig,frame):
 spy.write_text(json.dumps({'target':original,'entryCount':len(entry.read_bytes().splitlines()),
                           'disableRandomizationOff':'set disable-randomization off' in args,
                           'returnChildResult':'--return-child-result' in args,
                           'environment':dict(os.environ)}))
 print('#0 0x1234 in busy_function (private="value") at /private/source:19',flush=True)
 print('private body and arguments',flush=True)
 with open(tty,'wb',buffering=0) as output:output.write(b'{"kind":"target-final"}\\n')
 sys.exit(23)
signal.signal(signal.SIGINT,interrupted)
while True:time.sleep(.02)
`);
  const run = f.start();
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(await stat(f.spy).then(() => true, () => false), false);
  await writeFile(f.entry, 'original-producer\noriginal-consumer\n');
  const result = await run.closed;
  assert.equal(result.code, 23);
  assert.equal(result.signal, null);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, '{"kind":"target-original","private":"native-original"}\n{"kind":"target-final"}\n');
  const spy = JSON.parse(await readFile(f.spy, 'utf8'));
  assert.deepEqual(spy.target, f.target);
  assert.equal(spy.entryCount, 2);
  assert.equal(spy.disableRandomizationOff, true);
  assert.equal(spy.returnChildResult, true);
  assert.equal(spy.environment.PATH, join(f.directory, 'bin'));
  assert.equal(spy.environment.LANG, 'C');
  const report = JSON.parse(await readFile(f.report, 'utf8'));
  assert.deepEqual(report, {consumerExecutorEntered: true, sampleRequested: true,
    functions: ['busy_function'], conditions: []});
  assert.equal(JSON.stringify(report).includes('private'), false);
  assert.equal((await stat(f.report)).mode & 0o777, 0o600);
});

test('fake debugger early failure stays nonzero with stage unavailable and no private error output', {timeout: 5000}, async t => {
  const f = await fixture(t, `print('Could not trace: Operation not permitted; private argv and values',flush=True)
time.sleep(.05)
sys.exit(7)
`);
  const result = await f.start().closed;
  assert.equal(result.code, 7);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
  assert.deepEqual(JSON.parse(await readFile(f.report, 'utf8')), {
    consumerExecutorEntered: false, sampleRequested: false, functions: [],
    conditions: ['permission-denied', 'stage-not-observed', 'trace-unavailable']});
});

test('missing debugger reports availability without a target attempt or fallback', {timeout: 5000}, async t => {
  const f = await fixture(t);
  const result = await f.start().closed;
  assert.equal(result.code, 1);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
  assert.deepEqual(JSON.parse(await readFile(f.report, 'utf8')), {
    consumerExecutorEntered: false, sampleRequested: false, functions: [],
    conditions: ['debugger-unavailable', 'stage-not-observed']});
});

test('Native CI diagnostic is failure-only, bounded, and uploads only sanitized JSON', () => {
  const jobs = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8')).jobs;
  const original = jobs.native.steps.find(step => step.id === 'native-runtime-test');
  assert.equal(original.if, undefined);
  assert.equal(original['continue-on-error'], undefined);
  assert(original.run.includes('npm run check:native-http-client'));
  const diagnostic = jobs.native.steps.find(step => step.name === 'Diagnose only failed Linux Effect consumer functions');
  assert.equal(diagnostic.if, "${{ failure() && steps.native-runtime-test.outcome == 'failure' }}");
  assert.equal(diagnostic['continue-on-error'], true);
  assert.equal(diagnostic['timeout-minutes'], 6);
  assert(diagnostic.run.includes('ulimit -S -s 65536'));
  const helper = readFileSync(new URL('./diagnose-native-resident-functions.mjs', import.meta.url), 'utf8');
  assert(helper.includes('timeoutSeconds: 295, graceSeconds: 5'));
  const artifact = jobs.native.steps.find(step => step.name === 'Retain only sanitized Linux Effect function availability');
  assert.equal(artifact.if, diagnostic.if);
  assert.equal(artifact.with.path, '${{ runner.temp }}/native-effect-functions/sanitized.json');
  assert(!artifact.with.path.includes('*'));
  const lint = jobs.lint.steps.find(step => step.name === 'Test native SQLite namespace ownership');
  assert(lint.run.includes('scripts/native-resident-function-diagnostic.test.mjs'));
  assert.equal(spawnSync(python, ['-c',
    'import ast,sys;ast.parse(open(sys.argv[1]).read())', wrapper]).status, 0);
});
