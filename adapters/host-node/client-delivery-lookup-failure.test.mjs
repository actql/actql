import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {inspect} from 'node:util';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram} from './client-read-opening.fixture.mjs';

const expectedSummaries = {
  lookup_unavailable: 'The DeliveryAttempt lookup could not be completed. Read opening and delivery remain unresolved.',
  lookup_uninterpretable: 'This SDK could not interpret the DeliveryAttempt lookup response. Read opening and delivery remain unresolved.',
};
const hint = 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.';
for (const entrance of ['local', 'https']) {
  test(`${entrance}: rejected Delivery lookups preserve original read custody and published Run`,
    {timeout: 20000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-delivery-lookup-failure-', label: `${entrance} original read lookup`});
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(scratch.path);
      const operations = [];
      const authorize = fixture.services.authorizeConnection;
      fixture.services.authorizeConnection = facts => {operations.push(facts.operation); return authorize(facts);};
      let fault;
      const host = await connectOpeningHost(fixture, entrance, scratch.path, {deliveryLookupReply(answer) {
        if (fault === 'lost') return undefined;
        if (fault === 'future') return {kind: 'private-future-success'};
        if (fault === 'malformed') return {...answer, hostReleaseReceipt: null};
        if (fault === 'foreign') return {...answer, attempt: {...answer.attempt, attempt_id: 'private-other-attempt'}};
        if (fault === 'wire') return 'private-result-secret';
        return answer;
      }});
      try {
        const run = await host.client.start(openingProgram,
          {submissionRef: host.client.newSubmission({nonce: 'delivery-lookup-failure-run'})});
        const result = run.result('answer'), reader = result.rows();
        assert.deepEqual(await Array.fromAsync(reader), [{id: 1}, {id: 2}]);
        await host.settled();
        const original = await result.deliveryAttempt(reader.attemptId);
        const admitted = sdk.explainDeliveryAttempt(original);
        assert.equal(admitted.observation, 'host_delivery_succeeded');
        const retained = [];
        for (fault of [...['lost', 'future', 'malformed', 'foreign'], ...(entrance === 'https' ? ['wire'] : [])]) {
          let failure;
          try {await result.deliveryAttempt(reader.attemptId);} catch (error) {failure = error;}
          await host.settled();
          assert.equal(failure instanceof sdk.ClientError, true);
          const observation = fault === 'lost' ? 'lookup_unavailable' : 'lookup_uninterpretable';
          const expected = {observation, summary: expectedSummaries[observation], hint,
            next: {operation: 'deliveryAttempt', ref: run.ref, resultName: 'answer', attemptId: reader.attemptId,
              lookupContext: {endpoint: host.endpoint, scopeRef: 'principal'}}};
          assert.deepEqual(sdk.explainDeliveryAttempt(failure), expected, '[check-mutation:delivery-lookup-public-facts]');
          assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-result-secret|private-other-attempt|private-future|InjectedDeliveryLookupLoss/,
            '[check-mutation:delivery-lookup-public-disclosure]');
          const before = [...operations];
          failure.code = 'Succeeded'; failure.message = 'Run failed'; failure.attemptId = 'edited';
          for (const format of ['text', 'html', 'json']) {
            const output = sdk.formatDeliveryAttempt(failure, {format});
            assert.ok(output);
            assert.doesNotMatch(output, /private-|fixture-token|edited|Run failed/);
            if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected);
          }
          assert.equal(sdk.explainDeliveryAttempt({...failure}), undefined);
          assert.deepEqual(sdk.explainDeliveryAttempt(original), admitted);
          assert.deepEqual(operations, before);
          assert.equal(reader.state(), 'complete');
          assert.equal((await run.status()).status, 'succeeded');
          assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1},
            '[check-mutation:delivery-lookup-public-passive]');
          retained.push({failure, expected});
        }
        fault = undefined;
        fixture.authorize(false);
        let denied;
        try {await result.deliveryAttempt(reader.attemptId);} catch (error) {denied = error;}
        assert.equal(sdk.explainDeliveryAttempt(denied).observation, 'lookup_unavailable');
        assert.equal(sdk.explainDeliveryAttempt(denied).next.attemptId, reader.attemptId);
        fixture.authorize(true);
        assert.deepEqual(await result.deliveryAttempt(reader.attemptId), original);
        for (const {failure, expected} of retained) assert.deepEqual(sdk.explainDeliveryAttempt(failure), expected);
        assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
        console.log('DELIVERY_LOOKUP_FAILURE_EVIDENCE', JSON.stringify({entrance, ref: run.ref,
          attemptId: reader.attemptId, faults: retained.length, counts: fixture.counts, operations}));
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
}
