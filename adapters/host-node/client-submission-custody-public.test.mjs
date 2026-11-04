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
  test(`${entrance}: typed submission lookup restores the original Run in another process without redispatch`, async t => {
    const scratch = await createOwnedScratch({parent: acceptance.scratch ?? tmpdir(),
      prefix: 'actql-submit-typed-', label: `typed submission recovery ${entrance}`});
    t.diagnostic(`Typed submission recovery evidence: ${scratch.path}`);
    const keys = generateKeyPairSync('ed25519');
    await writeFile(join(scratch.path, 'keys.json'), JSON.stringify({publicKey: pem(keys.publicKey),
      privateKey: pem(keys.privateKey)}), {mode: 0o600});
    if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
    const phase = async phase => {
      const child = spawnSync(process.execPath, [fixture], {input: JSON.stringify({phase, entrance,
        root: scratch.path, runtime: acceptance.runtime, program, scenario: 'typed_submission'}),
      encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024});
      assert.equal(child.error, undefined, String(child.error));
      const report = JSON.parse(await readFile(join(scratch.path, `${phase}.json`), 'utf8'));
      assert.equal(child.status, 0, `${JSON.stringify(report)}\n${child.stderr}`);
      assert.equal(child.signal, null, 'first process exits before the restoring process starts');
      return report;
    };
    const initial = await phase('typed-initial');
    assert.equal(initial.state.status, 'succeeded');
    assert.deepEqual(initial.rows, [{id: 1}]);
    assert.equal(initial.computes, 1);
    if (entrance === 'https') assert.equal(initial.initialUnknown, 'SubmissionUnknown');
    else assert.deepEqual(initial.initialAttempt.attemptRef,
      {operation: 'submit', attemptId: 'typed-process-initial'});
    const restored = await phase('typed-lookup');
    assert.notEqual(restored.pid, initial.pid);
    assert.deepEqual(restored.ref, initial.ref);
    assert.deepEqual(restored.submissionRef, initial.submissionRef);
    assert.deepEqual(restored.lookup, initial.lookup);
    assert.deepEqual(restored.second, initial.lookup);
    assert.equal(restored.state.status, 'succeeded');
    assert.deepEqual(restored.rows, [{id: 1}]);
    assert.equal(restored.computes, 0);
    assert.equal(restored.conflict.kind, 'conflict');
    assert.equal(restored.conflict.reason, 'intent');
    assert.deepEqual(restored.conflict.attemptRef,
      {operation: 'submit', attemptId: 'typed-process-changed'});
    assert.deepEqual(restored.conflict.submissionRef, initial.submissionRef);
    assert.equal(restored.conflict.outcome, undefined);
    scratch.passed();
  });
}

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
      const row = database.prepare(`SELECT * FROM client_requests
        WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`)
        .get(initial.ref.namespaceId, initial.ref.authorityScopeCid, initial.ref.runDefinitionCid);
      assert.equal(row.run_definition_cid, initial.ref.runDefinitionCid);
      await writeFile(join(scratch.path, 'original-request-record.json'), JSON.stringify(row));
      assert.equal(Number(database.prepare('DELETE FROM client_requests WHERE caller_request_id = ?')
        .run(row.caller_request_id).changes), 1);
    } finally {database.close();}
    const resumed = await phase('resubmit');
    assert.equal(resumed.outcome, 'unknown', JSON.stringify(resumed));
    assert.equal(resumed.code, 'SubmissionUnknown');
    assert.equal(resumed.requestId, 'original-submission');
    assert.equal(resumed.computes, 0);
    assert.deepEqual(resumed.submissionRef, initial.submissionRef);
    assert.deepEqual(resumed.lookup, {kind: 'unresolvable', submissionRef: initial.submissionRef,
      problem: {code: 'submission_history_unresolvable'}});
    scratch.passed();
  });
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: explicit restart lookup restores the same linked Run after original processes exit`, async t => {
    const scratch = await createOwnedScratch({parent: acceptance.scratch ?? tmpdir(),
      prefix: 'actql-submit-restart-', label: `submission restart ${entrance}`});
    console.error(`Submission restart evidence: ${scratch.path}`);
    const keys = generateKeyPairSync('ed25519');
    await writeFile(join(scratch.path, 'keys.json'), JSON.stringify({publicKey: pem(keys.publicKey),
      privateKey: pem(keys.privateKey)}), {mode: 0o600});
    if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
    let initialCompletion;
    const phase = async phase => {
      const child = spawnSync(process.execPath, [fixture], {input: JSON.stringify({phase, entrance,
        root: scratch.path, runtime: acceptance.runtime, program, scenario: 'explicit_restart'}),
      encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024});
      const report = JSON.parse(await readFile(join(scratch.path, `${phase}.json`), 'utf8'));
      assert.equal(child.error, undefined, String(child.error));
      const complete = () => {
        assert.equal(child.status, 0, `${JSON.stringify(report)}\n${child.stderr}`);
        assert.equal(child.signal, null);
      };
      if (phase === 'restart-initial') initialCompletion = complete;
      else complete();
      return report;
    };
    const initial = await phase('restart-initial');
    const database = new DatabaseSync(join(scratch.path, 'host/requests/client-requests.sqlite3'),
      {readOnly: true});
    let requests, intents, links;
    try {
      requests = database.prepare('SELECT run_definition_cid, caller_request_id FROM client_requests ORDER BY caller_request_id')
        .all().map(value => ({...value}));
      intents = database.prepare('SELECT nonce, phase FROM client_submitted_intents ORDER BY nonce')
        .all().map(value => ({...value}));
      links = database.prepare('SELECT fresh_submission_id, original_submission_id, link_wire FROM client_submission_restarts ORDER BY fresh_submission_id')
        .all().map(value => ({...value}));
    } finally {database.close();}
    // An unresolved lookup is passive even when a valid replacement Program
    // has already been explicitly submitted. Inspect real durable births.
    await writeFile(join(scratch.path, 'unresolved-lookup-observation.json'),
      JSON.stringify({entrance, initial, requests, intents, links}), {mode: 0o600});
    // A faulty automatic restart can fail its later lookup after dispatching.
    // Observe that real excess first; missing work or an arbitrary child
    // failure must still fail the infrastructure assertion, not this marker.
    if (![initial.computes, requests.length, intents.length, links.length]
      .some(count => count > 1)) initialCompletion();
    assert.deepEqual({computes: initial.computes, requests: requests.length,
      intents: intents.length, links: links.length},
    {computes: 1, requests: 1, intents: 1, links: 1},
    '[check-mutation:unresolvable-no-restart]');
    initialCompletion();
    assert.deepEqual(requests.map(value => value.run_definition_cid), [initial.ref.runDefinitionCid]);
    assert.deepEqual(intents, [{nonce: 'deliberately-new-work', phase: 'ready'}]);
    assert.equal(initial.state.status, 'succeeded');
    assert.deepEqual(initial.rows, [{id: 1}]);
    assert.equal(initial.computes, 1);
    assert.equal(initial.lookup.kind, 'ready');
    assert.deepEqual(initial.lookup.unresolvedHistory, initial.decision.unresolvedHistory);
    assert.deepEqual(initial.second, initial.lookup);
    assert.equal(initial.original.kind, 'unresolvable');
    // spawnSync has observed the original process's exit before launching a
    // different process. Host and execution owner lived in that first process.
    const restored = await phase('restart-lookup');
    assert.notEqual(restored.pid, initial.pid);
    assert.deepEqual(restored.decision, initial.decision);
    assert.deepEqual(restored.lookup, initial.lookup);
    assert.deepEqual(restored.second, initial.lookup);
    assert.deepEqual(restored.original, initial.original);
    assert.deepEqual(restored.ref, initial.ref);
    assert.equal(restored.state.status, 'succeeded');
    assert.deepEqual(restored.rows, [{id: 1}]);
    assert.equal(restored.computes, 0, 'restored lookup and attach do not submit or compute');
    scratch.passed();
  });
}
