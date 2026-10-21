import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {deliverPublishedResult} from '../host-common/result-delivery.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// A focused diagnostic can select an independently qualified existing Common
// in its normal FFI layout. The default is the ordinary prepared JS target.
const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);
const cid = value => `sha256:${value.repeat(64)}`;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const at = '2026-09-18T01:00:00.000Z';

function originals(control) {
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1', result_definition_cid: cid('1'),
    invocation_cid: cid('2'), logical_result_cid: cid('3'),
    result_schema_cid: cid('4'), ordering_evidence_cid: cid('5'),
    actual_row_count: 1, actual_completeness: 'complete',
    effective_data_policy_cid: cid('6'), effective_retention_policy_cid: cid('7'),
    provenance_evidence_cids: [cid('8')],
  }), limits);
  const manifest = control.seal('result_manifest', JSON.stringify({
    version: 'actql-result-manifest/0.1', run_definition_cid: cid('9'),
    invocation_cid: cid('2'), results: {answer: JSON.parse(artifact.wire)},
  }), limits);
  const index = control.seal('public_index_entry', JSON.stringify({
    version: 'actql-public-index-entry/0.1', namespace_id: 'namespace',
    authority_scope_cid: cid('a'), run_definition_cid: cid('9'),
    invocation_cid: cid('2'), result_manifest_cid: manifest.identity,
    run_receipt_cid: cid('b'), captured_run_cid: cid('c'),
    durable_result_binding_cids: [cid('d')], publication_request_cid: cid('e'),
    publication_attempt_cid: cid('f'), committed_at: at,
  }), limits);
  const grant = control.issueResultReadGrant(index, manifest, {
    resultNames: ['answer'], formats: ['json'], principalId: 'principal',
    purpose: 'download', dataCeilingCid: cid('1'), maxBytes: 4096, maxUses: 1,
    expiresAt: '2026-09-19T00:00:00.000Z', authorizationContextCid: cid('2'),
    egressAdmissionCid: cid('3'),
  }, limits);
  const attempt = control.issueDeliveryAttempt(index, manifest, grant, {
    resultName: 'answer', format: 'json', attemptId: 'completion', requestedAt: at,
  }, limits);
  const update = (state, extra = {}) => ({state, confirmedByteCount: 0,
    exposure: 'exact', possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: undefined, receipt: undefined, failureCid: undefined,
    observedAt: at, cleanupOwnerCids: [], ...extra});
  const streaming = control.issueDeliveryRecord(attempt, undefined,
    update('streaming'), limits);
  const receipt = control.issueResultDeliveryReceipt(index, manifest, grant,
    attempt, {byteCount: 2, sha256: '0'.repeat(64)}, limits);
  const succeeded = control.issueDeliveryRecord(attempt, streaming,
    update('succeeded', {confirmedByteCount: 2, deliveredSha256: '0'.repeat(64),
      receipt}), limits);
  return {index, manifest, grant, attempt, streaming, receipt, succeeded};
}

async function fixture(t, beforeSync = () => {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-completion-'));
  const control = runtimeCore(moon).publicationControl;
  const root = originals(control), syncs = [];
  const configuration = {directory, storeAuthorityCid: cid('a'),
    capacityBytes: 1048576, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64};
  const stores = [];
  const reopen = async () => {
    const store = await openLocalPublicationStore(configuration, control, {
      async syncDirectory(path) {
        syncs.push(path);
        await beforeSync(path);
        const handle = await open(path, 'r');
        try { await handle.sync(); } finally { await handle.close(); }
      },
    });
    stores.push(store);
    return store;
  };
  t.after(async () => {
    for (const store of stores) await store.close();
    await rm(directory, {recursive: true});
  });
  const store = await reopen();
  await store.createDeliveryAttempt(root.attempt.wire, root.grant.wire);
  await store.appendDeliveryRecord(root.streaming.wire);
  syncs.length = 0;
  return {directory, control, root, store, syncs, reopen};
}

test('delivery END shares semantic directory ACKs for its real receipt and record', async t => {
  const {directory, root, store, syncs, reopen} = await fixture(t);
  // Retain the old executable path as the counter's baseline, not a fake
  // failed lookup or a claim that an absent optional port completed a batch.
  if (typeof store.appendDeliveryCompletion === 'function') {
    await store.appendDeliveryCompletion(root.receipt.wire, root.succeeded.wire);
  } else {
    await store.putPublicationContract(root.receipt.name, root.receipt.wire);
    await store.appendDeliveryRecord(root.succeeded.wire);
  }
  assert.equal(syncs.filter(path => path === join(directory, 'objects')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'contracts')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'deliveries',
    root.attempt.identity.slice(7))).length, 1);
  assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  assert.equal((await store.latestDeliveryRecord(root.attempt.identity)).state, 'succeeded');
  assert.equal((await store.readPublicationContract(root.receipt.identity,
    root.receipt.name)).wire, root.receipt.wire);
  await store.close();
  const reopened = await reopen();
  assert.equal((await reopened.latestDeliveryRecord(root.attempt.identity)).state,
    'succeeded');
  assert.equal((await reopened.readPublicationContract(root.receipt.identity,
    root.receipt.name)).wire, root.receipt.wire);
});
