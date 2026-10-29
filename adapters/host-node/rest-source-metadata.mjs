// Static author DATA enters the existing Common declaration owner. This
// module owns no provider I/O, credential, capacity, reader or publication
// writer. The generated definition itself is the installed schema original.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
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
  if (!closed(original, ['registration', 'revision', 'profileVersion', 'origin', 'auth', 'sources']) ||
      ![original.registration, original.revision, original.profileVersion, original.origin].every(text) ||
      !closed(original.auth, ['kind']) || original.auth.kind !== 'bearer' ||
      !Array.isArray(original.sources) || original.sources.length === 0 ||
      new Set(original.sources.map(source => source.resource)).size !== original.sources.length) {
    fail('InvalidRestSourceInstallationDefinition');
  }
  let origin;
  try {origin = new URL(original.origin);} catch { /* Closed refusal below. */ }
  if (origin?.protocol !== 'https:' || origin.origin !== original.origin || origin.username || origin.password) {
    fail('InvalidRestSourceInstallationOrigin');
  }
  const viewsWire = JSON.stringify({views: original.sources.map(source => ({resource: source.resource,
    resource_kind: source.resource_kind, fields: source.fields}))});
  const definitionWire = JSON.stringify(original);

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
    // No normal CA policy has been supplied by the Host selector yet. Never
    // borrow the unrelated secret bound or add an author/public tuning field.
    if (value.caPath !== undefined) fail('RestSourceTlsAuthorityPolicyUnavailable');
    return Object.freeze({...value});
  }
  async function readInputs(profile, {configurationReader, readJson} = {}) {
    const installed = checkProfile(profile);
    const reads = captureConfigurationReaders(configurationReader, readJson,
      () => fail('RestSourceConfigurationReaderUnavailable'));
    const site = checkSite(await reads.readJson(installed.siteProfilePath));
    return Object.freeze({installed, site, definition: original,
      // Canonical configuration identities alone normalize descriptive text.
      // Keep exact original strings too, including the Account wire, so that
      // physically distinct provider bindings cannot become Saved aliases.
      originalStringsCid: hash(JSON.stringify([definitionWire, ...profileKeys.map(name => installed[name]),
        ...siteKeys.map(name => site[name])]))});
  }
  async function identityParts(profile, providerProfile, readJson, _installation, context) {
    const input = await readInputs(providerProfile, {configurationReader: context?.configurationReader, readJson});
    return [Object.freeze({...profile, accountConfigurationWire: JSON.parse(input.installed.accountConfigurationWire)}),
      input.site, original, Object.freeze({originalStringsCid: input.originalStringsCid})];
  }
  function restore(profile, moon) {
    const installed = checkProfile(profile);
    const restore = moon?.clientProgramRowSourceRestoreDeclaration;
    const json = moon?.clientProgramRowSourceDeclarationJson;
    if (typeof restore !== 'function' || typeof json !== 'function') fail('RestSourceDeclarationRuntimeUnavailable');
    const declaration = checked(Reflect.apply(restore, moon, [installed.connectorId,
      original.registration, original.revision, viewsWire, undefined]));
    const declared = JSON.parse(Reflect.apply(json, moon, [declaration]));
    return Object.freeze({declaration, declared});
  }
  async function publish(profile, {moon, configurationReader} = {}) {
    // A static definition has no observed provider metadata generation. This
    // reports the SAME Common-issued declaration; it claims no durable write,
    // provider observation, Site opening or permission/admission result.
    const input = await readInputs(profile, {configurationReader});
    const {declared} = restore(input.installed, moon);
    return Object.freeze({connectorId: input.installed.connectorId,
      connectorRegistration: original.registration, connectorRevision: original.revision,
      catalogCid: declared.catalog_cid, catalog: declared.catalog,
      contracts: Object.freeze([...declared.contracts]),
      sourceViews: Object.freeze([...declared.view_bodies]),
      manifestEntry: declared.manifest_entry, originalStringsCid: input.originalStringsCid});
  }
  return Object.freeze({definition: original, checkProfile, readInputs, identityParts, restore, publish});
}
