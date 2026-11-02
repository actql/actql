// Installed Sheets uses the common row Source and Effect owners. This module
// supplies finite configuration, immutable collection binding and physical I/O.
import {randomUUID} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {mkdir, readFile, rename, rm, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {canonicalJson, contentCid} from '../../../host-node/local-account-config.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment, rowSourceMapping}
  from '../../../host-node/installed-row-source.mjs';
import {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import {prepareSheetsGridPages, prepareSheetsRangeTargetPages} from '../site/sheets-grid-pages.mjs';
import {checkSheetsGridConfiguration, checkSheetsTarget, prepareSheetsAppend,
  projectSheetsAppend, prepareSheetsTargetRequest, projectSheetsTarget, SHEETS_APPEND_OPERATION,
  SHEETS_READ_OPERATION, SHEETS_LIMITS} from '../site/sheets-exchange.mjs';
import {createSheetsRangeDriver, sheetsRangeCommand, sheetsRangeReference,
  withSheetsRangeCommand, sheetsRangeConfigurationBytes} from './sheets-range-command.mjs';
import {createSheetsClearDriver, sheetsClearCommand} from './sheets-clear-command.mjs';
import {sheetsOwnedResult} from '../site/sheets-owned-request.mjs';

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

async function readJson(path, originalRead) {
  if (originalRead !== undefined) return originalRead(path, {maxBytes: 1_048_576});
  const bytes = await readFile(path);
  if (bytes.length > 1_048_576) fail('SheetsConfigurationLimit');
  return JSON.parse(bytes.toString('utf8'));
}
async function readSite(path, providerMoon, configurationReader) {
  // Select original methods before the first awaited read, including the
  // exact-byte CA reader. A mutable adapter cannot swap it after Site input.
  const readers = configurationReader === undefined ? undefined
    : captureConfigurationReaders(configurationReader, undefined,
      () => fail('InstalledSheetsConfigurationReaderUnavailable'));
  const {version, caPath, ...site} = await readJson(path, readers?.readJson);
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
  const columns = Object.freeze(site.columns.map(column => Object.freeze({...column})));
  if (caPath !== undefined && readers !== undefined && readers.readOriginalBytes === undefined) {
    fail('InstalledSheetsConfigurationReaderUnavailable');
  }
  return Object.freeze({...site, columns, ca: caPath === undefined ? undefined
    : await (readers === undefined ? readFile(caPath) : readers.readOriginalBytes(caPath))});
}

// The SAME original native command/catalog builders remain the semantic
// owners. Capture all methods before the Source reserve/current boundary;
// retain their returned canonical wires instead of serializing the projection
// again merely to estimate or assemble its one Environment.
function prepareInitializedSheetsCommandDeclaration(sourceInitialization, providerMoon, profile, site, viewsWire, expectedCatalogCid) {
  const constructor = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareDeclaredCommands');
  if (!constructor || !Object.hasOwn(constructor, 'value') || typeof constructor.value !== 'function') {
    fail('InstalledSheetsInitializationUnavailable');
  }
  const commandName = profile.rangeCommand === 'clear' ? 'sheetsClearCommandJson' : 'sheetsRangeCommandJson';
  const names = [commandName, 'sheetsRangeCatalogJson', 'sheetsRangeFailureJson', 'sheetsRangeDeclarationConstructionCapacity'];
  const originals = Object.fromEntries(names.map(name => [name, checkedSourceMethod(providerMoon, name)]));
  const native = Object.freeze(Object.fromEntries(names.map(name => [name,
    (...args) => Reflect.apply(originals[name], providerMoon, args)])));
  const columnsWire = JSON.stringify(site.columns), rangeWire = JSON.stringify(site.gridRange);
  const connectorId = profile.connectorId;
  const limits = [SHEETS_LIMITS.maxResponseBytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
  const projection = Object.freeze({
    capacity(declaredWire) {
      return native.sheetsRangeDeclarationConstructionCapacity(Buffer.byteLength(columnsWire), site.columns.length,
        Buffer.byteLength(rangeWire), Buffer.byteLength(connectorId), Buffer.byteLength(declaredWire));
    },
    project(declaredWire) {
      const definitionWire = sheetsOwnedResult(native,
        native[commandName](connectorId, columnsWire, rangeWire, ...limits));
      const wire = sheetsOwnedResult(native, native.sheetsRangeCatalogJson(declaredWire, definitionWire, ...limits));
      const definition = Object.freeze(JSON.parse(definitionWire));
      return Object.freeze({declared: Object.freeze(JSON.parse(wire)), wire,
        commands: Object.freeze([definition.installed]), definition});
    },
  });
  return Reflect.apply(constructor.value, sourceInitialization, [viewsWire, projection, expectedCatalogCid]);
}

function restore(moon, providerMoon, profile, site, expectedCatalogCid, sourceInitialization) {
  if (profile.rangeCommand) {
    const schema = Object.fromEntries(site.columns.map(({name, type, nullable}) =>
      [name, {type, nullable}]));
    const view = (resource, resource_kind, schema) => ({resource, resource_kind,
      schema_wire: canonicalJson(schema), schema_cid: contentCid(schema)});
    const views = {views: [view('rows', 'sheet_rows', schema),
      view('range_target', 'sheet_range', {
        target: {type: 'resource_ref', resource_kind: 'sheet_range', nullable: false}})]};
    const viewsWire = JSON.stringify(views);
    if (sourceInitialization !== undefined) {
      return prepareInitializedSheetsCommandDeclaration(sourceInitialization, providerMoon, profile, site, viewsWire, expectedCatalogCid);
    }
    const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
      profile.connectorId, registration, revision, viewsWire, undefined));
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
  if (sourceInitialization !== undefined) {
    const constructor = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareAuthoredDeclaration');
    if (!constructor || !Object.hasOwn(constructor, 'value') || typeof constructor.value !== 'function') {
      fail('InstalledSheetsInitializationUnavailable');
    }
    return Reflect.apply(constructor.value, sourceInitialization, [views, expectedCatalogCid]);
  }
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    profile.connectorId, registration, revision, views, expectedCatalogCid));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  return {declaration, declared};
}
function mappingOf(moon, profile, site, declaration, sourceInitialization) {
  const writes = JSON.stringify({writes: [{resource: 'append_rows',
    resource_kind: 'sheet_collection', primary_identity: null,
    collection_identity: {spreadsheet_id: site.spreadsheetId, sheet_id: site.appendSheetId},
    fields: site.columns, create: {fields: site.columns.map(column => column.name),
      required: site.columns.map(column => column.name),
      permission: SHEETS_APPEND_OPERATION, approval: 'required'}}]});
  if (sourceInitialization !== undefined) {
    const constructor = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareMappings');
    if (!constructor || !Object.hasOwn(constructor, 'value') || typeof constructor.value !== 'function') {
      fail('InstalledSheetsInitializationUnavailable');
    }
    const sources = Object.freeze(profile.sources.map(source => Object.freeze({...source})));
    return Reflect.apply(constructor.value, sourceInitialization,
      [writes, Object.freeze([Object.freeze({resource: 'append_rows', sources})])]);
  }
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

async function readPublication(profile, site, declared, originalRead) {
  const publication = await readJson(profile.publicationPath, originalRead);
  const {publication_cid, ...preimage} = publication;
  if (!exact(publication, ['version', 'connectorId', 'catalogCid', 'binding', 'publication_cid']) ||
      publication.version !== publicationVersion || publication.connectorId !== profile.connectorId ||
      publication.catalogCid !== declared.catalog_cid || publication_cid !== contentCid(preimage) ||
      canonicalJson(publication.binding) !== canonicalJson(bindingFacts(site))) {
    fail('SheetsPublicationBindingChanged');
  }
  return publication;
}

async function openSite(profile, site, options, publication, installationServices) {
  const {root, principalId, moon, runtimeBundleCid, installation} = options;
  const connection = `sheets:${new URL(site.apiOrigin).host}/${site.spreadsheetId}`;
  const configuration = {profile: Object.freeze({...site, resourceOrigin: site.apiOrigin}),
    ca: site.ca, responseHeaders: installation?.responseHeaders ?? [],
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
        ? field === 'target' : site.columns.some(column => column.name === field))};
  let authorization, opened;
  if (installationServices !== undefined) {
    const open = Object.getOwnPropertyDescriptor(installationServices, 'openRowSite');
    if (!open || !Object.hasOwn(open, 'value') || typeof open.value !== 'function') {
      fail('InvalidInstalledEffectSiteServices');
    }
    ({authorization, site: opened} = await Reflect.apply(open.value, installationServices, [{
      installation,
      ...(options.sourceInitialization === undefined ? {} : {sourceInitialization: options.sourceInitialization}),
      accountConfiguration: profile.accountConfigurationWire,
      ...(options.runAcquisitionLimits === undefined ? {} : {runAcquisitionLimits:options.runAcquisitionLimits}),
      connection, ...configuration}]));
  } else {
    authorization = await installRowSourceAuthorization({
      accountConfiguration: profile.accountConfigurationWire, principalId, root,
      connectorRegistration: registration});
    opened = await openRowSourceCredentialSite({...configuration, principalId, authorization,
      connection, connectorRegistration: registration, connectorRevision: revision,
      runtimeBundleCid, commonMoon: moon});
  }
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

// Bind the existing native constructor once to the SAME validated private
// installation metadata. The original Plan supplies its existing input bound;
// the complete returned Option/tuple stays opaque until Core consumes it.
function bindSheetsAppendConstructionProfile(providerMoon, columns) {
  if (providerMoon === null || !['object', 'function'].includes(typeof providerMoon) ||
      nodeTypes.isProxy(providerMoon)) fail('InstalledStandardCreateRuntimeUnavailable');
  const native = Object.getOwnPropertyDescriptor(providerMoon, 'sheetsAppendRequestConstructionProfile');
  if (!native || !Object.hasOwn(native, 'value') || typeof native.value !== 'function' ||
      nodeTypes.isProxy(native.value) || nodeTypes.isAsyncFunction(native.value)) {
    fail('InstalledStandardCreateRuntimeUnavailable');
  }
  const schemaBytes = Buffer.byteLength(JSON.stringify(columns), 'utf8');
  const columnCount = columns.length;
  return Object.freeze({installedStandardCreateConstructionProfile(inputWireBytes, inputNodes, inputDepth) {
    return Reflect.apply(native.value, providerMoon, [schemaBytes, columnCount, inputWireBytes, inputNodes, inputDepth,
      SHEETS_LIMITS.maxRequestBytes, SHEETS_LIMITS.maxResponseBytes,
      SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth]);
  }});
}

// Preserve this implementation's existing response/cell limits. These are
// rejection/representation bounds, not user resource knobs or an admission.
function sheetsGridReaderLimits(site, publication, secretBytes, rangeCommand = false) {
  const rows = SHEETS_LIMITS.maxRows, columns = site.columns.length;
  const names = site.columns.map(column => column.name);
  const target = {version: targetVersion, catalog_cid: publication.catalogCid,
    binding: bindingFacts(site), fields: names, ...(rangeCommand ? {resource:'range_target'} : {})};
  const nameUnits = names.reduce((sum, name) => sum + name.length, 0);
  return Object.freeze({maxResponseBytes:SHEETS_LIMITS.maxResponseBytes,
    maxTotalResponseBytes:SHEETS_LIMITS.maxResponseBytes,
    maxNodes:SHEETS_LIMITS.maxNodes,maxDepth:SHEETS_LIMITS.maxDepth,
    maxRows:rows,maxTotalRows:rows,maxPages:1,pageSize:rows,
    // This one-page grid reader retains no cursor or row-identity strings.
    // Positive unused dimensions satisfy the common recipe grammar; these
    // are not cell-value limits (including a declared column named "id").
    maxCursorBytes:1,maxIdentityBytes:1,
    // The other declared relation has a single field named "target". Its
    // name may be longer than this grid's complete projected name vector.
    maxTargetBytes:Buffer.byteLength(JSON.stringify(target))+
      (rangeCommand?Buffer.byteLength(JSON.stringify(['target'])):0),
    maxValueNodes:1,maxValueTextBytes:SHEETS_LIMITS.maxResponseBytes,
    // The scalar values borrow at most the original response text. Each
    // original UTF16 unit may escape to six ASCII units; repeated column keys
    // and row punctuation are bounded independently by this exact schema.
    maxRowsWireBytes:6*SHEETS_LIMITS.maxResponseBytes + rows*(6*nameUnits+4*columns+3)+2,
    maxRowsWireNodes:1+rows*(columns+1),maxRowsWireDepth:4,maxSecretBytes:secretBytes});
}

function prepareInitializedSheetsReadTarget(sourceInitialization, providerMoon, site, catalogCid, bindingCid) {
  const field = Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareReadTarget');
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
    fail('InstalledSheetsInitializationUnavailable');
  }
  const names = ['sheetsRangeReferenceConstructionCapacity', 'sheetsRangeReferenceJson', 'sheetsRangeFailureJson'];
  const originals = Object.fromEntries(names.map(name => [name, checkedSourceMethod(providerMoon, name)]));
  const native = Object.freeze(Object.fromEntries(names.map(name => [name,
    (...args) => Reflect.apply(originals[name], providerMoon, args)])));
  return Reflect.apply(field.value, sourceInitialization, [Object.freeze({
    capacity() {
      return native.sheetsRangeReferenceConstructionCapacity(Buffer.byteLength(site.apiOrigin),
        Buffer.byteLength(site.spreadsheetId));
    },
    project() {
      return sheetsRangeReference({site, catalogCid, bindingCid, moon: native});
    },
  })]);
}

function prepareInitializedSheetsEffectDriver(sourceInitialization, providerMoon, site, catalogCid, bindingCid, command, clear, isCurrent) {
  const constructor = checkedSourceMethod(sourceInitialization, 'prepareEffectDriverConstruction');
  const names = ['sheetsRangeInstallationConstructionCapacity', 'sheetsRangeReferenceJson', 'sheetsRangeFailureJson',
    ...(clear ? ['sheetsClearBinding', 'sheetsClearPrepare', 'sheetsClearTargetMatches',
      'sheetsClearRequestJson', 'sheetsClearRequestBody', 'sheetsClearRequestCid', 'sheetsClearOutcomeJson',
      'sheetsClearRecoveryEntryJson', 'sheetsClearRecover', 'sheetsClearConstructionProfile', 'sheetsClearCaptureConstructionProfile']
      : ['sheetsRangeBinding', 'sheetsRangePrepare', 'sheetsRangeTargetMatches',
        'sheetsRangeRequestJson', 'sheetsRangeRequestBody', 'sheetsRangeRequestCid', 'sheetsAppendOutcomeJson',
        'sheetsRangeRecoveryEntryJson', 'sheetsRangeRecover', 'sheetsRangeConstructionProfile', 'sheetsRangeCaptureConstructionProfile'])];
  // Capture original provider methods/receivers before reserve/current can
  // reenter. Both the retained binding and its later Plan use this view.
  const originals = Object.fromEntries(names.map(name => [name, checkedSourceMethod(providerMoon, name)]));
  const native = Object.freeze(Object.fromEntries(names.map(name => [name,
    (...args) => Reflect.apply(originals[name], providerMoon, args)])));
  const configurationBytes = sheetsRangeConfigurationBytes(site);
  return Reflect.apply(constructor, sourceInitialization, [Object.freeze({
    capacity() {
      return native.sheetsRangeInstallationConstructionCapacity(configurationBytes, site.columns.length,
        Buffer.byteLength(site.apiOrigin), Buffer.byteLength(site.spreadsheetId));
    },
    project() {
      const target = sheetsRangeReference({site, catalogCid, bindingCid, moon: native});
      const driver = (clear ? createSheetsClearDriver : createSheetsRangeDriver)({moon: native, site,
        command, bindingCid, target, isCurrent});
      return Object.freeze({target, driver});
    },
  })]);
}

async function loadManagedSheetsGridSource(profile, options, site, publication, prepared) {
  const {moon,providerMoon,sourceInitialization,installation,installationServices}=options;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledSheetsSourceServicesUnavailable'),{code:'InstalledSheetsSourceServicesUnavailable'}));
  const policy=checkedSourceMethod(moon,'clientProgramInstalledSourceReaderPolicy');
  const selected=Reflect.apply(policy,moon,[]);
  if(!Array.isArray(selected)||selected.length!==3||selected.some(n=>!Number.isSafeInteger(n)||n<1)) {
    fail('InstalledSheetsSourcePolicyUnavailable');
  }
  const rangeCommand=profile.rangeCommand===true||profile.rangeCommand==='clear';
  const quote=checkedSourceMethod(providerMoon,rangeCommand?'sheetsRangeReadConstructionCapacity':'sheetsGridReadConstructionCapacity');
  const requestCapacity=Reflect.apply(quote,providerMoon,[Buffer.byteLength(JSON.stringify(site.columns)),
    site.columns.length,...[site.gridRange.sheetId,site.gridRange.startRow,site.gridRange.endRow,
      site.gridRange.startColumn,site.gridRange.endColumn],
    ...(rangeCommand?[SHEETS_LIMITS.maxNodes,SHEETS_LIMITS.maxDepth]:[])]);
  const limits=sheetsGridReaderLimits(site,publication,selected[0],rangeCommand);
  const requestConstruction=Object.freeze({capacity:requestCapacity,maxRequestBytes:SHEETS_LIMITS.maxRequestBytes});
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,limits,
    columnCount:site.columns.length,preservingRequestConstruction:requestConstruction});
  let opened,providerReader,closed=false;
  try {
    opened=await openSite(profile,site,{...options,runAcquisitionLimits:implementation.runAcquisitionLimits},
      publication,installationServices);
    const target=rangeCommand?prepareInitializedSheetsReadTarget(sourceInitialization,providerMoon,site,
      prepared.declared.catalog_cid,opened.bindingCid):undefined;
    const targetWire=target===undefined?undefined:canonicalJson(target);
    const targetSite=opened.site;
    const referenceCurrent=target===undefined?undefined:checkedSourceMethod(targetSite,'referenceCurrent');
    const targetCurrent=()=>!closed&&Reflect.apply(referenceCurrent,targetSite,[])===true;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site:opened.site,
      operation:SHEETS_READ_OPERATION,preparePageReader({resource,columns},applySynchronousProjection){
        if(rangeCommand&&resource==='range_target')return prepareSheetsRangeTargetPages({moon:providerMoon,
          spreadsheetId:site.spreadsheetId,columns:site.columns,range:site.gridRange,names:columns,
          limits:SHEETS_LIMITS,target},applySynchronousProjection);
        if(resource!=='rows')fail('UndeclaredSheetsResource');
        return prepareSheetsGridPages({moon:providerMoon,spreadsheetId:site.spreadsheetId,
          columns:site.columns,range:site.gridRange,names:columns,limits:SHEETS_LIMITS},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledSheetsReaderImplementationMismatch');
    const {declaration,declared,environment}=prepared;
    const adapter=await createInstalledRowSource({moon,declaration,declared,environment,environmentWire:environment.wire,
      ...(prepared.commands===undefined?{}:{commands:prepared.commands}),
      sourceInitialization,connectorId:profile.connectorId,connectorRegistration:registration,connectorRevision:revision,
      site:opened.site,authorization:opened.authorization,readOperation:SHEETS_READ_OPERATION,bindingCid:opened.bindingCid,
      physicalTarget(resource,fields){if(resource!=='rows'&&!(rangeCommand&&resource==='range_target'))fail('UndeclaredSheetsResource');
        return Object.freeze({version:targetVersion,catalog_cid:publication.catalogCid,
          binding:bindingFacts(site),fields:Object.freeze([...fields]),...(rangeCommand?{resource}:{})});},
      ...(target===undefined?{}:{referenceIssuer:moon.clientProgramResourceReferenceIssuer(
        (kind,wire)=>kind==='sheet_range'&&wire===targetWire&&targetCurrent(),targetCurrent)}),
      limits:{maxPages:1,maxPageBytes:SHEETS_LIMITS.maxResponseBytes,maxPageRows:SHEETS_LIMITS.maxRows,
        maxCaptureRows:SHEETS_LIMITS.maxRows},providerReader});
    // Keep the exact adapter retained by the Source initializer. Reference
    // currentness follows the original Site's own close/current lifetime;
    // a copied facade cannot finish this nominal Source construction.
    return adapter;
  }catch(cause){closed=true;throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:opened?.site});}
}

function checkedSourceMethod(receiver,name) {
  if(receiver===null||!['object','function'].includes(typeof receiver)||nodeTypes.isProxy(receiver)) {
    fail('InstalledSheetsSourceRuntimeUnavailable');
  }
  const field=Object.getOwnPropertyDescriptor(receiver,name);
  if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function'||
      nodeTypes.isProxy(field.value)||nodeTypes.isAsyncFunction(field.value))fail('InstalledSheetsSourceRuntimeUnavailable');
  return field.value;
}

async function load(profile, options, effect) {
  const {moon, providerMoon, sourceInitialization, configurationReader} = options;
  if (sourceInitialization === undefined) fail('InstalledSheetsInitializationUnavailable');
  if (configurationReader === undefined) fail('InstalledSheetsConfigurationReaderUnavailable');
  if (options.installationServices === undefined) fail('InvalidInstalledEffectSiteServices');
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => fail('InstalledSheetsConfigurationReaderUnavailable'));
  const site = await readSite(profile.siteProfilePath, providerMoon, readers);
  const restored = restore(moon, providerMoon, profile, site, undefined, sourceInitialization);
  const {declaration, declared} = restored;
  const rangeCommand = restored.commandDefinition ?? restored.rangeCommand;
  const publication = await readPublication(profile, site, declared, readers?.readJson);
  const prepared = effect && rangeCommand === undefined
    ? mappingOf(moon, profile, site, declaration, sourceInitialization) : undefined;
  const mappings = prepared?.mappings;
  const environment = effect && rangeCommand === undefined ? prepared.environment : restored.environment;
  if (!effect) return loadManagedSheetsGridSource(profile, options, site, publication, restored);
  const opened = await openSite(profile, site, options, publication,
    options.installationServices);
  let closed = false;
  try {
    const referenceCurrent = rangeCommand === undefined ? undefined
      : checkedSourceMethod(opened.site, 'referenceCurrent');
    const isCurrent = () => !closed && (referenceCurrent === undefined ||
      Reflect.apply(referenceCurrent, opened.site, []) === true);
    const construction = rangeCommand === undefined ? undefined
      : prepareInitializedSheetsEffectDriver(sourceInitialization, providerMoon, site, declared.catalog_cid,
        opened.bindingCid, rangeCommand.installed, profile.rangeCommand === 'clear', isCurrent);
    if (rangeCommand !== undefined) {
      const driver = construction.driver;
      return await createInstalledRowEffect({moon,
      providerMoon: driver.managedPlanProvider, managedPlanDefinition: driver.managedPlanDefinition,
      managedPlanConstruction: driver.managedPlanConstruction,
      commands: restored.commands ?? [rangeCommand.installed],
      declaration, declared, environment, sourceInitialization, environmentWire: environment.wire,
      connectorId: profile.connectorId, connectorRegistration: registration, connectorRevision: revision,
      connection: opened.connection, site: opened.site, authorization: opened.authorization,
      runtimeBundleCid: options.runtimeBundleCid, bindingCid: opened.bindingCid,
      ledgerRoot: options.ledgerRoot, installation: options.installation,
      driver});
    }
    const boundaryCid = contentCid({version: 'actql-sheets-append-boundary/0.1',
      api_origin: site.apiOrigin, spreadsheet_id: site.spreadsheetId, sheet_id: site.appendSheetId});
    return await createInstalledRowEffect({moon,
      providerMoon: bindSheetsAppendConstructionProfile(providerMoon, site.columns),
      mappings, declaration, declared, environment, sourceInitialization,
      environmentWire: environment.wire,
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
          http: {origin: site.apiOrigin, ...prepareSheetsTargetRequest(site.spreadsheetId),
            headers: [['accept', 'application/json']],
            maxRequestBytes: SHEETS_LIMITS.maxRequestBytes, maxResponseBytes: SHEETS_LIMITS.maxResponseBytes},
          body() {return undefined;},
          project({accepted, observation}) {
            return projectSheetsTarget({moon: providerMoon, spreadsheetId: site.spreadsheetId,
              columns: site.columns, range: site.gridRange, appendSheetId: site.appendSheetId,
              response: {accepted, statusCode: observation.statusCode, body: observation.body}});
          }},
        classify: options => projectSheetsAppend({...options, moon: providerMoon})}});
  } catch (cause) {
    closed = true;
    throw await retainInstalledHostInitializationFailure(cause, {installedEffect: opened.site});
  }
}
export const loadInstalledSheetsSource = (profile, options) =>
  load(checkInstalledSheetsSourceProfile(profile), options, false);
export const loadInstalledSheetsEffect = (profile, options) =>
  load(checkInstalledSheetsEffectProfile(profile), options, true);
