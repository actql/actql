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
import {isAccountConstruction, readAccountOriginal, readAccountCurrent} from './account-construction.mjs';

import type {BinaryLike} from 'node:crypto';
import type {createAccountConstruction} from './account-construction.mjs';
import type {loadExecutionAuthorizationRuntime} from './authorization.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type NodeAuthorizationOptions = NonNullable<Parameters<typeof createNodeAuthorizationGate>[0]>;
type AuthorizationRuntime = Awaited<ReturnType<typeof loadExecutionAuthorizationRuntime>>;
type AccountRuntime = Pick<AuthorizationRuntime, 'executionAuthorizationAdmit' | 'executionAuthorizationMissing'>;
type Account = ReturnType<AuthorizationRuntime['executionAuthorizationAdmit']>;
type LocalGate = Awaited<ReturnType<typeof createNodeAuthorizationGate>> & Readonly<{
  accountConfiguration?: string; context?: NodeAuthorizationOptions['context'];
}>;
type Construction = ReturnType<typeof createAccountConstruction>;
type Frame = ReturnType<Construction['begin']>;
type Selection = Readonly<{
  accountConfig?: string | null; accountConfiguration?: string | null;
  accountConstruction?: Construction;
}>;
type LocalAuthorizationOptions = NodeAuthorizationOptions & Selection & Readonly<{principal?: string}>;
type ObservedConfiguration = Readonly<{text: string; accountId: string; path?: string}>;
type ErrorFields = {code?: unknown; runtimeCode?: string};

export const ACCOUNT_CONFIG_INVALID = 'ACTQL_E_ACCOUNT_CONFIG_INVALID';
const MAX_CONFIGURATION_BYTES = 1_000_000;

// Physical observation only. Core admits/evaluates the returned original
// bytes. The extra byte detects growth without an unbounded read or allocation.
function observeAccountConfigurationWire(authorization: Selection | null | undefined, frame?: Frame) {
  try {
    let wire = authorization?.accountConfiguration;
    if (authorization?.accountConfig !== undefined) {
      if (wire !== undefined) return undefined;
      if (frame !== undefined) return readAccountCurrent(authorization.accountConfig!, frame);
      const fd = openSync(authorization.accountConfig!, 'r');
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
    return typeof wire === 'string' && (frame !== undefined || Buffer.byteLength(wire) <= MAX_CONFIGURATION_BYTES)
      ? wire : undefined;
  } catch { return undefined; }
}

// Shared by the installed Model owner and Local account gate. This reads no
// new identity or permit and preserves the existing Model Missing fallback.
const installedAccountObservations = new WeakMap<AccountRuntime, WeakMap<object, Readonly<{wire: string; account: Account}>>>();
export function observeInstalledAccount(moon: AccountRuntime, authorization?: Selection | null, construction?: Construction) {
  construction ??= authorization?.accountConstruction;
  if (construction !== undefined) {
    if (!isAccountConstruction(construction)) throw new TypeError('ForeignAccountConstruction');
    return construction.observe(frame => observeInstalledAccountOriginal(moon, authorization, frame, construction));
  }
  return observeInstalledAccountOriginal(moon, authorization);
}

function observeInstalledAccountOriginal(moon: AccountRuntime, authorization?: Selection | null, frame?: Frame, construction?: Construction) {
  try {
    const wire = observeAccountConfigurationWire(authorization, frame);
    if (wire === undefined) return moon.executionAuthorizationMissing();
    // Keep only one admitted immutable value per actual runtime/installation.
    // The original file is still read at EVERY protected boundary. Changed,
    // missing and rejected bytes cannot reuse the retained Account judgment.
    if (authorization === null || typeof authorization !== 'object') {
      return frame === undefined ? moon.executionAuthorizationAdmit(wire) : frame.admit(moon, wire);
    }
    let observations = installedAccountObservations.get(moon);
    if (observations === undefined) {
      observations = new WeakMap();
      installedAccountObservations.set(moon, observations);
    }
    const retained = observations.get(authorization);
    if (retained?.wire === wire) return retained.account;
    const account = frame === undefined ? moon.executionAuthorizationAdmit(wire) : frame.admit(moon, wire);
    observations.set(authorization, {wire, account});
    if (frame !== undefined) {
      frame.hold();
      construction!.onRetire(() => {observations!.delete(authorization);});
    }
    return account;
  } catch { return moon.executionAuthorizationMissing(); }
}

const fail: (code: string, detail?: unknown) => never = (code, detail) => {
  throw Object.assign(new Error(code, {cause: detail}), {code});
};

function normalizedText(value: string) {
  if (typeof value.isWellFormed === 'function' && !value.isWellFormed()) {
    fail('InvalidCanonicalText');
  }
  return value.normalize('NFC');
}

// Canonical JSON for Host-local identities: sorted keys, no whitespace,
// NFC text. Used for Host-local records and operator configuration authoring.
// Admitted Account identities come from Common, not this Host-local writer.
export function canonicalJson(value: unknown): string {
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
    .map(([key, item]): [string, unknown] => [normalizedText(key), item]);
  entries.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return `{${entries.map(([key, item]) =>
    `${JSON.stringify(key)}:${canonicalJson(item)}`).join(',')}}`;
}

export function contentCid(value: unknown) {
  return `sha256:${createHash('sha256').update(canonicalJson(value), 'utf8')
    .digest('hex')}`;
}

// Immutable private Store policy DATA shared by projected Content and the
// original lookup transport. This computes identities, never capture authority.
export function originalLocalContentStoragePolicy({storeAuthorityCid, authorityScopeCid,
  runDefinitionCid, expiresAt}: Readonly<{storeAuthorityCid: string; authorityScopeCid: string;
  runDefinitionCid: string; expiresAt: string}>) {
  return Object.freeze({
    availabilityEvidenceCid: contentCid({version:'actql-installed-local-policy/0.1',
      name:'content-availability', storeAuthorityCid, runDefinitionCid, expiresAt}),
    issuerContractCid: contentCid({version:'actql-installed-local-policy/0.1',
      name:'content-issuer', storeAuthorityCid, authorityScopeCid}),
  });
}

export function bytesCid(bytes: BinaryLike) {
  return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}

function configurationOf(text: string, frame?: Frame) {
  frame?.nativeJson(text);
  let document: {account_id?: unknown} | null;
  try { document = JSON.parse(text) as {account_id?: unknown} | null; }
  catch (error) { fail(ACCOUNT_CONFIG_INVALID, error); }
  if (document === null || typeof document !== 'object' ||
      typeof document.account_id !== 'string') {
    fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationShape');
  }
  return {
    text,
    accountId: document.account_id,
  };
}

// Read one original configuration file. Core owns admission (canonical order,
// overlap) and the admitted complete document's CID; the reader issues no CID.
export async function readAccountConfiguration(path: string, frame?: Frame) {
  if (typeof path !== 'string' || path.length === 0) {
    fail(ACCOUNT_CONFIG_INVALID, 'AccountConfigurationPathRequired');
  }
  const absolute = isAbsolute(path) ? path : resolve(path);
  let text: string;
  if (frame !== undefined) {
    try {text = await readAccountOriginal(absolute, frame);}
    catch (cause) {fail(ACCOUNT_CONFIG_INVALID, cause);}
    return Object.freeze({path: absolute, ...configurationOf(text, frame)});
  }
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
    if ((error as ErrorFields | null | undefined)?.code === ACCOUNT_CONFIG_INVALID) throw error;
    fail(ACCOUNT_CONFIG_INVALID, error);
  }
  return Object.freeze({path: absolute, ...configurationOf(text)});
}

// Trusted Local context for one account. The context CID identifies the
// principal and account the Host installed; it is not Program input.
export function localAuthorizationContext(principal: string, accountId: string | undefined) {
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
export async function createLocalAuthorizationGate({accountConstruction, ...options}: LocalAuthorizationOptions = {}): Promise<LocalGate> {
  if (accountConstruction === undefined) return createLocalAuthorizationGateOriginal(options);
  if (!isAccountConstruction(accountConstruction)) fail(ACCOUNT_CONFIG_INVALID, 'ForeignAccountConstruction');
  const frame = accountConstruction.begin();
  try {
    const gate = await createLocalAuthorizationGateOriginal(options, frame, accountConstruction);
    frame.retainGate(gate);
    frame.finish(true);
    return Object.freeze({...gate, close: frame.closeGate, cleanup: frame.closeGate,
      cleanupPending: frame.gateCleanupPending});
  } catch (cause) {frame.failure(cause); frame.finish(false); throw cause;}
}

async function createLocalAuthorizationGateOriginal({
  accountConfig, accountConfiguration, principal = 'local-operator', context,
  ...options
}: LocalAuthorizationOptions = {}, frame?: Frame, construction?: Construction) {
  const none = (value: unknown): value is null | undefined => value === undefined || value === null;
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
  const configuration: ObservedConfiguration = none(accountConfig)
    ? configurationOf(accountConfiguration!, frame)
    : await readAccountConfiguration(accountConfig, frame);
  const installedContext = context ?? localAuthorizationContext(principal,
    configuration.accountId);
  let observation: Frame | undefined;
  const withAccountObservation = <Value extends SynchronousRuntimeData>(operation: () => Value): Value => {
    if (observation !== undefined) fail(ACCOUNT_CONFIG_INVALID, 'AccountObservationReentry');
    return construction!.observe(current => {
      observation = current;
      try {return operation();} finally {observation = undefined;}
    });
  };
  try {
    const gate = await createNodeAuthorizationGate({
      ...options,
      ...(frame === undefined ? {} : {
        admitConfiguration: (moon, wire) => (observation ?? frame).admit(moon, wire),
        withAccountObservation,
      }),
      configuration: configuration.text,
      // Retain the installation's resolved path, not a later cwd or caller
      // property. A wire-backed gate owns its immutable admitted configuration.
      readConfiguration: configuration.path === undefined ? undefined
        : () => observeAccountConfigurationWire({accountConfig: configuration.path}, observation),
      context: installedContext,
    });
    // The installed row Source and its Checkpoint projection need the same
    // admitted configuration and context, not a second Missing Account. The
    // original gate still owns its file-current reader and decision methods;
    // this retained DATA neither grants a tuple nor acknowledges cleanup.
    return Object.freeze({...gate, accountConfiguration: configuration.text,
      context: installedContext});
  } catch (error) {
    if ((error as ErrorFields | null | undefined)?.code === 'ExecutionAuthorizationConfigurationRejected') {
      (error as ErrorFields).runtimeCode = ACCOUNT_CONFIG_INVALID;
    }
    throw error;
  }
}

// Canonical text of an explicit one-entry configuration for reading one
// source resource (`outcome` may also be `delegate` or `deny`). A helper for
// writing an operator-owned file; nothing installs it implicitly.
export function sourceReadAccountConfiguration({connection, resource,
  outcome = 'allow', accountId = 'local-account', entryId = 'source-read'}:
  Readonly<{connection: string; resource: string; outcome?: 'allow' | 'delegate' | 'deny'; accountId?: string; entryId?: string}>) {
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
