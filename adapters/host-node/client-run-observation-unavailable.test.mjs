import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {inspect} from 'node:util';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram} from './client-read-opening.fixture.mjs';

const expected = (operation, ref) => ({kind: 'unavailable', problem: 'observation_unavailable', operation,
  next: {operation: 'status', ref},
  summary: 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.',
  hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.'});
for (const entrance of ['local', 'https']) {
  test(`${entrance}: unavailable Run observations preserve publication and original lookup`, {timeout: 20000}, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-run-observation-unavailable-', label: `${entrance} original Run observation`});
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key',
      '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
    const fixture = await openReadOpeningFixture(scratch.path);
    const operations = [];
    let allowed = true, lost = false;
    fixture.services.authorizeConnection = facts => {operations.push(facts.operation); return allowed;};
    const host = await connectOpeningHost(fixture, entrance, scratch.path, {
      runObservationReply: answer => lost ? undefined : answer,
    });
    try {
      const submissionRef = host.client.newSubmission({nonce: 'original-observed-run'});
      const run = await host.client.start(openingProgram, {submissionRef});
      const original = await run.status();
      assert.equal(original.status, 'succeeded');
      assert.equal(original.result_available, true);
      const result = run.result('answer');
      const before = {...fixture.counts};
      const retained = [];
      for (const [operation, loss] of [['status', true], ['status', false], ['wait', false], ['reconcile', false]]) {
        lost = loss; allowed = loss;
        let error;
        try {await run[operation]();} catch (failure) {error = failure;}
        await host.settled();
        assert.equal(error instanceof sdk.ClientError, true);
        const view = sdk.explainRunObservationFailure(error);
        assert.deepEqual(view, expected(operation, run.ref), '[check-mutation:run-unavailable-public]');
        assert.equal(error.code, loss ? 'ClientTransportUnknown' : 'ClientConnectionDenied');
        assert.doesNotMatch(inspect({error, view}, {showHidden: true, depth: 8}), /InjectedRunObservationLoss|fixture-token/,
          '[check-mutation:run-unavailable-public-disclosure]');
        const sent = [...operations];
        assert.deepEqual(JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json'})), {
          domain: 'observation', explanation: expected(operation, run.ref),
          presentation: {locale: 'en', translationRevision: '2026-10-09.operations.en.13'},
        }, '[check-mutation:run-format-public]');
        for (const format of ['text', 'html']) {
          const output = sdk.formatRunObservationFailure(error, {format});
          assert.ok(output.includes('observation/unavailable:'));
          assert.ok(output.includes(run.ref.runDefinitionCid));
        }
        const localized = JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json', locale: 'ja'}));
        assert.deepEqual({kind: localized.explanation.kind, problem: localized.explanation.problem,
          operation: localized.explanation.operation, next: localized.explanation.next},
          {kind: 'unavailable', problem: 'observation_unavailable', operation, next: {operation: 'status', ref: run.ref}});
        assert.equal(sdk.formatRunObservationFailure({...error}), undefined);

        error.message = 'Succeeded'; error.kind = 'success'; error.next = {operation: 'submit'};
        assert.deepEqual(sdk.explainRunObservationFailure(error), expected(operation, run.ref));
        assert.equal(sdk.explainRunObservationFailure({...error}), undefined);
        assert.deepEqual(operations, sent);
        assert.equal(original.status, 'succeeded');
        assert.deepEqual(fixture.counts, before, '[check-mutation:run-unavailable-public-passive]');
        retained.push({error, view});
      }
      lost = false; allowed = true;
      assert.deepEqual(await run.status(), original);
      assert.deepEqual(await result.all(), [{id: 1}, {id: 2}]);
      await host.settled();
      assert.equal(fixture.counts.computes, 1);
      assert.equal(fixture.counts.definitions, 1);
      for (const {error, view} of retained) assert.deepEqual(sdk.explainRunObservationFailure(error), view);
      console.log('RUN_OBSERVATION_UNAVAILABLE_EVIDENCE', JSON.stringify({entrance, ref: run.ref,
        publishedStatus: original.status, observations: retained.length, counts: fixture.counts, operations}));
    } finally {await host.close(); await fixture.close();}
    scratch.passed();
  });
}
