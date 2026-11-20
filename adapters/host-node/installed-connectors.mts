// The standard Host's installed connector table: which connector-owned
// module an installed Host profile's version selects. Entries come from the
// generated `adapters/connectors-builtin/installations.generated.mjs`
// (connector `host-bundle.json` manifests) and from the Host's own built-in
// bindings. Selecting an entry grants nothing: the selected module checks
// the profile, restores its published declaration and binds its Site.
//
// A source installation module exports:
// - `check(providerProfile)`: the profile's shape, before any I/O;
// - `identityParts(profile, providerProfile, read, installation)`: the parts of the
//   installation identity (the profile and the installed, published
//   documents it names), without a credential value or provider I/O. The
//   selected declaration's finite implementation inventory is also available;
// - `load(checked, {root, principalId, moon, baseEnvironmentWire,
//   resolveSecret, installation, providerMoon?, runtimeBundleCid?})`: the
//   installed source adapter (`installed-source.mjs`);
// - optionally `publish(checked, options)`: the explicit publication step.
//
// Source and Effect are independent optional roles; an entry has at least one.
// An Effect installation module (`effect` section) exports the same
// entries; its `identityParts(profile, read, installation)` takes no separate
// provider profile, and its
// `load` also receives the Host's own `ledgerRoot` and returns the Effect
// Site hooks (`installed-effect.mjs`).
import {basename} from 'node:path';
import type {InstalledConnectorEntry as DeclaredEntry, InstalledConnectorTable} from '../../packages/local-node/index.d.ts';
import {validInstalledEffectIdentityProfile, validInstalledResponseHeaders}
  from '../host-common/installed-connector-declaration.mjs';

// Unchecked installation fields keep every original runtime guard. Checked
// declarations are DATA; only the original WeakMap/WeakSet recognize table custody.
type RoleInput = {profileVersion?: unknown; load?: unknown; identityProfile?: unknown};
type EntryInput = {name?: unknown; registration?: unknown; revision?: unknown;
  providerBundle?: unknown; responseHeaders?: unknown; implementationFiles?: unknown;
  source?: RoleInput | null; effect?: RoleInput | null};
type InstallationModule = {check(...args: unknown[]): unknown; identityParts(...args: unknown[]): unknown;
  load(...args: unknown[]): unknown; publish?: (...args: unknown[]) => unknown};
type ModuleInput = {check?: unknown; identityParts?: unknown; load?: unknown; publish?: unknown};
type ConnectorTable = ReadonlyMap<string, DeclaredEntry>;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new TypeError(code, {cause}), {code});
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const registrationPattern = /^[a-z][a-z0-9_]*$/u;
const profileVersionPattern = /^actql-installed-[a-z0-9-]+\/0\.1$/u;

function checkEntry(entry: EntryInput) {
  if (!entry || typeof entry !== 'object' || !text(entry.name) ||
      !registrationPattern.test(entry.name) ||
      (entry.source === undefined && entry.effect === undefined) ||
      (entry.source !== undefined && (!entry.source || typeof entry.source !== 'object' ||
        typeof entry.source.profileVersion !== 'string' ||
        !profileVersionPattern.test(entry.source.profileVersion ?? '') ||
        typeof entry.source.load !== 'function')) ||
      (entry.registration !== undefined && (entry.registration !== entry.name ||
        !text(entry.revision) ||
        !entry.revision.startsWith(`${entry.registration}/`))) ||
      (entry.revision !== undefined && !text(entry.revision)) ||
      (entry.providerBundle !== undefined &&
        (typeof entry.providerBundle !== 'string' ||
          !/^connectors\/[a-z][a-z0-9_]*\/[a-z][a-z0-9_]*$/u.test(
            entry.providerBundle))) ||
      (entry.responseHeaders !== undefined &&
        !validInstalledResponseHeaders(entry.responseHeaders)) ||
      (entry.implementationFiles !== undefined && (!Array.isArray(entry.implementationFiles) ||
        entry.implementationFiles.length < 1 || entry.implementationFiles.length > 128 ||
        new Set(entry.implementationFiles.map(file => file?.path)).size !== entry.implementationFiles.length ||
        entry.implementationFiles.some(file => typeof file?.path !== 'string' || typeof file.href !== 'string'))) ||
      (entry.effect !== undefined && (!entry.effect ||
        typeof entry.effect !== 'object' ||
        typeof entry.effect.profileVersion !== 'string' ||
        !profileVersionPattern.test(entry.effect.profileVersion ?? '') ||
        entry.effect.profileVersion === entry.source?.profileVersion ||
        (entry.effect.identityProfile !== undefined &&
          !validInstalledEffectIdentityProfile(entry.effect.identityProfile)) ||
        typeof entry.effect.load !== 'function'))) {
    fail('InvalidInstalledConnectorEntry');
  }
  return entry as DeclaredEntry;
}

// Handles and admitted entries carry owner-held provenance, not an exposed
// Map or a structural marker that caller data can copy.
const connectorTables = new WeakMap<object, {source: ConnectorTable; effect: ConnectorTable}>();
const connectorTableEntries = new WeakSet<object>();

function snapshotRole(section: RoleInput | null | undefined, role: string) {
  if (section === undefined) return undefined;
  if (!section || typeof section !== 'object' || Array.isArray(section)) {
    fail('InvalidInstalledConnectorEntry');
  }
  const {profileVersion, load} = section;
  const identityProfile = role === 'effect' ? section.identityProfile : undefined;
  if (identityProfile !== undefined && (!identityProfile ||
      typeof identityProfile !== 'object' || Array.isArray(identityProfile))) {
    fail('InvalidInstalledConnectorEntry');
  }
  return Object.freeze({profileVersion, load,
    ...(identityProfile === undefined ? {} :
      {identityProfile: Object.freeze({...identityProfile})})});
}

function snapshotEntry(entry: EntryInput) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    fail('InvalidInstalledConnectorEntry');
  }
  const {name, registration, revision, providerBundle, responseHeaders, implementationFiles,
    source, effect} = entry;
  if (responseHeaders !== undefined && !Array.isArray(responseHeaders)) {
    fail('InvalidInstalledConnectorEntry');
  }
  if (implementationFiles !== undefined && (!Array.isArray(implementationFiles) ||
      implementationFiles.some(file => !file || typeof file !== 'object' || Array.isArray(file)))) {
    fail('InvalidInstalledConnectorEntry');
  }
  const snapshot = {
    name,
    ...(registration === undefined ? {} : {registration}),
    ...(revision === undefined ? {} : {revision}),
    ...(providerBundle === undefined ? {} : {providerBundle}),
    ...(responseHeaders === undefined ? {} :
      {responseHeaders: Object.freeze([...responseHeaders])}),
    ...(implementationFiles === undefined ? {} :
      {implementationFiles: Object.freeze(implementationFiles.map(file =>
        Object.freeze({path: file.path, href: file.href})))}),
    ...(source === undefined ? {} : {source: snapshotRole(source, 'source')}),
    ...(effect === undefined ? {} : {effect: snapshotRole(effect, 'effect')}),
  };
  return Object.freeze(checkEntry(snapshot));
}

// Trusted Host bootstrap code chooses this complete, process-local table.
// Copy and validate every declaration before returning; loader references
// remain lazy. This handle provides neither durable identity nor authority.
export function createInstalledConnectorTable(entries: unknown) {
  if (!Array.isArray(entries)) fail('InvalidInstalledConnectorEntry');
  const snapshots = (entries as EntryInput[]).map(snapshotEntry);
  const source = installedConnectorTable(snapshots);
  const effect = installedEffectTable(snapshots);
  const handle = Object.freeze({});
  connectorTables.set(handle, {source, effect});
  for (const entry of snapshots) connectorTableEntries.add(entry);
  return handle as InstalledConnectorTable;
}

export function assertInstalledConnectorTable(handle: unknown) {
  if (!connectorTables.has(handle as object)) fail('InvalidInstalledConnectorTable');
  return handle as InstalledConnectorTable;
}

export function installedConnectorForTable(handle: unknown, role: unknown, profile: unknown,
  code = role === 'effect' ? 'InvalidInstalledEffectProfile' :
    'InvalidInstalledSourceProfile') {
  const table = connectorTables.get(assertInstalledConnectorTable(handle) as object)!;
  if (role !== 'source' && role !== 'effect') {
    fail('InvalidInstalledConnectorRole');
  }
  return installedConnectorFor(table[role], profile, code);
}

// Only the table owner can admit an entry; frozen caller objects and copies
// of admitted entries cannot supply an Effect identity profile.
export function isInstalledConnectorTableEntry(entry: unknown) {
  return connectorTableEntries.has(entry as object);
}

// The table by installed Effect profile version, over the entries that
// declare an Effect installation.
export function installedEffectTable(entries: unknown) {
  if (!Array.isArray(entries)) fail('InvalidInstalledConnectorEntry');
  const table = new Map<string, DeclaredEntry>();
  for (const entry of entries as EntryInput[]) {
    const checked = checkEntry(entry);
    if (checked.effect === undefined) continue;
    if (table.has(checked.effect.profileVersion)) {
      fail('InstalledConnectorVersionAmbiguous');
    }
    table.set(checked.effect.profileVersion, checked);
  }
  return table;
}

// Load the selected connector's Effect installation module.
export async function loadInstalledEffectModule(entry: {effect?: {load(): unknown}}) {
  const module = await entry.effect!.load() as ModuleInput;
  if (!module || typeof module !== 'object' ||
      typeof module.check !== 'function' ||
      typeof module.identityParts !== 'function' ||
      typeof module.load !== 'function' ||
      (module.publish !== undefined && typeof module.publish !== 'function')) {
    fail('InvalidInstalledConnectorModule');
  }
  return module as InstallationModule;
}

// The table by installed source profile version; duplicate versions refuse
// the whole table before any profile is read.
export function installedConnectorTable(entries: unknown) {
  if (!Array.isArray(entries)) fail('InvalidInstalledConnectorEntry');
  const table = new Map<string, DeclaredEntry>();
  for (const entry of entries as EntryInput[]) {
    const checked = checkEntry(entry);
    if (checked.source === undefined) continue;
    if (table.has(checked.source.profileVersion)) {
      fail('InstalledConnectorVersionAmbiguous');
    }
    table.set(checked.source.profileVersion, checked);
  }
  return table;
}

export function installedConnectorFor(table: ConnectorTable, profile: unknown,
  code = 'InvalidInstalledSourceProfile') {
  const entry = typeof (profile as {version?: unknown} | null | undefined)?.version === 'string'
    ? table.get((profile as {version: string}).version) : undefined;
  if (entry === undefined) fail(code);
  return entry;
}

// The connector's compiled provider bundle, next to the standard runtime.
export function providerBundleUrl(entry: Pick<DeclaredEntry, 'providerBundle'>, base: string | URL = import.meta.url) {
  if (entry.providerBundle === undefined) return undefined;
  return new URL(`../../_build/js/release/build/${entry.providerBundle}/` +
    `${basename(entry.providerBundle)}.js`, base);
}

// Load the selected connector's source installation module and check that
// it is one: every required entry is a function.
export async function loadInstalledConnectorModule(entry: {source?: {load(): unknown}}) {
  const module = await entry.source!.load() as ModuleInput;
  if (!module || typeof module !== 'object' ||
      typeof module.check !== 'function' ||
      typeof module.identityParts !== 'function' ||
      typeof module.load !== 'function' ||
      (module.publish !== undefined && typeof module.publish !== 'function')) {
    fail('InvalidInstalledConnectorModule');
  }
  return module as InstallationModule;
}

// The declared registration and revision are a claim about the installed
// implementation, not authority: the loaded adapter must identify itself
// with the same values, or the installation is refused.
export function verifyInstalledConnectorRegistration<T>(entry: Pick<DeclaredEntry, 'registration' | 'revision'>, adapter: T) {
  if (entry.registration === undefined) return adapter;
  if ((adapter as {connectorRegistration?: unknown} | null | undefined)?.connectorRegistration !== entry.registration ||
      (adapter as {connectorRevision?: unknown} | null | undefined)?.connectorRevision !== entry.revision) {
    fail('InstalledConnectorRegistrationMismatch');
  }
  return adapter;
}
