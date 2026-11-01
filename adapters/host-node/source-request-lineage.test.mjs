import assert from 'node:assert/strict';
import test from 'node:test';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {submissionEpoch, originalSubmission} from '../../packages/sdk/submission-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'source-lineage', capabilities: ['aql-document'], submissionEpoch,
  limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 65536, maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};

// Actual SDK, registry, ingress and submission transformations; explicit
// Common/Journal/Source ports stop before admission, dispatch or physical I/O.
async function fixture(t, inspect, deferredIngress = false) {
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const host = {}, installation = {}, receipt = {}, prepared = {};
  let packet, preparations = 0, finishes = 0, writes = 0;
  const original = value => registry.originalSourceRequest(host, installation, host, value);
  const bindOwnedRequest = (parent, derived) =>
    registry.bindSourceRequest(host, installation, host, parent, derived);
  const interrupted = Object.freeze(new Error('OriginalJournalNotEntered'));
  const journal = {close() {}, checkSubmittedIntent() {}, lookupSubmittedIntent() {},
    recordSubmittedIntent() {assert.fail('NoLegacyReceipt');},
    verifySubmissionEpoch: () => ({validity: 'admissible'}),
    submissionIdentity: () => ({requestId: 'original-request'}),
    checkSubmissionAttempt: () => ({kind: 'checked'}),
    recordSubmissionAttempt() {
      assert.equal(original(prepared), packet);
      writes++; throw interrupted;
    }};
  const service = installNodeClientSubmission({journal,
    moon: {clientSubmittedIntent: () => ({}), clientSubmittedIntentCid: () => cid('d')},
    authorizedScope: () => ({authorityScopeCid: cid('a'), namespaceId: 'original'}),
    async prepareSubmit(request) {
      preparations++;
      assert.notEqual(request, packet);
      assert.equal(original(request), packet);
      await Promise.resolve();
      assert.equal(original(request), packet);
      await inspect?.({registry, host, installation, request, packet, original});
      return prepared;
    },
    submit() {assert.fail('NoDispatch');}, lookupRequest() {return {kind: 'not_found'};},
    bindOwnedRequest,
  });
  const actualIngress = createNodeInProcessClientHost({authenticate: () => 'original-actor',
    authorizeConnection: () => true, negotiate: () => profile,
    submitIntent: service.submitAttempt, maxRowBytes: 65536, bindOwnedRequest});
  const ingress = deferredIngress ? createNodeInProcessClientHost({
    authenticate: () => 'original-actor',authorizeConnection: () => true,
    negotiate: () => profile,maxRowBytes:65536,bindOwnedRequest,
    async performInstalledRequest(operation,body,signal) {
      await Promise.resolve();
      return actualIngress.perform(operation,body,signal);
    },
  }) : actualIngress;
  const receiver = {
    captureSourceSnapshot(_receipt, value, snapshot) {return snapshot(value);},
    assertSourceSnapshotCurrent() {},
    publishSourceSnapshot() {},
    beforeSourceSnapshot: () => receipt, bindSourceSnapshot() {},
    bindSourceRequest(value, _body, request) {assert.equal(value, receipt); packet = request;},
    intentCid: () => cid('d'), finishSourceProducer(value) {
      assert.equal(value, receipt); finishes++;
    }};
  Object.assign(host, {port: {...ingress, [sourcePreparationPort]: receiver},
    dispatchOwner: {drain() {}}, retireTerminalEffects() {}, journal, store: {close() {}}});
  registry.registerPreparation(host, installation, host);
  const client = await registry.connect('/source-lineage', 'original', async () => host,
    {mode: 'local', owner: 'local'}, host);
  t.after(() => client.close());
  return {client, prepared, original, packet: () => packet,
    counts: () => ({preparations, finishes, writes})};
}

test('the original SDK packet survives Host copies and the awaited actual preparation return by nominal lineage', async t => {
  const f = await fixture(t);
  await assert.rejects(f.client.startSource('SELECT 1 AS n', {
    format: 'sql', submissionRef: originalSubmission('same-original-lineage')}));
  assert.deepEqual(f.counts(), {preparations: 1, finishes: 1, writes: 1});
  // The live ingress flight, not a matching body/CID, owns these aliases.
  assert.throws(() => f.original(f.prepared), {code: 'InstalledHostPreparationChanged'});
  assert.throws(() => f.original(f.packet()), {code: 'InstalledHostPreparationChanged'});
});

test('deferred same-Host ingress retains the actual SDK Source receipt through both admitted snapshots', async t => {
  const f = await fixture(t, undefined, true);
  await assert.rejects(f.client.startSource('SELECT 1 AS n', {
    format:'sql',submissionRef:originalSubmission('deferred-same-original-lineage')}));
  assert.deepEqual(f.counts(),{preparations:1,finishes:1,writes:1});
  assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
  assert.throws(()=>f.original(f.packet()),{code:'InstalledHostPreparationChanged'});
});

test('copied, foreign and over-limit aliases cannot manufacture another original or dispatch', async t => {
  const f = await fixture(t, ({registry, host, installation, request, packet, original}) => {
    assert.throws(() => original({...request}), {code: 'InstalledHostPreparationChanged'});
    assert.throws(() => registry.bindSourceRequest(host, installation, {}, request, {}),
      {code: 'InstalledHostPreparationChanged'});
    assert.throws(() => registry.bindSourceRequest(host, installation, host, {...packet}, {}),
      {code: 'InstalledHostPreparationChanged'});
    assert.throws(() => ({...registry, originalSourceRequest: () => packet})
      .bindSourceRequest(host, installation, host, {...packet}, {}),
    {code: 'InstalledHostPreparationChanged'});
    let accepted = 0;
    for (let index = 0; index < 16; index++) {
      const alias = {};
      try {registry.bindSourceRequest(host, installation, host, request, alias); accepted++;}
      catch (error) {assert.equal(error.code, 'SourceManagedPreparationUnavailable'); break;}
      assert.equal(original(alias), packet);
    }
    assert.ok(accepted > 0 && accepted < 16, 'Existing actual clones occupy their original bounded slots');
    assert.equal(original(request), packet, 'Refusal retains the same original pending request');
  });
  await assert.rejects(f.client.startSource('SELECT 1 AS n', {
    format: 'sql', submissionRef: originalSubmission('bounded-original-lineage')}));
  assert.deepEqual(f.counts(), {preparations: 1, finishes: 1, writes: 0});
});

test('read-only submission lookup keeps the original live Host ingress lineage', async t => {
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const host = {}, installation = {};
  const calls = {intentProjection: 0, retain: 0, release: 0, lookup: 0};
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'lookup-lineage', capabilities: ['aql-document'], submissionEpoch,
    limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
      maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
  const bindOwnedRequest = (parent, derived) =>
    registry.bindSourceRequest(host, installation, host, parent, derived);
  const journal = {close() {}, checkSubmittedIntent() {}, recordSubmittedIntent() {assert.fail('NoSubmit');},
    retainSubmissionOperation(_epoch, _control, borrowed) {
      assert.equal(borrowed, undefined); calls.retain++;
      return () => {calls.release++;};
    },
    lookupSubmittedIntent() {calls.lookup++; return undefined;}};
  const service = installNodeClientSubmission({journal,
    moon: {clientSubmittedIntent() {assert.fail('NoCompiler');}},
    authorizedScope: () => ({authorityScopeCid: 'sha256:' + 'a'.repeat(64), namespaceId: 'lookup-lineage'}),
    prepareSubmit() {assert.fail('NoPreparation');}, submit() {assert.fail('NoDispatch');},
    lookupRequest() {assert.fail('NoRunLookup');}, bindOwnedRequest,
    submittedIntentOriginal(request) {
      calls.intentProjection++;
      // The actual fixed Host resolves this original before asking whether
      // a selected producer has a borrowed intent. A lookup has no producer.
      try {registry.originalSourceRequest(host, installation, host, request);}
      catch(error) {console.log(JSON.stringify({boundary:'submittedIntentOriginal',code:error.code}));throw error;}
      return undefined;
    }});
  host.port = createNodeInProcessClientHost({authenticate: () => 'lookup-actor',
    authorizeConnection: () => true, negotiate: () => profile,
    lookupSubmission: service.lookupSubmission, maxRowBytes: 65536, bindOwnedRequest});
  Object.assign(host, {dispatchOwner: {drain() {}}, retireTerminalEffects() {}, journal, store: {close() {}}});
  registry.registerPreparation(host, installation, host);
  const client = await registry.connect('/lookup-lineage', 'lookup-lineage', async () => host,
    {mode: 'local', owner: 'local'}, host);
  t.after(() => client.close());
  const answer = await client.lookupSubmission(originalSubmission('lookup-only'));
  assert.equal(answer.kind, 'unresolvable');
  assert.deepEqual(calls, {intentProjection: 0, retain: 1, release: 1, lookup: 1});
});
