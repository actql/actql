import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram, openingExpected}
  from './client-read-opening.fixture.mjs';

for (const entrance of ['local', 'https']) {
  for (const phase of ['ready', 'not_accepted']) {
    test(`${entrance}: changed Program cannot rebind a ${phase} submission identity`, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(),
        prefix: 'actql-submission-intent-immutable-', label: `${entrance} ${phase}`});
      if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey',
        'rsa:2048', '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
      {cwd: scratch.path, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(scratch.path);
      const host = await connectOpeningHost(fixture, entrance, scratch.path);
      try {
        const submissionRef = host.client.newSubmission({nonce: `immutable-${phase}`});
        const original = structuredClone(openingProgram);
        if (phase === 'not_accepted') original.stages[0].steps[0].values.rows[0].id = 'wrong';
        let originalRun, originalFailure;
        try {originalRun = await host.client.start(original, {submissionRef});}
        catch (error) {originalFailure = error;}
        const originalOutcome = sdk.getSubmissionOutcome(originalRun ?? originalFailure);
        assert.equal(originalOutcome.kind, phase);
        if (phase === 'ready') {
          assert.equal((await originalRun.status()).status, 'succeeded');
          assert.deepEqual(await originalRun.result('answer').all(), openingExpected);
        } else assert.equal(originalRun, undefined);
        const originalInput = sdk.getSubmissionInput(originalRun ?? originalFailure);
        assert.deepEqual(originalInput.input, original);
        const database = new DatabaseSync(join(scratch.path, 'requests/client-requests.sqlite3'),
          {readOnly: true});
        const records = () => ({
          intents: database.prepare('SELECT * FROM client_submitted_intents ORDER BY submission_id')
            .all().map(value => ({...value})),
          requests: database.prepare('SELECT * FROM client_requests ORDER BY caller_request_id')
            .all().map(value => ({...value})),
        });
        try {
          const before = records();
          assert.equal(before.intents.length, 1);
          assert.equal(before.intents[0].phase, phase);
          const expectedComputes = phase === 'ready' ? 1 : 0;
          assert.equal(before.requests.length, expectedComputes);
          const changed = structuredClone(openingProgram);
          changed.stages[0].steps[0].values.rows[0].id = 20;
          let returnedRun, failure;
          try {returnedRun = await host.client.start(changed, {submissionRef});}
          catch (error) {failure = error;}
          await host.settled();
          const after = records();
          // Compare exact immutable records before interpreting the response.
          // An actual Run may be returned for the wrong bound input without
          // increasing Compute when the original Run was already published.
          await writeFile(join(scratch.path, 'changed-intent-observation.json'), JSON.stringify({
            entrance, phase, submissionRef, original, changed, originalOutcome,
            before, after, counts: fixture.counts, returnedRef: returnedRun?.ref,
            returnedOutcome: sdk.getSubmissionOutcome(returnedRun), failureCode: failure?.code,
          }), {mode: 0o600});
          assert.deepEqual({returnedRun: returnedRun !== undefined,
            intentsUnchanged: JSON.stringify(after.intents) === JSON.stringify(before.intents),
            requestsUnchanged: JSON.stringify(after.requests) === JSON.stringify(before.requests),
            computes: fixture.counts.computes, definitions: fixture.counts.definitions},
          {returnedRun: false, intentsUnchanged: true, requestsUnchanged: true,
            computes: expectedComputes, definitions: expectedComputes},
          '[check-mutation:submission-intent-immutable]');
          // Current wire lacks typed Conflict; generic dispatched failures
          // remain Unknown rather than deriving authority from their codes.
          assert.equal(failure.code, 'SubmissionUnknown');
          assert.deepEqual(sdk.getSubmissionInput(failure).input, changed);
          assert.deepEqual(sdk.getSubmissionInput(failure).submissionRef, submissionRef);
          assert.equal(sdk.getSubmissionOutcome(failure), undefined);
          assert.equal(sdk.explainSubmission(failure).observation, 'acceptance_unknown');
          assert.deepEqual(sdk.getSubmissionInput(originalRun ?? originalFailure), originalInput);
          assert.deepEqual(await host.client.lookupSubmission(submissionRef), originalOutcome);
          assert.deepEqual(records(), before);
          assert.equal(fixture.counts.computes, expectedComputes);
          console.error(`Changed-intent evidence retained: ${scratch.path}`);
        } finally {database.close();}
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
  }
}
