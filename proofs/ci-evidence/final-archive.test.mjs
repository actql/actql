import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {protectedRegistrationRevision} from './actions.mjs';
import {hash} from './inputs.mjs';
import {verifyCurrentFamily} from './final.mjs';
import {sealAcceptance} from './acceptance.mjs';
import {storedArchive} from './archive-fixture.mjs';
import {archiveFixture, jsonBytes} from './final-archive-fixture.mjs';

test('real ZIP consumer reconstructs actual Git and the executed complete certificate while retaining open boundaries', async t => {
  const f = await archiveFixture(t), result = await verifyCurrentFamily(f.options);
  assert.deepEqual(result.requiredActions, f.catalog.actions.map(action => action.id));
  assert.equal(result.protectedRevision, protectedRegistrationRevision);
  assert(result.applications.every(value => value.acquisition === 'fresh'));
  assert.equal(result.lean.accepted, true); assert.equal(result.comparison.confirmation.status, 'not-compared');
  assert.equal(result.comparison.reuseAuthorized, false);
  assert.equal(result.sourceArtifactBytes, f.original.length);
  assert.equal(result.costObservation.actions.length, 30);
  assert.deepEqual(result.costObservation.producerOwner, {runId: 3, runAttempt: 4, jobId: 5});
  assert(f.requests.filter(path => path === '/actions/runs/3').length >= 3);
  const {acceptanceInputs, ...acceptedResult} = result;
  const acceptance = sealAcceptance({result: acceptedResult, observations: acceptanceInputs.observations, event: 'workflow_dispatch', branch: 'main',
    owner: {runId: 3, runAttempt: 4, jobId: 7}, sourceArtifact: {id: 6, digest: hash(f.original)},
    certificateDigest: hash(f.members.get('checked.json'))});
  assert.deepEqual(acceptance.ready, [], 'Fixture success and an open/missing comparison cannot authorize reuse');

  f.job.conclusion = 'failure';
  await assert.rejects(verifyCurrentFamily(f.options), {name: 'AssertionError', actual: 'failure', expected: 'success'}); f.job.conclusion = 'success';
  f.run.run_attempt++;
  await assert.rejects(verifyCurrentFamily(f.options), {name: 'AssertionError', actual: 5, expected: 4}); f.run.run_attempt--;
  f.artifact.digest = `sha256:${'e'.repeat(64)}`;
  await assert.rejects(verifyCurrentFamily(f.options), /archive digest mismatch/u); f.artifact.digest = `sha256:${hash(f.original)}`;

  // Rebind transport to changed real ZIP bytes: deeper semantic validation
  // must refuse even when the independent API digest matches that new archive.
  for (const [change, refusal] of [
    [members => members.delete('receipts/events-connection-native.json'), /Artifact ZIP member not found/u],
    [members => members.set('lean-output.log', Buffer.from('changed actual certificate output')), /Changed Lean output/u],
    [members => {
      const state = JSON.parse(members.get('context.json'));
      state.actionRuntimes['mutations-js'].unresolved = [];
      members.set('context.json', jsonBytes(state));
    }, /Wrong isolated runtime inputs or erased residual/u],
  ]) {
    const members = new Map(f.members); change(members);
    const bytes = storedArchive(members), digest = hash(bytes);
    await writeFile(f.options.archive, bytes); f.artifact.digest = `sha256:${digest}`; f.artifact.size_in_bytes = bytes.length;
    await assert.rejects(verifyCurrentFamily({...f.options, expectedDigest: digest}), refusal);
  }
});
