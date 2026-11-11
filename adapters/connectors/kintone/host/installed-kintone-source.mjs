// The installation supplies original Form DATA and vendor I/O. Existing
// Account/Credential Site/Row Source owners keep authority, capture and cleanup.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

import {KINTONE_FORM_READ_OPERATION, KINTONE_RECORD_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {createKintoneManagedSequence} from '../site/kintone-managed-sequence.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {invocationScopeFields} from '../../../host-common/owned-invocation-context.mjs';

export const INSTALLED_KINTONE_SOURCE_VERSION = 'actql-installed-kintone-source/0.1';
export const INSTALLED_KINTONE_SITE_VERSION = 'actql-installed-kintone-site/0.1';
const registration = 'kintone', revision = 'kintone/0.1';
const profileKeys = ['version', 'connectorId', 'appId', 'resource', 'formResource',
  'fieldCodes', 'metadataPath', 'siteProfilePath', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'siteGeneration', 'siteKey', 'tokenEnvironment'];
const limitKeys = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameUnits',
  'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes', 'maxValueDepth',
  'maxValueTextBytes', 'maxContractPairs', 'maxRequestBytes', 'maxRequests',
  'maxPages', 'perPage', 'maxSecretBytes', 'maxRows', 'maxDeclarationBytes', 'maxDeclarationNodes'];
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledKintoneSourceProfile(profile) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_KINTONE_SOURCE_VERSION ||
      !text(profile.connectorId) || !/^[1-9][0-9]*$/u.test(profile.appId ?? '') ||
      !text(profile.resource) || !text(profile.formResource) || profile.resource === profile.formResource ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !text(profile.accountConfigurationWire) || !closed(profile.limits, limitKeys) ||
      !limitKeys.every(key => positive(profile.limits[key])) ||
      profile.limits.perPage > 500 || profile.limits.perPage > profile.limits.maxRows ||
      profile.limits.maxPages > profile.limits.maxRequests || profile.limits.maxRequests > 10000 ||
      !Array.isArray(profile.fieldCodes) || profile.fieldCodes.length > 998 ||
      !profile.fieldCodes.every(text) || new Set(profile.fieldCodes).size !== profile.fieldCodes.length ||
      profile.fieldCodes.some(code => code === '$id' || code === '$revision')) {
    fail('InvalidInstalledKintoneSourceProfile');
  }
  return Object.freeze({...profile, fieldCodes: Object.freeze([...profile.fieldCodes]),
    limits: Object.freeze({...profile.limits})});
}

function checkSite(value) {
  const {caPath, guestSpaceId, ...site} = value ?? {};
  let origin;
  try {origin = new URL(site.apiOrigin);} catch { /* Closed refusal below. */ }
  if (!closed(site, siteKeys) || site.version !== INSTALLED_KINTONE_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== site.apiOrigin ||
      !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(key => text(site[key])) ||
      !absolute(site.credentialPrivateKeyPath) || !absolute(site.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      !Number.isSafeInteger(site.siteGeneration) || site.siteGeneration < 0 ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(site.tokenEnvironment)) fail('InvalidInstalledKintoneSite');
  return Object.freeze({...site, ...(caPath === undefined ? {} : {caPath}),
    ...(guestSpaceId === undefined ? {} : {guestSpaceId})});
}

function metadataBodyBytes(encoded, maxBytes) {
  if (typeof encoded !== 'string' || encoded.length > Math.ceil(maxBytes / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(encoded)) {
    fail('InvalidInstalledKintoneMetadata');
  }
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0;
  const bytes = encoded.length / 4 * 3 - padding;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (bytes > maxBytes || padding !== 0 &&
      (alphabet.indexOf(encoded[encoded.length - padding - 1]) & (padding === 2 ? 15 : 3)) !== 0) {
    fail('InvalidInstalledKintoneMetadata');
  }
  return bytes;
}

function decodeMetadataBody(encoded, maxBytes) {
  const body = Buffer.from(encoded, 'base64');
  if (body.byteLength > maxBytes || body.toString('base64') !== encoded) fail('InvalidInstalledKintoneMetadata');
  return body;
}

async function inputs(profile, readers) {
  const installed = checkInstalledKintoneSourceProfile(profile);
  const site = checkSite(await readers.readJson(installed.siteProfilePath));
  const metadata = await readers.readJson(installed.metadataPath);
  if (!closed(metadata, ['version', 'connectorId', 'appId', 'apiOrigin', 'formBody']) ||
      metadata.version !== 'actql-kintone-record-metadata/0.1' ||
      metadata.connectorId !== installed.connectorId || metadata.appId !== installed.appId ||
      metadata.apiOrigin !== site.apiOrigin || typeof metadata.formBody !== 'string' ||
      metadata.formBody.length > Math.ceil(installed.limits.maxResponseBytes / 3) * 4) {
    fail('InvalidInstalledKintoneMetadata');
  }
  metadataBodyBytes(metadata.formBody, installed.limits.maxResponseBytes);
  return {installed, site, metadata};
}

export async function installedKintoneSourceIdentityParts(profile, providerProfile, readJson, _entry, {configurationReader} = {}) {
  const readers = captureConfigurationReaders(configurationReader, readJson,
    () => fail('KintoneSourceConstructionUnavailable'));
  const {site, metadata} = await inputs(providerProfile, readers);
  if (site.caPath !== undefined && configurationReader !== undefined && readers.readOriginalBytes === undefined) {
    fail('KintoneSourceConstructionUnavailable');
  }
  const ca = site.caPath === undefined ? undefined : await (configurationReader === undefined
    ? readFile(site.caPath) : readers.readOriginalBytes(site.caPath));
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    site, {metadataCid: cid(metadata), ...(ca === undefined ? {} : {
      caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

// The same initialization owner prepares original Form/declaration DATA for
// Source and Effect. No Site, credential resolution or physical read is opened.
export async function prepareInstalledKintoneMaterials(profile, {moon, construction, runtimePorts = []}) {
  if (construction === undefined || typeof construction.prepareNativeDeclaration !== 'function' ||
      construction.configurationReader === undefined || !Array.isArray(runtimePorts) ||
      runtimePorts.some(name => typeof name !== 'string')) fail('KintoneSourceConstructionUnavailable');
  const readers = construction.configurationReader;
  const {installed, site: siteProfile, metadata} = await inputs(profile, readers);
  const {limits} = installed;
  // A runtime with no genuine typed bridge refuses before Site/key/I/O entry.
  for (const name of ['ReadDeclarationConstructionCapacity', 'MetadataIdentityCapacity',
    'FormLimits', 'PageLimits', 'ValueLimits', 'DeclarationLimits', 'ProjectForm', 'DeclareRecords',
    'RecordDeclaration', ...runtimePorts]) {
    if (typeof moon?.[`clientProgramKintone${name}`] !== 'function') fail('KintoneOriginalReadUnavailable');
  }
  const formLimits = moon.clientProgramKintoneFormLimits(limits.maxResponseBytes, limits.maxNodes,
    limits.maxDepth, limits.maxFields, limits.maxNameUnits);
  const valueLimits = moon.clientProgramKintoneValueLimits(limits.maxColumns, limits.maxNameUnits,
    limits.maxValueNodes, limits.maxValueDepth, limits.maxValueTextBytes);
  const pageLimits = moon.clientProgramKintonePageLimits(limits.maxResponseBytes, limits.maxNodes,
    limits.maxDepth, limits.perPage, limits.maxColumns, limits.maxCells, limits.maxTableRows);
  const declarationLimits = moon.clientProgramKintoneDeclarationLimits(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes, limits.maxDepth, 1, limits.maxColumns);
  const encoded = metadata.formBody, bodyBytes = metadataBodyBytes(encoded, limits.maxResponseBytes);
  const {original, declared, metadataCid} = construction.prepareNativeDeclaration(Object.freeze({
    capacity() {
      const base = moon.clientProgramKintoneReadDeclarationConstructionCapacity(bodyBytes, encoded.length,
        installed.fieldCodes.length, installed.fieldCodes.reduce((sum, value) => sum + value.length, 0),
        installed.appId.length, installed.resource.length, installed.connectorId.length, revision.length,
        formLimits, valueLimits, declarationLimits);
      if (base === undefined || base === null) fail('KintoneDeclarationCapacityUnavailable');
      const complete = moon.clientProgramKintoneMetadataIdentityCapacity(base, encoded.length,
        installed.connectorId.length, installed.appId.length, siteProfile.apiOrigin.length);
      if (complete === undefined || complete === null) fail('KintoneDeclarationCapacityUnavailable');
      return complete;
    },
    project() {
      const form = decodeMetadataBody(encoded, limits.maxResponseBytes);
      const formCatalog = checked(moon.clientProgramKintoneProjectForm(form, installed.appId, formLimits));
      const original = checked(moon.clientProgramKintoneDeclareRecords(formCatalog, undefined,
        installed.fieldCodes, installed.connectorId, revision, installed.resource, valueLimits, declarationLimits));
      return Object.freeze({form, formCatalog, original, metadataCid: cid(metadata),
        declaration: moon.clientProgramKintoneRecordDeclaration(original)});
    },
  }));
  return Object.freeze({installed, siteProfile, metadata, original, declared, metadataCid,
    formLimits, valueLimits, pageLimits, declarationLimits});
}

export function installedKintoneSiteBinding({contextCid, runtimeBundleCid, metadataCid, site}) {
  return cid({version: 'actql-installed-kintone-binding/0.1', contextCid, runtimeBundleCid, metadataCid, site});
}

export async function loadInstalledKintoneSource(profile, {moon, runtimeBundleCid, resolveSecret, installation, construction}) {
  if (construction === undefined || typeof construction.prepareNativeDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' || typeof construction.createRowSource !== 'function' ||
      typeof construction.sourceReaderImplementation !== 'function' || typeof construction.createSourceReader !== 'function' ||
      construction.configurationReader === undefined) fail('KintoneSourceConstructionUnavailable');
  const {installed, siteProfile, metadata, original, declared, metadataCid,
    formLimits, valueLimits, pageLimits} = await prepareInstalledKintoneMaterials(profile, {moon, construction,
      runtimePorts: ['ManagedSourceReaderCapacity', 'ManagedResponseCapacity', 'AdoptManagedBorrow',
        'ManagedColumns', 'ManagedFormRequest', 'ManagedPageRequest', 'ManagedRecheckForm',
        'ManagedProjectPage', 'ManagedComplete', 'ManagedRetire']});
  const {limits} = installed;
  const readers = construction.configurationReader;
  const connection = `kintone:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-kintone-target/0.1',
    apiOrigin: siteProfile.apiOrigin, appId: installed.appId,
    ...(siteProfile.guestSpaceId === undefined ? {} : {guestSpaceId: siteProfile.guestSpaceId}),
    resource, metadataCid, fields: Object.freeze([...fields])});
  const admitsApprovalTarget = (binding, resource) => resource === installed.resource &&
    Array.isArray(binding?.fields) && new Set(binding.fields).size === binding.fields.length &&
    binding.fields.every(field => declared.views[0].fields.includes(field)) &&
    canonical(binding) === canonical(target(resource, binding.fields));
  // All original operator limits remain independent: record pages, aggregate
  // physical responses (including Form), rows and native value budgets.
  // The aggregate is represented by the existing Int port; never clamp it.
  const totalBytes = BigInt(limits.maxRequests) * BigInt(limits.maxResponseBytes);
  if (totalBytes > 2147483647n) fail('KintoneManagedAggregateUnavailable');
  const pathUnits = (siteProfile.guestSpaceId === undefined ? '/k/v1/'.length
    : '/k/guest/'.length + siteProfile.guestSpaceId.length + '/v1/'.length) + 'app/form/fields.json'.length;
  if (!positive(pathUnits)) fail('KintoneManagedAggregateUnavailable');
  const columnCount = declared.views[0].fields.length;
  const readerLimits = Object.freeze({maxResponseBytes: limits.maxResponseBytes,
    maxTotalResponseBytes: Number(totalBytes), maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
    maxRows: limits.perPage, maxTotalRows: limits.maxRows, maxPages: limits.maxRequests,
    pageSize: limits.perPage, maxCursorBytes: limits.maxResponseBytes,
    maxIdentityBytes: limits.maxResponseBytes, maxTargetBytes: pathUnits,
    maxValueNodes: limits.maxValueNodes, maxValueTextBytes: limits.maxValueTextBytes,
    maxRowsWireBytes: limits.maxResponseBytes, maxRowsWireNodes: limits.maxValueNodes,
    maxRowsWireDepth: limits.maxValueDepth, maxSecretBytes: limits.maxSecretBytes});
  const capacityMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramKintoneManagedSourceReaderCapacity');
  const responseMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramKintoneManagedResponseCapacity');
  if (!capacityMethod || !Object.hasOwn(capacityMethod, 'value') || typeof capacityMethod.value !== 'function' ||
      !responseMethod || !Object.hasOwn(responseMethod, 'value') || typeof responseMethod.value !== 'function') {
    fail('KintoneOriginalReadUnavailable');
  }
  const capacity = Reflect.apply(capacityMethod.value, moon, [
    installedJsonSourceReaderLimitNames.map(name => readerLimits[name]), limits.maxSecretBytes,
    original, pageLimits, valueLimits, limits.maxContractPairs, limits.perPage, limits.maxRequestBytes,
    siteProfile.apiOrigin, installed.resource, siteProfile.guestSpaceId ?? '']);
  if (capacity === undefined || capacity === null) fail('KintoneManagedCapacityUnavailable');
  const sequence = Object.freeze({operation: KINTONE_RECORD_READ_OPERATION, maxUses: limits.maxPages,
    children: Object.freeze([Object.freeze({operation: KINTONE_FORM_READ_OPERATION,
      resource: installed.formResource, maxUses: limits.maxRequests})])});
  const implementation = construction.sourceReaderImplementation({limits: readerLimits, columnCount,
    readSequenceConstruction: Object.freeze({capacity, originalLimits: limits, sequence,
      maxRequestBytes: limits.maxRequestBytes})});
  if (siteProfile.caPath !== undefined && typeof readers.readOriginalBytes !== 'function') fail('KintoneSourceConstructionUnavailable');
  const ca = siteProfile.caPath === undefined ? undefined : await readers.readOriginalBytes(siteProfile.caPath);
  const {site, authorization} = await construction.openRowSite({
    profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: installed.accountConfigurationWire, connection, ca, admitsApprovalTarget,
    runAcquisitionLimits: implementation.runAcquisitionLimits, secretPresentation: 'kintone-api-token',
    responseHeaders: installation?.responseHeaders ?? [], resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  const authorize = authorization.authorize, issueGrant = site.issueReadGrant;
  const providerReader = construction.createSourceReader({implementation,
    prepareReadSequence(input) {
      if (input.resource !== installed.resource || input.responseBorrow === undefined ||
          input.originalAuthorization === undefined) fail('ForeignKintoneReadPreparation');
      const scope = invocationScopeFields(input.originalAuthorization.scope, site.credential.control);
      let formGrant, signal, formUses = 0;
      // Capture one original callback per reader. The generic separate-resource
      // binding retains this SAME callback and surrounds it with root current.
      const verifyCurrent = async () => {
        if (signal === undefined) fail('KintoneFormCurrentUnavailable');
        signal.throwIfAborted();
        const decision = await Reflect.apply(authorize, authorization, ['acquisition',
          {connection, resource: installed.formResource, operation: 'read'},
          {subjectCid: cid({binding: target(input.resource, input.columns), operation: KINTONE_FORM_READ_OPERATION}), signal}]);
        signal.throwIfAborted();
        if (decision?.action !== 'dispatch') fail('KintoneFormReadDenied');
        return decision;
      };
      const authorizeForm = async (selected, selectedSignal) => {
        if (selected !== input || signal !== undefined && signal !== selectedSignal) fail('ForeignKintoneReadPreparation');
        signal = selectedSignal;
        if (formUses >= limits.maxRequests) fail('KintoneFormReadUseLimit');
        const index = formUses++;
        const decision = await verifyCurrent();
        if (formGrant === undefined) {
          formGrant = Reflect.apply(issueGrant, site, [{operation: KINTONE_FORM_READ_OPERATION,
            decision, resource: installed.formResource, runInvocationCid: scope.runInvocationCid,
            dispatchRequestCid: scope.dispatchRequestCid, maxUses: limits.maxRequests}]);
        }
        return Object.freeze({originalAuthorization: formGrant,
          authorization: Object.freeze({...formGrant, useId: `${scope.runInvocationCid}-form-${index}`}),
          verifyCurrent});
      };
      // This callback runs only after the normal generic owner has reserved
      // the complete selected capacity and bound the SAME response borrow.
      return createKintoneManagedSequence({moon, original,
        bounds: Object.freeze({form: formLimits, page: pageLimits, values: valueLimits}),
        limits, guestSpaceId: siteProfile.guestSpaceId, authorizeForm, baseCapacity: capacity,
        capacityForResponse(read, kind, bytes, previous) {
          return Reflect.apply(responseMethod.value, moon, [read, previous, bytes,
            kind === 'form', formLimits]);
        }})(input);
    }});
  if (providerReader.capacity !== implementation.capacity) fail('KintoneManagedImplementationMismatch');
  return await construction.createRowSource({readOperation: KINTONE_RECORD_READ_OPERATION,
    physicalTarget: target, providerReader,
    bindingCid: installedKintoneSiteBinding({contextCid: authorization.context.contextCid,
      runtimeBundleCid, metadataCid, site: siteProfile}),
    limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxResponseBytes,
      maxPageRows: limits.perPage, maxCaptureRows: limits.maxRows}});
}
