// Static author DATA enters the existing Common declaration owner. This
// module owns no provider I/O, credential, capacity, reader or publication
// writer. The generated definition itself is the installed schema original.
import {createHash} from 'node:crypto';
import type {BinaryLike} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {captureConfigurationReaders} from './source-profile-json.mjs';
import type {RestSourceInstallationDefinition, RestSourceProfile} from '../../packages/local-node/connector-installation.js';

export const REST_SOURCE_SITE_VERSION = 'actql-installed-rest-site/0.1';
type Site = Readonly<{
  version: typeof REST_SOURCE_SITE_VERSION; apiOrigin: string; credentialAuthorityId: string;
  credentialKeyId: string; credentialPrivateKeyPath: string; environment: string;
  journalRoot: string; namespaceId: string; siteGeneration: number; siteKey: string; caPath?: string;
}>;
type ReaderOptions = Readonly<{configurationReader?: unknown}>;
type ConfiguredReader = Readonly<{readJson(path: string): unknown; readOriginalBytes?(path: string): unknown}>;
export type DeclaredRestPublication = Readonly<{catalog_cid: string; catalog: string;
  contracts: readonly string[]; view_bodies: readonly string[]; manifest_entry: string}>;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = (value: unknown): value is string => text(value) && isAbsolute(value);
const hash = (value: BinaryLike) => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const closed = (value: unknown, names: readonly string[], optional: readonly string[] = []): value is Readonly<Record<string, unknown>> => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) return false;
  const fields = Object.getOwnPropertyDescriptors(value);
  return names.every(name => Object.hasOwn(fields, name)) && Reflect.ownKeys(fields).every(name =>
    typeof name === 'string' && (names.includes(name) || optional.includes(name)) &&
    Object.hasOwn(fields[name], 'value'));
};
const freeze = <Value,>(value: Value): Value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};
const profileKeys = ['version', 'connectorId', 'siteProfilePath', 'accountConfigurationWire'] as const;
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId', 'siteGeneration', 'siteKey'] as const;

export function createRestSourceMetadata(definition: RestSourceInstallationDefinition) {
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
  let origin: URL | undefined;
  try {origin = new URL(original.origin);} catch { /* Closed refusal below. */ }
  if (origin?.protocol !== 'https:' || origin.origin !== original.origin || origin.username || origin.password) {
    fail('InvalidRestSourceInstallationOrigin');
  }
  const definitionWire = JSON.stringify(original);

  function authoredDeclarationWire() {
    return original.authoredViewsWire;
  }

  function checkProfile(profile: unknown): Readonly<RestSourceProfile> {
    if (!closed(profile, profileKeys) || profile.version !== original.profileVersion ||
        !text(profile.connectorId) || !absolute(profile.siteProfilePath) ||
        typeof profile.accountConfigurationWire !== 'string') fail('InvalidInstalledRestSourceProfile');
    return Object.freeze({...profile} as unknown as RestSourceProfile);
  }
  function checkSite(value: unknown): Site {
    if (!closed(value, siteKeys, ['caPath']) || value.version !== REST_SOURCE_SITE_VERSION ||
        value.apiOrigin !== original.origin ||
        !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(name => text(value[name])) ||
        !absolute(value.credentialPrivateKeyPath) || !absolute(value.journalRoot) ||
        !Number.isSafeInteger(value.siteGeneration) || (value.siteGeneration as number) < 0 ||
        (value.caPath !== undefined && !absolute(value.caPath))) fail('InvalidInstalledRestSourceSite');
    return Object.freeze({...value} as Site);
  }
  async function readInputs(profile: unknown, {configurationReader}: ReaderOptions = {}) {
    const installed = checkProfile(profile);
    if (configurationReader === undefined) fail('RestSourceConfigurationReaderUnavailable');
    const reads = captureConfigurationReaders(configurationReader, undefined,
      () => fail('RestSourceConfigurationReaderUnavailable')) as unknown as ConfiguredReader;
    const site = checkSite(await reads.readJson(installed.siteProfilePath));
    // The original Host reader owns the observed FD extent and physical read.
    // Retain the same CA Buffer; no text projection or unrelated bound is used.
    let ca: Buffer | undefined;
    if (site.caPath !== undefined) {
      if (typeof reads.readOriginalBytes !== 'function') fail('RestSourceTlsAuthorityPolicyUnavailable');
      ca = await reads.readOriginalBytes(site.caPath) as Buffer;
      if (!Buffer.isBuffer(ca)) fail('InvalidInstalledRestSourceSite');
    }
    return Object.freeze({installed, site, ca, definition: original,
      // Canonical configuration identities alone normalize descriptive text.
      // Keep exact original strings too, including the Account wire, so that
      // physically distinct provider bindings cannot become Saved aliases.
      originalStringsCid: hash(JSON.stringify([definitionWire, ...profileKeys.map(name => installed[name]),
        ...siteKeys.map(name => site[name]),
        ...(site.caPath === undefined ? [] : ['tls-ca', site.caPath, hash(ca!)])]))});
  }
  async function identityParts(profile: object, providerProfile: unknown, _readJson?: unknown,
    _installation?: unknown, context?: ReaderOptions) {
    const input = await readInputs(providerProfile, {configurationReader: context?.configurationReader});
    return [Object.freeze({...profile, accountConfigurationWire: JSON.parse(input.installed.accountConfigurationWire)}),
      input.site, original, Object.freeze({originalStringsCid: input.originalStringsCid})] as const;
  }
  function reportPrepared(input: Awaited<ReturnType<typeof readInputs>>, declared: DeclaredRestPublication) {
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
