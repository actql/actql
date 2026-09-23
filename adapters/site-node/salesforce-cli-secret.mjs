import {execFile} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const aliasPattern = /^[A-Za-z][A-Za-z0-9_.-]{0,255}$/u;
const text = value => typeof value === 'string' && value.length > 0;
const positive = value => Number.isSafeInteger(value) && value > 0;
const sameConnection = (left, right) =>
  left.orgId === right.orgId && left.username === right.username &&
  left.instanceOrigin === right.instanceOrigin;

function fail(code) {
  // CLI output and errors can contain an access token. Never retain them.
  throw Object.assign(new Error(code), {code});
}

function origin(value) {
  if (!text(value)) fail('SalesforceCliInvalidConnection');
  let parsed;
  try { parsed = new URL(value); }
  catch { fail('SalesforceCliInvalidConnection'); }
  if (parsed.protocol !== 'https:' || parsed.username !== '' ||
      parsed.password !== '' || parsed.pathname !== '/' ||
      parsed.search !== '' || parsed.hash !== '') {
    fail('SalesforceCliInvalidConnection');
  }
  return parsed.origin;
}

function options({executable = 'sf', timeoutMs = 10_000,
  maxOutputBytes = 65_536, invoke = execute} = {}) {
  if (!text(executable) || !positive(timeoutMs) || timeoutMs > 60_000 ||
      !positive(maxOutputBytes) || maxOutputBytes > 1_048_576 ||
      typeof invoke !== 'function') {
    fail('SalesforceCliInvalidConfiguration');
  }
  return {executable, timeoutMs, maxOutputBytes, invoke};
}

async function command(args, config, signal) {
  signal?.throwIfAborted();
  let output;
  try {
    output = await config.invoke(config.executable, args, {
        encoding: 'utf8', timeout: config.timeoutMs,
        maxBuffer: config.maxOutputBytes, killSignal: 'SIGKILL',
        signal, env: {...process.env, SF_TEMP_SHOW_SECRETS: 'false'},
      });
  } catch (error) {
    if (signal?.aborted) fail('SalesforceCliCancelled');
    if (error?.code === 'ENOENT') fail('SalesforceCliUnavailable');
    if (error?.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') {
      fail('SalesforceCliOutputLimit');
    }
    if (error?.killed || error?.signal === 'SIGKILL') {
      fail('SalesforceCliTimeout');
    }
    fail('SalesforceCliAuthenticationFailed');
  }
  if (typeof output?.stdout !== 'string') {
    fail('SalesforceCliMalformedOutput');
  }
  if (Buffer.byteLength(output.stdout, 'utf8') > config.maxOutputBytes) {
    fail('SalesforceCliOutputLimit');
  }
  if (output.stdout.length === 0) fail('SalesforceCliMalformedOutput');
  let parsed;
  try { parsed = JSON.parse(output.stdout); }
  catch { fail('SalesforceCliMalformedOutput'); }
  if (parsed?.status !== 0) fail('SalesforceCliAuthenticationFailed');
  if (!parsed.result || typeof parsed.result !== 'object') {
    fail('SalesforceCliMalformedOutput');
  }
  return parsed.result;
}

async function display(alias, config, signal) {
  if (!aliasPattern.test(alias)) fail('SalesforceCliInvalidAlias');
  const result = await command(
    ['org', 'display', '--target-org', alias, '--json'], config, signal);
  if (result.alias !== alias || !text(result.id) ||
      !text(result.username) || !text(result.instanceUrl)) {
    fail('SalesforceCliMalformedOutput');
  }
  if ((result.connectedStatus !== undefined &&
       result.connectedStatus !== 'Connected') ||
      (result.status !== undefined && result.status !== 'Active')) {
    fail('SalesforceCliAuthenticationFailed');
  }
  return Object.freeze({alias, orgId: result.id,
    username: result.username, instanceOrigin: origin(result.instanceUrl)});
}

async function accessToken(username, config, signal) {
  const result = await command(['org', 'auth', 'show-access-token',
    '--target-org', username, '--json'], config, signal);
  if (!text(result.accessToken)) fail('SalesforceCliMalformedOutput');
  return result.accessToken;
}

function waitFor(promise, signal) {
  if (!signal) return promise;
  if (signal.aborted) fail('SalesforceCliCancelled');
  return new Promise((resolve, reject) => {
    const onAbort = () => {
      signal.removeEventListener('abort', onAbort);
      reject(Object.assign(new Error('SalesforceCliCancelled'),
        {code: 'SalesforceCliCancelled'}));
    };
    signal.addEventListener('abort', onAbort, {once: true});
    promise.then(value => {
      signal.removeEventListener('abort', onAbort);
      resolve(value);
    }, error => {
      signal.removeEventListener('abort', onAbort);
      reject(error);
    });
  });
}

/// Resolve the non-secret binding to persist at connection admission.
/// Calling this does not grant access to a Run or authorize an HTTP operation.
export async function inspectSalesforceCliConnection(alias, settings = {}) {
  const config = options(settings);
  return await display(alias, config, settings.signal);
}

/// Supply a token only to the Site credential boundary. A persisted connection
/// must carry the exact org, user, and instance discovered at admission.
export function createSalesforceCliSecretResolver({
  connection, principal, tenant, environment, siteKey, siteGeneration,
  tokenReuseMs = 30_000, monotonicNow = () => performance.now(),
  ...settings
} = {}) {
  const config = options(settings);
  if (!connection || !aliasPattern.test(connection.alias) ||
      !text(connection.orgId) || !text(connection.username) ||
      !text(principal) || !text(tenant) || !text(environment) ||
      !text(siteKey) || !Number.isSafeInteger(siteGeneration) ||
      siteGeneration < 0 || !positive(tokenReuseMs) ||
      tokenReuseMs > 300_000 || typeof monotonicNow !== 'function') {
    fail('SalesforceCliInvalidConnection');
  }
  const expectedOrigin = origin(connection.instanceOrigin);
  const expected = Object.freeze({alias: connection.alias,
    orgId: connection.orgId, username: connection.username,
    instanceOrigin: expectedOrigin});
  let cached;
  let refreshFlight;
  let epoch = 0;
  const clock = () => {
    const value = monotonicNow();
    if (!Number.isFinite(value) || value < 0) {
      fail('SalesforceCliInvalidClock');
    }
    return value;
  };
  async function refresh() {
    const startingEpoch = epoch;
    const before = await display(expected.alias, config);
    if (!sameConnection(before, expected)) {
      fail('SalesforceCliConnectionMismatch');
    }
    const token = await accessToken(expected.username, config);
    const after = await display(expected.alias, config);
    if (!sameConnection(after, expected)) {
      fail('SalesforceCliConnectionMismatch');
    }
    if (startingEpoch !== epoch) fail('SalesforceCliSessionInvalidated');
    cached = {token, issuedAt: clock()};
    return token;
  }
  async function resolveSecret(scope, signal) {
    if (scope?.principal !== principal || scope?.tenant !== tenant ||
        scope?.environment !== environment ||
        scope?.siteKey !== siteKey ||
        scope?.siteGeneration !== siteGeneration ||
        scope?.connectorRegistration !== 'salesforce' ||
        scope?.resourceOrigin !== expectedOrigin) {
      fail('SalesforceCliConnectionMismatch');
    }
    if (signal?.aborted) fail('SalesforceCliCancelled');
    const current = clock();
    if (cached && current >= cached.issuedAt &&
        current - cached.issuedAt < tokenReuseMs) {
      return cached.token;
    }
    cached = undefined;
    if (!refreshFlight) {
      const flight = refresh();
      refreshFlight = flight;
      flight.then(() => {
        if (refreshFlight === flight) refreshFlight = undefined;
      }, () => {
        if (refreshFlight === flight) refreshFlight = undefined;
      });
    }
    return await waitFor(refreshFlight, signal);
  }
  resolveSecret.invalidate = token => {
    if (token !== undefined && cached?.token !== token) return false;
    const hadCredential = cached !== undefined || refreshFlight !== undefined;
    cached = undefined;
    epoch++;
    return hadCredential;
  };
  Object.defineProperty(resolveSecret, 'connectionOrgId', {
    value: expected.orgId, enumerable: true,
  });
  return Object.freeze(resolveSecret);
}
