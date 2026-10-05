// SQL/fencing test doubles only. These do not establish real Core Model
// admission, fixed-input custody, retry classification or Store durability.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
import {DatabaseSync} from 'node:sqlite';
export const C = value => `sha256:${createHash('sha256').update(String(value)).digest('hex')}`;
export const encode = JSON.stringify;
export const owner = {runId: 'run-model', runDefinitionCid: C('run'), preparedInvocationCid: C('prepared')};
export const identity = {...owner, checkpointCid: C('checkpoint'), scopeCid: C('scope'),
  providerBindingCid: C('provider'), inputArtifactCid: C('input'), taskIndex: 0, strategyRevision: 0};
export const immediateIdentity = Object.fromEntries(Object.entries(identity).filter(([key]) => key !== 'checkpointCid'));
export const entryKeys = [...Object.keys(immediateIdentity), 'provenance', 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid'];
export const pickEntry = entry => Object.fromEntries((entry.provenance === 'deferred'
  ? [...Object.keys(identity), 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid',
      'intentId', 'claimant', 'generation', 'resolutionCid']
  : [...entryKeys, 'authorityCid']).map(k => [k, entry[k]]));
export function input(count = 3, maxAttempts = 1) {
  const slots = Array.from({length: count}, (_, ordinal) => ({ordinal,
    slotCid: C(`slot-${ordinal}`), modelTaskCid: C('task'), fixedRequestCid: C(`request-${ordinal}`), maxAttempts}));
  return {
    body: {kind: 'model_invocation', checkpoint_cid: identity.checkpointCid,
      checkpoint_id: 'checkpoint-model', run_id: owner.runId, run_definition_cid: owner.runDefinitionCid,
      subject: {subject_kind: 'run_unit', unit_id: 'unit-model'},
      phase: 'activation', required_artifact: {artifact_type: 'model_invocation_scope', artifact_cid: identity.scopeCid},
      requirements: [], review_projection_cid: C('review'), continuation_state_cid: C('continuation'),
      reason_code: 'approval', human_summary: 'Model call set', created_at: '1970-01-01T00:00:01.000Z',
      expires_at: '2030-01-01T00:00:00.000Z'},
    priorStatus: 'running', declaredResults: ['result'],
    authorities: [{keyId: 'key', reviewerId: 'reviewer'}],
    binding: {authorizationContextCid: C('auth'), environmentBindingCid: C('env')},
    modelCallSet: {
      originalRunWire: encode({...owner, validUntil: new Date(100000).toISOString()}),
      preparedInvocationWire: encode({cid: owner.preparedInvocationCid}),
      scopeWire: encode({...immediateIdentity, slots}), providerBindingWire: encode({cid: identity.providerBindingCid}),
      slotWires: slots.map(encode), fixedInputReceiptWire: encode({cid: identity.inputArtifactCid, durable: true}),
    },
  };
}
export const runtime = {
  checkpointSealBody(wire) { const b = JSON.parse(wire); return encode({ok: true,
    checkpoint_wire: wire, checkpoint_cid: b.checkpoint_cid, checkpoint_id: b.checkpoint_id,
    run_id: b.run_id, prepare_attempt_id: null, subject_kind: 'run_unit', expires_at: b.expires_at}); },
  checkpointAdmit(wire) {return this.checkpointSealBody(wire);},
  runTransitionAllowed: () => true,
  checkpointWaitingState: () => encode({ok: true, run_state_wire: encode({status: 'waiting_checkpoint'})}),
  checkpointLifecycleState: (runId, status) => encode({ok: true, run_state_wire: encode({runId, status})}),
  resumeFenceDecide(wire, claimant, generation, now) {
    const i = JSON.parse(wire); return encode({ok: true, action: i.state === 'claimed' &&
      i.claimant === claimant && i.generation === generation && i.lease_expires_ms > now ? 'current' : 'stale'});
  },
  resumedApprovalAt(wire, now) {
    return encode({...JSON.parse(wire), ok: true, current: Date.parse(now) < JSON.parse(wire).expires});
  },
  modelInvocationGrantAt(requestWire, checkpointWire, verifiedWire) {
    const scope = JSON.parse(JSON.parse(requestWire).scopeWire);
    const approval = JSON.parse(verifiedWire);
    return encode({...scope, ok: true, current: true,
      checkpointCid: JSON.parse(checkpointWire).checkpoint_cid,
      expiresAt: approval.expires_at, resolutionCid: approval.resolution_cid,
      verifiedResolutionCid: approval.verified_resolution_cid});
  },

  modelImmediateInvocationGrantAt(...args) {return this.modelInvocationGrantAt(...args);},};
export function open(root, {clock = {value: 1000}, settlements = new Map(),
  verifySettlement = async ({entry}) => settlements.get(entry.attemptCid) ?? null,
  faults = {}, mutateInventory, verifierOverrides = {}, runtimeOverrides = {},
  authorizeResolution = () => ({keyId: 'key', reviewerId: 'reviewer',
    authorityContextCid: C('authority-context'), policyCid: C('policy'), verifiedPreimage: 'proof'}),
  attestResolution = () => ({hostKeyId: 'host-key', signature: 'signature'})} = {}) {
  // Deliberate physical-owner doubles: exact object custody and exact issued
  // attempt bindings, not a production gate or A's unpublished callback adapter.
  const decisions = new WeakMap();
  const preparedOwners = new WeakMap();
  function issueImmediate(reference, {reuse, dispatchValidUntil = new Date(100000).toISOString()} = {}) {
    const tokens = reuse ?? {decision: Object.freeze({}), preparedCallSet: Object.freeze({})};
    if (reuse === undefined) {
      decisions.set(tokens.decision, {current: true, dispatchValidUntil, scopeCid: identity.scopeCid});
      preparedOwners.set(tokens.preparedCallSet, {scopeCid: identity.scopeCid, attempts: new Map()});
    }
    preparedOwners.get(tokens.preparedCallSet).attempts.set(reference.attemptCid, {
      attemptWire: reference.attemptWire, authorityWire: reference.authorityWire,
      slotCid: reference.slotCid, attemptIndex: reference.attemptIndex});
    return tokens;
  }
  function inventoryFrom(originals) {
    const scope = JSON.parse(originals.scopeWire);
    assert.deepEqual(scope.slots, originals.slotWires.map(JSON.parse));
    assert.equal(scope.providerBindingCid, JSON.parse(originals.providerBindingWire).cid);
    assert.equal(scope.preparedInvocationCid, JSON.parse(originals.preparedInvocationWire).cid);
    assert.equal(scope.inputArtifactCid, JSON.parse(originals.fixedInputReceiptWire).cid);
    assert.equal(JSON.parse(originals.fixedInputReceiptWire).durable, true);
    const inventory = {...scope, fixedInputCustody: JSON.parse(originals.fixedInputReceiptWire),
      retryBinding: {maxAttempts: scope.slots[0]?.maxAttempts ?? 1}};
    return mutateInventory ? mutateInventory(inventory) : inventory;
  }
  const verifier = {
    admitOriginalRun: ({originalRunWire}) => JSON.parse(originalRunWire),
    admitCallSet(originals) {
      return {...inventoryFrom(originals), checkpointCid: JSON.parse(originals.checkpointWire).checkpoint_cid};
    },
    admitImmediateCallSet(originals) {
      return {...inventoryFrom(originals), runValidUntil: JSON.parse(originals.originalRunWire).validUntil};
    },
    admitImmediateEntry({decision, preparedCallSet, inventory, slot, attemptIndex,
      attemptCid, attemptWire, authorityWire, at}) {
      const action = decisions.get(decision); const prepared = preparedOwners.get(preparedCallSet);
      assert.equal(action?.current, true);
      assert.equal(action.scopeCid, inventory.scopeCid);
      assert.equal(prepared?.scopeCid, inventory.scopeCid);
      assert.deepEqual(prepared.attempts.get(attemptCid), {attemptWire, authorityWire,
        slotCid: slot.slotCid, attemptIndex});
      assert.ok(Date.parse(at) < Date.parse(action.dispatchValidUntil));
      return {...immediateIdentity, ordinal: slot.ordinal, slotCid: slot.slotCid, attemptIndex, attemptCid,
        authorityCid: C(authorityWire), current: true, admittedAt: at,
        runValidUntil: inventory.runValidUntil, dispatchValidUntil: action.dispatchValidUntil};
    },
    admitAttempt({slot, attemptIndex, attemptCid, attemptWire, authorityWire}) {
      assert.deepEqual(JSON.parse(authorityWire), {scopeCid: identity.scopeCid});
      assert.deepEqual(JSON.parse(attemptWire), {slotCid: slot.slotCid, attemptIndex, attemptCid});
      return {attemptIndex, attemptCid};
    },
    verifySettlement,
    ...verifierOverrides,
  };
  const journal = openSqliteCheckpointJournal(root, {runtime: {...runtime, ...runtimeOverrides},
    expectedAuthorityScopeCid: C('authority'), authorizeResolution,
    attestResolution, modelResumeVerifier: verifier, now: () => clock.value, faults});
  return {journal, clock, settlements, issueImmediate,
    invalidateDecision: decision => {decisions.get(decision).current = false;}};
}
export function seedApproval(path, {generation = 1, expires = 100000} = {}) {
  const db = new DatabaseSync(path);
  const approval = {checkpoint_cid: identity.checkpointCid, resolution_cid: C('resolution'),
    verified_resolution_cid: C('verified'), expires, claims: [], reviewer_id: 'reviewer', expires_at: new Date(expires).toISOString()};
  db.exec('BEGIN IMMEDIATE');
  db.prepare('UPDATE checkpoints SET closure = ?, resolution_cid = ? WHERE checkpoint_cid = ?')
    .run('resolved', C('resolution'), identity.checkpointCid);
  db.prepare('UPDATE runs SET status = ? WHERE run_id = ?').run('resuming', owner.runId);
  db.prepare('INSERT INTO resolutions VALUES (?, ?, ?, ?, ?, ?)').run(C('resolution'), identity.checkpointCid,
    'approved', C('verified'), encode(approval), new Date(1000).toISOString());
  db.prepare(`INSERT INTO resume_intents VALUES (?, ?, ?, ?, NULL, 'claimed', ?, ?, ?, '', '')`)
    .run('intent', identity.checkpointCid, C('resolution'), owner.runId, generation, `owner-${generation}`, 1000000);
  db.exec('COMMIT'); db.close();
  return claim(generation);
}
export const claim = generation => ({intentId: 'intent', claimant: `owner-${generation}`, generation, runId: owner.runId});
export function replaceClaim(path, generation = 2) {
  const db = new DatabaseSync(path);
  db.prepare('UPDATE resume_intents SET generation = ?, claimant = ? WHERE intent_id = ?')
    .run(generation, `owner-${generation}`, 'intent'); db.close(); return claim(generation);
}
export function reference(ordinal, attemptIndex = 1) {
  const attemptCid = C(`attempt-${ordinal}-${attemptIndex}`);
  return {...identity, ordinal, slotCid: C(`slot-${ordinal}`), attemptIndex, attemptCid,
    resolutionCid: C('resolution'), authorityWire: encode({scopeCid: identity.scopeCid}), attemptWire: encode({slotCid: C(`slot-${ordinal}`), attemptIndex, attemptCid})};
}
export function immediateReference(ordinal, attemptIndex = 1) {
  const {checkpointCid, resolutionCid, ...value} = reference(ordinal, attemptIndex);
  return value;
}
export function saved(entry, state = 'SavedSuccess', retryAllowed = false) {
  return {entry: pickEntry(entry), state, durable: true, retryAllowed,
    evidence: {enteredAttemptCid: entry.attemptCid, captureCid: C(`capture-${entry.attemptCid}`), outcomeCid: C(`outcome-${entry.attemptCid}`)}};
}
