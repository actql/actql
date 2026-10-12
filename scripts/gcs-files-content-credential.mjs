// Test-only short-lived credential resolution. The installed Connector still
// owns targets, authorization, physical requests and capture. This adds finite
// campaign limits, not an alternative credential journal or acquisition owner.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {checkGcsAcceptanceEnvironment} from './gcs-files-content-environment.mjs';

const execute = promisify(execFile);
const fail = reason => { throw Object.assign(new Error(`GcsAcceptanceCredential:${reason}`),
  {code: 'GcsAcceptanceCredential', reason}); };

export function createGcsAcceptanceCredential(manifest, {
  maxResponseBytesPerCall, now = Date.now, run = execute,
} = {}) {
  const configuration = checkGcsAcceptanceEnvironment(manifest);
  if (!Number.isSafeInteger(maxResponseBytesPerCall) || maxResponseBytesPerCall < 1 ||
      maxResponseBytesPerCall > configuration.limits.maxResponseBytes ||
      typeof now !== 'function' || typeof run !== 'function') fail('configuration');
  const startedAt = now();
  let calls = 0, reservedResponseBytes = 0, mints = 0, pending, closed = false, mintFailure;
  const remaining = () => configuration.limits.maxDurationMs - (now() - startedAt);
  const current = signal => {
    signal?.throwIfAborted();
    if (closed) fail('closed');
    if (remaining() <= 0) fail('deadline');
  };
  const mint = async signal => {
    mints++;
    let answer;
    const env = {...process.env, CLOUDSDK_CORE_LOG_HTTP: 'false',
      CLOUDSDK_CORE_VERBOSITY: 'error'};
    for (const key of ['CLOUDSDK_AUTH_ACCESS_TOKEN', 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE',
      'CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT', 'GOOGLE_APPLICATION_CREDENTIALS']) delete env[key];
    try {
      answer = await run(configuration.credential.executable, [
        'auth', 'print-access-token',
        `--impersonate-service-account=${configuration.credential.serviceAccount}`,
        `--account=${configuration.credential.account}`,
        `--project=${configuration.project}`, '--quiet',
      ], {encoding: 'utf8', maxBuffer: 16384, env,
        timeout: Math.min(30000, remaining()), signal});
    } catch {
      // execFile failures contain stdout/stderr. Neither these nor a raw
      // subprocess cause may enter retained acceptance evidence.
      mintFailure = 'mint_failed';
      fail(mintFailure);
    }
    current(signal);
    const token = answer?.stdout?.trim();
    if (typeof token !== 'string' || !/^[A-Za-z0-9._~-]{20,4096}$/u.test(token)) {
      fail('invalid_token');
    }
    return token;
  };
  const resolveSecret = async (scope, signal) => {
    current(signal);
    if (scope?.resourceOrigin !== 'https://storage.googleapis.com' ||
        scope.connectorRegistration !== 'gcs' ||
        !['gcs:file:list', 'gcs:file:read'].includes(scope.operation)) fail('scope');
    // Reserve the installed transport's maximum reply before allowing each
    // send. Rejected replies consume this allowance too. A reservation is a
    // campaign upper bound, never a claim about actual bytes received.
    if (calls >= configuration.limits.maxRequests ||
        reservedResponseBytes + maxResponseBytesPerCall > configuration.limits.maxResponseBytes) {
      fail('budget');
    }
    calls++;
    reservedResponseBytes += maxResponseBytesPerCall;
    pending ??= mint(signal);
    const token = await pending;
    current(signal);
    return token;
  };
  // Do not automatically retry a failed request or silently mint a new token.
  // A rejected token leaves this campaign failed; a new campaign is explicit.
  resolveSecret.invalidate = () => { closed = true; pending = undefined; };
  return Object.freeze({resolveSecret,
    close() { closed = true; pending = undefined; },
    observation() { return Object.freeze({credentialResolutions: calls,
      reservedResponseBytes, tokenMints: mints, closed,
      ...(mintFailure === undefined ? {} : {mintFailure})}); }});
}
