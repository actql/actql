import {resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from './installed-project-connections.mjs';
import {mockChurnRiskCatalogue} from './mock-churn-risk-catalogue.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {contentCid} from './local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const mockRealization = 'installed-multi-acquired';

// The exact request Site subject of this same fixed Mock installation, before
// authorization-dependent adapters are built. The returned label grants no
// Source or operation; the installer below uses this same retained constant.
export function installedMockRequestRealization(preparation, runtime) {
  if (preparation.originalsForRuntime(runtime).sources.length !== 2) fail('ForeignInstalledMockPreparation');
  return mockRealization;
}

// Original installation preparation under the separately admitted Source
// phase, before any fixture acquisition. The bundled declarations are not
// inferred from rows, a Task, pathname or the original connection's secrets.
// This view supplies no read decision, physical child, Run or capacity.
export async function prepareInstalledProjectMock(moon, project, profile,
  {assertCurrent, openFile} = {}) {
  let projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  if (typeof assertCurrent !== 'function' || typeof project.directory !== 'string' ||
      !project.directory || typeof profile?.originalsForRuntime !== 'function' ||
      typeof profile?.mockLocatorsForRuntime !== 'function') {
    fail('InvalidInstalledMockPreparation');
  }
  let ports = Object.freeze({restore: moon?.clientProgramRowSourceRestoreRelationDeclaration,
    wire: moon?.clientProgramRowSourceDeclarationJson,
    mapping: moon?.clientProgramMockChurnRiskUpdateMapping,
    count: moon?.clientProjectConnectionsCount, name: moon?.clientProjectConnectionsName,
    connector: moon?.clientProjectConnectionsConnector});
  if (!Object.values(ports).every(port => typeof port === 'function')) {
    fail('InstalledProjectRuntimeUnavailable');
  }
  let profilePorts = Object.freeze({originals: profile.originalsForRuntime,
    locators: profile.mockLocatorsForRuntime});
  const call = (name, ...args) => Reflect.apply(ports[name], moon, args);
  const select = name => Reflect.apply(profilePorts[name], profile, [moon]);
  let selection = select('originals');
  function current() {
    assertCurrent();
    const observed = select('originals');
    if (installedProjectOriginalsForRuntime(project, moon) !== projectOriginal ||
        selection.configuration !== projectOriginal.configuration ||
        observed.configuration !== selection.configuration ||
        observed.selection !== selection.selection || observed.selected !== 'mock' ||
        selection.selected !== 'mock') fail('ForeignInstalledMockPreparation');
  }
  current();
  const locators = select('locators');
  if (typeof locators.dataFile !== 'string' || !locators.dataFile ||
      !locators.dataFile.isWellFormed() || locators.dataFile.length > 65536) {
    fail('InstalledMockDataUnavailable');
  }
  // This reads only the explicitly selected connections declaration. The
  // original metadata reader owns its same FD, UTF8 bounds and close carrier;
  // no entry's credential resolver, env variable or network is consulted.
  let connections = await loadInstalledProjectConnections(moon, project,
    {assertCurrent: current, ...(openFile === undefined ? {} : {openFile})});
  current();
  let connectionOriginal = connections.originalsForRuntime(moon);
  if (connectionOriginal.project !== projectOriginal ||
      connectionOriginal.connections === undefined) fail('InstalledMockConnectionsUnavailable');
  const count = call('count', connectionOriginal.connections);
  if (!Number.isSafeInteger(count) || count < 0 || count > 128) {
    fail('InstalledMockConnectionCountUnavailable');
  }
  let sources = [];
  for (const entry of mockChurnRiskCatalogue) {
    let found = false;
    for (let index = 0; index < count; index++) {
      if (call('name', connectionOriginal.connections, index) !== entry.connection) continue;
      if (call('connector', connectionOriginal.connections, index) !== entry.connectorId) {
        fail('InstalledMockConnectionChanged');
      }
      found = true;
    }
    if (!found) fail('InstalledMockCatalogueUnavailable');
    current();
    const declaration = checked(call('restore', entry.connectorId, entry.registration,
      entry.revision, JSON.stringify({views: entry.views}), undefined));
    const wire = call('wire', declaration);
    if (typeof wire !== 'string') fail('InvalidHostRuntimeResult');
    sources.push(Object.freeze({catalogue: entry, declaration, wire}));
  }
  sources = Object.freeze(sources);
  let mappingWire = checked(call('mapping', sources[0].declaration));
  if (typeof mappingWire !== 'string') fail('InvalidHostRuntimeResult');
  current();
  let originals = Object.freeze({project: projectOriginal, selection: selection.selection,
    configuration: selection.configuration, connections: connectionOriginal,
    dataFile: locators.dataFile, dataPath: resolve(project.directory, locators.dataFile),
    sources, mappingWire});
  let retired = false, view;
  function same(runtime, receiver) {
    if (runtime !== moon || receiver !== view) fail('ForeignInstalledMockPreparation');
  }
  view = Object.freeze({
    originalsForRuntime(runtime) {
      same(runtime, this);
      if (retired) fail('InstalledMockPreparationRetired');
      current();
      if (connections.originalsForRuntime(moon) !== connectionOriginal) {
        fail('ForeignInstalledMockPreparation');
      }
      return originals;
    },
    retire(runtime) {
      same(runtime, this);
      if (retired) return;
      // Managed references only, after the actual Source parent's close. This
      // cannot settle its FD, backing bytes, RowRuns or external cleanup ACKs.
      retired = true;
      originals = sources = mappingWire = connections = connectionOriginal = undefined;
      projectOriginal = selection = project = profile = profilePorts = ports = undefined;
      assertCurrent = openFile = undefined;
    },
  });
  return view;
}

// Physical installation of the same already retained Mock declarations. The
// ordinary Host supplies its existing Account gates and the actual selected
// Source/managed-Compute original; neither the profile label nor this factory
// issues a permission, a runtime parent, or a replacement Run.
export async function installPreparedProjectMockSources({moon, mockPreparation,
  sourceManaged, baseEnvironmentWire, authorizationFor, readAsset}) {
  if (typeof authorizationFor !== 'function' || typeof readAsset !== 'function' ||
      typeof sourceManaged?.assertCurrent !== 'function' ||
      typeof sourceManaged?.prepareRun !== 'function' ||
      typeof sourceManaged?.prepareRead !== 'function') fail('NodeManagedRunAdmissionUnavailable');
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (bundle.sources.length !== 2) fail('InstalledMockCatalogueUnavailable');
  let closing = false;
  const records = new Map(), originalReads = new WeakMap();
  const sources = [], closedSources = new Set();
  const current = () => {
    if (closing) fail('InstalledMockSourceClosed');
    sourceManaged.assertCurrent();
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  };
  const sameRun = prepared => {
    current();
    const record = records.get(prepared);
    if (record === undefined || record.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
    checked(moon.clientProgramInstalledManagedRunCheck(record.value, prepared, record.request));
    return record;
  };
  function prepareManagedRun(prepared, request) {
    current();
    let record = records.get(prepared);
    if (record !== undefined) {
      if (record.failure !== undefined) throw record.failure;
      sameRun(prepared);
      checked(moon.clientProgramInstalledManagedRunCheck(record.value, prepared, request));
      return;
    }
    // Retain every acquired original before the next fallible operation. A
    // failed start is sticky; another caller cannot replace the original Run.
    record = {prepared, request, original: undefined, admission: undefined,
      value: undefined, reads: [undefined, undefined], failure: undefined};
    if (records.size === 4096) fail('InstalledMockRunLimit');
    records.set(prepared, record);
    try {
      record.original = sourceManaged.prepareRun(prepared);
      sourceManaged.assertCurrent();
      record.admission = checked(moon.clientProgramNodeManagedRunPrepare(record.original, prepared));
      record.value = checked(moon.clientProgramInstalledManagedRunBegin(record.admission, prepared, request));
      sameRun(prepared);
    } catch (error) { record.failure = error; throw error; }
  }
  async function closeSource(index) {
    for (const record of records.values()) await closeRead(record.reads[index]);
  }
  async function closeRead(read) {
    if (read === undefined || read.closed) return;
    if (read.value !== undefined) checked(moon.clientProgramInstalledSourceReadRetire(read.value));
    // The actual FD/backing owner retains its own observation. A logical
    // Source retirement or completed Promise cannot stand in for that duty.
    const observed = await Reflect.apply(read.close, read.raw, []);
    const pending = observed !== null && typeof observed === 'object'
      ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
    if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
      fail('InstalledMockSourceCleanupPending');
    }
    read.closed = true;
  }
  const close = async () => {
    closing = true;
    const failures = [];
    for (const source of sources) {
      if (closedSources.has(source)) continue;
      try {await source.close(); closedSources.add(source);} catch (error) {failures.push(error);}
    }
    if (failures.length === 0) for (const record of records.values()) {
      try {
        if (record.value !== undefined) checked(moon.clientProgramInstalledManagedRunRetire(record.value));
        else if (record.admission !== undefined) {
          checked(moon.clientProgramNodeManagedRunCleanup(record.admission));
        }
      } catch (error) {failures.push(error);}
    }
    if (failures.length) throw new AggregateError(failures, 'InstalledMockSourceCleanupPending');
  };
  try {
    for (const [index, original] of bundle.sources.entries()) {
      current();
      const entry = original.catalogue, declaration = original.declaration;
      const declared = JSON.parse(original.wire);
      const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
      const authorization = await authorizationFor(entry.connection);
      current();
      const preparedReads = new WeakMap();
      const adapter = await createInstalledRowSource({moon, declaration, declared,
        environmentWire: environment.wire, connectorId: entry.connectorId,
        connectorRegistration: entry.registration, connectorRevision: entry.revision,
        bindingCid: contentCid({connection: entry.connection, dataPath: bundle.dataPath,
          declaration: original.wire}), authorization, readOperation: 'read',
        site: Object.freeze({connection: entry.connection, close: () => closeSource(index)}),
        physicalTarget: (resource, fields) => ({connection: entry.connection,
          resource, fields: [...fields], dataPath: bundle.dataPath}),
        readAsset,
        limits: {maxPages: 1, maxPageBytes: 1048576, maxPageRows: 100, maxCaptureRows: 100},
        // Match the existing RowRun page decoder's depth envelope. A wider
        // requested limit is rejected before even the original Mock read.
        originalPageLimits: {maxNodes: 4096, maxDepth: 32},
        prepareSourceRead({checkedOwner, effectful, declaration: selected, occurrence}) {
          const run = sameRun(checkedOwner);
          if (effectful || selected !== declaration || occurrence.stage !== index ||
              occurrence.input !== 0 || run.reads[index] !== undefined) fail('InstalledSourcePreparationMismatch');
          const raw = sourceManaged.prepareRead(checkedOwner, declaration, run.original);
          const read = {raw, close: undefined, bytes: undefined, value: undefined, closed: false};
          run.reads[index] = read;
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') {
            fail('InstalledMockSourceUnavailable');
          }
          sourceManaged.assertCurrent();
          read.value = checked(moon.clientProgramInstalledManagedRunSourceRead(run.value, index));
          originalReads.set(read.value, run);
          return read.value;
        },
        async readPages({rowRun, chargePage, verifyRead, signal}) {
          const held = originalReads.get(rowRun.originalRead);
          if (held === undefined) fail('InstalledSourcePreparationMismatch');
          const run = sameRun(held.prepared), read = run.reads[index];
          if (read?.value !== rowRun.originalRead || read.closed) fail('InstalledSourcePreparationMismatch');
          signal?.throwIfAborted();
          await verifyRead();
          signal?.throwIfAborted();
          sameRun(run.prepared);
          const bytes = await Reflect.apply(read.bytes, read.raw, []);
          signal?.throwIfAborted();
          sameRun(run.prepared);
          await verifyRead();
          signal?.throwIfAborted();
          sameRun(run.prepared);
          // Charge the full original response once before Common selects its
          // original relation. Never parse/re-encode a synthetic page in JS.
          const charge = chargePage(bytes);
          checked(moon.clientProgramMockChurnRiskAcceptChargedDocument(rowRun.run, charge,
            rowRun.acquisition, bundle.sources[0].declaration,
            bundle.sources[1].declaration, bytes, 2097152));
          sameRun(run.prepared);
        }});
      const queryAliases = Object.freeze(entry.queryAliases.map(alias => {
        const view = declared.views.find(view => view.resource === alias.resource);
        if (view === undefined) fail('InstalledMockCatalogueUnavailable');
        return Object.freeze({name: alias.name, sourceRef: view.source_ref,
          sourceViewContractCid: view.view_cid,
          schemaContractCid: view.carrier_schema_cid});
      }));
      sources.push(Object.freeze({...adapter, queryAliases,
        async prepare(facts) {
          const prepared = await adapter.prepare(facts);
          const run = sameRun(facts.preparedProgram);
          preparedReads.set(prepared, run);
          return prepared;
        },
        ledgerCapacity(prepared) {
          const run = preparedReads.get(prepared);
          if (run === undefined || run !== sameRun(run.prepared)) fail('InstalledSourcePreparationMismatch');
          return Object.freeze({...adapter.ledgerCapacity(prepared), managedRun: run.value});
        }}));
    }
    let environmentWire;
    for (const source of sources) environmentWire = composeInstalledCheckEnvironment(moon,
      baseEnvironmentWire, environmentWire, source.environmentWire);
    current();
    return Object.freeze({realizationKey: mockRealization, environmentWire,
      sources: Object.freeze(sources),
      connectorBindings: Object.freeze(sources.flatMap(source => source.connectorBindings)),
      queryAliases: Object.freeze(sources.flatMap(source => source.queryAliases)),
      admitsSource: ref => sources.some(source => source.admitsSource(ref)),
      prepareManagedRun, close});
  } catch (error) {
    throw await retainInstalledHostInitializationFailure(error,
      {sourceProfile: {close}});
  }
}
