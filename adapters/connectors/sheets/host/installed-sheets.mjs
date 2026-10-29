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
  projectSheetsAppend, readSheetsGrid, SHEETS_APPEND_OPERATION,
  SHEETS_READ_OPERATION, SHEETS_LIMITS, readSheetsRangeTarget} from '../site/sheets-exchange.mjs';
import {createSheetsRangeDriver, sheetsRangeCommand, sheetsRangeReference,
  withSheetsRangeCommand} from './sheets-range-command.mjs';
import {createSheetsClearDriver, sheetsClearCommand} from './sheets-clear-command.mjs';

export const SHEETS_SITE_VERSION = 'actql-installed-sheets-site/0.1';
export const SHEETS_SOURCE_VERSION = 'actql-installed-sheets-source/0.1';
export const SHEETS_EFFECT_VERSION = 'actql-installed-sheets-effect/0.1';
const registration = 'sheets', revision = 'sheets/0.1';
const publicationVersion = 'actql-sheets-publication/0.1';
const targetVersion = 'actql-installed-sheets-target/0.1';
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const absolute = value => text(value) && isAbsolute(value);
const gridIndex = value => Number.isInteger(value) && value >= 0 && value <= 2_147_483_647;
const exact = (value, keys) => value && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const sourceKeys = ['version', 'siteProfilePath', 'publicationPath',
  'connectorId', 'accountConfigurationWire'];
const siteKeys = ['apiOrigin', 'spreadsheetId', 'gridRange', 'appendSheetId',
  'columns', 'namespaceId', 'environment', 'siteKey', 'siteGeneration',
  'credentialAuthorityId', 'credentialKeyId', 'credentialPrivateKeyPath',
  'journalRoot', 'tokenEnvironment'];

function checkProfile(profile, effect) {
  const rangeCommand = profile?.rangeCommand === true || profile?.rangeCommand === 'clear';
  if (!exact(profile, rangeCommand ? [...sourceKeys, 'rangeCommand']
    : effect ? [...sourceKeys, 'sources'] : sourceKeys) ||
      profile.version !== (effect ? SHEETS_EFFECT_VERSION : SHEETS_SOURCE_VERSION) ||
      !absolute(profile.siteProfilePath) || !absolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire)) {
    fail(effect ? 'InvalidInstalledEffectProfile' : 'InvalidInstalledSourceProfile');
  }
  if (effect && !rangeCommand && (!Array.isArray(profile.sources) || profile.sources.length === 0 ||
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
      !gridIndex(site.appendSheetId) ||
      !Number.isSafeInteger(site.siteGeneration) || site.siteGeneration < 1 ||
      !absolute(site.credentialPrivateKeyPath) || !absolute(site.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(site.tokenEnvironment) ||
      !exact(site.gridRange, ['sheetId', 'startRow', 'endRow', 'startColumn', 'endColumn']) ||
      Object.values(site.gridRange).some(value => !gridIndex(value)) ||
      site.gridRange.endRow - site.gridRange.startRow > SHEETS_LIMITS.maxRows) {
    fail('InvalidInstalledSheetsSite');
  }
  // The MoonBit codec checks the declared scalar schema and rectangular bound.
  checkSheetsGridConfiguration(providerMoon, site.columns, site.gridRange);
  return Object.freeze({...site, ca: caPath === undefined ? undefined : await readFile(caPath)});
}

function restore(moon, providerMoon, profile, site, expectedCatalogCid) {
  if (profile.rangeCommand) {
    const schema = Object.fromEntries(site.columns.map(({name, type, nullable}) =>
      [name, {type, nullable}]));
    const view = (resource, resource_kind, schema) => ({resource, resource_kind,
      schema_wire: canonicalJson(schema), schema_cid: contentCid(schema)});
    const views = {views: [view('rows', 'sheet_rows', schema),
      view('range_target', 'sheet_range', {
        target: {type: 'resource_ref', resource_kind: 'sheet_range', nullable: false}})]};
    const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
      profile.connectorId, registration, revision, JSON.stringify(views), undefined));
    const rangeCommand = (profile.rangeCommand === 'clear' ? sheetsClearCommand : sheetsRangeCommand)(
      profile.connectorId, site, providerMoon);
    const declared = withSheetsRangeCommand(
      JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration)), rangeCommand, providerMoon);
    if (expectedCatalogCid !== undefined && expectedCatalogCid !== declared.catalog_cid) {
      fail('SheetsPublicationBindingChanged');
    }
    return {declaration, declared, rangeCommand};
  }
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
    admitsApprovalTarget: (binding, resource) => publication !== undefined &&
      (resource === 'rows' || (profile.rangeCommand && resource === 'range_target' && binding.resource === resource)) &&
      binding?.version === targetVersion && binding.catalog_cid === publication.catalogCid &&
      canonicalJson(binding.binding) === canonicalJson(bindingFacts(site)) &&
      Array.isArray(binding.fields) && binding.fields.every(field => resource === 'range_target'
        ? field === 'target' : site.columns.some(column => column.name === field))});
  const bindingCid = contentCid({version: 'actql-installed-sheets-binding/0.1',
    context_cid: authorization.context.contextCid, binding: bindingFacts(site),
    site_key: site.siteKey, site_generation: site.siteGeneration,
    namespace_id: site.namespaceId, environment: site.environment,
    credential_authority_id: site.credentialAuthorityId, credential_key_id: site.credentialKeyId});
  return {authorization, site: opened, connection, bindingCid};
}

async function publish(profile, options) {
  const site = await readSite(profile.siteProfilePath, options.providerMoon);
  const {declaration, declared, rangeCommand} = restore(options.moon, options.providerMoon, profile, site);
  // Validate all Mapping declarations before any provider I/O.
  const mapping = profile.sources === undefined ? undefined
    : mappingOf(options.moon, profile, site, declaration);
  const opened = await openSite(profile, site, options);
  let temporary;
  try {
    const resource = profile.rangeCommand ? 'range_target' : 'rows';
    const decision = await opened.authorization.authorize('acquisition',
      {connection: opened.connection, resource, operation: 'read'},
      {subjectCid: contentCid(bindingFacts(site)), signal: options.signal});
    if (decision?.action !== 'dispatch') fail('ExecutionAuthorizationDenied');
    const nonce = randomUUID(), invocation = contentCid({version: 'actql-sheets-publication-read/0.1', nonce});
    const grant = opened.site.issueReadGrant({operation: SHEETS_READ_OPERATION, decision,
      resource, runInvocationCid: invocation, dispatchRequestCid: invocation, maxUses: 1});
    await checkSheetsTarget({moon: options.providerMoon, spreadsheetId: site.spreadsheetId,
      columns: site.columns, range: site.gridRange,
      appendSheetId: profile.rangeCommand ? site.gridRange.sheetId : site.appendSheetId,
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
    const result = Object.freeze({...publication,
      ...(rangeCommand === undefined ? {} : {commands: [rangeCommand.installed]}),
      ...(mapping === undefined ? {} : {mappings: [{
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
  const {declaration, declared, rangeCommand} = restore(moon, providerMoon, profile, site);
  const publication = await readPublication(profile, site, declared);
  const mapping = effect && rangeCommand === undefined ? mappingOf(moon, profile, site, declaration) : undefined;
  let environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared,
    mapping === undefined ? [] : [mapping.body]);
  if (rangeCommand !== undefined) {
    const {evidence_bundle_cid: _, ...body} = JSON.parse(environment.wire);
    if (!Array.isArray(body.command_contracts) || body.command_contracts.length !== 0) {
      fail('InvalidRowSourceCheckEnvironmentBase');
    }
    const value = {...body, command_contracts: [rangeCommand.command]};
    environment = {wire: canonicalJson({...value, evidence_bundle_cid: contentCid(value)})};
  }
  const opened = await openSite(profile, site, options, publication);
  let closed = false;
  const target = rangeCommand === undefined ? undefined : sheetsRangeReference({site,
    catalogCid: declared.catalog_cid, bindingCid: opened.bindingCid, moon: providerMoon});
  try {
    if (!effect) {
      const adapter = await createInstalledRowSource({moon, declaration, declared,
      environmentWire: environment.wire, connectorId: profile.connectorId,
      connectorRegistration: registration, connectorRevision: revision,
      site: opened.site, authorization: opened.authorization, readOperation: SHEETS_READ_OPERATION,
      bindingCid: opened.bindingCid, physicalTarget: (resource, fields) => {
        if (resource !== 'rows' && !(profile.rangeCommand && resource === 'range_target')) fail('UndeclaredSheetsResource');
        return Object.freeze({version: targetVersion, catalog_cid: publication.catalogCid,
          binding: bindingFacts(site), fields: Object.freeze([...fields]),
          ...(profile.rangeCommand ? {resource} : {})});
      },
      ...(target === undefined ? {} : {referenceIssuer: moon.clientProgramResourceReferenceIssuer(
        (kind, wire) => !closed && kind === 'sheet_range' && wire === canonicalJson(target),
        () => !closed)}),
      limits: {maxPages: 1, maxPageBytes: SHEETS_LIMITS.maxResponseBytes,
        maxPageRows: SHEETS_LIMITS.maxRows, maxCaptureRows: SHEETS_LIMITS.maxRows},
      readPages: options => {
        if (profile.rangeCommand && options.resource === 'range_target') {
          return readSheetsRangeTarget({...options, moon: providerMoon,
            spreadsheetId: site.spreadsheetId, columns: site.columns, range: site.gridRange,
            target, credential: opened.site.credential, callResource: opened.site.callResource});
        }
        if (options.resource !== 'rows') fail('UndeclaredSheetsResource');
        return readSheetsGrid({...options, moon: providerMoon,
          spreadsheetId: site.spreadsheetId, columns: site.columns, range: site.gridRange,
          credential: opened.site.credential, callResource: opened.site.callResource});
      }});
      return rangeCommand === undefined ? adapter : Object.freeze({...adapter,
        close() { closed = true; return adapter.close(); }});
    }
    if (rangeCommand !== undefined) return await createInstalledRowEffect({moon,
      commands: [rangeCommand.installed], environmentWire: environment.wire,
      connectorId: profile.connectorId, connectorRegistration: registration, connectorRevision: revision,
      connection: opened.connection, site: {...opened.site,
        close() { closed = true; return opened.site.close(); }}, authorization: opened.authorization,
      runtimeBundleCid: options.runtimeBundleCid, bindingCid: opened.bindingCid,
      ledgerRoot: options.ledgerRoot, installation: options.installation,
      driver: (profile.rangeCommand === 'clear' ? createSheetsClearDriver : createSheetsRangeDriver)({moon: providerMoon, site,
        command: rangeCommand.installed, bindingCid: opened.bindingCid, target,
        isCurrent: () => !closed})});
    const boundaryCid = contentCid({version: 'actql-sheets-append-boundary/0.1',
      api_origin: site.apiOrigin, spreadsheet_id: site.spreadsheetId, sheet_id: site.appendSheetId});
    return await createInstalledRowEffect({moon,
      mappings: [{resource: 'append_rows', mappingRef: mapping.mappingRef,
        mappingCid: mapping.mappingCid, body: mapping.body}], environmentWire: environment.wire,
      connectorId: profile.connectorId, connectorRegistration: registration, connectorRevision: revision,
      connection: opened.connection, site: opened.site, authorization: opened.authorization,
      runtimeBundleCid: options.runtimeBundleCid, bindingCid: opened.bindingCid,
      ledgerRoot: options.ledgerRoot, installation: options.installation,
      write: {kind: 'create', operation: SHEETS_APPEND_OPERATION,
        resourceKind: 'sheet_collection', boundaryCid,
        http: {origin: site.apiOrigin, method: 'POST',
          path: `/v4/spreadsheets/${site.spreadsheetId}:batchUpdate`,
          headers: [['accept', 'application/json']],
          maxRequestBytes: SHEETS_LIMITS.maxRequestBytes, maxResponseBytes: SHEETS_LIMITS.maxResponseBytes},
        request: ({resource, value}) => {
          if (resource !== 'append_rows') fail('UndeclaredSheetsResource');
          const request = prepareSheetsAppend({moon: providerMoon, origin: site.apiOrigin,
            spreadsheetId: site.spreadsheetId, sheetId: site.appendSheetId, columns: site.columns, value});
          if (request.path !== `/v4/spreadsheets/${request.spreadsheetId}:batchUpdate`) {
            fail('InvalidSheetsAppendBinding');
          }
          return request;
        },
        check: {resource: 'rows', operation: SHEETS_READ_OPERATION,
          request: options => checkSheetsTarget({...options, moon: providerMoon,
          spreadsheetId: site.spreadsheetId, columns: site.columns, range: site.gridRange,
          appendSheetId: site.appendSheetId})},
        classify: options => projectSheetsAppend({...options, moon: providerMoon})}});
  } catch (cause) {
    closed = true;
    throw await retainInstalledHostInitializationFailure(cause,
      effect ? {installedEffect: opened.site} : {sourceProfile: opened.site});
  }
}
export const loadInstalledSheetsSource = (profile, options) =>
  load(checkInstalledSheetsSourceProfile(profile), options, false);
export const loadInstalledSheetsEffect = (profile, options) =>
  load(checkInstalledSheetsEffectProfile(profile), options, true);
