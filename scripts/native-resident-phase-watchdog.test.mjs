// The actual private harness supervisor with real owned child processes.
// These mechanism cases import no Native/Host runtime and issue no cleanup ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {fork} from 'node:child_process';
import {once} from 'node:events';
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
