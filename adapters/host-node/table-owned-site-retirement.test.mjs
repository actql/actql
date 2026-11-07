import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

// Execute the actual exported Site body without importing a different Common
// or the unrelated Table/SDK physical fixture. Authorization/current ports are
// explicit here; this is no Account, grant or Native funding acceptance.
function originalSite(options) {
  const source = readFileSync(new URL('./installed-table-source.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const pieces = [];
  for (const item of tree.body) {
    const node = item.type === 'ExportNamedDeclaration' ? item.declaration : item;
    if (node?.type === 'VariableDeclaration' && node.declarations.some(declaration =>
      ['fail', 'keys', 'identifier'].includes(declaration.id.name)) ||
        node?.type === 'FunctionDeclaration' && node.id.name === 'installedTableReadSite') {
      pieces.push(source.slice(node.start, node.end));
    }
  }
  return Function('canonicalJson', 'checkpointApprovalFacts', 'nodeTypes',
    pieces.join('\n') + '\nreturn installedTableReadSite;')(
    canonicalJson, checkpointApprovalFacts, nodeTypes)(options);
}
const cid = value => 'sha256:' + value.repeat(64);
function fixture(authorization, {ownAuthorization = true, targets} = {}) {
  const decision = Object.freeze({action: 'dispatch', boundary: 'acquisition',
    tuple: {connection: 'original-table', resource: 'rows', operation: 'read'}, contextCid: cid('a')});
  authorization.issued ??= original => original === decision;
  authorization.context ??= {contextCid: cid('a')};
  const site = originalSite({connection: 'original-table', principalId: 'original-principal',
    authorization, ownAuthorization, targets: targets ?? (() => [{resource: 'rows'}])});
  const request = {operation: 'table.read', decision, resource: 'rows', maxUses: 1,
    runInvocationCid: cid('b'), dispatchRequestCid: cid('c')};
  return {site, request};
}

test('Table owned Site keeps its original close and rejects new grants during pending or failed retirement', () => {
  let site, request, mode = 'pending', calls = 0, foreign = 0;
  const cause = Object.freeze({original: 'close failure'});
  const authorization = {close() {
    assert.equal(this, authorization); calls++;
    // Grant issuance must stop before entering the original callback.
    assert.equal(site.referenceCurrent(),false);
    assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
    assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
    if (mode === 'failed') throw cause;
    return mode === 'ack';
  }};
  ({site, request} = fixture(authorization));
  assert.equal(site.referenceCurrent(),true);
  assert.deepEqual(site.issueReadGrant(request),
    {runInvocationCid: request.runInvocationCid, dispatchRequestCid: request.dispatchRequestCid});
  assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
  assert.equal(site.referenceCurrent(),false);
  assert.equal(calls, 1);
  authorization.close = () => {foreign++; return true;};
  mode = 'failed';
  assert.throws(() => site.close(), error => error === cause);
  mode = 'ack'; site.close(); site.close();
  assert.equal(calls, 3); assert.equal(foreign, 0);
  assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
});

test('Table owned Site captures only an own synchronous close while borrowed Site leaves its owner untouched', () => {
  let gets = 0;
  const accessor = {get close() {gets++; return () => true;}};
  const inherited = Object.create({close() {return true;}});
  const asynchronous = {async close() {return true;}};
  for (const authorization of [accessor, inherited, asynchronous, {close: new Proxy(() => true, {})}]) {
    assert.throws(() => fixture(authorization), {code: 'InvalidInstalledTableAuthorization'});
  }
  assert.equal(gets, 0);
  const borrowed = {get close() {gets++; return () => true;}};
  const {site, request} = fixture(borrowed, {ownAuthorization: false});
  assert.ok(site.issueReadGrant(request)); site.close(); site.close();
  assert.equal(gets, 0);
  assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
});

test('Table original Site remains in existing failed-initialization cleanup until its same scope acknowledges', async () => {
  let acknowledged = false, calls = 0, foreign = 0;
  const authorization = {close() {assert.equal(this, authorization); calls++; return acknowledged;}};
  const {site, request} = fixture(authorization);
  const cause = Object.freeze({original: 'later constructor failure'});
  const failure = await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  assert.equal(failure.cause, cause); assert.equal(failure.primaryFailure, cause);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['source-profile']);
  assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
  authorization.close = () => {foreign++; return true;};
  acknowledged = true;
  const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
  assert.equal(first, second); await first;
  assert.equal(failure.cleanupHandle.status().pending, false);
  await failure.cleanupHandle.retry();
  assert.equal(calls, 2); assert.equal(foreign, 0);
});

test('Table Site cannot issue a grant after its original target or authorization callback closes the same Site', () => {
  for (const boundary of ['targets', 'issued']) {
    let site, closing = false;
    const authorization = {close() {return true;}, issued() {
      if (boundary === 'issued' && closing) site.close();
      return true;
    }};
    const f = fixture(authorization, {targets() {
      if (boundary === 'targets' && closing) site.close();
      return [{resource: 'rows'}];
    }});
    site = f.site; assert.ok(site.issueReadGrant(f.request)); closing = true;
    assert.throws(() => site.issueReadGrant(f.request), {code: 'InstalledTableSiteClosed'});
  }
});


test('Table owned Site never treats a Promise or foreign thenable as its original close ACK', async () => {
  let mode = 'promise', calls = 0, thenReads = 0;
  const asynchronous = Promise.reject(Object.freeze({original: 'late close refusal'}));
  const foreign = {get then() {thenReads++; throw new Error('foreign then getter');}};
  const authorization = {close() {
    assert.equal(this, authorization); calls++;
    return mode === 'promise' ? asynchronous : mode === 'thenable' ? foreign : true;
  }};
  const {site, request} = fixture(authorization);
  assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
  await new Promise(resolve => setImmediate(resolve));
  assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
  mode = 'thenable';
  assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
  assert.equal(thenReads, 0);
  mode = 'ack'; site.close(); site.close();
  assert.equal(calls, 3);
});

test('Table owned Site retains one unresolved original close flight without treating its settlement as ACK', async () => {
  let resolve, calls = 0, settled = false;
  const entered = new Promise(done => {resolve = done;});
  const authorization = {close() {calls++; return settled ? true : entered;}};
  const {site, request} = fixture(authorization);
  assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
  assert.throws(() => site.close(), {code: 'InstalledSourceAuthorizationCleanupPending'});
  assert.equal(calls, 1);
  resolve(true); await entered;
  assert.throws(() => site.issueReadGrant(request), {code: 'InstalledTableSiteClosed'});
  settled = true; site.close(); site.close();
  assert.equal(calls, 2);
});
