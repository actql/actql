// Actual Common/Effect Ledger and portable GCS owner; physical responses are
// controlled. No Account approval, installed driver or service is substituted.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from '../../../host-node/effect-response-recovery.mjs';
import {prepareGcsObjectBinding, admitGcsObjectMetadata, prepareOwnedGcsEffectMetadataPatch,
  prepareOwnedGcsObjectDelete, projectOwnedGcsObjectResponse, ownedGcsObjectResponseMatches,
  sendOwnedGcsObjectRequest, restoreOwnedGcsObjectMutationRequest} from '../site/gcs-owned-object-request.mjs';

const token = digit => `sha256:${digit.repeat(64)}`;
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const originalBody = Buffer.from(JSON.stringify({bucket: 'bucket', name: 'in/e\u0301.csv',
  generation: '9007199254740993', metageneration: '2', size: '7',
  metadata: {old: 'remove', 'actql-request': 'foreign-old-marker'}}));
const answer = changes => Buffer.from(JSON.stringify({bucket: 'bucket', name: 'in/e\u0301.csv',
  generation: '9007199254740993', metageneration: '3', size: '7', contentType: 'text/csv',
  metadata: {'e\u0301': '=exact\r\n', 'actql-request': token('d')}, ...changes}));

function bindingOf(kind, moon) {
  return prepareGcsObjectBinding(moon, {kind, bucket: 'bucket', prefix: 'in/',
    catalogCid: token('a'), installationCid: token('b'), contractCid: token('c'),
    permissions: [kind === 'patch_metadata' ? 'storage.objects.update' : 'storage.objects.delete'],
    metadata, maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384});
}

function requestOf(kind, moon = provider) {
  const binding = bindingOf(kind, moon);
  const original = admitGcsObjectMetadata(moon, {bytes: originalBody, bucket: 'bucket',
    prefix: 'in/', name: 'in/e\u0301.csv', limits: metadata});
  const request = kind === 'patch_metadata'
    ? prepareOwnedGcsEffectMetadataPatch({moon, binding, original,
      value: {content_type: 'text/csv', metadata: {$json: {'e\u0301': '=exact\r\n'}}},
      marker: token('d'), maxProjectionBytes: 8192})
    : prepareOwnedGcsObjectDelete({moon, binding, original, maxProjectionBytes: 8192});
  // Retained target bytes/intent are explicit component evidence. They do not
  // authenticate cold installation custody or reissue the old child's current.
  const saved = {name: 'in/e\u0301.csv', responseStatus: 200, responseHeaders: [],
    responseBytes: originalBody,
    responseSha256: createHash('sha256').update(originalBody).digest('hex'),
    changesBytes: Buffer.from(JSON.stringify(request.value)), body: request.body,
    requestCid: request.request_cid, maxProjectionBytes: 8192};
  return {binding, original, request, restore: () => restoreOwnedGcsObjectMutationRequest({
    moon, binding: bindingOf(kind, moon), ...saved})};
}

test('original PATCH response requires marker version and full logical replacement without another read', () => {
  const {binding, request} = requestOf('patch_metadata');
  assert.deepEqual(projectOwnedGcsObjectResponse(request, {statusCode: 200, body: answer()}, 1024),
    {kind: 'typed-success-response', outcome: {state: 'applied', result: {}}});
  for (const changes of [{metageneration: '2'}, {generation: '9007199254740994'},
    {metadata: {'e\u0301': '=exact\r\n'}},
    {metadata: {'e\u0301': '=exact\r\n', 'actql-request': 'another-request'}},
    {metadata: {'e\u0301': '=exact\r\n', old: 'remove', 'actql-request': token('d')}}]) {
    assert.deepEqual(projectOwnedGcsObjectResponse(request, {statusCode: 200, body: answer(changes)}, 1024),
      {kind: 'provider-response'});
  }
  const observed = admitGcsObjectMetadata(provider, {bytes: answer(), bucket: 'bucket',
    prefix: 'in/', name: 'in/e\u0301.csv', limits: metadata});
  assert.equal(ownedGcsObjectResponseMatches(request, observed, binding), true);
  assert.throws(() => projectOwnedGcsObjectResponse({...request}, {statusCode: 200, body: answer()}, 1024),
    {code: 'ForeignGcsObjectRequest'});
  assert.throws(() => ownedGcsObjectResponseMatches(request, observed, requestOf('patch_metadata').binding),
    {code: 'GcsForeignObjectBinding'});
  assert.throws(() => projectOwnedGcsObjectResponse(request, {statusCode: 200, body: new Uint8Array(new SharedArrayBuffer(16))}, 1024),
    {code: 'InvalidGcsObjectResponse'});
});

test('original DELETE classifies only direct empty 204 and conditional 412 without treating absence as apply', () => {
  const {request, original} = requestOf('delete');
  assert.deepEqual(projectOwnedGcsObjectResponse(request, {statusCode: 204, body: Buffer.alloc(0)}, 1024),
    {kind: 'typed-success-response', outcome: {state: 'applied', result: {}}});
  assert.equal(ownedGcsObjectResponseMatches(request, original), false);
  for (const [statusCode, body] of [[204, Buffer.from('{}')], [200, Buffer.alloc(0)], [404, Buffer.alloc(0)]]) {
    assert.deepEqual(projectOwnedGcsObjectResponse(request, {statusCode, body}, 1024), {kind: 'provider-response'});
  }
  assert.deepEqual(projectOwnedGcsObjectResponse(request, {statusCode: 412, body: Buffer.from('{}')}, 1024),
    {kind: 'typed-failure-response', outcome: {state: 'failed', error: {
      code: 'conflict', message: 'The original GCS mutation precondition failed'}}});
});

test('missing mutation response ABI refuses without classifying or replacing the original request', () => {
  const {request, original} = requestOf('patch_metadata', {...provider,
    gcsObjectResponseProjection: undefined, gcsObjectResponseMatches: undefined});
  assert.throws(() => projectOwnedGcsObjectResponse(request, {statusCode: 200, body: answer()}, 1024),
    {code: 'GcsObjectResponseUnavailable'});
  assert.throws(() => ownedGcsObjectResponseMatches(request, original),
    {code: 'GcsObjectResponseUnavailable'});
  assert.equal(request.method, 'PATCH');
  assert.match(request.request_cid, /^sha256:[0-9a-f]{64}$/u);
});

async function fixture(t, kind) {
  const {request, restore} = requestOf(kind), control = runtimeCore(common).effectApplicationControl;
  const scope = control.logicalRequestScope(token('a'), `mutation-${kind}`, 64);
  const key = control.dispatchKey(scope, token('b'), '"row-1"', 64, 8, 3);
  const locator = control.logicalItemLocator(scope, 'program', 'stage', 'Mutation', '{"row":"1"}', 64, 128, 8, 3);
  const basis = control.ledgerBasis(scope, locator, key, token('c'), token('d'), token('e'),
    request.request_cid, token('0'), 'unavailable', token('1'), token('2'));
  const claim = {scope, locator, key, basis, intentFingerprintCid: token('e'), canonicalRequestCid: request.request_cid};
  const parent = new URL('../../../../_build/gcs-mutation-ledger-evidence/', import.meta.url).pathname;
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, `original-${kind}-`));
  t.diagnostic(`Original mutation Ledger/raw evidence retained at ${root}`);
  const handles = new Set();
  const open = () => {
    const ledger = openEffectLedger({moon: common, root, authorityScopeCid: token('a'),
      callerRequestId: `mutation-${kind}`, maxEntryBytes: 8192});
    handles.add(ledger);return ledger;
  };
  const close = ledger => {ledger.close();handles.delete(ledger);};
  t.after(() => {for (const handle of handles) close(handle);});
  const send = callResource => sendOwnedGcsObjectRequest({request,
    authorization: {grant: {}, useId: 'controlled-original-response', scope: {
      resourceOrigin: 'https://storage.googleapis.com', operation: request.operation}},
    credential: {}, callResource, maxRequestBytes: 8192, maxResponseBytes: 8192});
  return {request, restore, claim, control, open, close, send};
}

for (const kind of ['patch_metadata', 'delete']) {
  test(`actual Core ${kind} direct response reopens from original Ledger without resend`, async t => {
    const f = await fixture(t, kind), ledger = f.open();let sends = 0;
    const statusCode = kind === 'patch_metadata' ? 200 : 204;
    const body = kind === 'patch_metadata' ? answer() : Buffer.alloc(0);
    const captured = await captureClaimedEffectResponse({ledger, claim: f.claim, requestCid: f.request.request_cid,
      execute: () => f.send(async () => {sends++;return {useCid: token('3'), accepted: true, statusCode, body, headers: []};})});
    assert.equal(projectOwnedGcsObjectResponse(f.request, captured.physical.observation, 1024).outcome.state, 'applied');
    f.close(ledger);const restarted = f.open();let authorized = 0;
    const restored = f.restore();
    assert.notEqual(restored, f.request, 'recovery uses new local nominal membership');
    assert.deepEqual(restored, f.request);
    const recovery = {ledger: restarted, claims: f.claim, commonMoon: common,
      expectedRequestCid: restored.request_cid,
      authorizeEvidenceRead: async value => {authorized++;assert.equal(value.canonicalRequestCid, f.request.request_cid);return true;},
      projectStored: stored => projectOwnedGcsObjectResponse(restored, {statusCode: stored.statusCode, body: stored.responseBytes}, 1024)};
    const recovered = await recoverProjectedEffectResponse(recovery);
    assert.equal(recovered.recovered.outcome.state, 'applied');assert.equal(authorized, 1);
    await assert.rejects(recoverProjectedEffectResponse({...recovery, authorizeEvidenceRead: async () => false}),
      {code: 'EffectEvidenceAccessDenied'});
    const repeated = await captureClaimedEffectResponse({ledger: restarted, claim: f.claim, requestCid: restored.request_cid,
      execute: () => assert.fail('Existing possible-dispatch ownership forbids another send')});
    assert.equal(repeated.claimed, false);assert.equal(sends, 1);
  });

  test(`actual Core ${kind} lost response remains Unknown after reopen without replacing original request`, async t => {
    const f = await fixture(t, kind), ledger = f.open();let sends = 0;
    const primary = Object.freeze(Object.assign(new Error(`original ${kind} response lost`), {cleanupPending: true}));
    await assert.rejects(captureClaimedEffectResponse({ledger, claim: f.claim, requestCid: f.request.request_cid,
      execute: () => f.send(async () => {sends++;throw primary;})}), error => error === primary);
    assert.equal(ledger.readClaimedResponse(f.claim), undefined);
    f.close(ledger);const restarted = f.open();
    const restored = f.restore();
    assert.equal(restored.request_cid, f.request.request_cid);
    const repeated = await captureClaimedEffectResponse({ledger: restarted, claim: f.claim, requestCid: restored.request_cid,
      execute: () => assert.fail('Object absence or matching metadata cannot authorize replay')});
    assert.equal(repeated.claimed, false);assert.equal(sends, 1);
    assert.equal(restarted.readClaimedResponse(f.claim), undefined);
  });
}
