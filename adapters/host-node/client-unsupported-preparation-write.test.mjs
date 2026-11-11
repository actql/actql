import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as sdk from '../../packages/sdk/index.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {clientHostOperations, validClientBody} from '../../packages/client-wire/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram, openingExpected}
  from './client-read-opening.fixture.mjs';

// These are adversarial names for unexposed writes, not new public APIs or
// proposed response contracts. A valid submit body must not acquire a route
// merely because it is carried under one of these operation names.
const operations = ['supplement-submission', 'respond-submission-checkpoint'];
for (const entrance of ['local', 'https']) {
  for (const operation of operations) {
    test(`${entrance}: unexposed ${operation} cannot admit a submission or Compute`, async () => {
      assert.equal(clientHostOperations.includes(operation), false);
      const scratch = await createOwnedScratch({parent: tmpdir(),
        prefix: 'actql-unsupported-preparation-write-', label: `${entrance} ${operation}`});
      if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey',
        'rsa:2048', '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
      {cwd: scratch.path, stdio: 'ignore'});
      const fixture = await openReadOpeningFixture(scratch.path);
      const host = await connectOpeningHost(fixture, entrance, scratch.path);
      try {
        const submissionRef = host.client.newSubmission({nonce: operation});
        const intent = {kind: 'program', input: openingProgram, parameters: null};
        const intentCid = 'sha256:' + createHash('sha256').update(canonicalJson({
          intent, version: 'actql-submitted-intent/0.1'}, {dataKeys: true})).digest('hex');
        const body = {connection: {mode: entrance === 'local' ? 'local' : 'remote',
          owner: entrance === 'local' ? 'local' : 'remote', consentRefs: [], runners: []},
        submissionRef, attemptRef: {operation: 'submit', attemptId: `unexposed-${operation}`},
        intentCid, ...intent};
        assert.equal(validClientBody('submit-intent', body), true);
        assert.equal(validClientBody(operation, body), false);
        let reply, problem;
        if (entrance === 'local') {
          try {reply = await createNodeInProcessClientHost(fixture.services).perform(operation, body);}
          catch (error) {problem = error.code;}
        } else {
          const response = await fetch(new URL(`actql/client/0.1/${operation}`, host.endpoint), {
            method: 'POST', headers: {'content-type': 'application/json', authorization: 'Bearer fixture-token'},
            body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
          });
          reply = await response.json();
          problem = reply.code;
        }
        await host.settled();
        const database = new DatabaseSync(join(scratch.path, 'requests/client-requests.sqlite3'),
          {readOnly: true});
        let requests, intents;
        try {
          requests = database.prepare('SELECT run_definition_cid, caller_request_id FROM client_requests ORDER BY caller_request_id')
            .all().map(value => ({...value}));
          intents = database.prepare('SELECT nonce, phase FROM client_submitted_intents ORDER BY nonce')
            .all().map(value => ({...value}));
        } finally {database.close();}
        await writeFile(join(scratch.path, 'unsupported-write-observation.json'), JSON.stringify({
          entrance, operation, submissionRef, counts: fixture.counts, requests, intents, reply, problem,
        }), {mode: 0o600});
        assert.deepEqual({...fixture.counts, requests: requests.length, intents: intents.length},
          {admissions: 0, readers: 0, computes: 0, definitions: 0, requests: 0, intents: 0},
          '[check-mutation:unsupported-preparation-no-write]');
        // Codes describe presentation only. The independent durable/physical
        // oracle above, not this code, establishes the test's zero-write fact.
        assert.equal(problem, entrance === 'local' ? 'InvalidClientRequest' : 'UnknownClientOperation');
        assert.equal(sdk.getSubmissionOutcome(reply), undefined);
        // An explicit ordinary SDK submission is still required and passes the
        // existing Owner with the same previously unused identity.
        const run = await host.client.start(openingProgram, {submissionRef});
        assert.equal((await run.status()).status, 'succeeded');
        assert.deepEqual(await run.result('answer').all(), openingExpected);
        assert.equal(fixture.counts.computes, 1);
        assert.equal(fixture.counts.definitions, 1);
        console.error(`Unsupported preparation write evidence: ${scratch.path}`);
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
  }
}
