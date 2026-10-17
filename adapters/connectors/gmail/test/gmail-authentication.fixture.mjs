// Actual existing Common/Account/Credential/SQLite/TLS caller composition.
// Fixture grants, RSA material and canonical RowRun amounts are independent
// test originals; they are not normal Site/material issuers or full funding.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, verify} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {Agent, createServer} from 'node:https';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as gmail from '../../../../_build/js/release/build/connectors/gmail/host_node/host_node.js';
import * as google from '../../../../_build/js/release/build/connectors/google_service_account/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson, createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {signRemoteCredentialGrant} from '../../../site-node/remote-credential-signature.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding,
  prepareHttpsCredentialAuthenticationMaterial, exchangeHttpsCredentialAuthentication}
  from '../../../site-node/https-credential-resource.mjs';
import {createGmailLabelListReader, GMAIL_LABEL_LIST_OPERATION} from '../site/gmail-label-list-read.mjs';
import {labelListReadLimits, labelListResponse, labelListRowOwner} from './gmail-label-list.fixture.mjs';

const control = runtimeCore(common).remoteCredentialControl;
const cid = value => `sha256:${value.repeat(64)}`;
const nativeConnect = Agent.prototype.createConnection;
const mailbox = 'support+box@example.test';
const oauthScopes = Object.freeze(['https://www.googleapis.com/auth/gmail.readonly']);
const signingLimits = Object.freeze({maxScopes: 4, maxScopeBytes: 1024,
  maxIdentityBytes: 512, maxClaimBytes: 2048, maxAssertionBytes: 4096,
  maxRequestBytes: 8192, maxKeyBits: 2048});
const responseLimits = Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8,
  maxTokenBytes: 128, maxLifetimeSeconds: 3600, maxScopes: 4, maxScopeBytes: 1024});

export async function gmailAuthenticationFixture(t, {format = 'sql'} = {}) {
  const parent = fileURLToPath(new URL('../../../../_build/gmail-authentication-fixtures/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'original-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=oauth2.googleapis.com', '-addext', 'subjectAltName=DNS:oauth2.googleapis.com,IP:127.0.0.1',
    '-keyout', 'tls.key', '-out', 'tls.crt'], {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'tls.key')), readFile(join(root, 'tls.crt'))]);
  const authority = generateKeyPairSync('ed25519');
  const nativeMaterial = generateKeyPairSync('rsa', {modulusLength: 2048});
  await Promise.all([
    writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({type: 'spki', format: 'pem'})),
    writeFile(join(root, 'original-material.key'), nativeMaterial.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600}),
  ]);
  const token = 'LOCAL_ONLY_GMAIL_ACCESS_TOKEN';
  const state = {authRequests: 0, apiRequests: 0, materialResolutions: 0,
    legacyResolutions: 0, bodyCharges: 0, rows: [], requests: [], errors: [],
    authResponse: JSON.stringify({access_token: token, token_type: 'Bearer', expires_in: 60,
      scope: oauthScopes[0]}), labels: labelListResponse(), onToken: undefined, onApi: undefined,
    now: Date.now(), materialCurrent: true};
  const issuedAt = Math.floor(state.now / 1000);
  const server = createServer({key, cert}, async (request, response) => {
    const chunks = [];
    try {
      for await (const chunk of request) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      state.requests.push({path: request.url, method: request.method, body,
        authorization: request.headers.authorization, contentType: request.headers['content-type']});
      if (request.url === '/token') {
        state.authRequests++;
        assert.equal(request.method, 'POST');
        assert.equal(request.headers.host, 'oauth2.googleapis.com');
        assert.equal(request.headers.authorization, undefined);
        assert.equal(request.headers['content-type'], 'application/x-www-form-urlencoded');
        const form = new URLSearchParams(body.toString('utf8'));
        assert.deepEqual([...form.keys()], ['grant_type', 'assertion']);
        assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
        const parts = form.get('assertion').split('.');
        assert.equal(parts.length, 3);
        assert.equal(verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`),
          nativeMaterial.publicKey, Buffer.from(parts[2], 'base64url')), true);
        assert.deepEqual(JSON.parse(Buffer.from(parts[1], 'base64url')), {
          iss: 'service@example.test', sub: mailbox, scope: oauthScopes[0],
          aud: 'https://oauth2.googleapis.com/token', iat: issuedAt, exp: issuedAt + 120,
        });
        if (await state.onToken?.(request, response)) return;
        response.writeHead(200, {'content-type': 'application/json'}).end(state.authResponse);
      } else {
        state.apiRequests++;
        assert.equal(request.url, '/gmail/v1/users/support%2Bbox%40example.test/labels?fields=labels%28id%2Cname%2Ctype%29');
        assert.equal(request.method, 'GET');
        assert.equal(body.byteLength, 0);
        assert.equal(request.headers.authorization, `Bearer ${token}`);
        if (await state.onApi?.(request, response)) return;
        response.writeHead(200, {'content-type': 'application/json'}).end(JSON.stringify(state.labels));
      }
    } catch (error) {state.errors.push(error); response.destroy();}
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  const port = server.address().port;
  // Private child-process fixture route only. Product Host/path/TLS identity
  // stay fixed at Google; no live Google endpoint or DNS request is reached.
  Agent.prototype.createConnection = function(options, callback) {
    if (options.hostname === 'oauth2.googleapis.com' || options.host === 'oauth2.googleapis.com') {
      assert.equal(String(options.port), '443');
      return nativeConnect.call(this, {...options, hostname: '127.0.0.1', host: '127.0.0.1',
        port, servername: 'oauth2.googleapis.com'}, callback);
    }
    return nativeConnect.call(this, options, callback);
  };
  const opens = () => openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['gmail-fixture', new Map([['original', authority.publicKey]])]])});
  const journal = opens();
  const scope = Object.freeze({issuerAuthority: 'gmail-fixture', principal: 'operator',
    namespaceId: 'fixture', environment: 'test', siteKey: 'site', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'gmail', connectorRevision: 'gmail/0.1',
    resourceOrigin: `https://127.0.0.1:${port}`, operation: GMAIL_LABEL_LIST_OPERATION,
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: BigInt(state.now + 600_000), maxUses: 1});
  const authScope = Object.freeze({...scope, resourceOrigin: 'https://oauth2.googleapis.com',
    operation: 'google:oauth:token'});
  const grant = control.prepare(scope), authGrant = control.prepare(authScope);
  const sign = value => signRemoteCredentialGrant(value, control, {keyId: 'original', privateKey: authority.privateKey});
  journal.acceptGrant(sign(grant), control); journal.acceptGrant(sign(authGrant), control);
  const accountPath = join(root, 'account.json');
  const writeAccount = outcome => writeFile(accountPath, canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'fixture', entries: [{entry_id: 'gmail-read', outcome, principal: {all: true},
      connection: {any_of: ['gmail:fixture']}, resource: {any_of: ['labels']},
      operation: {any_of: ['read']}, exclusions: []}]}));
  await writeAccount('allow');
  const gate = await createLocalAuthorizationGate({accountConfig: accountPath, principal: 'operator',
    context: {principal: 'operator', contextCid: cid('d')}});
  const current = async () => {
    const decision = await gate.authorize('acquisition', {connection: 'gmail:fixture', resource: 'labels', operation: 'read'},
      {subjectCid: scope.runInvocationCid});
    if (decision.action !== 'dispatch') throw Object.assign(new Error('GmailReadDenied'), {code: 'GmailReadDenied'});
  };
  const selected = {privateKey: nativeMaterial.privateKey, keyGeneration: 'original-test-key-generation',
    clientEmail: 'service@example.test', delegate: mailbox, scopes: oauthScopes,
    expiresUnixMilliseconds: BigInt(state.now + 300_000)};
  const resolveSecret = async () => {state.legacyResolutions++; throw Error('ForbiddenLegacyTokenResolution');};
  const credential = {control, journal, resolveSecret, ca: cert, now: () => state.now};
  const binding = openHttpsCredentialBinding({...credential, scope, maxSecretBytes: 128,
    authentication: {clientEmail: selected.clientEmail, delegate: mailbox, scopes: oauthScopes,
      keyGeneration: selected.keyGeneration, lifetimeSeconds: 120, signingLimits,
      tokenRuntime: google, responseLimits,
      resolveMaterial: async () => {state.materialResolutions++; return selected;},
      assertCurrentMaterial: value => {
        assert.equal(value, selected);
        if (!state.materialCurrent) throw Object.assign(new Error('OriginalMaterialRetired'), {code: 'OriginalMaterialRetired'});
      }}});
  let row, parentClaim, material;
  t.after(async () => {
    const errors = [];
    try {assert.equal(closeHttpsCredentialBinding(binding), 'closed');} catch (error) {errors.push(error);}
    try {row?.close();} catch (error) {errors.push(error);}
    try {journal.close();} catch (error) {errors.push(error);}
    server.closeAllConnections();
    try {await new Promise(resolve => server.close(resolve));} catch (error) {errors.push(error);}
    Agent.prototype.createConnection = nativeConnect;
    errors.push(...state.errors);
    t.diagnostic(`Retained original Gmail authentication fixture: ${root}`);
    if (errors.length) throw new AggregateError(errors, 'OriginalGmailAuthenticationCleanupUnconfirmed');
  });
  row = await labelListRowOwner(() => closeHttpsCredentialBinding(binding) === 'closed',
    '{"relation_keys":{"candidate_keys":[["id"]]}}', format, 'id, name, type');
  const authorization = Object.freeze({grant, scope, useId: 'original-labels'});
  const options = {moon: gmail, mailbox, names: ['name'], initialAuthorization: authorization,
    credential: {...credential, binding}, limits: labelListReadLimits, current,
    authorizationFor: () => authorization,
    chargeResponse: body => {state.bodyCharges++; return row.charge(body);},
    consumePage: (rows, {charge}) => {row.page(rows, charge); state.rows.push(...rows);}};
  return {root, state, binding, row, journal, opens, scope, authScope, grant, authGrant, control, writeAccount,
    reader: overrides => createGmailLabelListReader({...options, ...overrides}),
    parentClaim: () => parentClaim,
    async authenticate(overrides = {}) {
      await current();
      parentClaim ??= journal.claim(control.identity(grant), authorization.useId, BigInt(state.now), scope, control);
      material ??= await prepareHttpsCredentialAuthenticationMaterial({...credential, binding, scope, parentClaim,
        authenticationGrant: authGrant, authenticationScope: authScope, currentBeforeSign: current});
      return exchangeHttpsCredentialAuthentication({...credential, binding, material, scope, authGrant, authScope,
        useId: 'original-auth', currentBeforeSend: current, ...overrides});
    }};
}
