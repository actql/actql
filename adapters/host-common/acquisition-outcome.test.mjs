import assert from 'node:assert/strict';
import test from 'node:test';
import {AcquisitionOpenError, acquisitionFailure, acquisitionOutcome,
  acquisitionEndHandoff} from './acquisition-outcome.mjs';

test('throwing code classification preserves the original reason and stated outcome', () => {
  for (const secondary of [undefined, null, false, Object.freeze(new Error('CodeGetterFailure'))]) {
    let calls = 0;
    const reason = Object.freeze({get code() { calls++; throw secondary; }});
    const error = new AcquisitionOpenError(reason, 'not_started');
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.cause, reason); assert.equal(error.outcome, 'not_started');
    assert.equal(calls, 1); assert.ok(Object.hasOwn(error, 'classificationFailure'));
    assert.equal(error.classificationFailure, secondary);
    assert.equal(Object.keys(error).includes('classificationFailure'), false);
  }
});

test('throwing message classification is separate from the body rejection', () => {
  const secondary = Object.freeze({messageGetter: true});
  let codeReads = 0, messageReads = 0;
  const reason = Object.freeze({get code() { codeReads++; return 17; },
    get message() { messageReads++; throw secondary; }});
  const error = new AcquisitionOpenError(reason, 'unknown');
  assert.equal(error.code, 'AcquisitionFailed'); assert.equal(error.cause, reason);
  assert.equal(error.classificationFailure, secondary);
  assert.equal(codeReads, 1); assert.equal(messageReads, 1);
});

test('code classification captures one original value without a second getter access', () => {
  let reads = 0;
  const reason = {get code() { reads++; return reads === 1 ? 'OriginalCode' : 'ChangedCode'; }};
  const error = new AcquisitionOpenError(reason, 'stopped');
  assert.equal(error.code, 'OriginalCode'); assert.equal(error.message, 'OriginalCode');
  assert.equal(error.cause, reason); assert.equal(reads, 1);
});

test('message classification captures one value and performs no coercion', () => {
  let reads = 0;
  const reason = {get code() { return Symbol('not text'); },
    get message() { reads++; return reads === 1 ? 'OriginalMessage' : ''; }};
  const error = new AcquisitionOpenError(reason, 'unknown');
  assert.equal(error.code, 'OriginalMessage'); assert.equal(error.cause, reason);
  assert.equal(reads, 1);
});

test('factory prototype inspection cannot replace the original arbitrary rejection', () => {
  for (const secondary of [undefined, Object.freeze(new Error('PrototypeInspectionFailure'))]) {
    const reason = new Proxy(Object.create(null), {getPrototypeOf() { throw secondary; }});
    const error = acquisitionFailure(reason, 'unknown');
    assert.equal(error.cause, reason); assert.equal(error.code, 'AcquisitionFailed');
    assert.deepEqual(acquisitionOutcome(error), {outcome: 'unknown', recovery: undefined});
    assert.ok(Object.hasOwn(error, 'identityInspectionFailure'));
    assert.equal(error.identityInspectionFailure, secondary);
    assert.equal(Object.keys(error).includes('identityInspectionFailure'), false);
  }
});

test('revoked Proxy rejection retains its identity and both distinct inspection failures', () => {
  const {proxy, revoke} = Proxy.revocable({}, {}); revoke();
  const error = acquisitionFailure(proxy, 'not_started');
  assert.equal(error.cause, proxy); assert.equal(error.outcome, 'not_started');
  assert.equal(error.code, 'AcquisitionFailed');
  assert.ok(error.identityInspectionFailure instanceof TypeError);
  assert.ok(error.classificationFailure instanceof TypeError);
});

test('existing inner acquisition keeps its original end statement and recovery', () => {
  const recovery = Object.freeze({close() {}, cleanup() {}, cleanupPending() { return true; }});
  const reason = Object.freeze(new Error('OriginalBodyFailure'));
  const inner = new AcquisitionOpenError(reason, 'unknown', recovery);
  assert.equal(acquisitionFailure(inner, 'stopped'), inner);
  assert.equal(inner.cause, reason);
  const handoff = acquisitionEndHandoff(); assert.equal(handoff.retain(inner), inner);
  assert.deepEqual(handoff.outcome(), {outcome: 'unknown', recovery});
  assert.throws(() => acquisitionFailure(reason, 'invalid'), {message: 'InvalidAcquisitionOutcome'});
});

test('primitive normal Error and plain-object reasons preserve existing labels and identities', () => {
  for (const reason of [undefined, null, false, 0, '', Symbol('reason'),
    Object.freeze({original: true}), Object.freeze(new Error('OriginalError'))]) {
    const error = acquisitionFailure(reason, 'not_started');
    assert.equal(error.cause, reason); assert.equal(error.outcome, 'not_started');
    assert.equal(error.code, reason instanceof Error ? 'OriginalError' : 'AcquisitionFailed');
    assert.equal(Object.hasOwn(error, 'classificationFailure'), false);
    assert.equal(Object.hasOwn(error, 'identityInspectionFailure'), false);
  }
});
