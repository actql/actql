import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram} from './client-read-opening.fixture.mjs';
import {attemptBytes} from './client-read-run-capacity.fixture.mjs';

// Fixed independently of the delivery decoder and SDK explanations.
const expected = [{id: 1}, {id: 2}];

for (const entrance of ['local', 'https']) {
  for (const consumer of ['rows', 'all']) {
    test(`${entrance}: ${consumer} remains incomplete after all published rows when the terminator is lost`,
      {timeout: 20000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(),
          prefix: 'actql-read-terminator-', label: `${entrance} published terminator loss`});
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
        {cwd: scratch.path, stdio: 'ignore'});
        const fixture = await openReadOpeningFixture(scratch.path);
        const host = await connectOpeningHost(fixture, entrance, scratch.path, {loseReadTerminator: true});
        try {
          const submissionRef = host.client.newSubmission({nonce: 'terminator-run'});
          const run = await host.client.start(openingProgram, {submissionRef});
          const result = run.result('answer');
          assert.equal((await run.status()).status, 'succeeded');
          const reader = consumer === 'rows' ? result.rows() : undefined;
          const seen = [];
          let failure;
          try {
            if (reader) for await (const row of reader) seen.push(row);
            else seen.push(...await result.all());
          } catch (error) {failure = error;}
          await host.settled();
          assert.equal(host.terminatorLosses(), 1);
          assert.equal(failure instanceof sdk.ClientError, true, '[check-mutation:read-terminator-failure]');
          assert.deepEqual(seen, consumer === 'rows' ? expected : [], '[check-mutation:read-terminator-value]');
          const count = consumer === 'rows' ? 2 : 0;
          assert.equal(failure.rowsYielded, count);
          if (reader) {
            assert.equal(reader.rowsYielded(), 2);
            assert.equal(reader.state(), 'prefix', '[check-mutation:read-terminator-state]');
            assert.equal(failure.attemptId, reader.attemptId);
          }
          const explanation = sdk.explainReadFailure(failure);
          const {cleanup, ...facts} = explanation;
          assert.ok(cleanup === undefined || cleanup === 'unknown');
          assert.deepEqual(facts, {
            observation: 'read_incomplete', attemptId: failure.attemptId, rowsYielded: count,
            summary: `This read stopped after returning ${count} rows.`,
            hint: 'Keep this read reference. Look it up before deciding whether to open a new read from the beginning.',
            next: {operation: 'deliveryAttempt', ref: run.ref, resultName: 'answer', attemptId: failure.attemptId,
              lookupContext: {endpoint: host.endpoint, scopeRef: 'principal'}},
          }, '[check-mutation:read-terminator-facts]');
          const before = {...fixture.counts};
          for (const format of ['text', 'html', 'json']) {
            const output = sdk.formatReadFailure(failure, {format});
            assert.ok(output);
            assert.doesNotMatch(output, /InjectedReadTerminatorLoss|fixture-token/);
            if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, explanation);
          }
          assert.deepEqual(fixture.counts, before);
          assert.equal(sdk.explainReadFailure({...failure}), undefined);
          // Host success is an independent observation, not application
          // receipt, iterator completion, or permission to repeat Compute.
          const delivered = await result.deliveryAttempt(failure.attemptId);
          assert.equal(delivered.kind, 'found');
          assert.equal(delivered.record.state, 'succeeded');
          assert.notEqual(delivered.hostReleaseReceipt, null);
          const delivery = sdk.explainDeliveryAttempt(delivered);
          assert.equal(delivery.observation, 'host_delivery_succeeded');
          assert.equal(delivery.hostReleaseReceiptCid,
            delivered.hostReleaseReceipt.result_delivery_receipt_cid);
          assert.equal(delivery.hint, 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.');
          assert.deepEqual(sdk.explainReadFailure(failure), explanation);
          if (reader) assert.equal(reader.state(), 'prefix', '[check-mutation:read-terminator-state]');
          assert.equal((await run.status()).status, 'succeeded');
          assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1},
            '[check-mutation:read-terminator-passive]');
          // Only an explicit new read opens a second attempt. It starts
          // from the beginning and does not append to the failed iterator.
          const fresh = result.rows();
          assert.notEqual(fresh.attemptId, failure.attemptId);
          assert.deepEqual(await Array.fromAsync(fresh), expected);
          assert.equal(fresh.state(), 'complete');
          await host.settled();
          assert.deepEqual(await result.deliveryAttempt(failure.attemptId), delivered);
          assert.deepEqual(sdk.explainReadFailure(failure), explanation);
          const database = new DatabaseSync(join(scratch.path, 'requests', 'client-requests.sqlite3'),
            {readOnly: true});
          let requests, intents;
          try {
            requests = database.prepare('SELECT run_definition_cid, caller_request_id FROM client_requests ORDER BY caller_request_id')
              .all().map(value => ({...value}));
            intents = database.prepare('SELECT nonce, phase FROM client_submitted_intents ORDER BY nonce')
              .all().map(value => ({...value}));
          } finally {database.close();}
          const births = (await attemptBytes(scratch.path)).map(wire => JSON.parse(wire));
          // A physical rerun can return the same rows; inspect authoritative
          // journal/Store births and real executor counts before the oracle.
          await writeFile(join(scratch.path, 'reread-execution-observation.json'), JSON.stringify({
            entrance, consumer, ref: run.ref, originalAttempt: failure.attemptId,
            freshAttempt: fresh.attemptId, counts: fixture.counts, requests, intents, births,
            prefix: seen, explanation, delivered, freshState: fresh.state(),
          }), {mode: 0o600});
          assert.deepEqual(fixture.counts, {admissions: 2, readers: 2, computes: 1, definitions: 1},
            '[check-mutation:read-reread-no-compute]');
          assert.deepEqual(requests.map(value => value.run_definition_cid), [run.ref.runDefinitionCid]);
          // The journal request identity is Owner-derived, not the bare nonce.
          assert.match(requests[0].caller_request_id, /^sha256:[0-9a-f]{64}$/u);
          assert.deepEqual(intents, [{nonce: submissionRef.nonce, phase: 'ready'}]);
          assert.equal(births.length, 2);
          assert.equal(new Set(births.map(value => value.result_read_grant_cid)).size, 2);
          assert.equal(births.every(value => value.run_definition_cid === run.ref.runDefinitionCid), true);
          console.error(`Reread execution observation retained: ${scratch.path}`);
          console.log('READ_TERMINATOR_EVIDENCE', JSON.stringify({entrance, consumer,
            ref: run.ref, attemptId: failure.attemptId, rowsYielded: count,
            ownerState: delivered.record.state, readerComplete: false,
            receiptCid: delivery.hostReleaseReceiptCid, counts: fixture.counts}));
        } finally {await host.close(); await fixture.close();}
        scratch.passed();
      });
  }
}
