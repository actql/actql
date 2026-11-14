// Run only in the same normal installed namespace as required README consumers.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, isAbsolute} from 'node:path';
import {setTimeout} from 'node:timers/promises';
import {open} from '@actql/node';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [prefix] = process.argv.slice(2);
assert.equal(typeof prefix, 'string'); assert(isAbsolute(prefix));
const report = {case: 'packed-account-construction', pid: process.pid,
  cases: [], cleanup: [], complete: false};
const failures = [];
const facts = error => ({name: error?.name, code: error?.code, message: String(error?.message ?? '').slice(0, 2048)});
const save = (path, body) => writeFile(path, JSON.stringify(body, null, 2) + '\n', {mode: 0o600});
const progress = () => save(prefix + '.progress.json', report);
const directory = process.cwd(), defaultState = join(directory, 'default-state');
const defaultAccount = join(defaultState, 'account', 'account.json');
let originalDefault;

async function withHost(id, options, action) {
  const row = {id, hostOpenCalls: 0, firstClose: 'not-attempted', firstCloseCalls: 0,
    cleanup: [], complete: false};
  report.cases.push(row);
  let client, primary;
  const cleanup = [];
  const span = async (step, operation) => {
    row.step = step; await progress();
    try {return await operation();}
    catch (error) {row.firstFailedStep ??= step; throw error;}
  };
  try {
    row.hostOpenCalls++;
    client = await span('open', () => open(options));
    await action(client, row, span);
  } catch (error) {primary = error; row.primary = facts(error);}
  finally {
    row.firstClose = client === undefined ? 'not-attempted' : 'pending';
    // Persist the original failure/Run/current-control facts BEFORE first close.
    try {
      row.beforeCloseRecorded = true;
      await save(`${prefix}-${id}.pending.json`, {pid: report.pid, ...row});
    } catch (error) {row.beforeCloseRecorded = false; cleanup.push(error);}
    if (client !== undefined) try {
      row.step = 'FIRST-close';
      try {await progress();} catch (error) {cleanup.push(error);}
      row.firstCloseCalls++;
      await client.close(); row.firstClose = 'returned';
    } catch (error) {row.firstClose = 'threw'; cleanup.push(error);}
    if (row.firstClose === 'returned') try {
      // The process cwd is a directory reference in lsof, not a retained Host
      // descriptor. Observe the actual state and explicit Account originals.
      const roots = [options.stateDir,
        ...(options.installation?.authorization?.accountConfig === undefined ? [] :
          [options.installation.authorization.accountConfig])];
      const before = await observeRecordApprovalDescriptors(roots);
      await setTimeout(100);
      const after = await observeRecordApprovalDescriptors(roots);
      row.scopedOpenPaths = {before: before.openPaths, after: after.openPaths};
      row.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
      assert.deepEqual(row.aliveScopedFD, {before: 0, after: 0});
    } catch (error) {cleanup.push(error);}
    row.cleanup = cleanup.map(facts);
    row.complete = primary === undefined && cleanup.length === 0 && row.firstClose === 'returned';
    try {await save(`${prefix}-${id}.observation.json`, {pid: report.pid, ...row});}
    catch (error) {cleanup.push(error); row.complete = false;}
    if (primary !== undefined) failures.push(primary);
    failures.push(...cleanup);
  }
  return row;
}
async function smallResult(client, row, span) {
  const run = await span('submit-small', () => client.startSource('SELECT 7 AS n', {format: 'sql'}));
  row.ref = run.ref; await progress();
  const terminal = await span('wait-small', () => run.wait());
  assert.equal(terminal.status, 'succeeded'); assert.equal(terminal.result_available, true);
  const names = terminal.next_action?.results;
  assert(Array.isArray(names) && names.length === 1);
  row.resultName = names[0];
  const result = run.result(names[0]);
  row.rows = await span('read-small', () => result.all());
  assert.deepEqual(row.rows, [{n: 7}]);
  return result;
}
async function refusedRead(result) {
  let original;
  try {await result.all();} catch (error) {original = error;}
  assert(original, 'Current Account restriction must refuse the actual public Result read');
  assert.equal(original.code, 'ResultAccessDenied');
  return {code: original.code};
}

await withHost('bootstrap', {stateDir: defaultState}, async (client, row, span) => {
  // Default Account adoption is lazy and belongs to the first real Request.
  await smallResult(client, row, span);
  originalDefault = await span('read-adopted-account', async () => JSON.parse(await readFile(defaultAccount, 'utf8')));
  row.accountId = originalDefault.account_id;
  row.profile = originalDefault.bootstrap?.profile_id;
  assert.equal(row.profile, 'actql-local-standard');
});
if (report.cases[0].complete) {
  const original = await readFile(defaultAccount, 'utf8');
  const padded = ' '.repeat(1000001) + original;
  await writeFile(defaultAccount, padded, {mode: 0o600});
  await withHost('padded-default', {stateDir: defaultState}, async (client, row, span) => {
    const actual = await readFile(defaultAccount, 'utf8');
    row.rawBytes = Buffer.byteLength(actual); assert(row.rawBytes > 1000000);
    const parsed = JSON.parse(actual);
    assert.deepEqual(parsed, originalDefault);
    row.accountId = parsed.account_id; row.canonicalAccountUnchanged = true;
    await smallResult(client, row, span);
  });
} else {
  report.cases.push({id: 'padded-default', complete: false,
    unexecutedReason: 'Requires successful original default bootstrap and first close'});
}

const explicitDirectory = join(directory, 'explicit'); await mkdir(explicitDirectory);
const explicitAccount = join(explicitDirectory, 'account.json');
const authored = {version: 'actql-execution-account-config/0.1', account_id: 'packed-account-operator',
  entries: [{entry_id: 'actual-current-read', outcome: 'allow', principal: {all: true},
    connection: {all: true}, resource: {all: true}, operation: {all: true}, exclusions: []}]};
const wire = value => ' '.repeat(1000001) + JSON.stringify(value);
await writeFile(explicitAccount, wire(authored), {mode: 0o600});
await withHost('installed-explicit', {stateDir: join(explicitDirectory, 'state'),
  installation: {authorization: {accountConfig: explicitAccount}}}, async (client, row, span) => {
  row.rawBytes = Buffer.byteLength(await readFile(explicitAccount));
  assert(row.rawBytes > 1000000);
  const result = await smallResult(client, row, span);
  // All controls use this SAME live Host and its original Result. No reopen,
  // copied permit or replacement submission can conceal stale currency.
  row.sameLiveHost = true;
  const restricted = structuredClone(authored); restricted.entries[0].outcome = 'deny';
  await span('restrict-same-account', () => writeFile(explicitAccount, wire(restricted), {mode: 0o600}));
  const sameAccountRestriction = await span('read-same-account-denied', () => refusedRead(result));
  sameAccountRestriction.sameAccountId = restricted.account_id === authored.account_id;
  const changed = {...authored, account_id: 'different-packed-account'};
  await span('change-account-id', () => writeFile(explicitAccount, wire(changed), {mode: 0o600}));
  const changedAccount = await span('read-changed-account-denied', () => refusedRead(result));
  changedAccount.differentAccountId = changed.account_id !== authored.account_id;
  await span('restore-original-account', () => writeFile(explicitAccount, wire(authored), {mode: 0o600}));
  const restoredRows = await span('read-restored-same-host', () => result.all());
  assert.deepEqual(restoredRows, [{n: 7}]);
  row.currentControls = {sameAccountRestriction, changedAccount, restoredRows};
});
report.complete = failures.length === 0 && report.cases.every(row => row.complete);
if (failures.length) report.primary = facts(failures[0]);
await save(prefix + '.observation.json', report);
if (failures.length) throw new AggregateError(failures, 'PackedAccountConstructionFailed', {cause: failures[0]});
assert(report.complete);
console.log(JSON.stringify(report));
