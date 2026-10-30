import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';

const cid = 'sha256:' + 'a'.repeat(64);
function fixture(verifyRequestValuePolicy, {effectful = false} = {}) {
  const base = {}, verified = {}, initial = {}, final = {};
  const calls = [];
  const subject = {program_cid: cid, parameters_cid: cid,
    stage: 0, input: 0, source_ref: 'fixture:files', source_view_contract_cid: cid,
    request_cid: cid, request: {path: 'cafe\u0301\r\n'}, origins: {path: 'literal'}};
  const moon = {
    clientProgramPrepareEffectFreeWithParameters(...args) {
      if (effectful) return {rejected: true};
      calls.push(args); return args[2] === base ? initial : final;
    },
    clientProgramPreparationReady(value) {return value.rejected ? undefined : value;},
    clientProgramPreparationIssue() {return {};},
    clientProgramPreparationIssueCode() {return 'effect_not_supported';},
    clientProgramPrepareEffectComputationWithParameters(...args) {
      calls.push(args); return args[2] === base ? initial : final;
    },
    clientProgramEffectPreparationReady(value) {return value;},
    clientProgramEffectPreparationIssue() {}, clientProgramEffectPreparationIssueCode() {},
    clientProgramRequestValuePolicySubjects(value) {
      assert.equal(value, initial); return {$tag: 1, _0: [JSON.stringify(subject)]};
    },
    clientProgramBindHostVerifiedRequestValuePolicy(value, index, policy) {
      assert.equal(value, initial); assert.equal(index, 0); assert.equal(policy, cid);
      return {proof: true};
    },
    clientProgramCheckEnvironmentWithRequestValuePolicies(value, evidence) {
      assert.equal(value, base); assert.deepEqual(evidence, [{proof: true}]);
      return verified;
    },
  };
  moon.clientProgramEffectRequestValuePolicySubjects = moon.clientProgramRequestValuePolicySubjects;
  moon.clientProgramEffectBindHostVerifiedRequestValuePolicy = moon.clientProgramBindHostVerifiedRequestValuePolicy;
  const prepare = installNodeClientProgramPreparation({moon, environment: base,
    verifyRequestValuePolicy, allowEffects: effectful});
  const request = {kind: 'program', input: {version: 'actql/0.1'}, parameters: null};
  return {prepare, request, calls, subject, initial, final, moon};
}

test('trusted request verifier rechecks the original input through the common owner', async () => {
  let seen;
  const value = fixture(async subject => {
    seen = subject;
    assert.ok(Object.isFrozen(subject));
    assert.ok(Object.isFrozen(subject.request));
    assert.equal(subject.request.path, 'cafe\u0301\r\n');
    return cid;
  });
  const result = await value.prepare(value.request);
  assert.equal(result, value.final);
  value.prepare.assertOwned(result);
  assert.deepEqual(seen, value.subject);
  assert.equal(value.calls.length, 2);
  assert.equal(value.calls[0][0], value.calls[1][0]);
  assert.equal(value.calls[0][3], value.calls[1][3]);
  assert.notEqual(value.calls[0][2], value.calls[1][2]);
});

test('absent verification never defaults to the Source response policy', async () => {
  for (const verifier of [undefined, async () => undefined]) {
    const value = fixture(verifier);
    assert.equal(await value.prepare(value.request), value.initial);
    assert.equal(value.calls.length, 1);
  }
});

test('invalid verifier output cannot supplement the checker', async () => {
  for (const result of [true, null, {classification: 'public'}, 'internal']) {
    const value = fixture(async () => result);
    await assert.rejects(value.prepare(value.request), {code: 'ClientProgramPreparationFailure'});
    assert.equal(value.calls.length, 1);
  }
});

test('cancellation after awaited verification prevents the supplemental recheck', async () => {
  const controller = new AbortController();
  const value = fixture(async () => {controller.abort(); return cid;});
  value.request.signal = controller.signal;
  await assert.rejects(value.prepare(value.request), {name: 'AbortError'});
  assert.equal(value.calls.length, 1);
});

test('Effectful verification rechecks with the same Effect evidence and selected environment', async () => {
  const value = fixture(async () => cid, {effectful: true});
  assert.equal(await value.prepare(value.request), value.final);
  assert.equal(value.prepare.kindOf(value.final), 'effectful');
  assert.equal(value.calls.length, 2);
  assert.equal(value.calls[0][0], value.calls[1][0]);
  assert.equal(value.calls[0][3], value.calls[1][3]);
  assert.deepEqual(value.calls[0][4], value.calls[1][4]);
  assert.notEqual(value.calls[0][2], value.calls[1][2]);
});

test('raised subject failure is not mistaken for an empty successful evidence inventory', async () => {
  let verified = 0;
  const value = fixture(async () => {verified++; return cid;});
  value.moon.clientProgramRequestValuePolicySubjects = () => ({$tag: 0, _0: {issue: 'bounded'}});
  await assert.rejects(value.prepare(value.request), {code: 'MoonBitHostFailure'});
  assert.equal(verified, 0);
  assert.equal(value.calls.length, 1);
});

test('funded policy preparation forwards the original verifier without compiled-owner fallback', async () => {
  const environment = {}, prepared = {}, parametersCursor = {};
  const controller = new AbortController();
  const request = {kind: 'program', parameters: null, signal: controller.signal,
    input: {toJSON() {assert.fail('The original funded snapshot must not be serialized again');}}};
  const verify = async () => assert.fail('The funded Request owns policy verification before compilation');
  let preparations = 0;
  const prepare = installNodeClientProgramPreparation({moon: {}, environment,
    verifyRequestValuePolicy: verify,
    getFundedPreparation(actual, selected, originalVerifier) {
      assert.strictEqual(actual, request);
      assert.strictEqual(selected, environment);
      assert.strictEqual(originalVerifier, verify);
      preparations++;
      return {kind: 'effect_free', prepared,
        originalInputs: {environment, parameters: undefined, parametersCursor}};
    }});
  assert.strictEqual(await prepare(request), prepared);
  assert.equal(preparations, 1);
  assert.strictEqual(prepare.originalInputs(prepared).environment, environment);
  assert.strictEqual(prepare.originalInputs(prepared).parametersCursor, parametersCursor);
  prepare.retireOriginal(prepared);
});
