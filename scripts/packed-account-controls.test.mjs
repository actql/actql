// Routing/observation ports only. Actual ordinary Host acceptance is executed
// by the required Node22/24 same-artifact runner, never by these doubles.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, writeFile, readlink, access, rm, unlink, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {packedAccountCases, packedAccountMembers, assertPackedAccountOutcome,
  runPackedAccountControls} from './packed-account-controls.mjs';

function explicitPort(pid = 43) {
  const cases = packedAccountCases.map(id => ({id, complete: true, hostOpenCalls: 1,
    firstClose: 'returned', firstCloseCalls: 1, beforeCloseRecorded: true,
    aliveScopedFD: {before: 0, after: 0}, cleanup: [], rows: [{n: 7}],
    ref: {namespaceId: 'local', authorityScopeCid: 'fixture', runDefinitionCid: 'fixture'}, resultName: 'main'}));
  Object.assign(cases[0], {profile: 'actql-local-standard', accountId: 'original'});
  Object.assign(cases[1], {accountId: 'original', rawBytes: 1000001, canonicalAccountUnchanged: true});
  Object.assign(cases[2], {rawBytes: 1000001, sameLiveHost: true, currentControls: {
    sameAccountRestriction: {code: 'ResultAccessDenied', sameAccountId: true},
    changedAccount: {code: 'ResultAccessDenied', differentAccountId: true}, restoredRows: [{n: 7}],
  }});
  return {case: 'packed-account-construction', pid, complete: true, cleanup: [], cases};
}
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-routing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const consumer = join(root, 'original-consumer'); await mkdir(join(consumer, 'node_modules'), {recursive: true});
  const prepared = {consumer, manifest: {source: 'explicit test port'}, manifestPath: join(root, 'manifest.json')};
  const report = {account: {completed: false, status: 'unexecuted', unexecutedReason: 'not run'}}, cleanup = [];
  let checks = 0;
  const verifyPackages = async (...args) => {checks++; assert.deepEqual(args,
    [prepared.manifest, prepared.manifestPath, consumer]);};
  return {root, prepared, report, cleanup, verifyPackages, checks: () => checks,
    repository: fileURLToPath(new URL('../', import.meta.url))};
}

test('Account helper stages only its two members and uses the same installed artifact with the fixed120s child budget', async t => {
  const f = await fixture(t);
  await runPackedAccountControls({...f, command: async (command, args, options) => {
    assert.equal(command, process.execPath); assert.equal(options.timeout, 120000);
    assert.equal(options.name, 'account-controls');
    assert.equal(await readlink(join(options.cwd, 'node_modules')), join(f.prepared.consumer, 'node_modules'));
    assert.deepEqual(packedAccountMembers, ['scripts/fixtures/packed-account-construction.mjs',
      'scripts/fixtures/record-approval/scoped-fds.fixture.mjs']);
    for (const path of packedAccountMembers) assert.equal(
      await readFile(join(options.cwd, path), 'utf8'), await readFile(join(f.repository, path), 'utf8'));
    assert.equal(args[0], join(options.cwd, packedAccountMembers[0]));
    assert.equal(args[1], join(f.root, 'collection', 'account-controls'));
    assert.equal(options.env.ACTQL_PACKED_CLIENT_PACKAGES, undefined);
    return {pid: 43, code: 0, stdout: JSON.stringify(explicitPort())};
  }});
  assert.equal(f.report.account.status, 'passed'); assert.equal(f.report.account.completed, true);
  assert.equal(f.checks(), 2); assert.deepEqual(f.cleanup, []);
  await assert.rejects(access(join(f.root, 'collection/account-controls/node_modules')), {code: 'ENOENT'});
});

test('missing case, current denial, large raw input, before-close evidence, or first close cannot count as acceptance', () => {
  assertPackedAccountOutcome(explicitPort(), 43);
  for (const alter of [value => value.cases.pop(), value => {value.cases[2].currentControls.sameAccountRestriction.code = 'Unknown';},
    value => {value.cases[1].rawBytes = 1000000;}, value => {value.cases[0].beforeCloseRecorded = false;},
    value => {value.cases[1].firstClose = 'pending';}, value => {value.cases[2].firstCloseCalls = 2;}]) {
    const value = explicitPort(); alter(value); assert.throws(() => assertPackedAccountOutcome(value, 43));
  }
});

test('timeout preserves same-child original pre-close cause and pending first close, without successful cleanup inference', async t => {
  const f = await fixture(t);
  const original = Object.assign(new Error('child timed out'), {code: 'ETIMEDOUT',
    commandResult: {pid: 43, code: null, signal: 'SIGTERM', timedOut: true}});
  await assert.rejects(runPackedAccountControls({...f, command: async (_command, args) => {
    await writeFile(args[1] + '-bootstrap.pending.json', JSON.stringify({pid: 43, id: 'bootstrap',
      primary: {code: 'OriginalAccountFailure'}, firstClose: 'pending', firstCloseCalls: 1}));
    await writeFile(args[1] + '.progress.json', JSON.stringify({pid: 43, complete: false, step: 'FIRST-close'}));
    throw original;
  }}), error => error === original);
  assert.equal(f.report.account.completed, false); assert.equal(f.report.account.status, 'timeout');
  assert.deepEqual(f.report.account.partial[0].primary, {code: 'OriginalAccountFailure'});
  assert.equal(f.report.account.partial[0].firstClose, 'pending'); assert.equal(f.checks(), 2);
  await assert.rejects(access(join(f.root, 'collection/account-controls/node_modules')), {code: 'ENOENT'});
});

test('alias cleanup failure preserves the original command error and cannot complete the Account record', async t => {
  const f = await fixture(t), original = Object.assign(new Error('OriginalFailure'), {code: 'OriginalFailure'});
  await assert.rejects(runPackedAccountControls({...f, command: async (_command, _args, options) => {
    const alias = join(options.cwd, 'node_modules'); await unlink(alias);
    await symlink(join(f.root, 'different-software'), alias, 'dir'); throw original;
  }}), error => error === original);
  assert.equal(f.report.account.completed, false); assert.equal(f.report.account.status, 'failed');
  assert.equal(f.cleanup.length, 1); assert.equal(f.checks(), 2);
});
