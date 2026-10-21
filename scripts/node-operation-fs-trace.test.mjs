import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {attributeFilesystemOperation, calibrateFilesystemClock, pairFilesystemTrace}
  from './node-operation-fs-trace.mjs';
import {nodeBenchmarkInstrumentation} from './benchmark-node-operations.mjs';
const cat = 'node,node.fs,node.fs.async';
function pair(id, start, end, path) {
  return [{pid: 42, tid: 1, cat, ph: 'b', name: 'access', id, ts: start, args: {path}},
    {pid: 42, tid: 1, cat, ph: 'e', name: 'access', id, ts: end, args: {result: 0}}];
}
test('actual Node trace markers calibrate a standalone filesystem control', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-fs-clock-'));
  try {
    const child = join(root, 'control.mjs'), trace = join(root, 'trace.json'), report = join(root, 'report.json');
    const helper = new URL('./node-operation-fs-trace.mjs', import.meta.url).href;
    await writeFile(child, `import {writeFile,open} from 'node:fs/promises';
import {recordFilesystemClockMarker} from ${JSON.stringify(helper)};
const root=${JSON.stringify(root)},now=()=>Number(process.hrtime.bigint()/1000n),pause=()=>new Promise(r=>setTimeout(r,10));
await writeFile(root+'/before','');await writeFile(root+'/after','');
const markers=[await recordFilesystemClockMarker(root+'/before')];const startUs=now();
await pause();const handle=await open(root+'/data','wx');await handle.write('control');await handle.sync();await handle.close();await pause();
const endUs=now();markers.push(await recordFilesystemClockMarker(root+'/after'));
await writeFile(${JSON.stringify(report)},JSON.stringify({pid:process.pid,markers,startUs,endUs}));
`);
    const result = spawnSync(process.execPath, ['--trace-events-enabled',
      '--trace-event-categories=node.fs.async,node.fs.sync', '--trace-event-file-pattern=' + trace, child],
    {encoding: 'utf8', timeout: 10_000});
    assert.equal(result.status, 0, result.stderr);
    const events = JSON.parse(await readFile(trace, 'utf8')).traceEvents;
    const control = JSON.parse(await readFile(report, 'utf8'));
    const clock = calibrateFilesystemClock(events, control.markers, control.pid);
    const selected = attributeFilesystemOperation(events, control, clock);
    assert.equal(clock.markerCount, 2);
    assert.equal(selected.counts.fsync, 1);
    assert.equal(selected.counts.open, 1);
    assert.equal(selected.counts.close, 1);
    assert.equal(selected.counts.access ?? 0, 0, 'Calibration markers are outside the operation');
    assert.equal(selected.unpaired.length, 0);
    console.log(JSON.stringify({actualNodeControl: true, markerCount: 2, counts: selected.counts,
      clockWidthUs: clock.maximumUs - clock.minimumUs, ordinaryProductExecution: false}));
  } finally {await rm(root, {recursive: true, force: true});}
});
test('missing or failed actual markers cannot manufacture a clock relation', () => {
  const markers = [{path: '/first', beforeUs: 110, afterUs: 120},
    {path: '/last', beforeUs: 210, afterUs: 220}];
  const events = pair('a', 100, 105, '/first');
  assert.throws(() => calibrateFilesystemClock(events, markers, 42), /one actual paired/);
  const failed = [...events, ...pair('b', 200, 205, '/last')];
  failed.at(-1).args.result = -2;
  assert.throws(() => calibrateFilesystemClock(failed, markers, 42), /must succeed/);
});
test('disjoint clock bounds reject rather than assuming a shared epoch', () => {
  const events = [...pair('a', 100, 105, '/first'), ...pair('b', 200, 205, '/last')];
  assert.throws(() => calibrateFilesystemClock(events,
    [{path: '/first', beforeUs: 110, afterUs: 120},
      {path: '/last', beforeUs: 230, afterUs: 240}], 42), /intervals disagree/);
});
test('uncertain boundaries and unmatched events remain separate from completed work', () => {
  const events = [...pair('a', 100, 105, '/inside'), ...pair('b', 90, 99, '/boundary'),
    {pid: 42, tid: 1, cat, ph: 'b', name: 'fsync', id: 'pending', ts: 110, args: {}}];
  const result = attributeFilesystemOperation(events, {pid: 42, startUs: 100, endUs: 120},
    {minimumUs: 0, maximumUs: 10});
  assert.equal(result.contained.length, 1);assert.equal(result.boundary.length, 1);
  assert.equal(result.unpaired.length, 1);assert.deepEqual(result.counts, {access: 1});
  assert.equal(pairFilesystemTrace(events, 99).pairs.length, 0);
});

test('filesystem trace diagnostics cannot qualify as unprofiled benchmark samples', () => {
  for (const flag of ['--trace-events-enabled', '--trace-event-categories=node.fs.async']) {
    assert.equal(nodeBenchmarkInstrumentation({execArgv: [flag], nodeOptions: '', coverage: undefined}).profiled, true);
    assert.equal(nodeBenchmarkInstrumentation({execArgv: [], nodeOptions: flag, coverage: undefined}).profiled, true);
  }
  assert.equal(nodeBenchmarkInstrumentation({execArgv: [], nodeOptions: '', coverage: undefined}).profiled, false);
});
