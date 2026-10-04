// Focused installed Host cancellation regression with a local HTTPS provider.
// Uses real request/Checkpoint journals and fresh processes for restart.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {canonicalJson} from './local-account-config.mjs';

const embeddedUrl = new URL('./embedded-local.mjs', import.meta.url).href;
test('approved unentered target cancellation survives full installed Host restart without provider I/O', {timeout: 60000}, async t => {
const root = await mkdtemp(join(tmpdir(), 'actql-target-cancel-'));
t.after(() => rm(root, {recursive: true, force: true}));
const orgId = '00D000000000001EAA';
const token = 'target-cancel-test-only-token';
function runChild(script, env, args = [], expectedExit = 0) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], {cwd: root, env});
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    const timer = setTimeout(() => child.kill('SIGKILL'), 20000);
    child.on('error', reject);
    child.on('close', code => {
      clearTimeout(timer);
      if (code === expectedExit) resolve(stdout);
      else reject(new Error(`${script} failed:\n${stdout}\n${stderr}`));
    });
  });
}
const server = await (async () => {
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'org.key', '-out', 'org.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  const seen = [];
  const prefix = '/services/data/v62.0/';
  const https = createServer({key: await readFile(join(root, 'org.key')),
    cert: await readFile(join(root, 'org.crt'))}, (request, response) => {
    seen.push({method: request.method,
      path: decodeURIComponent(request.url ?? '').split('?')[0]});
    if (request.headers.authorization !== `Bearer ${token}`) {
      response.writeHead(401).end();
      return;
    }
    const json = value => {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify(value));
    };
    // Test_Record__c is read and written; Other_Record__c, of the same
    // shape, is the second Resource of an Effect Set.
    const described = ['Test_Record__c', 'Other_Record__c'].find(name =>
      request.url === `${prefix}sobjects/${name}/describe`);
    if (described !== undefined) {
      json({name: described, queryable: true, createable: true,
        updateable: true, fields: [
          {name: 'Id', type: 'id', nillable: false, sortable: false},
          {name: 'Name', type: 'string', nillable: false,
            defaultedOnCreate: false, createable: true, updateable: true},
          {name: 'External_Key__c', type: 'string', externalId: true,
            unique: true, caseSensitive: true, nillable: false,
            defaultedOnCreate: false, createable: true, updateable: true},
        ]});
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise(resolve => https.listen(0, '127.0.0.1', resolve));
  return {seen, origin: `https://127.0.0.1:${https.address().port}`,
    close: () => new Promise(resolve => https.close(resolve))};
})();

t.after(() => server.close());
  // The installed Site (secret references only) and the Host source profile.
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  await writeFile(join(root, 'site.json'), JSON.stringify({
    version: 'actql-installed-salesforce-site/0.1', apiVersion: 'v62.0',
    cliAlias: 'actql-target-cancel', cliUsername: 'target-cancel@example.test',
    connectionRevision: 'target-cancel-connection-a',
    credentialAuthorityId: 'target-cancel-authority', credentialKeyId: 'target-cancel-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'target-cancel', instanceOrigin: server.origin,
    journalRoot: join(root, 'credential-journal'), orgId, siteGeneration: 1,
    siteKey: 'target-cancel-site', namespaceId: 'target-cancel-namespace',
    caPath: join(root, 'org.crt')}));
  // A stand-in `sf` CLI: the org binding and a test-only token.
  await mkdir(join(root, 'bin'));
  await writeFile(join(root, 'bin', 'sf'), `#!/bin/sh
case "$2" in
  display) printf '%s' '{"status":0,"result":{"alias":"actql-target-cancel","id":"${orgId}","username":"target-cancel@example.test","instanceUrl":"${server.origin}","connectedStatus":"Connected"}}' ;;
  auth) printf '%s' '{"status":0,"result":{"accessToken":"${token}"}}' ;;
  *) exit 1 ;;
esac
`, {mode: 0o755});
  // Child processes exercise the same installed Host modules and durable root.
  const childEnvironment = {HOME: process.env.HOME,
    PATH: [join(root, 'bin'), dirname(process.execPath), '/usr/bin', '/bin']
      .join(':'),
    ACTQL_LOCAL_STATE_DIR: join(root, 'state')};
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'reviewer.key'), reviewer.privateKey.export({
    type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const effectAccount = canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'target-cancel-effect-account', entries: [
      {entry_id: 'effect-commit', outcome: 'delegate', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Other_Record__c', 'Test_Record__c']},
        operation: {any_of: ['effect']}},
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}},
      {entry_id: 'target-read', outcome: 'delegate', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Other_Record__c', 'Test_Record__c']},
        operation: {any_of: ['read']}},
    ]});
  await writeFile(join(root, 'authorization.json'), JSON.stringify({
    accountConfiguration: effectAccount,
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'host-key', privateKey: host.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    leaseMs: 10000,
    resumeAfterAnswer: false,
  }));
  await writeFile(join(root, 'effect.json'), JSON.stringify({
    version: 'actql-installed-salesforce-effect/0.1',
    siteProfilePath: join(root, 'site.json'),
    publicationPath: join(root, 'effect-publication.json'),
    connectorId: 'crm-main',
    writes: ['Test_Record__c', 'Other_Record__c'].map(resource =>
      ({resource, kind: 'update', fields: ['Name']})),
    accountConfigurationWire: effectAccount}));
  await writeFile(join(root, 'publish.mjs'), `
import {publishInstalledEffect} from ${JSON.stringify(embeddedUrl)};
await publishInstalledEffect();
console.log('published');
`);
  const environment = {...childEnvironment,
    ACTQL_LOCAL_EFFECT_PROFILE: join(root, 'effect.json')};
  const effectProfile = JSON.parse(await readFile(join(root, 'effect.json'), 'utf8'));
  await writeFile(join(root, 'effect.json'), JSON.stringify({...effectProfile,
    accountConfigurationWire: canonicalJson({...JSON.parse(effectAccount), entries:
      JSON.parse(effectAccount).entries.map(entry => entry.entry_id === 'target-read'
        ? {...entry, outcome: 'allow'} : entry)})}));
  assert.equal((await runChild('publish.mjs', environment)).trim(), 'published');
  await writeFile(join(root, 'effect.json'), JSON.stringify(effectProfile));
  const before = server.seen.length;
  await writeFile(join(root, 'run.mjs'), `
import assert from 'node:assert/strict';
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {connectEmbeddedLocal} from ${JSON.stringify(embeddedUrl)};
const authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
authorization.resumeAfterAnswer = false;
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: process.env.ACTQL_LOCAL_STATE_DIR,
    effectProfilePath: process.env.ACTQL_LOCAL_EFFECT_PROFILE, authorization}});
const step = process.argv[2];
const waitFor = async predicate => {
  for (let i = 0; i < 200; i++) {
    const result = await predicate();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error('TargetCancellationTimeout');
};
try {
  if (step === 'submit') {
    const generation = JSON.parse(readFileSync('effect-publication.json',
      'utf8'));
    // One member per installed Resource: an Effect Set over two Resources.
    const effects = Object.fromEntries(generation.mappings.map(
      (entry, index) => ['save_' + index, {update: {
        target: 'connector://crm-main/' + entry.write.resource,
        mapping: entry.mapping_ref, from: {result: 'rows'}, id: 'id',
        set: {Name: {field: 'id'}}}}]));
    const program = {version: 'actql/0.1', id: 'target-cancel-effect', stages: [{
      id: 'source', inputs: {},
      steps: [{values: {schema: {id: {type: 'string', nullable: false}},
        rows: [{id: 'a00000000000001'}, {id: 'a00000000000002'}]},
        as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects,
    }], results: {answer: {from: {stage: 'source', result: 'rows'}}}};
    const execution = await client.aql(JSON.stringify(program), {
      format: 'json', requestId: 'target-cancel-effect-1'});
    await waitFor(async () => {
      const status = await execution.status();
      if (status.status === 'failed') throw new Error('TargetCancelEffectFailed: ' + JSON.stringify(status));
      return status.status === 'waiting_checkpoint';
    });
    writeFileSync('effect-ref.json', JSON.stringify(execution.ref));
    console.log('held');
  } else {
    const ref = JSON.parse(readFileSync('effect-ref.json', 'utf8'));
    const lookup = await client.lookupRequest('target-cancel-effect-1');
    assert.equal(lookup.kind, 'found');
    assert.deepEqual(lookup.ref, ref);
    const execution = await client.attach(ref);
    if (step === 'cancel') {
      const state = await execution.status();
      assert.equal(state.status, 'waiting_checkpoint');
      const [checkpoint] = (await client.checkpoints()).items;
      assert.equal(checkpoint.kind, 'read_access');
      assert.ok(checkpoint.checkpointId.endsWith('-target-0'));
      const key = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
      const answered = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {
        signer: {keyId: 'reviewer-key', reviewerId: 'reviewer',
          authorityScopeCid: ref.authorityScopeCid, sign: bytes => sign(null, bytes, key)}});
      assert.deepEqual(answered.results.map(item => item.status), ['committed']);
      // Explicit no-auto-resume configuration is the deterministic barrier:
      // approval is durable, but no physical resume has been dispatched.
      await execution.cancel();
    } else assert.equal(step, 'recheck');
    const state = await waitFor(async () => {
      const observed = await execution.status();
      if (observed.status === 'failed') throw new Error(JSON.stringify(observed));
      return observed.status === 'cancelled' ? observed : undefined;
    });
    assert.equal(state.status, 'cancelled');
    assert.deepEqual(execution.ref, ref);
    console.log('cancelled');
  }
} finally { await client.close(); }
`);
  for (const [step, result] of [['submit', 'held'], ['cancel', 'cancelled'], ['recheck', 'cancelled']]) {
    assert.equal((await runChild('run.mjs', environment, [step])).trim(), result);
    const calls = server.seen.slice(before);
    assert.equal(calls.filter(item => item.method === 'GET').length, 0, step + ': target reads');
    assert.equal(calls.filter(item => item.method === 'PATCH').length, 0, step + ': Effect writes');
    assert.equal(calls.length, 0, step + ': any provider I/O');
  }
});
