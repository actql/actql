import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const aliasPattern = /^[A-Za-z][A-Za-z0-9_.-]{0,255}$/u;
const text = value => typeof value === 'string' && value.length > 0;
const positive = value => Number.isSafeInteger(value) && value > 0;

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
  ...settings
} = {}) {
  const config = options(settings);
  if (!connection || !aliasPattern.test(connection.alias) ||
      !text(connection.orgId) || !text(connection.username) ||
      !text(principal) || !text(tenant) || !text(environment) ||
      !text(siteKey) || !Number.isSafeInteger(siteGeneration) ||
      siteGeneration < 0) {
    fail('SalesforceCliInvalidConnection');
  }
  const expectedOrigin = origin(connection.instanceOrigin);
  const expected = Object.freeze({alias: connection.alias,
    orgId: connection.orgId, username: connection.username,
    instanceOrigin: expectedOrigin});
  return async function resolveSecret(scope, signal) {
    if (scope?.principal !== principal || scope?.tenant !== tenant ||
        scope?.environment !== environment ||
        scope?.siteKey !== siteKey ||
        scope?.siteGeneration !== siteGeneration ||
        scope?.connectorRegistration !== 'salesforce' ||
        scope?.resourceOrigin !== expectedOrigin) {
      fail('SalesforceCliConnectionMismatch');
    }
    const before = await display(expected.alias, config, signal);
    if (before.orgId !== expected.orgId ||
        before.username !== expected.username ||
        before.instanceOrigin !== expected.instanceOrigin) {
      fail('SalesforceCliConnectionMismatch');
    }
    const token = await accessToken(expected.username, config, signal);
    const after = await display(expected.alias, config, signal);
    if (after.orgId !== expected.orgId ||
        after.username !== expected.username ||
        after.instanceOrigin !== expected.instanceOrigin) {
      fail('SalesforceCliConnectionMismatch');
    }
    return token;
  };
}
