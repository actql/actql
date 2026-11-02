// The installation supplies original Form DATA and vendor I/O. Existing
// Account/Credential Site/Row Source owners keep authority, capture and cleanup.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

import {readKintoneRecords, KINTONE_FORM_READ_OPERATION,
  KINTONE_RECORD_READ_OPERATION} from '../site/kintone-record-read.mjs';

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

export async function loadInstalledKintoneSource(profile, {moon, runtimeBundleCid, resolveSecret, installation, construction}) {
  if (construction === undefined || typeof construction.prepareNativeDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' || typeof construction.createRowSource !== 'function' ||
      construction.configurationReader === undefined) fail('KintoneSourceConstructionUnavailable');
  const readers = construction.configurationReader;
  const {installed, site: siteProfile, metadata} = await inputs(profile, readers);
  const {limits} = installed;
  // A runtime with no genuine typed bridge refuses before Site/key/I/O entry.
  for (const name of ['ReadDeclarationConstructionCapacity', 'FormLimits', 'PageLimits', 'ValueLimits', 'DeclarationLimits',
    'ProjectForm', 'DeclareRecords', 'RecordDeclaration', 'PrepareRead', 'ReadAcquisition',
    'BorrowRead', 'BindReadCleanup', 'RecheckReadForm', 'AcceptReadPage', 'FormRequestBody',
    'PageRequestBody', 'PageNextCursor', 'RetireRead']) {
    if (typeof moon?.[`clientProgramKintone${name}`] !== 'function') fail('KintoneOriginalReadUnavailable');
  }
  const formLimits = moon.clientProgramKintoneFormLimits(limits.maxResponseBytes, limits.maxNodes,
    limits.maxDepth, limits.maxFields, limits.maxNameUnits);
  const valueLimits = moon.clientProgramKintoneValueLimits(limits.maxColumns, limits.maxNameUnits,
    limits.maxValueNodes, limits.maxValueDepth, limits.maxValueTextBytes);
  const declarationLimits = moon.clientProgramKintoneDeclarationLimits(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes, limits.maxDepth, 1, limits.maxColumns);
  const encoded = metadata.formBody, bodyBytes = metadataBodyBytes(encoded, limits.maxResponseBytes);
  const {original, declared} = construction.prepareNativeDeclaration(Object.freeze({
    capacity: () => moon.clientProgramKintoneReadDeclarationConstructionCapacity(bodyBytes, encoded.length,
      installed.fieldCodes.length, installed.fieldCodes.reduce((sum, value) => sum + value.length, 0),
      installed.appId.length, installed.resource.length, installed.connectorId.length, revision.length,
      formLimits, valueLimits, declarationLimits),
    project() {
      const form = decodeMetadataBody(encoded, limits.maxResponseBytes);
      const formCatalog = checked(moon.clientProgramKintoneProjectForm(form, installed.appId, formLimits));
      const original = checked(moon.clientProgramKintoneDeclareRecords(formCatalog, undefined,
        installed.fieldCodes, installed.connectorId, revision, installed.resource, valueLimits, declarationLimits));
      return Object.freeze({form, formCatalog, original, declaration: moon.clientProgramKintoneRecordDeclaration(original)});
    },
  }));
  const connection = `kintone:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-kintone-target/0.1',
    apiOrigin: siteProfile.apiOrigin, appId: installed.appId,
    ...(siteProfile.guestSpaceId === undefined ? {} : {guestSpaceId: siteProfile.guestSpaceId}),
    resource, metadataCid: cid(metadata), fields: Object.freeze([...fields])});
  const admitsApprovalTarget = (binding, resource) => resource === installed.resource &&
    Array.isArray(binding?.fields) && new Set(binding.fields).size === binding.fields.length &&
    binding.fields.every(field => declared.views[0].fields.includes(field)) &&
    canonical(binding) === canonical(target(resource, binding.fields));
  if (siteProfile.caPath !== undefined && typeof readers.readOriginalBytes !== 'function') fail('KintoneSourceConstructionUnavailable');
  const ca = siteProfile.caPath === undefined ? undefined : await readers.readOriginalBytes(siteProfile.caPath);
  const {site, authorization} = await construction.openRowSite({
    profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: installed.accountConfigurationWire, connection, ca, admitsApprovalTarget,
    responseHeaders: installation?.responseHeaders ?? [], resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  const preparations = new WeakMap();
  {
    return await construction.createRowSource({readOperation: KINTONE_RECORD_READ_OPERATION, physicalTarget: target,
      bindingCid: cid({version: 'actql-installed-kintone-binding/0.1', contextCid: authorization.context.contextCid,
        runtimeBundleCid, metadataCid: cid(metadata), site: siteProfile}),
      limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxResponseBytes,
        maxPageRows: limits.perPage, maxCaptureRows: limits.maxRows},
      prepareAcquisition: ({requirement, queryContract, evidenceContract}) => {
        const prepared = checked(moon.clientProgramKintonePrepareRead(original,
          requirement, queryContract, evidenceContract));
        const acquisition = moon.clientProgramKintoneReadAcquisition(prepared);
        preparations.set(acquisition, prepared);
        return acquisition;
      },
      readPages: async options => {
        const prepared = preparations.get(options.rowRun?.acquisition);
        if (prepared === undefined || options.resource !== installed.resource) {
          fail('ForeignKintoneReadPreparation');
        }
        const current = async operation => {
          options.signal?.throwIfAborted();
          const data = await options.verifyRead();
          if (operation === KINTONE_RECORD_READ_OPERATION) return data;
          if (operation !== KINTONE_FORM_READ_OPERATION) fail('ForeignKintoneReadOperation');
          // Form access is separately authorized under its real read Resource.
          // App identity observation and the data grant cannot supply it.
          const decision = await authorization.authorize('acquisition',
            {connection, resource: installed.formResource, operation: 'read'},
            {subjectCid: cid({binding: target(options.resource, options.columns), operation}), signal: options.signal});
          await options.verifyRead();
          if (decision?.action !== 'dispatch') fail('KintoneFormReadDenied');
          return decision;
        };
        let formGrant;
        const authorize = async ({operation, index}) => {
          const decision = await current(operation);
          if (operation === KINTONE_RECORD_READ_OPERATION) return options.authorizationFor(index);
          formGrant ??= site.issueReadGrant({operation, decision, resource: installed.formResource,
            runInvocationCid: options.rowRun.runInvocationCid,
            dispatchRequestCid: options.rowRun.dispatchRequestCid, maxUses: limits.maxRequests});
          return {...formGrant, useId: `${options.rowRun.requestId}-form-${index}`};
        };
        return await readKintoneRecords({moon, prepared, rowRun: options.rowRun, limits,
          guestSpaceId: siteProfile.guestSpaceId, authorizationFor: authorize,
          credential: site.credential, current, chargeResponse: options.chargePage,
          consumeObservation: options.consumeObservation, signal: options.signal, callResource: site.callResource});
      }});
  }
}
