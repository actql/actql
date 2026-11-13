// One ordinary Project-owned Local JOIN, followed by a separate process that
// reads only its original Saved Result from the same installed package set.
import assert from 'node:assert/strict';
import {access, mkdir, readFile, unlink, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {setTimeout} from 'node:timers/promises';
import {open} from '@actql/node';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [phase, handoffPath] = process.argv.slice(2);
assert(['capture', 'saved'].includes(phase));
assert.equal(typeof handoffPath, 'string');
const directory = process.cwd(), stateDir = join(directory, 'state');
const left = join(directory, 'left-data'), right = join(directory, 'right-data');
const paths = [join(left, 'left.txt'), join(right, 'right.txt')];
const expected = [{left_path: 'left.txt', left_bytes: 3,
  right_path: 'right.txt', right_bytes: 7}];
const report = {case: 'project-local-files-same-unit-join', phase, pid: process.pid,
  submits: 0, firstClose: 'unobserved', firstCloseCalls: 0, complete: false};
const save = (path, body) => writeFile(path, JSON.stringify(body, null, 2) + '\n', {mode: 0o600});
const observation = join(dirname(handoffPath), `project-files-${phase}.observation.json`);
const pending = join(dirname(handoffPath), `project-files-${phase}.pending.json`);
const assertAbsent = async () => {
  for (const path of paths) await assert.rejects(access(path), {code: 'ENOENT'});
};
const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
  account_id: 'project-file-join-operator', entries: [{entry_id: 'owned-fixture',
    outcome: 'allow', principal: {all: true}, connection: {all: true},
    resource: {all: true}, operation: {all: true}, exclusions: []}]});
let client, original, primary;
const cleanup = [];
try {
  if (phase === 'capture') {
    await mkdir(left); await mkdir(right);
    await writeFile(paths[0], 'abc', {flag: 'wx'});
    await writeFile(paths[1], '1234567', {flag: 'wx'});
    await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
      connectors: 'connectors.json'}), {flag: 'wx'});
    await writeFile(join(directory, 'connectors.json'), JSON.stringify({version: 'actql-connectors/0.1',
      connections: {left_source: {connector: 'local', root: './left-data', tables: {}},
        right_source: {connector: 'local', root: './right-data', tables: {}}}}), {flag: 'wx'});
  } else {
    original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.complete, true);
    assert.equal(original.case, report.case);
    await assertAbsent();
  }
  client = await open({stateDir, installation: {authorization: {accountConfiguration}}});
  let run, resultName;
  if (phase === 'capture') {
    // Different installed connection declarations prevent a same-Source alias
    // from hiding the second physical input. No custom Source profile is used.
    const sql = 'SELECT a.path AS left_path, a.size_bytes AS left_bytes, ' +
      'b.path AS right_path, b.size_bytes AS right_bytes ' +
      'FROM LIST_FILES(left_source) AS a JOIN LIST_FILES(right_source) AS b ON a.media_type = b.media_type';
    report.submits++;
    run = await client.startSource(sql, {format: 'sql'});
    original = {case: report.case, ref: run.ref, complete: false};
    await save(handoffPath, original);
    const terminal = await run.wait();
    assert.equal(terminal.status, 'succeeded');
    assert.equal(terminal.result_available, true);
    assert(Array.isArray(terminal.next_action?.results) && terminal.next_action.results.length === 1);
    resultName = terminal.next_action.results[0];
    original.resultName = resultName;
    report.physicalStop = terminal.control?.physical_stop ?? 'unobserved';
  } else {
    run = await client.attach(original.ref);
    resultName = original.resultName;
    assert.deepEqual(run.ref, original.ref);
  }
  report.rows = await run.result(resultName).all();
  assert.deepEqual(report.rows, expected);
  report.ref = run.ref; report.resultName = resultName;
  const terminal = await run.status();
  assert.equal(terminal.status, 'succeeded');
  if (phase === 'saved') await assertAbsent();
} catch (error) {
  primary = error;
  report.primary = {name: error?.name, code: error?.code};
} finally {
  report.firstClose = client === undefined ? 'not-attempted' : 'pending';
  try {await save(pending, report);} catch (error) {cleanup.push(error);}
  if (client !== undefined) try {
    report.firstCloseCalls++;
    await client.close(); report.firstClose = 'returned';
  } catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  if (report.firstClose === 'returned') try {
    const before = await observeRecordApprovalDescriptors([stateDir, left, right]);
    await setTimeout(100);
    const after = await observeRecordApprovalDescriptors([stateDir, left, right]);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (primary === undefined && cleanup.length === 0) try {
    if (phase === 'capture') for (const path of paths) await unlink(path);
    await assertAbsent(); report.originalFilesAbsent = true;
    if (phase === 'capture') await save(handoffPath, {...original, complete: true});
    report.complete = true;
  } catch (error) {cleanup.push(error);}
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code}));
  try {await save(observation, report);} catch (error) {cleanup.push(error);}
}
if (primary !== undefined || cleanup.length) throw new AggregateError(
  [...(primary === undefined ? [] : [primary]), ...cleanup], 'ProjectFileJoinFailed', {cause: primary});
console.log(JSON.stringify(report));
