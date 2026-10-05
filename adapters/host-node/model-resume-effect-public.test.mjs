// One public Program, real Model/Local driver and installed Salesforce Effect.
// The fixture's HTTPS org records actual HTTP writes; no Run facts, Preview,
// authorization verifier, Checkpoint journal or publication Store are mocked.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {connect} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {salesforceEffectSiteHooks} from '../connectors/salesforce/host/installed-salesforce-effect-hooks.mjs';
import {installedEffect, accountConfiguration, recordEntry} from
  '../connectors/salesforce/test/installed-salesforce-effect.fixture.mjs';
import {modelConfiguration, registerCompositionModel} from '../../scripts/fixtures/composed-infer-effect-input.mjs';
import {graphResultDataPolicy} from '../../scripts/fixtures/graph-infer-effect-input.mjs';

const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const owner = userInfo().username;
const orgId = '00D000000000001EAA';
const expectedRows = [{id: 'a00000000000002', risk: 'high', next_name: 'review-required'}];
const expectedWrites = [{path: '/services/data/v62.0/sobjects/Test_Record__c/a00000000000002',
  body: {Name: 'review-required'}}];

const programFor = mapping => ({version: 'actql/0.1', id: 'public-model-effect',
  stages: [{id: 'classify', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false}, score: {type: 'number', nullable: false}},
      rows: [{id: 'a00000000000001', score: 100}, {id: 'a00000000000002', score: 200}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}},
    {infer: {contract: 'model-task:composition-risk.v1', key: 'id',
      input: {score: {field: 'score'}}, on_non_success: 'outcomes'}, as: 'captured'},
    {filter: {eq: [{field: 'outcome'}, {literal: 'ok'}]}},
    {derive: {risk: {property: {value: {field: 'value'}, name: 'risk'}}}},
    {filter: {eq: [{field: 'risk'}, {literal: 'high'}]}},
    {derive: {next_name: {literal: 'review-required'}}},
    {select: ['id', 'risk', 'next_name'], as: 'updates'},
  ], results: {rows: {from: 'updates', fields: ['id', 'risk', 'next_name']}},
  effects: {save: {update: {target: mapping.target, mapping: mapping.mappingRef,
    from: {result: 'rows'}, id: 'id', set: {Name: {field: 'next_name'}}}}}}],
  results: {answer: {from: {stage: 'classify', result: 'rows'}}}});

test('public Model approval leaves downstream Effect writes at zero until its own approval', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-public-model-effect-'));
  const originalCertificates = getCACertificates('default');
  const sessions = new Set();
  t.after(async () => {
    for (const session of [...sessions]) await session.close();
    setDefaultCACertificates(originalCertificates);
    await rm(root, {recursive: true, force: true});
  });
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
  const key = await readFile(join(root, 'host.key'));
  const cert = await readFile(join(root, 'host.crt'));
  setDefaultCACertificates([...originalCertificates, cert.toString()]);
  const account = accountConfiguration([
    recordEntry(orgId, 'read'), recordEntry(orgId, 'effect', 'delegate'),
    {entry_id: 'run-acceptance', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}, exclusions: []},
    {entry_id: 'model-invocation', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['models/composition']}, resource: {all: true},
      operation: {any_of: ['infer']}, exclusions: []},
  ]);
  const installed = await installedEffect(t, {principalId: owner,
    accountConfigurationWire: account,
    writes: [{resource: 'Test_Record__c', kind: 'update', fields: ['Name']}]});
  const model = await modelConfiguration(JSON.parse(installed.baseEnvironmentWire));
  const reviewer = generateKeyPairSync('ed25519');
  const hostKey = generateKeyPairSync('ed25519');
  const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
    sign: bytes => sign(null, bytes, reviewer.privateKey)};
  const modelInputs = [];
  const observations = [];
  const writes = () => installed.org.seen.filter(item => ['PATCH', 'POST'].includes(item.method));
  let mapping;
  const open = async () => {
    const effect = await installed.load({accountConfigurationWire: account});
    mapping ??= effect.mappings[0];
    const site = createInstalledEffectSite({...salesforceEffectSiteHooks(effect),
      privateEvidenceKey: Buffer.alloc(32, 7)});
    const host = await openInstalledRemoteHttpHost({directory: join(root, 'state'),
      authenticate: header => header === 'Bearer fixture-owner' ? owner : undefined,
      effectInstallation: site, modelInstallation: model.installation,
      registerModelProviders: moon => registerCompositionModel(moon, model.taskCid,
        score => modelInputs.push(score)),
      resultDataPolicy: graphResultDataPolicy,
      authorization: {accountConfiguration: account, leaseMs: 1000,
        reviewers: [{keyId: signer.keyId, reviewerId: signer.reviewerId,
          principalId: owner, publicKey: pem(reviewer.publicKey)}], reviewReaders: [owner],
        hostKey: {keyId: 'host-key', privateKey: pem(hostKey.privateKey)},
        observe: (name, detail) => observations.push({name, detail})}});
    const server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const client = await connect({mode: 'remote', durability: 'durable', token: 'fixture-owner',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
    let closed = false;
    const session = {client, async close() {
      if (closed) return;
      closed = true;
      await client.close();
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
      await host.close();
      effect.close();
      sessions.delete(session);
    }};
    sessions.add(session);
    return session;
  };
  installed.onClose(async () => { for (const session of [...sessions]) await session.close(); });
  const waitFor = async check => {
    const deadline = Date.now() + 20_000;
    do {
      const value = await check();
      if (value) return value;
      await new Promise(resolve => setTimeout(resolve, 25));
    } while (Date.now() < deadline);
    throw new Error(`ModelEffectBoundaryTimeout: ${JSON.stringify(observations.slice(-12))}`);
  };
  let session = await open();
  let run = await session.client.start(programFor(mapping), {requestId: 'public-model-effect'});
  const ref = run.ref;
  const modelCheckpoint = await waitFor(async () =>
    (await session.client.checkpoints()).items.find(item => item.kind === 'model_invocation'));
  assert.equal(modelCheckpoint.subject.runDefinitionCid, ref.runDefinitionCid);
  assert.equal((await run.status()).run_id, modelCheckpoint.subject.runId);
  assert.deepEqual(modelInputs, []);
  assert.equal(writes().length, 0);
  const modelAnswer = await session.client.resolveCheckpoints([
    {checkpoint: modelCheckpoint, decision: 'approved'}], {signer});
  assert.equal(modelAnswer.results[0].status, 'committed');
  const effectCheckpoint = await waitFor(async () =>
    (await session.client.checkpoints()).items.find(item => item.kind === 'effect_set'));
  assert.equal(effectCheckpoint.subject.runId, modelCheckpoint.subject.runId);
  assert.equal(effectCheckpoint.subject.runDefinitionCid, ref.runDefinitionCid);
  assert.notEqual(effectCheckpoint.checkpointCid, modelCheckpoint.checkpointCid);
  assert.notEqual(effectCheckpoint.requiredArtifact.cid, modelCheckpoint.requiredArtifact.cid);
  assert.equal(effectCheckpoint.requiredArtifact.type, 'effect_set_preview');
  assert.ok(effectCheckpoint.requirements.includes('effect_scope_approved'));
  assert.deepEqual(modelInputs, [100, 200]);
  assert.equal(writes().length, 0, 'Model approval does not approve Effect writes');
  await assert.rejects(run.result('answer').all());
  const duplicate = await session.client.resolveCheckpoints(modelAnswer.signed);
  assert.equal(duplicate.results[0].status, 'duplicate');
  assert.equal(writes().length, 0, 'A repeated Model resolution still grants no Effect authority');
  await session.close();
  session = await open();
  run = await session.client.start(programFor(mapping), {requestId: 'public-model-effect'});
  assert.deepEqual(run.ref, ref);
  assert.deepEqual(modelInputs, [100, 200], 'Effect waiting restart must not rerun Model calls');
  assert.equal(writes().length, 0);
  const effectAnswer = await session.client.resolveCheckpoints([
    {checkpoint: effectCheckpoint, decision: 'approved'}],
  {signer: {...signer, authorityScopeCid: ref.authorityScopeCid}});
  assert.equal(effectAnswer.results[0].status, 'committed');
  const terminal = await waitFor(async () => {
    const state = await run.wait({signal: AbortSignal.timeout(20_000)});
    return ['running', 'resuming'].includes(state.status) ? undefined : state;
  });
  assert.equal(terminal.status, 'succeeded');
  assert.equal(terminal.run_id, modelCheckpoint.subject.runId);
  assert.deepEqual(await run.result('answer').all(), expectedRows);
  assert.deepEqual(writes().map(item => ({path: item.path, body: JSON.parse(item.body)})), expectedWrites);
  assert.deepEqual(modelInputs, [100, 200]);
  const again = await session.client.resolveCheckpoints(effectAnswer.signed);
  assert.equal(again.results[0].status, 'duplicate');
  assert.equal(writes().length, 1);
  await session.close();
});
