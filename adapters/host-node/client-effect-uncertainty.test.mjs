// The real Source/Compute/Effect owners write to the shared stateful HTTPS
// provider. It saves the second update and drops only its reply. Expected
// records are independently authored in the existing composition fixture.
import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
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
  next: {operation: 'reconcile', ref},
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: unresolved Effect keeps its identity after computation stops`, async t => {
    const setup = await readComputeEffectInstallation(t, {
      org: {loseReplyAfterApply: [2]}});
    const requestId = `effect-uncertain-${entrance}`;
    // The provider remains in the parent; each public Host and execution
    // owner live in a child whose exit is observed before the next step.
    const step = await setup.embedded(requestId, setup.program(), {transport: entrance});
    assert.deepEqual(await step('submit'), {held: true});
    assert.equal(setup.writes().length, 0);
    assert.equal(setup.queries(), 1);
    const computationEvents = events => events.filter(event =>
      event.name === 'effect_computation_completed');
    const initialComputation = computationEvents(await step.ownerObservations());
    assert.equal(initialComputation.length, 1,
      'the original Program completes Compute once before approval');
    assert.equal(initialComputation[0].pid, step.processes[0].pid);
    assert.deepEqual(await step('answer'), {answered: ['committed']});
    const resumed = await step('resume');
    // Record physical provider facts before checking the public outcome. A
    // lost reply cannot authorize another write of the original Effect.
    await writeFile(join(setup.root, 'effect-resend-observation.json'),
      JSON.stringify({entrance, expectedWrites: 2, actualWrites: setup.writes().length,
        resumedStatus: resumed.status, sourceQueries: setup.queries(),
        computeCompletions: computationEvents(await step.ownerObservations()).length}),
      {mode: 0o600});
    assert.equal(setup.writes().length, 2, '[check-mutation:effect-no-resend]');
    assert.deepEqual(resumed, {status: 'needs_reconciliation'});
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    const stoppedCounts = {writes: setup.writes().length, queries: setup.queries(), targetReads: setup.targetReads()};
    const originalProcesses = [...step.processes];
    assert.equal(originalProcesses.length, 3);
    // Keep optional trace events outside the strict mutation acceptance path.
    if (process.env.ACTQL_EFFECT_RECONCILIATION_TRACE === '1') {
      t.diagnostic(JSON.stringify({entrance, originalProcesses, fixtureRoot: setup.root}));
    }
    for (const process of originalProcesses) {
      assert.ok(Number.isSafeInteger(process.pid));
      assert.equal(process.exitCode, 0);
      assert.equal(process.signalCode, null);
    }
    const observe = () => step('observe-effect');
    const first = await observe();
    assert.ok(Number.isSafeInteger(first.pid));
    assert.equal(first.transport, entrance);
    assert.equal(first.httpsRequests > 0, entrance === 'https');
    assert.ok(originalProcesses.every(process => process.pid !== first.pid));
    assert.deepEqual({writes: setup.writes().length, queries: setup.queries(), targetReads: setup.targetReads()}, stoppedCounts,
      'original-Run reconciliation cannot resend or reacquire after execution-owner process exit');
    assert.deepEqual(computationEvents(await step.ownerObservations()), initialComputation,
      'the first original-Run reconciliation cannot regenerate Compute');
    if (process.env.ACTQL_EFFECT_RECONCILIATION_TRACE === '1') t.diagnostic(JSON.stringify({ref: first.ref, state: first.state,
      reconciled: first.reconciled, reconcileError: first.reconcileError,
      diagnostics: first.diagnostics}));
    // Establish the actual Owner/provider facts before testing presentation.
    assert.equal(first.state.status, 'needs_reconciliation');
    assert.deepEqual(first.state.next_action, {kind: 'reconcile', effects: ['save']});
    assert.equal(first.state.control.physical_stop, 'confirmed');
    assert.equal(first.state.result_available, false);
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    assert.deepEqual(first.explanation,
      expectedExplanation(first.ref, first.state.control.revision),
      '[check-mutation:effect-explanation]');
    assert.deepEqual(first.japaneseExplanation, {...expectedExplanation(first.ref, first.state.control.revision),
      summary: '外部Effectの結果は未確定です。計算の停止はEffectの結果や資源解放を示しません。'},
    '[check-mutation:operation-effect-public-locale]');
    assert.equal(first.copiedExplanation, undefined);
    assert.equal(first.formats.length, 3);
    for (const output of first.formats) assert.ok(output);
    assert.deepEqual(JSON.parse(first.formats[2]).explanation, first.explanation,
      '[check-mutation:operation-effect-public-format]');
    const queries = setup.queries(), reads = setup.targetReads();
    const again = await observe();
    assert.ok(Number.isSafeInteger(again.pid));
    assert.equal(again.transport, entrance);
    assert.equal(again.httpsRequests > 0, entrance === 'https');
    assert.notEqual(again.pid, first.pid);
    assert.ok(originalProcesses.every(process => process.pid !== again.pid));
    if (process.env.ACTQL_EFFECT_RECONCILIATION_TRACE === '1') t.diagnostic(JSON.stringify({ref: again.ref, state: again.state,
      reconciled: again.reconciled, reconcileError: again.reconcileError,
      diagnostics: again.diagnostics}));
    assert.deepEqual(again.japaneseExplanation, {...expectedExplanation(again.ref, again.state.control.revision),
      summary: '外部Effectの結果は未確定です。計算の停止はEffectの結果や資源解放を示しません。'},
    '[check-mutation:operation-effect-public-restart]');
    assert.deepEqual(again.ref, first.ref);
    assert.deepEqual(JSON.parse(again.formats[2]).explanation, first.explanation,
      '[check-mutation:operation-effect-public-format-restart]');
    assert.deepEqual(again.explanation, first.explanation,
      '[check-mutation:effect-restart]');
    assert.equal(setup.writes().length, 2, '[check-mutation:effect-no-resend]');
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    assert.equal(setup.queries(), queries);
    assert.equal(setup.targetReads(), reads);
    assert.deepEqual(computationEvents(await step.ownerObservations()), initialComputation,
      'repeated original-Run reconciliation cannot regenerate Compute');
    // The original Effect continuation is observation-only. Inconclusive
    // provider evidence must preserve uncertainty, not fail or resend a write.
    // Keep the Local path assertion after the independent no-resend facts,
    // so an Owner failure does not conceal those observations in this case.
    for (const observation of [first, again]) {
      assert.equal(observation.reconcileError, undefined,
        '[check-mutation:effect-reconciliation-path]');
      assert.equal(observation.reconciled.status, 'needs_reconciliation',
        '[check-mutation:effect-reconciliation-state]');
      assert.equal(observation.reconciled.run_id, first.state.run_id);
      assert.deepEqual(observation.reconciled.next_action,
        {kind: 'reconcile', effects: ['save']});
      assert.equal(observation.reconciled.control.physical_stop, 'confirmed');
      assert.equal(observation.reconciled.result_available, false);
      assert.deepEqual(observation.reconciledExplanation,
        expectedExplanation(first.ref, observation.reconciled.control.revision),
        '[check-mutation:effect-reconciliation-explanation]');
    }
  });
}

test('https: stale Effect reconciliation advice does not grant current authority', async t => {
  const setup = await readComputeEffectInstallation(t, {
    org: {loseReplyAfterApply: [2]}});
  const submittedHost = await setup.openHost();
  const submittingClient = await submittedHost.as('owner-token');
  const submissionRef = await setup.persistSubmission(
    submittingClient.newSubmission({nonce: 'effect-current-authority'}));
  const submitted = await submitReadComputeEffect(
    submittingClient, setup.program(), submissionRef);
  await waitFor(async () => (await submitted.status()).status === 'waiting_checkpoint');
  assert.equal(setup.writes().length, 0);
  assert.equal(setup.queries(), 1);
  await submittedHost.close();
  const approvingHost = await setup.openHost();
  await approveHeldSet(approvingHost, submitted);
  await approvingHost.close();

  const observingHost = await setup.openHost();
  let credential = 'owner-token';
  const client = await observingHost.as(() => credential);
  try {
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.submissionRef, submissionRef);
    assert.deepEqual(lookup.admission.ref, submitted.ref);
    const execution = await client.attach(submitted.ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return current.status === 'needs_reconciliation' &&
        current.control?.physical_stop === 'confirmed' ? current : undefined;
    });
    const explanation = sdk.explainEffectUncertainty(state);
    assert.deepEqual(explanation,
      expectedExplanation(execution.ref, state.control.revision));
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    const counts = {writes: setup.writes().length,
      queries: setup.queries(), targetReads: setup.targetReads()};
    const absentRef = {...execution.ref, runDefinitionCid: `sha256:${'0'.repeat(64)}`};
    assert.notEqual(absentRef.runDefinitionCid, execution.ref.runDefinitionCid);

    // The public SDK's credential callback changes the actual authenticated
    // actor at the real Host. The original candidate grants no access.
    for (const [token, code] of [['reviewer-token', 'ClientConnectionDenied'],
      ['unrecognized-token', 'ClientAuthenticationDenied']]) {
      credential = token;
      await assert.rejects(execution.reconcile(), {code});
      // Denied actors cannot distinguish the retained Run from an absent one.
      await assert.rejects(client.attach(execution.ref), {code});
      await assert.rejects(client.attach(absentRef), {code});
      assert.deepEqual(sdk.explainEffectUncertainty(state), explanation);
      assert.deepEqual({writes: setup.writes().length,
        queries: setup.queries(), targetReads: setup.targetReads()}, counts);
    }
    credential = 'owner-token';
    const current = await execution.reconcile();
    assert.deepEqual(sdk.explainEffectUncertainty(current),
      expectedExplanation(execution.ref, current.control.revision));
    assert.equal(current.status, 'needs_reconciliation');
    assert.deepEqual(sdk.explainEffectUncertainty(state), explanation);
    assert.deepEqual({writes: setup.writes().length,
      queries: setup.queries(), targetReads: setup.targetReads()}, counts);
  } finally { await observingHost.close(); }
});
