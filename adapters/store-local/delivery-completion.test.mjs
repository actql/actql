import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
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

test('native START retains the first subsequent record directory ACK after a lost reply',async t=>{
  let armed=false, parentAcks=0;
  const f=await fixture(t,(path,phase)=>{
    if(armed && phase==='after' && path===join(f.directory,'deliveries')) {
      parentAcks++;
      if(parentAcks===1) throw Object.assign(new Error('lost record directory ACK'),{code:'EIO'});
    }
  },false);
  const original=f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  const failed=f.control.issueDeliveryRecord(f.root.attempt,f.root.streaming,{
    state:'failed',confirmedByteCount:0,exposure:'exact',possibleUnconfirmedMaxBytes:undefined,
    deliveredSha256:undefined,receipt:undefined,failureCid:cid('b'),observedAt:at,cleanupOwnerCids:[],
  },limits);
  armed=true;
  await assert.rejects(f.store.appendDeliveryRecord(failed.wire),{code:'EIO'});
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state,'streaming');
  await f.store.appendDeliveryRecord(failed.wire);
  assert.equal(parentAcks,2,'the same visible directory is not a durability ACK');
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state,'failed');
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
  // Exercise the still-supported file-backed START/END protocol here. Native
  // metadata completion has its own lost-COMMIT cases below, not file ACKs.
  delete facade.beginDeliveryAttempt;
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

test('delivery without joint operations retains the existing receipt then record path', async t => {
  const f = await fixture(t, undefined, false);
  const {options, facade} = deliveryOptions(f, {
    async write(bytes) { return {confirmedBytes: bytes.byteLength}; },
    async finish() { return {confirmed: true}; },
  });
  delete facade.appendDeliveryCompletion;
  delete facade.beginDeliveryAttempt;
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

test('native START metadata commits without duplicate contract files or directory ACKs', async t => {
  const f = await fixture(t,undefined,false);
  const original = f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  let fileSyncs=0;
  const handle=await open('/dev/null','r'), prototype=Object.getPrototypeOf(handle);
  const sync=prototype.sync;
  await handle.close();
  t.mock.method(prototype,'sync',async function() {
    if((await this.stat()).isFile()) fileSyncs++;
    return Reflect.apply(sync,this,[]);
  });
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  assert.equal(fileSyncs,0,'the native committed metadata is the original, not another file preparation');
  assert.deepEqual(f.syncs,[]);
  for(const name of ['objects','contracts','deliveries','staging']) {
    assert.deepEqual(await readdir(join(f.directory,name)),[]);
  }
  for(const contract of [f.root.attempt,f.root.grant,f.root.streaming]) {
    assert.equal((await f.store.readPublicationContract(contract.identity,contract.name)).wire,contract.wire);
  }
  await f.store.close();
  const reopened=await f.reopen();
  f.syncs.length=0;
  fileSyncs=0;
  const parse=JSON.parse;
  let initialParses=0;
  t.mock.method(JSON,'parse',function(wire,...rest) {
    if(wire===f.root.streaming.wire) initialParses++;
    return Reflect.apply(parse,this,[wire,...rest]);
  });
  assert.equal((await reopened.lookupDeliveryAttempt({indexKey:{namespaceId:'namespace',
    authorityScopeCid:cid('a'),runDefinitionCid:cid('9')},principalId:'principal',
  purpose:'download',resultName:'answer',attemptId:'completion'})).record.state,'streaming');
  assert.equal(initialParses,1,'same selected native birth is parsed once in this operation');
  assert.equal((await reopened.latestDeliveryRecord(f.root.attempt.identity)).state,'streaming');
  assert.equal((await reopened.beginDeliveryAttempt(original,f.root.streaming)).created,false);
  assert.deepEqual(f.syncs,[],'targeted native reads do not recreate obsolete aliases');
  await reopened.appendDeliveryCompletion(f.root.attempt,f.root.receipt,f.root.succeeded);
  assert.equal(fileSyncs,0,'native END metadata retains no duplicate contract files');
  assert.equal((await reopened.latestDeliveryRecord(f.root.attempt.identity)).state,'succeeded');
});

test('native record confirmation retains initial-record compatibility and one real reopened ACK',async t=>{
  const exec=DatabaseSync.prototype.exec;
  let armed=false,commits=0;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if(armed && sql==='COMMIT') commits++;
    return Reflect.apply(exec,this,[sql]);
  });
  const f=await fixture(t,undefined,false);
  const original=f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  armed=true;
  assert.equal((await f.store.confirmDeliveryRecord(f.root.streaming.wire)).state,'streaming');
  assert.equal(commits,0,'the same confirmed claim already owns its real ACK');
  await f.store.close();
  armed=false;
  const reopened=await f.reopen();
  f.syncs.length=0;
  armed=true;
  assert.equal((await reopened.confirmDeliveryRecord(f.root.streaming.wire)).state,'streaming');
  assert.equal(commits,1,'a fresh Store confirms through the same native database');
  await reopened.confirmDeliveryRecord(f.root.streaming.wire);
  assert.equal(commits,1,'unchanged same-Store confirmation does not repeat the ACK');
  assert.deepEqual(f.syncs,[],'native originals do not require absent alias directories');
  await reopened.appendDeliveryCompletion(f.root.attempt,f.root.receipt,f.root.succeeded);
  assert.equal((await reopened.confirmDeliveryRecord(f.root.streaming.wire)).state,'streaming',
    'the retained initial original remains confirmable after its terminal successor');
});

test('native END metadata shares one real completion transaction without shadow contract files',async t=>{
  const exec=DatabaseSync.prototype.exec;
  let armed=false, commits=0;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if(armed && sql==='COMMIT') commits++;
    return Reflect.apply(exec,this,[sql]);
  });
  const f=await fixture(t,undefined,false);
  const original=f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  const nullHandle=await open('/dev/null','r'), prototype=Object.getPrototypeOf(nullHandle);
  const sync=prototype.sync;
  await nullHandle.close();
  let fileSyncs=0;
  t.mock.method(prototype,'sync',async function() {
    if((await this.stat()).isFile()) fileSyncs++;
    return Reflect.apply(sync,this,[]);
  });
  f.syncs.length=0;
  armed=true;
  await f.store.appendDeliveryCompletion(f.root.attempt,f.root.receipt,f.root.succeeded);
  assert.equal(fileSyncs,0,'native immutable completion metadata needs no duplicate contract files');
  assert.deepEqual(f.syncs,[]);
  assert.equal(commits,1,'receipt, record and exact head CAS share the actual durable commit');
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state,'succeeded');
  assert.equal((await f.store.readPublicationContract(f.root.receipt.identity,f.root.receipt.name)).wire,f.root.receipt.wire);
  await f.store.close();
  const reopened=await f.reopen();
  assert.equal((await reopened.latestDeliveryRecord(f.root.attempt.identity)).state,'succeeded');
  assert.equal((await reopened.readPublicationContract(f.root.receipt.identity,f.root.receipt.name)).wire,f.root.receipt.wire);
});

for(const afterCommit of [false,true]) {
  test(`native END metadata retains original completion across ${afterCommit?'after':'before'} COMMIT reply loss`,async t=>{
    const exec=DatabaseSync.prototype.exec;
    let armed=false,lost=false;
    t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
      if(armed && !lost && sql==='COMMIT') {
        lost=true;
        if(afterCommit) Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('lost original completion reply'),{code:'EIO'});
      }
      return Reflect.apply(exec,this,[sql]);
    });
    const f=await fixture(t,undefined,false);
    let writes=0,finishes=0,receipts=0;
    const {options}=deliveryOptions(f,{
      async write(bytes) {writes++;return {confirmedBytes:bytes.byteLength};},
      async finish() {finishes++;armed=true;return {confirmed:true};},
    });
    options.control={...f.control,issueResultDeliveryReceipt(...args) {
      receipts++;return f.control.issueResultDeliveryReceipt(...args);
    }};
    let failure;
    await assert.rejects(deliverPublishedResult(options),error=>{
      failure=error;return error.code==='ResultDeliveryDurabilityPending' && error.cleanupPending===true;
    });
    assert.equal(lost,true);
    assert.equal(finishes,1);assert.equal(receipts,1);
    const beforeWrites=writes;
    const first=failure.cleanupHandle.retry(),second=failure.cleanupHandle.retry();
    assert.equal(first,second);
    assert.equal((await first).pending,false);
    assert.equal(writes,beforeWrites);assert.equal(finishes,1);assert.equal(receipts,1);
    assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state,'succeeded');
    const db=new DatabaseSync(join(f.directory,'delivery-attempts.sqlite3'),{readOnly:true});
    try {
      assert.equal(db.prepare('SELECT count(*) AS n FROM completions').get().n,1);
      assert.equal(db.prepare('SELECT ack_revision FROM completions').get().ack_revision,afterCommit?2:1);
      assert.equal(db.prepare('SELECT uses FROM grant_uses').get().uses,1);
    } finally {db.close();}
    await f.store.close();
    const reopened=await f.reopen();
    const next=deliveryOptions({...f,store:reopened},{async write(){assert.fail('completed original must not resend');},
      async finish(){assert.fail('completed original must not finish again');}}).options;
    assert.equal((await deliverPublishedResult(next)).idempotent,true);
  });
}

for(const selected of ['record','receipt']) {
  test(`native END rejects a foreign persisted ${selected} original on its targeted read`,async t=>{
    const f=await fixture(t,undefined,false);
    const original=f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
      f.root.manifest,f.root.grant,limits);
    await f.store.beginDeliveryAttempt(original,f.root.streaming);
    await f.store.appendDeliveryCompletion(f.root.attempt,f.root.receipt,f.root.succeeded);
    await f.store.close();
    const database=new DatabaseSync(join(f.directory,'delivery-attempts.sqlite3'));
    try {
      if(selected==='record') database.prepare('UPDATE completions SET record_wire=?').run(f.root.streaming.wire);
      else {
        const foreign=f.control.issueResultDeliveryReceipt(f.root.index,f.root.manifest,f.root.grant,
          f.root.attempt,{byteCount:3,sha256:'1'.repeat(64)},limits);
        database.prepare('UPDATE completions SET receipt_wire=?').run(foreign.wire);
      }
    } finally {database.close();}
    const reopened=await f.reopen();
    await assert.rejects(selected==='record'
      ? reopened.latestDeliveryRecord(f.root.attempt.identity)
      : reopened.readPublicationContract(f.root.receipt.identity,f.root.receipt.name),
    {code:'InvalidDeliveryAttemptIndex'});
  });
}

test('delivery START uses native metadata durability before any row exposure', async t => {
  const f = await fixture(t, undefined, false);
  const {store, root, control, directory, syncs, admissions} = f;
  const original = control.captureIssuedDeliveryAttempt?.(root.attempt, root.index, root.manifest, root.grant, limits);
  const nullHandle = await open('/dev/null', 'r');
  const prototype = Object.getPrototypeOf(nullHandle), originalSync = prototype.sync;
  await nullHandle.close();
  let fileSyncs = 0;
  t.mock.method(prototype, 'sync', async function() {
    if ((await this.stat()).isFile()) fileSyncs++;
    return Reflect.apply(originalSync, this, []);
  });
  if (typeof store.beginDeliveryAttempt === 'function' && original !== undefined) {
    const admitted = await store.beginDeliveryAttempt(original, root.streaming);
    assert.equal(admitted.created, true);
    assert.equal(admitted.original, original);
  } else {
    await store.createDeliveryAttempt(root.attempt.wire, root.grant.wire);
    await store.appendDeliveryRecord(root.streaming.wire);
  }
  console.info('ACTQL_DELIVERY_START_WORK', JSON.stringify({fileSyncs,
    objects: syncs.filter(path => path === join(directory, 'objects')).length,
    contracts: syncs.filter(path => path === join(directory, 'contracts')).length,
    staging: syncs.filter(path => path.startsWith(join(directory, 'deliveries', '.staging-'))).length,
    deliveries: syncs.filter(path => path === join(directory, 'deliveries')).length,
    attempt: syncs.filter(path => path === join(directory, 'deliveries', root.attempt.identity.slice(7))).length}));
  assert.equal(syncs.filter(path => path === join(directory, 'objects')).length, 0);
  assert.equal(syncs.filter(path => path === join(directory, 'contracts')).length, 0);
  assert.equal(syncs.filter(path => path === join(directory, 'deliveries')).length, 0);
  assert.equal(syncs.filter(path => path.startsWith(join(directory, 'deliveries', '.staging-'))).length, 0);
  assert.equal(syncs.filter(path => path === join(directory, 'deliveries', root.attempt.identity.slice(7))).length, 0);
  assert.equal(fileSyncs, 0, 'metadata has one native original instead of three duplicate payload files');
  for (const contract of [root.grant, root.attempt, root.streaming]) {
    assert.equal(admissions.filter(identity => identity === contract.identity).length, 0);
  }
  assert.equal((await store.latestDeliveryRecord(root.attempt.identity)).state, 'streaming');
  await store.close();
  const reopened = await f.reopen();
  assert.equal((await reopened.latestDeliveryRecord(root.attempt.identity)).state, 'streaming');
  assert.equal((await reopened.beginDeliveryAttempt(original, root.streaming)).created, false);
  const next = control.issueDeliveryAttempt(root.index, root.manifest, root.grant,
    {resultName: 'answer', format: 'json', attemptId: 'another', requestedAt: at}, limits);
  const nextOriginal = control.captureIssuedDeliveryAttempt(next, root.index, root.manifest, root.grant, limits);
  const nextRecord = control.issueDeliveryRecord(next, undefined, {
    state: 'streaming', confirmedByteCount: 0, exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined, deliveredSha256: undefined,
    receipt: undefined, failureCid: undefined, observedAt: at, cleanupOwnerCids: [],
  }, limits);
  await assert.rejects(reopened.beginDeliveryAttempt(nextOriginal, nextRecord), {code: 'DeliveryGrantUseLimit'});
});

test('delivery START refuses copied or foreign originals and a mismatched initial record before writes', async t => {
  const f = await fixture(t, undefined, false);
  const {store, root, control, syncs} = f;
  const original = control.captureIssuedDeliveryAttempt(root.attempt, root.index, root.manifest, root.grant, limits);
  assert.equal(control.readIssuedDeliveryAttempt(original).attempt, root.attempt);
  assert.equal(control.captureIssuedDeliveryAttempt(root.attempt, root.index, root.manifest, root.grant,
    {...limits, maxNodes: limits.maxNodes + 1}), undefined);
  assert.equal(control.captureIssuedDeliveryAttempt(control.admit(root.attempt.name, root.attempt.wire, limits),
    root.index, root.manifest, root.grant, limits), undefined);
  let reads = 0;
  const foreign = new Proxy(original, {get() {reads++; throw new Error('foreign original read');}});
  const other = originals(control);
  const different = control.issueDeliveryAttempt(other.index, other.manifest, other.grant,
    {resultName: 'answer', format: 'json', attemptId: 'different', requestedAt: at}, limits);
  const wrongRecord = control.issueDeliveryRecord(different, undefined, {
    state: 'streaming', confirmedByteCount: 0, exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined, deliveredSha256: undefined,
    receipt: undefined, failureCid: undefined, observedAt: at, cleanupOwnerCids: [],
  }, limits);
  for (const [candidate, record] of [[{...original}, root.streaming], [foreign, root.streaming],
    [original, {...root.streaming}], [original, root.succeeded], [original, wrongRecord]]) {
    await assert.rejects(async () => store.beginDeliveryAttempt(candidate, record), {code: 'InvalidDeliveryStartEvidence'});
  }
  assert.equal(reads, 0);
  const foreignControl = runtimeCore({...moon}).publicationControl;
  const foreignRoot = originals(foreignControl);
  const foreignOriginal = foreignControl.captureIssuedDeliveryAttempt(foreignRoot.attempt,
    foreignRoot.index, foreignRoot.manifest, foreignRoot.grant, limits);
  await assert.rejects(async () => store.beginDeliveryAttempt(foreignOriginal, foreignRoot.streaming),
    {code: 'InvalidDeliveryStartEvidence'});
  assert.deepEqual(syncs, []);
});

test('native START acquires no redundant semantic writer', async t => {
  const f = await fixture(t, undefined, false);
  const {store, root, control} = f;
  const original = control.captureIssuedDeliveryAttempt(root.attempt, root.index, root.manifest, root.grant, limits);
  const originalOpen = fs.open;
  fs.open = async (...args) => {
    if (typeof args[0] === 'string' && args[0].startsWith(join(f.directory, 'staging', 'object-'))) {
      assert.fail('native metadata must not acquire another semantic payload FD');
    }
    return Reflect.apply(originalOpen, fs, args);
  };
  syncBuiltinESMExports();
  t.after(() => {fs.open = originalOpen; syncBuiltinESMExports();});
  assert.equal((await store.beginDeliveryAttempt(original, root.streaming)).created,true);
  assert.equal((await readdir(join(f.directory, 'staging'))).length, 0);
});

test('actual delivery caller captures START and does not append another initial record', async t => {
  const f = await fixture(t, undefined, false);
  let beginCalls = 0, records = 0, writes = 0;
  const {options, facade} = deliveryOptions(f, {
    async write(bytes) {
      writes++;
      assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state, 'streaming');
      return {confirmedBytes: bytes.byteLength};
    },
    async finish() {return {confirmed: true};},
  });
  const original = facade.beginDeliveryAttempt;
  facade.beginDeliveryAttempt = function(...args) {
    assert.equal(this, facade);
    beginCalls++;
    return Reflect.apply(original, f.store, args);
  };
  facade.appendDeliveryRecord = () => {records++; assert.fail('START already persisted its original state');};
  options.authorize = () => {
    facade.beginDeliveryAttempt = () => assert.fail('late replacement is not the captured START');
    f.control.readIssuedDeliveryAttempt = () => assert.fail('late replacement is not the Store original reader');
    return true;
  };
  assert.equal((await deliverPublishedResult(options)).idempotent, false);
  assert.equal(beginCalls, 1);
  assert.equal(records, 0);
  assert(writes > 0);
});

test('delivery START without issuer capture keeps the old path and malformed optional ports refuse', async t => {
  const f = await fixture(t, undefined, false);
  const {options, facade} = deliveryOptions(f, {
    async write(bytes) {return {confirmedBytes: bytes.byteLength};},
    async finish() {return {confirmed: true};},
  });
  options.control = {...f.control, captureIssuedDeliveryAttempt: undefined};
  facade.beginDeliveryAttempt = () => assert.fail('missing issuer capture must use separate create/append');
  let initialRecords = 0;
  const append = f.store.appendDeliveryRecord;
  facade.appendDeliveryRecord = wire => {
    if (JSON.parse(wire).state === 'streaming') initialRecords++;
    return Reflect.apply(append, f.store, [wire]);
  };
  assert.equal((await deliverPublishedResult(options)).idempotent, false);
  assert.equal(initialRecords, 1);
  facade.beginDeliveryAttempt = false;
  await assert.rejects(deliverPublishedResult(options), {code: 'InvalidResultDeliveryStore'});
});

test('current Deny after joint START still prevents the first protected row exposure', async t => {
  const f = await fixture(t, undefined, false);
  let writes = 0;
  const {options} = deliveryOptions(f, {
    async write(bytes) {writes++; return {confirmedBytes: bytes.byteLength};},
    async finish() {return {confirmed: true};},
  });
  options.authorize = facts => facts.stage !== 'read';
  await assert.rejects(deliverPublishedResult(options), {code: 'ResultDeliveryDenied'});
  assert.equal(writes, 0);
  assert.equal((await f.store.latestDeliveryRecord(f.root.attempt.identity)).state, 'failed');
});

test('native START does not invoke obsolete file representation ACK callbacks', async t => {
  let armed = false;
  const f = await fixture(t, (path, phase) => {
    if (armed) {
      throw Object.assign(new Error('lost START ACK reply'), {code: 'EIO'});
    }
  }, false);
  const original = f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  armed = true;
  assert.equal((await f.store.beginDeliveryAttempt(original,f.root.streaming)).created,true);
  assert.equal((await f.store.beginDeliveryAttempt(original,f.root.streaming)).created,false);
  armed = false;
  await f.store.close();
  const recovered = await f.reopen();
  assert.equal((await recovered.latestDeliveryRecord(f.root.attempt.identity)).state, 'streaming');
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
  const {options,facade} = deliveryOptions(f, {
    async write(bytes) { writes++; return {confirmedBytes: bytes.byteLength}; },
    async finish() { finishes++; armed = true; return {confirmed: true}; },
  });
  delete facade.beginDeliveryAttempt;
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

test('actual joint START uses one native claim COMMIT and restores only its selected original', async t => {
  const originalExec = DatabaseSync.prototype.exec;
  let armed = false, commits = 0;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(originalExec,this,[sql]);
  });
  const f = await fixture(t,undefined,false);
  const original = f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  armed = true;
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  console.info('ACTQL_DELIVERY_START_COMMITS',commits);
  assert.equal(commits,1,'file readiness does not need a second progress-only COMMIT');
  await f.store.close();
  // An unrelated historical original must not be admitted by ordinary open or
  // a lookup of this target. Its malformed wire makes accidental admission fail.
  const database = new DatabaseSync(join(f.directory,'delivery-attempts.sqlite3'));
  try {
    database.prepare('INSERT INTO attempts VALUES(?,?,?,?,?,?,1)').run('unrelated',cid('5'),
      cid('6'),cid('7'),'not an admitted attempt','not an admitted grant');
    database.prepare('INSERT INTO initial_records(attempt_cid,initial_wire) VALUES(?,?)').run(cid('5'),'not an admitted record');
    database.exec('UPDATE coverage SET entries=entries+1 WHERE id=1');
  } finally {database.close();}
  commits = 0;
  const reopened = await f.reopen();
  assert.equal(commits,0,'ordinary open does not recover complete joint-START history');
  const selected = await reopened.lookupDeliveryAttempt({indexKey: {
    namespaceId:'namespace',authorityScopeCid:cid('a'),runDefinitionCid:cid('9')},
    principalId:'principal',purpose:'download',resultName:'answer',attemptId:'completion'});
  assert.equal(selected.record.state,'streaming');
  assert.equal(commits,0,'target recovery has real file ACKs but no progress-only native COMMIT');
  await reopened.appendDeliveryCompletion(f.root.attempt,f.root.receipt,f.root.succeeded);
  assert.equal((await reopened.latestDeliveryRecord(f.root.attempt.identity)).state,'succeeded');
});

test('lost joint claim COMMIT reply preserves quota and initial streaming without sending', async t => {
  const originalExec = DatabaseSync.prototype.exec;
  let armed = false, lost = false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    const value = Reflect.apply(originalExec,this,[sql]);
    if (armed && !lost && sql === 'COMMIT') {
      lost = true;
      throw Object.assign(new Error('lost joint START COMMIT reply'),{code:'EIO'});
    }
    return value;
  });
  const f = await fixture(t,undefined,false);
  let writes = 0;
  const sink = {async write(bytes) {writes++; return {confirmedBytes:bytes.byteLength};},
    async finish() {return {confirmed:true};}};
  armed = true;
  await assert.rejects(deliverPublishedResult(deliveryOptions(f,sink).options),
    {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.equal(writes,0);
  await assert.rejects(deliverPublishedResult(deliveryOptions(f,sink).options),
    {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  await f.store.close();
  const reopened = await f.reopen();
  await assert.rejects(deliverPublishedResult(deliveryOptions({...f,store:reopened},sink).options),
    {code:'ResultDeliveryAttemptUnresolved'});
  assert.equal(writes,0);
  assert.equal((await reopened.latestDeliveryRecord(f.root.attempt.identity)).state,'streaming');
  const next = f.control.issueDeliveryAttempt(f.root.index,f.root.manifest,f.root.grant,
    {resultName:'answer',format:'json',attemptId:'replacement',requestedAt:at},limits);
  await assert.rejects(reopened.createDeliveryAttempt(next.wire,f.root.grant.wire),
    {code:'DeliveryGrantUseLimit'});
});

test('targeted joint START recovery rejects a mismatched retained initial record before file writes', async t => {
  const f = await fixture(t,undefined,false);
  const original = f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  await f.store.close();
  const database = new DatabaseSync(join(f.directory,'delivery-attempts.sqlite3'));
  try {database.prepare('UPDATE initial_records SET initial_wire=? WHERE attempt_cid=?')
    .run(f.root.succeeded.wire,f.root.attempt.identity);} finally {database.close();}
  const reopened = await f.reopen();
  f.syncs.length = 0;
  await assert.rejects(reopened.lookupDeliveryAttempt({indexKey: {
    namespaceId:'namespace',authorityScopeCid:cid('a'),runDefinitionCid:cid('9')},
    principalId:'principal',purpose:'download',resultName:'answer',attemptId:'completion'}),
  {code:'InvalidDeliveryAttemptIndex'});
  assert.deepEqual(f.syncs,[]);
});

test('legacy joint START cold recovery owns one file preparation through reentry', async t => {
  let reopened, armed = false, entries = 0;
  const query = {indexKey: {namespaceId:'namespace',authorityScopeCid:cid('a'),
    runDefinitionCid:cid('9')},principalId:'principal',purpose:'download',
    resultName:'answer',attemptId:'completion'};
  const f = await fixture(t,async (path,phase) => {
    if (armed && phase === 'before' && path === join(f.directory,'contracts')) {
      entries++;
      await assert.rejects(reopened.lookupDeliveryAttempt(query),
        {code:'ResultDeliveryAttemptUnresolved'});
    }
  },false);
  const original = f.control.captureIssuedDeliveryAttempt(f.root.attempt,f.root.index,
    f.root.manifest,f.root.grant,limits);
  await f.store.beginDeliveryAttempt(original,f.root.streaming);
  await f.store.close();
  // Retain the pre-native-representation protocol on this newly owned fixture.
  const database = new DatabaseSync(join(f.directory,'delivery-attempts.sqlite3'));
  try {database.prepare('UPDATE initial_records SET initial_cid=NULL WHERE attempt_cid=?').run(f.root.attempt.identity);}
  finally {database.close();}
  reopened = await f.reopen();
  armed = true;
  assert.equal((await reopened.lookupDeliveryAttempt(query)).record.state,'streaming');
  assert.equal(entries,1);
});
