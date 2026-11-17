// Required Account consumers of the existing verified normal package set.
// No package producer, checkout runtime import or new CI job.
import assert from 'node:assert/strict';
import {mkdir, copyFile, writeFile, readFile, symlink, readlink, unlink} from 'node:fs/promises';
import {join, dirname, isAbsolute} from 'node:path';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

export const packedAccountCases = Object.freeze(['bootstrap', 'padded-default', 'installed-explicit']);
export const packedAccountMembers = Object.freeze([
  'scripts/fixtures/packed-account-construction.mjs',
  'scripts/fixtures/record-approval/scoped-fds.fixture.mjs',
]);

export function assertPackedAccountOutcome(actual, pid) {
  assert.equal(actual.case, 'packed-account-construction');
  assert.equal(actual.pid, pid); assert.equal(actual.complete, true);
  assert.equal(actual.primary, undefined); assert.deepEqual(actual.cleanup, []);
  assert.deepEqual(actual.cases.map(row => row.id), packedAccountCases);
  for (const row of actual.cases) {
    assert.equal(row.complete, true); assert.equal(row.hostOpenCalls, 1);
    assert.equal(row.firstClose, 'returned'); assert.equal(row.firstCloseCalls, 1);
    assert.equal(row.primary, undefined); assert.deepEqual(row.cleanup, []);
    assert.equal(row.beforeCloseRecorded, true);
    assert.deepEqual(row.aliveScopedFD, {before: 0, after: 0});
    assert.deepEqual(row.rows, [{n: 7}]);
    assert(row.ref && typeof row.resultName === 'string' && row.resultName.length);
  }
  const [first, padded, installed] = actual.cases;
  assert.equal(first.profile, 'actql-local-standard');
  assert.equal(typeof first.accountId, 'string'); assert(first.accountId.length > 0);
  assert.equal(padded.accountId, first.accountId);
  assert(padded.rawBytes > 1000000); assert.equal(padded.canonicalAccountUnchanged, true);
  assert(installed.rawBytes > 1000000); assert.equal(installed.sameLiveHost, true);
  assert.deepEqual(installed.currentControls, {
    sameAccountRestriction: {code: 'ResultAccessDenied', sameAccountId: true},
    changedAccount: {code: 'ResultAccessDenied', differentAccountId: true},
    restoredRows: [{n: 7}],
  });
}

// The default verifier is the existing exact-source/tarball/installed-software
// verifier. The optional port is used only by routing tests, never by the runner.
export async function runPackedAccountControls({prepared, root, repository, command,
  report, cleanup, verifyPackages = verifyNodeBenchmarkPackages}) {
  const record = report.account;
  assert(record && typeof command === 'function');
  assert(isAbsolute(root) && isAbsolute(repository) && isAbsolute(prepared.consumer));
  const collection = join(root, 'collection'), application = join(collection, 'account-controls');
  await mkdir(application, {recursive: true});
  const prefix = join(collection, 'account-controls');
  const software = join(prepared.consumer, 'node_modules'), alias = join(application, 'node_modules');
  let primary, linked = false;
  const ownCleanup = [];
  Object.assign(record, {status: 'running', completed: false, startedAt: new Date().toISOString(),
    command: process.execPath, timeoutMs: 120000});
  delete record.unexecutedReason;
  try {
    await verifyPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    for (const path of packedAccountMembers) {
      await mkdir(dirname(join(application, path)), {recursive: true});
      await copyFile(join(repository, path), join(application, path));
    }
    await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
    const home = join(application, 'home'); await mkdir(home);
    const env = {...process.env, HOME: home, PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
    delete env.ACTQL_PACKED_CLIENT_PACKAGES;
    await symlink(software, alias, 'dir'); linked = true;
    const args = [join(application, packedAccountMembers[0]), prefix];
    Object.assign(record, {args, cwd: application});
    const observed = await command(process.execPath, args,
      {cwd: application, env, name: 'account-controls', timeout: 120000});
    Object.assign(record, {pid: observed.pid, exitCode: observed.code, signal: observed.signal ?? null});
    assert.equal(observed.code, 0); assert.equal(observed.signal ?? null, null);
    const actual = JSON.parse(observed.stdout.trim());
    record.actual = actual;
    assertPackedAccountOutcome(actual, observed.pid);
    record.completed = true; record.status = 'passed';
  } catch (error) {
    primary = error;
    const observed = error.commandResult;
    record.status = observed?.timedOut === true || error.code === 'ETIMEDOUT' ? 'timeout' : 'failed';
    record.error = nodeBenchmarkFailure(error);
    if (observed) Object.assign(record, {pid: observed.pid, exitCode: observed.code ?? null, signal: observed.signal ?? null});
    // Same-child pre-close facts remain evidence even when a first close or
    // the final stdout is unobserved. Neither timeout nor exit implies cleanup.
    record.partial = [];
    for (const id of packedAccountCases) try {
      const partial = JSON.parse(await readFile(`${prefix}-${id}.pending.json`, 'utf8'));
      if (partial.pid === record.pid) record.partial.push(partial);
    } catch { /* Preserve the original command/validation failure. */ }
    try {
      const progress = JSON.parse(await readFile(`${prefix}.progress.json`, 'utf8'));
      if (progress.pid === record.pid) record.progress = progress;
    }
    catch { /* Missing progress is not a successful completion. */ }
  } finally {
    if (linked) try {assert.equal(await readlink(alias), software); await unlink(alias);}
    catch (error) {ownCleanup.push(error);}
    try {await verifyPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);}
    catch (error) {ownCleanup.push(error);}
    record.endedAt = new Date().toISOString();
    record.cleanup = ownCleanup.map(nodeBenchmarkFailure);
    cleanup.push(...ownCleanup);
    if (ownCleanup.length) {record.completed = false; if (record.status === 'passed') record.status = 'failed';}
    try {await writeFile(`${prefix}.runner.observation.json`, JSON.stringify(record, null, 2) + '\n');}
    catch (error) {ownCleanup.push(error); cleanup.push(error); record.completed = false; record.status = 'failed';}
  }
  if (primary !== undefined) throw primary;
  if (ownCleanup.length) throw new AggregateError(ownCleanup, 'PackedAccountCleanupUnconfirmed');
}
