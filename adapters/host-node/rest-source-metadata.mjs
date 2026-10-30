// Static author DATA enters the existing Common declaration owner. This
// module owns no provider I/O, credential, capacity, reader or publication
// writer. The generated definition itself is the installed schema original.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {captureConfigurationReaders} from './source-profile-json.mjs';

export const REST_SOURCE_SITE_VERSION = 'actql-installed-rest-site/0.1';
const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const hash = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const closed = (value, names, optional = []) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) return false;
  const fields = Object.getOwnPropertyDescriptors(value);
  return names.every(name => Object.hasOwn(fields, name)) && Reflect.ownKeys(fields).every(name =>
    typeof name === 'string' && (names.includes(name) || optional.includes(name)) &&
    Object.hasOwn(fields[name], 'value'));
};
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};
const profileKeys = ['version', 'connectorId', 'siteProfilePath', 'accountConfigurationWire'];
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId', 'siteGeneration', 'siteKey'];

export function createRestSourceMetadata(definition) {
  // Generated module DATA, not an alternate author parser. Source field
  // types/nullability are passed unchanged to Common, which may reject them.
  const original = freeze(structuredClone(definition));
  if (!closed(original, ['registration', 'revision', 'profileVersion', 'origin', 'auth', 'sources', 'authoredViewsWire']) ||
      ![original.registration, original.revision, original.profileVersion, original.origin].every(text) ||
      !closed(original.auth, ['kind']) || original.auth.kind !== 'bearer' ||
      !Array.isArray(original.sources) || original.sources.length === 0 ||
      new Set(original.sources.map(source => source.resource)).size !== original.sources.length ||
      typeof original.authoredViewsWire !== 'string') {
    fail('InvalidRestSourceInstallationDefinition');
  }
  let origin;
  try {origin = new URL(original.origin);} catch { /* Closed refusal below. */ }
  if (origin?.protocol !== 'https:' || origin.origin !== original.origin || origin.username || origin.password) {
    fail('InvalidRestSourceInstallationOrigin');
  }
  const definitionWire = JSON.stringify(original);

  function authoredDeclarationWire() {
    return original.authoredViewsWire;
  }

  function checkProfile(profile) {
    if (!closed(profile, profileKeys) || profile.version !== original.profileVersion ||
        !text(profile.connectorId) || !absolute(profile.siteProfilePath) ||
        typeof profile.accountConfigurationWire !== 'string') fail('InvalidInstalledRestSourceProfile');
    return Object.freeze({...profile});
  }
  function checkSite(value) {
    if (!closed(value, siteKeys, ['caPath']) || value.version !== REST_SOURCE_SITE_VERSION ||
        value.apiOrigin !== original.origin ||
        !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(name => text(value[name])) ||
        !absolute(value.credentialPrivateKeyPath) || !absolute(value.journalRoot) ||
        !Number.isSafeInteger(value.siteGeneration) || value.siteGeneration < 0 ||
        (value.caPath !== undefined && !absolute(value.caPath))) fail('InvalidInstalledRestSourceSite');
    return Object.freeze({...value});
  }
  async function readInputs(profile, {configurationReader} = {}) {
    const installed = checkProfile(profile);
    if (configurationReader === undefined) fail('RestSourceConfigurationReaderUnavailable');
    const reads = captureConfigurationReaders(configurationReader, undefined,
      () => fail('RestSourceConfigurationReaderUnavailable'));
    const site = checkSite(await reads.readJson(installed.siteProfilePath));
    // The original Host reader owns the selected bound and physical read.
    // Keep its exact CA text; no author limit or unrelated secret bound is used.
    const ca = site.caPath === undefined ? undefined : await reads.readText(site.caPath);
    if (site.caPath !== undefined && typeof ca !== 'string') fail('InvalidInstalledRestSourceAuthority');
    return Object.freeze({installed, site, ca, definition: original,
      // Canonical configuration identities alone normalize descriptive text.
      // Keep exact original strings too, including the Account wire, so that
      // physically distinct provider bindings cannot become Saved aliases.
      originalStringsCid: hash(JSON.stringify([definitionWire, ...profileKeys.map(name => installed[name]),
        ...siteKeys.map(name => site[name]), site.caPath, ca]))});
  }
  async function identityParts(profile, providerProfile, _readJson, _installation, context) {
    const input = await readInputs(providerProfile, {configurationReader: context?.configurationReader});
    return [Object.freeze({...profile, accountConfigurationWire: JSON.parse(input.installed.accountConfigurationWire)}),
      input.site, original, Object.freeze({originalStringsCid: input.originalStringsCid,
        ...(input.ca === undefined ? {} : {ca: input.ca})})];
  }
  function reportPrepared(input, declared) {
    return Object.freeze({connectorId: input.installed.connectorId,
      connectorRegistration: original.registration, connectorRevision: original.revision,
      catalogCid: declared.catalog_cid, catalog: declared.catalog,
      contracts: Object.freeze([...declared.contracts]),
      sourceViews: Object.freeze([...declared.view_bodies]),
      manifestEntry: declared.manifest_entry, originalStringsCid: input.originalStringsCid});
  }
  return Object.freeze({definition: original, checkProfile, readInputs, identityParts,
    authoredDeclarationWire, reportPrepared});
}
