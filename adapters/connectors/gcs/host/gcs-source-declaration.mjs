// Connector-owned declaration inputs. Catalogs, schemas, capabilities and CIDs
// are restored/sealed by the existing common row-source declaration owner.
// No credential is resolved and no provider request is made at this boundary.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

export const INSTALLED_GCS_SOURCE_VERSION = 'actql-installed-gcs-source/0.1';
export const GCS_REGISTRATION = 'gcs';
export const GCS_REVISION = 'gcs/0.1';
const profileKeys = ['version', 'connectorId', 'project', 'bucket', 'prefix',
  'mediaType', 'siteProfilePath', 'accountConfigurationWire', 'limits'];
const limitKeys = ['maxListingItems', 'maxExaminedItems', 'maxPages',
  'maxAttempts', 'maxListingBytes', 'maxDurationMs', 'maxPathBytes',
  'maxPageBytes', 'maxPageItems', 'maxRequestBytes', 'maxContentBytes'];
const fail = () => { throw Object.assign(new TypeError('InvalidInstalledGcsSourceProfile'),
  {code: 'InvalidInstalledGcsSourceProfile'}); };
const exact = (value, maximum, empty = false) => typeof value === 'string' &&
  (empty || value.length > 0) && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value) && Buffer.byteLength(value) <= maximum;
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === keys.slice().sort().join('\0');
const positive = value => Number.isInteger(value) && value > 0 && value <= 2147483647;
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledGcsSourceProfile(profile) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_GCS_SOURCE_VERSION ||
      !exact(profile.connectorId, 128) || !exact(profile.project, 128) ||
      !exact(profile.bucket, 222) ||
      // Prefixes are exact query data, not header values or identifiers.
      typeof profile.prefix !== 'string' || !profile.prefix.isWellFormed() ||
      Buffer.byteLength(profile.prefix) > 1024 ||
      !exact(profile.mediaType, 1024) ||
      !/^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/u.test(profile.mediaType) ||
      !exact(profile.siteProfilePath, 4096) || !isAbsolute(profile.siteProfilePath) ||
      !exact(profile.accountConfigurationWire, 1000000) ||
      !closed(profile.limits, limitKeys)) fail();
  const limits = {...profile.limits};
  if (!limitKeys.filter(key => key !== 'maxContentBytes').every(key => positive(limits[key])) ||
      !Number.isInteger(limits.maxContentBytes) || limits.maxContentBytes < 0 ||
      limits.maxContentBytes > limits.maxPageBytes || limits.maxPages < 2 ||
      limits.maxAttempts < limits.maxPages || limits.maxPageItems > 1000 ||
      limits.maxPathBytes > 1024 || limits.maxPageBytes > Math.floor(2147483647 / 2) ||
      limits.maxListingItems > limits.maxExaminedItems) fail();
  let account;
  try { account = JSON.parse(profile.accountConfigurationWire); } catch { fail(); }
  if (account === null || typeof account !== 'object' || Array.isArray(account)) fail();
  return Object.freeze({...profile, limits: Object.freeze(limits)});
}

function view(resource, schema, request, acquisition) {
  return {resource, resource_kind: 'file', schema_wire: canonical(schema),
    schema_cid: cid(schema), request_schema_wire: canonical(request), facts_wire: '{}',
    ...(acquisition === undefined ? {} : {acquisition_wire: canonical(acquisition)})};
}

export function prepareGcsSourceDeclarationInputs(profile, {includeObjects = false} = {}) {
  const installed = checkInstalledGcsSourceProfile(profile);
  const {limits} = installed;
  const resource = {type: 'resource_ref', resource_kind: 'file', nullable: false};
  const version = {type: 'string', nullable: false};
  const request = fields => ({type: 'object', nullable: false,
    additional_properties: false, fields});
  const views = [
    view('files', {resource, version, name: {type: 'string', nullable: false},
      path: {type: 'string', nullable: true}, media_type: {type: 'string', nullable: true},
      size_bytes: {type: 'number', nullable: true}, modified_at: {type: 'timestamp', nullable: true}},
    request({paths: {type: 'array', nullable: true, max_items: limits.maxListingItems,
      items: {type: 'string', nullable: false}}, glob: {type: 'string', nullable: true}}),
    {kind: 'scan', authority: 'read_metadata'}),
    view('contents', {resource, version,
      ...(includeObjects ? {name: {type: 'string', nullable: false},
        media_type: {type: 'string', nullable: false}} : {}),
      content: {type: 'content_ref', media_type: installed.mediaType, nullable: false}},
    request({resource, version}), {kind: 'fetch', authority: 'read_content',
      correlation: {request_fields: ['resource', 'version'], response_fields: ['resource', 'version'],
        identity: ['resource', 'version'], cardinality: 'one'}}),
  ];
  if (includeObjects) {
    // Exact provider integers enter the existing nominal signed64 domain.
    // Canonical decimal transport text does not make them Decimal or String;
    // the provider's nonnegative signed64 range check remains unchanged.
    const integer = {type: 'int64', nullable: false};
    const optionalText = {type: 'string', nullable: true};
    views.push(view('objects', {resource, version, name: {type: 'string', nullable: false},
      size: integer, content_type: optionalText, generation: integer, metageneration: integer,
      storage_class: optionalText, updated: {type: 'timestamp', nullable: true},
      md5: optionalText, crc32c: optionalText, metadata: {type: 'json', nullable: true}},
    request({prefix: {type: 'string', nullable: true}}), {kind: 'scan', authority: 'read_metadata'}));
  }
  const scopeCid = cid({version: 'actql-gcs-resource-scope/0.1',
    project: installed.project, bucket: installed.bucket, prefix: installed.prefix});
  const versionCid = cid({version: 'actql-gcs-exact-version/0.1',
    representation: 'exact_stored_bytes', generation: 'opaque_decimal_string',
    metadata_preconditions: ['generation', 'ifGenerationMatch'],
    media_preconditions: ['generation', 'ifGenerationMatch', 'ifMetagenerationMatch']});
  const initialViews = Object.freeze(views.map(value => Object.freeze(value)));
  const deriveFinalViews = initial => {
    // The actual preliminary declaration supplies these carrier identities.
    // Never mutate its privately retained inputs or invent matching hashes.
    const finalViews = initialViews.map(value => ({...value}));
    finalViews[0].facts_wire = canonical({file_listing: {
    version: 'actql-file-list/0.1', kind: 'file_listing', selectable: ['paths', 'glob'],
    allow_unfiltered_listing: true, admitted_scope_contract_cid: scopeCid,
    listing_schema_contract_cid: initial.views.find(value => value.resource === 'files').carrier_schema_cid,
    version_capability: {contract_cid: versionCid, required_nonnull: true},
    max_listing_items: limits.maxListingItems, max_examined_items: limits.maxExaminedItems,
    max_listing_pages: limits.maxPages, max_request_attempts: limits.maxAttempts,
    max_listing_bytes: limits.maxListingBytes, max_listing_duration_ms: limits.maxDurationMs,
    maximum_path_length: limits.maxPathBytes,
  }});
    finalViews[1].facts_wire = canonical({file_content: {
    version: 'actql-file-content/0.1', kind: 'file_content',
    admitted_scope_contract_cid: scopeCid,
    content_schema_contract_cid: initial.views.find(value => value.resource === 'contents').carrier_schema_cid,
    version_capability: {contract_cid: versionCid, required_nonnull: true},
    representation: 'exact_stored_bytes',
  }, lookup_capacity: {version: 'actql-lookup-capacity/0.1',
    completeness: 'complete_per_requested_key', max_rows_per_key: 1,
    max_pages_per_request: 2, max_response_bytes_per_page: limits.maxPageBytes}});
    return Object.freeze(finalViews.map(value => Object.freeze(value)));
  };
  return Object.freeze({connectorId: installed.connectorId, initialViews, deriveFinalViews, scopeCid, versionCid});
}

// Standalone declaration compatibility preserves the same TWO Common
// restores. Installed load uses the bound common owner to fund/retain each.
export function restoreGcsSourceDeclaration(moon, profile, expectedCatalogCid,
  {includeObjects = false} = {}) {
  const inputs = prepareGcsSourceDeclarationInputs(profile, {includeObjects});
  const restore = (views, expected) => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    inputs.connectorId, GCS_REGISTRATION, GCS_REVISION, JSON.stringify({views}), expected));
  const preliminary = restore(inputs.initialViews, undefined);
  const initial = JSON.parse(moon.clientProgramRowSourceDeclarationJson(preliminary));
  const declaration = restore(inputs.deriveFinalViews(initial), expectedCatalogCid);
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  return Object.freeze({declaration, declared, scopeCid: inputs.scopeCid, versionCid: inputs.versionCid});
}
