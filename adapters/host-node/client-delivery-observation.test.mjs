import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram}
  from './client-read-opening.fixture.mjs';

const expected = {
  normal: ['host_delivery_succeeded', 'The Host confirmed this Delivery and issued its release receipt.'],
  'before-commit': ['lookup_unresolved', 'This lookup found no DeliveryAttempt; whether the read opened remains unresolved.'],
  'after-commit': ['attempt_recorded', 'The Host recorded this DeliveryAttempt; no delivery outcome is available yet.'],
};
const hint = 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.';

for (const entrance of ['local', 'https']) {
  for (const phase of ['normal', 'before-commit', 'after-commit']) {
    test(`${entrance}: delivery observation explains ${phase} against one published Run`, {timeout: 20000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-delivery-observation-', label: `${entrance} ${phase}`});
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(scratch.path);
      const operations = [];
      fixture.services.authorizeConnection = facts => {
        operations.push(facts.operation);
        return true;
      };
      const host = await connectOpeningHost(fixture, entrance, scratch.path);
      try {
        const run = await host.client.start(openingProgram, {requestId: 'delivery-observation-run'});
        assert.equal((await run.status()).status, 'succeeded');
        const result = run.result('answer');
        if (phase !== 'normal') fixture.arm(phase);
        const reader = result.rows();
        const returned = [];
        let failure;
        try {for await (const row of reader) returned.push(row);} catch (error) {failure = error;}
        await host.settled();
        assert.deepEqual(returned, phase === 'normal' ? [{id: 1}, {id: 2}] : []);
        assert.equal(reader.state(), phase === 'normal' ? 'complete' : 'open_unknown');
        if (phase !== 'normal') {
          assert.equal(failure.attemptId, reader.attemptId);
          const opening = sdk.explainReadFailure(failure);
          assert.equal(opening.observation, 'read_open_unknown', '[check-mutation:delivery-opening-explanation]');
          assert.equal(opening.rowsYielded, 0);
          assert.equal(opening.summary, 'Opening this read could not be confirmed. The DeliveryAttempt may already have been recorded.');
          failure.code = 'Succeeded'; failure.message = 'success';
          assert.deepEqual(sdk.explainReadFailure(failure), opening);
          assert.equal(sdk.explainReadFailure({...failure}), undefined);
        }
        const lookup = await result.deliveryAttempt(reader.attemptId);
        const before = [...operations];
        assert.equal(typeof sdk.explainDeliveryAttempt, 'function', '[check-mutation:delivery-observation-classification]');
        const explanation = sdk.explainDeliveryAttempt(lookup);
        assert.equal(explanation.observation, expected[phase][0], '[check-mutation:delivery-observation-classification]');
        assert.equal(explanation.summary, expected[phase][1]);
        assert.equal(explanation.hint, hint);
        assert.deepEqual(explanation.next, {operation: 'deliveryAttempt', ref: run.ref,
          resultName: 'answer', attemptId: reader.attemptId,
          lookupContext: {endpoint: host.endpoint, scopeRef: 'principal'}}, '[check-mutation:delivery-observation-reference]');
        if (phase === 'normal') {
          assert.equal(explanation.hostConfirmedByteCount, 18);
          assert.equal(explanation.recordSequence, 1);
          assert.equal(explanation.exposure, 'exact');
          assert.equal(explanation.hostReleaseReceiptCid, lookup.hostReleaseReceipt.result_delivery_receipt_cid,
            '[check-mutation:delivery-observation-receipt]');
          assert.equal(explanation.deliveredSha256,
            createHash('sha256').update('{"id":1}\n{"id":2}\n').digest('hex'));
        } else {
          assert.equal(Object.hasOwn(explanation, 'hostReleaseReceiptCid'), false);
          assert.equal(Object.hasOwn(explanation, 'hostConfirmedByteCount'), false);
        }
        for (const forbidden of ['rowsYielded', 'runStatus', 'stopped', 'cleanupComplete', 'applicationPersisted', 'permission', 'grantUses']) {
          assert.equal(Object.hasOwn(explanation, forbidden), false);
        }
        assert.equal(Object.isFrozen(explanation.next.ref), true);
        assert.equal(sdk.explainDeliveryAttempt(structuredClone(lookup)), undefined,
          '[check-mutation:delivery-observation-custody]');
        assert.equal(sdk.explainDeliveryAttempt(new sdk.ClientError('Succeeded')), undefined);
        for (const locale of ['en', 'ja']) {
          for (const format of ['text', 'html', 'json']) {
            const output = sdk.formatDeliveryAttempt(lookup, {format, locale});
            assert.ok(output);
            assert.doesNotMatch(output, /fixture-token|InjectedOpeningReplyLoss/u);
            if (format === 'json') {
              const displayed = JSON.parse(output).explanation;
              const {summary, hint: translatedHint, ...facts} = displayed;
              const {summary: english, hint: englishHint, ...originalFacts} = explanation;
              assert.deepEqual(facts, originalFacts, '[check-mutation:delivery-observation-format]');
              if (locale === 'ja') {assert.notEqual(summary, english); assert.notEqual(translatedHint, englishHint);}
            }
          }
        }
        assert.equal(sdk.formatDeliveryAttempt({...lookup}), undefined);
        assert.equal(sdk.explainDeliveryAttempt(lookup, {get locale() {throw new Error('private-locale');}}), explanation);
        assert.deepEqual(operations, before, '[check-mutation:delivery-observation-passive]');
        assert.deepEqual(fixture.counts, {admissions: 1, readers: phase === 'normal' ? 1 : 0, computes: 1, definitions: 1});
        fixture.authorize(false);
        await assert.rejects(result.deliveryAttempt(reader.attemptId));
        fixture.authorize(true);
        assert.equal((await run.status()).status, 'succeeded');
        console.log('DELIVERY_OBSERVATION_EVIDENCE', JSON.stringify({entrance, phase, ref: run.ref,
          attemptId: reader.attemptId, observation: explanation.observation, counts: fixture.counts}));
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
  }
}
