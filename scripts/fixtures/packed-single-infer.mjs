import assert from 'node:assert/strict';
import {createDecipheriv, createHash, generateKeyPairSync} from 'node:crypto';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {connect} from '@actql/node';
import {canonical, cid, configuration, program, expected} from
  './installed-infer-fixture.mjs';

const mode = process.argv[2];
assert.ok(['success', 'cancel', 'failure', 'capture', 'replay'].includes(mode));
const root = join(process.cwd(), mode === 'replay' ? 'capture' : mode);
const {installation, taskCid} = configuration(
  JSON.parse(readFileSync('base-environment.json', 'utf8')));
const keys = generateKeyPairSync('ed25519');
const authorization = {
  hostKey: {keyId: 'packed-host', privateKey: keys.privateKey.export({
    type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'packed-reviewer', reviewerId: 'packed-reviewer',
    principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  accountConfiguration: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-owner',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
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
    writeFileSync(join(process.cwd(), 'capture-boundary.json'),
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
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: root, authorization,
    modelInstallation: installation,
    registerModelProviders: moon => [{providerId: 'models/packed',
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
              `${JSON.stringify({mode, taskCid})}\n`);
            assert.notEqual(mode, 'replay', 'saved capture must not redispatch');
            assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
              '"urgent"');
            return moon.clientProgramModelResponse(request,
              '{"reason":null,"risk":"high"}', 'packed-risk-model',
              'packed-request', 1n, mode === 'failure' ? 1000n : 2n,
              new Date().toISOString());
          }))}), () => true),
    }],
  }});
try {
  run = await client.start(program, {requestId: 'packed-single-infer'});
  started();
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
    const holding = cid({role, slot: 0,
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
        mode === 'cancel' ? 'cancelled' : 'contract_violation');
      assert.equal(evidence.failure,
        mode === 'cancel' ? 'cancelled' : 'budget_exceeded');
    }
  }
  console.log(JSON.stringify({mode, status: terminal.status, calls,
    evidenceHoldings: 4}));
} finally {
  await client.close();
}
