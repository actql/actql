// The installed Salesforce Effect behind the standard Remote HTTP Host and the
// public Client: submit, Preview, approval of the whole Set, Host restart,
// current checks, writes and the Named Result. The org is a local HTTPS mock.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connect} from '../../../../packages/sdk/index.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openInstalledRemoteHttpHost} from
  '../../../host-node/embedded-local.mjs';
import {createInstalledEffectSite} from
  '../../../host-node/installed-effect-site.mjs';
import {salesforceEffectSiteHooks} from
  '../host/installed-salesforce-effect-hooks.mjs';
import {effectProgram, installedEffect} from
  './installed-salesforce-effect.fixture.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'salesforce-effect-host');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'host.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'host.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
test.after(() => rm(tlsRoot, {recursive: true, force: true}));

// The Host's principal and its one account configuration: the Host and the
// installed Site decide under the same admitted text.
const owner = userInfo().username;
const orgId = '00D000000000001EAA';
const connection = `salesforce:${orgId}`;
const resources = ['Other_Record__c', 'Test_Record__c'];
function hostConfiguration({commit = 'delegate', denied = []} = {}) {
  const entries = [
    ...resources.flatMap(resource => [
      {entry_id: `${resource.toLowerCase().replaceAll('_', '-')}-effect`,
        outcome: denied.includes(resource) ? 'deny' : commit,
        principal: {all: true}, connection: {any_of: [connection]},
        resource: {any_of: [resource]}, operation: {any_of: ['effect']},
        exclusions: []},
      {entry_id: `${resource.toLowerCase().replaceAll('_', '-')}-read`,
        outcome: 'allow', principal: {all: true},
        connection: {any_of: [connection]}, resource: {any_of: [resource]},
        operation: {any_of: ['read']}, exclusions: []}]),
    {entry_id: 'run-acceptance', outcome: 'allow', principal: {all: true},
      connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['source-free-values']},
      operation: {any_of: ['write']}, exclusions: []},
  ].sort((a, b) => a.entry_id < b.entry_id ? -1 : 1);
  return canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'salesforce-effect-host', entries});
}

const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const reviewers = [{keyId: 'reviewer-key', reviewerId: 'reviewer',
  principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}];
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal']]);

// One Host process over `directory` with the installed Effect as loaded now.
async function remoteHost(t, installation, directory, {configuration,
  resumeAfterAnswer = true, beforeDispatch} = {}) {
  // The Host and its installed Site run under the same account text.
  const effect = await installation.load({
    accountConfigurationWire: configuration});
  const site = createInstalledEffectSite({
    ...salesforceEffectSiteHooks(effect),
    privateEvidenceKey: Buffer.alloc(32, 7)});
  const effectInstallation = {...site, async resume(facts) {
    try { return await site.resume(facts); }
    catch (error) {
      diagnostics.push({name: 'resume_error', detail: {code: error.code,
        authorization: error.authorization}});
      throw error;
    }
  }};
  const host = await openInstalledRemoteHttpHost({
    directory: join(directory, 'state'),
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    beforeDispatch, effectInstallation,
    authorization: {accountConfiguration: configuration, reviewers,
      observe: (name, detail) => diagnostics.push({name,
        detail: detail?.stack ?? detail?.code ?? detail}),
      reviewReaders: [], resumeAfterAnswer,
      hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)}}});
  const server = createServer({key: tlsKey, cert: tlsCertificate},
    host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    server.closeAllConnections?.();
    await new Promise(resolve => server.close(resolve));
    await host.close();
    effect.close();
  };
  installation.onClose(close);
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  return {close, as: token => connect({mode: 'remote', endpoint, token,
    durability: 'durable'})};
}

export const diagnostics = [];
async function waitFor(check) {
  for (let attempt = 0; attempt < 600; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error(`Timeout ${JSON.stringify(diagnostics.slice(-12))}`);
}

const writesOf = org => org.seen.filter(item => item.method === 'PATCH' ||
  item.method === 'POST');
const ids = ['a00000000000001', 'a00000000000002'];

// `targets`: the Resources the Program updates, one Effect member each.
async function setup(t, {targets = ['Test_Record__c'], ...options} = {}) {
  const configuration = hostConfiguration(options);
  const installation = await installedEffect(t, {
    writes: targets.map(resource => ({resource, kind: 'update',
      fields: ['Name']})),
    org: {writableObjects: ['Other_Record__c']},
    principalId: owner, accountConfigurationWire: configuration});
  const directory = await mkdtemp(join(scratch, 'host-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const effect = await installation.load();
  const program = JSON.stringify(effectProgram(Object.fromEntries(
    effect.mappings.map((mapping, index) => [`save_${index}`, {update: {
      target: mapping.target, mapping: mapping.mappingRef,
      from: {result: 'rows'}, id: 'id', set: {Name: {field: 'id'}}}}])),
  ids.map(id => ({id}))));
  effect.close();
  return {installation, directory, configuration, program};
}

// Submit and wait until the whole Set's commit Checkpoint is held.
async function heldSet(t, x, requestId) {
  const host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  const client = await host.as('owner-token');
  const execution = await client.aql(x.program, {format: 'json', requestId});
  await waitFor(async () => (await execution.status()).status ===
    'waiting_checkpoint');
  const reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  assert.equal(checkpoint.kind, 'effect_set');
  await host.close();
  return {execution, checkpoint};
}

async function answer(t, x, checkpoint, decision, authorityScopeCid) {
  const host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration, resumeAfterAnswer: false});
  const reviewer = await host.as('reviewer-token');
  const answered = await reviewer.resolveCheckpoints([{checkpoint,
    decision}], {signer: {...signer, authorityScopeCid}});
  assert.deepEqual(answered.results.map(item => item.status), ['committed']);
  await host.close();
}

async function approvedSetResumes(t, targets) {
    const x = await setup(t, {targets});
    x.installation.org.setTargetName('observed-before');
    const {execution, checkpoint} = await heldSet(t, x, 'salesforce-set-a');
    // Previewed, read and held: nothing written before approval.
    assert.equal(writesOf(x.installation.org).length, 0);
    await answer(t, x, checkpoint, 'approved',
      execution.ref.authorityScopeCid);
    assert.equal(writesOf(x.installation.org).length, 0);
    const resumed = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration});
    const attached = await (await resumed.as('owner-token'))
      .attach(execution.ref);
    await waitFor(async () => (await attached.status()).status ===
      'succeeded');
    assert.deepEqual(writesOf(x.installation.org).map(item =>
      item.path.split('/').slice(-2).join('/')).sort(),
    targets.flatMap(resource => ids.map(id => `${resource}/${id}`)));
    assert.deepEqual(await attached.result('answer').all(),
      ids.map(id => ({id})));
    await resumed.close();
    // Another restart: the same published Run, no further write.
    const again = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration});
    const final = await (await again.as('owner-token')).attach(execution.ref);
    assert.equal((await final.status()).status, 'succeeded');
    assert.equal(writesOf(x.installation.org).length, 2 * targets.length);
    await again.close();
}

test('an approved Salesforce Effect Set resumes after a restart and publishes once',
  t => approvedSetResumes(t, ['Test_Record__c']));

// One approval of the complete Set covers its two independent Resource
// tuples; each tuple still has to pass its current account decision.
test('an approved Set over two Resources resumes and writes each tuple once',
  t => approvedSetResumes(t, resources));

test('a rejected Salesforce Effect Set writes nothing', async t => {
  const x = await setup(t);
  const {execution, checkpoint} = await heldSet(t, x, 'salesforce-set-b');
  await answer(t, x, checkpoint, 'rejected', execution.ref.authorityScopeCid);
  const host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  const attached = await (await host.as('owner-token')).attach(execution.ref);
  await waitFor(async () => ['failed', 'cancelled'].includes(
    (await attached.status()).status));
  assert.equal(writesOf(x.installation.org).length, 0);
  await host.close();
});

// Approved, then changed before the restarted Host resumes: nothing is sent.
for (const [label, change] of [
  ['the commit permission is revoked', x => ({
    configuration: hostConfiguration({denied: ['Test_Record__c']})})],
  ['the target record changed', x => {
    x.installation.org.setTargetName('changed-after-approval');
    return {};
  }],
]) {
  test(`an approved Set is not written when ${label}`, async t => {
    const x = await setup(t);
    x.installation.org.setTargetName('observed-before');
    const {execution, checkpoint} = await heldSet(t, x, 'salesforce-set-c');
    await answer(t, x, checkpoint, 'approved',
      execution.ref.authorityScopeCid);
    const {configuration = x.configuration} = change(x);
    const host = await remoteHost(t, x.installation, x.directory,
      {configuration});
    const attached = await (await host.as('owner-token'))
      .attach(execution.ref);
    // The resume is refused before any send. A revoked commit ends the Run
    // failed; a current-state refusal leaves it unfinished in the merged
    // Host (reported to C) and never succeeds.
    const seen = diagnostics.length;
    const state = await waitFor(async () => {
      const current = await attached.status();
      return ['failed', 'cancelled', 'succeeded', 'needs_reconciliation']
        .includes(current.status) ||
        diagnostics.slice(seen).some(item =>
          item.name === 'effect_resume_failed') ? current : undefined;
    });
    assert.notEqual(state.status, 'succeeded');
    assert.equal(writesOf(x.installation.org).length, 0);
    await host.close();
  });
}
