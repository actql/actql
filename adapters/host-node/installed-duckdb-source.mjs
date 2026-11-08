// Host-owned physical source installation. Programs select a checked Catalog
// source; they cannot provide a file path, account grant, or transport policy.
import {createHash, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {AcquisitionOpenError, acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {contentCid} from './local-account-config.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';
import {loadDuckDBNativeRuntime} from '../connectors/duckdb/node/native-runtime.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';
import {openCapturedDuckDBSource, prepareCapturedDuckDBSource, prepareRetainedCapturedDuckDBSource,
  capturedDuckDBConfiguration, capturedDuckDBPhysicalCapacity,
  capturedDuckDBPendingCapacity, capturedDuckDBRequirement} from
  './captured-duckdb-source.mjs';
import {checkDuckDBAcquisitionPlanning} from '../connectors/duckdb/node/acquisition-planning.mjs';

const sourceLimits = Object.freeze({
  maxRows: 10000, maxCells: 100000, maxTransportBytes: 10000000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 100,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});

function cid(value) {
  return `sha256:${createHash('sha256').update(JSON.stringify(value))
    .digest('hex')}`;
}

export const INSTALLED_DUCKDB_SOURCE_VERSION =
  'actql-installed-duckdb-source/0.1';

export async function loadInstalledDuckDBSource(path, {root, principalId}) {
  if (path === undefined) return undefined;
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  return installDuckDBSourceProfile(JSON.parse(await readFile(path, 'utf8')),
    {root, principalId});
}

// Original checked DATA snapshots are reusable only by identity. This neither
// admits an Environment nor issues an Account decision or Source construction.
const checkedProfiles = new WeakSet();
export function checkInstalledDuckDBSourceProfile(profile) {
  if (checkedProfiles.has(profile)) return profile;
  if (profile === null || typeof profile !== 'object' || nodeTypes.isProxy(profile) ||
      Array.isArray(profile) ||
      Reflect.ownKeys(Object.getOwnPropertyDescriptors(profile)).some(name =>
        typeof name !== 'string' || !Object.hasOwn(Object.getOwnPropertyDescriptor(profile, name), 'value')) ||
      Object.keys(profile).sort().join('\0') !==
        ['accountConfigurationWire', 'acquisitionPlanning', 'checkEnvironmentWire', 'database',
          'schema', 'sourceRef', 'table', 'version'].join('\0') ||
      profile.version !== 'actql-installed-duckdb-source/0.1' ||
      typeof profile.database !== 'string' ||
      !isAbsolute(profile.database) ||
      !['schema', 'table', 'sourceRef', 'checkEnvironmentWire',
        'accountConfigurationWire'].every(key =>
        typeof profile[key] === 'string' && profile[key].length > 0)) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const acquisitionPlanning = checkDuckDBAcquisitionPlanning(profile.acquisitionPlanning);
  const checked = Object.freeze({...profile, acquisitionPlanning});
  checkedProfiles.add(checked);
  return checked;
}

// Install one original checked profile on the selected Host runtime. The
// bound Source owner retains this gate before another fallible constructor.
export async function installDuckDBSourceProfile(profile, {root, principalId, runtime, retainAuthorization}) {
  profile = checkInstalledDuckDBSourceProfile(profile);
  const acquisitionPlanning = profile.acquisitionPlanning;
  const context = Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-source-context/0.1',
      root, principalId})});
  const options = {configuration: profile.accountConfigurationWire, context};
  const authorization = runtime === undefined
    ? await createNodeAuthorizationGate(options)
    : createAuthorizationGate({...options, runtime});
  // The bound caller owns this original before any returned-profile wrapper
  // or subsequent native-library constructor can fail.
  if (retainAuthorization !== undefined) retainAuthorization(authorization);
  return Object.freeze({
    // The source's own read authorization, for the Host's pre-acquisition
    // Checkpoint decision (the same configuration and context as the
    // adapter's check).
    readAuthorization: Object.freeze({
      accountConfiguration: profile.accountConfigurationWire, context}),
    environmentWire: profile.checkEnvironmentWire,
    database: profile.database, schema: profile.schema,
    table: profile.table, sourceRef: profile.sourceRef,
    sourceAccess: Object.freeze({authorization,
      connection: 'local-database', resource: profile.database,
      sourceRef: profile.sourceRef}),
    transportLimits: sourceLimits, acquisitionPlanning,
  });
}

// The known builtin constructor, selected only by the bound Host factory.
// Its Query/native-acquisition behavior remains the original implementation.
export async function createInstalledDuckDBSource(profile, moon, {root, principalId, sourceInitialization, environment, installation}) {
  if (sourceInitialization !== undefined) {
    assertInstalledSourceConstruction(sourceInitialization, undefined, undefined, environment);
    if (profile.environmentWire !== environment.wire) throw new TypeError('ForeignInstalledSourceConstruction');
  }
  const authorization = profile.sourceAccess.authorization;
  const closeAuthorization = Object.getOwnPropertyDescriptor(authorization, 'close')?.value;
  if (typeof closeAuthorization !== 'function') throw new TypeError('InstalledSourceAuthorizationCleanupMissing');
  let closing = false, closed = false;
  const current = () => {if (closing) throw new TypeError('InstalledSourceReaderNotCurrent');};
  await loadDuckDBNativeRuntime();
  const capacityContracts = Object.freeze(await Promise.all([
    'actql-query-acquisition.json', 'actql-query-process-evidence.json',
    'actql-query-two-receipt.json',
  ].map(name => {
    const path = new URL('../../spec/contracts/' + name, import.meta.url);
    return sourceInitialization === undefined ? readFile(path, 'utf8')
      : readInstalledSourceAcquisitionContract(sourceInitialization, path);
  })));
  if (sourceInitialization !== undefined) assertInstalledSourceConstruction(sourceInitialization, undefined, undefined, environment);
  const common = {moon, database: profile.database, schema: profile.schema,
    table: profile.table, acquisitionPlanning: profile.acquisitionPlanning};
  const catalogs = (environment?.body ?? JSON.parse(profile.environmentWire)).connector_catalogs;
  const catalogIds = catalogs.map(catalog => catalog.connector_id);
  const physicalBinding = duckDBPhysicalTarget(profile);
  const bindingCid = contentCid({version: 'actql-installed-duckdb-source-binding/0.1',
    root, principalId, physicalBinding, sourceRef: profile.sourceRef});
  const preparations = new WeakMap();
  const retainPrepared = (prepared, captureCapacity, retainedOnly = false) => {
    const matches = catalogs.filter(value => value.source_views.some(view =>
      view.contract_cid === prepared.checkedSource.sourceViewContractCid));
    const catalog = matches.length === 1 ? matches[0] : undefined;
    const binding = Object.freeze({connectorId: catalog?.connector_id,
      connectorRegistration: installation?.registration,
      connectorRevision: installation?.revision, bindingCid});
    if (sourceInitialization !== undefined && !validInstallationBinding(binding)) {
      throw new TypeError('InstalledSourcePreparationMismatch');
    }
    preparations.set(prepared, Object.freeze({physicalBinding: prepared.physicalBinding, binding,
      captureCapacity, retainedOnly}));
    return prepared;
  };
  const wholeCapacities = new WeakMap(), wholeReads = new Set();
  let wholePhysical, wholeLimits;
  const prepareWholeLimits = () => {
    if (wholeLimits !== undefined) return wholeLimits;
    wholePhysical = computePhysicalCapacity(profile.transportLimits);
    const maxPageDepth = moon.clientProgramDuckDBWholeSourcePageDepth();
    const maxPageNodes = profile.transportLimits.maxCells + profile.transportLimits.maxRows +
      profile.transportLimits.maxColumns + 1;
    if (!Number.isSafeInteger(maxPageNodes) || maxPageNodes > 2147483647 ||
        !Number.isSafeInteger(maxPageDepth) || maxPageDepth < 1) {
      throw new TypeError('InstalledSourceCapacityUnavailable');
    }
    wholeLimits = Object.freeze({maxRows: profile.transportLimits.maxRows,
      maxBytes: profile.transportLimits.maxChunkBytes ?? profile.transportLimits.maxTransportBytes,
      maxPageRows: profile.transportLimits.maxChunkRows ?? profile.transportLimits.maxRows,
      maxPageNodes, maxPageDepth});
    return wholeLimits;
  };
  const authorizeWhole = async (access, signal) => {
    current(); signal?.throwIfAborted();
    const decision = await access.authorization.authorize('acquisition', {
      connection: access.connection ?? 'local-database', resource: access.resource ?? profile.database,
      operation: 'read'}, {subjectCid: access.subjectCid, signal});
    current(); signal?.throwIfAborted();
    return decision;
  };
  const retireWhole = original => {
    if (original.retired) return;
    if (original.session !== undefined) original.session.close();
    else checked(moon.clientProgramInstalledSourceReadRetire(original.read));
    original.retired = true; wholeReads.delete(original);
  };
  const prepareWhole = async facts => {
    const {preparedProgram, requestIdentity, managedRun, occurrence, sourceAccess = profile.sourceAccess} = facts;
    const selected = wholeCapacities.get(preparedProgram);
    if (selected === undefined || occurrence.stage !== 0 || occurrence.input !== 0 || occurrence.task !== 0 ||
        facts.preparedEffect !== undefined || sourceAccess.sourceRef !== profile.sourceRef) {
      throw new TypeError('InstalledSourcePreparationMismatch');
    }
    if (facts.preparedSource !== undefined) {
      const original = preparations.get(facts.preparedSource);
      if (!original?.wholeInput || original.retired || original.session !== undefined ||
          original.checkedOwner !== preparedProgram || original.requestIdentity !== requestIdentity ||
          original.managedRun !== managedRun || original.capacity !== selected.capacity ||
          original.occurrence.stage !== occurrence.stage || original.occurrence.input !== occurrence.input ||
          original.occurrence.task !== occurrence.task ||
          (sourceAccess.connection ?? 'local-database') !== facts.preparedSource.readTuple.connection ||
          (sourceAccess.resource ?? profile.database) !== facts.preparedSource.readTuple.resource) {
        throw new TypeError('InstalledSourcePreparationMismatch');
      }
      checked(moon.clientProgramInstalledSourceReadCheckCurrent(original.read));
      const decision = await authorizeWhole(sourceAccess);
      if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
      checked(moon.clientProgramInstalledSourceReadCheckCurrent(original.read));
      original.sourceAccess = sourceAccess;
      return facts.preparedSource;
    }
    const tuple = checked(moon.clientProgramInstalledManagedDuckDBWholeSourceRead(
      managedRun, preparedProgram, requestIdentity, selected.capacity));
    const original = {read: runtimeField(tuple, 0), source: runtimeField(tuple, 1),
      acquisition: runtimeField(tuple, 2), capacity: runtimeField(tuple, 3), retired: false,
      checkedOwner: preparedProgram, requestIdentity, managedRun, sourceAccess, occurrence: Object.freeze({...occurrence})};
    wholeReads.add(original);
    try {
      const data = moon.clientProgramWholeSourceFacts(original.acquisition);
      const identity = moon.clientProgramWholeSourceInputIdentity(preparedProgram, original.source);
      if (!Array.isArray(data) || data.length !== 6 || data[0] !== profile.sourceRef || !runtimeIsBoxedSome(identity)) {
        throw new TypeError('InstalledSourcePreparationMismatch');
      }
      const [sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid] = data;
      const prepared = Object.freeze({checkedSource: Object.freeze({
        sourceInput: Object.freeze([...runtimeField(identity, 0)]), sourceRef, sourceContractCid,
        carrierSchemaContractCid, sourceDataPolicyCid, dataClassification, sourceViewContractCid}),
      occurrence: original.occurrence, physicalBinding,
      readTuple: Object.freeze({connection: sourceAccess.connection ?? 'local-database',
        resource: sourceAccess.resource ?? profile.database, operation: 'read'})});
      retainPrepared(prepared, original.capacity);
      Object.assign(original, preparations.get(prepared), {wholeInput: true, prepared});
      preparations.set(prepared, original);
      const decision = await authorizeWhole(sourceAccess);
      if (decision.action === 'deny' || facts.requireImmediateReadAuthorization && decision.action === 'unsupported') {
        throw new ExecutionAuthorizationError(decision);
      }
      checked(moon.clientProgramInstalledSourceReadCheckCurrent(original.read));
      return prepared;
    } catch (cause) {
      try {retireWhole(original);} catch { /* Same original remains with this Source owner. */ }
      throw cause;
    }
  };
  const openWhole = async options => {
    const original = preparations.get(options.preparedSource);
    const occurrence = options.occurrence ?? original?.occurrence;
    if (original === undefined || !original.wholeInput || original.retired || original.session !== undefined ||
        original.checkedOwner !== options.preparedProgram || original.sourceAccess !== (options.sourceAccess ?? profile.sourceAccess) ||
        original.occurrence.stage !== occurrence.stage || original.occurrence.input !== occurrence.input ||
        original.occurrence.task !== occurrence.task || options.ledger === undefined) {
      throw new TypeError('InstalledSourcePreparationMismatch');
    }
    const verifyRead = async () => {
      const decision = await authorizeWhole(original.sourceAccess, options.signal);
      if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
      checked(moon.clientProgramInstalledSourceReadCheckCurrent(original.read));
    };
    let native, grant, rowSession, charge;
    let nativeStarted = false, nativeStopped = false;
    const state = {closeFailed: false};
    try {
      await verifyRead();
      checked(moon.clientProgramInstalledSourceReadCheckLedger(original.read, options.ledger));
      rowSession = startInstalledRowRun({moon, acquisition: original.acquisition, nonce: `duckdb-whole-${randomUUID()}`,
        ledger: options.ledger, originalRead: original.read, wholeInput: true,
        capacity: {transferBytes: wholePhysical.transferBytes, executionBytes: wholePhysical.executionBytes}});
      original.session = rowSession;
      current(); options.signal?.throwIfAborted();
      const run = rowSession.run;
      checked(moon.clientProgramRowSourceBeginWithPageLimits(run, wholeLimits.maxBytes, wholeLimits.maxPageNodes, wholeLimits.maxPageDepth,
        wholeLimits.maxPageRows, wholeLimits.maxRows));
      const sql = checked(moon.clientProgramDuckDBWholeSourceSql(original.capacity, profile.schema, profile.table,
        profile.transportLimits.maxSqlBytes));
      native = await loadDuckDBNativeRuntime();
      grant = await native.session.authorizeLocalDatabase(profile.database, original.sourceAccess);
      current(); options.signal?.throwIfAborted();
      const borrow = checked(moon.clientProgramWholeSourceBorrowResponses(run, original.acquisition));
      checked(moon.clientProgramRowSourceBindResponseCleanup(borrow, () => !nativeStarted || nativeStopped));
      await native.session.withSourceDatabase(grant, profile.transportLimits, async session => {
        const acceptFrame = async frame => {
          await verifyRead();
          if (charge === undefined) throw new TypeError('InstalledSourcePageChargeUnavailable');
          checked(moon.clientProgramDuckDBWholeSourceAcceptPage(run, original.acquisition, charge,
            JSON.stringify(frame.fields.map(({name, type}) => [name, type.id,
              type.precision === undefined ? null : String(type.precision),
              type.scale === undefined ? null : String(type.scale)])),
            JSON.stringify(frame.columns), frame.rowCount));
          charge = undefined;
          await verifyRead();
        };
        await session.command(sql, [], acceptFrame, false, 'ordinary', fields =>
          acceptFrame({fields, columns: fields.map(() => []), rowCount: 0}));
      }, options.signal, {
        started() { checked(moon.clientProgramDuckDBWholeSourceBeginTransport(borrow)); nativeStarted = true; },
        chargeTransfer(bytes) {
          if (charge !== undefined) checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge));
          charge = checked(moon.clientProgramDuckDBWholeSourceChargeResponse(run, BigInt(bytes)));
        },
        settled(confirmed) {nativeStopped = confirmed === true; if (nativeStopped) rowSession.confirmTransportStopped();},
      });
      if (charge !== undefined) {checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge));charge=undefined;}
      await verifyRead();
      const completed = await rowSession.complete({owner: {checkedOwner: original.checkedOwner,
        occurrence: original.occurrence, effectful: false, wholeInput: true,
        providerCaptureCapacity: original.capacity}, prepared: options.preparedSource,
      registry: options.registry, values: options.values, fragment: options.fragment, ordered: options.ordered,
      retainedRelationOutput: options.retainedRelationOutput ?? false, signal: options.signal,
      currentRead: verifyRead, captureOnly: options.captureOnly ?? false});
      // The original dispatch caller immediately retains this same capture.
      // Keep only unreturned/pending children in the Source's fallback bag.
      wholeReads.delete(original);
      return completed;
    } catch (cause) {
      const handle = cause?.cleanupHandle;
      const recovery = handle === undefined ? undefined : Object.freeze({
        async cleanup() {await handle.retry();return !handle.status().pending;},
        cleanupPending: () => handle.status().pending,
      });
      if (rowSession !== undefined) rowSession.closeAfterFailure(state, recovery);
      if (state.closeFailed) {
        const failure = new AcquisitionOpenError(cause, 'unknown', state.recovery);
        options.reportAcquisitionFailure?.(failure); throw failure;
      }
      const failure = acquisitionFailure(cause, nativeStarted ? 'stopped' : 'not_started');
      options.reportAcquisitionFailure?.(failure); throw failure;
    }
  };
  const adapter = Object.freeze({
    realizationKey: 'duckdb-acquired',
    connectorRegistration: installation?.registration,
    connectorRevision: installation?.revision,
    supportsRetainedRelationOutput: true,
    environmentWire: profile.environmentWire,
    ...(sourceInitialization === undefined ? {} : {environmentOriginal: environment}),
    connectorBindings: Object.freeze(catalogIds.map(connectorId =>
      Object.freeze({connectorId, bindingCid}))),
    ordinaryRecoveryBinding(prepared) {
      current();
      const original = preparations.get(prepared);
      if (original === undefined || prepared.physicalBinding !== original.physicalBinding ||
          prepared.checkedSource.sourceRef !== profile.sourceRef) {
        throw new TypeError('InstalledSourcePreparationMismatch');
      }
      return original.binding;
    },
    readAuthorization: profile.readAuthorization,
    sourceAccess: profile.sourceAccess,
    admitsSource: sourceRef => !closing && sourceRef === profile.sourceRef,
    managedEffectPlanSelection() {
      current();
      // Inert inputs to the SAME Plan's native capture constructor. The Plan
      // prepares its Query once; this neither selects an acquisition nor
      // replaces the original Account gate with a row-backed declaration.
      const physical = computePhysicalCapacity(profile.transportLimits);
      return Object.freeze({nativeSource: Object.freeze({sourceRef: profile.sourceRef,
        schema: profile.schema, table: profile.table, contracts: capacityContracts}),
      transferBytes: physical.transferBytes, executionBytes: physical.executionBytes});
    },
    managedWholeSourceCapacity({preparedProgram, sourceSelection, installedContracts}) {
      current();
      if (installation?.registration !== 'builtin_source' || installation?.revision !== 'builtin_source/0.1') {
        throw new TypeError('InstalledSourceRegistrationMismatch');
      }
      prepareWholeLimits();
      if (moon.clientProgramSelectedSourceInputRef(sourceSelection) !== profile.sourceRef) throw new TypeError('InstalledSourceProgramMismatch');
      const capacity = checked(moon.clientProgramPrepareDuckDBWholeSourceCapacity(preparedProgram,
        sourceSelection, installedContracts, wholeLimits.maxRows, wholeLimits.maxBytes, wholeLimits.maxPageNodes, wholeLimits.maxPageDepth, wholeLimits.maxPageRows));
      const facts = moon.clientProgramWholeSourceFacts(moon.clientProgramWholeSourceCapacityAcquisition(capacity));
      const declaredCatalogs = catalogs.filter(catalog => catalog.source_views.some(view => view.contract_cid === facts?.[5]));
      if (!Array.isArray(facts) || facts[0] !== profile.sourceRef || declaredCatalogs.length !== 1 ||
          declaredCatalogs[0].connector_id !== moon.clientProgramDuckDBWholeSourceConnector(capacity)) {
        throw new TypeError('InstalledSourcePreparationMismatch');
      }
      const selected = Object.freeze({capacity, wholeInput: true,
        transferBytes: wholePhysical.transferBytes, executionBytes: wholePhysical.executionBytes});
      wholeCapacities.set(preparedProgram, selected);
      return selected;
    },
    retirePreparedSource(prepared) {
      const original = preparations.get(prepared);
      if (original?.wholeInput) retireWhole(original);
    },
    managedCaptureCapacity(requirement) {
      current();
      if (moon.clientProgramQueryRequirementSourceRef(requirement) !== profile.sourceRef) {
        throw new TypeError('InstalledSourceProgramMismatch');
      }
      const pending = checked(moon.clientProgramPrepareDuckDBCaptureCapacity(
        requirement, profile.schema, profile.table, ...capacityContracts));
      const capacity = moon.clientProgramInstalledPendingDuckDBCaptureCapacity(pending);
      if (capacity === undefined) throw new TypeError('InstalledSourceCapacityUnavailable');
      const physical = computePhysicalCapacity(profile.transportLimits);
      return Object.freeze({capacity, transferBytes: physical.transferBytes,
        executionBytes: physical.executionBytes});
    },
    retainedCapture(prepared) {
      current();
      const original = preparations.get(prepared);
      if (original === undefined || original.retainedOnly) throw new TypeError('InstalledSourcePreparationMismatch');
      if (original.wholeInput) return Object.freeze({inputKind: 'whole-input', wholeInput: true, capacity: original.capacity});
      return Object.freeze({requirement: capturedDuckDBRequirement(prepared),
        capacity: original.captureCapacity ?? moon.clientProgramInstalledPendingDuckDBCaptureCapacity(
          capturedDuckDBPendingCapacity(prepared))});
    },
    ledgerCapacity(prepared) {
      current();
      const original = preparations.get(prepared);
      if (original?.wholeInput) return Object.freeze({capacity: original.capacity, wholeInput: true,
        transferBytes: wholePhysical.transferBytes, executionBytes: wholePhysical.executionBytes});
      const queryPhysical = capturedDuckDBPhysicalCapacity(prepared);
      if (original === undefined) throw new TypeError('InstalledSourcePreparationMismatch');
      const capacity = original.captureCapacity ?? moon.clientProgramInstalledDuckDBCaptureCapacity(
        capturedDuckDBConfiguration(prepared));
      if (capacity === undefined) {
        throw new TypeError('InstalledSourceCapacityUnavailable');
      }
      return Object.freeze({
        capacity,
        transferBytes: queryPhysical.transferBytes,
        executionBytes: queryPhysical.executionBytes,
      });
    },
    prepareRetained({preparedProgram, requestIdentity, occurrence, registry, values, fragment, ordered,
      sourceAccess = profile.sourceAccess}) {
      current();
      const prepared = prepareRetainedCapturedDuckDBSource({...common,
        preparedProgram, requestIdentity, occurrence, registry, values, fragment, ordered, sourceAccess,
        transportLimits: profile.transportLimits});
      current();
      return retainPrepared(prepared, undefined, true);
    },
    prepareRetainedCapture(facts) {
      // This checked metadata constructor opens no database or Source reader.
      // The original recovery Request funds it before restoring its exact
      // saved capture against the same Ledger and current Source binding.
      const prepared = adapter.prepareRetained(facts);
      const original = adapter.managedCaptureCapacity(capturedDuckDBRequirement(prepared));
      current();
      return retainPrepared(prepared, original.capacity);
    },
    prepare: async ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence, requireImmediateReadAuthorization,
      queryTimePreparation, requestIdentity, managedRun, preparedSource}) => {
      current();
      if (managedRun !== undefined && preparedProgram !== undefined && wholeCapacities.has(preparedProgram)) {
        return prepareWhole({preparedProgram, preparedEffect, registry, values, fragment, ordered,
          sourceAccess, occurrence, requireImmediateReadAuthorization, queryTimePreparation, requestIdentity, managedRun, preparedSource});
      }
      let originalCapture;
      if (managedRun !== undefined) {
        const effectful = preparedEffect !== undefined;
        const readOriginal = effectful ? moon.clientProgramInstalledEffectManagedDuckDBCapture
          : moon.clientProgramInstalledManagedDuckDBCapture;
        if (typeof readOriginal !== 'function' || effectful && preparedProgram !== undefined) {
          throw new TypeError('InstalledSourcePreparationMismatch');
        }
        const original = checked(Reflect.apply(readOriginal, moon,
          [managedRun, effectful ? preparedEffect : preparedProgram, requestIdentity, occurrence.task]));
        current();
        originalCapture = Object.freeze({requirement: runtimeField(original, 0),
          capacity: runtimeField(original, 1)});
      }
      const prepared = await prepareCapturedDuckDBSource({...common,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      queryTimePreparation, requestIdentity, originalCapture, originalContracts: capacityContracts,
      sourceAccess, occurrence, requireImmediateReadAuthorization, transportLimits: profile.transportLimits});
      current();
      retainPrepared(prepared, originalCapture?.capacity);
      return prepared;
    },
    open: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, signal, preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput}) => {
      current();
      if (preparations.get(preparedSource)?.wholeInput) return openWhole({preparedProgram, preparedEffect,
        registry, values, fragment, ordered, sourceAccess, signal, preparedSource, reportAcquisitionFailure,
        occurrence, ledger, retainedRelationOutput});
      return openCapturedDuckDBSource({
      ...common, preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, transportLimits: profile.transportLimits, signal,
      preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput});
    },
    openCapture(options) {
      // The existing native opener already omits its standalone Host when
      // borrowing this Ledger. Capture-only must never select a fresh Ledger.
      if (options.ledger === undefined) throw new TypeError('InstalledSourceCaptureLedgerUnavailable');
      return adapter.open(options);
    },
    close() {
      if (closed) return;
      closing = true;
      for (const original of wholeReads) retireWhole(original);
      if (Reflect.apply(closeAuthorization, authorization, []) !== true) {
        throw new TypeError('InstalledSourceAuthorizationCleanupPending');
      }
      if (sourceInitialization !== undefined) closeInstalledSourceConstruction(sourceInitialization, adapter);
      closed = true;
    },
  });
  if (sourceInitialization !== undefined) {
    retainInstalledSourceConstruction(sourceInitialization, adapter, undefined, undefined, environment);
  }
  return adapter;
}
