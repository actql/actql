// The installed Salesforce Effect behind the standard Remote HTTP Host and the
// public Client: submit, Preview, approval of the whole Set, Host restart,
// current checks, writes and the Named Result. The org is a local HTTPS mock.
import assert from 'node:assert/strict';
// The public update acceptance runs with the installed Effect's Host tests.
import './update-effect.acceptance.test.mjs';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {mkdir, mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import {connect} from '../../../../packages/sdk/index.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openInstalledRemoteHttpHost} from
  '../../../host-node/embedded-local.mjs';
import {createInstalledEffectSite} from
  '../../../host-node/installed-effect-site.mjs';
import {salesforceEffectSiteHooks} from
  '../host/installed-salesforce-effect-hooks.mjs';
import {effectProgram, installedEffect, moon, salesforceMoon} from
  './installed-salesforce-effect.fixture.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite} from '../host/installed-salesforce-site.mjs';
import {recordCheckpointApproval} from '../../../host-common/checkpoint-approval.mjs';
import {releaseCompletedRunPreparedPayloads} from
  '../../../host-common/completed-run-publication.mjs';
import {completeInterruptedEffectRun} from '../../../host-node/effect-run-completion.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'salesforce-effect-host');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=salesforce-effect-host-fixture',
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
function hostConfiguration({commit = 'delegate', read = 'allow', denied = []} = {}) {
  const entries = [
    ...resources.flatMap(resource => [
      {entry_id: `${resource.toLowerCase().replaceAll('_', '-')}-effect`,
        outcome: denied.includes(resource) ? 'deny' : commit,
        principal: {all: true}, connection: {any_of: [connection]},
        resource: {any_of: [resource]}, operation: {any_of: ['effect']},
        exclusions: []},
      {entry_id: `${resource.toLowerCase().replaceAll('_', '-')}-read`,
        outcome: read, principal: {all: true},
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
  resumeAfterAnswer = true, beforeDispatch, decide, loseResolveReply = false,
  decisionOptions = {}, instrument} = {}) {
  // The Host and its installed Site run under the same account text.
  const effect = await installation.load({
    accountConfigurationWire: configuration});
  const hooks = salesforceEffectSiteHooks(effect);
  const site = createInstalledEffectSite({
    ...(instrument?.hooks?.(hooks) ?? hooks),
    privateEvidenceKey: Buffer.alloc(32, 7)});
  const effectInstallation = {...site,
    async execute(facts) {
      try {
        const result = await site.execute(instrument?.facts?.(facts, 'execute') ?? facts);
        instrument?.observeResult?.(result);
        return result;
      }
      catch (error) { instrument?.observeFailure?.(error); throw error; }
    },
    async resume(facts) {
    try { return await site.resume(instrument?.facts?.(facts, 'resume') ?? facts); }
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
    authorization: {accountConfiguration: configuration, reviewers, decide,
      ...decisionOptions,
      observe: (name, detail) => diagnostics.push({name,
        detail: detail?.stack ?? detail?.code ?? detail}),
      reviewReaders: [], resumeAfterAnswer,
      hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)}}});
  let dropped = false;
  const server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
    if (loseResolveReply && !dropped && request.url === '/actql/client/0.1/resolve') {
      // The real handler commits the answer before sending its JSON reply.
      // Drop that response only; the journal operation is not mocked.
      response.end = () => { dropped = true; response.destroy(); return response; };
    }
    return host.handler(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let closed = false, serverClosed = false;
  const close = async () => {
    if (closed) return;
    if (!serverClosed) {
      server.closeAllConnections?.();
      await new Promise(resolve => server.close(resolve));
      serverClosed = true;
    }
    const remaining = await host.close();
    effect.close();
    closed = true;
    return remaining;
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
async function setup(t, {targets = ['Test_Record__c'], org = {}, ...options} = {}) {
  const configuration = hostConfiguration(options);
  const installation = await installedEffect(t, {
    writes: targets.map(resource => ({resource, kind: 'update',
      fields: ['Name']})),
    org: {writableObjects: ['Other_Record__c'], ...org},
    // The explicit installation publication precedes the operation under
    // test. Its metadata permission is not retained as a target-read grant.
    principalId: owner, accountConfigurationWire: hostConfiguration({...options, read: 'allow'})});
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
    targets.flatMap(resource => ids.map(id => `${resource}/${id}`)).sort());
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

test('the same two-Resource Set in the other member order writes each once',
  t => approvedSetResumes(t, [...resources].reverse()));

test('target reads wait for both exact approvals before Preview and survive every Host restart', async t => {
  const x = await setup(t, {targets: resources, read: 'delegate'});
  const before = x.installation.org.seen.length;
  let host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  let client = await host.as('owner-token');
  let run = await client.aql(x.program, {format: 'json', requestId: 'target-reads-before-preview'});
  const ref = run.ref;
  for (let index = 0; index < 2; index++) {
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    const reviewer = await host.as('reviewer-token');
    const checkpoints = (await reviewer.checkpoints()).items;
    const checkpoint = checkpoints.find(item => item.kind === 'read_access');
    assert.ok(checkpoint, JSON.stringify(checkpoints));
    assert.equal(checkpoint.requiredArtifact.type, 'read_scope');
    assert.match(checkpoint.checkpointId, new RegExp(`-target-${index}$`));
    assert.deepEqual(run.ref, ref);
    assert.equal(x.installation.org.seen.length, before,
      'no provider read, metadata describe or write may precede every target approval');
    assert.equal(writesOf(x.installation.org).length, 0);
    await host.close();
    await answer(t, x, checkpoint, 'approved', ref.authorityScopeCid);
    host = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration});
    client = await host.as('owner-token');
    run = await client.attach(ref);
  }
  await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
  const checkpoint = (await (await host.as('reviewer-token')).checkpoints()).items
    .find(item => item.kind === 'effect_set');
  assert.ok(checkpoint, 'read approvals are not Effect-commit approval');
  assert.equal(writesOf(x.installation.org).length, 0);
  assert.ok(x.installation.org.seen.length > before);
  const targetReads = () => x.installation.org.seen.slice(before).filter(item =>
    item.method === 'GET' && /\/sobjects\/[^/]+\/[^/]+$/u.test(item.path) &&
    !item.path.endsWith('/describe')).length;
  assert.equal(targetReads(), 8);
  await host.close();
  await answer(t, x, checkpoint, 'approved', ref.authorityScopeCid);
  host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  run = await (await host.as('owner-token')).attach(ref);
  await waitFor(async () => (await run.status()).status === 'succeeded');
  assert.deepEqual(await run.result('answer').all(), ids.map(id => ({id})));
  assert.deepEqual((await run.result('answer').describe()).columns,
    [{name: 'id', contract: {type: 'string', nullable: false}}]);
  assert.equal(targetReads(), 12);
  assert.deepEqual(writesOf(x.installation.org).map(item =>
    item.path.split('/').slice(-2).join('/')).sort(),
  resources.flatMap(resource => ids.map(id => `${resource}/${id}`)).sort());
  await host.close();
  const readsAndWrites = x.installation.org.seen.length;
  host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  run = await (await host.as('owner-token')).attach(ref);
  assert.equal((await run.status()).status, 'succeeded');
  assert.deepEqual(await run.result('answer').all(), ids.map(id => ({id})));
  assert.equal(x.installation.org.seen.length, readsAndWrites);
  await host.close();
});

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

for (const outcome of ['rejected', 'current-denial']) {
  test(`a target read ${outcome} leaves no provider I/O or retained capture`, async t => {
    const x = await setup(t, {targets: resources, read: 'delegate'});
    const before = x.installation.org.seen.length;
    let host = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration});
    const run = await (await host.as('owner-token')).aql(x.program,
      {format: 'json', requestId: 'target-refusal-' + outcome});
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    const checkpoint = (await (await host.as('reviewer-token')).checkpoints()).items[0];
    assert.equal(checkpoint.kind, 'read_access');
    await host.close();
    await answer(t, x, checkpoint, outcome === 'rejected' ? 'rejected' : 'approved',
      run.ref.authorityScopeCid);
    host = await remoteHost(t, x.installation, x.directory,
      {configuration: outcome === 'rejected' ? x.configuration : hostConfiguration({read: 'deny'})});
    const attached = await (await host.as('owner-token')).attach(run.ref);
    const expected = outcome === 'rejected' ? 'cancelled' : 'failed';
    await waitFor(async () => (await attached.status()).status === expected);
    assert.equal(x.installation.org.seen.length, before);
    assert.equal(writesOf(x.installation.org).length, 0);
    const remaining = await host.close();
    assert.equal(remaining.storeCleanupPending, false);
    assert.deepEqual(remaining.pendingRetention, []);
    assert.deepEqual(await retained(x), {holdings: [], objects: []});
  });
}

for (const resumedDecision of ['permit', 'reject', 'defer']) {
  test(`immediate target permits are freshly decided as ${resumedDecision} after deferred commit`, async t => {
    const x = await setup(t, {targets: resources, read: 'delegate'});
    let readDecisions = 0;
    let readAnswer = 'permit';
    const decide = view => {
      if (view.boundary === 'acquisition') readDecisions++;
      return {decision: view.boundary === 'acquisition' ? readAnswer : 'defer',
        subject: view.subject, authority: 'reviewer', claims: view.requiredClaims};
    };
    let host = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration, decide});
    const run = await (await host.as('owner-token')).aql(x.program,
      {format: 'json', requestId: 'immediate-read-' + resumedDecision});
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    const [checkpoint] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set', 'an immediate permit does not create a read Checkpoint');
    assert.equal(readDecisions, 2);
    assert.equal(writesOf(x.installation.org).length, 0);
    await host.close();
    await answer(t, x, checkpoint, 'approved', run.ref.authorityScopeCid);
    readAnswer = resumedDecision;
    host = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration, decide});
    const attached = await (await host.as('owner-token')).attach(run.ref);
    const expected = resumedDecision === 'permit' ? 'succeeded' : 'failed';
    await waitFor(async () => (await attached.status()).status === expected);
    assert.equal(readDecisions, resumedDecision === 'permit' ? 4 : 3);
    assert.equal(writesOf(x.installation.org).length, resumedDecision === 'permit' ? 4 : 0);
    if (resumedDecision === 'permit') {
      assert.deepEqual(await attached.result('answer').all(), ids.map(id => ({id})));
    }
    const remaining = await host.close();
    assert.equal(remaining.storeCleanupPending, false);
    assert.deepEqual(remaining.pendingRetention, []);
    if (resumedDecision !== 'permit') {
      assert.deepEqual(await retained(x), {holdings: [], objects: []});
    }
  });
}

test('the credential Site independently refuses a foreign target binding before granting anything', async t => {
  const installation = await installedEffect(t, {writes: [{resource: 'Test_Record__c',
    kind: 'update', fields: ['Name']}]});
  const authorization = await installSalesforceAuthorization({
    accountConfiguration: installation.profile.accountConfigurationWire,
    principalId: 'principal-a', root: installation.root});
  const site = await loadInstalledSalesforceSite(installation.profile.siteProfilePath, {
    commonMoon: moon, salesforceMoon, authorization,
    runtimeBundleCid: installation.options.runtimeBundleCid,
    resolveSecret: async () => 'test-only-secret'});
  installation.onClose(() => site.close());
  const before = installation.org.seen.length;
  const tuple = {connection: site.connection, resource: 'Test_Record__c', operation: 'read'};
  let fences = 0;
  const decisionFor = binding => recordCheckpointApproval(Object.freeze({
    action: 'dispatch', basis: 'resumed_approval', boundary: 'acquisition', tuple}), {
    kind: 'effect_target', principalId: 'principal-a',
    configurationCid: site.authorization.configurationCid, contextCid: site.context.contextCid,
    readTuple: tuple, physicalBindings: [binding],
    assertCurrent() { fences++; }, enter() { assert.fail('Admission alone must not start I/O'); },
  });
  const bindingFor = actual => ({version: 'actql-installed-salesforce-effect-target-read/0.1',
    resource: 'Test_Record__c', site_binding_cid:
      installedSalesforceSiteBinding(actual, 'fixture').bindingCid});
  for (const change of [{siteGeneration: site.siteGeneration + 1},
    {instanceOrigin: 'https://other.invalid'}, {connectionRevision: 'another-revision'}]) {
    const binding = bindingFor({...site, ...change});
    assert.throws(() => site.admitCheckpointEffectTargetRead(decisionFor(binding), binding),
      {code: 'SalesforceEffectTargetReadApprovalNotAdmitted'});
  }
  const original = 'e\u0301\r\n' + JSON.stringify({nested: 'e\u0301'});
  const exact = {...bindingFor(site), opaque: {text: original}};
  for (const text of [original.normalize('NFC'), original.replace(/\r\n?/gu, '\n')]) {
    const changed = {...exact, opaque: {text}};
    assert.throws(() => site.admitCheckpointEffectTargetRead(decisionFor(exact), changed),
      {code: 'SalesforceEffectTargetReadApprovalNotAdmitted'});
  }
  assert.equal(fences, 0);
  const binding = bindingFor(site);
  const approved = site.admitCheckpointEffectTargetRead(decisionFor(binding), binding);
  assert.equal(approved.kind, 'effect_target');
  assert.equal(fences, 1);
  for (const operation of ['salesforce:query:read', 'salesforce:record:update']) {
    assert.throws(() => site.issueGrant({operation, decision: approved,
      resource: 'Test_Record__c', subjectCid: 'sha256:' + '1'.repeat(64)}),
    {code: 'SalesforceCredentialGrantNotAuthorized'});
  }
  assert.equal(installation.org.seen.length, before);
});

test('a lost target approval response retries the exact signed answer after restart without provider I/O', async t => {
  const x = await setup(t, {targets: resources, read: 'delegate'});
  const before = x.installation.org.seen.length;
  let host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration, resumeAfterAnswer: false, loseResolveReply: true});
  const execution = await (await host.as('owner-token')).aql(x.program,
    {format: 'json', requestId: 'target-answer-response-loss'});
  await waitFor(async () => (await execution.status()).status === 'waiting_checkpoint');
  let reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  assert.equal(checkpoint.kind, 'read_access');
  let lost;
  try {
    await reviewer.resolveCheckpoints([{checkpoint, decision: 'approved'}],
      {signer: {...signer, authorityScopeCid: execution.ref.authorityScopeCid}});
  } catch (error) { lost = error; }
  assert.equal(lost?.code, 'ResolutionUnknown');
  assert.equal(lost.signed.length, 1);
  assert.equal(x.installation.org.seen.length, before);
  await host.close();
  host = await remoteHost(t, x.installation, x.directory, {configuration: x.configuration});
  const attached = await (await host.as('owner-token')).attach(execution.ref);
  await waitFor(async () => (await attached.status()).status === 'waiting_checkpoint');
  reviewer = await host.as('reviewer-token');
  const retried = await reviewer.resolveCheckpoints(lost.signed);
  assert.equal(retried.results[0].status, 'duplicate');
  assert.deepEqual(retried.signed, lost.signed);
  const [second] = (await reviewer.checkpoints()).items;
  assert.equal(second.kind, 'read_access');
  assert.notEqual(second.checkpointCid, checkpoint.checkpointCid);
  assert.equal(second.subject.runId, checkpoint.subject.runId);
  assert.equal(x.installation.org.seen.length, before);
  await attached.cancel();
  await waitFor(async () => (await attached.status()).status === 'cancelled');
  assert.equal(x.installation.org.seen.length, before);
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
    // A definitive pre-send refusal terminates the same Run. A Store or
    // provider observation failure remains retryable and cannot use this path.
    const state = await waitFor(async () => {
      const current = await attached.status();
      return current.status === 'failed' ? current : undefined;
    });
    assert.equal(state.status, 'failed');
    assert.equal(writesOf(x.installation.org).length, 0);
    await host.close();
    const publication = join(x.directory, 'state', 'publication');
    assert.deepEqual(await readdir(join(publication, 'physical-holdings')),
      []);
    assert.deepEqual(await readdir(join(publication, 'objects')), []);
  });
}

// What a closed Host still holds of an unpublished capture.
async function retained(x) {
  const publication = join(x.directory, 'state', 'publication');
  return {holdings: await readdir(join(publication, 'physical-holdings')),
    objects: await readdir(join(publication, 'objects'))};
}

// A two-Resource Set, two rows each, approved and then changed only for the
// later Resource before the restarted Host resumes. Both member orders are
// run, so the first tuple is not special. Nothing of the Set is written, the
// same Run fails, and its capture and source holdings are retired.
for (const order of [resources, [...resources].reverse()]) {
  const later = order[1];
  for (const [label, change] of [
    [`${later}'s commit permission is revoked`, () => ({
      configuration: hostConfiguration({denied: [later]})})],
    [`${later}'s target record changed`, x => {
      x.installation.org.setTargetName('changed-after-approval', later);
      return {};
    }],
  ]) {
    test(`an approved two-Resource Set (${order.join(', ')}) writes nothing when ${label}`,
      async t => {
        const x = await setup(t, {targets: order});
        x.installation.org.setTargetName('observed-before');
        const {execution, checkpoint} = await heldSet(t, x,
          'salesforce-two-resource-refusal');
        await answer(t, x, checkpoint, 'approved',
          execution.ref.authorityScopeCid);
        const {configuration = x.configuration} = change(x);
        const host = await remoteHost(t, x.installation, x.directory,
          {configuration});
        const attached = await (await host.as('owner-token'))
          .attach(execution.ref);
        const state = await waitFor(async () => {
          const current = await attached.status();
          return ['failed', 'succeeded', 'needs_reconciliation']
            .includes(current.status) ? current : undefined;
        });
        assert.equal(state.status, 'failed');
        assert.equal(writesOf(x.installation.org).length, 0);
        const remaining = await host.close();
        assert.equal(remaining.storeCleanupPending, false);
        assert.deepEqual(remaining.pendingRetention, []);
        assert.deepEqual(await retained(x), {holdings: [], objects: []});
      });
  }
}

// The write reply to the first row is lost after it was sent. The outcome
// is unknown: the Run keeps reconciliation responsibility, and neither the
// resuming Host nor a later restart sends that row, or anything, again.
for (const targetRead of ['allow', 'delegate']) {
  test('a lost write reply keeps the approved Set unknown and is never resent' +
    (targetRead === 'allow' ? '' : ' after target-read approval'), async t => {
    const configuration = hostConfiguration({read: targetRead});
    const installation = await installedEffect(t, {
      writes: [{resource: 'Test_Record__c', kind: 'update',
        fields: ['Name']}],
      org: {writableObjects: ['Other_Record__c'], loseWriteReplyOnce: true},
      principalId: owner, accountConfigurationWire: hostConfiguration()});
    const directory = await mkdtemp(join(scratch, 'host-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const effect = await installation.load();
    const [mapping] = effect.mappings;
    effect.close();
    const x = {installation, directory, configuration,
      program: JSON.stringify(effectProgram({save: {update: {
        target: mapping.target, mapping: mapping.mappingRef,
        from: {result: 'rows'}, id: 'id', set: {Name: {field: 'id'}}}}},
      ids.map(id => ({id}))))};
    let held;
    if (targetRead === 'delegate') {
      const before = installation.org.seen.length;
      const first = await remoteHost(t, installation, directory, {configuration});
      const execution = await (await first.as('owner-token')).aql(x.program,
        {format: 'json', requestId: 'salesforce-lost'});
      await waitFor(async () => (await execution.status()).status === 'waiting_checkpoint');
      const read = (await (await first.as('reviewer-token')).checkpoints()).items[0];
      assert.equal(read.kind, 'read_access');
      assert.equal(installation.org.seen.length, before);
      await first.close();
      await answer(t, x, read, 'approved', execution.ref.authorityScopeCid);
      const prepared = await remoteHost(t, installation, directory, {configuration});
      const attached = await (await prepared.as('owner-token')).attach(execution.ref);
      await waitFor(async () => (await attached.status()).status === 'waiting_checkpoint');
      const checkpoint = (await (await prepared.as('reviewer-token')).checkpoints()).items[0];
      assert.equal(checkpoint.kind, 'effect_set');
      await prepared.close();
      held = {execution, checkpoint};
    } else held = await heldSet(t, x, 'salesforce-lost');
    const {execution, checkpoint} = held;
    await answer(t, x, checkpoint, 'approved',
      execution.ref.authorityScopeCid);
    let priorCalls;
    for (let restart = 0; restart < 2; restart++) {
      const host = await remoteHost(t, installation, directory,
        {configuration});
      const attached = await (await host.as('owner-token'))
        .attach(execution.ref);
      const state = await waitFor(async () => {
        const current = await attached.status();
        return ['failed', 'succeeded', 'needs_reconciliation']
          .includes(current.status) ? current : undefined;
      });
      assert.equal(state.status, 'needs_reconciliation');
      assert.equal(writesOf(installation.org).length, 1);
      await host.close();
      const kept = await retained(x);
      assert.ok(kept.holdings.length > 0, 'unknown Effect keeps durable capture responsibility');
      assert.ok(kept.objects.length > 0);
      if (priorCalls !== undefined) assert.equal(installation.org.seen.length, priorCalls);
      priorCalls = installation.org.seen.length;
    }
  });
}

test('target and commit approvals retain original data through public Host restarts', async t => {
  const x = await setup(t, {read: 'delegate'});
  const text = 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
  const program = JSON.parse(x.program);
  const values = program.stages[0].steps[0].values;
  values.schema.original = {type: 'string', nullable: false};
  for (const row of values.rows) row.original = text;
  program.stages[0].results.rows.fields.push('original');
  x.program = JSON.stringify(program);
  const before = x.installation.org.seen.length;
  let host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  let run = await (await host.as('owner-token')).aql(x.program,
    {format: 'json', requestId: 'exact-target-and-commit'});
  const ref = run.ref;
  await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
  const [read] = (await (await host.as('reviewer-token')).checkpoints()).items;
  assert.equal(read.kind, 'read_access');
  assert.equal(x.installation.org.seen.length, before);
  await host.close();
  await answer(t, x, read, 'approved', ref.authorityScopeCid);
  host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  run = await (await host.as('owner-token')).attach(ref);
  await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
  const [commit] = (await (await host.as('reviewer-token')).checkpoints()).items;
  assert.equal(commit.kind, 'effect_set');
  assert.equal(writesOf(x.installation.org).length, 0);
  await host.close();
  await answer(t, x, commit, 'approved', ref.authorityScopeCid);
  host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  run = await (await host.as('owner-token')).attach(ref);
  await waitFor(async () => (await run.status()).status === 'succeeded');
  const expected = ids.map(id => ({id, original: text}));
  assert.deepEqual(await run.result('answer').all(), expected);
  assert.equal(writesOf(x.installation.org).length, 2);
  await host.close();
  const calls = x.installation.org.seen.length;
  host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  run = await (await host.as('owner-token')).attach(ref);
  assert.deepEqual(await run.result('answer').all(), expected);
  assert.equal(x.installation.org.seen.length, calls);
  await host.close();
});

// These are consuming combinations over one public Run, rather than sums of
// isolated gate tests. Every wrapped method delegates to the original owner.
function integratedFault(t, selected) {
  const state = {armed: true, phase: 'initial', injections: 0,
    owners: [], captures: 0, recoveries: 0, computes: 0};
  t.after(() => { state.armed = false; });
  const blocked = name => state.armed && name === selected;
  const fail = name => {
    state.injections++;
    throw Object.assign(new Error(`Integrated${name}Unavailable`),
      {code: `Integrated${name}Unavailable`});
  };
  const wrapOwner = (owner, name) => {
    const calls = {name, close: 0, cleanup: 0, completed: false};
    state.owners.push(calls);
    return {...owner, async close() {
      calls.close++;
      if (blocked(name)) fail(name);
      const result = await owner.close();
      // A Compute close and its reclamation are distinct obligations.
      calls.completed = name !== 'computeClose' && result !== false &&
        owner.cleanupPending?.() !== true;
      return result;
    }, async cleanup() {
      calls.cleanup++;
      if (blocked(name)) fail(name);
      const result = await owner.cleanup();
      calls.completed = result !== false && owner.cleanupPending?.() !== true;
      return result;
    }, cleanupPending: () => owner.cleanupPending?.() ?? !calls.completed};
  };
  const stageOf = stage => ({...stage,
    ...(stage.releaseInputs === undefined ? {} : {releaseInputs() {
      if (blocked('inputs')) fail('inputs');
      return stage.releaseInputs();
    }}), dispose() {
      if (blocked('stage')) fail('stage');
      return stage.dispose?.();
    }});
  const prepare = DatabaseSync.prototype.prepare;
  const exec = DatabaseSync.prototype.exec;
  const close = DatabaseSync.prototype.close;
  const ledgers = new Set();
  DatabaseSync.prototype.exec = function(sql) {
    if (sql.includes('CREATE TABLE IF NOT EXISTS effect_ledger_entries') &&
        state.phase === 'recovered') ledgers.add(this);
    return exec.call(this, sql);
  };
  DatabaseSync.prototype.close = function() {
    if (ledgers.has(this) && blocked('recoveredLedger')) fail('recoveredLedger');
    return close.call(this);
  };
  DatabaseSync.prototype.prepare = function(sql) {
    if (sql.includes('physical_close_confirmed = 1') && blocked('stopObservation')) {
      fail('stopObservation');
    }
    return prepare.call(this, sql);
  };
  t.after(() => {
    DatabaseSync.prototype.prepare = prepare;
    DatabaseSync.prototype.exec = exec;
    DatabaseSync.prototype.close = close;
  });
  return Object.assign(state, {hooks: hooks => ({...hooks,
    async prepareCaptured(facts) {
      state.phase = 'captured'; state.captures++;
      return stageOf(await hooks.prepareCaptured(facts));
    },
    async prepareRecovered(facts) {
      state.phase = 'recovered'; state.recoveries++;
      return stageOf(await hooks.prepareRecovered(facts));
    }}), facts(facts, path) {
      const result = {...facts,
        retainExecution(owner) {
          state.custody = owner;
          facts.retainExecution(owner);
        },
        effectAuthorization: async options => {
          const gate = await facts.effectAuthorization(options);
          return wrapOwner(gate, 'commitClose');
        }};
      if (path === 'execute') {
        if (facts.targetReads !== undefined) {
          result.targetReads = wrapOwner(facts.targetReads, 'targetClose');
        }
        result.openComputation = async options => {
          state.computes++;
          const opened = await facts.openComputation(options);
          return {...opened,
            cleanupOwner: wrapOwner(opened.cleanupOwner ?? opened.execution, 'computeClose')};
        };
      } else if (facts.prepareTargetReads !== undefined) {
        result.prepareTargetReads = async claimed => {
          const gate = await facts.prepareTargetReads(claimed);
          return gate === undefined ? undefined : wrapOwner(gate, 'targetClose');
        };
      }
      return result;
    }});
}

function exactValueProgram(x) {
  const original = 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
  const program = JSON.parse(x.program);
  const values = program.stages[0].steps[0].values;
  values.schema.original = {type: 'string', nullable: false};
  for (const row of values.rows) row.original = original;
  program.stages[0].results.rows.fields.push('original');
  x.program = JSON.stringify(program);
  return ids.map(id => ({id, original}));
}

for (const failed of ['targetClose', 'commitClose', 'inputs', 'computeClose',
  'stage', 'recoveredLedger', 'stopObservation']) {
  test(`integrated Run retains ${failed} custody across both approvals and exact-value restarts`,
    {timeout: 30_000}, async t => {
    const fault = integratedFault(t, failed);
    const x = await setup(t, {read: 'delegate'});
    const expected = exactValueProgram(x);
    const before = x.installation.org.seen.length;
    const options = {configuration: x.configuration, instrument: fault,
      decisionOptions: {decisionTimeoutMs: 250, maxInFlightDecisions: 1,
        maxRetainedDecisions: 32}};
    let host = await remoteHost(t, x.installation, x.directory, options);
    let run = await (await host.as('owner-token')).aql(x.program,
      {format: 'json', requestId: 'integrated-' + failed});
    const ref = run.ref;
    let recoveredFailure;
    const closePhase = async shouldFail => {
      const io = x.installation.org.seen.length;
      if (shouldFail) {
        await assert.rejects(host.close(), error => {
          recoveredFailure = error;
          assert.equal(error.cleanupPending, true);
          assert.equal(typeof error.cleanupHandle?.retry, 'function');
          assert.ok(error.cleanupHandle.status().pending.length > 0);
          return true;
        });
        assert.ok(fault.injections > 0, 'the selected physical failure must actually fire');
        const completed = fault.owners.filter(value => value.completed)
          .map(value => [value, value.close, value.cleanup]);
        fault.armed = false;
        await recoveredFailure.cleanupHandle.retry();
        assert.deepEqual(recoveredFailure.cleanupHandle.status().pending, []);
        await recoveredFailure.cleanupHandle.retry();
        for (const [value, closes, cleanups] of completed) {
          assert.equal(value.close, closes, 'completed children are not closed twice');
          assert.equal(value.cleanup, cleanups, 'retry only visits pending children');
        }
      }
      const remaining = await host.close();
      if (remaining !== undefined) {
        assert.equal(remaining.storeCleanupPending, false);
        assert.deepEqual(remaining.pendingRetention, []);
      }
      assert.equal(x.installation.org.seen.length, io,
        'cleanup cannot reacquire or dispatch provider work');
    };
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    let [checkpoint] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(checkpoint.kind, 'read_access');
    assert.equal(x.installation.org.seen.length, before);
    await closePhase(['targetClose', 'stopObservation'].includes(failed));
    await answer(t, x, checkpoint, 'approved', ref.authorityScopeCid);
    host = await remoteHost(t, x.installation, x.directory, options);
    run = await (await host.as('owner-token')).attach(ref);
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    [checkpoint] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    assert.deepEqual(run.ref, ref);
    assert.equal(writesOf(x.installation.org).length, 0);
    await closePhase(['commitClose', 'inputs', 'computeClose', 'stage'].includes(failed));
    await answer(t, x, checkpoint, 'approved', ref.authorityScopeCid);
    host = await remoteHost(t, x.installation, x.directory, options);
    run = await (await host.as('owner-token')).attach(ref);
    await waitFor(async () => (await run.status()).status === 'succeeded');
    assert.deepEqual(await run.result('answer').all(), expected);
    assert.equal(writesOf(x.installation.org).length, 2);
    await closePhase(failed === 'recoveredLedger');
    assert.equal(fault.computes, 1, 'approval and cleanup reuse the original computation');
    assert.equal(fault.captures, 1);
    assert.equal(fault.recoveries, 1);
    assert.ok(fault.injections > 0);
    const io = x.installation.org.seen.length;
    host = await remoteHost(t, x.installation, x.directory, options);
    run = await (await host.as('owner-token')).attach(ref);
    assert.equal((await run.status()).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), expected);
    await host.close();
    assert.equal(x.installation.org.seen.length, io);
    t.diagnostic(JSON.stringify({baseline: '91ae3cb79fe7431e75fccfcb55a1ee59b84a5cc3',
      failure: failed, runDefinitionCid: ref.runDefinitionCid,
      injections: fault.injections, computes: fault.computes,
      captures: fault.captures, recoveries: fault.recoveries,
      writes: writesOf(x.installation.org).length}));
  });
}

for (const boundary of ['acquisition', 'effect_commit']) {
  test(`integrated Run keeps a timed-out ${boundary} callback through shutdown retry`,
    {timeout: 20_000}, async t => {
    const x = await setup(t, {read: 'delegate'});
    exactValueProgram(x);
    let host, run;
    const requestId = 'integrated-timeout-' + boundary;
    if (boundary === 'effect_commit') {
      host = await remoteHost(t, x.installation, x.directory,
        {configuration: x.configuration});
      run = await (await host.as('owner-token')).aql(x.program,
        {format: 'json', requestId});
      await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
      const [read] = (await (await host.as('reviewer-token')).checkpoints()).items;
      assert.equal(read.kind, 'read_access');
      await host.close();
      await answer(t, x, read, 'approved', run.ref.authorityScopeCid);
    }
    const calls = [];
    const decide = (view, {signal}) => new Promise(settle => {
      calls.push({view, signal, settle});
    });
    t.after(async () => {
      for (const call of calls) call.settle({decision: 'unavailable'});
      await new Promise(setImmediate);
    });
    host = await remoteHost(t, x.installation, x.directory,
      {configuration: x.configuration, decide,
        decisionOptions: {decisionTimeoutMs: 40, maxInFlightDecisions: 1,
          maxRetainedDecisions: 32}});
    if (run === undefined) run = await (await host.as('owner-token')).aql(x.program,
      {format: 'json', requestId});
    else run = await (await host.as('owner-token')).attach(run.ref);
    await waitFor(() => calls.length === 1);
    assert.equal(calls[0].view.boundary, boundary);
    await waitFor(() => calls[0].signal.aborted);
    assert.equal(writesOf(x.installation.org).length, 0);
    assert.ok(!['succeeded', 'cancelled'].includes((await run.status()).status));
    let failure;
    await assert.rejects(host.close(), error => {
      failure = error;
      assert.equal(error.cleanupPending, true);
      assert.equal(typeof error.cleanupHandle?.retry, 'function');
      return true;
    });
    const io = x.installation.org.seen.length;
    const handle = failure.cleanupHandle;
    await assert.rejects(handle.retry(), error => error.cleanupPending === true);
    assert.ok(handle.status().pending.length > 0,
      'deadline and repeated close cannot reclaim an unfinished callback');
    assert.equal(calls.length, 1);
    calls[0].settle({decision: 'permit', subject: calls[0].view.subject,
      authority: 'reviewer'});
    await new Promise(setImmediate);
    try { await handle.retry(); }
    catch (error) {
      const describe = failure => ({code: failure?.code, message: failure?.message,
        pending: failure?.cleanupHandle?.status?.(),
        errors: failure?.cleanupErrors?.map(item => ({owner: item.owner,
          code: item.error?.code, message: item.error?.message,
          status: item.error?.cleanupHandle?.status?.()}))});
      t.diagnostic(JSON.stringify({callbackBoundary: boundary,
        retained: await retained(x), failure: describe(error)}));
      throw error;
    }
    assert.deepEqual(handle.status().pending, []);
    await handle.retry();
    await host.close();
    assert.equal(calls.length, 1, 'cleanup cannot ask for another decision');
    assert.equal(x.installation.org.seen.length, io,
      'late permit cannot dispatch or reacquire the timed-out Run');
    assert.equal(writesOf(x.installation.org).length, 0);
    if (boundary === 'effect_commit') {
      const kept = await retained(x);
      assert.ok(kept.holdings.length > 0 && kept.objects.length > 0,
        'releasing process-local payloads cannot erase the durable capture');
      const restarted = await remoteHost(t, x.installation, x.directory,
        {configuration: x.configuration, decide});
      const attached = await (await restarted.as('owner-token')).attach(run.ref);
      assert.deepEqual(attached.ref, run.ref);
      assert.ok(!['succeeded', 'cancelled'].includes((await attached.status()).status));
      await restarted.close();
      assert.equal(calls.length, 1, 'restart does not request a replacement judgment');
      assert.equal(x.installation.org.seen.length, io, 'restart cannot resend the Run');
    }
    t.diagnostic(JSON.stringify({boundary, configuredTimeoutMs: 40,
      runDefinitionCid: run.ref.runDefinitionCid, callbacks: calls.length,
      latePermitWrites: writesOf(x.installation.org).length}));
  });
}

for (const capacity of ['physical', 'retained']) {
test(`integrated Run shares one ${capacity} decision slot at target and commit across exact-value restarts`,
  {timeout: 30_000}, async t => {
  const x = await setup(t, {read: 'delegate'});
  const expected = exactValueProgram(x);
  const calls = [];
  const decide = (view, {signal}) => new Promise(settle => {
    calls.push({view, signal, settle});
  });
  t.after(async () => {
    for (const call of calls) call.settle({decision: 'unavailable'});
    await new Promise(setImmediate);
  });
  const options = {configuration: x.configuration, decide,
    decisionOptions: {decisionTimeoutMs: 5_000,
      maxInFlightDecisions: capacity === 'physical' ? 1 : 4,
      maxRetainedDecisions: capacity === 'retained' ? 1 : 32}};
  let host = await remoteHost(t, x.installation, x.directory, options);
  let run = await (await host.as('owner-token')).aql(x.program,
    {format: 'json', requestId: 'integrated-shared-slot'});
  const ref = run.ref;
  let configurationCid, primaryRunId;
  for (const [index, boundary] of ['acquisition', 'effect_commit'].entries()) {
    await waitFor(() => calls.length === index + 1);
    const call = calls[index];
    assert.equal(call.view.boundary, boundary);
    configurationCid ??= call.view.subject.configuration_cid;
    assert.equal(call.view.subject.configuration_cid, configurationCid,
      'execution options never replace account-configuration identity');
    const before = diagnostics.length;
    if (capacity === 'retained') {
      await assert.rejects((await host.as('owner-token')).aql(x.program,
        {format: 'json', requestId: `integrated-contender-${index}`}),
      error => error.code === 'ACTQL_E_DELEGATION_UNAVAILABLE');
    } else {
      const contender = await (await host.as('owner-token')).aql(x.program,
        {format: 'json', requestId: `integrated-contender-${index}`});
      await waitFor(async () => (await contender.status()).status === 'failed');
      assert.ok(diagnostics.slice(before).some(value =>
        JSON.stringify(value).includes('ExecutionAuthorizationDecisionFailed')),
      JSON.stringify(diagnostics.slice(before)));
    }
    assert.equal(calls.length, index + 1, 'a second Run cannot acquire the owned slot');
    assert.equal(writesOf(x.installation.org).length, 0);
    call.settle({decision: 'defer', subject: call.view.subject});
    await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
    const [checkpoint] = (await (await host.as('reviewer-token')).checkpoints()).items;
    assert.equal(checkpoint.kind, index === 0 ? 'read_access' : 'effect_set');
    primaryRunId ??= checkpoint.subject.runId;
    assert.equal(checkpoint.subject.runId, primaryRunId);
    await host.close();
    await answer(t, x, checkpoint, 'approved', ref.authorityScopeCid);
    host = await remoteHost(t, x.installation, x.directory, options);
    run = await (await host.as('owner-token')).attach(ref);
  }
  await waitFor(async () => (await run.status()).status === 'succeeded');
  assert.deepEqual(await run.result('answer').all(), expected);
  assert.equal(calls.length, 2, 'committed approvals do not request replacement judgments');
  assert.equal(writesOf(x.installation.org).length, 2);
  await host.close();
  t.diagnostic(JSON.stringify({runDefinitionCid: ref.runDefinitionCid,
    configurationCid, callbacks: calls.map(call => call.view.boundary),
    deniedContenders: 2, ...options.decisionOptions}));
});
}


// Fail only after the real Host has acquired a complete durable capture. The
// public Result's composite prepared handle can be instrumented without
// replacing the Store's physical holding owner or the ledger connection.
for (const boundary of ['pre-send-abort', 'refresh-io', 'published']) {
  for (const blockedCleanup of [false, true]) {
    test(`captured Run keeps ${boundary} payload custody${blockedCleanup ? ' through cleanup retry' : ''}`,
      {timeout: 20_000}, async t => {
      const x = await setup(t, {commit: 'allow'});
      const abort = new AbortController();
      const primary = new Error(`Injected captured ${boundary}`);
      const cleanupFailure = new Error('Injected prepared payload release');
      const state = {blocked: blockedCleanup, prepared: [], releases: 0,
        inputs: 0, disposals: 0, captures: 0, refusals: 0, refreshes: 0};
      t.after(() => { state.blocked = false; });
      const instrument = {
        observeFailure(error) { state.failure = error; },
        observeResult(result) { state.result = result; },
        hooks: hooks => ({...hooks, async prepareCaptured(facts) {
          const stage = await hooks.prepareCaptured(facts);
          state.captures++;
          state.stage = stage;
          assert.ok(state.prepared.length > 0);
          assert.ok(state.prepared.some(owner => owner.status().pending));
          state.store = facts.store;
          if (boundary === 'pre-send-abort') abort.abort(primary);
          return {...stage,
            apply: {...stage.apply, async refreshPreflight(...args) {
              state.refreshes++;
              if (boundary === 'refresh-io') throw primary;
              return stage.apply.refreshPreflight(...args);
            }},
            releaseInputs() { state.inputs++; return stage.releaseInputs(); },
            dispose() { state.disposals++; return stage.dispose(); }};
        }}),
        facts: facts => ({...facts, signal: abort.signal,
          ...(boundary !== 'published' ? {} : {store: {...facts.store,
            async commitEffectfulIndex(...args) {
              await facts.store.commitEffectfulIndex(...args);
              // The second real Store call observes the committed index.
              const result = await facts.store.commitEffectfulIndex(...args);
              assert.equal(result.idempotent, true);
              state.terminalRelease = true;
              return result;
            }}}),
          retainExecution(owner) { state.custody = owner; facts.retainExecution(owner); },
          observePreEffectFailure() { state.refusals++; facts.observePreEffectFailure?.(); },
          async openComputation(options) {
            const opened = await facts.openComputation(options);
            const original = opened.execution;
            return {...opened, cleanupOwner: opened.cleanupOwner ?? original,
              execution: {...original, async storePublicationResult(...args) {
                const stored = await original.storePublicationResult(...args);
                const prepared = stored.prepared;
                state.prepared.push(prepared);
                const release = async () => {
                  state.releases++;
                  if (state.blocked) throw cleanupFailure;
                  return prepared.release();
                };
                return {...stored, prepared: {status() {
                  // After Store transfer, a failed status observation still
                  // leaves the completed owner responsible for its release.
                  if (state.blocked && state.terminalRelease) throw cleanupFailure;
                  return prepared.status();
                }, release,
                  async retry() { await release(); return prepared.status(); }}};
              }}};
          }}),
      };
      const host = await remoteHost(t, x.installation, x.directory,
        {configuration: x.configuration, instrument,
          decisionOptions: {maxInFlightDecisions: 1, maxRetainedDecisions: 32}});
      const run = await (await host.as('owner-token')).aql(x.program,
        {format: 'json', requestId: `captured-${boundary}-${blockedCleanup}`});
      if (boundary === 'published') {
        if (blockedCleanup) {
          await waitFor(() => state.failure !== undefined);
          assert.ok(state.failure.cleanupErrors.includes(cleanupFailure));
        }
        if (!blockedCleanup) await waitFor(() => state.result?.status === 'published');
        await waitFor(async () => (await run.status()).status === 'succeeded');
      } else {
        await waitFor(() => state.failure !== undefined);
        assert.equal(state.failure, primary, 'the original generic exception stays primary');
      }
      assert.equal(state.refusals, 0, 'generic failures are not definitive pre-send refusals');
      assert.equal(state.captures, 1);
      assert.equal(state.refreshes, boundary === 'pre-send-abort' ? 0 : 1);
      assert.equal(writesOf(x.installation.org).length, boundary === 'published' ? 2 : 0);
      const io = x.installation.org.seen.length;
      const capacity = state.store.status();
      if (blockedCleanup) {
        let failure;
        await assert.rejects(host.close(), error => {
          failure = error;
          assert.equal(error.cleanupPending, true);
          assert.equal(typeof error.cleanupHandle?.retry, 'function');
          return true;
        });
        assert.ok(state.releases > 0, 'captured payload cleanup was attempted');
        assert.equal(state.custody.cleanupPending(), true);
        assert.equal(state.disposals, 0, 'ledger stays owned until payload cleanup finishes');
        await assert.rejects(failure.cleanupHandle.retry());
        const releases = state.releases;
        state.blocked = false;
        try { await failure.cleanupHandle.retry(); }
        catch (error) {
          t.diagnostic(JSON.stringify({code: error.code,
            cleanup: error.failures?.map(item => item.cleanup?.code)}));
          throw error;
        }
        assert.deepEqual(failure.cleanupHandle.status().pending, []);
        if (boundary !== 'published') assert.ok(state.releases > releases);
        const completed = state.releases;
        await failure.cleanupHandle.retry();
        assert.equal(state.releases, completed, 'completed payloads are not released twice');
      }
      let remaining;
      try { remaining = await host.close(); }
      catch (error) {
        t.diagnostic(JSON.stringify({boundary, blockedCleanup,
          code: error.code, pending: error.cleanupHandle?.status(),
          failures: error.cleanupErrors?.map(item => ({owner: item.owner,
            code: item.error?.code, message: item.error?.message,
            stack: item.error?.stack}))}));
        throw error;
      }
      if (remaining !== undefined) {
        assert.equal(remaining.storeCleanupPending, false);
        assert.deepEqual(remaining.pendingRetention, []);
      }
      assert.ok(state.prepared.every(owner => owner.status().pending === false),
        'no process-local prepared Result owner survives Host cleanup');
      assert.equal(state.custody.cleanupPending(), false);
      assert.equal(state.inputs, 1, 'consumer pins are released once');
      assert.equal(state.disposals, 1, 'the ledger connection is disposed once');
      assert.equal(x.installation.org.seen.length, io, 'cleanup performs no provider I/O');
      const kept = await retained(x);
      if (boundary === 'published') {
        assert.ok(kept.holdings.length > 0 && kept.objects.length > 0,
          'terminal payload release cannot retire published Store custody');
      } else {
        assert.deepEqual(kept, {holdings: [], objects: []},
          'the existing Host owner retires an unheld capture after physical stop');
      }
      assert.ok(state.store.status().storedBytes <= capacity.storedBytes,
        'cleanup never duplicates Store capacity');
      assert.ok(state.store.status().objectCount <= capacity.objectCount);
      const restarted = await remoteHost(t, x.installation, x.directory,
        {configuration: x.configuration});
      const attached = await (await restarted.as('owner-token')).attach(run.ref);
      if (boundary === 'published') {
        assert.equal((await attached.status()).status, 'succeeded');
        assert.deepEqual(await attached.result('answer').all(), ids.map(id => ({id})));
      } else {
        assert.ok(!['succeeded', 'cancelled'].includes((await attached.status()).status));
      }
      await restarted.close();
      assert.equal(x.installation.org.seen.length, io, 'restart cannot duplicate the original Run');
      assert.equal(writesOf(x.installation.org).length, boundary === 'published' ? 2 : 0);
    });
  }
}


test('a captured Checkpoint cannot switch an already retained payload owner to retirement',
  async t => {
  const x = await setup(t);
  let captured;
  const instrument = {hooks: hooks => ({...hooks, async prepareCaptured(facts) {
    captured = {stage: await hooks.prepareCaptured(facts), control: facts.control};
    return captured.stage;
  }})};
  const host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration, instrument});
  const run = await (await host.as('owner-token')).aql(x.program,
    {format: 'json', requestId: 'captured-release-mode-conflict'});
  await waitFor(async () => (await run.status()).status === 'waiting_checkpoint');
  assert.throws(() => releaseCompletedRunPreparedPayloads(
    captured.stage.storedResults, captured.control),
  {code: 'CompletedRunResultSetReleaseModeConflict'});
  await host.close();
  const kept = await retained(x);
  assert.ok(kept.holdings.length > 0 && kept.objects.length > 0);
  assert.equal(writesOf(x.installation.org).length, 0);
});


test('an interrupted captured Run keeps transferred custody after repeated receipt I/O failures',
  async t => {
  const x = await setup(t, {commit: 'allow', org: {loseWriteReplyOnce: true}});
  const primary = new Error('Injected receipt evidence I/O');
  const state = {blocked: true, reads: 0, refusals: 0};
  t.after(() => { state.blocked = false; });
  const instrument = {
    observeFailure(error) { state.failure = error; },
    facts: facts => ({...facts,
      retainExecution(owner) { state.custody = owner; facts.retainExecution(owner); },
      observePreEffectFailure() { state.refusals++; facts.observePreEffectFailure?.(); },
      async openComputation(options) {
        const opened = await facts.openComputation(options);
        const owner = opened.cleanupOwner ?? opened.execution;
        return {...opened, cleanupOwner: {...owner,
          cleanup: () => state.blocked ? false : owner.cleanup()}};
      }}),
    hooks: hooks => ({...hooks, async prepareCaptured(facts) {
      const stage = await hooks.prepareCaptured(facts);
      state.prepared = stage.storedResults.results.map(result => result.prepared);
      state.stage = {...stage,
        releaseInputs() {
          if (state.blocked) throw new Error('Injected input pin release');
          return stage.releaseInputs();
        },
        receipt: {...stage.receipt,
          async authorizeEvidenceRead() { state.reads++; throw primary; }}};
      return state.stage;
    }}),
  };
  const host = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration, instrument});
  const run = await (await host.as('owner-token')).aql(x.program,
    {format: 'json', requestId: 'captured-interrupted-receipt'});
  await waitFor(() => state.failure !== undefined);
  assert.equal(state.failure, primary);
  assert.equal(state.refusals, 0);
  assert.equal(state.reads, 1);
  assert.equal(state.custody.cleanupPending(), true);
  const {apply, receipt, publication} = state.stage;
  await assert.rejects(completeInterruptedEffectRun({apply, receipt, publication}, false),
    error => error === primary);
  assert.equal(state.reads, 2);
  assert.equal(writesOf(x.installation.org).length, 1);
  const io = x.installation.org.seen.length;
  state.blocked = false;
  await host.close();
  assert.ok(state.prepared.every(owner => owner.status().pending === false));
  assert.equal(state.custody.cleanupPending(), false);
  const kept = await retained(x);
  assert.ok(kept.holdings.length > 0 && kept.objects.length > 0,
    'physical dispatch has transferred durable capture custody');
  const restarted = await remoteHost(t, x.installation, x.directory,
    {configuration: x.configuration});
  const attached = await (await restarted.as('owner-token')).attach(run.ref);
  assert.ok(!['succeeded', 'cancelled'].includes((await attached.status()).status));
  await restarted.close();
  assert.equal(x.installation.org.seen.length, io);
  assert.equal(writesOf(x.installation.org).length, 1,
    'neither interrupted completion nor cleanup can send the uncertain row again');
});
