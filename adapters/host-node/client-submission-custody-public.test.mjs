import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const input = process.env.ACTQL_SUBMISSION_CUSTODY_ACCEPTANCE_INPUTS;
const acceptance = input === undefined ? {runtime: {
  client: new URL('../../packages/node/index.mjs', import.meta.url).href,
  sdk: new URL('../../packages/sdk/index.mjs', import.meta.url).href,
  httpHost: new URL('./embedded-local.mjs', import.meta.url).href,
}} : JSON.parse(await readFile(input, 'utf8'));
if (input === undefined) {
  const {prepareSourceNodeClient} = await import('./fixtures/source-node-client.mjs');
  await prepareSourceNodeClient({assemble: true});
}
const fixture = fileURLToPath(new URL('./client-submission-custody-public.fixture.mjs', import.meta.url));
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const program = {version: 'actql/0.1', id: 'original-submission', stages: [{id: 's',
  inputs: {}, steps: [{as: 'rows', values: {schema: {id: {type: 'number', nullable: false}},
    rows: [{id: 1}]}}], results: {out: {from: 'rows', fields: ['id']}}}],
results: {answer: {from: {stage: 's', result: 'out'}}}};

for (const entrance of ['local', 'https']) {
  test(`${entrance}: lost submission custody cannot create another Run for the original identity`, async t => {
    const scratch = await createOwnedScratch({parent: acceptance.scratch ?? tmpdir(),
      prefix: 'actql-submit-custody-', label: `submission custody ${entrance}`});
    t.diagnostic(`Submission custody evidence: ${scratch.path}`);
    const keys = generateKeyPairSync('ed25519');
    await writeFile(join(scratch.path, 'keys.json'), JSON.stringify({publicKey: pem(keys.publicKey),
      privateKey: pem(keys.privateKey)}), {mode: 0o600});
    if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
    const phase = async phase => {
      const child = spawnSync(process.execPath, [fixture], {input: JSON.stringify({phase, entrance,
        root: scratch.path, runtime: acceptance.runtime, program}), encoding: 'utf8',
      timeout: 30000, maxBuffer: 4 * 1024 * 1024});
      const report = JSON.parse(await readFile(join(scratch.path, `${phase}.json`), 'utf8'));
      assert.equal(child.error, undefined, String(child.error));
      assert.equal(child.status, 0, `${JSON.stringify(report)}\n${child.stderr}`);
      return report;
    };
    const initial = await phase('initial');
    assert.equal(initial.outcome, 'accepted');
    assert.equal(initial.state.status, 'succeeded');
    assert.deepEqual(initial.rows, [{id: 1}]);
    assert.equal(initial.computes, 1);
    // The first process is stopped. Lose only its test-owned request row,
    // preserving the original and independent publication/Run evidence.
    const database = new DatabaseSync(join(scratch.path, 'host/requests/client-requests.sqlite3'));
    try {
      const row = database.prepare('SELECT * FROM client_requests WHERE caller_request_id = ?')
        .get('original-submission');
      assert.equal(row.run_definition_cid, initial.ref.runDefinitionCid);
      await writeFile(join(scratch.path, 'original-request-record.json'), JSON.stringify(row));
      assert.equal(Number(database.prepare('DELETE FROM client_requests WHERE caller_request_id = ?')
        .run('original-submission').changes), 1);
    } finally {database.close();}
    const resumed = await phase('resubmit');
    assert.equal(resumed.outcome, 'unknown', JSON.stringify(resumed));
    assert.equal(resumed.code, 'SubmissionUnknown');
    assert.equal(resumed.requestId, 'original-submission');
    assert.equal(resumed.computes, 0);
    assert.deepEqual(resumed.lookup, {kind: 'not_found'});
    assert.equal(resumed.lookupObservation, 'lookup_unresolved');
    scratch.passed();
  });
}
