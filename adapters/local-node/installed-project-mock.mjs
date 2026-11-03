import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createFixtureFileSupplier} from './fixture-file-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime} from '../host-node/installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from '../host-node/installed-project-connections.mjs';
import {loadDeclaredProjectCatalog} from './declared-project-catalog.mjs';
import {composeInstalledCheckEnvironment} from '../host-node/installed-check-environment.mjs';
import {contentCid} from '../host-node/local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';
import {retireNodeInferOriginalRead} from '../host-node/infer-operation.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const mockRealization = 'installed-multi-acquired';
const canonical = value => canonicalJson(value, {dataKeys: true});
const exactCid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

// The exact request Site subject of this same fixed Mock installation, before
// authorization-dependent adapters are built. The returned label grants no
// Source or operation; the installer below uses this same retained constant.
export function installedMockRequestRealization(preparation, runtime) {
  if (preparation.originalsForRuntime(runtime).sources.length < 1) fail('ForeignInstalledMockPreparation');
  return mockRealization;
}

// Original installation preparation under the separately admitted Source
// phase, before any fixture acquisition. The bundled declarations are not
// inferred from rows, a Task, pathname or the original connection's secrets.
// This view supplies no read decision, physical child, Run or capacity.
export async function prepareInstalledProjectMock(moon, project, profile,
  {assertCurrent, openFile, installationInventory} = {}) {
  let projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  if (typeof assertCurrent !== 'function' || typeof project.directory !== 'string' ||
      !project.directory || typeof profile?.originalsForRuntime !== 'function' ||
      typeof profile?.mockLocatorsForRuntime !== 'function') {
    fail('InvalidInstalledMockPreparation');
  }
  let ports = Object.freeze({restore: moon?.clientProgramRowSourceRestoreRelationDeclaration,
    wire: moon?.clientProgramRowSourceDeclarationJson,
    mapping: moon?.clientProgramRelationUpdateMapping,
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
    {assertCurrent: current, installationInventory, ...(openFile === undefined ? {} : {openFile})});
  current();
  let connectionOriginal = connections.originalsForRuntime(moon);
  if (connectionOriginal.project !== projectOriginal ||
      connectionOriginal.connections === undefined) fail('InstalledMockConnectionsUnavailable');
  const count = call('count', connectionOriginal.connections);
  if (!Number.isSafeInteger(count) || count < 0 || count > 128) {
    fail('InstalledMockConnectionCountUnavailable');
  }
  let catalog = await loadDeclaredProjectCatalog(moon, {directory: project.directory,
    catalogFile: locators.catalogFile, dataFile: locators.dataFile, connectionOriginal,
    connections: connectionOriginal.connections,
    assertCurrent: current, openFile, installationInventory});
  let sources = catalog.sources;
  const targets = sources.flatMap(source => source.writes.map(write => ({source, write})));
  if (targets.length > 1) fail('InstalledMockCatalogueUnavailable');
  let writable = targets[0];
  let mappingWire = writable?.write.mappingWire;
  current();
  let originals = Object.freeze({physicalKind: 'declared-json-document',
    project: projectOriginal, selection: selection.selection,
    configuration: selection.configuration, connections: connectionOriginal,
    dataFile: locators.dataFile, dataPath: resolve(project.directory, locators.dataFile),
    sources, mappingWire, writable, catalog});
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
      originals = sources = mappingWire = writable = catalog = connections = connectionOriginal = undefined;
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
  sourceManaged, baseEnvironmentWire, authorizationFor, readAsset, prepareManagedModelRun, prepareManagedSourceRun, effectManagedRun}) {
  if (typeof authorizationFor !== 'function' || typeof readAsset !== 'function' ||
      typeof prepareManagedSourceRun !== 'function' ||
      typeof sourceManaged?.assertCurrent !== 'function' ||
      typeof sourceManaged?.prepareRead !== 'function') fail('NodeManagedRunAdmissionUnavailable');
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (bundle.sources.length < 1) fail('InstalledMockCatalogueUnavailable');
  let closing = false;
  const prepareRequestModel = prepareManagedModelRun;
  const prepareRequestSource = prepareManagedSourceRun;
  const records = new Map(), originalReads = new WeakMap();
  // Weak provenance for Source and Effect Runs already owned by this Host.
  const effectRuns = new WeakMap(), effectReads = new Set(), keyedReads = new Set();
  const sources = [], closedSources = new Set();
  const current = () => {
    if (closing) fail('InstalledMockSourceClosed');
    sourceManaged.assertCurrent();
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  };
  const sameRun = prepared => {
    current();
    const record = records.get(prepared) ?? effectRuns.get(prepared)?.deref();
    if (record === undefined || record.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
    if (record.preparationKind === 'effect-plan') {
      if (typeof effectManagedRun !== 'function' ||
          effectManagedRun(prepared, record.request) !== record) fail('ForeignInstalledModelPreparation');
      return record;
    }
    checked(moon.clientProgramInstalledManagedRunCheck(record.value, prepared, record.request));
    return record;
  };
  function prepareManagedRun(facts) {
    if (arguments.length !== 1 || facts?.preparedProgram === undefined ||
        facts.requestIdentity === undefined || facts.effectful !== undefined) {
      fail('InvalidInstalledManagedRunRequest');
    }
    const {preparedProgram: prepared, requestIdentity: request, prepareInvocation} = facts;
    current();
    if (typeof prepareRequestSource !== 'function') fail('NodeManagedRunAdmissionUnavailable');
    // The Host retains partial construction and the adopted original before
    // this callback returns. This weak index adds no Root or retirement owner.
    const record = Reflect.apply(prepareRequestSource, undefined,
      [Object.freeze({preparedProgram: prepared, requestIdentity: request, prepareInvocation})]);
    if (record?.prepared !== prepared || record.request !== request ||
        record.runtime !== moon || record.closed || record.value === undefined) {
      fail('ForeignInstalledSourcePreparation');
    }
    if (Object.hasOwn(record, 'failure')) throw record.failure;
    effectRuns.set(prepared, new WeakRef(record));
    const value = record.value;
    current();
    if (Object.hasOwn(record, 'failure')) throw record.failure;
    if (effectRuns.get(prepared)?.deref() !== record || record.prepared !== prepared ||
        record.request !== request || record.runtime !== moon || record.closed || record.value !== value) {
      fail('ForeignInstalledSourcePreparation');
    }
    return value;
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
    retireNodeInferOriginalRead(model);
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
  // Called only by the same Host Run after its native retirement succeeds (or
  // the existing payload-sever witness confirms it). This releases aliases,
  // never a physical child, native read or consumed occurrence. The separate
  // physical-close ACK for every original child must already be retained.
  function releaseEffectSourceAliases(prepared, request) {
    const run = this, direct = run.mockSourceReads;
    const reads = [...(direct ?? []), ...(run.mockKeyedReads ?? [])];
    if (effectRuns.get(prepared)?.deref() !== run || run.prepared !== prepared ||
        run.request !== request || run.closed ||
        run.releaseMockSourceAliases !== releaseEffectSourceAliases || !Array.isArray(direct)) {
      fail('InstalledSourcePreparationMismatch');
    }
    // Check the whole same-Run inventory before cutting any sibling's document
    // correspondence. Pending/failed close keeps every original for its retry.
    for (const read of reads) if (read !== undefined) {
      if (!read.physicalClosed || !read.closed && !effectReads.has(read) && !keyedReads.has(read) ||
          read.value !== undefined && originalReads.get(read.value)?.run !== run) {
        fail('InstalledMockSourceCleanupPending');
      }
    }
    for (const read of reads) if (read !== undefined) {
      if (read.value !== undefined) originalReads.delete(read.value);
      effectReads.delete(read); keyedReads.delete(read);
      read.raw = read.close = read.bytes = read.observedBytes = read.document = read.projections = read.value = undefined;
      read.closed = true;
    }
    effectRuns.delete(prepared);
    run.mockSourceReads = run.mockKeyedReads = run.releaseMockSourceAliases = undefined;
  }
  async function closeSource(index) {
    for (const read of keyedReads) if (read.source === index) {
      await closeRead(read); keyedReads.delete(read);
    }
    for (const read of effectReads) if (read.source === index) {
      await closeRead(read);
      effectReads.delete(read);
    }
    for (const record of records.values()) {
      for (const read of record.reads) if (read?.source === index) await closeRead(read);
    }
  }
  async function closeRead(read) {
    if (read === undefined || read.closed) return;
    // A completed Promise or logical retirement cannot acknowledge the
    // physical child. Preserve this read and every projection until its ACK.
    await closePhysicalRead(read);
    if (read.value !== undefined) checked((read.keyed
      ? moon.clientProgramInstalledKeyedSourceReadRetire : moon.clientProgramInstalledSourceReadRetire)(read.value));
    read.closed = true;
    read.raw = read.close = read.bytes = read.observedBytes = read.document = read.projections = undefined;
  }
  async function closePhysicalRead(read) {
    if (read.physicalClosed) return;
    const observed = await Reflect.apply(read.close, read.raw, []);
    const pending = observed !== null && typeof observed === 'object'
      ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
    if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
      fail('InstalledMockSourceCleanupPending');
    }
    read.physicalClosed = true;
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
      const preparedSource = original.sourcePrepared;
      if (typeof original.sourceMember?.load !== 'function' ||
          preparedSource?.declaration !== declaration || preparedSource.wire !== original.wire) {
        fail('InstalledSourceInitializationUnavailable');
      }
      const {declared, environment} = preparedSource;
      const authorization = await authorizationFor(entry.connection);
      current();
      const preparedReads = new WeakMap();
      const knownResources = new Map();
      const referenceIssuer = original.fileBindings.length === 0 ? undefined
        : moon.clientProgramResourceReferenceIssuer((kind, wire) => kind === 'file' && knownResources.has(wire),
          () => {try {current(); return true;} catch {return false;}});
      async function readOriginal(options) {
        const originalRead = options.rowRun.originalRead ?? options.rowRun.originalKeyedRead;
        const held = originalReads.get(originalRead);
        if (held === undefined) fail('InstalledSourcePreparationMismatch');
        const run = sameRun(held.run.prepared), read = held.read;
        if (run !== held.run || read.source !== index || read.value !== originalRead || read.closed) {
          fail('InstalledSourcePreparationMismatch');
        }
        options.signal?.throwIfAborted(); await options.verifyRead();
        options.signal?.throwIfAborted(); sameRun(run.prepared);
        const bytes = await Reflect.apply(read.bytes, read.raw, []);
        options.signal?.throwIfAborted(); sameRun(run.prepared);
        await options.verifyRead(); options.signal?.throwIfAborted(); sameRun(run.prepared);
        const siblings = [...(run.mockSourceReads ?? run.reads), ...(run.mockKeyedReads ?? [])];
        for (const sibling of siblings) if (sibling?.observedBytes !== undefined &&
            !bytes.equals(sibling.observedBytes)) fail('InstalledMockSourceChanged');
        read.observedBytes = bytes;
        return bytes;
      }
      function projectOriginal(physical, bytes, options) {
        const held = originalReads.get(options.rowRun.originalRead ?? options.rowRun.originalKeyedRead);
        if (held === undefined || held.read.source !== index || held.read.observedBytes !== bytes ||
            held.read.document !== undefined || held.read.closed) fail('InstalledSourcePreparationMismatch');
        sameRun(held.run.prepared);
        const document = checked(moon.clientProgramRelationAdmitDocument(bytes, 1048576, 4096, 32, 100, 16777216));
        // Retain the SAME raw backing and every bounded projection under the
        // managed read before another projection/current check can refuse.
        held.read.document = document;
        const projections = held.read.projections = new Map();
        for (const source of bundle.sources) for (const model of source.physical) {
          projections.set(model, checked(moon.clientProgramRelationProjectTargetDocument(document,
            model.declaration, model.resource, model.itemsPath, model.keyPath,
            model.primaryIdentity, model.writableFields)));
        }
        sameRun(held.run.prepared);
        const selected = projections.get(physical);
        if (selected === undefined) fail('InstalledMockPhysicalBindingUnavailable');
        return selected;
      }
      const fileSuppliers = new Map(original.fileBindings.map(binding => {
        const physical = original.physical.find(value => value.resource === binding.data_resource);
        const supplier = createFixtureFileSupplier({moon, physical,
          fields: {identity: binding.identity_field, name: binding.name_field, version: binding.version_field,
            mediaType: binding.media_type_field, contentUtf8: binding.content_utf8_field,
            ...(binding.path_field === undefined ? {} : {path: binding.path_field})},
          limits: {maxBytes: 1048576, maxNodes: 4096, maxDepth: 32, maxRows: 100,
            maxWork: 16777216, maxPageBytes: 1048576, maxContentBytes: 1048576},
          assertCurrent: current, readOriginalBytes: readOriginal,
          projectOriginalDocument: (bytes, options) => projectOriginal(physical, bytes, options),
          issueResource(identity) {
            current();
            const resource = Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
              provider_namespace: entry.provider, resource_kind: 'file', provider_identity_cid: original.scopeCid,
              authority_scope_cid: authorization.context.contextCid, boundary_cid: original.scopeCid,
              identity_cid: exactCid({scope: original.scopeCid, collection: binding.data_resource, identity})});
            const key = canonical(resource);
            if (!knownResources.has(key) && knownResources.size >= 100) fail('InstalledMockResourceInventoryLimit');
            knownResources.set(key, {binding, identity}); return resource;
          },
          resolveResource(resource) {
            current(); const held = knownResources.get(canonical(resource));
            return held?.binding === binding ? held.identity : undefined;
          }});
        return [binding, supplier];
      }));
      const adapter = await original.sourceMember.load({moon, declaration, declared,
        environmentWire: environment.wire, connectorId: entry.connectorId,
        connectorRegistration: entry.registration, connectorRevision: entry.revision,
        bindingCid: contentCid({connection: entry.connection, dataPath: bundle.dataPath,
          declaration: original.wire}), authorization, readOperation: 'read',
        site: Object.freeze({connection: entry.connection,
          async close() {await closeSource(index); knownResources.clear();},
          issueReadGrant({operation, decision, resource, runInvocationCid, dispatchRequestCid, maxUses}) {
            current();
            if (operation !== 'read' || !declared.views.some(view => view.resource === resource) ||
                !/^sha256:[0-9a-f]{64}$/u.test(runInvocationCid) ||
                !/^sha256:[0-9a-f]{64}$/u.test(dispatchRequestCid) || maxUses !== 1 ||
                decision?.action !== 'dispatch' || decision.boundary !== 'acquisition' ||
                decision.tuple?.connection !== entry.connection || decision.tuple?.resource !== resource ||
                decision.tuple?.operation !== 'read' || decision.contextCid !== authorization.context.contextCid ||
                typeof authorization.assertAccountCurrent !== 'function') fail('InstalledMockReadNotAuthorized');
            Reflect.apply(authorization.assertAccountCurrent, authorization, [decision]); current();
            return Object.freeze({runInvocationCid, dispatchRequestCid});
          }}),
        physicalTarget: (resource, fields) => ({connection: entry.connection,
          resource, fields: [...fields], dataPath: bundle.dataPath}),
        readAsset, referenceIssuer,
        limits: {maxPages: 1, maxPageBytes: 1048576, maxPageRows: 100, maxCaptureRows: 100},
        // Match the existing RowRun page decoder's depth envelope. A wider
        // requested limit is rejected before even the original Mock read.
        originalPageLimits: {maxNodes: 4096, maxDepth: 32},
        prepareSourceRead({checkedOwner, effectful, declaration: selected, occurrence, managedRun, originalRead}) {
          const run = sameRun(checkedOwner);
          if (run.closed || run.retiringMockSources) fail('InstalledMockSourceCleanupPending');
          const count = effectful ? moon.clientProgramEffectAcquisitionCount(checkedOwner)
            : moon.clientProgramAcquisitionCount(checkedOwner);
          const shared = effectRuns.get(checkedOwner)?.deref() === run;
          const reads = shared ? run.mockSourceReads ??= [] : run.reads;
          if (effectful !== (run.preparationKind === 'effect-plan' || run.effectful === true) || selected !== declaration ||
              !['stage', 'input', 'task'].every(name => Number.isSafeInteger(occurrence[name]) && occurrence[name] >= 0) ||
              reads.length >= count || reads.some(read => read !== undefined &&
                ['stage', 'input', 'task'].every(name => read.occurrence[name] === occurrence[name])) ||
              shared && (managedRun !== run.value || originalRead === undefined)) fail('InstalledSourcePreparationMismatch');
          if (shared) {
            if (run.releaseMockSourceAliases !== undefined &&
                run.releaseMockSourceAliases !== releaseEffectSourceAliases) fail('InstalledSourcePreparationMismatch');
            run.releaseMockSourceAliases = releaseEffectSourceAliases;
          }
          const raw = sourceManaged.prepareRead(checkedOwner, declaration,
            shared || run.requestOwned ? run.value : run.original, occurrence);
          const read = {raw, source: index, occurrence: Object.freeze({...occurrence}),
            close: undefined, bytes: undefined, value: undefined, closed: false};
          reads.push(read);
          if (shared) effectReads.add(read);
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') {
            fail('InstalledMockSourceUnavailable');
          }
          sourceManaged.assertCurrent();
          read.value = shared ? originalRead : checked(moon.clientProgramInstalledManagedRunSourceReadAt(
            run.value, occurrence.stage, occurrence.input, occurrence.task));
          originalReads.set(read.value, {run, read});
          return read.value;
        },
        async closeSourceRead(value) {
          const held = originalReads.get(value);
          if (held === undefined || held.read.source !== index) fail('InstalledSourcePreparationMismatch');
          // Close the physical/raw child before Row completion. Core capture
          // and the same native read keep their separate retirement duties.
          await closePhysicalRead(held.read);
          return Object.freeze({pending: false});
        },
        prepareKeyedSourceRead({checkedOwner, keyedAcquisition, request, declaration: selected, managedRun, originalRead}) {
          const run = sameRun(checkedOwner);
          if (selected !== declaration || run.closed || run.retiringMockSources ||
              managedRun !== undefined && managedRun !== run.value ||
              typeof sourceManaged.prepareKeyedRead !== 'function') fail('InstalledSourcePreparationMismatch');
          const reads = run.mockKeyedReads ??= [];
          if (reads.some(read => read.request === request)) fail('InstalledSourcePreparationMismatch');
          const raw = sourceManaged.prepareKeyedRead(checkedOwner, declaration, run.value, request);
          const read = {raw, source: index, request, keyed: true, close: undefined, bytes: undefined,
            value: undefined, closed: false};
          reads.push(read); keyedReads.add(read);
          read.close = Object.getOwnPropertyDescriptor(raw, 'close')?.value;
          read.bytes = Object.getOwnPropertyDescriptor(raw, 'readOriginalBytes')?.value;
          if (typeof read.close !== 'function' || typeof read.bytes !== 'function') fail('InstalledMockSourceUnavailable');
          sameRun(checkedOwner);
          read.value = originalRead ?? checked(moon.clientProgramInstalledManagedKeyedSourceRead(
            run.value, keyedAcquisition, request, declaration));
          originalReads.set(read.value, {run, read}); return read.value;
        },
        async closeKeyedSourceRead(value) {
          const held = originalReads.get(value);
          if (held === undefined || held.read.source !== index || !held.read.keyed) fail('InstalledSourcePreparationMismatch');
          await closePhysicalRead(held.read);
          return Object.freeze({pending: false});
        },
        async readPages(options) {
          const {resource, rowRun, chargePage} = options;
          const fileBinding = original.fileBindings.find(binding =>
            binding.listing_resource === resource || binding.content_resource === resource);
          if (fileBinding !== undefined) {
            const supplier = fileSuppliers.get(fileBinding);
            return resource === fileBinding.listing_resource
              ? supplier.readListing(options) : supplier.readContent(options);
          }
          const bytes = await readOriginal(options);
          const charge = chargePage(bytes);
          const physical = original.physical.find(value => value.resource === resource);
          if (physical === undefined || physical.declaration !== declaration) fail('InstalledMockPhysicalBindingUnavailable');
          const selected = projectOriginal(physical, bytes, options);
          checked(moon.clientProgramRelationAcceptChargedDocument(rowRun.run, charge,
            rowRun.acquisition, selected, 16777216));
          current();
        }});
      const queryAliases = Object.freeze(entry.queryAliases.map(alias => {
        const view = declared.views.find(view => view.resource === alias.resource);
        if (view === undefined) fail('InstalledMockCatalogueUnavailable');
        return Object.freeze({name: alias.name, sourceRef: view.source_ref,
          sourceViewContractCid: view.view_cid,
          schemaContractCid: view.carrier_schema_cid});
      }));
      sources.push(Object.freeze({...adapter, queryAliases,
        ...(original.fileBindings.length === 0 ? {} : {requiresRunContentCapture: true}),
        async prepare(facts) {
          const owner = facts.preparedEffect ?? facts.preparedProgram;
          if (facts.preparedEffect !== undefined) {
            if (typeof effectManagedRun !== 'function') fail('InstalledEffectPlanUnavailable');
            const selected = effectManagedRun(owner, facts.requestIdentity);
            if (selected.value !== facts.managedRun) fail('ForeignInstalledModelPreparation');
            effectRuns.set(owner, new WeakRef(selected));
          }
          const run = sameRun(owner);
          // The SAME adopted Plan retains its original Query/acquisition.
          // Let the existing Core borrower select it instead of preparing a
          // second requirement from the physical source description.
          const forwarded = run.requestOwned || effectRuns.get(owner)?.deref() === run ? Object.freeze({...facts,
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
      mockWritableSource: bundle.writable === undefined ? undefined
        : sources[bundle.sources.indexOf(bundle.writable.source)],
      connectorBindings: Object.freeze(sources.flatMap(source => source.connectorBindings)),
      queryAliases: Object.freeze(sources.flatMap(source => source.queryAliases)),
      admitsSource: ref => sources.some(source => source.admitsSource(ref)),
      prepareManagedRun, prepareManagedMockModelRun, modelPreparation, close});
  } catch (error) {
    throw await retainInstalledHostInitializationFailure(error,
      {sourceProfile: {close}});
  }
}
