import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createPrivateKey, sign} from 'node:crypto';
import {signedAnswer, canonicalJson, contentCid, reviewBytesMatchCid} from './checkpoints.mjs';
import {validCheckpointPage} from '../client-wire/index.mjs';

const fixture = JSON.parse(readFileSync(new URL(
  '../../portability/corpus/model-invocation-scope.json', import.meta.url), 'utf8'));
const key = createPrivateKey({format: 'der', type: 'pkcs8', key: Buffer.concat([
  Buffer.from('302e020100300506032b657004220420', 'hex'),
  Buffer.from(Array.from({length: 32}, (_, index) => index))])});
const signer = {keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
  sign: bytes => sign(null, bytes, key)};
const without = (value, name) => Object.fromEntries(
  Object.entries(value).filter(([key]) => key !== name));
const page = summary => validCheckpointPage({items: [summary]}, 1);

test('Model summary is a closed, Run-only public wire variant', () => {
  assert.equal(page(fixture.summary), true);
  for (const value of [
    without(fixture.summary, 'preparedInvocationCid'),
    {...fixture.summary, preparedInvocationCid: 'not-a-cid'},
    {...fixture.summary, phase: 'commit'},
    {...fixture.summary, kind: 'read_access'},
    {...fixture.summary, subject: {kind: 'prepare_attempt', prepareAttemptId: 'p', requestId: 'r'}},
    {...fixture.summary, requiredArtifact: {...fixture.summary.requiredArtifact, type: 'prepared_invocation'}},
    {...fixture.summary, requirements: ['effect_scope_approved']},
    {...fixture.summary, unreviewedProvider: 'models/another'},
  ]) assert.equal(page(value), false);
});

test('SDK signed Model approval equals the independent fixed CID and Ed25519 wires', async () => {
  const answer = await signedAnswer(fixture.summary, 'approved', signer, fixture.decided_at);
  assert.equal(answer.resolutionWire, fixture.expected_resolution_wire);
  assert.equal(answer.approvalEvidenceWire, fixture.expected_approval_evidence_wire);
  const resolution = JSON.parse(answer.resolutionWire);
  const evidence = JSON.parse(answer.approvalEvidenceWire);
  assert.equal(resolution.required_artifact_cid, fixture.summary.requiredArtifact.cid);
  assert.equal(evidence.compatibility_approval.prepared_invocation_cid,
    fixture.summary.preparedInvocationCid);
  assert.notEqual(resolution.required_artifact_cid,
    evidence.compatibility_approval.prepared_invocation_cid);
});

test('Model rejection carries exact Run/scope and no compatibility approval', async () => {
  const answer = await signedAnswer(fixture.summary, 'rejected', signer, fixture.decided_at);
  const body = JSON.parse(answer.resolutionWire);
  assert.equal(answer.approvalEvidenceWire, '');
  assert.equal(body.run_id, fixture.summary.subject.runId);
  assert.equal(body.run_definition_cid, fixture.summary.subject.runDefinitionCid);
  assert.equal(body.required_artifact_cid, fixture.summary.requiredArtifact.cid);
  assert.equal(body.prepare_attempt_id, undefined);
  assert.equal(body.approval_evidence_cid, undefined);
});

test('SDK refuses missing original, unsupported phase, subject and claims before signing', async () => {
  let calls = 0;
  const observer = {...signer, sign(bytes) { calls++; return signer.sign(bytes); }};
  for (const summary of [
    without(fixture.summary, 'preparedInvocationCid'),
    {...fixture.summary, phase: 'commit'},
    {...fixture.summary, subject: {kind: 'prepare_attempt'}},
    {...fixture.summary, requirements: []},
    {...fixture.summary, requirements: ['invocation_scope_approved', 'effect_scope_approved']},
    {...fixture.summary, kind: 'cost_scope'},
  ]) await assert.rejects(signedAnswer(summary, 'approved', observer, fixture.decided_at),
    {message: 'UnsupportedCheckpointAnswer'});
  assert.equal(calls, 0);
});

test('async signing owns the original Model scope metadata', async () => {
  const summary = structuredClone(fixture.summary);
  let first = true;
  const mutatingSigner = {...signer, sign(bytes) {
    if (first) {
      first = false;
      summary.preparedInvocationCid = summary.requiredArtifact.cid;
      summary.subject.runId = 'another-run';
    }
    return signer.sign(bytes);
  }};
  const answer = await signedAnswer(summary, 'approved', mutatingSigner, fixture.decided_at);
  assert.equal(answer.resolutionWire, fixture.expected_resolution_wire);
  assert.equal(answer.approvalEvidenceWire, fixture.expected_approval_evidence_wire);
});

test('integrated acquired Source read still signs its Run-bound approval and rejection', async () => {
  const summary = without({...fixture.summary, kind: 'read_access',
    requiredArtifact: {...fixture.summary.requiredArtifact, type: 'read_scope'}},
  'preparedInvocationCid');
  for (const decision of ['approved', 'rejected']) {
    const answer = await signedAnswer(summary, decision, signer, fixture.decided_at);
    const resolution = JSON.parse(answer.resolutionWire);
    assert.equal(resolution.run_id, summary.subject.runId);
    assert.equal(resolution.run_definition_cid, summary.subject.runDefinitionCid);
    assert.equal(resolution.prepare_attempt_id, undefined);
    assert.equal(resolution.required_artifact_cid, summary.requiredArtifact.cid);
    if (decision === 'approved') {
      const evidence = JSON.parse(answer.approvalEvidenceWire);
      assert.equal(evidence.kind, 'read_access');
      assert.equal(evidence.compatibility_approval.prepared_invocation_cid,
        summary.requiredArtifact.cid);
    } else assert.equal(answer.approvalEvidenceWire, '');
  }
});


test('SDK verifies canonical Model review identity without confusing its storage digest', async () => {
  const review = fixture.cases.find(value => value.kind === 'run_review_projection');
  assert.ok(review);
  const wire = canonicalJson(review.artifact);
  const bytes = value => new TextEncoder().encode(value);
  assert.equal(await reviewBytesMatchCid(bytes(wire), review.expected_cid), true);
  assert.notEqual(await contentCid(review.artifact), review.expected_cid);
  for (const changed of [
    ` ${wire}`, wire.replace('"version":', '"version":"other","version":'),
    canonicalJson({...review.artifact, review_projection_cid: `sha256:${'0'.repeat(64)}`}),
    canonicalJson({...review.artifact, approval_claims: []}),
    canonicalJson({...review.artifact, version: 'actql-run-review-projection/other'}),
  ]) assert.equal(await reviewBytesMatchCid(bytes(changed), review.expected_cid), false);
  assert.equal(await reviewBytesMatchCid(Uint8Array.of(255), review.expected_cid), false);
  const legacy = {summary: 'legacy review'};
  assert.equal(await reviewBytesMatchCid(bytes(canonicalJson(legacy)), await contentCid(legacy)), true);
});
