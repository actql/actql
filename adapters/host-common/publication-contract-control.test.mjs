import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:http';
import test from 'node:test';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {link, mkdir, mkdtemp, open, readdir, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';
import {DatabaseSync} from 'node:sqlite';
import {runtimeCore} from './runtime-core.mjs';
import {checked} from './runtime-result.mjs';
import {publishEffectFreeRun, publishEffectfulRun} from
  './run-publication.mjs';
import {retainIssuedEffectSetReceipt} from
  './effect-receipt-custody.mjs';
import {publishCompletedEffectFreeRun} from
  './completed-run-publication.mjs';
import {prepareCompletedEffectFreeRunPublication} from
  './run-publication-preflight.mjs';
import {deliverPublishedResult} from './result-delivery.mjs';
import {
  deliverAuthorizedResult,
  installResultAccessAuthority,
  installNodeResultAccessService,
} from '../host-node/result-access.mjs';
import {
  inspectAuthorizedRunState,
  installRunStateAuthority,
  installRunStateService,
} from './run-state-access.mjs';
import {
  installManifestAccessAuthority,
  installManifestAccessService,
  readAuthorizedManifest,
} from './manifest-access.mjs';
import {
  extendResultRetention,
  installMetadataRetentionAuthority,
  installMetadataRetentionService,
  installResultRetentionAuthority,
  installResultRetentionExtensionAuthority,
  installResultRetentionExtensionService,
  installResultRetentionService,
  retireExpiredResult,
  retireExpiredPublicationMetadata,
} from './result-retention.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';
import {createClientHttpHandler} from '../host-node/client-http.mjs';
import {fundedClientPreparation} from '../host-node/funded-client-preparation.fixture.mjs';
import {openClientRequestJournal} from '../host-node/client-request-journal.mjs';
import {installNodeClientRunStateObservation, observeClientRunState} from
  '../host-node/client-run-state.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});

test('publication persistence consumes its same-owner immutable contracts without another admission', async t => {
  let admissions = 0;
  const observed = Object.freeze({...moon, strategyPublicationAdmit(...args) {
    admissions++;
    return Reflect.apply(moon.strategyPublicationAdmit, moon, args);
  }});
  const control = runtimeCore(observed).publicationControl;
  const first = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
  const second = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: cid('3'),
    observation_set_cid: cid('4'),
  }), limits);
  const directory = await mkdtemp(join(tmpdir(), 'actql-original-publication-'));
  let store;
  t.after(async () => {
    if (store !== undefined) await store.close();
    await rm(directory, {recursive: true});
  });
  store = await openLocalPublicationStore({directory, storeAuthorityCid: cid('5'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth}, control);
  const source = await readFile(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'persistContracts');
  const persist = Function('return ('+source.slice(declaration.start, declaration.end)+')')();
  await persist(store, [first, second, first]);
  assert.equal(admissions, 0, 'the original Common issuance already admitted these unchanged bodies');
  assert.equal(store.status().objectCount, 2);
  assert.equal((await store.readPublicationContract(first.identity, first.name)).wire, first.wire);
  assert.equal((await store.readPublicationContract(second.identity, second.name)).wire, second.wire);
});

test('original publication metadata has one native durable commit without duplicate body files', async t => {
  const control = runtimeCore(moon).publicationControl;
  const contracts = [1, 3].map(digit => control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: cid(String(digit)),
    observation_set_cid: cid(String(digit + 1)),
  }), limits));
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-publication-'));
  const configuration = {directory, storeAuthorityCid: cid('5'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64};
  let store;
  t.after(async () => {
    if (store !== undefined) await store.close();
    await rm(directory, {recursive: true});
  });
  const originalExec = DatabaseSync.prototype.exec, originalOpen = fs.open;
  let commits = 0, armed = false;
  const fileSyncs = [];
  DatabaseSync.prototype.exec = function(sql, ...args) {
    const result = Reflect.apply(originalExec, this, [sql, ...args]);
    if (armed && sql.trim() === 'COMMIT') commits++;
    return result;
  };
  fs.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (armed && typeof path === 'string' && path.startsWith(directory + '/')) {
      const originalSync = handle.sync;
      handle.sync = async function(...parameters) {
        const result = await Reflect.apply(originalSync, this, parameters);
        fileSyncs.push(path);
        return result;
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    // The native Owner captures exec at open. Install observation before that
    // capture, then count only this publication, not initialization COMMITs.
    store = await openLocalPublicationStore(configuration, control);
    armed = true;
    await store.putOriginalPublicationContracts(contracts);
  } finally {
    DatabaseSync.prototype.exec = originalExec;
    fs.open = originalOpen;
    syncBuiltinESMExports();
  }
  assert.equal(commits, 1, 'the same Store database owns the complete durable metadata group');
  assert.deepEqual(fileSyncs, [], 'metadata bodies have no duplicate per-body file representation');
  assert.equal(store.status().objectCount, 2);
  assert.equal(store.status().storedBytes, contracts.reduce((sum, contract) =>
    sum + Buffer.byteLength(contract.wire, 'utf8'), 0));
  assert.deepEqual(await readdir(join(directory, 'contracts')), []);
  assert.deepEqual(await readdir(join(directory, 'objects')), []);
  await store.close();
  store = await openLocalPublicationStore(configuration, control);
  for (const contract of contracts) {
    assert.equal((await store.readPublicationContract(contract.identity, contract.name)).wire, contract.wire);
  }
  assert.equal(store.status().objectCount, 2);
});

for (const afterCommit of [false, true]) {
  test(`native publication metadata retains capacity across ${afterCommit ? 'after' : 'before'} COMMIT reply loss`, async t => {
    const control = runtimeCore(moon).publicationControl;
    const contract = control.seal('run_invocation', JSON.stringify({
      version:'actql-run-invocation/0.1',invocation_template_cid:cid('1'),observation_set_cid:cid('2'),
    }), limits);
    const directory = await mkdtemp(join(tmpdir(),'actql-publication-native-unknown-'));
    let store, armed = false, lost = false, commits = 0, confirmations = 0, originalDatabase;
    const exec = DatabaseSync.prototype.exec;
    t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
      if (armed && sql === 'COMMIT') {
        commits++;
        if (!lost) {
          lost = true;
          originalDatabase = this;
          if (afterCommit) Reflect.apply(exec,this,[sql]);
        }
        throw Object.assign(new Error('lost original publication COMMIT reply'),{code:'EIO'});
      }
      if (lost && sql === 'COMMIT') {
        assert.equal(this, originalDatabase);
        confirmations++;
      }
      return Reflect.apply(exec,this,[sql]);
    });
    t.after(async () => { if (store !== undefined) await store.close(); await rm(directory,{recursive:true}); });
    store = await openLocalPublicationStore({directory,storeAuthorityCid:cid('5'),
      capacityBytes:1048576,maxObjectBytes:65536,maxObjects:2,maxContractNodes:4096,maxContractDepth:64},control);
    armed = true;
    let originalFailure;
    await assert.rejects(store.putOriginalPublicationContracts([contract]), error => {
      originalFailure = error;
      return error.code === 'PublicationMetadataCommitOutcomeUnknown' && error.outcome === 'unknown';
    });
    assert.equal(store.status().objectCount,0,'an unobserved COMMIT is not reported as durable success');
    assert.equal(store.status().reservedObjects,1);
    assert.equal(store.status().reservedBytes,Buffer.byteLength(contract.wire,'utf8'));
    await assert.rejects(store.close(),{code:'PublicationStoreCleanupPending'});
    await assert.rejects(store.putOriginalPublicationContracts([contract]),{code:'PublicationStoreCleanupPending'});
    await assert.rejects(store.readPublicationContract(contract.identity,contract.name),
      {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
    assert.equal(originalFailure.cleanupHandle.status().pending,true);
    armed = false;
    assert.equal((await originalFailure.cleanupHandle.retry()).pending,false);
    assert.equal(commits,2,'initial write and close retry both retain the injected unavailable ACK');
    assert.equal(confirmations,1,'only the same metadata duty makes a real confirmation write');
    assert.equal(store.status().reservedObjects,0);
    assert.equal(store.status().objectCount,1);
    assert.equal(store.status().storedBytes,Buffer.byteLength(contract.wire,'utf8'));
    assert.equal((await store.readPublicationContract(contract.identity,contract.name)).wire,contract.wire);
    await store.putOriginalPublicationContracts([contract]);
    await store.putPublicationContract(contract.name,contract.wire);
    assert.equal(confirmations,1,'known immutable metadata is not committed or duplicated again');
    assert.deepEqual(await readdir(join(directory,'contracts')),[]);
    assert.deepEqual(await readdir(join(directory,'objects')),[]);
    assert.equal(store.status().objectCount,1);
  });
}

test('native publication capacity and legacy files share the original Store limits', async t => {
  const control = runtimeCore(moon).publicationControl;
  const contracts = [1,3,5].map(digit => control.seal('run_invocation',JSON.stringify({
    version:'actql-run-invocation/0.1',invocation_template_cid:cid(String(digit)),
    observation_set_cid:cid(String(digit+1)),
  }),limits));
  const directory = await mkdtemp(join(tmpdir(),'actql-publication-native-capacity-'));
  let store;
  t.after(async () => { if (store !== undefined) await store.close(); await rm(directory,{recursive:true}); });
  const configuration = {directory,storeAuthorityCid:cid('7'),capacityBytes:1048576,
    maxObjectBytes:65536,maxObjects:2,maxContractNodes:4096,maxContractDepth:64};
  store = await openLocalPublicationStore(configuration,control);
  await store.putPublicationContract(contracts[0].name,contracts[0].wire);
  const fileBytes = store.status().storedBytes;
  await assert.rejects(store.putOriginalPublicationContracts(contracts.slice(1)),{code:'PublicationStoreObjectLimit'});
  assert.equal(store.status().objectCount,1);
  assert.equal(store.status().reservedObjects,0,'a refused whole group releases only unpublished reservations');
  assert.equal(store.status().storedBytes,fileBytes);
  await store.putOriginalPublicationContracts(contracts.slice(0,2));
  assert.equal(store.status().objectCount,2,'the old file is not duplicated or charged a second time');
  assert.equal((await readdir(join(directory,'contracts'))).length,1);
  assert.equal((await readdir(join(directory,'objects'))).length,1);
  await assert.rejects(store.putBytes(Buffer.from('payload')),{code:'PublicationStoreObjectLimit'});
  await store.close();
  store = await openLocalPublicationStore(configuration,control);
  assert.equal(store.status().objectCount,2);
  assert.equal(store.status().storedBytes,fileBytes+Buffer.byteLength(contracts[1].wire,'utf8'));
  for (const contract of contracts.slice(0,2)) {
    assert.equal((await store.readPublicationContract(contract.identity,contract.name)).wire,contract.wire);
  }
});

test('native publication bodies retain byte capacity and cold actual-wire admission', async t => {
  let admissions = 0;
  const control = runtimeCore(Object.freeze({...moon,strategyPublicationAdmit(...args) {
    admissions++;
    return Reflect.apply(moon.strategyPublicationAdmit,moon,args);
  }})).publicationControl;
  const contracts = [1,3].map(digit => control.seal('run_invocation',JSON.stringify({
    version:'actql-run-invocation/0.1',invocation_template_cid:cid(String(digit)),
    observation_set_cid:cid(String(digit+1)),
  }),limits));
  const byteCount = Buffer.byteLength(contracts[0].wire,'utf8');
  assert.equal(Buffer.byteLength(contracts[1].wire,'utf8'),byteCount);
  const directory = await mkdtemp(join(tmpdir(),'actql-publication-native-bytes-'));
  let store;
  t.after(async () => { if (store !== undefined) await store.close(); await rm(directory,{recursive:true}); });
  const configuration = {directory,storeAuthorityCid:cid('5'),capacityBytes:2*byteCount-1,
    maxObjectBytes:byteCount,maxObjects:100,maxContractNodes:4096,maxContractDepth:64};
  store = await openLocalPublicationStore(configuration,control);
  await assert.rejects(store.putOriginalPublicationContracts(contracts),{code:'PublicationStoreCapacity'});
  assert.equal(store.status().objectCount,0);
  assert.equal(store.status().reservedObjects,0);
  await store.putOriginalPublicationContracts([contracts[0]]);
  assert.equal(admissions,3,'these tighter consumer wire bounds keep the normal admission fallback');
  await assert.rejects(store.putBytes(Buffer.alloc(byteCount)),{code:'PublicationStoreCapacity'});
  await store.close();
  store = await openLocalPublicationStore(configuration,control);
  assert.equal((await store.readPublicationContract(contracts[0].identity,contracts[0].name)).wire,contracts[0].wire);
  assert.equal(admissions,4,'a cold selected row admits the actual acquired wire once');
  await store.close();
  // Dedicated new fixture corruption, not mutation/replay of any original Run.
  const database = new DatabaseSync(join(directory,'delivery-attempts.sqlite3'));
  try { database.prepare('UPDATE publication_contracts SET wire=? WHERE semantic_cid=?')
    .run(contracts[1].wire,contracts[0].identity); }
  finally { database.close(); }
  store = await openLocalPublicationStore(configuration,control);
  await assert.rejects(store.readPublicationContract(contracts[0].identity,contracts[0].name),
    {code:'InvalidDeliveryAttemptIndex'});
  assert.equal(admissions,5,'a mismatched selected original does not inherit another body\'s identity');
});

test('native publication metadata is not duplicated by a mixed legacy group', async t => {
  const control = runtimeCore(moon).publicationControl;
  const invocation = control.seal('run_invocation',JSON.stringify({version:'actql-run-invocation/0.1',
    invocation_template_cid:cid('1'),observation_set_cid:cid('2')}),limits);
  const record = control.seal('publication_record',JSON.stringify({version:'actql-publication-record/0.1',
    publication_attempt_cid:cid('3'),sequence:0,state:'preparing',cleanup_owner_cids:[],
    observed_at:'2026-09-18T00:00:00.000Z'}),limits);
  const directory = await mkdtemp(join(tmpdir(),'actql-publication-native-mixed-'));
  let store;
  t.after(async () => { if (store !== undefined) await store.close(); await rm(directory,{recursive:true}); });
  store = await openLocalPublicationStore({directory,storeAuthorityCid:cid('5'),capacityBytes:1048576,
    maxObjectBytes:65536,maxObjects:3,maxContractNodes:4096,maxContractDepth:64},control);
  await store.putOriginalPublicationContracts([invocation]);
  // Construct a real legacy file original; an all-native group stays native.
  await store.putSemantic(record.wire, record.identity);
  await store.putPublicationContracts([invocation,record].map(({name,wire}) => ({name,wire})));
  assert.equal(store.status().objectCount,2,'a mixed file/native group retains each original representation once');
  const stored = await store.putOriginalPublicationContracts([invocation,record]);
  assert.deepEqual(stored.map(value=>value.semanticCid),[invocation.identity,record.identity]);
  assert.equal(store.status().objectCount,2);
  assert.equal((await readdir(join(directory,'contracts'))).length,1);
  assert.equal((await readdir(join(directory,'objects'))).length,1);
  for (const contract of [invocation,record]) {
    assert.equal((await store.readPublicationContract(contract.identity,contract.name)).wire,contract.wire);
  }
});

test('publication originals preserve owner identity and captured issuance bounds', () => {
  const control = runtimeCore(moon).publicationControl;
  const selected = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
  const original = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), selected);
  selected.maxWireBytes = selected.maxNodes = selected.maxDepth = 1;
  assert.equal(control.admitOriginal(original, limits), original);
  assert.equal(control.admitOriginal(original, {...limits, maxNodes: original.wire.length}), original);
  assert.equal(control.admitOriginal(original, {...limits, maxNodes: 1}), undefined);
  assert.equal(control.admitOriginal(original, {...limits, maxDepth: 1}), undefined);
  assert.equal(control.admitOriginal(original, {...limits,
    maxWireBytes: Buffer.byteLength(original.wire, 'utf8') - 1}), undefined);
  assert.equal(control.admitOriginal(Object.freeze({...original}), limits), undefined);
  const foreign = runtimeCore(Object.freeze({...moon})).publicationControl;
  assert.equal(foreign.admitOriginal(original, limits), undefined);
  const admitted = control.admit(original.name, original.wire, limits);
  assert.equal(control.admitOriginal(admitted, limits), admitted);
  const {run, invoked} = admittedRun(control, cid('6'));
  assert.equal(control.admitOriginal(run, limits), run, 'actual Run issuer retains its checked bounds');
  assert.equal(control.admitOriginal(invoked, limits), invoked, 'actual Invocation issuer retains its checked bounds');
});

test('publication original persistence falls back for copies foreign owners and tighter limits', async t => {
  let admissions = 0;
  const observed = Object.freeze({...moon, strategyPublicationAdmit(...args) {
    admissions++;
    return Reflect.apply(moon.strategyPublicationAdmit, moon, args);
  }});
  const control = runtimeCore(observed).publicationControl;
  const body = JSON.stringify({version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'), observation_set_cid: cid('2')});
  const owned = control.seal('run_invocation', body, limits);
  const foreign = runtimeCore(moon).publicationControl.seal('run_invocation', body, limits);
  const stores = [], directories = [];
  t.after(async () => {
    for (const store of stores) await store.close();
    for (const directory of directories) await rm(directory, {recursive: true});
  });
  const makeStore = async extra => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-original-fallback-'));
    directories.push(directory);
    const store = await openLocalPublicationStore({directory, storeAuthorityCid: cid('5'),
      capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
      maxContractNodes: 4096, maxContractDepth: 64, ...extra}, control);
    stores.push(store);return store;
  };
  const store = await makeStore({});
  await store.putOriginalPublicationContracts([Object.freeze({...owned})]);
  assert.equal(admissions, 1);
  await store.putOriginalPublicationContracts([foreign]);
  assert.equal(admissions, 2);
  const bounded = await makeStore({maxContractNodes: 1});
  await assert.rejects(bounded.putOriginalPublicationContracts([owned]),
    error => error.code === 'InvalidPublicationContract');
  assert.equal(admissions, 3, 'the actual Core checks a tighter unsupported node bound');
  assert.equal(bounded.status().objectCount, 0);
  assert.deepEqual(await readdir(join(directories[1], 'staging')), []);
  const changed = Object.freeze({...owned, wire: owned.wire.replace(cid('2'), cid('3'))});
  await assert.rejects(store.putOriginalPublicationContracts([changed]),
    error => error.code === 'InvalidPublicationContract');
  assert.equal(admissions, 4);
  const freshRead = await store.readPublicationContract(owned.identity, owned.name);
  assert.equal(freshRead.wire, owned.wire);
  assert.equal(admissions, 5, 'a cold selected read still admits its actual disk bytes');
});

test('publication persister retains legacy receivers and waits for the selected group outcome', async () => {
  const source = await readFile(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'persistContracts');
  assert.ok(declaration);
  // Execute this exact private adapter function, not a second publication
  // implementation. The real Common/Store integration is checked below.
  const persist = Function('return ('+source.slice(declaration.start, declaration.end)+')')();
  const first = Object.freeze({identity: cid('1'), name: 'first', wire: 'first-body'});
  const second = Object.freeze({identity: cid('2'), name: 'second', wire: 'second-body'});
  const calls = [];
  const legacy = {async putPublicationContract(name, wire) {
    assert.equal(this, legacy);calls.push([name, wire]);
  }};
  await persist(legacy, [first, second, first]);
  assert.deepEqual(calls, [['first', 'first-body'], ['second', 'second-body']]);
  const gate = Promise.withResolvers();let batches = 0, settled = false;
  const grouped = {putPublicationContract() {throw new Error('NoIndividualFallback');},
    async putPublicationContracts(contracts) {
      assert.equal(this, grouped);batches++;
      assert.equal(Object.isFrozen(contracts), true);
      assert(contracts.every(Object.isFrozen));
      assert.deepEqual(contracts, [{name: 'first', wire: 'first-body'}, {name: 'second', wire: 'second-body'}]);
      await gate.promise;
    }};
  const pending = persist(grouped, [first, second, first]).then(() => {settled = true;});
  await Promise.resolve();assert.equal(settled, false);assert.equal(batches, 1);
  gate.resolve();await pending;
  const original = new Error('OriginalGroupFailure');
  grouped.putPublicationContracts = async () => {throw original;};
  await assert.rejects(persist(grouped, [first]), error => error === original);
  await persist({putPublicationContracts() {throw new Error('EmptyGroupDoesNoWork');}}, []);
  const owned = {putPublicationContracts() {throw new Error('NoRawFallback');},
    async putOriginalPublicationContracts(contracts) {
      assert.equal(this, owned);
      assert.equal(Object.isFrozen(contracts), true);
      assert.equal(contracts[0], first);
      assert.equal(contracts[1], second);
      assert.equal(contracts.length, 2);
      throw original;
    }};
  await assert.rejects(persist(owned, [first, second, first]), error => error === original);
});

test('initial publication group consumes actual Common originals and keeps the post-group cancellation boundary', async t => {
  const control = runtimeCore(moon).publicationControl;
  const attempt = control.seal('publication_attempt', JSON.stringify({
    version:'actql-publication-attempt/0.1', publication_request_cid:cid('1'),
    run_definition_cid:cid('2'), attempt_id:'actual-initial-group', fence_cid:cid('3'),
    started_at:'2026-09-18T00:00:01.000Z',
  }), limits);
  const directory = await mkdtemp(join(tmpdir(), 'actql-common-initial-group-'));
  let store;
  t.after(async () => { if (store !== undefined) await store.close(); await rm(directory, {recursive:true}); });
  store = await openLocalPublicationStore({directory, storeAuthorityCid:cid('5'),
    capacityBytes:1024*1024, maxObjectBytes:65536, maxObjects:100,
    maxContractNodes:4096, maxContractDepth:64}, control);
  await store.createAttempt(attempt.wire);
  const source = await readFile(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {sourceType:'module', ecmaVersion:'latest'});
  const helper = ast.body.find(node=>node.type==='FunctionDeclaration' && node.id.name==='appendInitialStates');
  const initial = ast.body.find(node=>node.type==='FunctionDeclaration' && node.id.name==='initialPublicationStates');
  const member = ast.body.find(node=>node.type==='VariableDeclaration' && node.declarations.some(item=>item.id.name==='member'));
  const append = Function('fail', source.slice(member.start,member.end)+'\n'+source.slice(initial.start,initial.end)+'\n'+source.slice(helper.start,helper.end)+'\nreturn appendInitialStates;')(
    code=>{throw Object.assign(new Error(code),{code});});
  let issued = 0;
  const observed = {...control, issuePublicationRecord(...args) {
    issued++; return Reflect.apply(control.issuePublicationRecord, control, args);
  }};
  const committing = await append(store, observed, attempt, undefined, ()=>'2026-09-18T00:00:02.000Z', limits);
  assert.equal(issued,2);
  assert.equal(JSON.parse(committing.wire).state,'committing');
  assert.equal(control.publicationAttemptAction(committing,false,false),'check_active');
  assert.equal(control.publicationCancellationAction(committing),'cancel_committing');
  const cancelled = control.issuePublicationRecord(attempt, committing, {
    state:'cancelled',observedAt:'2026-09-18T00:00:03.000Z',cleanupOwnerCids:[],uncommittedConfirmed:true,
  },limits);
  await store.appendRecord(cancelled.wire,{uncommittedConfirmed:true});
  assert.equal((await store.latestRecord(attempt.identity)).state,'cancelled');
});

test('complete publication start consumes actual Common originals and preserves later cancellation', async t => {
  const control = runtimeCore(moon).publicationControl;
  const exec = DatabaseSync.prototype.exec;
  let commits = 0, armed = false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if(armed && sql==='COMMIT')commits++;
    return Reflect.apply(exec,this,[sql]);
  });
  const attempt = control.seal('publication_attempt', JSON.stringify({
    version:'actql-publication-attempt/0.1', publication_request_cid:cid('1'),
    run_definition_cid:cid('2'), attempt_id:'actual-complete-start', fence_cid:cid('3'),
    started_at:'2026-09-18T00:00:01.000Z',
  }), limits);
  const directory = await mkdtemp(join(tmpdir(),'actql-common-publication-start-'));
  let store;
  t.after(async () => {if (store !== undefined) await store.close(); await rm(directory,{recursive:true});});
  store = await openLocalPublicationStore({directory,storeAuthorityCid:cid('5'),
    capacityBytes:1024*1024,maxObjectBytes:65536,maxObjects:100,
    maxContractNodes:4096,maxContractDepth:64},control);
  const source = await readFile(new URL('./run-publication.mjs',import.meta.url),'utf8');
  const ast = parse(source,{sourceType:'module',ecmaVersion:'latest'});
  const declarations = ['initialPublicationStates','persistContracts','requireActiveAttempt','appendState']
    .map(name => ast.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name===name));
  const member = ast.body.find(node=>node.type==='VariableDeclaration'&&node.declarations.some(item=>item.id.name==='member'));
  const helpers = Function('fail',source.slice(member.start,member.end)+'\n'+
    declarations.map(node=>source.slice(node.start,node.end)).join('\n')+
    '\nreturn {initialPublicationStates,persistContracts,requireActiveAttempt};')(
    code=>{throw Object.assign(new Error(code),{code});});
  const cancellation = new AbortController();
  const now = ()=>'2026-09-18T00:00:02.000Z';
  const initial = helpers.initialPublicationStates(control,attempt,cancellation.signal,now,limits);
  armed = true;
  assert.equal(await helpers.persistContracts(store,[],attempt,initial.records),true);
  assert.equal(commits,1);
  assert.equal((await store.latestRecordContract(attempt.identity)).wire,initial.next.wire);
  assert.equal(control.publicationAttemptAction(initial.next,false,false),'check_active');
  cancellation.abort();
  await assert.rejects(helpers.requireActiveAttempt(cancellation.signal,store,control,attempt,now,limits),{name:'AbortError'});
  assert.equal(commits,2,'later cancellation remains a separate real durable mutation');
  assert.equal((await store.latestRecord(attempt.identity)).state,'cancelled');
});

test('generated publication owner crosses the JS bridge as named actions', () => {
  const core = runtimeCore(moon);
  const control = core.publicationControl;
  assert.equal(control.publicationSetupAction(false, false, false, false,
    false, false, false), 'check_existing_commit');
  assert.equal(control.publicationAttemptAction(undefined, false, false),
    'append_preparing');
  assert.equal(control.publicationCancellationAction(undefined), 'rethrow');
  assert.equal(control.committedPublicationFinalizationAction(undefined),
    'invalid');
  assert.equal(control.publicationCommitFailureAction(false, false, false,
    false), 'reconcile_commit');
  assert.equal(control.publicationUnknownRetryAction(false, false, false,
    false), 'reconcile');
  assert.equal(control.publicationPreparedReleaseAction(-1, 0, false, false,
    false), 'finished');
  assert.equal(control.publicationCleanupOwnerAction(0, 0, false, false,
    false, false), 'finished');
  assert.equal(core.outputExportControl.payloadFailureAction(false, false,
    false, false, false, false, false, false), 'finished');
});

const publicationOutputLimits = Object.freeze({
  maxResultFields: 10,
  maxResultMappingWork: 100,
  maxResultOrderWork: 100,
  maxResultWorkspaceEntries: 10,
  maxRows: 100,
  maxValueNodes: 1000,
  maxValueTextBytes: 4096,
  maxValueDepth: 10,
  maxValueWork: 8192,
  maxWireBytes: 4096,
  maxWireNodes: 1000,
  maxWireDepth: 10,
  maxColumns: 10,
  maxOrderWork: 1000,
  maxLogicalWireBytes: 8192,
  maxLogicalWireNodes: 1003,
  maxLogicalWireDepth: 12,
  maxSchemaFields: 10,
  maxSchemaBytes: 4096,
  maxSchemaNodes: 100,
  maxSchemaDepth: 10,
  maxBatchBytes: 1024,
});
const canonical = value => Array.isArray(value)
  ? value.map(canonical)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort()
      .map(key => [key, canonical(value[key])]))
    : value;
const canonicalCid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(canonical(value))).digest('hex')}`;

function invocation(control) {
  return control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cid('1'),
    observation_set_cid: cid('2'),
  }), limits);
}

function admittedRun(control, programDefinitionCid) {
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: programDefinitionCid,
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: programDefinitionCid,
    program_semantics_cid: cid('a'),
    aoa_contract_cid: cid('b'),
    aoa_logical_cid: cid('c'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const run = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('a'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z',
  }, limits);
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: cid('a'),
    }),
    limits,
  );
  return Object.freeze({
    admission,
    run,
    observation,
    invoked: control.issueRunInvocation(template, observation, limits),
  });
}

test('Checkpoint lifetime projects only the same original admitted Run without renewal', () => {
  const control = runtimeCore(moon).publicationControl;
  const {run, invoked} = admittedRun(control, cid('6'));
  const lifetime = control.runDefinitionLifetime(run, run.identity);
  assert.deepEqual(lifetime, {createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z'});
  assert.equal(Object.isFrozen(lifetime), true);
  assert.throws(() => control.runDefinitionLifetime(run, cid('f')));
  assert.throws(() => control.runDefinitionLifetime(invoked, invoked.identity));
  assert.throws(() => control.runDefinitionLifetime({...run}, run.identity),
    /Foreign publication contract/u);
  assert.deepEqual(control.runDefinitionLifetime(run, run.identity), lifetime);
});

function deliveryRoot(control) {
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: cid('1'),
    invocation_cid: cid('2'),
    logical_result_cid: cid('3'),
    result_schema_cid: cid('4'),
    ordering_evidence_cid: cid('5'),
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('6'),
    effective_retention_policy_cid: cid('7'),
    provenance_evidence_cids: [cid('8')],
  }), limits);
  const manifest = control.seal('result_manifest', JSON.stringify({
    version: 'actql-result-manifest/0.1',
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    results: {answer: JSON.parse(artifact.wire)},
  }), limits);
  const index = control.seal('public_index_entry', JSON.stringify({
    version: 'actql-public-index-entry/0.1',
    namespace_id: 'namespace',
    authority_scope_cid: cid('a'),
    run_definition_cid: cid('9'),
    invocation_cid: cid('2'),
    result_manifest_cid: manifest.identity,
    run_receipt_cid: cid('b'),
    captured_run_cid: cid('c'),
    durable_result_binding_cids: [cid('d')],
    publication_request_cid: cid('e'),
    publication_attempt_cid: cid('f'),
    committed_at: '2026-09-18T00:00:00.000Z',
  }), limits);
  return {artifact, manifest, index};
}

async function logicalDeliveryStore(t, control, durability) {
  const scratch = new URL('../../_build/local-delivery-tests/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(new URL('store-', scratch).pathname);
  const configuration = {directory, storeAuthorityCid: cid('a'),
    capacityBytes: 1024 * 1024, maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100, maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth};
  const stores = [];
  const reopen = async () => {
    const store = await openLocalPublicationStore(configuration, control, durability);
    stores.push(store);
    return store;
  };
  t.after(async () => {
    for (const store of stores) await store.close();
    await rm(directory, {recursive: true, force: true});
  });
  return {directory, configuration, reopen, store: await reopen()};
}

function logicalDeliveryRequest(control, maxUses = 1) {
  const root = deliveryRoot(control);
  const policy = {resultNames: ['answer'], formats: ['json', 'jsonl'],
    principalId: 'principal', purpose: 'download', dataCeilingCid: cid('1'),
    maxBytes: 4096, maxUses, expiresAt: '2026-09-19T00:00:00.000Z',
    authorizationContextCid: cid('2'), egressAdmissionCid: cid('3')};
  const grant = control.issueResultReadGrant(root.index, root.manifest, policy, limits);
  const attempt = (seconds, options = {}, selectedGrant = grant) =>
    control.issueDeliveryAttempt(root.index, root.manifest, selectedGrant, {
      resultName: 'answer', format: 'json', attemptId: 'logical-attempt',
      requestedAt: `2026-09-18T01:00:0${seconds}.000Z`, ...options,
    }, limits);
  return {...root, policy, grant, attempt};
}

test('Local delivery retains its logical attempt and successful record across restart',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control, 2);
    const {store, reopen, directory} = await logicalDeliveryStore(t, control);
    const original = request.attempt(0);
    await store.createDeliveryAttempt(original.wire, request.grant.wire);
    const fields = {state: 'streaming', confirmedByteCount: 0, exposure: 'exact',
      observedAt: '2026-09-18T01:00:00.000Z', cleanupOwnerCids: []};
    const streaming = control.issueDeliveryRecord(original, undefined, fields, limits);
    await store.appendDeliveryRecord(streaming.wire);
    const receipt = control.issueResultDeliveryReceipt(request.index, request.manifest,
      request.grant, original, {byteCount: 2, sha256: '0'.repeat(64)}, limits);
    await store.putPublicationContract(receipt.name, receipt.wire);
    const succeeded = control.issueDeliveryRecord(original, streaming, {...fields,
      state: 'succeeded', confirmedByteCount: 2, deliveredSha256: '0'.repeat(64),
      receipt, observedAt: '2026-09-18T01:00:01.000Z'}, limits);
    await store.appendDeliveryRecord(succeeded.wire);
    const path = join(directory, 'deliveries', original.identity.slice(7), '1.json');
    const bytes = await readFile(path);
    const usage = store.status();
    await store.close();
    const resumed = await reopen();
    for (const seconds of [1, 2, 3]) {
      const selected = await resumed.createDeliveryAttempt(request.attempt(seconds).wire,
        request.grant.wire);
      assert.equal(selected.created, false);
      assert.deepEqual(selected.attempt, JSON.parse(original.wire));
      assert.equal((await resumed.latestDeliveryRecordContract(original.identity)).wire,
        succeeded.wire);
      assert.deepEqual(await readFile(path), bytes);
      assert.deepEqual(resumed.status(), usage);
    }
    // The second grant use is still available for a genuinely different request.
    assert.equal((await resumed.createDeliveryAttempt(request.attempt(4,
      {attemptId: 'independent'}).wire, request.grant.wire)).created, true);
    await assert.rejects(resumed.createDeliveryAttempt(request.attempt(5,
      {attemptId: 'third'}).wire, request.grant.wire), {code: 'DeliveryGrantUseLimit'});
    assert.equal((await readdir(join(directory, 'deliveries'))).length, 2);
  });

test('Local delivery selects one durable owner for concurrent different-time requests',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control);
    const {store, reopen, directory} = await logicalDeliveryStore(t, control);
    const outcomes = await Promise.all([0, 1].map(seconds =>
      store.createDeliveryAttempt(request.attempt(seconds).wire, request.grant.wire)));
    assert.equal(outcomes.filter(value => value.created).length, 1);
    assert.deepEqual(outcomes[0].attempt, outcomes[1].attempt);
    assert.deepEqual(outcomes[0].attempt, JSON.parse(request.attempt(0).wire));
    assert.equal(await store.latestDeliveryRecordContract(
      outcomes[0].attempt.delivery_attempt_cid), undefined);
    await store.close();
    const resumed = await reopen();
    const retry = await resumed.createDeliveryAttempt(request.attempt(2).wire,
      request.grant.wire);
    assert.equal(retry.created, false);
    assert.deepEqual(retry.attempt, outcomes[0].attempt);
    assert.equal((await readdir(join(directory, 'deliveries'))).length, 1);
  });

test('Local delivery preserves contract-sized attempt IDs independently of lookup limits',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control);
    const {store} = await logicalDeliveryStore(t, control);
    const attemptId = 'x'.repeat(300);
    const original = request.attempt(0, {attemptId});
    assert.equal((await store.createDeliveryAttempt(original.wire,
      request.grant.wire)).created, true);
    const replay = await store.createDeliveryAttempt(request.attempt(1,
      {attemptId}).wire, request.grant.wire);
    assert.equal(replay.created, false);
    assert.deepEqual(replay.attempt, JSON.parse(original.wire));
    await assert.rejects(store.lookupDeliveryAttempt({
      indexKey: {namespaceId: 'namespace', authorityScopeCid: cid('a'),
        runDefinitionCid: cid('9')}, principalId: 'principal', purpose: 'download',
      resultName: 'answer', attemptId,
    }), {code: 'InvalidDeliveryAttemptLookup'});
  });

test('Local delivery rejects changed immutable binding without consuming another use',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control, 2);
    const {store, directory} = await logicalDeliveryStore(t, control);
    const original = request.attempt(0);
    await store.createDeliveryAttempt(original.wire, request.grant.wire);
    const alternativeGrant = control.issueResultReadGrant(request.index, request.manifest,
      {...request.policy, maxBytes: 2048}, limits);
    for (const [attempt, grant] of [
      [request.attempt(1, {format: 'jsonl'}), request.grant],
      [request.attempt(1, {}, alternativeGrant), alternativeGrant],
    ]) {
      await assert.rejects(store.createDeliveryAttempt(attempt.wire, grant.wire),
        {code: 'DeliveryAttemptConflict'});
    }
    assert.equal((await readdir(join(directory, 'deliveries'))).length, 1);
    assert.equal((await store.createDeliveryAttempt(request.attempt(2,
      {attemptId: 'independent'}).wire, request.grant.wire)).created, true);
  });

test('Local delivery retains a visible selection after final sync failure without a record',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control);
    let deliveries, failSync = false, failures = 0;
    const durability = {async syncDirectory(path) {
      if (path === deliveries && failSync) {
        failSync = false;
        failures++;
        throw Object.assign(new Error('delivery selection sync failed'), {code: 'EIO'});
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    }};
    const {store, reopen, directory} = await logicalDeliveryStore(t, control, durability);
    deliveries = join(directory, 'deliveries');
    const original = request.attempt(0);
    failSync = true;
    await assert.rejects(store.createDeliveryAttempt(original.wire, request.grant.wire),
      {code: 'EIO'});
    assert.equal(await store.latestDeliveryRecordContract(original.identity), undefined);
    // This lifetime retains failed original admission instead of issuing another ACK.
    await assert.rejects(store.createDeliveryAttempt(request.attempt(1).wire,
      request.grant.wire), {code: 'ResultDeliveryAttemptUnresolved'});
    assert.equal(failures, 1);
    await store.close();
    const resumed = await reopen();
    const selected = await resumed.createDeliveryAttempt(request.attempt(2).wire,
      request.grant.wire);
    assert.equal(selected.created, false);
    assert.deepEqual(selected.attempt, JSON.parse(original.wire));
    assert.equal(await resumed.latestDeliveryRecordContract(original.identity), undefined);
    assert.deepEqual(await readdir(deliveries), [original.identity.slice(7)]);
    await assert.rejects(resumed.createDeliveryAttempt(request.attempt(3,
      {attemptId: 'independent'}).wire, request.grant.wire), {code: 'DeliveryGrantUseLimit'});
  });

test('Local delivery logical keys keep scope Run principal purpose and Result independent',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control);
    const {store} = await logicalDeliveryStore(t, control);
    const change = (contract, fields) => {
      const body = {...JSON.parse(contract.wire), ...fields};
      delete body[contract.identityField];
      return control.seal(contract.name, JSON.stringify(body), limits);
    };
    const original = request.attempt(0);
    await store.createDeliveryAttempt(original.wire, request.grant.wire);
    for (const field of ['namespace', 'scope', 'run', 'principal', 'purpose', 'result']) {
      const resultName = field === 'result' ? 'other' : 'answer';
      const runCid = field === 'run' ? cid('e') : cid('9');
      const manifest = change(request.manifest, {run_definition_cid: runCid,
        results: {[resultName]: JSON.parse(request.artifact.wire)}});
      const index = change(request.index, {run_definition_cid: runCid,
        result_manifest_cid: manifest.identity,
        namespace_id: field === 'namespace' ? 'other' : 'namespace',
        authority_scope_cid: field === 'scope' ? cid('e') : cid('a')});
      const grant = control.issueResultReadGrant(index, manifest, {...request.policy,
        resultNames: [resultName], principalId: field === 'principal' ? 'other' : 'principal',
        purpose: field === 'purpose' ? 'other' : 'download'}, limits);
      const issue = seconds => control.issueDeliveryAttempt(index, manifest, grant,
        {resultName, format: 'json', attemptId: 'logical-attempt',
          requestedAt: `2026-09-18T01:00:0${seconds}.000Z`}, limits);
      const first = issue(0);
      assert.equal((await store.createDeliveryAttempt(first.wire, grant.wire)).created,
        true, field);
      const repeat = await store.createDeliveryAttempt(issue(1).wire, grant.wire);
      assert.equal(repeat.created, false, field);
      assert.deepEqual(repeat.attempt, JSON.parse(first.wire), field);
    }
  });

test('Local delivery selects the same unfinished attempt after abrupt process exit',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control);
    const {store, directory, configuration, reopen} = await logicalDeliveryStore(t, control);
    await store.close();
    const original = request.attempt(0);
    const child = spawnSync(process.execPath, ['--input-type=module', '--eval', `
      import {open} from 'node:fs/promises';
      import * as moon from ${JSON.stringify(new URL(
    '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    import.meta.url).href)};
      import {runtimeCore} from ${JSON.stringify(new URL('./runtime-core.mjs', import.meta.url).href)};
      import {openLocalPublicationStore} from ${JSON.stringify(new URL(
    '../store-local/publication-store.mjs', import.meta.url).href)};
      let armed = false;
      const store = await openLocalPublicationStore(${JSON.stringify(configuration)},
        runtimeCore(moon).publicationControl, {async syncDirectory(path) {
          if (armed && path === ${JSON.stringify(join(directory, 'deliveries'))}) {
            process.exit(19); // selection visible, final durability/ACK not returned
          }
          const handle = await open(path, 'r');
          try { await handle.sync(); } finally { await handle.close(); }
        }});
      armed = true;
      await store.createDeliveryAttempt(${JSON.stringify(original.wire)},
        ${JSON.stringify(request.grant.wire)});
      process.exit(20);
    `], {encoding: 'utf8', timeout: 30000});
    assert.equal(child.status, 19, child.stderr);
    const resumed = await reopen();
    const selected = await resumed.createDeliveryAttempt(request.attempt(1).wire,
      request.grant.wire);
    assert.equal(selected.created, false);
    assert.deepEqual(selected.attempt, JSON.parse(original.wire));
    assert.equal(await resumed.latestDeliveryRecordContract(original.identity), undefined);
    assert.deepEqual(await readdir(join(directory, 'deliveries')), [original.identity.slice(7)]);
    await assert.rejects(resumed.createDeliveryAttempt(request.attempt(2,
      {attemptId: 'independent'}).wire, request.grant.wire), {code: 'DeliveryGrantUseLimit'});
  });

test('Local delivery refuses preexisting ambiguous logical attempts without rewriting them',
  async t => {
    const control = runtimeCore(moon).publicationControl;
    const request = logicalDeliveryRequest(control, 2);
    const {store, directory, reopen} = await logicalDeliveryStore(t, control);
    // Reproduce the previous writer's two valid CID-keyed entries. Do not invent
    // a migration rule that guesses which record/exposure owns this request.
    await store.putPublicationContract('result_read_grant', request.grant.wire);
    const paths = [];
    for (const seconds of [0, 1]) {
      const attempt = request.attempt(seconds);
      await store.putPublicationContract('delivery_attempt', attempt.wire);
      const target = join(directory, 'deliveries', attempt.identity.slice(7));
      await mkdir(target);
      const path = join(target, 'attempt.json');
      await link(join(directory, 'contracts', `${attempt.identity.slice(7)}.json`), path);
      paths.push([path, await readFile(path)]);
    }
    await store.close();
    // Dedicated pre-index layout, not mutation behind a live complete index.
    await rm(join(directory, 'delivery-attempts.sqlite3'));
    await rm(join(directory, 'delivery-attempts-index.json'));
    await assert.rejects(reopen(), {code: 'AmbiguousDeliveryAttemptLookup'});
    assert.equal((await readdir(join(directory, 'deliveries'))).length, 2);
    for (const [path, bytes] of paths) assert.deepEqual(await readFile(path), bytes);
  });

test('installed publication control uses the portable contract owner', () => {
  const control = runtimeCore(moon).publicationControl;
  const sealed = invocation(control);
  assert.deepEqual(sealed, {
    name: 'run_invocation',
    identityField: 'invocation_cid',
    identity:
      'sha256:49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18',
    wire: '{"invocation_cid":"sha256:' +
      '49e5afcdeaf57b77db072d5db04ce83fcaf25b6eee8f5d33ae9606fb504ded18' +
      '","invocation_template_cid":"' + cid('1') +
      '","observation_set_cid":"' + cid('2') +
      '","version":"actql-run-invocation/0.1"}',
  });
  assert.deepEqual(
    control.admit('run_invocation', sealed.wire, limits),
    sealed,
  );
  assert.throws(
    () => control.recordAllowsCommit(Object.freeze({...sealed})),
    /Foreign publication contract/u,
  );
});

test('portable delivery owner binds grants attempts and receipts', () => {
  const control = runtimeCore(moon).publicationControl;
  const {artifact, manifest, index} = deliveryRoot(control);
  assert.equal(
    control.resultSerializationContractCid('json', limits),
    // Fixed profile preimage from portability/corpus/typed-json-literals.json.
    canonicalCid({
      json_value_wire_contract_cid:
        'sha256:8ce92036074141bdc4b39436fe2460c7d1460810af1c345b45c6fc102b36791b',
      version: 'actql-json/0.1',
    }),
  );
  const grant = control.issueResultReadGrant(index, manifest, {
    resultNames: ['answer'],
    formats: ['json', 'jsonl', 'csv'],
    principalId: 'principal',
    purpose: 'download',
    dataCeilingCid: cid('1'),
    maxBytes: 4096,
    maxUses: 2,
    expiresAt: '2026-09-19T00:00:00.000Z',
    authorizationContextCid: cid('2'),
    egressAdmissionCid: cid('3'),
  }, limits);
  assert.deepEqual(JSON.parse(grant.wire).results, [{
    result_artifact_cid: artifact.identity,
    result_name: 'answer',
  }]);
  const attempt = control.issueDeliveryAttempt(
    index,
    manifest,
    grant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'attempt-1',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  const streaming = control.issueDeliveryRecord(attempt, undefined, {
    state: 'streaming',
    confirmedByteCount: 0,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: undefined,
    receipt: undefined,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:00.000Z',
    cleanupOwnerCids: [],
  }, limits);
  const receipt = control.issueResultDeliveryReceipt(
    index,
    manifest,
    grant,
    attempt,
    {byteCount: 2, sha256: '0'.repeat(64)},
    limits,
  );
  const succeeded = control.issueDeliveryRecord(attempt, streaming, {
    state: 'succeeded',
    confirmedByteCount: 2,
    exposure: 'exact',
    possibleUnconfirmedMaxBytes: undefined,
    deliveredSha256: '0'.repeat(64),
    receipt,
    failureCid: undefined,
    observedAt: '2026-09-18T01:00:01.000Z',
    cleanupOwnerCids: [],
  }, limits);
  assert.equal(
    JSON.parse(succeeded.wire).result_delivery_receipt_cid,
    receipt.identity,
  );
});

test('portable delivery serializer owns the three canonical formats', () => {
  const control = runtimeCore(moon).publicationControl;
  const schema = JSON.stringify({
    amount: {nullable: false, precision: 4, scale: 2, type: 'decimal'},
    enabled: {nullable: false, type: 'boolean'},
    meta: {
      additional_properties: false,
      fields: {k: {nullable: false, type: 'string'}},
      nullable: false,
      type: 'object',
    },
    missing: {nullable: true, type: 'number'},
    name: {nullable: false, type: 'string'},
    score: {nullable: false, type: 'number'},
  });
  const fields = ['name', 'score', 'amount', 'enabled', 'missing', 'meta'];
  const row = JSON.stringify({
    amount: '2.30',
    enabled: false,
    meta: {k: 'é'},
    missing: null,
    name: 'x,"y',
    score: 1.5,
  });
  const expected =
    '{"name":"x,\\"y","score":1.5,"amount":"2.30",' +
    '"enabled":false,"missing":null,"meta":{"k":"é"}}';

  const serialize = format => {
    const serializer = control.prepareResultDeliverySerializer(
      format,
      schema,
      fields,
      limits,
    );
    return control.beginResultDelivery(serializer) +
      control.nextResultDeliveryRow(serializer, row) +
      control.finishResultDelivery(serializer);
  };

  assert.equal(serialize('json'), `[${expected}]`);
  assert.equal(serialize('jsonl'), `${expected}\n`);
  assert.equal(
    serialize('csv'),
    '"name","score","amount","enabled","missing","meta"\n' +
      '"x,""y",1.5,2.30,false,\\N,"{""k"":""é""}"\n',
  );
});

test('portable evidence owner issues Invocation after exact capture', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: cid('7'),
    }),
    limits,
  );
  assert.deepEqual(
    control.admitRunEvidence(template.name, template.wire, limits),
    template,
  );
  const issued = control.issueRunInvocation(template, observation, limits);
  assert.deepEqual(JSON.parse(issued.wire), {
    invocation_cid: issued.identity,
    invocation_template_cid: template.identity,
    observation_set_cid: observation.identity,
    version: 'actql-run-invocation/0.1',
  });
  const foreign = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      ...JSON.parse(template.wire),
      bound_invocation_template_cid: undefined,
      program_definition_cid: cid('8'),
    }),
    limits,
  );
  assert.throws(
    () => control.issueRunInvocation(foreign, observation, limits),
    {code: 'MoonBitHostFailure'},
  );
});

test('portable admission issues Run Definition from exact authority', () => {
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('1'),
      parameter_values_cid: cid('2'),
      invocation_bindings_cid: cid('3'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('6'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('1'),
    program_semantics_cid: cid('a'),
    aoa_contract_cid: cid('b'),
    aoa_logical_cid: cid('c'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('8'),
      host_policy_cid: cid('9'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const definition = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('a'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:00:00.000Z',
  }, limits);
  assert.deepEqual(JSON.parse(definition.wire), {
    authorization_context_cid: cid('8'),
    compiled_plan_cid: compiledPlan.identity,
    created_at: '2026-09-18T00:00:00.000Z',
    input_artifact_set_cid: cid('a'),
    invocation_template_cid: template.identity,
    run_definition_cid: definition.identity,
    run_id: 'run',
    scope_id: 'scope',
    valid_until: '2026-09-18T02:00:00.000Z',
    version: 'actql-run-definition/0.1',
  });
  assert.throws(
    () => control.issueRunDefinition(
      Object.freeze({kind: 'run-publication-admission'}),
      {
        scopeId: 'scope',
        runId: 'run',
        inputArtifactSetCid: cid('a'),
        createdAt: '2026-09-18T00:00:00.000Z',
        validUntil: '2026-09-18T02:00:00.000Z',
      },
      limits,
    ),
    /Foreign Run publication admission/u,
  );
});

test('publication preflight rejects immutable or physical incompatibility',
  () => {
    const control = runtimeCore(moon).publicationControl;
    const {admission, run, invoked, observation} = admittedRun(control, cid('6'));
    const normalizationJournal = control.sealRunEvidence('normalization_journal',
      JSON.stringify({version: 'actql-normalization-journal/0.1',
        rule_catalog_cid: cid('c'), entries: []}), limits);
    const authoringContext = control.sealRunEvidence('authoring_context',
      JSON.stringify({version: 'actql-authoring-context/0.1',
        program_definition_cid: cid('6'), annotations: []}), limits);
    const definition = control.seal('result_definition', JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: cid('6'),
      result_name: 'answer',
    }), limits);
    const retention = control.seal(
      'result_retention_policy',
      JSON.stringify({
        version: 'actql-result-retention-policy/0.1',
        retention_contract_cid: cid('b'),
        effective_data_policy_cid: cid('a'),
        available_until: '2026-09-18T01:00:00.000Z',
        delete_by: '2026-09-18T02:00:00.000Z',
        extension_ceiling_at: '2026-09-18T03:00:00.000Z',
        metadata_retention_policy_cid: cid('c'),
        metadata_delete_by: '2026-09-18T04:00:00.000Z',
        clock_contract_cid: cid('d'),
      }),
      limits,
    );
    const plan = Object.freeze({
      admission,
      runDefinition: run,
      invocation: invoked,
      observation,
      normalizationJournal,
      authoringContext,
      results: Object.freeze([
        Object.freeze({
          retention,
          evidenceContext: Object.freeze({
            computationContractCid: cid('1'),
            inputRelationCids: Object.freeze([]),
            scopeCid: cid('2'),
            effectiveDataPolicyCid: cid('a'),
            authorityScopeCid: cid('7'),
          }),
        }),
      ]),
      receiptEvidence: Object.freeze({
        bindings: Object.freeze([]),
        sourceEvidence: Object.freeze([]),
        modelEvidence: Object.freeze([]),
        barrierAttemptReceiptCids: Object.freeze([]),
      }),
      captureEvidence: Object.freeze({
        pendingSourceStateAdvances: Object.freeze([]),
        modelEvidence: Object.freeze([]),
      }),
      request: Object.freeze({
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('7'),
        publicationPolicyCid: cid('8'),
        publicationTargetCid: cid('9'),
        requestedAt: '2026-09-18T00:00:00.000Z',
      }),
      attempt: Object.freeze({
        attemptId: 'attempt-a',
        fenceCid: cid('0'),
        externalIdempotencyKey: undefined,
        startedAt: '2026-09-18T00:00:01.000Z',
      }),
      outputLimits: publicationOutputLimits,
      contractLimits: limits,
      now: () => '2026-09-18T00:00:02.000Z',
    });
    const publicationInventory = Object.freeze({
      programDefinitionCid: cid('6'),
      occurrences: Object.freeze([
        Object.freeze({definitionContract: definition}),
      ]),
    });
    let requirement;
    const admitted = prepareCompletedEffectFreeRunPublication({
      store: {
        publicationCapacitySupports(value) {
          requirement = value;
          return true;
        },
      },
      control,
      publicationInventory,
      plan,
    });
    assert.equal(admitted.request.name, 'publication_request');
    assert.equal(admitted.attempt.name, 'publication_attempt');
    // Common owns the per-kind schema bounds. Independently sum the Host's
    // six known originals, six Result objects and nine global obligations;
    // this attempt reserves the foreign terminal because no retained winner
    // preflight token funds it.
    const resultBounds = control.resultPublicationContractByteBounds(
      [], publicationOutputLimits.maxSchemaBytes, limits);
    const frontier = control.ordinaryPublicationFrontierByteBounds(
      admitted.request, 1, limits);
    const volumes = [run, invoked, definition, retention,
      admitted.request, admitted.attempt].map(contract =>
        Buffer.byteLength(contract.wire, 'utf8'));
    volumes.push(publicationOutputLimits.maxWireBytes,
      publicationOutputLimits.maxSchemaBytes, ...resultBounds,
      frontier.manifest,
      control.ordinaryPublicationReceiptByteBound(plan, admitted.request, limits),
      limits.maxWireBytes, frontier.index, frontier.current.preparing,
      frontier.current.committing, frontier.current.publicationUnknown,
      frontier.current.terminal, frontier.possibleForeignWinnerTerminal);
    assert.equal(volumes.length, 21);
    const expectedBytes = volumes.reduce((sum, size) => sum + size, 0);
    assert.deepEqual(requirement, {
      requiredBytes: expectedBytes,
      objectCount: 21,
      maxObjectBytes: Math.max(...volumes),
    });
    for (const available of [expectedBytes, expectedBytes - 1]) {
      const prepare = () => prepareCompletedEffectFreeRunPublication({
        store: {publicationCapacitySupports: value => value.requiredBytes <= available},
        control, publicationInventory, plan,
      });
      if (available === expectedBytes) assert.doesNotThrow(prepare);
      else assert.throws(prepare, {code: 'RunPublicationCapacityUnsupported'});
    }
    for (const name of ['observation', 'normalizationJournal']) {
      assert.throws(() => prepareCompletedEffectFreeRunPublication({
        store: {publicationCapacitySupports: () => true},
        control, publicationInventory,
        plan: Object.freeze({...plan, [name]: Object.freeze({...plan[name]})}),
      }), error => error.code === 'InvalidRunPublicationPreflight' &&
        error.cause?.message === 'Foreign Run evidence');
    }
    assert(Object.isFrozen(admitted.plan));
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => false},
      control,
      publicationInventory,
      plan,
    }), {code: 'RunPublicationCapacityUnsupported'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory: Object.freeze({occurrences: Object.freeze([])}),
      plan,
    }), {code: 'InvalidRunPublicationPreflight'});
    const missingBatchLimit = Object.freeze(Object.fromEntries(
      Object.entries(publicationOutputLimits)
        .filter(([name]) => name !== 'maxBatchBytes'),
    ));
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({...plan, outputLimits: missingBatchLimit}),
    }), {code: 'InvalidRunPublicationPreflight'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({
        ...plan,
        outputLimits: Object.freeze({
          ...publicationOutputLimits,
          maxSchemaBytes: -1,
        }),
      }),
    }), {code: 'InvalidRunPublicationPreflight'});
    assert.throws(() => prepareCompletedEffectFreeRunPublication({
      store: {publicationCapacitySupports: () => true},
      control,
      publicationInventory,
      plan: Object.freeze({
        ...plan,
        outputLimits: Object.freeze({
          ...publicationOutputLimits,
          unboundedBytes: 1,
        }),
      }),
    }), {code: 'InvalidRunPublicationPreflight'});
  });

test('portable control validates the exact Run Result publication chain', () => {
  const control = runtimeCore(moon).publicationControl;
  const run = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1',
    scope_id: 'scope',
    run_id: 'run',
    compiled_plan_cid: cid('3'),
    invocation_template_cid: cid('1'),
    authorization_context_cid: cid('4'),
    input_artifact_set_cid: cid('5'),
    created_at: '2026-09-18T00:00:00.000Z',
    valid_until: '2026-09-18T01:00:00.000Z',
  }), limits);
  const invoked = invocation(control);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-18T04:00:00.000Z',
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  assert.equal(control.runChainValid(
    run, invoked, [definition], [artifact], manifest, limits,
  ), true);
  assert.equal(control.runChainValid(
    run, invoked, [definition], [], manifest, limits,
  ), false);
});

test('portable control validates Receipt and Captured Run references',
  async t => {
  const retainedStores = [];
  const retainedJournals = [];
  const retainedDirectories = [];
  t.after(async () => {
    for (const journal of retainedJournals) journal.close();
    for (const store of retainedStores.toReversed()) {
      assert.equal(await store.close(), true);
    }
    for (const directory of retainedDirectories) {
      await rm(directory, {recursive: true, force: true});
    }
  });
  const control = runtimeCore(moon).publicationControl;
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: cid('6'),
      parameter_values_cid: cid('1'),
      invocation_bindings_cid: cid('2'),
      check_environment_cid: cid('4'),
      grammar_manifest_cid: cid('5'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: cid('7'),
      source_evidence: 'unbound',
    }),
    limits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-0.1',
    aoa_ir_version: 'aoa-ir-0.1',
    executable_plan_cid: cid('0'),
    program_definition_cid: cid('6'),
    program_semantics_cid: cid('e'),
    aoa_contract_cid: cid('d'),
    aoa_logical_cid: cid('f'),
  }), limits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    limits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('4'),
      host_policy_cid: cid('5'),
      decision: 'allowed',
    }),
    limits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const run = control.issueRunDefinition(admission, {
    scopeId: 'scope',
    runId: 'run',
    inputArtifactSetCid: cid('5'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T01:00:00.000Z',
  }, limits);
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: cid('a'),
    }),
    limits,
  );
  const invoked = control.issueRunInvocation(template, observation, limits);
  const definition = control.seal('result_definition', JSON.stringify({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('6'),
    result_name: 'answer',
  }), limits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'),
    effective_data_policy_cid: cid('a'),
    available_until: '2026-09-18T01:00:00.000Z',
    delete_by: '2026-09-18T02:00:00.000Z',
    extension_ceiling_at: '2026-09-18T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-18T04:00:00.000Z',
    clock_contract_cid: cid('d'),
  }), limits);
  const resultSchema = Object.freeze({
    value: Object.freeze({nullable: false, type: 'integer'}),
  });
  const resultSchemaWire = JSON.stringify(canonical(resultSchema));
  const resultSchemaCid = canonicalCid(resultSchema);
  const derivation = control.seal('derivation_evidence', JSON.stringify({
    version: 'actql-acquisition-derivation-evidence/0.1',
    producer_contract_cid: definition.identity,
    computation_contract_cid: cid('3'),
    input_relation_cids: [],
    logical_value_cid: canonicalCid({
      sort: 'relation',
      value: [{value: 7}],
    }),
    relation_schema_cid: resultSchemaCid,
    scope_cid: cid('5'),
    effective_data_policy_cid: cid('a'),
    ordering: {kind: 'occurrence', terms: []},
    issuer_id: 'common-host',
    authority_scope_cid: cid('d'),
  }), limits);
  const ordering = control.seal('ordering_evidence', JSON.stringify({
    version: 'actql-acquisition-ordering/0.1',
    producer_contract_cid: definition.identity,
    kind: 'occurrence',
    terms: [],
    witness_evidence: [{kind: 'derivation', cid: derivation.identity}],
  }), limits);
  const resultRows = [{value: 7}];
  const logicalResultCid = canonicalCid({sort: 'relation', value: resultRows});
  const artifact = control.seal('result_artifact', JSON.stringify({
    version: 'actql-result-artifact/0.1',
    result_definition_cid: definition.identity,
    invocation_cid: invoked.identity,
    logical_result_cid: logicalResultCid,
    result_schema_cid: resultSchemaCid,
    ordering_evidence_cid: ordering.identity,
    actual_row_count: 1,
    actual_completeness: 'complete',
    effective_data_policy_cid: cid('a'),
    effective_retention_policy_cid: retention.identity,
    provenance_evidence_cids: [derivation.identity],
  }), limits);
  const manifest = control.issueResultManifest(
    run, invoked, [definition], [artifact], limits,
  );
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal',
    JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('c'),
      entries: [],
    }),
    limits,
  );
  const receipt = control.issueEffectFreeRunReceipt({
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
  }, {
    normalizationJournal,
    bindings: [],
    sourceEvidence: [],
    modelEvidence: [],
    barrierAttemptReceiptCids: [],
  }, limits);
  const authoringContext = control.sealRunEvidence(
    'authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: cid('6'),
      annotations: [],
    }),
    limits,
  );
  const snapshot = control.admitCapturedResultSnapshot(
    definition,
    artifact,
    JSON.stringify(resultRows),
    ['value'],
    limits,
  );
  const captured = await control.issueEffectFreeCapturedRun({
    runDefinition: run,
    invocation: invoked,
    definitions: [definition],
    artifacts: [artifact],
    manifest,
    receipt,
  }, {
    snapshots: [snapshot],
    pendingSourceStateAdvances: [],
    authoringContext,
    modelEvidence: [],
  }, limits);
  const receiptBody = JSON.parse(receipt.wire);
  const {result_definition_cid: ignoredDefinition,
    ordering_evidence_cid: ignoredOrdering,
    result_artifact_cid: ignoredIdentity, ...artifactBody} =
    JSON.parse(artifact.wire);
  const sourceArtifact = control.seal('effect_source_artifact',
    JSON.stringify({...artifactBody,
      version: 'actql-effect-source-artifact/0.1',
      source_result: 'rows', source_binding_cid: cid('9'),
      store_authority_cid: cid('a')}), limits);
  const previewBody = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: receiptBody.program_semantics_cid,
    program_definition_cid: receiptBody.program_definition_cid,
    invocation_cid: invoked.identity, run_identity_cid: run.identity,
    compiled_plan_cid: receiptBody.compiled_plan_cid,
    check_environment_cid: receiptBody.check_environment_cid,
    authoring_context: JSON.parse(authoringContext.wire),
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [],
    effects: [{
      effect_id: 'WriteOne', effect_kind: 'update', target: 'Object',
      mapping: 'mapping:fixture', resolved_mapping_contract_cid: cid('9'),
      effect_identity_cid: cid('9'), effect_plan_logical_cid: cid('9'),
      source_result: 'rows', result_artifact_cid: sourceArtifact.identity,
      preview_strength: 'full_diff', source_binding_cid: cid('9'),
      capability_evidence_cid: cid('9'), authority_scope_cid: cid('9'),
      write_footprint: {kind: 'exact_targets',
        resource_identity_scheme_cid: cid('9'),
        provider_namespace: 'provider', provider_boundary_cid: cid('9'),
        resource_kind: 'Object', provider_object_identity_cids: [cid('1')]},
      count: 0, max_items: 1, required_permissions: ['write'],
      approval: 'none', on_item_failure: 'halt', changes: [], row_order: [],
      effect_member_preview_cid: cid('1'), executed: false,
    }],
    executed: false, effect_preview_cid: cid('2'),
  };
  const previewWire = () => JSON.stringify(canonical(previewBody));
  previewBody.effects[0].effect_member_preview_cid =
    checked(moon.strategyEffectPreviewIdentities(previewWire(),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth))[1];
  previewBody.effect_preview_cid =
    checked(moon.strategyEffectPreviewIdentities(previewWire(),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth))[0];
  assert.equal(previewBody.authoring_context.authoring_context_cid,
    authoringContext.identity);
  assert.equal(previewBody.authoring_context.program_definition_cid,
    previewBody.program_definition_cid);
  assert.equal(previewBody.run_identity_cid, run.identity);
  assert.deepEqual(checked(moon.strategyEffectPreviewIdentities(previewWire(),
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth)),
  [previewBody.effect_preview_cid,
    previewBody.effects[0].effect_member_preview_cid]);
  const preview = control.admitEffectComputationPreview(
    previewWire(), run, authoringContext, limits);
  const privateBinding = control.effectPrivateEvidenceBinding(preview, cid('a'));
  assert.deepEqual(Object.keys(privateBinding),
    ['name', 'semanticCid', 'holdingCid', 'wire']);
  assert.equal(privateBinding.name, 'effect_preview');
  assert.equal(privateBinding.semanticCid, previewBody.effect_preview_cid);
  assert.equal(privateBinding.wire, previewWire());
  assert.match(privateBinding.holdingCid, /^sha256:[0-9a-f]{64}$/u);
  assert.notEqual(control.effectPrivateEvidenceBinding(
    preview, cid('b')).holdingCid, privateBinding.holdingCid);
  assert.throws(() => control.effectPrivateEvidenceBinding(
    Object.freeze({kind: 'effect-computation-preview'}), cid('a')),
  /Foreign Effect computation Preview/u);
  assert.throws(() => control.effectPrivateEvidenceBinding(
    preview, 'foreign'), {code: 'MoonBitHostFailure'});
  const computationChain = {
    runDefinition: run, invocation: invoked, definitions: [definition],
    artifacts: [artifact], manifest, receipt,
  };
  const computationEvidence = {snapshots: [snapshot],
    effectSources: [control.admitCapturedEffectSourceArtifact(
      preview, 0, invoked, sourceArtifact, cid('a'))],
    pendingSourceStateAdvances: [], authoringContext, modelEvidence: []};
  await assert.rejects(() => control.issueEffectfulCapturedRun(
    computationChain, computationEvidence, preview,
    [{name: 'WriteOne', wire: '{}'}], limits),
  {name: 'TypeError', message: 'Invalid Effectful Captured Run request'});
  const localDefinitionBody = {
    version: 'actql-local-result-definition/0.1',
    unit_definition_cid: cid('1'), result_name: 'rows',
  };
  const localDefinition = canonical({
    ...localDefinitionBody,
    self_cid: canonicalCid(localDefinitionBody),
  });
  const localInvocationBody = {
    version: 'actql-local-computation-semantics/0.1',
    unit_definition_cid: cid('1'), used_values_cid: cid('2'),
    local_contracts_cid: cid('3'), observation_cids: [],
    policy_cid: cid('a'),
  };
  const localInvocation = canonical({
    ...localInvocationBody,
    self_cid: canonicalCid(localInvocationBody),
  });
  const localDerivationBody = {...JSON.parse(derivation.wire),
    producer_contract_cid: localDefinition.self_cid};
  delete localDerivationBody[derivation.identityField];
  const localDerivation = control.seal('derivation_evidence',
    JSON.stringify(localDerivationBody), limits);
  const localOrderingBody = {...JSON.parse(ordering.wire),
    producer_contract_cid: localDefinition.self_cid,
    witness_evidence: [{kind: 'derivation',
      cid: localDerivation.identity}]};
  delete localOrderingBody[ordering.identityField];
  const localOrdering = control.seal('ordering_evidence',
    JSON.stringify(localOrderingBody), limits);
  const localArtifact = control.seal('result_artifact', JSON.stringify({
    ...artifactBody,
    version: 'actql-result-artifact/0.1',
    result_definition_cid: localDefinition.self_cid,
    invocation_cid: localInvocation.self_cid,
    ordering_evidence_cid: localOrdering.identity,
    provenance_evidence_cids: [localDerivation.identity],
  }), limits);
  const localManifestBody = {
    version: 'actql-local-result-manifest/0.1',
    unit_definition_cid: cid('1'),
    local_invocation_cid: localInvocation.self_cid,
    results: {rows: localArtifact.identity},
  };
  const localManifest = canonical({
    ...localManifestBody,
    self_cid: canonicalCid(localManifestBody),
  });
  const rawContract = value => checked(moon.strategyPublicationAdmit(
    value.name, value.wire,
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const rawPreview = checked(moon.strategyAdmitEffectComputationPreview(
    previewWire(), run.identity, authoringContext.identity,
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const rawSource = checked(moon.strategyAdmitCapturedEffectSourceArtifact(
    rawPreview, 0, rawContract(invoked), rawContract(sourceArtifact), cid('a')));
  const rawLocal = checked(moon.strategyAdmitCapturedLocalEffectSource(
    rawSource, JSON.stringify(localDefinition),
    JSON.stringify(localInvocation), JSON.stringify(localManifest),
    rawContract(localArtifact), rawContract(localDerivation),
    rawContract(localOrdering), rawContract(retention),
    limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const issueDirect = plans => {
    const rawCaptured = checked(moon.strategyIssueEffectfulCapturedRun(
      rawContract(run), rawContract(invoked), [rawContract(definition)],
      [rawContract(artifact)], rawContract(manifest), rawContract(receipt),
      [checked(moon.strategyAdmitCapturedResultSnapshot(
        rawContract(definition), rawContract(artifact),
        JSON.stringify(resultRows), ['value'],
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth))],
      [rawSource], [rawLocal], [],
      checked(moon.strategyRunEvidenceAdmit('authoring_context',
        authoringContext.wire, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth)), [], rawPreview,
      plans.map(value => value.name), plans.map(value => value.wire),
      limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    return control.admit('captured_run',
      moon.strategyPublicationContractJson(rawCaptured), limits);
  };
  const effectfulCaptured = issueDirect([{name: 'WriteOne', wire: '{}'}]);
  assert.equal(effectfulCaptured.name, 'captured_run');
  assert.deepEqual(Object.keys(JSON.parse(effectfulCaptured.wire)
    .effect_context.effect_source_local_inventory), ['WriteOne']);
  assert.deepEqual(Object.keys(JSON.parse(effectfulCaptured.wire)
    .effect_context.effects), ['WriteOne']);
  assert.throws(() => issueDirect([]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => issueDirect([{name: 'Foreign', wire: '{}'}]),
  {code: 'MoonBitHostFailure'});
  const memberReceipt = control.seal('effect_apply_receipt',
    JSON.stringify({
      version: 'actql-effect-apply-receipt/0.1',
      run_identity_cid: previewBody.run_identity_cid,
      effect_preview_cid: previewBody.effect_preview_cid,
      effect_member_preview_cid:
        previewBody.effects[0].effect_member_preview_cid,
      rows: [], status: 'applied',
    }), limits);
  const setReceipt = control.seal('effect_set_apply_receipt',
    JSON.stringify({
      version: 'actql-effect-set-apply-receipt/0.1',
      effect_preview_cid: previewBody.effect_preview_cid,
      apply_policy: 'attempt_all',
      effects: [{
        effect_id: 'WriteOne',
        effect_member_preview_cid:
          previewBody.effects[0].effect_member_preview_cid,
        state: 'applied', replayed: false,
        member_receipt_cid: memberReceipt.identity,
      }],
      status: 'applied',
    }), limits);
  const issuedSet = control.issueEffectSetApplyReceiptFromMembers(
    preview, [memberReceipt], [false], limits);
  assert.equal(issuedSet.identity, setReceipt.identity);
  assert.equal(control.effectSetReceiptRunDisposition(preview, {
    setWire: issuedSet.wire, memberWires: [memberReceipt.wire],
  }, limits), 0);
  assert.throws(() => control.issueEffectSetApplyReceiptFromMembers(
    preview, [memberReceipt], [], limits), {code: 'MoonBitHostFailure'});
  const finalChain = {
    runDefinition: run, invocation: invoked,
    definitions: [definition], artifacts: [artifact], manifest,
    computationReceipt: receipt, capturedRun: effectfulCaptured,
  };
  const finalReceipt = control.issueEffectfulFinalRunReceipt(
    finalChain, preview, {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits);
  assert.equal(JSON.parse(finalReceipt.wire).captured_run_cid,
    effectfulCaptured.identity);
  assert.equal(JSON.parse(finalReceipt.wire).effect_preview_cid,
    previewBody.effect_preview_cid);
  assert.notEqual(finalReceipt.identity, receipt.identity);
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    finalChain, {}, {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits),
  {name: 'TypeError', message: 'Foreign Effect computation Preview'});
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    finalChain, preview, {setWire: setReceipt.wire,
      memberWires: []}, limits),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => control.issueEffectfulFinalRunReceipt(
    {...finalChain, capturedRun: captured}, preview,
    {setWire: setReceipt.wire,
      memberWires: [memberReceipt.wire]}, limits),
  {code: 'MoonBitHostFailure'});
  const payloadWire = JSON.stringify(resultRows);
  const payloadBytes = Buffer.byteLength(payloadWire, 'utf8');
  const physicalCid = `sha256:${createHash('sha256')
    .update(payloadWire).digest('hex')}`;
  const binding = control.issueDurableResultBinding({
    runDefinition: run,
    definition,
    invocation: invoked,
    artifact,
    ordering,
    retention,
  }, {
    codecContractCid: cid('b'),
    resultFields: ['value'],
    resultSchemaWire,
    materialGenerationCid: physicalCid,
    storeAuthorityCid: cid('a'),
    rowCount: 1,
    byteCount: payloadBytes,
    physicalSha256: physicalCid.slice(7),
  }, limits);
  const request = control.issuePublicationRequest(run, [definition], {
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    publicationPolicyCid: cid('e'),
    publicationTargetCid: cid('f'),
    requestedAt: '2026-09-18T00:00:00.000Z',
  }, limits);
  const attempt = control.issuePublicationAttempt(request, run, {
    attemptId: 'attempt-1',
    fenceCid: cid('0'),
    startedAt: '2026-09-18T00:00:01.000Z',
  }, limits);
  const indexEntry = control.issuePublicIndexEntry({
    runDefinition: run,
    invocation: invoked,
    manifest,
    receipt,
    capturedRun: captured,
    durableBindings: [binding],
    request,
    attempt,
  }, '2026-09-18T00:00:02.000Z', limits);
  const effectfulIndex = control.issuePublicIndexEntry({
    runDefinition: run,
    invocation: invoked,
    manifest,
    receipt: finalReceipt,
    capturedRun: effectfulCaptured,
    durableBindings: [binding],
    request,
    attempt,
  }, '2026-09-18T00:00:02.000Z', limits);
  assert.equal(control.publicIndexSameCommittedContent(
    indexEntry, indexEntry), true);
  assert.equal(control.publicIndexSameCommittedContent(
    indexEntry, effectfulIndex), false);
  const effectfulEvidence = {
    ...finalChain,
    derivations: [derivation],
    orderings: [ordering],
    retentions: [retention],
    durableBindings: [binding],
  };
  const effectfulReceipts = {setWire: setReceipt.wire,
    memberWires: [memberReceipt.wire], finalWire: finalReceipt.wire};
  assert.equal(control.effectfulCommitValid(effectfulEvidence, preview,
    effectfulReceipts, request, attempt, effectfulIndex, limits), true);
  assert.equal(control.effectfulCommitValid(effectfulEvidence, preview,
    effectfulReceipts, request, attempt, indexEntry, limits), false);
  assert.equal(control.effectfulCommitValid({...effectfulEvidence,
    derivations: []}, preview, effectfulReceipts, request, attempt,
  effectfulIndex, limits), false);
  assert.throws(() => control.effectfulCommitValid(effectfulEvidence, {},
    effectfulReceipts, request, attempt, effectfulIndex, limits),
  {name: 'TypeError', message: 'Foreign Effect computation Preview'});
  assert.equal(await control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), true);
  assert.equal(await control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    indexEntry,
    limits,
  ), true);
  const foreignDefinition = control.seal(
    'result_definition',
    JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: cid('f'),
      result_name: 'answer',
    }),
    limits,
  );
  assert.equal(await control.effectFreeChainValid(
    run,
    invoked,
    [foreignDefinition],
    [artifact],
    manifest,
    receipt,
    captured,
    limits,
  ), false);
  const wrongReceiptValue = JSON.parse(receipt.wire);
  delete wrongReceiptValue.receipt_identity_cid;
  wrongReceiptValue.compiled_plan_cid = cid('e');
  const wrongReceipt = control.seal(
    'run_receipt', JSON.stringify(wrongReceiptValue), limits,
  );
  const wrongReceiptCaptureValue = JSON.parse(captured.wire);
  delete wrongReceiptCaptureValue.captured_run_cid;
  wrongReceiptCaptureValue.receipt = JSON.parse(wrongReceipt.wire);
  const wrongReceiptCapture = control.seal(
    'captured_run', JSON.stringify(wrongReceiptCaptureValue), limits,
  );
  assert.equal(await control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    wrongReceipt,
    wrongReceiptCapture,
    limits,
  ), false);
  const wrongInventoryValue = JSON.parse(captured.wire);
  delete wrongInventoryValue.captured_run_cid;
  const wrongEffect = wrongInventoryValue.effect_context;
  delete wrongEffect.effect_context_cid;
  wrongEffect.result_values = {foreign: null};
  wrongEffect.effect_context_cid = canonicalCid(wrongEffect);
  const wrongInventoryCapture = control.seal(
    'captured_run', JSON.stringify(wrongInventoryValue), limits,
  );
  assert.equal(await control.effectFreeChainValid(
    run,
    invoked,
    [definition],
    [artifact],
    manifest,
    receipt,
    wrongInventoryCapture,
    limits,
  ), false);
  const wrongIndex = control.seal('public_index_entry', JSON.stringify({
    ...JSON.parse(indexEntry.wire),
    public_index_entry_cid: undefined,
    result_manifest_cid: cid('0'),
  }), limits);
  assert.equal(await control.effectFreeCommitValid(
    run,
    invoked,
    [definition],
    [artifact],
    [derivation],
    [ordering],
    [retention],
    [binding],
    manifest,
    receipt,
    captured,
    request,
    attempt,
    wrongIndex,
    limits,
  ), false);
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-chain-',
  ));
  retainedDirectories.push(directory);
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    privateEvidenceKey: Buffer.alloc(32, 4),
  }, control);
  retainedStores.push(store);
  const privatePrepared = await store.preparePrivateEvidence(
    privateBinding.name, privateBinding.wire, privateBinding.semanticCid,
  );
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private',
    holding_cid: privateBinding.holdingCid,
    manifest_cid: privateBinding.semanticCid,
    objects: [{cid: privatePrepared.physicalCid,
      byte_count: privatePrepared.bytes}],
  }, [privatePrepared.prepared]);
  assert.equal((await store.readPrivateEvidence(
    privateBinding.name,
    privateBinding.semanticCid,
    privateBinding.holdingCid,
  )).toString('utf8'), privateBinding.wire);
  assert.equal((await store.confirmPrivateEvidence(privateBinding))
    .holding_cid, privateBinding.holdingCid);
  for (const contract of [
    run,
    invoked,
    definition,
    artifact,
    derivation,
    ordering,
    retention,
    binding,
    manifest,
    receipt,
    captured,
    request,
    sourceArtifact,
    effectfulCaptured,
    memberReceipt,
    setReceipt,
    finalReceipt,
    foreignDefinition,
  ]) {
    await store.putPublicationContract(contract.name, contract.wire);
  }
  await store.putSemantic(resultSchemaWire, resultSchemaCid);
  await store.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  await store.createAttempt(attempt.wire);
  const preparing = control.issuePublicationRecord(attempt, undefined, {
    state: 'preparing',
    observedAt: '2026-09-18T00:00:03.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(preparing.wire, {
    uncommittedConfirmed: false,
  });
  const committing = control.issuePublicationRecord(attempt, preparing, {
    state: 'committing',
    observedAt: '2026-09-18T00:00:04.000Z',
    cleanupOwnerCids: [],
    uncommittedConfirmed: false,
  }, limits);
  await store.appendRecord(committing.wire, {
    uncommittedConfirmed: false,
  });
  const source = computationEvidence.effectSources[0];
  const sourceWriter = store.createPreparedObjectWriter(payloadBytes);
  await sourceWriter.append(Buffer.from(payloadWire, 'utf8'));
  const sourcePrepared = await sourceWriter.seal(physicalCid);
  const sourceHoldingCid = control.capturedEffectSourceHoldingCid(source);
  await store.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source',
    holding_cid: sourceHoldingCid,
    manifest_cid: sourceArtifact.identity,
    objects: [{cid: sourcePrepared.cid, byte_count: sourcePrepared.bytes}],
  }, [sourcePrepared.prepared]);
  const effectfulPreparation = {
    index: effectfulIndex,
    chain: effectfulEvidence,
    preview,
    receipts: effectfulReceipts,
    privateBinding,
    effectSources: [source],
  };
  const checkedPreparation = await store.inspectEffectfulStoredEvidence(
    effectfulPreparation);
  assert.equal(Object.isFrozen(checkedPreparation.verifiedBindings), true);
  assert.equal(checkedPreparation.verifiedBindings[0].binding
    .durable_result_binding_cid, binding.identity);
  assert.equal(checkedPreparation.verifiedBindings[0].physical.cid, physicalCid);
  assert.equal(checkedPreparation.verifiedBindings[0].schema.cid, resultSchemaCid);
  assert.equal(checkedPreparation.finalReceipt.identity,
    finalReceipt.identity);
  assert.equal(checkedPreparation.privateHoldingCid,
    privateBinding.holdingCid);
  assert.deepEqual(checkedPreparation.effectSourceHoldingCids,
    [sourceHoldingCid]);
  const effectfulDirectory = await mkdtemp(join(
    tmpdir(), 'actql-effectful-publication-commit-',
  ));
  retainedDirectories.push(effectfulDirectory);
  const effectfulConfiguration = {
    directory: effectfulDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    privateEvidenceKey: Buffer.alloc(32, 4),
  };
  const effectfulStore = await openLocalPublicationStore(
    effectfulConfiguration, control,
  );
  retainedStores.push(effectfulStore);
  const effectfulPrivate = await effectfulStore.preparePrivateEvidence(
    privateBinding.name, privateBinding.wire, privateBinding.semanticCid,
  );
  await effectfulStore.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private',
    holding_cid: privateBinding.holdingCid,
    manifest_cid: privateBinding.semanticCid,
    objects: [{cid: effectfulPrivate.physicalCid,
      byte_count: effectfulPrivate.bytes}],
  }, [effectfulPrivate.prepared]);
  for (const contract of [
    run, invoked, definition, artifact, derivation, ordering, retention,
    binding, manifest, receipt, sourceArtifact, effectfulCaptured,
    memberReceipt, setReceipt, finalReceipt, request, attempt,
  ]) {
    await effectfulStore.putPublicationContract(
      contract.name, contract.wire,
    );
  }
  await effectfulStore.putSemantic(resultSchemaWire, resultSchemaCid);
  await effectfulStore.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  await effectfulStore.createAttempt(attempt.wire);
  await effectfulStore.appendRecord(preparing.wire, {
    uncommittedConfirmed: false,
  });
  await effectfulStore.appendRecord(committing.wire, {
    uncommittedConfirmed: false,
  });
  const effectfulSourceWriter = effectfulStore.createPreparedObjectWriter(
    payloadBytes,
  );
  await effectfulSourceWriter.append(Buffer.from(payloadWire, 'utf8'));
  const effectfulSource = await effectfulSourceWriter.seal(physicalCid);
  await effectfulStore.commitPhysicalHolding({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source',
    holding_cid: sourceHoldingCid,
    manifest_cid: sourceArtifact.identity,
    objects: [{cid: effectfulSource.cid,
      byte_count: effectfulSource.bytes}],
  }, [effectfulSource.prepared]);
  const effectfulRequired = [...new Set([
    run.identity, invoked.identity, definition.identity, artifact.identity,
    derivation.identity, ordering.identity, retention.identity,
    binding.identity, manifest.identity, receipt.identity,
    sourceArtifact.identity, effectfulCaptured.identity,
    memberReceipt.identity, setReceipt.identity, finalReceipt.identity,
    request.identity, attempt.identity, resultSchemaCid,
  ])];
  await assert.rejects(effectfulStore.commitEffectfulIndex(
    effectfulPreparation,
    effectfulRequired.filter(cid => cid !== sourceArtifact.identity),
  ), {code: 'IncompletePublicationCommitInventory'});
  assert.equal(await effectfulStore.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), undefined);
  const effectfulFixtureLedger = Object.freeze({});
  const effectfulPublication = {
    store: effectfulStore,
    control,
    chain: effectfulEvidence,
    preview,
    ledger: effectfulFixtureLedger,
    issuedSet: retainIssuedEffectSetReceipt({
      set: setReceipt, members: [memberReceipt],
      ledger: effectfulFixtureLedger, preview,
    }),
    effectSources: [source],
    sourceArtifacts: [sourceArtifact],
    request: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      publicationPolicyCid: cid('e'),
      publicationTargetCid: cid('f'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    },
    attempt: {
      attemptId: 'attempt-1',
      fenceCid: cid('0'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    },
    limits,
    now: () => '2026-09-18T00:00:02.000Z',
    signal: undefined,
  };
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication, sourceArtifacts: [],
  }), {code: 'InvalidEffectfulRunPublicationEvidence'});
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication,
    issuedSet: {...effectfulPublication.issuedSet},
  }), {code: 'EffectSetReceiptEvidenceNotOwned'});
  await assert.rejects(publishEffectfulRun({
    ...effectfulPublication, ledger: Object.freeze({}),
  }), {code: 'EffectSetReceiptEvidenceNotOwned'});
  assert.equal(await effectfulStore.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), undefined);
  let loseEffectfulCommitResponse = true;
  const effectfulBindingPayloadReads = [];
  let metadataBatches = 0, individualMetadataWrites = 0;
  const lostEffectfulStore = Object.freeze({
    ...effectfulStore,
    async beginPublicationAttemptWithRecords(...args) {
      metadataBatches++;
      return Reflect.apply(effectfulStore.beginPublicationAttemptWithRecords, effectfulStore, args);
    },
    async beginPublicationAttempt(...args) {
      metadataBatches++;
      return Reflect.apply(effectfulStore.beginPublicationAttempt, effectfulStore, args);
    },
    async putPublicationContracts(contracts) {
      metadataBatches++;
      return Reflect.apply(effectfulStore.putPublicationContracts, effectfulStore, [contracts]);
    },
    async putOriginalPublicationContracts(contracts) {
      metadataBatches++;
      return Reflect.apply(effectfulStore.putOriginalPublicationContracts, effectfulStore, [contracts]);
    },
    async putPublicationContract(...args) {
      individualMetadataWrites++;
      return Reflect.apply(effectfulStore.putPublicationContract, effectfulStore, args);
    },
    async commitEffectfulIndex(...args) {
      const originalOpen = fs.open;
      const payloadPath = join(effectfulDirectory, 'objects', physicalCid.slice(7));
      let reads = 0;
      fs.open = async function(path, ...options) {
        const bindingRead = path === payloadPath &&
          new Error().stack.includes('verifyDurableResultBinding');
        const handle = await Reflect.apply(originalOpen, this, [path, ...options]);
        if (bindingRead) reads++;
        return handle;
      };
      syncBuiltinESMExports();
      let committed;
      try {
        committed = await effectfulStore.commitEffectfulIndex(...args);
      } finally {
        fs.open = originalOpen;
        syncBuiltinESMExports();
        effectfulBindingPayloadReads.push(reads);
      }
      if (loseEffectfulCommitResponse) {
        loseEffectfulCommitResponse = false;
        throw new Error('LostEffectfulCommitResponse');
      }
      return committed;
    },
  });
  const effectfulCommitted = await publishEffectfulRun({
    ...effectfulPublication, store: lostEffectfulStore,
  });
  assert.equal(metadataBatches, 1, 'one publication setup persists its immutable metadata as one group');
  assert.equal(individualMetadataWrites, 0, 'the grouped caller does not issue per-contract writes again');
  assert.notEqual(effectfulBindingPayloadReads.length, 0);
  assert.deepEqual(effectfulBindingPayloadReads,
    effectfulBindingPayloadReads.map(() => 1));
  assert.equal(effectfulCommitted.committed, false);
  assert.equal(effectfulCommitted.idempotent, true);
  assert.equal(effectfulCommitted.state, 'succeeded');
  assert.equal(effectfulCommitted.index.identity, effectfulIndex.identity);
  const effectfulReplay = await publishEffectfulRun(effectfulPublication);
  assert.equal(effectfulReplay.idempotent, true);
  const effectfulPayloadPath = join(effectfulDirectory, 'objects', physicalCid.slice(7));
  try {
    await fs.writeFile(effectfulPayloadPath, Buffer.alloc(payloadBytes, 0));
    await assert.rejects(effectfulStore.validateCommittedEffectfulEvidence(
      effectfulPreparation), {code: 'PublicationObjectCorrupt'});
  } finally {
    await fs.writeFile(effectfulPayloadPath, payloadWire);
  }
  assert.equal(await effectfulStore.validateCommittedEffectfulEvidence(
    effectfulPreparation), true);
  const effectfulKey = {
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  };
  assert.deepEqual(await effectfulStore.inspectCommittedIndex(effectfulKey),
    JSON.parse(effectfulIndex.wire));
  await effectfulStore.close();
  const reopenedEffectfulStore = await openLocalPublicationStore(
    {...effectfulConfiguration, privateEvidenceKey: Buffer.alloc(32, 4)},
    control,
  );
  retainedStores.push(reopenedEffectfulStore);
  assert.deepEqual(
    await reopenedEffectfulStore.inspectCommittedIndex(effectfulKey),
    JSON.parse(effectfulIndex.wire),
  );
  assert.equal(await reopenedEffectfulStore
    .validateCommittedEffectfulEvidence(effectfulPreparation), true);
  assert.notEqual(await reopenedEffectfulStore.inspectPhysicalHolding(
    privateBinding.holdingCid), undefined);
  assert.notEqual(await reopenedEffectfulStore.inspectPhysicalHolding(
    sourceHoldingCid), undefined);
  const effectfulRetired =
    await reopenedEffectfulStore.retireCommittedPublicationMetadata(
      effectfulKey, '2026-09-18T00:00:08.000Z',
    );
  assert.equal(effectfulRetired.deleted, true);
  assert.equal(await reopenedEffectfulStore.inspectPhysicalHolding(
    privateBinding.holdingCid), undefined);
  assert.equal(await reopenedEffectfulStore.inspectPhysicalHolding(
    sourceHoldingCid), undefined);
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation, index: indexEntry,
  }), {code: 'InvalidEffectfulCommitChain'});
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation,
    privateBinding: {...privateBinding, wire: '{}'},
  }), {code: 'EffectfulPrivateEvidenceUnavailable'});
  await assert.rejects(store.inspectEffectfulStoredEvidence({
    ...effectfulPreparation, effectSources: [],
  }), {code: 'InvalidEffectfulSourceInventory'});
  assert.equal((await store.retirePhysicalHolding(
    privateBinding.holdingCid,
  )).deleted, true);
  await assert.rejects(store.inspectEffectfulStoredEvidence(
    effectfulPreparation), {code: 'EffectfulPrivateEvidenceUnavailable'});
  await t.test('Effect-free delivery and HTTP boundaries', async t => {
  const evidence = Object.freeze({
    runDefinition: run,
    invocation: invoked,
    definitions: Object.freeze([definition]),
    artifacts: Object.freeze([artifact]),
    derivations: Object.freeze([derivation]),
    orderings: Object.freeze([ordering]),
    retentions: Object.freeze([retention]),
    durableBindings: Object.freeze([binding]),
    manifest,
    receipt,
    capturedRun: captured,
  });
  const required = [...new Set([
    run.identity,
    invoked.identity,
    definition.identity,
    artifact.identity,
    derivation.identity,
    ordering.identity,
    retention.identity,
    binding.identity,
    manifest.identity,
    receipt.identity,
    captured.identity,
    request.identity,
    attempt.identity,
  ])];
  const foreignEvidence = Object.freeze({
    ...evidence,
    definitions: Object.freeze([foreignDefinition]),
  });
  await assert.rejects(store.commitIndex(
    indexEntry.wire,
    [...new Set([...required, foreignDefinition.identity])],
    foreignEvidence,
  ), error => error?.code === 'InvalidPublicationCommitChain');
  const times = [
    '2026-09-18T00:00:05.000Z',
    '2026-09-18T00:00:06.000Z',
  ];
  const publicationOptions = {
    store,
    control,
    evidence,
    request: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      publicationPolicyCid: cid('e'),
      publicationTargetCid: cid('f'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    },
    attempt: {
      attemptId: 'attempt-1',
      fenceCid: cid('0'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    },
    limits,
    now: () => times.shift() ?? '2026-09-18T00:00:07.000Z',
    signal: undefined,
  };
  let exportedResults = 0;
  const execution = Object.freeze({
    status: 'host-tasks-completed',
    resultInventory: Object.freeze([{name: 'answer', task: 1}]),
    publicationInventory: Object.freeze({
      occurrences: Object.freeze([Object.freeze({
        name: 'answer',
        task: 1,
        definitionContract: definition,
      })]),
    }),
    async storePublicationResult(index, target, supplied) {
      exportedResults++;
      assert.equal(index, 0);
      assert.equal(target, store);
      assert.equal(supplied.runDefinition, run);
      assert.equal(supplied.invocation, invoked);
      assert.equal(supplied.retention, retention);
      return Object.freeze({
        occurrence: Object.freeze({
          name: 'answer', task: 1, definition,
        }),
        physical: Object.freeze({cid: physicalCid, bytes: payloadBytes}),
        orderedRows: Object.freeze({rows: 1}),
        publication: Object.freeze({
          derivation,
          ordering,
          artifact,
          snapshot,
          durableBinding: binding,
        }),
      });
    },
  });
  const completedPublicationOptions = {
    execution,
    store,
    control,
    admission,
    runDefinition: run,
    invocation: invoked,
    observation,
    normalizationJournal,
    authoringContext,
    results: [{retention, evidenceContext: {}}],
    receiptEvidence: {
      bindings: [],
      sourceEvidence: [],
      modelEvidence: [],
      barrierAttemptReceiptCids: [],
    },
    captureEvidence: {
      pendingSourceStateAdvances: [],
      modelEvidence: [],
    },
    request: publicationOptions.request,
    attempt: publicationOptions.attempt,
    outputLimits: {},
    contractLimits: limits,
    now: () => '2026-09-18T00:00:05.000Z',
    signal: undefined,
  };
  await assert.rejects(publishCompletedEffectFreeRun({
    ...completedPublicationOptions,
    results: [],
  }), {code: 'InvalidCompletedRunPublicationOptions'});
  assert.equal(exportedResults, 0);
  const assembled = await publishCompletedEffectFreeRun(
    completedPublicationOptions,
  );
  assert.equal(exportedResults, 1);
  assert.equal(assembled.evidence.manifest.identity, manifest.identity);
  assert.equal(assembled.evidence.receipt.identity, receipt.identity);
  assert.equal(assembled.evidence.capturedRun.identity, captured.identity);
  const committed = assembled.publication;
  assert.equal(committed.state, 'succeeded');
  assert.equal(committed.committed, true);
  assert.equal(committed.idempotent, false);
  assert.deepEqual(await store.inspectCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  }), JSON.parse(committed.index.wire));
  const retried = await publishEffectFreeRun(publicationOptions);
  assert.equal(retried.state, 'succeeded');
  assert.equal(retried.committed, false);
  assert.equal(retried.idempotent, true);
  assert.equal(retried.index.identity, committed.index.identity);
  const alreadyCancelled = new AbortController();
  alreadyCancelled.abort(new Error('cancelled after durable publication'));
  const cancelledReplay = await publishEffectFreeRun({
    ...publicationOptions, signal: alreadyCancelled.signal,
  });
  assert.equal(cancelledReplay.state, 'succeeded');
  assert.equal(cancelledReplay.idempotent, true);
  assert.equal(cancelledReplay.index.identity, committed.index.identity);
  assert.equal(exportedResults, 1);

  const completedUnknownDirectory = await mkdtemp(join(
    tmpdir(), 'actql-completed-publication-unknown-',
  ));
  retainedDirectories.push(completedUnknownDirectory);
  let completedUnknownIndexSelected = false, completedUnknownIndexUnavailable = true;
  let completedUnknownIndexFailures = 0;
  const originalPrepare = DatabaseSync.prototype.prepare;
  const originalExec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(originalPrepare, this, [sql]);
    if (sql === 'INSERT INTO native_publication_indexes VALUES(?,?,?,?,?,1)') {
      const run = statement.run;
      t.mock.method(statement, 'run', function(...args) {
        const result = Reflect.apply(run, this, args);
        completedUnknownIndexSelected = true;
        return result;
      });
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (completedUnknownIndexSelected && completedUnknownIndexUnavailable && sql === 'COMMIT') {
      completedUnknownIndexFailures++;
      throw Object.assign(new Error('injected native Index COMMIT reply loss'), {code: 'EIO'});
    }
    return Reflect.apply(originalExec, this, [sql]);
  });
  const completedUnknownStore = await openLocalPublicationStore({
    directory: completedUnknownDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  retainedStores.push(completedUnknownStore);
  await completedUnknownStore.putSemantic(resultSchemaWire, resultSchemaCid);
  const completedUnknownWriter =
    completedUnknownStore.createPreparedObjectWriter(payloadBytes);
  await completedUnknownWriter.append(payloadWire);
  const completedUnknownPayload =
    await completedUnknownWriter.seal(physicalCid);
  let completedUnknownExports = 0;
  const completedUnknownExecution = Object.freeze({
    ...execution,
    async storePublicationResult(index, target, supplied) {
      completedUnknownExports++;
      assert.equal(index, 0);
      assert.equal(target, completedUnknownStore);
      assert.equal(supplied.runDefinition, run);
      assert.equal(supplied.invocation, invoked);
      return Object.freeze({
        occurrence: Object.freeze({
          name: 'answer', task: 1, definition,
        }),
        physical: Object.freeze({cid: physicalCid, bytes: payloadBytes}),
        orderedRows: Object.freeze({rows: 1}),
        publication: Object.freeze({
          derivation,
          ordering,
          artifact,
          snapshot,
          durableBinding: binding,
        }),
        // Match durable-result-payload: publication adopts the exact physical
        // holder, while the cleanup view retains the same release duty.
        physicalPrepared: completedUnknownPayload.prepared,
        prepared: completedUnknownPayload.prepared,
      });
    },
  });
  let completedUnknownFailure;
  await assert.rejects(publishCompletedEffectFreeRun({
    ...completedPublicationOptions,
    execution: completedUnknownExecution,
    store: completedUnknownStore,
    attempt: {
      ...completedPublicationOptions.attempt,
      attemptId: 'unknown-completed-attempt',
    },
  }), error => {
    completedUnknownFailure = error;
    return error?.code === 'RunPublicationUnknown' &&
      error.cleanupHandle?.status().pending === true;
  });
  assert.equal(completedUnknownExports, 1);
  assert(completedUnknownIndexFailures > 0, 'the actual native Index commit boundary was injected');
  assert.equal(completedUnknownPayload.prepared.status().pending, true);
  assert.equal((await completedUnknownStore.verifyObject(physicalCid)).bytes,
    payloadBytes);
  completedUnknownIndexUnavailable = false;
  const reconciledCompletedUnknown =
    await completedUnknownFailure.cleanupHandle.retry();
  assert.equal(reconciledCompletedUnknown.pending, false,
    JSON.stringify(reconciledCompletedUnknown, (_name, value) => value instanceof Error
      ? {name: value.name, code: value.code, message: value.message, stack: value.stack}
      : value));
  assert.equal(reconciledCompletedUnknown.outcome, 'committed');
  assert.equal(completedUnknownPayload.prepared.status().pending, false);
  assert.equal(completedUnknownExports, 1);
  assert.equal(
    completedUnknownFailure.primaryFailure.publicationResult.state,
    'succeeded',
  );
  assert.equal(await completedUnknownStore.close(), true);

  await store.close();
  const deliveryStore = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  retainedStores.push(deliveryStore);
  const deliveryIndexValue = await deliveryStore.confirmCommittedIndex({
    namespaceId: 'namespace-a',
    authorityScopeCid: cid('d'),
    runDefinitionCid: run.identity,
  });
  const deliveryIndex = await deliveryStore.readPublicationContract(
    deliveryIndexValue.public_index_entry_cid,
    'public_index_entry',
  );
  const deliveryManifest = await deliveryStore.readPublicationContract(
    deliveryIndexValue.result_manifest_cid,
    'result_manifest',
  );
  const deliveryGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json', 'jsonl', 'csv'],
      principalId: 'principal-a',
      purpose: 'download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 4,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const createDigest = () => {
    const hash = createHash('sha256');
    return Object.freeze({
      update: bytes => hash.update(bytes),
      finish: () => hash.digest('hex'),
    });
  };
  let requestAccessAllowed = true;
  let accessAllowed = true;
  let advanceAccessTimeAt;
  let readRequestGate;
  let accessTime = '2026-09-18T01:00:00.000Z';
  const accessChecks = [];
  const accessAuthority = installResultAccessAuthority({
    async authorizeResultReadRequest(facts) {
      accessChecks.push(`authorize:request:${facts.resultName}`);
      if (readRequestGate !== undefined) {
        readRequestGate.started();
        await readRequestGate.wait;
      }
      return requestAccessAllowed;
    },
    async authorizeDeliveryAttemptLookup(facts) {
      accessChecks.push(`authorize:attempt:${facts.resultName}`);
      return accessAllowed;
    },
    async admitResultRead(facts) {
      accessChecks.push(`admit:${facts.resultName}:${facts.format}`);
      return {
        authorizationContextCid: cid('2'),
        dataCeilingCid: cid('1'),
        egressAdmissionCid: cid('3'),
        expiresAt: '2026-09-19T00:00:00.000Z',
        maxBytes: 1024,
        maxUses: 3,
      };
    },
    async authorizeResultRead(facts) {
      accessChecks.push(`authorize:${facts.delivery.stage}`);
      if (advanceAccessTimeAt !== undefined &&
          facts.delivery.stage === 'write') {
        await Promise.resolve();
        accessTime = advanceAccessTimeAt;
      }
      return accessAllowed;
    },
  });
  const accessService = installNodeResultAccessService({
    store: deliveryStore,
    control,
    authority: accessAuthority,
    now: () => accessTime,
    limits,
    frameLimits: {
      maxRowBytes: 4096,
      maxDepth: 32,
      maxFrameBytes: 4096,
    },
  });
  let stateAccessAllowed = true;
  let resultPolicyAvailable = true;
  const stateAuthority = installRunStateAuthority({
    authorizeRunState: () => stateAccessAllowed,
    resultPolicyAvailable: () => resultPolicyAvailable,
  });
  const stateService = installRunStateService({
    store: deliveryStore,
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  let manifestAccessAllowed = true;
  const manifestAuthority = installManifestAccessAuthority({
    authorizeManifestRead: () => manifestAccessAllowed,
    admitManifestRead: () => ({
      authorizationContextCid: cid('2'),
      clockContractCid: cid('d'),
      dataCeilingCid: cid('1'),
      expiresAt: '2026-09-19T00:00:00.000Z',
      maxBytes: limits.maxWireBytes,
      maxUses: 1,
    }),
  });
  const manifestService = installManifestAccessService({
    store: deliveryStore,
    control,
    authority: manifestAuthority,
    now: () => accessTime,
    limits,
  });
  const stateRequest = {
    indexKey: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity,
    },
    principalId: 'principal-a',
    purpose: 'inspect',
  };
  const availableState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(availableState.status, 'succeeded');
  assert.equal(availableState.result_available, true);
  assert.deepEqual(availableState.next_action, {
    kind: 'read_result', results: ['answer'],
  });
  assert.deepEqual(availableState.result_availability.answer, {
    observed_at: accessTime,
    reason: 'confirmed_present',
    state: 'available',
  });
  const contradictoryStateService = installRunStateService({
    store: Object.freeze({
      ...deliveryStore,
      latestRecordContract: () => deliveryStore.readPublicationContract(
        deliveryIndexValue.public_index_entry_cid, 'public_index_entry'),
    }),
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  await assert.rejects(
    inspectAuthorizedRunState(contradictoryStateService, stateRequest),
    {code: 'InvalidCommittedPublicationState'},
  );
  // Public observation revisions belong to the original physical request Journal,
  // not to a successful publication snapshot or a callback-generated counter.
  const requestDirectory = await mkdtemp(join(tmpdir(), 'actql-publication-request-'));
  retainedDirectories.push(requestDirectory);
  const requestJournal = openClientRequestJournal(requestDirectory);
  retainedJournals.push(requestJournal);
  const requestIdentity = moon.clientRequestAdmitRecord(cid('d'), 'publication-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'), 'sha256:127ed76fb9b6ab693e306632d7d89290dec524313965cce13f433d1e26bdfcd5',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert.ok(requestIdentity);
  const acceptedRequest = requestJournal.acceptDefinition(requestIdentity, {
    namespaceId: 'namespace-a', runDefinition: run,
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  }, moon, control);
  assert.deepEqual(acceptedRequest.ref, stateRequest.indexKey);
  const runStateObservation = installNodeClientRunStateObservation({
    journal: requestJournal, requestControl: moon, publicationControl: control,
  });
  const availableClientState = await observeClientRunState(runStateObservation,
    stateService, stateRequest);
  assert.equal(availableClientState.status, 'succeeded');
  assert.deepEqual(availableClientState.result_availability, availableState.result_availability);
  const environmentWire = await readFile(new URL(
    '../../spec/local-check-environment.json', import.meta.url), 'utf8');
  const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, true, false, false, false);
  assert.ok(environment);
  const funded = await fundedClientPreparation(t, {moon, environment, http: true});
  const clientHost = createServer(createClientHttpHandler({
    prepareRequest: funded.prepareRequest,
    authenticate: authorization => authorization === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: facts => facts.connection.mode === 'local' &&
      facts.connection.owner === 'local' &&
      (facts.ref === undefined || facts.ref.namespaceId === 'namespace-a'),
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'durable', scopeRef: 'principal-a',
      capabilities: ['result-jsonl'],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024,
        maxRetainedValueBytes: 4096, maxRows: 100,
        maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
    }),
    attach: async ({ref, principalId}) => {
      await inspectAuthorizedRunState(stateService, {
        indexKey: ref, principalId, purpose: 'inspect',
      });
      return {ref, durability: 'durable', revision: 0};
    },
    stateService, runStateObservation,
    resultService: accessService,
  }));
  await new Promise(resolve => clientHost.listen(0, '127.0.0.1', resolve));
  try {
    const base = `http://127.0.0.1:${clientHost.address().port}`;
    const headers = {authorization: 'Bearer scoped-token',
      'content-type': 'application/json'};
    const connection = {mode: 'local', owner: 'local',
      runners: [], consentRefs: []};
    const statusReply = await fetch(`${base}/actql/client/0.1/status`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey}),
    });
    assert.equal(statusReply.status, 200, await statusReply.clone().text());
    assert.deepEqual(await statusReply.json(), availableClientState);
    const readReply = await fetch(`${base}/actql/client/0.1/read`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey,
        resultName: 'answer', format: 'json', attemptId: 'http-result-read'}),
    });
    assert.equal(readReply.status, 200);
    assert.equal(await readReply.text(), '[{"value":7}]');
    const streamReply = await fetch(`${base}/actql/client/0.1/read`, {
      method: 'POST', headers,
      body: JSON.stringify({connection, ref: stateRequest.indexKey,
        resultName: 'answer', format: 'jsonl',
        attemptId: 'http-result-stream'}),
    });
    assert.equal(streamReply.status, 200);
    assert.equal(await streamReply.text(), '{"value":7}\n\x1e');
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: `${base}/`, token: 'scoped-token'});
    const attached = await client.attach(stateRequest.indexKey);
    assert.deepEqual(await attached.status(), availableClientState);
    const reader = attached.result('answer').rows();
    assert.deepEqual(await Array.fromAsync(reader), [{value: 7}]);
    assert.equal(reader.state(), 'complete');
    assert.equal((await attached.result('answer')
      .deliveryAttempt(reader.attemptId)).kind, 'found');
    const inspectAttempt = async attemptId => fetch(
      `${base}/actql/client/0.1/delivery-attempt`, {
        method: 'POST', headers,
        body: JSON.stringify({connection, ref: stateRequest.indexKey,
          resultName: 'answer', attemptId}),
      });
    const attemptReply = await inspectAttempt('http-result-stream');
    assert.equal(attemptReply.status, 200);
    let attemptStatus = await attemptReply.json();
    assert.equal(attemptStatus.kind, 'found');
    assert.equal(attemptStatus.attempt.attempt_id, 'http-result-stream');
    for (let tries = 0; tries < 100 &&
        attemptStatus.record?.state !== 'succeeded'; tries++) {
      await new Promise(resolve => setTimeout(resolve, 10));
      attemptStatus = await (await inspectAttempt('http-result-stream')).json();
    }
    assert.equal(attemptStatus.record.state, 'succeeded');
    assert.equal(attemptStatus.hostReleaseReceipt.delivered_byte_count,
      Buffer.byteLength('{"value":7}\n'));
    assert.deepEqual(await (await inspectAttempt('missing')).json(),
      {kind: 'not_found'});
    accessAllowed = false;
    const deniedAttempt = await inspectAttempt('http-result-stream');
    const deniedMissing = await inspectAttempt('missing');
    assert.equal(deniedAttempt.status, 403);
    assert.equal(deniedMissing.status, 403);
    accessAllowed = true;
  } finally {
    await new Promise(resolve => clientHost.close(resolve));
  }
  const uncertainStateService = installRunStateService({
    store: Object.freeze({
      confirmCommittedIndex: key =>
        deliveryStore.confirmCommittedIndex(key),
      readPublicationContract: (identity, name) =>
        deliveryStore.readPublicationContract(identity, name),
      latestRecordContract: identity =>
        deliveryStore.latestRecordContract(identity),
      observeTrustedClock: (identity, at) =>
        deliveryStore.observeTrustedClock(identity, at),
      readCommittedResultRetentionExtension: (key, definition) =>
        deliveryStore.readCommittedResultRetentionExtension(key, definition),
      withCommittedResult: async () => {
        throw new Error('temporary Store query failure');
      },
    }),
    control,
    authority: stateAuthority,
    now: () => accessTime,
    limits,
  });
  const uncertainState = await inspectAuthorizedRunState(
    uncertainStateService, stateRequest,
  );
  assert.equal(uncertainState.result_available, false);
  assert.deepEqual(uncertainState.next_action, {
    kind: 'refresh_availability', results: ['answer'],
  });
  assert.equal(
    uncertainState.result_availability.answer.reason,
    'store_query_failed',
  );
  resultPolicyAvailable = false;
  const policyState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(policyState.result_available, false);
  assert.deepEqual(policyState.next_action, {kind: 'none'});
  assert.equal(
    policyState.result_availability.answer.reason,
    'policy_unavailable',
  );
  resultPolicyAvailable = true;
  stateAccessAllowed = false;
  await assert.rejects(
    inspectAuthorizedRunState(stateService, stateRequest),
    {code: 'RunStateAccessDenied'},
  );
  stateAccessAllowed = true;
  const manifestRequest = {
    indexKey: stateRequest.indexKey,
    principalId: 'principal-a',
    purpose: 'inspect',
    attemptId: 'manifest-read-a',
  };
  const manifestResponse = await readAuthorizedManifest(
    manifestService, manifestRequest,
  );
  assert.equal(manifestResponse.manifestCid, manifest.identity);
  assert.equal(manifestResponse.manifest.results.answer.result_artifact_cid,
    artifact.identity);
  assert.equal(manifestResponse.idempotent, false);
  assert.equal((await readAuthorizedManifest(
    manifestService, manifestRequest,
  )).idempotent, true);
  await assert.rejects(readAuthorizedManifest(manifestService, {
    ...manifestRequest,
    attemptId: 'manifest-read-b',
  }), {code: 'ManifestReadGrantUseLimit'});
  manifestAccessAllowed = false;
  await assert.rejects(
    readAuthorizedManifest(manifestService, manifestRequest),
    {code: 'ManifestAccessDenied'},
  );
  manifestAccessAllowed = true;
  const authorizedChunks = [];
  requestAccessAllowed = false;
  for (const deniedRequest of [
    {
      ...stateRequest,
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-existing',
    },
    {
      ...stateRequest,
      indexKey: {...stateRequest.indexKey, runDefinitionCid: cid('0')},
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-missing-index',
    },
    {
      ...stateRequest,
      purpose: 'download',
      resultName: 'missing-result',
      format: 'json',
      attemptId: 'denied-missing-result',
    },
  ]) {
    await assert.rejects(deliverAuthorizedResult(
      accessService,
      deniedRequest,
      {
        write: () => assert.fail('denied request exposed bytes'),
        finish: () => assert.fail('denied request completed delivery'),
      },
    ), error => error?.code === 'ResultAccessDenied' &&
      error.cause === undefined && error.primaryFailure === undefined);
  }
  requestAccessAllowed = true;
  const authorizedDelivery = await deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-json',
    },
    {
      async write(bytes) {
        authorizedChunks.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  );
  assert.equal(Buffer.concat(authorizedChunks).toString('utf8'),
    '[{"value":7}]');
  assert.equal(authorizedDelivery.idempotent, false);
  assert.ok(accessChecks.includes('authorize:request:answer'));
  assert.ok(accessChecks.includes('authorize:read'));
  assert.ok(accessChecks.includes('authorize:write'));
  assert.ok(accessChecks.includes('authorize:receipt'));
  let releaseReadRequest;
  let readAuthorizationStarted;
  const readStarted = new Promise(resolve => {
    readAuthorizationStarted = resolve;
  });
  const readWait = new Promise(resolve => { releaseReadRequest = resolve; });
  readRequestGate = {started: readAuthorizationStarted, wait: readWait};
  const changedReadRequest = {
    indexKey: {namespaceId: 'namespace-a', authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity},
    principalId: 'principal-a', purpose: 'download', resultName: 'answer',
    format: 'json', attemptId: 'snapshot-json',
  };
  const snapshottedChunks = [];
  const pendingRead = deliverAuthorizedResult(
    accessService, changedReadRequest, {
      async write(bytes) {
        snapshottedChunks.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  );
  await readStarted;
  changedReadRequest.resultName = 'missing-result';
  changedReadRequest.format = 'csv';
  changedReadRequest.attemptId = 'foreign-attempt';
  changedReadRequest.indexKey.namespaceId = 'namespace-b';
  changedReadRequest.indexKey.runDefinitionCid = cid('0');
  releaseReadRequest();
  readRequestGate = undefined;
  const snapshottedDelivery = await pendingRead;
  assert.equal(snapshottedDelivery.idempotent, false);
  assert.equal(Buffer.concat(snapshottedChunks).toString('utf8'),
    '[{"value":7}]');
  accessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-revoked',
    },
    {
      write: () => assert.fail('revoked access exposed bytes'),
      finish: () => assert.fail('revoked access finished delivery'),
    },
  ), {code: 'ResultDeliveryDenied'});
  accessAllowed = true;
  accessTime = '2026-09-18T01:00:00.001Z';
  requestAccessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-expired',
    },
    {
      write: () => assert.fail('denied expired Result exposed bytes'),
      finish: () => assert.fail('denied expired Result finished delivery'),
    },
  ), {code: 'ResultAccessDenied'});
  requestAccessAllowed = true;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: {
        namespaceId: 'namespace-a',
        authorityScopeCid: cid('d'),
        runDefinitionCid: run.identity,
      },
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-expired',
    },
    {
      write: () => assert.fail('expired Result exposed bytes'),
      finish: () => assert.fail('expired Result finished delivery'),
    },
  ), {code: 'ResultUnavailable'});
  const expiredState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(expiredState.result_available, false);
  assert.deepEqual(expiredState.next_action, {kind: 'none'});
  assert.equal(
    expiredState.result_availability.answer.reason,
    'retention_expired',
  );
  accessTime = '2026-09-18T01:00:00.000Z';
  const deliveryBase = {
    store: deliveryStore,
    control,
    indexKey: {
      namespaceId: 'namespace-a',
      authorityScopeCid: cid('d'),
      runDefinitionCid: run.identity,
    },
    grant: deliveryGrant,
    resultName: 'answer',
    limits,
    frameLimits: {
      maxRowBytes: 4096,
      maxDepth: 32,
      maxFrameBytes: 4096,
    },
    now: () => '2026-09-18T01:00:00.000Z',
    createDigest,
    authorize: () => true,
    signal: undefined,
  };
  const expiringGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'expiring-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-18T01:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let expiringTime = '2026-09-18T00:59:59.999Z';
  let expiredSinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: expiringGrant,
    format: 'json',
    attemptId: 'delivery-expired-during-authorization',
    now: () => expiringTime,
    async authorize(facts) {
      if (facts.stage === 'write') {
        await Promise.resolve();
        expiringTime = '2026-09-18T01:00:00.001Z';
      }
      return true;
    },
    sink: {
      async write(bytes) {
        expiredSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), {code: 'ResultDeliveryGrantExpired'});
  assert.equal(expiredSinkWrites, 0);

  const cancelledGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'cancelled-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const cancelledController = new AbortController();
  let cancelledSinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: cancelledGrant,
    format: 'json',
    attemptId: 'delivery-cancelled-during-authorization',
    signal: cancelledController.signal,
    async authorize(facts) {
      if (facts.stage === 'write') {
        await Promise.resolve();
        cancelledController.abort(new Error('authorization cancelled'));
      }
      return true;
    },
    sink: {
      async write(bytes) {
        cancelledSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), error => error?.message === 'authorization cancelled');
  assert.equal(cancelledSinkWrites, 0);
  const expectedDelivery = Object.freeze({
    json: '[{"value":7}]',
    jsonl: '{"value":7}\n',
    csv: '"value"\n7\n',
  });
  let jsonReaders = 0, enteredRecord, releaseRecord, gateEntered = false;
  const recordEntered = new Promise(resolve => { enteredRecord = resolve; });
  const recordGate = new Promise(resolve => { releaseRecord = resolve; });
  const jsonStore = {
    ...deliveryStore,
    async beginDeliveryAttempt(...args) {
      const admitted = await deliveryStore.beginDeliveryAttempt(...args);
      if (!gateEntered) {
        gateEntered = true;
        enteredRecord();
        await recordGate;
      }
      return admitted;
    },
    withCommittedResultRows(...args) {
      jsonReaders++;
      return deliveryStore.withCommittedResultRows(...args);
    },
  };
  for (const format of ['json', 'jsonl', 'csv']) {
    const chunks = [];
    const options = {
      ...deliveryBase,
      store: format === 'json' ? jsonStore : deliveryStore,
      format,
      attemptId: `delivery-${format}`,
      createDigest: format === 'jsonl' ? () => {
        const digest = createDigest();
        return {update: bytes => digest.update(bytes),
          finish: async () => digest.finish()};
      } : createDigest,
      sink: {
        async write(bytes) {
          chunks.push(Buffer.from(bytes));
          return {confirmedBytes: bytes.byteLength};
        },
        async finish() { return {confirmed: true}; },
      },
    };
    const first = deliverPublishedResult(options);
    if (format === 'json') {
      // The current atomic attempt/initial-record pair is committed, but no
      // payload reader exists yet. A concurrent request cannot acquire its slot.
      await Promise.race([recordEntered, first.then(() => {
        assert.fail('delivery bypassed the first-record boundary');
      })]);
      try {
        await assert.rejects(deliverPublishedResult({...options,
          now: () => '2026-09-18T01:00:01.000Z'}),
        {code: 'ResultDeliveryAttemptUnresolved'});
        assert.equal(jsonReaders, 0);
        assert.equal(chunks.length, 0);
      } finally { releaseRecord(); await first; }
    }
    const delivered = await first;
    const deliveryBytes = Buffer.concat(chunks);
    assert.equal(deliveryBytes.toString('utf8'), expectedDelivery[format]);
    assert.equal(delivered.byteCount, deliveryBytes.byteLength);
    assert.equal(
      delivered.sha256,
      createHash('sha256').update(deliveryBytes).digest('hex'),
    );
  }
  assert.equal(jsonReaders, 1);
  const emptyGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['jsonl'],
      principalId: 'principal-a',
      purpose: 'empty-download',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 3,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  const emptyStore = Object.freeze({
    ...deliveryStore,
    withCommittedResultRows(
      indexKey,
      resultDefinitionCid,
      authorize,
      suppliedFrameLimits,
      use,
      frameControl,
    ) {
      return deliveryStore.withCommittedResultRows(
        indexKey,
        resultDefinitionCid,
        authorize,
        suppliedFrameLimits,
        (metadata, _readRows) => use(
          Object.freeze({...metadata, rowCount: 0}),
          async _emit => undefined,
        ),
        frameControl,
      );
    },
  });
  let emptyFinishes = 0;
  const emptyDelivery = await deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-jsonl',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      async finish() {
        emptyFinishes++;
        return {confirmed: true};
      },
    },
  });
  assert.equal(emptyFinishes, 1);
  assert.equal(emptyDelivery.byteCount, 0);
  assert.equal(
    emptyDelivery.sha256,
    createHash('sha256').update('').digest('hex'),
  );
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-finish-failed',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      finish: () => Promise.reject(new Error('sink finish failed')),
    },
  }), {code: 'ResultDeliverySinkCompletionFailed'});
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    store: emptyStore,
    grant: emptyGrant,
    format: 'jsonl',
    attemptId: 'delivery-empty-finish-unknown',
    sink: {
      write: () => assert.fail('empty JSONL wrote bytes'),
      finish: () => ({confirmed: false}),
    },
  }), {code: 'ResultDeliverySinkCompletionUnknown'});
  for (const attemptId of [
    'delivery-empty-finish-failed',
    'delivery-empty-finish-unknown',
  ]) {
    const attempt = control.issueDeliveryAttempt(
      deliveryIndex,
      deliveryManifest,
      emptyGrant,
      {
        resultName: 'answer',
        format: 'jsonl',
        attemptId,
        requestedAt: '2026-09-18T01:00:00.000Z',
      },
      limits,
    );
    const record = await deliveryStore.latestDeliveryRecord(
      attempt.identity,
    );
    assert.equal(record.state, 'failed');
    assert.equal(record.result_delivery_receipt_cid, undefined);
  }
  const beforeReplay = await deliveryStore.lookupDeliveryAttempt({
    indexKey: deliveryBase.indexKey, principalId: 'principal-a',
    purpose: 'download', resultName: 'answer', attemptId: 'delivery-json',
  });
  const idempotentDelivery = await deliverPublishedResult({
    ...deliveryBase,
    store: jsonStore,
    now: () => '2026-09-18T01:00:01.000Z',
    format: 'json',
    attemptId: 'delivery-json',
    sink: {
      write: () => assert.fail('idempotent delivery wrote bytes'),
      finish: () => assert.fail('idempotent delivery finished sink'),
    },
  });
  assert.equal(idempotentDelivery.idempotent, true);
  assert.equal(idempotentDelivery.attempt.identity,
    beforeReplay.attempt.delivery_attempt_cid);
  assert.deepEqual(JSON.parse(idempotentDelivery.record.wire), beforeReplay.record);
  assert.deepEqual(JSON.parse(idempotentDelivery.receipt.wire),
    beforeReplay.hostReleaseReceipt);
  assert.equal(jsonReaders, 1);

  let sinkWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    format: 'json',
    attemptId: 'delivery-partial',
    sink: {
      async write(bytes) {
        sinkWrites++;
        if (sinkWrites === 1) {
          return {confirmedBytes: bytes.byteLength};
        }
        const failure = new Error('partial sink failure');
        failure.deliveryProgress = {
          confirmedBytes: 1,
          exposure: 'unknown_additional',
          possibleUnconfirmedMaxBytes: bytes.byteLength - 1,
        };
        throw failure;
      },
      async finish() { return {confirmed: true}; },
    },
  }), /ResultDeliverySinkWriteFailed/u);
  const partialAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    deliveryGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-partial',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  const partialRecord = await deliveryStore.latestDeliveryRecord(
    partialAttempt.identity,
  );
  assert.equal(partialRecord.state, 'failed');
  assert.equal(partialRecord.exposure, 'unknown_additional');
  assert.ok(partialRecord.confirmed_byte_count > 1);

  const revocationGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'revocation-check',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let authorizedWrites = 0;
  let exposedWrites = 0;
  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    grant: revocationGrant,
    format: 'json',
    attemptId: 'delivery-revoked',
    authorize(facts) {
      return facts.stage !== 'write' || ++authorizedWrites === 1;
    },
    sink: {
      async write(bytes) {
        exposedWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      async finish() { return {confirmed: true}; },
    },
  }), {code: 'ResultDeliveryDenied'});
  assert.equal(exposedWrites, 1);
  const revokedAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    revocationGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-revoked',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  assert.equal((await deliveryStore.latestDeliveryRecord(
    revokedAttempt.identity,
  )).state, 'failed');

  await assert.rejects(deliverPublishedResult({
    ...deliveryBase,
    format: 'json',
    attemptId: 'delivery-over-limit',
    sink: {
      write: () => assert.fail('exhausted grant wrote bytes'),
      finish: () => assert.fail('exhausted grant finished delivery'),
    },
  }), {code: 'DeliveryGrantUseLimit'});

  const recoveryGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'cleanup-recovery',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let failTerminalRecord = true;
  const recoveryStore = Object.freeze({
    ...deliveryStore,
    async appendDeliveryRecord(recordWire) {
      if (failTerminalRecord &&
          JSON.parse(recordWire).state === 'failed') {
        failTerminalRecord = false;
        const error = new Error('injected terminal record failure');
        error.code = 'EIO';
        throw error;
      }
      return deliveryStore.appendDeliveryRecord(recordWire);
    },
  });
  let recoveryFailure;
  try {
    await deliverPublishedResult({
      ...deliveryBase,
      store: recoveryStore,
      grant: recoveryGrant,
      format: 'json',
      attemptId: 'delivery-cleanup-retry',
      sink: {
        write: () => Promise.reject(new Error('sink unavailable')),
        finish: () => assert.fail('failed delivery finished sink'),
      },
    });
    assert.fail('delivery unexpectedly succeeded');
  } catch (error) {
    recoveryFailure = error;
  }
  assert.equal(recoveryFailure.code, 'ResultDeliveryFailed');
  assert.equal(recoveryFailure.cleanupPending, true);
  assert.equal((await recoveryFailure.cleanupHandle.retry()).pending, false);
  const recoveryAttempt = control.issueDeliveryAttempt(
    deliveryIndex,
    deliveryManifest,
    recoveryGrant,
    {
      resultName: 'answer',
      format: 'json',
      attemptId: 'delivery-cleanup-retry',
      requestedAt: '2026-09-18T01:00:00.000Z',
    },
    limits,
  );
  assert.equal((await deliveryStore.latestDeliveryRecord(
    recoveryAttempt.identity,
  )).state, 'failed');

  await t.test('concurrent cleanup retains the real Store owner until terminal durability is confirmed',
    async sub => {
      const directory = await mkdtemp(join(tmpdir(), 'actql-concurrent-delivery-cleanup-'));
      const deliveryStore = await openLocalPublicationStore({
        directory, storeAuthorityCid: cid('a'), capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: limits.maxWireBytes, maxObjects: 100,
        maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
      }, control);
      sub.after(async () => {
        await deliveryStore.close();
        await rm(directory, {recursive: true, force: true});
      });
      await deliveryStore.putSemantic(resultSchemaWire, resultSchemaCid);
      await deliveryStore.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
      const publication = await publishEffectFreeRun({...publicationOptions,
        store: deliveryStore,
        attempt: {...publicationOptions.attempt, attemptId: 'concurrent-cleanup-publication'},
      });
      const deliveryIndex = publication.index;
      const grant = control.issueResultReadGrant(deliveryIndex, deliveryManifest, {
        resultNames: ['answer'], formats: ['json'], principalId: 'principal-a',
        purpose: 'concurrent-cleanup-recovery', dataCeilingCid: cid('1'),
        maxBytes: 1024, maxUses: 1, expiresAt: '2026-09-19T00:00:00.000Z',
        authorizationContextCid: cid('2'), egressAdmissionCid: cid('3'),
      }, limits);
      const original = new Error('payload reader refused before exposure');
      const terminalFailure = new Error('terminal append unavailable');
      const terminalReplyLost = new Error('terminal append reply lost');
      let entered, release, retries = 0, payloadCalls = 0, sinkCalls = 0;
      const arrived = new Promise(resolve => { entered = resolve; });
      const retryGate = new Promise(resolve => { release = resolve; });
      const attempted = [];
      let terminalAvailable = false, loseTerminalReply = true;
      const retryStore = Object.freeze({...deliveryStore,
        async appendDeliveryRecord(wire) {
          attempted.push(wire);
          assert.equal(JSON.parse(wire).state, 'failed');
          if (!terminalAvailable) {
            if (attempted.length > 1) { retries++; entered(); await retryGate; }
            throw terminalFailure;
          }
          await deliveryStore.appendDeliveryRecord(wire);
          if (loseTerminalReply) { loseTerminalReply = false; throw terminalReplyLost; }
        },
        withCommittedResultRows() { payloadCalls++; throw original; },
      });
      let failure;
      await assert.rejects(deliverPublishedResult({...deliveryBase,
        store: retryStore, grant, format: 'json', attemptId: 'concurrent-cleanup',
        sink: {
          write() { sinkCalls++; assert.fail('cleanup must never resend bytes'); },
          finish() { sinkCalls++; assert.fail('cleanup must never finish the sink'); },
        },
      }), error => { failure = error; return error.code === 'ResultDeliveryFailed'; });
      const attemptCid = JSON.parse(attempted[0]).delivery_attempt_cid;
      const latest = () => deliveryStore.latestDeliveryRecord(attemptCid);
      assert.equal((await latest()).state, 'streaming');
      assert.deepEqual(failure.cleanupErrors, [terminalFailure]);
      const first = failure.cleanupHandle.retry();
      await arrived;
      const second = failure.cleanupHandle.retry();
      assert.equal(failure.cleanupHandle.status().pending, true);
      release();
      const [firstStatus, secondStatus] = await Promise.all([first, second]);
      assert.equal(first, second);
      assert.equal(firstStatus, secondStatus);
      assert.equal(firstStatus.pending, true);
      assert.deepEqual(firstStatus.errors, [terminalFailure, terminalFailure]);
      assert.equal(retries, 1);
      assert.equal((await latest()).state, 'streaming');
      terminalAvailable = true;
      assert.equal((await failure.cleanupHandle.retry()).pending, true);
      assert.equal((await latest()).state, 'failed');
      assert.equal(failure.cleanupPending, true, 'a lost persistence reply remains unresolved');
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(failure.cleanupPending, false);
      assert.equal(failure.cause, original);
      assert.equal(failure.primaryFailure, original);
      assert.deepEqual(failure.cleanupErrors, [terminalFailure, terminalReplyLost],
        'bounded diagnostics retain the first and latest original failures');
      assert.equal(attempted.length, 4);
      for (const wire of attempted) assert.equal(wire, attempted[0]);
      assert.equal((await latest()).delivery_record_cid,
        JSON.parse(attempted[0]).delivery_record_cid);
      await failure.cleanupHandle.retry();
      assert.equal(attempted.length, 4);
      assert.equal(payloadCalls, 1, 'cleanup never reacquires the original reader');
      assert.equal(sinkCalls, 0);

    });

  const durabilityGrant = control.issueResultReadGrant(
    deliveryIndex,
    deliveryManifest,
    {
      resultNames: ['answer'],
      formats: ['json'],
      principalId: 'principal-a',
      purpose: 'durability-recovery',
      dataCeilingCid: cid('1'),
      maxBytes: 1024,
      maxUses: 1,
      expiresAt: '2026-09-19T00:00:00.000Z',
      authorizationContextCid: cid('2'),
      egressAdmissionCid: cid('3'),
    },
    limits,
  );
  let failSucceededDurability = true;
  const durabilityStore = Object.freeze({
    ...deliveryStore,
    async appendDeliveryCompletion(attempt, receipt, record) {
      const result = await deliveryStore.appendDeliveryCompletion(attempt, receipt, record);
      if (failSucceededDurability &&
          JSON.parse(record.wire).state === 'succeeded') {
        failSucceededDurability = false;
        const error = new Error('injected delivery record sync failure');
        error.code = 'EIO';
        throw error;
      }
      return result;
    },
  });
  let durabilityWrites = 0;
  let durabilityFinishes = 0;
  let durabilityFailure;
  try {
    await deliverPublishedResult({
      ...deliveryBase,
      store: durabilityStore,
      grant: durabilityGrant,
      format: 'json',
      attemptId: 'delivery-durability-retry',
      sink: {
        async write(bytes) {
          durabilityWrites++;
          return {confirmedBytes: bytes.byteLength};
        },
        async finish() {
          durabilityFinishes++;
          return {confirmed: true};
        },
      },
    });
    assert.fail('delivery durability failure was accepted');
  } catch (error) {
    durabilityFailure = error;
  }
  assert.equal(
    durabilityFailure.code,
    'ResultDeliveryDurabilityPending',
  );
  assert.equal(durabilityFailure.cleanupPending, true);
  assert.equal(durabilityWrites > 0, true);
  assert.equal(durabilityFinishes, 1);
  assert.equal(
    (await durabilityFailure.cleanupHandle.retry()).pending,
    false,
  );
  const durabilityRetry = await deliverPublishedResult({
    ...deliveryBase,
    store: durabilityStore,
    grant: durabilityGrant,
    format: 'json',
    attemptId: 'delivery-durability-retry',
    sink: {
      write: () => assert.fail('durability retry repeated delivery'),
      finish: () => assert.fail('durability retry repeated completion'),
    },
  });
  assert.equal(durabilityRetry.idempotent, true);
  assert.equal(durabilityFinishes, 1);

  accessTime = '2026-09-18T01:30:00.000Z';
  const expiredBeforeExtension = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(expiredBeforeExtension.result_available, false);
  assert.equal(
    expiredBeforeExtension.result_availability.answer.reason,
    'retention_expired',
  );
  const deniedExtensionService = installResultRetentionExtensionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionExtensionAuthority({
      authorizeResultExtension: () => false,
    }),
    now: () => accessTime,
    limits,
  });
  await assert.rejects(extendResultRetention(deniedExtensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  }), {code: 'ResultRetentionExtensionDenied'});
  const extensionStages = [];
  const extensionService = installResultRetentionExtensionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionExtensionAuthority({
      authorizeResultExtension(facts) {
        extensionStages.push(facts.stage);
        return true;
      },
    }),
    now: () => accessTime,
    limits,
  });
  await assert.rejects(extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T02:00:00.001Z',
    reason: 'forbidden_extension',
  }), {code: 'ResultRetentionExtensionNotAllowed'});
  const extended = await extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  });
  assert.equal(extended.idempotent, false);
  assert.deepEqual(extensionStages, ['request', 'request', 'extend']);
  const extensionRetry = await extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:45:00.000Z',
    reason: 'authorized_download',
  });
  assert.equal(extensionRetry.idempotent, true);
  const availableAfterExtension = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(availableAfterExtension.result_available, true);
  assert.equal(
    availableAfterExtension.result_availability.answer.reason,
    'confirmed_present',
  );
  const extendedBytes = [];
  const extendedDelivery = await deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'extended-download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-after-extension',
    },
    {
      write(bytes) {
        extendedBytes.push(Buffer.from(bytes));
        return {confirmedBytes: bytes.byteLength};
      },
      finish() { return {confirmed: true}; },
    },
  );
  assert.equal(extendedDelivery.idempotent, false);
  assert.ok(Buffer.concat(extendedBytes).byteLength > 0);

  let unavailableSinkWrites = 0;
  advanceAccessTimeAt = '2026-09-18T01:45:00.001Z';
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'authorization-crosses-retention',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorization-crosses-retention',
    },
    {
      write(bytes) {
        unavailableSinkWrites++;
        return {confirmedBytes: bytes.byteLength};
      },
      finish() { return {confirmed: true}; },
    },
  ), {code: 'ResultDeliveryDenied'});
  advanceAccessTimeAt = undefined;
  assert.equal(unavailableSinkWrites, 0);

  const retentionAuthority = installResultRetentionAuthority({
    authorizeResultDeletion: () => true,
  });
  const notDueRetentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: retentionAuthority,
    now: () => '2026-09-18T01:45:00.001Z',
    limits,
  });
  await assert.rejects(retireExpiredResult(notDueRetentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  }), {code: 'ResultDeletionNotDue'});
  const deniedRetentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: installResultRetentionAuthority({
      authorizeResultDeletion: () => false,
    }),
    now: () => '2026-09-18T02:00:00.000Z',
    limits,
  });
  await assert.rejects(retireExpiredResult(deniedRetentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  }), {code: 'ResultRetentionDenied'});
  const retentionService = installResultRetentionService({
    store: deliveryStore,
    control,
    authority: retentionAuthority,
    now: () => '2026-09-18T02:00:00.000Z',
    limits,
  });
  const retired = await retireExpiredResult(retentionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    reason: 'retention_deadline',
  });
  assert.equal(retired.cleanupPending, false);
  accessTime = '2026-09-18T02:00:00.000Z';
  await assert.rejects(extendResultRetention(extensionService, {
    indexKey: stateRequest.indexKey,
    resultName: 'answer',
    availableUntil: '2026-09-18T01:50:00.000Z',
    reason: 'too_late',
  }), {code: 'ResultRetentionExtensionUnavailable'});
  requestAccessAllowed = false;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'denied-deleted',
    },
    {
      write: () => assert.fail('denied deleted Result exposed bytes'),
      finish: () => assert.fail('denied deleted Result finished delivery'),
    },
  ), {code: 'ResultAccessDenied'});
  requestAccessAllowed = true;
  await assert.rejects(deliverAuthorizedResult(
    accessService,
    {
      indexKey: stateRequest.indexKey,
      principalId: 'principal-a',
      purpose: 'download',
      resultName: 'answer',
      format: 'json',
      attemptId: 'authorized-after-deletion',
    },
    {
      write: () => assert.fail('deleted Result exposed bytes'),
      finish: () => assert.fail('deleted Result finished delivery'),
    },
  ), {code: 'ResultUnavailable'});
  const deletedState = await inspectAuthorizedRunState(
    stateService, stateRequest,
  );
  assert.equal(deletedState.status, 'succeeded');
  assert.equal(deletedState.result_available, false);
  assert.deepEqual(deletedState.next_action, {kind: 'none'});
  assert.equal(
    deletedState.result_availability.answer.reason,
    'deleted',
  );
  const metadataAuthority = installMetadataRetentionAuthority({
    authorizeMetadataDeletion: () => true,
  });
  const earlyMetadataService = installMetadataRetentionService({
    store: deliveryStore,
    control,
    authority: metadataAuthority,
    now: () => '2026-09-18T03:59:59.999Z',
    limits,
  });
  await assert.rejects(retireExpiredPublicationMetadata(
    earlyMetadataService,
    {indexKey: stateRequest.indexKey, reason: 'metadata_deadline'},
  ), {code: 'MetadataDeletionNotDue'});
  const metadataStages = [];
  const metadataService = installMetadataRetentionService({
    store: deliveryStore,
    control,
    authority: installMetadataRetentionAuthority({
      authorizeMetadataDeletion(facts) {
        metadataStages.push(facts.stage);
        return true;
      },
    }),
    now: () => '2026-09-18T04:00:00.000Z',
    limits,
  });
  const retiredMetadata = await retireExpiredPublicationMetadata(
    metadataService,
    {indexKey: stateRequest.indexKey, reason: 'metadata_deadline'},
  );
  assert.equal(retiredMetadata.cleanupPending, false);
  assert.deepEqual(metadataStages, ['request', 'delete']);
  assert.equal(await deliveryStore.confirmCommittedIndex(
    stateRequest.indexKey,
  ), undefined);

  const lostDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-lost-response-',
  ));
  retainedDirectories.push(lostDirectory);
  const lostBase = await openLocalPublicationStore({
    directory: lostDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await lostBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await lostBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  retainedStores.push(lostBase);
  let loseCommitResponse = true;
  const lostStore = Object.freeze({
    ...lostBase,
    async commitIndex(...arguments_) {
      const value = await lostBase.commitIndex(...arguments_);
      if (loseCommitResponse) {
        loseCommitResponse = false;
        throw new Error('simulated lost commit response');
      }
      return value;
    },
  });
  const lost = await publishEffectFreeRun({
    ...publicationOptions,
    store: lostStore,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'lost-response-attempt',
    },
  });
  assert.equal(lost.state, 'succeeded');
  assert.equal(lost.committed, false);
  assert.equal(lost.idempotent, true);
  assert.equal((await lostBase.latestRecord(lost.attempt.identity)).state,
    'succeeded');

  const raceDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-race-',
  ));
  retainedDirectories.push(raceDirectory);
  const raceBase = await openLocalPublicationStore({
    directory: raceDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await raceBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await raceBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  retainedStores.push(raceBase);
  let commitArrivals = 0;
  let releaseCommits;
  const commitsReady = new Promise(resolve => { releaseCommits = resolve; });
  let finalizationArrivals = 0;
  let releaseFinalizations;
  const finalizationsReady = new Promise(resolve => { releaseFinalizations = resolve; });
  let releaseFirstFinalization;
  const firstFinalization = new Promise(resolve => { releaseFirstFinalization = resolve; });
  let staleFinalizationCode;
  const raceStore = Object.freeze({
    ...raceBase,
    async commitIndex(...arguments_) {
      commitArrivals++;
      if (commitArrivals === 2) releaseCommits();
      await commitsReady;
      return raceBase.commitIndex(...arguments_);
    },
    async appendRecord(wire, options) {
      if (JSON.parse(wire).state !== 'succeeded') {
        return raceBase.appendRecord(wire, options);
      }
      // Both callers issue their next record before either physical append.
      // The second then observes the first durable append, not a link race.
      const arrival = ++finalizationArrivals;
      if (arrival === 2) releaseFinalizations();
      await finalizationsReady;
      if (arrival === 1) {
        try { return await raceBase.appendRecord(wire, options); }
        finally { releaseFirstFinalization(); }
      }
      await firstFinalization;
      try { return await raceBase.appendRecord(wire, options); }
      catch (error) { staleFinalizationCode = error.code; throw error; }
    },
  });
  const raceAttempts = ['race-a', 'race-b'].map(attemptId => ({
    ...publicationOptions.attempt,
    attemptId,
  }));
  const raced = await Promise.all(raceAttempts.map(attempt =>
    publishEffectFreeRun({...publicationOptions, store: raceStore, attempt})));
  assert.equal(raced.filter(value => value.committed).length, 1);
  assert.equal(raced.filter(value => value.idempotent).length, 1);
  assert.equal(raced[0].index.identity, raced[1].index.identity);
  assert.equal(raced[0].attempt.identity, raced[1].attempt.identity);
  assert.equal(finalizationArrivals, 2);
  assert.equal(staleFinalizationCode, 'InvalidPublicationRecordTransition');
  const raceContracts = raceAttempts.map(attempt =>
    control.issuePublicationAttempt(request, run, attempt, limits));
  const raceStates = await Promise.all(raceContracts.map(attempt =>
    raceBase.latestRecord(attempt.identity)));
  assert.deepEqual(
    raceStates.map(value => value.state).sort(),
    ['cancelled', 'succeeded'],
  );
  // The winning original is native metadata; no legacy inventory file is made.
  assert.equal((await readdir(join(raceDirectory, 'metadata-inventories'))).length, 0);
  const raceMetadata = new DatabaseSync(join(raceDirectory, 'delivery-attempts.sqlite3'), {readOnly: true});
  try {
    assert.equal(raceMetadata.prepare('SELECT count(*) AS n FROM native_publication_inventories').get().n, 1);
    assert.equal(raceMetadata.prepare('SELECT count(*) AS n FROM native_publication_indexes').get().n, 1);
  } finally { raceMetadata.close(); }
  const raceIndexes = raceContracts.map(raceAttempt =>
    control.issuePublicIndexEntry({
      runDefinition: run,
      invocation: invoked,
      manifest,
      receipt,
      capturedRun: captured,
      durableBindings: [binding],
      request,
      attempt: raceAttempt,
    }, '2026-09-18T00:00:07.000Z', limits));
  const losingIndex = raceIndexes.find(candidate =>
    JSON.parse(candidate.wire).publication_attempt_cid !==
      raced[0].attempt.identity);
  await assert.rejects(
    raceBase.readPublicationContract(
      losingIndex.identity, 'public_index_entry',
    ),
    error => error?.code === 'PublicationContractMissing',
  );

  const refusedDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-finalization-refusal-',
  ));
  retainedDirectories.push(refusedDirectory);
  const refusedBase = await openLocalPublicationStore({
    directory: refusedDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  retainedStores.push(refusedBase);
  await refusedBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await refusedBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  const refusal = Object.assign(new Error('finalization not physically appended'), {
    code: 'InvalidPublicationRecordTransition',
  });
  const foreignFinished = await raceBase.latestRecordContract(raced[0].attempt.identity);
  let refuseWithForeignRecord = false;
  let finalizationRefused = false;
  const refusedStore = Object.freeze({
    ...refusedBase,
    async latestRecordContract(attemptCid) {
      if (refuseWithForeignRecord && finalizationRefused) return foreignFinished;
      return refusedBase.latestRecordContract(attemptCid);
    },
    async appendRecord(wire, options) {
      if (JSON.parse(wire).state === 'succeeded') {
        finalizationRefused = true;
        throw refusal;
      }
      return refusedBase.appendRecord(wire, options);
    },
  });
  const refusedOptions = {...publicationOptions,
    attempt: {...publicationOptions.attempt, attemptId: 'refused-finalization'}};
  await assert.rejects(publishEffectFreeRun({...refusedOptions, store: refusedStore}),
    error => error === refusal);
  // A terminal success for another committed index cannot discharge this
  // failure. Removing the exact-index check makes this negative case succeed.
  refuseWithForeignRecord = true;
  finalizationRefused = false;
  await assert.rejects(publishEffectFreeRun({...refusedOptions, store: refusedStore}),
    error => error === refusal);
  const refusedAttempt = control.issuePublicationAttempt(request, run,
    refusedOptions.attempt, limits);
  assert.equal((await refusedBase.latestRecord(refusedAttempt.identity)).state,
    'committing');
  // A real pending finalization is not mistaken for durable success. Replay
  // reconciles the existing committed index through the unchanged Store owner.
  const recoveredRefusal = await publishEffectFreeRun({...refusedOptions,
    store: refusedBase});
  assert.equal(recoveredRefusal.state, 'succeeded');
  assert.equal(recoveredRefusal.idempotent, true);
  assert.equal(recoveredRefusal.attempt.identity, refusedAttempt.identity);

  const unknownDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-unknown-',
  ));
  retainedDirectories.push(unknownDirectory);
  const unknownBase = await openLocalPublicationStore({
    directory: unknownDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await unknownBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await unknownBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  retainedStores.push(unknownBase);
  let indexInspections = 0;
  const unknownStore = Object.freeze({
    ...unknownBase,
    async confirmCommittedIndex(...arguments_) {
      indexInspections++;
      if (indexInspections > 1) throw new Error('index unavailable');
      return unknownBase.confirmCommittedIndex(...arguments_);
    },
    async commitIndex() { throw new Error('commit outcome unavailable'); },
  });
  const unknownAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'unknown-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: unknownStore,
    attempt: unknownAttempt,
  }), error => error?.code === 'RunPublicationUnknown' &&
    error.publicationState === 'publication_unknown');
  const unknownContract = control.issuePublicationAttempt(
    request, run, unknownAttempt, limits,
  );
  assert.equal((await unknownBase.latestRecord(unknownContract.identity)).state,
    'publication_unknown');
  const reconciled = await publishEffectFreeRun({
    ...publicationOptions,
    store: unknownBase,
    attempt: {
      ...publicationOptions.attempt,
      attemptId: 'reconciled-attempt',
    },
  });
  assert.equal(reconciled.state, 'succeeded');

  const cancelledDirectory = await mkdtemp(join(
    tmpdir(), 'actql-publication-cancelled-',
  ));
  retainedDirectories.push(cancelledDirectory);
  const cancelledBase = await openLocalPublicationStore({
    directory: cancelledDirectory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: limits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, control);
  await cancelledBase.putSemantic(resultSchemaWire, resultSchemaCid);
  await cancelledBase.putBytes(Buffer.from(payloadWire, 'utf8'), physicalCid);
  retainedStores.push(cancelledBase);
  const cancellation = new AbortController();
  const cancelledStore = Object.freeze({
    ...cancelledBase,
    async beginPublicationAttemptWithRecords(...args) {
      const value = await cancelledBase.beginPublicationAttemptWithRecords(...args);
      cancellation.abort();
      return value;
    },
    async appendInitialPublicationRecords(records) {
      const value = await cancelledBase.appendInitialPublicationRecords(records);
      cancellation.abort();
      return value;
    },
    async appendRecord(wire, options) {
      const value = await cancelledBase.appendRecord(wire, options);
      if (value.state === 'preparing') cancellation.abort();
      return value;
    },
  });
  const cancelledAttempt = {
    ...publicationOptions.attempt,
    attemptId: 'cancelled-attempt',
  };
  await assert.rejects(publishEffectFreeRun({
    ...publicationOptions,
    store: cancelledStore,
    attempt: cancelledAttempt,
    signal: cancellation.signal,
  }), {name: 'AbortError'});
  const cancelledContract = control.issuePublicationAttempt(
    request, run, cancelledAttempt, limits,
  );
  assert.equal((await cancelledBase.latestRecord(
    cancelledContract.identity,
  )).state, 'cancelled');
  });
});

test('local durable Store accepts only MoonBit-admitted contract wire',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-runtime-',
    ));
    let store;
    t.after(async () => {
      try { await store?.close(); }
      finally { await rm(directory, {recursive: true, force: true}); }
    });
    const control = runtimeCore(moon).publicationControl;
    store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cid('a'),
      capacityBytes: 1024 * 1024,
      maxObjectBytes: limits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, control);
    const sealed = invocation(control);
    const stored = await store.putPublicationContract(
      sealed.name, sealed.wire,
    );
    assert.equal(stored.semanticCid, sealed.identity);
    assert.deepEqual(
      await store.readJsonObject(sealed.identity, sealed.name),
      JSON.parse(sealed.wire),
    );
  });

test('complete publication reclaims prepared payloads after a later export fails',
  async () => {
    const definition = Object.freeze({
      name: 'result_definition', identity: cid('1'), wire: '{}',
    });
    const runDefinition = Object.freeze({
      name: 'run_definition', identity: cid('2'), wire: '{}',
    });
    const invoked = Object.freeze({
      name: 'run_invocation', identity: cid('3'), wire: '{}',
    });
    const retention = Object.freeze({
      name: 'result_retention_policy', identity: cid('4'), wire: '{}',
    });
    let pending = true;
    let releases = 0;
    const prepared = Object.freeze({
      status: () => Object.freeze({pending, errors: Object.freeze([])}),
      async release() { releases++; pending = false; return true; },
      async retry() { pending = false; return this.status(); },
    });
    const publication = Object.freeze({
      artifact: definition,
      derivation: definition,
      ordering: definition,
      durableBinding: definition,
      snapshot: Object.freeze({}),
    });
    const occurrences = Object.freeze([0, 1].map((_, index) =>
      Object.freeze({
        name: `result-${index}`,
        task: index + 1,
        definitionContract: definition,
      })));
    const execution = Object.freeze({
      status: 'host-tasks-completed',
      resultInventory: occurrences,
      publicationInventory: Object.freeze({occurrences}),
      async storePublicationResult(index) {
        if (index === 1) throw new Error('second export failed');
        return Object.freeze({
          occurrence: Object.freeze({
            name: 'result-0', task: 1, definition,
          }),
          publication,
          prepared,
        });
      },
    });
    const progress = runtimeCore(moon).publicationControl;
    const control = Object.freeze({
      publicationPreparedReleaseAction:
        progress.publicationPreparedReleaseAction,
      publicationCleanupOwnerAction:
        progress.publicationCleanupOwnerAction,
      issueResultManifest() { assert.fail('Manifest must not be issued'); },
      issueEffectFreeRunReceipt() { assert.fail('Receipt must not be issued'); },
      issueEffectFreeCapturedRun() {
        assert.fail('Captured Run must not be issued');
      },
    });
    await assert.rejects(publishCompletedEffectFreeRun({
      execution,
      store: Object.freeze({}),
      control,
      admission: Object.freeze({}),
      runDefinition,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: [0, 1].map(() => ({
        retention,
        evidenceContext: Object.freeze({}),
      })),
      receiptEvidence: {
        bindings: [], sourceEvidence: [], modelEvidence: [],
        barrierAttemptReceiptCids: [],
      },
      captureEvidence: {
        pendingSourceStateAdvances: [], modelEvidence: [],
      },
      request: Object.freeze({}),
      attempt: Object.freeze({}),
      outputLimits: Object.freeze({}),
      contractLimits: Object.freeze({}),
      now: () => '2026-09-18T00:00:00.000Z',
      signal: undefined,
    }), /second export failed/u);
    assert.equal(releases, 1);
    assert.equal(pending, false);
  });

test('complete publication composes every unresolved cleanup owner',
  async () => {
    const definition = Object.freeze({
      name: 'result_definition', identity: cid('1'), wire: '{}',
    });
    const runDefinition = Object.freeze({
      name: 'run_definition', identity: cid('2'), wire: '{}',
    });
    const invoked = Object.freeze({
      name: 'run_invocation', identity: cid('3'), wire: '{}',
    });
    const retention = Object.freeze({
      name: 'result_retention_policy', identity: cid('4'), wire: '{}',
    });
    let preparedPending = true;
    let primaryPending = true;
    let allowPrepared = false;
    let allowPrimary = false;
    let preparedRetries = 0;
    let primaryRetries = 0;
    const prepared = Object.freeze({
      status: () => Object.freeze({
        pending: preparedPending, errors: Object.freeze([]),
      }),
      async release() { throw new Error('prepared release failed'); },
      async retry() {
        preparedRetries++;
        if (allowPrepared) preparedPending = false;
        return this.status();
      },
    });
    const primaryCleanup = Object.freeze({
      status: () => Object.freeze({
        pending: primaryPending, errors: Object.freeze([]),
      }),
      async retry() {
        primaryRetries++;
        if (allowPrimary) primaryPending = false;
        return this.status();
      },
    });
    const primary = Object.freeze({
      code: 'SecondExportFailed',
      cleanupPending: true,
      cleanupHandle: primaryCleanup,
    });
    const publication = Object.freeze({
      artifact: definition,
      derivation: definition,
      ordering: definition,
      durableBinding: definition,
      snapshot: Object.freeze({}),
    });
    const occurrences = Object.freeze([0, 1].map((_, index) =>
      Object.freeze({
        name: `result-${index}`,
        task: index + 1,
        definitionContract: definition,
      })));
    const execution = Object.freeze({
      status: 'host-tasks-completed',
      resultInventory: occurrences,
      publicationInventory: Object.freeze({occurrences}),
      async storePublicationResult(index) {
        if (index === 1) throw primary;
        return Object.freeze({
          occurrence: Object.freeze({
            name: 'result-0', task: 1, definition,
          }),
          publication,
          prepared,
        });
      },
    });
    const progress = runtimeCore(moon).publicationControl;
    const control = Object.freeze({
      publicationPreparedReleaseAction:
        progress.publicationPreparedReleaseAction,
      publicationCleanupOwnerAction:
        progress.publicationCleanupOwnerAction,
      issueResultManifest() { assert.fail('Manifest must not be issued'); },
      issueEffectFreeRunReceipt() { assert.fail('Receipt must not be issued'); },
      issueEffectFreeCapturedRun() {
        assert.fail('Captured Run must not be issued');
      },
    });
    let failure;
    await assert.rejects(publishCompletedEffectFreeRun({
      execution,
      store: Object.freeze({}),
      control,
      admission: Object.freeze({}),
      runDefinition,
      invocation: invoked,
      observation: Object.freeze({}),
      normalizationJournal: Object.freeze({}),
      authoringContext: Object.freeze({}),
      results: [0, 1].map(() => ({
        retention,
        evidenceContext: Object.freeze({}),
      })),
      receiptEvidence: {
        bindings: [], sourceEvidence: [], modelEvidence: [],
        barrierAttemptReceiptCids: [],
      },
      captureEvidence: {
        pendingSourceStateAdvances: [], modelEvidence: [],
      },
      request: Object.freeze({}),
      attempt: Object.freeze({}),
      outputLimits: Object.freeze({}),
      contractLimits: Object.freeze({}),
      now: () => '2026-09-18T00:00:00.000Z',
      signal: undefined,
    }), error => {
      failure = error;
      return error?.code === 'SecondExportFailed' &&
        error.primaryFailure === primary &&
        error.cleanupHandle?.status().pending === true;
    });
    allowPrepared = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(preparedPending, false);
    assert.equal(primaryPending, true);
    allowPrimary = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(preparedRetries, 1);
    assert.equal(primaryRetries, 2);
  });


// This adapter-only control isolates physical custody metadata classification.
// Contract admission is stubbed; it does not claim a Captured Run chain, Store
// custody or recovery authority. Actual Table/import inventory admission is
// covered by the existing real Common Host controls and installed campaign.
test('portable dependency payload custody retains Table and Result roots with exact coverage', () => {
  const metadataMoon = {...moon,
    strategyPublicationAdmit(name, wire) { return {$tag: 1, _0: {name, wire}}; },
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'captured_run_cid',
    strategyPublicationContractIdentity: () => cid('f'),
    strategyPublicationContractJson: value => value.wire};
  const control = runtimeCore(metadataMoon).publicationControl;
  const capture = inventory => control.admit('captured_run', JSON.stringify({
    effect_context: {effect_dependency_inventory: inventory}}), limits);
  const table = {artifact_cid: cid('a'), physical_cid: cid('c'), byte_count: 13};
  const result = {artifact_cid: cid('b'), physical_cid: cid('d'), byte_count: 21};
  const inventory = [{kind: 'table_input_artifact', cid: table.artifact_cid},
    {kind: 'result_artifact', cid: result.artifact_cid},
    {kind: 'relation_schema', cid: cid('e')}];
  const captured = capture(inventory);
  const bind = values => control.capturedEffectDependencyPayloadBindings(captured, values);
  assert.deepEqual(bind([table, result]), [table, result]);
  assert.deepEqual(bind([result, table]), [result, table]);
  assert.deepEqual(control.capturedEffectDependencyPayloadBindings(capture([]), []), []);
  assert.deepEqual(control.capturedEffectDependencyPayloadBindings(
    capture([{kind: 'result_artifact', cid: result.artifact_cid}]), [result]), [result]);
  assert.deepEqual(control.capturedEffectDependencyPayloadBindings(
    capture([{kind: 'table_input_artifact', cid: table.artifact_cid}]), [table]), [table]);
  for (const omitted of [[table], [result], []]) {
    assert.throws(() => bind(omitted), /IncompleteEffectDependencyPayloadBindings/);
  }
  for (const changed of [[table, result, result], [{...table, artifact_cid: cid('e')}, result],
    [{...table, extra: true}, result], [{...table, byte_count: -1}, result],
    [{...table, physical_cid: 'not-a-cid'}, result]]) {
    assert.throws(() => bind(changed), /InvalidEffectDependencyPayloadBindings/);
  }
  assert.throws(() => control.capturedEffectDependencyPayloadBindings({...captured}, [table, result]),
    /Foreign publication contract/);
  assert(Object.isFrozen(bind([table, result])));
  assert(bind([table, result]).every(Object.isFrozen));
});
