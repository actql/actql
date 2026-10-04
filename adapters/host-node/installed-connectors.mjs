// The standard Host's installed connector table: which connector-owned
// module an installed Host profile's version selects. Entries come from the
// generated `adapters/connectors-builtin/installations.generated.mjs`
// (connector `host-bundle.json` manifests) and from the Host's own built-in
// bindings. Selecting an entry grants nothing: the selected module checks
// the profile, restores its published declaration and binds its Site.
//
// A source installation module exports:
// - `check(providerProfile)`: the profile's shape, before any I/O;
// - `identityParts(profile, providerProfile, read)`: the parts of the
//   installation identity (the profile and the installed, published
//   documents it names), without a credential value or provider I/O;
// - `load(checked, {root, principalId, moon, baseEnvironmentWire,
//   resolveSecret, installation, providerMoon?, runtimeBundleCid?})`: the
//   installed source adapter (`installed-source.mjs`);
// - optionally `publish(checked, options)`: the explicit publication step.
//
// An Effect installation module (optional `effect` section) exports the same
// entries; its `identityParts(profile, read)` takes the profile only, and its
// `load` also receives the Host's own `ledgerRoot` and returns the Effect
// Site hooks (`installed-effect.mjs`).
import {basename} from 'node:path';

const fail = (code, cause) => {
  throw Object.assign(new TypeError(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const registrationPattern = /^[a-z][a-z0-9_]*$/u;
const profileVersionPattern = /^actql-installed-[a-z0-9-]+\/0\.1$/u;

function checkEntry(entry) {
  if (!entry || typeof entry !== 'object' || !text(entry.name) ||
      !registrationPattern.test(entry.name) ||
      !entry.source || typeof entry.source !== 'object' ||
      !profileVersionPattern.test(entry.source.profileVersion ?? '') ||
      typeof entry.source.load !== 'function' ||
      (entry.registration !== undefined && (entry.registration !== entry.name ||
        !text(entry.revision) ||
        !entry.revision.startsWith(`${entry.registration}/`))) ||
      (entry.providerBundle !== undefined &&
        !/^connectors\/[a-z][a-z0-9_]*\/[a-z][a-z0-9_]*$/u.test(
          entry.providerBundle)) ||
      (entry.responseHeaders !== undefined &&
        !Array.isArray(entry.responseHeaders)) ||
      (entry.effect !== undefined && (!entry.effect ||
        typeof entry.effect !== 'object' ||
        !profileVersionPattern.test(entry.effect.profileVersion ?? '') ||
        entry.effect.profileVersion === entry.source.profileVersion ||
        typeof entry.effect.load !== 'function'))) {
    fail('InvalidInstalledConnectorEntry');
  }
  return entry;
}

// The table by installed Effect profile version, over the entries that
// declare an Effect installation.
export function installedEffectTable(entries) {
  if (!Array.isArray(entries)) fail('InvalidInstalledConnectorEntry');
  const table = new Map();
  for (const entry of entries) {
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
export async function loadInstalledEffectModule(entry) {
  const module = await entry.effect.load();
  if (!module || typeof module !== 'object' ||
      typeof module.check !== 'function' ||
      typeof module.identityParts !== 'function' ||
      typeof module.load !== 'function' ||
      (module.publish !== undefined && typeof module.publish !== 'function')) {
    fail('InvalidInstalledConnectorModule');
  }
  return module;
}

// The table by installed source profile version; duplicate versions refuse
// the whole table before any profile is read.
export function installedConnectorTable(entries) {
  if (!Array.isArray(entries)) fail('InvalidInstalledConnectorEntry');
  const table = new Map();
  for (const entry of entries) {
    const checked = checkEntry(entry);
    if (table.has(checked.source.profileVersion)) {
      fail('InstalledConnectorVersionAmbiguous');
    }
    table.set(checked.source.profileVersion, checked);
  }
  return table;
}

export function installedConnectorFor(table, profile,
  code = 'InvalidInstalledSourceProfile') {
  const entry = typeof profile?.version === 'string'
    ? table.get(profile.version) : undefined;
  if (entry === undefined) fail(code);
  return entry;
}

// The connector's compiled provider bundle, next to the standard runtime.
export function providerBundleUrl(entry, base = import.meta.url) {
  if (entry.providerBundle === undefined) return undefined;
  return new URL(`../../_build/js/release/build/${entry.providerBundle}/` +
    `${basename(entry.providerBundle)}.js`, base);
}

// Load the selected connector's source installation module and check that
// it is one: every required entry is a function.
export async function loadInstalledConnectorModule(entry) {
  const module = await entry.source.load();
  if (!module || typeof module !== 'object' ||
      typeof module.check !== 'function' ||
      typeof module.identityParts !== 'function' ||
      typeof module.load !== 'function' ||
      (module.publish !== undefined && typeof module.publish !== 'function')) {
    fail('InvalidInstalledConnectorModule');
  }
  return module;
}

// The declared registration and revision are a claim about the installed
// implementation, not authority: the loaded adapter must identify itself
// with the same values, or the installation is refused.
export function verifyInstalledConnectorRegistration(entry, adapter) {
  if (entry.registration === undefined) return adapter;
  if (adapter?.connectorRegistration !== entry.registration ||
      adapter?.connectorRevision !== entry.revision) {
    fail('InstalledConnectorRegistrationMismatch');
  }
  return adapter;
}
