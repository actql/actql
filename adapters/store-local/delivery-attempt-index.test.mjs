import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

// These fixtures reconstruct an earlier private schema, rather than merely
// relabel a current database while retaining its newer adopted tables.
function removePublicationProgressSchema(database) {
  database.exec('DROP TABLE result_deletion_recovery; DROP TABLE publication_records; DROP TABLE publication_attempts');
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

test('Result cleanup lifecycle upgrades version ten into required legacy recovery once', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-recovery-v10-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory, {recursive: true});});
  const path = join(directory, 'index.sqlite3'), options = {create: false, maxEntries: 4, maxWireBytes: 4096};
  index = await openDeliveryAttemptIndex(path, {...options, create: true}); index.migrate([]); index.close();
  const database = new DatabaseSync(path);
  try {database.exec('DROP TABLE result_deletion_recovery; UPDATE coverage SET version=10 WHERE id=1');}
  finally {database.close();}
  index = await openDeliveryAttemptIndex(path, options);
  assert.equal(index.resultDeletionRecoveryRequired(), true, 'old producers did not record this cleanup lifetime');
  index.retainResultDeletionSeal(); index.close();
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

test('native publication progress upgrades version nine without re-admitting historical bodies',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-publication-progress-v9-'));
  let index; t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:4,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);
  const body={semantic_cid:'sha256:'+'a'.repeat(64),name:'invocation',wire:'{}',byte_count:2};
  index.putPublicationContracts([body],{objects:1,bytes:2});index.close();
  const database=new DatabaseSync(path);
  try{removePublicationProgressSchema(database);database.exec('UPDATE coverage SET version=9');}
  finally{database.close();}
  index=await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.publicationContract(body.semantic_cid),body);
  assert.deepEqual(index.publicationAttemptsForRun('sha256:'+'b'.repeat(64)),[]);
  assert.equal(index.publicationUsage().objects,1);
});

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

test('version eight physical capacity migration is explicit and adopted only once',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-physical-v8-'));
  let index;t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);index.close();
  const db=new DatabaseSync(path);
  try{removePublicationProgressSchema(db);db.exec('DROP TABLE physical_objects; DROP TABLE physical_object_usage; DROP TABLE physical_object_preparations; UPDATE coverage SET version=8 WHERE id=1');}finally{db.close();}
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.physicalObjectUsage().complete,0);
  const original={cid:'sha256:'+'1'.repeat(64),byte_count:13,device:'1',inode:'2'};
  index.migratePhysicalObjects([original]);index.close();index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.physicalObjectUsage().bytes,13);
  assert.throws(()=>index.migratePhysicalObjects([]),{code:'DeliveryAttemptIndexAlreadyComplete'});
  assert.deepEqual(index.physicalObject(original.cid),original);
});

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
  const original={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"original":1}'};
  if(phase!=='stageNativePublicationInventory')index.stageNativePublicationInventory(original);
  armed=true;
  assert.throws(()=>index[phase](original),error=>error.outcome==='unknown');
  assert.throws(()=>index.nativePublicationInventory(original.public_index_cid),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  assert.throws(()=>index[phase]({...original,inventory_wire:'{"foreign":1}'}),{code:'DeliveryAttemptIndexCommitOutcomeUnknown'});
  index[phase](original);
  assert.deepEqual(index.nativePublicationInventory(original.public_index_cid),phase==='retireNativePublicationInventory'?undefined:original);
  assert.deepEqual(index.pendingPublications(),phase==='stageNativePublicationInventory'?[original]:[]);
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

test('native publication inventory upgrades version6 without reclassifying its pending originals',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-native-inventory-v6-'));
  let index;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'),options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});index.migrate([]);
  const original={public_index_cid:'sha256:'+'1'.repeat(64),inventory_wire:'{"legacy":1}'};
  index.migratePublicationRecovery([original]);index.close();
  const database=new DatabaseSync(path);
  try{removePublicationProgressSchema(database);database.exec('DROP TABLE physical_objects; DROP TABLE physical_object_usage; DROP TABLE physical_object_preparations; DROP TABLE metadata_deletion_fences; DROP TABLE metadata_deletion_fence_coverage; DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; UPDATE coverage SET version=6 WHERE id=1');}
  finally{database.close();}
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.needsPublicationRecoveryMigration(),false);
  assert.deepEqual(index.pendingPublications(),[original]);
  assert.deepEqual(index.nativePublicationInventories(),[]);
  index.finishPublicationInventory(original);
});

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

test('legacy indexed attempts keep the original pending and finish protocol after additive upgrade', async t => {
  const directory = await mkdtemp(join(tmpdir(),'actql-delivery-index-legacy-'));
  let index;
  t.after(async () => {index?.close(); await rm(directory,{recursive:true});});
  const path = join(directory,'index.sqlite3');
  index = await openDeliveryAttemptIndex(path,{create:true,maxEntries:2,maxWireBytes:4096});
  index.migrate([]);
  const cid = value => 'sha256:'+value.repeat(64);
  const row = {logical_key:'legacy',attempt_cid:cid('1'),grant_cid:cid('2'),
    run_cid:cid('3'),attempt_wire:'{}',grant_wire:'{}'};
  index.claim(row,1);
  index.close();
  // Reconstruct the exact pre-extension schema, not an empty replacement DB.
  const database = new DatabaseSync(path);
  try {removePublicationProgressSchema(database);database.exec('DROP TABLE physical_objects; DROP TABLE physical_object_usage; DROP TABLE physical_object_preparations; DROP TABLE metadata_deletion_fences; DROP TABLE metadata_deletion_fence_coverage; DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions; DROP TABLE initial_records; UPDATE coverage SET version=1 WHERE id=1');}
  finally {database.close();}
  index = await openDeliveryAttemptIndex(path,{create:false,maxEntries:2,maxWireBytes:4096});
  assert.equal(index.pending().length,1);
  assert.equal(index.lookup(row.logical_key).initial_wire,null);
  index.finish(row.logical_key,row.attempt_cid);
  assert.deepEqual(index.pending(),[]);
  assert.throws(() => index.claim({...row,logical_key:'next',attempt_cid:cid('4')},1),
    {code:'DeliveryGrantUseLimit'});
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

test('version two initial records remain file-backed after additive native-original upgrade',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-delivery-index-v2-'));
  let index;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'), options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);
  const cid=value=>'sha256:'+value.repeat(64);
  const row={logical_key:'v2',attempt_cid:cid('1'),grant_cid:cid('2'),run_cid:cid('3'),attempt_wire:'{}',grant_wire:'{}'};
  index.claim(row,1,'{"initial":1}');
  index.close();
  const database=new DatabaseSync(path);
  try {removePublicationProgressSchema(database);database.exec(`DROP TABLE physical_objects; DROP TABLE physical_object_usage; DROP TABLE physical_object_preparations; DROP TABLE metadata_deletion_fences; DROP TABLE metadata_deletion_fence_coverage; DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions;
    ALTER TABLE initial_records DROP COLUMN ack_revision;
    DROP INDEX initial_record_identity;
    ALTER TABLE initial_records DROP COLUMN initial_cid; UPDATE coverage SET version=2 WHERE id=1`);}
  finally {database.close();}
  index=await openDeliveryAttemptIndex(path,options);
  assert.equal(index.lookup(row.logical_key).initial_wire,'{"initial":1}');
  assert.equal(index.lookup(row.logical_key).initial_cid,null);
  assert.equal(index.contract(row.attempt_cid),undefined,'old original still selects its file protocol');
  assert.equal(index.claim(row,1).created,false);
});

test('version three native originals survive additive completion storage without body rewrites',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-delivery-index-v3-'));
  let index;
  t.after(async()=>{index?.close();await rm(directory,{recursive:true});});
  const path=join(directory,'index.sqlite3'), options={create:false,maxEntries:2,maxWireBytes:4096};
  index=await openDeliveryAttemptIndex(path,{...options,create:true});
  index.migrate([]);
  const cid=value=>'sha256:'+value.repeat(64);
  const row={logical_key:'v3',attempt_cid:cid('1'),grant_cid:cid('2'),run_cid:cid('3'),
    attempt_wire:'{"attempt":1}',grant_wire:'{"grant":1}'};
  index.claim(row,1,'{"initial":1}',cid('4'));
  index.close();
  const database=new DatabaseSync(path);
  try {removePublicationProgressSchema(database);database.exec(`DROP TABLE physical_objects; DROP TABLE physical_object_usage; DROP TABLE physical_object_preparations; DROP TABLE metadata_deletion_fences; DROP TABLE metadata_deletion_fence_coverage; DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions; ALTER TABLE initial_records DROP COLUMN ack_revision;
    UPDATE coverage SET version=3 WHERE id=1`);} finally {database.close();}
  index=await openDeliveryAttemptIndex(path,options);
  assert.deepEqual(index.contract(cid('4')),{name:'delivery_record',wire:'{"initial":1}'});
  assert.equal(index.confirmRecord(row.attempt_cid,cid('4'),'{"initial":1}'),true);
  assert.equal(index.claim(row,1).created,false);
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
