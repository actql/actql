import assert from 'node:assert/strict';
import test from 'node:test';
import {clientHostOperations, prepareClientHostRequest, validClientBody,
  validClientConnection, validRunRef} from './index.mjs';

const connection = Object.freeze({mode: 'remote', owner: 'remote',
  consentRefs: [], runners: []});
const ref = Object.freeze({namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});

test('public wire accepts the exact connected request shapes', () => {
  // Run, request, submission-intent, read-only Plan/Facts, check and discovery.
  assert.deepEqual([...clientHostOperations].sort(), [
    'connect', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent', 'lookup-submission',
    'check', 'plan', 'static-explanation', 'inspect-run', 'run-plan', 'run-explanation',
    'run-explanation-context', 'run-sample', 'attach', 'lookup-request', 'status', 'wait', 'cancel',
    'lookup-cancellation', 'lookup-control-operation', 'resume-run', 'reconcile', 'read', 'result-describe',
    'delivery-attempt', 'checkpoints', 'checkpoint-review', 'resolve',
    'cancel-request', 'resources', 'resource-inspect', 'resource-peek',
    'owner-observations',
  ].sort());
  assert.equal(validClientConnection(connection), true);
  assert.equal(validRunRef(ref), true);
  assert.equal(validClientBody('connect', {connection}), true);
  assert.equal(validClientBody('submit', {connection, requestId: 'saved-a',
    kind: 'aql', input: {text: 'version: actql/0.1\n', format: 'yaml'},
    parameters: null}), true);
  const staticPlan = {connection, kind: 'program', input: {}, parameters: null,
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64};
  assert.equal(validClientBody('plan', staticPlan), true);
  assert.equal(validClientBody('plan', {...staticPlan, requestId: 'not-a-submission'}), false);
  assert.equal(validClientBody('static-explanation', staticPlan), true);
  for (const change of [{requestId: 'not-a-submission'}, {ref}, {maxDepth: 65}]) {
    assert.equal(validClientBody('static-explanation', {...staticPlan, ...change}), false);
  }
  const inspectRun = {connection, ref, maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64};
  const lookup = {...inspectRun, operationRef: {run_ref: ref, operation_id: 'original-command',
    command_cid: ref.runDefinitionCid, accepted_from_revision: 1}};
  assert.equal(validClientBody('lookup-control-operation', lookup), true);
  for (const change of [{extra: true}, {operation_id: 'x'.repeat(257)},
    {run_ref: {...ref, namespaceId: 'foreign'}}, {accepted_from_revision: -1}]) {
    assert.equal(validClientBody('lookup-control-operation',
      {...lookup, operationRef: {...lookup.operationRef, ...change}}), false);
  }
  const resume = {...inspectRun, command: {version: 'actql-control-command/0.1', run_ref: ref,
    operation: 'resume', expected_control_revision: 1, operation_id: 'original-command',
    interval: {until: 'step', guards: null}, self_cid: ref.runDefinitionCid}};
  assert.equal(validClientBody('resume-run', resume), true);
  for (const change of [{operation: 'pause'}, {operation_id: 'x'.repeat(257)},
    {run_ref: {...ref, namespaceId: 'foreign'}}, {mode: 'resume'},
    {expected_control_revision: -1}, {interval: {until: 'breakpoint', guards: null}}]) {
    assert.equal(validClientBody('resume-run', {...resume, command: {...resume.command, ...change}}), false);
  }
  const capturedResume = prepareClientHostRequest('resume-run', resume);
  resume.command.interval.until = 'terminal';
  assert.ok(capturedResume && validClientBody('resume-run', capturedResume.body));
  assert.equal(capturedResume.body.command.interval?.until, 'step');
  assert.equal(Object.isFrozen(capturedResume.body.command.run_ref), true);
  const sample = {...inspectRun, selector: {step: {by: 'name', name: 'original'}, role: 'output'}};
  assert.equal(validClientBody('run-sample', sample), true);
  const nextSample = {...sample, nextRevision: 5, selector: {step: {by: 'id', step_id: ref.runDefinitionCid},
    role: 'input', input_port_id: ref.runDefinitionCid}};
  assert.equal(validClientBody('run-sample', nextSample), true);
  assert.equal(validClientBody('run-sample', {...sample, nextRevision: 5}), false);
  assert.equal(validClientBody('run-sample', {...nextSample, nextRevision: 0}), false);
  assert.equal(validClientBody('run-sample', {...nextSample, producerAttempt: 2}), false);
  assert.equal(validClientBody('run-sample', inspectRun), false);
  assert.equal(validClientBody('run-sample', {...sample,
    selector: {...sample.selector, input_port_id: ref.runDefinitionCid}}), false);
  assert.equal(validClientBody('run-explanation-context', {...inspectRun, ref: undefined}), false);
  assert.equal(validClientBody('run-explanation-context',
    {...inspectRun, ref: {...ref, extra: true}}), false);
  for (const operation of ['inspect-run', 'run-plan', 'run-explanation', 'run-explanation-context'] as const) {
    assert.equal(validClientBody(operation, inspectRun), true);
    for (const change of [{requestId: 'not-a-submission'}, {maxWireBytes: 0},
      {maxDepth: 65}, {maxNodes: 10001}]) {
      assert.equal(validClientBody(operation, {...inspectRun, ...change}), false);
    }
  }
  const submissionRef = {epoch: {version: 'actql-submission-epoch/0.1',
    authorityScopeCid: ref.authorityScopeCid, epochNonce: 'c'.repeat(64),
    notBefore: 1800000000000, expiresAt: 1800000001000, authenticator: 'd'.repeat(64)},
  nonce: 'original-submission'};
  const submitted = {connection, submissionRef,
    intentCid: 'sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44',
    kind: 'program', input: {}, parameters: null,
    attemptRef: {operation: 'submit', attemptId: 'original-submission-attempt'}};
  assert.equal(validClientBody('submit-intent', submitted), true);
  assert.equal(validClientBody('submit-named-intent', {...submitted, requestName: 'original-public-name'}), true);
  assert.equal(validClientBody('submit-named-intent', submitted), false);
  assert.equal(validClientBody('submit-intent', {...submitted, requestName: 'original-public-name'}), false);
  const fresh = {...submissionRef, epoch: {...submissionRef.epoch,
    epochNonce: 'e'.repeat(64), notBefore: 1800000001000, expiresAt: 1800000002000}, nonce: 'fresh'};
  const restarted = {...submitted, submissionRef: fresh, unresolvedHistory: {
    submissionRef, acknowledgement: 'possible_prior_execution_and_effects'}};
  assert.equal(validClientBody('restart-intent', restarted), true);
  assert.equal(validClientBody('submit-intent', restarted), false);
  for (const unresolvedHistory of [undefined, {...restarted.unresolvedHistory, acknowledgement: 'retry'},
    {...restarted.unresolvedHistory, actorId: 'caller-selected'},
    {...restarted.unresolvedHistory, submissionRef: fresh},
    {...restarted.unresolvedHistory, submissionRef: {...submissionRef,
      epoch: {...submissionRef.epoch, authorityScopeCid: 'sha256:' + '0'.repeat(64)}}}]) {
    assert.equal(validClientBody('restart-intent', {...restarted, unresolvedHistory}), false);
  }
  assert.equal(validClientBody('lookup-submission', {connection, submissionRef}), true);
  for (const changed of [{requestId: 'unbound'}, {intentCid: 'invalid'},
    {attemptRef: undefined}, {attemptRef: {operation:'cancel', attemptId:'wrong-operation'}},
    {attemptRef: {operation:'submit', attemptId:''}},
    {submissionRef: {...submissionRef, epoch: {...submissionRef.epoch, expiresAt: 1800000000000}}},
    {submissionRef: {...submissionRef, nonce: 'e\u0301'}}]) {
    assert.equal(validClientBody('submit-intent', {...submitted, ...changed}), false);
  }
  assert.equal(validClientBody('read', {connection, ref,
    resultName: 'answer', format: 'jsonl', attemptId: 'read-a'}), true);
  const description = {connection, ref, resultName: 'answer', format: 'jsonl',
    attemptId: 'metadata-a', maxWireBytes: 1048576, maxNodes: 10000, maxDepth: 64};
  assert.equal(validClientBody('result-describe', description), true);
  for (const invalid of [{format: 'parquet'}, {maxWireBytes: 0},
    {maxNodes: 10001}, {maxDepth: 65}, {extra: true}]) {
    assert.equal(validClientBody('result-describe',
      {...description, ...invalid}), false);
  }
});
