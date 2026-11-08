// OAuth operator mechanism only: loopback callbacks and synthetic token
// responses, no HubSpot account/SDK/Host/business operation or real secret.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:net';
import {mkdtemp, writeFile, readFile, stat, chmod, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {hubspotAuthorizationUrl, loginHubSpotOAuth} from './fixtures/hubspot-approval/oauth.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-hubspot-oauth-mechanism-'));
  t.after(() => rm(root, {recursive: true}));
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const configuration = {clientId: 'independent-client', clientSecretFile: join(root, 'client-secret'),
    redirectUri: `http://localhost:${port}/oauth-callback`, tokensFile: join(root, 'tokens.json')};
  await writeFile(configuration.clientSecretFile, 'synthetic-client-secret\n', {mode: 0o600});
  const install = new URL('https://app.hubspot.com/oauth/authorize');
  install.search = new URLSearchParams({client_id: configuration.clientId,
    redirect_uri: configuration.redirectUri, scope: 'oauth crm.objects.companies.read', optional_scope: 'crm.objects.companies.write'}).toString();
  const callback = url => {
    const input = new URL(url), value = new URL(configuration.redirectUri);
    value.hostname = '127.0.0.1'; value.searchParams.set('state', input.searchParams.get('state'));
    value.searchParams.set('code', 'independent-one-use-code'); return value;
  };
  return {configuration, install: install.href, callback};
}

test('HubSpot OAuth operator preserves selected scopes and refuses foreign or secret-bearing install URLs', async t => {
  const f = await fixture(t), state = 'a'.repeat(64);
  const url = hubspotAuthorizationUrl(f.install, f.configuration, state);
  assert.equal(url.searchParams.get('state'), state);
  assert.equal(url.searchParams.get('scope'), 'oauth crm.objects.companies.read');
  assert.equal(url.searchParams.get('optional_scope'), 'crm.objects.companies.write');
  for (const mutate of [url => {url.hostname = 'example.invalid';},
    url => {url.searchParams.set('client_id', 'foreign');},
    url => {url.searchParams.set('client_secret', 'must-not-be-in-a-url');},
    url => {url.searchParams.append('client_id', 'duplicate');},
    url => {url.searchParams.set('redirect_uri', 'http://localhost:2/elsewhere');}]) {
    const wrong = new URL(f.install); mutate(wrong);
    assert.throws(() => hubspotAuthorizationUrl(wrong, f.configuration, state));
  }
});

test('HubSpot OAuth operator accepts one original-state callback, stores private tokens and closes its listener', async t => {
  const f = await fixture(t); let calls = 0, callback;
  f.configuration.expectedHubId = '7';
  const result = await loginHubSpotOAuth(f.configuration, f.install, {
    async authorize(url) {
      callback = f.callback(url);
      const wrong = new URL(callback); wrong.searchParams.set('state', 'wrong');
      const refused = await fetch(wrong); assert.equal(refused.status, 403); await refused.text();
      const accepted = await fetch(callback); assert.equal(accepted.status, 200); await accepted.text();
    }, async fetchToken(url, options) {
      calls++; assert.equal(url, 'https://api.hubspot.com/oauth/v3/token');
      assert.equal(options.method, 'POST'); assert.equal(options.redirect, 'error');
      assert.deepEqual(Object.fromEntries(options.body), {client_id: f.configuration.clientId,
        client_secret: 'synthetic-client-secret', code: 'independent-one-use-code',
        grant_type: 'authorization_code', redirect_uri: f.configuration.redirectUri});
      return new Response(JSON.stringify({access_token: 'synthetic-access', refresh_token: 'synthetic-refresh',
        token_type: 'bearer', expires_in: 1800, hub_id: 7, scopes: ['oauth']}));
    }});
  assert.equal(calls, 1); assert.equal(result.status, 'oauth_authorized'); assert.equal(result.hubId, '7');
  assert(!JSON.stringify(result).includes('synthetic-access'));
  const saved = JSON.parse(await readFile(result.tokensFile, 'utf8'));
  assert.equal(saved.access_token, 'synthetic-access'); assert.equal(saved.refresh_token, 'synthetic-refresh');
  assert.equal((await stat(result.tokensFile)).mode & 0o777, 0o600);
  await assert.rejects(fetch(callback));
});

test('HubSpot OAuth operator rejects another account without saving tokens and validates selection before browser use', async t => {
  const f = await fixture(t); let calls = 0, browsers = 0, callback;
  const options = {async authorize(url) {
    browsers++; callback = f.callback(url); const response = await fetch(callback); await response.text();
  }, async fetchToken() {
    calls++;
    return new Response(JSON.stringify({access_token: 'foreign-synthetic-access', refresh_token: 'foreign-synthetic-refresh',
      token_type: 'bearer', expires_in: 1800, hub_id: 8, scopes: ['oauth']}));
  }};
  await assert.rejects(loginHubSpotOAuth({...f.configuration, expectedHubId: '7'}, f.install, options),
    error => error.code === 'HubSpotOAuthAccountMismatch' && !error.message.includes('foreign-synthetic'));
  assert.equal(calls, 1); assert.equal(browsers, 1);
  await assert.rejects(stat(f.configuration.tokensFile), {code: 'ENOENT'});
  await assert.rejects(fetch(callback));
  await assert.rejects(loginHubSpotOAuth({...f.configuration, expectedHubId: 7}, f.install, options),
    {code: 'InvalidHubSpotOAuthAccountSelection'});
  assert.equal(calls, 1); assert.equal(browsers, 1);
});

test('HubSpot OAuth operator preserves token refusal without leaking provider body or writing a token file', async t => {
  const f = await fixture(t); let calls = 0;
  await assert.rejects(loginHubSpotOAuth(f.configuration, f.install, {
    async authorize(url) {const response = await fetch(f.callback(url)); await response.text();},
    async fetchToken() {calls++; return new Response('synthetic-secret-must-not-leak', {status: 400});}
  }), error => error.code === 'HubSpotOAuthTokenRejected' && !error.message.includes('synthetic-secret'));
  assert.equal(calls, 1); await assert.rejects(stat(f.configuration.tokensFile), {code: 'ENOENT'});
});

test('HubSpot OAuth operator refuses public secret files before browser use and bounds an uncompleted callback', async t => {
  const f = await fixture(t); let browsers = 0, calls = 0;
  const options = {authorize() {browsers++;}, fetchToken() {calls++; throw new Error('Unexpected token request');}};
  await chmod(f.configuration.clientSecretFile, 0o644);
  await assert.rejects(loginHubSpotOAuth(f.configuration, f.install, options), {code: 'HubSpotOAuthPrivateSecretRequired'});
  assert.equal(browsers, 0); await chmod(f.configuration.clientSecretFile, 0o600);
  await assert.rejects(loginHubSpotOAuth(f.configuration, f.install, {...options, timeoutMilliseconds: 100}),
    {code: 'HubSpotOAuthAuthorizationTimeout'});
  assert.equal(browsers, 1); assert.equal(calls, 0);
  await assert.rejects(stat(f.configuration.tokensFile), {code: 'ENOENT'});
});
