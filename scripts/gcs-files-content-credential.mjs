// Test-only short-lived credential resolution. The installed Connector still
// owns targets, authorization, physical requests and capture. This adds finite
// campaign limits, not an alternative credential journal or acquisition owner.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {isAbsolute} from 'node:path';
import {checkGcsAcceptanceEnvironment} from './gcs-files-content-environment.mjs';

const execute = promisify(execFile);
const fail = reason => { throw Object.assign(new Error(`GcsAcceptanceCredential:${reason}`),
  {code: 'GcsAcceptanceCredential', reason}); };

// Classify only the existing subprocess result. Never read/retain message,
// output, command, path or cause; even accessors are not diagnostic inputs.
// Termination is not proof of timeout, IAM failure or physical cleanup.
function mintFailureDetail(error) {
  const ownData = name => {
    if (error === null || !['object', 'function'].includes(typeof error)) return undefined;
    const field = Object.getOwnPropertyDescriptor(error, name);
    return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  try {
    const code = ownData('code');
    if (code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') return Object.freeze({kind: 'output_limit'});
    if (code === 'ABORT_ERR') return Object.freeze({kind: 'aborted'});
    if (['ENOENT', 'EACCES', 'EPERM', 'ENOEXEC', 'EAGAIN', 'ENOMEM'].includes(code)) {
      return Object.freeze({kind: 'spawn_failed'});
    }
    if (ownData('killed') === true ||
        ['SIGTERM', 'SIGKILL', 'SIGINT', 'SIGHUP'].includes(ownData('signal'))) {
      return Object.freeze({kind: 'terminated'});
    }
    if (Number.isInteger(code) && code >= 1 && code <= 255) {
      return Object.freeze({kind: 'nonzero_exit', exitCode: code});
    }
  } catch {
    // A foreign/proxy exception supplies no trustworthy process classification.
  }
  return Object.freeze({kind: 'unclassified'});
}

const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === keys.slice().sort().join('\0');
const text = (value, maximum) => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value) && Buffer.byteLength(value) <= maximum;
const positive = (value, maximum) => Number.isSafeInteger(value) && value > 0 && value <= maximum;

// A distinct test scenario, not a relaxation of the historical content-reader
// manifest. The installed Source still binds project/bucket/prefix and proves
// authorization; this nonsecret document alone issues no credential grant.
export function checkGcsMetadataAcceptanceEnvironment(value) {
  if (!closed(value, ['version', 'project', 'bucket', 'prefix', 'credential',
    'permissions', 'limits', 'costLimitUsd', 'expectedObjects']) ||
      value.version !== 'actql-gcs-metadata-acceptance/0.1') fail('metadata_shape');
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u.test(value.project ?? '') ||
      !/^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/u.test(value.bucket ?? '') ||
      !text(value.prefix, 1024) || !value.prefix.endsWith('/')) fail('metadata_scope');
  if (!closed(value.credential, ['kind', 'serviceAccount', 'account', 'executable']) ||
      value.credential.kind !== 'gcloud-impersonation' ||
      !text(value.credential.account, 256) || !/^[^\s@]+@[^\s@]+$/u.test(value.credential.account) ||
      !text(value.credential.serviceAccount, 256) ||
      !value.credential.serviceAccount.endsWith(`@${value.project}.iam.gserviceaccount.com`) ||
      value.credential.serviceAccount.split('@').length !== 2 ||
      !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u.test(value.credential.serviceAccount.split('@')[0]) ||
      !text(value.credential.executable, 4096) || !isAbsolute(value.credential.executable)) {
    fail('metadata_credential');
  }
  if (!Array.isArray(value.permissions) || value.permissions.length !== 2 ||
      !value.permissions.includes('list') || !value.permissions.includes('read_metadata')) {
    fail('metadata_permissions');
  }
  if (!closed(value.limits, ['maxRequests', 'maxResponseBytes', 'maxDurationMs']) ||
      !positive(value.limits.maxRequests, 10) || !positive(value.limits.maxResponseBytes, 1048576) ||
      !positive(value.limits.maxDurationMs, 60000)) fail('metadata_limits');
  if (!Number.isFinite(value.costLimitUsd) || value.costLimitUsd <= 0 || value.costLimitUsd > 1) {
    fail('metadata_cost');
  }
  if (!Array.isArray(value.expectedObjects) || value.expectedObjects.length === 0 ||
      value.expectedObjects.length > 16 || new Set(value.expectedObjects).size !== value.expectedObjects.length ||
      value.expectedObjects.some(name => !text(name, 1024) || !name.startsWith(value.prefix))) {
    fail('metadata_objects');
  }
  return Object.freeze({...value, credential: Object.freeze({...value.credential}),
    permissions: Object.freeze(value.permissions.slice()), limits: Object.freeze({...value.limits}),
    expectedObjects: Object.freeze(value.expectedObjects.slice())});
}

export function createGcsAcceptanceCredential(manifest, options = {}) {
  return createCredential(checkGcsAcceptanceEnvironment(manifest),
    ['gcs:file:list', 'gcs:file:read'], options);
}

export function createGcsMetadataAcceptanceCredential(manifest, options = {}) {
  return createCredential(checkGcsMetadataAcceptanceEnvironment(manifest), ['gcs:file:list'], options);
}

function createCredential(configuration, operations, {
  maxResponseBytesPerCall, now = Date.now, run = execute,
} = {}) {
  if (!Number.isSafeInteger(maxResponseBytesPerCall) || maxResponseBytesPerCall < 1 ||
      maxResponseBytesPerCall > configuration.limits.maxResponseBytes ||
      typeof now !== 'function' || typeof run !== 'function') fail('configuration');
  const startedAt = now();
  if (!Number.isSafeInteger(startedAt) || startedAt < 0) fail('configuration');
  let calls = 0, reservedResponseBytes = 0, mints = 0, pending, closed = false, mintFailure;
  let processFailure;
  const remaining = () => {
    const observed = now();
    if (!Number.isSafeInteger(observed) || observed < startedAt) fail('clock');
    return Math.max(0, configuration.limits.maxDurationMs - (observed - startedAt));
  };
  const current = signal => {
    signal?.throwIfAborted();
    if (closed) fail('closed');
    if (remaining() <= 0) fail('deadline');
  };
  const mint = async signal => {
    current(signal);
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
    } catch (error) {
      // execFile failures contain stdout/stderr. Neither these nor a raw
      // subprocess cause may enter retained acceptance evidence.
      mintFailure = 'mint_failed';
      processFailure = mintFailureDetail(error);
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
        !operations.includes(scope.operation)) fail('scope');
    // Reserve the installed transport's maximum reply before allowing each
    // send. Rejected replies consume this allowance too. A reservation is a
    // campaign upper bound, never a claim about actual bytes received.
    if (calls >= configuration.limits.maxRequests ||
        reservedResponseBytes + maxResponseBytesPerCall > configuration.limits.maxResponseBytes) {
      fail('budget');
    }
    calls++;
    reservedResponseBytes += maxResponseBytesPerCall;
    // Install the one-shot promise before invoking an injected subprocess
    // adapter, so even synchronous adapter reentry cannot start a second mint.
    pending ??= Promise.resolve().then(() => mint(signal));
    const token = await pending;
    current(signal);
    return token;
  };
  // Do not automatically retry a failed request or silently mint a new token.
  // A rejected token leaves this campaign failed; a new campaign is explicit.
  resolveSecret.invalidate = () => { closed = true; pending = undefined; };
  return Object.freeze({resolveSecret,
    // The caller must use the remaining campaign time for its actual Source
    // cancellation/transport deadline too. Checking before mint/send does not
    // itself abort an already-running HTTP request.
    remainingDurationMs() { current(); return remaining(); },
    close() { closed = true; pending = undefined; },
    observation() { return Object.freeze({credentialResolutions: calls,
      reservedResponseBytes, tokenMints: mints, closed,
      ...(mintFailure === undefined ? {} : {mintFailure, mintFailureDetail: processFailure})}); }});
}
