import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openSqliteCoordinatorDispatchJournal} from './sqlite-coordinator-journal.mjs';

async function originalDatabase(sql) {
  const scratch=await createOwnedScratch({parent:fileURLToPath(new URL('../../_build/',import.meta.url)),
    prefix:'coordinator-schema-original-',label:'original Coordinator schema refusal'});
  const path=join(scratch.path,'coordinator-dispatch-journal.sqlite3');
  const database=new DatabaseSync(path);
  try { database.exec(sql); } finally { database.close(); }
  return {scratch,path,bytes:fs.readFileSync(path)};
}

for(const [kind,sql]of [
  ['view',`CREATE VIEW journal_metadata AS WITH RECURSIVE tiny(n) AS
    (SELECT 1 UNION ALL SELECT n+1 FROM tiny WHERE n<3)
    SELECT 'schema_version' AS key,
      CASE WHEN sum(n)=6 THEN 'actql-remote-coordinator-history-journal/0.1' END AS value FROM tiny;`],
  ['generated column',`CREATE TABLE journal_metadata (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT GENERATED ALWAYS AS (CASE WHEN key='schema_version'
        THEN 'actql-remote-coordinator-history-journal/0.1' ELSE 'original-coordinator' END) VIRTUAL
    ) STRICT;
    INSERT INTO journal_metadata(key) VALUES ('schema_version'),('coordinator_authority');`],
])test('unadmitted metadata '+kind+' refuses before selecting any of its values',async()=>{
  const {scratch,path,bytes}=await originalDatabase(sql);
  const prepare=DatabaseSync.prototype.prepare;
  let metadataSelections=0,opened;
  DatabaseSync.prototype.prepare=function(text){
    if(/\bFROM\s+journal_metadata\b/iu.test(text))metadataSelections++;
    return Reflect.apply(prepare,this,[text]);
  };
  try{
    assert.throws(()=>{opened=openSqliteCoordinatorDispatchJournal(scratch.path,
      {coordinatorAuthority:'original-coordinator'});}, {code:'UnknownCoordinatorJournalFormat'});
    assert.equal(metadataSelections,0);
    assert.deepEqual(fs.readFileSync(path),bytes);
  }finally{opened?.close();DatabaseSync.prototype.prepare=prepare;}
  scratch.passed();
});

test('plain metadata from an unsupported schema refuses without adopting its records',async()=>{
  const {scratch,path,bytes}=await originalDatabase(`
    CREATE TABLE journal_metadata (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    ) STRICT;
    INSERT INTO journal_metadata VALUES ('schema_version','actql-remote-coordinator-journal/0.1');`);
  assert.throws(()=>openSqliteCoordinatorDispatchJournal(scratch.path,
    {coordinatorAuthority:'original-coordinator'}), {code:'UnknownCoordinatorJournalFormat'});
  assert.deepEqual(fs.readFileSync(path),bytes);
  scratch.passed();
});

for (const [field, value, code] of [
  ['coordinator_authority', 'foreign-coordinator', 'CoordinatorJournalAuthorityMismatch'],
  ['dispatch_delivery', 'foreign-delivery-marker', 'UnknownCoordinatorJournalFormat'],
]) test(`Coordinator rechecks ${field} on the opened original before durability setup`, async () => {
  const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
  const scratch = await createOwnedScratch({parent, prefix: 'coordinator-live-schema-', label: 'live Coordinator admission'});
  const originalRoot = join(scratch.path, 'original');
  const foreignRoot = join(scratch.path, 'foreign');
  const options = {coordinatorAuthority: 'original-coordinator'};
  const original = openSqliteCoordinatorDispatchJournal(originalRoot, options);
  const path = original.path;
  assert.equal(original.close(), true);
  const foreign = openSqliteCoordinatorDispatchJournal(foreignRoot, options);
  const foreignPath = foreign.path;
  assert.equal(foreign.close(), true);
  const changed = new DatabaseSync(foreignPath);
  try {changed.prepare('UPDATE journal_metadata SET value = ? WHERE key = ?').run(value, field);}
  finally {changed.close();}
  const foreignBytes = fs.readFileSync(foreignPath);
  const originalBytes = fs.readFileSync(path);
  const originalSaved = join(scratch.path, 'saved');
  const close = DatabaseSync.prototype.close, exec = DatabaseSync.prototype.exec;
  let swapped = false, opened;
  const liveDurability = [];
  DatabaseSync.prototype.close = function () {
    const location = this.location();
    const result = Reflect.apply(close, this, []);
    if (!swapped && location !== path && location?.endsWith('coordinator-dispatch-journal.sqlite3')) {
      fs.renameSync(path, originalSaved);
      fs.renameSync(foreignPath, path);
      swapped = true;
    }
    return result;
  };
  DatabaseSync.prototype.exec = function (sql) {
    if (this.location() === path && /PRAGMA (?:journal_mode|synchronous)/u.test(sql)) liveDurability.push(sql);
    return Reflect.apply(exec, this, [sql]);
  };
  try {
    assert.throws(() => {opened = openSqliteCoordinatorDispatchJournal(originalRoot, options);}, {code});
    assert.equal(swapped, true);
    assert.deepEqual(liveDurability, []);
    assert.deepEqual(fs.readFileSync(path), foreignBytes);
    assert.deepEqual(fs.readFileSync(originalSaved), originalBytes);
  } finally {
    DatabaseSync.prototype.close = close;
    DatabaseSync.prototype.exec = exec;
    opened?.close();
  }
  scratch.passed();
});
