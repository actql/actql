// Local Host selection of the execution-account configuration.
//
// The configuration is always explicit Host installation: a file the operator
// names (for example `--account-config`). Nothing here infers grants from a
// missing file, a registered Connector or a Program. A missing selection
// installs the Missing gate, which denies every protected boundary with
// `configuration_missing` (runtime code ACTQL_E_ACCOUNT_CONFIG_INVALID); an
// unreadable or rejected file fails installation with the same runtime code.
import {createHash} from 'node:crypto';
import {readFile, stat} from 'node:fs/promises';
import {openSync, readSync, closeSync, fstatSync} from 'node:fs';
import {isAbsolute, resolve} from 'node:path';
import {createNodeAuthorizationGate} from './authorization.mjs';

export const ACCOUNT_CONFIG_INVALID = 'ACTQL_E_ACCOUNT_CONFIG_INVALID';
const MAX_CONFIGURATION_BYTES = 1_000_000;

// Physical observation only. Core admits/evaluates the returned original
// bytes. The extra byte detects growth without an unbounded read or allocation.
function observeAccountConfigurationWire(authorization) {
  try {
    let wire = authorization?.accountConfiguration;
    if (authorization?.accountConfig !== undefined) {
      if (wire !== undefined) return undefined;
      const fd = openSync(authorization.accountConfig, 'r');
      try {
        // Size selects only a bounded workspace, never configuration identity
        // or authority. Read the original FD's contents below; one extra byte
        // refuses growth rather than admitting a truncated configuration.
        const size = fstatSync(fd).size;
        if (!Number.isSafeInteger(size) || size < 0 || size > MAX_CONFIGURATION_BYTES) {
          return undefined;
        }
        const buffer = Buffer.alloc(size + 1);
        let used = 0;
        while (used < buffer.length) {
          const read = readSync(fd, buffer, used, buffer.length - used, used);
          if (read === 0) break;
          used += read;
        }
        if (used > size) return undefined;
        wire = new TextDecoder('utf-8', {fatal: true}).decode(buffer.subarray(0, used));
      } finally { closeSync(fd); }
    }
    return typeof wire === 'string' && Buffer.byteLength(wire) <= MAX_CONFIGURATION_BYTES
      ? wire : undefined;
  } catch { return undefined; }
}

// Shared by the installed Model owner and Local account gate. This reads no
// new identity or permit and preserves the existing Model Missing fallback.
const installedAccountObservations = new WeakMap();
export function observeInstalledAccount(moon, authorization) {
  try {
    const wire = observeAccountConfigurationWire(authorization);
    if (wire === undefined) return moon.executionAuthorizationMissing();
    // Keep only one admitted immutable value per actual runtime/installation.
    // The original file is still read at EVERY protected boundary. Changed,
    // missing and rejected bytes cannot reuse the retained Account judgment.
    if (authorization === null || typeof authorization !== 'object') {
      return moon.executionAuthorizationAdmit(wire);
    }
    let observations = installedAccountObservations.get(moon);
    if (observations === undefined) {
      observations = new WeakMap();
      installedAccountObservations.set(moon, observations);
    }
    const retained = observations.get(authorization);
    if (retained?.wire === wire) return retained.account;
    const account = moon.executionAuthorizationAdmit(wire);
    observations.set(authorization, {wire, account});
    return account;
  } catch { return moon.executionAuthorizationMissing(); }
}

const fail = (code, detail) => {
  throw Object.assign(new Error(code, {cause: detail}), {code});
};

function normalizedText(value) {
  if (typeof value.isWellFormed === 'function' && !value.isWellFormed()) {
    fail('InvalidCanonicalText');
  }
  return value.normalize('NFC');
}

// Canonical JSON for Host-local identities: sorted keys, no whitespace,
// NFC text. Used for the configuration CID and Local Host records.
export function canonicalJson(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || Object.is(value, -0)) fail('InvalidCanonicalNumber');
    return JSON.stringify(value);
  }
  if (typeof value === 'string') return JSON.stringify(normalizedText(value));
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (typeof value !== 'object' || Object.getPrototypeOf(value) !== Object.prototype) {
    fail('InvalidCanonicalValue');
  }
  const entries = Object.entries(value)
    .filter(([, item]) => item !== undefined)
    .map(([key, item]) => [normalizedText(key), item]);
  entries.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return `{${entries.map(([key, item]) =>
    `${JSON.stringify(key)}:${canonicalJson(item)}`).join(',')}}`;
}

export function contentCid(value) {
  return `sha256:${createHash('sha256').update(canonicalJson(value), 'utf8')
    .digest('hex')}`;
}

// Immutable private Store policy DATA shared by projected Content and the
// original lookup transport. This computes identities, never capture authority.
export function originalLocalContentStoragePolicy({storeAuthorityCid, authorityScopeCid,
  runDefinitionCid, expiresAt}) {
  return Object.freeze({
    availabilityEvidenceCid: contentCid({version:'actql-installed-local-policy/0.1',
      name:'content-availability', storeAuthorityCid, runDefinitionCid, expiresAt}),
    issuerContractCid: contentCid({version:'actql-installed-local-policy/0.1',
      name:'content-issuer', storeAuthorityCid, authorityScopeCid}),
  });
}

export function bytesCid(bytes) {
  return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}

function configurationOf(text) {
  let document;
  try { document = JSON.parse(text); }
  catch (error) { fail(ACCOUNT_CONFIG_INVALID, error); }
  if (document === null || typeof document !== 'object' ||
      typeof document.account_id !== 'string') {
    fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationShape');
  }
  return {
    text,
    configurationCid: contentCid(document),
    accountId: document.account_id,
  };
}

// Read one configuration file. Its identity is the CID of the complete
// canonical document; admission (canonical order, overlap) stays in Core.
export async function readAccountConfiguration(path) {
  if (typeof path !== 'string' || path.length === 0) {
    fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationPathRequired');
  }
  const absolute = isAbsolute(path) ? path : resolve(path);
  let text;
  try {
    if ((await stat(absolute)).size > MAX_CONFIGURATION_BYTES) {
      fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationTooLarge');
    }
    const bytes = await readFile(absolute);
    if (bytes.length > MAX_CONFIGURATION_BYTES) {
      fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationTooLarge');
    }
    text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
  } catch (error) {
    if (error?.code === ACCOUNT_CONFIG_INVALID) throw error;
    fail(ACCOUNT_CONFIG_INVALID, error);
  }
  return Object.freeze({path: absolute, ...configurationOf(text)});
}

// Trusted Local context for one account. The context CID identifies the
// principal and account the Host installed; it is not Program input.
export function localAuthorizationContext(principal, accountId) {
  return Object.freeze({
    principal,
    contextCid: contentCid({host: 'actql-local-host', principal,
      account_id: accountId ?? null}),
  });
}

// Install the gate from an explicit configuration file (`accountConfig`) or
// the exact configuration text a trusted parent Host installed
// (`accountConfiguration`), or the Missing gate when neither was selected. A
// selected but unreadable or rejected configuration is an installation
// failure; it never degrades to Missing or to allow.
export async function createLocalAuthorizationGate({
  accountConfig, accountConfiguration, principal = 'local-operator', context,
  ...options
} = {}) {
  const none = value => value === undefined || value === null;
  if (!none(accountConfig) && !none(accountConfiguration)) {
    fail(ACCOUNT_CONFIG_INVALID, 'ConflictingAccountConfiguration');
  }
  if (none(accountConfig) && none(accountConfiguration)) {
    return createNodeAuthorizationGate({...options, readConfiguration: undefined,
      context: context ??
      localAuthorizationContext(principal, undefined)});
  }
  if (!none(accountConfiguration) && typeof accountConfiguration !== 'string') {
    fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationText');
  }
  const configuration = none(accountConfig)
    ? configurationOf(accountConfiguration)
    : await readAccountConfiguration(accountConfig);
  const installedContext = context ?? localAuthorizationContext(principal,
    configuration.accountId);
  try {
    const gate = await createNodeAuthorizationGate({
      ...options,
      configuration: configuration.text,
      configurationCid: configuration.configurationCid,
      // Retain the installation's resolved path, not a later cwd or caller
      // property. A wire-backed gate owns its immutable admitted configuration.
      readConfiguration: configuration.path === undefined ? undefined
        : () => observeAccountConfigurationWire({accountConfig: configuration.path}),
      context: installedContext,
    });
    // The installed row Source and its Checkpoint projection need the same
    // admitted configuration and context, not a second Missing Account. The
    // original gate still owns its file-current reader and decision methods;
    // this retained DATA neither grants a tuple nor acknowledges cleanup.
    return Object.freeze({...gate, accountConfiguration: configuration.text,
      context: installedContext});
  } catch (error) {
    if (error?.code === 'ExecutionAuthorizationConfigurationRejected') {
      error.runtimeCode = ACCOUNT_CONFIG_INVALID;
    }
    throw error;
  }
}

// Canonical text of an explicit one-entry configuration for reading one
// source resource (`outcome` may also be `delegate` or `deny`). A helper for
// writing an operator-owned file; nothing installs it implicitly.
export function sourceReadAccountConfiguration({connection, resource,
  outcome = 'allow', accountId = 'local-account', entryId = 'source-read'}) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: accountId,
    entries: [{
      entry_id: entryId,
      outcome,
      principal: {all: true},
      connection: {any_of: [connection]},
      resource: {any_of: [resource]},
      operation: {any_of: ['read']},
      exclusions: [],
    }],
  });
}

