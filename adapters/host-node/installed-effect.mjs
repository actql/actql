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
import {open, readFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {canonicalJson} from './local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {composeInstalledEffects, validPluralEffectPaths}
  from './installed-effect-inventory.mjs';
export {installedEffectFor} from './installed-effect-inventory.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedConnectorForTable, installedEffectTable,
  loadInstalledEffectModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

const installations = installedEffectTable(installedConnectors);

const refuse = (code, cause) => {
  const failure = Object.assign(new TypeError(code, {cause}), {code});
  if (cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) {
    Object.assign(failure, {cleanupHandle: cause.cleanupHandle,
      cleanupPending: cause.cleanupPending, cleanupErrors: cause.cleanupErrors,
      primaryFailure: cause.primaryFailure ?? cause});
  }
  throw failure;
};

// Bound profile and identity-part reads before buffering, including files that
// grow after opening. This limit is distinct from Check Environment admission.
async function readProfileJson(path) {
  const maxBytes = 8 * 1024 * 1024;
  const file = await open(path, 'r');
  let released = false;
  const release = async () => {
    if (released) return;
    await file.close();
    released = true;
  };
  let failure;
  try {
    const chunks = [];
    let bytes = 0, used = 0;
    let buffer = Buffer.allocUnsafe(64 * 1024);
    for (;;) {
      const {bytesRead} = await file.read(buffer, used, buffer.length - used, null);
      if (bytesRead === 0) {
        chunks.push(buffer.subarray(0, used));
        return JSON.parse(Buffer.concat(chunks, bytes).toString('utf8'));
      }
      bytes += bytesRead;
      used += bytesRead;
      if (bytes > maxBytes) refuse('InvalidInstalledEffectProfile');
      if (used === buffer.length) {
        chunks.push(buffer);
        buffer = Buffer.allocUnsafe(Math.min(64 * 1024, maxBytes - bytes + 1));
        used = 0;
      }
    }
  } catch (cause) { failure = cause; throw cause; }
  finally {
    try { await release(); }
    catch (cause) {
      // No installation has returned yet. Preserve the same file's release
      // responsibility through the existing initialization cleanup owner.
      throw await retainInstalledHostInitializationFailure(failure ?? cause,
        {installedEffect: {close: release}});
    }
  }
}

async function readProfile(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    refuse('InvalidInstalledEffectProfilePath');
  }
  let profile;
  try { profile = await readProfileJson(path); }
  catch (cause) { refuse('InvalidInstalledEffectProfile', cause); }
  return profile;
}

// Select the installed connector of an Effect profile. An unknown version
// is refused before any Site or provider I/O; an explicit table never falls
// back to the standard installation.
async function selectInstallation(profile, connectorTable) {
  const entry = connectorTable === undefined
    ? installedConnectorFor(installations, profile, 'InvalidInstalledEffectProfile')
    : installedConnectorForTable(connectorTable, 'effect', profile,
      'InvalidInstalledEffectProfile');
  return {entry, module: await loadInstalledEffectModule(entry)};
}

// The Site binds its capability attestation and credential grants to the
// exact standard runtime this Host executes.
const runtimeBundleCid = async runtimeUrl => `sha256:${createHash('sha256')
  .update(await readFile(runtimeUrl)).digest('hex')}`;

async function providerRuntime(entry, runtimeUrl) {
  const bundle = providerBundleUrl(entry);
  return {...(bundle === undefined ? {} : {providerMoon:
    await import(bundle.href)}),
  runtimeBundleCid: await runtimeBundleCid(runtimeUrl)};
}

// Only installation references and published, immutable declarations enter
// this identity. The referenced Site profile contains credential references,
// never an access token; no profile contents are returned to the caller.
export async function installedEffectIdentity(path, {connectorTable} = {}) {
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  module.check(profile);
  const parts = await module.identityParts(profile, readProfileJson, entry);
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
  return `sha256:${hash.digest('hex')}`;
}

// The explicit publication step of an installed Effect: one generation of its
// declaration, execution Mappings and Check Environment. A Host start never
// runs it; it uses the same state root and principal the Host will.
export async function publishInstalledEffectProfile(path, {root, principalId,
  moon, runtimeUrl, baseEnvironmentWire, resolveSecret, signal, connectorTable}) {
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  if (module.publish === undefined) {
    refuse('InstalledEffectPublicationUnsupported');
  }
  return module.publish(module.check(profile), {root, principalId, moon,
    baseEnvironmentWire, resolveSecret, signal, installation: entry,
    ...await providerRuntime(entry, runtimeUrl)});
}

// Load the Host's installed Effect from `path`, or none. An unknown version
// or an invalid profile is refused before any Site or provider I/O; the
// published generation is restored without provider I/O. Its Effect Ledger
// lives under the Host's state root.
async function loadEffect(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret, connectorTable}, own) {
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile, connectorTable);
  const installed = await module.load(module.check(profile), {root,
    principalId, moon, baseEnvironmentWire, resolveSecret, installation: entry,
    ledgerRoot: join(root, 'state', 'effects', 'ledger'),
    ...await providerRuntime(entry, runtimeUrl)});
  own(installed);
  verifyInstalledConnectorRegistration(entry, installed);
  if (typeof installed?.prepareCaptured !== 'function' ||
      typeof installed.prepareRecovered !== 'function' ||
      typeof installed.environmentWire !== 'string' ||
      typeof installed.close !== 'function') {
    refuse('InvalidInstalledEffectInstallation');
  }
  return Object.freeze({environmentWire: installed.environmentWire,
    connectorBindings: installed.connectorBindings,
    effectSelectors: installed.effectSelectors,
    mappings: installed.mappings,
    targetReadInventory: installed.targetReadInventory,
    targetReadAuthorization: installed.targetReadAuthorization,
    prepareCaptured: installed.prepareCaptured,
    prepareRecovered: installed.prepareRecovered,
    close: () => installed.close()});
}

export async function loadInstalledEffect(path, options) {
  if (path === undefined) return undefined;
  let installed;
  try {
    return await loadEffect(path, options, value => { installed = value; });
  } catch (cause) {
    if (installed === undefined) throw cause;
    throw await retainInstalledHostInitializationFailure(cause,
      {installedEffect: installed});
  }
}

export function installedEffectPaths({effectProfilePath, effectProfilePaths} = {},
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

export async function loadInstalledEffects(paths, options) {
  if (!Array.isArray(paths)) refuse('InvalidInstalledEffectProfiles');
  if (paths.length < 2) return loadInstalledEffect(paths[0], options);
  if (!validPluralEffectPaths(paths)) refuse('InvalidInstalledEffectProfiles');
  return composeInstalledEffects(paths, options, loadEffect);
}
