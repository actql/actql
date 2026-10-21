// SDK protocol controls and explicit Local-port doubles, not physical signing.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import test from 'node:test';
import {connectInProcess, ClientError} from './index.mjs';
import {canonicalJson, contentCid, signedAnswer} from './checkpoints.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const keys = generateKeyPairSync('ed25519');
const original = Object.freeze({checkpointId: 'action-original', checkpointCid: cid('a'),
  kind: 'effect_set', phase: 'commit', subject: Object.freeze({kind: 'run_unit',
    runId: 'original-run', runDefinitionCid: cid('b')}),
  requiredArtifact: Object.freeze({type: 'effect_set_preview', cid: cid('c')}),
  reviewProjectionCid: cid('d'), requirements: Object.freeze(['effect_scope_approved']),
  createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z',
  humanSummary: 'Original selected Effect'});
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'reviewer', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const signer = {keyId: 'original-key', reviewerId: 'reviewer', authorityScopeCid: cid('e'),
  sign: bytes => sign(null, bytes, keys.privateKey)};
const committed = body => ({results: body.items.map(item => ({checkpointCid: item.checkpointCid,
  status: 'committed', decision: JSON.parse(item.resolutionWire).decision,
  resolutionCid: JSON.parse(item.resolutionWire).resolution_cid}))});

async function fixture(t, {lookup = () => ({items: [original]}), resolve = committed,
  answerCheckpoint, extra = {}} = {}) {
  const calls = [];
  const port = {async perform(operation, body) {
    calls.push({operation, body});
    if (operation === 'connect') return profile;
    if (operation === 'checkpoints') return lookup(body);
    if (operation === 'resolve') return resolve(body);
    assert.fail('unexpected operation: ' + operation);
  }, ...(answerCheckpoint === undefined ? {} : {answerCheckpoint}), ...extra};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  return {client, calls, port};
}

test('approve looks up one exact original ID and signs the same Summary and claims', async t => {
  const {client, calls} = await fixture(t);
  const answer = await client.approve(original.checkpointId, {signer});
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'checkpoints', 'resolve']);
  assert.deepEqual(calls[1].body, {connection: {mode: 'local', owner: 'local',
    consentRefs: [], runners: []}, after: '', limit: 1, checkpointId: original.checkpointId});
  const item = calls[2].body.items[0], resolution = JSON.parse(item.resolutionWire);
  const evidence = JSON.parse(item.approvalEvidenceWire).compatibility_approval;
  assert.equal(resolution.checkpoint_id, original.checkpointId);
  assert.equal(resolution.checkpoint_cid, original.checkpointCid);
  assert.equal(resolution.run_id, original.subject.runId);
  assert.equal(resolution.run_definition_cid, original.subject.runDefinitionCid);
  assert.equal(resolution.required_artifact_cid, original.requiredArtifact.cid);
  assert.equal(evidence.effect_preview_cid, original.requiredArtifact.cid);
  assert.equal(evidence.review_projection_cid, original.reviewProjectionCid);
  assert.equal(evidence.authority_scope_cid, signer.authorityScopeCid);
  assert.deepEqual(evidence.claims, original.requirements);
  assert.equal(answer.results[0].status, 'committed');
  assert.deepEqual(answer.signed, [item]);
});

test('reject uses the same exact lookup and carries no approval evidence', async t => {
  const {client, calls} = await fixture(t);
  const result = await client.reject(original.checkpointId, {signer});
  const item = calls.at(-1).body.items[0];
  assert.equal(JSON.parse(item.resolutionWire).decision, 'rejected');
  assert.equal(item.approvalEvidenceWire, '');
  assert.equal(result.results[0].decision, 'rejected');
});

test('missing signer, invalid IDs and already-aborted calls do no lookup or signature', async t => {
  let signatures = 0;
  const selected = {...signer, sign(bytes) {signatures++; return signer.sign(bytes);}};
  const {client, calls} = await fixture(t);
  await assert.rejects(client.approve(original.checkpointId), {code: 'CheckpointSignerUnavailable'});
  for (const id of [null, undefined, '', {}, 42]) {
    await assert.rejects(client.approve(id, {signer: selected}), {code: 'InvalidCheckpointReference'});
  }
  await assert.rejects(client.approve(original.checkpointId, {signer: {}}), {code: 'InvalidCheckpointSigner'});
  const controller = new AbortController(); controller.abort();
  await assert.rejects(client.approve(original.checkpointId, {signer: selected, signal: controller.signal}),
    {name: 'AbortError'});
  assert.equal(signatures, 0); assert.equal(calls.length, 1);
});

test('empty, foreign, paginated or duplicate lookup responses never reach signing', async t => {
  let signatures = 0;
  for (const page of [{items: []}, {items: [{...original, checkpointId: 'foreign'}]},
    {items: [original], next: 'another-page'}, {items: [original, original]}]) {
    const {client, calls} = await fixture(t, {lookup: () => page});
    await assert.rejects(client.approve(original.checkpointId, {signer: {...signer,
      sign(bytes) {signatures++; return signer.sign(bytes);}}}),
    {code: page.items.length === 0 ? 'CheckpointUnavailable' : 'InvalidHostCheckpointPage'});
    assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  }
  assert.equal(signatures, 0);
});

test('exact public Checkpoint lookup refuses mixed page selectors before I/O', async t => {
  const {client, calls} = await fixture(t);
  assert.deepEqual((await client.checkpoints({checkpointId: original.checkpointId})).items, [original]);
  for (const options of [{checkpointId: original.checkpointId, limit: 2},
    {checkpointId: original.checkpointId, after: 'cursor'}]) {
    await assert.rejects(client.checkpoints(options), {code: 'InvalidCheckpointReference'});
  }
  assert.equal(calls.filter(call => call.operation === 'checkpoints').length, 1);
});

test('Checkpoint page captures each original response field before admission', async t => {
  let reads = 0;
  const summary = {...original};
  Object.defineProperty(summary, 'checkpointId', {enumerable: true,
    get() { return ++reads === 1 ? original.checkpointId : 'substituted-checkpoint'; }});
  const page = {items: [summary]};
  const {client, calls} = await fixture(t, {lookup: () => page});
  const captured = await client.checkpoints({limit: 1});
  assert.equal(captured.items[0].checkpointId, original.checkpointId);
  assert.equal(reads, 1);
  assert.equal(Object.isFrozen(captured), true);
  assert.equal(Object.isFrozen(captured.items[0].subject), true);
  assert.equal(Object.isFrozen(page), false);
  page.items.length = 0;
  assert.equal(captured.items.length, 1);
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'checkpoints']);
});

test('exact Checkpoint lookup captures once without copying the admitted response again', async t => {
  let reads = 0, responseCopies = 0;
  const clone = globalThis.structuredClone;
  t.mock.method(globalThis, 'structuredClone', value => {
    // Transport still owns its required outbound packet copy.
    if (!Object.hasOwn(value, 'connection')) responseCopies++;
    return clone(value);
  });
  const summary = {...original};
  Object.defineProperty(summary, 'checkpointId', {enumerable: true,
    get() {reads++; return original.checkpointId;}});
  const {client, calls} = await fixture(t, {lookup: () => ({items: [summary]})});
  const page = await client.checkpoints({checkpointId: original.checkpointId});
  assert.deepEqual(page.items, [original]);
  assert.equal(reads, 1);
  assert.equal(responseCopies, 0);
  assert.equal(Object.isFrozen(page.items[0].requirements), true);
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'checkpoints']);
});

test('Checkpoint response capture refuses unreadable data without retaining private errors', async t => {
  const privateFailure = new Error('private response getter');
  const {client, calls} = await fixture(t, {lookup: () => ({get items() {throw privateFailure;}})});
  await assert.rejects(client.checkpoints(), error => {
    assert.equal(error.code, 'InvalidHostCheckpointPage');
    assert.equal(error.cause, undefined);
    return true;
  });
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'checkpoints']);
});

test('original signer values and receiver survive mutation during lookup', async t => {
  let release, arrived;
  const waiting = new Promise(resolve => {arrived = resolve;});
  const response = new Promise(resolve => {release = resolve;});
  const mutable = {...signer, sign(bytes) {
    assert.equal(this, mutable); return signer.sign(bytes);
  }};
  const {client, calls} = await fixture(t, {lookup: () => {arrived(); return response;}});
  const pending = client.approve(original.checkpointId, {signer: mutable});
  await waiting;
  mutable.keyId = 'different-key'; mutable.reviewerId = 'different-reviewer';
  mutable.authorityScopeCid = cid('f'); mutable.sign = () => assert.fail('replacement signer');
  release({items: [original]}); await pending;
  const resolution = JSON.parse(calls.at(-1).body.items[0].resolutionWire);
  const evidence = JSON.parse(calls.at(-1).body.items[0].approvalEvidenceWire).compatibility_approval;
  assert.equal(resolution.proof.key_id, signer.keyId); assert.equal(resolution.actor, signer.reviewerId);
  assert.equal(evidence.authority_scope_cid, signer.authorityScopeCid);
});

test('closing during lookup refuses before any application signature', async t => {
  let release, arrived, signatures = 0;
  const waiting = new Promise(resolve => {arrived = resolve;});
  const response = new Promise(resolve => {release = resolve;});
  const {client, calls} = await fixture(t, {lookup: () => {arrived(); return response;}});
  const result = client.approve(original.checkpointId, {signer: {...signer,
    sign(bytes) {signatures++; return signer.sign(bytes);}}}).catch(error => error);
  await waiting; await client.close(); release({items: [original]});
  assert.equal((await result).code, 'ClientClosed');
  assert.equal(signatures, 0); assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
});

test('Local original answer hook is captured once with its original receiver and immutable Summary', async t => {
  let invoked = 0;
  const {client, port, calls} = await fixture(t, {async answerCheckpoint(summary, decision) {
    assert.equal(this, port); invoked++;
    assert.equal(Object.isFrozen(summary), true); assert.equal(Object.isFrozen(summary.subject), true);
    assert.equal(Object.isFrozen(summary.requirements), true);
    assert.throws(() => {summary.subject.runId = 'foreign';}, TypeError);
    return signedAnswer(summary, decision, signer, '2026-10-18T00:01:00.000Z');
  }});
  port.answerCheckpoint = () => assert.fail('substituted provider callback');
  const result = await client.approve(original.checkpointId);
  assert.equal(invoked, 1); assert.equal(result.results[0].status, 'committed');
  assert.equal(calls.filter(call => call.operation === 'resolve').length, 1);
});

test('foreign or malformed Local signed answers refuse without resolution I/O', async t => {
  const good = await signedAnswer(original, 'approved', signer, '2026-10-18T00:01:00.000Z');
  for (const answer of [{...good, checkpointCid: cid('f')}, {}, null]) {
    let invoked = 0;
    const {client, calls} = await fixture(t, {async answerCheckpoint() {invoked++; return answer;}});
    await assert.rejects(client.approve(original.checkpointId), {code: 'InvalidCheckpointAnswer'});
    assert.equal(invoked, 1); assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  }
});

for (const [action, opposite] of [['approve', 'rejected'], ['reject', 'approved']]) {
  test(`${action} refuses an original-port answer for the opposite decision and retains its bytes`, async t => {
    const originalAnswer = await signedAnswer(original, opposite, signer,
      '2026-10-18T00:01:00.000Z');
    let signatures = 0;
    const {client, calls} = await fixture(t, {async answerCheckpoint(summary, decision) {
      assert.equal(summary.checkpointId, original.checkpointId);
      assert.equal(decision, action === 'approve' ? 'approved' : 'rejected');
      signatures++;
      return originalAnswer;
    }});
    const failure = await client[action](original.checkpointId).catch(error => error);
    assert.equal(failure.code, 'InvalidCheckpointAnswer');
    assert.deepEqual(failure.signed, [originalAnswer]);
    assert.equal(signatures, 1);
    assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  });
}

test('valid signatures for another original Summary refuse before resolution', async t => {
  for (const foreign of [
    {...original, checkpointId: 'another-checkpoint'},
    {...original, subject: {...original.subject, runId: 'another-run'}},
    {...original, subject: {...original.subject, runDefinitionCid: cid('f')}},
    {...original, requiredArtifact: {...original.requiredArtifact, cid: cid('f')}},
    {...original, reviewProjectionCid: cid('f')},
    {...original, requirements: ['effect_scope_approved', 'partial_application_accepted']},
  ]) {
    const originalAnswer = await signedAnswer(foreign, 'approved', signer,
      '2026-10-18T00:01:00.000Z');
    const {client, calls} = await fixture(t, {async answerCheckpoint() {return originalAnswer;}});
    const failure = await client.approve(original.checkpointId).catch(error => error);
    assert.equal(failure.code, 'InvalidCheckpointAnswer');
    assert.deepEqual(failure.signed, [originalAnswer]);
    assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  }
});

test('returned answer artifact grammar and nested evidence bind the original request', async t => {
  const good = await signedAnswer(original, 'approved', signer, '2026-10-18T00:01:00.000Z');
  const without = (value, key) => Object.fromEntries(Object.entries(value).filter(([name]) => name !== key));
  for (const mutate of [
    resolution => {resolution.unknown = true;},
    resolution => {resolution.version = 'unregistered';},
    resolution => {resolution.prepare_attempt_id = 'foreign';},
    (_resolution, evidence) => {evidence.unknown = true;},
    (_resolution, evidence) => {evidence.kind = 'read_access';},
    (_resolution, evidence) => {evidence.compatibility_approval.approver = 'another-reviewer';},
    (_resolution, evidence) => {evidence.compatibility_approval.proof.key_id = 'another-key';},
    (_resolution, evidence) => {evidence.compatibility_approval.effect_preview_cid = cid('f');},
    (_resolution, evidence) => {evidence.compatibility_approval.claims = [];},
  ]) {
    const resolution = JSON.parse(good.resolutionWire), evidence = JSON.parse(good.approvalEvidenceWire);
    mutate(resolution, evidence);
    const approval = evidence.compatibility_approval;
    approval.attestation_cid = await contentCid(without(approval, 'attestation_cid'));
    resolution.approval_evidence_cid = await contentCid(evidence);
    resolution.resolution_cid = await contentCid(without(resolution, 'resolution_cid'));
    const returned = {...good, resolutionWire: canonicalJson(resolution),
      approvalEvidenceWire: canonicalJson(evidence)};
    const {client, calls} = await fixture(t, {async answerCheckpoint() {return returned;}});
    const failure = await client.approve(original.checkpointId).catch(error => error);
    assert.equal(failure.code, 'InvalidCheckpointAnswer');
    assert.deepEqual(failure.signed, [returned]);
    assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  }
  for (const returned of [
    {...good, resolutionWire: '{}'},
    {...good, resolutionWire: good.resolutionWire.replace('resolution-action-original-approved', 'resolution-other-approved')},
    {...good, approvalEvidenceWire: ''},
    {...good, approvalEvidenceWire: 'null'},
  ]) {
    const {client, calls} = await fixture(t, {async answerCheckpoint() {return returned;}});
    await assert.rejects(client.approve(original.checkpointId), {code: 'InvalidCheckpointAnswer'});
    assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  }
});

test('a lost resolution reply preserves exact signed bytes without automatic re-sign or resend', async t => {
  let signatures = 0, lost = true;
  const {client, calls} = await fixture(t, {resolve(body) {
    if (lost) throw new Error('lost response');
    return {results: [{checkpointCid: body.items[0].checkpointCid, status: 'duplicate',
      decision: 'approved', resolutionCid: JSON.parse(body.items[0].resolutionWire).resolution_cid}]};
  }});
  const failure = await client.approve(original.checkpointId, {signer: {...signer,
    sign(bytes) {signatures++; return signer.sign(bytes);}}}).catch(error => error);
  assert.equal(failure.code, 'ResolutionUnknown'); assert.equal(failure.signed.length, 1);
  assert.equal(signatures, 2); assert.equal(calls.filter(call => call.operation === 'resolve').length, 1);
  const first = calls.at(-1).body.items;
  lost = false;
  assert.equal((await client.resolveCheckpoints(failure.signed)).results[0].status, 'duplicate');
  assert.deepEqual(calls.at(-1).body.items, first); assert.equal(signatures, 2);
  assert.equal(calls.filter(call => call.operation === 'checkpoints').length, 1);
});

test('Resolution reply captures original result fields before validation', async t => {
  const item = await signedAnswer(original, 'approved', signer, '2026-10-18T00:01:00.000Z');
  let reads = 0;
  const result = {status: 'committed', decision: 'approved',
    resolutionCid: JSON.parse(item.resolutionWire).resolution_cid};
  Object.defineProperty(result, 'checkpointCid', {enumerable: true,
    get() {return ++reads === 1 ? original.checkpointCid : cid('f');}});
  const raw = {results: [result]};
  const {client, calls} = await fixture(t, {resolve: () => raw});
  const answer = await client.resolveCheckpoints([item]);
  assert.equal(answer.results[0].checkpointCid, original.checkpointCid);
  assert.equal(reads, 1);
  assert.equal(Object.isFrozen(answer.results[0]), true);
  assert.equal(Object.isFrozen(raw), false);
  raw.results.length = 0;
  assert.equal(answer.results.length, 1);
  assert.deepEqual(answer.signed, [item]);
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'resolve']);
});

test('abort during a pending signature observes settlement and makes no second signature or resolve', async t => {
  let release, arrived, signatures = 0;
  const waiting = new Promise(resolve => {arrived = resolve;});
  const held = new Promise(resolve => {release = resolve;});
  const controller = new AbortController();
  const {client, calls} = await fixture(t);
  const pending = client.approve(original.checkpointId, {signal: controller.signal,
    signer: {...signer, async sign(bytes) {signatures++; arrived(); await held; return signer.sign(bytes);}}})
    .catch(error => error);
  await waiting; controller.abort(); release();
  assert.equal((await pending).name, 'AbortError'); assert.equal(signatures, 1);
  assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
});

test('Local signing Unknown and Host authority refusal are preserved without resolve or fallback', async t => {
  const originalFailure = Object.assign(new Error('LocalSigningUnknown'), {code: 'LocalSigningUnknown', cleanupPending: true});
  const {client, calls} = await fixture(t, {async answerCheckpoint() {throw originalFailure;}});
  assert.equal(await client.approve(original.checkpointId).catch(error => error), originalFailure);
  assert.equal(originalFailure.cleanupPending, true);
  assert.equal(calls.filter(call => call.operation === 'resolve').length, 0);
  let signed = 0;
  const denied = await fixture(t, {lookup() {throw new ClientError('CheckpointListDenied');}});
  await assert.rejects(denied.client.approve(original.checkpointId, {signer: {...signer,
    sign(bytes) {signed++; return signer.sign(bytes);}}}), {code: 'CheckpointListDenied'});
  assert.equal(signed, 0);
});
