import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {registerHooks} from 'node:module';
import {readFileSync} from 'node:fs';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {originalSubmission, readySubmissionAttempt, submissionEpoch} from './submission-fixture.mjs';

// Count completed SDK wire-admission passes, not transport copies, cheap
// identity comparisons, nested validator entries, or cache hits. The wrappers
// always invoke the unchanged real validator and maintain no result cache.
const admissions = new Map();
const counterKey = Symbol.for('actql.sdk.operation-validation.test');
globalThis[counterKey] = admissions;
const names = ['validClientAdmission', 'validSubmissionAttempt', 'validSubmissionLookup',
  'validRequestLookup', 'validRequestCancellation', 'validCancellationAttempt',
  'validCancellationLookup', 'validDeliveryAttemptLookup', 'validCheckOutcome',
  'validCheckpointPage', 'validCheckpointLookup', 'validResultDescription',
  'validResolveItem', 'validResolveResults'];
const wireUrl = new URL('../client-wire/index.mjs', import.meta.url).href;
const wrapper = `import * as wire from ${JSON.stringify(wireUrl)};
export * from ${JSON.stringify(wireUrl)};
${names.map(name => `export function ${name}(...args) {
  const result = wire.${name}(...args);
  const counts = globalThis[Symbol.for('actql.sdk.operation-validation.test')];
  // The selected lookup response below is nonempty. Its separate empty
  // selector probe is not a response admission or a nested validator pass.
  const key = '${name}' === 'validCheckpointLookup' && args[0]?.items?.length === 0
    ? 'checkpointSelectorProbe' : '${name}';
  counts.set(key, (counts.get(key) ?? 0) + 1);
  return result;
}`).join('\n')}`;
const wrapperUrl = `data:text/javascript,${encodeURIComponent(wrapper)}`;
const hook = registerHooks({resolve(specifier, context, nextResolve) {
  if (specifier === '@actql/client-wire' && context.parentURL?.includes('/packages/sdk/')) {
    return {url: wrapperUrl, shortCircuit: true};
  }
  return nextResolve(specifier, context);
}});
const sdk = await import('./index.mjs');
hook.deregister();
const {signedAnswer} = await import('./checkpoints.mjs');

const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const cancelRef = {...ref, cancelId: 'cancel', expectedRevision: 6};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
const admission = {ref, durability: 'durable', revision: 1};
const delivered = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const checked = JSON.parse(readFileSync(new URL('../client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));

async function fixture(t, respond) {
  const calls = [];
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return admission;
      return respond(operation, body);
    },
  });
  t.after(() => client.close());
  return {client, calls};
}
const assertPasses = expected => assert.deepEqual(Object.fromEntries(admissions), expected);

for (const kind of ['effect_set', 'model_invocation']) {
  for (const [action, decision] of [['approve', 'approved'], ['reject', 'rejected']]) {
    test(`${action} ${kind} constructs each signed CID once from the admitted Summary`, async t => {
      const model = kind === 'model_invocation';
      const summary = model ? JSON.parse(readFileSync(new URL(
        '../../portability/corpus/model-invocation-scope.json', import.meta.url))).summary
        : {checkpointId: 'checkpoint', checkpointCid: cid('c'), kind,
          phase: 'commit', subject: {kind: 'run_unit', runId: 'run', runDefinitionCid: cid('b')},
          requiredArtifact: {type: 'effect_set_preview', cid: cid('d')},
          reviewProjectionCid: cid('e'), requirements: ['effect_scope_approved'],
          createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z',
          humanSummary: 'Original Effect'};
      const keys = generateKeyPairSync('ed25519');
      let signatures = 0, sent;
      const signer = {keyId: 'key', reviewerId: 'reviewer', authorityScopeCid: cid('f'),
        sign(bytes) {signatures++; return sign(null, bytes, keys.privateKey);}};
      const f = await fixture(t, (operation, body) => {
        if (operation === 'checkpoints') return {items: [summary]};
        assert.equal(operation, 'resolve');
        sent = body.items[0];
        return {results: [{checkpointCid: summary.checkpointCid, status: 'committed', decision,
          resolutionCid: JSON.parse(sent.resolutionWire).resolution_cid}]};
      });
      const digests = [];
      const digest = crypto.subtle.digest;
      mock.method(crypto.subtle, 'digest', function (algorithm, bytes) {
        digests.push(Buffer.from(bytes).toString('hex'));
        return Reflect.apply(digest, this, [algorithm, bytes]);
      });
      try {
        admissions.clear();
        const answer = await f.client[action](summary.checkpointId, {signer});
        assert.equal(admissions.get('validCheckpointLookup'), 1);
        assert.equal(admissions.get('validCheckpointPage') ?? 0, 0,
          'the captured lookup Summary is already admitted');
        assert.equal(admissions.get('validResolveItem'), 1,
          'one bounded envelope check retains the application signature output boundary');
        assert.equal(admissions.get('validResolveResults'), 1);
        assert.equal(digests.length, decision === 'approved' ? 5 : 2,
          'only the distinct unsigned/signature-bearing/evidence preimages are hashed');
        assert.equal(new Set(digests).size, digests.length,
          'no constructor-produced CID preimage is hashed again');
        assert.equal(signatures, decision === 'approved' ? 2 : 1);
        assert.deepEqual(answer.signed[0], sent,
          'the transport may copy the envelope, never change its signed bytes');
        assert.equal(Object.isFrozen(answer.signed[0]), true);
        assert.equal(JSON.parse(sent.resolutionWire).decision, decision);
        assert.deepEqual(f.calls, ['connect', 'checkpoints', 'resolve']);
      } finally {mock.restoreAll();}
    });
  }
}

test('raw Model signing admits its copied Summary once and preserves the independent wires', async () => {
  const value = JSON.parse(readFileSync(new URL(
    '../../portability/corpus/model-invocation-scope.json', import.meta.url)));
  // This raw helper remains an intake boundary, unlike the lookup continuation.
  const {createPrivateKey} = await import('node:crypto');
  const key = createPrivateKey({format: 'der', type: 'pkcs8', key: Buffer.concat([
    Buffer.from('302e020100300506032b657004220420', 'hex'),
    Buffer.from(Array.from({length: 32}, (_, index) => index))])});
  admissions.clear();
  const answer = await signedAnswer(value.summary, 'approved', {
    keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
    sign: bytes => sign(null, bytes, key)}, value.decided_at);
  assertPasses({validCheckpointPage: 1});
  assert.equal(answer.resolutionWire, value.expected_resolution_wire);
  assert.equal(answer.approvalEvidenceWire, value.expected_approval_evidence_wire);
});

test('application signature output keeps the existing envelope limit before resolve', async t => {
  const summary = {checkpointId: 'checkpoint', checkpointCid: cid('c'),
    kind: 'effect_set', phase: 'commit',
    subject: {kind: 'run_unit', runId: 'run', runDefinitionCid: cid('b')},
    requiredArtifact: {type: 'effect_set_preview', cid: cid('d')},
    reviewProjectionCid: cid('e'), requirements: ['effect_scope_approved'],
    createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z',
    humanSummary: 'Original Effect'};
  const f = await fixture(t, operation => {
    assert.equal(operation, 'checkpoints');
    return {items: [summary]};
  });
  let signatures = 0;
  admissions.clear();
  await assert.rejects(f.client.reject(summary.checkpointId, {signer: {
    keyId: 'key', reviewerId: 'reviewer', sign() {signatures++; return 'A'.repeat(16384);},
  }}), {code: 'InvalidCheckpointAnswer'});
  assert.equal(signatures, 1);
  assert.equal(admissions.get('validResolveItem'), 1);
  assert.deepEqual(f.calls, ['connect', 'checkpoints']);
});

for (const [action, decision] of [['approve', 'approved'], ['reject', 'rejected']]) {
  test(`${action} reuses one admitted signed answer through resolution`, async t => {
    const summary = {checkpointId: 'checkpoint', checkpointCid: cid('c'),
      kind: 'effect_set', phase: 'commit',
      subject: {kind: 'run_unit', runId: 'run', runDefinitionCid: cid('b')},
      requiredArtifact: {type: 'effect_set_preview', cid: cid('d')},
      reviewProjectionCid: cid('e'), requirements: ['effect_scope_approved'],
      createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z',
      humanSummary: 'Original Effect'};
    const keys = generateKeyPairSync('ed25519');
    const original = await signedAnswer(summary, decision, {keyId: 'key', reviewerId: 'reviewer',
      authorityScopeCid: cid('f'), sign: bytes => sign(null, bytes, keys.privateKey)},
    '2026-10-18T00:01:00.000Z');
    const calls = [];
    let originalAnswers = 0;
    const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
      answerCheckpoint(observed, requested) {
        originalAnswers++;
        assert.deepEqual(observed, summary);
        assert.equal(requested, decision);
        return original;
      },
      perform(operation, body) {
        calls.push(operation);
        if (operation === 'connect') return profile;
        if (operation === 'checkpoints') return {items: [summary]};
        assert.equal(operation, 'resolve');
        assert.deepEqual(body.items, [original]);
        return {results: [{checkpointCid: summary.checkpointCid, status: 'committed',
          decision, resolutionCid: JSON.parse(original.resolutionWire).resolution_cid}]};
      },
    });
    t.after(() => client.close());
    admissions.clear();
    const answer = await client[action](summary.checkpointId);
    assert.equal(admissions.get('validResolveItem'), 1, 'one envelope admission, not three internal entries');
    assert.equal(admissions.get('validResolveResults'), 1);
    assert.deepEqual(answer.signed, [original]);
    assert.equal(originalAnswers, 1);
    assert.deepEqual(calls, ['connect', 'checkpoints', 'resolve']);
    admissions.clear();
    await client.resolveCheckpoints(answer.signed);
    assert.equal(admissions.get('validResolveItem'), 1, 'an explicit later resend is a new public operation');
    assert.equal(admissions.get('validResolveResults'), 1);
    assert.equal(originalAnswers, 1, 'never obtain replacement signed bytes');
  });
}

test('Checkpoint page and exact lookup each admit one captured response', async t => {
  const summary = {checkpointId: 'checkpoint', checkpointCid: cid('c'),
    kind: 'effect_set', phase: 'commit',
    subject: {kind: 'run_unit', runId: 'run', runDefinitionCid: cid('b')},
    requiredArtifact: {type: 'effect_set_preview', cid: cid('d')},
    reviewProjectionCid: cid('e'), requirements: ['effect_scope_approved'],
    createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z',
    humanSummary: 'Original Effect'};
  const f = await fixture(t, () => ({items: [summary]}));
  admissions.clear();
  await f.client.checkpoints({limit: 1});
  assertPasses({validCheckpointPage: 1});
  admissions.clear();
  const page = await f.client.checkpoints({checkpointId: summary.checkpointId});
  assertPasses({checkpointSelectorProbe: 1, validCheckpointLookup: 1});
  admissions.clear();
  assert.equal(page.items[0].checkpointId, summary.checkpointId);
  assertPasses({});
});

test('Result description admits one captured response and pure access does no readmission', async t => {
  const canonical = value => value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
  const identity = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
  const schema = {n: {type: 'number', nullable: false}};
  const programDefinitionCid = cid('c');
  const answer = {ref, resultName: 'answer', programDefinitionCid,
    resultDefinitionCid: identity({version: 'actql-result-definition/0.1',
      program_definition_cid: programDefinitionCid, result_name: 'answer'}),
    resultArtifactCid: cid('d'), resultSchemaCid: identity(schema),
    columns: [{name: 'n', contract: schema.n}],
    serialization: {format: 'jsonl', version: 'actql-jsonl/0.1',
      contractCid: identity({json_value_wire_contract_cid:
        'sha256:8ce92036074141bdc4b39436fe2460c7d1460810af1c345b45c6fc102b36791b',
      version: 'actql-jsonl/0.1'})}};
  const f = await fixture(t, () => answer);
  const run = await f.client.attach(ref);
  admissions.clear();
  const captured = await run.result('answer').describe();
  assertPasses({validResultDescription: 1});
  admissions.clear();
  assert.deepEqual(captured.ref, ref);
  assert.equal(captured.columns[0].name, 'n');
  assertPasses({});
  assert.deepEqual(f.calls, ['connect', 'attach', 'result-describe']);
});

test('ready submit admits its envelope once and constructs a Run without readmission', async t => {
  const f = await fixture(t, (_operation, body) => readySubmissionAttempt(body, admission));
  admissions.clear();
  const run = await f.client.start({}, {submissionRef: originalSubmission('original')});
  assert.deepEqual(run.ref, ref);
  assertPasses({validSubmissionAttempt: 1});
  const before = new Map(admissions);
  run.result('answer');
  sdk.explainSubmission(run);
  sdk.getSubmissionInput(run);
  assert.deepEqual(admissions, before);
  assert.deepEqual(f.calls, ['connect', 'submit-intent']);
});

test('attach validates one admission and pure handle access performs no admission', async t => {
  const f = await fixture(t);
  admissions.clear();
  const run = await f.client.attach(ref);
  assertPasses({validClientAdmission: 1});
  admissions.clear();
  assert.deepEqual(run.ref, ref);
  run.result('answer');
  assertPasses({});
  assert.deepEqual(f.calls, ['connect', 'attach']);
});

for (const [name, validator, reply, invoke] of [
  ['request lookup', 'validRequestLookup', {kind: 'found', requestId: 'saved', ref,
    durability: 'durable', lookupExpiresAt: '2099-01-01T00:00:00.000Z'},
  f => f.client.lookupRequest('saved')],
  ['request cancel', 'validRequestCancellation', {kind: 'accepted', requestId: 'saved', ref, revision: 7},
  f => f.client.cancelRequest('saved')],
  ['submission lookup', 'validSubmissionLookup', {kind: 'preparing',
    submissionRef: originalSubmission('original'), intentCid: cid('c')},
  f => f.client.lookupSubmission(originalSubmission('original'))],
  ['cancel', 'validCancellationAttempt', {kind: 'accepted',
    attemptRef: {operation: 'cancel', attemptId: 'attempt'},
    cancellation: {kind: 'accepted', ref, cancelRef, revision: 7}},
  f => f.run.cancel({cancelId: 'cancel', expectedRevision: 6, attemptId: 'attempt'})],
  ['cancel lookup', 'validCancellationLookup', {kind: 'found',
    cancellation: {kind: 'accepted', ref, cancelRef, revision: 7}},
  f => f.run.lookupCancellation(cancelRef)],
  ['delivery lookup', 'validDeliveryAttemptLookup', delivered,
  f => f.run.result('answer').deliveryAttempt('read-a')],
  ['static check', 'validCheckOutcome', checked,
  f => f.client.check('SELECT 1 AS n', {kind: 'text', scope: 'bound_input', format: 'sql'})],
]) {
  test(`${name} admits one captured reply and no repeated verification`, async t => {
    const f = await fixture(t, () => reply);
    f.run = await f.client.attach(ref);
    admissions.clear();
    const answer = await invoke(f);
    assertPasses({[validator]: 1});
    assert.equal(Object.isFrozen(answer), true);
    const before = new Map(admissions);
    sdk.explainSubmission(answer);
    sdk.explainCancellation(answer);
    sdk.explainRequestLookup(answer);
    sdk.explainDeliveryAttempt(answer);
    assert.deepEqual(admissions, before);
    assert.equal(f.calls.length, 3);
  });
}
