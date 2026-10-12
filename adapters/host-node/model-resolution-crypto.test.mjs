// Compiled-Core + SDK + Ed25519 composition. Only fixed synthetic test keys
// are used. Complete-call custody and retry facts remain explicit doubles;
// this test neither invokes a provider nor proves the Model execution driver.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createPrivateKey, createPublicKey, sign, verify} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {recordCheckpointApproval, checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

const runtime = await loadCheckpointRuntime();
const fixture = JSON.parse(readFileSync(new URL('./fixtures/model-resolution-crypto.json', import.meta.url), 'utf8'));
// Independent JSON/hashlib fixture inputs use ASCII and safe integers. This
// small verifier canonicalizer deliberately does not reuse SDK output helpers.
const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cidOf = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const without = (value, ...keys) => Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key)));
const admitted = text => {const result = JSON.parse(text); assert.equal(result.ok, true, text); return result;};
const privateKey = offset => createPrivateKey({format: 'der', type: 'pkcs8', key: Buffer.concat([
  Buffer.from('302e020100300506032b657004220420', 'hex'),
  Buffer.from(Array.from({length: 32}, (_, index) => index + offset)),
])});
const reviewer = privateKey(0);
const reviewerPublic = createPublicKey(reviewer);
const host = privateKey(32);
const hostPublic = createPublicKey(host);
const signer = {keyId: 'reviewer-key', reviewerId: 'alice',
  sign: bytes => sign(null, bytes, reviewer)};
const now = Date.parse('2026-09-25T12:00:00.000Z');
const decidedAt = new Date(now).toISOString();
const checkpoint = JSON.parse(fixture.request.checkpointWire);
const originalRun = JSON.parse(fixture.request.originalRunWire);
const definition = JSON.parse(originalRun.runDefinitionWire);
const prepared = JSON.parse(fixture.request.preparedInvocationWire);
const binding = {authorizationContextCid: definition.authorization_context_cid,
  environmentBindingCid: prepared.execution_context_cid};
const request = {...fixture.request, fixedInputReceiptWire: canonical({testOnly: true,
  inputArtifactCid: JSON.parse(fixture.request.scopeWire).input_artifact_cid})};
const verifier = {
  admitOriginalRun: ({originalRunWire}) => admitted(runtime.modelOriginalRunAdmit(originalRunWire)),
  admitCallSet(originals) {
    const facts = admitted(runtime.modelCallSetAdmit(canonical(originals)));
    return {...facts, fixedInputCustody: {testOnly: true, source: 'synthetic input owner'},
      retryBinding: {testOnly: true, maxAttempts: 1},
      slots: facts.slots.map(slot => ({...slot, maxAttempts: 1}))};
  },
  admitAttempt: ({originals, slot, attemptWire, authorityWire, attemptIndex}) => admitted(
    runtime.modelCallAttemptAdmit(canonical(originals), slot.ordinal, attemptWire, authorityWire, attemptIndex)),
  projectOriginalJournalIdentity: ({originals, row}) => admitted(
    runtime.modelOriginalJournalIdentity(JSON.stringify(originals), JSON.stringify(row))),
  verifySettlement: async () => {throw Error('No physical settlement is exercised');},
};
const inventory = verifier.admitCallSet(request);

function setup(t, {reviewExpiresAt, checkpointExpiresAt,
  clock = {value: now}, onAttest} = {}) {
  // Independent fixture mutations preserve original Run/scope/call identities.
  // Only their review and Checkpoint validity windows and CIDs are resealed.
  const localRequest = structuredClone(request);
  const localCheckpoint = JSON.parse(localRequest.checkpointWire);
  if (reviewExpiresAt !== undefined) {
    const review = JSON.parse(localRequest.reviewWire);
    review.expires_at = reviewExpiresAt;
    review.review_projection_cid = cidOf(without(review, 'review_projection_cid'));
    localRequest.reviewWire = canonical(review);
    localCheckpoint.review_projection_cid = review.review_projection_cid;
  }
  if (checkpointExpiresAt !== undefined) localCheckpoint.expires_at = checkpointExpiresAt;
  localCheckpoint.checkpoint_cid = cidOf(without(localCheckpoint, 'checkpoint_cid'));
  localRequest.checkpointWire = canonical(localCheckpoint);
  const localInventory = verifier.admitCallSet(localRequest);
  const settlements = new Map();
  const root = mkdtempSync(join(tmpdir(), 'model-resolution-crypto-'));
  const counts = {resolution: 0, approval: 0, attestation: 0};
  const journal = openSqliteCheckpointJournal(root, {runtime, modelResumeVerifier: {...verifier,
    verifySettlement: async ({entry}) => settlements.get(entry.attemptCid) ?? null},
    expectedAuthorityScopeCid: fixture.authentication.expected_authority_scope_cid,
    now: () => clock.value,
    // Same two-signature checks as the installed Checkpoint Host port. Both
    // artifacts must use the trusted reviewer identity and actual Ed25519 key.
    authorizeResolution({resolutionWire, approvalEvidenceWire, proofPreimage}) {
      const resolution = JSON.parse(resolutionWire);
      if (resolution.proof?.key_id !== signer.keyId || resolution.actor !== signer.reviewerId ||
          !verify(null, Buffer.from(proofPreimage, 'utf8'), reviewerPublic,
            Buffer.from(resolution.proof.signature ?? '', 'base64'))) {
        throw Error('InvalidResolutionSignature');
      }
      counts.resolution++;
      const approval = JSON.parse(approvalEvidenceWire).compatibility_approval;
      const approvalPreimage = cidOf(without(approval, 'proof', 'run_scope_approval_cid'));
      if (approval.proof?.key_id !== signer.keyId || approval.approver !== signer.reviewerId ||
          !verify(null, Buffer.from(approvalPreimage, 'utf8'), reviewerPublic,
            Buffer.from(approval.proof.signature ?? '', 'base64'))) {
        throw Error('InvalidApprovalSignature');
      }
      counts.approval++;
      return {keyId: signer.keyId, reviewerId: signer.reviewerId,
        authorityContextCid: fixture.authentication.authority_context_cid,
        policyCid: fixture.authentication.policy_cid, verifiedPreimage: proofPreimage};
    },
    attestResolution(preimage) {
      counts.attestation++;
      onAttest?.();
      return {hostKeyId: 'host-key', signature: sign(null, Buffer.from(preimage, 'utf8'), host).toString('base64')};
    },
  });
  t.after(() => {journal.close(); rmSync(root, {recursive: true, force: true});});
  journal.registerResumeCallSet({body: without(localCheckpoint, 'checkpoint_cid'),
    priorStatus: 'running', declaredResults: ['result'], binding,
    authorities: [{keyId: signer.keyId, reviewerId: signer.reviewerId}],
    requestedClaims: ['invocation_scope_approved'], decisionSubjectCid: inventory.scopeCid,
    configurationCid: fixture.request.expectedBoundary.configuration_cid,
    modelCallSet: localRequest});
  const view = journal.activeRunCheckpoint(inventory.runId);
  const identities = journal.modelCheckpointSummary(view.checkpointCid);
  assert.equal(identities.checkpointCid, view.checkpointCid);
  assert.equal(identities.runId, view.runId);
  assert.equal(identities.runDefinitionCid, view.runDefinitionCid);
  assert.equal(identities.scopeCid, view.requiredArtifact.cid);
  assert.equal(identities.reviewProjectionCid, view.reviewProjectionCid);
  const summary = {checkpointId: view.checkpointId, checkpointCid: view.checkpointCid,
    kind: view.kind, phase: view.phase, subject: {kind: 'run_unit', runId: view.runId,
      runDefinitionCid: view.runDefinitionCid}, requiredArtifact: {...view.requiredArtifact},
    preparedInvocationCid: identities.preparedInvocationCid,
    reviewProjectionCid: view.reviewProjectionCid, requirements: [...view.requirements],
    createdAt: view.createdAt, expiresAt: view.expiresAt, humanSummary: view.humanSummary};
  return {journal, summary, counts, inventory: localInventory, request: localRequest, clock, settlements};
}
const unchanged = journal => {
  assert.equal(journal.resolutionOf(inventory.checkpointCid), undefined);
  assert.deepEqual(journal.readResumeCalls(inventory).slots.map(slot => slot.state), ['Unsent', 'Unsent']);
};

test('original journal deferred identity preserves real signed approval admission without new permission', async t => {
  const {journal} = setup(t);
  const summary = journal.activeRunCheckpoint(inventory.runId);
  const identities = journal.modelCheckpointSummary(summary.checkpointCid);
  const publicSummary = {checkpointId: summary.checkpointId, checkpointCid: summary.checkpointCid,
    kind: summary.kind, phase: summary.phase, subject: {kind: 'run_unit', runId: summary.runId,
      runDefinitionCid: summary.runDefinitionCid}, requiredArtifact: {...summary.requiredArtifact},
    preparedInvocationCid: identities.preparedInvocationCid,
    reviewProjectionCid: summary.reviewProjectionCid, requirements: [...summary.requirements],
    createdAt: summary.createdAt, expiresAt: summary.expiresAt, humanSummary: summary.humanSummary};
  await journal.submitResolution(await signedAnswer(publicSummary, 'approved', signer, decidedAt));
  const claimed = journal.claimResume(inventory.runId, {claimant: 'original-journal', leaseMs: 1000, binding});
  const approval = journal.admitResume(claimed.claim, {checkpointCid: inventory.checkpointCid});
  const attempt = JSON.parse(fixture.attemptWire);
  journal.enterResumedCall(claimed.claim, {...inventory, ordinal: 0,
    slotCid: attempt.slot_cid, attemptIndex: 1, attemptCid: attempt.self_cid,
    attemptWire: fixture.attemptWire, authorityWire: fixture.authorityWire,
    intentId: claimed.claim.intentId, claimant: claimed.claim.claimant,
    generation: claimed.claim.generation, resolutionCid: approval.resolutionCid});
  const observation = journal.observeOriginalModelJournal(inventory);
  const raw = journal.originalModelJournalObservationFacts(observation).attempts[0];
  const entry = JSON.parse(raw.entry_json);
  const actual = journal.originalModelJournalDataIdentities(observation)[0];
  const expected = {version: 'actql-model-journal-entry/0.1',
    run_id: entry.runId, run_definition_cid: entry.runDefinitionCid,
    prepared_invocation_cid: entry.preparedInvocationCid, scope_cid: entry.scopeCid,
    provider_binding_cid: entry.providerBindingCid, input_artifact_cid: entry.inputArtifactCid,
    task_index: entry.taskIndex, strategy_revision: entry.strategyRevision,
    ordinal: entry.ordinal, slot_cid: entry.slotCid, attempt_index: entry.attemptIndex,
    attempt_cid: entry.attemptCid, dispatch_authority_cid: JSON.parse(fixture.authorityWire).self_cid,
    admitted_at: entry.admittedAt, model_grant_expires_at: entry.modelGrantExpiresAt,
    provenance: 'deferred', immediate: null, deferred: {
      checkpoint_cid: approval.checkpointCid, intent_id: approval.intentId,
      claimant: approval.claimant, generation: approval.generation,
      resolution_cid: approval.resolutionCid, verified_resolution_cid: approval.verifiedResolutionCid,
      lease_expires_ms: approval.leaseExpiresMs, prepare_attempt_id: null,
      kind: 'model_invocation', required_artifact_cid: approval.requiredArtifactCid,
      decision_subject_cid: approval.decisionSubjectCid, requested_claims: [...approval.requestedClaims],
      configuration_cid: approval.configurationCid, observed_claims: [...approval.observedClaims],
      authority: approval.authority, approval_expires_at: approval.approvalExpiresAt}};
  assert.equal(actual.entryWire, canonical({...expected, self_cid: cidOf(expected)}));
  assert.equal(actual.settlementWire, null);
  const changed = {...raw, entry_json: JSON.stringify({...entry, generation: entry.generation + 1})};
  assert.equal(JSON.parse(runtime.modelOriginalJournalIdentity(JSON.stringify(request), JSON.stringify(changed))).ok, false);
  assert.strictEqual(journal.reconfirmOriginalModelJournal(observation), observation);
});
const flipped = signature => {const bytes = Buffer.from(signature, 'base64'); bytes[0] ^= 1; return bytes.toString('base64');};

// This checks the existing identity-bound approval recorder after the actual
// Checkpoint authority boundary. It does not add or imitate a Model read API.
test('real SDK Model signatures commit exact inventory through compiled Core and recorded approval provenance', async t => {
  const {journal, summary, counts} = setup(t);
  const answer = await signedAnswer(summary, 'approved', signer, decidedAt);
  const committed = await journal.submitResolution(answer);
  assert.equal(committed.outcome, 'committed');
  assert.deepEqual(counts, {resolution: 1, approval: 1, attestation: 1});
  const verified = JSON.parse(committed.verifiedResolutionWire);
  const hostPreimage = admitted(runtime.verifiedAttestationPreimage(committed.verifiedResolutionWire)).preimage;
  assert.equal(hostPreimage, cidOf(without(verified, 'host_attestation', 'verified_resolution_cid')));
  assert.equal(verify(null, Buffer.from(hostPreimage, 'utf8'), hostPublic,
    Buffer.from(verified.host_attestation.signature, 'base64')), true);
  assert.equal(verify(null, Buffer.from(hostPreimage, 'utf8'), hostPublic,
    Buffer.from(flipped(verified.host_attestation.signature), 'base64')), false);
  const claimed = journal.claimResume(inventory.runId, {claimant: 'crypto-diagnostic', leaseMs: 1000, binding});
  assert.equal(claimed.action, 'claimed');
  const approval = journal.admitResume(claimed.claim, {checkpointCid: inventory.checkpointCid});
  assert.equal(approval.authority, signer.reviewerId);
  const decision = recordCheckpointApproval(Object.freeze({boundary: 'activation',
    action: 'dispatch', basis: 'resumed_approval', checkpointCid: approval.checkpointCid}),
  {checkpointCid: approval.checkpointCid, runId: inventory.runId,
    runDefinitionCid: inventory.runDefinitionCid, scopeCid: inventory.scopeCid,
    preparedInvocationCid: inventory.preparedInvocationCid});
  assert.deepEqual(checkpointApprovalFacts(decision), {checkpointCid: inventory.checkpointCid,
    runId: inventory.runId, runDefinitionCid: inventory.runDefinitionCid,
    scopeCid: inventory.scopeCid, preparedInvocationCid: inventory.preparedInvocationCid});
  assert.equal(checkpointApprovalFacts(Object.freeze({...decision})), undefined);
  assert.deepEqual(journal.readResumeCalls(inventory).slots.map(slot => slot.slotCid),
    JSON.parse(request.scopeWire).model_call_slot_cids);
  assert.deepEqual(journal.readResumeCalls(inventory).slots.map(slot => slot.state), ['Unsent', 'Unsent']);
});

test('altered Resolution signature is rejected by real Ed25519 before commit', async t => {
  const {journal, summary, counts} = setup(t);
  const answer = await signedAnswer(summary, 'approved', signer, decidedAt);
  const resolution = JSON.parse(answer.resolutionWire);
  resolution.proof.signature = flipped(resolution.proof.signature);
  resolution.resolution_cid = cidOf(without(resolution, 'resolution_cid'));
  await assert.rejects(journal.submitResolution({...answer, resolutionWire: canonical(resolution)}),
    error => error.code === 'ResolutionAuthenticationFailed' && error.cause?.message === 'InvalidResolutionSignature');
  assert.deepEqual(counts, {resolution: 0, approval: 0, attestation: 0});
  unchanged(journal);
});

test('altered compatibility approval signature is rejected even with a correctly re-signed Resolution', async t => {
  const {journal, summary, counts} = setup(t);
  const answer = await signedAnswer(summary, 'approved', signer, decidedAt);
  const evidence = JSON.parse(answer.approvalEvidenceWire);
  evidence.compatibility_approval.proof.signature = flipped(evidence.compatibility_approval.proof.signature);
  evidence.compatibility_approval.run_scope_approval_cid = cidOf(without(evidence.compatibility_approval, 'run_scope_approval_cid'));
  const resolution = JSON.parse(answer.resolutionWire);
  resolution.approval_evidence_cid = cidOf(evidence);
  resolution.proof.signature = sign(null, Buffer.from(cidOf(without(resolution, 'proof', 'resolution_cid')), 'utf8'), reviewer).toString('base64');
  resolution.resolution_cid = cidOf(without(resolution, 'resolution_cid'));
  await assert.rejects(journal.submitResolution({...answer, resolutionWire: canonical(resolution),
    approvalEvidenceWire: canonical(evidence)}),
  error => error.code === 'ResolutionAuthenticationFailed' && error.cause?.message === 'InvalidApprovalSignature');
  assert.deepEqual(counts, {resolution: 1, approval: 0, attestation: 0});
  unchanged(journal);
});

for (const field of ['reviewProjectionCid', 'preparedInvocationCid']) {
  test(`correctly signed foreign ${field} is rejected by compiled original binding`, async t => {
    const {journal, summary, counts} = setup(t);
    const answer = await signedAnswer({...summary, [field]: cidOf({foreign: field})}, 'approved', signer, decidedAt);
    await assert.rejects(journal.submitResolution(answer), {code: 'InvalidResolution'});
    assert.deepEqual(counts, {resolution: 1, approval: 1, attestation: 0});
    unchanged(journal);
  });
}

const scopeIdentityKeys = ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'checkpointCid',
  'scopeCid', 'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision'];
const entryIdentityKeys = [...scopeIdentityKeys, 'ordinal', 'slotCid', 'attemptIndex',
  'attemptCid', 'intentId', 'claimant', 'generation', 'resolutionCid'];
function attemptOriginals(localRequest, ordinal) {
  const slot = JSON.parse(localRequest.slotWires[ordinal]);
  const authority = JSON.parse(fixture.authorityWire);
  authority.model_task_cid = slot.model_task_cid;
  authority.fixed_request_cid = slot.fixed_request_cid;
  authority.resource = slot.model_task_cid;
  authority.self_cid = cidOf(without(authority, 'self_cid'));
  const attempt = JSON.parse(fixture.attemptWire);
  attempt.slot_cid = slot.model_call_slot_cid;
  attempt.model_task_cid = slot.model_task_cid;
  attempt.fixed_request_cid = slot.fixed_request_cid;
  attempt.authority_evidence_cid = authority.self_cid;
  attempt.self_cid = cidOf(without(attempt, 'self_cid'));
  return {ordinal, slotCid: slot.model_call_slot_cid, attemptIndex: 1,
    attemptCid: attempt.self_cid, attemptWire: canonical(attempt), authorityWire: canonical(authority)};
}
for (const variant of [
  {name: 'review', expiresAt: '2026-09-26T13:00:00.000Z'},
  {name: 'Run', expiresAt: '2026-09-26T14:00:00.000Z', reviewExpiresAt: '2026-09-26T15:00:00.000Z'},
]) {
  test(`real ${variant.name} expiry fences an unsent call while its signed approval remains current`, async t => {
    const f = setup(t, {checkpointExpiresAt: '2026-09-26T16:00:00.000Z', reviewExpiresAt: variant.reviewExpiresAt});
    const answer = await signedAnswer(f.summary, 'approved', signer, decidedAt);
    const committed = await f.journal.submitResolution(answer);
    f.clock.value = Date.parse(variant.expiresAt) - 1;
    const grant = admitted(runtime.modelInvocationGrantAt(canonical(f.request), f.request.checkpointWire,
      committed.verifiedResolutionWire, new Date(f.clock.value).toISOString()));
    assert.equal(grant.expiresAt, variant.expiresAt);
    const claimed = f.journal.claimResume(f.inventory.runId, {claimant: 'expiry-diagnostic', leaseMs: 1000, binding});
    assert.equal(claimed.action, 'claimed');
    const first = f.journal.enterResumedCall(claimed.claim, {...f.inventory,
      resolutionCid: committed.resolutionCid, ...attemptOriginals(f.request, 0)});
    assert.equal(first.modelGrantExpiresAt, variant.expiresAt);
    assert.equal(first.admission.modelGrantExpiresAt, variant.expiresAt);
    assert.equal(f.journal.admitResume(claimed.claim, {checkpointCid: f.inventory.checkpointCid}).modelGrantExpiresAt, variant.expiresAt);
    const next = attemptOriginals(f.request, 1);
    admitted(runtime.modelCallAttemptAdmit(canonical(f.request), 1, next.attemptWire, next.authorityWire, 1));
    f.clock.value++;
    assert.equal(f.journal.committedApprovalAt(f.inventory.checkpointCid).current, true);
    assert.throws(() => f.journal.admitResume(claimed.claim, {checkpointCid: f.inventory.checkpointCid}),
      {code: 'ModelInvocationGrantRejected'});
    assert.throws(() => f.journal.enterResumedCall(claimed.claim, {...f.inventory,
      resolutionCid: committed.resolutionCid, ...next}), {code: 'ModelInvocationGrantRejected'});
    assert.deepEqual(f.journal.readResumeCalls(f.inventory).slots.map(slot => [slot.state, slot.attempts.length]),
      [['EnteredUnknown', 1], ['Unsent', 0]]);
    // The physical Store remains a declared double. Its already-entered exact
    // observation is allowed after live grant expiry, without provider re-entry.
    f.settlements.set(first.attemptCid, {entry: Object.fromEntries(entryIdentityKeys.map(key => [key, first[key]])),
      state: 'SavedSuccess', durable: true, retryAllowed: false,
      evidence: {testOnly: true, enteredAttemptCid: first.attemptCid}});
    assert.equal((await f.journal.observeResumedCall(first)).state, 'SavedSuccess');
    assert.deepEqual(f.journal.readResumeCalls(f.inventory).slots.map(slot => slot.state), ['SavedSuccess', 'Unsent']);
  });
}

test('real immediate Model grant rechecks review expiry after asynchronous Host attestation', async t => {
  const clock = {value: now};
  const f = setup(t, {clock, checkpointExpiresAt: '2026-09-26T16:00:00.000Z',
    onAttest: () => {clock.value = Date.parse('2026-09-26T13:00:00.000Z');}});
  const answer = await signedAnswer(f.summary, 'approved', signer, decidedAt);
  await assert.rejects(f.journal.admitImmediateResolution({body: without(JSON.parse(f.request.checkpointWire), 'checkpoint_cid'),
    authorities: [{keyId: signer.keyId, reviewerId: signer.reviewerId}],
    modelCallSet: f.request, ...answer}), {code: 'ModelInvocationGrantRejected'});
  assert.deepEqual(f.counts, {resolution: 1, approval: 1, attestation: 1});
  assert.deepEqual(f.journal.readResumeCalls(f.inventory).slots.map(slot => slot.state), ['Unsent', 'Unsent']);
});


test('compiled stopped proof distinguishes terminal contract violations from unknown attempts', () => {
  const original = attemptOriginals(request, 0);
  const seal = body => canonical({...body, self_cid: cidOf(body)});
  const accounting = {version: 'actql-model-attempt-accounting/0.1',
    attempt_cid: original.attemptCid, slot_cid: original.slotCid,
    cumulative_work: 23, uncertain_wire_bytes: 66536,
    input_tokens: 1, output_tokens: 1000, cost_units: null, duration_ms: null};
  const outcome = {version: 'actql-model-attempt-outcome/0.1',
    attempt_cid: original.attemptCid, slot_cid: original.slotCid,
    category: 'contract_violation', failure: 'budget_exceeded'};
  const check = (cost = seal(accounting), result = seal(outcome), attempt = original.attemptWire) =>
    JSON.parse(runtime.modelStoppedCallAdmit(canonical(request), 0, attempt,
      original.authorityWire, cost, result));
  const accepted = check();
  assert.equal(accepted.ok, true, JSON.stringify(accepted));
  assert.equal(accepted.state, 'SavedFailure');
  assert.equal(accepted.attemptCid, original.attemptCid);
  assert.equal(accepted.captureCid, undefined);
  for (const category of ['cancelled', 'result_unknown', 'provider_failure', 'ok']) {
    assert.equal(check(seal(accounting), seal({...outcome, category})).ok, false);
  }
  assert.equal(check('', seal(outcome)).ok, false);
  assert.equal(check(seal(accounting), '').ok, false);
  assert.equal(check(seal({...accounting, slot_cid: `sha256:${'f'.repeat(64)}`})).ok, false);
  assert.equal(check(seal(accounting), seal({...outcome, attempt_cid: `sha256:${'f'.repeat(64)}`})).ok, false);
  assert.equal(check(seal(accounting), seal({...outcome, failure: 'result_unknown'})).ok, false);
});
