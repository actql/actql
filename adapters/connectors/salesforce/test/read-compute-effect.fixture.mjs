// Acceptance assembly for Read→Compute→Effect through the public Client: a
// stateful local HTTPS org, the installed Salesforce source and Effect of one
// Site on one Host, and a Program that acquires records, filters and derives
// a value locally, and updates the same records. Every expected value below
// is written by hand from the org's stored records; none is derived from
// ActQL output.
import assert from 'node:assert/strict';
import {execFile, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readdir, readFile, rm, unlink, writeFile} from
  'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {connect, RequestHeld} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from
  '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../host/installed-salesforce-site.mjs';
import {INSTALLED_SALESFORCE_SOURCE_VERSION,
  publishInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'salesforce-read-compute-effect');
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
after(() => rm(tlsRoot, {recursive: true, force: true}));

const owner = userInfo().username;
const cid = digit => `sha256:${digit.repeat(64)}`;
export const runtimeBundleCid = `sha256:${createHash('sha256').update(
  await readFile(new URL(
    '../../../../_build/js/release/build/connectors_builtin_node/' +
    'connectors_builtin_node.js', import.meta.url))).digest('hex')}`;
export const secret = async () => 'test-only-secret';
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
export const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal']]);

// --- Independent expectations -------------------------------------------

// The org's stored records. The Program keeps every record whose Name is not
// 'record-2' and derives `next_name` = External_Key__c + '-processed'.
export const storedRecords = Object.freeze([
  {Id: 'a00000000000001', Name: 'record-1', External_Key__c: 'key-1'},
  {Id: 'a00000000000002', Name: 'record-2', External_Key__c: 'key-2'},
  {Id: 'a00000000000003', Name: 'record-3', External_Key__c: 'key-3'},
]);
// Four records for halt and continue: three are targets.
export const fourRecords = Object.freeze([...storedRecords,
  {Id: 'a00000000000004', Name: 'record-4', External_Key__c: 'key-4'}]);
// The Named Result `updates`, in Id order.
export const expectedUpdates = Object.freeze([
  {Id: 'a00000000000001', next_name: 'key-1-processed'},
  {Id: 'a00000000000003', next_name: 'key-3-processed'},
]);
// The provider bodies, by target Id.
export const expectedBodies = Object.freeze({
  a00000000000001: '{"Name":"key-1-processed"}',
  a00000000000003: '{"Name":"key-3-processed"}',
  a00000000000004: '{"Name":"key-4-processed"}',
});
// The org after the success path: the two targets renamed, the filtered-out
// record untouched.
export const expectedOrgAfterSuccess = Object.freeze([
  {Id: 'a00000000000001', Name: 'key-1-processed', External_Key__c: 'key-1'},
  {Id: 'a00000000000002', Name: 'record-2', External_Key__c: 'key-2'},
  {Id: 'a00000000000003', Name: 'key-3-processed', External_Key__c: 'key-3'},
]);

// --- The Program ----------------------------------------------------------

// Acquire the records view (scan, filter, select), derive the new name
// locally, and update the same records by Id. `onItemFailure` 'continue'
// makes the rows independent; the default halts at the first failed row.
export function readComputeEffectProgram(mappingRef, {onItemFailure} = {}) {
  const update = {target: 'connector://crm-main/Test_Record__c',
    mapping: mappingRef, from: {result: 'updates'}, id: 'Id',
    set: {Name: {field: 'next_name'}},
    ...(onItemFailure === undefined ? {}
      : {on_item_failure: onItemFailure})};
  return JSON.stringify({version: 'actql/0.1', id: 'salesforce-rce',
    stages: [
      {id: 'acquire',
        inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
        steps: [{filter: "Name <> 'record-2'", as: 'filtered'},
          {select: ['Id', 'External_Key__c'], as: 'captured'}],
        results: {r: {from: 'captured', fields: ['Id', 'External_Key__c']}}},
      {id: 'compute',
        inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
        steps: [
          {derive: {next_name: "concat(External_Key__c, '-processed')"},
            as: 'derived'},
          {select: ['Id', 'next_name'], as: 'out'}],
        results: {updates: {from: 'out', fields: ['Id', 'next_name']}},
        effects: {save: {update}}},
    ],
    results: {updates: {from: {stage: 'compute', result: 'updates'}}}});
}

// A submission refused because the common path does not yet run an Effect
// from an acquisition: recorded as not connected, never as a defect of the
// Salesforce side and never as passing.
export async function submitReadComputeEffect(client, program, requestId) {
  try {
    return await client.aql(program, {format: 'json', requestId});
  } catch (error) {
    if (error?.code === 'ClientProgramUnsupported') {
      throw Object.assign(new Error('ReadComputeEffectNotConnected: the ' +
        'common Host refuses an Effect Program that acquires from a source ' +
        '(ClientProgramUnsupported); this waits on the common path.',
      {cause: error}), {code: 'ReadComputeEffectNotConnected'});
    }
    throw error;
  }
}

// --- The installation -----------------------------------------------------

const accountEntry = (entry_id, outcome, orgId, operation) => ({entry_id,
  outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [`salesforce:${orgId}`]},
  resource: {any_of: ['Test_Record__c']}, operation: {any_of: [operation]}});

// The Host's account configuration: the Effect commit is delegated to the
// reviewer, Host runs and target reads are allowed. `effect` overrides the
// commit entry's outcome.
export const hostAccountConfiguration = (orgId, {effect = 'delegate'} = {}) =>
  canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'salesforce-rce-host', entries: [
      accountEntry('effect-commit', effect, orgId, 'effect'),
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}},
      accountEntry('target-read', 'allow', orgId, 'read'),
    ]});

export const checkpointAuthorization = (accountConfiguration, extra) => ({
  accountConfiguration,
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}],
  reviewReaders: ['reviewer-principal'],
  hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
  leaseMs: 10_000, resumeAfterAnswer: false, ...extra});

// One Site with its source and Effect installed on one Host over the
// stateful org. `org` options go to the shared org fixture.
// `sourceRead` is the source profile's read decision: 'allow', 'deny', or
// 'delegate' (a deferred read, which this path refuses).
// `writes` are the installed Effect writes (default: an update of Name).
export async function readComputeEffectInstallation(t, {org: orgOptions = {},
  records = storedRecords, sourceRead = 'allow',
  writes = [{resource: 'Test_Record__c', kind: 'update',
    fields: ['Name']}]} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    statefulRecords: true, storedRecords: records.map(record => ({...record})),
    storedOrder: records.map((_, index) => index + 1), ...orgOptions});
  const root = await mkdtemp(join(scratch, 'host-'));
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
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
      account_id: 'salesforce-rce-source',
      entries: [accountEntry('records-read', 'allow', org.orgId,
        'read')]})};
  const sourceProfilePath = join(root, 'source-profile.json');
  await writeFile(sourceProfilePath, JSON.stringify(sourceProfile));
  const hostRoot = join(root, 'state');
  await publishInstalledSalesforceSource(sourceProfile, {root: hostRoot,
    principalId: owner, moon: commonMoon, providerMoon: salesforceMoon,
    runtimeBundleCid,
    resolveSecret: secret});
  // The read decision the Host then runs under; the publication itself
  // described the Resource under an allowed read.
  if (sourceRead !== 'allow') {
    await writeFile(sourceProfilePath, JSON.stringify({...sourceProfile,
      accountConfigurationWire: canonicalJson({
        version: 'actql-execution-account-config/0.1',
        account_id: 'salesforce-rce-source',
        entries: [accountEntry('records-read', sourceRead, org.orgId,
          'read')]})}));
  }
  const effectProfilePath = join(root, 'effect-profile.json');
  const writeEffectProfile = accountConfigurationWire => writeFile(
    effectProfilePath, JSON.stringify({
      version: 'actql-installed-salesforce-effect/0.1',
      siteProfilePath: sitePath,
      publicationPath: join(root, 'effect-publication.json'),
      connectorId: 'crm-main', accountConfigurationWire,
      writes}));
  await writeEffectProfile(hostAccountConfiguration(org.orgId));
  const published = await publishInstalledEffect({effectProfilePath,
    directory: hostRoot, resolveEffectSecret: secret});
  const mappingRef = published.mappings[0].mappingRef;

  // Open the Remote HTTP Host over this installation.
  const openHost = async ({accountConfiguration =
    hostAccountConfiguration(org.orgId), authorization: extra,
  diagnostics = []} = {}) => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
      sourceProfilePath, resolveSourceSecret: secret,
      effectProfilePath, resolveEffectSecret: secret,
      authorization: checkpointAuthorization(accountConfiguration, {
        observe: (name, detail) => diagnostics.push({name, detail}),
        ...extra})});
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
    };
    closers.push(close);
    const endpoint = `https://127.0.0.1:${server.address().port}/`;
    const as = async token => {
      const connected = await connect({mode: 'remote', endpoint, token,
        durability: 'durable'});
      closers.push(() => connected.close());
      return connected;
    };
    return {as, close, diagnostics};
  };

  // Run the Embedded steps of one request, each in a new process over this
  // installation: the local owner submits, reviews and resumes.
  const embedded = async (requestId, program, {accountConfiguration =
    hostAccountConfiguration(org.orgId)} = {}) => {
    const path = join(root, `embedded-${requestId}.json`);
    await writeFile(path, JSON.stringify({directory: hostRoot,
      sourceProfilePath, effectProfilePath, program, requestId,
      reviewerPrivateKey: pem(reviewerKeys.privateKey),
      authorization: {...checkpointAuthorization(accountConfiguration),
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: owner, publicKey: pem(reviewerKeys.publicKey)}],
        reviewReaders: [owner]}}));
    return step => new Promise((resolve, reject) => {
      execFile(process.execPath, [fileURLToPath(new URL(
        './read-compute-effect.embedded-child.mjs', import.meta.url)),
      step, path], {timeout: 120_000}, (error, stdout, stderr) => {
        if (error) {
          reject(Object.assign(error, {stdout, stderr}));
          return;
        }
        resolve(JSON.parse(stdout.trim().split('\n').at(-1)));
      });
    });
  };

  const count = predicate => org.seen.filter(predicate).length;
  const prefix = '/services/data/v62.0/';
  // The durable objects of a held Effect, by role, from the Store's own
  // physical holding manifests (never by guessing file names or taking a
  // manifest's first entry):
  // - 'effect-input': the Effect input body, named by an `effect-source`
  //   holding;
  // - 'upstream-dependency': a body only the `effect-capture` holding names,
  //   such as an acquired Program's upstream Stage Result.
  const heldObjects = async () => {
    const holdings = [];
    const walk = async directory => {
      for (const entry of await readdir(directory, {withFileTypes: true})) {
        const path = join(directory, entry.name);
        if (entry.isDirectory()) await walk(path);
        else if (entry.name.endsWith('.json') &&
            directory.includes('physical-holdings')) {
          const holding = JSON.parse(await readFile(path, 'utf8'));
          const store = directory.slice(0,
            directory.indexOf('physical-holdings'));
          holdings.push({namespace: holding.namespace,
            objects: holding.objects.map(object =>
              join(store, 'objects', object.cid.slice(7)))});
        }
      }
    };
    await walk(hostRoot);
    const named = namespace => new Set(holdings.filter(holding =>
      holding.namespace === namespace).flatMap(holding => holding.objects));
    const input = named('effect-source');
    return {
      'effect-input': [...input],
      'upstream-dependency': [...named('effect-capture')].filter(path =>
        !input.has(path)),
    };
  };
  // Remove or alter exactly one durable object of `role` while the Host is
  // stopped. Exactly one object per role is expected here; anything else
  // means the inventory changed and the test must choose again.
  const damageHeld = async (role, kind) => {
    const objects = (await heldObjects())[role];
    assert.equal(objects?.length, 1, `expected one ${role} object`);
    const [path] = objects;
    if (kind === 'missing') {
      await unlink(path);
    } else {
      const bytes = await readFile(path);
      bytes[bytes.length - 1] ^= 0x01;
      await writeFile(path, bytes);
    }
  };
  return {org, root, mappingRef, openHost, writeEffectProfile, embedded,
    heldObjects, damageHeld,
    program: options => readComputeEffectProgram(mappingRef, options),
    // Source acquisitions (queries), target check reads, and writes are
    // counted apart.
    queries: () => count(item => item.method === 'GET' &&
      item.path.startsWith(`${prefix}query`)),
    targetReads: () => count(item => item.method === 'GET' &&
      /\/sobjects\/Test_Record__c\/[^/]+$/u.test(item.path) &&
      !item.path.endsWith('/describe')),
    writes: () => org.seen.filter(item => item.method === 'PATCH' ||
      item.method === 'POST')};
}

// Approve the one held Effect Set as the reviewer.
export async function approveHeldSet(host, execution) {
  const reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  assert.equal(checkpoint?.kind, 'effect_set');
  const answer = await reviewer.resolveCheckpoints([
    {checkpoint, decision: 'approved'}], {signer: {...signer,
    authorityScopeCid: execution.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
  return checkpoint;
}

export async function waitFor(check, {attempts = 400} = {}) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('WaitForTimeout');
}

export {RequestHeld};
