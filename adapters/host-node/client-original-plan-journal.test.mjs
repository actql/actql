import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';
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

test('original reader failure retains evidence and cannot recapture a replacement', t => {
  const f = fixture(t); f.accept(f.owner.ticket());
  const reads = f.owner.counts.captureReads;
  const unavailable = {...f.owner.publication, readStoredRunPlanOriginal() {
    throw new Error('OriginalMapReadFailure');
  }};
  assert.throws(() => f.journal.lookupRunDefinition(f.ref, requestControl, unavailable),
    {code: 'ClientRequestPlanReadUnknown'});
  assert.deepEqual(f.lookup().runAdmissionEvidence.logicalPlanOriginal, planOriginal);
  assert.equal(f.owner.counts.captureReads, reads);
  assert.equal(f.lookup().revision, 0);
});
