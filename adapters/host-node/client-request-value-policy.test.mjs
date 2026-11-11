import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';

test('legacy compiled-policy exports cannot replace the original Request verifier owner', () => {
  let legacyCalls = 0;
  const legacy = () => {legacyCalls++;};
  const moon = {
    clientProgramPrepareEffectFreeWithParameters: legacy,
    clientProgramPreparationReady: legacy,
    clientProgramPreparationIssue: legacy,
    clientProgramPreparationIssueCode: legacy,
    clientProgramRequestValuePolicySubjects: legacy,
    clientProgramBindHostVerifiedRequestValuePolicy: legacy,
    clientProgramCheckEnvironmentWithRequestValuePolicies: legacy,
  };
  assert.throws(() => installNodeClientProgramPreparation({moon, environment: {},
    verifyRequestValuePolicy() {}}), {message: 'InvalidClientProgramPreparationInstallation'});
  assert.equal(legacyCalls, 0);
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
    getFundedPreparation(actual, selected, originalVerifier, signal) {
      assert.strictEqual(actual, request);
      assert.strictEqual(selected, environment);
      assert.strictEqual(originalVerifier, verify);
      assert.strictEqual(signal, controller.signal);
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

test('funded policy owner failure keeps its original cause without public checking or legacy preparation', async () => {
  const cause = Object.assign(new Error('Original verifier failure'), {code: 'ClientProgramRejected'});
  let attempts = 0, checks = 0;
  const prepare = installNodeClientProgramPreparation({moon: {}, environment: {},
    verifyRequestValuePolicy() {assert.fail('Only the original Request may invoke this verifier');},
    getFundedPreparation() {attempts++; throw cause;},
    check() {checks++; assert.fail('A failed original must not be checked again');}});
  await assert.rejects(prepare({kind: 'aql', input: {format: 'sql', text: 'SELECT 1 AS n'}, parameters: null}),
    error => error === cause);
  assert.equal(attempts, 1); assert.equal(checks, 0);
  assert.equal(Object.hasOwn(prepare, 'sourceCheckFailure'), false);
});
