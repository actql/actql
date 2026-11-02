// Actual Account gate, Local driver and Linux Files. Run/Content domain setup
// is explicit fixture ports; these tests do not assert Common Run ownership.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, readdir, writeFile, mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createLocalAuthorizationGate, canonicalJson} from '../../../host-node/local-account-config.mjs';
import {physicalLocal} from '../test/fixtures/file-store-authorization.mjs';
const physicalTarget = {skip: process.platform !== 'linux' || process.arch !== 'x64'
  ? 'Physical Files fixture requires Linux x64' : false};
const cid = digit => 'sha256:' + digit.repeat(64);
const scope = {connection: 'local', resource: 'files', operation: 'effect'};
const account = outcome => canonicalJson({version: 'actql-execution-account-config/0.1', account_id: 'physical',
  entries: [{entry_id: 'files', outcome, principal: {all: true}, connection: {any_of: ['local']},
    resource: {any_of: ['files']}, operation: {any_of: ['effect']}, exclusions: []}]});
async function gate(t, options = {}) {
  const owner = await createLocalAuthorizationGate({accountConfiguration: account('allow'), principal: 'owner', ...options});
  t.after(() => owner.close()); return owner;
}
const decision = owner => owner.authorize('effect_commit', scope, {subjectCid: cid('4')});
test('real Account Allow writes exact bytes once through the Local driver and actual Files', physicalTarget, async t => {
  const owner = await gate(t), f = await physicalLocal(t, owner), permission = f.grant(await decision(owner));
  const response = await f.send(permission);
  assert.equal(f.driver.project({request: f.prepared.request, observation: response.observation}).outcome.state, 'applied');
  assert.deepEqual(await readFile(join(f.directory, 'result.txt')), f.bytes);
  assert.equal(f.renames(), 1); assert.equal(f.reads(), 1);
  await assert.rejects(f.send(permission), {code: 'ForeignLocalStoreUse'});
  await assert.rejects(f.send(f.grant(await decision(owner))), {code: 'LocalFileWriteAlreadyAttempted'});
  assert.equal(f.renames(), 1); assert.equal(f.reads(), 1);
});
test('denied and copied decisions never acquire Files or change the directory', physicalTarget, async t => {
  const owner = await gate(t), denied = await gate(t, {accountConfiguration: account('deny')});
  const f = await physicalLocal(t, owner);
  for (const value of [await decision(denied), {...await decision(owner)}]) {
    assert.throws(() => f.grant(value), {code: 'LocalStoreNotAuthorized'});
  }
  assert.equal(f.nativeCalls(), 0); assert.deepEqual(await readdir(f.directory), []);
});
test('foreign Run, request, target binding and subject cannot reach native write', physicalTarget, async t => {
  const owner = await gate(t), f = await physicalLocal(t, owner), allowed = await decision(owner);
  assert.throws(() => f.grant(allowed, {subjectCid: cid('9')}), {code: 'LocalStoreNotAuthorized'});
  await f.rejectForeignTarget();
  await assert.rejects(f.send(f.grant(allowed), {runOriginal: {}}), {code: 'ForeignLocalStoreDescription'});
  await assert.rejects(f.send(f.grant(allowed), {request: {...f.prepared.request}}), {code: 'ForeignLocalStoreRequest'});
  await assert.rejects(f.send(f.grant(allowed, {dispatchRequestCid: cid('9')})), {code: 'ForeignLocalStoreUse'});
  await assert.rejects(f.send(f.grant(allowed, {runInvocationCid: cid('9')})), {code: 'ForeignLocalStoreUse'});
  assert.equal(f.nativeCalls(), 0); assert.deepEqual(await readdir(f.directory), []);
});
test('actual Account denial after grant is rechecked before Files acquisition', physicalTarget, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'local-account-current-')), path = join(directory, 'account.json');
  await writeFile(path, account('allow'));
  const owner = await gate(t, {accountConfiguration: undefined, accountConfig: path});
  const f = await physicalLocal(t, owner), permission = f.grant(await decision(owner));
  await writeFile(path, account('deny'));
  await assert.rejects(f.send(permission), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.nativeCalls(), 0); assert.deepEqual(await readdir(f.directory), []);
});
test('post-rename Unknown remains a failure and neither original nor replacement grant resends', physicalTarget, async t => {
  const owner = await gate(t), f = await physicalLocal(t, owner, {fault: 4});
  const permission = f.grant(await decision(owner));
  await assert.rejects(f.send(permission), {code: 'LocalFilePublishDurabilityUnknown'});
  assert.deepEqual(await readFile(join(f.directory, 'result.txt')), f.bytes);
  await assert.rejects(f.send(permission), {code: 'ForeignLocalStoreUse'});
  await assert.rejects(f.send(f.grant(await decision(owner))), {code: 'LocalFileWriteAlreadyAttempted'});
  assert.equal(f.renames(), 1); assert.equal(f.reads(), 1);
});
