import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';

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
  assert.equal(index.claim(row,1,initialWire).created,true);
  assert.equal(commits,1);
  assert.deepEqual(index.pending(),[]);
  assert.equal(index.lookup(row.logical_key).initial_wire,initialWire);
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
  try {database.exec('DROP TABLE initial_records; UPDATE coverage SET version=1 WHERE id=1');}
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
