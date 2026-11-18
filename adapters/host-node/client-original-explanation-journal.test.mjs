// Actual SQLite persistence with explicit nominal compiler-control ports.
// This is not funded compiler capture or installed Host/SDK acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';
import schemaSupport from './host-journal-schema-support.cjs';
import {controls, request, requestControl, options, evidence, planOriginal} from './fixtures/original-plan-journal.mjs';
import {explanationFacts} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
function fixture(t, configuration = {}, afterAcknowledgement) {
  const path = mkdtempSync(join(tmpdir(), 'actql-g-original-explanation-'));
  let journal = openClientRequestJournal(path,configuration), captures = 0, acknowledgements = 0;
  const tickets = new WeakMap(), base = controls();
  const control = {...base.publication, originalRunExplanationAdmissionEvidence(ticket, definition, program, original) {
    captures++;
    if (!tickets.has(ticket)) throw TypeError('Foreign compiler capture');
    assert.equal(program, request.programDefinitionCid); assert.deepEqual(original, evidence);
    return tickets.get(ticket);
  }, originalRunExplanationAdmissionAcknowledged(ticket, definition, program, original) {
    assert.equal(tickets.has(ticket), true);
    assert.equal(definition.identity, options.runDefinition.identity);
    assert.equal(program, request.programDefinitionCid);
    assert.equal(original.prepared, evidence.prepared);
    assert.equal(original.authorization, evidence.authorization);
    acknowledgements++;
    afterAcknowledgement?.();
  }};
  const ref = {namespaceId: 'original', authorityScopeCid: request.authorityScopeCid,
    runDefinitionCid: options.runDefinition.identity};
  t.after(() => {journal.close(); rmSync(path, {recursive: true, force: true});});
  return {path, control, ref, captures: () => captures, acknowledgements: () => acknowledgements,
    ticket(factsWire = JSON.stringify(explanationFacts)) {const ticket = Object.freeze({}); tickets.set(ticket, {factsWire}); return ticket;},
    planTicket: () => base.ticket(),
    accept: ticket => journal.acceptDefinition(request, {...options, originalPlan: base.ticket(), originalExplanation: ticket}, requestControl, control),
    lookup: () => journal.lookupRunDefinition(ref, requestControl, control),
    explanation: () => journal.lookupRunExplanationOriginal(ref, requestControl, control),
    get journal() {return journal;}, reopen() {journal.close(); journal = openClientRequestJournal(path,configuration);}};
}

test('first explanation original is atomic, immutable and restored without compiler recapture', t => {
  const f = fixture(t), ticket = f.ticket(); const first = f.accept(ticket);
  assert.equal(first.inserted, true);
  assert.equal(Object.isFrozen(f.explanation()), true);
  const captures = f.captures(); f.reopen();
  assert.equal(f.explanation().factsWire, JSON.stringify(explanationFacts));
  assert.equal(f.captures(), captures); assert.equal(f.lookup().physicalStartReserved, false);
  assert.equal(f.accept(ticket).inserted, false);
  assert.throws(() => f.accept(f.ticket('{}')), {code: 'ClientRequestExplanationEvidenceMismatch'});
});

test('legacy absence is not backfilled, and caller DATA cannot mint a nominal explanation', t => {
  const f = fixture(t); f.accept(); f.reopen();
  assert.equal(f.explanation(), undefined);
  assert.throws(() => f.accept(f.ticket()), {code: 'ClientRequestExplanationEvidenceMissing'});
  assert.throws(() => f.journal.acceptDefinition(request, {...options, runAdmissionEvidence: {
    ...evidence, structuralExplanationOriginal: {factsWire: '{}'}}}, requestControl, f.control),
  {code: 'InvalidClientRunExplanationOriginal'});
  assert.throws(() => f.accept({}), {code: 'InvalidClientRunExplanationOriginal'});
});

test('retained explanation has its own exact byte/shape guard on cold journal metadata', t => {
  const f = fixture(t);
  assert.throws(() => f.accept(f.ticket('x'.repeat(65537))), {code: 'InvalidClientRunAdmissionEvidence'});
  f.accept(f.ticket()); f.reopen();
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  t.after(() => db.close());
  for (const replacement of ['', 'x'.repeat(65537)]) {
    db.prepare('UPDATE client_run_explanation_originals SET facts_wire=?').run(replacement);
    assert.throws(f.explanation, {code: 'ClientRequestJournalCorrupt'});
  }
  db.prepare('UPDATE client_run_explanation_originals SET facts_wire=?').run(JSON.stringify(explanationFacts));
  db.exec('ALTER TABLE client_run_explanation_originals ADD COLUMN unexpected TEXT');
  assert.throws(f.explanation, {code: 'UnknownClientRequestJournalFormat'});
});


test('associated explanation keeps original persisted Plan and admission evidence bytes unchanged', t => {
  const f=fixture(t); f.accept(f.ticket());
  const db=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try {
    const row=db.prepare('SELECT run_definition_wire, run_admission_evidence_json FROM client_requests').get();
    assert.equal(row.run_definition_wire,options.runDefinition.wire);
    assert.equal(row.run_admission_evidence_json,JSON.stringify({...evidence,logicalPlanOriginal:planOriginal}));
  } finally {db.close();}
});


test('normal first Plan admission forwards the same nominal explanation without a Saved recapture', async t => {
  const f=fixture(t); let issued=0;
  const accepted=await f.journal.admitOrLookupDefinition(request,{
    ...options,issueDefinition:async()=>{issued++;return {...options,originalPlan:f.planTicket(),originalExplanation:f.ticket()};},
  },requestControl,f.control);
  assert.equal(accepted.inserted,true);assert.equal(issued,1);
  assert.equal(f.explanation().factsWire,JSON.stringify(explanationFacts));
  const captures=f.captures();f.reopen();
  assert.equal(f.explanation().factsWire,JSON.stringify(explanationFacts));
  assert.equal(f.captures(),captures);assert.equal(f.lookup().physicalStartReserved,false);
  const found=await f.journal.admitOrLookupDefinition(request,{
    ...options,issueDefinition(){assert.fail('Saved must not issue or capture another original');},
  },requestControl,f.control);
  assert.equal(found.inserted,false);assert.equal(issued,1);assert.equal(f.captures(),captures);
});

test('associated explanation insertion failure rolls back the same first Run admission', t => {
  const f=fixture(t);
  // Independent expected additive format, not a second product table issuer.
  // The test-only SQLite trigger supplies a real failure in this fresh scratch.
  const db=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try {
    db.exec(`CREATE TABLE client_run_explanation_originals (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  facts_wire TEXT NOT NULL
) STRICT`);
    db.exec(`CREATE TRIGGER fail_explanation_fixture BEFORE INSERT ON client_run_explanation_originals
      BEGIN SELECT RAISE(ABORT,'AuthoredExplanationInsertFailure'); END`);
    let failure;
    try {f.accept(f.ticket());}catch(error){failure=error;}
    assert.ok(failure,'actual insertion failure must propagate, not omit optional facts');
    assert.equal(failure.code,'ClientRequestAcceptanceUnknown');
    assert.equal(failure.outcome,'failed');assert.equal(failure.connectionUsable,true);
    assert.equal(db.prepare('SELECT count(*) AS count FROM client_requests').get().count,0);
    assert.equal(db.prepare('SELECT count(*) AS count FROM client_run_explanation_originals').get().count,0);
    assert.equal(f.lookup(),undefined);assert.equal(f.explanation(),undefined);
    assert.equal(f.acknowledgements(),0);
  } finally {db.close();}
});

test('the original loan receives its ACK only after the same Facts transaction is externally visible', t => {
  const f=fixture(t,{},()=>{
    // A second native connection cannot see the new table/row inside the
    // writer's uncommitted transaction. No synthetic durability flag is used.
    const db=new DatabaseSync(join(f.path,'client-requests.sqlite3'),{readOnly:true});
    try {
      assert.equal(db.prepare('SELECT facts_wire FROM client_run_explanation_originals').get().facts_wire,
        JSON.stringify(explanationFacts));
      assert.equal(db.prepare('SELECT count(*) AS count FROM client_requests').get().count,1);
    } finally {db.close();}
  });
  f.accept(f.ticket());
  assert.equal(f.acknowledgements(),1);
});

test('a lost COMMIT reply retains the original loan even when the fresh row was written', t => {
  const f=fixture(t), original=DatabaseSync.prototype.exec;
  const primary=Error('AuthoredLostFactsCommitReply');
  let injected=false;
  DatabaseSync.prototype.exec=function(sql){
    const result=Reflect.apply(original,this,[sql]);
    if(sql==='COMMIT'&&!injected){injected=true;throw primary;}
    return result;
  };
  try {
    let failure;
    try {f.accept(f.ticket());} catch(error){failure=error;}
    assert.equal(injected,true);
    assert.equal(failure?.code,'ClientRequestAcceptanceUnknown');
    assert.equal(failure?.outcome,'unknown');
    assert.equal(failure?.cause,primary);
    assert.equal(f.acknowledgements(),0);
  } finally {DatabaseSync.prototype.exec=original;}
  assert.equal(f.explanation().factsWire,JSON.stringify(explanationFacts));
});

test('post-ACK cleanup failure preserves its primary and the committed original Facts', t => {
  const primary=Error('AuthoredFactsLoanReturnPending');
  const f=fixture(t,{},()=>{throw primary;});
  assert.throws(()=>f.accept(f.ticket()),error=>error===primary);
  assert.equal(f.acknowledgements(),1);
  assert.equal(f.explanation().factsWire,JSON.stringify(explanationFacts));
  assert.equal(f.lookup().physicalStartReserved,false);
});


const explanationSchemaConfiguration = Object.freeze({maxDatabaseBytes:4194304,
  primarySchemaLimits:{maxSchemaBytes:65536,maxSchemaEntries:128,maxSchemaPages:256,maxWalFrames:8192},
  primarySchemaSqlSupport:schemaSupport.sql});
test('selected exact own-schema admits and cold-restores the associated facet', t => {
  const f=fixture(t,explanationSchemaConfiguration);f.accept(f.ticket());
  f.reopen();assert.equal(f.explanation().factsWire,JSON.stringify(explanationFacts));
  assert.equal(f.lookup().runAdmissionEvidence.structuralExplanationOriginal,undefined);
});
test('unsupported exact facet schema refuses supplied capture without manufacturing absence', t => {
  const configuration={...explanationSchemaConfiguration,primarySchemaSqlSupport:schemaSupport.sql.filter(sql=>
    !sql.startsWith('CREATE TABLE client_run_explanation_originals ('))};
  const f=fixture(t,configuration);
  assert.throws(()=>f.accept(f.ticket()),{code:'ClientRequestExplanationStorageUnavailable'});
  assert.equal(f.captures(),0);assert.equal(f.lookup(),undefined);
  const legacy=fixture(t,configuration);legacy.accept();
  assert.equal(legacy.lookup().runAdmissionEvidence.structuralExplanationOriginal,undefined);
  assert.equal(legacy.explanation(),undefined);
});


test('a retained facet with foreign original reference is corruption, never legacy absence', t => {
  const f=fixture(t);f.accept(f.ticket());
  const db=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try {
    for(const [column,foreign] of [['namespace_id','foreign-namespace'],['authority_scope_cid','sha256:'+ '9'.repeat(64)]]) {
      db.prepare(`UPDATE client_run_explanation_originals SET ${column}=?`).run(foreign);
      assert.throws(f.explanation,{code:'ClientRequestJournalCorrupt'});
      db.prepare('UPDATE client_run_explanation_originals SET namespace_id=?,authority_scope_cid=?')
        .run(f.ref.namespaceId,f.ref.authorityScopeCid);
    }
  } finally {db.close();}
});
test('nominal original capture snapshots only one own DATA field without invoking accessors', t => {
  const f=fixture(t);let reads=0;
  const control={...f.control,originalRunExplanationAdmissionEvidence(){return {
    get factsWire(){reads++;return JSON.stringify(explanationFacts);},
  };}};
  assert.throws(()=>f.journal.acceptDefinition(request,{...options,originalPlan:f.planTicket(),originalExplanation:{}},
    requestControl,control),{code:'InvalidClientRunExplanationOriginal'});
  assert.equal(reads,0);assert.equal(f.lookup(),undefined);
});

test('cold explanation rejects oversized stored fields before native rows cross into JavaScript', t => {
  const f=fixture(t);f.accept(f.ticket());f.reopen();
  const db=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  const prepare=DatabaseSync.prototype.prepare,get=StatementSync.prototype.get;
  const selected=new WeakSet(),observations=[];
  DatabaseSync.prototype.prepare=function(sql,...args) {
    const statement=Reflect.apply(prepare,this,[sql,...args]);
    if (/FROM\s+client_run_explanation_originals\b/u.test(sql)) selected.add(statement);
    return statement;
  };
  StatementSync.prototype.get=function(...args) {
    const row=Reflect.apply(get,this,args);
    if (selected.has(this)&&row!==undefined) observations.push({
      stringBytes:Object.values(row).filter(value=>typeof value==='string').map(value=>Buffer.byteLength(value)),
      nulls:Object.values(row).filter(value=>value===null).length,
    });
    return row;
  };
  try {
    // The real SQLite row is corrupt. Observe the native result BEFORE the
    // imported Journal can validate it; throwing after an oversized get is
    // insufficient. UTF-8 and NUL controls reject character-count shortcuts.
    for(const replacement of ['x'.repeat(131072),'é'.repeat(32769),'{}\0'+'x'.repeat(65536)]) {
      db.prepare('UPDATE client_run_explanation_originals SET facts_wire=?').run(replacement);
      assert.throws(f.explanation,{code:'ClientRequestJournalCorrupt'});
      const observed=observations.at(-1);
      assert.ok(observed.stringBytes.every(bytes=>bytes<=65536),
        'the native row must never return an oversized string');
      assert.equal(observed.nulls,1,'over-limit facts must be rejected, never truncated');
    }
    db.prepare('UPDATE client_run_explanation_originals SET facts_wire=?').run(JSON.stringify(explanationFacts));
    for(const column of ['namespace_id','authority_scope_cid']) {
      db.prepare(`UPDATE client_run_explanation_originals SET ${column}=?`).run('z'.repeat(131072));
      assert.throws(f.explanation,{code:'ClientRequestJournalCorrupt'});
      assert.ok(observations.at(-1).stringBytes.every(bytes=>bytes<=65536),
        'original-reference binding fields must not escape as unbounded strings');
      db.prepare('UPDATE client_run_explanation_originals SET namespace_id=?,authority_scope_cid=?')
        .run(f.ref.namespaceId,f.ref.authorityScopeCid);
    }
    const exact='x'.repeat(65536);
    db.prepare('UPDATE client_run_explanation_originals SET facts_wire=?').run(exact);
    assert.equal(f.explanation().factsWire,exact,'the byte boundary must not truncate an admitted original');
    db.prepare('DELETE FROM client_run_explanation_originals').run();
    assert.equal(f.explanation(),undefined,'an absent facet remains distinct from a rejected stored row');
  } finally {
    StatementSync.prototype.get=get;DatabaseSync.prototype.prepare=prepare;db.close();
  }
});

test('explicit structural read probes only scalar extents then selects one original bounded row', t => {
  for (const retained of [false, true]) {
    const f = fixture(t);
    f.accept(retained ? f.ticket() : undefined);
    const captures = f.captures();
    f.reopen();
    const extent = f.journal.probeRunExplanationOriginal(f.ref);
    assert(Object.isFrozen(extent));
    assert(Object.values(extent).every(Number.isSafeInteger));
    assert.equal(extent.definitionBytes, Buffer.byteLength(options.runDefinition.wire));
    assert.equal(extent.evidenceBytes, Buffer.byteLength(JSON.stringify({...evidence, logicalPlanOriginal: planOriginal})));
    assert.equal(extent.factsBytes, retained ? Buffer.byteLength(JSON.stringify(explanationFacts)) : 0);
    assert.equal(extent.storedBytes, extent.definitionBytes + extent.evidenceBytes + extent.factsBytes + 142);
    const original = f.journal.readRunExplanationOriginal(f.ref, extent);
    assert(Object.isFrozen(original));
    assert.deepEqual(original, {definitionWire: options.runDefinition.wire,
      admissionEvidenceWire: JSON.stringify({...evidence, logicalPlanOriginal: planOriginal}),
      programDefinitionCid: request.programDefinitionCid, parameterValuesCid: request.parameterValuesCid,
      factsWire: retained ? JSON.stringify(explanationFacts) : undefined});
    assert.equal(f.captures(), captures, 'the explicit cold read cannot recapture compiler facts');
    assert.equal(f.journal.probeRunExplanationOriginal({...f.ref, namespaceId: 'foreign'}), undefined);
    assert.equal(f.journal.readRunExplanationOriginal({...f.ref, namespaceId: 'foreign'}, extent), undefined);
  }
});

test('structural full read refuses growth after its scalar probe before any oversized native string result', t => {
  const f = fixture(t); f.accept(f.ticket());
  const extent = f.journal.probeRunExplanationOriginal(f.ref);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  const prepare = DatabaseSync.prototype.prepare, get = StatementSync.prototype.get;
  const selected = new WeakSet(), observations = [];
  DatabaseSync.prototype.prepare = function(sql, ...args) {
    const statement = Reflect.apply(prepare, this, [sql, ...args]);
    if (/FROM client_requests r\s+LEFT JOIN client_run_explanation_originals/u.test(sql)) {
      assert(sql.length <= 4096, 'the authored structural-read SQL source must fit its fixed entry geometry');
      selected.add(statement);
    }
    return statement;
  };
  StatementSync.prototype.get = function(...args) {
    const row = Reflect.apply(get, this, args);
    if (selected.has(this) && row !== undefined) observations.push(row);
    return row;
  };
  try {
    const trials = [
      ['client_requests', 'run_definition_wire', options.runDefinition.wire],
      ['client_requests', 'run_admission_evidence_json', JSON.stringify({...evidence, logicalPlanOriginal: planOriginal})],
      ['client_requests', 'program_definition_cid', request.programDefinitionCid],
      ['client_requests', 'parameter_values_cid', request.parameterValuesCid],
      ['client_run_explanation_originals', 'facts_wire', JSON.stringify(explanationFacts)],
    ];
    for (const [table, field, original] of trials) {
      db.prepare(`UPDATE ${table} SET ${field}=?`).run('é'.repeat(65537));
      assert.throws(() => f.journal.readRunExplanationOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
      assert(Object.values(observations.at(-1)).filter(value => typeof value === 'string')
        .every(value => Buffer.byteLength(value) <= Math.max(extent.definitionBytes, extent.evidenceBytes, extent.factsBytes, 71)),
      'native CASE must reject growth before JavaScript materializes original strings');
      assert.throws(() => f.journal.probeRunExplanationOriginal(f.ref), {code: 'ClientRequestJournalCorrupt'});
      db.prepare(`UPDATE ${table} SET ${field}=?`).run(original);
    }
    db.prepare('UPDATE client_run_explanation_originals SET namespace_id=?').run('x'.repeat(131072));
    assert.throws(() => f.journal.readRunExplanationOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
    assert(!Object.values(observations.at(-1)).includes('x'.repeat(131072)));
  } finally {StatementSync.prototype.get = get; DatabaseSync.prototype.prepare = prepare; db.close();}
});
