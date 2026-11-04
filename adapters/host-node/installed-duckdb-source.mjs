// Host-owned physical source installation. Programs select a checked Catalog
// source; they cannot provide a file path, account grant, or transport policy.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {contentCid} from './local-account-config.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';
import {loadDuckDBNativeRuntime} from '../connectors/duckdb/node/native-runtime.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';
import {openCapturedDuckDBSource, prepareCapturedDuckDBSource,
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
  const capacityContracts = await Promise.all([
    'actql-query-acquisition.json', 'actql-query-process-evidence.json',
    'actql-query-two-receipt.json',
  ].map(name => {
    const path = new URL('../../spec/contracts/' + name, import.meta.url);
    return sourceInitialization === undefined ? readFile(path, 'utf8')
      : readInstalledSourceAcquisitionContract(sourceInitialization, path);
  }));
  if (sourceInitialization !== undefined) assertInstalledSourceConstruction(sourceInitialization, undefined, undefined, environment);
  const common = {moon, database: profile.database, schema: profile.schema,
    table: profile.table, acquisitionPlanning: profile.acquisitionPlanning};
  const catalogs = (environment?.body ?? JSON.parse(profile.environmentWire)).connector_catalogs;
  const catalogIds = catalogs.map(catalog => catalog.connector_id);
  const physicalBinding = duckDBPhysicalTarget(profile);
  const bindingCid = contentCid({version: 'actql-installed-duckdb-source-binding/0.1',
    root, principalId, physicalBinding, sourceRef: profile.sourceRef});
  const preparations = new WeakMap();
  const adapter = Object.freeze({
    realizationKey: 'duckdb-acquired',
    connectorRegistration: installation?.registration,
    connectorRevision: installation?.revision,
    supportsRetainedRelationOutput: true,
    environmentWire: profile.environmentWire,
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
      if (original === undefined) throw new TypeError('InstalledSourcePreparationMismatch');
      return Object.freeze({requirement: capturedDuckDBRequirement(prepared),
        capacity: original.captureCapacity ?? moon.clientProgramInstalledPendingDuckDBCaptureCapacity(
          capturedDuckDBPendingCapacity(prepared))});
    },
    ledgerCapacity(prepared) {
      current();
      const physical = capturedDuckDBPhysicalCapacity(prepared);
      const original = preparations.get(prepared);
      if (original === undefined) throw new TypeError('InstalledSourcePreparationMismatch');
      const capacity = original.captureCapacity ?? moon.clientProgramInstalledDuckDBCaptureCapacity(
        capturedDuckDBConfiguration(prepared));
      if (capacity === undefined) {
        throw new TypeError('InstalledSourceCapacityUnavailable');
      }
      return Object.freeze({
        capacity,
        transferBytes: physical.transferBytes,
        executionBytes: physical.executionBytes,
      });
    },
    prepare: async ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, occurrence, requireImmediateReadAuthorization,
      queryTimePreparation, requestIdentity, managedRun}) => {
      current();
      let originalCapture;
      if (managedRun !== undefined) {
        if (preparedEffect !== undefined || typeof moon.clientProgramInstalledManagedDuckDBCapture !== 'function') {
          throw new TypeError('InstalledSourcePreparationMismatch');
        }
        const original = checked(moon.clientProgramInstalledManagedDuckDBCapture(
          managedRun, preparedProgram, requestIdentity, occurrence.task));
        current();
        originalCapture = Object.freeze({requirement: runtimeField(original, 0),
          capacity: runtimeField(original, 1)});
      }
      const prepared = await prepareCapturedDuckDBSource({...common,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      queryTimePreparation, requestIdentity, originalCapture,
      sourceAccess, occurrence, requireImmediateReadAuthorization, transportLimits: profile.transportLimits});
      current();
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
        captureCapacity: originalCapture?.capacity}));
      return prepared;
    },
    open: ({preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, signal, preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput}) => {
      current();
      return openCapturedDuckDBSource({
      ...common, preparedProgram, preparedEffect, registry, values, fragment, ordered,
      sourceAccess, transportLimits: profile.transportLimits, signal,
      preparedSource, reportAcquisitionFailure, occurrence, ledger,
      retainedRelationOutput});
    },
    close() {
      if (closed) return;
      closing = true;
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
