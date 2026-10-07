import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {admitRunDefinition, privateRunDefinition, sealRunEvidenceValue,
  prepareRunCancellationIdentity, runCancellationIntentCid,
  prepareRunCancellationOperation} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const definition = runId => admitRunDefinition(sealRunEvidenceValue('run_definition',
  JSON.stringify({version: 'actql-run-definition/0.1', scope_id: 'scope-a', run_id: runId,
    compiled_plan_cid: cid('1'), invocation_template_cid: cid('2'),
    authorization_context_cid: cid('3'), input_artifact_set_cid: cid('4'),
    created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z'}),
  {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64}).wire);
const scope = {namespaceId: 'workspace-a', authorityScopeCid: cid('a'),
  cancelId: 'original-cancel', expectedRevision: 19};
const facts = {currentRevision: 19, currentAuthorization: true,
  terminalObserved: false, cancellationRequested: false};

// These are real common-Owner identities and decisions, not physical storage,
// stop observations or Cloud public cancellation acceptance.
test('portable cancellation identity matches its independent exact-value preimage', () => {
  const run = definition('run-a');
  const identity = prepareRunCancellationIdentity(run, scope);
  const preimage = JSON.stringify({authority_scope_cid: scope.authorityScopeCid,
    cancel_id: scope.cancelId, expected_revision: 19, namespace_id: scope.namespaceId,
    operation: 'cancel', run_definition_cid: privateRunDefinition(run).cid,
    version: 'actql-client-host/0.1'});
  assert.equal(runCancellationIntentCid(identity),
    `sha256:${createHash('sha256').update(preimage).digest('hex')}`);
  const composed = prepareRunCancellationIdentity(run, {...scope, cancelId: '\u00e9'});
  const decomposed = prepareRunCancellationIdentity(run, {...scope, cancelId: 'e\u0301'});
  assert.notEqual(runCancellationIntentCid(composed), runCancellationIntentCid(decomposed));
  assert.throws(() => runCancellationIntentCid({kind: 'cancellation-identity'}),
    /ForeignRunHostHandle/u);
});

test('portable cancellation selects first admission and exact saved replay independently', () => {
  const run = definition('run-a');
  const original = prepareRunCancellationIdentity(run, scope);
  assert.equal(prepareRunCancellationOperation(run, original, facts), 'accepted');
  assert.equal(prepareRunCancellationOperation(run, original,
    {...facts, cancellationRequested: true}), 'already_requested');
  assert.equal(prepareRunCancellationOperation(run, original,
    {...facts, terminalObserved: true}), 'already_terminal');
  const restored = prepareRunCancellationIdentity(admitRunDefinition(privateRunDefinition(run).wire), scope);
  assert.equal(prepareRunCancellationOperation(run, restored, {...facts,
    retained: original, currentRevision: 21, terminalObserved: true,
    cancellationRequested: true}), 'replay_original');
  assert.throws(() => prepareRunCancellationOperation(run, restored,
    {...facts, retained: original, currentRevision: 21, currentAuthorization: false}),
  {code: 'ClientCancellationDenied'});
});

test('portable cancellation refuses changed target, revision, operation and foreign Run', () => {
  const run = definition('run-a'), otherRun = definition('run-b');
  const original = prepareRunCancellationIdentity(run, scope);
  for (const [target, requested] of [
    [otherRun, prepareRunCancellationIdentity(otherRun, scope)],
    [run, prepareRunCancellationIdentity(run, {...scope, expectedRevision: 20})],
  ]) {
    assert.throws(() => prepareRunCancellationOperation(target, requested,
      {...facts, retained: original}), {code: 'ClientCancellationIntentConflict'});
  }
  const unrelated = prepareRunCancellationIdentity(run, {...scope, cancelId: 'another-cancel'});
  assert.throws(() => prepareRunCancellationOperation(run, unrelated,
    {...facts, retained: original}), {code: 'ClientCancellationOperationMismatch'});
  assert.throws(() => prepareRunCancellationOperation(otherRun, original, facts),
    {code: 'ClientCancellationRunMismatch'});
  assert.throws(() => prepareRunCancellationOperation(run, original,
    {...facts, currentRevision: 20}), {code: 'ClientCancellationRevisionConflict'});
  const overflow = prepareRunCancellationIdentity(run, {...scope, expectedRevision: 2147483647});
  assert.throws(() => prepareRunCancellationOperation(run, overflow,
    {...facts, currentRevision: 2147483647}), {code: 'ClientCancellationRevisionConflict'});
});

test('portable cancellation refuses invalid public inputs before owner admission', () => {
  const run = definition('run-a'), original = prepareRunCancellationIdentity(run, scope);
  for (const expectedRevision of [-1, 1.5, 2147483648, NaN]) {
    assert.throws(() => prepareRunCancellationIdentity(run,
      {...scope, expectedRevision}), /InvalidRunCancellationIdentity/u);
  }
  assert.throws(() => prepareRunCancellationIdentity(run, {...scope, cancelId: ''}),
    {code: 'RunHostCancellationIdentityRejected'});
  for (const currentRevision of [-1, 1.5, 2147483648]) {
    assert.throws(() => prepareRunCancellationOperation(run, original,
      {...facts, currentRevision}), /InvalidRunCancellationOperation/u);
  }
  assert.throws(() => prepareRunCancellationOperation(run, original,
    {...facts, retained: {kind: 'cancellation-identity'}}), /ForeignRunHostHandle/u);
  assert.throws(() => prepareRunCancellationOperation(run, original,
    {...facts, currentAuthorization: 'true'}), /InvalidRunCancellationOperation/u);
});
