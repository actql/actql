// The actual private harness supervisor with real owned child processes.
// These mechanism cases import no Native/Host runtime and issue no cleanup ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {fork} from 'node:child_process';
import {EventEmitter, once} from 'node:events';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';

const source = readFileSync(new URL('./test-native-resident-site.mjs', import.meta.url), 'utf8');
const syntax = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = syntax.body.find(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(value => value.id.name === 'residentPhaseKinds'));
const initializer = declaration.declarations.find(value => value.id.name === 'residentPhaseKinds').init;
const kinds = Function(`return (${source.slice(initializer.start, initializer.end)});`)();
const original = syntax.body.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === 'runResidentPhaseWatchdog');
assert(original);
const supervise = Function('fork', 'residentPhaseKinds', `return (${source.slice(original.start, original.end)});`)(fork, kinds);

test('Resident consumer diagnostics preserve the original refusal under relay noise without private fields',()=>{
  const declaration=syntax.body.find(node=>node.type==='FunctionDeclaration' &&
    node.id.name==='residentConsumerFailureSummary');
  assert(declaration);
  const summarize=Function(`return (${source.slice(declaration.start,declaration.end)});`)();
  const refused={kind:'consumer-refused',reason:'retained-input',boundary:'producer-route',request_cid:'private-request',
    body:'private-frame',message:'private-message'};
  const lines=[{kind:'holder-input-frame',operation:'retained-plan'},
    {kind:'holder-input-frame',operation:'consumer',holder_request_cid:'private-holder'},refused,
    ...Array.from({length:1000},()=>({kind:'consumer-relayed',sent:'false',request_cid:'private-request'})),
    {kind:'consumer-accept-pending',reason:'private-provider-message',boundary:'private-frame'},
    {kind:'private-event',reason:'private-provider-message'}];
  const original=JSON.stringify(lines);
  assert.deepEqual(summarize(lines),[
    {kind:'holder-input-frame',operation:'consumer',count:1},
    {kind:'consumer-refused',reason:'retained-input',boundary:'producer-route',count:1},
    {kind:'consumer-relayed',sent:false,count:1000},
    {kind:'consumer-accept-pending',reason:'unselected',boundary:'unselected',count:1},
  ]);
  assert.equal(JSON.stringify(lines),original);
  assert.equal(JSON.stringify(summarize(lines)).includes('private-'),false);
  assert.deepEqual(summarize([]),[]);
});

async function childFixture(t, body) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-resident-watchdog-'));
  const script = join(directory, 'child.mjs');
  await writeFile(script, body);
  t.after(() => rm(directory, {recursive: true, force: true}));
  return {directory, script};
}
const phase = (name, line) => `process.send({kind:'native-resident-phase',phase:${JSON.stringify(name)},line:${line}});`;

test('Native Resident watchdog fails a real stalled original group and preserves the last safe phase', {timeout: 5000}, async t => {
  const f = await childFixture(t, `import{writeFileSync}from'node:fs';
    writeFileSync(new URL('./original.txt',import.meta.url),'original failure evidence');
    process.on('SIGTERM',()=>{});setInterval(()=>{},1000);
    ${phase('bundle-activated', 1)}${phase('engine-contracts-enter', 2)}`);
  const reports = [];
  const result = await supervise(f.script, {phaseTimeoutMilliseconds: 100,
    killGraceMilliseconds: 100, report: value => reports.push(value)});
  assert.equal(result.code, 124);
  assert.equal(result.timedOut, true);
  assert.equal(result.signal, 'SIGKILL');
  assert.deepEqual(result.lastPhase, {phase: 'engine-contracts-enter', line: 2});
  assert.deepEqual(reports.at(-1), {event: 'timeout', phase: 'engine-contracts-enter',
    line: 2, cleanup: 'unconfirmed'});
  assert.equal(await readFile(join(f.directory, 'original.txt'), 'utf8'), 'original failure evidence');
});

test('Native Resident watchdog retains an original nonzero child outcome without substituting timeout or cleanup', {timeout: 5000}, async t => {
  const f = await childFixture(t, `${phase('bundle-activated', 1)}${phase('run-materials-enter', 2)}process.exit(7);`);
  const reports = [];
  const result = await supervise(f.script, {phaseTimeoutMilliseconds: 1000,
    report: value => reports.push(value)});
  assert.equal(result.code, 7);
  assert.equal(result.timedOut, false);
  assert.equal(result.signal, null);
  assert.equal(reports.some(value => value.event === 'timeout'), false);
});

test('Native Resident concurrent stop identifies the remaining control without confirming cleanup', {timeout: 5000}, async t => {
  const declaration = syntax.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'stopConcurrentResidentControls');
  assert(declaration);
  const f = await childFixture(t, `import{fork}from'node:child_process';import{once}from'node:events';
    process.on('SIGTERM',()=>{});
    const residentPhase=phase=>process.send({kind:'native-resident-phase',phase,line:7});
    const stop=${source.slice(declaration.start, declaration.end)};
    const start=mode=>{const child=fork(new URL('./control.mjs',import.meta.url),[mode],
      {stdio:['ignore','ignore','ignore','ipc']});return{child,exited:once(child,'exit')};};
    const left=start('normal'),right=start('ignore-term');
    await Promise.all([once(left.child,'message'),once(right.child,'message')]);
    residentPhase('bundle-activated');await stop(left,right);`);
  await writeFile(join(f.directory, 'control.mjs'), `
    if(process.argv[2]==='ignore-term')process.on('SIGTERM',()=>{});
    setInterval(()=>{},1000);process.send({ready:true});`);
  const reports = [];
  const result = await supervise(f.script, {phaseTimeoutMilliseconds: 200,
    killGraceMilliseconds: 100, report: value => reports.push(value)});
  assert.equal(result.code, 124);
  assert.equal(result.timedOut, true);
  assert.deepEqual(result.lastPhase, {phase: 'concurrent-left-exit-return', line: 7});
  assert.equal(reports.some(value => value.phase === 'concurrent-right-exit-return'), false);
  assert.deepEqual(reports.at(-1), {event: 'timeout', phase: 'concurrent-left-exit-return',
    line: 7, cleanup: 'unconfirmed'});
});

test('Native Resident watchdog settles after force stop precedes child close while the group remains observable', async () => {
  const child = new EventEmitter();
  child.pid = 43123;
  const supervisor = new EventEmitter();
  supervisor.argv = ['node', 'watchdog'];
  const signals = [], timers = [], reports = [];
  supervisor.kill = (pid, signal) => {
    assert.equal(pid, -child.pid);
    signals.push(signal);
    return true; // The original group remains observable, not a cleanup ACK.
  };
  const run = Function('fork', 'residentPhaseKinds', 'process', 'setTimeout', 'clearTimeout',
    `return (${source.slice(original.start, original.end)});`)(() => child, kinds, supervisor,
      callback => { timers.push(callback); return callback; }, () => {});
  let completed;
  const outcome = run('original.mjs', {report: value => reports.push(value)});
  outcome.then(value => { completed = value; });
  child.emit('message', {kind: 'native-resident-phase', phase: 'bundle-activated', line: 7});
  assert.equal(timers.length, 1);
  timers.shift()(); // Original phase timeout, then its original KILL grace.
  assert.equal(timers.length, 1);
  timers.shift()(); // Direct child's close notification has not arrived yet.
  assert.equal(completed, undefined);
  assert.deepEqual(signals, ['SIGTERM', 'SIGKILL']);
  child.emit('close', null, 'SIGKILL');
  await new Promise(resolve => setImmediate(resolve));
  assert(completed, 'closed child must settle after its already-dispatched force stop');
  assert.equal(completed.code, 124);
  assert.equal(completed.timedOut, true);
  assert.equal(completed.signal, 'SIGKILL');
  assert.deepEqual(completed.lastPhase, {phase: 'bundle-activated', line: 7});
  assert.deepEqual(reports.at(-1), {event: 'timeout', phase: 'bundle-activated',
    line: 7, cleanup: 'unconfirmed'});
  assert.equal(reports.some(value => value.cleanup === 'confirmed'), false);
});

test('Native Resident watchdog preserves natural success and ignores unselected diagnostic payloads', {timeout: 5000}, async t => {
  const f = await childFixture(t, `${phase('bundle-activated', 1)}
    process.send({kind:'native-resident-phase',phase:'unselected-payload',line:3,body:'never-forward'});
    ${phase('cleanup-calls-returned', 4)}process.exit(0);`);
  const reports = [];
  const result = await supervise(f.script, {phaseTimeoutMilliseconds: 1000,
    report: value => reports.push(value)});
  assert.equal(result.code, 0);
  assert.equal(result.timedOut, false);
  assert.equal(reports.length, 2);
  assert.deepEqual(result.lastPhase, {phase: 'cleanup-calls-returned', line: 4});
  assert.equal(JSON.stringify(reports).includes('never-forward'), false);
});


test('Native Resident supervisor TERM stops only its owned group and remains nonzero', {timeout: 5000}, async t => {
  const f = await childFixture(t, `process.on('SIGTERM',()=>{});setInterval(()=>{},1000);${phase('bundle-activated', 1)}`);
  const wrapper = join(f.directory, 'supervisor.mjs');
  await writeFile(wrapper, `import{fork}from'node:child_process';
    const residentPhaseKinds=new Set(${JSON.stringify([...kinds])});
    const supervise=${source.slice(original.start, original.end)};
    const result=await supervise(${JSON.stringify(f.script)},{phaseTimeoutMilliseconds:1000,killGraceMilliseconds:100,
      report:value=>{if(value.event==='phase')process.send({armed:true});}});
    process.exitCode=result.code;if(process.connected)process.disconnect();`);
  const parent = fork(wrapper, [], {stdio: ['ignore', 'ignore', 'inherit', 'ipc']});
  const closed = once(parent, 'close');
  const [ready] = await once(parent, 'message');
  assert.equal(ready.armed, true);
  parent.kill('SIGTERM');
  const [code, signal] = await closed;
  assert.equal(code, 143);
  assert.equal(signal, null);
});


test('Native Resident reconciliation observer crash retains unknown evidence without a cleanup ACK', {timeout: 5000}, async t => {
  const declaration = syntax.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'crashResidentReconciliationObserver');
  assert(declaration);
  const crashObserver = Function('assert', `return (${source.slice(declaration.start, declaration.end)});`)(assert);
  const f = await childFixture(t, `import{writeFileSync}from'node:fs';
    writeFileSync(new URL('./unknown.txt',import.meta.url),'original unresolved allocation debt');
    process.on('SIGTERM',()=>{});setInterval(()=>{},1000);process.send({ready:true});`);
  const child = fork(f.script, [], {stdio: ['ignore', 'ignore', 'inherit', 'ipc']});
  const exited = once(child, 'exit');
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
      await exited;
    }
  });
  const [ready] = await once(child, 'message');
  assert.equal(ready.ready, true);
  const original = await readFile(join(f.directory, 'unknown.txt'));
  assert.equal(await crashObserver({child, exited}), undefined);
  assert.equal(child.signalCode, 'SIGKILL');
  assert.deepEqual(await readFile(join(f.directory, 'unknown.txt')), original);
  // No release/close response or physical resource observation was supplied.
});


test('Resident preparation timings preserve the exact original six producer calls and return values', () => {
  const declaration = syntax.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'timedResidentPreparation');
  assert(declaration, 'Resident prerequisite time must be separated from test execution');
  const records = []; let clock = 0;
  const timed = Function('performance', 'console', `return (${source.slice(declaration.start, declaration.end)});`)(
    {now: () => clock++}, {error: line => records.push(JSON.parse(line.slice('ACTQL_NATIVE_CI_PHASE '.length)))});
  for (const retainedConsumerMode of [false, true]) {
    const calls = [], originals = Array.from({length: 6}, () => ({}));
    const record = name => (...args) => {calls.push({name, args}); return originals[calls.length - 1];};
    const begin = source.indexOf('  const httpLibrary = '), end = source.indexOf('  const moonModule = ', begin);
    assert(begin >= 0 && end > begin);
    const values = Function('timedResidentPreparation', 'prepareNativeResidentHttpLibrary',
      'prepareNativeResidentSite', 'execFileSync', 'prepareNativeRuntimeBundle',
      'prepareNativeRuntimeBundleLibraries', 'moon', 'repository', 'root', 'join', 'retainedConsumerMode',
      source.slice(begin, end) + '\nreturn [httpLibrary, executable, bundleTool, bundleLibraries];')(
      timed, record('http'), record('resident'), record('command'), record('bundle'), record('components'),
      '/selected/moon', '/original/source', '/owned/case', join, retainedConsumerMode);
    assert.deepEqual(calls, [
      {name: 'http', args: []},
      {name: 'resident', args: ['/original/source', '/owned/case/resident-producer']},
      {name: 'command', args: ['/selected/moon', ['build', '--target', 'js', '--release',
        'src/connectors_builtin_node'], {cwd: '/original/source', stdio: 'inherit'}]},
      {name: 'command', args: [process.execPath, ['scripts/build-runtime-packages.mjs',
        'coordinator-core', 'run-host-core', ...(retainedConsumerMode ? ['transfer-core'] : [])],
        {cwd: '/original/source', stdio: 'inherit'}]},
      {name: 'bundle', args: ['/original/source', '/owned/case/runtime-bundle-producer']},
      {name: 'components', args: ['/original/source', '/owned/case/runtime-bundle-components']},
    ]);
    for (const [index, value] of values.entries()) assert.strictEqual(value, originals[[0, 1, 4, 5][index]]);
  }
  assert.equal(records.length, 12);
  for (const offset of [0, 6]) assert.deepEqual(records.slice(offset, offset + 6),
    ['http-component', 'resident-command', 'portable-core-build', 'portable-owner-build', 'bundle-command', 'bundle-components']
      .map(phase => ({scope: 'resident-preparation', phase, milliseconds: 1, succeeded: true})));
});

test('Resident preparation timing retains original failure and never turns observer failure into execution failure', () => {
  const declaration = syntax.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'timedResidentPreparation');
  assert(declaration);
  const records = [], original = new Error('Original producer failure'); let calls = 0;
  const create = observe => Function('performance', 'console', `return (${source.slice(declaration.start, declaration.end)});`)(
    {now: () => 10}, {error: observe});
  const timed = create(line => records.push(JSON.parse(line.slice('ACTQL_NATIVE_CI_PHASE '.length))));
  assert.throws(() => timed('portable-core-build', () => {calls++; throw original;}), error => error === original);
  assert.equal(calls, 1);
  assert.deepEqual(records, [{scope: 'resident-preparation', phase: 'portable-core-build', milliseconds: 0, succeeded: false}]);
  const broken = create(() => {throw new Error('Diagnostic sink failure');});
  assert.throws(() => broken('portable-core-build', () => {throw original;}), error => error === original);
  const value = {}; assert.strictEqual(broken('portable-core-build', () => value), value);
});
