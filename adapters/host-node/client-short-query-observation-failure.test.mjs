import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {inspect} from 'node:util';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const expected = ref => ({kind: 'unavailable', problem: 'observation_unavailable', operation: 'wait',
  next: {operation: 'status', ref},
  summary: 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.',
  hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.'});
for (const entrance of ['local', 'https']) {
  for (const language of ['sql', 'aql']) {
    test(`${entrance}/${language}: short query observation failure preserves the original published Run without retry`,
      {timeout: 20000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-short-query-observation-',
          label: `${entrance}/${language} original short query`});
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key',
          '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
        const fixture = await openReadOpeningFixture(scratch.path, undefined,
          {expectedRowCount: 1, expressionFragment: true});
        const operations = [];
        let allowWait = false;
        fixture.services.authorizeConnection = facts => {
          operations.push(facts.operation);
          return facts.operation !== 'wait' || allowWait;
        };
        const host = await connectOpeningHost(fixture, entrance, scratch.path);
        try {
          const text = 'SELECT 1 AS id';
          const query = host.client[language](text, undefined, {submissionRef: host.client.newSubmission({nonce: `original-query-${language}`})});
          let error;
          try {await query;} catch (value) {error = value;}
          await host.settled();
          assert.equal(error instanceof sdk.ClientError, true);
          assert.equal(error.code, 'QueryObservationUnknown');
          assert.equal(error.cause.code, 'ClientConnectionDenied');
          const ref = error.execution.ref;
          const view = expected(ref);
          assert.deepEqual(sdk.explainRunObservationFailure(error), view,
            '[check-mutation:query-run-public]');
          assert.deepEqual(sdk.getSubmissionInput(error)?.input,
            {text, format: language === 'sql' ? 'sql' : 'aql-text'}, '[check-mutation:query-input-public]');
          assert.equal(sdk.getSubmissionInput(error).requestId, query.requestId);
          assert.deepEqual(fixture.counts, {admissions: 0, readers: 0, computes: 1, definitions: 1});
          const sent = [...operations];
          assert.deepEqual(JSON.parse(sdk.formatRunObservationFailure(error, {format: 'json'})).explanation, view);
          for (const format of ['text', 'html']) {
            const display = sdk.formatRunObservationFailure(error, {format});
            assert.ok(display.includes('observation/unavailable:'));
            assert.ok(display.includes(ref.runDefinitionCid));
          }
          assert.equal(sdk.explainRunObservationFailure({...error}), undefined);
          assert.equal(sdk.getSubmissionInput({...error}), undefined);
          assert.equal(sdk.formatRunObservationFailure(structuredClone(error)), undefined);
          assert.doesNotMatch(inspect({error, view}, {showHidden: true, depth: 8}), /fixture-token/);
          await assert.rejects(query, value => value === error);
          await assert.rejects(query.all(), value => value === error);
          assert.deepEqual(operations, sent, '[check-mutation:query-public-passive]');
          allowWait = true;
          const state = await error.execution.status();
          assert.equal(state.status, 'succeeded');
          assert.equal(state.result_available, true);
          assert.deepEqual(await error.execution.result('main').all(), [{id: 1}]);
          await host.settled();
          assert.equal(fixture.counts.computes, 1);
          assert.equal(fixture.counts.definitions, 1);
          assert.deepEqual(sdk.explainRunObservationFailure(error), view);
          console.log('SHORT_QUERY_OBSERVATION_EVIDENCE', JSON.stringify({entrance, language,
            ref, requestId: query.requestId, publishedStatus: state.status, counts: fixture.counts, operations}));
        } finally {await host.close(); await fixture.close();}
        scratch.passed();
      });
  }
}
