import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';

// Original-reference service ports only. The actual plan callee checks the
// request association before this explicit compiler-control refusal. This
// constructs no Common grant, physical start, Result or normal acceptance.
async function retainedRequestControl({copiedRequest = false} = {}) {
  const prepared = Object.freeze({});
  const request = Object.freeze({original: 'request'});
  const supplied = copiedRequest ? Object.freeze({...request}) : request;
  const definition = Object.freeze({wire: 'original-retained-definition'});
  const ref = Object.freeze({runDefinitionCid: 'original-retained-run'});
  const original = Object.freeze({preparedProgram: prepared, requestIdentity: request,
    compiled: Object.freeze({kind: 'values'}), runDefinition: definition,
    queryTimePreparation: Object.freeze({}), queryTime: Object.freeze({})});
  const entered = new Error('OriginalCompiledOwnerControl');
  const plans = [], failures = [];
  let compiledChecks = 0, physicalStarts = 0, preDispatchFailures = 0;
  const owner = installNodeClientDispatchOwner({moon: {}, control: {}, namespaceId: 'original-namespace',
    journal: {reservePhysicalStart() {physicalStarts++; assert.fail('No physical work in this control');},
      markPreDispatchFailure(value) {assert.strictEqual(value, ref); preDispatchFailures++;}},
    store: {}, hostConnection: () => true,
    startRun: async ({identity}) => {assert.strictEqual(identity, supplied); return {kind: 'reconcile', ref};},
    observed(name, detail) {if (name === 'dispatch_failed') failures.push(detail);},
    planFor(submission, retainedDefinitionWire, requestIdentity) {
      plans.push({prepared: submission.preparedProgram, retainedDefinitionWire, requestIdentity});
      return sourceFreeValuesPlan({preparedProgram: submission.preparedProgram,
        requestIdentity, retainedDefinitionWire, invocationOriginal: original,
        control: {checkClientCompiledRunOwner(compiled, program) {
          assert.strictEqual(compiled, original.compiled);
          assert.strictEqual(program, prepared);
          compiledChecks++;
          throw entered;
        }}});
    }});
  const submission = {preparedProgram: prepared, principalId: 'owner',
    connection: {}, requestId: 'original-request'};
  const accepted = {ref, runDefinition: definition, dispatchReserved: true,
    physicalStartReserved: false, preDispatchFailureConfirmed: false,
    cancellationRequested: false};
  assert.equal(await owner.start(submission, supplied, accepted, {}), 'not_started');
  await owner.drain();
  assert.equal(owner.operation(ref), undefined);
  assert.equal(plans.length, 1);
  assert.strictEqual(plans[0].prepared, prepared);
  assert.strictEqual(plans[0].requestIdentity, supplied);
  assert.equal(plans[0].retainedDefinitionWire, definition.wire);
  assert.equal(physicalStarts, 0);
  assert.equal(preDispatchFailures, 1);
  assert.equal(failures.length, 1);
  return {compiledChecks, failure: failures[0]};
}

test('retained dispatch forwards the same request into its original timed-plan validator', async () => {
  const observed = await retainedRequestControl();
  assert.equal(observed.compiledChecks, 1);
  assert.equal(observed.failure.code, 'OriginalCompiledOwnerControl');
});

test('retained dispatch cannot substitute a copied request for the timed-plan original', async () => {
  const observed = await retainedRequestControl({copiedRequest: true});
  assert.equal(observed.compiledChecks, 0);
  assert.equal(observed.failure.code, 'ForeignClientQueryInvocationOriginal');
});
