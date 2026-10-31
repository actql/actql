import {resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime} from '../host-node/installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from '../host-node/installed-project-connections.mjs';
import {mockChurnRiskCatalogue} from './mock-churn-risk-catalogue.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from '../host-node/installed-row-source.mjs';
import {composeInstalledCheckEnvironment} from '../host-node/installed-check-environment.mjs';
import {contentCid} from '../host-node/local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';
import {inferOriginalReadCleanupComplete} from '../host-node/infer-operation.mjs';

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
  sourceManaged, baseEnvironmentWire, authorizationFor, readAsset, prepareManagedModelRun}) {
  if (typeof authorizationFor !== 'function' || typeof readAsset !== 'function' ||
      typeof sourceManaged?.assertCurrent !== 'function' ||
      typeof sourceManaged?.prepareRun !== 'function' ||
      typeof sourceManaged?.prepareRead !== 'function') fail('NodeManagedRunAdmissionUnavailable');
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (bundle.sources.length !== 2) fail('InstalledMockCatalogueUnavailable');
  let closing = false;
  const prepareRequestModel = prepareManagedModelRun;
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
  function prepareManagedRun(prepared, request, model, effectful = false) {
    if (effectful !== false) fail('InstalledEffectPlanUnavailable');
    current();
    if (model !== undefined && !effectful) fail('InstalledMockModelOperationalAdmissionUnavailable');
    let record = records.get(prepared);
    if (record !== undefined) {
      if (record.failure !== undefined) throw record.failure;
      if (record.model !== model || record.effectful !== effectful) fail('ForeignInstalledModelPreparation');
      sameRun(prepared);
      checked(moon.clientProgramInstalledManagedRunCheck(record.value, prepared, request));
      return;
    }
    // Retain every acquired original before the next fallible operation. A
    // failed start is sticky; another caller cannot replace the original Run.
    record = {prepared, request, original: undefined, admission: undefined,
      value: undefined, reads: [], model, effectful, failure: undefined};
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
  function prepareManagedMockModelRun(prepared, request, control, plan, selection, publicationCapacity) {
    current();
    let record = records.get(prepared);
    if (record !== undefined) {
      if (record.failure !== undefined) throw record.failure;
      if (!record.requestOwned || record.request !== request || record.model?.compiled !== plan.compiled ||
          record.model?.runDefinition !== plan.runDefinition || record.model?.graph !== selection.graph ||
          record.model?.control !== control || record.model.closed) fail('ForeignInstalledModelPreparation');
      sameRun(prepared);
      return;
    }
    if (typeof prepareRequestModel !== 'function') fail('InstalledMockModelOperationalAdmissionUnavailable');
    if (records.size === 4096) fail('InstalledMockRunLimit');
    const model = {control, compiled: plan.compiled, runDefinition: plan.runDefinition,
      graph: selection.graph, occurrence: selection.occurrence, queryTimePreparation: plan.queryTimePreparation,
      scope: undefined, publicationCapacity, releaseAliases() {
        if (this !== model) fail('ForeignInstalledModelPreparation');
        if (record.aliasesReleased) return;
        if (model.scope !== undefined && model.scopeFinished !== true || model.read !== undefined ||
            record.reads.some(read => read !== undefined && !read.closed)) fail('InstalledMockModelCleanupPending');
        records.delete(record.prepared);
        for (const key of Object.keys(model)) model[key] = undefined;
        model.closed = true;
        record.prepared = record.request = record.original = record.value = record.model = record.failure = undefined;
        record.reads.length = 0; record.aliasesReleased = true; record.retired = true;
      }};
    record = {prepared, request, model, requestOwned: true, effectful: false, original: undefined,
      value: undefined, reads: [], failure: undefined};
    records.set(prepared, record);
    try {
      // The original Host owns module/Scope/partial failure on this Request.
      // Local retains this SAME model carrier before either can be issued.
      const run = Reflect.apply(prepareRequestModel, undefined, [prepared, request, model]);
      record.original = run.original; record.value = run.value; record.preparationFunded = true;
      sameRun(prepared);
    } catch (cause) {record.failure = cause; throw cause;}
  }
  function modelPreparation(prepared, plan) {
    const run = sameRun(prepared), model = run.model;
    if (model === undefined || model.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition ||
        model.scope === undefined) fail('ForeignInstalledModelPreparation');
    const publicationCapacity = () => {
      sameRun(prepared);
      if (model.closed || typeof model.publicationCapacity !== 'function') fail('HostResultPublicationUnavailable');
      return model.publicationCapacity();
    };
    return Object.freeze({control: model.control, compiled: model.compiled,
      runDefinition: model.runDefinition, scope: model.scope, publicationCapacity,
      readRetainedBytes: model.budget.readRetainedBytes, readExecutionBytes: model.budget.readExecutionBytes,
      modelRetainedBytes: model.budget.modelRetainedBytes, modelExecutionBytes: model.budget.modelExecutionBytes,
      retain() {
        if (model.closed || model.taken || model.readAttempted) fail('ForeignInstalledModelPreparation');
        model.taken = true;
      },
      openSourceFreeHost(registry, values, fragment, ordered, providers) {
        sameRun(prepared);
        if (run.effectful || run.retired || model.closed || !model.taken || model.hostAttempted ||
            moon.clientProgramAcquisitionCount(prepared) !== 0) {
          fail('ForeignInstalledModelPreparation');
        }
        // The checked Source-free driver and Model component borrow this
        // original Run Ledger. No captured Source or second parent is made.
        model.hostAttempted = true;
        return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
          run.value, prepared, run.request, registry, values, fragment, ordered, providers));
      },
      prepareRead() {
        // The Scope predates all Sources. Its descriptor/read snapshots the
        // same Ledger only when Local hands the actual prefix inputs to the
        // Model component: earlier Source/Compute mutations must not make a
        // previously issued claim stale, nor may they reset a spent claim.
        if (model.closed) fail('ForeignInstalledModelPreparation');
        if (model.readAttempted && model.readFailure !== undefined) throw model.readFailure;
        if (!model.taken || model.readAttempted) fail('ForeignInstalledModelPreparation');
        model.readAttempted = true;
        try {
          sameRun(prepared);
          model.read = model.control.prepareCheckedClientInferOriginalRead(model.compiled,
            model.runDefinition, model.graph, model.scope, model.budget);
          return Object.freeze({control: model.control, compiled: model.compiled,
            runDefinition: model.runDefinition, scope: model.scope, read: model.read, publicationCapacity,
            readRetainedBytes: model.budget.readRetainedBytes, readExecutionBytes: model.budget.readExecutionBytes,
            modelRetainedBytes: model.budget.modelRetainedBytes, modelExecutionBytes: model.budget.modelExecutionBytes});
        } catch (error) {model.readFailure = error; throw error;}
      },
      async retire() {
        if (model.closed || run.retired) return true;
        // Source capture can still be borrowed by the Local DAG. Its own
        // retirement/FD checks, not Model completion, decide when each read
        // is closed. The same scope then checks the whole original census.
        for (const read of run.reads) await closeRead(read);
        retireModelRead(model);
        if (model.control.finishCheckedClientInferOriginalReadScope(model.compiled,
          model.runDefinition, model.graph, model.scope, true) !== true) return false;
        model.scopeFinished = true;
        if (run.requestOwned) {
          // Physical child/Scope cleanup is complete. Existing Host registry
          // retirement still owns payload severing, borrows and parent stop.
          model.closed = true;
          return true;
        }
        retireRunRecord(run);
        return true;
      }});
  }
  function retireModelRead(model) {
    if (model.read === undefined) return;
    if (inferOriginalReadCleanupComplete(model.read)) {
      // Core stopped the same consuming execution, not this parent's read
      // reservation. Its separate owning cleanup settles that original once
      // after Source custody above has closed; a failed settlement retains it.
      model.control.settleCheckedClientInferOriginalReadPreparation(model.compiled,
        model.runDefinition, model.graph, model.read, true);
      model.read = undefined;
      return;
    }
    model.control.stopCheckedClientInferOriginalReadPreparation(model.compiled,
      model.runDefinition, model.graph, model.scope, model.read);
    model.control.settleCheckedClientInferOriginalReadPreparation(model.compiled,
      model.runDefinition, model.graph, model.read, true);
    model.read = undefined;
  }
  function retireRunRecord(record) {
    if (record.retired) return;
    if (record.requestOwned) {
      if (!record.model?.closed) fail('InstalledMockModelCleanupPending');
      return;
    }
    if (record.value !== undefined) checked(moon.clientProgramInstalledManagedRunRetire(record.value));
    else if (record.admission !== undefined) checked(moon.clientProgramNodeManagedRunCleanup(record.admission));
    record.retired = true;
  }
  async function closeSource(index) {
    for (const record of records.values()) {
      for (const read of record.reads) if (read?.source === index) await closeRead(read);
    }
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
        if (record.requestOwned) {
          const model = record.model;
          if (model.taken && !model.closed) fail('InstalledMockModelCleanupPending');
          retireModelRead(model);
          if (model.scope !== undefined && model.scopeFinished !== true) {
            if (model.control.finishCheckedClientInferOriginalReadScope(model.compiled,
              model.runDefinition, model.graph, model.scope, true) !== true) fail('InstalledMockModelCleanupPending');
            model.scopeFinished = true;
          }
          model.closed = true;
        }
        if (record.model?.read !== undefined) {
          // A handed-off component owns its real cleanup. Host close cannot
          // acknowledge it just because both Source FileHandles have closed.
          if (record.model.taken) fail('InstalledMockModelCleanupPending');
          retireModelRead(record.model);
        }
        retireRunRecord(record);
      } catch (error) {failures.push(error);}
    }
    if (failures.length) throw new AggregateError(failures, 'InstalledMockSourceCleanupPending');
    // Retire only our managed references, after every original Source close
    // and the same Run's cleanup have succeeded. A failed sibling or Model
    // cleanup retains this whole record for its original retry; clearing it
    // is not an FD/native acknowledgement or a promise about GC/RSS.
    for (const record of records.values()) {
      // The same Host Run continuation cuts Request-owned aliases only after
      // its actual Core payload-sever witness; close is not that witness.
      if (record.requestOwned) continue;
      if (record.model !== undefined) {
        const model = record.model;
        model.closed = true;
        model.control = model.compiled = model.compilation = model.runDefinition = model.graph = undefined;
        model.publicationCapacity = undefined;
        model.occurrence = model.scope = model.budget = model.readFailure = undefined;
      }
      record.prepared = record.request = record.original = record.admission = record.value = undefined;
      record.model = record.failure = undefined;
      record.reads.length = 0;
    }
    records.clear();
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
          if (effectful !== false) fail('InstalledEffectPlanUnavailable');
          const run = sameRun(checkedOwner);
          const count = moon.clientProgramAcquisitionCount(checkedOwner);
          const slot = occurrence.stage;
          if (effectful !== run.effectful || selected !== declaration ||
              !Number.isSafeInteger(slot) || slot < 0 || slot >= count ||
              occurrence.input !== 0 || run.reads[slot] !== undefined) fail('InstalledSourcePreparationMismatch');
          const raw = sourceManaged.prepareRead(checkedOwner, declaration,
            run.requestOwned ? run.value : run.original);
          const read = {raw, source: index, close: undefined, bytes: undefined, value: undefined, closed: false};
          run.reads[slot] = read;
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') {
            fail('InstalledMockSourceUnavailable');
          }
          sourceManaged.assertCurrent();
          read.value = checked(moon.clientProgramInstalledManagedRunSourceRead(run.value, slot));
          originalReads.set(read.value, {run, read});
          return read.value;
        },
        async readPages({rowRun, chargePage, verifyRead, signal}) {
          const held = originalReads.get(rowRun.originalRead);
          if (held === undefined) fail('InstalledSourcePreparationMismatch');
          const run = sameRun(held.run.prepared), read = held.read;
          if (run !== held.run || read.source !== index ||
              read.value !== rowRun.originalRead || read.closed) fail('InstalledSourcePreparationMismatch');
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
          const owner = facts.preparedEffect ?? facts.preparedProgram, run = sameRun(owner);
          // The SAME adopted Plan retains its original Query/acquisition.
          // Let the existing Core borrower select it instead of preparing a
          // second requirement from the physical source description.
          const forwarded = run.requestOwned ? Object.freeze({...facts,
            managedRun: run.value, requestIdentity: run.request}) : facts;
          const prepared = await adapter.prepare(forwarded);
          if (sameRun(owner) !== run) fail('ForeignInstalledModelPreparation');
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
      prepareManagedRun, prepareManagedMockModelRun, modelPreparation, close});
  } catch (error) {
    throw await retainInstalledHostInitializationFailure(error,
      {sourceProfile: {close}});
  }
}
