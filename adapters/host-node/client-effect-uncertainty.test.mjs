// The real Source/Compute/Effect owners write to the shared stateful HTTPS
// provider. It saves the second update and drops only its reply. Expected
// records are independently authored in the existing composition fixture.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import * as sdk from '../../packages/sdk/index.mjs';
import {approveHeldSet, expectedOrgAfterSuccess,
  readComputeEffectInstallation, submitReadComputeEffect, waitFor} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

const expectedExplanation = (ref, revision) => ({
  observation: 'effect_outcome_unknown',
  summary: 'External Effect outcomes are unknown. Computation stop does not establish their outcome or resource release.',
  effects: ['save'],
  physicalStop: 'confirmed',
  controlRevision: revision,
  next: {operation: 'status', ref},
});

const localObservation = path => new Promise((resolve, reject) => {
  execFile(process.execPath, [fileURLToPath(new URL(
    '../../scripts/fixtures/client-effect-uncertainty.child.mjs', import.meta.url)), path],
  {timeout: 30_000}, (error, stdout, stderr) => {
    if (error) { reject(Object.assign(error, {stdout, stderr})); return; }
    try { resolve(JSON.parse(stdout.trim().split('\n').at(-1))); }
    catch (cause) { reject(cause); }
  });
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: unresolved Effect keeps its identity after computation stops`, async t => {
    const setup = await readComputeEffectInstallation(t, {
      org: {loseReplyAfterApply: [2]}});
    const requestId = `effect-uncertain-${entrance}`;
    let observe;
    if (entrance === 'local') {
      // Reuse the existing public Local submission/approval child and its
      // private fixture configuration. Observation has its own thin child.
      const step = await setup.embedded(requestId, setup.program());
      assert.deepEqual(await step('submit'), {held: true});
      assert.deepEqual(await step('answer'), {answered: ['committed']});
      observe = () => localObservation(join(setup.root,
        `embedded-${requestId}.json`));
    } else {
      const first = await setup.openHost();
      const execution = await submitReadComputeEffect(
        await first.as('owner-token'), setup.program(), requestId);
      await waitFor(async () => (await execution.status()).status === 'waiting_checkpoint');
      await first.close();
      const second = await setup.openHost();
      await approveHeldSet(second, execution);
      await second.close();
      observe = async () => {
        const host = await setup.openHost();
        try {
          const attached = await (await host.as('owner-token')).attach(execution.ref);
          const state = await waitFor(async () => {
            const value = await attached.status();
            return value.status === 'needs_reconciliation' ? value : undefined;
          });
          let reconcileError;
          try { await attached.reconcile(); }
          catch (error) { reconcileError = error.code; }
          return {ref: attached.ref, state, reconcileError,
            explanation: sdk.explainEffectUncertainty?.(state),
            copiedExplanation: sdk.explainEffectUncertainty?.({...state})};
        } finally { await host.close(); }
      };
    }
    const first = await observe();
    // Establish the actual Owner/provider facts before testing presentation.
    assert.equal(first.state.status, 'needs_reconciliation');
    assert.deepEqual(first.state.next_action, {kind: 'reconcile', effects: ['save']});
    assert.equal(first.state.control.physical_stop, 'confirmed');
    assert.equal(first.state.result_available, false);
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    // This standard Host has not connected a public reconciliation handler.
    // That missing operation is distinct from knowing an Effect outcome.
    assert.equal(first.reconcileError, 'ClientOperationUnavailable');
    assert.deepEqual(first.explanation,
      expectedExplanation(first.ref, first.state.control.revision),
      '[check-mutation:effect-explanation]');
    assert.equal(first.copiedExplanation, undefined);
    const queries = setup.queries(), reads = setup.targetReads();
    const again = await observe();
    assert.deepEqual(again.ref, first.ref);
    assert.deepEqual(again.explanation, first.explanation,
      '[check-mutation:effect-restart]');
    assert.equal(setup.writes().length, 2, '[check-mutation:effect-no-resend]');
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    assert.equal(setup.queries(), queries);
    assert.equal(setup.targetReads(), reads);
  });
}
