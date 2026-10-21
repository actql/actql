import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir, arch, platform, release, cpus, totalmem} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nodeBenchmarkInstrumentation, nodeWarmSmallQueryFixtures, runNodeWarmBenchmark, nodeWarmProtocol} from './benchmark-node-operations.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
test('known startup profiling cannot be labeled uninstrumented latency', () => {
  const ordinary = {execArgv: [], nodeOptions: '', coverage: undefined};
  assert.equal(nodeBenchmarkInstrumentation(ordinary).profiled, false);
  for (const flags of [['--cpu-prof'], ['--cpu-prof-dir=output'], ['--prof'], ['--inspect=0'], ['--heap-prof']]) {
    assert.equal(nodeBenchmarkInstrumentation({...ordinary, execArgv: flags}).profiled, true);
  }
  assert.equal(nodeBenchmarkInstrumentation({...ordinary, nodeOptions: '--cpu-prof'}).profiled, true);
  assert.equal(nodeBenchmarkInstrumentation({...ordinary, coverage: 'coverage'}).profiled, true);
});
async function fixture(t, fail = false, slow = false, wrong = '') {
  const root = await mkdtemp(join(tmpdir(), 'actql-benchmark-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packageRoot = join(root, 'consumer/node_modules/@actql/node');
  await mkdir(packageRoot, {recursive: true});
  // Explicit synthetic public-port double tests collector/cleanup behavior only.
  // These bytes are not an ordinary product cohort or a latency observation.
  const code = Buffer.from(`import {appendFile,mkdir,writeFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
export async function open({stateDir}) {
 await mkdir(stateDir); let closed=false;
 const run={ref:{id:'same'}, wait:async()=>({status:'succeeded'}),
   result:()=>({all:async()=>{${slow ? 'await delay(110);' : ''}return [{id:1}];}}),status:async()=>({status:'succeeded',revision:1})};
 return {startSource:async()=>run,sql:text=>({all:async()=>{
  await appendFile(stateDir+'/queries',JSON.stringify(text)+'\\n');
  ${fail ? "throw new Error('Unknown; no resend');" : ''}
  ${slow ? 'await delay(110);' : 'await Promise.resolve();'}
  if(text.includes('JOIN rhs'))return ${wrong === 'join' ? "[{id:1,label:'foreign'}]" : "[{id:1,label:'joined'}]"};
  if(text.includes('SUM(amount)'))return ${wrong === 'decimal' ? '[{total:4}]' : "[{total:'4.00'}]"};
  if(text.includes('UNION ALL'))return ${wrong === 'union' ? '[{id:1}]' : '[{id:1},{id:2}]'};
  return [{id:1}];}}),
 close:async()=>{if(closed)throw new Error('close twice');closed=true;await writeFile(stateDir+'/closed','yes');}};
}`);
  const product = join(packageRoot, 'index.mjs'); await writeFile(product, code, {mode: 0o644});
  const tar = Buffer.from('synthetic unit fixture, not a package tarball');
  await writeFile(join(root, 'test.tgz'), tar);
  const manifestPath = join(root, 'release.json');
  await writeFile(manifestPath, JSON.stringify({sourceSha: 'a'.repeat(40), packages: [{name: '@actql/node',
    file: 'test.tgz', bytes: tar.length, sha256: hash(tar), integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'),
    files: [{path: 'index.mjs', bytes: code.length, mode: 0o644, sha256: hash(code)}]}]}));
  const controlsPath = join(root, 'controls.json');
  await writeFile(controlsPath, JSON.stringify({sourceSha: 'a'.repeat(40), cohortSha256: hash(await readFile(manifestPath)),
    environment: {platform: platform(), arch: arch(), node: process.version,
    osRelease: release(), cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()},
    load: 'isolated', historyProtocolSha256: hash(Buffer.from(JSON.stringify(nodeWarmProtocol('diagnostic'))))}));
  return {manifestPath, consumer: join(root, 'consumer'), controlsPath, output: join(root, 'new-benchmark'), mode: 'diagnostic'};
}
test('public warm adapter verifies output, awaits close, retains samples without claiming final p95', async t => {
  const options = await fixture(t);
  const report = await runNodeWarmBenchmark(options);
  assert.equal(report.cleanup.closed, true); assert.equal(report.installedPayloadsUnchanged, true);
  assert.equal(report.latency.length, 6);
  assert(report.assessments.every(row => row.status === 'incomplete' && row.summary.p95Ms === null));
  assert.equal(report.fullAcceptance, false);
  assert.equal(await readFile(join(options.output, 'new-state/closed'), 'utf8'), 'yes');
  assert.equal(report.functional.rows.length, 6);
  assert(report.functional.rows.every(row => row.completed && row.expectedSha256 === row.actualSha256));
});
test('public functional Unknown stops without another sample and still awaits the original close', async t => {
  const options = await fixture(t, true);
  const report = await runNodeWarmBenchmark(options);
  assert.equal(report.stoppedAt, 'warm-select'); assert.equal(report.latency.length, 1);
  assert.equal(report.latency[0].samples.length, 1); assert.equal(report.latency[0].samples[0].verified, false);
  assert.match(report.firstFailure.message, /Unknown; no resend/u);
  assert.equal(report.cleanup.closed, true); assert.equal(report.fullAcceptance, false);
});
test('adapter refuses a changed cohort or altered history protocol before public initialization', async t => {
  const options = await fixture(t);
  const controls = JSON.parse(await readFile(options.controlsPath));
  controls.cohortSha256 = '0'.repeat(64); await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeWarmBenchmark(options));
  controls.cohortSha256 = hash(await readFile(options.manifestPath));
  controls.historyProtocolSha256 = '0'.repeat(64); await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeWarmBenchmark(options));
});
test('the earlier three-family protocol cannot silently qualify the expanded experiment', async t => {
  const options = await fixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  controls.historyProtocolSha256 = '79afac6fecf2e12ded6e1e275a687661c4410b3f5c12194f03bf35d8732634b8';
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeWarmBenchmark(options));
});
test('slow successful diagnostic families stay failed/incomplete but do not hide other family costs', async t => {
  const options = await fixture(t, false, true);
  const report = await runNodeWarmBenchmark(options);
  assert.equal(report.latency.length, 6);
  assert.equal(report.latency[0].samples.length, 1);
  assert.equal(report.latency[1].samples.length, 1);
  assert(report.latency.every(row => row.samples.every(sample => sample.verified)));
  assert(report.diagnosticFindings.some(reason => reason.startsWith('warm-select:')));
  assert(report.diagnosticFindings.some(reason => reason.startsWith('warm-result:')));
  assert(report.assessments.every(row => row.status !== 'passed'));
  assert.equal(report.cleanup.closed, true); assert.equal(report.fullAcceptance, false);
});

test('small public SQL is fixed in the experiment and uses distinct independent row oracles', async t => {
  const options = await fixture(t), report = await runNodeWarmBenchmark(options);
  assert.deepEqual(nodeWarmSmallQueryFixtures.map(row => [row.operation, row.expected]), [
    ['warm-join', [{id: 1, label: 'joined'}]],
    ['warm-union', [{id: 1}, {id: 2}]],
    ['warm-decimal-sum', [{total: '4.00'}]],
  ]);
  assert.deepEqual(report.historyProtocol.smallQueries, nodeWarmSmallQueryFixtures);
  const calls = (await readFile(join(options.output, 'new-state/queries'), 'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(calls, ['SELECT 1 AS id', 'SELECT 1 AS id', 'SELECT 1 AS id',
    ...nodeWarmSmallQueryFixtures.flatMap(row => [row.text, row.text, row.text])]);
  const small = report.latency.slice(3);
  assert.deepEqual(small.map(row => row.operation), ['warm-join', 'warm-union', 'warm-decimal-sum']);
  assert.equal(new Set(small.map(row => row.fixtureSha256)).size, 3);
  for (const series of small) {
    assert.equal(series.fixtureSha256, hash(Buffer.from(JSON.stringify(series.query))));
    assert(series.samples.every(row => row.verified && row.hostId === series.hostId && row.fixtureSha256 === series.fixtureSha256));
  }
  assert(report.assessments.slice(3).every(row => row.target.p95Ms === 500 && row.summary.p95Ms === null));
});
for (const [wrong, operation] of [['join', 'warm-join'], ['union', 'warm-union'], ['decimal', 'warm-decimal-sum']]) {
  test(`${operation} refuses a wrong materialized result without retry or later families`, async t => {
    const options = await fixture(t, false, false, wrong), report = await runNodeWarmBenchmark(options);
    assert.equal(report.firstFailure.operation, operation); assert.equal(report.stoppedAt, operation);
    const last = report.latency.at(-1);
    assert.equal(last.operation, operation); assert.equal(last.samples.length, 1); assert.equal(last.samples[0].verified, false);
    assert.equal(report.functional.rows.at(-1).completed, false);
    assert.equal(report.cleanup.closed, true); assert.equal(report.fullAcceptance, false);
  });
}
