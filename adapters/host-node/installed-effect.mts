// The standard Host's installed Effects, each selected by its Host profile's
// version from the installed connector table
// (a connector's `host-bundle.json` `effect` section). The installation
// supplies only its Check Environment and the provider projections of a
// Run's capture and recovery; the Host's Run, Checkpoint, dispatch and
// publication owners stay the same, and the Host never branches on a
// provider name. It holds no secret value or private key: the Site profile
// names the credential material, and the Host's private evidence key is the
// Host's own.
//
// An installation provides `environmentWire`, `connectorBindings`,
// `connectorRegistration`/`connectorRevision` (verified against the
// declaration), `prepareCaptured(facts)` and `prepareRecovered(facts)` over
// the Host's Effect Site facts, and `close()`.
import {createHash} from 'node:crypto';
import {isAbsolute, join} from 'node:path';
import {canonicalJson} from './local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {readSourceProfileJson, installedRuntimeBundleCid, captureConfigurationReaders} from './source-profile-json.mjs';
import {composeInstalledEffects, installedUpdateTargets, validPluralEffectPaths}
  from './installed-effect-inventory.mjs';
import {retainInstalledRowEffectAdapter} from './installed-row-effect.mjs';
import {retainInstalledHostServiceInstallation, installedSourceConfigurationReader,
  reserveInstalledSourceRuntimeIdentity, withInstalledSourceLoading,
  beginInstalledSourceInitialization, finishInstalledSourceInitialization,
  bindInstalledSourceConstruction, retainBoundInstalledSourceFailure} from './installed-host-services.mjs';
export {installedEffectFor} from './installed-effect-inventory.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedConnectorForTable, installedEffectTable,
  loadInstalledEffectModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

import type {EffectOwner} from './installed-effect-inventory.mjs';
import type {createInstalledEffectSite} from './installed-effect-site.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Installation = ReturnType<typeof installedConnectorFor>;
type ReadLimits = Readonly<{maxBytes?: number}>;
type ReadProfile = (path: unknown, options?: ReadLimits) => Awaitable<unknown>;
type Readers = ReturnType<typeof captureConfigurationReaders> & Readonly<{readProfile?: ReadProfile}>;
type BoundSource = Parameters<typeof bindInstalledSourceConstruction>;
type ProfileConstruction = NonNullable<BoundSource[3]> & Readonly<{
  value: unknown; construct<Value>(project: () => Value): Value;
}>;
type ProfileSnapshot = Readonly<{
  profile: unknown; providerProfile: Readonly<Record<string, unknown>>;
  queryUpdateTargets: NonNullable<EffectOwner['queryUpdateTargets']>; construction?: ProfileConstruction;
}>;
type CleanupFault = Readonly<{
  message?: unknown; cleanupHandle?: Readonly<{primaryFailure?: unknown}>; cleanupPending?: boolean;
  cleanupErrors?: readonly unknown[]; primaryFailure?: unknown;
}>;
type IdentityOptions = Readonly<{connectorTable?: unknown; configurationReader?: object}>;
type ComposeOptions = Parameters<typeof composeInstalledEffects>[1];
type ProviderOptions = Readonly<{
  root: string; principalId: string; moon: ComposeOptions['moon']; baseEnvironmentWire: string;
  runtimeUrl?: string | URL; resolveSecret?: unknown; connectorTable?: unknown;
}>;
type LoadOptions = ProviderOptions & Readonly<{installationServices?: BoundSource[0]}>;
type PublishOptions = ProviderOptions & Readonly<{signal?: AbortSignal}>;
type Site = Parameters<typeof createInstalledEffectSite>[0];
type InstalledPorts = Pick<Site, 'targetReadInventory' | 'targetReadAuthorization' | 'prepareManagedPlan'> & Readonly<{
  mappings?: unknown;
  prepareCaptured(facts: unknown): unknown; prepareRecovered(facts: unknown): unknown;
  close(): unknown;
}>;
type LoadedEffect = EffectOwner & InstalledPorts;
type LoadedEffectInventory = Awaited<ReturnType<typeof composeInstalledEffects<string, LoadOptions & ComposeOptions, LoadedEffect>>>;
type EffectPaths = Readonly<{effectProfilePath?: string; effectProfilePaths?: readonly string[]}>;


const installations = installedEffectTable(installedConnectors);

const refuse: (code: string, cause?: unknown) => never = (code, cause) => {
  const failure = Object.assign(new TypeError(code, {cause}), {code});
  if ((cause as CleanupFault | null | undefined)?.cleanupHandle !== undefined || (cause as CleanupFault | null | undefined)?.cleanupPending === true) {
    Object.assign(failure, {cleanupHandle: (cause as CleanupFault).cleanupHandle,
      cleanupPending: (cause as CleanupFault).cleanupPending, cleanupErrors: (cause as CleanupFault).cleanupErrors,
      primaryFailure: (cause as CleanupFault).primaryFailure ?? cause});
  }
  throw failure;
};

// Bound profile and identity-part reads before buffering, including files that
// grow after opening. This limit is distinct from Check Environment admission.
async function readProfileJson(path: unknown, {maxBytes = 8 * 1024 * 1024}: ReadLimits = {}, read: unknown = readSourceProfileJson) {
  try { return await (read as ReadProfile)(path, {maxBytes}); }
  catch (cause) {
    if ((cause as CleanupFault | null | undefined)?.cleanupHandle !== undefined) {
      // The same acquired reader supplies its primary; do not infer it from
      // an error class, message or an arbitrary nested cause.
      const primary = (cause as CleanupFault).cleanupHandle!.primaryFailure;
      const failure = await retainInstalledHostInitializationFailure(cause, {});
      failure.primaryFailure = primary;
      throw failure;
    }
    if ((cause as CleanupFault | null | undefined)?.message === 'InvalidInstalledSourceProfile') {
      refuse('InvalidInstalledEffectProfile', cause);
    }
    throw cause;
  }
}

async function readProfile(path: unknown, read: ReadProfile = readProfileJson) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    refuse('InvalidInstalledEffectProfilePath');
  }
  let profile: unknown;
  try { profile = await read(path); }
  catch (cause) { refuse('InvalidInstalledEffectProfile', cause); }
  return profile;
}

// The retained original text selects the same shared profile recipe as
// Source. Split/snapshot and the later checked profile are distinct native
// constructors; neither borrows a finished JSON reader's parser workspace.
async function readConstructedProfile(path: unknown, readers: Readers,
  configurationReader: unknown): Promise<ProfileSnapshot> {
  if (configurationReader === undefined) {
    const profile = await readProfile(path, (path, options) => readProfileJson(path, options, readers.readJson));
    return {profile, ...splitUpdateTargetProfile(profile)};
  }
  const construction = await readProfile(path, selected => {
    if (typeof readers.readProfile !== 'function') refuse('InstalledConfigurationReaderUnavailable');
    return readers.readProfile(selected, {maxBytes: 8 * 1024 * 1024});
  }) as ProfileConstruction;
  // Only read/parse/FD-close belongs to that wrapper. Preserve the original
  // later split or constructor/current refusal rather than relabeling it.
  const value = construction.construct(() => Object.freeze({
    profile: construction.value, ...splitUpdateTargetProfile(construction.value)}));
  return Object.freeze({...value, construction});
}

// Select the installed connector of an Effect profile. An unknown version
// is refused before any Site or provider I/O; an explicit table never falls
// back to the standard installation.
async function selectInstallation(profile: unknown, connectorTable: unknown) {
  const entry = connectorTable === undefined
    ? installedConnectorFor(installations, profile, 'InvalidInstalledEffectProfile')
    : installedConnectorForTable(connectorTable, 'effect', profile,
      'InvalidInstalledEffectProfile');
  return {entry, module: await loadInstalledEffectModule(entry)};
}

// Host-owned positive names are separate from the provider's closed profile.
// Preserve exact semantic strings; configuration canonicalization may use NFC.
function splitUpdateTargetProfile(profile: unknown) {
  if (profile === null || typeof profile !== 'object' || Array.isArray(profile)) {
    refuse('InvalidInstalledEffectProfile');
  }
  const {queryUpdateTargets = [], ...providerProfile} = profile as Readonly<Record<string, unknown>>;
  if (!Array.isArray(queryUpdateTargets) || queryUpdateTargets.length > 1024 ||
      Buffer.byteLength(JSON.stringify(queryUpdateTargets)) > 1024 * 1024) {
    refuse('InvalidInstalledUpdateTargets');
  }
  const aliases = Object.freeze((queryUpdateTargets as NonNullable<EffectOwner['queryUpdateTargets']>).map(entry => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join('\0') !== 'name\0targetRef' ||
        typeof entry.name !== 'string' || entry.name.length === 0 ||
        entry.name.length > 1024 || !entry.name.isWellFormed() ||
        typeof entry.targetRef !== 'string' || entry.targetRef.length === 0 ||
        entry.targetRef.length > 4096 || !entry.targetRef.isWellFormed()) {
      refuse('InvalidInstalledUpdateTargets');
    }
    return Object.freeze({...entry});
  }));
  return {providerProfile, queryUpdateTargets: aliases};
}

// The Site binds its capability attestation and credential grants to the
// exact standard runtime this Host executes.

async function providerRuntime(entry: Installation, runtimeUrl: unknown, readRuntimeIdentity = installedRuntimeBundleCid) {
  const bundle = providerBundleUrl(entry);
  return {...(bundle === undefined ? {} : {providerMoon:
    await import(bundle.href)}),
  runtimeBundleCid: await readRuntimeIdentity(runtimeUrl)};
}

// Only installation references and published, immutable declarations enter
// this identity. The referenced Site profile contains credential references,
// never an access token; no profile contents are returned to the caller.
export async function installedEffectIdentity(path: unknown, {connectorTable, configurationReader}: IdentityOptions = {}) {
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => refuse('InstalledConfigurationReaderUnavailable'));
  const read = (path: unknown, options?: ReadLimits) => readProfileJson(path, options, readers.readJson);
  const {profile, providerProfile, queryUpdateTargets, construction} = await readConstructedProfile(path, readers, configurationReader);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  if (construction === undefined) module.check(providerProfile);
  else construction.construct(() => module.check(providerProfile));
  const parts = await module.identityParts(providerProfile, read, entry, {configurationReader});
  if (!Array.isArray(parts) || parts.length === 0) {
    refuse('InvalidInstalledEffectProfile');
  }
  const hash = createHash('sha256');
  for (const part of parts) {
    const canonical = canonicalJson(part);
    hash.update(String(Buffer.byteLength(canonical)));
    hash.update('\0');
    hash.update(canonical);
  }
  if (queryUpdateTargets.length !== 0) {
    // The Host pins the original registration, not an authority-filtered view.
    // Omission and an empty list retain the historical Effect identity.
    const exact = JSON.stringify(['actql-installed-query-update-targets/0.1',
      queryUpdateTargets.map(entry => [entry.name, entry.targetRef])]);
    hash.update(String(Buffer.byteLength(exact)));
    hash.update('\0');
    hash.update(exact);
  }
  return `sha256:${hash.digest('hex')}`;
}

// The explicit publication step of an installed Effect: one generation of its
// declaration, execution Mappings and Check Environment. A Host start never
// runs it; it uses the same state root and principal the Host will.
export async function publishInstalledEffectProfile(path: unknown, {root, principalId,
  moon, runtimeUrl, baseEnvironmentWire, resolveSecret, signal, connectorTable}: PublishOptions) {
  const profile = await readProfile(path);
  const {providerProfile} = splitUpdateTargetProfile(profile);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  if (module.publish === undefined) {
    refuse('InstalledEffectPublicationUnsupported');
  }
  return module.publish(module.check(providerProfile), {root, principalId, moon,
    baseEnvironmentWire, resolveSecret, signal, installation: entry,
    ...await providerRuntime(entry, runtimeUrl)});
}

// Load the Host's installed Effect from `path`, or none. An unknown version
// or an invalid profile is refused before any Site or provider I/O; the
// published generation is restored without provider I/O. Its Effect Ledger
// lives under the Host's state root.
async function loadEffect(path: unknown, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}: LoadOptions,
  own: (value: LoadedEffect | undefined) => void) {
  // The SAME initial material owns profile/runtime input and stays pending
  // through the awaited installer. Plural composition uses this same entry.
  return withInstalledSourceLoading(installationServices, async () => {
    const configurationReader = installationServices === undefined ? undefined
      : installedSourceConfigurationReader(installationServices);
    const readers = captureConfigurationReaders(configurationReader, undefined,
      () => refuse('InstalledConfigurationReaderUnavailable'));
    const {profile, providerProfile, queryUpdateTargets, construction} = await readConstructedProfile(path, readers, configurationReader);
    const {entry, module} = await selectInstallation(profile, connectorTable);
    const checked = construction === undefined ? module.check(providerProfile)
      : construction.construct(() => module.check(providerProfile));
    const readRuntimeIdentity = installationServices === undefined ? undefined
      : reserveInstalledSourceRuntimeIdentity(installationServices);
    const runtime = await providerRuntime(entry, runtimeUrl, readRuntimeIdentity);
    retainInstalledHostServiceInstallation(installationServices, entry, runtime.runtimeBundleCid);
    const sourceInitialization = installationServices === undefined ? undefined
      : beginInstalledSourceInitialization(installationServices, entry, (checked as {connectorId?: unknown}).connectorId, baseEnvironmentWire, 'effect');
    let installed: LoadedEffect | undefined;
    try {
      installed = await module.load(checked, {root,
        principalId, moon, baseEnvironmentWire, resolveSecret, installation: entry,
        ledgerRoot: join(root, 'state', 'effects', 'ledger'),
        ...(installationServices === undefined ? {} : {installationServices}),
        ...(sourceInitialization === undefined ? {} : {sourceInitialization,
          construction: bindInstalledSourceConstruction(installationServices!, sourceInitialization, checked, construction)}),
        ...(configurationReader === undefined ? {} : {configurationReader}), ...runtime}) as LoadedEffect;
      own(installed);
      verifyInstalledConnectorRegistration(entry, installed);
      if (typeof installed?.prepareCaptured !== 'function' ||
          typeof installed.prepareRecovered !== 'function' ||
          typeof installed.environmentWire !== 'string' ||
          typeof installed.close !== 'function') {
        refuse('InvalidInstalledEffectInstallation');
      }
      const adapter = retainInstalledRowEffectAdapter(installed, Object.freeze({environmentWire: installed.environmentWire,
        connectorBindings: installed.connectorBindings,
        effectSelectors: installed.effectSelectors,
        queryUpdateTargets: installedUpdateTargets(installed, queryUpdateTargets),
        queryTableBindings: installed.queryTableBindings,
        queryTableWriteAccesses: installed.queryTableWriteAccesses,
        mappings: installed.mappings,
        targetReadInventory: installed.targetReadInventory,
        targetReadAuthorization: installed.targetReadAuthorization,
        prepareManagedPlan: installed.prepareManagedPlan,
        prepareCaptured: installed.prepareCaptured,
        prepareRecovered: installed.prepareRecovered,
        close: () => installed!.close()})) as LoadedEffect;
      finishInstalledSourceInitialization(sourceInitialization, installed);
      return adapter;
    } catch (cause) {
      const failure = await retainBoundInstalledSourceFailure(sourceInitialization!, cause, installed);
      finishInstalledSourceInitialization(sourceInitialization, installed, failure, true);
      own(undefined);
      throw failure;
    }
  });
}

export async function loadInstalledEffect(path: unknown, options: LoadOptions): Promise<LoadedEffect | undefined> {
  if (path === undefined) return undefined;
  let installed: LoadedEffect | undefined;
  try {
    return await loadEffect(path, options, value => { installed = value; });
  } catch (cause) {
    if (installed === undefined) throw cause;
    throw await retainInstalledHostInitializationFailure(cause,
      {installedEffect: installed});
  }
}

export function installedEffectPaths({effectProfilePath, effectProfilePaths}: EffectPaths = {},
  fallback = process.env.ACTQL_LOCAL_EFFECT_PROFILE) {
  if (effectProfilePaths !== undefined) {
    if (effectProfilePath !== undefined || fallback !== undefined ||
        !validPluralEffectPaths(effectProfilePaths)) {
      refuse('InvalidInstalledEffectProfiles');
    }
    return Object.freeze([...effectProfilePaths]);
  }
  const path = effectProfilePath ?? fallback;
  return path === undefined ? Object.freeze([]) : Object.freeze([path]);
}

export async function loadInstalledEffects(paths: unknown, options: LoadOptions): Promise<LoadedEffect | LoadedEffectInventory | undefined> {
  if (!Array.isArray(paths)) refuse('InvalidInstalledEffectProfiles');
  if (paths.length < 2) return loadInstalledEffect(paths[0], options);
  if (!validPluralEffectPaths(paths)) refuse('InvalidInstalledEffectProfiles');
  return composeInstalledEffects(paths, options as LoadOptions & ComposeOptions, loadEffect);
}
