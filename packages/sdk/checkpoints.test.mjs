import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {createPrivateKey, generateKeyPairSync, sign, verify} from
  'node:crypto';
import {readFileSync} from 'node:fs';
import {connect, ClientError, RequestHeld, getSubmissionInput} from './index.mjs';
import {canonicalJson, contentCid, signedAnswer} from './checkpoints.mjs';

const vectors = JSON.parse(readFileSync(new URL(
  '../../portability/corpus/checkpoint-resolution-signatures.json',
  import.meta.url), 'utf8'));
const cid = digit => `sha256:${digit.repeat(64)}`;
const profile = Object.freeze({version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'scope-a', capabilities: ['result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}});
const options = {mode: 'remote', endpoint: 'https://host.example/',
  token: 'scoped-token'};
const summary = Object.freeze({checkpointId: 'prepare-a-preparation',
  checkpointCid: cid('c'), kind: 'run_scope', phase: 'preflight',
  subject: {kind: 'prepare_attempt', prepareAttemptId: 'prepare-a',
    requestId: 'saved-a'},
  requiredArtifact: {type: 'prepared_invocation', cid: cid('d')},
  reviewProjectionCid: cid('e'),
  requirements: ['invocation_scope_approved'],
  createdAt: '2026-09-26T00:00:00.000Z',
  expiresAt: '2026-09-27T00:00:00.000Z', humanSummary: 'Run on site-a'});
const keys = generateKeyPairSync('ed25519');
const signer = Object.freeze({keyId: 'alice-key', reviewerId: 'alice',
  sign: bytes => sign(null, bytes, keys.privateKey)});
const without = (value, ...names) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !names.includes(key)));

function host(t, replies) {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    const body = JSON.parse(init.body);
    requests.push({operation, body, authorization:
      init.headers.authorization});
    if (operation === 'connect') return Response.json(profile);
    return replies[operation](body);
  });
  t.after(() => mock.restoreAll());
  return requests;
}

test('Client canonical CIDs and signatures follow the pinned vectors',
  async () => {
    const seed = Buffer.from(Array.from({length: 32}, (_, index) => index));
    const reviewer = createPrivateKey({key: Buffer.concat([
      Buffer.from('302e020100300506032b657004220420', 'hex'), seed]),
    format: 'der', type: 'pkcs8'});
    const resolutions = vectors.cases.filter(vector =>
      vector.kind === 'checkpoint_resolution');
    assert.ok(resolutions.length > 0);
    for (const vector of resolutions) {
      const {artifact} = vector;
      const selfField = 'resolution_cid';
      const unsigned = without(artifact, 'proof', selfField);
      const text = await contentCid(unsigned);
      assert.equal(sign(null, Buffer.from(text, 'utf8'), reviewer)
        .toString('base64'), artifact.proof.signature, vector.id);
      assert.equal(await contentCid(without(artifact, selfField)),
        artifact[selfField], vector.id);
    }
    assert.equal(canonicalJson({b: 'é', a: [1, true, null]}),
      '{"a":[1,true,null],"b":"é"}');
  });

test('a signed answer binds this Checkpoint and verifies with the reviewer key',
  async () => {
    const approved = await signedAnswer(summary, 'approved', signer,
      '2026-09-26T01:00:00.000Z');
    const body = JSON.parse(approved.resolutionWire);
    const evidence = JSON.parse(approved.approvalEvidenceWire);
    assert.equal(approved.checkpointCid, summary.checkpointCid);
    assert.equal(body.checkpoint_cid, summary.checkpointCid);
    assert.equal(body.prepare_attempt_id, 'prepare-a');
    assert.equal(body.actor, 'alice');
    assert.equal(body.approval_evidence_cid, await contentCid(evidence));
    assert.equal(evidence.checkpoint_cid, summary.checkpointCid);
    assert.equal(evidence.compatibility_approval.prepared_invocation_cid,
      summary.requiredArtifact.cid);
    const unsigned = await contentCid(without(body, 'proof',
      'resolution_cid'));
    assert.equal(verify(null, Buffer.from(unsigned, 'utf8'), keys.publicKey,
      Buffer.from(body.proof.signature, 'base64')), true);
    const approval = evidence.compatibility_approval;
    assert.equal(verify(null, Buffer.from(await contentCid(without(approval,
      'proof', 'run_scope_approval_cid')), 'utf8'), keys.publicKey,
    Buffer.from(approval.proof.signature, 'base64')), true);
    // No key, credential or signer material is in the answer.
    assert.equal(/PRIVATE|scoped-token/u.test(approved.resolutionWire +
      approved.approvalEvidenceWire), false);
    const rejected = await signedAnswer(summary, 'rejected', signer,
      '2026-09-26T01:00:00.000Z');
    assert.equal(rejected.approvalEvidenceWire, '');
    await assert.rejects(signedAnswer({...summary, kind: 'effect_set'},
      'approved', signer, 'x'), {message: 'UnsupportedCheckpointAnswer'});
    // A held source read of a request before its Run is answered the same way.
    const read = await signedAnswer({...summary, kind: 'read_access',
      requiredArtifact: {type: 'read_scope', cid: cid('7')}}, 'approved',
    signer, '2026-09-26T01:00:00.000Z');
    assert.equal(JSON.parse(read.approvalEvidenceWire).kind, 'read_access');
    assert.equal(JSON.parse(read.resolutionWire).required_artifact_cid,
      cid('7'));
    await assert.rejects(signedAnswer(summary, 'maybe', signer, 'x'),
      {message: 'InvalidCheckpointDecision'});
  });

test('a held submit is a control result, not a failure or unknown submission',
  async t => {
    const held = {kind: 'held', requestId: 'saved-a',
      prepareAttemptId: 'prepare-a', state: 'waiting_checkpoint',
      durability: 'durable', lookupExpiresAt: '2026-10-03T00:00:00.000Z',
      checkpoint: {checkpointId: summary.checkpointId,
        checkpointCid: summary.checkpointCid, kind: 'run_scope',
        expiresAt: summary.expiresAt}};
    const requests = host(t, {
      submit: () => Response.json(held),
      'lookup-request': () => Response.json(held),
    });
    const client = await connect(options);
    let error;
    try { await client.aql('version: actql/0.1\n', {format: 'yaml',
      requestId: 'saved-a'}); }
    catch (cause) { error = cause; }
    assert.equal(error instanceof RequestHeld, true);
    assert.equal(error instanceof ClientError, true);
    assert.equal(error.code, 'RequestHeld');
    assert.equal(error.requestId, 'saved-a');
    assert.equal(error.held.checkpoint.checkpointCid, summary.checkpointCid);
    assert.equal('ref' in error.held, false);
    assert.deepEqual(getSubmissionInput(error).input,
      {text: 'version: actql/0.1\n', format: 'yaml'});
    assert.equal(getSubmissionInput(error).requestId, 'saved-a');
    assert.equal(getSubmissionInput(error).lookupContext.scopeRef, 'scope-a');
    assert.equal(Object.isFrozen(getSubmissionInput(error)), true);
    assert.deepEqual(await client.lookupRequest('saved-a'), held);
    // A held reply for another request is not accepted as held.
    mock.restoreAll();
    host(t, {submit: () => Response.json({...held, requestId: 'saved-b'})});
    const other = await connect(options);
    await assert.rejects(other.aql('version: actql/0.1\n', {format: 'yaml',
      requestId: 'saved-a'}), {code: 'SubmissionUnknown'});
    assert.equal(requests.filter(item => item.operation === 'submit').length,
      1);
  });

const effectSummary = () => ({...summary, kind: 'effect_set', phase: 'commit',
  subject: {kind: 'run_unit', runId: 'run-a', runDefinitionCid: cid('1')},
  requiredArtifact: {type: 'effect_set_preview', cid: cid('2')},
  requirements: ['effect_scope_approved']});

test('Effect answers bind the Run, full Preview and exact authority scope',
  async () => {
    for (const requirements of [['effect_scope_approved'],
      ['effect_scope_approved', 'partial_application_accepted']]) {
      const checkpoint = {...effectSummary(), requirements};
      const answer = await signedAnswer(checkpoint, 'approved',
        {...signer, authorityScopeCid: cid('3')}, summary.createdAt);
      const resolution = JSON.parse(answer.resolutionWire);
      const evidence = JSON.parse(answer.approvalEvidenceWire);
      const approval = evidence.compatibility_approval;
      assert.equal(resolution.run_id, 'run-a');
      assert.equal(resolution.run_definition_cid, cid('1'));
      assert.equal('prepare_attempt_id' in resolution, false);
      assert.equal(approval.version, 'actql-approval-attestation/0.1');
      assert.equal(approval.effect_preview_cid, cid('2'));
      assert.equal(approval.authority_scope_cid, cid('3'));
      assert.deepEqual(approval.claims, requirements);
      assert.equal(approval.attestation_cid,
        await contentCid(without(approval, 'attestation_cid')));
      assert.equal(verify(null, Buffer.from(await contentCid(without(approval,
        'proof', 'attestation_cid'))), keys.publicKey,
      Buffer.from(approval.proof.signature, 'base64')), true);
      assert.equal(resolution.approval_evidence_cid, await contentCid(evidence));
    }
    await assert.rejects(signedAnswer(effectSummary(), 'approved', signer,
      summary.createdAt), {message: 'EffectApprovalAuthorityScopeRequired'});
    await assert.rejects(signedAnswer({...effectSummary(),
      requirements: ['invocation_scope_approved']}, 'approved',
    {...signer, authorityScopeCid: cid('3')}, summary.createdAt),
    {message: 'UnsupportedEffectApprovalClaims'});
    const rejected = await signedAnswer(effectSummary(), 'rejected', signer,
      summary.createdAt);
    assert.equal(rejected.approvalEvidenceWire, '');
    assert.equal(JSON.parse(rejected.resolutionWire).run_id, 'run-a');
  });

test('a pending signer cannot change the reviewed Effect binding', async () => {
  const checkpoint = effectSummary();
  const mutableSigner = {...signer, authorityScopeCid: cid('3')};
  mutableSigner.sign = bytes => {
    checkpoint.subject.runId = 'foreign-run';
    checkpoint.requiredArtifact.cid = cid('9');
    checkpoint.requirements.push('partial_application_accepted');
    mutableSigner.reviewerId = 'foreign-reviewer';
    mutableSigner.authorityScopeCid = cid('8');
    return signer.sign(bytes);
  };
  const answer = await signedAnswer(checkpoint, 'approved', mutableSigner,
    summary.createdAt);
  const resolution = JSON.parse(answer.resolutionWire);
  const approval = JSON.parse(answer.approvalEvidenceWire)
    .compatibility_approval;
  assert.equal(resolution.run_id, 'run-a');
  assert.equal(resolution.required_artifact_cid, cid('2'));
  assert.equal(resolution.actor, 'alice');
  assert.equal(approval.authority_scope_cid, cid('3'));
  assert.deepEqual(approval.claims, ['effect_scope_approved']);
});

test('listing and review are bounded and the review bytes are verified',
  async t => {
    const content = Buffer.from(canonicalJson({displayed_scope: {site:
      'site-a'}}), 'utf8');
    const artifactCid = await contentCid({displayed_scope: {site: 'site-a'}});
    let reply = () => Response.json({kind: 'review',
      checkpointCid: summary.checkpointCid, artifactCid,
      byteLength: content.byteLength,
      contentBase64: content.toString('base64')});
    const requests = host(t, {
      checkpoints: () => Response.json({items: [summary], next: 'x|y'}),
      'checkpoint-review': body => reply(body),
    });
    const client = await connect(options);
    const page = await client.checkpoints({limit: 5});
    assert.deepEqual(page.items, [summary]);
    assert.equal(page.next, 'x|y');
    assert.deepEqual(requests.at(-1).body.after, '');
    await assert.rejects(client.checkpoints({limit: 101}),
      {code: 'InvalidCheckpointPage'});
    const review = await client.reviewCheckpoint(
      {...summary, reviewProjectionCid: artifactCid}, {maxBytes: 1024});
    assert.equal(Buffer.from(review.bytes).equals(content), true);
    assert.equal(requests.at(-1).body.maxBytes, 1024);
    // Bytes that do not match the named artifact are refused.
    reply = () => Response.json({kind: 'review',
      checkpointCid: summary.checkpointCid, artifactCid: cid('9'),
      byteLength: content.byteLength,
      contentBase64: content.toString('base64')});
    await assert.rejects(client.reviewCheckpoint(summary.checkpointCid,
      {maxBytes: 1024}), {code: 'ReviewIntegrityFailed'});
    // A review larger than asked is refused, never truncated.
    reply = () => Response.json({kind: 'review',
      checkpointCid: summary.checkpointCid, artifactCid,
      byteLength: content.byteLength,
      contentBase64: content.toString('base64')});
    await assert.rejects(client.reviewCheckpoint(summary.checkpointCid,
      {maxBytes: 4}), {code: 'InvalidHostCheckpointReview'});
    reply = () => new Response(JSON.stringify(
      {code: 'CheckpointReviewDenied'}), {status: 403});
    await assert.rejects(client.reviewCheckpoint(summary.checkpointCid),
      {code: 'CheckpointReviewDenied'});
  });

test('answers are per item and a lost reply returns the exact signed items',
  async t => {
    const second = {...summary, checkpointId: 'prepare-b-preparation',
      checkpointCid: cid('f'), subject: {...summary.subject,
        prepareAttemptId: 'prepare-b', requestId: 'saved-b'}};
    let reply = body => Response.json({results: [
      {checkpointCid: body.items[0].checkpointCid, status: 'committed',
        decision: 'approved', resolutionCid: cid('1')},
      {checkpointCid: body.items[1].checkpointCid, status: 'conflicting',
        reason: 'CheckpointResolutionConflict'}]});
    const requests = host(t, {resolve: body => reply(body)});
    const client = await connect(options);
    const answered = await client.resolveCheckpoints([
      {checkpoint: summary, decision: 'approved'},
      {checkpoint: second, decision: 'rejected'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed', 'conflicting']);
    assert.equal(answered.signed.length, 2);
    // Transport loss: the error carries the same signed answers, and a
    // resend presents them unchanged (no new decision time or signature).
    reply = () => { throw new TypeError('connection reset'); };
    mock.restoreAll();
    const resent = host(t, {resolve: body => reply(body)});
    const retrying = await connect(options);
    let lost;
    try { await retrying.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer}); }
    catch (cause) { lost = cause; }
    assert.equal(lost.code, 'ResolutionUnknown');
    assert.equal(lost.signed.length, 1);
    reply = body => Response.json({results: [{checkpointCid:
      body.items[0].checkpointCid, status: 'duplicate', decision: 'approved',
    resolutionCid: cid('1')}]});
    const again = await retrying.resolveCheckpoints(lost.signed);
    assert.equal(again.results[0].status, 'duplicate');
    const sent = resent.filter(item => item.operation === 'resolve');
    assert.deepEqual(sent.at(-1).body.items, [...lost.signed]);
    // A Host 5xx is also unknown; a Host refusal is not.
    reply = () => new Response(JSON.stringify({code: 'ClientHostFailure'}),
      {status: 500});
    await assert.rejects(retrying.resolveCheckpoints(lost.signed),
      {code: 'ResolutionUnknown'});
    reply = () => new Response(JSON.stringify(
      {code: 'CheckpointAnswerDenied'}), {status: 403});
    await assert.rejects(retrying.resolveCheckpoints(lost.signed),
      {code: 'CheckpointAnswerDenied'});
    await assert.rejects(retrying.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}]), {code: 'InvalidCheckpointSigner'});
    assert.equal(requests.some(item =>
      JSON.stringify(item.body).includes('PRIVATE')), false);
  });

test('a request cancellation is typed and an unknown result is resent',
  async t => {
    let reply = body => Response.json({requestId: body.requestId,
      kind: 'accepted'});
    const requests = host(t, {'cancel-request': body => reply(body)});
    const client = await connect(options);
    assert.deepEqual(await client.cancelRequest('saved-a'),
      {requestId: 'saved-a', kind: 'accepted'});
    // Transport loss or a Host failure is unknown; the same ID is resent.
    reply = () => { throw new TypeError('connection reset'); };
    await assert.rejects(client.cancelRequest('saved-a'), error =>
      error.code === 'CancellationUnknown' && error.requestId === 'saved-a');
    reply = () => new Response(JSON.stringify({code: 'ClientHostFailure'}),
      {status: 500});
    await assert.rejects(client.cancelRequest('saved-a'),
      {code: 'CancellationUnknown'});
    // A refusal or a missing request stays a typed error, never a success.
    for (const [code, status] of [['ClientRequestNotFound', 404],
      ['ClientRequestCancellationDenied', 403]]) {
      reply = () => new Response(JSON.stringify({code}), {status});
      await assert.rejects(client.cancelRequest('saved-a'), {code});
    }
    // A reply for another request is not accepted.
    reply = () => Response.json({requestId: 'saved-b', kind: 'accepted'});
    await assert.rejects(client.cancelRequest('saved-a'),
      {code: 'CancellationUnknown'});
    assert.ok(requests.filter(item => item.operation === 'cancel-request')
      .every(item => item.body.requestId === 'saved-a'));
  });


test('Checkpoint canonical bytes retain data values and reject identifier collisions', async () => {
  const values = ['\r', '\n', '\r\n', 'é', 'e\u0301', '\\n'];
  const expected = ['"\\r"', '"\\n"', '"\\r\\n"', '"é"', '"e\u0301"', '"\\\\n"'];
  const identities = new Set();
  for (let index = 0; index < values.length; index++) {
    assert.equal(canonicalJson(values[index]), expected[index]);
    identities.add(await contentCid(values[index]));
  }
  assert.equal(identities.size, 6);
  assert.throws(() => canonicalJson({'é': 1, 'e\u0301': 2}), /CanonicalKeyCollision/);
  assert.equal(canonicalJson({'e\u0301\r': 1}), '{"é\\n":1}');
});
