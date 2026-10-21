import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installClientRunPlan} from './client-run-plan.mjs';
import {controls, request, requestControl, options, definition, evidence,
  planOriginal, originalPlanWire} from './fixtures/original-plan-journal.mjs';

function fixture(t, limits) {
  const path = mkdtempSync(join(tmpdir(), 'actql-d-original-map-'));
  let journal = openClientRequestJournal(path, limits);
  const owner = controls();
  t.after(() => {journal.close(); rmSync(path, {recursive: true, force: true});});
  const ref = {namespaceId: 'original', authorityScopeCid: request.authorityScopeCid,
    runDefinitionCid: definition.identity};
  return {path, owner, ref, get journal() {return journal;},
    accept: ticket => journal.acceptDefinition(request, {...options, originalPlan: ticket}, requestControl, owner.publication),
    lookup: () => journal.lookupRunDefinition(ref, requestControl, owner.publication),
    reopen() {journal.close(); journal = openClientRequestJournal(path, limits);}};
}

function planRequest(ref) {
  return {connection:{mode:'local',owner:'local',consentRefs:[],runners:[]},
    principalId:'original-caller',ref,maxWireBytes:65536,maxNodes:4096,maxDepth:64};
}

test('Run metadata and nominal acceptance do not validate an unused logical map', t => {
  const f = fixture(t);
  f.accept(f.owner.ticket());
  assert.equal(f.owner.counts.captureReads,1);
  assert.equal(f.owner.counts.storedReads,0,
    'the nominal compiler owner already checked the original before its ticket escaped');
  for (let i = 0; i < 20; i++) assert.deepEqual(f.lookup().runDefinition,definition);
  f.reopen();
  assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal,planOriginal);
  assert.equal(f.owner.counts.storedReads,0,
    'Run metadata does not consume the logical map or compile another one');
});

test('actual Run plan read validates its original once across Journal lookups', async t => {
  const f = fixture(t);
  f.accept(f.owner.ticket());
  f.owner.counts.storedReads = 0;
  let allowed = true;
  const read = installClientRunPlan({authorize:()=>allowed,
    lookupOriginal:()=>f.lookup(),control:f.owner.publication});
  const view = await read(planRequest(f.ref));
  assert.deepEqual(view.plan_view,JSON.parse(planOriginal.planViewWire));
  assert.equal(f.owner.counts.storedReads,1,
    'only the actual plan reader admits its used map; metadata observations do not repeat it');
  allowed = false;
  await assert.rejects(read(planRequest(f.ref)),{code:'RunObservationAccessDenied'});
  assert.equal(f.owner.counts.storedReads,1,'a later Deny refuses before another plan read');
});

test('unused original map still obeys retained shape and byte limits', t => {
  const f = fixture(t);
  f.accept(f.owner.ticket());
  f.owner.counts.storedReads = 0;
  const database = new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try {
    const stored = JSON.parse(database.prepare('SELECT run_admission_evidence_json FROM client_requests').get().run_admission_evidence_json);
    for (const view of ['x'.repeat(65537),42]) {
      const changed = {...stored,logicalPlanOriginal:{...stored.logicalPlanOriginal,planViewWire:view}};
      database.prepare('UPDATE client_requests SET run_admission_evidence_json=?').run(JSON.stringify(changed));
      assert.throws(f.lookup,{code:'ClientRequestJournalCorrupt'});
    }
    assert.equal(f.owner.counts.storedReads,0,'range/shape refusal does not run semantic map admission');
  } finally { database.close(); }
});

test('original compiler plan is retained atomically and lookup never recaptures it', t => {
  const f = fixture(t), selected = f.owner.ticket();
  const accepted = f.accept(selected);
  assert.deepEqual(accepted.runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(Object.isFrozen(accepted.runAdmissionEvidence.logicalPlanOriginal), true);
  assert.equal(f.accept(selected).inserted, false);
  const reads = f.owner.counts.captureReads;
  f.reopen();
  assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(f.owner.counts.captureReads, reads);
  assert.equal(f.lookup().revision, 0);
  assert.equal(f.lookup().physicalStartReserved, false);
});

test('legacy map absence is not backfilled and different original bytes do not replace acceptance', t => {
  const f = fixture(t);
  f.accept(undefined);
  assert.throws(() => f.accept(f.owner.ticket()), {code: 'ClientRequestPlanEvidenceMissing'});
  f.reopen(); assert.equal(f.lookup().runAdmissionEvidence.logicalPlanOriginal, undefined);
  assert.equal(f.lookup().revision, 0);
});

test('duplicate acceptance requires exact original plan bytes', t => {
  const f = fixture(t); f.accept(f.owner.ticket());
  const changed = {...planOriginal, planViewWire: originalPlanWire(['changed'])};
  assert.throws(() => f.accept(f.owner.ticket(changed)), {code: 'ClientRequestPlanEvidenceMismatch'});
  const spaced = {...planOriginal, planViewWire: JSON.stringify(JSON.parse(planOriginal.planViewWire), null, 2)};
  assert.throws(() => f.accept(f.owner.ticket(spaced)), {code: 'ClientRequestPlanEvidenceMismatch'});
  assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(f.lookup().revision, 0);
});

test('copied wire or unowned compiler ticket cannot supply the first original map', t => {
  const f = fixture(t);
  assert.throws(() => f.accept({}), {code: 'InvalidClientRunPlanOriginal'});
  assert.throws(() => f.journal.acceptDefinition(request, {...options,
    runAdmissionEvidence: {...evidence, logicalPlanOriginal: planOriginal}},
  requestControl, f.owner.publication), {code: 'InvalidClientRunPlanOriginal'});
  assert.equal(f.lookup(), undefined);
  for (const value of [null, {}, {...planOriginal,planViewWire:''},
    {...planOriginal,compiledPlanWire:42}]) {
    assert.throws(() => f.accept(f.owner.ticket(value)), {code:'InvalidClientRunPlanOriginal'});
  }
  assert.equal(f.lookup(),undefined);
});

test('original map aggregate bytes use the existing admission capacity', t => {
  const f = fixture(t, {maxRunDefinitionWireBytes: 1024});
  assert.throws(() => f.accept(f.owner.ticket()), {code: 'InvalidClientRunAdmissionEvidence'});
  assert.equal(f.lookup(), undefined);
});

test('original map and Run roll back together on custody commit failure', t => {
  const f = fixture(t), database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  t.after(() => database.close());
  database.exec(`CREATE TRIGGER reject_map_custody BEFORE UPDATE ON client_submission_custody
    BEGIN SELECT RAISE(ABORT, 'OriginalMapCustodyFailure'); END`);
  assert.throws(() => f.accept(f.owner.ticket()), {code: 'ClientRequestAcceptanceUnknown'});
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
  assert.equal(database.prepare('SELECT issued_count AS n FROM client_submission_custody').get().n, 0);
  database.exec('DROP TRIGGER reject_map_custody');
  assert.equal(f.accept(f.owner.ticket()).inserted, true);
});

test('separate process recovers the original map after the acceptance reply is discarded', t => {
  const f = fixture(t); f.journal.close();
  const journalUrl = new URL('./client-request-journal.mjs', import.meta.url).href;
  const fixtureUrl = new URL('./fixtures/original-plan-journal.mjs', import.meta.url).href;
  const code = `import {openClientRequestJournal} from ${JSON.stringify(journalUrl)};
    import {controls,request,requestControl,options} from ${JSON.stringify(fixtureUrl)};
    const journal=openClientRequestJournal(process.argv[1]);const owner=controls();
    journal.acceptDefinition(request,{...options,originalPlan:owner.ticket()},requestControl,owner.publication);
    journal.close();`;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', code, f.path],
    {encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
  assert.equal(child.error, undefined); assert.equal(child.signal, null); assert.equal(child.status, 0);
  assert.equal(child.stdout, '');
  f.reopen(); assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(f.owner.counts.captureReads, 0);
  assert.equal(f.lookup().ref.runDefinitionCid, definition.identity);
  assert.equal(f.lookup().revision, 0);
  assert(readFileSync(join(f.path, 'client-requests.sqlite3')).length > 0);
});

test('original map string values retain Unicode and line endings across storage restart', t => {
  const f = fixture(t);
  const names = ['e\u0301', 'é', '\r', '\n', '\r\n'];
  const original = {...planOriginal, planViewWire: originalPlanWire(names)};
  f.accept(f.owner.ticket(original)); f.reopen();
  const stored = f.lookup().runAdmissionEvidence.logicalPlanOriginal.planViewWire;
  assert.equal(stored, original.planViewWire);
  assert.deepEqual(JSON.parse(stored).logical_map.steps[0].names, names);
});

test('original reader failure belongs to plan use and cannot recapture a replacement', async t => {
  const f = fixture(t); f.accept(f.owner.ticket());
  const reads = f.owner.counts.captureReads;
  const originalFailure = new Error('OriginalMapReadFailure');
  let mapReads = 0;
  const unavailable = {...f.owner.publication, readStoredRunPlanOriginal() {
    mapReads++;
    throw originalFailure;
  }};
  const lookupOriginal = () => f.journal.lookupRunDefinition(f.ref,requestControl,unavailable);
  assert.equal(lookupOriginal().runDefinition.identity,definition.identity);
  assert.equal(mapReads,0,'an unused map reader cannot block Run metadata or cleanup');
  const read = installClientRunPlan({authorize:()=>true,lookupOriginal,control:unavailable});
  await assert.rejects(read(planRequest(f.ref)),error=>error===originalFailure);
  assert.equal(mapReads,1);
  assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(f.owner.counts.captureReads, reads);
  assert.equal(f.lookup().revision, 0);
});
