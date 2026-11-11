import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

test('durable preparation restores its exact semantic target and refuses retargeting', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-target-'));
  const path = join(directory, 'index.sqlite3');
  const options = {create: true, maxEntries: 2, maxWireBytes: 4096};
  const original = {cid:'sha256:'+'1'.repeat(64), byte_count:13, device:'1', inode:'2',
    semantic_cid:'sha256:'+'2'.repeat(64)};
  let index = await openDeliveryAttemptIndex(path, options);
  t.after(async () => {index.finishPhysicalPreparations([original]); index.close(); await rm(directory, {recursive:true});});
  index.migratePhysicalObjects([]); index.migrate([]);
  index.stagePhysicalObjects([original]); index.close();
  index = await openDeliveryAttemptIndex(path, {...options, create:false});
  index.beginPhysicalObjectLifetime();
  assert.deepEqual(index.pendingPhysicalObject(original), original);
  assert.throws(() => index.stagePhysicalObjects([{...original, semantic_cid:'sha256:'+'3'.repeat(64)}]),
    {code:'PublicationObjectAccountingMismatch'});
  index.recordPhysicalObjects([original], {retainPreparations:true});
  assert.deepEqual(index.pendingPhysicalObjects(), [original]);
  index.recordPhysicalObjects([original]);
  assert.deepEqual(index.pendingPhysicalObjects(), []);
});

test('semantic batch preparation remains durable until its own alias settlement', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-native-preparation-'));
  const path = join(directory, 'index.sqlite3');
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  const index = await openDeliveryAttemptIndex(path,
    {create: true, maxEntries: 2, maxWireBytes: 4096});
  t.after(async () => {
    index.finishPhysicalPreparations([original]);
    index.close();
    await rm(directory, {recursive: true});
  });
  index.migratePhysicalObjects([]);
  index.migrate([]);
  index.beginPhysicalObjectLifetime();
  const stored = () => {
    const reader = new DatabaseSync(path, {readOnly: true});
    try { return reader.prepare('SELECT cid,byte_count,device,inode FROM physical_object_preparations').all().map(row => ({...row})); }
    finally { reader.close(); }
  };
  index.stagePhysicalObjects([original], {durable: true});
  assert.deepEqual(stored(), [original], 'a quota dirty bit alone cannot recover an unpublished semantic allocation');
  index.recordPhysicalObjects([original], {retainPreparations: true});
  assert.deepEqual(stored(), [original], 'physical directory ACK does not settle the later alias duty');
  assert.deepEqual(index.pendingPhysicalObjects(), [original]);
  assert.equal(index.physicalObjectUsage().bytes, 13);
  index.finishPhysicalPreparations([original]);
  assert.deepEqual(stored(), []);
});

test('independent physical adoption settles the same durable preparation without charging twice', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-native-adoption-'));
  const path = join(directory, 'index.sqlite3');
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  const index = await openDeliveryAttemptIndex(path, {create: true, maxEntries: 2, maxWireBytes: 4096});
  t.after(async () => {index.finishPhysicalPreparations([original]); index.close(); await rm(directory, {recursive: true});});
  index.migratePhysicalObjects([]); index.migrate([]); index.beginPhysicalObjectLifetime();
  index.stagePhysicalObjects([original], {durable: true});
  index.recordPhysicalObjects([original], {retainPreparations: true});
  index.recordPhysicalObjects([original]);
  assert.deepEqual(index.pendingPhysicalObjects(), []);
  assert.equal(index.physicalObjectUsage().bytes, 13);
  const reader = new DatabaseSync(path, {readOnly: true});
  try { assert.deepEqual(reader.prepare('SELECT * FROM physical_object_preparations').all(), []); }
  finally { reader.close(); }
});

test('a rejected stale physical generation does not settle its pending preparation', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-native-stale-'));
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  const successor = {...original, inode: '3'};
  const index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, maxEntries: 2, maxWireBytes: 4096});
  t.after(async () => {index.finishPhysicalPreparations([original]); index.close(); await rm(directory, {recursive: true});});
  index.migratePhysicalObjects([]); index.migrate([]); index.beginPhysicalObjectLifetime();
  index.stagePhysicalObjects([original], {durable: true});
  index.recordPhysicalObjects([successor], {retainPreparations: true});
  assert.throws(() => index.recordPhysicalObjects([original]), {code: 'PublicationObjectAccountingMismatch'});
  assert.deepEqual(index.pendingPhysicalObjects(), [original]);
  assert.deepEqual(index.physicalObject(original.cid), successor);
});

test('selected prior physical originals exclude new and retired-then-restored lifetime generations', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-prior-physical-generation-'));
  const path = join(directory, 'index.sqlite3');
  const options = {maxEntries: 4, maxWireBytes: 4096};
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  const untouched = {...original, cid: 'sha256:' + '2'.repeat(64), inode: '3'};
  const fresh = {...original, cid: 'sha256:' + '3'.repeat(64), inode: '4'};
  let index = await openDeliveryAttemptIndex(path, {...options, create: true});
  t.after(async () => {index.close(); await rm(directory, {recursive: true});});
  index.migratePhysicalObjects([original, untouched]); index.migrate([]);
  assert.equal(index.physicalObject(original.cid, {priorLifetime: true}), undefined);
  index.close();
  index = await openDeliveryAttemptIndex(path, options);
  assert.deepEqual(index.physicalObject(original.cid, {priorLifetime: true}), original);
  index.beginPhysicalObjectLifetime();
  index.recordPhysicalObjects([fresh]);
  assert.equal(index.physicalObject(fresh.cid, {priorLifetime: true}), undefined);
  index.removePhysicalObjects([original]);
  index.recordPhysicalObjects([original]);
  assert.deepEqual(index.physicalObject(original.cid), original);
  assert.equal(index.physicalObject(original.cid, {priorLifetime: true}), undefined,
    'restoring equal DATA cannot restore the prior closed allocation generation');
  assert.deepEqual(index.physicalObject(untouched.cid, {priorLifetime: true}), untouched,
    'unrelated current changes do not erase the untouched opening original');
});

test('quota recovery preserves the original pending preparation for the next owned lifetime', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-native-recovery-'));
  const path = join(directory, 'index.sqlite3');
  const options = {create: false, maxEntries: 2, maxWireBytes: 4096};
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  let index = await openDeliveryAttemptIndex(path, {...options, create: true});
  t.after(async () => {index.finishPhysicalPreparations([original]); index.close(); await rm(directory, {recursive: true});});
  index.migratePhysicalObjects([]); index.migrate([]);
  index.stagePhysicalObjects([original]); index.close();
  // Explicit metadata fixture for an unsealed prior lifetime. The Store's
  // physical census and directory ACK remain separate original inputs.
  const marker = new DatabaseSync(path);
  try { marker.exec('PRAGMA user_version=1'); } finally { marker.close(); }
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.physicalObjectRecoveryRequired(), true);
  index.recoverPhysicalObjects([original]);
  assert.deepEqual(index.pendingPhysicalObjects(), [original], 'a quota census is not semantic adoption');
  index.beginPhysicalObjectLifetime();
  assert.deepEqual(index.pendingPhysicalObjects(), [original]);
  index.finishPhysicalPreparations([original]);
  assert.deepEqual(index.pendingPhysicalObjects(), []);
});

for (const kind of ['stage', 'finish']) for (const afterCommit of [false, true]) {
test(`durable lifetime preparation ${kind} retains ${afterCommit ? 'committed' : 'rolled-back'} Unknown original`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-native-unknown-'));
  let index, armed = false, lost = false;
  const original = {cid: 'sha256:' + '1'.repeat(64), byte_count: 13, device: '1', inode: '2'};
  t.after(async () => {index?.finishPhysicalPreparations([original]); index?.close(); await rm(directory, {recursive: true});});
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && !lost && sql === 'COMMIT') {
      lost = true;
      if (afterCommit) Reflect.apply(exec, this, [sql]);
      throw Object.assign(new Error('original durable preparation reply lost'), {code: 'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'), {create: true, maxEntries: 2, maxWireBytes: 4096});
  index.migratePhysicalObjects([]); index.migrate([]); index.beginPhysicalObjectLifetime();
  if (kind === 'finish') index.stagePhysicalObjects([original], {durable: true});
  armed = true;
  assert.throws(() => kind === 'stage'
    ? index.stagePhysicalObjects([original], {durable: true})
    : index.finishPhysicalPreparations([original]), error => error.outcome === 'unknown');
  assert.throws(() => index.pendingPhysicalObjects(), {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(() => index.finishPhysicalPreparations([{...original, inode: '3'}]), {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index.finishPhysicalPreparations([original]);
  assert.deepEqual(index.pendingPhysicalObjects(), []);
  assert.equal(index.physicalObjectUsage().bytes, 0);
});
}

test('empty schema initialization never replaces an existing coverage original', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-empty-index-initialization-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory, {recursive: true});});
  const path = join(directory, 'index.sqlite3');
  const options = {create: true, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.needsMigration(), true);
  index.close();
  const before = new DatabaseSync(path, {readOnly: true});
  let coverage;
  try {coverage = {...before.prepare('SELECT * FROM coverage WHERE id=1').get()};}
  finally {before.close();}
  await assert.rejects(openDeliveryAttemptIndex(path, {...options, initializeEmpty: true}),
    {code: 'DeliveryAttemptIndexUnavailable'});
  const after = new DatabaseSync(path, {readOnly: true});
  try {assert.deepEqual({...after.prepare('SELECT * FROM coverage WHERE id=1').get()}, coverage);}
  finally {after.close();}
  index = await openDeliveryAttemptIndex(path, {...options, create: false});
  assert.equal(index.needsMigration(), true, 'a supplied empty flag cannot reset incomplete existing coverage');
});

test('publication statements are acquired on use after unchanged schema admission', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-statements-'));
  let index;
  const prepared = [], original = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    if (/\b(?:FROM|INTO) publication_(?:contracts|attempts|records)\b/u.test(sql)) prepared.push(sql);
    return Reflect.apply(original, this, [sql]);
  });
  t.after(async () => {index?.close(); await rm(directory, {recursive: true});});
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true});
  index.migrate([]);
  index.close(); prepared.length = 0;
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(prepared.length, 0, 'opening does not allocate unused publication statements');
  const entry = {semantic_cid: 'sha256:' + 'a'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  assert.equal(index.publicationContract(entry.semantic_cid), undefined);
  assert.equal(index.publicationContract(entry.semantic_cid), undefined);
  assert.equal(prepared.length, 1, 'same native statement is reused within this connection');
  index.putPublicationContracts([entry], {objects: 1, bytes: 2});
  assert.deepEqual(index.publicationContract(entry.semantic_cid), entry);
  assert.equal(prepared.length, 2, 'only the selected read and insert were acquired');
  index.removePublicationContract(entry);
  assert.equal(index.publicationContract(entry.semantic_cid), undefined);
  assert.equal(prepared.length, 3);
  index.close();
  assert.throws(() => index.publicationContract(entry.semantic_cid), {code: 'DeliveryAttemptIndexClosed'});
  assert.equal(prepared.length, 3, 'a closed connection cannot allocate another statement');
  prepared.length = 0;
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(prepared.length, 0, 'a new connection owns its own initially empty holders');
  assert.equal(index.publicationContract(entry.semantic_cid), undefined);
  assert.equal(prepared.length, 1);
});

test('publication statement acquisition failure rolls back before the same input can retry', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-statement-failure-'));
  let index, armed = false, lost = false, rollbacks = 0, commits = 0;
  const prepare = DatabaseSync.prototype.prepare, exec = DatabaseSync.prototype.exec;
  const failure = Object.assign(new Error('publication statement acquisition failed'), {code: 'EIO'});
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    if (armed && !lost && sql === 'INSERT INTO publication_contracts VALUES(?,?,?,?)') {
      lost = true; throw failure;
    }
    return Reflect.apply(prepare, this, [sql]);
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'ROLLBACK') rollbacks++;
    if (armed && sql === 'COMMIT') commits++;
    return result;
  });
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, maxEntries: 4, maxWireBytes: 4096});
  index.migrate([]);
  const entry = {semantic_cid: 'sha256:' + 'b'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  const before = index.publicationUsage();
  armed = true;
  assert.throws(() => index.putPublicationContracts([entry], {objects: 1, bytes: 2}), error => error === failure);
  assert.equal(lost, true);
  assert.deepEqual({rollbacks, commits}, {rollbacks: 1, commits: 0});
  assert.equal(index.publicationContract(entry.semantic_cid), undefined);
  assert.deepEqual(index.publicationUsage(), before);
  index.putPublicationContracts([entry], {objects: 1, bytes: 2});
  assert.deepEqual(index.publicationContract(entry.semantic_cid), entry);
  assert.deepEqual({rollbacks, commits}, {rollbacks: 1, commits: 1});
});

function publicationBlockWork(t) {
  let armed = false;
  const reads = [], writes = [];
  let commits = 0;
  const prepare = DatabaseSync.prototype.prepare, exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]);
    for (const method of ['get', 'all', 'run']) {
      const original = statement[method];
      t.mock.method(statement, method, function(...args) {
        const result = Reflect.apply(original, this, args);
        if (armed && /^SELECT \* FROM publication_contracts WHERE semantic_cid(?:=| IN )/u.test(sql)) {
          reads.push({args, rows: method === 'all' ? result : result === undefined ? [] : [result]});
        }
        if (armed && /^INSERT INTO publication_contracts /u.test(sql)) writes.push({args, changes: result.changes});
        return result;
      });
    }
    return statement;
  });
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') commits++;
    return result;
  });
  return {arm() {armed = true;}, disarm() {armed = false;},
    snapshot() {return {reads, writes, commits};}};
}

test('publication quota selection bounds exact keys across blocks and refuses invalid input before reading', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-quota-selection-'));
  let index;
  const work = publicationBlockWork(t);
  t.after(async () => {work.disarm(); index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, maxEntries: 96, maxWireBytes: 4096});
  index.migrate([]);
  const entry = n => ({semantic_cid: 'sha256:' + n.toString(16).padStart(64, '0'),
    name: 'invocation', wire: '{}', byte_count: 2});
  const selected = Array.from({length: 65}, (_, n) => entry(n + 1));
  const unrelated = Array.from({length: 8}, (_, n) => entry(n + 100));
  const installed = [...selected.slice(0, 63), ...unrelated];
  index.putPublicationContracts(installed, {objects: installed.length, bytes: installed.length * 2});
  const before = index.publicationUsage();
  work.arm();
  const rows = index.publicationContracts(selected.map(row => row.semantic_cid));
  work.disarm();
  assert.equal(rows.length, 63);
  assert(Object.isFrozen(rows) && rows.every(Object.isFrozen));
  assert.deepEqual(new Set(rows.map(row => row.semantic_cid)), new Set(selected.slice(0, 63).map(row => row.semantic_cid)));
  assert.deepEqual(work.snapshot().reads.map(read => read.args.length), [64, 1]);
  assert.equal(work.snapshot().reads.flatMap(read => read.rows).length, 63);
  assert.equal(work.snapshot().commits, 0);
  assert.deepEqual(index.publicationUsage(), before);
  assert.deepEqual(index.publicationContracts([selected[0].semantic_cid, selected[0].semantic_cid]), [selected[0]]);
  assert.deepEqual(index.publicationContracts([]), []);
  const readCount = work.snapshot().reads.length;
  work.arm();
  for (const invalid of [null, [undefined], Array(1), ['foreign'], Array(97).fill(selected[0].semantic_cid)]) {
    assert.throws(() => index.publicationContracts(invalid), {code: 'InvalidDeliveryAttemptIndex'});
  }
  work.disarm();
  assert.equal(work.snapshot().reads.length, readCount);
  index.close();
  assert.throws(() => index.publicationContracts([]), {code: 'DeliveryAttemptIndexClosed'});
});

test('publication mutation consumes only its original unchanged preflight once', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-preflight-once-'));
  let index;
  const work = publicationBlockWork(t);
  t.after(async () => {work.disarm(); index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, initializeEmpty: true, maxEntries: 4, maxWireBytes: 4096});
  const entries = ['1', '2'].map(value => ({semantic_cid: 'sha256:' + value.repeat(64),
    name: 'invocation', wire: '{}', byte_count: 2}));
  work.arm();
  const selected = index.publicationContracts(entries.map(entry => entry.semantic_cid));
  index.putPublicationContracts(entries, {objects: 2, bytes: 4}, undefined, selected);
  assert.equal(work.snapshot().reads.length, 1);
  assert.equal(work.snapshot().commits, 1);
  const next = index.publicationContracts(entries.map(entry => entry.semantic_cid));
  assert(Object.isFrozen(next) && next.every(Object.isFrozen));
  assert.throws(() => {next[0].wire = 'changed';}, TypeError);
  index.putPublicationContracts(entries, {objects: 0, bytes: 0}, undefined, next);
  assert.equal(work.snapshot().reads.length, 2, 'a new operation observes its own rows');
  index.putPublicationContracts(entries, {objects: 0, bytes: 0}, undefined, next);
  assert.equal(work.snapshot().reads.length, 3, 'even unchanged no-op selection is spent once');
  assert.equal(work.snapshot().commits, 1, 'unchanged bodies do not manufacture another durable mutation');
});

test('publication preflight copies foreign keys and actual mutation keep full selection', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-preflight-boundaries-'));
  let index, foreign;
  const work = publicationBlockWork(t);
  t.after(async () => {work.disarm(); index?.close(); foreign?.close(); await rm(directory, {recursive: true});});
  const options = {create: true, initializeEmpty: true, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'), options);
  foreign = await openDeliveryAttemptIndex(join(directory, 'foreign.sqlite3'), options);
  const entry = {semantic_cid: 'sha256:' + '1'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  const other = {...entry, semantic_cid: 'sha256:' + '2'.repeat(64)};
  index.putPublicationContracts([entry], {objects: 1, bytes: 2});
  for (const copied of [Object.freeze([]), [...index.publicationContracts([entry.semantic_cid])],
    foreign.publicationContracts([entry.semantic_cid])]) {
    work.arm(); const before = work.snapshot().reads.length;
    index.putPublicationContracts([entry], {objects: 0, bytes: 0}, undefined, copied);
    assert.equal(work.snapshot().reads.length, before + 1);
    work.disarm();
  }
  const wrongKeys = index.publicationContracts([entry.semantic_cid]);
  work.arm(); let before = work.snapshot().reads.length;
  index.putPublicationContracts([other], {objects: 1, bytes: 2}, undefined, wrongKeys);
  assert.equal(work.snapshot().reads.length, before + 1);
  work.disarm();
  const original = index.publicationContracts([entry.semantic_cid]);
  index.removePublicationContract(entry);
  const changed = {...entry, wire: '{"changed":1}', byte_count: 13};
  index.putPublicationContracts([changed], {objects: 1, bytes: 13});
  work.arm(); before = work.snapshot().reads.length;
  assert.throws(() => index.putPublicationContracts([entry], {objects: 0, bytes: 0}, undefined, original),
    {code: 'PublicationSemanticIdentityConflict'});
  assert.equal(work.snapshot().reads.length, before + 1, 'actual native mutation invalidates the old observation');
  work.disarm(); index.close();
  assert.throws(() => index.putPublicationContracts([entry], {objects: 0, bytes: 0}, undefined, original),
    {code: 'DeliveryAttemptIndexClosed'});
});

for (const afterCommit of [false, true]) {
test(`publication preflight ${afterCommit ? 'committed' : 'rolled-back'} Unknown reacquires before original confirmation`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-preflight-unknown-'));
  let index, armed = false, lost = false;
  const work = publicationBlockWork(t), exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && !lost && sql === 'COMMIT') {
      lost = true; if (afterCommit) Reflect.apply(exec, this, [sql]);
      throw Object.assign(new Error('lost original preflight mutation reply'), {code: 'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  t.after(async () => {armed = false; work.disarm(); index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, initializeEmpty: true, maxEntries: 4, maxWireBytes: 4096});
  const entry = {semantic_cid: 'sha256:' + '1'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  work.arm();
  const selected = index.publicationContracts([entry.semantic_cid]);
  armed = true;
  assert.throws(() => index.putPublicationContracts([entry], {objects: 1, bytes: 2}, undefined, selected),
    error => error.outcome === 'unknown');
  assert(lost);
  assert.equal(work.snapshot().reads.length, 1);
  assert.throws(() => index.publicationContracts([entry.semantic_cid]), {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index.putPublicationContracts([entry], {objects: 1, bytes: 2}, undefined, selected);
  assert.equal(work.snapshot().reads.length, 2, 'same-original retry selects actual current rows, not the spent observation');
  assert.deepEqual(index.publicationContract(entry.semantic_cid), entry);
  assert.equal(index.publicationUsage().objects, 1);
  assert.equal(index.publicationUsage().bytes, 2);
  assert.equal(work.snapshot().commits, afterCommit ? 2 : 1, 'only real successful COMMIT calls are counted');
});
}

test('native publication block selects only supplied keys and groups its insertion calls', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-block-'));
  let index;
  const work = publicationBlockWork(t);
  t.after(async () => {work.disarm(); index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, maxEntries: 128, maxWireBytes: 4096});
  index.migrate([]);
  const entry = n => ({semantic_cid: 'sha256:' + n.toString(16).padStart(64, '0'),
    name: 'invocation', wire: '{}', byte_count: 2});
  const selected = Array.from({length: 8}, (_, n) => entry(n + 1));
  const unrelated = Array.from({length: 24}, (_, n) => entry(n + 100));
  const installed = [...selected.slice(0, 2), ...unrelated];
  index.putPublicationContracts(installed, {objects: installed.length, bytes: installed.length * 2});
  const before = index.publicationUsage();
  work.arm();
  index.putPublicationContracts(selected, {objects: 6, bytes: 12});
  work.disarm();
  for (const row of [...selected, ...unrelated]) assert.deepEqual(index.publicationContract(row.semantic_cid), row);
  const usage = index.publicationUsage();
  assert.equal(usage.objects, before.objects + 6);
  assert.equal(usage.bytes, before.bytes + 12);
  const observed = work.snapshot(), keys = new Set(selected.map(row => row.semantic_cid));
  assert.deepEqual(observed.reads.flatMap(read => read.args).filter(value => value !== null).sort(), [...keys].sort());
  assert.equal(observed.reads.flatMap(read => read.rows).length, 2);
  assert(observed.reads.every(read => read.rows.every(row => keys.has(row.semantic_cid))), 'unrelated rows are not acquired');
  assert.equal(observed.writes.reduce((sum, write) => sum + write.changes, 0), 6);
  assert.deepEqual({selectedStatements: observed.reads.length, insertStatements: observed.writes.length,
    commits: observed.commits}, {selectedStatements: 1, insertStatements: 1, commits: 1});
});

test('native publication block preserves total bounds across multiple native handoffs', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-block-bound-'));
  let index;
  const work = publicationBlockWork(t);
  t.after(async () => {work.disarm(); index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, maxEntries: 66, maxWireBytes: 4096});
  index.migrate([]);
  const rows = Array.from({length: 65}, (_, n) => ({semantic_cid: 'sha256:' + (n + 1).toString(16).padStart(64, '0'),
    name: 'invocation', wire: '{}', byte_count: 2}));
  work.arm();
  index.putPublicationContracts(rows, {objects: 65, bytes: 130});
  work.disarm();
  const actual = work.snapshot();
  assert.deepEqual({reads: actual.reads.length, writes: actual.writes.length, commits: actual.commits},
    {reads: 2, writes: 2, commits: 1});
  assert.equal(actual.writes.reduce((sum, write) => sum + write.changes, 0), 65);
  assert.deepEqual(actual.reads.flatMap(read => read.args), rows.map(row => row.semantic_cid));
  const before = index.publicationUsage();
  assert.throws(() => index.putPublicationContracts([rows[0], rows[0]], {objects: 0, bytes: 0}),
    {code: 'InvalidDeliveryAttemptIndex'});
  assert.throws(() => index.putPublicationContracts([{...rows[0], wire: '[]'}], {objects: 0, bytes: 0}),
    {code: 'PublicationSemanticIdentityConflict'});
  const extra = {...rows[0], semantic_cid: 'sha256:' + 'f'.repeat(64)};
  assert.throws(() => index.putPublicationContracts([extra], {objects: 0, bytes: 0}),
    {code: 'PublicationStoreCapacity'});
  assert.throws(() => index.putPublicationContracts([...rows, extra, {...extra, semantic_cid: 'sha256:' + 'e'.repeat(64)}],
    {objects: 2, bytes: 4}), {code: 'DeliveryAttemptIndexLimit'});
  assert.deepEqual(index.publicationUsage(), before);
  for (const row of rows) assert.deepEqual(index.publicationContract(row.semantic_cid), row);
});

test('native publication block rolls back earlier inserts if a later handoff fails', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-block-rollback-'));
  let index, armed = false, inserts = 0;
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  const prepare = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]), run = statement.run;
    if (/^INSERT INTO publication_contracts /u.test(sql)) t.mock.method(statement, 'run', function(...args) {
      if (armed && ++inserts === 2) throw Object.assign(new Error('second metadata insert failed'), {code: 'EIO'});
      return Reflect.apply(run, this, args);
    });
    return statement;
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 66, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]);
  const rows = Array.from({length: 65}, (_, n) => ({semantic_cid: 'sha256:' + (n + 1).toString(16).padStart(64, '0'),
    name: 'invocation', wire: '{}', byte_count: 2}));
  armed = true;
  assert.throws(() => index.putPublicationContracts(rows, {objects: 65, bytes: 130}), {code: 'EIO'});
  armed = false;
  assert.equal(inserts, 2, 'first block actually inserted before the later failure');
  assert.equal(index.publicationUsage().objects, 0);
  assert.equal(index.publicationUsage().bytes, 0);
  for (const row of rows) assert.equal(index.publicationContract(row.semantic_cid), undefined);
  index.close(); index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.publicationUsage().objects, 0);
  for (const row of rows) assert.equal(index.publicationContract(row.semantic_cid), undefined);
});

for (const afterCommit of [false, true]) {
test(`native publication block retains its ${afterCommit ? 'committed' : 'rolled-back'} Unknown original`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-block-unknown-'));
  let index, armed = false, lost = false, commits = 0;
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        lost = true;
        if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('publication block COMMIT reply lost'), {code: 'EIO'});
      }
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 66, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]);
  const rows = Array.from({length: 65}, (_, n) => ({semantic_cid: 'sha256:' + (n + 1).toString(16).padStart(64, '0'),
    name: 'invocation', wire: '{}', byte_count: 2}));
  const put = () => index.putPublicationContracts(rows, {objects: 65, bytes: 130});
  armed = true;
  assert.throws(put, error => error.outcome === 'unknown');
  assert.equal(lost, true);
  assert.throws(() => index.publicationUsage(), {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(() => index.putPublicationContracts([...rows].reverse(), {objects: 65, bytes: 130}),
    {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(() => index.putPublicationContracts([{...rows[0], wire: '[]'}], {objects: 65, bytes: 130}),
    {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  put();
  assert.equal(commits, 2, 'same original retry confirms through a real new COMMIT');
  armed = false;
  assert.equal(index.publicationUsage().objects, 65);
  assert.equal(index.publicationUsage().bytes, 130);
  for (const row of rows) assert.deepEqual(index.publicationContract(row.semantic_cid), row);
  index.close(); index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.publicationUsage().objects, 65);
  for (const row of rows) assert.deepEqual(index.publicationContract(row.semantic_cid), row);
});
}

test('Result cleanup lifecycle is durable and native close alone never seals it', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-recovery-'));
  let index, armed = false, commits = 0;
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]);
  assert.equal(index.resultDeletionRecoveryRequired(), false);
  armed = true;
  index.beginResultDeletionLifetime(); index.beginResultDeletionLifetime();
  assert.equal(commits, 1, 'one real intent commit for this cleanup lifetime');
  assert.equal(index.resultDeletionRecoveryRequired(), true);
  index.close(); assert.equal(commits, 1, 'database close is not a Result cleanup acknowledgement');
  armed = false; index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.resultDeletionRecoveryRequired(), true);
  armed = true;
  index.retainResultDeletionSeal(); index.retainResultDeletionSeal();
  assert.equal(commits, 1, 'retaining the Store acknowledgement is not a native seal ACK');
  index.close();
  assert.equal(commits, 2, 'one real seal after the Store reports its original children settled');
  armed = false;
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.resultDeletionRecoveryRequired(), false);
});

for (const missing of ['table', 'row']) {
test(`Result cleanup lifecycle refuses adopted ${missing} loss`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-recovery-loss-'));
  t.after(() => rm(directory, {recursive: true}));
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  const index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]); index.close();
  const database = new DatabaseSync(path);
  try {database.exec(missing === 'table' ? 'DROP TABLE result_deletion_recovery' : 'DELETE FROM result_deletion_recovery');}
  finally {database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path, options), {code: 'DeliveryAttemptIndexUnavailable'});
});
}

for (const phase of ['begin', 'seal']) for (const afterCommit of [false, true]) {
test(`Result cleanup lifecycle ${phase} retains its ${afterCommit ? 'committed' : 'rolled-back'} Unknown original`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-recovery-unknown-'));
  let index, armed = false, lost = false;
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && !lost && sql === 'COMMIT') {
      lost = true;
      if (afterCommit) Reflect.apply(exec, this, [sql]);
      throw Object.assign(new Error('lost Result cleanup lifecycle reply'), {code: 'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]);
  if (phase === 'seal') {index.beginResultDeletionLifetime(); index.retainResultDeletionSeal();}
  const change = () => index[phase === 'begin' ? 'beginResultDeletionLifetime' : 'close']();
  armed = true;
  assert.throws(change, error => error.outcome === 'unknown');
  const refusal = phase === 'begin' ? 'DeliveryAttemptIndexCommitOutcomeUnknown' : 'DeliveryAttemptIndexCleanupPending';
  assert.throws(() => index.publicationUsage(), {code: refusal});
  assert.throws(() => index.putPublicationContracts([], {objects: 0, bytes: 0}), {code: refusal});
  change();
  if (phase === 'begin') assert.equal(index.resultDeletionRecoveryRequired(), true);
  index.close(); armed = false;
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.resultDeletionRecoveryRequired(), phase === 'begin');
});
}

for (const afterCommit of [false, true]) {
test(`Result cleanup keeps recovery dirty when an unrelated ${afterCommit ? 'committed' : 'rolled-back'} Unknown closes`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-recovery-unrelated-'));
  let index, armed = false, lost = false, commits = 0;
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        lost = true; if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('unrelated original native reply lost'), {code: 'EIO'});
      }
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]);
  index.beginResultDeletionLifetime();
  armed = true;
  const body = {semantic_cid: 'sha256:' + 'a'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  let primary;
  assert.throws(() => index.putPublicationContracts([body], {objects: 1, bytes: 2}),
    error => {primary = error; return error.outcome === 'unknown';});
  index.retainResultDeletionSeal();
  index.close();
  assert.equal(commits, 1, 'native close does not invent a confirmation for the unrelated mutation or seal');
  assert.equal(primary.outcome, 'unknown');
  armed = false; index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.resultDeletionRecoveryRequired(), true);
});
}

for(const missing of['publication_attempts','publication_records','publication_attempt_runs']){
test(`native publication progress refuses adopted ${missing} loss`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-progress-loss-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:4,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);index.close();
  const database=new DatabaseSync(path);
  try{database.exec(`DROP ${missing==='publication_attempt_runs'?'INDEX':'TABLE'} ${missing}`);}
  finally{database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

test('publication completion batch joins the next required native transaction', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-finish-batch-'));
  let index, armed = false, commits = 0;
  t.after(async () => { armed = false; index?.close(); await rm(directory, {recursive: true}); });
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true});
  index.migrate([]); index.migratePublicationRecovery([]);
  const originals = [1, 2, 3].map(n => ({public_index_cid: 'sha256:' + String(n).repeat(64),
    inventory_wire: JSON.stringify({original: n})}));
  for (const original of originals) index.stageNativePublicationInventory(original);
  armed = true;
  for (const original of originals) index.retainPublicationInventoryFinish(original);
  assert.equal(commits, 0, 'retention is not a durable completion acknowledgement');
  assert.deepEqual(index.pendingPublications(), originals, 'actual pending originals remain durable until COMMIT');
  assert.throws(() => index.retainPublicationInventoryFinish({...originals[0], inventory_wire: '{}'}),
    {code: 'PublicationMetadataInventoryConflict'});
  const body = {semantic_cid: 'sha256:' + '4'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  index.putPublicationContracts([body], {bytes: 2, objects: 1});
  assert.equal(commits, 1);
  assert.deepEqual(index.pendingPublications(), []);
  assert.deepEqual(index.nativePublicationInventories(), originals);
  index.close(); assert.equal(commits, 1);
  armed = false; index = await openDeliveryAttemptIndex(path, options);
  assert.deepEqual(index.pendingPublications(), []);
  assert.equal(index.publicationContract(body.semantic_cid).wire, '{}');
});

test('publication completion batch flushes at close and keeps the original native close ACK separate', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-finish-close-'));
  let index, armed = false, refuse = false, commits = 0;
  t.after(async () => { armed = false; refuse = false; index?.close(); await rm(directory, {recursive: true}); });
  const exec = DatabaseSync.prototype.exec, close = DatabaseSync.prototype.close;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(exec, this, [sql]);
  });
  t.mock.method(DatabaseSync.prototype, 'close', function() { return refuse ? false : Reflect.apply(close, this, []); });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 2, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true});
  index.migrate([]); index.migratePublicationRecovery([]);
  const original = {public_index_cid: 'sha256:' + '1'.repeat(64), inventory_wire: '{"original":1}'};
  index.stageNativePublicationInventory(original); index.retainPublicationInventoryFinish(original);
  armed = refuse = true;
  assert.throws(() => index.close(), {code: 'DeliveryAttemptIndexCleanupPending'});
  assert.equal(commits, 1);
  assert.throws(() => index.pendingPublications(), {code: 'DeliveryAttemptIndexCleanupPending'});
  refuse = false; assert.equal(index.close(), true); assert.equal(commits, 1);
  armed = false; index = await openDeliveryAttemptIndex(path, options);
  assert.deepEqual(index.pendingPublications(), []);
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid), original);
});

for (const phase of ['next transaction', 'close']) for (const afterCommit of [false, true]) {
test(`publication completion batch keeps its ${phase} ${afterCommit ? 'committed' : 'rolled-back'} Unknown original`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-finish-unknown-'));
  let index, armed = false, lost = false;
  t.after(async () => { armed = false; index?.close(); await rm(directory, {recursive: true}); });
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && !lost && sql === 'COMMIT') {
      lost = true; if (afterCommit) Reflect.apply(exec, this, [sql]);
      throw Object.assign(new Error('lost original completion batch reply'), {code: 'EIO'});
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 2, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true});
  index.migrate([]); index.migratePublicationRecovery([]);
  const original = {public_index_cid: 'sha256:' + '1'.repeat(64), inventory_wire: '{"original":1}'};
  index.stageNativePublicationInventory(original); index.retainPublicationInventoryFinish(original);
  const body = {semantic_cid: 'sha256:' + '2'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  const finish = () => phase === 'close' ? index.close() : index.putPublicationContracts([body], {bytes: 2, objects: 1});
  armed = true; assert.throws(finish, error => error.outcome === 'unknown'); assert.equal(lost, true);
  assert.throws(() => index.retainPublicationInventoryFinish({...original, inventory_wire: '{}'}));
  if (phase !== 'close') {
    assert.throws(() => index.putPublicationContracts([{...body, wire: '[]'}], {bytes: 2, objects: 1}),
      {code: 'DeliveryAttemptIndexCommitOutcomeUnknown'});
  }
  finish();
  if (phase === 'close') { armed = false; index = await openDeliveryAttemptIndex(path, options); }
  assert.deepEqual(index.pendingPublications(), []);
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid), original);
  if (phase !== 'close') assert.equal(index.publicationUsage().objects, 1);
});
}

for (const afterCommit of [false, true]) {
test(`publication completion batch closes an unrelated ${afterCommit ? 'committed' : 'rolled-back'} Unknown without acknowledging it`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-finish-unrelated-'));
  let index, armed = false, lost = false, commits = 0;
  t.after(async () => { armed = false; index?.close(); await rm(directory, {recursive: true}); });
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (armed && sql === 'COMMIT') {
      commits++;
      if (!lost) {
        lost = true; if (afterCommit) Reflect.apply(exec, this, [sql]);
        throw Object.assign(new Error('lost unrelated native metadata reply'), {code: 'EIO'});
      }
    }
    return Reflect.apply(exec, this, [sql]);
  });
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 2, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true});
  index.migrate([]); index.migratePublicationRecovery([]);
  const original = {public_index_cid: 'sha256:' + '1'.repeat(64), inventory_wire: '{"original":1}'};
  const body = {semantic_cid: 'sha256:' + '2'.repeat(64), name: 'invocation', wire: '{}', byte_count: 2};
  index.stageNativePublicationInventory(original); index.retainPublicationInventoryFinish(original);
  armed = true; let failure;
  assert.throws(() => index.putPublicationContracts([body], {bytes: 2, objects: 1}), error => {
    failure = error; return error.outcome === 'unknown';
  });
  assert.equal(index.close(), true); assert.equal(commits, 1, 'physical close does not confirm the unrelated mutation');
  assert.equal(failure.outcome, 'unknown');
  armed = false; index = await openDeliveryAttemptIndex(path, options);
  assert.deepEqual(index.pendingPublications(), afterCommit ? [] : [original]);
  assert.equal(index.publicationContract(body.semantic_cid)?.wire, afterCommit ? '{}' : undefined);
  if (!afterCommit) index.finishPublicationInventory(original);
});
}

test('owned physical quota lifetime seals only its bounded final changes',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-lifetime-'));
  let index,armed=false,commits=0;t.after(async()=>{armed=false;index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){if(armed&&sql==='COMMIT')commits++;return Reflect.apply(exec,this,[sql]);});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migratePhysicalObjects([]);index.migrate([]);
  const first={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  const second={...first,cid:'sha256:'+'2'.repeat(64),inode:'3'};
  index.recordPhysicalObjects([first]);index.beginPhysicalObjectLifetime();armed=true;
  index.stagePhysicalObjects([second]);index.recordPhysicalObjects([second]);
  assert.deepEqual(index.pendingPhysicalObjects(),[]);
  index.removePhysicalObjects([second]);
  const replacement={...first,inode:'4'};
  index.removePhysicalObjects([first]);index.recordPhysicalObjects([replacement]);
  assert.throws(()=>index.removePhysicalObjects([first]),{code:'PublicationObjectAccountingMismatch'});
  assert.equal(index.physicalObjectUsage().bytes,13);assert.equal(commits,0);
  index.close();assert.equal(commits,1);armed=false;
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.physicalObjectRecoveryRequired(),false);
  assert.deepEqual(index.physicalObject(first.cid),replacement);
  assert.equal(index.physicalObject(second.cid),undefined);
  assert.equal(index.physicalObjectUsage().objects,1);
});

for(const afterCommit of[false,true])test(`owned physical quota seal keeps its ${afterCommit?'committed':'rolled-back'} Unknown original`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-seal-unknown-'));
  let index,armed=false,lost=false;t.after(async()=>{armed=false;index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost original quota seal reply'),{code:'EIO'});
    }return Reflect.apply(exec,this,[sql]);
  });
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migratePhysicalObjects([]);index.migrate([]);
  index.beginPhysicalObjectLifetime();
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  index.recordPhysicalObjects([original]);armed=true;
  assert.throws(()=>index.close(),error=>error.outcome==='unknown');assert(lost);
  assert.throws(()=>index.recordPhysicalObjects([{...original,inode:'3'}]),{code:'DeliveryAttemptIndexCleanupPending'});
  assert.equal(index.close(),true);armed=false;
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.physicalObjectRecoveryRequired(),false);
  assert.deepEqual(index.physicalObject(original.cid),original);
  assert.equal(index.physicalObjectUsage().bytes,13);
});

test('owned physical quota seal precedes but does not replace the same native close ACK',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-seal-close-'));
  let index,armed=false,refuse=false,commits=0;
  t.after(async()=>{refuse=false;index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec,close=DatabaseSync.prototype.close;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){if(armed&&sql==='COMMIT')commits++;return Reflect.apply(exec,this,[sql]);});
  t.mock.method(DatabaseSync.prototype,'close',function(){return refuse?false:Reflect.apply(close,this,[]);});
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migratePhysicalObjects([]);index.migrate([]);index.beginPhysicalObjectLifetime();
  index.recordPhysicalObjects([{cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'}]);
  armed=refuse=true;
  assert.throws(()=>index.close(),{code:'DeliveryAttemptIndexCleanupPending'});assert.equal(commits,1);
  assert.throws(()=>index.physicalObjectUsage(),{code:'DeliveryAttemptIndexCleanupPending'});
  refuse=false;assert.equal(index.close(),true);assert.equal(commits,1,'only original native close retries after seal ACK');
});

for(const damage of['header','table','counter'])test(`unclean physical quota refuses adopted ${damage} loss without recreating coverage`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-dirty-damage-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migratePhysicalObjects([]);index.migrate([]);index.close();
  const database=new DatabaseSync(path);
  try{database.exec(damage==='header'?'PRAGMA user_version=2':
    'PRAGMA user_version=1; '+(damage==='table'?'DROP TABLE physical_objects':'DELETE FROM physical_object_usage'));}
  finally{database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});

test('physical object accounting retains exact generations and bounded totals across reopen',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-usage-'));
  let index;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});
  const first={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  const second={cid:'sha256:'+'2'.repeat(64),byte_count:17,device:'1',inode:'3'};
  assert.equal(index.physicalObjectUsage().complete,0);
  index.migratePhysicalObjects([first]);index.migrate([]);
  assert.equal(index.recordPhysicalObjects([second]).bytes,30);
  const revision=index.physicalObjectUsage().ack_revision;
  assert.equal(index.recordPhysicalObjects([first,second]).ack_revision,revision);
  assert.throws(()=>index.recordPhysicalObjects([{...first,inode:'4'}]),{code:'PublicationObjectAccountingMismatch'});
  assert.throws(()=>index.removePhysicalObjects([{...first,inode:'4'}]),{code:'PublicationObjectAccountingMismatch'});
  assert.throws(()=>index.recordPhysicalObjects([{...first,cid:'sha256:'+'3'.repeat(64)}]),{code:'DeliveryAttemptIndexLimit'});
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.physicalObject(first.cid),first);
  assert.equal(index.physicalObjectUsage().bytes,30);
  assert.equal(index.removePhysicalObjects([first]).bytes,17);
  const retired=index.physicalObjectUsage().ack_revision;
  assert.equal(index.removePhysicalObjects([first]).ack_revision,retired);
  assert.deepEqual(index.physicalObject(second.cid),second);
});

for(const kind of ['record','remove'])for(const afterCommit of [false,true]) {
test(`physical object ${kind} retains ${afterCommit?'committed':'rolled-back'} Unknown until same-original confirmation`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-unknown-'));
  let index,armed=false,lost=false;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost original physical accounting reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migratePhysicalObjects([]);index.migrate([]);
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  if(kind==='remove')index.recordPhysicalObjects([original]);
  const mutate=value=>kind==='record'?index.recordPhysicalObjects([value]):index.removePhysicalObjects([value]);
  armed=true;assert.throws(()=>mutate(original),error=>error.outcome==='unknown');
  assert.throws(()=>index.physicalObjectUsage(),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(()=>mutate({...original,inode:'3'}),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  mutate(original);
  assert.equal(index.physicalObjectUsage().bytes,kind==='record'?13:0);
  assert.deepEqual(index.physicalObject(original.cid),kind==='record'?original:undefined);
});
}

for(const afterCommit of [false,true]) {
test(`physical cleanup settles only the same ${afterCommit?'committed':'rolled-back'} uncertain installation`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-cleanup-'));
  let index,armed=false,lost=false;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost original physical install reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migratePhysicalObjects([]);index.migrate([]);
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  armed=true;assert.throws(()=>index.recordPhysicalObjects([original]),error=>error.outcome==='unknown');
  assert.throws(()=>index.removePhysicalObjects([{...original,inode:'3'}]),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  // This private index port is invoked by Store only after its real unlink
  // and directory ACK. It supplies no physical cleanup or semantic authority.
  assert.equal(index.removePhysicalObjects([original]).bytes,0);
  assert.equal(index.physicalObject(original.cid),undefined);
});
}

for(const missing of ['physical_objects','physical_object_usage','physical_object_preparations','singleton']) {
test(`physical object accounting refuses missing adopted ${missing}`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-missing-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migratePhysicalObjects([]);index.close();
  const db=new DatabaseSync(path);
  try{db.exec(missing==='singleton'?'DELETE FROM physical_object_usage':`DROP TABLE ${missing}`);}finally{db.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

test('native physical preparations distinguish concurrent generations and join the winning quota commit',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-preparations-'));
  let index,armed=false,commits=0;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT')commits++;return Reflect.apply(exec,this,[sql]);
  });
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migratePhysicalObjects([]);index.migrate([]);
  const first={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  const second={...first,inode:'3'};
  index.stagePhysicalObjects([first]);index.stagePhysicalObjects([second]);
  assert.equal(index.pendingPhysicalObjects().length,2);
  assert.equal(index.physicalObjectUsage().bytes,0,'preparation is not installed bytes');
  armed=true;index.recordPhysicalObjects([first]);
  assert.equal(commits,1,'physical charge and removal of its pending generation share a transaction');
  assert.deepEqual(index.pendingPhysicalObjects(),[second]);
  index.finishPhysicalPreparations([second]);assert.equal(commits,2);
  index.finishPhysicalPreparations([second]);assert.equal(commits,2);
  assert.deepEqual(index.physicalObject(first.cid),first);
  assert.equal(index.physicalObjectUsage().bytes,13);
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.pendingPhysicalObjects(),[]);
  assert.deepEqual(index.physicalObject(first.cid),first);
});

for(const kind of ['stage','finish'])for(const afterCommit of [false,true]) {
test(`native physical preparation ${kind} retains ${afterCommit?'committed':'rolled-back'} Unknown original`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-preparation-unknown-'));
  let index,armed=false,lost=false;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('original physical preparation reply lost'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migratePhysicalObjects([]);index.migrate([]);
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  if(kind==='finish')index.stagePhysicalObjects([original]);
  const mutate=values=>kind==='stage'?index.stagePhysicalObjects(values):index.finishPhysicalPreparations(values);
  armed=true;assert.throws(()=>mutate([original]),error=>error.outcome==='unknown');
  assert.throws(()=>index.pendingPhysicalObjects(),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(()=>index.finishPhysicalPreparations([{...original,inode:'3'}]),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  // The Store supplies actual no-link/unlink directory ACK before this
  // idempotent metadata cleanup; this index port cannot issue that ACK.
  index.finishPhysicalPreparations([original]);
  assert.deepEqual(index.pendingPhysicalObjects(),[]);
  assert.equal(index.physicalObjectUsage().bytes,0);
});
}

for(const afterCommit of [false,true]) {
test(`physical capacity migration retains ${afterCommit?'committed':'rolled-back'} Unknown without partial coverage`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-migration-unknown-'));
  let index,armed=false,lost=false;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('original migration COMMIT reply lost'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  armed=true;assert.throws(()=>index.migratePhysicalObjects([original]),error=>error.outcome==='unknown');
  assert.throws(()=>index.physicalObjectUsage(),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.physicalObjectUsage().complete,afterCommit?1:0);
  assert.equal(index.physicalObjectUsage().bytes,afterCommit?13:0);
  if(!afterCommit)index.migratePhysicalObjects([original]);
  assert.deepEqual(index.physicalObject(original.cid),original);
  assert.equal(index.physicalObjectUsage().bytes,13);
});
}

test('metadata deletion fences select the exact Run and migrate retired history only once',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-metadata-fences-'));
  let index;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:1,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);index.migratePublicationRecovery([]);
  const first={metadata_key:'1'.repeat(64),run_cid:'sha256:'+'2'.repeat(64)},other='sha256:'+'3'.repeat(64);
  assert.throws(()=>index.hasRunMetadataDeletionFence(first.run_cid),{code:'DeliveryAttemptIndexUnavailable'});
  index.migrateMetadataDeletionFences([{...first,retired:1}]);index.close();
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.needsMetadataDeletionFenceMigration(),true);
  index.migrateMetadataDeletionFences([{...first,retired:1}]);
  const second={metadata_key:'4'.repeat(64),run_cid:other};
  index.migrateMetadataDeletionFences([{...second,retired:0}],true);
  assert.equal(index.hasRunMetadataDeletionFence(first.run_cid),true);
  assert.equal(index.hasRunMetadataDeletionFence('sha256:'+'5'.repeat(64)),false);
  assert.deepEqual(index.metadataDeletionFence(first.metadata_key),{...first,retired:1});
  assert.throws(()=>index.retireNativePublicationInventory(undefined,{...first,run_cid:other}),
    {code:'PublicationMetadataDeletionConflict'});
  index.finishMetadataDeletionFence(second);index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.needsMetadataDeletionFenceMigration(),false);
  assert.equal(index.hasRunMetadataDeletionFence(other),true);
  assert.deepEqual(index.metadataDeletionFence(second.metadata_key),{...second,retired:1});
});

test('metadata deletion transfer and native inventory retirement share the original transaction',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-metadata-fence-transfer-'));
  let index,armed=false,commits=0;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT')commits++;return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:1,maxWireBytes:4096});
  index.migrate([]);index.migratePublicationRecovery([]);index.migrateMetadataDeletionFences([],true);
  const original={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"same":1}'};
  const fence={metadata_key:'2'.repeat(64),run_cid:'sha256:'+'3'.repeat(64)};
  index.stageNativePublicationInventory(original);armed=true;
  index.retireNativePublicationInventory(original,fence);
  assert.equal(commits,1);assert.deepEqual(index.pendingPublications(),[]);
  assert.equal(index.nativePublicationInventory(original.public_index_cid),undefined);
  assert.deepEqual(index.metadataDeletionFence(fence.metadata_key),{...fence,retired:0});
  index.retireNativePublicationInventory(original,fence);assert.equal(commits,1);
});

for(const finish of [false,true])for(const afterCommit of [false,true]) {
test(`metadata deletion fence ${finish?'completion':'transfer'} retains ${afterCommit?'committed':'rolled-back'} Unknown`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-metadata-fence-unknown-'));
  let index,armed=false,lost=false;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost original metadata fence reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);index.migratePublicationRecovery([]);index.migrateMetadataDeletionFences([],true);
  const fence={metadata_key:'1'.repeat(64),run_cid:'sha256:'+'2'.repeat(64)};
  if(finish)index.retireNativePublicationInventory(undefined,fence);
  const mutate=value=>finish?index.finishMetadataDeletionFence(value):index.retireNativePublicationInventory(undefined,value);
  armed=true;assert.throws(()=>mutate(fence),error=>error.outcome==='unknown');
  assert.throws(()=>index.hasRunMetadataDeletionFence(fence.run_cid),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(()=>mutate({...fence,run_cid:'sha256:'+'3'.repeat(64)}),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  mutate(fence);
  assert.deepEqual(index.metadataDeletionFence(fence.metadata_key),{...fence,retired:finish?1:0});
});
}

for(const missing of ['metadata_deletion_fences','metadata_deletion_fence_coverage','metadata_deletion_runs']) {
test(`metadata deletion fences refuse missing adopted ${missing}`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-metadata-fence-missing-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:1,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});index.close();
  const db=new DatabaseSync(path);try{db.exec(`DROP ${missing==='metadata_deletion_runs'?'INDEX':'TABLE'} ${missing}`);}finally{db.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

function referenceInventory(owner, contract, holding) {
  const cid = value => 'sha256:' + value.repeat(64);
  return {public_index_cid: cid(owner), inventory_wire: JSON.stringify({
    contract_objects: [{semantic_cid: cid(contract)}], physical_holding_cids: [cid(holding)],
  })};
}

test('native reference selection binds kind CID and excluded owner without unrelated inventory reads', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-reference-selection-'));
  let index, armed = false, commits = 0, fullReads = 0;
  const reads = [], exec = DatabaseSync.prototype.exec, prepare = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') commits++;
    return result;
  });
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]), all = statement.all;
    t.mock.method(statement, 'all', function(...args) {
      const rows = Reflect.apply(all, this, args);
      if (armed && sql.includes('FROM native_publication_references r')) reads.push({args, rows});
      if (armed && /^SELECT \* FROM native_publication_inventories ORDER BY/u.test(sql)) fullReads += rows.length;
      return rows;
    });
    return statement;
  });
  t.after(async () => {armed = false; index?.close(); await rm(directory, {recursive: true});});
  index = await openDeliveryAttemptIndex(join(directory, 'index.sqlite3'),
    {create: true, initializeEmpty: true, maxEntries: 4, maxWireBytes: 4096});
  const first = referenceInventory('1', 'a', 'b'), second = referenceInventory('2', 'a', 'b');
  const unrelated = referenceInventory('3', 'b', 'c');
  armed = true;
  for (const original of [first, second, unrelated]) index.stageNativePublicationInventory(original);
  assert.equal(commits, 3, 'body, pending and references share each original transaction');
  const holding = 'sha256:' + 'b'.repeat(64), contract = 'sha256:' + 'a'.repeat(64);
  assert.deepEqual(index.nativePublicationReferenceOwners('holding', holding, first.public_index_cid), [second]);
  assert.deepEqual(index.nativePublicationReferenceOwners('contract', contract), [first, second]);
  assert.deepEqual(index.nativePublicationReferenceOwners('contract', holding), [unrelated]);
  assert.equal(fullReads, 0);
  assert.deepEqual(reads.map(read => read.rows.length), [1, 2, 1]);
  const count = reads.length;
  for (const args of [['foreign', holding], ['holding', 'foreign'], ['holding', holding, null]]) {
    assert.throws(() => index.nativePublicationReferenceOwners(...args), {code: 'InvalidDeliveryAttemptIndex'});
  }
  assert.equal(reads.length, count, 'invalid selection performs no owner lookup');
  assert.equal(commits, 3, 'selection does not persist another representation');
  index.retireNativePublicationInventory(first);
  assert.equal(commits, 4, 'owner removal and reference removal share one transaction');
  assert.deepEqual(index.nativePublicationReferenceOwners('holding', holding), [second]);
  assert.deepEqual(index.pendingPublications(), [second, unrelated]);
  assert(Object.isFrozen(index.nativePublicationReferenceOwners('holding', holding)));
});

for (const [type, name] of [['TABLE', 'native_publication_references'],
  ['INDEX', 'native_publication_reference_owners'], ['TRIGGER', 'native_publication_references_insert'],
  ['TRIGGER', 'native_publication_references_update']]) {
test(`native reference coverage refuses adopted ${name} loss`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-reference-loss-'));
  t.after(() => rm(directory, {recursive: true}));
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  const index = await openDeliveryAttemptIndex(path, {...options, create: true, initializeEmpty: true});
  index.stageNativePublicationInventory(referenceInventory('1', 'a', 'b')); index.close();
  const database = new DatabaseSync(path);
  try {database.exec(`DROP ${type} ${name}`);} finally {database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path, options), {code: 'DeliveryAttemptIndexUnavailable'});
  const after = new DatabaseSync(path, {readOnly: true});
  try {assert.equal(after.prepare('SELECT version FROM coverage').get().version, 15);
    assert.equal(after.prepare('SELECT inventory_wire FROM native_publication_inventories').get().inventory_wire,
      referenceInventory('1', 'a', 'b').inventory_wire);}
  finally {after.close();}
});
}

function nativeIndexOriginal(label = '1') {
  const digits = value => value.length === 64 ? value : value.repeat(64);
  const cid = value => 'sha256:' + digits(value);
  const key = {metadata_key:digits(label),namespace_id:'original namespace',
    authority_scope_cid:cid('a'),run_cid:cid(label)};
  const wire = JSON.stringify({index:label});
  const body = {semantic_cid:cid(label),name:'public_index_entry',wire,byte_count:Buffer.byteLength(wire)};
  const inventory = {public_index_cid:body.semantic_cid,inventory_wire:JSON.stringify({
    contract_objects:[{semantic_cid:body.semantic_cid}],physical_holding_cids:[],
  })};
  const bindings = [{result_definition_cid:cid('b'),binding_cid:cid('c'),material_cid:cid('d')}];
  const allowance = {objects:1,bytes:body.byte_count};
  const progress = {attemptCid:'sha256:e'+digits(label).slice(1),recordCid:'sha256:9'+digits(label).slice(1)};
  return {key,body,inventory,bindings,allowance,progress};
}

function prepareNativeIndexOriginal(index, original) {
  const first = 'sha256:f'+original.key.metadata_key.slice(1);
  index.putPublicationContracts([
    {semantic_cid:original.progress.attemptCid,name:'publication_attempt',wire:'{}',byte_count:2},
    {semantic_cid:first,name:'publication_record',wire:'{}',byte_count:2},
    {semantic_cid:original.progress.recordCid,name:'publication_record',wire:'{}',byte_count:2},
  ],{objects:3,bytes:6},{kind:'initial-attempt',attemptCid:original.progress.attemptCid,runCid:original.key.run_cid,
    records:[{sequence:0,recordCid:first,previousCid:null},{sequence:1,recordCid:original.progress.recordCid,previousCid:first}]});
}

const commitNativeIndexOriginal = (index, original) => index.commitNativePublicationIndex(
  original.key,original.body,original.inventory,original.bindings,original.allowance,original.progress);

test('native Index commits its complete key body inventory and payload owners atomically', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-index-atomic-'));
  let index, armed = false, commits = 0;
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = Reflect.apply(exec,this,[sql]); if (armed && sql === 'COMMIT') commits++; return result;
  });
  t.after(async () => {armed = false; index?.close(); await rm(directory,{recursive:true});});
  const path = join(directory,'index.sqlite3'),options = {create:false,maxEntries:8,maxWireBytes:4096};
  index = await openDeliveryAttemptIndex(path,{...options,create:true,initializeEmpty:true});
  const original = nativeIndexOriginal();
  prepareNativeIndexOriginal(index,original);
  const before = index.publicationUsage();
  armed = true;
  assert.equal(commitNativeIndexOriginal(index,original).created,true);
  assert.equal(commits,1);
  const selected = index.nativePublicationIndex(original.key.metadata_key);
  assert.deepEqual(selected,{...original.key,body:original.body,ack_revision:1});
  assert(Object.isFrozen(selected) && Object.isFrozen(selected.body));
  assert.deepEqual(index.nativePublicationInventory(original.body.semantic_cid),original.inventory);
  assert.deepEqual(index.pendingPublications(),[original.inventory]);
  assert.deepEqual(index.nativePublicationReferenceOwners('contract',original.body.semantic_cid),[original.inventory]);
  assert.deepEqual(index.nativePublicationMaterialReferences(original.bindings[0].material_cid),[
    {...original.bindings[0],public_index_cid:original.body.semantic_cid,metadata_key:original.key.metadata_key},
  ]);
  assert.equal(commitNativeIndexOriginal(index,original).created,false);
  assert.equal(commits,1,'an already acknowledged original is not a new mutation');
  assert.throws(() => commitNativeIndexOriginal(index,{...nativeIndexOriginal('2'),key:original.key}),
    {code:'PublicationCommitConflict'});
  assert.throws(() => commitNativeIndexOriginal(index,{...original,key:{...original.key,namespace_id:'foreign'}}),
    {code:'PublicationCommitConflict'});
  assert.equal(index.publicationUsage().objects,before.objects+1);
  assert.equal(index.publicationUsage().bytes,before.bytes+original.body.byte_count);
  armed = false; index.close();
  index = await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.nativePublicationIndex(original.key.metadata_key),selected);
  armed = true;
  const confirmed = index.confirmNativePublicationIndex(selected);
  assert.equal(confirmed.ack_revision,2);
  assert.equal(commits,2,'independent durable confirmation is one real same-original write');
  index.retireNativePublicationInventory(original.inventory,{metadata_key:original.key.metadata_key,run_cid:original.key.run_cid});
  assert.equal(index.nativePublicationIndex(original.key.metadata_key),undefined);
  assert.deepEqual(index.nativePublicationMaterialReferences(original.bindings[0].material_cid),[]);
  assert.deepEqual(index.publicationContract(original.body.semantic_cid),original.body,'physical metadata reclamation remains separate');
  assert.throws(() => commitNativeIndexOriginal(index,original),{code:'PublicationMetadataDeleted'});
  index.removePublicationContract(original.body);
  assert.equal(index.publicationUsage().objects,before.objects);
});

test('native Index quota and duplicate binding refusal install no partial owner', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-index-refusal-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory,{recursive:true});});
  index = await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
    {create:true,initializeEmpty:true,maxEntries:8,maxWireBytes:4096});
  const original = nativeIndexOriginal();
  prepareNativeIndexOriginal(index,original);
  const before = index.publicationUsage();
  assert.throws(() => commitNativeIndexOriginal(index,{...original,allowance:{objects:0,bytes:0}}),{code:'PublicationStoreCapacity'});
  assert.throws(() => commitNativeIndexOriginal(index,{...original,bindings:[original.bindings[0],original.bindings[0]]}),
    {code:'InvalidDeliveryAttemptIndex'});
  assert.equal(index.nativePublicationIndex(original.key.metadata_key),undefined);
  assert.equal(index.publicationContract(original.body.semantic_cid),undefined);
  assert.deepEqual(index.pendingPublications(),[]);
  assert.deepEqual(index.nativePublicationMaterialReferences(original.bindings[0].material_cid),[]);
  assert.equal(index.publicationUsage().objects,before.objects);
});

for (const phase of ['commit','confirm']) for (const afterCommit of [false,true]) {
test(`native Index ${phase} retains its ${afterCommit ? 'committed' : 'rolled-back'} Unknown original`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-index-unknown-'));
  let index, armed = false, lost = false;
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed && !lost && sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost native Index original reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  t.after(async()=>{armed=false;index?.close();await rm(directory,{recursive:true});});
  index = await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
    {create:true,initializeEmpty:true,maxEntries:8,maxWireBytes:4096});
  const original = nativeIndexOriginal();
  prepareNativeIndexOriginal(index,original);
  const before = index.publicationUsage();
  if (phase === 'confirm') commitNativeIndexOriginal(index,original);
  const selected = phase === 'confirm' ? index.nativePublicationIndex(original.key.metadata_key) : undefined;
  const mutate = () => phase === 'commit' ? commitNativeIndexOriginal(index,original) : index.confirmNativePublicationIndex(selected);
  armed = true;
  assert.throws(mutate,error=>error.outcome==='unknown'); assert(lost);
  assert.throws(() => index.nativePublicationIndex(original.key.metadata_key),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(() => commitNativeIndexOriginal(index,nativeIndexOriginal('2')),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  const confirmed = mutate();
  if (phase === 'commit') assert.equal(confirmed.created,true,'the SAME initial publication is retained through confirmation');
  assert.deepEqual(index.nativePublicationIndex(original.key.metadata_key).body,original.body);
  assert.equal(index.publicationUsage().objects,before.objects+1);
  assert.deepEqual(index.pendingPublications(),[original.inventory]);
});
}

for (const missing of ['native_publication_indexes','native_publication_materials']) {
test(`native Index refuses adopted ${missing} loss`, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-index-missing-'));
  t.after(() => rm(directory,{recursive:true}));
  const path = join(directory,'index.sqlite3'),options = {create:false,maxEntries:8,maxWireBytes:4096};
  const index = await openDeliveryAttemptIndex(path,{...options,create:true,initializeEmpty:true});
  const original=nativeIndexOriginal();prepareNativeIndexOriginal(index,original);
  commitNativeIndexOriginal(index,original); index.close();
  const db = new DatabaseSync(path);
  try {db.exec('DROP TABLE '+missing);} finally {db.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

test('native Index material lookup pages only the selected material owners', async t => {
  const directory = await mkdtemp(join(tmpdir(),'actql-native-material-pages-'));
  let index,armed=false;
  const reads=[],prepare=DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql){
    const statement=Reflect.apply(prepare,this,[sql]),all=statement.all;
    if(sql.includes('FROM native_publication_materials m'))t.mock.method(statement,'all',function(...args){
      const rows=Reflect.apply(all,this,args);if(armed)reads.push({args,rows});return rows;
    });
    return statement;
  });
  t.after(async()=>{armed=false;index?.close();await rm(directory,{recursive:true});});
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
    {create:true,initializeEmpty:true,maxEntries:300,maxWireBytes:4096});
  const selected=[];
  for(let n=1;n<=69;n++){
    let original=nativeIndexOriginal(n.toString(16).padStart(64,'0'));
    if(n>65)original={...original,bindings:[{...original.bindings[0],material_cid:'sha256:'+'e'.repeat(64)}]};
    prepareNativeIndexOriginal(index,original);
    commitNativeIndexOriginal(index,original);if(n<=65)selected.push(original.body.semantic_cid);
  }
  armed=true;
  const first=index.nativePublicationMaterialReferences('sha256:'+'d'.repeat(64));
  const last=first.at(-1);
  const second=index.nativePublicationMaterialReferences('sha256:'+'d'.repeat(64),last.public_index_cid,last.result_definition_cid);
  assert.deepEqual([first.length,second.length],[64,1]);
  assert.deepEqual([...first,...second].map(row=>row.public_index_cid),selected);
  assert.deepEqual(reads.map(read=>read.rows.length),[64,1]);
  assert(reads.every(read=>read.args[0]==='sha256:'+'d'.repeat(64)));
  assert(first.every(Object.isFrozen)&&Object.isFrozen(first));
  const count=reads.length;
  assert.throws(()=>index.nativePublicationMaterialReferences('sha256:'+'d'.repeat(64),last.public_index_cid),
    {code:'InvalidDeliveryAttemptIndex'});
  assert.equal(reads.length,count,'invalid partial cursor performs no native read');
});

test('native publication inventory and pending lookup share one commit without a shadow body',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-native-inventory-'));
  let index,armed=false,commits=0;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&sql==='COMMIT')commits++;
    return Reflect.apply(exec,this,[sql]);
  });
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:1,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);index.migratePublicationRecovery([]);
  const original={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"original":1}'};
  armed=true;index.stageNativePublicationInventory(original);
  assert.equal(commits,1);
  assert.deepEqual(index.pendingPublications(),[original]);
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid),original);
  index.stageNativePublicationInventory(original);assert.equal(commits,1);
  index.finishPublicationInventory(original);assert.equal(commits,2);
  assert.deepEqual(index.pendingPublications(),[]);
  assert.deepEqual(index.nativePublicationInventories(),[original]);
  assert.throws(()=>index.stageNativePublicationInventory({...original,public_index_cid:'sha256:'+'2'.repeat(64)}),
    {code:'DeliveryAttemptIndexLimit'});
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.equal(commits,2,'opening does not rewrite completed originals');
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid),original);
  assert.throws(()=>index.retireNativePublicationInventory({...original,inventory_wire:'{"different":1}'}),
    {code:'PublicationMetadataInventoryConflict'});
  index.retireNativePublicationInventory(original);assert.equal(commits,3);
  index.retireNativePublicationInventory(original);assert.equal(commits,3);
  assert.deepEqual(index.nativePublicationInventories(),[]);
});

for(const phase of ['stageNativePublicationInventory','finishPublicationInventory','retireNativePublicationInventory']) {
for(const afterCommit of [false,true]) {
test(`native publication inventory ${phase} retains ${afterCommit?'committed':'rolled-back'} Unknown original`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-native-inventory-unknown-'));
  let index,armed=false,lost=false;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost same native inventory reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);index.migratePublicationRecovery([]);
  const original=referenceInventory('1','a','b');
  if(phase!=='stageNativePublicationInventory')index.stageNativePublicationInventory(original);
  armed=true;
  assert.throws(()=>index[phase](original),error=>error.outcome==='unknown');
  assert.throws(()=>index.nativePublicationInventory(original.public_index_cid),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(()=>index[phase]({...original,inventory_wire:'{"foreign":1}'}),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index[phase](original);
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid),phase==='retireNativePublicationInventory'?undefined:original);
  assert.deepEqual(index.pendingPublications(),phase==='stageNativePublicationInventory'?[original]:[]);
  assert.deepEqual(index.nativePublicationReferenceOwners('holding','sha256:'+'b'.repeat(64)),
    phase==='retireNativePublicationInventory'?[]:[original]);
});
}}

for(const missing of ['native_publication_inventories','native_publication_inventory_usage']) {
test(`native publication inventory refuses missing adopted ${missing}`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-native-inventory-missing-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);index.migratePublicationRecovery([]);index.close();
  const database=new DatabaseSync(path);
  try{database.exec(`DROP TABLE ${missing}`);}finally{database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

test('publication recovery coverage retains only pending originals across reopen', async t => {
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-recovery-'));
  let index;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'), options={create:false,maxEntries:1,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);
  const entry={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"inventory":1}'};
  assert.equal(index.needsPublicationRecoveryMigration(),true);
  assert.throws(()=>index.pendingPublications(),{code:'DeliveryAttemptIndexUnavailable'});
  index.migratePublicationRecovery([entry]);
  assert.equal(index.needsPublicationRecoveryMigration(),false);
  assert.deepEqual(index.pendingPublications(),[entry]);
  assert.throws(()=>index.stagePublicationInventory({...entry,inventory_wire:'{"foreign":1}'}),
    {code:'PublicationMetadataInventoryConflict'});
  assert.throws(()=>index.stagePublicationInventory({...entry,public_index_cid:'sha256:'+'2'.repeat(64)}),
    {code:'DeliveryAttemptIndexLimit'});
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.needsPublicationRecoveryMigration(),false);
  assert.deepEqual(index.pendingPublications(),[entry]);
  index.finishPublicationInventory(entry);
  assert.deepEqual(index.pendingPublications(),[]);
  index.finishPublicationInventory(entry);
  index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.pendingPublications(),[]);
});

for(const missing of ['publication_recovery','pending_publications']) {
test(`publication recovery refuses missing adopted ${missing} instead of rebuilding history`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-recovery-missing-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  const index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);index.migratePublicationRecovery([]);index.close();
  const database=new DatabaseSync(path);
  try{database.exec(`DROP TABLE ${missing}`);}finally{database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
});
}

for(const phase of ['stage','finish'])for(const afterCommit of [false,true]) {
test(`publication recovery ${phase} retains same original after ${afterCommit?'committed':'rolled-back'} lost reply`,async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-recovery-unknown-'));
  let index,armed=false,lost=false;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const exec=DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw Object.assign(new Error('lost same publication recovery reply'),{code:'EIO'});
    }
    return Reflect.apply(exec,this,[sql]);
  });
  index=await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
    {create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);index.migratePublicationRecovery([]);
  const entry={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"inventory":1}'};
  if(phase==='finish')index.stagePublicationInventory(entry);
  const change=()=>index[phase==='stage'?'stagePublicationInventory':'finishPublicationInventory'](entry);
  armed=true;
  assert.throws(change,error=>error.outcome==='unknown');
  assert.throws(()=>index.stagePublicationInventory({...entry,public_index_cid:'sha256:'+'2'.repeat(64)}),
    {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  change();
  assert.deepEqual(index.pendingPublications(),phase==='stage'?[entry]:[]);
  index.finishPublicationInventory(entry);
  assert.deepEqual(index.pendingPublications(),[]);
});
}

for (const missing of ['publication_contracts','publication_usage']) {
  test(`adopted publication metadata refuses missing ${missing} without resetting coverage`,async t => {
    const directory = await mkdtemp(join(tmpdir(),'actql-native-publication-missing-'));
    t.after(() => rm(directory,{recursive:true}));
    const path = join(directory,'index.sqlite3');
    const options = {create:false,maxEntries:2,maxWireBytes:4096};
    const index = await openDeliveryAttemptIndex(path,{...options,create:true});
    index.migrate([]);
    index.close();
    const database = new DatabaseSync(path);
    try {database.exec(`DROP TABLE ${missing}`);} finally {database.close();}
    await assert.rejects(openDeliveryAttemptIndex(path,options),{code:'DeliveryAttemptIndexUnavailable'});
  });
}

for (const afterCommit of [false,true]) {
  test(`native publication retirement confirms the same ${afterCommit ? 'committed' : 'rolled-back'} removal without refunding twice`,async t => {
    const directory = await mkdtemp(join(tmpdir(),'actql-native-publication-retirement-'));
    let index, armed = false, lost = false;
    t.after(async () => { index?.close(); await rm(directory,{recursive:true}); });
    const exec = DatabaseSync.prototype.exec;
    t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
      if (armed && !lost && sql === 'COMMIT') {
        lost = true;
        if (afterCommit) Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('lost original metadata removal reply'),{code:'EIO'});
      }
      return Reflect.apply(exec,this,[sql]);
    });
    index = await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
      {create:true,maxEntries:2,maxWireBytes:4096});
    index.migrate([]);
    // Existing physical-index boundary; no Run/Account/semantic issuer.
    const entry = {semantic_cid:'sha256:'+'1'.repeat(64),name:'run_invocation',wire:'{}',byte_count:2};
    const other = {...entry,semantic_cid:'sha256:'+'2'.repeat(64)};
    index.putPublicationContracts([entry,other],{objects:2,bytes:4});
    armed = true;
    assert.throws(() => index.removePublicationContract(entry),
      error => error.outcome === 'unknown');
    assert.throws(() => index.removePublicationContract(other),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
    assert.equal(index.removePublicationContract(entry).objects,1);
    assert.equal(index.publicationUsage().bytes,2);
    assert.equal(index.publicationContract(entry.semantic_cid),undefined);
    assert.deepEqual(index.publicationContract(other.semantic_cid),other);
    assert.equal(index.removePublicationContract(entry).objects,1);
    assert.equal(index.publicationUsage().bytes,2,'idempotent removal does not refill capacity twice');
  });
}

test('same original indexed removal retries after a lost COMMIT reply without decrementing twice', async t => {
  const directory = await mkdtemp(join(tmpdir(),'actql-delivery-index-removal-'));
  let index;
  t.after(async () => { index?.close(); await rm(directory,{recursive:true}); });
  const original = DatabaseSync.prototype.exec;
  let armed = false, lost = false;
  DatabaseSync.prototype.exec = function(sql) {
    const value = Reflect.apply(original,this,[sql]);
    if (armed && !lost && sql === 'COMMIT') {
      lost = true;
      throw Object.assign(new Error('lost same removal COMMIT reply'),{code:'EIO'});
    }
    return value;
  };
  try { index = await openDeliveryAttemptIndex(join(directory,'index.sqlite3'),
    {create:true,maxEntries:2,maxWireBytes:4096}); }
  finally { DatabaseSync.prototype.exec = original; }
  index.migrate([]);
  // Private physical-index fixture, not a grant/Run issuer or stream dispatch.
  const cid = value => 'sha256:'+value.repeat(64);
  const row = {logical_key:'one',attempt_cid:cid('1'),grant_cid:cid('2'),
    run_cid:cid('3'),attempt_wire:'{}',grant_wire:'{}'};
  index.claim(row,1);
  index.finish(row.logical_key,row.attempt_cid);
  armed = true;
  assert.throws(() => index.forgetRun(row.run_cid),
    error => error.code === 'DeliveryAttemptIndexCommitOutcomeUnknown' && error.outcome === 'unknown');
  assert.throws(() => index.claim({...row,logical_key:'replacement'},1),
    {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(() => index.forgetRun(cid('4')),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index.forgetRun(row.run_cid);
  assert.equal(index.lookup(row.logical_key),undefined);
  index.forgetRun(row.run_cid);
  const next = {...row,logical_key:'next',attempt_cid:cid('5')};
  assert.equal(index.claim(next,1).created,true);
  assert.throws(() => index.claim({...next,logical_key:'over-limit',attempt_cid:cid('6')},1),
    {code:'DeliveryGrantUseLimit'});
});

test('joint START retains its initial original in one native claim and no open-time pending scan', async t => {
  const directory = await mkdtemp(join(tmpdir(),'actql-delivery-index-start-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory,{recursive:true});});
  const original = DatabaseSync.prototype.exec;
  let commits = 0, armed = false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    if (armed && sql === 'COMMIT') commits++;
    return Reflect.apply(original,this,[sql]);
  });
  const path = join(directory,'index.sqlite3');
  index = await openDeliveryAttemptIndex(path,{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);
  const cid = value => 'sha256:'+value.repeat(64);
  const row = {logical_key:'one',attempt_cid:cid('1'),grant_cid:cid('2'),
    run_cid:cid('3'),attempt_wire:'{"attempt":1}',grant_wire:'{"grant":1}'};
  const initialWire = '{"initial":1}';
  armed = true;
  assert.equal(index.claim(row,1,initialWire,cid('8')).created,true);
  assert.equal(commits,1);
  assert.deepEqual(index.pending(),[]);
  assert.equal(index.lookup(row.logical_key).initial_wire,initialWire);
  assert.deepEqual(index.contract(row.attempt_cid),{name:'delivery_attempt',wire:row.attempt_wire});
  assert.deepEqual(index.contract(row.grant_cid),{name:'result_read_grant',wire:row.grant_wire});
  assert.deepEqual(index.contract(cid('8')),{name:'delivery_record',wire:initialWire});
  assert.equal(index.claim(row,1,initialWire).created,false);
  assert.equal(commits,1,'same claim is not another durable mutation');
  index.close();
  index = await openDeliveryAttemptIndex(path,{create:false,maxEntries:2,maxWireBytes:4096});
  assert.equal(index.lookup(row.logical_key).initial_wire,initialWire);
  assert.deepEqual(index.pending(),[]);
  assert.equal(commits,1,'reopening complete metadata does not replay historical claims');
  assert.throws(() => index.claim({...row,logical_key:'two',attempt_cid:cid('4')},1,initialWire),
    {code:'DeliveryGrantUseLimit'});
  index.forgetRun(row.run_cid);
  for(const id of [row.attempt_cid,row.grant_cid,cid('8')]) assert.equal(index.contract(id),undefined);
  assert.equal(index.claim({...row,logical_key:'two',attempt_cid:cid('4')},1,initialWire).created,true);
});

test('adopted initial-record coverage is not recreated from a missing table', async t => {
  const directory = await mkdtemp(join(tmpdir(),'actql-delivery-index-missing-starts-'));
  t.after(() => rm(directory,{recursive:true}));
  const path = join(directory,'index.sqlite3');
  const index = await openDeliveryAttemptIndex(path,{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);
  index.close();
  const database = new DatabaseSync(path);
  try {database.exec('DROP TABLE initial_records');} finally {database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,{create:false,maxEntries:2,maxWireBytes:4096}),
    {code:'DeliveryAttemptIndexUnavailable'});
});

test('adopted completion storage is not recreated when its original table is missing',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-delivery-index-missing-end-'));
  t.after(()=>rm(directory,{recursive:true}));
  const path=join(directory,'index.sqlite3');
  const index=await openDeliveryAttemptIndex(path,{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);index.close();
  const database=new DatabaseSync(path);
  try {database.exec('DROP TABLE completions');} finally {database.close();}
  await assert.rejects(openDeliveryAttemptIndex(path,{create:false,maxEntries:2,maxWireBytes:4096}),
    {code:'DeliveryAttemptIndexUnavailable'});
});

for(const afterCommit of [false,true]) {
  test(`native initial confirmation retains the same original across ${afterCommit?'after':'before'} COMMIT reply loss`,async t=>{
    const directory=await mkdtemp(join(tmpdir(),'actql-delivery-index-confirm-'));
    let index,armed=false,lost=false;
    t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
    const exec=DatabaseSync.prototype.exec;
    t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
      if(armed && !lost && sql==='COMMIT') {
        lost=true;
        if(afterCommit) Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('lost original initial ACK'),{code:'EIO'});
      }
      return Reflect.apply(exec,this,[sql]);
    });
    const path=join(directory,'index.sqlite3'), options={create:false,maxEntries:2,maxWireBytes:4096};
    index=await openDeliveryAttemptIndex(path,{...options,create:true});
    index.migrate([]);
    const cid=value=>'sha256:'+value.repeat(64);
    const row={logical_key:'one',attempt_cid:cid('1'),grant_cid:cid('2'),run_cid:cid('3'),
      attempt_wire:'{}',grant_wire:'{}'};
    index.claim(row,1,'{"initial":1}',cid('4'));index.close();
    index=await openDeliveryAttemptIndex(path,options);
    armed=true;
    assert.throws(()=>index.confirmRecord(row.attempt_cid,cid('4'),'{"initial":1}'),
      error=>error.code==='DeliveryAttemptIndexCommitOutcomeUnknown' && error.outcome==='unknown');
    assert.throws(()=>index.confirmRecord(row.attempt_cid,cid('4'),'different'),
      {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
    assert.throws(()=>index.claim({...row,logical_key:'replacement',attempt_cid:cid('5')},1),
      {code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
    assert.equal(index.confirmRecord(row.attempt_cid,cid('4'),'{"initial":1}'),true);
    index.close();
    const database=new DatabaseSync(path,{readOnly:true});
    try {
      assert.equal(database.prepare('SELECT ack_revision FROM initial_records').get().ack_revision,afterCommit?3:2);
      assert.equal(database.prepare('SELECT uses FROM grant_uses').get().uses,1);
    } finally {database.close();}
  });
}

test('completion receipt statement is acquired once per original connection', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-completion-statement-'));
  const path = join(directory, 'index.sqlite3');
  const options = {create:true, maxEntries:3, maxWireBytes:4096};
  const sql = 'SELECT receipt_wire FROM completions WHERE receipt_cid=? LIMIT 1';
  const original = DatabaseSync.prototype.prepare;
  let prepared = 0, index;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(selected) {
    if (selected === sql) prepared++;
    return Reflect.apply(original, this, [selected]);
  });
  t.after(async () => {index?.close(); await rm(directory, {recursive:true});});
  index = await openDeliveryAttemptIndex(path, options);
  index.migrate([]);
  assert.equal(prepared, 0, 'opening does not prepare an unused completion lookup');
  const cid = value => 'sha256:' + value.repeat(64);
  const claim = (key, attempt, run, initial) => {
    index.claim({logical_key:key, attempt_cid:cid(attempt), grant_cid:cid('f'),
      run_cid:cid(run), attempt_wire:'{}', grant_wire:'{}'}, 3, '{}', cid(initial));
  };
  claim('first', '1', '2', '3');
  claim('second', '4', '5', '6');
  claim('third', '7', '8', '9');
  const first = {attempt_cid:cid('1'), prior_cid:cid('3'), record_cid:cid('a'),
    record_wire:'{"record":1}', receipt_cid:cid('e'), receipt_wire:'{"receipt":1}'};
  const second = {...first, attempt_cid:cid('4'), prior_cid:cid('6'),
    record_cid:cid('b'), record_wire:'{"record":2}'};
  index.complete(first);
  index.complete(second);
  assert.equal(prepared, 1, 'distinct attempts reuse the same connection-owned lookup');
  const third = {...first, attempt_cid:cid('7'), prior_cid:cid('9'),
    record_cid:cid('c'), record_wire:'{"record":3}'};
  assert.throws(() => index.complete({...third, receipt_wire:'{"different":true}'}),
    {code:'DeliveryRecordConflict'});
  assert.equal(index.completion(third.attempt_cid), undefined);
  index.close();
  assert.throws(() => index.complete(third), {code:'DeliveryAttemptIndexClosed'});
  assert.equal(prepared, 1, 'closed owners cannot prepare or reuse the lookup');
  index = await openDeliveryAttemptIndex(path, {...options, create:false});
  assert.equal(prepared, 1, 'a new connection keeps its lookup unprepared until needed');
  index.complete(third);
  assert.equal(prepared, 2, 'the new connection acquires its own statement');
  for (const end of [first, second, third]) {
    assert.equal(index.completion(end.attempt_cid).record_cid, end.record_cid);
    assert.equal(index.completion(end.attempt_cid).ack_revision, 1);
  }
});

test('native completion CAS and retirement retain the other original Run and exact grant use',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-delivery-index-end-retirement-'));
  let index;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3');
  index=await openDeliveryAttemptIndex(path,{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);
  const cid=value=>'sha256:'+value.repeat(64);
  const row={logical_key:'one',attempt_cid:cid('1'),grant_cid:cid('2'),run_cid:cid('3'),
    attempt_wire:'{}',grant_wire:'{}'};
  const other={...row,logical_key:'other',attempt_cid:cid('7'),run_cid:cid('8')};
  index.claim(row,2,'{"initial":1}',cid('4'));
  index.claim(other,2,'{"initial":2}',cid('9'));
  const end={attempt_cid:row.attempt_cid,prior_cid:cid('4'),record_cid:cid('5'),
    record_wire:'{"end":1}',receipt_cid:cid('6'),receipt_wire:'{"receipt":1}'};
  assert.throws(()=>index.complete({...end,prior_cid:cid('9')}),{code:'DeliveryRecordConflict'});
  index.complete(end);
  assert.throws(()=>index.complete({...end,receipt_wire:'{"receipt":2}'}),{code:'DeliveryRecordConflict'});
  index.complete({...end,attempt_cid:other.attempt_cid,prior_cid:cid('9'),record_cid:cid('a'),
    record_wire:'{"end":2}',receipt_cid:cid('b'),receipt_wire:'{"receipt":2}'});
  index.forgetRun(row.run_cid);
  for(const id of [row.attempt_cid,cid('4'),cid('5'),cid('6')]) assert.equal(index.contract(id),undefined);
  assert.equal(index.completion(other.attempt_cid).record_cid,cid('a'));
  assert.equal(index.contract(cid('b')).wire,'{"receipt":2}');
  index.close();
  const database=new DatabaseSync(path,{readOnly:true});
  try {
    assert.equal(database.prepare('SELECT entries FROM coverage').get().entries,1);
    assert.equal(database.prepare('SELECT uses FROM grant_uses').get().uses,1);
    assert.equal(database.prepare('SELECT count(*) AS n FROM completions').get().n,1);
  } finally {database.close();}
});

for (const legacy of [false, true]) {
  test(legacy ? 'version 14 completion storage is rejected without migration or byte changes' : 'distinct delivery attempts retain one immutable receipt across reopen', async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-shared-receipt-'));
    const path = join(directory, 'index.sqlite3');
    const options = {create:true, maxEntries:3, maxWireBytes:4096};
    let index = await openDeliveryAttemptIndex(path, options);
    t.after(async () => {index?.close(); await rm(directory, {recursive:true});});
    index.migrate([]);
    const cid = digit => 'sha256:' + digit.repeat(64);
    const first = {logical_key:'first', attempt_cid:cid('1'), grant_cid:cid('2'),
      run_cid:cid('3'), attempt_wire:'{"attempt":1}', grant_wire:'{"grant":1}'};
    const second = {...first, logical_key:'second', attempt_cid:cid('7'), run_cid:cid('8')};
    const receipt = {receipt_cid:cid('6'), receipt_wire:'{"receipt":"same immutable delivery"}'};
    const end = {attempt_cid:first.attempt_cid, prior_cid:cid('4'), record_cid:cid('5'),
      record_wire:'{"record":1}', ...receipt};
    index.claim(first, 3, '{"initial":1}', cid('4'));
    index.complete(end);
    index.complete(end);
    let original = index.completion(first.attempt_cid);
    assert.equal(original.ack_revision, 2);
    index.close();
    if (legacy) {
      const db = new DatabaseSync(path);
      try {
        // Exact prior private format, containing a real acknowledged original.
        db.exec(`BEGIN IMMEDIATE;
          ALTER TABLE completions RENAME TO fixture_completions;
          CREATE TABLE completions (
  attempt_cid TEXT PRIMARY KEY REFERENCES attempts(attempt_cid) ON DELETE CASCADE,
  record_cid TEXT NOT NULL UNIQUE, record_wire TEXT NOT NULL,
  receipt_cid TEXT NOT NULL UNIQUE, receipt_wire TEXT NOT NULL,
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
) WITHOUT ROWID;
          INSERT INTO completions SELECT * FROM fixture_completions;
          DROP TABLE fixture_completions;
          UPDATE coverage SET version=14 WHERE id=1;
          COMMIT;`);
      } finally {db.close();}
    }
    if (legacy) {
      const before = await readFile(path);
      await assert.rejects(openDeliveryAttemptIndex(path, {...options, create:false}),
        {code:'DeliveryAttemptIndexUnavailable'});
      assert.deepEqual(await readFile(path), before);
      return;
    }
    index = await openDeliveryAttemptIndex(path, {...options, create:false});
    assert.deepEqual(index.completion(first.attempt_cid), original);
    index.claim(second, 3, '{"initial":2}', cid('9'));
    const other = {...end, attempt_cid:second.attempt_cid, prior_cid:cid('9'),
      record_cid:cid('a'), record_wire:'{"record":2}'};
    await Promise.all([Promise.resolve().then(() => index.complete(other)),
      Promise.resolve().then(() => index.complete(end))]);
    assert.equal(index.completion(first.attempt_cid).ack_revision, 3);
    original = index.completion(first.attempt_cid);
    assert.equal(index.completion(second.attempt_cid).ack_revision, 1);
    assert.deepEqual(index.completion(first.attempt_cid), original);
    assert.throws(() => index.complete({...other, receipt_wire:'{"different":true}'}),
      {code:'DeliveryRecordConflict'});
    const pending = {...first, logical_key:'pending', attempt_cid:cid('b'), run_cid:cid('c')};
    index.claim(pending, 3, '{"initial":3}', cid('d'));
    assert.throws(() => index.complete({...end, attempt_cid:pending.attempt_cid,
      prior_cid:cid('d'), record_cid:cid('e'), receipt_wire:'{"different":true}'}),
      {code:'DeliveryRecordConflict'});
    assert.equal(index.completion(pending.attempt_cid), undefined);
    index.close();
    for (let reopen = 0; reopen < 2; reopen++) {
      index = await openDeliveryAttemptIndex(path, {...options, create:false});
      assert.deepEqual(index.completion(first.attempt_cid), original);
      assert.equal(index.completion(second.attempt_cid).receipt_wire, receipt.receipt_wire);
      assert.equal(index.completion(pending.attempt_cid), undefined);
      assert.equal(index.lookup(pending.logical_key).attempt_cid, pending.attempt_cid);
      assert.equal(index.contract(receipt.receipt_cid).wire, receipt.receipt_wire);
      index.close();
    }
    index = await openDeliveryAttemptIndex(path, {...options, create:false});
    index.forgetRun(first.run_cid);
    assert.equal(index.completion(first.attempt_cid), undefined);
    assert.equal(index.completion(second.attempt_cid).record_cid, other.record_cid);
    assert.equal(index.contract(receipt.receipt_cid).wire, receipt.receipt_wire);
    index.close();
    const db = new DatabaseSync(path, {readOnly:true});
    try {
      assert.equal(db.prepare('SELECT version FROM coverage').get().version, 15);
      assert.equal(db.prepare('SELECT count(*) AS n FROM completions').get().n, 1);
      assert.equal(db.prepare('SELECT uses FROM grant_uses').get().uses, 2);
    } finally {db.close();}
  });
}

for (const oldVersion of Array.from({length: 14}, (_, i) => i + 1)) {
  test(`private format ${oldVersion} is refused untouched without upgrade or cleanup`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-format-refusal-'));
    t.after(() => rm(directory, {recursive: true}));
    const path = join(directory, 'index.sqlite3');
    const options = {create: false, maxEntries: 4, maxWireBytes: 4096};
    const index = await openDeliveryAttemptIndex(path, {...options, create: true, initializeEmpty: true});
    index.stageNativePublicationInventory(referenceInventory('1', 'a', 'b'));
    index.close();
    const old = new DatabaseSync(path);
    try { old.prepare('UPDATE coverage SET version=?').run(oldVersion); } finally { old.close(); }
    const before = await readFile(path);
    const exec = DatabaseSync.prototype.exec, statements = [];
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      statements.push(sql); return Reflect.apply(exec, this, [sql]);
    });
    for (const create of [false, true]) {
      await assert.rejects(openDeliveryAttemptIndex(path, {...options, create}),
        {code: 'DeliveryAttemptIndexUnavailable'});
      assert.deepEqual(await readFile(path), before, 'refusal preserves original database bytes');
    }
    assert.deepEqual(statements, [], 'no persistent PRAGMA, transaction, DDL, or cleanup is attempted');
    const retained = new DatabaseSync(path, {readOnly: true});
    try {
      assert.equal(retained.prepare('SELECT version FROM coverage').get().version, oldVersion);
      assert.equal(retained.prepare('SELECT inventory_wire FROM native_publication_inventories').get().inventory_wire,
        referenceInventory('1', 'a', 'b').inventory_wire);
    } finally { retained.close(); }
  });
}

test('current private format reopens without rewriting or scanning inventory history', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-delivery-current-reopen-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory, {recursive: true});});
  const path = join(directory, 'index.sqlite3');
  const options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true, initializeEmpty: true});
  const original = referenceInventory('1', 'a', 'b');
  index.stageNativePublicationInventory(original); index.close();
  const exec = DatabaseSync.prototype.exec, prepare = DatabaseSync.prototype.prepare;
  const mutations = [], historyReads = [];
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (/^(?:BEGIN|CREATE|ALTER|DROP|INSERT|UPDATE|DELETE)/u.test(sql)) mutations.push(sql);
    return Reflect.apply(exec, this, [sql]);
  });
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]), all = statement.all;
    if (/FROM native_publication_inventories(?: ORDER BY| LIMIT)/u.test(sql)) {
      t.mock.method(statement, 'all', function(...args) {
        historyReads.push(sql); return Reflect.apply(all, this, args);
      });
    }
    return statement;
  });
  for (let repeat = 0; repeat < 2; repeat++) {
    index = await openDeliveryAttemptIndex(path, options);
    assert.deepEqual(index.nativePublicationInventory(original.public_index_cid), original);
    index.close();
  }
  assert.deepEqual(mutations, []);
  assert.deepEqual(historyReads, []);
});
