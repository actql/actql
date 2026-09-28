// The standard Host's installed source: one source per Host, selected by the
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
// - `prepare({preparedProgram, registry, values, fragment, ordered,
//   sourceAccess})`: the checked source, read tuple and physical binding an
//   approval covers, without provider I/O;
// - `open({... , sourceAccess, signal, preparedSource})`: the acquisition. It
//   returns the captured source ({checkedSource, identity, logicalInput,
//   setup, capture, issueSourceEvidence, close}), which the dispatch owner
//   closes; on failure the adapter releases what it opened itself;
// - optionally `discovery` ({resources, inspectResource, peekResource}) and
//   `close()`.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from './local-account-config.mjs';
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
  const parts = [profile];
  if (profile?.version === INSTALLED_SALESFORCE_SOURCE_VERSION) {
    const {checkInstalledSalesforceSourceProfile} = await import(
      '../connectors/salesforce/host/installed-salesforce-source.mjs');
    const checked = checkInstalledSalesforceSourceProfile(profile);
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

function duckdbAdapter(profile, moon) {
  const common = {moon, database: profile.database, schema: profile.schema,
    table: profile.table};
  return Object.freeze({
    realizationKey: 'duckdb-acquired',
    environmentWire: profile.environmentWire,
    readAuthorization: profile.readAuthorization,
    sourceAccess: profile.sourceAccess,
    admitsSource: sourceRef => sourceRef === profile.sourceRef,
    prepare: ({preparedProgram, registry, values, fragment, ordered,
      sourceAccess}) => prepareCapturedDuckDBSource({...common,
      preparedProgram, registry, values, fragment, ordered, sourceAccess}),
    open: ({preparedProgram, registry, values, fragment, ordered,
      sourceAccess, signal, preparedSource}) => openCapturedDuckDBSource({
      ...common, preparedProgram, registry, values, fragment, ordered,
      sourceAccess, transportLimits: profile.transportLimits, signal,
      preparedSource}),
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
  const checked = checkInstalledSalesforceSourceProfile(profile);
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
  if (profile?.version === INSTALLED_DUCKDB_SOURCE_VERSION) {
    return duckdbAdapter(await installDuckDBSourceProfile(profile,
      {root, principalId}), moon);
  }
  if (profile?.version === INSTALLED_SALESFORCE_SOURCE_VERSION) {
    // The Salesforce adapter and its provider bundle are loaded only for a
    // Salesforce installation.
    const {checkInstalledSalesforceSourceProfile,
      loadInstalledSalesforceSource} = await import(
      '../connectors/salesforce/host/installed-salesforce-source.mjs');
    const checked = checkInstalledSalesforceSourceProfile(profile);
    const salesforceMoon = await import(salesforceBundle.href);
    // The Site binds its credential grants to the exact standard runtime
    // this Host executes.
    const runtimeBundleCid = `sha256:${createHash('sha256')
      .update(await readFile(runtimeUrl)).digest('hex')}`;
    return loadInstalledSalesforceSource(checked, {root, principalId, moon,
      salesforceMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret});
  }
  throw Object.assign(new TypeError('InvalidInstalledSourceProfile'),
    {code: 'InvalidInstalledSourceProfile'});
}
