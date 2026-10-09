import assert from 'node:assert/strict';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {checkpointAdmit, checkpointWaitingState} from
  '@actql/run-host-core/checkpoints';
import {checkpointSealBody} from './dist/checkpoint_runtime_node.js';

// Independent request facts, not a physical Effect or approval receipt.
const cid = digit => `sha256:${digit.repeat(64)}`;
const body = {
  version: 'actql-execution-checkpoint/0.1',
  checkpoint_id: 'resident-effect-review', run_id: 'original-run',
  run_definition_cid: cid('1'), continuation_state_cid: cid('2'),
  subject: {kind: 'run_unit', run_id: 'original-run', unit_id: 'compute',
    continuation: 'resume_unit'},
  phase: 'commit', kind: 'effect_set',
  required_artifact: {artifact_type: 'effect_set_preview', artifact_cid: cid('3')},
  review_projection_cid: cid('4'), requirements: ['effect_scope_approved'],
  reason_code: 'effect_review_required', human_summary: 'Update identity 3',
  created_at: '2026-09-25T10:00:00.000Z',
  expires_at: '2026-09-26T10:00:00.000Z',
};
const sealed = JSON.parse(checkpointSealBody(JSON.stringify(body)));
assert.equal(sealed.ok, true);

test('formal checkpoint subpath admits the original Owner wire and rejects a changed identity', () => {
  const admitted = JSON.parse(checkpointAdmit(sealed.checkpoint_wire));
  assert.equal(admitted.ok, true);
  assert.equal(admitted.checkpoint_wire, sealed.checkpoint_wire);
  assert.equal(admitted.run_id, 'original-run');
  assert.equal(admitted.checkpoint_cid, sealed.checkpoint_cid);
  const altered = {...JSON.parse(sealed.checkpoint_wire), run_id: 'another-run'};
  assert.equal(JSON.parse(checkpointAdmit(JSON.stringify(altered))).ok, false);
  assert.equal(JSON.parse(checkpointAdmit('{}')).ok, false);
});

test('waiting is projected only after exact persisted-byte confirmation', () => {
  const at = '2026-09-25T11:00:00.000Z';
  const waiting = JSON.parse(checkpointWaitingState(sealed.checkpoint_wire,
    sealed.checkpoint_wire, at, '["answer"]'));
  assert.equal(waiting.ok, true);
  const state = JSON.parse(waiting.run_state_wire);
  assert.equal(state.run_id, 'original-run');
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(state.checkpoint.checkpoint_cid, sealed.checkpoint_cid);
  const changed = JSON.stringify({...JSON.parse(sealed.checkpoint_wire),
    human_summary: 'Different proposal'});
  const refused = JSON.parse(checkpointWaitingState(sealed.checkpoint_wire,
    changed, at, '["answer"]'));
  assert.equal(refused.ok, false);
  assert.equal(refused.issue, 'PersistedWireMismatch');
});

test('checkpoint subpath bundles for a Worker without Node or Local runtime imports', () => {
  const result = buildSync({stdin: {contents:
    "export {checkpointAdmit, checkpointWaitingState} from '@actql/run-host-core/checkpoints';",
  resolveDir: import.meta.dirname}, bundle: true, write: false,
  platform: 'browser', format: 'esm', target: 'es2022', metafile: true});
  const inputs = Object.keys(result.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/dist/checkpoint_runtime_node.js')));
  assert(inputs.every(path => !path.includes('client_values_host_abi') &&
    !path.includes('local-node') && !path.includes('host-node') &&
    !path.startsWith('node:')));
});
