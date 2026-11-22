// The standard Host's provider-neutral installed row source. A connector
// whose Site driver returns pages of JSON rows (keyed by its declared field
// names) is installed through this adapter: declaration restore, Check
// Environment, read decisions, credential grants, acquisition, capture and
// Source Evidence are the common runtime's and this module's; the connector
// supplies only its view specification, its physical target and its page
// driver. No provider name or type appears here.
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {createHash, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {performance} from 'node:perf_hooks';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {acquisitionFailure, acquisitionOutcome, AcquisitionOpenError} from
  '../host-common/acquisition-outcome.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {canonicalJson, contentCid} from
  './local-account-config.mjs';
import {bindClientSourceOperationRowRun} from './client-source-operation.mjs';
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
import {createInstalledRowSourcePreparation} from './installed-row-source-preparation.mjs';

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

  async function open(options) {
    const state = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  // A keyed consumer first borrows this original capture prefix. Its enclosing
  // task is not complete until the checked JOIN's other inputs are acquired.
  // This exposes no replacement Program, raw rows or fabricated task result.
  async function openCapture(options) {
    const state = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options, true);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  // One checked keyed occurrence, not whole-lookup completion. The enclosing
  // Host keeps the original left capture and all right captures until its
  // checked JOIN barrier has completed; this method issues no Source evidence.
  const selectedKeyedContent = value => {
    if (value === undefined) return undefined;
    const capture = value?.capture, issuer = value?.referenceIssuer;
    if (typeof capture !== 'function' || issuer === undefined || captureContent !== undefined) {
      fail('InvalidInstalledContentCapture');
    }
    // Select once before any await. Caller mutation cannot replace the Run's
    // capture or issuer between current authorization and row admission.
    return Object.freeze({capture, referenceIssuer: issuer});
  };
  async function openKeyed({preparedProgram, preparedEffect, managedRun, keyedAcquisition,
    request, ledger, signal, preparedKeyed, chargeVerification, capturedResourcePath,
    keyedContent, lookupPublication, lookupOriginal,
    sourceAccess: access = sourceAccess}) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    const state = {started: false, closeFailed: false, recovery: undefined};
    let session, lookupActivation, lookupRaw;
    let originalKeyedRead, originalClosed = prepareKeyedSourceRead === undefined;
    const closeOriginal = async () => {
      if (originalClosed) return;
      if (originalKeyedRead === undefined) return;
      const observed = await closeKeyedSourceRead(originalKeyedRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      originalClosed = true;
    };
    let deadline;
    let responsePageActive = false;
    const budgetAbort = new AbortController();
    signal = signal === undefined ? budgetAbort.signal : AbortSignal.any([signal, budgetAbort.signal]);
    try {
      // Per-Run capture custody is selected by the original dispatch owner,
      // never stored on the shared installation. Its issuer admits only the
      // same held content returned by that owner for this exact lookup.
      keyedContent = selectedKeyedContent(keyedContent);
      const captureBytes = keyedContent?.capture ?? captureContent;
      // Content custody belongs to this Run, but the returned Resource still
      // belongs to the installed Source. Do not replace either authority or
      // fall back to the other domain after an issuer refuses a reference.
      const captureIssuer = keyedContent === undefined ? referenceIssuer
        : moon.clientProgramRowContentReferenceIssuer(referenceIssuer,
          keyedContent.referenceIssuer);
      signal?.throwIfAborted();
      if ((preparedProgram === undefined) === (preparedEffect === undefined) ||
          ledger === undefined || (preparedEffect === undefined
            ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition,
              preparedProgram)
            : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition,
              preparedEffect)) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const facts = checked(
        moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(text) || !sourceRefs.has(facts[0])) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      if (prepareKeyedSourceRead !== undefined) {
        if (preparedKeyed === undefined || !keyedPreparations.has(preparedKeyed) ||
            preparedEffect !== undefined && managedRun === undefined) fail('InstalledSourcePreparationMismatch');
        // The same installing Source retains its physical-child duty before
        // returning this Core original. Preserve it before current/getter use.
        originalKeyedRead = prepareKeyedSourceRead(Object.freeze({
          checkedOwner: preparedEffect ?? preparedProgram, keyedAcquisition, request, declaration,
          ...(managedRun === undefined ? {} : {managedRun}),
          rowLimits: Object.freeze({maxPageBytes: limits.maxPageBytes,
            maxTextBytes: limits.maxPageBytes, maxWork: 1000000})}));
        checked(moon.clientProgramInstalledKeyedSourceReadCheckCurrent(originalKeyedRead));
      }
      const acquisition = checked(originalKeyedRead === undefined
        ? moon.clientProgramKeyedRowPrepareAcquisition(keyedAcquisition, request,
          declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000)
        : moon.clientProgramInstalledKeyedSourceReadAcquisition(originalKeyedRead));
      const [resource, ...columns] = checked(
        moon.clientProgramKeyedRowTarget(acquisition));
      const physicalBinding = physicalTarget(resource, columns);
      const scope = preparedKeyed === undefined ? undefined : keyedPreparations.get(preparedKeyed);
      if (preparedKeyed !== undefined && (scope === undefined ||
          scope.preparedProgram !== preparedProgram || scope.preparedEffect !== preparedEffect ||
          scope.keyedAcquisition !== keyedAcquisition ||
          scope.access !== access || valueCid(physicalBinding) !== valueCid(preparedKeyed.physicalBinding))) {
        fail('InstalledSourcePreparationMismatch');
      }
      const nonce = randomUUID();
      const backingField = lookupPublication === undefined ? undefined
        : Object.getOwnPropertyDescriptor(lookupPublication, 'responseBackingReleased');
      if (backingField !== undefined && (!Object.hasOwn(backingField, 'value') ||
          typeof backingField.value !== 'function')) fail('ForeignOriginalKeyedRawResponse');
      const responseBackingReleased = backingField === undefined ? undefined
        : () => !responsePageActive && Reflect.apply(backingField.value, lookupPublication, []) === true;
      session = startInstalledRowRun({moon, acquisition, nonce, ledger,
        keyed: true, originalKeyedRead, responseBackingReleased,
        capacity: {transferBytes: keyedTransferBytes, executionBytes: keyedExecutionBytes}});
      const {run} = session;
      // Encode only under the common acquisition's workspace reservation.
      const requestWire = checked(
        moon.clientProgramKeyedRequestWire(request, limits.maxPageBytes));
      const readSubject = Object.freeze({version: 'actql-keyed-row-source-read/0.1',
        sourceFacts: [...facts],
        occurrence: [...moon.clientProgramKeyedAcquisitionCoordinates(keyedAcquisition)],
        request: JSON.parse(requestWire), physicalBinding,
        connectorRegistration, connectorRevision, bindingCid});
      const prepared = Object.freeze({...preparedKeyed, readSubjectCid: valueCid(readSubject), physicalBinding,
        readTuple: Object.freeze({connection: site.connection, resource,
          operation: 'read'})});
      const verifyRead = () => currentRead(prepared, access, signal);
      const decision = await verifyRead();
      signal?.throwIfAborted();
      const granted = decision.basis === 'resumed_approval'
        ? site.admitCheckpointReadApproval(decision) : decision;
      const runInvocationCid = valueCid({version: 'actql-keyed-row-acquisition/0.1',
        readSubject, nonce});
      const dispatchRequestCid = cid({
        version: 'actql-keyed-row-acquisition-dispatch/0.1', runInvocationCid});
      checked(moon.clientProgramKeyedRowBegin(run, captureIssuer));
      const operation = operationBindings.get(resource);
      const grant = site.issueReadGrant({operation,
        decision: granted, resource, runInvocationCid, dispatchRequestCid,
        maxUses: limits.maxPages});
      const observedMs = () => BigInt(Math.floor(performance.now()));
      let sendIndex = 0;
      await readPages({resource, columns, requestWire, operation,
        signal, verifyRead,
        ...(lookupPublication === undefined ? {} : {retainRawResponse: async bytes => {
          // The installed driver already brackets this awaited hook with the
          // SAME verifyRead/signal fences. Do not repeat its authorization I/O.
          signal?.throwIfAborted();
          if (lookupActivation === undefined || lookupRaw !== undefined) fail('ForeignOriginalKeyedRawResponse');
          lookupRaw = await lookupPublication.retainRawResponse(lookupOriginal, request, lookupActivation, bytes);
          signal?.throwIfAborted();
        }}),
        rowRun: Object.freeze({acquisition, run, requestId: nonce, runInvocationCid, dispatchRequestCid,
          ...(originalKeyedRead === undefined ? {} : {originalKeyedRead})}),
        capturedResourcePath: capturedResourcePath === undefined ? undefined : async () => {
          await verifyRead();
          signal?.throwIfAborted();
          if (state.started) fail('InstalledFileLocatorAfterSend');
          return await capturedResourcePath(verifyRead, signal);
        },
        chargeVerification: chargeVerification === undefined ? undefined : async bytes => {
          if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > 4096) {
            fail('InvalidKeyedVerificationObservation');
          }
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          await chargeVerification(bytes);
        },
        // Host-selected capture receives original typed request/Source facts,
        // not a driver-selected request, target or permission. The callback
        // transfers actual verified bytes to the existing holding owner before
        // returning an issued envelope for this keyed row's ordinary admission.
        captureContent: captureBytes === undefined ? undefined : async bytes => {
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          const content = await captureBytes({...bytes, keyedAcquisition,
            request, readSubjectCid: prepared.readSubjectCid, verifyRead, signal});
          await verifyRead();
          signal?.throwIfAborted();
          return content;
        },
        // The driver supplies the actual serialized request before each send.
        // Grants and lookup accounting share this boundary; returning from
        // readPages without an observed send cannot produce a capture.
        beginRequest: async body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedRequestObservation');
          await verifyRead();
          signal?.throwIfAborted();
          if (lookupPublication !== undefined) {
            if (lookupActivation !== undefined || sendIndex !== 0) fail('OriginalKeyedLookupAlreadyActivated');
            // The SAME current activation is durably indexed before this
            // attempt is consumed and before the driver can receive a grant.
            lookupActivation = lookupPublication.activate(lookupOriginal, request);
            await verifyRead();
            signal?.throwIfAborted();
          }
          checked(moon.clientProgramKeyedRequestObserveAttempt(request,
            BigInt(body.byteLength), observedMs()));
          if (deadline === undefined) {
            const remaining = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs()));
            // Schedule beyond the inclusive exact boundary and clamp only the
            // timer representation. Long policies are rechecked on every
            // observation; the timer must not overflow to immediate expiry.
            const expire = () => {
              try {
                const left = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs()));
                deadline = setTimeout(expire, Number(left < 2147483646n ? left + 1n : 2147483647n));
                deadline.unref();
              } catch (cause) {
                budgetAbort.abort(Object.assign(new Error('KeyedLookupDurationExceeded', {cause}),
                  {code: 'KeyedLookupDurationExceeded'}));
              }
            };
            deadline = setTimeout(expire, Number(remaining < 2147483646n ? remaining + 1n : 2147483647n));
            deadline.unref();
          }
          state.started = true;
          return {...grant, useId: `${nonce}-read-${sendIndex++}`};
        },
        chargePage: body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedResponseObservation');
          // Preserve the physical Ledger charge even when the lookup ceiling
          // rejects this received body before decoding or private admission.
          const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            BigInt(body.byteLength), 0n, observedMs()));
          return charge;
        },
        // Received native file bytes use this original RowRun's pending
        // ticket before the subsequent encoded row is charged. A lookup
        // verification count is not a physical-byte observation or a grant.
        consumeObservation: charge => checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge)),
        // The Site must await admission before returning protocol completion.
        consumePage: async (rows, {charge} = {}) => {
          // The codec comes from the exact Request's installed execution
          // original. A driver Bool or an earlier current decision cannot
          // select raw evidence or replace its pending activation.
          const identityResponse = lookupPublication !== undefined &&
            moon.clientProgramKeyedSourceResponseEncoding(request) === 'typed_json_row_array';
          if (identityResponse && (backingField === undefined || responsePageActive)) fail('ForeignOriginalKeyedRawResponse');
          if (identityResponse) responsePageActive = true;
          let body;
          try {
          if (identityResponse) {
            await verifyRead(); signal?.throwIfAborted();
            if (moon.clientProgramKeyedSourceResponseEncoding(request) !== 'typed_json_row_array') fail('ForeignOriginalKeyedRawResponse');
          }
          body = identityResponse ? encodeTypedResponseJson(rows, limits.maxPageBytes)
            : Buffer.from(JSON.stringify(rows), 'utf8');
          const ticket = charge ?? checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            charge === undefined ? BigInt(body.byteLength) : 0n,
            BigInt(body.byteLength), observedMs()));
          if (identityResponse) {
            if (lookupActivation === undefined || lookupRaw !== undefined) fail('ForeignOriginalKeyedRawResponse');
            lookupRaw = await lookupPublication.retainRawResponse(lookupOriginal,
              request, lookupActivation, body);
            await verifyRead(); signal?.throwIfAborted();
          }
          return await session.consumeKeyedPage(body,
            {charge: ticket, currentRead: verifyRead, signal});
          } finally {
            body = undefined;
            if (identityResponse) responsePageActive = false;
          }
        }});
      session.confirmTransportStopped();
      const capture = await session.capture({currentRead: verifyRead, signal});
      checked(moon.clientProgramKeyedRequestFinishIO(request, observedMs()));
      if (lookupPublication !== undefined) {
        lookupPublication.adopt(lookupOriginal, request, lookupActivation, capture, lookupRaw);
        await verifyRead(); signal?.throwIfAborted();
      }
      return Object.freeze({capture: Object.freeze({read: () => checked(
        moon.clientProgramKeyedRowCaptureRead(capture)), identity: () => checked(
        moon.clientProgramKeyedRowCaptureIdentity(capture))}),
        verifyRead,
        // Only the actual installed successful capture can enter assembly.
        acceptLookup: lookup => checked(moon.clientProgramKeyedLookupAcceptCapture(
          lookup, keyedAcquisition, request, capture)),
        async close() {session.close(); await closeOriginal();}});
    } catch (error) {
      if (session !== undefined) {
        moon.clientProgramKeyedRequestFailIO(request);
        // Before dispatch there was no physical reader to stop. Once entered,
        // absence of an explicit transport-end observation remains pending.
        const end = acquisitionOutcome(error);
        if (!state.started || end.outcome === 'stopped' || end.outcome === 'not_started') {
          session.confirmTransportStopped();
        } else if (end.recovery !== undefined) {
          // The physical driver's same recovery owner stops its own resources;
          // it does not settle successful response evidence or the RowRun.
          try { await end.recovery.close(); } catch { /* Keep pending custody. */ }
        }
        session.closeAfterFailure(state, end.recovery);
      }
      if (originalKeyedRead !== undefined) {
        const rowRecovery = state.recovery;
        let cleaned = false;
        const cleanup = async () => {
          if (cleaned) return true;
          if (rowRecovery !== undefined &&
              (await rowRecovery.cleanup() === false || rowRecovery.cleanupPending())) return false;
          if (session === undefined) checked(moon.clientProgramInstalledKeyedSourceReadRetire(originalKeyedRead));
          await closeOriginal();
          cleaned = true;
          return true;
        };
        try {await cleanup();} catch { /* Retain the same original duty below. */ }
        if (!cleaned) {
          state.closeFailed = true;
          state.recovery = Object.freeze({close: () => rowRecovery?.close(),
            cleanup, cleanupPending: () => !cleaned});
        }
      }
      // Do not let an inner transport outcome bypass this RowRun's pending
      // retention/cleanup responsibility through acquisitionFailure's reuse.
      throw new AcquisitionOpenError(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    } finally {
      clearTimeout(deadline);
    }
  }

  // Exact-key sharing changes physical reads, not original left multiplicity.
  // This assembles a right Relation input; it is not Source/task evidence.
  async function openKeyedLookup({preparedProgram, preparedEffect,
    keyedAcquisition, left, ledger, signal, preparedKeyed, originalCapture, originalCaptures, managedRun,
    keyedContent, publication, sourceLookup,
    sourceAccess: access = sourceAccess, maxWork = 1000000, maxNodes = maxWork, quantum = 64}) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    keyedContent = selectedKeyedContent(keyedContent);
    if (!Number.isSafeInteger(maxWork) || maxWork < 1 || maxWork > 2147483647 ||
        !Number.isSafeInteger(maxNodes) || maxNodes < 1 || maxNodes > 2147483647 ||
        !Number.isSafeInteger(quantum) || quantum < 1 || quantum > 1024) {
      fail('InstalledKeyedLookupLimits');
    }
    const rows = moon.clientProgramKeyedLeftReadRows(left);
    if (rows === undefined || ledger === undefined ||
        moon.clientProgramKeyedLeftMatchesAcquisition(left, keyedAcquisition) !== true ||
        (preparedProgram === undefined) === (preparedEffect === undefined) ||
        (preparedEffect === undefined
          ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram)
          : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition, preparedEffect)) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    signal?.throwIfAborted();
    const lookup = sourceLookup === undefined
      ? checked(moon.clientProgramKeyedLookupStart(left, ledger, limits.maxPageBytes, maxWork))
      : preparedEffect === undefined || managedRun === undefined
        ? fail('InstalledSourceProgramMismatch')
        : checked(moon.clientProgramInstalledEffectKeyedLookupOriginal(managedRun,
          preparedEffect, sourceLookup));
    if (sourceLookup !== undefined && moon.clientProgramKeyedLookupLeft(lookup) !== left) {
      fail('InstalledSourceProgramMismatch');
    }
    const children = [];
    const released = new Set();
    let pendingRecovery;
    let unownedUncertainty = false;
    let preparation;
    let ioStarted = false;
    let closed = false;
    const stop = () => {
      moon.clientProgramKeyedLookupStop(lookup);
      if (preparation !== undefined) {
        moon.clientProgramKeyedRequestCancel(preparation);
        preparation = undefined;
      }
    };
    const cleanup = async () => {
      if (closed) return true;
      stop();
      let pending = unownedUncertainty;
      for (const child of children) {
        if (released.has(child)) continue;
        try { await child.close(); released.add(child); }
        catch { pending = true; }
      }
      if (pendingRecovery !== undefined) {
        try {
          await pendingRecovery.close();
          if (await pendingRecovery.cleanup() === false || pendingRecovery.cleanupPending()) pending = true;
          else pendingRecovery = undefined;
        } catch { pending = true; }
      }
      // Keep assembly custody until all original physical children settle.
      // Cleanup never obtains a new Request or sends again.
      if (pending) return false;
      while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, quantum))) {
        await yieldEventLoop();
      }
      children.length = 0;
      released.clear();
      closed = true;
      return true;
    };
    const close = async () => {
      if (!await cleanup()) fail('InstalledSourceCleanupPending');
    };
    const recovery = Object.freeze({close: stop, cleanup, cleanupPending: () => !closed});
    try {
      const publicationInput = preparedEffect !== undefined;
      // Generic content_ref Sources use their actual Store/Row capture, not a
      // Native declared-JSON activation, raw-response Journal or page history.
      const nativePublication = publicationInput && publication?.protocol !== 'generic-source';
      const publicationDepth = (managedPageLimits ?? pageLimits)?.maxDepth ?? 32;
      if (publicationInput) {
        if (typeof publication?.initialize !== 'function' || typeof publication?.finishInput !== 'function' ||
            nativePublication && (typeof publication?.activate !== 'function' ||
              typeof publication?.retainRawResponse !== 'function' || typeof publication?.adopt !== 'function')) {
          fail('OriginalKeyedLookupPublicationUnavailable');
        }
        publication.initialize(lookup);
      }
      // Prepare each original request once, then dispatch those SAME originals.
      // No response or Model read can precede the closed typed key inventory.
      for (let phase = 0; phase < (nativePublication ? 2 : 1); phase++) {
        for (let row = 0; row < rows; row++) {
          signal?.throwIfAborted();
          let request;
          if (nativePublication && phase === 1) {
            const originalRow = checked(moon.clientProgramKeyedLookupNextPlannedRow(lookup));
            request = checked(moon.clientProgramKeyedLookupPlannedRequest(lookup, originalRow));
          } else {
            preparation = checked(moon.clientProgramKeyedLookupRequestStart(lookup, row));
            while (request === undefined) {
              signal?.throwIfAborted();
              for (let poll = 0; poll < quantum; poll++) {
                let compilerTuple1 = moon.clientProgramKeyedLookupRequestAdvance(lookup, preparation);
                const status = runtimeField(compilerTuple1, 0), value = runtimeField(compilerTuple1, 2), issue = runtimeField(compilerTuple1, 3);
                compilerTuple1 = undefined;
                if (status === 2) fail('InstalledKeyedRequestFailed', issue);
                if (status === 1) { request = value; break; }
              }
              if (request === undefined) await yieldEventLoop();
            }
            preparation = undefined;
          }
          if (nativePublication && phase === 0) {
            checked(moon.clientProgramKeyedLookupRequestPlanRetain(lookup, request));
            continue;
          }
          const index = checked(moon.clientProgramKeyedLookupFind(lookup, request));
          if (index >= 0) {
            await children[index].verifyRead();
            signal?.throwIfAborted();
            checked(moon.clientProgramKeyedLookupReuse(lookup, request, index));
            continue;
          }
          let acquired;
          try {
            acquired = await openKeyed({preparedProgram, preparedEffect,
              keyedContent, managedRun,
              lookupPublication: nativePublication ? publication : undefined, lookupOriginal: lookup,
              keyedAcquisition, request, ledger, signal, preparedKeyed, sourceAccess: access,
              capturedResourcePath: async (verifyRead, activeSignal) => {
                let locator;
                if (originalCaptures !== undefined) {
                  if (!Array.isArray(originalCaptures) || originalCaptures.length !== 2) fail('InstalledFileLocatorUnavailable');
                  locator = checked(moon.clientProgramComposedKeyedFileLocatorStart(lookup, request,
                    originalCaptures.map(capture => capture.source()),
                    originalCaptures.map(capture => capture.originalRead?.())));
                } else {
                  if (typeof originalCapture?.originalRead !== 'function') fail('InstalledFileLocatorUnavailable');
                  const read = originalCapture.originalRead();
                  if (read === undefined) fail('InstalledFileLocatorUnavailable');
                  locator = checked(moon.clientProgramKeyedFileLocatorStart(lookup, request,
                    originalCapture.source(), read));
                }
                try {
                  for (;;) {
                    await verifyRead();
                    activeSignal?.throwIfAborted();
                    for (let poll = 0; poll < quantum; poll++) {
                      const path = checked(moon.clientProgramKeyedFileLocatorAdvance(locator));
                      if (path !== undefined) return path;
                    }
                    await yieldEventLoop();
                  }
                } finally {
                  moon.clientProgramKeyedFileLocatorCancel(locator);
                }
              },
              chargeVerification: bytes => checked(
                moon.clientProgramKeyedLookupChargeVerification(lookup, request, bytes))});
            ioStarted = true;
          } catch (error) {
            const end = acquisitionOutcome(error);
            if (end.outcome !== 'not_started') ioStarted = true;
            if (end.outcome === 'unknown') {
              pendingRecovery = end.recovery;
              unownedUncertainty = end.recovery === undefined;
            }
            throw error;
          }
          // Preserve the physical close handle before copying can fail.
          children.push(acquired);
          acquired.acceptLookup(lookup);
          while (!checked(moon.clientProgramKeyedLookupAdvance(lookup, quantum))) {
            signal?.throwIfAborted();
            await acquired.verifyRead();
            signal?.throwIfAborted();
            await yieldEventLoop();
          }
        }
        if (nativePublication && phase === 0) {
          checked(moon.clientProgramKeyedLookupRequestPlanFinish(lookup,
            limits.maxPageBytes, maxNodes, publicationDepth));
        }
      }
      for (const child of children) {
        await child.verifyRead();
        signal?.throwIfAborted();
      }
      signal?.throwIfAborted();
      const read = publicationInput && preparedEffect !== undefined
        ? publication.finishInput(lookup)
        : checked(publicationInput
          ? moon.clientProgramKeyedLookupPublicationInput(lookup,
            limits.maxPageBytes, maxNodes, publicationDepth)
          : moon.clientProgramKeyedLookupRead(lookup));
      return Object.freeze({capture: Object.freeze({
        read: () => closed ? fail('InstalledSourceClosed')
          : checked(moon.clientProgramKeyedLookupRead(lookup)),
        identity: () => {
          const identity = moon.clientProgramKeyedLookupIdentity(lookup);
          if (identity === undefined) fail('InstalledSourceClosed');
          return identity;
        }}), close, cleanup, cleanupPending: recovery.cleanupPending,
        work: () => moon.clientProgramKeyedLookupWork(lookup), read,
        async issueObservation({authorityScopeCid, observedAt}) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          const observation = checked(moon.clientProgramKeyedLookupIssueObservation(
            lookup, authorityScopeCid, observedAt));
          const wires = moon.clientProgramKeyedLookupObservationWires(observation);
          if (wires === undefined) fail('InstalledSourceClosed');
          return Object.freeze({observation,
            inputLogicalWire: runtimeField(wires, 0), sourceEvidenceWire: runtimeField(wires, 1)});
        },
        async openDag() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (preparedEffect !== undefined) {
            fail('InstalledKeyedEffectDagRequiresRunOwner');
          }
          if (closed) fail('InstalledSourceClosed');
          return checked(moon.clientProgramKeyedLookupOpenDag(preparedProgram,
            lookup, ledger));
        },
        async openHost({registry, values, fragment, ordered, retainedRelationOutput = false,
          managedRun, requestIdentity}) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          if (preparedEffect !== undefined) fail('InstalledKeyedEffectDagRequiresRunOwner');
          if (managedRun !== undefined || requestIdentity !== undefined) {
            if (managedRun === undefined || requestIdentity === undefined ||
                typeof moon.clientProgramOpenInstalledManagedKeyedCaptureHost !== 'function') {
              fail('InstalledKeyedHostOriginalRunUnavailable');
            }
            return checked(moon.clientProgramOpenInstalledManagedKeyedCaptureHost(
              managedRun, preparedProgram, requestIdentity, lookup));
          }
          const host = moon.clientProgramKeyedLookupOpenLocalHost(preparedProgram,
            lookup, ledger, registry, values, fragment, ordered, retainedRelationOutput);
          if (host === undefined) fail('InstalledKeyedHostPreparation');
          return host;
        },
        // Original Local preparation, not a replacement acquisition Program.
        // The normal dispatcher must reserve its capacity and own its child.
        async borrowSerializationInput() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          // This is the original sealed lookup, not a new task completion or
          // a transfer of custody. The dependent prefix must stop first.
          checked(moon.clientProgramKeyedLookupRead(lookup));
          return lookup;
        },
        async prepareJoin({registry, values, fragment, ordered}) {
          if (closed) fail('InstalledSourceClosed');
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          const prepared = preparedEffect === undefined
            ? moon.clientProgramKeyedLookupJoinPrepare(preparedProgram, lookup,
              registry, values, fragment, ordered)
            : moon.clientProgramEffectKeyedLookupJoinPrepare(preparedEffect, lookup,
              registry, values, fragment, ordered);
          if (prepared === undefined) fail('InstalledKeyedJoinPreparation');
          return prepared;
        }});
    } catch (error) {
      let complete = false;
      try { complete = await cleanup(); } catch { /* Same recovery retains custody. */ }
      throw new AcquisitionOpenError(error, complete
        ? ioStarted ? 'stopped' : 'not_started' : 'unknown', complete ? undefined : recovery);
    }
  }

  async function acquire(state, {preparedProgram, preparedEffect, registry,
    values, fragment, ordered, sourceAccess: access = sourceAccess, signal,
    preparedSource, retainedRelationOutput = false,
    occurrence = {stage: 0, input: 0, task: 0}, ledger,
    originalOperationScope}, captureOnly = false) {
    const prepared = preparedSource ?? await prepare({preparedProgram,
      preparedEffect, registry, values, fragment, ordered,
      sourceAccess: access, occurrence});
    const owner = preparations.get(prepared);
    if (owner === undefined || owner.retainedOnly === true ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== (preparedEffect !== undefined) ||
        owner.access !== access ||
        owner.occurrence.stage !== occurrence.stage ||
        owner.occurrence.input !== occurrence.input ||
        owner.occurrence.task !== occurrence.task) {
      fail('InstalledSourcePreparationMismatch');
    }
    if (originalReader !== undefined) {
      if (ledger === undefined) fail('InstalledProviderSourceLedgerRequired');
      captureCapacity(owner);
    }
    const decision = await currentRead(prepared, access, signal);
    const granted = decision.basis === 'resumed_approval'
      ? site.admitCheckpointReadApproval(decision) : decision;
    const acquisition = owner.acquisition;
    const columns = owner.wholeInput ? moon.clientProgramWholeSourceTarget(acquisition).slice(1)
      : [...moon.clientProgramRowSourceColumns(acquisition)];
    const nonce = randomUUID();
    const identity = directReadIdentity === undefined ? undefined
      : directReadIdentity.attempt(prepared, nonce);
    if (directReadIdentity !== undefined &&
        (identity === null || typeof identity !== 'object' ||
          Object.getPrototypeOf(identity) !== Object.prototype ||
          !Object.isFrozen(identity) ||
          Object.keys(identity).sort().join('\0') !==
            ['dispatchRequestCid', 'runInvocationCid'].join('\0') ||
          !cidPattern.test(identity.runInvocationCid) ||
          !cidPattern.test(identity.dispatchRequestCid))) {
      fail('InvalidInstalledSourceReadIdentity');
    }
    const runInvocationCid = identity?.runInvocationCid ??
      cid({version: 'actql-row-source-acquisition/0.1',
        ...(owner.wholeInput ? {sourceInput: prepared.checkedSource.sourceInput}
          : {requirementCid: prepared.checkedSource.requirementCid}), nonce});
    const dispatchRequestCid = identity?.dispatchRequestCid ?? cid({
      version: 'actql-row-source-acquisition-dispatch/0.1', runInvocationCid});
    let preparedRead;
    if (prepareRead !== undefined && originalReader === undefined) {
      // A provider's original bounded metadata observation precedes the row
      // attempt. Mark the physical start before awaiting that same operation;
      // a lost response is never reclassified as an unstarted acquisition.
      state.started = true;
      preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
        decision, granted, resource: owner.resource, nonce, runInvocationCid,
        dispatchRequestCid, signal}));
    }
    const capacity = {transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes),
      ...(readerDemand?.transferUnitBytes === undefined ? {} : {transferUnitBytes:readerDemand.transferUnitBytes})};
    if (originalReader !== undefined) capacity.provider = originalReader.capacity;
    if (!owner.wholeInput && listingReportCapacity !== undefined &&
        moon.clientProgramRowSourceIsListing(acquisition)) {
      // Extra report/control backing is admitted by Core before page I/O and
      // retained through original capture/evidence/cleanup, not settled by
      // this JS caller when capture returns. Ordinary rows have no new field.
      capacity.listingReport = listingReportCapacity;
    }
    const session = startInstalledRowRun({moon, acquisition, nonce, ledger, capacity,
      originalRead: owner.originalRead, wholeInput: owner.wholeInput});
    preparingSourceReads.delete(owner.originalRead);
    const {run} = session;
    let externalClosed = closeSourceRead === undefined || owner.managedRun === undefined;
    let externalCloseAttempted = false;
    let nativeReadPending = false;
    const closeOriginal = async () => {
      if (externalClosed) return;
      externalCloseAttempted = true;
      const observed = await closeSourceRead(owner.originalRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      externalClosed = true;
    };
    const complete = async () => {
      const verifyRead = () => currentRead(prepared, access, signal);
      // The completed Direct prefix owns its own logical input and Source
      // observation even when later keyed inputs are still unacquired. Reuse
      // the existing capture tuple issuer, never label it as JOIN completion.
      return await session.complete({owner, prepared, registry,
        values, fragment, ordered, retainedRelationOutput, signal,
        currentRead: verifyRead, captureOnly});
    };
    try {
      if (prepareRead !== undefined && originalReader !== undefined) {
        // A managed Reader's original facts are prepared only after its SAME
        // accounted Run starts. Its native protocol owns every physical child;
        // the original session catches and retires a failed preparation too.
        preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
          wholeInput: owner.wholeInput,
          decision, granted, resource: owner.resource, nonce, runInvocationCid,
          dispatchRequestCid, signal}));
      }
      // Encode only after the existing RowRun's accounted reservation. The
      // common owner includes this wire while its completion records overlap.
      // The driver decodes its declared typed Request (including existing wire
      // markers for JSON scalars), not a replacement selector.
      const requestWire = checked(owner.wholeInput ? moon.clientProgramWholeSourceRequestWire(acquisition)
        : moon.clientProgramRowSourceRequestWire(acquisition));
      const operation = operationBindings.get(owner.resource);
      const issueGrant = () => site.issueReadGrant({operation,
        decision: granted, resource: owner.resource, runInvocationCid,
        dispatchRequestCid, maxUses: (readerDemand?.sequences?.[owner.resource] ?? readerDemand?.sequence)?.maxUses ?? limits.maxPages});
      // Preserve a selected driver's original grant/attempt order. The
      // ordinary JSON/listing path keeps its existing post-begin issuance.
      // A local original read has no credential to issue. A managed provider
      // read adds Resource custody only: it still needs the same Site grant
      // and current Account decision, never permission from its Run identity.
      const credentialRead = owner.originalRead === undefined ||
        owner.managedRun !== undefined && originalReader !== undefined;
      let grant = credentialRead && grantBeforeBegin ? issueGrant() : undefined;
      const readChildGrants = new Map(), readChildUses = new Map();
      const readChildOriginals = new WeakMap();
      let readChildIndex = 0, rootReadUses = 0, propertyOccurrences = 0;
      const beginPageLimits = owner.wholeInput ? managedPageLimits ?? pageLimits : pageLimits;
      checked(beginPageLimits === undefined
        ? moon.clientProgramRowSourceBegin(run, limits.maxPageBytes,
          limits.maxPageRows, limits.maxCaptureRows, referenceIssuer)
        : moon.clientProgramRowSourceBeginWithPageLimits(run, limits.maxPageBytes,
          beginPageLimits.maxNodes, beginPageLimits.maxDepth, limits.maxPageRows,
          limits.maxCaptureRows, referenceIssuer));
      const isListing = owner.wholeInput
        ? moon.clientProgramWholeSourceIsListing(acquisition)
        : moon.clientProgramRowSourceIsListing(acquisition);
      // paths=[] is already typed and complete. Do not issue a read grant or
      // enter a Site driver merely to manufacture an empty transport result.
      if (isListing && moon.clientProgramRowSourceListingComplete(run)) {
        await closeOriginal();
        return await complete();
      }
      if (credentialRead && !grantBeforeBegin) grant = issueGrant();
      state.started = true;
      const rowRun = Object.freeze({acquisition, run, requestId: nonce,
        runInvocationCid, dispatchRequestCid,
        ...(owner.wholeInput ? {inputKind: 'whole-input'} : {}),
        ...(owner.originalRead === undefined ? {} : {originalRead: owner.originalRead})});
      const withOriginalJob = originalOperationScope === undefined ? undefined
        : bindClientSourceOperationRowRun(originalOperationScope, moon,
          preparedProgram, prepared, rowRun);
      const readerOptions = {resource: owner.resource, columns, requestWire, preparedRead,
        operation, signal,
        verifyRead: () => currentRead(prepared, access, signal),
        // Same-runtime opaque borrowing for trusted installed adapters only.
        // The original Host keeps finish/capture/close and physical capacity.
        rowRun,
        ...(withOriginalJob === undefined ? {} : {withOriginalJob}),
        ...(isListing ? {listing: rowListingCallbacks({moon, run, signal,
          currentRead: () => currentRead(prepared, access, signal)})} : {}),
        // The current read decision is taken again before every request.
        ...(credentialRead ? {originalAuthorization: grant, authorizationFor: async index => {
          if (index > 0) await currentRead(prepared, access, signal);
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce, index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return {...grant, useId};
        }, authorizeReadChild: async (childOperation,index,occurrence,supplied,childSignal = signal) => {
          if (readerDemand?.sequence !== undefined || readerDemand?.sequences !== undefined) {
            const sequence = readerDemand.sequences?.[owner.resource] ?? readerDemand.sequence;
            if (sequence === undefined || operation !== sequence.operation || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses || occurrence === null || typeof occurrence !== 'object' ||
                nodeTypes.isProxy(occurrence) || readChildOriginals.has(occurrence)) fail('InvalidInstalledSourceReadChild');
            let selected;
            if (childOperation === sequence.operation) {
              if (rootReadUses >= sequence.maxUses) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              selected = sequence.children.find(entry => entry.operation === childOperation);
              if (selected === undefined) fail('InvalidInstalledSourceReadChild');
              const used = readChildUses.get(childOperation) ?? 0;
              if (used >= selected.maxUses) fail('InstalledSourceReadChildUseLimit');
              readChildUses.set(childOperation,used+1);
            }
            readChildIndex++;
            // Spend the original occurrence before any reentrant current or
            // Site callback. Failure cannot restore a consumed request/use.
            readChildOriginals.set(occurrence,true);
            const decision = await currentRead(prepared,access,signal);
            if (supplied !== undefined) return supplied;
            if (selected?.resource !== undefined && selected.resource !== owner.resource) {
              // This child shares the original request/target, not the parent
              // Resource's permission. The already declared Resource gets its
              // own current Account decision and original Site-issued grant.
              let original = readChildGrants.get(childOperation);
              if (original === undefined) {
                const verifyCurrent = async () => {
                  childSignal?.throwIfAborted();
                  const childDecision = await access.authorization.authorize('acquisition',
                    {connection: prepared.readTuple.connection, resource: selected.resource, operation: 'read'},
                    {subjectCid: cid({binding: prepared.physicalBinding, operation: childOperation}), signal: childSignal});
                  childSignal?.throwIfAborted();
                  if (childDecision?.action !== 'dispatch') {
                    throw Object.assign(new Error('ExecutionAuthorizationDenied'),
                      {code: 'ExecutionAuthorizationDenied', decision: childDecision});
                  }
                  return childDecision;
                };
                const childDecision = await verifyCurrent();
                const childGrant = site.issueReadGrant({operation: childOperation, decision: childDecision,
                  resource: selected.resource, runInvocationCid, dispatchRequestCid, maxUses: selected.maxUses});
                original = Object.freeze({grant: childGrant, verifyCurrent});
                readChildGrants.set(childOperation, original);
              } else await original.verifyCurrent();
              const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
                : directReadIdentity.useId(nonce,index);
              if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
              return Object.freeze({originalAuthorization: original.grant,
                authorization: Object.freeze({...original.grant, useId}), verifyCurrent: original.verifyCurrent});
            }
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval(decision) : decision;
            let original = childOperation === operation ? grant : readChildGrants.get(childOperation);
            if (original === undefined) {
              original = site.issueReadGrant({operation:childOperation,decision:childGranted,
                resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:sequence.children.find(entry => entry.operation === childOperation).maxUses});
              readChildGrants.set(childOperation,original);
            }
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization:original,authorization:Object.freeze({...original,useId})});
          }
          if (readerDemand?.nested === true) {
            if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses) fail('InvalidInstalledSourceReadChild');
            let entry;
            if (childOperation === operation) {
              if (rootReadUses >= readerDemand.queryPages) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              if (occurrence === null || typeof occurrence !== 'object' || nodeTypes.isProxy(occurrence)) {
                fail('InstalledSourceReadChildOriginalUnavailable');
              }
              entry = readChildOriginals.get(occurrence);
              if (entry === undefined) {
                if (propertyOccurrences >= readerDemand.propertyOccurrences) fail('InstalledSourcePropertyOccurrenceLimit');
                propertyOccurrences++;
                // A weak occurrence key never turns the completed native
                // query/property graph into a retained all-pages history.
                entry = {operation: childOperation, uses: 0, grant: undefined};
                readChildOriginals.set(occurrence, entry);
              }
              if (entry.operation !== childOperation || entry.uses >= readerDemand.propertyPages) {
                fail('InstalledSourcePropertyUseLimit');
              }
              entry.uses++;
            }
            readChildIndex++;
            const decision = await currentRead(prepared, access, signal);
            if (supplied !== undefined) return supplied;
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval(decision) : decision;
            if (entry !== undefined && entry.grant === undefined) {
              entry.grant = site.issueReadGrant({operation: childOperation, decision: childGranted,
                resource: owner.resource, runInvocationCid, dispatchRequestCid, maxUses: readerDemand.propertyPages});
            }
            const selected = entry === undefined ? grant : entry.grant;
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization: selected,
              authorization: Object.freeze({...selected,useId})});
          }
          if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex || index >= limits.maxPages) {
            fail('InvalidInstalledSourceReadChild');
          }
          // Spend this original ordinal before an external current callback.
          // A failed or reentrant call cannot reuse it to issue another child.
          readChildIndex++;
          await currentRead(prepared, access, signal);
          if (supplied !== undefined) return supplied;
          let original = childOperation === operation ? grant : readChildGrants.get(childOperation);
          if (original === undefined) {
            original = site.issueReadGrant({operation:childOperation,decision:granted,
              resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:limits.maxPages});
            readChildGrants.set(childOperation,original);
          }
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce,index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return Object.freeze({originalAuthorization:original,
            authorization:Object.freeze({...original,useId})});
        }} : {}),
        chargePage: body => checked(moon.clientProgramRowSourceChargePage(
          run, body)),
        consumeObservation: ledger === undefined ? undefined : function consumeObservation(charge) {
          return checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge));
        },
        consumeProjectedPage: (page, {charge} = {}) => {
          // The same compiled RowRun checks opaque page provenance and the
          // original response ticket before full schema/retention admission.
          // Foreign pages never fall back to serialization or another parse.
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedProjectedPage(run, charge, page));
        },
        ...(originalReader === undefined ? {} : {consumeValues: (columns, rows, {charge} = {}) => {
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedValues(run, charge, columns, rows));
        }}),
        consumePageWire: (wire, {charge} = {}) => {
          if (typeof wire !== 'string') fail('InvalidInstalledSourcePageWire');
          const bytes = Buffer.from(wire, 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        },
        consumePage: (rows, {charge} = {}) => {
          const bytes = Buffer.from(JSON.stringify(rows), 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        }};
      if (originalReader === undefined) {
        nativeReadPending = true;
        await readPages(readerOptions);
        nativeReadPending = false;
      }
      else await session.readProvider({prepare: originalReader.prepare,
        receiver: originalReader.receiver, options: Object.freeze(readerOptions)});
      await closeOriginal();
      return await complete();
    } catch (error) {
      if (nativeReadPending && !externalClosed && closeSourceRead !== undefined && owner.managedRun !== undefined &&
          error instanceof AcquisitionOpenError && error.outcome === 'unknown') {
        // The native adapter already attempted cleanup. Preserve its original
        // recovery instead of immediately asking another helper to close it.
        // An absent owner cannot be replaced by a different close's success.
        const original = error.recovery ?? Object.freeze({
          async cleanup() {return false;}, cleanupPending: () => true,
        });
        session.closeAfterFailure(state, original);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      if (!externalClosed && !externalCloseAttempted) {
        try {await closeOriginal();} catch { /* Same cleanup remains pending. */ }
      }
      if (!externalClosed) {
        // The original external child still owns its backing. Do not close
        // the Core RowRun or release that capacity ahead of its actual ACK.
        const recovery = Object.freeze({close() {}, async cleanup() {
          try {await closeOriginal();} catch {return false;}
          return true;
        }, cleanupPending: () => !externalClosed});
        session.closeAfterFailure(state, recovery);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      session.closeAfterFailure(state);
      throw error;
    }
  }

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
