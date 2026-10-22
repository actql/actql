import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir, arch, platform, release, cpus, totalmem} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nodeBenchmarkInstrumentation, nodeWarmSmallQueryFixtures, runNodeWarmBenchmark, nodeWarmProtocol,
  nodePriorityProtocol, runNodePriorityBenchmark, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

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
async function fixture(t, fail = false, slow = false, wrong = '', markImport = false) {
  const root = await mkdtemp(join(tmpdir(), 'actql-benchmark-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packageRoot = join(root, 'consumer/node_modules/@actql/node');
  await mkdir(packageRoot, {recursive: true});
  // Explicit synthetic public-port double tests collector/cleanup behavior only.
  // These bytes are not an ordinary product cohort or a latency observation.
  const code = Buffer.from(`import {appendFile,mkdir,writeFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
${markImport ? `await writeFile(${JSON.stringify(join(root, 'imported'))},'yes');` : ''}
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
  return {manifestPath, consumer: join(root, 'consumer'), controlsPath, output: join(root, 'new-benchmark'),
    importMarker: join(root, 'imported'), mode: 'diagnostic'};
}
test('public warm adapter verifies output, awaits close, retains samples without claiming final p95', async t => {
  const options = await fixture(t);
  const controls = JSON.parse(await readFile(options.controlsPath));
  // Explicitly incomplete synthetic metadata tests transport only; no baseline
  // measurements, actual durability correspondence or speed are invented here.
  controls.comparison = {baseline: null, profile: {qualification: 'synthetic incomplete profile'}};
  controls.comparisonMatches = {'warm-select': {qualification: 'explicit synthetic workload statement'}};
  controls.comparisonSettings = {qualification: 'not a measured product setting'};
  await writeFile(options.controlsPath, JSON.stringify(controls));
  const report = await runNodeWarmBenchmark(options);
  assert.equal(report.cleanup.closed, true); assert.equal(report.installedPayloadsUnchanged, true);
  assert.equal(report.latency.length, 6);
  assert(report.assessments.every(row => row.status === 'incomplete' && row.summary.p95Ms === null));
  assert.equal(report.fullAcceptance, false);
  assert.equal(await readFile(join(options.output, 'new-state/closed'), 'utf8'), 'yes');
  assert.equal(report.functional.rows.length, 6);
  assert(report.functional.rows.every(row => row.completed && row.expectedSha256 === row.actualSha256));
  assert.deepEqual(report.comparison, controls.comparison);
  assert.deepEqual(report.latency[0].comparisonMatch, controls.comparisonMatches['warm-select']);
  assert.deepEqual(report.latency[0].comparisonSettings, controls.comparisonSettings);
  assert.equal(report.latency[0].expectedSha256, report.functional.rows[0].expectedSha256);
  assert.match(report.latency[0].executableSha256, /^[a-f0-9]{64}$/u);
});
test('Result storage matching facts come only from explicit experiment controls', async t => {
  const options = await fixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  controls.resultStorageMatches = {'warm-result': {qualification: 'explicit synthetic actual-context statement'}};
  await writeFile(options.controlsPath, JSON.stringify(controls));
  const report = await runNodeWarmBenchmark(options);
  assert.deepEqual(report.latency.find(row => row.operation === 'warm-result').resultStorageMatch,
    controls.resultStorageMatches['warm-result']);
  assert(report.latency.filter(row => row.operation !== 'warm-result').every(row => row.resultStorageMatch === undefined));
  assert.equal(report.cleanup.closed, true);
  assert.equal(report.assessments.find(row => row.operation === 'warm-result').status, 'incomplete');
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
  assert(report.assessments.slice(3).every(row => row.target.comparison === 'local-sqlite' &&
    row.summary.p95Ms === null && row.missing.includes('measured fixed SQLite comparison profile')));
});
test('final collector refuses a missing comparison before importing or opening the public product', async t => {
  const options = await fixture(t, false, false, '', true);
  options.mode = 'final';
  const controls = JSON.parse(await readFile(options.controlsPath));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodeWarmProtocol('final'))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeWarmBenchmark(options), /Final comparison profile incomplete before public open/u);
  await assert.rejects(readFile(options.importMarker), {code: 'ENOENT'});
  await assert.rejects(readFile(join(options.output, 'new-state/closed')), {code: 'ENOENT'});
  await assert.rejects(readFile(join(options.output, 'new-state/queries')), {code: 'ENOENT'});
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

async function priorityFixture(t, fault = '', mode = 'diagnostic') {
  const root = await mkdtemp(join(tmpdir(), 'actql-priority-collector-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const base = join(root, 'consumer/node_modules/@actql/node'); await mkdir(base, {recursive: true});
  // Synthetic public-port sequencing only: no ordinary package, actual product
  // duration, resource observation or safety qualification is supplied here.
  const code = Buffer.from(`import assert from 'node:assert/strict';
import {appendFile,mkdir,writeFile} from 'node:fs/promises';
await writeFile(${JSON.stringify(join(root, 'imported'))},'yes');
export async function open({stateDir}) {
 await mkdir(stateDir); let closed=false;
 const event=(kind,id)=>appendFile(stateDir+'/events',JSON.stringify({kind,id})+'\\n');
 return {info:{stateDir},sql(text) {
  let promise;
  const ensure=()=>promise??=(async()=>{
   const id=Number(/^SELECT (\\d+) AS id$/.exec(text)?.[1]);assert(Number.isInteger(id));await event('submit',id);
   ${fault === 'unknown' ? "if(id===2)throw Object.assign(new Error('Unknown; no resend'),{code:'SubmissionUnknown'});" : ''}
   ${fault === 'nested-unknown' ? `if(id===2){
    const cause=Object.assign(new Error('underlying observation refused'),{code:'LocalObservationRefused',status:500,requestId:'original-request'});
    Object.defineProperty(cause,'original_error',{value:Object.assign(new Error('selected resource issue'),{code:'SelectedResourceIssue'})});
    const execution={ref:{namespaceId:'local',authorityScopeCid:'scope-original',runDefinitionCid:'run-original'},
      status(){event('unexpected-status',id);throw new Error('must not query');},
      result(){event('unexpected-result',id);throw new Error('must not read');}};
    const error=Object.assign(new Error('QueryObservationUnknown'),{code:'QueryObservationUnknown',requestId:'original-request',cleanupPending:true});
    Object.defineProperties(error,{cause:{value:cause},execution:{value:execution},
      observation:{value:{run_id:'original-run',status:'resuming',revision:2,result_available:false}}});
    throw error;
   }` : ''}
   const rows=${fault === 'wrong' ? 'id===2?[{id:999}]:[{id}]' : '[{id}]'};
   const ref={id:${fault === 'same-run' ? "'same'" : 'id'}};
   const execution={ref,result(name){assert.equal(name,'main');return{all:async()=>{await event('saved',id);return[{id}];}};}};
   return{rows,selected:{ref:{run:ref,resultName:'main'},execution}};
  })();
  return{all:async()=>(await ensure()).rows,then:(resolve,reject)=>ensure().then(value=>value.selected).then(resolve,reject)};
 },close:async()=>{assert(!closed);closed=true;await event('close',null);
 ${fault === 'package' ? `await appendFile(${JSON.stringify(join(base, 'index.mjs'))},'\\n// changed during close\\n');` : ''}
 }};
}`);
  await writeFile(join(base, 'index.mjs'), code, {mode: 0o644});
  const tar = Buffer.from('synthetic package identity, not an ordinary tarball'); await writeFile(join(root, 'test.tgz'), tar);
  const manifestPath = join(root, 'release.json');
  await writeFile(manifestPath, JSON.stringify({sourceSha: 'a'.repeat(40), packages: [{name: '@actql/node',
    file: 'test.tgz', bytes: tar.length, sha256: hash(tar), integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'),
    files: [{path: 'index.mjs', bytes: code.length, mode: 0o644, sha256: hash(code)}]}]}));
  const controlsPath = join(root, 'controls.json');
  await writeFile(controlsPath, JSON.stringify({sourceSha: 'a'.repeat(40), cohortSha256: hash(await readFile(manifestPath)),
    environment: {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
      cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()}, load: 'isolated',
    historyProtocolSha256: hash(Buffer.from(JSON.stringify(nodePriorityProtocol(mode))))}));
  return {manifestPath, controlsPath, consumer: join(root, 'consumer'), output: join(root, 'new-priority'),
    importMarker: join(root, 'imported'), mode};
}
const priorityEvents = async options => (await readFile(join(options.output, 'new-state/events'), 'utf8'))
  .trim().split('\n').map(JSON.parse);

test('priority collector binds varied new Runs and saved originals to raw rows without inventing missing work', async t => {
  const options = await priorityFixture(t), report = await runNodePriorityBenchmark(options);
  assert.equal(report.cleanup.closed, true); assert.equal(report.installedPayloadsUnchanged, true);
  assert.equal(report.executionPath, 'node-sdk'); assert.equal(report.selection, 'priority-transition');
  assert.deepEqual(report.publicCallAttempts, {sql: 4, savedResultAll: 3});
  assert.equal(report.firstQuery.verified, true); assert.equal(report.latency.length, 2);
  const [fresh, saved] = report.latency;
  assert.equal(fresh.samples.length, 3); assert.equal(saved.samples.length, 3);
  assert.equal(new Set(fresh.samples.map(row => row.runRefSha256)).size, 3);
  assert.equal(new Set(saved.samples.map(row => row.resultRefSha256)).size, 3);
  assert.equal(new Set(fresh.samples.map(row => row.actualSha256)).size, 3);
  assert(fresh.samples.every(row => row.publicOperationId !== report.firstQuery.publicOperationId &&
    row.runRefSha256 !== report.firstQuery.runRefSha256));
  for (const series of report.latency) {
    assert.equal(series.fixtureSha256, hash(Buffer.from(JSON.stringify(series.publicWorkload))));
    assert(series.samples.every(row => row.pid === report.firstQuery.pid && row.hostId === report.firstQuery.hostId &&
      row.stateId === report.firstQuery.stateId && row.verified));
    const functional = report.functional.rows.find(row => row.operation === series.operation);
    assert.equal(functional.completed, true);
    assert.equal(functional.expectedSha256, hash(Buffer.from(JSON.stringify(series.samples.map(row => row.expectedSha256)))));
    assert.equal(functional.actualSha256, hash(Buffer.from(JSON.stringify(series.samples.map(row => row.actualSha256)))));
    assert.equal(Object.hasOwn(series, 'population'), false);
  }
  assert.deepEqual(report.priorityConditions, {startedHost: true});
  assert.equal(report.priorityAssessment.status, 'incomplete'); assert.equal(report.fullAcceptance, false);
  assert.equal(report.priorityAssessment.gates.node.checks['warm-select workload'].status, 'passed');
  assert.equal(report.priorityAssessment.gates.node.checks['warm-result workload'].status, 'passed');
  assert.deepEqual((await priorityEvents(options)).filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2, 3]);
});
test('priority final selection collects 100 synthetic samples per route without requiring the full SQLite profile', async t => {
  const options = await priorityFixture(t, '', 'final'), report = await runNodePriorityBenchmark(options);
  assert.deepEqual(report.latency.map(row => row.samples.length), [100, 100]);
  assert.deepEqual(report.publicCallAttempts, {sql: 101, savedResultAll: 100});
  assert.equal(report.savedOriginals.length, 3);
  assert.equal(report.priorityAssessment.gates.node.checks['warm-select workload'].status, 'passed');
  assert.equal(report.priorityAssessment.gates.node.checks['warm-result workload'].status, 'passed');
  assert.equal(report.priorityAssessment.status, 'incomplete');
  assert(report.priorityAssessment.gates.node.missing.some(reason => reason.includes('population')));
  assert.equal(Object.hasOwn(report, 'comparison'), false);
});
test('priority Unknown stops at its first actual attempt with no stale Run identity or saved-read tail', async t => {
  const options = await priorityFixture(t, 'unknown'), report = await runNodePriorityBenchmark(options);
  assert.equal(report.firstFailure.code, 'SubmissionUnknown'); assert.equal(report.cleanup.closed, true);
  assert.equal(report.latency.length, 1); assert.equal(report.latency[0].samples.length, 2);
  const failed = report.latency[0].samples[1];
  assert.equal(failed.verified, false); assert.equal(Object.hasOwn(failed, 'runRefSha256'), false);
  assert.equal(Object.hasOwn(failed, 'actualSha256'), false); assert.equal(report.publicCallAttempts.savedResultAll, 0);
  assert.deepEqual((await priorityEvents(options)).filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2]);
});
test('priority package-fence failure cannot retain a positive functional qualification', async t => {
  const options = await priorityFixture(t, 'package'), report = await runNodePriorityBenchmark(options);
  assert(report.packageFailure); assert.equal(report.cleanup.closed, true);
  assert(report.functional.rows.every(row => row.completed === false && !Object.hasOwn(row, 'actualSha256')));
  assert.equal(report.priorityAssessment.status, 'failed');
});
for (const fault of ['wrong', 'same-run']) {
  test(`priority ${fault} refuses without continuing new submissions or saved reads`, async t => {
    const options = await priorityFixture(t, fault), report = await runNodePriorityBenchmark(options);
    assert.equal(report.firstFailure.operation, 'warm-select'); assert.equal(report.cleanup.closed, true);
    assert.equal(report.latency.length, 1); assert.equal(report.functional.rows[0].completed, false);
    assert.equal(report.publicCallAttempts.savedResultAll, 0);
    assert.equal(report.publicCallAttempts.sql, fault === 'wrong' ? 3 : 2);
    assert.equal(report.priorityAssessment.status, 'failed');
  });
}
test('priority foreign protocol refuses before public import and cannot reuse a full-mode fixture identity', async t => {
  const options = await priorityFixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodeWarmProtocol('diagnostic'))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodePriorityBenchmark(options));
  await assert.rejects(readFile(options.importMarker), {code: 'ENOENT'});
});
test('priority CLI emits raw observations but remains nonzero for missing population and safety evidence', async t => {
  const options = await priorityFixture(t);
  const result = spawnSync(process.execPath, [new URL('./benchmark-node-operations.mjs', import.meta.url).pathname,
    '--selection', 'priority-transition', '--manifest', options.manifestPath, '--consumer', options.consumer,
    '--output', options.output, '--controls', options.controlsPath, '--mode', options.mode], {encoding: 'utf8'});
  assert.equal(result.signal, null); assert.equal(result.status, 1, result.stderr);
  const printed = JSON.parse(result.stdout);
  assert.equal(printed.selection, 'priority-transition'); assert.equal(printed.assessment.status, 'incomplete');
  const raw = JSON.parse(await readFile(join(options.output, 'measurements.json')));
  assert.deepEqual(raw.latency.map(row => row.samples.length), [3, 3]);
  assert.equal(raw.cleanup.closed, true); assert.equal(raw.installedPayloadsUnchanged, true);
  assert.equal(Object.hasOwn(raw.latency[0], 'population'), false);
});


test('priority retains nonenumerable failure causes and original execution data without another public call', async t => {
  const options = await priorityFixture(t, 'nested-unknown');
  const result = spawnSync(process.execPath, [new URL('./benchmark-node-operations.mjs', import.meta.url).pathname,
    '--selection', 'priority-transition', '--manifest', options.manifestPath, '--consumer', options.consumer,
    '--output', options.output, '--controls', options.controlsPath, '--mode', options.mode], {encoding: 'utf8'});
  assert.equal(result.status, 1, result.stderr); assert.equal(result.signal, null);
  const report = JSON.parse(await readFile(join(options.output, 'measurements.json')));
  assert.equal(report.firstFailure.code, 'QueryObservationUnknown');
  assert.deepEqual(report.firstFailure.errorChain.map(row => [row.edge, row.code]),
    [['primary', 'QueryObservationUnknown'], ['cause', 'LocalObservationRefused'], ['original_error', 'SelectedResourceIssue']]);
  assert.equal(report.firstFailure.requestId, 'original-request');
  assert.equal(report.firstFailure.cleanupPending, true);
  assert.equal(report.firstFailure.errorChain[1].status, 500);
  assert.equal(report.firstFailure.errorChain[1].requestId, 'original-request');
  assert.deepEqual(report.firstFailure.executionRef,
    {namespaceId: 'local', authorityScopeCid: 'scope-original', runDefinitionCid: 'run-original'});
  assert.deepEqual(report.firstFailure.observation,
    {run_id: 'original-run', status: 'resuming', revision: 2, result_available: false});
  assert.equal(report.cleanup.closed, true); assert.equal(report.installedPayloadsUnchanged, true);
  assert.equal(report.publicCallAttempts.savedResultAll, 0);
  assert.equal(report.latency[0].samples.at(-1).verified, false);
  assert.equal(Object.hasOwn(report.latency[0].samples.at(-1), 'runRefSha256'), false);
  const events = await priorityEvents(options);
  assert.deepEqual(events.filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2]);
  assert.equal(events.filter(row => row.kind === 'close').length, 1);
  assert(!events.some(row => row.kind.startsWith('unexpected-')));
});

test('failure diagnostics bound cycles and text without evaluating accessors or serializing live handles', () => {
  const first = new Error('x'.repeat(4096)); let getterCalls = 0, toJSONCalls = 0;
  Object.defineProperty(first, 'execution', {get() {getterCalls++; throw new Error('unexpected accessor');}});
  first.toJSON = () => {toJSONCalls++; throw new Error('unexpected serialization');};
  let tail = first;
  for (let n = 0; n < 12; n++) {const next = new Error(String(n)); tail.cause = next; tail = next;}
  tail.cause = first;
  const report = nodeBenchmarkFailure(first);
  assert.equal(report.message.length, 2048); assert.equal(report.errorChain.length, 8);
  assert.equal(report.errorChainTruncated, true); assert.equal(getterCalls, 0);
  assert.doesNotThrow(() => JSON.stringify(report)); assert.equal(toJSONCalls, 0);
});
