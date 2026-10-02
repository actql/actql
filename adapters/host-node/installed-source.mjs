// The standard Host's installed source binding, selected by the
// Host profile's version. Each installation adapter keeps its own physical
// I/O, grants and cleanup; the Host's Run, Checkpoint and dispatch owners
// stay the same for every adapter.
//
// An adapter provides:
// - `realizationKey`, `environmentWire` (the Check Environment of this
//   installation), `readAuthorization` ({accountConfiguration, context}, for
//   the Host's pre-acquisition Checkpoint) and `sourceAccess` (the base
//   access whose `authorization` a Checkpoint may wrap);
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
import {composeInstalledCheckEnvironment, verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {INSTALLED_DUCKDB_SOURCE_VERSION, installDuckDBSourceProfile} from
  './installed-duckdb-source.mjs';
import {openCapturedDuckDBSource, prepareCapturedDuckDBSource} from
  './captured-duckdb-source.mjs';

const INSTALLED_SALESFORCE_SOURCE_VERSION =
  'actql-installed-salesforce-source/0.1';
const salesforceBundle = new URL('../../_build/js/release/build/' +
  'connectors/salesforce/host_node/host_node.js', import.meta.url);

// A connected embedded Host keeps one installed source for its lifetime.
// Compare its full published generation and Site binding on later connects,
// without reading a credential value or probing the provider.
export async function installedSourceIdentity(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  const read = async name => {
    const bytes = await readFile(name);
    if (bytes.byteLength > 8 * 1024 * 1024) {
      throw new TypeError('InvalidInstalledSourceProfile');
    }
    return JSON.parse(bytes.toString('utf8'));
  };
  const profile = await read(path);
  const {providerProfile, queryAliases} = splitSourceAliasProfile(profile);
  // Omission and an explicitly empty alias publication have the same meaning.
  if (queryAliases.length === 0) delete profile.queryAliases;
  const parts = [profile];
  if (profile?.version === INSTALLED_SALESFORCE_SOURCE_VERSION) {
    const {checkInstalledSalesforceSourceProfile} = await import(
      '../connectors/salesforce/host/installed-salesforce-source.mjs');
    const checked = checkInstalledSalesforceSourceProfile(
      providerProfile);
    parts.push(await read(checked.siteProfilePath),
      await read(checked.publicationPath));
    profile.accountConfigurationWire = JSON.parse(
      profile.accountConfigurationWire);
  } else if (profile?.version !== INSTALLED_DUCKDB_SOURCE_VERSION) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const hash = createHash('sha256');
  for (const part of parts) {
    const canonical = canonicalJson(part);
    hash.update(String(Buffer.byteLength(canonical)));
    hash.update('\0');
    hash.update(canonical);
  }
  return `sha256:${hash.digest('hex')}`;
}

function duckdbAdapter(profile, moon, {root, principalId}) {
  const common = {moon, database: profile.database, schema: profile.schema,
    table: profile.table, acquisitionPlanning: profile.acquisitionPlanning};
  const catalogIds = JSON.parse(profile.environmentWire).connector_catalogs
    .map(catalog => catalog.connector_id);
  return Object.freeze({
    realizationKey: 'duckdb-acquired',
    environmentWire: profile.environmentWire,
    connectorBindings: Object.freeze(catalogIds.map(connectorId =>
      Object.freeze({connectorId, bindingCid: contentCid({
        version: 'actql-installed-duckdb-source-binding/0.1',
        root, principalId, database: profile.database,
        schema: profile.schema, table: profile.table,
        sourceRef: profile.sourceRef,
      })}))),
    readAuthorization: profile.readAuthorization,
    sourceAccess: profile.sourceAccess,
    admitsSource: sourceRef => sourceRef === profile.sourceRef,
    prepare: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence}) => prepareCapturedDuckDBSource({...common,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence, transportLimits: profile.transportLimits}),
    open: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, signal, preparedSource, reportAcquisitionFailure, occurrence, ledger}) =>
      openCapturedDuckDBSource({
      ...common, preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, transportLimits: profile.transportLimits, signal,
      preparedSource, reportAcquisitionFailure, occurrence, ledger}),
    close: () => {},
  });
}

// The explicit publication step of an installed source that has one (a
// Salesforce source publishes its targeted declaration). A Host start never
// runs it; it uses the same state root and principal the Host will.
export async function publishInstalledSourceProfile(path, {root, principalId,
  moon, runtimeUrl, resolveSecret, signal}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  let profile;
  try { profile = JSON.parse(await readFile(path, 'utf8')); }
  catch (cause) {
    throw Object.assign(new TypeError('InvalidInstalledSourceProfile',
      {cause}), {code: 'InvalidInstalledSourceProfile'});
  }
  if (profile?.version !== INSTALLED_SALESFORCE_SOURCE_VERSION) {
    throw Object.assign(new TypeError('InstalledSourcePublicationUnsupported'),
      {code: 'InstalledSourcePublicationUnsupported'});
  }
  const {checkInstalledSalesforceSourceProfile,
    publishInstalledSalesforceSource} = await import(
    '../connectors/salesforce/host/installed-salesforce-source.mjs');
  const checked = checkInstalledSalesforceSourceProfile(
    splitSourceAliasProfile(profile).providerProfile);
  const salesforceMoon = await import(salesforceBundle.href);
  const runtimeBundleCid = `sha256:${createHash('sha256')
    .update(await readFile(runtimeUrl)).digest('hex')}`;
  return publishInstalledSalesforceSource(checked, {root, principalId, moon,
    salesforceMoon, runtimeBundleCid, resolveSecret, signal});
}

// Load the Host's installed source from `path`, or none. An unknown version
// or an invalid profile is refused before any provider or Site I/O.
export async function loadInstalledSource(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret}) {
  if (path === undefined) return undefined;
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  let profile;
  try { profile = JSON.parse(await readFile(path, 'utf8')); }
  catch (cause) {
    throw Object.assign(new TypeError('InvalidInstalledSourceProfile',
      {cause}), {code: 'InvalidInstalledSourceProfile'});
  }
  const {providerProfile, queryAliases} = splitSourceAliasProfile(profile);
  if (profile?.version === INSTALLED_DUCKDB_SOURCE_VERSION) {
    const adapter = duckdbAdapter(await installDuckDBSourceProfile(providerProfile,
      {root, principalId}), moon, {root, principalId});
    return Object.freeze({...adapter, queryAliases});
  }
  if (profile?.version === INSTALLED_SALESFORCE_SOURCE_VERSION) {
    // The Salesforce adapter and its provider bundle are loaded only for a
    // Salesforce installation.
    const {checkInstalledSalesforceSourceProfile,
      loadInstalledSalesforceSource} = await import(
      '../connectors/salesforce/host/installed-salesforce-source.mjs');
    const checked = checkInstalledSalesforceSourceProfile(providerProfile);
    const salesforceMoon = await import(salesforceBundle.href);
    // The Site binds its credential grants to the exact standard runtime
    // this Host executes.
    const runtimeBundleCid = `sha256:${createHash('sha256')
      .update(await readFile(runtimeUrl)).digest('hex')}`;
    const adapter = await loadInstalledSalesforceSource(checked, {root,
      principalId, moon, salesforceMoon, baseEnvironmentWire, runtimeBundleCid,
      resolveSecret});
    return Object.freeze({...adapter, queryAliases});
  }
  throw Object.assign(new TypeError('InvalidInstalledSourceProfile'),
    {code: 'InvalidInstalledSourceProfile'});
}

// Installation inventory is bounded and inert. Only a checked acquisition
// occurrence selects a member later; installing a binding never reads it.
export function installedSourcePaths({sourceProfilePath, sourceProfilePaths} = {},
  fallback = process.env.ACTQL_LOCAL_SOURCE_PROFILE) {
  if (sourceProfilePaths !== undefined) {
    if (sourceProfilePath !== undefined || fallback !== undefined ||
        !Array.isArray(sourceProfilePaths) || sourceProfilePaths.length !== 2 ||
        sourceProfilePaths.some(path => typeof path !== 'string' || !isAbsolute(path)) ||
        new Set(sourceProfilePaths).size !== sourceProfilePaths.length) {
      throw new TypeError('InvalidInstalledSourceProfiles');
    }
    return Object.freeze([...sourceProfilePaths]);
  }
  const path = sourceProfilePath ?? fallback;
  return path === undefined ? Object.freeze([]) : Object.freeze([path]);
}

export async function loadInstalledSources(paths, options) {
  if (paths.length < 2) return loadInstalledSource(paths[0], options);
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
    for (const path of paths) {
      const source = await loadInstalledSource(path, options);
      sources.push(source);
      // This first public multi-input profile is two independent DuckDB
      // acquisitions. Other providers retain their existing singular path.
      if (source.realizationKey !== 'duckdb-acquired') {
        throw new TypeError('InstalledMultiSourceUnsupported');
      }
    }
    verifyInstalledConnectorBindings(sources[0], sources[1]);
    const environmentWire = composeInstalledCheckEnvironment(options.moon,
      options.baseEnvironmentWire, sources[0].environmentWire, sources[1].environmentWire);
    const refs = sources.map(source => source.sourceAccess.sourceRef);
    if (new Set(refs).size !== refs.length) {
      throw new TypeError('InstalledSourceBindingAmbiguous');
    }
    return Object.freeze({
      realizationKey: 'duckdb-acquired', environmentWire,
      sources: Object.freeze(sources),
      connectorBindings: Object.freeze(sources.flatMap(source => source.connectorBindings)),
      queryAliases: Object.freeze(sources.flatMap(source => source.queryAliases ?? [])),
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
