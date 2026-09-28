// The standard Host's installed Effect: one Effect installation per Host,
// selected by the Host profile's version. The installation supplies only its
// Check Environment and the provider projections of a Run's capture and
// recovery; the Host's Run, Checkpoint, dispatch and publication owners stay
// the same. It holds no secret value or private key: the Site profile names
// the credential material, and the Host's private evidence key is the Host's
// own.
//
// An installation provides `environmentWire`, `prepareCaptured(facts)` and
// `prepareRecovered(facts)` over the Host's Effect Site facts, and `close()`.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {canonicalJson} from './local-account-config.mjs';

const INSTALLED_SALESFORCE_EFFECT_VERSION =
  'actql-installed-salesforce-effect/0.1';
const salesforceBundle = new URL('../../_build/js/release/build/' +
  'connectors/salesforce/host_node/host_node.js', import.meta.url);

const refuse = (code, cause) => {
  throw Object.assign(new TypeError(code, {cause}), {code});
};

async function readProfile(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    refuse('InvalidInstalledEffectProfilePath');
  }
  let profile;
  try { profile = JSON.parse(await readFile(path, 'utf8')); }
  catch (cause) { refuse('InvalidInstalledEffectProfile', cause); }
  if (profile?.version !== INSTALLED_SALESFORCE_EFFECT_VERSION) {
    refuse('InvalidInstalledEffectProfile');
  }
  return profile;
}

// Only installation references and published, immutable declarations enter
// this identity. The referenced Site profile contains credential references,
// never an access token; no profile contents are returned to the caller.
export async function installedEffectIdentity(path) {
  const profile = await readProfile(path);
  const {checkInstalledSalesforceEffectProfile} = await import(
    '../connectors/salesforce/host/installed-salesforce-effect.mjs');
  const checked = checkInstalledSalesforceEffectProfile(profile);
  const parts = await Promise.all([path, checked.siteProfilePath,
    checked.publicationPath].map(async name => {
    const bytes = await readFile(name);
    if (bytes.byteLength > 8 * 1024 * 1024) {
      refuse('InvalidInstalledEffectProfile');
    }
    return JSON.parse(bytes.toString('utf8'));
  }));
  parts[0].accountConfigurationWire = JSON.parse(
    parts[0].accountConfigurationWire);
  const hash = createHash('sha256');
  for (const part of parts) {
    const canonical = canonicalJson(part);
    hash.update(String(Buffer.byteLength(canonical)));
    hash.update('\0');
    hash.update(canonical);
  }
  return `sha256:${hash.digest('hex')}`;
}

// The Site binds its capability attestation and credential grants to the
// exact standard runtime this Host executes.
const runtimeBundleCid = async runtimeUrl => `sha256:${createHash('sha256')
  .update(await readFile(runtimeUrl)).digest('hex')}`;

// The explicit publication step of an installed Effect: one generation of its
// declaration, execution Mappings and Check Environment. A Host start never
// runs it; it uses the same state root and principal the Host will.
export async function publishInstalledEffectProfile(path, {root, principalId,
  moon, runtimeUrl, baseEnvironmentWire, resolveSecret, signal}) {
  const profile = await readProfile(path);
  const {checkInstalledSalesforceEffectProfile,
    publishInstalledSalesforceEffect} = await import(
    '../connectors/salesforce/host/installed-salesforce-effect.mjs');
  const checked = checkInstalledSalesforceEffectProfile(profile);
  const salesforceMoon = await import(salesforceBundle.href);
  return publishInstalledSalesforceEffect(checked, {root, principalId, moon,
    salesforceMoon, runtimeBundleCid: await runtimeBundleCid(runtimeUrl),
    baseEnvironmentWire, resolveSecret, signal});
}

// Load the Host's installed Effect from `path`, or none. An unknown version
// or an invalid profile is refused before any Site or provider I/O; the
// published generation is restored without provider I/O. Its Effect Ledger
// lives under the Host's state root.
export async function loadInstalledEffect(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret}) {
  if (path === undefined) return undefined;
  const profile = await readProfile(path);
  const [{checkInstalledSalesforceEffectProfile,
    loadInstalledSalesforceEffect}, {salesforceEffectSiteHooks}] =
    await Promise.all([
      import('../connectors/salesforce/host/installed-salesforce-effect.mjs'),
      import(
        '../connectors/salesforce/host/installed-salesforce-effect-hooks.mjs'),
    ]);
  const checked = checkInstalledSalesforceEffectProfile(profile);
  const salesforceMoon = await import(salesforceBundle.href);
  const effect = await loadInstalledSalesforceEffect(checked, {root,
    principalId, moon, salesforceMoon, baseEnvironmentWire,
    runtimeBundleCid: await runtimeBundleCid(runtimeUrl), resolveSecret,
    ledgerRoot: join(root, 'state', 'effects', 'ledger')});
  const hooks = salesforceEffectSiteHooks(effect);
  return Object.freeze({environmentWire: effect.environmentWire,
    connectorBindings: effect.connectorBindings,
    prepareCaptured: hooks.prepareCaptured,
    prepareRecovered: hooks.prepareRecovered,
    close: () => effect.close()});
}
