import assert from 'node:assert/strict';
import {mkdtemp, rm, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createCaptureSink} from './capture-sink.mjs';
import {contentCid, referenceCid} from './evidence-reference.mjs';
import {runEvaluatorProcess} from './evaluator-process.mjs';

const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
const subject = {runDefinitionCid: referenceCid('original-run'), authorityScopeCid: referenceCid('current-scope')};
const attemptCid = referenceCid('original-model-attempt');
const task = referenceCid('task'), slot = referenceCid('slot'), request = referenceCid('request');
const value = {reason: null, risk: 'high'};
const outputCid = contentCid(JSON.stringify(value));
const evidence = {version: 'actql-model-invocation-evidence/0.1', model_task_contract_cid: task,
  model_call_slot_cid: slot, semantic_request_cid: request, validated_structured_output_cid: outputCid};
const body = {barrier_receipts: [], captures: [{evidence, model_call_slot_cid: slot,
  semantic_request_cid: request, structured_response: value}], version: 'actql-model-capture-bundle/0.1'};
const bundleCid = referenceCid(body);
const original = {captureBundleCid: bundleCid, modelCallSlotCid: slot,
  semanticRequestCid: request, modelTaskCid: task};
const wires = {typedInput: JSON.stringify({model_task_contract_cid: task,
    model_call_slot_cid: slot, semantic_request_cid: request,
    input_contract: {type: 'object'}, output_contract: {type: 'object'}, key: ['a'], inputs: {text: 'URGENT'}}),
  typedOutput: JSON.stringify({outcome: 'ok', value, validatedOutputCid: outputCid}),
  renderedInput: JSON.stringify({instructions: 'Keep é/é and \r\n unchanged', text: 'URGENT'}),
  contextManifest: JSON.stringify({selectedFields: ['text'], retrievalPolicy: 'none', providerHiddenContext: 'unknown'}),
  validation: JSON.stringify({outcome: 'accepted', evidence, captureBundleWire: JSON.stringify({...body, bundle_cid: bundleCid})})};

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-o3-capture-test-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  let allowed = true, external = true, at = Date.now();
  const calls = [];
  const sink = await createCaptureSink({directory, destination: 'local:independent-evaluator',
    maxBytes: 4096, maxPendingBytes: 1048576, retentionMs: 10000, now: () => at,
    authorize(facts) {calls.push(facts); return allowed && (facts.purpose !== 'external_evaluation' || external);}});
  const capture = await sink.capture({subject, attemptCid, original,
    policy: {kind: 'data_policy', cid: contentCid(policyWire), wire: policyWire}, wires});
  assert.equal(capture.status, 'complete');
  const request = {subject, attemptCid, references: capture.references};
  return {directory, sink, capture, request, calls,
    denyRead() {allowed = false;}, denySend() {external = false;}, expire() {at += 10000;}};
}

test('unknown provenance remains capture metadata and an independent evaluator process scores complete copies', async t => {
  const f = await fixture(t);
  assert.equal(f.capture.references.typedOutput.kind, 'model_capture');
  assert.equal(JSON.parse(f.capture.references.typedOutput.policy.wire).unknown_provenance, true);
  let pid;
  const result = await f.sink.withEvaluatorEvidence(f.request, async resolvedEvidence => {
    assert.equal(Buffer.from(resolvedEvidence.renderedInput.base64, 'base64').toString(), wires.renderedInput);
    assert(f.sink.pendingBytes() > 0);
    return runEvaluatorProcess({job: {caseId: 'held-out', expected: 'high', role: 'final_test',
      subject, evidence: {...f.capture, attemptCid}}, resolvedEvidence, deadline: Date.now() + 10000,
      onProcess(value) {pid = value;}});
  });
  assert.notEqual(pid, process.pid);
  assert(Number.isInteger(pid));
  assert.equal(result.score, 1);
  assert.equal(f.sink.pendingBytes(), 0);
});

for (const [name, change, code] of [
  ['current read authority revoked', f => f.denyRead(), 'EvidenceReadDenied'],
  ['expired original', f => f.expire(), 'EvidenceExpired'],
  ['other Run reference reuse', f => {f.request = {...f.request, subject: {...subject, runDefinitionCid: referenceCid('other-run')}};}, 'EvidenceSubjectMismatch'],
  ['other attempt reference reuse', f => {f.request = {...f.request, attemptCid: referenceCid('other-attempt')};}, 'EvidenceSubjectMismatch'],
  ['external destination not permitted by read grant', f => f.denySend(), 'EvidenceExternalSendDenied'],
  ['original removed from sink', async f => unlink(join(f.directory, f.capture.references.typedInput.evidenceRefCid.slice(7))), 'EvidenceOriginalMissing'],
]) {
  test(name, async t => {
    const f = await fixture(t);
    await change(f);
    await assert.rejects(f.sink.withEvaluatorEvidence(f.request, () => assert.fail('denied evidence cannot be sent')), {code});
    assert.equal(f.sink.pendingBytes(), 0);
    // No execution/provider port exists in this resolver. Public acceptance
    // additionally observes the original Run and physical call counts.
  });
}

test('incomplete evidence is rejected before spawning the evaluator and cannot become zero', async t => {
  const f = await fixture(t);
  let started = 0;
  await f.sink.withEvaluatorEvidence(f.request, async copies => {
    delete copies.validation;
    await assert.rejects(runEvaluatorProcess({job: {subject, evidence: {...f.capture, attemptCid}},
      resolvedEvidence: copies, deadline: Date.now() + 10000, onProcess() {started++;}}), {code: 'RequiredEvidenceUnavailable'});
  });
  assert.equal(started, 0);
});

test('retained sink quota survives reopen and immutable captures are not overwritten', async t => {
  const f = await fixture(t);
  const bytes = f.sink.retainedBytes();
  assert(bytes > 0);
  const reopened = await createCaptureSink({directory: f.directory, destination: 'local:independent-evaluator',
    maxBytes: 4096, maxPendingBytes: 1048576, maxRetainedBytes: bytes + 100,
    retentionMs: 10000, authorize: () => true});
  assert.equal(reopened.retainedBytes(), bytes);
  const denied = await reopened.capture({subject, attemptCid: referenceCid('new-attempt'), original,
    policy: {kind: 'data_policy', cid: contentCid(policyWire), wire: policyWire}, wires});
  assert.equal(denied.status, 'incomplete');
  assert.equal(denied.reason, 'EvaluationBudgetExceeded');
  assert.equal(reopened.retainedBytes(), bytes);
  assert.equal(reopened.pendingBytes(), 0);
  assert.equal(reopened.cleanupPending(), false);
  // The previous permitted original still has its exact read identity.
  await f.sink.withEvaluatorEvidence(f.request, copies => {
    assert.equal(Buffer.from(copies.typedOutput.base64, 'base64').toString(), wires.typedOutput);
  });
});

test('altered captured output cannot be scored as the original common response', async t => {
  const f = await fixture(t);
  await f.sink.withEvaluatorEvidence(f.request, async copies => {
    const changed = JSON.stringify({outcome: 'ok', value: {reason: null, risk: 'low'}, validatedOutputCid: outputCid});
    // A permitted user-owned copy has its own hash, but must still agree with
    // the common validation original before this rubric may score it.
    const {evidenceRefCid, ...body} = f.capture.references.typedOutput;
    const nextBody = {...body, content: {...body.content, cid: contentCid(changed), sizeBytes: Buffer.byteLength(changed)}};
    const changedRef = {...nextBody, evidenceRefCid: referenceCid(nextBody)};
    const references = {...f.capture.references, typedOutput: changedRef};
    const resolved = {...copies, typedOutput: {refCid: changedRef.evidenceRefCid, base64: Buffer.from(changed).toString('base64')}};
    await assert.rejects(runEvaluatorProcess({job: {caseId: 'altered-output', expected: 'high', role: 'selection',
      subject, evidence: {...f.capture, references, attemptCid}}, resolvedEvidence: resolved,
      deadline: Date.now() + 10000}), {code: 'RequiredEvidenceUnavailable'});
  });
});
