// Actual SQLite persistence with explicit nominal compiler-control ports.
// This is not funded compiler capture or installed Host/SDK acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';
import schemaSupport from './host-journal-schema-support.cjs';
import recipeModule from './host-journal-service-recipe.cjs';
import {controls, request, requestControl, options, evidence, planOriginal} from './fixtures/original-plan-journal.mjs';
import {explanationFacts} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
import {effectfulStaticExplanationFixture} from '../../scripts/fixtures/effectful-static-plan-vectors.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
const contextWire = JSON.stringify(effectfulStaticExplanationFixture().context);
// The storage control is explicit here. The Common capture test establishes
// the semantic Template/Run/Check Environment relation independently.
const invocationTemplateWire = '{"test_original_template":"effect-first-admission"}';
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
    ticket(factsWire = JSON.stringify(explanationFacts), context,
      template = context === undefined ? undefined : invocationTemplateWire) {
      const ticket = Object.freeze({});
      tickets.set(ticket, {factsWire,
        ...(context === undefined ? {} : {contextWire: context}),
        ...(template == null ? {} : {invocationTemplateWire: template})});
      return ticket;
    },
    planTicket: () => base.ticket(),
    accept: ticket => journal.acceptDefinition(request, {...options, originalPlan: base.ticket(), originalExplanation: ticket}, requestControl, control),
    lookup: () => journal.lookupRunDefinition(ref, requestControl, control),
    lookupPlan: () => journal.lookupRunPlanOriginal(ref, requestControl, control),
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
  for (const context of [undefined, contextWire]) {
    const f = fixture(t), original = DatabaseSync.prototype.exec;
    const primary = Error('AuthoredLostExplanationCommitReply');
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      const result = Reflect.apply(original, this, [sql]);
      if (sql === 'COMMIT' && !injected) {injected = true; throw primary;}
      return result;
    };
    try {
      assert.throws(() => f.accept(f.ticket(undefined, context)), error => {
        assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
        assert.equal(error.outcome, 'unknown');
        assert.equal(error.cause, primary);
        return true;
      });
      assert.equal(injected, true);
      assert.equal(f.acknowledgements(), 0);
    } finally {DatabaseSync.prototype.exec = original;}
    const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
    const retained = f.journal.readRunExplanationContextOriginal(f.ref, extent);
    assert.equal(retained.factsWire, JSON.stringify(explanationFacts));
    assert.equal(retained.contextWire, context);
    assert.equal(retained.invocationTemplateWire, context === undefined ? undefined : invocationTemplateWire);
  }
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

test('Context and Template join the same committed Plan and Facts with separate admission evidence', async t => {
  let acknowledged = false;
  const f = fixture(t, explanationSchemaConfiguration, () => {
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
    try {
      const committed = db.prepare(`SELECT r.run_definition_wire, r.run_admission_evidence_json,
        f.facts_wire, c.context_wire, c.invocation_template_wire, p.compiled_plan_wire, p.plan_view_wire FROM client_requests r
        JOIN client_run_explanation_originals f ON f.run_definition_cid = r.run_definition_cid
        JOIN client_run_explanation_context_originals c ON c.run_definition_cid = f.run_definition_cid
        JOIN client_run_explanation_plan_originals p ON p.run_definition_cid = c.run_definition_cid`).get();
      assert.equal(committed.run_definition_wire, options.runDefinition.wire);
      assert.equal(committed.run_admission_evidence_json, JSON.stringify(evidence));
      assert.equal(committed.compiled_plan_wire, planOriginal.compiledPlanWire);
      assert.equal(committed.plan_view_wire, planOriginal.planViewWire);
      assert.equal(committed.facts_wire, JSON.stringify(explanationFacts));
      assert.equal(committed.context_wire, contextWire);
      assert.equal(committed.invocation_template_wire, invocationTemplateWire);
      acknowledged = true;
    } finally {db.close();}
  });
  assert.equal(f.journal.supportsOriginalExplanationContext(), true);
  const ticket = f.ticket(undefined, contextWire);
  const first = await f.journal.admitOrLookupDefinition(request, {
    ...options, issueDefinition: async () => ({...options, originalPlan: f.planTicket(), originalExplanation: ticket}),
  }, requestControl, f.control);
  assert.equal(first.inserted, true);
  assert.equal(acknowledged, true);
  const captures = f.captures();
  f.reopen();
  const old = f.journal.probeRunExplanationOriginal(f.ref);
  const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
  assert.equal(Object.hasOwn(old, 'contextBytes'), false);
  assert.equal(Object.hasOwn(old, 'invocationTemplateBytes'), false);
  assert.equal(extent.contextBytes, Buffer.byteLength(contextWire));
  assert.equal(extent.invocationTemplateBytes, Buffer.byteLength(invocationTemplateWire));
  assert.equal(extent.storedBytes, old.storedBytes + extent.contextBytes + extent.invocationTemplateBytes + 64);
  const original = f.journal.readRunExplanationOriginal(f.ref, old);
  assert.equal(Object.hasOwn(original, 'contextWire'), false);
  assert.equal(Object.hasOwn(original, 'invocationTemplateWire'), false);
  assert.deepEqual(f.journal.readRunExplanationContextOriginal(f.ref, extent),
    {...original, contextWire, invocationTemplateWire});
  assert.equal(f.captures(), captures);
  assert.equal(f.journal.probeRunExplanationContextOriginal({...f.ref, namespaceId: 'foreign'}), undefined);
  assert.equal(f.journal.readRunExplanationContextOriginal({...f.ref, namespaceId: 'foreign'}, extent), undefined);
  assert.equal(f.accept(ticket).inserted, false);
  assert.throws(() => f.accept(f.ticket(undefined, '{}')), {code: 'ClientRequestExplanationEvidenceMismatch'});
  assert.throws(() => f.accept(f.ticket(undefined, contextWire, '{}')), {code: 'ClientRequestExplanationEvidenceMismatch'});
});

test('old Facts-only Runs never backfill Context and selected unsupported storage refuses admission', t => {
  const f = fixture(t, explanationSchemaConfiguration);
  f.accept(f.ticket());
  f.reopen();
  const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
  assert.equal(extent.contextBytes, 0);
  assert.equal(extent.invocationTemplateBytes, 0);
  const original = f.journal.readRunExplanationContextOriginal(f.ref, extent);
  assert.equal(original.contextWire, undefined);
  assert.equal(original.invocationTemplateWire, undefined);
  assert.throws(() => f.accept(f.ticket(undefined, contextWire)), {code: 'ClientRequestExplanationEvidenceMissing'});
  const unsupported = fixture(t, {...explanationSchemaConfiguration, primarySchemaSqlSupport:
    schemaSupport.sql.filter(sql => !sql.startsWith('CREATE TABLE client_run_explanation_context_originals ('))});
  assert.equal(unsupported.journal.supportsOriginalExplanation(), true);
  assert.equal(unsupported.journal.supportsOriginalExplanationContext(), false);
  assert.throws(() => unsupported.accept(unsupported.ticket(undefined, contextWire)),
    {code: 'ClientRequestExplanationStorageUnavailable'});
  assert.equal(unsupported.lookup(), undefined);
  assert.equal(unsupported.acknowledgements(), 0);
  unsupported.accept(unsupported.ticket());
  assert.equal(unsupported.explanation().factsWire, JSON.stringify(explanationFacts));
});

test('split Effect Plan uses the same two bounded records, preserving the original atomic commit', t => {
  const limit = 65536;
  const captured = fixture(t, explanationSchemaConfiguration);
  const ticket = captured.ticket(undefined, contextWire, invocationTemplateWire);
  const selectedPlan = Object.freeze({...planOriginal, planViewWire: 'p'.repeat(25000)});
  const material = Object.freeze({...evidence, effectOriginalRunWire: 'm'.repeat(54000)});
  assert(Buffer.byteLength(JSON.stringify(material)) <= limit);
  assert(Buffer.byteLength(JSON.stringify({...material, logicalPlanOriginal: selectedPlan})) > limit);
  const control = {...captured.control,
    originalRunExplanationAdmissionEvidence(selected, run, program, admitted) {
      assert.equal(admitted, material);
      return captured.control.originalRunExplanationAdmissionEvidence(selected, run, program, evidence);
    },
    originalRunPlanAdmissionEvidence(selected, run, program, admitted) {
      assert.equal(admitted, material);
      return selectedPlan;
    },
  };
  const accept = (bound = control) => captured.journal.acceptDefinition(request,
    {...options, runAdmissionEvidence: material, originalPlan: captured.planTicket(), originalExplanation: ticket},
    requestControl, bound);
  assert.equal(accept().inserted, true);
  assert.equal(captured.acknowledgements(), 1);
  captured.reopen();
  assert.equal(captured.lookup().runAdmissionEvidence.logicalPlanOriginal, undefined);
  assert.deepEqual(captured.lookupPlan().runAdmissionEvidence.logicalPlanOriginal, selectedPlan);
  const extent = captured.journal.probeRunExplanationContextOriginal(captured.ref);
  assert.equal(extent.compiledPlanBytes, Buffer.byteLength(selectedPlan.compiledPlanWire));
  assert.equal(extent.planViewBytes, Buffer.byteLength(selectedPlan.planViewWire));
  const record = captured.journal.readRunExplanationContextOriginal(captured.ref, extent);
  assert.deepEqual(JSON.parse(record.admissionEvidenceWire), material);
  assert.equal(record.compiledPlanWire, selectedPlan.compiledPlanWire);
  assert.equal(record.planViewWire, selectedPlan.planViewWire);
  assert.equal(record.contextWire, contextWire);
  const legacyRead = captured.journal.probeRunExplanationOriginal(captured.ref);
  assert.equal(captured.journal.readRunExplanationOriginal(captured.ref, legacyRead).planViewWire,
    selectedPlan.planViewWire);
  const changed = {...control, originalRunPlanAdmissionEvidence: () => ({...selectedPlan, planViewWire: 'q'.repeat(25000)})};
  assert.throws(() => accept(changed), {code: 'ClientRequestPlanEvidenceMismatch'});
  assert.equal(accept().inserted, false);

  const db = new DatabaseSync(join(captured.path, 'client-requests.sqlite3'));
  try {
    db.prepare('UPDATE client_run_explanation_plan_originals SET plan_view_wire=?').run('é'.repeat(65536));
    assert.throws(() => captured.journal.probeRunExplanationContextOriginal(captured.ref),
      {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => captured.journal.readRunExplanationContextOriginal(captured.ref, extent),
      {code: 'ClientRequestJournalCorrupt'});
    assert.throws(captured.lookupPlan, {code: 'ClientRequestJournalCorrupt'});
  } finally {db.close();}
});

test('Context with its retired inline Plan refuses on either read without repairing the row', t => {
  const f = fixture(t, explanationSchemaConfiguration);
  assert.equal(f.accept(f.ticket(undefined, contextWire)).inserted, true);
  f.reopen();
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    const before = JSON.stringify({...evidence, logicalPlanOriginal: planOriginal});
    db.exec('DROP TABLE client_run_explanation_plan_originals');
    db.prepare('UPDATE client_requests SET run_admission_evidence_json=?').run(before);
    assert.throws(f.lookupPlan, {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => f.journal.probeRunExplanationOriginal(f.ref), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => f.journal.probeRunExplanationContextOriginal(f.ref), {code: 'ClientRequestJournalCorrupt'});
    assert.equal(db.prepare('SELECT run_admission_evidence_json AS wire FROM client_requests').get().wire, before);
  } finally {db.close();}
});

test('the split Plan and Context share one exact write limit', t => {
  const facts = JSON.stringify(explanationFacts);
  for (const extra of [0, 1]) {
    const f = fixture(t, explanationSchemaConfiguration);
    const available = 65536 - [facts, contextWire, invocationTemplateWire, planOriginal.compiledPlanWire]
      .reduce((bytes, wire) => bytes + Buffer.byteLength(wire), 0);
    const control = {...f.control, originalRunPlanAdmissionEvidence: () => ({
      compiledPlanWire: planOriginal.compiledPlanWire, planViewWire: 'x'.repeat(available + extra),
    })};
    const admit = () => f.journal.acceptDefinition(request, {...options, originalPlan: f.planTicket(),
      originalExplanation: f.ticket(facts, contextWire, invocationTemplateWire)}, requestControl, control);
    if (extra === 0) {
      assert.equal(admit().inserted, true);
      assert.equal(f.journal.probeRunExplanationContextOriginal(f.ref).planViewBytes, available);
    } else {
      assert.throws(admit, {code: 'InvalidClientRunAdmissionEvidence'});
      assert.equal(f.lookup(), undefined);
      assert.equal(f.acknowledgements(), 0);
    }
  }
});

test('selected wider Journal caps optional Context facets and evidence at the same 64 KiB extent', t => {
  const policy = recipeModule.declareHostJournalServiceRecipe({}).journal;
  assert.equal(policy.maxRunDefinitionWireBytes, 64 * 1024 * 1024);
  const limit = 65536;
  for (const extra of [0, 1]) {
    const f = fixture(t, policy);
    assert.equal(f.journal.originalExplanationContextLimit(), limit);
    const facts = JSON.stringify(explanationFacts);
    const remaining = limit - [facts, invocationTemplateWire, ...Object.values(planOriginal)]
      .reduce((bytes, wire) => bytes + Buffer.byteLength(wire), 0);
    const sized = 'x'.repeat(remaining + extra);
    const ticket = f.ticket(facts, sized);
    if (extra === 0) {
      assert.equal(f.accept(ticket).inserted, true);
      f.reopen();
      const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
      assert.equal(extent.factsBytes + extent.contextBytes + extent.invocationTemplateBytes +
        extent.compiledPlanBytes + extent.planViewBytes, limit);
      assert.equal(f.acknowledgements(), 1);
    } else {
      assert.throws(() => f.accept(ticket), {code: 'InvalidClientRunAdmissionEvidence'});
      assert.equal(f.lookup(), undefined);
      assert.equal(f.acknowledgements(), 0);
    }
  }
  for (const extra of [0, 1]) {
    const f = fixture(t, policy), ticket = f.ticket(undefined, contextWire), originalPlan = f.planTicket();
    const prefix = {...evidence, effectOriginalRunWire: ''};
    const available = limit - Buffer.byteLength(JSON.stringify(prefix));
    const base = Object.freeze({...prefix, effectOriginalRunWire: 'x'.repeat(available + extra)});
    assert.equal(Buffer.byteLength(JSON.stringify(base)), limit + extra);
    const control = {...f.control,
      originalRunPlanAdmissionEvidence(selected, run, program, admitted) {
        assert.equal(admitted, base);
        return f.control.originalRunPlanAdmissionEvidence(selected, run, program, evidence);
      },
      originalRunExplanationAdmissionEvidence(selected, run, program, admitted) {
        assert.equal(admitted, base);
        return f.control.originalRunExplanationAdmissionEvidence(selected, run, program, evidence);
      },
    };
    const accept = contextTicket => f.journal.acceptDefinition(request, {...options,
      runAdmissionEvidence: base, originalPlan: contextTicket === undefined ? undefined : originalPlan,
      originalExplanation: contextTicket}, requestControl, control);
    if (extra === 0) {
      assert.equal(accept(ticket).inserted, true);
      assert.equal(f.acknowledgements(), 1);
    } else {
      const stringify = JSON.stringify;
      JSON.stringify = (value, ...args) => {
        assert.notEqual(value?.effectOriginalRunWire, base.effectOriginalRunWire, 'oversized optional evidence must not be serialized');
        return stringify(value, ...args);
      };
      try {assert.throws(() => accept(ticket), {code: 'InvalidClientRunAdmissionEvidence'});}
      finally {JSON.stringify = stringify;}
      assert.equal(f.lookup(), undefined);
      assert.equal(f.acknowledgements(), 0);
      assert.equal(accept(undefined).inserted, true, 'the ordinary Journal policy still admits this size');
      const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
      assert.equal(extent.evidenceBytes, limit + extra);
      assert.equal(extent.contextBytes, 0);
    }
  }
});

test('competing Effect Context keeps the exact durable winner and returns only its own loan', t => {
  for (const retainedContext of [undefined, contextWire]) {
    const f = fixture(t);
    f.accept(f.ticket(undefined, retainedContext));
    const body = JSON.parse(options.runDefinition.wire);
    delete body.run_definition_cid;
    body.run_id = 'competing-context-run';
    const identity = 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
    const runDefinition = Object.freeze({name: 'run_definition', identity,
      wire: canonicalText({...body, run_definition_cid: identity})});
    assert.notEqual(runDefinition.identity, f.ref.runDefinitionCid);
    const ticket = f.ticket(undefined, '{}');
    const plan = f.planTicket();
    const control = {...f.control,
      admit(kind, wire) {
        assert.equal(kind, 'run_definition');
        if (wire === options.runDefinition.wire) return options.runDefinition;
        assert.equal(wire, runDefinition.wire);
        return runDefinition;
      },
      originalRunPlanAdmissionEvidence(selected, definition, program, original) {
        assert.equal(selected, plan);
        assert.equal(definition, runDefinition);
        return f.control.originalRunPlanAdmissionEvidence(selected, options.runDefinition, program, original);
      },
      originalRunExplanationAdmissionAcknowledged(selected, definition, program, original) {
        assert.equal(selected, ticket);
        assert.equal(definition, runDefinition);
        f.control.originalRunExplanationAdmissionAcknowledged(selected, options.runDefinition, program, original);
      },
    };
    const accepted = f.journal.acceptDefinition(request, {...options, runDefinition,
      originalPlan: plan, originalExplanation: ticket}, requestControl, control);
    assert.equal(accepted.inserted, false);
    assert.deepEqual(accepted.ref, f.ref);
    assert.equal(f.acknowledgements(), 2);
    const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
    assert.equal(f.journal.readRunExplanationContextOriginal(f.ref, extent).contextWire, retainedContext);
    assert.equal(f.journal.probeRunExplanationContextOriginal({...f.ref, runDefinitionCid: identity}), undefined);
  }
});

test('failed Context insertion rolls back the first Run, Plan and Facts before acknowledgement', t => {
  const f = fixture(t);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    db.exec(`CREATE TABLE client_run_explanation_context_originals (
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_run_explanation_originals(run_definition_cid) ON DELETE CASCADE,
  context_wire TEXT NOT NULL,
  context_wire_sha256 TEXT NOT NULL,
  invocation_template_wire TEXT NOT NULL
) STRICT`);
    db.exec(`CREATE TRIGGER fail_context_fixture BEFORE INSERT ON client_run_explanation_context_originals
      BEGIN SELECT RAISE(ABORT, 'test Context write failure'); END`);
    assert.throws(() => f.accept(f.ticket(undefined, contextWire)), error => {
      assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
      assert.equal(error.outcome, 'failed');
      assert.equal(error.connectionUsable, true);
      assert.match(error.cause?.message, /test Context write failure/u);
      return true;
    });
    assert.equal(f.lookup(), undefined);
    assert.equal(f.explanation(), undefined);
    assert.equal(f.acknowledgements(), 0);
    assert.equal(db.prepare('SELECT count(*) AS n FROM client_run_explanation_context_originals').get().n, 0);
  } finally {db.close();}
});

test('Context and Template enforce a paired aggregate extent and refuse changed rows inside the native SELECT', t => {
  const f = fixture(t);
  assert.throws(() => f.accept(f.ticket(undefined, contextWire, null)), {code: 'InvalidClientRunExplanationOriginal'});
  assert.throws(() => f.accept(f.ticket(undefined, undefined, invocationTemplateWire)), {code: 'InvalidClientRunExplanationOriginal'});
  assert.throws(() => f.accept(f.ticket(undefined, 'é'.repeat(32768))), {code: 'InvalidClientRunAdmissionEvidence'});
  assert.throws(() => f.accept(f.ticket(undefined, contextWire, 'é'.repeat(32768))), {code: 'InvalidClientRunAdmissionEvidence'});
  assert.equal(f.lookup(), undefined);
  f.accept(f.ticket(undefined, contextWire));
  const extent = f.journal.probeRunExplanationContextOriginal(f.ref);
  assert.throws(() => f.journal.readRunExplanationContextOriginal(f.ref, {...extent,
    invocationTemplateBytes: 0, storedBytes: extent.storedBytes - extent.invocationTemplateBytes}),
  {code: 'InvalidClientRunExplanationExtent'});
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  const prepare = DatabaseSync.prototype.prepare, get = StatementSync.prototype.get;
  const selected = new WeakSet();
  let observed;
  DatabaseSync.prototype.prepare = function(sql, ...args) {
    const statement = Reflect.apply(prepare, this, [sql, ...args]);
    if (sql.includes('JOIN client_run_explanation_context_originals')) {
      assert(Buffer.byteLength(sql) <= 4096);
      selected.add(statement);
    }
    return statement;
  };
  StatementSync.prototype.get = function(...args) {
    const row = Reflect.apply(get, this, args);
    if (selected.has(this)) observed = row;
    return row;
  };
  try {
    for (const [field, original] of [['context_wire', contextWire], ['invocation_template_wire', invocationTemplateWire]]) {
      const update = db.prepare(`UPDATE client_run_explanation_context_originals SET ${field}=?`);
      for (const changed of ['{}', 'é'.repeat(32769)]) {
        update.run(changed);
        assert.throws(() => f.journal.readRunExplanationContextOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
        assert.equal(observed[field], null, 'the native reader must withhold the changed original');
        assert.equal(f.explanation().factsWire, JSON.stringify(explanationFacts));
      }
      assert.throws(() => f.journal.probeRunExplanationContextOriginal(f.ref), {code: 'ClientRequestJournalCorrupt'});
      update.run(original);
    }
    const changed = contextWire.replace('["tag"]', '["zip"]');
    assert.notEqual(changed, contextWire);
    assert.equal(Buffer.byteLength(changed), extent.contextBytes);
    const updateContext = db.prepare('UPDATE client_run_explanation_context_originals SET context_wire=?');
    updateContext.run(changed);
    assert.throws(() => f.journal.readRunExplanationContextOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
    assert.equal(observed.context_wire, changed, 'length alone admits the replacement from SQLite');
    assert.equal(f.explanation().factsWire, JSON.stringify(explanationFacts));
    updateContext.run(contextWire);
    const original = f.journal.readRunExplanationContextOriginal(f.ref, extent);
    assert.equal(original.contextWire, contextWire);
    assert.equal(Object.hasOwn(original, 'contextWireSha256'), false);
    const replaceChecksum = db.prepare('UPDATE client_run_explanation_context_originals SET context_wire_sha256=?');
    replaceChecksum.run(createHash('sha256').update('sha256:' + 'f'.repeat(64)).update(contextWire).digest('hex'));
    assert.throws(() => f.journal.readRunExplanationContextOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
    replaceChecksum.run(createHash('sha256').update(f.ref.runDefinitionCid).update(contextWire).digest('hex'));
    assert.equal(f.journal.readRunExplanationContextOriginal(f.ref, extent).contextWire, contextWire);
    db.prepare('DELETE FROM client_run_explanation_context_originals').run();
    assert.throws(() => f.journal.readRunExplanationContextOriginal(f.ref, extent), {code: 'ClientRequestJournalCorrupt'});
  } finally {
    StatementSync.prototype.get = get;
    DatabaseSync.prototype.prepare = prepare;
    db.close();
  }
});
