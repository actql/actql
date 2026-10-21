import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync,StatementSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const fields = {authorityScopeCid:`sha256:${'a'.repeat(64)}`,currentAuthorization:true};
const connection = {mode:'local',owner:'local',durability:'durable',consentRefs:[],runners:[]};
const start = 1_800_000_000_000;
const intent = () => moon.clientSubmittedIntent(JSON.stringify({kind:'aql',
  input:{text:"SELECT '猫' AS value",format:'aql-text'},parameters:null}),1048576,65536,64);

async function fixture(t,options={}) {
  const directory = await mkdtemp(join(tmpdir(),'actql-submission-usage-'));
  let now = start;
  const journals = [];
  const open = () => {
    const journal = openClientRequestJournal(directory,{...options,
      submissionEpochTtlMs:1000,submissionEpochNow:()=>now});
    journals.push(journal);
    return journal;
  };
  const journal = open();
  t.after(async () => {for(const j of journals) j.close(); await rm(directory,{recursive:true});});
  const database = use => {
    const db = new DatabaseSync(join(directory,'client-requests.sqlite3'));
    try {return use(db);} finally {db.close();}
  };
  const ref = (nonce,owner=journal) => ({epoch:owner.issueSubmissionEpoch(fields,moon),nonce});
  return {directory,journal,open,database,ref,now:n=>{now=n;}};
}

function aggregateCounter(t) {
  const sql = new WeakMap(), scans = [];
  let armed = false;
  const prepare = DatabaseSync.prototype.prepare, get = StatementSync.prototype.get;
  t.mock.method(DatabaseSync.prototype,'prepare',function(text,...args) {
    const statement = Reflect.apply(prepare,this,[text,...args]);
    sql.set(statement,text);
    return statement;
  });
  t.mock.method(StatementSync.prototype,'get',function(...args) {
    const query = sql.get(this) ?? '';
    if (armed && /\b(?:COUNT|SUM)\s*\(/iu.test(query) &&
        /\bFROM\s+client_(?:submitted_intents|submission_restarts)\b/iu.test(query)) scans.push(query);
    return Reflect.apply(get,this,args);
  });
  return {scans,arm(){armed=true;}};
}

function removeRequestRowUsage(database) {
  for(const table of ['client_request_row_usage','client_cancellation_row_usage']) {
    for(const suffix of ['insert','delete']) database.exec(`DROP TRIGGER ${table}_${suffix}`);
    database.exec(`DROP TABLE ${table}`);
  }
}

for (const history of [0,5,25]) {
  test(`new submitted intent uses no historical aggregate with ${history} retained originals`,async t => {
    const counter = aggregateCounter(t), f = await fixture(t);
    const original = intent();
    for (let i=0;i<history;i++) f.journal.recordSubmittedIntent(f.ref(`old-${i}`),original,fields,moon);
    const reference = f.ref('fresh');
    counter.arm();
    const result = f.journal.recordSubmittedIntent(reference,original,fields,moon);
    assert.equal(result.inserted,true);
    console.info('ACTQL_SUBMISSION_HISTORY_WORK',JSON.stringify({history,aggregateReads:counter.scans.length}));
    assert.deepEqual(counter.scans,[]);
    assert.equal(f.journal.recordSubmittedIntent(reference,original,fields,moon).inserted,false);
    assert.throws(()=>f.journal.recordSubmittedIntent(reference,original,
      {...fields,currentAuthorization:false},moon),{code:'ClientSubmissionEpochUnauthorized'});
    f.journal.close();
    const reopened = f.open();
    assert.equal(reopened.lookupSubmittedIntent(reference,fields,moon).intentCid,result.intentCid);
    assert.deepEqual(counter.scans,[],'complete ordinary open does not rerun aggregate adoption');
  });
}

test('original intent insertion and formal retirement keep exact UTF8 quota beside issued and retired counters',async t => {
  const f = await fixture(t,{maxRecords:1}), original = intent();
  const reference = f.ref('first');
  const first = f.journal.recordSubmittedIntent(reference,original,fields,moon);
  const size = Buffer.byteLength(first.intentWire,'utf8');
  f.database(db => assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
    {singleton:1,retained_count:1,retained_bytes:size,revision:1}));
  assert.throws(()=>f.journal.recordSubmittedIntent(f.ref('over-count'),original,fields,moon),
    {code:'ClientSubmittedIntentCapacity'});
  f.journal.completeSubmittedIntent(reference,{kind:'preparation_failed',submissionRef:reference,
    intentCid:first.intentCid,problem:{code:'FixtureFailure',classification:'operation_failed'}},
  {...fields,connection,expectedRevision:first.revision},moon);
  f.now(start+1000);
  assert.deepEqual(f.journal.retireSubmittedIntent(reference,{...fields,expectedRevision:1},moon),{retired:true});
  assert.deepEqual(f.journal.retireSubmittedIntent(reference,{...fields,expectedRevision:1},moon),{retired:false});
  f.database(db => {
    assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
      {singleton:1,retained_count:0,retained_bytes:0,revision:2});
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,1);
    assert.equal(db.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count,1);
  });
  assert.equal(f.journal.recordSubmittedIntent(f.ref('next'),original,fields,moon).inserted,true);
  f.database(db => assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
    {singleton:1,retained_count:1,retained_bytes:size,revision:3}));
});

test('failed original row mutation rolls back usage and issuance in the same native transaction',async t => {
  const f = await fixture(t), reference = f.ref('rollback');
  f.database(db => db.exec(`CREATE TRIGGER refuse_submission AFTER INSERT ON client_submitted_intents
    BEGIN SELECT RAISE(ABORT,'fixture rejected insertion'); END;`));
  assert.throws(()=>f.journal.recordSubmittedIntent(reference,intent(),fields,moon));
  f.database(db => {
    assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
      {singleton:1,retained_count:0,retained_bytes:0,revision:0});
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,0);
    assert.equal(db.prepare('SELECT submission_id FROM client_submitted_intents LIMIT 1').get(),undefined);
    db.exec('DROP TRIGGER refuse_submission');
  });
  assert.equal(f.journal.recordSubmittedIntent(reference,intent(),fields,moon).inserted,true);
});

test('lost submitted-intent COMMIT response keeps the same original and exact usage without another insertion',async t => {
  const f = await fixture(t), reference = f.ref('unknown');
  const requestId = f.journal.submissionIdentity(reference.epoch,reference.nonce,
    {...fields,purpose:'admit'},moon).requestId;
  const exec = DatabaseSync.prototype.exec;
  let lost = false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
    const value = Reflect.apply(exec,this,[sql]);
    if (!lost && sql==='COMMIT' && this.prepare(
      'SELECT submission_id FROM client_submitted_intents WHERE submission_id=?').get(requestId)) {
      lost = true;
      throw Object.assign(new Error('lost original commit response'),{code:'EIO'});
    }
    return value;
  });
  assert.throws(()=>f.journal.recordSubmittedIntent(reference,intent(),fields,moon),
    error=>error.code==='ClientRequestJournalCommitOutcomeUnknown' && error.outcome==='unknown');
  assert.equal(lost,true);
  const retained = f.journal.recordSubmittedIntent(reference,intent(),fields,moon);
  assert.equal(retained.inserted,false);
  assert.equal(retained.phase,'preparing');
  f.database(db => assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
    {singleton:1,retained_count:1,retained_bytes:Buffer.byteLength(retained.intentWire),revision:1}));
  f.journal.close();
  assert.equal(f.open().lookupSubmittedIntent(reference,fields,moon).requestId,requestId);
});

test('legacy usage adoption scans one bounded original prefix once and never recreates lost issuance',async t => {
  const f = await fixture(t), reference = f.ref('legacy');
  const retained = f.journal.recordSubmittedIntent(reference,intent(),fields,moon);
  f.journal.close();
  f.database(db => {
    for(const table of ['client_submitted_intent_usage','client_submission_restart_usage']) {
      for(const suffix of ['insert','delete','update']) db.exec(`DROP TRIGGER ${table}_${suffix}`);
      db.exec(`DROP TABLE ${table}`);
    }
    removeRequestRowUsage(db);
    db.exec('PRAGMA user_version=0');
  });
  await rm(join(f.directory,'submission-usage-format.json'),{force:true});
  const counter = aggregateCounter(t);
  counter.arm();
  const reopened = f.open();
  assert.equal(counter.scans.length,2,'only the two bounded one-time adoption aggregates');
  assert.equal(reopened.lookupSubmittedIntent(reference,fields,moon).requestId,retained.requestId);
  reopened.close();
  counter.scans.length=0;
  f.open();
  assert.deepEqual(counter.scans,[]);
});

test('explicit restart keeps original link usage and unchanged issuance without a history aggregate',async t => {
  const f = await fixture(t,{maxRecords:1}), counter = aggregateCounter(t);
  const prior = f.ref('unresolved');
  f.now(start+1000);
  const reference = f.ref('fresh-restart'), original = intent();
  const options = {...fields,actorId:'original-actor',unresolvedHistory:{submissionRef:prior,
    acknowledgement:'possible_prior_execution_and_effects'}};
  counter.arm();
  const first = f.journal.recordSubmittedIntent(reference,original,options,moon);
  assert.equal(first.unresolvedHistory.actorId,'original-actor');
  assert.deepEqual(first.unresolvedHistory.submissionRef,prior);
  assert.equal(f.journal.recordSubmittedIntent(reference,original,options,moon).inserted,false);
  assert.deepEqual(counter.scans,[]);
  f.database(db => {
    const link = db.prepare('SELECT link_wire FROM client_submission_restarts WHERE fresh_submission_id=?')
      .get(first.requestId).link_wire;
    assert.deepEqual({...db.prepare('SELECT * FROM client_submission_restart_usage').get()},
      {singleton:1,retained_count:1,retained_bytes:Buffer.byteLength(link),revision:1});
    assert.equal(db.prepare('SELECT issued_count FROM client_submission_restart_custody').get().issued_count,1);
  });
  f.now(start+2000);
  assert.throws(()=>f.journal.recordSubmittedIntent(f.ref('over-restarts'),original,options,moon),
    {code:'ClientSubmissionRestartCapacity'});
  f.database(db=>db.exec('DELETE FROM client_submission_restarts'));
  assert.throws(()=>f.journal.lookupSubmittedIntent(reference,fields,moon),
    {code:'ClientSubmissionRestartCustodyLost'});
});

test('legacy usage adoption preserves formal retirements instead of treating issued as retained',async t => {
  const f = await fixture(t,{maxRecords:1}), reference = f.ref('retire-before-upgrade');
  const first = f.journal.recordSubmittedIntent(reference,intent(),fields,moon);
  f.journal.completeSubmittedIntent(reference,{kind:'preparation_failed',submissionRef:reference,
    intentCid:first.intentCid,problem:{code:'FixtureFailure',classification:'operation_failed'}},
  {...fields,connection,expectedRevision:0},moon);
  f.now(start+1000);
  f.journal.retireSubmittedIntent(reference,{...fields,expectedRevision:1},moon);
  f.journal.close();
  f.database(db => {
    for(const table of ['client_submitted_intent_usage','client_submission_restart_usage']) {
      for(const suffix of ['insert','delete','update']) db.exec(`DROP TRIGGER ${table}_${suffix}`);
      db.exec(`DROP TABLE ${table}`);
    }
    removeRequestRowUsage(db);
    db.exec('PRAGMA user_version=0');
  });
  await rm(join(f.directory,'submission-usage-format.json'),{force:true});
  const reopened = f.open();
  assert.equal(reopened.recordSubmittedIntent(f.ref('after-retirement',reopened),intent(),fields,moon).inserted,true);
  f.database(db => {
    assert.equal(db.prepare('SELECT retained_count FROM client_submitted_intent_usage').get().retained_count,1);
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,2);
    assert.equal(db.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count,1);
  });
});

test('legacy usage adoption refuses missing original intent custody without replacing it',async t => {
  const f = await fixture(t);
  f.journal.recordSubmittedIntent(f.ref('lost-legacy'),intent(),fields,moon);
  f.journal.close();
  f.database(db => {
    for(const table of ['client_submitted_intent_usage','client_submission_restart_usage']) {
      for(const suffix of ['insert','delete','update']) db.exec(`DROP TRIGGER ${table}_${suffix}`);
      db.exec(`DROP TABLE ${table}`);
    }
    removeRequestRowUsage(db);
    db.exec('PRAGMA user_version=0');
    db.exec('DELETE FROM client_submitted_intents');
  });
  await rm(join(f.directory,'submission-usage-format.json'),{force:true});
  assert.throws(()=>f.open(),{code:'ClientSubmittedIntentCustodyLost'});
  f.database(db => {
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,1);
    assert.equal(db.prepare("SELECT name FROM sqlite_master WHERE name='client_submitted_intent_usage'").get(),undefined);
  });
});

test('retained byte quota refuses before changing original intent or issuance',async t => {
  const f = await fixture(t), reference = f.ref('quota');
  // A negative private accounting-row fixture, not allocated payload backing,
  // a supplied resource, or a claim that 64MiB was physically acquired.
  f.database(db=>db.exec('UPDATE client_submitted_intent_usage SET retained_bytes=67108864'));
  assert.throws(()=>f.journal.recordSubmittedIntent(reference,intent(),fields,moon),
    {code:'ClientSubmittedIntentCapacity'});
  f.database(db => {
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,0);
    assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},
      {singleton:1,retained_count:0,retained_bytes:67108864,revision:0});
  });
});

for(const afterCommit of [false,true]) {
  test(`usage adoption recovers after a lost native COMMIT response ${afterCommit?'after':'before'} commit`,async t => {
    const directory = await mkdtemp(join(tmpdir(),'actql-submission-usage-adoption-'));
    let journal;
    t.after(async()=>{journal?.close(); await rm(directory,{recursive:true});});
    const exec = DatabaseSync.prototype.exec;
    let lost = false;
    const intercepted = t.mock.method(DatabaseSync.prototype,'exec',function(sql) {
      if (!lost && sql==='COMMIT' && this.prepare(
        "SELECT name FROM sqlite_master WHERE name='client_submitted_intent_usage'").get()) {
        lost = true;
        if(afterCommit) Reflect.apply(exec,this,[sql]);
        throw Object.assign(new Error('lost usage adoption commit response'),{code:'EIO'});
      }
      return Reflect.apply(exec,this,[sql]);
    });
    try {
      assert.throws(()=>openClientRequestJournal(directory),
        error=>error.code==='ClientRequestJournalCommitOutcomeUnknown'&&error.outcome==='unknown');
      assert.equal(lost,true);
    } finally {intercepted.mock.restore();}
    const counter = aggregateCounter(t);
    counter.arm();
    journal = openClientRequestJournal(directory);
    assert.equal(counter.scans.length,afterCommit?0:2);
    journal.close();
    counter.scans.length=0;
    journal = openClientRequestJournal(directory);
    assert.deepEqual(counter.scans,[]);
    const database = new DatabaseSync(join(directory,'client-requests.sqlite3'));
    try {
      assert.equal(database.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,0);
      assert.equal(database.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count,0);
    } finally {database.close();}
  });
}

for(const marker of ['absent','partial']) {
  test(`complete pre-header usage finishes its original format when the old marker is ${marker}`,async t => {
    const f = await fixture(t), reference = f.ref('same-original');
    const retained = f.journal.recordSubmittedIntent(reference,intent(),fields,moon);
    f.journal.close();
    const before = f.database(db=>{
      removeRequestRowUsage(db);
      db.exec('PRAGMA user_version=0');
      return {...db.prepare('SELECT * FROM client_submitted_intent_usage').get()};
    });
    const path = join(f.directory,'submission-usage-format.json');
    if(marker==='partial') await writeFile(path,'{"version":',{mode:0o600});
    const counter = aggregateCounter(t);
    counter.arm();
    const reopened = f.open();
    assert.equal(reopened.lookupSubmittedIntent(reference,fields,moon).requestId,retained.requestId);
    assert.deepEqual(counter.scans,[]);
    f.database(db=>{
      assert.equal(db.prepare('PRAGMA user_version').get().user_version,2);
      assert.deepEqual({...db.prepare('SELECT * FROM client_submitted_intent_usage').get()},before);
      assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count,1);
    });
    if(marker==='partial') assert.equal(await readFile(path,'utf8'),'{"version":');
    else assert.equal(existsSync(path),false,'no separate marker acquisition remains');
  });
}

for(const loss of ['table','row','trigger']) {
  test(`adopted submission usage ${loss} loss refuses without rebuilding coverage`,async t => {
    const f = await fixture(t);
    f.journal.recordSubmittedIntent(f.ref('retained'),intent(),fields,moon);
    f.journal.close();
    f.database(db => db.exec(loss==='table' ? 'DROP TABLE client_submitted_intent_usage' :
      loss==='row' ? 'DELETE FROM client_submitted_intent_usage' :
        'DROP TRIGGER client_submitted_intent_usage_insert'));
    const path = join(f.directory,'client-requests.sqlite3'), before = await readFile(path);
    assert.throws(()=>f.open(),{code:'UnknownClientRequestJournalFormat'});
    assert.deepEqual(await readFile(path),before);
  });
}
