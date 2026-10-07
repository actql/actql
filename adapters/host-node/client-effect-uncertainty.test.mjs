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
  next: {operation: 'reconcile', ref},
});

const localObservation = path => new Promise((resolve, reject) => {
  execFile(process.execPath, [fileURLToPath(new URL(
    '../../scripts/fixtures/client-effect-uncertainty.child.mjs', import.meta.url)), path],
  {timeout: 30_000}, (error, stdout, stderr) => {
    if (error) {
      const progress = stderr.split(/\r?\n/u)
        .filter(line => line.startsWith('ACTQL_EFFECT_OBSERVATION_PROGRESS ')).join('\n');
      error.message += '\nChild process outcome: ' + JSON.stringify({code: error.code,
        signal: error.signal, killed: error.killed}) + '\n' + progress;
      reject(Object.assign(error, {stdout, stderr})); return;
    }
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
      assert.equal(setup.writes().length, 0);
      assert.equal(setup.queries(), 1);
      assert.deepEqual(await step('answer'), {answered: ['committed']});
      assert.deepEqual(await step('resume'), {status: 'needs_reconciliation'});
      observe = () => localObservation(join(setup.root,
        `embedded-${requestId}.json`));
    } else {
      const first = await setup.openHost();
      const client = await first.as('owner-token');
      const submissionRef = await setup.persistSubmission(client.newSubmission({nonce: requestId}));
      const execution = await submitReadComputeEffect(
        client, setup.program(), submissionRef);
      await waitFor(async () => (await execution.status()).status === 'waiting_checkpoint');
      assert.equal(setup.writes().length, 0);
      assert.equal(setup.queries(), 1);
      await first.close();
      const second = await setup.openHost();
      await approveHeldSet(second, execution);
      await second.close();
      observe = async () => {
        const host = await setup.openHost();
        try {
          const client = await host.as('owner-token');
          const lookup = await client.lookupSubmission(submissionRef);
          assert.equal(lookup.kind, 'ready');
          assert.deepEqual(lookup.submissionRef, submissionRef);
          assert.deepEqual(lookup.admission.ref, execution.ref);
          const attached = await client.attach(lookup.admission.ref);
          const state = await waitFor(async () => {
            const value = await attached.status();
            return value.status === 'needs_reconciliation' && value.control?.physical_stop === 'confirmed' ? value : undefined;
          });
          let reconcileError;
          let reconciled;
          try { reconciled = await attached.reconcile(); }
          catch (error) { reconcileError = error.code; }
          return {ref: attached.ref, state, reconcileError, reconciled,
            diagnostics: host.diagnostics.map(({name, detail}) => ({name, code: detail?.code})),
            reconciledExplanation: sdk.explainEffectUncertainty?.(reconciled),
            explanation: sdk.explainEffectUncertainty?.(state),
            japaneseExplanation: sdk.explainEffectUncertainty?.(state, {locale: 'ja'}),
            copiedExplanation: sdk.explainEffectUncertainty?.({...state}),
            formats: ['text', 'html', 'json'].map(format => sdk.formatEffectUncertainty(state, {format}))};
        } finally { await host.close(); }
      };
    }
    const first = await observe();
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
