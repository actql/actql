import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost, openingProgram} from './client-read-opening.fixture.mjs';
import {attemptBytes} from './client-read-run-capacity.fixture.mjs';

// Authored independently: a generic new read has no row-count resume cursor.
const firstRows = [{id: 1}, {id: 2}];
const freshRows = [{id: 2}, {id: 1}];

for (const entrance of ['local', 'https']) {
  for (const consumer of ['rows', 'all']) {
    test(`${entrance}: explicit reordered ${consumer} reread never skips the previous prefix`,
      {timeout: 20000}, async () => {
        const scratch = await createOwnedScratch({parent: tmpdir(),
          prefix: 'actql-read-reorder-', label: `${entrance} ${consumer} reordered reread`});
        execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
          '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
        {cwd: scratch.path, stdio: 'ignore'});
        const fixture = await openReadOpeningFixture(scratch.path, undefined, {reverseRereads: true});
        const host = await connectOpeningHost(fixture, entrance, scratch.path, {loseReadTerminator: true});
        try {
          const run = await host.client.start(openingProgram,
            {submissionRef: host.client.newSubmission({nonce: 'reordered-run'})});
          const result = run.result('answer');
          const reader = consumer === 'rows' ? result.rows() : undefined;
          const prefix = [];
          let failure;
          try {
            if (reader) for await (const row of reader) prefix.push(row);
            else prefix.push(...await result.all());
          } catch (error) {failure = error;}
          await host.settled();
          assert.ok(failure instanceof sdk.ClientError);
          assert.deepEqual(prefix, consumer === 'rows' ? firstRows : []);
          const explanation = sdk.explainReadFailure(failure);
          assert.equal(explanation.rowsYielded, consumer === 'rows' ? 2 : 0);
          const original = await result.deliveryAttempt(failure.attemptId);
          assert.equal(original.record.state, 'succeeded');
          assert.deepEqual(fixture.counts, {admissions: 1, readers: 1, computes: 1, definitions: 1});
          const ordersBeforeAdvice = structuredClone(fixture.deliveryOrders);
          for (const format of ['text', 'html', 'json']) assert.ok(sdk.formatReadFailure(failure, {format}));
          assert.deepEqual(fixture.deliveryOrders, ordersBeforeAdvice);

          const fresh = result.rows();
          const received = await Array.fromAsync(fresh);
          await host.settled();
          const delivered = await result.deliveryAttempt(fresh.attemptId);
          const births = (await attemptBytes(scratch.path)).map(wire => JSON.parse(wire));
          // Retain real Store/Owner and caller observations before the oracle.
          await writeFile(join(scratch.path, 'reordered-read-observation.json'), JSON.stringify({
            entrance, consumer, ref: run.ref, prefix, received, counts: fixture.counts,
            deliveryOrders: fixture.deliveryOrders, births, original, delivered,
            explanation, firstAttempt: failure.attemptId, freshAttempt: fresh.attemptId,
            state: fresh.state(), rowsYielded: fresh.rowsYielded(),
          }), {mode: 0o600});
          assert.deepEqual(received, freshRows, '[check-mutation:read-reordered-whole-value]');
          assert.equal(fresh.rowsYielded(), 2);
          assert.equal(fresh.state(), 'complete');
          assert.notEqual(fresh.attemptId, failure.attemptId);
          assert.equal(births.length, 2);
          assert.equal(new Set(births.map(value => value.result_read_grant_cid)).size, 2);
          for (const birth of births) {
            for (const field of ['run_definition_cid', 'result_manifest_cid', 'result_artifact_cid',
              'serialization_contract_cid']) assert.match(birth[field], /^sha256:[0-9a-f]{64}$/u);
            assert.equal(birth.result_name, 'answer');
          }
          assert.equal(new Set(births.map(value => JSON.stringify([
            value.run_definition_cid, value.result_manifest_cid, value.result_name,
            value.result_artifact_cid, value.serialization_contract_cid,
          ]))).size, 1);
          assert.deepEqual(fixture.counts, {admissions: 2, readers: 2, computes: 1, definitions: 1});
          assert.equal(delivered.record.state, 'succeeded');
          assert.notEqual(delivered.hostReleaseReceipt, null);
          assert.deepEqual(await result.deliveryAttempt(failure.attemptId), original);
          assert.deepEqual(sdk.explainReadFailure(failure), explanation);
          assert.deepEqual(prefix, consumer === 'rows' ? firstRows : []);
          assert.equal((await run.status()).status, 'succeeded');
          console.error(`Reordered read observation retained: ${scratch.path}`);
        } finally {await host.close(); await fixture.close();}
        scratch.passed();
      });
  }
}
