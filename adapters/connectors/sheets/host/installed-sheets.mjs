// Installed Sheets uses the common row Source and Effect owners. This module
// supplies finite configuration, immutable collection binding and physical I/O.
import {randomUUID} from 'node:crypto';
import {mkdir, readFile, rename, rm, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {canonicalJson, contentCid} from '../../../host-node/local-account-config.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment, rowSourceMapping}
  from '../../../host-node/installed-row-source.mjs';
import {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';
import {checkSheetsGridConfiguration, checkSheetsTarget, prepareSheetsAppend,
  projectSheetsAppend, readSheetsGrid, sendSheetsAppend, SHEETS_APPEND_OPERATION,
  SHEETS_READ_OPERATION, SHEETS_LIMITS} from '../site/sheets-exchange.mjs';

export const SHEETS_SITE_VERSION = 'actql-installed-sheets-site/0.1';
export const SHEETS_SOURCE_VERSION = 'actql-installed-sheets-source/0.1';
export const SHEETS_EFFECT_VERSION = 'actql-installed-sheets-effect/0.1';
const registration = 'sheets', revision = 'sheets/0.1';
const publicationVersion = 'actql-sheets-publication/0.1';
const targetVersion = 'actql-installed-sheets-target/0.1';
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const absolute = value => text(value) && isAbsolute(value);
const exact = (value, keys) => value && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const sourceKeys = ['version', 'siteProfilePath', 'publicationPath',
  'connectorId', 'accountConfigurationWire'];
const siteKeys = ['apiOrigin', 'spreadsheetId', 'gridRange', 'appendSheetId',
  'columns', 'namespaceId', 'environment', 'siteKey', 'siteGeneration',
  'credentialAuthorityId', 'credentialKeyId', 'credentialPrivateKeyPath',
  'journalRoot', 'tokenEnvironment'];

function checkProfile(profile, effect) {
  if (!exact(profile, effect ? [...sourceKeys, 'sources'] : sourceKeys) ||
      profile.version !== (effect ? SHEETS_EFFECT_VERSION : SHEETS_SOURCE_VERSION) ||
      !absolute(profile.siteProfilePath) || !absolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire)) {
    fail(effect ? 'InvalidInstalledEffectProfile' : 'InvalidInstalledSourceProfile');
  }
  if (effect && (!Array.isArray(profile.sources) || profile.sources.length === 0 ||
      profile.sources.length > 64 || profile.sources.some(source =>
        !exact(source, ['target', 'field', 'null_behavior']) ||
        !text(source.target) || !text(source.field) || source.null_behavior !== 'reject'))) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...profile});
}
export const checkInstalledSheetsSourceProfile = profile => checkProfile(profile, false);
export const checkInstalledSheetsEffectProfile = profile => checkProfile(profile, true);

async function readJson(path) {
  const bytes = await readFile(path);
  if (bytes.length > 1_048_576) fail('SheetsConfigurationLimit');
  return JSON.parse(bytes.toString('utf8'));
}
async function readSite(path, providerMoon) {
  const {version, caPath, ...site} = await readJson(path);
  let origin;
  try { origin = new URL(site.apiOrigin); } catch { /* Refused below. */ }
  if (version !== SHEETS_SITE_VERSION || !exact(site, siteKeys) ||
      origin?.protocol !== 'https:' || origin.origin !== site.apiOrigin ||
      !/^[A-Za-z0-9_-]{1,128}$/u.test(site.spreadsheetId) ||
      !Number.isSafeInteger(site.appendSheetId) || site.appendSheetId < 0 ||
      !Number.isSafeInteger(site.siteGeneration) || site.siteGeneration < 1 ||
      !absolute(site.credentialPrivateKeyPath) || !absolute(site.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(site.tokenEnvironment) ||
      !exact(site.gridRange, ['sheetId', 'startRow', 'endRow', 'startColumn', 'endColumn']) ||
      Object.values(site.gridRange).some(value => !Number.isSafeInteger(value) || value < 0) ||
      site.gridRange.endRow - site.gridRange.startRow > SHEETS_LIMITS.maxRows) {
    fail('InvalidInstalledSheetsSite');
  }
  // The MoonBit codec checks the declared scalar schema and rectangular bound.
  checkSheetsGridConfiguration(providerMoon, site.columns, site.gridRange);
  return Object.freeze({...site, ca: caPath === undefined ? undefined : await readFile(caPath)});
}

function restore(moon, profile, site, expectedCatalogCid) {
  const views = JSON.stringify({views: [{resource: 'rows', resource_kind: 'sheet_rows',
    fields: site.columns}]});
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    profile.connectorId, registration, revision, views, expectedCatalogCid));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  return {declaration, declared};
}
function mappingOf(moon, profile, site, declaration) {
  const writes = JSON.stringify({writes: [{resource: 'append_rows',
    resource_kind: 'sheet_collection', primary_identity: null,
    collection_identity: {spreadsheet_id: site.spreadsheetId, sheet_id: site.appendSheetId},
    fields: site.columns, create: {fields: site.columns.map(column => column.name),
      required: site.columns.map(column => column.name),
      permission: SHEETS_APPEND_OPERATION, approval: 'required'}}]});
  return rowSourceMapping(moon, declaration, writes, 'append_rows', profile.sources);
}
const bindingFacts = site => ({api_origin: site.apiOrigin,
  spreadsheet_id: site.spreadsheetId, read_grid: site.gridRange,
  append_sheet_id: site.appendSheetId, columns: site.columns});

async function identityParts(profile, read) {
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    await read(profile.siteProfilePath), await read(profile.publicationPath)];
}
export const installedSheetsSourceIdentityParts = (profile, providerProfile, read) =>
  identityParts(checkInstalledSheetsSourceProfile(providerProfile), read);
export const installedSheetsEffectIdentityParts = (profile, read) =>
  identityParts(checkInstalledSheetsEffectProfile(profile), read);

async function readPublication(profile, site, declared) {
  const publication = await readJson(profile.publicationPath);
  const {publication_cid, ...preimage} = publication;
  if (!exact(publication, ['version', 'connectorId', 'catalogCid', 'binding', 'publication_cid']) ||
      publication.version !== publicationVersion || publication.connectorId !== profile.connectorId ||
      publication.catalogCid !== declared.catalog_cid || publication_cid !== contentCid(preimage) ||
      canonicalJson(publication.binding) !== canonicalJson(bindingFacts(site))) {
    fail('SheetsPublicationBindingChanged');
  }
  return publication;
}

async function openSite(profile, site, options, publication) {
  const {root, principalId, moon, runtimeBundleCid, installation} = options;
  const connection = `sheets:${new URL(site.apiOrigin).host}/${site.spreadsheetId}`;
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: profile.accountConfigurationWire, principalId, root,
    connectorRegistration: registration});
  const opened = await openRowSourceCredentialSite({profile: {...site,
    resourceOrigin: site.apiOrigin}, principalId, authorization, connection,
    connectorRegistration: registration, connectorRevision: revision, runtimeBundleCid,
    commonMoon: moon, ca: site.ca, responseHeaders: installation?.responseHeaders ?? [],
    resolveSecret: options.resolveSecret ?? (async () => {
      const token = process.env[site.tokenEnvironment];
      if (!text(token)) fail('RemoteCredentialSecretUnavailable');
      return token;
    }),
    admitsApprovalTarget: (binding, resource) => publication !== undefined && resource === 'rows' &&
      binding?.version === targetVersion && binding.catalog_cid === publication.catalogCid &&
      canonicalJson(binding.binding) === canonicalJson(bindingFacts(site)) &&
      Array.isArray(binding.fields) && binding.fields.every(field => site.columns.some(column => column.name === field))});
  const bindingCid = contentCid({version: 'actql-installed-sheets-binding/0.1',
    context_cid: authorization.context.contextCid, binding: bindingFacts(site),
    site_key: site.siteKey, site_generation: site.siteGeneration,
    namespace_id: site.namespaceId, environment: site.environment,
    credential_authority_id: site.credentialAuthorityId, credential_key_id: site.credentialKeyId});
  return {authorization, site: opened, connection, bindingCid};
}

async function publish(profile, options) {
  const site = await readSite(profile.siteProfilePath, options.providerMoon);
  const {declaration, declared} = restore(options.moon, profile, site);
  // Validate all Mapping declarations before any provider I/O.
  const mapping = profile.sources === undefined ? undefined
    : mappingOf(options.moon, profile, site, declaration);
  const opened = await openSite(profile, site, options);
  let temporary;
  try {
    const decision = await opened.authorization.authorize('acquisition',
      {connection: opened.connection, resource: 'rows', operation: 'read'},
      {subjectCid: contentCid(bindingFacts(site)), signal: options.signal});
    if (decision?.action !== 'dispatch') fail('ExecutionAuthorizationDenied');
    const nonce = randomUUID(), invocation = contentCid({version: 'actql-sheets-publication-read/0.1', nonce});
    const grant = opened.site.issueReadGrant({operation: SHEETS_READ_OPERATION, decision,
      resource: 'rows', runInvocationCid: invocation, dispatchRequestCid: invocation, maxUses: 1});
    await checkSheetsTarget({moon: options.providerMoon, spreadsheetId: site.spreadsheetId,
      columns: site.columns, range: site.gridRange, appendSheetId: site.appendSheetId,
      authorization: {...grant, useId: `${nonce}-metadata`}, credential: opened.site.credential,
      callResource: opened.site.callResource, signal: options.signal});
    const body = {version: publicationVersion, connectorId: profile.connectorId,
      catalogCid: declared.catalog_cid, binding: bindingFacts(site)};
    const publication = {...body, publication_cid: contentCid(body)};
    await mkdir(dirname(profile.publicationPath), {recursive: true});
    temporary = `${profile.publicationPath}.${nonce}`;
    await writeFile(temporary, canonicalJson(publication), {mode: 0o600});
    await rename(temporary, profile.publicationPath);
    temporary = undefined;
    const result = Object.freeze({...publication, ...(mapping === undefined ? {} : {mappings: [{
      resource: 'append_rows', kind: 'create', target: mapping.target,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}]})});
    // Closure failure retains the same Site/journal owner; publication is not
    // repeated merely to retry cleanup.
    opened.site.close();
    return result;
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile: {async close() {
        opened.site.close();
        // Only this attempt's UUID-named, unpublished file is owned here.
        // A removal failure stays on the existing initialization retry handle.
        if (temporary !== undefined) {
          await rm(temporary, {force: true});
          temporary = undefined;
        }
      }}});
  }
}
export const publishInstalledSheetsSource = (profile, options) =>
  publish(checkInstalledSheetsSourceProfile(profile), options);
export const publishInstalledSheetsEffect = (profile, options) =>
  publish(checkInstalledSheetsEffectProfile(profile), options);

async function load(profile, options, effect) {
  const {moon, providerMoon, baseEnvironmentWire} = options;
  const site = await readSite(profile.siteProfilePath, providerMoon);
  const {declaration, declared} = restore(moon, profile, site);
  const publication = await readPublication(profile, site, declared);
  const mapping = effect ? mappingOf(moon, profile, site, declaration) : undefined;
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared,
    mapping === undefined ? [] : [mapping.body]);
  const opened = await openSite(profile, site, options, publication);
  try {
    if (!effect) return await createInstalledRowSource({moon, declaration, declared,
      environmentWire: environment.wire, connectorId: profile.connectorId,
      connectorRegistration: registration, connectorRevision: revision,
      site: opened.site, authorization: opened.authorization, readOperation: SHEETS_READ_OPERATION,
      bindingCid: opened.bindingCid, physicalTarget: (resource, fields) => {
        if (resource !== 'rows') fail('UndeclaredSheetsResource');
        return Object.freeze({version: targetVersion, catalog_cid: publication.catalogCid,
          binding: bindingFacts(site), fields: Object.freeze([...fields])});
      },
      limits: {maxPages: 1, maxPageBytes: SHEETS_LIMITS.maxResponseBytes,
        maxPageRows: SHEETS_LIMITS.maxRows, maxCaptureRows: SHEETS_LIMITS.maxRows},
      readPages: options => {
        if (options.resource !== 'rows') fail('UndeclaredSheetsResource');
        return readSheetsGrid({...options, moon: providerMoon,
          spreadsheetId: site.spreadsheetId, columns: site.columns, range: site.gridRange,
          credential: opened.site.credential, callResource: opened.site.callResource});
      }});
    const boundaryCid = contentCid({version: 'actql-sheets-append-boundary/0.1',
      api_origin: site.apiOrigin, spreadsheet_id: site.spreadsheetId, sheet_id: site.appendSheetId});
    return await createInstalledRowEffect({moon,
      mappings: [{resource: 'append_rows', mappingRef: mapping.mappingRef,
        mappingCid: mapping.mappingCid, body: mapping.body}], environmentWire: environment.wire,
      connectorId: profile.connectorId, connectorRegistration: registration, connectorRevision: revision,
      connection: opened.connection, site: opened.site, authorization: opened.authorization,
      runtimeBundleCid: options.runtimeBundleCid, bindingCid: opened.bindingCid,
      ledgerRoot: options.ledgerRoot, installation: options.installation,
      driver: {kinds: ['create'], writeOperation: () => SHEETS_APPEND_OPERATION,
        check: {resource: 'rows', operation: SHEETS_READ_OPERATION},
        requestFacts: request => ({value: request.value}),
        prepareRequest: ({member, value}) => {
          if (member.resource !== 'append_rows') fail('UndeclaredSheetsResource');
          const request = prepareSheetsAppend({moon: providerMoon, origin: site.apiOrigin,
            spreadsheetId: site.spreadsheetId, sheetId: site.appendSheetId, columns: site.columns, value});
          return {request, requestCid: request.requestCid};
        },
        checkRequest: options => checkSheetsTarget({...options, moon: providerMoon,
          spreadsheetId: site.spreadsheetId, columns: site.columns, range: site.gridRange,
          appendSheetId: site.appendSheetId}),
        send: sendSheetsAppend,
        project: options => projectSheetsAppend({...options, moon: providerMoon}),
        footprint: () => ({providerNamespace: registration, resourceKind: 'sheet_collection', boundaryCid})}});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      effect ? {installedEffect: opened.site} : {sourceProfile: opened.site});
  }
}
export const loadInstalledSheetsSource = (profile, options) =>
  load(checkInstalledSheetsSourceProfile(profile), options, false);
export const loadInstalledSheetsEffect = (profile, options) =>
  load(checkInstalledSheetsEffectProfile(profile), options, true);
