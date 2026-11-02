import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, tmpdir, totalmem} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runNodeProcessBenchmark} from './benchmark-node-process-operations.mjs';
import {nodeOperationProtocol, runNodeWarmBenchmark} from './benchmark-node-operations.mjs';
import {assessPerformanceEvidence} from './operation-performance.mjs';

const hash = b => createHash('sha256').update(b).digest('hex');
async function fixture(t, {mode = 'diagnostic', operation = 'cold-existing', fail = '', closeFailure} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-process-collector-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const base = join(root, 'consumer/node_modules/@actql/node'); await mkdir(base, {recursive: true});
  // Explicit synthetic public-port double. These real process tests establish
  // collector PID/state/cleanup behavior, never ordinary product performance.
  const code = Buffer.from(`import assert from 'node:assert/strict';
import {appendFile,mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
export async function open({stateDir}) {
 await mkdir(stateDir,{recursive:true});
 const event=kind=>appendFile(stateDir+'/events',JSON.stringify({kind,pid:process.pid})+'\\n');
 await event('open');
 const ref={namespaceId:'synthetic',authorityScopeCid:'sha256:'+'a'.repeat(64),runDefinitionCid:'sha256:'+createHash('sha256').update(stateDir+process.pid).digest('hex')};
 const run={ref,wait:async()=>({status:'succeeded'}),status:async()=>({status:'succeeded',revision:1}),
  result:()=>({all:async()=>JSON.parse(await readFile(stateDir+'/rows','utf8'))})};
 return {startSource:async(text,options)=>{
  assert.equal(text,'SELECT 1 AS id');assert.equal(options.format,'sql');
  await event('submit');
  ${fail === 'unknown' ? "if(options.requestId!=='benchmark-seed')throw new Error('Unknown; no resend');" : ''}
  ${fail === 'exit' ? "if(options.requestId!=='benchmark-seed')process.exit(7);" : ''}
  await writeFile(stateDir+'/rows','[{"id":1}]');return run;},
  attach:async()=>assert.fail('cold-existing must execute a NEW query, never Saved-only'),
  sql:(text,parameters,options)=>({all:async()=>text==='SELECT @id AS id'?(assert.deepEqual(parameters,{id:7}),assert.deepEqual(options,{parameterDeclarations:{id:{type:'number'}}}),[{id:7}])
    :text==="SELECT 'é😀' AS label"?[{label:'é😀'}]:text.includes('JOIN rhs')?[{id:1,label:'joined'}]
    :text.includes('SUM(amount)')?[{total:'4.00'}]
    :text.includes('UNION ALL')?[{id:1},{id:2}]:[{id:1}]}),
  close:async()=>{await event('close');${fail === 'close' ? "throw new Error('cleanup pending');" : ''}
   ${closeFailure === undefined ? '' : `throw ${closeFailure};`}}};
}`);
  await writeFile(join(base, 'index.mjs'), code, {mode: 0o644});
  const tar = Buffer.from('synthetic archive identity only; not an ordinary tarball');
  await writeFile(join(root, 'test.tgz'), tar);
  const manifestPath = join(root, 'release.json');
  await writeFile(manifestPath, JSON.stringify({sourceSha: 'a'.repeat(40), packages: [{name: '@actql/node',
    file: 'test.tgz', bytes: tar.length, sha256: hash(tar), integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'),
    files: [{path: 'index.mjs', bytes: code.length, mode: 0o644, sha256: hash(code)}]}]}));
  const controlsPath = join(root, 'controls.json');
  await writeFile(controlsPath, JSON.stringify({sourceSha: 'a'.repeat(40), cohortSha256: hash(await readFile(manifestPath)),
    environment: {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
      cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()}, load: 'isolated',
    historyProtocolSha256: hash(Buffer.from(JSON.stringify(nodeOperationProtocol(mode))))}));
  return {manifestPath, consumer: join(root, 'consumer'), controlsPath, output: join(root, 'new-benchmark'), operation, mode};
}
const events = async state => (await readFile(join(state, 'events'), 'utf8')).trim().split('\n').map(JSON.parse);

test('cold-existing uses initialized same-candidate state then a distinct NEW Run per actual child', async t => {
  const options = await fixture(t);
  const report = await runNodeProcessBenchmark(options), series = report.latency[0];
  assert.equal(series.samples.length, 3);
  const pids = [report.seed.pid, ...series.samples.map(row => row.pid)];
  assert.equal(new Set(pids).size, 4); assert(!pids.includes(process.pid));
  assert.equal(new Set(series.samples.map(row => row.stateId)).size, 1);
  assert(series.samples.every(row => row.verified && row.childCpuAvailable && row.childObservation.pid === row.pid));
  assert(series.samples.every(row => row.stateDirectory.entryCount > 0));
  assert(series.samples.every(row => row.cpuUserUs >= row.childObservation.operationCpuUserUs &&
    row.cpuSystemUs >= row.childObservation.operationCpuSystemUs));
  assert(series.samples.every(row => row.cpuScope.includes('startup-through-close')));
  assert(series.samples.every(row => row.wallNs >= row.childObservation.operationWallNs));
  assert(series.samples.every(row=>row.firstResultNs>0&&row.firstResultNs<=row.wallNs&&row.parentClock.notificationCount===1));
  assert(series.samples.every(row=>row.childObservation.phaseSpans.map(x=>x.name).join(',')===
    'product-import,public-open,new-run-submission,wait-execution-publication,all-result-rows,first-close'));
  assert(series.samples.every(row=>row.childObservation.phaseSpans.every(x=>x.completed&&x.endNs>=x.startNs)));
  const trace = await events(series.samples[0].stateId);
  assert.equal(trace.filter(row => row.kind === 'submit').length, 4);
  assert.equal(trace.filter(row => row.kind === 'attach').length, 0);
  assert.equal(trace.filter(row => row.kind === 'close').length, 4);
  assert.equal(report.cleanup.allChildrenExited, true);
  assert.equal(report.cleanup.allOriginalClientsClosed, true);
  assert.equal(report.installedPayloadsUnchanged, true);
  assert.equal(report.assessments[0].status, 'incomplete'); assert.equal(report.assessments[0].summary.p95Ms, null);
  assert.equal(report.fullAcceptance, false);
});
test('final initialization records thirty real child processes and thirty distinct empty states', async t => {
  const options = await fixture(t, {operation: 'first-init', mode: 'final'});
  const report = await runNodeProcessBenchmark(options), rows = report.latency[0].samples;
  assert.equal(rows.length, 30); assert.equal(new Set(rows.map(row => row.pid)).size, 30);
  assert.equal(new Set(rows.map(row => row.stateId)).size, 30);
  assert(rows.every(row => row.pid !== process.pid && row.verified && row.childCpuAvailable));
  for (const row of rows) {
    const trace = await events(row.stateId);
    assert.deepEqual(trace.map(row => row.kind), ['open', 'submit', 'close']);
    assert(trace.every(event => event.pid === row.pid));
  }
  assert.equal(report.assessments[0].summary.count, 30);
  assert.notEqual(report.assessments[0].summary.p95Ms, null);
  assert.equal(report.fullAcceptance, false); // Synthetic collector evidence only.
});
test('warm and process reports share one explicit experiment binding but cannot complete missing release gates', async t => {
  const options = await fixture(t), cold = await runNodeProcessBenchmark(options);
  const warm = await runNodeWarmBenchmark({...options, output: options.output + '-warm'});
  assert.equal(warm.historyProtocolSha256, cold.historyProtocolSha256);
  const report = {...cold, latency: [...warm.latency, ...cold.latency],
    functional: {...cold.functional, rows: [...warm.functional.rows, ...cold.functional.rows]}};
  const assessment = assessPerformanceEvidence(report);
  assert.equal(assessment.status, 'incomplete'); assert(assessment.missing.includes('history'));
  const changed = structuredClone(report); changed.latency[0].cohortSha256 = 'f'.repeat(64);
  assert.throws(() => assessPerformanceEvidence(changed), /cohort differs/u);
});
test('Unknown stops after the first actual cold failure and still awaits original Client close', async t => {
  const options = await fixture(t, {fail: 'unknown'}), report = await runNodeProcessBenchmark(options);
  assert.equal(report.latency[0].samples.length, 1);
  assert.equal(report.latency[0].samples[0].verified, false);
  assert.match(report.firstFailure.message, /Unknown; no resend/u);
  assert.equal(report.cleanup.allOriginalClientsClosed, true);
  const trace = await events(report.latency[0].samples[0].stateId);
  assert.equal(trace.filter(row => row.kind === 'submit').length, 2);
  assert.equal(trace.filter(row => row.kind === 'attach').length, 0);
  assert.equal(trace.filter(row => row.kind === 'close').length, 2);
});
test('a child exit without a receipt stays failed and does not manufacture child CPU or cleanup', async t => {
  const options = await fixture(t, {fail: 'exit'}), report = await runNodeProcessBenchmark(options);
  const row = report.latency[0].samples[0];
  assert.equal(row.code, 7); assert.equal(row.verified, false); assert.equal(row.childCpuAvailable, false);
  assert.equal(row.childObservation, null);
  assert.equal(row.cpuScope, 'collector-process-only; child CPU unavailable');
  assert.equal(report.cleanup.allOriginalClientsClosed, false);
  assert.equal(report.cleanup.allChildrenExited, true); assert.equal(report.latency[0].samples.length, 1);
});
test('failed awaited close cannot qualify a successful result as a process sample', async t => {
  const options = await fixture(t, {operation: 'first-init', fail: 'close'});
  const report = await runNodeProcessBenchmark(options), row = report.latency[0].samples[0];
  assert.equal(row.verified, false); assert.equal(report.latency[0].samples.length, 1);
  assert.match(row.childObservation.cleanup.failure.message, /cleanup pending/u);
  assert.equal(report.cleanup.allOriginalClientsClosed, false);
});
test('foreign environment/protocol and changed installed bytes refuse before any process sample', async t => {
  const options = await fixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  const actualEnvironment = {...controls.environment};
  controls.environment.node = 'foreign'; await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeProcessBenchmark(options));
  controls.environment = actualEnvironment; controls.historyProtocolSha256 = 'f'.repeat(64);
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeProcessBenchmark(options));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodeOperationProtocol(options.mode))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await writeFile(join(options.consumer, 'node_modules/@actql/node/index.mjs'), 'changed');
  await assert.rejects(runNodeProcessBenchmark(options));
});

for (const operation of ['cold-existing', 'first-init']) {
  test(`record-only ${operation} retains three actual child observations`, async t => {
    const options = await fixture(t, {mode: 'record-only', operation});
    const report = await runNodeProcessBenchmark(options);
    assert.equal(report.latency[0].samples.length, 3);
    assert.deepEqual(report.assessments, []);
    assert.equal(report.measurements[0].p95Ms, null);
    assert.equal(report.measurements[0].resources.rss.available, true);
    assert.equal(report.cleanup.allOriginalClientsClosed, true);
  });
}
test('record-only process failure remains failed and is never replayed', async t => {
  const options = await fixture(t, {mode: 'record-only', fail: 'unknown'});
  const report = await runNodeProcessBenchmark(options);
  assert(report.firstFailure); assert.equal(report.latency[0].samples.length, 1);
  assert.equal(report.measurements, undefined);
});

for (const [label, literal] of [
  ['undefined', 'undefined'], ['null', 'null'], ['false', 'false'], ['zero', '0'], ['empty string', "''"],
]) {
  test(`record-only process retains falsy close failure: ${label}`, async t => {
    const options = await fixture(t, {mode: 'record-only', operation: 'first-init', closeFailure: literal});
    const report = await runNodeProcessBenchmark(options);
    assert(report.firstFailure);
    assert.equal(report.latency[0].samples.length, 1);
    const row = report.latency[0].samples[0];
    assert(row.childObservation, 'the failed original child still supplies its own diagnostic receipt');
    assert.equal(row.childObservation.cleanup.closed, false);
    assert.equal(typeof row.childObservation.cleanup.failure.message, 'string');
    assert.equal(row.completed, false); assert.equal(row.verified, false);
    assert.notEqual(row.code, 0);
    assert.equal(report.measurements, undefined);
    assert.equal(report.cleanup.allOriginalClientsClosed, false);
    const trace = await events(row.stateId);
    assert.deepEqual(trace.map(event => event.kind), ['open', 'submit', 'close']);
  });
}

test('record-only process CLI retains an undefined close failure and exits nonzero', async t => {
  const options = await fixture(t, {mode: 'record-only', operation: 'first-init', closeFailure: 'undefined'});
  const child = spawnSync(process.execPath, ['scripts/benchmark-node-process-operations.mjs',
    '--manifest', options.manifestPath, '--consumer', options.consumer, '--output', options.output,
    '--controls', options.controlsPath, '--mode', options.mode, '--operation', options.operation],
  {encoding: 'utf8', timeout: 20_000});
  assert.equal(child.error, undefined);
  assert.equal(child.status, 1, child.stderr);
  const report = JSON.parse(await readFile(join(options.output, 'measurements.json')));
  assert(report.firstFailure); assert.equal(report.measurements, undefined);
  const row = report.latency[0].samples[0];
  assert.equal(row.childObservation.cleanup.closed, false);
  assert.equal(typeof row.childObservation.cleanup.failure.message, 'string');
  assert.deepEqual((await events(row.stateId)).map(event => event.kind), ['open', 'submit', 'close']);
});
