import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

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
  try{database.exec('DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; UPDATE coverage SET version=6 WHERE id=1');}
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
  try {database.exec('DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions; DROP TABLE initial_records; UPDATE coverage SET version=1 WHERE id=1');}
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
  try {database.exec(`DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions;
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
  try {database.exec(`DROP TABLE native_publication_inventories; DROP TABLE native_publication_inventory_usage; DROP TABLE pending_publications; DROP TABLE publication_recovery; DROP TABLE publication_contracts; DROP TABLE publication_usage; DROP TABLE completions; ALTER TABLE initial_records DROP COLUMN ack_revision;
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
