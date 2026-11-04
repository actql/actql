import {composeInstalledSourceEnvironment} from './installed-funded-environment.mjs';
import {sourceAliasIdentityRow} from './source-alias-request.mjs';
import {captureSourceAliasConstruction, sourceAliasProfileConstructionGeometry,
  sourceAliasIdentityConstructionGeometry, sourceAliasCollectionConstructionGeometry} from './source-alias-construction.mjs';
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
import {verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure, retainInstalledHostRuntimeFailure}
  from './installed-host-cleanup.mjs';
import {MAX_INSTALLED_SOURCE_AUTHORITIES} from './installed-source-limits.mjs';
import {readSourceProfileJson, installedRuntimeBundleCid, captureConfigurationReaders,
  installedConfigurationByteLimit} from './source-profile-json.mjs';
import {retainInstalledHostServiceInstallation, installedSourceConfigurationReader, installedSourceEnvironmentConstructionReader,
  beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization, finishInstalledSourceInitialization,
  bindInstalledSourceConstruction, retainBoundInstalledSourceFailure,
  reserveInstalledSourceRuntimeIdentity,
  withInstalledSourceLoading} from './installed-host-services.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {INSTALLED_DUCKDB_SOURCE_VERSION, installDuckDBSourceProfile, checkInstalledDuckDBSourceProfile, createInstalledDuckDBSource} from
  './installed-duckdb-source.mjs';

import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedConnectorForTable, installedConnectorTable,
  loadInstalledConnectorModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

// DuckDB is the Host's built-in source binding: it needs no provider bundle
// or credential Site. It enters the same table as every declared connector;
// moving it behind its own manifest is a separate change.
const duckdbSourceModule = Object.freeze({
  check: checkInstalledDuckDBSourceProfile,
  // Logical profile canonicalization must not alias distinct provider names.
  identityParts: profile => [profile, duckDBPhysicalTarget(profile)],
  load: async (profile, {root, principalId, moon, construction, sourceInitialization}) => {
    if (construction !== undefined) return construction.createDuckDBSource();
    if (sourceInitialization !== undefined) throw new TypeError('InstalledSourceConstructorUnavailable');
    return createInstalledDuckDBSource(await installDuckDBSourceProfile(profile, {root, principalId}), moon, {root, principalId});
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
const sourcePublications = new WeakMap();

// Provenance of this explicit Host call, not a grant or a durable preparation.
// Only publishInstalledSourceProfile issues a member. Cold DATA and another
// publication with equal configuration cannot recreate the original request.
const publicationRequests = new WeakMap();
const publicationBindings = Object.freeze(['root', 'principalId', 'moon',
  'installation', 'profile', 'resolveSecret', 'runtimeBundleCid', 'providerMoon']);

const publicationFailure = code => {
  throw Object.assign(new TypeError(code), {code});
};

function originalPublicationRequest(request) {
  const original = request !== null && typeof request === 'object'
    ? publicationRequests.get(request) : undefined;
  if (original === undefined) publicationFailure('ForeignInstalledSourcePublication');
  return original;
}

// Read-only lookup, including while original cleanup is pending. This UUID is
// the Host's original request coordinate, never an issuer or a permission.
export function installedSourcePublicationRequestId(request) {
  return originalPublicationRequest(request).requestId;
}

// A synchronous fence for the exact trusted installer pair. In particular it
// can follow an awaited Account/Site/egress/resource check immediately before
// the same journal claim/send, with no new await or caller boolean admission.
// Those checks and physical cleanup are independent duties of that Site.
export function assertInstalledSourcePublicationRequest(request, originals) {
  const original = originalPublicationRequest(request);
  if (original.phase !== 'active') publicationFailure('InstalledSourcePublicationClosed');
  original.signal?.throwIfAborted();
  if (originals === null || typeof originals !== 'object') {
    publicationFailure('ForeignInstalledSourcePublicationBinding');
  }
  const descriptors = Object.getOwnPropertyDescriptors(originals);
  for (const name of publicationBindings) {
    const descriptor = descriptors[name];
    // Optional runtime fields may be absent only when the original was too.
    if (descriptor === undefined && original.bindings[name] === undefined) continue;
    if (descriptor === undefined || !Object.hasOwn(descriptor, 'value') ||
        descriptor.value !== original.bindings[name]) {
      publicationFailure('ForeignInstalledSourcePublicationBinding');
    }
  }
  original.used = true;
}

// Observe only this request's original Host profile. This is not Account,
// issuer, Site generation, credential, egress or funding authorization. The
// physical adapter must still check all of those, and then use the synchronous
// original-pair fence above. No replacement profile is returned to the caller.
export async function observeInstalledSourcePublicationCurrent(request, originals) {
  assertInstalledSourcePublicationRequest(request, originals);
  const original = originalPublicationRequest(request);
  try {
    const observed = await readProfile(original.path);
    assertInstalledSourcePublicationRequest(request, originals);
    if (JSON.stringify(observed) !== original.profileWire) {
      publicationFailure('InstalledSourcePublicationChanged');
    }
  } catch (cause) {
    // Observed replacement/failure cannot reopen this request if a caller later
    // restores equal bytes. Keep the original aliases for its cleanup only.
    original.phase = 'retiring';
    throw cause;
  }
}

export function installedSourcePublicationFacts(source) {
  return source !== null && typeof source === 'object'
    ? sourcePublications.get(source) : undefined;
}

// Select the installed connector of a Host profile and load its
// installation module. An explicit table is complete, including built-ins;
// an unknown version is refused before any installation I/O.
async function selectInstallation(profile, connectorTable) {
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
async function providerRuntime(entry, runtimeUrl, readRuntimeIdentity = installedRuntimeBundleCid) {
  const bundle = providerBundleUrl(entry);
  if (bundle === undefined) return runtimeUrl === undefined ? {}
    : {runtimeBundleCid: await readRuntimeIdentity(runtimeUrl)};
  return {providerMoon: await import(bundle.href),
    runtimeBundleCid: await readRuntimeIdentity(runtimeUrl)};
}

// A connected embedded Host keeps one installed source for its lifetime.
// Compare its full published generation and Site binding on later connects,
// without reading a credential value or probing the provider.
export async function installedSourceIdentity(path, {connectorTable, configurationReader, moon} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  const construct = captureSourceAliasConstruction(configurationReader, moon);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => {throw new TypeError('InstalledConfigurationReaderUnavailable');});
  return identityFromAliasProfile(await readAliasProfile(path, readers, construct, configurationReader),
    {connectorTable, configurationReader}, readers.readJson, construct);
}

async function identityFromAliasProfile({profile, providerProfile, queryAliases},
  {connectorTable, configurationReader}, read, construct, optional = false) {
  // Omission and an explicitly empty alias publication have the same meaning.
  if (queryAliases.length === 0) delete profile.queryAliases;
  let parts;
  try {
    const {entry, module} = await selectInstallation(profile, connectorTable);
    parts = await module.identityParts(profile, providerProfile, read, entry, {configurationReader});
  } catch (cause) {
    if (!optional || cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) throw cause;
    return undefined;
  }
  // A funding refusal is not optional missing metadata. Keep the unchanged
  // cause outside the namespace observation's recoverable metadata catch.
  return constructAliasIdentity(construct, parts, queryAliases);
}

// The retained original wire selects the complete parse/snapshot demand before
// either constructor runs. No mutable parsed request crosses a quote callback.
async function readAliasProfile(path, readers, construct, configurationReader) {
  const snapshot = profile => {
    const split = splitSourceAliasProfile(profile);
    // Identity providers borrow the same immutable request DATA. The parsed
    // caller tree is never left as an unfrozen alias behind a quote callback.
    if (Object.hasOwn(profile, 'queryAliases')) profile.queryAliases = split.queryAliases;
    return Object.freeze({profile, ...split});
  };
  // Standalone diagnostics retain their historical read/parse/close ordering.
  // They have no installed material to fund and cannot impersonate its reader.
  if (configurationReader === undefined) return snapshot(await readers.readJson(path));
  const wire = await readers.readText(path, {maxBytes: installedConfigurationByteLimit});
  return construct(sourceAliasProfileConstructionGeometry(wire), () => snapshot(JSON.parse(wire)));
}

function constructAliasIdentity(construct, parts, aliases) {
  if (aliases.length === 0) return sourceIdentityFromParts(parts, aliases);
  return construct(sourceAliasIdentityConstructionGeometry(aliases), () => Object.freeze({
    identity: sourceIdentityFromParts(parts, aliases),
  })).identity;
}

function sourceIdentityFromParts(parts, queryAliases) {
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


async function readProfile(path, read = readSourceProfileJson) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  try { return await read(path); }
  catch (cause) {
    const failure = Object.assign(new TypeError('InvalidInstalledSourceProfile',
      {cause}), {code: 'InvalidInstalledSourceProfile'});
    if (cause?.cleanupHandle !== undefined) {
      Object.assign(failure, {cleanupHandle: cause.cleanupHandle,
        cleanupPending: cause.cleanupPending});
    }
    throw failure;
  }
}

// The explicit publication step of an installed source whose connector has
// one (a Salesforce source publishes its targeted declaration). A Host start
// never runs it; it uses the same state root and principal the Host will.
export async function publishInstalledSourceProfile(path, {root, principalId,
  moon, runtimeUrl, resolveSecret, signal, connectorTable}) {
  const request = Object.freeze({});
  const original = {path, requestId: randomUUID(), signal, phase: 'preparing',
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
export async function loadInstalledSource(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}) {
  if (path === undefined) return undefined;
  return withInstalledSourceLoading(installationServices, () => loadInstalledSourceMember(path,
    {root, principalId, moon, runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}));
}

async function loadInstalledSourceMember(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable, installationServices}) {
  // The original initial reservation precedes shared profile parsing and
  // identity metadata reads, not merely the selected provider's load call.
  const configurationReader = installationServices === undefined ? undefined
    : installedSourceConfigurationReader(installationServices);
  const construct = captureSourceAliasConstruction(configurationReader, moon);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => {throw new TypeError('InstalledConfigurationReaderUnavailable');});
  const read = readers.readJson;
  const {profile, providerProfile, queryAliases} = await readProfile(path,
    selected => readAliasProfile(selected, readers, construct, configurationReader));
  const {entry, module} = await selectInstallation(profile, connectorTable);
  const checked = module.check(providerProfile);
  let identityParts, publicationRevision;
  try {
    // Metadata reads only: no provider request or credential resolution.
    const identityProfile = {...profile};
    if (queryAliases.length === 0) delete identityProfile.queryAliases;
    identityParts = await module.identityParts(
      identityProfile, providerProfile, read, entry, {configurationReader});
  } catch (cause) {
    if (cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) throw cause;
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
  let adapter;
  try {
    adapter = await module.load(checked, {root, principalId, moon,
      baseEnvironmentWire, resolveSecret, installation: entry, installationServices,
      sourceInitialization, configurationReader,
      construction: sourceInitialization === undefined ? undefined
        : bindInstalledSourceConstruction(installationServices, sourceInitialization, checked), ...runtime});
    verifyInstalledConnectorRegistration(entry, adapter);
    const source = Object.freeze({...adapter, queryAliases});
    if (publicationRevision !== undefined) {
      let current;
      if (configurationReader === undefined) {
        // Preserve the standalone diagnostic's historical optional reread.
        try { current = await installedSourceIdentity(path, {connectorTable, moon}); }
        catch (cause) {
          if (cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) throw cause;
        }
      } else {
        // Managed profile construction is funded before optional identity
        // metadata observation. Its quote/parse/snapshot/hash refusal must
        // propagate unchanged, including an undefined or null thrown cause.
        const currentProfile = await readAliasProfile(path, readers, construct, configurationReader);
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
    const failure = await retainBoundInstalledSourceFailure(sourceInitialization, cause, adapter);
    finishInstalledSourceInitialization(sourceInitialization, adapter, failure, true);
    throw failure;
  }
}

// Installation inventory is bounded and inert. Only a checked acquisition
// occurrence selects a member later; installing a binding never reads it.
export function installedSourceReadAccesses(source) {
  const accesses = source.sourceReadAccesses ?? [source.sourceAccess];
  if (!Array.isArray(accesses) || accesses.length === 0 ||
      accesses.length > 64) {
    throw new TypeError('InvalidInstalledSourceReadAccesses');
  }
  if (source.sourceReadAccesses !== undefined) {
    const refs = new Set();
    for (const access of accesses) {
      if (typeof access?.sourceRef !== 'string' ||
          typeof access.connection !== 'string' ||
          access.connection !== source.sourceAccess?.connection ||
          typeof access.resource !== 'string' ||
          access.authorization !== source.sourceAccess?.authorization ||
          typeof source.admitsSource !== 'function' ||
          !source.admitsSource(access.sourceRef) ||
          refs.has(access.sourceRef)) {
        throw new TypeError('InvalidInstalledSourceReadAccesses');
      }
      refs.add(access.sourceRef);
    }
  }
  return accesses;
}

export function installedSourceReadBindings(source) {
  if (typeof source.sourceAccess?.authorization?.authorize !== 'function' ||
      typeof source.ledgerCapacity !== 'function' ||
      typeof source.admitsSource !== 'function') {
    throw new TypeError('InstalledMultiSourceUnsupported');
  }
  const refs = [];
  for (const access of installedSourceReadAccesses(source)) {
    if (typeof access?.sourceRef !== 'string' ||
        typeof access.connection !== 'string' ||
        typeof access.resource !== 'string' ||
        access.authorization !== source.sourceAccess.authorization ||
        !source.admitsSource(access.sourceRef)) {
      throw new TypeError('InstalledMultiSourceUnsupported');
    }
    refs.push(access.sourceRef);
  }
  if (new Set(refs).size !== refs.length) {
    throw new TypeError('InstalledSourceBindingAmbiguous');
  }
  return refs;
}

export function installedSourcePaths({sourceProfilePath, sourceProfilePaths} = {},
  fallback = process.env.ACTQL_LOCAL_SOURCE_PROFILE) {
  if (sourceProfilePaths !== undefined) {
    if (sourceProfilePath !== undefined || fallback !== undefined ||
        !validPluralSourcePaths(sourceProfilePaths)) {
      throw new TypeError('InvalidInstalledSourceProfiles');
    }
    return Object.freeze([...sourceProfilePaths]);
  }
  const path = sourceProfilePath ?? fallback;
  return path === undefined ? Object.freeze([]) : Object.freeze([path]);
}

function validPluralSourcePaths(paths) {
  return Array.isArray(paths) && paths.length >= 2 &&
    paths.length <= MAX_INSTALLED_SOURCE_AUTHORITIES &&
    Array.from(paths).every(path => typeof path === 'string' && isAbsolute(path)) &&
    new Set(paths).size === paths.length;
}

export async function loadInstalledSources(paths, options) {
  // Capture the options once: later callbacks cannot switch the admitted
  // service/runtime or revive a missing-services diagnostic path.
  options = Object.freeze({...options});
  installedSourceEnvironmentConstructionReader(options?.installationServices, options?.moon);
  if (paths.length < 2) return loadInstalledSource(paths[0], options);
  if (!validPluralSourcePaths(paths)) {
    throw new TypeError('InvalidInstalledSourceProfiles');
  }
  const configurationReader = options.installationServices === undefined ? undefined
    : installedSourceConfigurationReader(options.installationServices);
  const construct = captureSourceAliasConstruction(configurationReader, options.moon);
  const sources = [];
  const closed = new Set();
  const close = async () => {
    const failures = [];
    for (const source of sources) {
      if (closed.has(source)) continue;
      try { await source.close(); closed.add(source); }
      catch (error) { failures.push(error); }
    }
    if (failures.length) throw new AggregateError(failures, 'InstalledSourceCleanupPending');
  };
  try {
    const refs = new Set();
    for (const path of paths) {
      const source = await loadInstalledSource(path, options);
      sources.push(source);
      // Each independently installed source must have an exact checked
      // occurrence and an owned capacity before any read may start.
      for (const ref of installedSourceReadBindings(source)) {
        if (refs.has(ref)) throw new TypeError('InstalledSourceBindingAmbiguous');
        refs.add(ref);
      }
      if (refs.size > MAX_INSTALLED_SOURCE_AUTHORITIES) {
        throw new TypeError('InvalidInstalledSourceReadAccesses');
      }
    }
    let environmentWire, environmentOriginal;
    const bindings = new Map();
    for (const source of sources) {
      const combinedOriginal = composeInstalledSourceEnvironment(options.installationServices, options.moon,
          options.baseEnvironmentWire, environmentOriginal, source.environmentOriginal ?? source.environmentWire);
      const combined = combinedOriginal.wire;
      verifyInstalledConnectorBindings(environmentWire === undefined ? undefined
        : {environmentWire, connectorBindings: [...bindings.values()]}, source);
      environmentWire = combined;
      environmentOriginal = combinedOriginal;
      // Validate a member's own duplicates before coalescing matching physical
      // bindings across members. Preserve the original declaration order.
      for (const binding of source.connectorBindings ?? []) {
        if (!bindings.has(binding.connectorId)) {
          bindings.set(binding.connectorId, binding);
        }
      }
    }
    Object.freeze(sources);
    const {queryAliases} = construct(sourceAliasCollectionConstructionGeometry(sources), () => {
      // Every row/request is the original immutable profile snapshot. This
      // stage owns only the aggregate list and duplicate-name collections.
      const queryAliases = Object.freeze(sources.flatMap(source => source.queryAliases));
      if (new Set(queryAliases.map(alias => alias.name)).size !== queryAliases.length) {
        throw new TypeError('InvalidPublicSourcePublication');
      }
      return Object.freeze({queryAliases});
    });
    return Object.freeze({
      realizationKey: sources.every(source =>
        source.realizationKey === 'duckdb-acquired')
        ? 'duckdb-acquired' : 'installed-multi-acquired', environmentWire, environmentOriginal,
      sources: Object.freeze(sources),
      connectorBindings: Object.freeze([...bindings.values()]),
      queryAliases,
      admitsSource: ref => sources.some(source => source.admitsSource(ref)),
      close,
    });
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: {close}});
  }
}

export function installedSourceFor(profile, sourceRef) {
  const matches = (profile?.sources ?? (profile === undefined ? [] : [profile]))
    .filter(source => source.admitsSource(sourceRef));
  if (matches.length !== 1) throw new Error('InstalledSourceProgramMismatch');
  return matches[0];
}
