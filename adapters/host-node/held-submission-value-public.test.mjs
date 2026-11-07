import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
const inputs = process.env.ACTQL_HELD_VALUE_ACCEPTANCE_INPUTS;
const acceptance = inputs === undefined ? {runtime: {
  client: new URL('../../packages/node/index.mjs', import.meta.url).href,
  httpHost: new URL('./embedded-local.mjs', import.meta.url).href,
  root: new URL('../../', import.meta.url).href,
}} : JSON.parse(await readFile(inputs, 'utf8'));
if (inputs === undefined) {
  const {prepareSourceNodeClient} = await import('./fixtures/source-node-client.mjs');
  await prepareSourceNodeClient({assemble: true});
}
const processFixture = fileURLToPath(new URL('../../scripts/fixtures/held-submission-value-process.mjs', import.meta.url));
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const program = {
  version: 'actql/0.1', id: 'held-exact-values', params: {suffix: {type: 'string'}},
  stages: [{id: 's', inputs: {}, steps: [
    {as: 'seed', values: {schema: {id: {type: 'number', nullable: false}, label: {type: 'string', nullable: false}},
      rows: [{id: 1, label: 'e\u0301'}, {id: 2, label: 'é'}, {id: 3, label: 'a\rb'},
        {id: 4, label: 'a\nb'}, {id: 5, label: 'a\r\nb'}]}},
    {as: 'out', derive: {supplied: '$suffix', nested: {typed_literal: {type: 'json',
      value: '{"outer":[{"é":"é","é":"é","line":"a\\r\\nb"}]}'}}}},
  ], results: {out: {from: 'out', fields: ['id', 'label', 'supplied', 'nested']}}}],
  results: {answer: {from: {stage: 's', result: 'out'}}},
};
const parameters = {suffix: 'e\u0301\r\n'};
const nested = {$json: {outer: [{'é': 'é', 'e\u0301': 'e\u0301', line: 'a\r\nb'}]}};
const expected = [{id: 1, label: 'e\u0301', supplied: 'e\u0301\r\n', nested},
  {id: 2, label: 'é', supplied: 'e\u0301\r\n', nested},
  {id: 3, label: 'a\rb', supplied: 'e\u0301\r\n', nested},
  {id: 4, label: 'a\nb', supplied: 'e\u0301\r\n', nested},
  {id: 5, label: 'a\r\nb', supplied: 'e\u0301\r\n', nested}];

for (const entrance of ['local', 'https']) {
  test(`synthetic historical held ${entrance}: exact values and original request survive both process restarts`, async t => {
    const scratch = await createOwnedScratch({parent: acceptance.scratch ?? tmpdir(),
      prefix: 'actql-held-values-', label: `held exact values ${entrance}`});
    t.diagnostic(`Held-value evidence: ${scratch.path}`);
    const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
    await writeFile(join(scratch.path, 'keys.json'), JSON.stringify({reviewerPublic: pem(reviewer.publicKey),
      reviewerPrivate: pem(reviewer.privateKey), hostPrivate: pem(host.privateKey)}), {mode: 0o600});
    if (entrance === 'https') execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
    const text = JSON.stringify(program);
    const phase = async phase => {
      const outcome = spawnSync(process.execPath, [processFixture], {input: JSON.stringify({
        root: scratch.path, phase, entrance, runtime: acceptance.runtime, text, parameters}),
      encoding: 'utf8', timeout: 45000, maxBuffer: 4 * 1024 * 1024,
      // Load this test's own Host certificate before the child initializes TLS.
      env: entrance === 'https' ? {...process.env,
        NODE_EXTRA_CA_CERTS: join(scratch.path, 'host.crt')} : process.env});
      assert.equal(outcome.error, undefined, String(outcome.error));
      const report = JSON.parse(await readFile(join(scratch.path, `${phase}.json`), 'utf8'));
      assert.equal(outcome.status, 0, `${JSON.stringify(report)}\n${outcome.stderr}`);
      return report;
    };
    const first = await phase('initial');
    assert.equal(first.lookup.state, 'waiting_checkpoint');
    assert.equal(first.computes, 0);
    assert.equal(first.starts, 0);
    assert.deepEqual(first.snapshot.runs, []);
    assert.deepEqual(first.snapshot.accepted, []);
    assert.equal(first.snapshot.intents, 0);
    assert.deepEqual(Object.values(first.snapshot.holdings), Array(5).fill('held'));
    assert.deepEqual(Object.values(first.snapshot.physicalHoldings), Array(5).fill(true));
    assert.equal(first.reviewWire, first.original.reviewWire);
    assert.equal(first.checkpoint.checkpointCid, first.original.checkpointCid);
    const review = JSON.parse(first.reviewWire);
    assert.equal(review.displayed_scope.document, text);
    assert.deepEqual(review.displayed_scope.parameters, parameters);
    const approved = await phase('approve');
    assert.equal(approved.checkpoint.checkpointCid, first.checkpoint.checkpointCid);
    assert.equal(approved.reviewWire, first.reviewWire);
    assert.equal(approved.computes, 0);
    assert.equal(approved.starts, 0);
    assert.deepEqual(approved.snapshot.runs, []);
    assert.deepEqual(approved.snapshot.accepted, []);
    assert.deepEqual(approved.original, first.original);
    assert.deepEqual(approved.resolutions.map(item => item.status), ['committed']);
    const resumed = await phase('resume');
    assert.equal(resumed.state.status, 'succeeded');
    assert.deepEqual(resumed.rows, expected);
    assert.equal(resumed.computes, 1);
    assert.equal(resumed.starts, 1);
    assert.deepEqual(resumed.original, first.original);
    assert.equal(resumed.snapshot.runs.length, 1);
    assert.equal(resumed.snapshot.intents, 0);
    assert.deepEqual(resumed.snapshot.accepted, [{caller_request_id: first.original.requestId,
      logical_request_scope_cid: first.original.logicalRequestScopeCid,
      intent_fingerprint_cid: first.original.intentFingerprintCid,
      program_definition_cid: first.original.programDefinitionCid,
      parameter_values_cid: first.original.parameterValuesCid,
      caller_input_intent_cid: first.original.callerInputIntentCid,
      run_definition_cid: resumed.lookup.ref.runDefinitionCid, physical_start_reserved: 1}]);
    const restored = await phase('lookup');
    assert.deepEqual(restored.lookup.ref, resumed.lookup.ref);
    assert.equal(restored.state.run_id, resumed.state.run_id);
    assert.deepEqual(restored.rows, expected);
    assert.equal(restored.computes, 0);
    assert.equal(restored.starts, 0);
    assert.deepEqual(restored.original, first.original);
    assert.deepEqual(restored.snapshot, resumed.snapshot);
    scratch.passed();
  });
}
