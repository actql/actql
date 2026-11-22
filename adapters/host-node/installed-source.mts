import {composeInstalledSourceEnvironment} from './installed-funded-environment.mjs';
import {sourceAliasIdentityRow} from './source-alias-request.mjs';
import {captureSourceAliasConstruction,
  sourceAliasIdentityConstructionGeometry} from './source-alias-construction.mjs';
// The standard Host's installed source binding, selected by the Host
// profile's version from the installed connector table. Each installation
// adapter keeps its own physical I/O, grants and cleanup; the Host's Run,
// Checkpoint and dispatch owners stay the same for every adapter, and the
// Host never branches on a provider name: a connector enters the table by
// its own `host-bundle.json` manifest (`installed-connectors.mjs`).
//
// An adapter provides:
// - `realizationKey`, `environmentWire` (the Check Environment of this
//   installation), `readAuthorization` ({accountConfiguration, context}, for
//   the Host's pre-acquisition Checkpoint) and `sourceAccess` (the base
//   access whose `authorization` a Checkpoint may wrap);
// - optionally `sourceReadAccesses`: one declared sourceRef and read tuple
//   per view for Check disclosure and plural Checkpoint authority. Its
//   acquisition still uses the installation-scoped `sourceAccess`;
// - `connectorRegistration`/`connectorRevision` when its manifest declares
//   them: the installed implementation's own identification, which must
//   equal the declaration;
// - `admitsSource(sourceRef)`: whether a checked source is this installation's;
// - `prepare({preparedProgram, preparedEffect, registry, values, fragment, ordered,
//   sourceAccess})`: the checked source, read tuple and physical binding an
//   approval covers, without provider I/O. Exactly one checked owner is given;
//   an Effect owner must not be rechecked as an Effect-free Program;
// - optionally `retainedCapture(prepared)`: the checked requirement and opaque
//   installed capacity for restoring that exact capture on the existing Run
//   ledger. This is custody preparation, not a read grant or provider replay;
// - `open({... , sourceAccess, signal, preparedSource})`: the acquisition. It
//   returns the captured source ({checkedSource, identity, logicalInput,
//   setup, capture, issueSourceEvidence, close}), which the dispatch owner
//   closes; on failure the adapter releases what it opened itself;
// - optionally `discovery` ({resources, inspectResource, peekResource}) and
//   `close()`.
import {createHash, randomUUID} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {retainInstalledHostInitializationFailure, retainInstalledHostRuntimeFailure}
  from './installed-host-cleanup.mjs';
import {readSourceProfileJson, installedRuntimeBundleCid, captureConfigurationReaders,
  installedConfigurationByteLimit} from './source-profile-json.mjs';
// @ts-expect-error TS7016: remove after installed-host-services has an authored TypeScript entry.
import {retainInstalledHostServiceInstallation, installedSourceConfigurationReader, installedSourceEnvironmentConstructionReader, beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization, finishInstalledSourceInitialization, bindInstalledSourceConstruction, retainBoundInstalledSourceFailure, reserveInstalledSourceRuntimeIdentity, withInstalledSourceLoading} from './installed-host-services.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {createInstalledSourcePublicationRequests} from './installed-source-publication.mjs';
import {createInstalledSourceInventoryLoader} from './installed-source-inventory.mjs';
// @ts-expect-error TS7016: remove after installed-duckdb-source has an authored TypeScript entry.
import {INSTALLED_DUCKDB_SOURCE_VERSION, installDuckDBSourceProfile, checkInstalledDuckDBSourceProfile, createInstalledDuckDBSource} from './installed-duckdb-source.mjs';

import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedConnectorForTable, installedConnectorTable,
  loadInstalledConnectorModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

import type {ConfigurationReader} from './source-alias-construction.mjs';
import type {InventoryMember, LoadOptions} from './installed-source-inventory.mjs';
import type {OriginalPublication} from './installed-source-publication.mjs';

type Installation = ReturnType<typeof installedConnectorFor>;
type Constructor = ReturnType<typeof captureSourceAliasConstruction>;
type AliasProfile = ReturnType<typeof splitSourceAliasProfile>;
type QueryAliases = AliasProfile['queryAliases'];
type SnapshottedProfile = {
  queryAliases?: QueryAliases;
} & Record<string, unknown>;
type ProfileConstruction = Readonly<{
  value: ProfileSnapshot;
  construct: <Value>(project: () => Value) => Value;
}>;
type ProfileSnapshot = Readonly<{profile: SnapshottedProfile}> & AliasProfile;
type AliasProfileRead = ProfileSnapshot & Readonly<{construction?: ProfileConstruction}>;
type CapturedReaders = ReturnType<typeof captureConfigurationReaders>;
type IdentityOptions = Readonly<{connectorTable?: unknown; configurationReader?: ConfigurationReader; moon?: unknown}>;
type CleanupFault = Readonly<{cleanupHandle?: unknown; cleanupPending?: unknown}> | null | undefined;
type PublicationFacts = Readonly<{path: string; revision: string; aliases: QueryAliases}>;
type PublishOptions = Pick<LoadOptions, 'root' | 'principalId' | 'runtimeUrl' | 'resolveSecret' | 'connectorTable'> &
  Readonly<{moon: unknown; signal?: AbortSignal}>;
type SourceCheck = Readonly<{sourceRef?: unknown; checkEnvironmentWire?: unknown; connectorId?: unknown}>;
type DuckDBLoadOptions = Pick<LoadOptions, 'root' | 'principalId' | 'moon'> & Readonly<{
  construction?: {createDuckDBSource(): unknown};
  sourceInitialization?: unknown;
  installation: Installation;
}>;

// DuckDB is the Host's built-in source binding: it needs no provider bundle
// or credential Site. It enters the same table as every declared connector;
// moving it behind its own manifest is a separate change.
const duckdbSourceModule = Object.freeze({
  check: checkInstalledDuckDBSourceProfile,
  // Logical profile canonicalization must not alias distinct provider names.
  identityParts: (profile: Parameters<typeof duckDBPhysicalTarget>[0]) => [profile, duckDBPhysicalTarget(profile)],
  load: async (profile: unknown, {root, principalId, moon, construction, sourceInitialization, installation}: DuckDBLoadOptions) => {
    if (construction !== undefined) return construction.createDuckDBSource();
    if (sourceInitialization !== undefined) throw new TypeError('InstalledSourceConstructorUnavailable');
    return createInstalledDuckDBSource(await installDuckDBSourceProfile(profile, {root, principalId}), moon,
      {root, principalId, installation});
  },
});
const duckdbInstallation = Object.freeze({
  name: 'builtin_source',
  registration: 'builtin_source',
  revision: 'builtin_source/0.1',
  source: Object.freeze({
    profileVersion: INSTALLED_DUCKDB_SOURCE_VERSION,
    load: async () => duckdbSourceModule,
  }),
});
const installations = installedConnectorTable([duckdbInstallation,
  ...installedConnectors]);

// Original adapters whose metadata generation was stable through installation.
// This is process-local custody, not a second catalog or a durable certificate.
const sourcePublications = new WeakMap<object, PublicationFacts>();

const {publicationRequests, installedSourcePublicationRequestId, assertInstalledSourcePublicationRequest,
  observeInstalledSourcePublicationCurrent} = createInstalledSourcePublicationRequests(readProfile);
export {installedSourcePublicationRequestId, assertInstalledSourcePublicationRequest,
  observeInstalledSourcePublicationCurrent};

export function installedSourcePublicationFacts(source: unknown) {
  return source !== null && typeof source === 'object'
    ? sourcePublications.get(source) : undefined;
}

// Select the installed connector of a Host profile and load its
// installation module. An explicit table is complete, including built-ins;
// an unknown version is refused before any installation I/O.
async function selectInstallation(profile: unknown, connectorTable: unknown) {
  const entry = connectorTable === undefined
    ? installedConnectorFor(installations, profile)
    : installedConnectorForTable(connectorTable, 'source', profile);
  return {entry, module: await loadInstalledConnectorModule(entry)};
}

// The Site binds its credential grants to the exact standard runtime this
// Host executes.

// Provider compilation and Site runtime binding are independent. A JS-only
// physical Source still binds credential grants to the actual Host runtime;
// it must not add a dummy provider bundle merely to receive that identity.
// A built-in binding without a Site or supplied runtime needs neither.
async function providerRuntime(entry: Installation, runtimeUrl: unknown, readRuntimeIdentity = installedRuntimeBundleCid) {
  const bundle = providerBundleUrl(entry);
  if (bundle === undefined) return runtimeUrl === undefined ? {}
    : {runtimeBundleCid: await readRuntimeIdentity(runtimeUrl)};
  return {providerMoon: await import(bundle.href),
    runtimeBundleCid: await readRuntimeIdentity(runtimeUrl)};
}

// A connected embedded Host keeps one installed source for its lifetime.
// Compare its full published generation and Site binding on later connects,
// without reading a credential value or probing the provider.
export async function installedSourceIdentity(path: unknown, {connectorTable, configurationReader, moon}: IdentityOptions = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  const construct = captureSourceAliasConstruction(configurationReader!, moon);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => {throw new TypeError('InstalledConfigurationReaderUnavailable');});
  return identityFromAliasProfile(await readAliasProfile(path, readers, configurationReader),
    {connectorTable, configurationReader}, readers.readJson, construct);
}

async function identityFromAliasProfile({profile, providerProfile, queryAliases}: ProfileSnapshot,
  {connectorTable, configurationReader}: IdentityOptions, read: unknown, construct: Constructor, optional = false) {
  // Omission and an explicitly empty alias publication have the same meaning.
  if (queryAliases.length === 0) delete profile.queryAliases;
  let parts: unknown;
  try {
    const {entry, module} = await selectInstallation(profile, connectorTable);
    parts = await module.identityParts(profile, providerProfile, read, entry, {configurationReader});
  } catch (cause) {
    if (!optional || (cause as CleanupFault)?.cleanupHandle !== undefined || (cause as CleanupFault)?.cleanupPending === true) throw cause;
    return undefined;
  }
  // A funding refusal is not optional missing metadata. Keep the unchanged
  // cause outside the namespace observation's recoverable metadata catch.
  return constructAliasIdentity(construct, parts, queryAliases);
}

// The retained original wire selects the complete parse/snapshot demand before
// either constructor runs. No mutable parsed request crosses a quote callback.
async function readAliasProfile(path: string, readers: CapturedReaders,
  configurationReader: ConfigurationReader | undefined): Promise<AliasProfileRead> {
  const snapshot = (profile: unknown) => {
    const split = splitSourceAliasProfile(profile);
    // Identity providers borrow the same immutable request DATA. The parsed
    // caller tree is never left as an unfrozen alias behind a quote callback.
    if (Object.hasOwn(profile as object, 'queryAliases')) (profile as SnapshottedProfile).queryAliases = split.queryAliases;
    return Object.freeze({profile: profile as SnapshottedProfile, ...split});
  };
  // Standalone diagnostics retain their historical read/parse/close ordering.
  // They have no installed material to fund and cannot impersonate its reader.
  if (configurationReader === undefined) return snapshot(await (readers.readJson as (path: string) => unknown)(path));
  const wire = await readers.readText(path, {maxBytes: installedConfigurationByteLimit}) as string;
  const construction = (readers as {prepareProfile?: (wire: string, snapshot: () => ProfileSnapshot) => ProfileConstruction})
    .prepareProfile!(wire, () => snapshot(JSON.parse(wire)));
  return Object.freeze({...construction.value, construction});
}

function constructAliasIdentity(construct: Constructor, parts: unknown, aliases: QueryAliases) {
  if (aliases.length === 0) return sourceIdentityFromParts(parts, aliases);
  return construct(sourceAliasIdentityConstructionGeometry(aliases), () => Object.freeze({
    identity: sourceIdentityFromParts(parts, aliases),
  })).identity;
}

function sourceIdentityFromParts(parts: unknown, queryAliases: QueryAliases) {
  if (!Array.isArray(parts) || parts.length === 0) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const hash = createHash('sha256');
  for (const part of parts) {
    const canonical = canonicalJson(part);
    hash.update(String(Buffer.byteLength(canonical)));
    hash.update('\0');
    hash.update(canonical);
  }
  if (queryAliases.length !== 0) {
    // Query alias names and Source references are semantic values. Keep their
    // exact spelling outside the configuration canonicalizer's NFC domain.
    // Fixed member order avoids treating JSON object key order as a change.
    const exact = JSON.stringify(['actql-installed-query-alias-generation/0.1',
      queryAliases.map(sourceAliasIdentityRow)]);
    hash.update(String(Buffer.byteLength(exact)));
    hash.update('\0');
    hash.update(exact);
  }
  return `sha256:${hash.digest('hex')}`;
}


async function readProfile<Profile = unknown>(path: unknown,
  read: (path: string) => Promise<Profile> = readSourceProfileJson as (path: string) => Promise<Profile>) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  try { return await read(path); }
  catch (cause) {
    const failure = Object.assign(new TypeError('InvalidInstalledSourceProfile',
      {cause}), {code: 'InvalidInstalledSourceProfile'});
    if ((cause as CleanupFault)?.cleanupHandle !== undefined) {
      Object.assign(failure, {cleanupHandle: (cause as NonNullable<CleanupFault>).cleanupHandle,
        cleanupPending: (cause as NonNullable<CleanupFault>).cleanupPending});
    }
    throw failure;
  }
}

// The explicit publication step of an installed source whose connector has
// one (a Salesforce source publishes its targeted declaration). A Host start
// never runs it; it uses the same state root and principal the Host will.
export async function publishInstalledSourceProfile(path: unknown, {root, principalId,
  moon, runtimeUrl, resolveSecret, signal, connectorTable}: PublishOptions) {
  const request = Object.freeze({});
  const original: OriginalPublication = {path, requestId: randomUUID(), signal, phase: 'preparing',
    used: false, bindings: undefined, profileWire: undefined};
  publicationRequests.set(request, original);
  const retire = () => publicationRequests.delete(request);
  try {
    const profile = await readProfile(path);
    // Preserve the parsed original before a trusted checker receives its own
    // provider profile. This exact value observation has no new CID domain.
    original.profileWire = JSON.stringify(profile);
    const {entry, module} = await selectInstallation(profile, connectorTable);
    const publish = module.publish, check = module.check;
    if (publish === undefined) {
      throw Object.assign(new TypeError('InstalledSourcePublicationUnsupported'),
        {code: 'InstalledSourcePublicationUnsupported'});
    }
    const checked = Reflect.apply(check, module,
      [splitSourceAliasProfile(profile).providerProfile]);
    const runtime = await providerRuntime(entry, runtimeUrl);
    original.bindings = Object.freeze({root, principalId, moon,
      installation: entry, profile: checked, resolveSecret, ...runtime});
    original.phase = 'active';
    signal?.throwIfAborted();
    const result = await Reflect.apply(publish, module, [checked,
      {root, principalId, moon, resolveSecret, signal, installation: entry,
        ...runtime, publicationRequest: request}]);
    // Legacy installers that do not consume this seam retain their existing
    // behavior. Operational metadata consumers also fence their own save and
    // every protected call; this final check cannot replace those barriers.
    if (original.used) {
      await observeInstalledSourcePublicationCurrent(request, original.bindings);
    }
    original.phase = 'retiring';
    retire();
    return result;
  } catch (cause) {
    // Close new-operation admission immediately, but retain the same request
    // and all original references until the child's real cleanup status ACK.
    original.phase = 'retiring';
    throw retainInstalledHostRuntimeFailure(cause, retire);
  }
}

// Load the Host's installed source from `path`, or none. An unknown version
// or an invalid profile is refused before any provider or Site I/O. Only the
// selected connector's module and provider bundle are loaded.
export function loadInstalledSource(path: string, options: LoadOptions): Promise<InventoryMember>;
export function loadInstalledSource(path: string | undefined, options: LoadOptions): Promise<InventoryMember | undefined>;
export async function loadInstalledSource(path: string | undefined, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}: LoadOptions) {
  if (path === undefined) return undefined;
  return withInstalledSourceLoading(installationServices, () => loadInstalledSourceMember(path,
    {root, principalId, moon, runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}));
}

async function loadInstalledSourceMember(path: string, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}: LoadOptions): Promise<InventoryMember> {
  // The original initial reservation precedes shared profile parsing and
  // identity metadata reads, not merely the selected provider's load call.
  const configurationReader = installationServices === undefined ? undefined
    : installedSourceConfigurationReader(installationServices) as ConfigurationReader | undefined;
  const construct = captureSourceAliasConstruction(configurationReader!, moon);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => {throw new TypeError('InstalledConfigurationReaderUnavailable');});
  const read = readers.readJson;
  const {profile, providerProfile, queryAliases, construction} = await readProfile(path,
    selected => readAliasProfile(selected, readers, configurationReader));
  const {entry, module} = await selectInstallation(profile, connectorTable);
  const checked = (construction === undefined ? module.check(providerProfile)
    : construction.construct(() => module.check(providerProfile))) as SourceCheck;
  let identityParts: unknown, publicationRevision: string | undefined;
  try {
    // Metadata reads only: no provider request or credential resolution.
    const identityProfile = {...profile};
    if (queryAliases.length === 0) delete identityProfile.queryAliases;
    identityParts = await module.identityParts(
      identityProfile, providerProfile, read, entry, {configurationReader});
  } catch (cause) {
    if ((cause as CleanupFault)?.cleanupHandle !== undefined || (cause as CleanupFault)?.cleanupPending === true) throw cause;
    // Usable positive installation metadata alone cannot prove completeness.
  }
  if (identityParts !== undefined) {
    publicationRevision = constructAliasIdentity(construct, identityParts, queryAliases);
  }
  const readRuntimeIdentity = installationServices === undefined ? undefined
    : reserveInstalledSourceRuntimeIdentity(installationServices);
  const runtime = await providerRuntime(entry, runtimeUrl, readRuntimeIdentity);
  retainInstalledHostServiceInstallation(installationServices, entry, runtime.runtimeBundleCid);
  const sourceInitialization = installationServices === undefined ? undefined
    : module === duckdbSourceModule
      ? beginInstalledPublishedSourceInitialization(installationServices, entry,
        checked.sourceRef, checked.checkEnvironmentWire, baseEnvironmentWire)
      : beginInstalledSourceInitialization(installationServices, entry, checked.connectorId, baseEnvironmentWire);
  let adapter: InventoryMember | undefined;
  try {
    adapter = await module.load(checked, {root, principalId, moon,
      baseEnvironmentWire, resolveSecret, installation: entry, installationServices,
      sourceInitialization, configurationReader,
      construction: sourceInitialization === undefined ? undefined
        : bindInstalledSourceConstruction(installationServices, sourceInitialization, checked, construction), ...runtime}) as InventoryMember;
    verifyInstalledConnectorRegistration(entry, adapter);
    const source = Object.freeze({...adapter, queryAliases});
    if (publicationRevision !== undefined) {
      let current;
      if (configurationReader === undefined) {
        // Preserve the standalone diagnostic's historical optional reread.
        try { current = await installedSourceIdentity(path, {connectorTable, moon}); }
        catch (cause) {
          if ((cause as CleanupFault)?.cleanupHandle !== undefined || (cause as CleanupFault)?.cleanupPending === true) throw cause;
        }
      } else {
        // Managed profile construction is funded before optional identity
        // metadata observation. Its quote/parse/snapshot/hash refusal must
        // propagate unchanged, including an undefined or null thrown cause.
        const currentProfile = await readAliasProfile(path, readers, configurationReader);
        current = await identityFromAliasProfile(currentProfile,
          {connectorTable, configurationReader}, read, construct, true);
      }
      if (current === publicationRevision) {
        sourcePublications.set(source, Object.freeze({path,
          revision: publicationRevision, aliases: queryAliases}));
      }
    }
    finishInstalledSourceInitialization(sourceInitialization, adapter);
    return source;
  } catch (cause) {
    // The caller cannot own an adapter until validation returns it.
    // Without a bound context, this initializer retains the exact adapter
    // returned by its selected loader. Bound construction keeps its own
    // registered originals; a returned foreign value cannot replace them.
    const failure = sourceInitialization === undefined
      ? await retainInstalledHostInitializationFailure(cause, {sourceProfile: adapter})
      : await retainBoundInstalledSourceFailure(sourceInitialization, cause, adapter);
    finishInstalledSourceInitialization(sourceInitialization, adapter, failure, true);
    throw failure;
  }
}

export {installedSourceReadAccesses, installedSourceReadBindings, installedSourcePaths,
  prepareInstalledSourceCheckpointInventory, installedSourceFor} from './installed-source-inventory.mjs';
export const loadInstalledSources = createInstalledSourceInventoryLoader({
  loadInstalledSource, installedSourceConfigurationReader, installedSourceEnvironmentConstructionReader,
});
