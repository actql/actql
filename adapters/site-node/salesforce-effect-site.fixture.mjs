import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from
  './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  './remote-credential-signature.mjs';
import {syncSalesforceCatalog} from
  './salesforce-catalog-sync.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

export async function openSalesforceEffectSiteFixture(t, {
  commonMoon, salesforceMoon, runInvocationCid, dispatchRequestCid,
  orgId = '00D000000000001EAA',
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
  const server = createServer({cert, key}, (request, response) => {
    const observed = {method: request.method, path: request.url,
      authorization: request.headers.authorization};
    seen.push(observed);
    if (request.headers.authorization !== 'Bearer test-only-secret') {
      response.writeHead(401).end();
      return;
    }
    const prefix = '/services/data/v62.0/';
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
            defaultedOnCreate: false, createable: true, updateable: true},
        ]}));
      return;
    }
    if (request.method === 'PATCH' && request.url?.startsWith(
        `${prefix}sobjects/Test_Record__c/`)) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        assert.deepEqual(Object.keys(JSON.parse(observed.body)), ['Name']);
        response.writeHead(204).end();
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
        response.end(JSON.stringify([
          {id: null, success: false, errors: [{statusCode: 'INVALID_FIELD',
            message: 'Rejected field', fields: ['Name']}]},
          {id: '001000000000002', success: true, errors: []},
        ]));
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
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['credential-authority-a',
      new Map([['credential-key-a', authority.publicKey]])]]),
  });
  t.after(async () => {
    journal.close();
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  });
  const control = runtimeCore(commonMoon).remoteCredentialControl;
  const scope = operation => Object.freeze({
    issuerAuthority: 'credential-authority-a',
    principal: 'principal-a', tenant: 'tenant-a', environment: 'test',
    siteKey: 'site-a', siteGeneration: 4, runtimeBundleCid: cid('a'),
    connectorRegistration: 'salesforce',
    connectorRevision: 'salesforce/0.1', resourceOrigin: origin,
    operation, runInvocationCid, taskAttempt: 2, dispatchRequestCid,
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 10,
  });
  const authorize = operation => {
    const value = scope(operation);
    const grant = control.prepare(value);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
      keyId: 'credential-key-a', privateKey: authority.privateKey,
    }), control);
    return {grant, scope: value};
  };
  const list = authorize('salesforce:catalog:list');
  const describe = authorize('salesforce:catalog:describe');
  const write = authorize('salesforce:record:update');
  const credential = {orgId, control, journal,
    resolveSecret: async () => 'test-only-secret', ca,
    now: () => 1_999_999_999_999};
  const catalog = await syncSalesforceCatalog({
    moon: salesforceMoon, apiVersion: 'v62.0',
    connectionRevision: 'connection-revision-a', orgId,
    syncOccurrence: 'catalog-sync-a', maxObservationBytes: 10000,
    listAuthorization: {...list, useId: 'list-use'},
    authorizationForDescribe: async name => ({...describe,
      useId: `describe-${name}`}),
    credential,
    listLimits: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxResources: 20, maxSelected: 20, maxNameUnits: 1000},
    describeLimits: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxFields: 20, maxNameUnits: 1000},
  });
  assert.equal(catalog.status, 'complete');
  return {seen, journal, orgId, origin, catalog, write, credential};
}
