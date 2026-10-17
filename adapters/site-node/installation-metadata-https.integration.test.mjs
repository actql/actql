// Actual installed publication/Common/SQLite/loopback TLS with explicit private
// fixture Account/current/signing material. No normal authority/funding claim.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createServer} from 'node:https';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {createInstalledConnectorTable} from '../host-node/installed-connectors.mjs';
import {publishInstalledSourceProfile, installedSourcePublicationRequestId,
  assertInstalledSourcePublicationRequest, observeInstalledSourcePublicationCurrent}
  from '../host-node/installed-source.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';
import {openHttpsCredentialBinding, callHttpsCredentialResource,
  closeHttpsCredentialBinding} from './https-credential-resource.mjs';

assert(process.env.ACTQL_METADATA_COMMON_RUNTIME, 'Select actual matching Common explicitly');
const runtimeUrl = pathToFileURL(process.env.ACTQL_METADATA_COMMON_RUNTIME);
const moon = await import(runtimeUrl.href);
const cid = digit => 'sha256:' + digit.repeat(64);
const emptyBody = 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const version = 'actql-installed-metadata-https-private-fixture/0.1';

async function fixture(t) {
  const base = join(process.cwd(), '_build', 'metadata-https-fixtures');
  await mkdir(base, {recursive: true, mode: 0o700});
  const root = await mkdtemp(join(base, 'original-'));
  const ssl = (...args) => execFileSync('openssl', args, {cwd: root, stdio: 'ignore'});
  ssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'tls.key',
    '-out', 'tls.crt', '-subj', '/CN=localhost', '-days', '1',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1');
  const cert = await readFile(join(root, 'tls.crt')), key = await readFile(join(root, 'tls.key'));
  let requests = [], secrets = 0, secret = 'original-private-token';
  const server = createServer({cert, key}, (req, res) => {
    requests.push({path: req.url, method: req.method,
      originalMaterial: req.headers.authorization === 'Bearer original-private-token'});
    assert.equal(req.headers.authorization, 'Bearer original-private-token');
    res.writeHead(200, {'content-type': 'application/json'}).end(JSON.stringify({path: req.url}));
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  const origin = 'https://127.0.0.1:' + server.address().port;
  const keys = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'issuer-private.pem'), keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  await writeFile(join(root, 'issuer-public.pem'), keys.publicKey.export({type: 'spki', format: 'pem'}), {mode: 0o600});
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {credentialAuthorities:
    new Map([['fixture-issuer', new Map([['fixture-key', keys.publicKey]])]]), maxGrants: 10, maxUses: 20});
  const profilePath = join(root, 'profile.json');
  await writeFile(profilePath, JSON.stringify({version, connection: 'fixture-connection'}));
  const resolveSecret = async () => {secrets++; return secret;};
  let binding, active = true, currentCount = 0, onCurrent, assertResult;
  const f = {root, journal, requests: () => [...requests], secrets: () => secrets,
    rotate: () => {secret = 'replacement-token';}, revoke: () => {active = false;},
    setCurrent: callback => {onCurrent = callback;},
    setAssertResult: value => {assertResult = value;},
    closeBinding: () => closeHttpsCredentialBinding(binding)};
  t.after(async () => {
    if (binding) assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    journal.close();
    await new Promise(resolve => server.close(resolve));
    await writeFile(join(root, 'physical-observation.json'), JSON.stringify({requests,
      secretResolutions: secrets, currentCount, originalJournalClosed: true, originalServerClosed: true}));
    console.error('Original metadata HTTPS fixture retained: ' + root);
  });
  f.run = async callback => {
    const module = {check: value => Object.freeze({...value}),
      identityParts() {assert.fail('Publication must not rediscover identity');},
      load() {assert.fail('Publication must not load a query Source');},
      async publish(profile, options) {
      const request = options.publicationRequest, originals = {...options, profile};
      const view = runtimeCore(moon).installationPreparationMetadata();
      const subject = view.prepareSubject({accountConfigurationCid: cid('a'), accountId: 'fixture-account',
        connection: profile.connection, connectorRegistration: options.installation.registration,
        connectorRevision: options.installation.revision, declarationSourceCid: cid('b'),
        installationRequestId: installedSourcePublicationRequestId(request), principal: options.principalId,
        runtimeBundleCid: options.runtimeBundleCid, siteGeneration: 4, siteKey: 'fixture-site'});
      const control = view.forSubject(subject);
      const scopes = ['database', 'schema'].map(name => view.prepareScope(subject, {
        metadataOccurrenceId: name + '-original', operation: 'metadata:' + name, requestBodyCid: emptyBody,
        requestMethod: 'GET', requestPath: '/metadata/' + name, resourceOrigin: origin}));
      function assertCurrent() {
        assert.equal(this, undefined, 'The private Credential binding is not a callback receiver');
        assertInstalledSourcePublicationRequest(request, originals);
        if (!active) throw Object.assign(new Error('FixtureAuthorityRevoked'), {code: 'FixtureAuthorityRevoked'});
        return assertResult;
      };
      const currentBeforeSend = async () => {
        await observeInstalledSourcePublicationCurrent(request, originals);
        currentCount++; await onCurrent?.(currentCount);
        assertCurrent();
      };
      binding = openHttpsCredentialBinding({scope: scopes[0], control, journal,
        resolveSecret, maxSecretBytes: 128, assertCurrent});
      const credential = {binding, control, journal, resolveSecret, currentBeforeSend, ca: cert, now: () => 1};
      const authorization = index => {
        const grant = control.prepare({issuerAuthority: 'fixture-issuer', scope: scopes[index],
          expiresUnixMilliseconds: 10000n, maxUses: 2});
        journal.acceptGrant(signRemoteCredentialGrant(grant, control,
          {keyId: 'fixture-key', privateKey: keys.privateKey}), control);
        return {grant, scope: scopes[index], useId: 'original-' + index};
      };
      const call = (index, changes = {}, original = authorization(index)) => invokeScopedCredentialOperation({
        authorization: original, credential, callResource: callHttpsCredentialResource,
        operation: 'metadata:' + ['database', 'schema'][index], method: 'GET',
        path: '/metadata/' + ['database', 'schema'][index], maxRequestBytes: 128, maxResponseBytes: 1024, ...changes});
      await callback({...f, control, view, subject, scopes, credential, authorization, call});
      return Object.freeze({fixtureOnly: true});
    }};
    const connectorTable = createInstalledConnectorTable([{name: 'notion', registration: 'notion',
      revision: 'notion/fixture-0.1', source: {profileVersion: version, load: async () => module}}]);
    return publishInstalledSourceProfile(profilePath, {root, principalId: 'fixture-actor', moon,
      runtimeUrl, resolveSecret, connectorTable});
  };
  return f;
}

test('metadata actual publication sends database and selected schema through the same original binding', async t => {
  const f = await fixture(t);
  await f.run(async x => {
    for (const index of [0, 1]) {
      const response = await x.call(index);
      assert.equal(response.accepted, true);
      assert.deepEqual(JSON.parse(response.body), {path: '/metadata/' + ['database', 'schema'][index]});
    }
    assert.deepEqual(x.journal.recover().map(row => row.outcome), ['succeeded', 'succeeded']);
  });
  assert.equal(f.secrets(), 2);
  assert.deepEqual(f.requests().map(row => [row.method, row.path, row.originalMaterial]),
    [['GET', '/metadata/database', true], ['GET', '/metadata/schema', true]]);
});

test('metadata foreign copied Scope and changed operation request refuse before claim or HTTPS', async t => {
  const f = await fixture(t);
  await f.run(async x => {
    const authorization = x.authorization(0);
    const copiedSubject = x.view.admitSubject(x.view.subjectWire(x.subject), x.view.subjectCid(x.subject));
    const foreignScope = x.view.prepareScope(copiedSubject, x.control.scopeFields(x.scopes[0]));
    for (const change of [{operation: 'metadata:schema'}, {path: '/metadata/other'},
      {method: 'POST', body: '{}'},
      {credential: {...x.credential, binding: undefined}},
      {credential: {...x.credential, currentBeforeSend: undefined}},
      {authorization: {...authorization, scope: foreignScope}},
      {authorization: {...authorization, scope: {...authorization.scope}}}]) {
      await assert.rejects(async () => x.call(0, change, authorization));
    }
    assert.deepEqual(x.journal.recover(), []);
  });
  assert.equal(f.requests().length, 0); assert.equal(f.secrets(), 0);
});

test('metadata resolver rotation refuses another send without retry or replacement material', async t => {
  const f = await fixture(t);
  await f.run(async x => {
    await x.call(0); x.rotate();
    const next = x.authorization(1);
    await assert.rejects(x.call(1, {}, next), {code: 'RemoteCredentialBindingChanged'});
    await assert.rejects(x.call(1, {}, next), {code: 'RemoteCredentialBindingChanged'});
    assert.deepEqual(x.journal.recover().map(row => row.outcome), ['succeeded', 'failed']);
  });
  assert.equal(f.requests().length, 1); assert.equal(f.secrets(), 2);
});

test('metadata current revocation before send and after response prevents wrong disclosure', async t => {
  for (const phase of [2, 3]) {
    const f = await fixture(t);
    f.setCurrent(count => {if (count === phase) f.revoke();});
    await f.run(async x => {
      await assert.rejects(x.call(0), {code: 'FixtureAuthorityRevoked'});
      assert.equal(x.journal.recover()[0].outcome, phase === 2 ? 'failed' : 'unknown');
    });
    assert.equal(f.requests().length, phase === 2 ? 0 : 1);
  }
});

test('metadata outcome COMMIT reply loss does not repeat finish or send another request', async t => {
  const f = await fixture(t);
  await f.run(async x => {
    const authorization = x.authorization(0), exec = DatabaseSync.prototype.exec;
    let commits = 0, outcomeCommits = 0;
    DatabaseSync.prototype.exec = function(sql) {
      // Claim and read-only authorize are also real transactions. Select the
      // actual succeeded outcome transaction, rather than guessing its ordinal.
      const outcome = sql === 'COMMIT' ? this.prepare(
        'SELECT outcome FROM credential_uses ORDER BY rowid DESC LIMIT 1').get()?.outcome : undefined;
      const result = Reflect.apply(exec, this, [sql]);
      if (sql === 'COMMIT') {
        commits++;
        if (outcome === 1 && ++outcomeCommits === 1) throw new Error('OriginalMetadataOutcomeReplyLost');
      }
      return result;
    };
    let original;
    try {await assert.rejects(x.call(0, {}, authorization), error => {
      original = error; return error.code === 'RemoteCredentialJournalCommitOutcomeUnknown';
    });} finally {DatabaseSync.prototype.exec = exec;}
    assert.equal(outcomeCommits, 1);
    t.diagnostic('Original outcome COMMITs: ' + outcomeCommits + '; all COMMITs: ' + commits);
    await assert.rejects(x.call(0, {}, authorization), error => error === original);
    assert.equal(x.requests().length, 1);
  });
});

test('metadata binding retirement after physical response retains pending until original operation closes', async t => {
  const f = await fixture(t); let pending;
  f.setCurrent(count => {if (count === 3) pending = f.closeBinding();});
  await f.run(async x => {
    await assert.rejects(x.call(0), {code: 'RemoteCredentialBindingRetiring'});
    assert.equal(pending, 'pending');
    assert.equal(x.journal.recover()[0].outcome, 'unknown');
    assert.equal(x.closeBinding(), 'closed');
  });
  assert.equal(f.requests().length, 1);
});


test('metadata async or boolean synchronous current fence cannot authorize a claim', async t => {
  for (const value of [Promise.resolve(), true]) {
    const f = await fixture(t); f.setAssertResult(value);
    await f.run(async x => {
      await assert.rejects(x.call(0), {code: 'InvalidInstallationMetadataCurrentFence'});
      assert.deepEqual(x.journal.recover(), []);
    });
    assert.equal(f.requests().length, 0); assert.equal(f.secrets(), 0);
  }
});
