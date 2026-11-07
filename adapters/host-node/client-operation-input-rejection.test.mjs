import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as sdk from '../../packages/sdk/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const program = (steps, parameter, result = {from: 'seed', fields: ['id']}) => ({version: 'actql/0.1', id: 'operation-input-rejection',
  params: {n: parameter}, stages: [{id: 'source', inputs: {}, steps,
    results: {rows: result}}],
  results: {answer: {from: {stage: 'source', result: 'rows'}}}});
const vectorProgram = program([
  {values: {schema: {id: {type: 'number', nullable: false},
    embedding: {type: 'vector', dimensions: 2, nullable: false}}, rows: [{id: 1, embedding: [1, 0]}]}, as: 'seed'},
  {to_vectors: {id: 'id', vector: 'embedding'}},
  {score_vectors: {query: {$param: 'n'}, metric: 'dot'}},
], {type: 'array', items: {type: 'number'}});
const rangeProgram = program([
  {time_series: {start: {$param: 'n'}, end: '2000-01-01T00:00:00.000Z', step: 1}, as: 'grid'},
  {select: [{id: 'time'}, {value: 'time'}], as: 'selected'},
], {type: 'timestamp'}, {from: 'selected', fields: ['id', 'value']});
const cases = [
  ['reversed bound range', rangeProgram, {n: '2000-01-02T00:00:00.000Z'}],
  ['empty bound vector query', vectorProgram, {n: []}],
  ['short bound vector query', vectorProgram, {n: [1]}],
  ['long bound vector query', vectorProgram, {n: [1, 2, 3]}],
];
for (const entrance of ['local', 'https']) {
  for (const [name, input, parameters] of cases) {
    test(`${entrance}: ${name} is rejected before admission or Compute`, {timeout: 20000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-operation-input-rejection-', label: `${entrance} ${name}`});
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key',
        '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
      const wire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
      const environment = moon.clientProgramCheckEnvironment(wire.trimEnd(),
        'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
        false, true, true, false, true, false, false);
      assert.ok(environment);
      const fixture = await openReadOpeningFixture(scratch.path, undefined, {environment});
      const host = await connectOpeningHost(fixture, entrance, scratch.path);
      try {
        let error;
        try {await host.client.start(input, {submissionRef:
          host.client.newSubmission({nonce: `invalid-${name}`}), parameters});}
        catch (value) {error = value;}
        await host.settled();
        assert.equal(error instanceof sdk.ClientError, true);
        assert.equal(error.code, 'SubmissionNotAccepted', '[check-mutation:operation-input-public]');
        const outcome = sdk.getSubmissionOutcome(error);
        assert.equal(outcome.kind, 'not_accepted');
        assert.equal(outcome.problem.code, 'ClientProgramRejected', '[check-mutation:operation-input-public]');
        assert.deepEqual(await host.client.lookupSubmission(outcome.submissionRef), outcome);
        assert.notEqual(error.code, 'SubmissionUnknown');
        assert.deepEqual(fixture.counts, {admissions: 0, readers: 0, computes: 0, definitions: 0},
          '[check-mutation:operation-input-no-execution]');
        assert.equal(fixture.journal.lookup({namespaceId: 'opening-fixture',
          authorityScopeCid: 'sha256:' + 'a'.repeat(64), requestId: `invalid-${name}`}, moon), undefined);
        console.log('OPERATION_INPUT_REJECTION_EVIDENCE', JSON.stringify({entrance, name, code: error.code, counts: fixture.counts}));
      } finally {await host.close(); await fixture.close();}
      scratch.passed();
    });
  }
}
