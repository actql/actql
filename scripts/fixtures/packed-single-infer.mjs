import assert from 'node:assert/strict';
import {scopedModelHolding} from './model-custody-fixture.mjs';
import {providerBindingOriginals} from './model-provider-binding-fixture.mjs';
import {execFileSync} from 'node:child_process';
import {createDecipheriv, createHash, generateKeyPairSync, sign} from 'node:crypto';
import {appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {canonical, cid, configuration, program, expected} from
  './installed-infer-fixture.mjs';

const mode = process.argv[2];
const transport = process.argv[3] ?? 'local';
const approval = mode.startsWith('approval-');
// The deferred path must retain these exact data bytes across custody/restart.
const approvalText = 'urgent e\u0301 \u00e9\r\nline';
const submittedProgram = structuredClone(program);
if (approval) submittedProgram.stages[0].steps[0].values.rows[0].text = approvalText;
assert.ok(['success', 'cancel', 'failure', 'capture', 'replay',
  'approval-wait', 'approval-approve', 'approval-replay'].includes(mode));
assert.ok(['local', 'http'].includes(transport));
const root = join(process.cwd(), transport,
  approval ? 'approval' : mode === 'replay' ? 'capture' : mode);
// Fixture signer/report files must not prepopulate an unadmitted Host root.
const hostRoot = approval ? join(root, 'host') : root;
const certificateRoot = join(process.cwd(), transport);
mkdirSync(root, {recursive: true});
const {installation, taskCid} = configuration(
  JSON.parse(readFileSync('base-environment.json', 'utf8')));
const keys = generateKeyPairSync('ed25519');
const keyPath = join(root, 'fixture-reviewer.json');
const keyMaterial = approval && existsSync(keyPath)
  ? JSON.parse(readFileSync(keyPath, 'utf8')) : {
    privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'}),
  };
if (approval && !existsSync(keyPath)) writeFileSync(keyPath,
  JSON.stringify(keyMaterial), {mode: 0o600});
const authorization = {
  reviewReaders: [userInfo().username],
  hostKey: {keyId: 'packed-host', privateKey: keyMaterial.privateKey},
  reviewers: [{keyId: 'packed-reviewer', reviewerId: 'packed-reviewer',
    principalId: userInfo().username,
    publicKey: keyMaterial.publicKey}],
  accountConfiguration: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-owner',
    entries: approval ? [
      {entry_id: 'model', outcome: 'delegate', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['infer']}, exclusions: []},
      {entry_id: 'run', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
    ] : [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {all: true},
      exclusions: []}],
  }),
};
let calls = 0;
let run;
let cancelled = false;
let started;
const ready = new Promise(resolve => { started = resolve; });
authorization.faultInjection = async name => {
  if (mode === 'capture' && name === 'infer_capture_committed') {
    assert.equal(calls, 1);
    writeFileSync(join(process.cwd(), `capture-boundary-${transport}.json`),
      JSON.stringify({calls, boundary: name}));
    process.exit(0);
  }
  if (mode === 'cancel' && name === 'infer_execution_advanced' &&
      calls === 1 && !cancelled) {
    cancelled = true;
    await ready;
    await run.cancel();
  }
};
const checked = result => {
  assert.equal(result.$tag, 1, 'physical request must pass common admission');
  return result._0;
};
const installationOptions = {directory: hostRoot, authorization,
    modelInstallation: installation,
    registerModelProviders: moon => [{providerId: 'models/packed',
      bindingOriginals: providerBindingOriginals('models/packed', {selector: 'packed-risk-model'}),
      invoke() { throw new Error('UnpreparedModelCall'); },
      validatePrompt(actual, selector, wire) {
        return actual === taskCid && selector === 'packed-risk-model' &&
          JSON.parse(wire).format === 'packed-risk/0.1';
      },
      quantityCapacity: {
        limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
        perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
      observeEgress: () => ({_0: 'public', _1: 'fixture-region',
        _2: false, _3: false}),
      physicalPreflight: request => moon.clientProgramModelRequestPreflight(
        () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
          request, 1000n, 33n, 0n, 500n, () => {
            calls++;
            appendFileSync(join(process.cwd(), 'provider-calls.jsonl'),
              `${JSON.stringify({mode, taskCid, transport})}\n`);
            assert.ok(!['replay', 'approval-replay', 'approval-wait'].includes(mode),
              'saved response or unsent approval cannot dispatch');
            assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
              approval ? JSON.stringify(approvalText) : '"urgent"');
            return moon.clientProgramModelResponse(request,
              '{"reason":null,"risk":"high"}', 'packed-risk-model',
              'packed-request', 1n, mode === 'failure' ? 1000n : 2n,
              new Date().toISOString());
          }))}), () => true),
    }]};
let host, server;
let client;
const priorCertificates = getCACertificates('default');
if (transport === 'http') {
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: certificateRoot, stdio: 'ignore'});
  const certificate = readFileSync(join(certificateRoot, 'host.crt'));
  setDefaultCACertificates([...priorCertificates, certificate.toString()]);
  host = await openInstalledRemoteHttpHost({...installationOptions,
    authenticate: header => header === 'Bearer fixture-owner'
      ? userInfo().username : undefined});
  server = createServer({key: readFileSync(join(certificateRoot, 'host.key')),
    cert: certificate}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  client = await connect({mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-owner', durability: 'durable'});
} else {
  client = await connect({mode: 'local', owner: 'local',
    durability: 'durable', installation: installationOptions});
}
try {
  run = await client.start(submittedProgram, {requestId: 'packed-single-infer'});
  started();
  if (approval) {
    const recordPath = join(root, 'approval-run.json');
    if (mode === 'approval-wait') {
      const deadline = Date.now() + 20_000;
      let summary;
      do {
        summary = (await client.checkpoints()).items.find(item => item.kind === 'model_invocation');
        if (summary !== undefined) break;
        await new Promise(resolve => setTimeout(resolve, 20));
      } while (Date.now() < deadline);
      assert.ok(summary, 'Model approval did not reach durable Waiting');
      assert.equal((await run.status()).status, 'waiting_checkpoint');
      assert.equal(calls, 0);
      assert.equal(summary.subject.runDefinitionCid, run.ref.runDefinitionCid);
      const reviewed = await client.reviewCheckpoint(summary);
      const review = JSON.parse(new TextDecoder().decode(reviewed.bytes));
      assert.equal(review.displayed_scope.model_invocation_scope_cid, summary.requiredArtifact.cid);
      assert.equal(review.displayed_scope.model_call_slot_cids.length, 1);
      writeFileSync(recordPath, JSON.stringify({ref: run.ref,
        runId: summary.subject.runId, summary}));
      console.log(JSON.stringify({mode, transport, status: 'waiting_checkpoint', calls: 0}));
    } else {
      const saved = JSON.parse(readFileSync(recordPath, 'utf8'));
      assert.deepEqual(run.ref, saved.ref);
      if (mode === 'approval-approve') {
        const resolved = await client.resolveCheckpoints([{checkpoint: saved.summary,
          decision: 'approved'}], {signer: {keyId: 'packed-reviewer',
          reviewerId: 'packed-reviewer', sign: bytes => sign(null, bytes, keyMaterial.privateKey)}});
        assert.equal(resolved.results[0].status, 'committed');
      }
      const deadline = Date.now() + 20_000;
      let state;
      do {
        state = await run.wait();
        if (state.status === 'succeeded') break;
        assert.ok(['running', 'resuming', 'waiting_checkpoint'].includes(state.status), JSON.stringify(state));
        await new Promise(resolve => setTimeout(resolve, 20));
      } while (Date.now() < deadline);
      assert.equal(state.status, 'succeeded');
      assert.equal(state.run_id, saved.runId);
      assert.deepEqual(await run.result('answer').all(), expected);
      assert.equal(calls, mode === 'approval-approve' ? 1 : 0);
      console.log(JSON.stringify({mode, transport, status: state.status, calls,
        ref: run.ref, runId: state.run_id}));
    }
  } else {
  let terminal = await run.wait();
  for (let i = 0; mode === 'failure' &&
      terminal.status === 'needs_reconciliation' && i < 100; i++) {
    await new Promise(resolve => setImmediate(resolve));
    terminal = await run.wait();
  }
  assert.equal(terminal.status, mode === 'cancel' ? 'cancelled' :
    mode === 'failure' ? 'failed' : 'succeeded');
  if (mode === 'cancel' || mode === 'failure') {
    await assert.rejects(run.result('answer').all());
  } else {
    assert.deepEqual(await run.result('answer').all(), expected);
  }
  assert.equal(calls, mode === 'replay' ? 0 : 1);
  assert.equal(cancelled, mode === 'cancel');
  // Inspect durable evidence retention independently of Store helper APIs.
  const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root,
    principalId: userInfo().username})).digest('hex')}`;
  for (const role of ['model_call_attempt', 'model_attempt_accounting',
    'model_attempt_outcome', 'model_dispatch_authority']) {
    const holding = mode === 'cancel' || mode === 'failure'
      ? scopedModelHolding(root, run.ref.runDefinitionCid, storeCid, role)
      : cid({role, slot: 0,
      run_definition_cid: run.ref.runDefinitionCid,
      store_authority_cid: storeCid,
      version: 'actql-model-private-holding/0.1'});
    const record = JSON.parse(readFileSync(join(root, 'publication',
      'physical-holdings', `${holding.slice(7)}.json`), 'utf8'));
    assert.equal(record.holding_cid, holding);
    assert.equal(record.namespace, 'publication-private');
    assert.equal(record.objects.length, 1);
    const object = record.objects[0];
    const bytes = readFileSync(join(root, 'publication', 'objects',
      object.cid.slice(7)));
    assert.equal(bytes.byteLength, object.byte_count);
    assert.equal(`sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      object.cid);
    const envelope = JSON.parse(bytes);
    assert.equal(envelope.version, 'actql-private-publication-evidence/0.1');
    const key = readFileSync(join(root, 'checkpoints', 'private-evidence.key'));
    let evidence;
    try {
      const decipher = createDecipheriv('aes-256-gcm', key,
        Buffer.from(envelope.nonce, 'base64'));
      decipher.setAAD(Buffer.from(
        `actql-private-publication-evidence/0.1\0${role}\0${record.manifest_cid}`));
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      evidence = JSON.parse(Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
        decipher.final()]));
    } finally { key.fill(0); }
    if (role === 'model_attempt_accounting') {
      assert.equal(evidence.input_tokens, 1);
      assert.equal(evidence.output_tokens, mode === 'failure' ? 1000 : 2);
      assert.equal(evidence.cost_units, null);
      assert.equal(evidence.duration_ms, null);
      assert.ok(evidence.cumulative_work > 0);
    }
    if (role === 'model_attempt_outcome' &&
        (mode === 'cancel' || mode === 'failure')) {
      assert.equal(evidence.category,
        mode === 'cancel' ? 'ok' : 'contract_violation');
      assert.equal(evidence.failure,
        mode === 'cancel' ? null : 'budget_exceeded');
    }
  }
  console.log(JSON.stringify({mode, transport, status: terminal.status, calls,
    evidenceHoldings: 4}));
  }
} finally {
  await client.close();
  if (server !== undefined) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
  setDefaultCACertificates(priorCertificates);
}
