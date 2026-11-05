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
  publishFunctionDiagnostic, runFunctionDiagnosticCase} from './diagnose-native-resident-functions.mjs';

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
  return {directory, entry, report, spy, target, start: ({pipeInput = false} = {}) => {
    const child = spawn(python, [wrapper, report, ...target], {
      env: {PATH: bin, LANG: 'C'}, stdio: [pipeInput ? 'pipe' : 'ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    return {child, closed: once(child, 'close').then(([code, signal]) => ({code, signal, stdout, stderr}))};
  }};
}

async function fakeDebuggerReady(f) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      const value = JSON.parse(await readFile(f.spy, 'utf8'));
      if (value.ready === true) return value;
    } catch (error) {
      if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error;
    }
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.fail('fake debugger did not install its signal handler');
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
payload=json.loads(os.pread(int(original[-1]),1048576,0))
print('private debugger argv '+repr(args),flush=True)
print('#0 must_not_capture_before_entry (private="value")',flush=True)
def interrupted(sig,frame):
 spy.write_text(json.dumps({'target':payload['argv'],'entryCount':len(entry.read_bytes().splitlines()),
                           'disableRandomizationOff':'set disable-randomization off' in args,
                           'returnChildResult':'--return-child-result' in args,
                           'followExecSame':'set follow-exec-mode same' in args,
                           'environment':payload['environment']}))
 print('#0 0x1234 in busy_function (private="value") at /private/source:19',flush=True)
 print('private body and arguments',flush=True)
 sys.exit(23)
signal.signal(signal.SIGINT,interrupted)
spy.write_text(json.dumps({'ready':True}))
while True:time.sleep(.02)
`);
  const run = f.start();
  assert.deepEqual(await fakeDebuggerReady(f), {ready: true});
  await writeFile(f.entry, 'original-producer\noriginal-consumer\n');
  const result = await run.closed;
  assert.equal(result.code, 23);
  assert.equal(result.signal, null);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, '');
  const spy = JSON.parse(await readFile(f.spy, 'utf8'));
  assert.deepEqual(spy.target, f.target);
  assert.equal(spy.entryCount, 2);
  assert.equal(spy.disableRandomizationOff, true);
  assert.equal(spy.returnChildResult, true);
  assert.equal(spy.followExecSame, true);
  assert.deepEqual(spy.environment, {PATH: join(f.directory, 'bin'), LANG: 'C'});
  const report = JSON.parse(await readFile(f.report, 'utf8'));
  assert.deepEqual(report, {consumerExecutorEntered: true, sampleRequested: true,
    functions: ['busy_function'], conditions: []});
  assert.equal(JSON.stringify(report).includes('private'), false);
  assert.equal((await stat(f.report)).mode & 0o777, 0o600);
});

test('real inferior bootstrap preserves request/response pipes, separate stderr, exact argv/environment and nonzero exit', {timeout: 10000}, async t => {
  const f = await fixture(t, `
import subprocess
args=sys.argv[1:]
inferior=args[args.index('--args')+1:]
print('private debugger console and arguments '+repr(args),flush=True)
child=subprocess.Popen(inferior,pass_fds=tuple(int(value) for value in inferior[2:]),
                       stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
code=child.wait()
print('private debugger final output',flush=True)
sys.exit(code)
`);
  const target = join(f.directory, 'real-target.mjs');
  await writeFile(target, `import{writeFileSync}from'node:fs';
writeFileSync(${JSON.stringify(f.spy)},JSON.stringify({argv:process.argv.slice(1),environment:process.env}));
process.stdout.write('{"kind":"ready"}\\n');
let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>{input+=chunk;});
process.stdin.on('end',()=>{process.stdout.write(JSON.stringify({kind:'reply',input})+'\\n');
process.stderr.write('native-stderr-only\\n');process.exitCode=19;});
`);
  f.target.splice(0, f.target.length, process.execPath, target,
    'argument with spaces', 'literal-$;`value`', '--executor-entry-log', f.entry);
  const run = f.start({pipeInput: true});
  const [ready] = await once(run.child.stdout, 'data');
  assert.equal(ready.toString(), '{"kind":"ready"}\n');
  const input = 'original request: λ\r\n';
  run.child.stdin.end(input);
  const result = await run.closed;
  assert.equal(result.code, 19);
  assert.equal(result.signal, null);
  assert.equal(result.stdout, '{"kind":"ready"}\n' + JSON.stringify({kind: 'reply', input}) + '\n');
  assert.equal(result.stderr, 'native-stderr-only\n');
  const original = JSON.parse(await readFile(f.spy, 'utf8'));
  assert.deepEqual(original.argv, f.target.slice(1));
  // Compare the real target against the unwrapped original OS launch too:
  // macOS's Node runtime itself adds its CoreFoundation locale variable.
  const direct = spawnSync(f.target[0], f.target.slice(1), {input, encoding: 'utf8',
    env: {PATH: join(f.directory, 'bin'), LANG: 'C'}, timeout: 3000});
  assert.equal(direct.status, 19);
  assert.equal(direct.stdout, result.stdout);
  assert.equal(direct.stderr, result.stderr);
  assert.deepEqual(original, JSON.parse(await readFile(f.spy, 'utf8')));
  assert.equal(result.stdout.includes('private debugger'), false);
  assert.equal(result.stderr.includes('private debugger'), false);
  const report = JSON.parse(await readFile(f.report, 'utf8'));
  assert.deepEqual(report, {consumerExecutorEntered: false, sampleRequested: false,
    functions: [], conditions: ['stage-not-observed']});
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

test('outer publication retains an atomic function snapshot when the sampled debugger hangs and is killed', {timeout: 10000}, async t => {
  const f = await fixture(t, `
def interrupted(sig,frame):
 print('#0 0x1234 in busy_then_hangs (private="value") at /private/source:19',flush=True)
 print('private debugger arguments and body',flush=True)
signal.signal(signal.SIGINT,interrupted)
spy.write_text(json.dumps({'pid':os.getpid(),'ready':True}))
while True:time.sleep(.02)
`);
  const run = f.start();
  let debuggerPid;
  let stopped = false;
  t.after(async () => {
    if (stopped) return;
    run.child.kill('SIGKILL');
    try {
      debuggerPid ??= JSON.parse(await readFile(f.spy, 'utf8')).pid;
      process.kill(debuggerPid, 'SIGKILL');
    } catch (error) { if (error.code !== 'ESRCH' && error.code !== 'ENOENT') throw error; }
  });
  await fakeDebuggerReady(f);
  await writeFile(f.entry, 'original-producer\noriginal-consumer\n');
  const deadline = Date.now() + 6000;
  let snapshot;
  while (Date.now() < deadline) {
    try { snapshot = JSON.parse(await readFile(f.report, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (snapshot?.functions.includes('busy_then_hangs')) break;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.deepEqual(snapshot.functions, ['busy_then_hangs']);
  assert.equal(run.child.exitCode, null, 'the sampled owner has not returned');
  debuggerPid = JSON.parse(await readFile(f.spy, 'utf8')).pid;
  run.child.kill('SIGKILL');
  process.kill(debuggerPid, 'SIGKILL');
  stopped = true;
  const result = await run.closed;
  assert.equal(result.signal, 'SIGKILL');
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
  const output = join(f.directory, 'sanitized.json');
  const summary = publishFunctionDiagnostic(output, f.report, 124);
  assert.equal(summary.supervisorExit, 124, 'outer timeout stays nonzero');
  assert.equal(summary.timedOut, true);
  assert.equal(summary.caseExit, null, 'killed case has no invented exit receipt');
  assert.equal(summary.consumerExecutorEntered, true);
  assert.equal(summary.sampleRequested, true);
  assert.deepEqual(summary.functions, ['busy_then_hangs']);
  const wire = await readFile(output, 'utf8');
  assert.deepEqual(JSON.parse(wire), summary);
  assert.equal(wire.includes('private'), false);
  assert.equal((await stat(output)).mode & 0o777, 0o600);
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
  const dependencies = jobs.native.steps.find(step => step.name === 'Select the original pinned Noble static Crypto inputs');
  assert(dependencies.run.includes('sudo apt-get install --yes "$openssl_development" "$openssl_runtime" gnupg gpgv gdb'));
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
  assert.equal(spawnSync(python, ['-c', 'import ast,sys;ast.parse(open(sys.argv[1]).read())',
    fileURLToPath(new URL('./fixtures/native-resident-function-bootstrap.py', import.meta.url))]).status, 0);
});
