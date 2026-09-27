import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION, installSalesforceAuthorization,
  loadInstalledSalesforceSite} from '../host/installed-salesforce-site.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

// The Host account configuration for the local orgs: Test_Record__c reads
// and Effects are allowed; nothing else is configured.
export function salesforceSiteAccountConfiguration(orgIds) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'salesforce-test-account',
    entries: [{
      entry_id: 'test-records', outcome: 'allow', exclusions: [],
      principal: {all: true},
      connection: {any_of: orgIds.map(orgId => `salesforce:${orgId}`)},
      resource: {any_of: ['Test_Record__c']},
      operation: {any_of: ['effect', 'read']},
    }],
  });
}

export async function openSalesforceEffectSiteFixture(t, {
  commonMoon, salesforceMoon, runInvocationCid, dispatchRequestCid,
  orgId = '00D000000000001EAA',
  loseWriteReplyOnce = false,
  rateLimitWriteOnce = false,
  collectionPartial = true,
  writeOperation = 'update',
  authorization,
}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-site-'));
  const openssl = (...args) => execFileSync('openssl', args,
    {cwd: root, stdio: 'ignore'});
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl('req', '-x509', '-new', '-key', 'ca.key', '-out',
    'ca.crt', '-subj', '/CN=ActQL Effect Test CA', '-days', '1');
  openssl('genrsa', '-out', 'resource.key', '2048');
  openssl('req', '-new', '-key', 'resource.key', '-out',
    'resource.csr', '-subj', '/CN=localhost');
  await writeFile(join(root, 'resource.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n');
  openssl('x509', '-req', '-in', 'resource.csr', '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', 'resource.crt',
    '-days', '1', '-extfile', 'resource.ext');
  const [ca, cert, key] = await Promise.all([
    readFile(join(root, 'ca.crt')),
    readFile(join(root, 'resource.crt')),
    readFile(join(root, 'resource.key')),
  ]);
  const seen = [];
  let loseReply = loseWriteReplyOnce;
  let rateLimitReply = rateLimitWriteOnce;
  let observedName = 'before';
  let nameUpdateable = true;
  const server = createServer({cert, key}, (request, response) => {
    const observed = {method: request.method, path: request.url,
      authorization: request.headers.authorization};
    seen.push(observed);
    if (request.headers.authorization !== 'Bearer test-only-secret') {
      response.writeHead(401).end();
      return;
    }
    const prefix = '/services/data/v62.0/';
    if (request.method === 'GET' && request.url?.startsWith(`${prefix}query?q=`)) {
      // Three stored records answer a bounded preview query.
      const soql = decodeURIComponent(request.url.slice(
        `${prefix}query?q=`.length));
      const match = /^SELECT ([A-Za-z_,]+) FROM Test_Record__c LIMIT ([0-9]+)$/u
        .exec(soql);
      if (match === null) {
        response.writeHead(400, {'content-type': 'application/json'});
        response.end('[{"errorCode":"MALFORMED_QUERY"}]');
        return;
      }
      const stored = [1, 2, 3].map(index => ({Id: `a0000000000000${index}`,
        Name: `record-${index}`, External_Key__c: `key-${index}`}));
      const records = stored.slice(0, Number(match[2])).map(record =>
        Object.fromEntries([['attributes', {type: 'Test_Record__c'}],
          ...match[1].split(',').map(name => [name, record[name]])]));
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({totalSize: records.length, done: true,
        records}));
      return;
    }
    if (request.method === 'GET' && request.url ===
        `${prefix}sobjects/`) {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({sobjects: [{name: 'Test_Record__c',
        queryable: true, createable: true, updateable: true}]}));
      return;
    }
    if (request.method === 'GET' && request.url ===
        `${prefix}sobjects/Test_Record__c/describe`) {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({name: 'Test_Record__c', queryable: true,
        createable: true, updateable: true, fields: [
          {name: 'Id', type: 'id', nillable: false},
          {name: 'Name', type: 'string', nillable: false,
            defaultedOnCreate: false, createable: true,
            updateable: nameUpdateable},
          {name: 'External_Key__c', type: 'string', externalId: true,
            unique: true, caseSensitive: true, nillable: false,
            defaultedOnCreate: false, createable: true,
            updateable: true},
        ]}));
      return;
    }
    if (request.method === 'GET' && request.url?.startsWith(
        `${prefix}sobjects/Test_Record__c/`)) {
      const target = decodeURIComponent(request.url.slice(
        `${prefix}sobjects/Test_Record__c/`.length).split('/').at(-1));
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({Id: target, Name: observedName,
        External_Key__c: target}));
      return;
    }
    if (request.method === 'POST' && request.url ===
        `${prefix}sobjects/Test_Record__c/`) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        assert.deepEqual(JSON.parse(observed.body), {
          External_Key__c: JSON.parse(observed.body).Name,
          Name: JSON.parse(observed.body).Name,
        });
        if (loseReply) {
          loseReply = false;
          request.socket.destroy();
          return;
        }
        if (rateLimitReply) {
          rateLimitReply = false;
          response.writeHead(403, {'content-type': 'application/json'});
          response.end(JSON.stringify([{message: 'Request limit exceeded',
            errorCode: 'REQUEST_LIMIT_EXCEEDED'}]));
          return;
        }
        const sequence = seen.filter(item => item.method === 'POST').length;
        response.writeHead(201, {'content-type': 'application/json'});
        response.end(JSON.stringify({id: `a0012345678901${sequence}`,
          success: true, errors: []}));
      });
      return;
    }
    if (request.method === 'PATCH' && request.url?.startsWith(
        `${prefix}sobjects/Test_Record__c/`)) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        assert.deepEqual(Object.keys(JSON.parse(observed.body)), ['Name']);
        if (loseReply) {
          loseReply = false;
          request.socket.destroy();
          return;
        }
        if (rateLimitReply) {
          rateLimitReply = false;
          response.writeHead(403, {'content-type': 'application/json'});
          response.end(JSON.stringify([{message: 'Request limit exceeded',
            errorCode: 'REQUEST_LIMIT_EXCEEDED'}]));
          return;
        }
        if (writeOperation === 'upsert') {
          const sequence = seen.filter(item => item.method === 'PATCH').length;
          response.writeHead(200, {'content-type': 'application/json'});
          response.end(JSON.stringify({id: `a0012345678901${sequence}`,
            success: true, errors: [], created: false}));
        } else {
          response.writeHead(204).end();
        }
      });
      return;
    }
    if (request.method === 'PATCH' && request.url ===
        `${prefix}composite/sobjects`) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        const batch = JSON.parse(observed.body);
        assert.equal(batch.allOrNone, false);
        assert.equal(batch.records.length, 2);
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(batch.records.map((_, index) =>
          collectionPartial && index === 0
            ? {id: null, success: false, errors: [
              {statusCode: 'INVALID_FIELD', message: 'Rejected field',
                fields: ['Name']}]}
            : {id: `00100000000000${index + 1}`, success: true,
              errors: []})));
      });
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  // The Site is installed from a Host profile and the Host's account gate;
  // the test supplies only the local org and its secret.
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), ca);
  const profilePath = join(root, 'salesforce-site.json');
  await writeFile(profilePath, JSON.stringify({
    version: INSTALLED_SALESFORCE_SITE_VERSION, apiVersion: 'v62.0',
    cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'credential-authority-a',
    credentialKeyId: 'credential-key-a',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: origin,
    journalRoot: join(root, 'journal'), orgId, siteGeneration: 4,
    siteKey: 'site-a', tenant: 'tenant-a', caPath: join(root, 'org-ca.crt'),
  }));
  const hostAuthorization = authorization ??
    await installSalesforceAuthorization({
      accountConfiguration: salesforceSiteAccountConfiguration([orgId]),
      principalId: 'principal-a', root});
  const installed = await loadInstalledSalesforceSite(profilePath, {
    commonMoon, salesforceMoon, authorization: hostAuthorization,
    runtimeBundleCid: cid('a'), resolveSecret: async () => 'test-only-secret',
    now: () => 1_999_999_999_999, grantLifetimeMs: 1});
  const journal = installed.credential.journal;
  t.after(async () => {
    installed.close();
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  });
  const control = installed.credential.control;
  const dispatch = {runInvocationCid, taskAttempt: 2, dispatchRequestCid};
  // Record grants follow the Host gate's own dispatch for this org's
  // Test_Record__c; the gate still decides each commit separately.
  const recordGrant = async (operation, boundary, operationClass) => {
    const decision = await hostAuthorization.authorize(boundary, {
      connection: installed.connection, resource: 'Test_Record__c',
      operation: operationClass}, {subjectCid: runInvocationCid});
    return installed.issueGrant({operation, decision,
      resource: 'Test_Record__c', ...dispatch, maxUses: 32});
  };
  const observe = await recordGrant('salesforce:record:observe',
    'acquisition', 'read');
  const write = await recordGrant(`salesforce:record:${writeOperation}`,
    'effect_commit', 'effect');
  const credential = installed.credential;
  let catalogSequence = 0;
  const catalogLimits = {
    list: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxResources: 20, maxSelected: 20, maxNameUnits: 1000},
    describe: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxFields: 20, maxNameUnits: 1000},
    maxObservationBytes: 10000,
  };
  const refreshCatalog = async ({signal} = {}) => {
    const sequence = catalogSequence++;
    return await installed.refreshCatalog({...dispatch,
      occurrence: sequence === 0 ? 'catalog-sync-a' :
        `catalog-sync-${sequence}`,
      retainResponses: sequence === 0,
      maxRetainedBytes: sequence === 0 ? 30000 : 0,
      // One dispatch's metadata grants serve every refresh of the Run.
      limits: catalogLimits, grantUses: 32, signal});
  };
  const catalog = await refreshCatalog();
  assert.equal(catalog.status, 'complete');
  const recoveryGrant = authorization => Object.freeze({
    cid: control.identity(authorization.grant),
    wire: control.json(authorization.grant),
  });
  const recoveryConnection = Object.freeze({
    origin, orgId,
    caBase64: ca.toString('base64'),
    journalRoot: join(root, 'journal'),
    authorityPublicKey: authority.publicKey.export({
      type: 'spki', format: 'pem',
    }),
    list: recoveryGrant(catalog.grants.list),
    describe: recoveryGrant(catalog.grants.describe),
    observe: recoveryGrant(observe),
    write: recoveryGrant(write),
  });
  return {seen, journal, orgId, origin, catalog, observe, write, credential,
    refreshCatalog, recoveryConnection,
    setTargetName(name) { observedName = name; },
    setNameUpdateable(value) { nameUpdateable = value; }};
}
