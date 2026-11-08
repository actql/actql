// Trusted operator setup only. This obtains an OAuth token outside the
// checkout; the installed Account/Credential owners still grant every use.
import assert from 'node:assert/strict';
import {randomBytes, timingSafeEqual} from 'node:crypto';
import {createServer} from 'node:http';
import {open, readFile, writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {isAbsolute, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const tokenEndpoint = 'https://api.hubspot.com/oauth/v3/token';
const fail = code => {throw Object.assign(new Error(code), {code});};

export function hubspotAuthorizationUrl(installUrl, {clientId, redirectUri}, state) {
  const url = new URL(installUrl), callback = new URL(redirectUri);
  const allowed = new Set(['client_id', 'redirect_uri', 'scope', 'optional_scope', 'state', 'response_type']);
  if (url.origin !== 'https://app.hubspot.com' || url.pathname !== '/oauth/authorize' ||
      url.username || url.password || url.hash ||
      [...url.searchParams.keys()].some(name => !allowed.has(name) || url.searchParams.getAll(name).length !== 1) ||
      url.searchParams.get('client_id') !== clientId || !url.searchParams.get('scope')?.trim() ||
      url.searchParams.has('response_type') && url.searchParams.get('response_type') !== 'code') {
    fail('InvalidHubSpotInstallUrl');
  }
  if (callback.protocol !== 'http:' || callback.hostname !== 'localhost' || !callback.port ||
      callback.port === '0' || callback.username || callback.password || callback.search || callback.hash ||
      url.searchParams.has('redirect_uri') && url.searchParams.get('redirect_uri') !== redirectUri) {
    fail('HubSpotOAuthRequiresOriginalLoopbackRedirect');
  }
  assert.match(state, /^[0-9a-f]{64}$/u);
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('state', state);
  return url;
}

async function authorizationCode(url, redirectUri, state, authorize, timeoutMilliseconds) {
  const callback = new URL(redirectUri);
  let accept, refuse, consumed = false, timer;
  const original = new Promise((resolve, reject) => {accept = resolve; refuse = reject;});
  original.catch(() => {});
  const server = createServer((request, response) => {
    const received = new URL(request.url, callback);
    const actual = received.searchParams.get('state') ?? '';
    const validState = received.searchParams.getAll('state').length === 1 &&
      Buffer.byteLength(actual) === Buffer.byteLength(state) &&
      timingSafeEqual(Buffer.from(actual), Buffer.from(state));
    if (consumed || request.method !== 'GET' || received.pathname !== callback.pathname || !validState) {
      response.writeHead(403, {'content-type': 'text/plain'}); response.end('Invalid OAuth callback'); return;
    }
    consumed = true;
    if (received.searchParams.has('error') || received.searchParams.getAll('code').length !== 1 ||
        !received.searchParams.get('code')) {
      response.writeHead(400, {'content-type': 'text/plain'}); response.end('Authorization was not completed');
      refuse(Object.assign(new Error('HubSpotOAuthAuthorizationRejected'), {code: 'HubSpotOAuthAuthorizationRejected'}));
      return;
    }
    response.writeHead(200, {'content-type': 'text/plain', 'cache-control': 'no-store'});
    response.end('Authorization received. You can close this tab.');
    accept(received.searchParams.get('code'));
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(Number(callback.port), '127.0.0.1', resolve);
    });
    timer = setTimeout(() => refuse(Object.assign(new Error('HubSpotOAuthAuthorizationTimeout'),
      {code: 'HubSpotOAuthAuthorizationTimeout'})), timeoutMilliseconds);
    return await Promise.race([original, Promise.resolve().then(() => authorize(url.href)).then(() => original)]);
  } finally {
    clearTimeout(timer);
    if (server.listening) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

export async function loginHubSpotOAuth(configuration, installUrl, {fetchToken = fetch,
  authorize = url => execute('open', [url], {timeout: 10000}), timeoutMilliseconds = 180000} = {}) {
  const {clientId, clientSecretFile, redirectUri, tokensFile, expectedHubId} = configuration;
  for (const path of [clientSecretFile, tokensFile]) assert(isAbsolute(path));
  assert.equal(typeof clientId, 'string');
  if (expectedHubId !== undefined && (typeof expectedHubId !== 'string' ||
      !/^[1-9][0-9]*$/u.test(expectedHubId) || !Number.isSafeInteger(Number(expectedHubId)))) {
    fail('InvalidHubSpotOAuthAccountSelection');
  }
  const state = randomBytes(32).toString('hex');
  const url = hubspotAuthorizationUrl(installUrl, {clientId, redirectUri}, state);
  const handle = await open(clientSecretFile, constants.O_RDONLY | constants.O_NOFOLLOW);
  let secret;
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.mode & 0o077 || stat.size < 1 || stat.size > 4096) fail('HubSpotOAuthPrivateSecretRequired');
    const buffer = Buffer.alloc(4097), {bytesRead} = await handle.read(buffer, 0, buffer.length, 0);
    if (bytesRead > 4096) fail('HubSpotOAuthPrivateSecretRequired');
    secret = buffer.subarray(0, bytesRead).toString('utf8').replace(/^\uFEFF/u, '').trim();
    if (!secret || /[\r\n\u0000]/u.test(secret)) fail('HubSpotOAuthPrivateSecretRequired');
  } finally {await handle.close();}
  const code = await authorizationCode(url, redirectUri, state, authorize, timeoutMilliseconds);
  const response = await fetchToken(tokenEndpoint, {method: 'POST', redirect: 'error',
    headers: {'content-type': 'application/x-www-form-urlencoded'}, signal: AbortSignal.timeout(15000),
    body: new URLSearchParams({client_id: clientId, client_secret: secret,
      code, grant_type: 'authorization_code', redirect_uri: redirectUri})});
  if (!response.ok) fail('HubSpotOAuthTokenRejected');
  const reader = response.body.getReader(), chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      bytes += value.byteLength;
      if (bytes > 16384) {await reader.cancel(); fail('HubSpotOAuthTokenResponseLimit');}
      chunks.push(Buffer.from(value));
    }
  } finally {reader.releaseLock();}
  let token;
  try {token = JSON.parse(Buffer.concat(chunks).toString('utf8'));}
  catch {fail('InvalidHubSpotOAuthTokenResponse');}
  if (!token || !['access_token', 'refresh_token'].every(name => typeof token[name] === 'string' && token[name]) ||
      typeof token.token_type !== 'string' || token.token_type.toLowerCase() !== 'bearer' ||
      !Number.isSafeInteger(token.expires_in) || token.expires_in <= 0 ||
      !(Number.isSafeInteger(token.hub_id) && token.hub_id > 0) ||
      !Array.isArray(token.scopes) || !token.scopes.every(value => typeof value === 'string')) fail('InvalidHubSpotOAuthTokenResponse');
  if (expectedHubId !== undefined && String(token.hub_id) !== expectedHubId) fail('HubSpotOAuthAccountMismatch');
  const expiresAt = new Date(Date.now() + token.expires_in * 1000).toISOString();
  await writeFile(tokensFile, JSON.stringify({access_token: token.access_token, refresh_token: token.refresh_token,
    token_type: token.token_type, hub_id: token.hub_id, scopes: token.scopes, expiresAt}) + '\n', {mode: 0o600, flag: 'wx'});
  return {status: 'oauth_authorized', hubId: String(token.hub_id), expiresAt, tokensFile};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [configurationPath, installUrlPath] = process.argv.slice(2);
  assert.equal(process.argv.length, 4, 'usage: oauth.mjs CONFIGURATION INSTALL_URL_FILE');
  const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
  const installUrl = (await readFile(installUrlPath, 'utf8')).trim();
  console.log(JSON.stringify(await loginHubSpotOAuth(configuration, installUrl)));
}
