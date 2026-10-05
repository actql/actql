// Cross-version state for Salesforce record updates: an installed Remote
// HTTPS Host over the stateful local org, driven only through the public
// Client and real Host processes. The generator (generate-update-state.mjs)
// uses it with the pre-migration product code to save Host state at four
// phases; the resume test (update-state.resume.test.mjs) uses it with the
// current code to resume each one. Nothing here edits a journal or a Store.
import {execFile, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdir, readFile, readdir, stat, writeFile} from 'node:fs/promises';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import * as commonMoon from
  '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {connect} from '../../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from
  '../../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../../host/installed-salesforce-site.mjs';
import {INSTALLED_SALESFORCE_SOURCE_VERSION,
  publishInstalledSalesforceSource} from
  '../../host/installed-salesforce-source.mjs';
import {openSalesforceEffectSiteFixture} from
  '../salesforce-effect-site.fixture.mjs';

export const STATE_VERSION = 'actql-salesforce-update-cross-version/0.1';
export const runtimeUrl = new URL('../../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
export const secret = async () => 'test-only-secret';
// The installed Host's principal is the operating-system user.
export const owner = userInfo().username;
export const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal']]);
const cid = digit => `sha256:${digit.repeat(64)}`;
export const runtimeBundleCid = async () => `sha256:${createHash('sha256')
  .update(await readFile(runtimeUrl)).digest('hex')}`;

const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const accountEntry = (entry_id, outcome, orgId, operation) => ({entry_id,
  outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [`salesforce:${orgId}`]},
  resource: {any_of: ['Test_Record__c']}, operation: {any_of: [operation]}});
// The Effect commit is delegated to the reviewer; target reads are allowed.
export const accountConfiguration = orgId => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-update-cross-version', entries: [
    accountEntry('effect-commit', 'delegate', orgId, 'effect'),
    {entry_id: 'host-run', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['write']}},
    accountEntry('target-read', 'allow', orgId, 'read')]});

// The test-only keys of one generated state: the reviewer's signing key,
// the Host's Checkpoint key and the Site's credential authority.
export function newKeys() {
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  const authority = generateKeyPairSync('ed25519');
  return {reviewerPrivate: pem(reviewer.privateKey),
    reviewerPublic: pem(reviewer.publicKey), hostPrivate: pem(host.privateKey),
    authorityPrivate: pem(authority.privateKey)};
}

// The Host's Checkpoint authorization over `keys`. Approvals do not expire
// within any test's lifetime. On Embedded Local (`local`), the reviewer is
// the local owner.
export const hostAuthorization = (orgId, keys, {local = false} = {}) => ({
  accountConfiguration: accountConfiguration(orgId),
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: local ? owner : 'reviewer-principal',
    publicKey: keys.reviewerPublic}],
  reviewReaders: [local ? owner : 'reviewer-principal'],
  hostKey: {keyId: 'host-key', privateKey: keys.hostPrivate},
  leaseMs: 10_000, resumeAfterAnswer: false,
  checkpointTtlMs: 100 * 365 * 24 * 60 * 60 * 1000});

// The local org at `port` with the certificates in `certificateDirectory`
// (issued for ten years when absent) and the stored records.
export function openOrg(t, {port, certificateDirectory, records,
  holdWrites = [], onHeldWrite, writeOperation = 'update'}) {
  return openSalesforceEffectSiteFixture(t, {commonMoon, salesforceMoon,
    runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    statefulRecords: true, storedRecords: records.map(record => ({...record})),
    storedOrder: records.map((_, index) => index + 1), port,
    certificateDirectory, certificateDays: 3650, holdWrites, onHeldWrite,
    writeOperation});
}

// The installed write of each kind: a Result-backed create, an update and an
// upsert of Test_Record__c. The installed path takes one kind per Set.
export const kindWrites = Object.freeze({
  create: {resource: 'Test_Record__c', kind: 'createFromResult', sources: [
    {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
    {target: 'Name', field: 'id', nullBehavior: 'reject'}]},
  update: {resource: 'Test_Record__c', kind: 'update', fields: ['Name']},
  upsert: {resource: 'Test_Record__c', kind: 'upsert', key: 'External_Key__c',
    fields: ['Name']}});

// Install the source and the Effect `writes` (default: an update of Name)
// under `root` for `org`, and publish both. Returns the paths a Host is
// opened with and the published Mappings.
export async function install({root, org, keys,
  writes = [{resource: 'Test_Record__c', kind: 'update', fields: ['Name']}]}) {
  await mkdir(root, {recursive: true});
  await writeFile(join(root, 'credential.key'), keys.authorityPrivate);
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const sitePath = join(root, 'salesforce-site.json');
  await writeFile(sitePath, JSON.stringify({
    version: INSTALLED_SALESFORCE_SITE_VERSION, apiVersion: 'v62.0',
    cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'credential-journal'), orgId: org.orgId,
    siteGeneration: 1, siteKey: 'salesforce-site',
    namespaceId: 'namespace-a', caPath: join(root, 'org-ca.crt')}));
  const sourceProfile = {version: INSTALLED_SALESFORCE_SOURCE_VERSION,
    siteProfilePath: sitePath,
    publicationPath: join(root, 'source-publication.json'),
    connectorId: 'crm-main', resources: ['Test_Record__c'],
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'salesforce-update-source',
      entries: [accountEntry('records-read', 'allow', org.orgId, 'read')]})};
  const sourceProfilePath = join(root, 'source-profile.json');
  await writeFile(sourceProfilePath, JSON.stringify(sourceProfile));
  const directory = join(root, 'state');
  await publishInstalledSalesforceSource(sourceProfile, {root: directory,
    principalId: owner, moon: commonMoon, providerMoon: salesforceMoon,
    runtimeBundleCid: await runtimeBundleCid(), resolveSecret: secret});
  const effectProfilePath = join(root, 'effect-profile.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: 'actql-installed-salesforce-effect/0.1',
    siteProfilePath: sitePath,
    publicationPath: join(root, 'effect-publication.json'),
    connectorId: 'crm-main',
    accountConfigurationWire: accountConfiguration(org.orgId), writes}));
  const published = await publishInstalledEffect({effectProfilePath,
    directory, resolveEffectSecret: secret});
  return {directory, sourceProfilePath, effectProfilePath,
    mappingRef: published.mappings[0].mappingRef};
}

// One Set of `kind` from the rows `ids` through `mappingRef`: a create keyed
// and named by each id, or an update or upsert naming the record by it.
export const kindProgram = (kind, mappingRef, ids) => {
  const target = 'connector://crm-main/Test_Record__c';
  const effect = kind === 'create'
    ? {create: {target, mapping: mappingRef, from: {result: 'rows'}}}
    : kind === 'update'
      ? {update: {target, mapping: mappingRef, from: {result: 'rows'},
        id: 'id', set: {Name: {field: 'id'}}}}
      : {upsert: {target, mapping: mappingRef, from: {result: 'rows'},
        key: 'id', set: {Name: {field: 'id'}}}};
  return JSON.stringify({version: 'actql/0.1', id: 'client-values',
    stages: [{id: 'source', inputs: {}, steps: [{values: {schema: {
      id: {type: 'string', nullable: false}}, rows: ids.map(id => ({id}))},
    as: 'selected'}], results: {rows: {from: 'selected', fields: ['id']}},
    effects: {save: effect}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}});
};

const tlsMaterial = (() => {
  let material;
  return root => {
    if (material !== undefined) return material;
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey',
      'rsa:2048', '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
      '-subj', '/CN=localhost', '-addext',
      'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
    material = {key: readFileSync(join(root, 'host.key')),
      cert: readFileSync(join(root, 'host.crt'))};
    setDefaultCACertificates([...getCACertificates('default'),
      material.cert.toString('utf8')]);
    return material;
  };
})();

// Open a Remote HTTPS Host in this process over an installation.
export async function openHost({installation, orgId, keys, tlsRoot}) {
  const host = await openInstalledRemoteHttpHost({
    directory: installation.directory,
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    sourceProfilePath: installation.sourceProfilePath,
    resolveSourceSecret: secret,
    effectProfilePath: installation.effectProfilePath,
    resolveEffectSecret: secret,
    authorization: hostAuthorization(orgId, keys)});
  const {key, cert} = tlsMaterial(tlsRoot);
  const server = createServer({key, cert}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const clients = [];
  let closed = false;
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  return {
    async as(token) {
      const client = await connect({mode: 'remote', endpoint, token,
        durability: 'durable'});
      clients.push(client);
      return client;
    },
    async close() {
      if (closed) return;
      closed = true;
      for (const client of clients) await client.close();
      server.closeAllConnections?.();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    }};
}

// Start a Host in a child process over an installation. The child resumes
// approved Runs at start; the caller kills it.
export function startHostProcess({installation, orgId, keys}) {
  const config = JSON.stringify({installation, orgId, keys});
  const child = execFile(process.execPath, [fileURLToPath(new URL(
    './update-state.host-child.mjs', import.meta.url))],
  {env: {...process.env, ACTQL_CROSS_VERSION_HOST: config}});
  child.stdout?.resume();
  child.stderr?.resume();
  return child;
}

// Run one Embedded Local step in a child process; `resume` is returned
// running, for the caller to kill.
export function localStep(step, {installation, orgId, keys, program,
  refPath}) {
  const config = JSON.stringify({installation, orgId, keys, step, program,
    refPath});
  const child = execFile(process.execPath, [fileURLToPath(new URL(
    './update-state.local-child.mjs', import.meta.url))],
  {env: {...process.env, ACTQL_CROSS_VERSION_LOCAL: config}});
  let stdout = '';
  child.stdout?.on('data', chunk => { stdout += chunk; });
  child.stderr?.resume();
  if (step === 'resume') return child;
  return new Promise((resolveStep, rejectStep) => child.once('exit', code =>
    code === 0 ? resolveStep(stdout) : rejectStep(new Error(`LocalStep ${step} ${code}`))));
}

export async function waitFor(check, {attempts = 800} = {}) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('WaitForTimeout');
}

export const terminal = ['succeeded', 'failed', 'needs_reconciliation',
  'cancelled'];

// Approve the one held Set with the reviewer key of `keys`.
export async function approve(host, execution, keys) {
  const reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  if (checkpoint?.kind !== 'effect_set') throw new Error('NoHeldEffectSet');
  const {createPrivateKey} = await import('node:crypto');
  const key = createPrivateKey(keys.reviewerPrivate);
  const answer = await reviewer.resolveCheckpoints([
    {checkpoint, decision: 'approved'}], {signer: {keyId: 'reviewer-key',
    reviewerId: 'reviewer', authorityScopeCid: execution.ref.authorityScopeCid,
    sign: bytes => sign(null, bytes, key)}});
  if (answer.results[0]?.status !== 'committed') {
    throw new Error('ApprovalNotCommitted');
  }
}

// The SHA-256 of every file under `root`, by relative path.
export async function digests(root) {
  const result = {};
  const walk = async directory => {
    for (const entry of await readdir(directory, {withFileTypes: true})) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await walk(path);
      else if ((await stat(path)).isFile()) {
        result[relative(root, path)] = `sha256:${createHash('sha256')
          .update(await readFile(path)).digest('hex')}`;
      }
    }
  };
  await walk(root);
  return Object.fromEntries(Object.entries(result).sort(([a], [b]) =>
    a < b ? -1 : 1));
}
