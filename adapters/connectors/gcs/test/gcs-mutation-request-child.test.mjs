// Actual compiled GCS semantics and existing Credential binding. Physical
// success ports are explicit contract controls, not normal funding/admission.
import assert from 'node:assert/strict';
import {open, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {createGcsMutationRequestChild, prepareGcsObjectBinding,
  ownedGcsObjectRequestCid, sendOwnedGcsObjectRequest} from '../site/gcs-owned-object-request.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const name = 'in/e\u0301%2F.csv';
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const scope = Object.freeze({issuerAuthority: 'fixture', principal: 'operator',
  namespaceId: 'fixture', environment: 'test', siteKey: 'site', siteGeneration: 1,
  runtimeBundleCid: cid('a'), connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
  resourceOrigin: 'https://storage.googleapis.com', operation: 'gcs:file:read',
  runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
  expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 1});
const authorization = () => ({scope, grant: {}, useId: 'original-target-read'});
const bytes = () => Buffer.from(JSON.stringify({bucket: 'bucket', name, generation: '9007199254740993',
  metageneration: '2', size: '7', metadata: {drop: 'old', keep: 'kept', 'actql-request': 'old'}}));
const response = () => ({accepted: true, statusCode: 200, useCid: cid('e'), body: bytes(), headers: []});
const deferred = () => {let resolve;const promise = new Promise(r => {resolve = r;});return {promise, resolve};};
async function entered(predicate) {
  for (let i = 0; i < 100; i++) {
    if (predicate()) return;
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('Original operation was not entered');
}
function options(extra = {}) {
  const kind = extra.kind ?? 'patch_metadata';
  return {moon, kind, binding: prepareGcsObjectBinding(moon, {kind, bucket: 'bucket', prefix: 'in/',
    catalogCid: cid('a'), installationCid: cid('b'), contractCid: cid('c'),
    permissions: [kind === 'patch_metadata' ? 'storage.objects.update' : 'storage.objects.delete'],
    metadata, maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384}),
  name, value: {content_type: 'text/csv', metadata: {keep: 'kept', new: '=e\u0301\r\n'}},
  marker: cid('d'), maxProjectionBytes: 8192, maxRequestBytes: 4096, maxSecretBytes: 128,
  credential: {control: {identity: () => cid('a')}, journal: {claim() {}, authorize() {}, finish() {}},
    resolveSecret: async () => 'fixture-only'},
  authorizationForRow: async () => authorization(), assertCurrent() {}, callResource: async () => response(), ...extra};
}

test('original mutation child registers before one GET and invalidates the same request on retirement', async () => {
  let calls = 0, approvals = 0;
  const child = createGcsMutationRequestChild(options({
    authorizationForRow: async () => {approvals++;return authorization();},
    callResource: async invocation => {
      calls++;assert.ok(invocation.binding);
      assert.equal(invocation.operations.get('gcs:file:read').method, 'GET');
      return response();
    }}));
  const snapshot = child.status();
  assert.equal(snapshot.pending, true);
  const first = child.prepare();
  assert.equal(child.prepare(), first);
  const {request, requestCid} = await first;
  assert.equal(requestCid, 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(ownedGcsObjectRequestCid(request), requestCid);
  assert.equal(calls, 1);assert.equal(approvals, 1);
  assert.equal(child.status().pending, true, 'prepared request remains borrowed until explicit owner retirement');
  assert.equal(await child.release(), true);
  assert.equal(child.status().pending, false);
  assert.equal(snapshot.pending, true);
  assert.ok(Object.isFrozen(snapshot));
  assert.throws(() => ownedGcsObjectRequestCid(request), {code: 'ForeignGcsObjectRequest'});
  await assert.rejects(sendOwnedGcsObjectRequest({request}), {code: 'ForeignGcsObjectRequest'});
  await assert.rejects(child.prepare(), {code: 'GcsOriginalMutationPreparationUnavailable'});
  assert.equal(await child.retry(), false);
  assert.equal(calls, 1);
});

test('original mutation child produces a bodyless delete from the same original before observation', async () => {
  const child = createGcsMutationRequestChild(options({kind: 'delete', value: {}}));
  const {request} = await child.prepare();
  assert.equal(request.method, 'DELETE');assert.equal(request.body, '');
  assert.ok(request.path.endsWith('ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2'));
  assert.equal(await child.release(), true);
});

test('original mutation child retains pending GET and cannot prepare another request after release', async () => {
  const gate = deferred();let calls = 0;
  const child = createGcsMutationRequestChild(options({callResource: async () => {calls++;await gate.promise;return response();}}));
  const preparation = child.prepare();
  const rejected = assert.rejects(preparation, {code: 'GcsOriginalMutationPreparationUnavailable'});
  await entered(() => calls === 1);
  const release = child.release();assert.equal(child.retry(), release);
  assert.equal(await release, false);assert.equal(child.status().pending, true);
  gate.resolve();await rejected;
  assert.equal(await child.retry(), true);
  assert.equal(child.status().pending, false);assert.equal(calls, 1);
});

test('original mutation child rechecks currentness after approval before opening the read', async () => {
  const gate = deferred();let current = true, calls = 0, approvals = 0;
  const primary = Object.freeze(new Error('OriginalSiteRetired'));
  const child = createGcsMutationRequestChild(options({
    assertCurrent() {if (!current) throw primary;},
    authorizationForRow: async () => {approvals++;await gate.promise;return authorization();},
    callResource: async () => {calls++;assert.fail('No original current read');}}));
  const preparation = child.prepare();
  const rejected = assert.rejects(preparation, error => error === primary);
  await entered(() => approvals === 1);current = false;gate.resolve();await rejected;
  await assert.rejects(child.prepare(), error => error === primary);
  assert.equal(calls, 0);assert.equal(approvals, 1);
  assert.equal(await child.release(), true);
});

test('original mutation child rechecks the same Site after the original GET without another read', async () => {
  let current = true, calls = 0;
  const primary = Object.freeze(new Error('OriginalSiteChangedAfterRead'));
  const child = createGcsMutationRequestChild(options({
    assertCurrent() {if (!current) throw primary;},
    callResource: async () => {calls++;current = false;return response();}}));
  await assert.rejects(child.prepare(), error => error === primary);
  await assert.rejects(child.prepare(), error => error === primary);
  assert.equal(child.status().pending, true);
  assert.equal(await child.release(), true);assert.equal(calls, 1);
});

test('original mutation child can retire before prepare without issuing approval or opening a binding', async () => {
  let approvals = 0;
  const child = createGcsMutationRequestChild(options({authorizationForRow: async () => {approvals++;assert.fail('No entry after retirement');}}));
  assert.equal(await child.release(), true);
  await assert.rejects(child.prepare(), {code: 'GcsOriginalMutationPreparationUnavailable'});
  assert.equal(child.status().pending, false);assert.equal(approvals, 0);
});

test('original mutation child snapshots admitted row bytes before approval await', async () => {
  const gate = deferred();let approvals = 0;
  const value = {content_type: 'text/csv', metadata: {keep: 'kept', new: '=e\u0301\r\n'}};
  const child = createGcsMutationRequestChild(options({value,
    authorizationForRow: async () => {approvals++;await gate.promise;return authorization();}}));
  const preparation = child.prepare();await entered(() => approvals === 1);
  value.content_type = 'changed/after-await';value.metadata = {'foreign': 'replacement'};
  gate.resolve();const {requestCid} = await preparation;
  assert.equal(requestCid, 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(await child.release(), true);
});

test('original mutation child requires selected bounds ABI and original binding kind before read approval', async () => {
  let approvals = 0;
  const base = options({authorizationForRow: async () => {approvals++;assert.fail('No original approval');}});
  for (const extra of [{maxSecretBytes: undefined}, {maxSecretBytes: 0},
    {moon: {...moon, gcsObjectTargetObservation: undefined}}, {kind: 'delete'},
    {name: 'outside/scope'}, {assertCurrent: undefined}]) {
    const child = createGcsMutationRequestChild({...base, ...extra});
    await assert.rejects(child.prepare());
    assert.equal(await child.release(), true);
  }
  assert.equal(approvals, 0);
});

test('original mutation child snapshots the same Credential methods before approval await', async () => {
  const gate = deferred();let approvals = 0, observed;
  const original = options();
  const originalResolver = original.credential.resolveSecret;
  const child = createGcsMutationRequestChild({...original,
    authorizationForRow: async () => {approvals++;await gate.promise;return authorization();},
    callResource: async invocation => {observed = invocation.resolveSecret;return response();}});
  const preparation = child.prepare();await entered(() => approvals === 1);
  original.credential.resolveSecret = async () => 'replacement';
  gate.resolve();await preparation;
  assert.equal(observed, originalResolver);assert.equal(await child.release(), true);
  const foreign = createGcsMutationRequestChild({...original,
    credential: {...original.credential, binding: {}},
    authorizationForRow: async () => assert.fail('Do not replace an original owned binding')});
  await assert.rejects(foreign.prepare(), {code: 'GcsOriginalMutationPreparationUnavailable'});
  assert.equal(await foreign.release(), true);
});

test('original mutation child refuses an asynchronous fence but retains its original pending borrower', async () => {
  const gate = deferred();let approvals = 0;
  const child = createGcsMutationRequestChild(options({assertCurrent: () => gate.promise,
    authorizationForRow: async () => {approvals++;assert.fail('Async fence is not admission');}}));
  await assert.rejects(child.prepare(), {code: 'GcsOriginalMutationPreparationUnavailable'});
  assert.equal(await child.release(), false);assert.equal(child.status().pending, true);
  gate.resolve();await gate.promise;
  assert.equal(await child.retry(), true);assert.equal(approvals, 0);
});

test('original mutation child preserves frozen failure and same real FD close-only retry', async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-child-close-', label: 'GCS original preparation FD counter'});
  const path = join(scratch.path, 'response');await writeFile(path, bytes());
  const fd = await open(path);let pending = true, closes = 0, allowClose = false, calls = 0;
  t.after(async () => {await fd.close();scratch.passed();});
  const cleanupHandle = Object.freeze({status() {assert.equal(this, cleanupHandle);return {pending};}, async retry() {
    assert.equal(this, cleanupHandle);
    closes++;if (!allowClose) return false;await fd.close();pending = false;return {pending};
  }});
  const primary = Object.freeze(Object.assign(new Error('OriginalReadFailure'), {cleanupHandle, cleanupPending: false}));
  const child = createGcsMutationRequestChild(options({callResource: async () => {calls++;throw primary;}}));
  await assert.rejects(child.prepare(), error => error === primary);
  assert.equal(await child.release(), false);await fd.stat();
  assert.equal(child.status().errors[0], primary);assert.equal(primary.cleanupPending, false);
  allowClose = true;
  assert.equal(await child.retry(), true);
  await assert.rejects(fd.stat(), {code: 'EBADF'});
  assert.equal(closes, 2);assert.equal(calls, 1);
  assert.equal(child.status().pending, false);
});

test('original mutation child retains null thrown failure and retries a rejected same cleanup', async () => {
  const empty = createGcsMutationRequestChild(options({callResource: async () => {throw null;}}));
  await assert.rejects(empty.prepare(), failure => failure === null);
  assert.equal(empty.status().errors[0], null);assert.equal(await empty.release(), true);
  let pending = true, calls = 0;
  const closeFailure = Object.freeze(new Error('OriginalCloseRejected'));
  const primary = Object.freeze(Object.assign(new Error('OriginalReadRejected'), {cleanupHandle: {
    status: () => ({pending}), async retry() {calls++;if(calls === 1)throw closeFailure;pending = false;},
  }}));
  const child = createGcsMutationRequestChild(options({callResource: async () => {throw primary;}}));
  await assert.rejects(child.prepare(), error => error === primary);
  await assert.rejects(child.release(), error => error === closeFailure);
  assert.equal(child.status().pending, true);assert.equal(child.status().errors[0], primary);
  assert.equal(await child.retry(), true);assert.equal(calls, 2);
});

test('original mutation child uses the existing active Credential binding until resolver retirement without TCP', async () => {
  const gate = deferred();let resolutions = 0, claims = 0, finished = 0, physical = 0;
  const child = createGcsMutationRequestChild(options({callResource: callHttpsCredentialResource,
    credential: {control: {identity: () => cid('a')},
      journal: {claim() {claims++;return {replayed: false, record: {grantCid: cid('a'), useCid: cid('e')}, use: {}};},
        authorize() {physical++;assert.fail('Retired binding cannot enter physical send');}, finish() {finished++;}},
      resolveSecret: async () => {resolutions++;await gate.promise;return 'original-secret';}}}));
  const preparation = child.prepare();
  const rejected = assert.rejects(preparation, {code: 'RemoteCredentialBindingRetiring'});
  await entered(() => resolutions === 1);
  assert.equal(await child.release(), false);assert.equal(child.status().pending, true);
  gate.resolve();await rejected;
  assert.equal(await child.retry(), true);
  assert.equal(claims, 1);assert.equal(resolutions, 1);assert.equal(finished, 1);assert.equal(physical, 0);
});
