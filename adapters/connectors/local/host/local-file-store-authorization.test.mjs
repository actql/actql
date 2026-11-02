// Genuine compiled Account decisions consumed by the actual Local grant route.
// No request, Content, native writer, checkpoint substitute, or physical send.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalAuthorizationGate, canonicalJson} from '../../../host-node/local-account-config.mjs';
import {authorizationDispatchFacts} from '../../../host-common/authorization-gate.mjs';
import {createLocalFileStoreDriver} from './installed-project-file-effects.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
const tuple = Object.freeze({connection: 'local', resource: 'files', operation: 'effect'});
const account = ({outcome = 'allow', id = 'owned-files-test'} = {}) => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: id,
  entries: [{entry_id: 'files', outcome, principal: {all: true},
    connection: {any_of: ['local', 'other']}, resource: {any_of: ['files', 'other']},
    operation: {any_of: ['effect', 'read']}, exclusions: []}],
});
async function gate(t, options = {}) {
  const owned = await createLocalAuthorizationGate({accountConfiguration: account(), principal: 'owner', ...options});
  t.after(() => owned.close()); return owned;
}
function local(t, authorization, principalId = 'owner') {
  const noUse = new Proxy({}, {get() {assert.fail('grant-only test must not acquire Run, Content or native resources');}});
  const {site} = createLocalFileStoreDriver({entry: {connection: 'local'}, target: {}, command: {},
    bindingCid: cid('1'), principalId, authorization, assertCurrent() {},
    resources: noUse, limits: {}, nativeFilesystem: noUse});
  t.after(() => site.close());
  return {site, grant(decision, changes = {}) {
    return site.issueEffectGrant({operation: 'files.write', resource: 'files',
      runInvocationCid: cid('2'), dispatchRequestCid: cid('3'), subjectCid: cid('4'), decision, ...changes});
  }};
}
const decision = (owner, scope = tuple, boundary = 'effect_commit', subjectCid = cid('4')) =>
  owner.authorize(boundary, scope, {subjectCid});

test('Local grant accepts original Account Allow without inventing approval fields', async t => {
  const owner = await gate(t), original = await decision(owner), route = local(t, owner);
  assert.equal(original.action, 'dispatch'); assert.equal(original.basis, 'account_allow');
  assert.equal(original.checkpointCid, undefined); assert.equal(original.resolutionCid, undefined);
  assert.equal(original.admission, undefined);
  assert.equal(authorizationDispatchFacts(original).principal, 'owner');
  const granted = route.grant(original);
  assert.equal(Object.isFrozen(granted), true); assert.equal(typeof granted.proof, 'object');
});

test('Local grant accepts a genuine current delegated Host permit without checkpoint fields', async t => {
  let asked = 0;
  const owner = await gate(t, {accountConfiguration: account({outcome: 'delegate'}), answeringAuthorities: ['test-owner'], decide(view) {
    asked++; return {decision: 'permit', subject: view.subject, authority: 'test-owner', claims: []};
  }});
  const original = await decision(owner);
  assert.equal(original.basis, 'host_permit'); assert.equal(asked, 1);
  assert.equal(original.checkpointCid, undefined);
  assert.ok(local(t, owner).grant(original).proof);
});

test('Local grant rejects real Deny and copied or edited decision DATA', async t => {
  const owner = await gate(t), route = local(t, owner), original = await decision(owner);
  const deniedOwner = await gate(t, {accountConfiguration: account({outcome: 'deny'})});
  const denied = await decision(deniedOwner);
  assert.equal(denied.action, 'deny');
  for (const value of [denied, {...original}, {...original, basis: 'resumed', checkpointCid: cid('5'), resolutionCid: cid('6')}]) {
    assert.throws(() => route.grant(value), {code: 'LocalStoreNotAuthorized'});
  }
});

test('Local grant rejects original decisions for foreign principal, configuration, tuple or subject', async t => {
  const owner = await gate(t), route = local(t, owner);
  const foreignPrincipal = await gate(t, {principal: 'other-owner'});
  const foreignConfig = await gate(t, {accountConfiguration: account({id: 'other-account'})});
  const decisions = [await decision(foreignPrincipal), await decision(foreignConfig),
    await decision(owner, {...tuple, connection: 'other'}),
    await decision(owner, {...tuple, resource: 'other'}),
    await decision(owner, {...tuple, operation: 'read'}),
    await decision(owner, tuple, 'acquisition'), await decision(owner, tuple, 'effect_commit', cid('9'))];
  for (const original of decisions) {
    assert.equal(original.action, 'dispatch', 'negative uses a genuine dispatch for a different binding');
    assert.throws(() => route.grant(original), {code: 'LocalStoreNotAuthorized'});
  }
});

test('Local grant rejects a closed genuine decision scope and closing installation', async t => {
  const owner = await gate(t), route = local(t, owner), original = await decision(owner);
  owner.close();
  assert.throws(() => route.grant(original), {code: 'AuthorizationDecisionScopeClosed'});
  await route.site.close();
  assert.throws(() => route.grant(original), {code: 'LocalStoreInstallationClosing'});
});

test('Local grant rechecks the actual installed Account file before granting', async t => {
  const root = await mkdtemp(join(tmpdir(), 'local-store-authorization-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json'); await writeFile(path, account());
  const owner = await gate(t, {accountConfiguration: undefined, accountConfig: path});
  const route = local(t, owner), original = await decision(owner);
  await writeFile(path, account({outcome: 'deny'}));
  assert.throws(() => route.grant(original), {code: 'AuthorizationCurrentAccountChanged'});
});
