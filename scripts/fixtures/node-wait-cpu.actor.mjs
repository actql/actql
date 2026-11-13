// The parent stages this harness beside the verified ordinary installation.
// Only wait is sampled. Full rows, EOF and first close remain independent.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {Session} from 'node:inspector';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {observeRecordApprovalDescriptors} from './scoped-fds.fixture.mjs';

const [output, ...extra] = process.argv.slice(2); assert(output && extra.length === 0);
const count = 100000, stateDir = join(output, 'fresh-state');
const report = {node: process.version, platform: process.platform, arch: process.arch,
  count, submissions: 0, firstClose: 'unobserved', phases: [], complete: false,
  installation: {sourceFreeMaxWork: 30000000,
    requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824}},
  history: 'Fresh Host with one query; the same SQL as the README collection 100k case, not its preceding smaller-query history.',
  qualification: 'One instrumented wait; no causal speedup, percentiles, call counts or full-machine isolation claim.'};
let client, session, active = false, primary;
const post = (method, params = {}) => new Promise((yes, no) =>
  session.post(method, params, (error, value) => error ? no(error) : yes(value)));
async function span(name, action) {
  const started = process.hrtime.bigint(), cpu = process.cpuUsage(), item = {name};
  report.phases.push(item);
  try {const value = await action(); item.complete = true; return value;}
  catch (error) {item.complete = false; throw error;}
  finally {
    const used = process.cpuUsage(cpu);
    Object.assign(item, {wallNs: Number(process.hrtime.bigint() - started),
      cpuUserUs: used.user, cpuSystemUs: used.system});
  }
}
async function stopProfile() {
  if (!active) return;
  active = false;
  const {profile} = await post('Profiler.stop');
  const bytes = Buffer.from(JSON.stringify(profile));
  assert(bytes.length <= 64 * 1024 ** 2);
  await writeFile(join(output, 'wait.cpuprofile'), bytes, {flag: 'wx', mode: 0o600});
}
try {
  await mkdir(stateDir);
  const {open} = await span('import', () => import('@actql/node'));
  client = await span('open', () => open({stateDir, installation: report.installation}));
  const digits = Array.from({length: 10}, (_, n) => `SELECT ${n} AS n`).join(' UNION ALL ');
  const sql = `WITH d AS (${digits}) SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < ${count}`;
  report.querySha256 = createHash('sha256').update(sql).digest('hex');
  report.submissions++;
  const run = await span('submit', () => client.startSource(sql, {format: 'sql'}));
  await writeFile(join(output, 'original-ref.json'), JSON.stringify(run.ref) + '\n', {flag: 'wx', mode: 0o600});
  session = new Session(); session.connect();
  await span('profiler-setup', async () => {
    await post('Profiler.enable'); await post('Profiler.setSamplingInterval', {interval: 1000});
    await post('Profiler.start'); active = true;
  });
  let terminal, waitFailure;
  try {terminal = await span('wait-100000', () => run.wait({signal: AbortSignal.timeout(300000)}));}
  catch (error) {waitFailure = error;}
  finally {
    try {await span('profiler-stop', stopProfile);}
    catch (error) {report.profilerFailure = {name: error.name}; waitFailure ??= error;}
  }
  if (waitFailure) throw waitFailure;
  assert.equal(terminal.status, 'succeeded');
  const names = terminal.next_action?.results;
  assert(Array.isArray(names) && names.length === 1);
  await span('all-100000', async () => {
    const rows = await run.result(names[0]).all(); assert.equal(rows.length, count);
    for (const row of rows) assert.deepEqual(row, {n: 0});
    report.all = {rows: count, exact: true};
  });
  await span('rows-100000-EOF', async () => {
    let rows = 0;
    for await (const row of run.result(names[0]).rows()) {assert.deepEqual(row, {n: 0}); rows++;}
    assert.equal(rows, count); report.stream = {rows, eof: true, exact: true};
  });
} catch (error) {primary = error; report.failure = {name: error.name, code: error.code ?? null};}
finally {
  try {await stopProfile();} catch (error) {primary ??= error; report.profilerFailure = {name: error.name};}
  session?.disconnect();
  report.firstClose = client ? 'pending' : 'not-attempted';
  try {await writeFile(join(output, 'consumer-pending.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});}
  catch (error) {primary ??= error; report.recordingFailure = {name: error.name};}
  if (client) {
    try {await span('FIRST-close', () => client.close()); report.firstClose = 'returned';}
    catch (error) {primary ??= error; report.firstClose = 'threw';}
  }
  if (report.firstClose === 'returned') {
    try {
      const before = await observeRecordApprovalDescriptors([stateDir]);
      const after = await observeRecordApprovalDescriptors([stateDir]);
      report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
      assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
    } catch (error) {primary ??= error; report.fdObservationFailure = {name: error.name};}
  }
  report.complete = primary === undefined;
  await writeFile(join(output, 'consumer.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
}
if (primary) throw new Error('Original installed Node wait or cleanup failed', {cause: {name: primary.name, code: primary.code ?? null}});
console.log(JSON.stringify({complete: true, submissions: report.submissions,
  rows: count, firstClose: report.firstClose, aliveScopedFD: report.aliveScopedFD}));
