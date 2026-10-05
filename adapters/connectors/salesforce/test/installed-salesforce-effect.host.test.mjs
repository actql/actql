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
  resumeAfterAnswer = true, beforeDispatch, decide, loseResolveReply = false} = {}) {
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
    authorization: {accountConfiguration: configuration, reviewers, decide,
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
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    server.closeAllConnections?.();
    await new Promise(resolve => server.close(resolve));
    const remaining = await host.close();
    effect.close();
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
async function setup(t, {targets = ['Test_Record__c'], ...options} = {}) {
  const configuration = hostConfiguration(options);
  const installation = await installedEffect(t, {
    writes: targets.map(resource => ({resource, kind: 'update',
      fields: ['Name']})),
    org: {writableObjects: ['Other_Record__c']},
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
