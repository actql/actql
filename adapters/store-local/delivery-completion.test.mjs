import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
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

async function fixture(t, beforeSync = () => {}, prepare = true) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-completion-'));
  const originalControl = runtimeCore(moon).publicationControl;
  const admissions = [];
  const control = {...originalControl, admit(...args) {
    const value = originalControl.admit(...args);
    admissions.push(value.identity);
    return value;
  }};
  const root = originals(control), syncs = [];
  const configuration = {directory, storeAuthorityCid: cid('a'),
    capacityBytes: 1048576, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64};
  const stores = [];
  const reopen = async () => {
    const store = await openLocalPublicationStore(configuration, control, {
      async syncDirectory(path) {
        syncs.push(path);
        await beforeSync(path, 'before');
        const handle = await open(path, 'r');
        try { await handle.sync(); } finally { await handle.close(); }
        await beforeSync(path, 'after');
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
  if (prepare) {
    await store.createDeliveryAttempt(root.attempt.wire, root.grant.wire);
    await store.appendDeliveryRecord(root.streaming.wire);
  }
  syncs.length = 0;
  admissions.length = 0;
  return {directory, control, root, store, syncs, admissions, reopen};
}

test('delivery END shares semantic directory ACKs for its real receipt and record', async t => {
  const {directory, root, store, syncs, admissions, reopen} = await fixture(t);
  // Retain the old executable path as the counter's baseline, not a fake
  // failed lookup or a claim that an absent optional port completed a batch.
  if (typeof store.appendDeliveryCompletion === 'function') {
    await store.appendDeliveryCompletion(root.attempt, root.receipt, root.succeeded);
  } else {
    await store.putPublicationContract(root.receipt.name, root.receipt.wire);
    await store.appendDeliveryRecord(root.succeeded.wire);
  }
  assert.equal(syncs.filter(path => path === join(directory, 'objects')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'contracts')).length, 1);
  assert.equal(syncs.filter(path => path === join(directory, 'deliveries',
    root.attempt.identity.slice(7))).length, 1);
  for (const original of [root.attempt, root.receipt, root.succeeded]) {
    assert.equal(admissions.filter(identity => identity === original.identity).length, 0,
      'same-owner issued inputs need no Store raw decode/admission');
  }
  assert.equal(admissions.filter(identity => identity === root.streaming.identity).length, 1,
    'the distinct stored predecessor is admitted once');
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

test('delivery END rejects copied originals and non-success records before writing', async t => {
  const {store, root, syncs} = await fixture(t);
  for (const [receipt, record] of [
    [Object.freeze({...root.receipt}), root.succeeded],
    [root.receipt, Object.freeze({...root.succeeded})],
    [originals(runtimeCore(moon).publicationControl).receipt, root.streaming],
  ]) {
    await assert.rejects(store.appendDeliveryCompletion(root.attempt, receipt, record),
      {code: 'InvalidDeliverySuccessEvidence'});
  }
  assert.deepEqual(syncs, []);
  assert.equal((await store.latestDeliveryRecord(root.attempt.identity)).state, 'streaming');
});

function deliveryOptions(f, sink, overrides = {}) {
  const {store, root, control} = f;
  // Physical END persistence uses the real Store/Common. Publication lookup
  // and the single materialized input row are explicit authorized ports here,
  // not a complete installed Host/Account or funded Source fixture.
  const facade = {...store,
    async confirmCommittedIndex() { return JSON.parse(root.index.wire); },
    async readPublicationContract(cid, name) {
      if (name === root.index.name && cid === root.index.identity) return root.index;
      if (name === root.manifest.name && cid === root.manifest.identity) return root.manifest;
      return store.readPublicationContract(cid, name);
    },
    async withCommittedResultRows(_key, definition, authorize, _bounds, use) {
      assert.equal(authorize({resultDefinitionCid: definition}), true);
      return use({durableResultBindingCid: cid('d'), logicalResultCid: cid('3'),
        resultSchemaCid: cid('4'), rowCount: 1, payloadBytes: 11,
        resultSchemaWire: '{"value":{"nullable":false,"type":"number"}}',
        resultFields: ['value']}, async row => { await row('{"value":7}'); });
    },
  };
  const options = {store: facade, control,
    indexKey: {namespaceId: 'namespace', authorityScopeCid: cid('a'),
      runDefinitionCid: cid('9')}, grant: root.grant, resultName: 'answer',
    format: 'json', attemptId: 'completion', limits,
    frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096},
    now: () => at, sink, createDigest() {
      const hash = createHash('sha256');
      return {update: bytes => hash.update(bytes), finish: () => hash.digest('hex')};
    }, authorize: () => true, signal: undefined, ...overrides};
  return {options, facade};
}

test('actual delivery caller retains joint END originals through partial ACK cleanup without resend', async t => {
  let armed = false, selectedDirectory;
  const f = await fixture(t, path => {
    if (armed && path === selectedDirectory) {
      throw Object.assign(new Error('END directory ACK'), {code: 'EIO'});
    }
  }, false);
  selectedDirectory = join(f.directory, 'contracts');
  let writes = 0, finishes = 0, issuedReceipts = 0, completionCalls = 0;
  const {options, facade} = deliveryOptions(f, {
    async write(bytes) { writes++; return {confirmedBytes: bytes.byteLength}; },
    async finish() { finishes++; armed = true; return {confirmed: true}; },
  });
  options.control = {...f.control, issueResultDeliveryReceipt(...args) {
    issuedReceipts++;
    return f.control.issueResultDeliveryReceipt(...args);
  }};
  let retainedReceipt, retainedRecord;
  const originalCompletion = f.store.appendDeliveryCompletion;
  facade.appendDeliveryCompletion = function(attempt, receipt, record) {
    assert.equal(this, facade);
    assert.equal(attempt.wire, f.root.attempt.wire);
    completionCalls++;
    if (retainedReceipt === undefined) {
      retainedReceipt = receipt;
      retainedRecord = record;
    } else {
      assert.equal(receipt, retainedReceipt);
      assert.equal(record, retainedRecord);
    }
    return Reflect.apply(originalCompletion, f.store, [attempt, receipt, record]);
  };
  options.authorize = facts => {
    if (facts.stage === 'read') facade.appendDeliveryCompletion = () => {
      assert.fail('late replacement must not receive original END duties');
    };
    return true;
  };
  let failure;
  await assert.rejects(deliverPublishedResult(options), error => {
    failure = error;
    return error.code === 'ResultDeliveryDurabilityPending' && error.cleanupPending;
  });
  assert.equal(finishes, 1);
  assert.equal(issuedReceipts, 1);
  assert.equal(completionCalls, 1);
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state, 'streaming');
  const previousWrites = writes;
  armed = false;
  const first = failure.cleanupHandle.retry();
  const second = failure.cleanupHandle.retry();
  assert.equal(first, second, 'same cleanup flight owns the original END');
  assert.equal((await first).pending, false);
  assert.equal(writes, previousWrites);
  assert.equal(finishes, 1);
  assert.equal(issuedReceipts, 1);
  assert.equal(completionCalls, 2);
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state, 'succeeded');
  assert.equal((await f.store.readPublicationContract(retainedReceipt.identity,
    retainedReceipt.name)).wire, retainedReceipt.wire);
});

test('delivery without joint END support retains the existing receipt then record path', async t => {
  const f = await fixture(t, undefined, false);
  const {options, facade} = deliveryOptions(f, {
    async write(bytes) { return {confirmedBytes: bytes.byteLength}; },
    async finish() { return {confirmed: true}; },
  });
  delete facade.appendDeliveryCompletion;
  const order = [];
  facade.putPublicationContract = async (...args) => {
    order.push('receipt');
    return f.store.putPublicationContract(...args);
  };
  facade.appendDeliveryRecord = async wire => {
    order.push(JSON.parse(wire).state);
    return f.store.appendDeliveryRecord(wire);
  };
  assert.equal((await deliverPublishedResult(options)).record.name, 'delivery_record');
  assert.deepEqual(order, ['streaming', 'receipt', 'succeeded']);
});

test('joint END retains a lost final ACK reply without reissuing receipt or payload', async t => {
  let armed = false, directory;
  const f = await fixture(t, (path, phase) => {
    if (armed && phase === 'after' && path === directory) {
      throw Object.assign(new Error('lost END ACK reply'), {code: 'EIO'});
    }
  }, false);
  directory = join(f.directory, 'deliveries', f.root.attempt.identity.slice(7));
  let writes = 0, finishes = 0, issuances = 0;
  const {options} = deliveryOptions(f, {
    async write(bytes) { writes++; return {confirmedBytes: bytes.byteLength}; },
    async finish() { finishes++; armed = true; return {confirmed: true}; },
  });
  options.control = {...f.control, issueResultDeliveryReceipt(...args) {
    issuances++;
    return f.control.issueResultDeliveryReceipt(...args);
  }};
  let failure;
  await assert.rejects(deliverPublishedResult(options), error => {
    failure = error;
    return error.code === 'ResultDeliveryDurabilityPending';
  });
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state, 'succeeded');
  assert.equal(failure.cleanupHandle.status().pending, true,
    'visible succeeded bytes do not supply the missing original reply');
  const count = writes;
  armed = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(writes, count);
  assert.equal(finishes, 1);
  assert.equal(issuances, 1);
});
