// A HubSpot installation supplies original metadata and physical reads only.
// The standard Host owns the declaration, Account gate, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {types} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {prepareHubSpotManagedSequence} from '../site/hubspot-managed-sequence.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION,
  HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import type {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import type {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';

type Limit = (typeof limitKeys)[number];
type Site = Readonly<Record<Exclude<(typeof siteKeys)[number], 'siteGeneration'>, string> &
  {siteGeneration: number; caPath?: string}>;
type Resource = Readonly<{resource: string; objectType: string}>;
type MetadataResources = Readonly<{account: string; properties: string}>;
type Installed = Readonly<{version: typeof INSTALLED_HUBSPOT_SOURCE_VERSION; connectorId: string; portalId: string;
  resources: readonly Resource[]; metadataPath: string; siteProfilePath: string; metadataResources: MetadataResources;
  accountConfigurationWire: string; limits: Readonly<Record<Limit, number>>}>;
type MetadataObject = Resource & Readonly<{propertiesBody: string}>;
type Metadata = Readonly<{version: string; connectorId: string; portalId: string; apiOrigin: string;
  accountBody: string; objects: readonly MetadataObject[]}>;
type Managed = Parameters<typeof prepareHubSpotManagedSequence>[0];
type Provider = Managed['moon'] & Readonly<{
  hubspotPropertyCatalogNames(catalog: unknown): readonly string[];
  hubspotObjectSchemaWire(catalog: unknown, names: readonly string[], maxColumns: number, maxNameUnits: number,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  hubspotObjectRelationFactsWire(): string;
}>;
export type HubSpotReadCommon = Readonly<{
  clientProgramHubSpotAccountConstructionCapacity(bodyBytes: number, encodedUnits: number, portalUnits: number,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramHubSpotObjectConstructionCapacity(bodyBytes: number, encodedUnits: number, objectTypeUnits: number,
    maxBytes: number, maxNodes: number, maxDepth: number, maxProperties: number, maxNameUnits: number,
    maxColumns: number, maxSelectedUnits: number, maxDeclarationBytes: number, maxDeclarationNodes: number,
    maxDeclarationDepth: number): unknown;
}>;
type CapacityMethods = Readonly<{
  clientProgramHubSpotMetadataIdentityCapacity(objects: number, bodyUnits: bigint, stringUnits: bigint): unknown;
  clientProgramHubSpotReadTargetCapacity(objects: number, targetFields: bigint): unknown;
  clientProgramHubSpotReadSequenceBounds(maxRequests: number, maxResponseBytes: number, originUnits: number,
    portalUnits: number, objectUnits: number, fieldUnits: bigint): unknown;
}>;
type View = Readonly<{resource: string; resource_kind: string; schema_wire: string; facts_wire: string; schema_cid: string}>;
type DeclaredView = Readonly<{resource: string; fields: readonly string[]}>;
type Declared = Readonly<{views: readonly DeclaredView[]}>;
type Readers = Readonly<{readJson(path: string): unknown; readOriginalBytes?(path: string): Buffer | PromiseLike<Buffer>}>;
type NativeInput<Value> = Readonly<{capacity(): unknown; project(): Value}>;
type Reader = ReturnType<typeof createInstalledCredentialSourceReader>;
type RowSource = ReturnType<typeof createInstalledRowSource>;
type RowSourceSite = Parameters<typeof createInstalledRowSource>[0]['site'];
type Selection = Readonly<{resource: string; columns: readonly string[]; responseBorrow?: unknown; originalAuthorization?: unknown}>;
type Implementation = Readonly<{capacity: unknown; runAcquisitionLimits: unknown}>;
export type HubSpotOpenedSite = Readonly<{site: RowSourceSite & Readonly<{credential: unknown}>; authorization: Readonly<{context: Readonly<{contextCid: string}>}>}>;
export type HubSpotMaterialsConstruction = Readonly<{
  configurationReader: Readers;
  prepareNativeInput<Value>(input: NativeInput<Value>): Value;
  prepareDeclaration(views: readonly View[]): Readonly<{declared: Declared}>;
}>;
type Construction = HubSpotMaterialsConstruction & Readonly<{
  openRowSite(options: Readonly<Record<string, unknown>>): PromiseLike<HubSpotOpenedSite>;
  prepareReadTarget<Value>(input: NativeInput<Value>): Value;
  createRowSource(options: Readonly<Record<string, unknown>>): RowSource;
  sourceReaderImplementation(options: Readonly<Record<string, unknown>>): Implementation;
  createSourceReader(options: Readonly<{implementation: Implementation;
    prepareReadSequence(input: Selection): ReturnType<typeof prepareHubSpotManagedSequence>}>): Reader;
}>;
type MaterialOptions = Readonly<{moon: HubSpotReadCommon; providerMoon: Provider; construction?: HubSpotMaterialsConstruction}>;
type RequiredMaterialOptions = MaterialOptions & Readonly<{construction: HubSpotMaterialsConstruction}>;
type LoadOptions = MaterialOptions & Readonly<{construction?: Construction; runtimeBundleCid: string; resolveSecret?: unknown;
  installation?: Readonly<{responseHeaders?: readonly string[]}>}>;
type Materials = Readonly<{installed: Installed; siteProfile: Site; metadata: Metadata; objects: Map<string, MetadataObject>;
  catalogs: Map<string, unknown>; views: View[]; identityExtent: Readonly<{objects: number; bodyUnits: bigint; stringUnits: bigint}>}>;
type Target = Resource & Readonly<{version: string; apiOrigin: string; portalId: string; metadataCid: string; fields: readonly string[]}>;

export const INSTALLED_HUBSPOT_SOURCE_VERSION = 'actql-installed-hubspot-source/0.1';
export const INSTALLED_HUBSPOT_SITE_VERSION = 'actql-installed-hubspot-site/0.1';
const registration = 'hubspot', revision = 'hubspot/0.1';
const profileKeys = ['version', 'connectorId', 'portalId', 'resources', 'metadataPath',
  'siteProfilePath', 'metadataResources', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'siteGeneration', 'siteKey', 'tokenEnvironment'] as const;
const limitKeys = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxPages', 'maxRows', 'maxRequests', 'perPage', 'maxColumns',
  'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth', 'maxObjects', 'maxDeclarationBytes',
  'maxDeclarationNodes', 'maxSecretBytes'] as const;
const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = (value: unknown): value is string => text(value) && isAbsolute(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) < 2147483647;
const closed = <Key extends string,>(value: unknown, keys: readonly Key[]): value is Record<Key, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const closedMetadata = <Key extends string,>(value: unknown, keys: readonly Key[]): value is Record<Key, unknown> => !types.isProxy(value) && closed(value, keys) &&
  Object.getPrototypeOf(value) === Object.prototype && keys.every(key =>
    Object.hasOwn(Object.getOwnPropertyDescriptor(value, key)!, 'value'));
const canonical = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledHubSpotSourceProfile(profile: unknown) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_HUBSPOT_SOURCE_VERSION ||
      !text(profile.connectorId) || typeof profile.portalId !== 'string' || !/^[1-9][0-9]{0,10}$/u.test(profile.portalId) ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !text(profile.accountConfigurationWire) || !closed(profile.limits, limitKeys) ||
      !limitKeys.every(key => positive((profile.limits as Installed['limits'])[key])) ||
      !closed(profile.metadataResources, ['account', 'properties']) ||
      !Object.values(profile.metadataResources).every(text) ||
      profile.metadataResources.account === profile.metadataResources.properties ||
      !Array.isArray(profile.resources) || profile.resources.length === 0 ||
      profile.resources.length > (profile.limits.maxObjects as number) ||
      !profile.resources.every(value => closed(value, ['resource', 'objectType']) &&
        text(value.resource) && text(value.objectType) &&
        value.objectType !== '.' && value.objectType !== '..') ||
      new Set(profile.resources.map(value => value.resource)).size !== profile.resources.length ||
      profile.resources.some(value => Object.values(profile.metadataResources as MetadataResources).includes(value.resource)) ||
      (profile.limits.maxPages as number) > (profile.limits.maxRequests as number) ||
      (profile.limits.perPage as number) > (profile.limits.maxRows as number)) fail('InvalidInstalledHubSpotSourceProfile');
  return Object.freeze({...profile, resources: Object.freeze(profile.resources.map(value => Object.freeze({...value}))),
    limits: Object.freeze({...profile.limits}), metadataResources: Object.freeze({...profile.metadataResources})}) as Installed;
}

function checkSite(site: unknown) {
  const {caPath, ...rest} = (site as Partial<Site> | null | undefined) ?? {};
  let origin: URL | undefined;
  try {origin = new URL(rest.apiOrigin!);} catch { /* Closed rejection below. */ }
  if (!closed(rest, siteKeys) || rest.version !== INSTALLED_HUBSPOT_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !(['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'] as const).every(key => text(rest[key])) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !Number.isSafeInteger(rest.siteGeneration) || (rest.siteGeneration as number) < 0 ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment!)) fail('InvalidInstalledHubSpotSite');
  return Object.freeze({...rest, ...(caPath === undefined ? {} : {caPath})}) as Site;
}

function metadataBodyBytes(encoded: unknown, maxBytes: number) {
  if (typeof encoded !== 'string' || encoded.length > Math.ceil(maxBytes / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(encoded)) {
    fail('InvalidInstalledHubSpotMetadata');
  }
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0;
  const bytes = encoded.length / 4 * 3 - padding;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (bytes > maxBytes || padding !== 0 &&
      (alphabet.indexOf(encoded[encoded.length - padding - 1]) & (padding === 2 ? 15 : 3)) !== 0) {
    fail('InvalidInstalledHubSpotMetadata');
  }
  return bytes;
}

function decodeMetadataBody(encoded: string, maxBytes: number) {
  const body = Buffer.from(encoded, 'base64');
  if (body.byteLength > maxBytes || body.toString('base64') !== encoded) fail('InvalidInstalledHubSpotMetadata');
  return body;
}

async function readInputs(profile: unknown, readers: Readers) {
  const installed = checkInstalledHubSpotSourceProfile(profile);
  const site = checkSite(await readers.readJson(installed.siteProfilePath));
  const metadata = await readers.readJson(installed.metadataPath) as Metadata;
  if (!closedMetadata(metadata, ['version', 'connectorId', 'portalId', 'apiOrigin', 'accountBody', 'objects']) ||
      metadata.version !== 'actql-hubspot-read-metadata/0.1' ||
      metadata.connectorId !== installed.connectorId || metadata.portalId !== installed.portalId ||
      metadata.apiOrigin !== site.apiOrigin || !Array.isArray(metadata.objects) || types.isProxy(metadata.objects) ||
      Object.getPrototypeOf(metadata.objects) !== Array.prototype ||
      Reflect.ownKeys(metadata.objects).length !== metadata.objects.length + 1 ||
      metadata.objects.length !== installed.resources.length) fail('InvalidInstalledHubSpotMetadata');
  metadataBodyBytes(metadata.accountBody, installed.limits.maxResponseBytes);
  // Observe the admitted original's body and String extents during its one
  // validation walk. Common owns the canonicalization and digest inventory.
  let bodyUnits = BigInt(metadata.accountBody.length);
  let stringUnits = BigInt(
    metadata.version.length + metadata.connectorId.length + metadata.portalId.length + metadata.apiOrigin.length);
  const objects = new Map<string, MetadataObject>();
  for (let index = 0; index < metadata.objects.length; index++) {
    const entry = Object.getOwnPropertyDescriptor(metadata.objects, index);
    if (!entry || !Object.hasOwn(entry, 'value')) fail('InvalidInstalledHubSpotMetadata');
    const object = entry.value as MetadataObject;
    if (!closedMetadata(object, ['resource', 'objectType', 'propertiesBody']) ||
        objects.has(object.resource) || !installed.resources.some(value =>
          value.resource === object.resource && value.objectType === object.objectType)) {
      fail('InvalidInstalledHubSpotMetadata');
    }
    metadataBodyBytes(object.propertiesBody, installed.limits.maxResponseBytes);
    bodyUnits += BigInt(object.propertiesBody.length);
    stringUnits += BigInt(object.resource.length + object.objectType.length);
    // Keep the same validated JSON originals, including the real reader's
    // objectType. Do not retain a digest of a still-mutable metadata graph.
    objects.set(object.resource, Object.freeze(object));
  }
  Object.freeze(metadata.objects);
  Object.freeze(metadata);
  return {installed, site, metadata, objects,
    identityExtent: Object.freeze({objects: metadata.objects.length, bodyUnits, stringUnits})};
}

export async function installedHubSpotSourceIdentityParts(profile: Readonly<{accountConfigurationWire: string}>,
  providerProfile: unknown, readJson?: unknown, _entry?: unknown, {configurationReader}: Readonly<{configurationReader?: unknown}> = {}) {
  const readers = captureConfigurationReaders(configurationReader, readJson,
    () => fail('HubSpotSourceConstructionUnavailable')) as unknown as Readers;
  const {site, metadata} = await readInputs(providerProfile, readers);
  if (site.caPath !== undefined && configurationReader !== undefined && readers.readOriginalBytes === undefined) {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const ca = site.caPath === undefined ? undefined : await (configurationReader === undefined
    ? readFile(site.caPath) : readers.readOriginalBytes!(site.caPath));
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)}, site,
    {metadataCid: cid(metadata), ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

function siteBinding(contextCid: string, runtimeBundleCid: string, metadataCid: string, site: Site) {
  // Preserve the Source's complete original non-secret physical binding.
  // Each role supplies its own observed material; this issues no permission.
  return cid({version: 'actql-installed-hubspot-binding/0.1', contextCid,
    runtimeBundleCid, metadataCid, site});
}

export function installedHubSpotSiteBinding({contextCid, runtimeBundleCid, metadata, site}: Readonly<{contextCid: string; runtimeBundleCid: string; metadata: Metadata; site: Site}>) {
  return siteBinding(contextCid, runtimeBundleCid, cid(metadata), site);
}

// Source and Effect borrow the same original metadata preparation. This does
// not open a Site, authorize a read/write, resolve a secret or send a request.
// Provider Catalogs stay in their original runtime; the Common declaration is
// produced separately by the existing parent construction owner.
async function prepareHubSpotMaterials<Value>(profile: unknown, {moon, providerMoon: provider, construction}: MaterialOptions, finish: (materials: Materials) => Value) {
  if (construction === undefined || typeof construction.prepareNativeInput !== 'function' ||
      typeof construction.prepareDeclaration !== 'function' || construction.configurationReader === undefined) {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const readers = construction.configurationReader;
  const {installed, site: siteProfile, metadata, objects, identityExtent} = await readInputs(profile, readers);
  const {limits} = installed;
  for (const name of ['clientProgramHubSpotAccountConstructionCapacity', 'clientProgramHubSpotObjectConstructionCapacity']) {
    if (typeof Object.getOwnPropertyDescriptor(moon ?? {}, name)?.value !== 'function') fail('HubSpotOriginalReadUnavailable');
  }
  construction.prepareNativeInput(Object.freeze({
    capacity: () => moon.clientProgramHubSpotAccountConstructionCapacity(
      metadataBodyBytes(metadata.accountBody, limits.maxResponseBytes), metadata.accountBody.length,
      installed.portalId.length, limits.maxResponseBytes, limits.maxNodes, limits.maxDepth),
    project() {
      const account = decodeMetadataBody(metadata.accountBody, limits.maxResponseBytes);
      const identity = JSON.parse(provider.hubspotRecheckAccountIdentityJson(account, installed.portalId,
        limits.maxResponseBytes, limits.maxNodes, limits.maxDepth));
      if (identity.refused !== undefined || identity.account?.portalId !== installed.portalId) {
        fail('InvalidInstalledHubSpotAccount');
      }
      return Object.freeze({account, identity});
    },
  }));
  const catalogs = new Map<string, unknown>(), views: View[] = [];
  for (const {resource, objectType} of installed.resources) {
    const encoded = objects.get(resource)!.propertiesBody;
    const projected = construction.prepareNativeInput(Object.freeze({
      capacity: () => moon.clientProgramHubSpotObjectConstructionCapacity(
        metadataBodyBytes(encoded, limits.maxResponseBytes), encoded.length, objectType.length,
        limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, limits.maxProperties, limits.maxNameUnits,
        limits.maxColumns, limits.maxNameUnits, limits.maxDeclarationBytes, limits.maxDeclarationNodes, limits.maxDepth),
      project() {
        const body = decodeMetadataBody(encoded, limits.maxResponseBytes);
        const catalog = checked(provider.hubspotProjectProperties(body, objectType, limits.maxResponseBytes,
          limits.maxNodes, limits.maxDepth, limits.maxProperties, limits.maxNameUnits));
        const names = provider.hubspotPropertyCatalogNames(catalog);
        const wire = checked(provider.hubspotObjectSchemaWire(catalog, names, limits.maxColumns,
          limits.maxNameUnits, limits.maxDeclarationBytes, limits.maxDeclarationNodes, limits.maxDepth)) as string;
        return Object.freeze({body, catalog, names, wire, view: Object.freeze({resource, resource_kind: 'object',
          schema_wire: wire, facts_wire: provider.hubspotObjectRelationFactsWire(),
          schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`})});
      },
    }));
    catalogs.set(resource, projected.catalog);
    views.push(projected.view);
  }
  return finish({installed, siteProfile, metadata, objects, catalogs, views, identityExtent});
}

export async function prepareInstalledHubSpotMaterials(profile: unknown, options: RequiredMaterialOptions) {
  return prepareHubSpotMaterials(profile, options, ({views, identityExtent: _identityExtent, ...materials}) => {
    const {declared} = options.construction.prepareDeclaration(views);
    return Object.freeze({...materials, declared});
  });
}

export async function loadInstalledHubSpotSource(profile: unknown, {moon, providerMoon: provider,
  runtimeBundleCid, resolveSecret, installation, construction}: LoadOptions) {
  if (construction === undefined || typeof construction.prepareNativeInput !== 'function' ||
      typeof construction.prepareDeclaration !== 'function' || typeof construction.openRowSite !== 'function' ||
      typeof construction.prepareReadTarget !== 'function' ||
      typeof construction.createRowSource !== 'function' || typeof construction.sourceReaderImplementation !== 'function' ||
      typeof construction.createSourceReader !== 'function' || construction.configurationReader === undefined) {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const prepareTargets = construction.prepareReadTarget;
  const capacityMethods = Object.freeze(Object.fromEntries([
    'clientProgramHubSpotMetadataIdentityCapacity', 'clientProgramHubSpotReadTargetCapacity',
    'clientProgramHubSpotReadSequenceBounds',
  ].map(name => {
    const method = Object.getOwnPropertyDescriptor(moon, name);
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') fail('HubSpotSourceConstructionUnavailable');
    return [name, (...args: unknown[]) => Reflect.apply(method.value, moon, args)];
  }))) as CapacityMethods;
  const {installed, siteProfile, catalogs, declared, metadataCid} =
    await prepareHubSpotMaterials(profile, {moon, providerMoon: provider, construction}, ({views, ...materials}) => {
      const {objects, bodyUnits, stringUnits} = materials.identityExtent;
      const identity = construction.prepareNativeInput(Object.freeze({
        capacity: () => checked(capacityMethods.clientProgramHubSpotMetadataIdentityCapacity(
          objects, bodyUnits, stringUnits)),
        project: () => Object.freeze({metadataCid: cid(materials.metadata)}),
      }));
      const {declared} = construction.prepareDeclaration(views);
      return Object.freeze({...materials, declared, metadataCid: identity.metadataCid});
    });
  const {limits} = installed;
  const readers = construction.configurationReader;
  const connection = `hubspot:${installed.connectorId}`;
  let targetFields = 0n, objectUnits = 0;
  for (const {resource, objectType} of installed.resources) {
    const view = declared.views.find(value => value.resource === resource);
    if (view === undefined) fail('ForeignHubSpotReadPreparation');
    targetFields += BigInt(view.fields.length);
    objectUnits = Math.max(objectUnits, objectType.length);
  }
  // The pre-declaration native constructor already retained the digest and
  // removed its identity workspace. Retain only the new target/field records.
  const targets = Reflect.apply(prepareTargets, construction, [Object.freeze({
    capacity: () => checked(capacityMethods.clientProgramHubSpotReadTargetCapacity(
      installed.resources.length, targetFields)),
    project: () => Object.freeze(installed.resources.map(({resource, objectType}) => Object.freeze({
      version: 'actql-installed-hubspot-target/0.1', apiOrigin: siteProfile.apiOrigin,
      portalId: installed.portalId, resource, objectType, metadataCid,
      fields: Object.freeze([...declared.views.find(value => value.resource === resource)!.fields]),
    }))),
  })]) as readonly Target[];
  const target = (resource: string, fields: readonly string[]) => {
    const original = targets.find(value => value.resource === resource);
    if (original === undefined) fail('ForeignHubSpotReadPreparation');
    return Object.freeze({...original, fields: Object.freeze([...fields])});
  };
  const admitsApprovalTarget = (binding: Readonly<{fields?: unknown}> | null | undefined, resource: string) => {
    const original = targets.find(value => value.resource === resource);
    return original !== undefined && Array.isArray(binding?.fields) &&
      new Set(binding.fields).size === binding.fields.length && binding.fields.every(field => original.fields.includes(field)) &&
      canonical(binding) === canonical(target(resource, binding.fields));
  };
  if (siteProfile.caPath !== undefined && typeof readers.readOriginalBytes !== 'function') fail('HubSpotSourceConstructionUnavailable');
  const ca = siteProfile.caPath === undefined ? undefined : await readers.readOriginalBytes!(siteProfile.caPath);
  let fieldUnits = 0n;
  for (const view of declared.views) {
    let units = 0n;
    for (const field of view.fields) units += BigInt(field.length);
    if (units > fieldUnits) fieldUnits = units;
  }
  const bounds = capacityMethods.clientProgramHubSpotReadSequenceBounds(limits.maxRequests,
    limits.maxResponseBytes, siteProfile.apiOrigin.length, installed.portalId.length, objectUnits, fieldUnits);
  if (runtimeIsError(bounds)) fail('HubSpotManagedAggregateUnavailable');
  const geometry = checked(bounds);
  const totalBytes = runtimeField(geometry, 0) as number, targetUnits = runtimeField(geometry, 1);
  if (!Number.isSafeInteger(totalBytes) || totalBytes < 1 || totalBytes > 2147483647 ||
      !positive(targetUnits)) fail('HubSpotManagedAggregateUnavailable');
  const readerLimits = Object.freeze({maxResponseBytes: limits.maxResponseBytes,
    maxTotalResponseBytes: totalBytes, maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
    maxRows: limits.perPage, maxTotalRows: limits.maxRows, maxPages: limits.maxRequests, pageSize: limits.perPage,
    maxCursorBytes: limits.maxCursorUnits, maxIdentityBytes: limits.maxResponseBytes, maxTargetBytes: targetUnits,
    maxValueNodes: limits.maxValueNodes, maxValueTextBytes: limits.maxValueTextBytes,
    maxRowsWireBytes: limits.maxRowsWireBytes, maxRowsWireNodes: limits.maxRowsWireNodes,
    maxRowsWireDepth: limits.maxRowsWireDepth, maxSecretBytes: limits.maxSecretBytes});
  const quote = Object.getOwnPropertyDescriptor(moon, 'clientProgramHubSpotSourceReaderObservedCapacity');
  if (!quote || !Object.hasOwn(quote, 'value') || typeof quote.value !== 'function') fail('HubSpotManagedCapacityUnavailable');
  const readerBounds = Object.freeze(installedJsonSourceReaderLimitNames.map(name => readerLimits[name]));
  const protocolBounds = Object.freeze(limitKeys.slice(0, 16).map(name => limits[name]));
  const columnCount = Math.max(...declared.views.map(view => view.fields.length));
  const capacityFor = (bodies: readonly number[], _received?: bigint, propertyGeometry: readonly number[] = Object.freeze([])) => {
    const capacity = Reflect.apply(quote.value, moon,
      [readerBounds, columnCount, limits.maxSecretBytes, protocolBounds, targetUnits, bodies, propertyGeometry]);
    if (capacity === undefined || capacity === null) fail('HubSpotManagedCapacityUnavailable');
    return capacity;
  };
  const implementation = construction.sourceReaderImplementation({limits: readerLimits, columnCount,
    readSequenceConstruction: Object.freeze({capacity: capacityFor([]), originalLimits: limits,
      maxQueryBytes: targetUnits,
      sequence: Object.freeze({operation: HUBSPOT_OBJECT_LIST_OPERATION, maxUses: limits.maxPages,
        children: Object.freeze([
          Object.freeze({operation: HUBSPOT_ACCOUNT_DETAILS_OPERATION,
            resource: installed.metadataResources.account, maxUses: limits.maxRequests}),
          Object.freeze({operation: HUBSPOT_PROPERTIES_READ_OPERATION,
            resource: installed.metadataResources.properties, maxUses: limits.maxRequests}),
        ])})})});
  const {authorization} = await construction.openRowSite({
    profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: installed.accountConfigurationWire, connection, ca, admitsApprovalTarget,
    runAcquisitionLimits: implementation.runAcquisitionLimits,
    responseHeaders: installation?.responseHeaders ?? [], resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  const providerReader = construction.createSourceReader({implementation, prepareReadSequence(input: Selection) {
    const catalog = catalogs.get(input.resource), objectType = targets.find(value => value.resource === input.resource)?.objectType;
    if (catalog === undefined || input.responseBorrow === undefined || input.originalAuthorization === undefined) {
      fail('ForeignHubSpotReadPreparation');
    }
    return prepareHubSpotManagedSequence({moon: provider, originalPortalId: installed.portalId,
      originalCatalog: catalog, objectType: objectType!, properties: input.columns.filter(name => name !== 'id'), limits,
      responseCapacity: capacityFor});
  }});
  if (providerReader.capacity !== implementation.capacity) fail('HubSpotManagedImplementationMismatch');
  return await construction.createRowSource({readOperation: HUBSPOT_OBJECT_LIST_OPERATION,
    physicalTarget: targets, providerReader, bindingCid: siteBinding(
      authorization.context.contextCid, runtimeBundleCid, metadataCid, siteProfile),
    limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxResponseBytes,
      maxPageRows: limits.perPage, maxCaptureRows: limits.maxRows}});
}
