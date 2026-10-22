import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdirSync, readFileSync, symlinkSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Fresh actual Node SQLite/FS children with a counted native forwarding port.
// This diagnostic establishes selection/capture, not an operational supplier.
for (const selected of ['primary', 'copy']) {
  test(`selected ${selected} canonical paths use the captured native operation`, () => {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
      import assert from 'node:assert/strict';
      import fs from 'node:fs';
      import {join} from 'node:path';
      import {createOwnedScratch} from ${JSON.stringify(new URL('../../scripts/owned-scratch.mjs', import.meta.url).href)};
      const originalNative=fs.realpathSync.native;
      let reads=0;
      fs.realpathSync.native=function(...args){reads++;return Reflect.apply(originalNative,this,args);};
      const {openClientRequestJournal}=await import(${JSON.stringify(new URL('./client-request-journal.mjs', import.meta.url).href)});
      const {inspectSqliteSnapshot}=await import(${JSON.stringify(new URL('../host-common/sqlite-format-inspection.mjs', import.meta.url).href)});
      // Later mutation must not change the captured operation, even under this
      // explicit unaccounted current fixture. The nominal current fence is
      // tested separately and must refuse that mutation in production.
      fs.realpathSync.native=()=>{throw new Error('MustNotCallReplacementNative');};
      const scratch=await createOwnedScratch({parent:${JSON.stringify(fileURLToPathForBuild())},
        prefix:'journal-native-path-',label:'same native canonical-path diagnostic'});
      let journal;
      try {
        if(${JSON.stringify(selected)}==='primary') {
          journal=openClientRequestJournal(join(scratch.path,'requests'),{primaryCurrent(){}});
          assert.equal(reads,1);
        } else {
          const {DatabaseSync}=await import('node:sqlite');
          const path=join(scratch.path,'original.sqlite3');
          const database=new DatabaseSync(path);
          database.exec("CREATE TABLE metadata(value TEXT) STRICT; INSERT INTO metadata VALUES ('original')");
          database.close();
          assert.equal(inspectSqliteSnapshot(path,db=>db.prepare('SELECT value FROM metadata').get().value,
            {assertCurrent(){}}),'original');
          assert.equal(reads,2);
        }
      } finally {fs.realpathSync.native=originalNative;journal?.close();}
      scratch.passed();
    `], {encoding:'utf8', timeout:15000});
    assert.equal(result.error,undefined);
    assert.equal(result.status,0,result.stderr);
  });
}

function fileURLToPathForBuild() {
  return fileURLToPath(new URL('../../_build/', import.meta.url));
}

test('selected native paths retain the real ancestor-link Journal and cold-copy meaning', async () => {
  const {openClientRequestJournal,observeOriginalClientRequestJournalCustody} =
    await import('./client-request-journal.mjs');
  const {inspectSqliteSnapshot} = await import('../host-common/sqlite-format-inspection.mjs');
  const scratch=await createOwnedScratch({parent:fileURLToPathForBuild(),
    prefix:'journal-native-link-',label:'same original linked Journal path diagnostic'});
  const target=join(scratch.path,'target'),alias=join(scratch.path,'alias');
  mkdirSync(target);
  symlinkSync(target,alias,'dir');
  const directory=join(alias,'requests');
  let journal=openClientRequestJournal(directory,{primaryCurrent(){}});
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed,true);
  const path=join(directory,'client-requests.sqlite3');
  assert.equal(realpathSync(path),join(realpathSync(target),'requests','client-requests.sqlite3'));
  const before=readFileSync(path);
  assert.ok(inspectSqliteSnapshot(path,db=>
    db.prepare('SELECT count(*) AS n FROM sqlite_master').get().n,{assertCurrent(){}})>0);
  assert.deepEqual(readFileSync(path),before);
  journal=openClientRequestJournal(directory,{primaryCurrent(){}});
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed,true);
  scratch.passed();
});
