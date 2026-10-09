import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram} from './client-read-opening.fixture.mjs';
import {loseRequestRecord} from './client-request-record-loss.fixture.mjs';

for (const entrance of ['local', 'https']) {
  test(`${entrance}: missing submission record preserves uncertainty despite an already published Run`,
    {timeout: 20000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-request-record-loss-',
        label: `${entrance} actual published request record loss`});
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(scratch.path);
      const host = await connectOpeningHost(fixture, entrance, scratch.path);
      try {
        const submissionRef = host.client.newSubmission({nonce: 'original-request'});
        const run = await host.client.start(openingProgram, {submissionRef});
        const originalInput = sdk.getSubmissionInput(run);
        const before = await host.client.lookupRequest('original-request');
        assert.equal(before.kind, 'found');
        assert.deepEqual(before.ref, run.ref);
        assert.equal((await run.status()).status, 'succeeded');
        const record = await loseRequestRecord(scratch.path, 'original-request');
        assert.equal(record.run_definition_cid, run.ref.runDefinitionCid);
        assert.equal(record.caller_request_id, 'original-request');
        const absent = await host.client.lookupRequest('original-request');
        assert.deepEqual(absent, {kind: 'not_found'});
        const explanation = sdk.explainRequestLookup(absent);
        assert.equal(explanation.observation, 'lookup_unresolved', '[check-mutation:request-record-loss-kind]');
        assert.deepEqual(explanation, {
          observation: 'lookup_unresolved',
          summary: 'This lookup does not establish whether the submission was accepted.',
          hint: 'Keep the original request reference and use an authorized lookup. This observation grants no permission to resubmit, execute, answer a Checkpoint or release resources.',
          next: {operation: 'lookupRequest', requestId: 'original-request',
            lookupContext: {endpoint: host.endpoint, scopeRef: 'principal'}},
        }, '[check-mutation:request-record-loss-advice]');
        for (const format of ['text', 'html', 'json']) {
          const output = sdk.formatRequestLookup(absent, {format});
          assert.ok(output);
          assert.doesNotMatch(output, /fixture-token/);
          if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, explanation);
        }
        assert.equal(sdk.explainRequestLookup({...absent}), undefined);
        assert.equal(sdk.getSubmissionInput(run), originalInput);
        assert.equal(sdk.getSubmissionInput(absent), undefined);
        assert.deepEqual(fixture.counts, {admissions: 0, readers: 0, computes: 1, definitions: 1},
          '[check-mutation:request-record-loss-passive]');
        // The publication owner still knows this completed Run and Result.
        // Missing request metadata cannot undo that independent observation.
        assert.equal((await run.status()).status, 'succeeded');
        assert.deepEqual(await run.result('answer').all(), [{id: 1}, {id: 2}]);
        await host.settled();
        assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
        assert.deepEqual(await host.client.lookupRequest('original-request'), absent);
        fixture.authorize(false);
        await assert.rejects(host.client.lookupRequest('original-request'), {code: 'ClientRequestLookupDenied'});
        assert.deepEqual(sdk.explainRequestLookup(absent), explanation);
        assert.equal(sdk.getSubmissionInput(run), originalInput);
        assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
        console.log('REQUEST_RECORD_LOSS_EVIDENCE', JSON.stringify({entrance, ref: run.ref,
          originalRecord: record, lookup: absent, explanation, counts: fixture.counts}));
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
}
