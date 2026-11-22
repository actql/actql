// The standard Host's provider-neutral installed row source. A connector
// whose Site driver returns pages of JSON rows (keyed by its declared field
// names) is installed through this adapter: declaration restore, Check
// Environment, read decisions, credential grants, acquisition, capture and
// Source Evidence are the common runtime's and this module's; the connector
// supplies only its view specification, its physical target and its page
// driver. No provider name or type appears here.
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {fileURLToPath} from 'node:url';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {canonicalJson, contentCid} from
  './local-account-config.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction,
  closeInstalledSourceConstruction, prepareInstalledSourceAcquisitionContracts, readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import {valueCid} from './installed-row-source-environment.mjs';
import {installRowSourceAuthorization} from './installed-row-source-authorization.mjs';
import {encodeTypedResponseJson} from './typed-response-json-codec.mjs';
import {prepareImmutablePhysicalTargets} from './installed-row-source-targets.mjs';
import {createInstalledRowSourceCredentialSite} from './installed-row-source-credential-site.mjs';
import {createInstalledRowSourceReadAuthority} from './installed-row-source-read-authority.mjs';
import {createInstalledRowSourceKeyedPreparation} from './installed-row-source-keyed-preparation.mjs';
import {createInstalledRowSourceKeyedRead} from './installed-row-source-keyed-read.mjs';
import {createInstalledRowSourceKeyedLookup} from './installed-row-source-keyed-lookup.mjs';
import {createInstalledRowSourcePreparation} from './installed-row-source-preparation.mjs';
import {createInstalledRowSourceAcquisition} from './installed-row-source-acquisition.mjs';

export {rowSourceMapping} from './installed-row-source-mapping.mjs';
export {rowSourceCheckEnvironment} from './installed-row-source-environment.mjs';
export {installRowSourceAuthorization, encodeTypedResponseJson};
const text = value => typeof value === 'string' && value.length > 0;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const contractRoot = new URL('../../spec/contracts/', import.meta.url);

export const {installedRowCredentialOperationSite, loadRowSourceCredentialCustody,
  openRowSourceCredentialCustody, openRowSourceCredentialSite, openInstalledRowSite} =
  createInstalledRowSourceCredentialSite({runtimeCore, text, cidPattern});

// The installed source adapter of one row declaration (see
// `installed-source.mjs`). `readPages({resource, columns, requestWire, operation,
// authorizationFor, chargePage, consumeObservation, consumePage, listing, signal})`
// is the Site driver.
// A checked listing uses listing.beginRequest(token) before each actual send
// and awaits listing.consumePage(fullEnvelope, {charge}) for all observed items.
// Provider translation charges the original response before decoding; its
// exact ticket carries physical bytes into the common listing budget.
// An accounted ordinary acquisition can consume a non-row observation's exact
// ticket without adding a data page. Its request authorization/count and typed
// observation remain the installed driver's responsibility; this is no grant.
// ordinary rows use consumePage. Completion is never the driver's return alone;
// `physicalTarget(resource, fields)` the exact target an approval covers.
// Standard installations may instead supply their frozen full target DATA
// inventory. It has no authorization/current/physical cleanup methods.
export async function createInstalledRowSource({moon, declaration, commands,
  declared, environmentWire, environment, sourceInitialization, connectorId, connectorRegistration,
  connectorRevision, site, authorization, readOperation, physicalTarget,
  readPages, bindingCid, publicationBindingCid, tableReadTargets, publication,
  publicationSurface, realizationKey = 'row-source-acquired', limits, referenceIssuer, listingPolicy, captureContent,
  listingReportCapacity, prepareAcquisition, directReadIdentity,
  prepareRead, grantBeforeBegin = false, originalSourceAccess, providerReader,
  prepareSourceRead, closeSourceRead, prepareKeyedSourceRead, closeKeyedSourceRead,
  originalKeyedTransport, readAsset, originalPageLimits}) {
  if (typeof realizationKey !== 'string' || realizationKey.length === 0) fail('InvalidInstalledSourcePublication');
  let selectedSurface;
  if (publicationSurface !== undefined) {
    if (!Array.isArray(publicationSurface) || nodeTypes.isProxy(publicationSurface) ||
        !Object.isFrozen(publicationSurface)) fail('InvalidInstalledSourcePublication');
    selectedSurface = [];
    for (let i = 0; i < publicationSurface.length; i++) {
      const field = Object.getOwnPropertyDescriptor(publicationSurface, String(i));
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string' ||
          selectedSurface.includes(field.value)) fail('InvalidInstalledSourcePublication');
      selectedSurface.push(field.value);
    }
    if (['realizationKey','supportsRetainedRelationOutput','connectorRegistration','connectorRevision',
      'environmentWire','connectorBindings','readAuthorization','sourceAccess','sourceReadAccesses',
      'admitsSource','ledgerCapacity','prepare','open','close'].some(key => !selectedSurface.includes(key))) {
      fail('InvalidInstalledSourcePublication');
    }
    // Common preparation cleanup is part of the original Source lifecycle.
    // A provider's publication selection cannot hide an unentered read owner.
    for (const name of ['retirePreparedSource', 'prepareRetained',
      ...(environment === undefined ? [] : ['environmentOriginal'])]) {
      if (!selectedSurface.includes(name)) selectedSurface.push(name);
    }
  }
  let publicationFields = {};
  if (publication !== undefined) {
    if (!publication || typeof publication !== 'object' || nodeTypes.isProxy(publication) ||
        !Object.isFrozen(publication) ||
        ![Object.prototype, null].includes(Object.getPrototypeOf(publication))) fail('InvalidInstalledSourcePublication');
    publicationFields = Object.getOwnPropertyDescriptors(publication);
    for (const key of Reflect.ownKeys(publicationFields)) {
      if (typeof key !== 'string' || key === 'then' ||
          !Object.hasOwn(publicationFields[key], 'value')) fail('InvalidInstalledSourcePublication');
    }
  }
  const readerDemand = sourceInitialization === undefined ? undefined
    : assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, providerReader, undefined, commands);
  const retainedAcquisitionContracts = sourceInitialization !== undefined && prepareAcquisition === undefined;
  const prepareWithContracts = !retainedAcquisitionContracts ? undefined
    : moon.clientProgramRowSourcePrepareAcquisitionWithContracts;
  if (retainedAcquisitionContracts && typeof prepareWithContracts !== 'function') {
    fail('InstalledSourceInitializationRuntimeUnavailable');
  }
  if (sourceInitialization !== undefined && environment?.wire !== environmentWire) {
    fail('ForeignInstalledSourceConstruction');
  }
  // Trusted installation compatibility only: preserve an existing provider
  // identity and ordering while this one Owner retains preparation, current
  // authorization, RowRun, capture and failure cleanup. No wire selects this
  // port and none of these callbacks issues authority or a cleanup ACK.
  if (directReadIdentity !== undefined &&
      (directReadIdentity === null || typeof directReadIdentity !== 'object' ||
        Array.isArray(directReadIdentity) || !Object.isFrozen(directReadIdentity) ||
        Object.getPrototypeOf(directReadIdentity) !== Object.prototype ||
        Object.keys(directReadIdentity).sort().join("\0") !==
          ["attempt", "input", "subject", "useId"].join("\0") ||
        !Number.isSafeInteger(directReadIdentity.input) || directReadIdentity.input < 0 ||
        !["subject", "attempt", "useId"].every(key =>
          typeof directReadIdentity[key] === "function"))) {
    fail("InvalidInstalledSourceReadIdentity");
  }
  if ((prepareRead !== undefined && typeof prepareRead !== "function") ||
      typeof grantBeforeBegin !== "boolean") {
    fail("InvalidInstalledSourceReadPreparation");
  }
  // One trusted installation's original declaration and I/O-free preparer.
  // Public packets/configuration cannot replace either after preparation.
  // The declaration is DATA; Core still reserves on the original Run Ledger.
  let originalReader;
  // Managed and advanced page readers are distinct installation alternatives.
  // A managed reader never needs a dummy or fallback unaccounted readPages.
  if (providerReader === undefined ? typeof readPages !== 'function' : readPages !== undefined) {
    fail('InvalidInstalledSourceReader');
  }
  if ((prepareKeyedSourceRead !== undefined || closeKeyedSourceRead !== undefined) &&
      (typeof prepareKeyedSourceRead !== 'function' || typeof closeKeyedSourceRead !== 'function' ||
        providerReader !== undefined || listingReportCapacity !== undefined ||
        ['clientProgramInstalledKeyedSourceReadCheckCurrent',
          'clientProgramInstalledKeyedSourceReadAcquisition',
          'clientProgramInstalledKeyedSourceReadRetire']
          .some(name => typeof moon?.[name] !== 'function'))) fail('InstalledKeyedSourceReadUnavailable');
  if (prepareSourceRead !== undefined && (typeof prepareSourceRead !== 'function' ||
      providerReader !== undefined || listingReportCapacity !== undefined ||
      ['clientProgramInstalledSourceReadCheckCurrent', 'clientProgramInstalledSourceReadBindProgram',
        'clientProgramInstalledSourceReadBindEffectProgram', 'clientProgramInstalledSourceReadAttachAcquisition']
        .some(name => typeof moon?.[name] !== 'function'))) fail('InstalledSourceReadUnavailable');
  if (closeSourceRead !== undefined && (typeof closeSourceRead !== 'function' ||
      prepareSourceRead === undefined)) fail('InstalledSourceReadUnavailable');
  // Only the original local Source consumer can borrow these private
  // installation inputs. Neither option is a public packet or a capacity
  // issuer; the same RowRun still admits its actual original child below.
  if (readAsset !== undefined && (prepareSourceRead === undefined ||
      typeof readAsset !== 'function')) fail('InstalledSourceReadUnavailable');
  let pageLimits;
  if (originalPageLimits !== undefined) {
    if (prepareSourceRead === undefined || originalPageLimits === null ||
        typeof originalPageLimits !== 'object' || nodeTypes.isProxy(originalPageLimits) ||
        Object.getPrototypeOf(originalPageLimits) !== Object.prototype) fail('InvalidInstalledSourcePageLimits');
    const properties = Object.getOwnPropertyDescriptors(originalPageLimits);
    if (Reflect.ownKeys(properties).length !== 2 || ['maxNodes', 'maxDepth'].some(name =>
      !Object.hasOwn(properties[name] ?? {}, 'value') ||
      !Number.isSafeInteger(properties[name].value) || properties[name].value < 1 ||
      properties[name].value > 2147483647) ||
      typeof moon.clientProgramRowSourceBeginWithPageLimits !== 'function') fail('InvalidInstalledSourcePageLimits');
    pageLimits = Object.freeze({maxNodes: properties.maxNodes.value, maxDepth: properties.maxDepth.value});
  }
  if (providerReader !== undefined) {
    if (providerReader === null || typeof providerReader !== 'object' ||
        nodeTypes.isProxy(providerReader)) fail('InvalidInstalledSourceReader');
    const fields = Object.getOwnPropertyDescriptors(providerReader);
    const names = Reflect.ownKeys(fields);
    if (names.length !== (Object.hasOwn(fields, 'retire') ? 3 : 2) ||
        ['capacity', 'prepare'].some(function invalidReaderField(name) {
          return !Object.hasOwn(fields[name] ?? {}, 'value');
        }) ||
        Object.hasOwn(fields, 'retire') && (!Object.hasOwn(fields.retire, 'value') ||
          typeof fields.retire.value !== 'function')) fail('InvalidInstalledSourceReader');
    const capacity = fields.capacity.value, prepare = fields.prepare.value;
    const retire = fields.retire?.value;
    if (capacity === undefined || capacity === null || typeof prepare !== 'function' ||
        listingReportCapacity !== undefined) fail('InvalidInstalledSourceReader');
    if (['clientProgramInstalledProviderRowCaptureCapacity',
      'clientProgramInstalledProviderRowCaptureCapacityMatches',
      'clientProgramRowSourceStartProviderAccounted', 'clientProgramRowSourceBorrowResponses',
      'clientProgramRowSourceBindResponseCleanup'].some(name => typeof moon?.[name] !== 'function')) {
      fail('InstalledProviderSourceUnavailable');
    }
    originalReader = Object.freeze({capacity, prepare, retire, receiver: providerReader});
  }
  let managedPageLimits;
  if (readerDemand !== undefined) {
    // This is the SAME immutable service selection already checked against
    // this declaration/Environment/reader, not the legacy preparer option.
    if (nodeTypes.isProxy(readerDemand)) fail('InvalidInstalledSourceReaderPageDemand');
    const nodes = Object.getOwnPropertyDescriptor(readerDemand, 'maxNodes');
    const depth = Object.getOwnPropertyDescriptor(readerDemand, 'maxDepth');
    if (!nodes || !depth || !Object.hasOwn(nodes, 'value') || !Object.hasOwn(depth, 'value') ||
        !Number.isSafeInteger(nodes.value) || nodes.value < 1 || nodes.value > 2147483647 ||
        !Number.isSafeInteger(depth.value) || depth.value < 1 || depth.value > 2147483647 ||
        typeof moon.clientProgramRowSourceBeginWithPageLimits !== 'function') {
      fail('InvalidInstalledSourceReaderPageDemand');
    }
    managedPageLimits = Object.freeze({maxNodes: nodes.value, maxDepth: depth.value});
  }
  if (prepareAcquisition !== undefined &&
      (typeof prepareAcquisition !== 'function' ||
        typeof moon?.clientProgramRowSourceCheckOriginalAcquisition !== 'function')) {
    fail('InvalidInstalledSourceAcquisitionPreparer');
  }
  if (captureContent !== undefined && typeof captureContent !== 'function') {
    fail('InvalidInstalledContentCapture');
  }
  // Exact trusted installation declaration, not a packet value or a callback
  // capable of choosing another capacity after acquisition. The installation
  // must justify it for every listing selector admitted by this declaration,
  // target and limits. Absence keeps the existing non-report profile; it does
  // not manufacture the completed-report guarantees or a Model grant.
  if (listingReportCapacity !== undefined &&
      (listingReportCapacity === null || typeof listingReportCapacity !== 'object' ||
        Array.isArray(listingReportCapacity))) {
    fail('InvalidInstalledListingReportCapacity');
  }
  if (listingReportCapacity !== undefined &&
      (typeof moon?.clientProgramInstalledListingRowCaptureCapacity !== 'function' ||
        typeof moon?.clientProgramRowSourceStartListingAccounted !== 'function')) {
    fail('InstalledListingSourceUnavailable');
  }
  const [queryContract, evidenceContract] = readAsset === undefined
    ? await Promise.all(['actql-query-acquisition.json', 'actql-query-process-evidence.json']
      .map(name => sourceInitialization !== undefined
        ? readInstalledSourceAcquisitionContract(sourceInitialization, fileURLToPath(new URL(name,contractRoot)))
        : readFile(new URL(name, contractRoot), 'utf8')))
    : ['actql-query-acquisition.json', 'actql-query-process-evidence.json']
      .map(name => readAsset(`spec/contracts/${name}`));
  if (typeof queryContract !== 'string' || typeof evidenceContract !== 'string') {
    fail('InstalledSourceReadUnavailable');
  }
  // The default normal constructor retains one admitted protocol original on
  // its SAME initialization material. Existing provider-specific preparers and
  // explicit legacy constructors keep their original raw-wire entry law.
  let acquisitionContracts = retainedAcquisitionContracts
    ? prepareInstalledSourceAcquisitionContracts(sourceInitialization, queryContract, evidenceContract) : undefined;
  const constructReadMetadata = () => {
    const sourceRefs = new Set();
    const sourceReadAccesses = Object.freeze(declared.views.map(view => {
      sourceRefs.add(view.source_ref);
      return Object.freeze({authorization, connection: site.connection,
        sourceRef: view.source_ref, resource: view.resource});
    }));
    return Object.freeze({sourceRefs, sourceReadAccesses});
  };
  const {sourceRefs, sourceReadAccesses} = sourceInitialization === undefined
    ? constructReadMetadata()
    : sourceInitialization.prepareReadMetadata(declared, constructReadMetadata);
  if (!['maxPages', 'maxPageBytes', 'maxPageRows', 'maxCaptureRows']
    .every(key => Number.isSafeInteger(limits?.[key]) && limits[key] > 0 &&
      limits[key] <= 2_147_483_647)) {
    fail('InvalidInstalledRowSourceLimits');
  }
  if (readerDemand !== undefined && (limits.maxPages !== readerDemand.queryPages ||
      limits.maxPageBytes !== readerDemand.maxResponseBytes || limits.maxPageRows !== readerDemand.maxRows ||
      limits.maxCaptureRows !== readerDemand.maxTotalRows)) fail('ForeignInstalledSourceReaderDemand');
  const maxTransferBytes = readerDemand?.transferBytes ??
    BigInt(limits.maxPages) * BigInt(limits.maxPageBytes);
  let keyedTransferBytes = maxTransferBytes, keyedExecutionBytes = BigInt(limits.maxPageBytes);
  if (originalKeyedTransport !== undefined) {
    // Fixed installing Source limits, not a public packet, grant or Resource
    // original. Actual same-Run admission must cover this complete transport
    // workspace, including collected native bytes beside encoding/capture.
    if (prepareKeyedSourceRead === undefined || originalKeyedTransport === null ||
        typeof originalKeyedTransport !== 'object' || nodeTypes.isProxy(originalKeyedTransport)) {
      fail('InvalidInstalledKeyedTransportLimits');
    }
    const fields = Object.getOwnPropertyDescriptors(originalKeyedTransport);
    if (Reflect.ownKeys(fields).length !== 2 || ['transferBytes', 'executionBytes'].some(name =>
      !Object.hasOwn(fields[name] ?? {}, 'value') || typeof fields[name].value !== 'bigint' ||
      fields[name].value < 0n || fields[name].value > 9223372036854775807n)) {
      fail('InvalidInstalledKeyedTransportLimits');
    }
    keyedTransferBytes = fields.transferBytes.value;
    keyedExecutionBytes = fields.executionBytes.value;
  }
  // A plural Source can expose separately registered metadata/content reads.
  // Copy its closed Resource->operation binding once; a Run's selected view
  // cannot substitute another operation or inherit a missing view's grant.
  const resources = new Set(declared.views.map(view => view.resource));
  const operationBindings = typeof readOperation === 'string'
    ? new Map([...resources].map(resource => [resource, readOperation]))
    : readOperation !== null && typeof readOperation === 'object' && !Array.isArray(readOperation)
      ? new Map(Object.entries(readOperation)) : undefined;
  if (operationBindings === undefined || operationBindings.size !== resources.size ||
      [...operationBindings].some(([resource, operation]) => !resources.has(resource) || !text(operation))) {
    fail('InvalidInstalledRowSourceOperations');
  }
  const immutableTargets = prepareImmutablePhysicalTargets(physicalTarget);
  if (immutableTargets !== undefined) physicalTarget = immutableTargets.prepare;
  let physicalTargetGeneration = immutableTargets?.inventory;
  const preparations = new WeakMap();
  // SAME prepared read, retained until the accounted RowRun takes custody.
  const preparingSourceReads = new Set();
  const reauthorizingPreparations = new WeakSet();
  const keyedPreparations = new WeakMap();
  function prepareOriginalAcquisition(requirement) {
    if (retainedAcquisitionContracts && acquisitionContracts === undefined) fail('InstalledSourceInitializationClosed');
    const acquisition = prepareAcquisition === undefined
      ? !retainedAcquisitionContracts
        ? checked(moon.clientProgramRowSourcePrepareAcquisition(
          declaration, requirement, queryContract, evidenceContract, listingPolicy))
        : checked(Reflect.apply(prepareWithContracts, moon,
          [declaration, requirement, acquisitionContracts, listingPolicy]))
      : prepareAcquisition(Object.freeze({declaration, requirement,
        queryContract, evidenceContract}));
    if (prepareAcquisition !== undefined) {
      checked(moon.clientProgramRowSourceCheckOriginalAcquisition(
        acquisition, declaration, requirement));
    }
    return acquisition;
  }
  const providerSiteCurrent = originalReader === undefined ? undefined : site.referenceCurrent;
  function managedProviderCaptureCapacity(requirement) {
    if (originalReader === undefined) {
      if (typeof prepareSourceRead !== 'function') fail('InstalledSourceCapacityUnavailable');
      // A Host-backed original read uses the same checked Row acquisition,
      // without pretending to have a provider reader or a second Run budget.
      const acquisition = prepareOriginalAcquisition(requirement);
      const capacity = moon.clientProgramInstalledRowCaptureCapacity(acquisition);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({capacity, transferBytes: maxTransferBytes,
        executionBytes: BigInt(limits.maxPageBytes)});
    }
    if (typeof providerSiteCurrent !== 'function' ||
        Reflect.apply(providerSiteCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
    const acquisition = prepareOriginalAcquisition(requirement);
    const capacity = moon.clientProgramInstalledProviderRowCaptureCapacity(acquisition, originalReader.capacity);
    if (capacity === undefined || moon.clientProgramInstalledProviderRowCaptureCapacityMatches(
      capacity, acquisition, originalReader.capacity) !== true) fail('InstalledSourceCapacityUnavailable');
    return Object.freeze({capacity, transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes)});
  }
  function managedWholeSourceCapacity({preparedProgram, sourceSelection, installedContracts}) {
    if (originalReader === undefined) {
      if (typeof prepareSourceRead !== 'function') fail('InstalledSourceCapacityUnavailable');
    } else if (typeof providerSiteCurrent !== 'function' ||
        Reflect.apply(providerSiteCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
    const selectedPageLimits = managedPageLimits ?? pageLimits;
    const capacity = checked(moon.clientProgramPrepareWholeSourceCapacity(
      preparedProgram, sourceSelection, declaration, installedContracts, originalReader?.capacity,
      limits.maxCaptureRows, limits.maxPageBytes, selectedPageLimits?.maxNodes ?? 400000,
      selectedPageLimits?.maxDepth ?? 32, limits.maxPageRows, limits.maxPages));
    return Object.freeze({capacity, wholeInput: true, transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes)});
  }
  const captureCapacity = owner => {
    if (originalReader !== undefined) {
      if (owner.wholeInput) {
        if (moon.clientProgramWholeSourceCapacityMatches(
          owner.providerCaptureCapacity, owner.acquisition, originalReader.capacity) !== true) {
          fail('InstalledSourcePreparationMismatch');
        }
        return owner.providerCaptureCapacity;
      }
      if (moon.clientProgramInstalledProviderRowCaptureCapacityMatches(
        owner.providerCaptureCapacity, owner.acquisition, originalReader.capacity) !== true) {
        fail('InstalledSourcePreparationMismatch');
      }
      return owner.providerCaptureCapacity;
    }
    if (owner.providerCaptureCapacity !== undefined) return owner.providerCaptureCapacity;
    return listingReportCapacity !== undefined &&
        moon.clientProgramRowSourceIsListing(owner.acquisition)
      ? moon.clientProgramInstalledListingRowCaptureCapacity(owner.acquisition, listingReportCapacity)
      : moon.clientProgramInstalledRowCaptureCapacity(owner.acquisition);
  };
  const installationBinding = Object.freeze({connectorId, connectorRegistration,
    connectorRevision, bindingCid});
  function currentPhysicalTargetGeneration() { return physicalTargetGeneration; }
  const {ordinaryRecoveryBinding, decideRead, currentRead} = createInstalledRowSourceReadAuthority({
    preparations, installationBinding, immutableTargets,
    currentPhysicalTargetGeneration,
    moon, declaration, site, physicalTarget, directReadIdentity, valueCid, cid, cidPattern});
  // Preserve an original installation's exact immutable access metadata;
  // this is neither a wire object nor an authorization decision. Defaults
  // keep the ordinary singleton Source projection unchanged.
  if (originalSourceAccess !== undefined &&
      (originalSourceAccess === null || typeof originalSourceAccess !== 'object' ||
        Object.getPrototypeOf(originalSourceAccess) !== Object.prototype ||
        !Object.isFrozen(originalSourceAccess) ||
        Reflect.ownKeys(originalSourceAccess).sort().join('\0') !== 'authorization\0connection' ||
        Object.getOwnPropertyDescriptor(originalSourceAccess, 'authorization')?.value !== authorization ||
        Object.getOwnPropertyDescriptor(originalSourceAccess, 'connection')?.value !== site.connection)) {
    fail('InvalidInstalledSourceAccess');
  }
  const sourceAccess = originalSourceAccess ?? Object.freeze({authorization,
    connection: site.connection,
    ...(sourceRefs.size === 1 ? {sourceRef: [...sourceRefs][0]} : {})});
  const {prepareKeyed, verifyKeyedRead, keyedRecoveryBinding} = createInstalledRowSourceKeyedPreparation({
    keyedPreparations, originalReader, moon, declaration, limits, sourceRefs, cidPattern, valueCid, site, physicalTarget,
    sourceAccess, decideRead, currentRead, connectorRegistration, connectorRevision, bindingCid});

  const {prepare, prepareRetained} = createInstalledRowSourcePreparation({
    moon, declaration, sourceRefs, site, physicalTarget, cidPattern, immutableTargets, currentPhysicalTargetGeneration,
    sourceAccess, preparations, preparingSourceReads, reauthorizingPreparations, valueCid,
    ordinaryRecoveryBinding, directReadIdentity, currentRead, originalReader, prepareSourceRead, decideRead,
    prepareOriginalAcquisition});

  const {open, openCapture} = createInstalledRowSourceAcquisition({
    prepare, preparations, originalReader, captureCapacity, currentRead, site, moon, directReadIdentity, cidPattern, cid,
    prepareRead, maxTransferBytes, limits, readerDemand, listingReportCapacity, startInstalledRowRun, preparingSourceReads,
    closeSourceRead, operationBindings, grantBeforeBegin, pageLimits, managedPageLimits, referenceIssuer, text,
    readPages, sourceAccess});

  const {openKeyed, selectedKeyedContent} = createInstalledRowSourceKeyedRead({
    originalReader, captureContent, referenceIssuer, moon, sourceRefs, text, prepareKeyedSourceRead, closeKeyedSourceRead,
    keyedPreparations, declaration, limits, physicalTarget, valueCid, keyedTransferBytes, keyedExecutionBytes,
    connectorRegistration, connectorRevision, bindingCid, currentRead, site, cid, operationBindings, readPages, sourceAccess});

  const openKeyedLookup = createInstalledRowSourceKeyedLookup({
    moon, limits, originalReader, selectedKeyedContent, sourceAccess, managedPageLimits, pageLimits, openKeyed});

  let constructionClosed = false;
  const sourceBody = {
    realizationKey,
    supportsRetainedRelationOutput: true,
    connectorRegistration, connectorRevision,
    environmentWire,
    ...(environment === undefined ? {} : {environmentOriginal: environment}),
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid: publicationBindingCid ?? bindingCid})]),
    ...(tableReadTargets === undefined ? {} : {tableReadTargets, declarationCatalogCid: declared.catalog_cid}),
    readAuthorization: Object.freeze({
      accountConfiguration: authorization.accountConfiguration,
      accountConstruction: authorization.accountConstruction,
      context: authorization.context}),
    sourceAccess,
    sourceReadAccesses,
    ...(originalReader !== undefined || typeof prepareSourceRead === 'function'
      ? {managedCaptureCapacity: managedProviderCaptureCapacity} : {}),
    ...(originalReader !== undefined || typeof prepareSourceRead === 'function'
      ? {managedWholeSourceCapacity} : {}),
      managedEffectPlanSelection(selection) {
        // This entry selects the common original acquisition constructor.
        // A compatibility preparer/policy or earlier physical callback cannot
        // be replaced by that default merely because its column counts match.
        if (prepareAcquisition !== undefined || listingPolicy !== undefined ||
            prepareRead !== undefined && originalReader === undefined) {
          fail('InstalledSourcePlanConstructorUnavailable');
        }
        if (originalReader === undefined && typeof prepareSourceRead !== 'function') {
          fail('InstalledSourcePlanConstructorUnavailable');
        }
        if (originalReader !== undefined && (typeof providerSiteCurrent !== 'function' ||
            Reflect.apply(providerSiteCurrent, site, []) !== true)) fail('InstalledSourceReaderNotCurrent');
        const selectedPageLimits = managedPageLimits ?? pageLimits;
        let inputLimits;
        if (selection === undefined) {
          if (typeof moon.clientProgramInstalledRowInputPolicy !== 'function') fail('InstalledSourcePlanConstructorUnavailable');
          inputLimits = moon.clientProgramInstalledRowInputPolicy(
            limits.maxCaptureRows, limits.maxPageBytes, selectedPageLimits?.maxNodes ?? 400000,
            selectedPageLimits?.maxDepth ?? 32, limits.maxPageRows);
        } else {
          const prepared = Object.getOwnPropertyDescriptor(selection, 'preparedEffect');
          if (!Object.isFrozen(selection) || prepared === undefined || !Object.hasOwn(prepared, 'value') ||
              prepared.value === undefined || typeof moon.clientProgramInstalledEffectRowInputPolicy !== 'function') {
            fail('InstalledSourcePlanConstructorUnavailable');
          }
          inputLimits = checked(moon.clientProgramInstalledEffectRowInputPolicy(
            limits.maxPages, limits.maxCaptureRows, limits.maxPageBytes,
            selectedPageLimits?.maxNodes ?? 400000, selectedPageLimits?.maxDepth ?? 32, limits.maxPageRows));
        }
        return Object.freeze({declaration, provider: originalReader?.capacity,
          inputLimits,
          transferBytes: maxTransferBytes, executionBytes: BigInt(limits.maxPageBytes)});
      },
    admitsSource: sourceRef => sourceRefs.has(sourceRef),
    ordinaryRecoveryBinding,
    prepareRetained,
    retirePreparedSource(prepared) {
      const owner = preparations.get(prepared);
      if (owner === undefined) fail('InstalledSourcePreparationMismatch');
      // Started reads have already transferred to their original RowRun's
      // close. This cut only returns the SAME still-unentered preparation;
      // a later sibling's refusal must not strand it until installation close.
      if (preparingSourceReads.has(owner.originalRead)) {
        checked(moon.clientProgramInstalledSourceReadRetire(owner.originalRead));
        preparingSourceReads.delete(owner.originalRead);
      }
    },
    retainedCapture(prepared) {
      const owner = preparations.get(prepared);
      if (owner === undefined || owner.retainedOnly === true) fail('InstalledSourcePreparationMismatch');
      const capacity = captureCapacity(owner);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({capacity, referenceIssuer,
        ...(owner.wholeInput ? {wholeInput: true} : {requirement: owner.requirement})});
    },
    ledgerCapacity(prepared) {
      const owner = preparations.get(prepared);
      if (owner === undefined || owner.retainedOnly === true) fail('InstalledSourcePreparationMismatch');
      const capacity = captureCapacity(owner);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({
        capacity,
        ...(owner.wholeInput ? {wholeInput: true} : {}),
        ...(owner.managedRun === undefined ? {} : {managedRun: owner.managedRun}),
        transferBytes: maxTransferBytes,
        executionBytes: BigInt(limits.maxPageBytes),
      });
    },
    keyedLedgerCapacity(keyedAcquisition, {maxWork, originalWork} = {}) {
      if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
      for (const value of [maxWork, originalWork]) {
        if (value !== undefined && (!Number.isSafeInteger(value) || value < 1 || value > 2147483647)) {
          fail('InstalledKeyedLookupLimits');
        }
      }
      // The original installed Plan supplies work, not a parser-node grant.
      // An explicit tighter selection remains binding; standalone callers keep
      // the existing default and node ceiling.
      const maxNodes = maxWork ?? 1000000;
      maxWork = originalWork === undefined ? maxNodes
        : Math.min(maxWork ?? originalWork, originalWork);
      const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(text) || !sourceRefs.has(facts[0])) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
        declaration, limits.maxPageBytes, limits.maxPageBytes, maxWork));
      return Object.freeze({capacity, transferBytes: keyedTransferBytes,
        executionBytes: keyedExecutionBytes, maxBytes: limits.maxPageBytes, maxWork, maxNodes});
    },
    prepare, prepareKeyed, verifyKeyedRead, keyedRecoveryBinding, open, openCapture, openKeyed, openKeyedLookup,
    close() {
      // Invalidate this installation's immutable target selection as soon as
      // retirement starts. Physical pending/ACK handling remains below.
      physicalTargetGeneration = undefined;
      for (const read of preparingSourceReads) {
        checked(moon.clientProgramInstalledSourceReadRetire(read));
        preparingSourceReads.delete(read);
      }
      if (originalReader?.retire !== undefined &&
          Reflect.apply(originalReader.retire, originalReader.receiver, []) !== true) {
        fail('InstalledSourceReaderCleanupPending');
      }
      const observed = site.close();
      if (sourceInitialization === undefined) return observed;
      // Only the existing Site's completed physical cleanup releases this
      // constructor's aliases; the request to stop is not its acknowledgement.
      return Promise.resolve(observed).then(value => {
        if (!constructionClosed) {
          closeInstalledSourceConstruction(sourceInitialization, installedSource);
          acquisitionContracts = undefined;
          constructionClosed = true;
        }
        return value;
      });
    },
  };
  for (const key of Object.keys(publicationFields)) {
    if (Object.hasOwn(sourceBody, key)) fail('InstalledSourcePublicationCollision');
  }
  // Provider-only publication fields enter the sole adapter before freezing
  // and exact registration. They cannot replace any common lifecycle method.
  let surface = sourceBody;
  if (selectedSurface !== undefined) {
    surface = {};
    for (const key of selectedSurface) {
      if (!Object.hasOwn(sourceBody, key)) fail('InvalidInstalledSourcePublication');
      Object.defineProperty(surface, key, Object.getOwnPropertyDescriptor(sourceBody, key));
    }
  }
  const installedSource = Object.freeze(Object.defineProperties(surface, publicationFields));
  if (sourceInitialization !== undefined) {
    retainInstalledSourceConstruction(sourceInitialization, installedSource, declaration, declared, environment);
  }
  return installedSource;
}
