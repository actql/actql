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
