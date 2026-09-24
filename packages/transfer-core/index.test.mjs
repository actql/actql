import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../adapters/host-common/runtime-core.mjs';
import * as transfer from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const bounds = {maxChunks: 2, maxManifestBytes: 4096,
  maxReferencedBytes: 5n};
const issuer = runtimeCore(moon).remoteTransferControl;
const sourceRequest = issuer.prepare({
  coordinatorAuthority: 'coordinator-a',
  transferAttemptId: 'transfer-a', route: 'direct',
  sourceSite: 'source-a', sourceSiteGeneration: 1,
  destinationSite: 'destination-b', destinationSiteGeneration: 2,
  sourceMaterialGeneration: 'material-a',
  physicalManifest: {
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'), viewContractCid: cid('2'),
    codecContractCid: cid('3'), rowCount: 1,
    chunks: [{cid: cid('a'), byteLength: 5n, rowCount: 1}],
  },
  limits: bounds, capacityBytes: 5n,
  expiresAtMilliseconds: 2_000_000_000_000n,
  sourceGrantCid: cid('4'), destinationGrantCid: cid('5'),
  routeCapabilityCid: cid('6'),
});
const envelope = issuer.admissionEnvelopeJson(sourceRequest);
const requestCid = issuer.identity(sourceRequest);
const manifestCid = issuer.requestProjection(sourceRequest)[7];

test('portable Transfer owner admits exact envelope and canonical record',
  () => {
    const request = transfer.admitEnvelopeJson(envelope, requestCid,
      manifestCid, bounds);
    assert.equal(transfer.requestCid(request), requestCid);
    assert.deepEqual(transfer.requestJournalKey(request),
      ['coordinator-a', 'destination-b', '2', 'transfer-a']);
    assert.deepEqual(transfer.requestProjection(request), {
      cid: requestCid, route: 'direct', sourceSiteKey: 'source-a',
      sourceSiteGeneration: '1', destinationSiteKey: 'destination-b',
      destinationSiteGeneration: '2', materialGeneration: 'material-a',
      manifestCid, maxBytes: '5', expiresUnixMs: '2000000000000',
      sourceGrantCid: cid('4'), destinationGrantCid: cid('5'),
      routeCapabilityCid: cid('6'),
    });
    assert.deepEqual(transfer.chunks(request),
      [{cid: cid('a'), byteLength: 5n}]);
    assert.equal(transfer.activeAt(request, 1_999_999_999_999n), true);
    assert.equal(transfer.activeAt(request, 2_000_000_000_000n), false);
    assert.throws(() => transfer.admitEnvelopeJson(envelope,
      cid('f'), manifestCid, bounds), {code: 'TransferOwnerRejected'});
    assert.throws(() => transfer.admitEnvelopeJson(`${envelope} `,
      requestCid, manifestCid, bounds), {code: 'TransferOwnerRejected'});

    const initial = transfer.openRecord(request);
    const initialBody = transfer.recordDurableJson(initial);
    const restored = transfer.admitDurableJson(initialBody, bounds);
    assert.equal(transfer.durableRevision(restored), 0);
    assert.equal(transfer.durableRequestCid(restored), requestCid);
    assert.equal(transfer.replyJson(transfer.restoreDurable(restored)),
      transfer.replyJson(initial));
    const persist = transition => {
      const expected = transfer.transitionExpectedRevision(transition);
      const body = transfer.transitionDurableJson(transition);
      const admitted = transfer.admitDurableJson(body, bounds);
      assert.equal(transfer.durableRevision(admitted), expected + 1);
      transfer.commitTransition(transition);
      return transfer.restoreDurable(admitted);
    };
    let record = transfer.restoreDurable(restored);
    record = persist(transfer.prepareStart(record));
    assert.equal(transfer.directProgress(record), 1);
    record = persist(transfer.prepareSourceSettled(record, true, false));
    assert.equal(transfer.directProgress(record), 2);
    record = persist(transfer.prepareDestinationCommit(record));
    assert.equal(transfer.directProgress(record), 3);
    assert.equal(transfer.recordIsDestinationCommitted(record), true);
    const reply = transfer.replyJson(record);
    assert.equal(issuer.recordIsDestinationCommitted(
      issuer.admitReplyJson(reply, sourceRequest)), true);
    assert.throws(() => transfer.admitDurableJson(
      initialBody.replace('"revision":0', '"revision":3'), bounds),
    {code: 'TransferOwnerRejected'});
  });
