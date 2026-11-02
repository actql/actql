import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Actual installed Host/Account/Credential/SQLite/RowRun with a disposable TLS
// peer independently verifying real RSA JWT bytes. No live Snowflake account.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, verify} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import test from 'node:test';
import {loadInstalledSource, installedSourceIdentity} from '../../../host-node/installed-source.mjs';
import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedSnowflakeFixture as fixture} from './installed-snowflake.fixture.mjs';
import {pending, resultBody, decimal38} from './snowflake-read.fixture.mjs';
import {publicSnowflakeInstallation} from './public-snowflake.fixture.mjs';
const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
const rsa = generateKeyPairSync('rsa', {modulusLength: 2048});
const rotated = generateKeyPairSync('rsa', {modulusLength: 2048});
const pem = key => key.privateKey.export({type: 'pkcs8', format: 'pem'});

async function keyPairFixture(t) {
  const f = await fixture(t), lookups = [];
  const {tokenEnvironment, ...originalSite} = f.site;
  const keyPair = {accountIdentifier: 'testorg-testaccount', user: 'operator',
    privateKeyEnvironment: 'SNOWFLAKE_PRIVATE_KEY'};
  const site = {...originalSite, authenticationType: 'KEYPAIR_JWT', keyPair};
  // New explicit key-material transport profile, not a widening of the
  // original OAuth128-byte cases or any Host/Run/VM numerical profile.
  const profile = {...f.profile, limits: {...f.profile.limits, maxSecretBytes: 4096}};
  await writeFile(f.siteProfilePath, JSON.stringify(site)); await writeFile(f.path, JSON.stringify(profile));
  let current = rsa;
  const source=await f.load({resolveSecret:async value=>{lookups.push(value);return pem(current);}});
  return {...f, source, site, profile, lookups, rotate: () => {current = rotated;}};
}
function acceptJwt(entry) {
  assert.equal(entry.headers['x-snowflake-authorization-token-type'], 'KEYPAIR_JWT');
  const raw = entry.headers.authorization; assert.match(raw, /^Bearer /u);
  const token = raw.slice(7), parts = token.split('.'); assert.equal(parts.length, 3);
  assert(verify('RSA-SHA256', Buffer.from(parts.slice(0, 2).join('.')), rsa.publicKey, Buffer.from(parts[2], 'base64url')));
  const body = JSON.parse(Buffer.from(parts[1], 'base64url'));
  const fp = createHash('sha256').update(rsa.publicKey.export({type: 'spki', format: 'der'})).digest('base64');
  assert.equal(body.iss, 'TESTORG-TESTACCOUNT.OPERATOR.SHA256:' + fp);
  assert.equal(body.sub, 'TESTORG-TESTACCOUNT.OPERATOR'); assert.equal(body.exp - body.iat, 3540);
  assert(body.iat <= Math.floor(Date.now() / 1000) && body.exp > Math.floor(Date.now() / 1000));
  assert(!raw.includes('PRIVATE KEY')); return token;
}

test('installed key-pair profile is lazy, scope-bound and uses one token for original POST/status/capture', async t => {
  const f = await keyPairFixture(t);
  assert.equal(f.lookups.length, 0); assert.equal(f.state.requests.length, 0);
  const tokens = [];
  f.state.onRequest = entry => {tokens.push(acceptJwt(entry)); return f.state.requests.length === 1
    ? {status: 202, body: pending('keypair-original')} : {body: resultBody({handle: 'keypair-original'})};};
  const ledger = checked(f.moon.clientProgramAcquisitionLedger(1, 1, 65536n, 100000000n, 100000000n, 0));
  const opened = await f.source.openCapture({...f.preparation, preparedSource: await f.prepare(f.source), ledger});
  f.captures.push(opened);
  const exported = checked(f.moon.clientProgramExportSourceCapture(opened.capture.source(), opened.requirement, 'keypair-original'));
  assert(f.moon.clientProgramSourceCaptureExportRows(exported)[0].includes(decimal38));
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET']); assert.equal(tokens[0], tokens[1]);
  assert.equal(f.lookups.length, 2);
  for (const lookup of f.lookups) {
    assert.equal(lookup.materialEnvironment, 'SNOWFLAKE_PRIVATE_KEY'); assert.equal(lookup.operation, 'snowflake:sql:read');
    assert.equal(lookup.resourceOrigin, f.site.apiOrigin); assert.equal(lookup.namespaceId, f.site.namespaceId);
    assert.equal(lookup.siteGeneration, f.site.siteGeneration); assert.match(lookup.grantCid, /^sha256:/u);
  }
  await opened.close(); assert.deepEqual(ledgerUsageFieldsFor(f.moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  t.diagnostic(JSON.stringify({issuer: 'TESTORG-TESTACCOUNT.OPERATOR',
    tokenSha256: createHash('sha256').update(tokens[0]).digest('hex'),
    tokenBytes: Buffer.byteLength(tokens[0]), publicKeyFingerprint: 'SHA256:' + createHash('sha256')
      .update(rsa.publicKey.export({type: 'spki', format: 'der'})).digest('base64'),
    physicalExchanges: 2, currentMaterialLookups: f.lookups.length, capturedRows: 2,
    sameInFlightToken: true, originalReservationsClosed: true,
    selectedSecretLimit: 4096, unchangedOAuthFixtureSecretLimit: 128}));
});

test('actual key rotation after 202 cannot replace original token or resend the statement', async t => {
  const f = await keyPairFixture(t);
  f.state.onRequest = entry => {acceptJwt(entry); f.rotate(); return {status: 202, body: pending('rotated-original')};};
  const ledger = checked(f.moon.clientProgramAcquisitionLedger(1, 1, 65536n, 100000000n, 100000000n, 0));
  await assert.rejects(f.source.openCapture({...f.preparation, ledger}), error => {
    assert.equal(error.code, 'RemoteCredentialBindingChanged');
    assert.equal(error.outcome, 'unknown'); assert.equal(error.originalStatement.statementHandle, 'rotated-original'); return true;
  });
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST']); assert.equal(f.lookups.length, 2);
  assert.deepEqual(ledgerUsageFieldsFor(f.moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('key-pair/token ambiguity and OAuth key-pair substitution refuse before material or Provider use', async t => {
  const f = await fixture(t);
  for(const [site,expected]of [
    [{...f.site,keyPair:{accountIdentifier:'org-acct',user:'user',privateKeyEnvironment:'KEY'}},'InvalidInstalledSnowflakeSite'],
    [{...f.site,tokenEnvironment:undefined,authenticationType:'KEYPAIR_JWT',keyPair:null},'InvalidSnowflakeKeyPairProfile'],
  ]){
    await writeFile(f.siteProfilePath,JSON.stringify(site));
    await assert.rejects(f.load(),error=>{assert.equal(error.primaryFailure?.code,expected);assert.equal(error.cleanupPending,false);return true;});
  }
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('issuer selection changes installed identity without resolving or granting credentials', async t => {
  const f = await fixture(t); const {tokenEnvironment, ...base} = f.site;
  const keyPair = {accountIdentifier: 'org-acct', user: 'one', privateKeyEnvironment: 'KEY'};
  await writeFile(f.siteProfilePath, JSON.stringify({...base, authenticationType: 'KEYPAIR_JWT', keyPair}));
  const first = await installedSourceIdentity(f.path);
  await writeFile(f.siteProfilePath, JSON.stringify({...base, authenticationType: 'KEYPAIR_JWT', keyPair: {...keyPair, user: 'two'}}));
  assert.notEqual(await installedSourceIdentity(f.path), first);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('public Local SQL reaches the original key-pair Site and Named Result without attach resends', async t => {
  const f = await publicSnowflakeInstallation(t);
  const {tokenEnvironment, ...site} = f.site;
  await writeFile(f.siteProfilePath, JSON.stringify({...site, authenticationType: 'KEYPAIR_JWT',
    keyPair: {accountIdentifier: 'testorg-testaccount', user: 'operator', privateKeyEnvironment: 'KEY'}}));
  const originalProfile = JSON.parse(await readFile(f.path, 'utf8'));
  await writeFile(f.path, JSON.stringify({...originalProfile,
    limits: {...originalProfile.limits, maxSecretBytes: 4096}}));
  let lookups = 0;
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
    installation: {...f.installation, resolveSourceSecret: async value => {
      assert.equal(value.materialEnvironment, 'KEY'); lookups++; return pem(rsa);
    }}});
  t.after(() => client.close());
  assert.equal(lookups, 0); assert.equal(f.state.requests.length, 0);
  f.state.onRequest = entry => {acceptJwt(entry); return f.state.requests.length === 1
    ? {status: 202, body: pending('keypair-public-original')}
    : {body: resultBody({handle: 'keypair-public-original'})};};
  const text = 'SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, TREND AS trend ' +
    'FROM snowflake.usage_30d |> RESULT usage';
  const report = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql'});
  assert.equal(report.report.verdict, 'verified'); assert.equal(lookups, 0);
  const submissionRef = client.newSubmission({nonce: 'keypair-public-original'});
  const run = await client.startSource(text, {format: 'sql', submissionRef});
  assert.equal((await run.wait({signal: AbortSignal.timeout(20000)})).status, 'succeeded');
  const expected = [{account_id: 'a1', active_users: decimal38, trend: 'down'},
    {account_id: 'a2', active_users: '0', trend: null}];
  assert.deepEqual(await run.result('usage').all(), expected);
  assert.deepEqual(await (await client.attach(run.ref)).result('usage').all(), expected);
  const original = await client.startSource(text, {format: 'sql', submissionRef});
  assert.deepEqual(original.ref, run.ref); assert.deepEqual(await original.result('usage').all(), expected);
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET']); assert.equal(lookups, 2);
  await client.close();
  const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
  assert.equal(cleanup.length, 1);
  for (const name of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes',
    'reservedExecutionBytes', 'uncertainTransferBytes']) assert.equal(cleanup[0][1].resourceUsage[name], '0');
  t.diagnostic(JSON.stringify({entrance: 'repository public Local, retained Core',
    physicalExchanges: 2, materialLookups: lookups, originalNamedResult: true,
    sameRunAttachAndSubmission: true, originalCleanup: 1, usage: cleanup[0][1].resourceUsage}));
});
