import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir, arch, platform, release, cpus, totalmem} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {assessPriorityTransition} from './operation-performance.mjs';
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
 return {startSource:async()=>run,sql:(text,parameters,options)=>({all:async()=>{
  await appendFile(stateDir+'/queries',JSON.stringify(text)+'\\n');
  ${fail ? "throw new Error('Unknown; no resend');" : ''}
  ${slow ? 'await delay(110);' : 'await Promise.resolve();'}
  if(text.includes('JOIN rhs'))return ${wrong === 'join' ? "[{id:1,label:'foreign'}]" : "[{id:1,label:'joined'}]"};
  if(text.includes('SUM(amount)'))return ${wrong === 'decimal' ? '[{total:4}]' : "[{total:'4.00'}]"};
  if(text.includes('UNION ALL'))return ${wrong === 'union' ? '[{id:1}]' : '[{id:1},{id:2}]'};
  if(text==='SELECT @id AS id') {
    if(JSON.stringify(parameters)!==JSON.stringify({id:7}) ||
       JSON.stringify(options)!==JSON.stringify({parameterDeclarations:{id:{type:'number'}}}))throw new Error('Public parameter arguments lost');
    return ${wrong === 'parameters' ? '[{id:8}]' : '[{id:7}]'};
  }
  if(text==="SELECT 'é😀' AS label")return ${wrong === 'unicode' ? "[{label:'foreign'}]" : "[{label:'é😀'}]"};
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
  assert.equal(report.latency.length, 8);
  assert(report.assessments.every(row => row.status === 'incomplete' && row.summary.p95Ms === null));
  assert.equal(report.fullAcceptance, false);
  assert.equal(await readFile(join(options.output, 'new-state/closed'), 'utf8'), 'yes');
  assert.equal(report.functional.rows.length, 8);
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
  assert.equal(report.latency.length, 8);
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
    ['warm-parameters', [{id: 7}]],
    ['warm-unicode', [{label: 'é😀'}]],
  ]);
  assert.deepEqual(report.historyProtocol.smallQueries, nodeWarmSmallQueryFixtures);
  const calls = (await readFile(join(options.output, 'new-state/queries'), 'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(calls, ['SELECT 1 AS id', 'SELECT 1 AS id', 'SELECT 1 AS id',
    ...nodeWarmSmallQueryFixtures.flatMap(row => [row.text, row.text, row.text])]);
  const small = report.latency.slice(3);
  assert.deepEqual(small.map(row => row.operation), ['warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']);
  assert.equal(new Set(small.map(row => row.fixtureSha256)).size, 5);
  for (const series of small) {
    assert.equal(series.fixtureSha256, hash(Buffer.from(JSON.stringify(series.query))));
    assert(series.samples.every(row => row.verified && row.hostId === series.hostId && row.fixtureSha256 === series.fixtureSha256));
  }
  assert(report.assessments.slice(3).every(row => row.target.comparison === 'local-sqlite' &&
    row.summary.p95Ms === null && row.missing.includes('measured fixed SQLite comparison profile')));
});
test('parameter fixture follows the public sql(text, parameters, options) contract', async t => {
  const options = await fixture(t), report = await runNodeWarmBenchmark(options);
  assert.equal(report.firstFailure, undefined);
  const parameter = report.latency.find(row => row.operation === 'warm-parameters');
  assert.equal(parameter.samples.length, 3);
  assert(parameter.samples.every(row => row.verified));
  assert.deepEqual(parameter.query.parameters, {id: 7});
  assert.deepEqual(parameter.query.options, {parameterDeclarations: {id: {type: 'number'}}});
  assert.equal(report.cleanup.closed, true);
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
for (const [wrong, operation] of [['join', 'warm-join'], ['union', 'warm-union'], ['decimal', 'warm-decimal-sum'],
  ['parameters', 'warm-parameters'], ['unicode', 'warm-unicode']]) {
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

async function resourceFixture(t, fault = '', mode = 'diagnostic') {
  const options = await priorityFixture(t, ['unknown', 'package'].includes(fault) ? fault : '', mode);
  const root = options.manifestPath.slice(0, -'/release.json'.length);
  const nodeFile = join(options.consumer, 'node_modules/@actql/node/index.mjs');
  let code = await readFile(nodeFile, 'utf8');
  code = code.replace('open({stateDir})', 'open({stateDir,installation})')
    .replace('const ref={id:id};', "const ref={namespaceId:'local',authorityScopeCid:'sha256:'+'a'.repeat(64),runDefinitionCid:'sha256:'+String(id).padStart(64,'0')};")
    .replace("await event('saved',id);return[{id}];", "await event('saved',id);installation?.observation.record(ref);return[{id}];")
    .replace('all:async()=>(await ensure()).rows', 'all:async()=>{const v=await ensure();installation?.observation.record(v.selected.execution.ref);return v.rows;}')
    .replace("closed=true;await event('close',null);", "closed=true;await installation?.observation.close();await event('close',null);");
  await writeFile(nodeFile, code);
  const scalars = {
    'actql.resource.limit.planning_work': '100000', 'actql.resource.limit.attempts': '1',
    'actql.resource.limit.holdings': '1', 'actql.resource.limit.transfer_bytes': '1000000',
    'actql.resource.limit.retained_bytes': '200000000', 'actql.resource.limit.execution_bytes': '536870912',
    'actql.resource.usage.planning': '0', 'actql.resource.usage.attempts': '1',
    'actql.resource.usage.holdings': '1', 'actql.resource.usage.transferred': '0',
    'actql.resource.usage.uncertain': '0', 'actql.resource.usage.reserved_transfer': '0',
    'actql.resource.usage.held_bytes': '0', 'actql.resource.usage.reserved_retention': '0',
    'actql.resource.usage.reserved_execution': '0', 'actql.resource.usage.peak_retention': '14240000',
  };
  // Synthetic observation transport only. These values are not measured usage.
  const observer = `export function createHostObservationConnection({deliver,currentContext}){
 let sequence=0,closed=false;
 return{record(ref){
  const attributes={'actql.resource.scope':'managed-run-ledger','actql.run.definition_cid':ref.runDefinitionCid,...${JSON.stringify(scalars)}};
  ${fault === 'scalar' ? "delete attributes['actql.resource.usage.held_bytes'];" : ''}
  ${fault === 'foreign' ? "attributes['actql.run.definition_cid']='sha256:'+'f'.repeat(64);" : ''}
  const record={version:'actql-observation/0.1',operation:'compute',event:'resources_observed',sequence:sequence++,parent:currentContext(),attributes};
  ${fault === 'missing' ? '' : 'deliver(record);'}
  ${fault === 'duplicate' ? 'deliver({...record,sequence:sequence++});' : ''}
 },status(){return{dropped:0,deliveryFailed:0,budgetUnavailable:0,queueOverflow:0,limited:0,repeated:0,queued:0,queuedBytes:0,active:0,activeSegments:0,closed,cleanupPending:false,loss:{}};},async close(){closed=true;}};
}`;
  const file = 'adapters/host-common/observation.mjs';
  const observerRoot = join(options.consumer, 'node_modules/@actql/local-node');
  await mkdir(join(observerRoot, 'adapters/host-common'), {recursive: true});
  await writeFile(join(observerRoot, file), observer, {mode: 0o644});
  const tar = Buffer.from('synthetic observer transport, not an ordinary package');
  await writeFile(join(root, 'observer.tgz'), tar);
  const manifest = JSON.parse(await readFile(options.manifestPath));
  manifest.packages[0].files[0] = {path: 'index.mjs', bytes: Buffer.byteLength(code), mode: 0o644, sha256: hash(Buffer.from(code))};
  manifest.packages.push({name: '@actql/local-node', file: 'observer.tgz', bytes: tar.length,
    sha256: hash(tar), integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'),
    files: [{path: file, bytes: Buffer.byteLength(observer), mode: 0o644, sha256: hash(Buffer.from(observer))}]});
  await writeFile(options.manifestPath, JSON.stringify(manifest));
  const controls = JSON.parse(await readFile(options.controlsPath));
  options.resourceObservations = 'managed-run-ledger';
  controls.cohortSha256 = hash(await readFile(options.manifestPath));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodePriorityProtocol(mode, options.resourceObservations))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  return options;
}

test('priority managed Run resources bind actual public calls without manufacturing a population', async t => {
  const options = await resourceFixture(t), report = await runNodePriorityBenchmark(options);
  const captured = report.managedRunObservations;
  assert.equal(captured.status, 'passed'); assert.equal(captured.scope, 'managed-run-ledger');
  assert.equal(captured.operations.length, 7); assert.equal(captured.records.length, 7);
  assert.equal(captured.afterClose.closed, true); assert.equal(captured.afterClose.cleanupPending, false);
  const samples = [report.firstQuery, ...report.latency.flatMap(row => row.samples)];
  assert.deepEqual(captured.operations.map(row => row.publicOperationId), samples.map(row => row.publicOperationId));
  assert(captured.records.every(row => Object.keys(row.scalars).length === 16));
  assert.equal(captured.records[0].scalars['actql.resource.usage.held_bytes'], '0');
  assert(report.latency.every(row => !Object.hasOwn(row, 'population')));
  assert.equal(report.priorityAssessment.gates.node.status, 'incomplete');
  assert(report.priorityAssessment.gates.node.missing.some(reason => reason.includes('population')));
  const events = await priorityEvents(options);
  assert.deepEqual(events.filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2, 3]);
  assert.equal(events.filter(row => row.kind === 'saved').length, 3);
  assert.equal(events.filter(row => row.kind === 'close').length, 1);
  const foreign = structuredClone(report); foreign.managedRunObservations.environmentSha256 = 'f'.repeat(64);
  assert.throws(() => assessPriorityTransition({sourceSha: foreign.sourceSha, platforms: {node: [foreign]}}), /Managed Run observation differs/u);
  const mixed = structuredClone(report); mixed.managedRunObservations.operations[0].runRefSha256 = 'f'.repeat(64);
  assert.equal(assessPriorityTransition({sourceSha: mixed.sourceSha, platforms: {node: [mixed]}}).gates.node.status, 'failed');
});
for (const fault of ['foreign', 'scalar', 'duplicate', 'missing']) {
  test(`priority managed Run ${fault} observation cannot qualify requested collection`, async t => {
    const options = await resourceFixture(t, fault), report = await runNodePriorityBenchmark(options);
    const expected = fault === 'missing' ? 'incomplete' : 'failed';
    assert.equal(report.managedRunObservations.status, expected);
    assert.equal(report.priorityAssessment.gates.node.status, expected);
    assert.equal(report.cleanup.closed, true);
    assert(report.functional.rows.every(row => row.completed), 'Collection failure must not invent a failed product row');
    assert(report.latency.every(row => !Object.hasOwn(row, 'population')));
  });
}
test('priority managed Run observation retains Unknown and closes without a saved-read tail', async t => {
  const options = await resourceFixture(t, 'unknown'), report = await runNodePriorityBenchmark(options);
  assert.equal(report.firstFailure.code, 'SubmissionUnknown'); assert.equal(report.cleanup.closed, true);
  assert.equal(report.managedRunObservations.status, 'incomplete');
  assert.equal(report.managedRunObservations.afterClose.closed, true);
  assert.equal(report.publicCallAttempts.savedResultAll, 0);
  assert.deepEqual((await priorityEvents(options)).filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2]);
});
test('priority managed Run package failure retains raw observations without qualifying their cohort', async t => {
  const options = await resourceFixture(t, 'package'), report = await runNodePriorityBenchmark(options);
  assert(report.packageFailure); assert.equal(report.cleanup.closed, true);
  assert.equal(report.managedRunObservations.records.length, 7);
  assert.equal(report.managedRunObservations.status, 'failed');
  assert(report.managedRunObservations.failures.some(row => /package correspondence/u.test(row.message)));
  assert(report.functional.rows.every(row => !row.completed && !Object.hasOwn(row, 'actualSha256')));
  assert.equal(report.priorityAssessment.gates.node.status, 'failed');
});
test('priority managed Run final synthetic transport stays bounded to the actual 201 public calls', async t => {
  const options = await resourceFixture(t, '', 'final'), report = await runNodePriorityBenchmark(options);
  assert.equal(report.managedRunObservations.status, 'passed');
  assert.equal(report.managedRunObservations.records.length, 201);
  assert.equal(report.managedRunObservations.operations.length, 201);
  assert.equal(report.priorityAssessment.status, 'incomplete');
});
test('priority managed Run CLI selection is explicit and remains incomplete for missing public evidence', async t => {
  const options = await resourceFixture(t);
  const result = spawnSync(process.execPath, [new URL('./benchmark-node-operations.mjs', import.meta.url).pathname,
    '--selection', 'priority-transition', '--resource-observations', 'managed-run-ledger',
    '--manifest', options.manifestPath, '--consumer', options.consumer, '--output', options.output,
    '--controls', options.controlsPath, '--mode', options.mode], {encoding: 'utf8'});
  assert.equal(result.status, 1, result.stderr); assert.equal(result.signal, null);
  const report = JSON.parse(await readFile(join(options.output, 'measurements.json')));
  assert.equal(report.managedRunObservations.status, 'passed'); assert.equal(report.cleanup.closed, true);
  assert.equal(report.priorityAssessment.gates.node.status, 'incomplete');
});
test('priority managed Run collection requires a verified installed module before public import', async t => {
  const options = await priorityFixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  options.resourceObservations = 'managed-run-ledger';
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodePriorityProtocol(options.mode, options.resourceObservations))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  const report = await runNodePriorityBenchmark(options);
  assert.match(report.firstFailure.message, /Verified installed observation module required/u);
  assert.equal(report.publicCallAttempts.sql, 0); assert.equal(report.cleanup.closed, false);
  await assert.rejects(readFile(options.importMarker), {code: 'ENOENT'});
});

async function rowFixture(t, fault = '', both = false) {
  const options = await resourceFixture(t, ['unknown', 'package'].includes(fault) ? fault : '');
  const observerFile = join(options.consumer, 'node_modules/@actql/local-node/adapters/host-common/observation.mjs');
  const original = (await readFile(observerFile, 'utf8'))
    .replace('export function createHostObservationConnection', 'function createResourceConnection');
  // Synthetic projected rows only. They are not product reads or DB metrics.
  const observer = original + `
export function createHostObservationConnection(options){
 let sequence=0;
 const resource=createResourceConnection({...options,deliver:record=>options.deliver({...record,sequence:sequence++})});
 return{record(ref){
  if(options.measurements.include.includes('resources'))resource.record(ref);
  for(let index=0;index<2;index++){
   const attributes={'actql.rows.owner':'request-journal','actql.rows.selection':index?'request':'run-definition',
    'actql.rows.kind':'run','actql.rows.returned':index?0:1,'actql.rows.coverage':'selected-returned',
    'actql.run.definition_cid':ref.runDefinitionCid,...(index?{'actql.rows.unrelated':0}:{})};
   ${fault === 'foreign' ? "attributes['actql.run.definition_cid']='sha256:'+'f'.repeat(64);" : ''}
   ${fault === 'missing-run' ? "delete attributes['actql.run.definition_cid'];" : ''}
   ${fault === 'scalar' ? "attributes['actql.rows.returned']='1';" : ''}
   const record={version:'actql-observation/0.1',operation:'run',event:'selected_rows_observed',
    sequence:sequence++,parent:options.currentContext(),attributes};
   ${fault === 'context' ? "record.parent={traceId:'f'.repeat(32),spanId:'f'.repeat(16)};" : ''}
   ${fault === 'missing' ? '' : 'options.deliver(record);'}
  }
 },status(){return{...resource.status(),${fault === 'loss' ? "dropped:1,loss:{rowsUnavailable:1}," : ''}repeated:3};},close:()=>resource.close()};
}`;
  await writeFile(observerFile, observer);
  const manifest = JSON.parse(await readFile(options.manifestPath));
  // The base synthetic observer artifact is rebound to its new exact bytes.
  const pkg = manifest.packages.find(row => row.name === '@actql/local-node');
  pkg.files[0] = {...pkg.files[0], bytes: Buffer.byteLength(observer), sha256: hash(Buffer.from(observer))};
  await writeFile(options.manifestPath, JSON.stringify(manifest));
  delete options.resourceObservations;
  if (both) options.resourceObservations = 'managed-run-ledger';
  options.rowObservations = 'selected-returned';
  const controls = JSON.parse(await readFile(options.controlsPath));
  controls.cohortSha256 = hash(await readFile(options.manifestPath));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodePriorityProtocol(options.mode,
    options.resourceObservations, options.rowObservations))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  return options;
}

test('priority selected rows preserve actual multiplicity and missing classification without a population claim', async t => {
  const options = await rowFixture(t), report = await runNodePriorityBenchmark(options);
  const captured = report.selectedRowObservations;
  assert.equal(captured.status, 'passed'); assert.equal(captured.records.length, 14);
  assert.equal(captured.operations.length, 7);
  assert(captured.operations.every(row => row.rowObservationSequences.length === 2));
  assert(captured.records.filter(row => row.selection === 'run-definition').every(row => !Object.hasOwn(row, 'unrelated')));
  assert(captured.records.filter(row => row.selection === 'request').every(row => row.unrelated === 0));
  assert.equal(captured.afterClose.repeated, 3, 'Deduplicated lifecycle events are not missing row records');
  assert(report.latency.every(row => !Object.hasOwn(row, 'population')));
  assert.equal(report.priorityAssessment.gates.node.status, 'incomplete');
  const foreign = structuredClone(report); foreign.selectedRowObservations.environmentSha256 = 'f'.repeat(64);
  assert.throws(() => assessPriorityTransition({sourceSha: foreign.sourceSha, platforms: {node: [foreign]}}), /Selected row observation differs/u);
  const unmatched = structuredClone(report); unmatched.selectedRowObservations.operations[0].rowObservationSequences = [999];
  assert.equal(assessPriorityTransition({sourceSha: unmatched.sourceSha, platforms: {node: [unmatched]}}).gates.node.status, 'failed');
  const unrelated = structuredClone(report); unrelated.selectedRowObservations.records[0].unrelated = 1;
  assert.equal(assessPriorityTransition({sourceSha: unrelated.sourceSha, platforms: {node: [unrelated]}}).gates.node.status, 'failed');
});
for (const fault of ['foreign', 'scalar', 'missing', 'loss', 'context', 'missing-run']) {
  test(`priority selected rows ${fault} cannot qualify requested collection`, async t => {
    const options = await rowFixture(t, fault), report = await runNodePriorityBenchmark(options);
    const expected = ['missing', 'loss', 'missing-run'].includes(fault) ? 'incomplete' : 'failed';
    assert.equal(report.selectedRowObservations.status, expected);
    assert.equal(report.priorityAssessment.gates.node.status, expected);
    assert.equal(report.cleanup.closed, true);
    assert(report.functional.rows.every(row => row.completed));
    if (fault === 'missing-run') assert(report.selectedRowObservations.records.every(row => !Object.hasOwn(row, 'runDefinitionCid')));
    if (fault === 'loss') assert.deepEqual(report.selectedRowObservations.afterClose.loss, {rowsUnavailable: 1});
  });
}
test('priority selected rows and managed resources bind the same seven public operations', async t => {
  const options = await rowFixture(t, '', true), report = await runNodePriorityBenchmark(options);
  assert.equal(report.managedRunObservations.status, 'passed');
  assert.equal(report.selectedRowObservations.status, 'passed');
  assert.equal(report.managedRunObservations.records.length, 7);
  assert.deepEqual(report.managedRunObservations.operations.map(row => row.publicOperationId),
    report.selectedRowObservations.operations.map(row => row.publicOperationId));
  assert.equal(report.priorityAssessment.status, 'incomplete');
});
test('priority selected rows package failure cannot retain functional or collection qualification', async t => {
  const options = await rowFixture(t, 'package'), report = await runNodePriorityBenchmark(options);
  assert.equal(report.selectedRowObservations.status, 'failed');
  assert.equal(report.selectedRowObservations.records.length, 14);
  assert.equal(report.priorityAssessment.gates.node.status, 'failed');
  assert(report.functional.rows.every(row => !row.completed && !Object.hasOwn(row, 'actualSha256')));
});
test('priority selected rows retain Unknown without retry or saved-read continuation', async t => {
  const options = await rowFixture(t, 'unknown'), report = await runNodePriorityBenchmark(options);
  assert.equal(report.firstFailure.code, 'SubmissionUnknown');
  assert.equal(report.selectedRowObservations.status, 'incomplete');
  assert.equal(report.publicCallAttempts.savedResultAll, 0); assert.equal(report.cleanup.closed, true);
  assert.deepEqual((await priorityEvents(options)).filter(row => row.kind === 'submit').map(row => row.id), [0, 1, 2]);
});
test('priority selected rows CLI is explicit and cannot turn partial rows into population acceptance', async t => {
  const options = await rowFixture(t);
  const result = spawnSync(process.execPath, [new URL('./benchmark-node-operations.mjs', import.meta.url).pathname,
    '--selection', 'priority-transition', '--row-observations', 'selected-returned',
    '--manifest', options.manifestPath, '--consumer', options.consumer, '--output', options.output,
    '--controls', options.controlsPath, '--mode', options.mode], {encoding: 'utf8'});
  assert.equal(result.status, 1, result.stderr);
  const report = JSON.parse(await readFile(join(options.output, 'measurements.json')));
  assert.equal(report.selectedRowObservations.status, 'passed');
  assert.equal(report.priorityAssessment.gates.node.status, 'incomplete');
  assert.throws(() => nodePriorityProtocol('diagnostic', undefined, 'all-reads'));
});
