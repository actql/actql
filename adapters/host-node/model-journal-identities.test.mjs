// Actual bounded Common codec and SQLite journal; physical input custody,
// live dispatch and Store settlement are explicit doubles. No Provider I/O.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

const runtime = await loadCheckpointRuntime();
const fixture = JSON.parse(readFileSync(new URL('./fixtures/model-resolution-crypto.json', import.meta.url), 'utf8'));
// Independent data oracle: sorted keys, verbatim string data, no product hash.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const hash = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const checked = wire => {const value = JSON.parse(wire); assert.equal(value.ok, true, wire); return value;};
const request = {...Object.fromEntries(Object.entries(fixture.request)
  .filter(([key]) => key !== 'checkpointWire' && key !== 'reviewWire')),
fixedInputReceiptWire: JSON.stringify({testOnly: true, cid: hash({fixedOriginalInput: true})})};
const inventory = checked(runtime.modelImmediateCallSetAdmit(JSON.stringify(request)));
const identityKeys = ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'scopeCid',
  'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision'];
const identity = Object.fromEntries(identityKeys.map(key => [key, inventory[key]]));
const attempt = JSON.parse(fixture.attemptWire);
const authority = JSON.parse(fixture.authorityWire);
const instant = '2026-09-25T12:00:00.000Z';
const entry = {...identity, provenance: 'immediate', ordinal: 0,
  slotCid: attempt.slot_cid, attemptIndex: 1, attemptCid: attempt.self_cid,
  authorityCid: authority.self_cid, admittedAt: instant, modelGrantExpiresAt: inventory.runValidUntil,
  admission: {kind: 'model_invocation', provenance: 'immediate', runId: inventory.runId,
    requiredArtifactCid: inventory.scopeCid, authorityCid: authority.self_cid,
    admittedAt: instant, runValidUntil: inventory.runValidUntil,
    dispatchValidUntil: inventory.runValidUntil, modelGrantExpiresAt: inventory.runValidUntil}};
const unknownRow = () => ({scope_cid: inventory.scopeCid, ordinal: 0, attempt_index: 1,
  attempt_cid: attempt.self_cid, entry_json: JSON.stringify(entry),
  attempt_wire: fixture.attemptWire, authority_wire: fixture.authorityWire,
  state: 'EnteredUnknown', settlement_json: '', entered_at: instant, settled_at: ''});
const entryBody = () => ({version: 'actql-model-journal-entry/0.1',
  run_id: inventory.runId, run_definition_cid: inventory.runDefinitionCid,
  prepared_invocation_cid: inventory.preparedInvocationCid, scope_cid: inventory.scopeCid,
  provider_binding_cid: inventory.providerBindingCid, input_artifact_cid: inventory.inputArtifactCid,
  task_index: inventory.taskIndex, strategy_revision: inventory.strategyRevision,
  ordinal: 0, slot_cid: attempt.slot_cid, attempt_index: 1, attempt_cid: attempt.self_cid,
  dispatch_authority_cid: authority.self_cid, admitted_at: instant,
  model_grant_expires_at: inventory.runValidUntil, provenance: 'immediate',
  immediate: {run_valid_until: inventory.runValidUntil,
    dispatch_valid_until: inventory.runValidUntil, parent_resume_fence: null}, deferred: null});
const project = row => checked(runtime.modelOriginalJournalIdentity(JSON.stringify(request), JSON.stringify(row)));
const rejected = row => assert.equal(JSON.parse(runtime.modelOriginalJournalIdentity(
  JSON.stringify(request), JSON.stringify(row))).ok, false);
const settlementEntry = original => Object.fromEntries([...identityKeys, 'provenance',
  'ordinal', 'slotCid', 'attemptIndex', 'attemptCid', 'authorityCid'].map(key => [key, original[key]]));
const reference = cid => ({cid, holdingCid: hash({independentHolding: cid})});
const evidence = () => ({model_call_attempt: reference(attempt.self_cid),
  model_dispatch_authority: reference(authority.self_cid),
  model_attempt_accounting: reference(hash({originalAccounting: true})),
  model_attempt_outcome: reference(hash({originalOutcome: true}))});

test('original journal Common projection preserves actual Entry identity and Unknown absence', () => {
  const result = project(unknownRow()); const body = entryBody();
  assert.equal(result.entryCid, hash(body));
  assert.equal(result.entryWire, canonical({...body, self_cid: hash(body)}));
  assert.equal(result.settlementCid, null); assert.equal(result.settlementWire, null);
  assert.equal(Object.hasOwn(result, 'current'), false);
  assert.equal(Object.hasOwn(result, 'send'), false);
});

test('original journal Common projection rejects every original binding change and extra field', () => {
  for (const key of [...identityKeys, 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid', 'authorityCid']) {
    const row = unknownRow(); const changed = JSON.parse(row.entry_json);
    changed[key] = typeof changed[key] === 'number' ? changed[key] + 1 : hash({foreign: key});
    row.entry_json = JSON.stringify(changed); rejected(row);
  }
  for (const key of ['scope_cid', 'ordinal', 'attempt_index', 'attempt_cid', 'entered_at']) {
    const row = unknownRow(); row[key] = typeof row[key] === 'number' ? row[key] + 1 : 'foreign'; rejected(row);
  }
  const extra = unknownRow(); extra.grant = true; rejected(extra);
  const empty = unknownRow(); empty.state = 'Unsent'; rejected(empty);
});

test('original journal Common projection preserves original parent Unicode and refuses missing provenance', () => {
  const row = unknownRow(); const original = JSON.parse(row.entry_json);
  original.admission.parentResumeFence = {checkpointCid: hash({parent: true}),
    intentId: 'e\u0301\r\n', claimant: 'original-e\u0301', generation: 2};
  row.entry_json = JSON.stringify(original);
  const body = entryBody(); body.immediate.parent_resume_fence = {
    checkpoint_cid: original.admission.parentResumeFence.checkpointCid,
    intent_id: 'e\u0301\r\n', claimant: 'original-e\u0301', generation: 2};
  assert.equal(project(row).entryWire, canonical({...body, self_cid: hash(body)}));
  original.admission.parentResumeFence.resolutionCid = hash({fabricated: true});
  row.entry_json = JSON.stringify(original); rejected(row);
  delete original.provenance; row.entry_json = JSON.stringify(original); rejected(row);
});

test('original journal Common projection keeps partial saved failure and absent versus observed false', () => {
  const row = unknownRow(); const refs = {...evidence(), model_slot_capture: reference(hash({partial: true})), terminalFailure: false};
  const saved = {entry: settlementEntry(entry), state: 'SavedFailure', durable: true, retryAllowed: false, evidence: refs};
  row.state = saved.state; row.settlement_json = JSON.stringify(saved); row.settled_at = instant;
  const mapped = Object.fromEntries(Object.entries(refs).filter(([key]) => key !== 'terminalFailure')
    .map(([key, value]) => [key, {cid: value.cid, holding_cid: value.holdingCid}]));
  const body = {version: 'actql-model-journal-settlement/0.1', entry_identity_cid: hash(entryBody()),
    state: 'SavedFailure', durable: true, retry_allowed: false, settled_at: instant,
    evidence: {...mapped, model_capture_bundle: null, terminal_failure: false}};
  assert.equal(project(row).settlementWire, canonical({...body, self_cid: hash(body)}));
  delete saved.evidence.terminalFailure; row.settlement_json = JSON.stringify(saved);
  assert.equal(JSON.parse(project(row).settlementWire).evidence.terminal_failure, null);
  saved.evidence.model_call_attempt.cid = hash({foreign: true});
  row.settlement_json = JSON.stringify(saved); rejected(row);
});

function openActual(t, onProjection) {
  const root = mkdtempSync(join(tmpdir(), 'model-journal-identity-'));
  const settlements = new Map(); const owner = Object.freeze({});
  const verifier = {
    admitOriginalRun: ({originalRunWire}) => checked(runtime.modelOriginalRunAdmit(originalRunWire)),
    admitImmediateCallSet: originals => {
      const facts = checked(runtime.modelImmediateCallSetAdmit(JSON.stringify(originals)));
      return {...facts, fixedInputCustody: {testOnly: true}, retryBinding: {testOnly: true},
        slots: facts.slots.map(slot => ({...slot, maxAttempts: 1}))};
    },
    admitAttempt: ({originals, slot, attemptWire, authorityWire, attemptIndex}) => checked(
      runtime.modelImmediateCallAttemptAdmit(JSON.stringify(originals), slot.ordinal, attemptWire, authorityWire, attemptIndex)),
    admitImmediateEntry: ({decision, preparedCallSet, at}) => {
      assert.strictEqual(decision, owner); assert.strictEqual(preparedCallSet, owner);
      return {...identity, ordinal: 0, slotCid: attempt.slot_cid, attemptIndex: 1,
        attemptCid: attempt.self_cid, authorityCid: authority.self_cid, current: true,
        admittedAt: at, runValidUntil: inventory.runValidUntil, dispatchValidUntil: inventory.runValidUntil};
    },
    verifySettlement: async ({entry}) => settlements.get(entry.attemptCid) ?? null,
    projectOriginalJournalIdentity: facts => {onProjection?.(); return checked(
      runtime.modelOriginalJournalIdentity(JSON.stringify(facts.originals), JSON.stringify(facts.row)));},
  };
  const journal = openSqliteCheckpointJournal(root, {runtime, modelResumeVerifier: verifier,
    expectedAuthorityScopeCid: fixture.authentication.expected_authority_scope_cid,
    authorizeResolution: () => {throw Error('No approval is exercised');},
    attestResolution: () => {throw Error('No approval is exercised');},
    now: () => Date.parse(instant)});
  t.after(() => {journal.close(); rmSync(root, {recursive: true, force: true});});
  journal.registerImmediateModelCallSet({modelCallSet: request, declaredResults: ['result']});
  const entered = journal.enterImmediateModelCall({...identity, ordinal: 0,
    slotCid: attempt.slot_cid, attemptIndex: 1, attemptCid: attempt.self_cid,
    attemptWire: fixture.attemptWire, authorityWire: fixture.authorityWire},
  {decision: owner, preparedCallSet: owner});
  return {journal, settlements, entered};
}

test('actual journal nominal observation projects same originals across saved readback without new Entry', async t => {
  const f = openActual(t); const observation = f.journal.observeOriginalModelJournal(identity);
  const unknown = f.journal.originalModelJournalDataIdentities(observation);
  assert.equal(unknown.length, 1); assert.equal(unknown[0].entryCid, hash(entryBody()));
  assert.equal(unknown[0].settlementCid, null);
  assert.throws(() => f.journal.originalModelJournalDataIdentities({...observation}), {code: 'ForeignModelOriginalJournalObservation'});
  f.settlements.set(f.entered.attemptCid, {entry: settlementEntry(f.entered), state: 'SavedFailure',
    durable: true, retryAllowed: false, evidence: evidence()});
  await f.journal.observeImmediateModelCall(f.entered);
  assert.throws(() => f.journal.originalModelJournalDataIdentities(observation), {code: 'ModelOriginalJournalObservationChanged'});
  const fresh = f.journal.observeOriginalModelJournal(identity);
  const saved = f.journal.originalModelJournalDataIdentities(fresh);
  assert.equal(saved[0].entryCid, unknown[0].entryCid); assert.notEqual(saved[0].settlementCid, null);
  const db = new DatabaseSync(f.journal.path);
  try {assert.equal(db.prepare('SELECT count(*) AS n FROM resume_model_attempts').get().n, 1);}
  finally {db.close();}
});

test('actual journal reselects facts after projection callback and refuses changed observation', t => {
  let journal; let mutation = false;
  const f = openActual(t, () => {if (mutation) journal.fenceRunCancellation({originalRunWire: request.originalRunWire});});
  journal = f.journal;
  const observation = journal.observeOriginalModelJournal(identity); mutation = true;
  assert.throws(() => journal.originalModelJournalDataIdentities(observation), {code: 'ModelOriginalJournalObservationChanged'});
  assert.equal(journal.readModelCalls(identity).slots[0].state, 'EnteredUnknown');
  assert.equal(journal.modelCancellationFenced(identity.runId, identity.runDefinitionCid), true);
});

test('actual journal Common cut projects original latest Entry and unsent Slot without grant', t => {
  const f = openActual(t);
  const observation = f.journal.observeOriginalModelJournal(identity);
  const facts = f.journal.originalModelJournalObservationFacts(observation);
  const actual = checked(runtime.modelOriginalJournalCutData(JSON.stringify(facts)));
  assert.deepEqual(actual.cut, {scope_cid: identity.scopeCid,
    input_artifact_cid: identity.inputArtifactCid,
    fixed_input_receipt_cid: hash({fixedOriginalInput: true}), run_version: 1,
    continuation: null, slots: [{ordinal: 0, slot_cid: attempt.slot_cid,
      attempt_index: 1, state: 'EnteredUnknown', entry_identity_cid: hash(entryBody()), settlement_identity_cid: null},
    {ordinal: 1, slot_cid: JSON.parse(request.slotWires[1]).model_call_slot_cid,
      attempt_index: 0, state: 'Unsent', entry_identity_cid: null, settlement_identity_cid: null}]});
  assert.equal(Object.hasOwn(actual, 'park'), false);
  const changed = structuredClone(facts); changed.slots[0].attempt_index = 0;
  assert.equal(JSON.parse(runtime.modelOriginalJournalCutData(JSON.stringify(changed))).ok, false);
  changed.slots = []; assert.equal(JSON.parse(runtime.modelOriginalJournalCutData(JSON.stringify(changed))).ok, false);
});
