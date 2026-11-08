// A HubSpot installation supplies original metadata and physical reads only.
// The standard Host owns the declaration, Account gate, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {types} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

import {invocationScopeFields} from '../../../host-common/owned-invocation-context.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {prepareHubSpotManagedSequence} from '../site/hubspot-managed-sequence.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION,
  HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';

export const INSTALLED_HUBSPOT_SOURCE_VERSION = 'actql-installed-hubspot-source/0.1';
export const INSTALLED_HUBSPOT_SITE_VERSION = 'actql-installed-hubspot-site/0.1';
const registration = 'hubspot', revision = 'hubspot/0.1';
const profileKeys = ['version', 'connectorId', 'portalId', 'resources', 'metadataPath',
  'siteProfilePath', 'metadataResources', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'siteGeneration', 'siteKey', 'tokenEnvironment'];
const limitKeys = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxPages', 'maxRows', 'maxRequests', 'perPage', 'maxColumns',
  'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth', 'maxObjects', 'maxDeclarationBytes',
  'maxDeclarationNodes', 'maxSecretBytes'];
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const closedMetadata = (value, keys) => !types.isProxy(value) && closed(value, keys) &&
  Object.getPrototypeOf(value) === Object.prototype && keys.every(key =>
    Object.hasOwn(Object.getOwnPropertyDescriptor(value, key), 'value'));
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledHubSpotSourceProfile(profile) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_HUBSPOT_SOURCE_VERSION ||
      !text(profile.connectorId) || typeof profile.portalId !== 'string' || !/^[1-9][0-9]{0,10}$/u.test(profile.portalId) ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !text(profile.accountConfigurationWire) || !closed(profile.limits, limitKeys) ||
      !limitKeys.every(key => positive(profile.limits[key])) ||
      !closed(profile.metadataResources, ['account', 'properties']) ||
      !Object.values(profile.metadataResources).every(text) ||
      profile.metadataResources.account === profile.metadataResources.properties ||
      !Array.isArray(profile.resources) || profile.resources.length === 0 ||
      profile.resources.length > profile.limits.maxObjects ||
      !profile.resources.every(value => closed(value, ['resource', 'objectType']) &&
        text(value.resource) && text(value.objectType) &&
        value.objectType !== '.' && value.objectType !== '..') ||
      new Set(profile.resources.map(value => value.resource)).size !== profile.resources.length ||
      profile.resources.some(value => Object.values(profile.metadataResources).includes(value.resource)) ||
      profile.limits.maxPages > profile.limits.maxRequests ||
      profile.limits.perPage > profile.limits.maxRows) fail('InvalidInstalledHubSpotSourceProfile');
  return Object.freeze({...profile, resources: Object.freeze(profile.resources.map(value => Object.freeze({...value}))),
    limits: Object.freeze({...profile.limits}), metadataResources: Object.freeze({...profile.metadataResources})});
}

function checkSite(site) {
  const {caPath, ...rest} = site ?? {};
  let origin;
  try {origin = new URL(rest.apiOrigin);} catch { /* Closed rejection below. */ }
  if (!closed(rest, siteKeys) || rest.version !== INSTALLED_HUBSPOT_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(key => text(rest[key])) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !Number.isSafeInteger(rest.siteGeneration) || rest.siteGeneration < 0 ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment)) fail('InvalidInstalledHubSpotSite');
  return Object.freeze({...rest, ...(caPath === undefined ? {} : {caPath})});
}

function metadataBodyBytes(encoded, maxBytes) {
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

function decodeMetadataBody(encoded, maxBytes) {
  const body = Buffer.from(encoded, 'base64');
  if (body.byteLength > maxBytes || body.toString('base64') !== encoded) fail('InvalidInstalledHubSpotMetadata');
  return body;
}

async function readInputs(profile, readers) {
  const installed = checkInstalledHubSpotSourceProfile(profile);
  const site = checkSite(await readers.readJson(installed.siteProfilePath));
  const metadata = await readers.readJson(installed.metadataPath);
  if (!closedMetadata(metadata, ['version', 'connectorId', 'portalId', 'apiOrigin', 'accountBody', 'objects']) ||
      metadata.version !== 'actql-hubspot-read-metadata/0.1' ||
      metadata.connectorId !== installed.connectorId || metadata.portalId !== installed.portalId ||
      metadata.apiOrigin !== site.apiOrigin || !Array.isArray(metadata.objects) || types.isProxy(metadata.objects) ||
      Object.getPrototypeOf(metadata.objects) !== Array.prototype ||
      Reflect.ownKeys(metadata.objects).length !== metadata.objects.length + 1 ||
      metadata.objects.length !== installed.resources.length) fail('InvalidInstalledHubSpotMetadata');
  metadataBodyBytes(metadata.accountBody, installed.limits.maxResponseBytes);
  // Observe the closed original's identity extent during this SAME validation,
  // not by serializing, parsing or walking the metadata again. The graph has
  // one root/array punctuation prefix and eight punctuation tokens/object.
  // Base64 is exact ASCII; six units bound escaping of each other observed
  // String unit. Fixed JSON vocabulary is independent of policy ceilings.
  let identityNodes = 15n;
  let identityUnits = 256n + BigInt(metadata.accountBody.length) + 6n * BigInt(
    metadata.version.length + metadata.connectorId.length + metadata.portalId.length + metadata.apiOrigin.length);
  const objects = new Map();
  for (let index = 0; index < metadata.objects.length; index++) {
    const entry = Object.getOwnPropertyDescriptor(metadata.objects, index);
    if (!entry || !Object.hasOwn(entry, 'value')) fail('InvalidInstalledHubSpotMetadata');
    const object = entry.value;
    if (!closedMetadata(object, ['resource', 'objectType', 'propertiesBody']) ||
        objects.has(object.resource) || !installed.resources.some(value =>
          value.resource === object.resource && value.objectType === object.objectType)) {
      fail('InvalidInstalledHubSpotMetadata');
    }
    metadataBodyBytes(object.propertiesBody, installed.limits.maxResponseBytes);
    identityNodes += 8n;
    identityUnits += 128n + BigInt(object.propertiesBody.length) +
      6n * BigInt(object.resource.length + object.objectType.length);
    // Keep the same validated JSON originals, including the real reader's
    // objectType. Do not retain a digest of a still-mutable metadata graph.
    objects.set(object.resource, Object.freeze(object));
  }
  Object.freeze(metadata.objects);
  Object.freeze(metadata);
  return {installed, site, metadata, objects,
    identityExtent: Object.freeze({nodes: identityNodes, units: identityUnits})};
}

export async function installedHubSpotSourceIdentityParts(profile, providerProfile, readJson, _entry, {configurationReader} = {}) {
  const readers = captureConfigurationReaders(configurationReader, readJson,
    () => fail('HubSpotSourceConstructionUnavailable'));
  const {site, metadata} = await readInputs(providerProfile, readers);
  if (site.caPath !== undefined && configurationReader !== undefined && readers.readOriginalBytes === undefined) {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const ca = site.caPath === undefined ? undefined : await (configurationReader === undefined
    ? readFile(site.caPath) : readers.readOriginalBytes(site.caPath));
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)}, site,
    {metadataCid: cid(metadata), ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

function siteBinding(contextCid, runtimeBundleCid, metadataCid, site) {
  // Preserve the Source's complete original non-secret physical binding.
  // Each role supplies its own observed material; this issues no permission.
  return cid({version: 'actql-installed-hubspot-binding/0.1', contextCid,
    runtimeBundleCid, metadataCid, site});
}

export function installedHubSpotSiteBinding({contextCid, runtimeBundleCid, metadata, site}) {
  return siteBinding(contextCid, runtimeBundleCid, cid(metadata), site);
}

// Source and Effect borrow the same original metadata preparation. This does
// not open a Site, authorize a read/write, resolve a secret or send a request.
// Provider Catalogs stay in their original runtime; the Common declaration is
// produced separately by the existing parent construction owner.
async function prepareHubSpotMaterials(profile, {moon, providerMoon: provider, construction}, finish) {
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
  const catalogs = new Map(), views = [];
  for (const {resource, objectType} of installed.resources) {
    const encoded = objects.get(resource).propertiesBody;
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
          limits.maxNameUnits, limits.maxDeclarationBytes, limits.maxDeclarationNodes, limits.maxDepth));
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

export async function prepareInstalledHubSpotMaterials(profile, options) {
  return prepareHubSpotMaterials(profile, options, ({views, ...materials}) => {
    const {declared} = options.construction.prepareDeclaration(views);
    return Object.freeze({...materials, declared});
  });
}

export async function loadInstalledHubSpotSource(profile, {moon, providerMoon: provider,
  runtimeBundleCid, resolveSecret, installation, construction}) {
  if (construction === undefined || typeof construction.prepareNativeInput !== 'function' ||
      typeof construction.prepareDeclaration !== 'function' || typeof construction.openRowSite !== 'function' ||
      typeof construction.prepareReadTarget !== 'function' ||
      typeof construction.createRowSource !== 'function' || typeof construction.sourceReaderImplementation !== 'function' ||
      typeof construction.createSourceReader !== 'function' || construction.configurationReader === undefined) {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const prepareTargets = construction.prepareReadTarget;
  const targetCapacity = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceConstructionCapacity');
  if (!targetCapacity || !Object.hasOwn(targetCapacity, 'value') || typeof targetCapacity.value !== 'function') {
    fail('HubSpotSourceConstructionUnavailable');
  }
  const capacityMethods = Object.freeze(Object.fromEntries([
    'clientProgramInstalledProfileConstructionCapacities', 'clientProgramComposeInstalledSourceConstructionCapacity',
    'clientProgramSerializationCapacityBytes', 'clientProgramRowSourceProviderCapacity',
  ].map(name => {
    const method = Object.getOwnPropertyDescriptor(moon, name);
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') fail('HubSpotSourceConstructionUnavailable');
    return [name, (...args) => Reflect.apply(method.value, moon, args)];
  })));
  const {installed, siteProfile, catalogs, declared, metadataCid} =
    await prepareHubSpotMaterials(profile, {moon, providerMoon: provider, construction}, ({views, ...materials}) => {
      const {nodes, units} = materials.identityExtent;
      const identity = construction.prepareNativeInput(Object.freeze({
        capacity() {
          const zero = checked(Reflect.apply(targetCapacity.value, moon, [0n, 0n, 0n, 0n, 0n, 0n]));
          const [profile] = checked(capacityMethods.clientProgramInstalledProfileConstructionCapacities(nodes, units));
          const peak = checked(capacityMethods.clientProgramComposeInstalledSourceConstructionCapacity(zero, [profile]));
          const output = checked(Reflect.apply(targetCapacity.value, moon,
            [2n, 71n, 0n, 2n, 71n, 3n * units + 128n]));
          const outputBytes = capacityMethods.clientProgramSerializationCapacityBytes(output);
          const identityBytes = capacityMethods.clientProgramSerializationCapacityBytes(peak);
          return capacityMethods.clientProgramRowSourceProviderCapacity(runtimeField(outputBytes, 0),
            runtimeField(outputBytes, 1) + runtimeField(identityBytes, 1));
        },
        project: () => Object.freeze({metadataCid: cid(materials.metadata)}),
      }));
      const {declared} = construction.prepareDeclaration(views);
      return Object.freeze({...materials, declared, metadataCid: identity.metadataCid});
    });
  const {limits} = installed;
  const readers = construction.configurationReader;
  const connection = `hubspot:${installed.connectorId}`;
  // Same existing constructor and Core quantity as the REST DATA entrance.
  // Only target records/ordered field references are new; original strings
  // and the validated metadata remain borrowed, not copied or re-parsed.
  let slots = 1n;
  for (const {resource} of installed.resources) {
    const view = declared.views.find(value => value.resource === resource);
    if (view === undefined) fail('ForeignHubSpotReadPreparation');
    slots += 10n + BigInt(view.fields.length);
  }
  // The pre-declaration native constructor already retained the digest and
  // removed its identity workspace. Retain only the new target/field records.
  const targets = Reflect.apply(prepareTargets, construction, [Object.freeze({
    capacity: () => checked(Reflect.apply(targetCapacity.value, moon, [slots, 0n, 0n, slots, 0n, 0n])),
    project: () => Object.freeze(installed.resources.map(({resource, objectType}) => Object.freeze({
      version: 'actql-installed-hubspot-target/0.1', apiOrigin: siteProfile.apiOrigin,
      portalId: installed.portalId, resource, objectType, metadataCid,
      fields: Object.freeze([...declared.views.find(value => value.resource === resource).fields]),
    }))),
  })]);
  const target = (resource, fields) => {
    const original = targets.find(value => value.resource === resource);
    if (original === undefined) fail('ForeignHubSpotReadPreparation');
    return Object.freeze({...original, fields: Object.freeze([...fields])});
  };
  const admitsApprovalTarget = (binding, resource) => {
    const original = targets.find(value => value.resource === resource);
    return original !== undefined && Array.isArray(binding?.fields) &&
      new Set(binding.fields).size === binding.fields.length && binding.fields.every(field => original.fields.includes(field)) &&
      canonical(binding) === canonical(target(resource, binding.fields));
  };
  if (siteProfile.caPath !== undefined && typeof readers.readOriginalBytes !== 'function') fail('HubSpotSourceConstructionUnavailable');
  const ca = siteProfile.caPath === undefined ? undefined : await readers.readOriginalBytes(siteProfile.caPath);
  const totalBytes = BigInt(limits.maxRequests) * BigInt(limits.maxResponseBytes);
  const targetUnits = 1024 + 6 * (siteProfile.apiOrigin.length + installed.portalId.length +
    Math.max(...installed.resources.map(value => value.objectType.length)) +
    Math.max(...declared.views.map(view => view.fields.reduce((n, field) => n + field.length, 0))));
  if (totalBytes > 2147483647n || !positive(targetUnits)) fail('HubSpotManagedAggregateUnavailable');
  const readerLimits = Object.freeze({maxResponseBytes: limits.maxResponseBytes,
    maxTotalResponseBytes: Number(totalBytes), maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
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
  const capacityFor = (bodies, _received, propertyGeometry = Object.freeze([])) => {
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
  const {site, authorization} = await construction.openRowSite({
    profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: installed.accountConfigurationWire, connection, ca, admitsApprovalTarget,
    runAcquisitionLimits: implementation.runAcquisitionLimits,
    responseHeaders: installation?.responseHeaders ?? [], resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  const providerReader = construction.createSourceReader({implementation, prepareReadSequence(input) {
    const catalog = catalogs.get(input.resource), objectType = targets.find(value => value.resource === input.resource)?.objectType;
    if (catalog === undefined || input.responseBorrow === undefined || input.originalAuthorization === undefined) {
      fail('ForeignHubSpotReadPreparation');
    }
    const scope = invocationScopeFields(input.originalAuthorization.scope, site.credential.control);
    const grants = new Map();
    const authorizeMetadata = async (operation, index, signal) => {
      const resource = operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION ? installed.metadataResources.account
        : operation === HUBSPOT_PROPERTIES_READ_OPERATION ? installed.metadataResources.properties
        : fail('ForeignHubSpotReadOperation');
      let original = grants.get(operation);
      if (original === undefined) {
        const verifyCurrent = async () => {
          signal.throwIfAborted();
          const decision = await authorization.authorize('acquisition', {connection, resource, operation: 'read'},
            {subjectCid: cid({binding: target(input.resource, input.columns), operation}), signal});
          signal.throwIfAborted();
          if (decision?.action !== 'dispatch') fail('HubSpotMetadataReadDenied');
          return decision;
        };
        const decision = await verifyCurrent();
        const grant = site.issueReadGrant({operation, decision, resource,
          runInvocationCid: scope.runInvocationCid, dispatchRequestCid: scope.dispatchRequestCid,
          maxUses: limits.maxRequests});
        original = Object.freeze({grant, verifyCurrent});grants.set(operation, original);
      } else await original.verifyCurrent();
      return Object.freeze({originalAuthorization: original.grant,
        authorization: Object.freeze({...original.grant, useId: `${scope.runInvocationCid}-metadata-${index}`}),
        verifyCurrent: original.verifyCurrent});
    };
    return prepareHubSpotManagedSequence({moon: provider, originalPortalId: installed.portalId,
      originalCatalog: catalog, objectType, properties: input.columns.filter(name => name !== 'id'), limits,
      authorizeMetadata, responseCapacity: capacityFor});
  }});
  if (providerReader.capacity !== implementation.capacity) fail('HubSpotManagedImplementationMismatch');
  return await construction.createRowSource({readOperation: HUBSPOT_OBJECT_LIST_OPERATION,
    physicalTarget: targets, providerReader, bindingCid: siteBinding(
      authorization.context.contextCid, runtimeBundleCid, metadataCid, siteProfile),
    limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxResponseBytes,
      maxPageRows: limits.perPage, maxCaptureRows: limits.maxRows}});
}
