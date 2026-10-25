import test, {before} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime,assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';
let open,getSubmissionInput,coherence;
before(async()=>{
 coherence=await verifyLocalSourceRuntime(fileURLToPath(new URL('../../',import.meta.url)));
 ({open}=await import('../../packages/node/index.mjs'));
 ({getSubmissionInput}=await import('../../packages/sdk/index.mjs'));
});
const program = n => ({version:'actql/0.1',id:'prepared-journal-failure',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:[{x:n}]}}],results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});

// The ordinary submission owner adopts the prepared Run immediately before
// recordSubmittedIntent. A disposable SQLite trigger fails that exact write;
// no production hook, foreign preparation, fabricated cleanup ACK or user data.
test('funded adopted but undispatched preparations retire after journal write failure', {timeout:30000}, async()=>{
 const stateDir=await mkdtemp(join(tmpdir(),'actql-prepared-journal-failure-'));
 let db=await open({stateDir}), storage, successful=false;
 try {
  storage=new DatabaseSync(join(stateDir,'requests','client-requests.sqlite3'));
  storage.exec("CREATE TRIGGER test_prepared_journal_failure BEFORE INSERT ON client_submitted_intents BEGIN SELECT RAISE(ABORT, 'test_after_prepared_adoption'); END");
  const outcomes=await Promise.allSettled([db.start(program(1)),db.start(program(2))]);
  assert.deepEqual(outcomes.map(result=>result.status),['rejected','rejected']);
  const callerSnapshots=outcomes.map(result=>getSubmissionInput(result.reason));
  assert.deepEqual(callerSnapshots.map(value=>value.input.stages[0].steps[0].values.rows[0].x),[1,2]);
  assert.ok(callerSnapshots.every(Object.isFrozen));
  assert.equal(storage.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n,0);
  storage.exec('DROP TRIGGER test_prepared_journal_failure');storage.close();storage=undefined;
  // Handler finally is complete but dispatch never began. Only the fixed
  // registry close path may return these original manager/handler holders.
  await db.close();db=undefined;
  for(let i=0;i<outcomes.length;i++) assert.equal(getSubmissionInput(outcomes[i].reason),callerSnapshots[i]);
  db=await open({stateDir});
  const run=await db.start(program(9));
  assert.equal((await run.wait({signal:AbortSignal.timeout(10000)})).status,'succeeded');
  assert.deepEqual(await run.result('answer').all(),[{x:9}]);
  await db.close();db=undefined;successful=true;
 } finally {
  storage?.close();
  if(!successful) console.error('preserved preparation journal failure state',stateDir);
  if(db!==undefined) await db.close().catch(error=>console.error('original cleanup remains pending',error));
  assertSourceRuntimeReceiptCurrent(coherence);
  if(successful) await rm(stateDir,{recursive:true,force:true});
 }
});
