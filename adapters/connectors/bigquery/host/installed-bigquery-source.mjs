// Installation DATA and adaptation of the existing original accounted Job.
// Common/RowSource/Journal/Credential owners retain current, backing and cleanup.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson, readBoundedConfigurationText} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {readBigQuerySqlApi, BIGQUERY_SQL_READ_OPERATION} from '../site/bigquery-sql-read.mjs';

export const INSTALLED_BIGQUERY_SOURCE_VERSION = 'actql-installed-bigquery-source/0.1';
export const INSTALLED_BIGQUERY_SITE_VERSION = 'actql-installed-bigquery-site/0.1';
const registration = 'bigquery', revision = 'bigquery/0.1';
const fail = code => {throw Object.assign(new TypeError(code), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const own = (value, required, optional, code) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || nodeTypes.isProxy(value)) fail(code);
  const entries = Object.getOwnPropertyDescriptors(value), keys = Reflect.ownKeys(entries);
  if (required.some(name => !Object.hasOwn(entries[name] ?? {}, 'value')) || keys.some(name =>
    typeof name !== 'string' || ![...required, ...optional].includes(name) || !Object.hasOwn(entries[name], 'value'))) fail(code);
  return Object.fromEntries(keys.map(name => [name, entries[name].value]));
};
const limitKeys = ['maxBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameBytes', 'maxSchemaBytes',
  'maxRows', 'maxTotalRows', 'maxValueNodes', 'maxValueTextBytes', 'maxJobBytes', 'maxPageTokenBytes',
  'maxPages', 'maxResults', 'timeoutMs', 'maxRequests', 'maxRequestBytes', 'maxSecretBytes', 'pollDelayMs',
  'maximumBytesBilled', 'maxDeclarationBytes', 'maxDeclarationNodes', 'maxCaBytes'];

export function checkInstalledBigQuerySourceProfile(value) {
  const code = 'InvalidInstalledBigQuerySourceProfile';
  const profile = own(value, ['version', 'connectorId', 'resource', 'project', 'dataset', 'table', 'location',
    'metadataPath', 'siteProfilePath', 'accountConfigurationWire', 'limits'], [], code);
  const limits = own(profile.limits, limitKeys, [], code);
  if (profile.version !== INSTALLED_BIGQUERY_SOURCE_VERSION ||
      !['connectorId', 'resource', 'project', 'dataset', 'table', 'location', 'accountConfigurationWire'].every(name => text(profile[name])) ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !limitKeys.filter(name => name !== 'maximumBytesBilled').every(name =>
        Number.isSafeInteger(limits[name]) && limits[name] >= (['timeoutMs', 'pollDelayMs'].includes(name) ? 0 : 1) &&
        limits[name] <= 2147483647) || limits.maxRows > limits.maxTotalRows ||
      typeof limits.maximumBytesBilled !== 'string' || !/^[1-9][0-9]{0,18}$/u.test(limits.maximumBytesBilled) ||
      BigInt(limits.maximumBytesBilled) > 9223372036854775807n) fail(code);
  return Object.freeze({...profile, limits: Object.freeze(limits)});
}

export function checkInstalledBigQuerySiteProfile(value) {
  const code = 'InvalidInstalledBigQuerySite';
  const site = own(value, ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId', 'credentialPrivateKeyPath',
    'environment', 'journalRoot', 'namespaceId', 'siteGeneration', 'siteKey', 'tokenEnvironment'], ['caPath'], code);
  let origin;try {origin = new URL(site.apiOrigin);} catch { /* Reject below. */ }
  if (site.version !== INSTALLED_BIGQUERY_SITE_VERSION || origin?.protocol !== 'https:' || origin.origin !== site.apiOrigin ||
      !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(name => text(site[name])) ||
      !absolute(site.credentialPrivateKeyPath) || !absolute(site.journalRoot) ||
      (Object.hasOwn(site, 'caPath') && !absolute(site.caPath)) ||
      !Number.isSafeInteger(site.siteGeneration) || site.siteGeneration < 0 ||
      typeof site.tokenEnvironment !== 'string' || !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(site.tokenEnvironment)) fail(code);
  return Object.freeze(site);
}

async function readInputs(value) {
  const installed = checkInstalledBigQuerySourceProfile(value);
  const site = checkInstalledBigQuerySiteProfile(await readSourceProfileJson(installed.siteProfilePath));
  const metadata = own(await readSourceProfileJson(installed.metadataPath), ['version', 'connectorId', 'resource',
    'project', 'dataset', 'table', 'location', 'apiOrigin', 'body'], [], 'InvalidInstalledBigQueryMetadata');
  if (metadata.version !== 'actql-bigquery-read-metadata/0.1' ||
      !['connectorId', 'resource', 'project', 'dataset', 'table', 'location'].every(name => metadata[name] === installed[name]) ||
      metadata.apiOrigin !== site.apiOrigin || typeof metadata.body !== 'string' ||
      metadata.body.length > Math.ceil(installed.limits.maxBytes / 3) * 4) fail('InvalidInstalledBigQueryMetadata');
  const body = Buffer.from(metadata.body, 'base64');
  if (body.byteLength > installed.limits.maxBytes || body.toString('base64') !== metadata.body) fail('InvalidInstalledBigQueryMetadata');
  let ca;
  if (site.caPath !== undefined) {
    const pem = await readBoundedConfigurationText(site.caPath, {maxBytes: installed.limits.maxCaBytes});
    if (/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem) || !pem.includes('-----BEGIN CERTIFICATE-----') ||
        !pem.includes('-----END CERTIFICATE-----')) fail('InvalidInstalledBigQueryTlsAuthority');
    ca = Buffer.from(pem, 'ascii');
  }
  return {installed, site, metadata, body, ca};
}

export async function installedBigQuerySourceIdentityParts(profile, providerProfile) {
  const {installed, site, metadata, ca} = await readInputs(providerProfile);
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)}, site,
    {metadataCid: cid(metadata), exactTargetCid: cid({project: installed.project, dataset: installed.dataset,
      table: installed.table, location: installed.location, resource: installed.resource}),
    ...(ca === undefined ? {} : {caSha256: `sha256:${createHash('sha256').update(ca).digest('hex')}`})}];
}

export async function loadInstalledBigQuerySource(value, {root, principalId, moon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation}) {
  const {installed, site: siteProfile, metadata, body, ca} = await readInputs(value);
  const {limits} = installed;
  const names = ['DescriptionLimits', 'DeclarationLimits', 'DescribeTable', 'GenerateReadDeclaration',
    'PrepareRead', 'ReadAcquisition', 'OriginalJob', 'BorrowRead', 'QueryLimits', 'PrepareJob', 'NextRequest',
    'RequestMaterial', 'AttemptRequest', 'ChargeResponse', 'AcceptResponse', 'RecordDecoderRefusal',
    'RecordResponseLoss', 'JobComplete', 'JobRemoteDone', 'JobOriginal', 'ReadUsage', 'InterruptRead',
    'RetireReadBorrow', 'BindReadTransport', 'JobRecordLimits', 'JobOriginalRecord', 'JobOriginalRecordWire',
    'JobOriginalRecordMatchesRequest', 'JobReadMatchesRowRun'];
  if (names.some(name => typeof Object.getOwnPropertyDescriptor(moon ?? {}, `clientProgramBigQuery${name}`)?.value !== 'function') ||
      typeof Object.getOwnPropertyDescriptor(moon ?? {}, 'clientProgramRowSourceDeclarationJson')?.value !== 'function') {
    fail('BigQueryOriginalReadUnavailable');
  }
  const descriptionLimits = moon.clientProgramBigQueryDescriptionLimits(limits.maxBytes, limits.maxNodes,
    limits.maxDepth, limits.maxFields, limits.maxNameBytes, limits.maxSchemaBytes);
  const declarationLimits = moon.clientProgramBigQueryDeclarationLimits(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes, limits.maxDepth, 1, limits.maxFields);
  const description = checked(moon.clientProgramBigQueryDescribeTable(installed.project, installed.dataset,
    installed.table, body, descriptionLimits));
  const declaration = checked(moon.clientProgramBigQueryGenerateReadDeclaration(description, installed.resource,
    installed.connectorId, revision, descriptionLimits, declarationLimits));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const authorization = await installRowSourceAuthorization({root, principalId, connectorRegistration: registration,
    accountConfiguration: installed.accountConfigurationWire});
  const connection = `bigquery:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-bigquery-target/0.1',
    apiOrigin: siteProfile.apiOrigin, project: installed.project, dataset: installed.dataset,
    table: installed.table, location: installed.location, resource, metadataCid: cid(metadata),
    catalogCid: declared.catalog_cid, fields: Object.freeze([...fields])});
  const allFields = declared.views[0].fields;
  const admitsApprovalTarget = (binding, resource) => resource === installed.resource &&
    binding !== null && typeof binding === 'object' && Array.isArray(binding.fields) &&
    new Set(binding.fields).size === binding.fields.length && binding.fields.every(field => allFields.includes(field)) &&
    canonical(binding) === canonical(target(resource, binding.fields));
  const site = await openRowSourceCredentialSite({profile: {...siteProfile, resourceOrigin: siteProfile.apiOrigin},
    principalId, authorization, connection, connectorRegistration: registration, connectorRevision: revision,
    runtimeBundleCid, commonMoon: moon, ca, admitsApprovalTarget,
    responseHeaders: installation?.responseHeaders ?? ['content-encoding'], resolveSecret: resolveSecret ?? (async () => {
      const token = process.env[siteProfile.tokenEnvironment];
      if (!text(token)) fail('RemoteCredentialSecretUnavailable');return token;
    })});
  try {
    const preparedReads = new WeakMap();
    const readLimits = Object.freeze({...limits, maxTotalRows: BigInt(limits.maxTotalRows),
      maximumBytesBilled: BigInt(limits.maximumBytesBilled)});
    return await createInstalledRowSource({moon, declaration, declared, environmentWire: environment.wire,
      connectorId: installed.connectorId, connectorRegistration: registration, connectorRevision: revision,
      site, authorization, readOperation: BIGQUERY_SQL_READ_OPERATION, physicalTarget: target,
      bindingCid: cid({version: 'actql-installed-bigquery-binding/0.1', contextCid: authorization.context.contextCid,
        runtimeBundleCid, metadataCid: cid(metadata), site: siteProfile}),
      limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxBytes,
        maxPageRows: limits.maxRows, maxCaptureRows: limits.maxTotalRows},
      prepareAcquisition: options => {
        const prepared = checked(moon.clientProgramBigQueryPrepareRead(description, options.declaration,
          options.requirement, options.queryContract, options.evidenceContract, descriptionLimits, declarationLimits));
        const acquisition = moon.clientProgramBigQueryReadAcquisition(prepared);
        preparedReads.set(acquisition, prepared);return acquisition;
      },
      readPages: async options => {
        const prepared = preparedReads.get(options.rowRun?.acquisition);
        if (prepared === undefined) fail('ForeignBigQueryReadPreparation');
        if (typeof options.withOriginalJob !== 'function') fail('BigQueryOriginalOperationUnavailable');
        const frame = options.rowRun;
        if (typeof frame.requestId !== 'string' || typeof frame.runInvocationCid !== 'string' ||
            typeof frame.dispatchRequestCid !== 'string') fail('ForeignBigQueryReadPreparation');
        // This is a provider Job name bound to the actual Source attempt, not
        // a dispatch issuer. The standard original-operation CAS/current port
        // must still enter once before the driver can send its first POST.
        const jobId = 'actql_' + createHash('sha256').update(JSON.stringify([
          frame.runInvocationCid, frame.dispatchRequestCid, frame.requestId])).digest('hex');
        const job = checked(moon.clientProgramBigQueryOriginalJob(installed.project, jobId,
          installed.location, limits.maxJobBytes));
        await readBigQuerySqlApi({...options, moon, prepared, job, limits: readLimits,
          credential: site.credential, callResource: site.callResource});
      }});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  }
}
