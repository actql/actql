import assert from 'node:assert/strict';
import test from 'node:test';
import {signedAnswer} from './checkpoints.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const summary = Object.freeze({
  checkpointId: 'checkpoint-original', checkpointCid: cid('1'),
  kind: 'run_scope', phase: 'preflight',
  subject: Object.freeze({kind: 'prepare_attempt',
    prepareAttemptId: 'preparation-original', requestId: 'request-original'}),
  requiredArtifact: Object.freeze({type: 'prepared_invocation', cid: cid('2')}),
  reviewProjectionCid: cid('3'), requirements: ['invocation_scope_approved'],
  createdAt: '2026-11-18T00:00:00.000Z',
  expiresAt: '2026-11-19T00:00:00.000Z', humanSummary: 'Display only',
});
const decidedAt = '2026-11-18T01:00:00.000Z';

test('fabricated noncanonical original identities refuse before application signing', async () => {
  const noncanonical = 'e\u0301';
  const candidates = [
    {...summary, checkpointId: noncanonical},
    {...summary, subject: {...summary.subject, prepareAttemptId: noncanonical}},
    {...summary, kind: 'read_access', subject: {kind: 'run_unit',
      runId: noncanonical, runDefinitionCid: cid('4')},
    requiredArtifact: {type: 'read_scope', cid: cid('5')}},
  ];
  for (const candidate of candidates) {
    let signatures = 0;
    const signer = {keyId: 'fixture-key', reviewerId: 'fixture-reviewer',
      sign() { signatures++; return new Uint8Array(64); }};
    await assert.rejects(signedAnswer(candidate, 'rejected', signer, decidedAt),
      {message: 'InvalidCheckpointAnswer'});
    assert.equal(signatures, 0);
    // Refusal must not normalize one claimed original into another identity.
    assert.equal(JSON.stringify(candidate).includes(noncanonical), true);
  }
});

test('canonical original identities stay exact while display text does not enter signed preimages', async () => {
  const sign = captured => bytes => {
    captured.push(new TextDecoder().decode(bytes));
    return new Uint8Array(64);
  };
  const signer = captured => ({keyId: 'fixture-key',
    reviewerId: 'fixture-reviewer', sign: sign(captured)});
  const legal = {...summary, checkpointId: ' id-é ',
    subject: {...summary.subject, prepareAttemptId: 'préparation-original'}};
  const before = [], after = [];
  const original = await signedAnswer(legal, 'approved', signer(before), decidedAt);
  const displayed = await signedAnswer({...legal, humanSummary: 'e\u0301\r\n'},
    'approved', signer(after), decidedAt);
  assert.equal(JSON.parse(displayed.resolutionWire).checkpoint_id, legal.checkpointId);
  assert.equal(JSON.parse(displayed.resolutionWire).prepare_attempt_id,
    legal.subject.prepareAttemptId);
  assert.deepEqual(after, before);
  assert.deepEqual(displayed, original);
  assert.equal(after.length, 2);
});

test('signer byte capacity and encoding use the original typed array storage', async () => {
  const tooLong = new Uint8Array(65);
  Object.defineProperty(tooLong, 'byteLength', {value: 64});
  tooLong[Symbol.iterator] = () => new Uint8Array(64).values();
  const signer = sign => ({keyId: 'fixture-key', reviewerId: 'fixture-reviewer', sign});
  await assert.rejects(signedAnswer(summary, 'rejected', signer(() => tooLong), decidedAt),
    {message: 'InvalidCheckpointSignature'});

  const exact = new Uint8Array(64);
  exact[Symbol.iterator] = () => assert.fail('Use the original byte storage');
  const fromBytes = await signedAnswer(summary, 'rejected', signer(() => exact), decidedAt);
  const fromText = await signedAnswer(summary, 'rejected',
    signer(() => 'A'.repeat(86) + '=='), decidedAt);
  assert.deepEqual(fromBytes, fromText);
});
