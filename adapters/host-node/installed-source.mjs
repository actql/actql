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
// - `open({... , sourceAccess, signal, preparedSource})`: the acquisition. It
//   returns the captured source ({checkedSource, identity, logicalInput,
//   setup, capture, issueSourceEvidence, close}), which the dispatch owner
//   closes; on failure the adapter releases what it opened itself;
// - optionally `discovery` ({resources, inspectResource, peekResource}) and
//   `close()`.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {loadDuckDBNativeRuntime} from '../connectors/duckdb/node/native-runtime.mjs';
import {composeInstalledCheckEnvironment, verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {MAX_INSTALLED_SOURCE_AUTHORITIES} from './installed-source-limits.mjs';
import {readSourceProfileJson} from './source-profile-json.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {INSTALLED_DUCKDB_SOURCE_VERSION, installDuckDBSourceProfile} from
  './installed-duckdb-source.mjs';
import {openCapturedDuckDBSource, prepareCapturedDuckDBSource,
  capturedDuckDBConfiguration, capturedDuckDBPhysicalCapacity} from
  './captured-duckdb-source.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedConnectorForTable, installedConnectorTable,
  loadInstalledConnectorModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

// DuckDB is the Host's built-in source binding: it needs no provider bundle
// or credential Site. It enters the same table as every declared connector;
// moving it behind its own manifest is a separate change.
const duckdbInstallation = Object.freeze({
  name: 'builtin_source',
  source: Object.freeze({
    profileVersion: INSTALLED_DUCKDB_SOURCE_VERSION,
    load: async () => Object.freeze({
      check: profile => profile,
      // Logical profile canonicalization must not alias distinct provider
      // names: the exact physical target is its own identity part.
      identityParts: profile => [profile, duckDBPhysicalTarget(profile)],
      load: async (profile, {root, principalId, moon}) => duckdbAdapter(
        await installDuckDBSourceProfile(profile, {root, principalId}), moon,
        {root, principalId}),
    }),
  }),
});
const installations = installedConnectorTable([duckdbInstallation,
  ...installedConnectors]);

// Original adapters whose metadata generation was stable through installation.
// This is process-local custody, not a second catalog or a durable certificate.
const sourcePublications = new WeakMap();

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
const runtimeBundleCidOf = async runtimeUrl => `sha256:${createHash('sha256')
  .update(await readFile(runtimeUrl)).digest('hex')}`;

// The connector's compiled provider bundle and the runtime identity its
// Site binds to; a built-in binding without a provider bundle needs neither.
async function providerRuntime(entry, runtimeUrl) {
  const bundle = providerBundleUrl(entry);
  if (bundle === undefined) return {};
  return {providerMoon: await import(bundle.href),
    runtimeBundleCid: await runtimeBundleCidOf(runtimeUrl)};
}

// A connected embedded Host keeps one installed source for its lifetime.
// Compare its full published generation and Site binding on later connects,
// without reading a credential value or probing the provider.
export async function installedSourceIdentity(path, {connectorTable} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  const read = readSourceProfileJson;
  const profile = await read(path);
  const {providerProfile, queryAliases} = splitSourceAliasProfile(profile);
  // Omission and an explicitly empty alias publication have the same meaning.
  if (queryAliases.length === 0) delete profile.queryAliases;
  const {entry, module} = await selectInstallation(profile, connectorTable);
  const parts = await module.identityParts(profile, providerProfile, read, entry);
  return sourceIdentityFromParts(parts, queryAliases);
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
      queryAliases.map(entry => [entry.name, entry.sourceRef,
        entry.sourceViewContractCid, entry.schemaContractCid])]);
    hash.update(String(Buffer.byteLength(exact)));
    hash.update('\0');
    hash.update(exact);
  }
  return `sha256:${hash.digest('hex')}`;
}

async function duckdbAdapter(profile, moon, {root, principalId}) {
  await loadDuckDBNativeRuntime();
  const common = {moon, database: profile.database, schema: profile.schema,
    table: profile.table, acquisitionPlanning: profile.acquisitionPlanning};
  const catalogIds = JSON.parse(profile.environmentWire).connector_catalogs
    .map(catalog => catalog.connector_id);
  return Object.freeze({
    realizationKey: 'duckdb-acquired',
    supportsRetainedRelationOutput: true,
    environmentWire: profile.environmentWire,
    connectorBindings: Object.freeze(catalogIds.map(connectorId =>
      Object.freeze({connectorId, bindingCid: contentCid({
        version: 'actql-installed-duckdb-source-binding/0.1',
        root, principalId, physicalBinding: duckDBPhysicalTarget(profile),
        sourceRef: profile.sourceRef,
      })}))),
    readAuthorization: profile.readAuthorization,
    sourceAccess: profile.sourceAccess,
    admitsSource: sourceRef => sourceRef === profile.sourceRef,
    ledgerCapacity(prepared) {
      const physical = capturedDuckDBPhysicalCapacity(prepared);
      const capacity = moon.clientProgramInstalledDuckDBCaptureCapacity(
        capturedDuckDBConfiguration(prepared));
      if (capacity === undefined) {
        throw new TypeError('InstalledSourceCapacityUnavailable');
      }
      return Object.freeze({
        capacity,
        transferBytes: physical.transferBytes,
        executionBytes: physical.executionBytes,
      });
    },
    prepare: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence}) => prepareCapturedDuckDBSource({...common,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence, transportLimits: profile.transportLimits}),
    open: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, signal, preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput}) =>
      openCapturedDuckDBSource({
      ...common, preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, transportLimits: profile.transportLimits, signal,
      preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput}),
    close: () => {},
  });
}

async function readProfile(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  try { return await readSourceProfileJson(path); }
  catch (cause) {
    throw Object.assign(new TypeError('InvalidInstalledSourceProfile',
      {cause}), {code: 'InvalidInstalledSourceProfile'});
  }
}

// The explicit publication step of an installed source whose connector has
// one (a Salesforce source publishes its targeted declaration). A Host start
// never runs it; it uses the same state root and principal the Host will.
export async function publishInstalledSourceProfile(path, {root, principalId,
  moon, runtimeUrl, resolveSecret, signal, connectorTable}) {
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  if (module.publish === undefined) {
    throw Object.assign(new TypeError('InstalledSourcePublicationUnsupported'),
      {code: 'InstalledSourcePublicationUnsupported'});
  }
  const checked = module.check(splitSourceAliasProfile(profile).providerProfile);
  return module.publish(checked, {root, principalId, moon, resolveSecret,
    signal, installation: entry, ...await providerRuntime(entry, runtimeUrl)});
}

// Load the Host's installed source from `path`, or none. An unknown version
// or an invalid profile is refused before any provider or Site I/O. Only the
// selected connector's module and provider bundle are loaded.
export async function loadInstalledSource(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable}) {
  if (path === undefined) return undefined;
  const profile = await readProfile(path);
  const {providerProfile, queryAliases} = splitSourceAliasProfile(profile);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  const checked = module.check(providerProfile);
  let publicationRevision;
  try {
    // Metadata reads only: no provider request or credential resolution.
    const identityProfile = {...profile};
    if (queryAliases.length === 0) delete identityProfile.queryAliases;
    publicationRevision = sourceIdentityFromParts(await module.identityParts(
      identityProfile, providerProfile, readSourceProfileJson, entry), queryAliases);
  } catch {
    // Usable positive installation metadata alone cannot prove completeness.
  }
  const adapter = await module.load(checked, {root, principalId, moon,
    baseEnvironmentWire, resolveSecret, installation: entry,
    ...await providerRuntime(entry, runtimeUrl)});
  try {
    verifyInstalledConnectorRegistration(entry, adapter);
    const source = Object.freeze({...adapter, queryAliases});
    if (publicationRevision !== undefined) {
      let current;
      try { current = await installedSourceIdentity(path, {connectorTable}); }
      catch { /* Missing metadata leaves the namespace observation unresolved. */ }
      if (current === publicationRevision) {
        sourcePublications.set(source, Object.freeze({path,
          revision: publicationRevision, aliases: queryAliases}));
      }
    }
    return source;
  } catch (cause) {
    // The caller cannot own an adapter until validation returns it.
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile: adapter});
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
  if (paths.length < 2) return loadInstalledSource(paths[0], options);
  if (!validPluralSourcePaths(paths)) {
    throw new TypeError('InvalidInstalledSourceProfiles');
  }
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
    let environmentWire;
    const bindings = new Map();
    for (const source of sources) {
      const combined = composeInstalledCheckEnvironment(options.moon,
        options.baseEnvironmentWire, environmentWire, source.environmentWire);
      verifyInstalledConnectorBindings(environmentWire === undefined ? undefined
        : {environmentWire, connectorBindings: [...bindings.values()]}, source);
      environmentWire = combined;
      // Validate a member's own duplicates before coalescing matching physical
      // bindings across members. Preserve the original declaration order.
      for (const binding of source.connectorBindings ?? []) {
        if (!bindings.has(binding.connectorId)) {
          bindings.set(binding.connectorId, binding);
        }
      }
    }
    const {queryAliases} = splitSourceAliasProfile({queryAliases:
      sources.flatMap(source => source.queryAliases ?? [])});
    if (new Set(queryAliases.map(alias => alias.name)).size !== queryAliases.length) {
      throw new TypeError('InvalidPublicSourcePublication');
    }
    return Object.freeze({
      realizationKey: sources.every(source =>
        source.realizationKey === 'duckdb-acquired')
        ? 'duckdb-acquired' : 'installed-multi-acquired', environmentWire,
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
