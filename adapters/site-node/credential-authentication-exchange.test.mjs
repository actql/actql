import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, verify} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {Agent, createServer} from 'node:https';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as google from '../../_build/js/release/build/connectors/google_service_account/host_node/host_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding,
  prepareHttpsCredentialAuthenticationMaterial, exchangeHttpsCredentialAuthentication,
  callHttpsCredentialResource} from './https-credential-resource.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const signingLimits = Object.freeze({maxScopes: 4, maxScopeBytes: 1024, maxIdentityBytes: 512,
  maxClaimBytes: 2048, maxAssertionBytes: 4096, maxRequestBytes: 8192, maxKeyBits: 2048});
const responseLimits = Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8,
  maxTokenBytes: 128, maxLifetimeSeconds: 3600, maxScopes: 4, maxScopeBytes: 1024});
const nowValue = 1_700_000_000_000;
const nativeHttpsConnect = Agent.prototype.createConnection;

async function fixture(t, options = {}) {
  const parent = fileURLToPath(new URL('../../_build/authentication-exchange/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'owned-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=oauth2.googleapis.com', '-addext', 'subjectAltName=DNS:oauth2.googleapis.com,IP:127.0.0.1',
    '-keyout', 'tls.key', '-out', 'tls.crt'], {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all([readFile(join(root, 'tls.key')), readFile(join(root, 'tls.crt'))]);
  const authority = generateKeyPairSync('ed25519'), materialKey = generateKeyPairSync('rsa', {modulusLength: 2048});
  await writeFile(join(root, 'original-material.key'), materialKey.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  await writeFile(join(root, 'original-authority.key'), authority.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const opens = () => openSqliteCredentialJournal(join(root, 'journal'), {credentialAuthorities:
    new Map([['authority', new Map([['issuer', authority.publicKey]])]])});
  const journal = opens();
  let tokenRequests = 0, resourceRequests = 0, resolutions = 0, legacyResolutions = 0, materialChecks = 0;
  let observedNow = nowValue;
  const originalToken = 'LOCAL_ONLY_ORIGINAL_TOKEN';
  const bodies = [], headers = [], serverErrors = [];
  let entered;
  const requestEntered = new Promise(resolve => {entered = resolve;});
  const server = createServer({cert, key}, (request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.once('end', () => {
      try {
        if (request.url === '/token') {
          tokenRequests++;
          assert.equal(request.method, 'POST');
          assert.equal(request.headers.host, 'oauth2.googleapis.com');
          assert.equal(request.headers.authorization, undefined);
          assert.equal(request.headers['content-type'], 'application/x-www-form-urlencoded');
          const body = Buffer.concat(chunks); bodies.push(body); headers.push(request.headers);
          assert.equal(Number(request.headers['content-length']), body.length);
          const form = new URLSearchParams(body.toString('utf8'));
          assert.deepEqual([...form.keys()], ['grant_type', 'assertion']);
          assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
          const jwt = form.get('assertion').split('.'); assert.equal(jwt.length, 3);
          assert.equal(verify('RSA-SHA256', Buffer.from(`${jwt[0]}.${jwt[1]}`), materialKey.publicKey,
            Buffer.from(jwt[2], 'base64url')), true);
          assert.deepEqual(JSON.parse(Buffer.from(jwt[1], 'base64url')), {
            iss: 'fixture@example.test', scope: 'scope:a scope:b',
            aud: 'https://oauth2.googleapis.com/token', iat: nowValue / 1000,
            exp: nowValue / 1000 + Math.min(120, Math.floor((options.authLifetimeMs ?? 600_000) / 1000)),
          });
          entered();
          if (options.onToken?.(request, response)) return;
          response.writeHead(200, {'content-type': 'application/json'});
          response.end(options.response ?? JSON.stringify({access_token: originalToken,
            token_type: 'Bearer', expires_in: 60, scope: 'scope:a scope:b'}));
        } else if (request.url === '/resource') {
          resourceRequests++;
          assert.equal(request.method, 'GET');
          assert.equal(request.headers.authorization, `Bearer ${originalToken}`);
          if (options.onResource?.(request, response)) return;
          response.writeHead(200, {'content-type': 'application/json'}).end('{"records":[1]}');
        } else throw Error('Unexpected original request target');
      } catch (error) { serverErrors.push(error); response.destroy(); }
    });
  });
  await new Promise((resolve, reject) => {server.once('error', reject);server.listen(0, '127.0.0.1', resolve);});
  const port = server.address().port;
  // Private one-process fixture routing only. The actual product request keeps
  // its fixed Google Host/path/body and TLS server name; only its TCP route is
  // replaced with this owned loopback server. No Google/live endpoint is used.
  const originalConnect = nativeHttpsConnect;
  Agent.prototype.createConnection = function(settings, callback) {
    if (settings.host === 'oauth2.googleapis.com' || settings.hostname === 'oauth2.googleapis.com') {
      assert.equal(String(settings.port), '443');
      return originalConnect.call(this, {...settings, host: '127.0.0.1', hostname: '127.0.0.1',
        port, servername: 'oauth2.googleapis.com'}, callback);
    }
    return originalConnect.call(this, settings, callback);
  };
  const scope = Object.freeze({issuerAuthority: 'authority', principal: 'principal',
    namespaceId: 'namespace', environment: 'production', siteKey: 'site', siteGeneration: 2,
    runtimeBundleCid: cid('a'), connectorRegistration: 'google-fixture', connectorRevision: '0.1',
    resourceOrigin: `https://127.0.0.1:${port}`, operation: 'read', runInvocationCid: cid('b'),
    taskAttempt: 3, dispatchRequestCid: cid('c'), expiresUnixMilliseconds: BigInt(nowValue + 600_000), maxUses: 4});
  const authScope = Object.freeze({...scope, resourceOrigin: 'https://oauth2.googleapis.com', operation: 'google:oauth:token',
    expiresUnixMilliseconds: BigInt(nowValue + (options.authLifetimeMs ?? 600_000))});
  const grant = control.prepare(scope), authGrant = control.prepare(authScope);
  const sign = value => signRemoteCredentialGrant(value, control, {privateKey: authority.privateKey, keyId: 'issuer'});
  journal.acceptGrant(sign(grant), control); journal.acceptGrant(sign(authGrant), control);
  const parentClaim = journal.claim(control.identity(grant), 'original-parent', BigInt(nowValue), scope, control);
  let selected;
  const original = {privateKey: materialKey.privateKey, keyGeneration: 'actual-fixture-generation',
    clientEmail: 'fixture@example.test', scopes: ['scope:a', 'scope:b'], expiresUnixMilliseconds: BigInt(nowValue + 300_000)};
  selected = original;
  const resolveSecret = async () => {legacyResolutions++; throw Error('Forbidden legacy token resolver');};
  const registration = {resolveMaterial: async () => {resolutions++; return original;},
    assertCurrentMaterial: value => {
      options.onMaterialCurrent?.({checks: ++materialChecks, binding, journal, authGrant});
      assert.equal(value, original); assert.equal(selected, original);
    },
    clientEmail: original.clientEmail, keyGeneration: original.keyGeneration, scopes: original.scopes,
    lifetimeSeconds: 120, signingLimits, tokenRuntime: options.missingCodec ? undefined : google,
    responseLimits: options.missingLimits ? undefined : responseLimits};
  const binding = openHttpsCredentialBinding({scope, control, journal, resolveSecret,
    maxSecretBytes: 128, authentication: registration});
  t.after(async () => {
    const closed = closeHttpsCredentialBinding(binding);
    assert.equal(closed, 'closed');
    journal.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    Agent.prototype.createConnection = originalConnect;
    assert.deepEqual(serverErrors, []);
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') console.error(`Original auth exchange scratch retained: ${root}`);
    else await rm(root, {recursive: true, force: true});
  });
  const material = await prepareHttpsCredentialAuthenticationMaterial({binding, scope, control,
    journal, resolveSecret, parentClaim, authenticationGrant: authGrant, authenticationScope: authScope,
    currentBeforeSign: async () => {}, now: () => observedNow});
  const exchange = overrides => exchangeHttpsCredentialAuthentication({binding, material, scope,
    control, journal, resolveSecret, authGrant, authScope, useId: 'original-auth',
    currentBeforeSend: async () => {}, now: () => observedNow, ca: cert, ...overrides});
  const resource = overrides => callHttpsCredentialResource({binding, grant, useId: 'original-parent',
    scope, control, journal, resolveSecret, currentBeforeSend: async () => {},
    operations: new Map([['read', {method: 'GET', path: '/resource'}]]),
    now: () => observedNow, ca: cert, ...overrides});
  return {binding, material, scope, authScope, grant, authGrant, parentClaim,
    journal, opens, exchange, resource, requestEntered, bodies, headers, original,
    tokenRequests: () => tokenRequests, resourceRequests: () => resourceRequests,
    resolutions: () => resolutions, legacyResolutions: () => legacyResolutions,
    rotate: () => {selected = {};}, advance: value => {observedNow = value;}};
}

test('same original material authenticates once then the original parent API use sends once', async t => {
  const f = await fixture(t);
  const auth = await f.exchange();
  assert.deepEqual(Object.keys(auth), ['useCid']);
  assert.equal(f.tokenRequests(), 1);
  assert.equal(f.resolutions(), 1); assert.equal(f.legacyResolutions(), 0);
  const response = await f.resource();
  assert.equal(response.body.toString(), '{"records":[1]}');
  assert.equal(f.resourceRequests(), 1);
  const records = f.journal.recover();
  assert.equal(records.length, 2);
  assert.deepEqual(records.map(x => x.outcome), ['succeeded', 'succeeded']);
  assert.equal(records.find(x => x.useId === 'original-parent').useCid, f.parentClaim.record.useCid);
  await assert.rejects(f.exchange(), {code: 'RemoteCredentialAuthenticationAlreadyClaimed'});
  await assert.rejects(f.resource(), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.deepEqual(f.journal.recover().map(x => x.outcome), ['succeeded', 'succeeded']);
  assert.equal(f.tokenRequests(), 1); assert.equal(f.resourceRequests(), 1);
});

test('missing actual codec or response ceilings refuses before auth claim or send', async t => {
  for (const option of ['missingCodec', 'missingLimits']) {
    const f = await fixture(t, {[option]: true});
    await assert.rejects(f.exchange(), {code: 'RemoteCredentialAuthenticationUnavailable'});
    assert.equal(f.journal.recover().length, 1); assert.equal(f.tokenRequests(), 0);
  }
});

test('foreign material and each missing generated scope field refuse before another use', async t => {
  const f = await fixture(t);
  await assert.rejects(f.exchange({material: Object.freeze({})}), {code: 'RemoteCredentialAuthenticationUnavailable'});
  const {credentialInvocationBindingKeys} = await import('../host-common/credential-scope-fields.generated.mjs');
  for (const name of credentialInvocationBindingKeys) {
    const missing = {...f.authScope}; delete missing[name];
    await assert.rejects(f.exchange({authScope: missing}), {code: 'ForeignRemoteCredentialAuthenticationScope'});
  }
  assert.equal(f.tokenRequests(), 0); assert.equal(f.journal.recover().length, 1);
});

test('current or capacity refusal before auth claim keeps original parent and sends nothing', async t => {
  const f = await fixture(t), refusal = Object.assign(new Error('OriginalCapacityUnavailable'), {code: 'OriginalCapacityUnavailable'});
  await assert.rejects(f.exchange({currentBeforeSend: async () => {throw refusal;}}), error => error === refusal);
  assert.equal(f.journal.recover().length, 1); assert.equal(f.tokenRequests(), 0);
});

test('auth revocation across final current await refuses before the physical POST', async t => {
  const f = await fixture(t); let checks = 0;
  await assert.rejects(f.exchange({currentBeforeSend: async () => {
    if (++checks === 2) f.journal.revoke(control.identity(f.authGrant));
  }}));
  assert.equal(f.tokenRequests(), 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'failed');
  assert.equal(f.journal.recover().find(x => x.useId === 'original-parent').outcome, 'claimed');
});

test('a lost token reply is the same original Unknown without refresh claim or resend', async t => {
  const f = await fixture(t, {onToken(request) {request.socket.destroy(); return true;}});
  await assert.rejects(f.exchange());
  assert.equal(f.tokenRequests(), 1); assert.equal(f.resolutions(), 1);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  const reopened = f.opens();
  assert.equal(reopened.recover().find(x => x.useId === 'original-auth').outcome, 'unknown'); reopened.close();
  await assert.rejects(f.exchange(), {code: 'RemoteCredentialAuthenticationAlreadyClaimed'});
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  await assert.rejects(f.resource(), {code: 'RemoteCredentialAuthenticationUnavailable'});
  assert.equal(f.tokenRequests(), 1); assert.equal(f.resourceRequests(), 0);
});

test('cleanup while token response is pending waits for the same request socket then retains Unknown', async t => {
  const f = await fixture(t, {onToken() {return true;}});
  const result = assert.rejects(f.exchange());
  await f.requestEntered;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  await result;
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  assert.equal(f.tokenRequests(), 1); assert.equal(f.resourceRequests(), 0);
});

test('revocation during token response prevents token use and preserves the sent original Unknown', async t => {
  let send;
  const f = await fixture(t, {onToken(request, response) {send = () => response.end('{"access_token":"X","token_type":"Bearer","expires_in":60}');return true;}});
  const result = assert.rejects(f.exchange());
  await f.requestEntered;
  f.journal.revoke(control.identity(f.authGrant)); send();
  await result;
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
  await assert.rejects(f.resource(), {code: 'RemoteCredentialAuthenticationUnavailable'});
  assert.equal(f.resourceRequests(), 0);
});

test('strict original token response and scope mismatch never become API authority or public token data', async t => {
  for (const response of [
    '{"access_token":"PRIVATE_SENTINEL","access_token":"X","token_type":"Bearer","expires_in":60}',
    '{"access_token":"PRIVATE_SENTINEL","token_type":"Bearer","expires_in":60,"scope":"foreign:scope"}',
  ]) {
    const f = await fixture(t, {response});
    await assert.rejects(f.exchange(), error => {assert.equal(JSON.stringify(error).includes('PRIVATE_SENTINEL'), false);return true;});
    assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'unknown');
    await assert.rejects(f.resource(), {code: 'RemoteCredentialAuthenticationUnavailable'});
    assert.equal(f.resourceRequests(), 0);
  }
});

test('token expiry and original material rotation prevent an API send without another resolver', async t => {
  const f = await fixture(t); await f.exchange();
  f.advance(nowValue + 61_000);
  await assert.rejects(f.resource(), {code: 'RemoteCredentialAuthenticationMaterialExpired'});
  assert.equal(f.resourceRequests(), 0); assert.equal(f.resolutions(), 1);
  const rotated = await fixture(t); await rotated.exchange(); rotated.rotate();
  await assert.rejects(rotated.resource());
  assert.equal(rotated.resourceRequests(), 0); assert.equal(rotated.resolutions(), 1);
});

test('lost API response keeps its already claimed parent Unknown and never refreshes or replays it', async t => {
  const f = await fixture(t, {onResource(request) {request.socket.destroy(); return true;}});
  await f.exchange(); await assert.rejects(f.resource());
  assert.equal(f.journal.recover().find(x => x.useId === 'original-parent').outcome, 'unknown');
  await assert.rejects(f.resource());
  assert.equal(f.resourceRequests(), 1); assert.equal(f.tokenRequests(), 1); assert.equal(f.resolutions(), 1);
});

test('retirement inside the original material-current callback refuses before the auth POST', async t => {
  let pending;
  const f = await fixture(t, {onMaterialCurrent({checks, binding}) {
    if (checks === 4) pending = closeHttpsCredentialBinding(binding);
  }});
  await assert.rejects(f.exchange(), {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(pending, 'pending');
  assert.equal(f.tokenRequests(), 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'failed');
});

test('the actual auth grant deadline constrains the original assertion and retained token', async t => {
  const f = await fixture(t, {authLifetimeMs: 10_000});
  await f.exchange();
  assert.equal(f.tokenRequests(), 1);
  f.advance(nowValue + 11_000);
  await assert.rejects(f.resource());
  assert.equal(f.resourceRequests(), 0);
  assert.equal(f.resolutions(), 1);
});

test('lost outcome COMMIT reply publishes no token and never repeats the confirmed SQLite write', async t => {
  const f = await fixture(t);
  const probe = new DatabaseSync(':memory:');
  const statements = Object.getPrototypeOf(probe.prepare('SELECT 1')); probe.close();
  const originalRun = statements.run, originalExec = DatabaseSync.prototype.exec;
  let armed = false, writes = 0, lost = 0;
  const loss = new Error('OriginalAuthenticationOutcomeCommitReplyLost');
  statements.run = function(...values) {
    const result = originalRun.apply(this, values);
    if (/UPDATE credential_uses SET outcome/u.test(this.sourceSQL)) {armed = true;writes++;}
    return result;
  };
  DatabaseSync.prototype.exec = function(sql) {
    const result = originalExec.call(this, sql);
    if (sql === 'COMMIT' && armed && lost++ === 0) {armed = false;throw loss;}
    return result;
  };
  try {
    await assert.rejects(f.exchange(), error => {
      assert.equal(error.code, 'RemoteCredentialJournalCommitOutcomeUnknown');
      assert.equal(error.cause, loss); assert.equal(error.outcome, 'unknown'); return true;
    });
  } finally { statements.run = originalRun; DatabaseSync.prototype.exec = originalExec; }
  // Fault injection follows a real SQLite COMMIT, not a claimed kernel fault.
  // Its durable state is evidence, not a token returned after an unknown reply.
  assert.equal(writes, 1); assert.equal(lost, 1);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'succeeded');
  await assert.rejects(f.resource(), {code: 'RemoteCredentialAuthenticationUnavailable'});
  await assert.rejects(f.exchange(), {code: 'RemoteCredentialAuthenticationAlreadyClaimed'});
  assert.equal(f.tokenRequests(), 1); assert.equal(f.resourceRequests(), 0);
  assert.equal(f.journal.recover().find(x => x.useId === 'original-auth').outcome, 'succeeded');
});

test('an unknown API outcome reply blocks a different page use on the same retained token', async t => {
  const f = await fixture(t); await f.exchange();
  const probe = new DatabaseSync(':memory:');
  const statements = Object.getPrototypeOf(probe.prepare('SELECT 1')); probe.close();
  const originalRun = statements.run, originalExec = DatabaseSync.prototype.exec;
  let armed = false, writes = 0, lost = 0, originalFailure;
  const loss = new Error('OriginalApiOutcomeCommitReplyLost');
  statements.run = function(...values) {
    const result = originalRun.apply(this, values);
    if (/UPDATE credential_uses SET outcome/u.test(this.sourceSQL)) {armed = true;writes++;}
    return result;
  };
  DatabaseSync.prototype.exec = function(sql) {
    const result = originalExec.call(this, sql);
    if (sql === 'COMMIT' && armed && lost++ === 0) {armed = false;throw loss;}
    return result;
  };
  try {
    await assert.rejects(f.resource(), error => {
      assert.equal(error.code, 'RemoteCredentialJournalCommitOutcomeUnknown');
      assert.equal(error.cause, loss); originalFailure = error; return true;
    });
  } finally { statements.run = originalRun; DatabaseSync.prototype.exec = originalExec; }
  assert.equal(writes, 1); assert.equal(lost, 1);
  // Observing durable success does not resolve the caller's unknown ACK.
  assert.equal(f.journal.recover().find(x => x.useId === 'original-parent').outcome, 'succeeded');
  await assert.rejects(f.resource({useId: 'page-after-unknown'}), error => error === originalFailure);
  assert.equal(f.resourceRequests(), 1); assert.equal(f.tokenRequests(), 1);
  assert.equal(f.journal.recover().length, 2);
});
