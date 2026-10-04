// The standard Host's installed Effect: one Effect installation per Host,
// selected by the Host profile's version from the installed connector table
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
import {readFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {canonicalJson} from './local-account-config.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {installedConnectorFor, installedEffectTable,
  loadInstalledEffectModule, providerBundleUrl,
  verifyInstalledConnectorRegistration} from './installed-connectors.mjs';

const installations = installedEffectTable(installedConnectors);

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
  return profile;
}

// Select the installed connector of an Effect profile. An unknown version
// is refused before any Site or provider I/O.
async function selectInstallation(profile) {
  const entry = installedConnectorFor(installations, profile,
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
export async function installedEffectIdentity(path) {
  const profile = await readProfile(path);
  const {module} = await selectInstallation(profile);
  module.check(profile);
  const read = async name => {
    const bytes = await readFile(name);
    if (bytes.byteLength > 8 * 1024 * 1024) {
      refuse('InvalidInstalledEffectProfile');
    }
    return JSON.parse(bytes.toString('utf8'));
  };
  const parts = await module.identityParts(profile, read);
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
  moon, runtimeUrl, baseEnvironmentWire, resolveSecret, signal}) {
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile);
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
export async function loadInstalledEffect(path, {root, principalId, moon,
  runtimeUrl, baseEnvironmentWire, resolveSecret}) {
  if (path === undefined) return undefined;
  const profile = await readProfile(path);
  const {entry, module} = await selectInstallation(profile);
  const installed = verifyInstalledConnectorRegistration(entry,
    await module.load(module.check(profile), {root, principalId, moon,
      baseEnvironmentWire, resolveSecret, installation: entry,
      ledgerRoot: join(root, 'state', 'effects', 'ledger'),
      ...await providerRuntime(entry, runtimeUrl)}));
  if (typeof installed?.prepareCaptured !== 'function' ||
      typeof installed.prepareRecovered !== 'function' ||
      typeof installed.environmentWire !== 'string') {
    refuse('InvalidInstalledEffectInstallation');
  }
  return Object.freeze({environmentWire: installed.environmentWire,
    connectorBindings: installed.connectorBindings,
    targetReadInventory: installed.targetReadInventory,
    targetReadAuthorization: installed.targetReadAuthorization,
    prepareCaptured: installed.prepareCaptured,
    prepareRecovered: installed.prepareRecovered,
    close: () => installed.close()});
}
