import assert from 'node:assert/strict';
import test from 'node:test';
import {modelCheckpointMetadata} from './model-checkpoint-metadata.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const view = {kind: 'model_invocation', prepareAttemptId: null,
  phase: 'preflight', checkpointCid: cid('1'), runId: 'original-run',
  runDefinitionCid: cid('2'), reviewProjectionCid: cid('3'),
  requiredArtifact: {type: 'model_invocation_scope', cid: cid('4')}};
const identity = {checkpointCid: cid('1'), runId: 'original-run',
  runDefinitionCid: cid('2'), reviewProjectionCid: cid('3'),
  scopeCid: cid('4'), preparedInvocationCid: cid('5')};
// This is a projection test. Real original admission is tested at the journal
// and common runtime boundary, rather than being imitated by this fake port.
const journal = answer => ({modelCheckpointSummary(checkpointCid) {
  assert.equal(checkpointCid, cid('1'));
  return answer;
}});

test('Model summary exposes the original prepared identity, not the scope alias', () => {
  const result = modelCheckpointMetadata(journal(identity), view);
  assert.deepEqual(result, {preparedInvocationCid: cid('5')});
  assert.notEqual(result.preparedInvocationCid, view.requiredArtifact.cid);
  assert.equal(Object.isFrozen(result), true);
});

for (const field of ['checkpointCid', 'runId', 'runDefinitionCid',
  'reviewProjectionCid', 'scopeCid', 'preparedInvocationCid']) {
  test(`Model summary rejects mismatched checked ${field}`, () => {
    assert.throws(() => modelCheckpointMetadata(journal({...identity,
      [field]: 'substituted'}), view), {code: 'InvalidModelCheckpointMetadata'});
  });
}

test('Model summary refuses missing or unsupported checked metadata', () => {
  for (const input of [undefined, null, {}]) {
    assert.throws(() => modelCheckpointMetadata(journal(input), view),
      {code: 'InvalidModelCheckpointMetadata'});
  }
  assert.throws(() => modelCheckpointMetadata({}, view),
    {code: 'InvalidModelCheckpointMetadata'});
  assert.throws(() => modelCheckpointMetadata(journal(identity),
    {...view, prepareAttemptId: 'another-subject'}),
  {code: 'InvalidModelCheckpointMetadata'});
});

test('other Checkpoint summaries never consult or expose Model metadata', () => {
  const unreadable = {modelCheckpointSummary() { throw new Error('UnexpectedRead'); }};
  for (const kind of ['read_access', 'run_scope', 'effect_set', 'cost_scope', 'data_egress']) {
    assert.deepEqual(modelCheckpointMetadata(unreadable, {...view, kind}), {});
  }
});
