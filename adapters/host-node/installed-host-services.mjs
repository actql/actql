// Standard installed Host service owner. This public cut retains the exact
// original Source implementation/Site association; numerical DATA is neither
// a Run admission nor permission. Other service facets extend this SAME owner.
import {openInstalledRowSite, installedRowCredentialOperationSite, rowSourceCheckEnvironment,
  rowSourceMapping} from './installed-row-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {readSourceProfileJson, readBoundedConfigurationText, installedConfigurationByteLimit,
  installedConfigurationChunkBytes, readOriginalConfigurationText, readOriginalConfigurationBytes,
  installedRuntimeBundleCid} from './source-profile-json.mjs';
import {runtimeField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {types as nodeTypes} from 'node:util';

const installations = new WeakMap();
const sourceContexts = new WeakMap();
const fail = code => {throw Object.assign(new TypeError(code), {code});};

function requireSourceConstructor(services, installation, fields, prepared = false) {
  const original = installations.get(services);
  const field = fields.sourceInitialization;
  if (field === undefined && original.initialPreparation === undefined && original.material === undefined) {
    return installation;
  }
  if (!field || !Object.hasOwn(field, 'value')) fail('InstalledSourceInitializationUnavailable');
  const context = field.value, selected = sourceContexts.get(context);
  if (selected?.original !== original || selected.material.phase !== 'working' ||
      !selected.scope.active || selected.scope.installation !== installation ||
      prepared && (selected.scope.prepared === undefined ||
        selected.scope.role === 'effect' && selected.scope.prepared.mappings === undefined)) {
    fail('InstalledSourceInitializationUnavailable');
  }
  return context;
}

// Native initialization uses the SAME initial Resource reservation. These are
// material quantities for existing shared node/text/byte allowances, not a JS
// Ledger, a profile limit or a second permission/cleanup decision. Small fixed
// methods and control frames belong to the trusted Host baseline.
function sourceMaterial(original) {
  if (original.material !== undefined) return original.material;
  if (original.initialPreparation === undefined) return undefined;
  if (typeof original.restoreDeclaration !== 'function' && typeof original.restoreAuthoredDeclaration !== 'function' ||
      typeof original.declarationJson !== 'function') {
    fail('InstalledSourceInitializationRuntimeUnavailable');
  }
  const methods = Object.freeze({
    TakeHostInitializationSourceCapacity: original.moon.clientProgramTakeHostInitializationSourceCapacity,
    ContinueInstalledSourceMaterial: original.moon.clientProgramContinueInstalledSourceMaterial,
    InstalledSourceConstructionCapacity: original.moon.clientProgramInstalledSourceConstructionCapacity,
    ReserveInstalledSourceConstruction: original.moon.clientProgramReserveInstalledSourceConstruction,
    ReconcileInstalledSourceConstruction: original.moon.clientProgramReconcileInstalledSourceConstruction,
    CompleteInstalledSourceMaterial: original.moon.clientProgramCompleteInstalledSourceMaterial,
    BorrowInstalledSourceMaterial: original.moon.clientProgramBorrowInstalledSourceMaterial,
    BorrowedInstalledSourceEnvironment: original.moon.clientProgramBorrowedInstalledSourceEnvironment,
    ReturnInstalledSourceMaterial: original.moon.clientProgramReturnInstalledSourceMaterial,
    RetireInstalledSourceMaterial: original.moon.clientProgramRetireInstalledSourceMaterial,
    AbortUncontinuedSourceMaterial: original.moon.clientProgramAbortUncontinuedSourceMaterial,
    BeginInstalledSourceIo: original.moon.clientProgramBeginInstalledSourceIo,
    ChargeInstalledSourceIo: original.moon.clientProgramChargeInstalledSourceIo,
    MarkInstalledSourceIoTransferUncertain: original.moon.clientProgramMarkInstalledSourceIoTransferUncertain,
    FinishInstalledSourceIoAfterCleanup: original.moon.clientProgramFinishInstalledSourceIoAfterCleanup,
  });
  for (const fn of Object.values(methods)) {
    if (typeof fn !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
  }
  const material = {methods, input: undefined, unit: undefined, capacity: undefined,
    phase: 'opening', busy: false, ioPending: 0, constructors: 0,
    nodes: 0n, text: 0n, wire: 0n, inputs: [], contexts: [], cleanup: [], workspaces: new Set(),
    environment: undefined, sourceOriginal: undefined, environmentWire: undefined};
  // Retain before the one-shot take or continuation can call the original
  // current fence. A failed continuation still owns the uncontinued pair.
  original.material = material;
  try {
    const pair = checked(Reflect.apply(methods.TakeHostInitializationSourceCapacity,
      original.moon, [original.initialPreparation]));
    material.input = runtimeField(pair, 0); material.unit = runtimeField(pair, 1);
    material.capacity = checked(Reflect.apply(methods.ContinueInstalledSourceMaterial,
      original.moon, [material.unit, material.input]));
    material.phase = 'working';
  } catch (cause) {material.phase = 'failed'; throw cause;}
  return material;
}

function sourceCall(original, material, name, args) {
  if (material.busy) fail('InstalledSourceInitializationReentry');
  material.busy = true;
  try {return checked(Reflect.apply(material.methods[name], original.moon, args));}
  finally {material.busy = false;}
}

// This is only a bound view of the SAME original Core material. The existing
// file owner retains its operation tokens and sole physical close/retry duty.
function sourceIo(original, material) {
  if (material.io !== undefined) return material.io;
  const io = Object.freeze({
    begin(bytes) {
      if (this !== io) fail('ForeignInstalledSourceIo');
      if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
      return sourceCall(original, material, 'BeginInstalledSourceIo', [material.capacity, material.input, bytes]);
    },
    charge(operation, bytes) {
      if (this !== io) fail('ForeignInstalledSourceIo');
      return sourceCall(original, material, 'ChargeInstalledSourceIo', [operation, bytes]);
    },
    uncertain(operation) {
      if (this !== io) fail('ForeignInstalledSourceIo');
      return sourceCall(original, material, 'MarkInstalledSourceIoTransferUncertain', [operation]);
    },
    finish(operation) {
      if (this !== io) fail('ForeignInstalledSourceIo');
      return sourceCall(original, material, 'FinishInstalledSourceIoAfterCleanup', [operation]);
    },
  });
  material.io = io;
  return io;
}

function sourceQuote(original, material, nodes = 0n, text = 0n, wire = 0n) {
  return sourceCall(original, material, 'InstalledSourceConstructionCapacity',
    [material.nodes, material.text, material.wire, nodes, text, wire]);
}

function releaseFinishedSourceWorkspaces(material) {
  for (const workspace of material.workspaces) {
    if (!workspace.finished || typeof workspace.cleanup?.method !== 'function') continue;
    try {
      const value = Reflect.apply(workspace.cleanup.method, workspace.cleanup.handle, []);
      if (Object.getOwnPropertyDescriptor(value ?? {}, 'pending')?.value === false) {
        material.workspaces.delete(workspace);
      }
    } catch { /* An unknown original cleanup state keeps its full workspace. */ }
  }
}

function reserveSource(original, material, nodes = 0n, text = 0n, wire = 0n, workspace) {
  if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
  releaseFinishedSourceWorkspaces(material);
  let activeNodes = nodes, activeText = text, activeWire = wire;
  for (const active of material.workspaces) {
    if (active === workspace) continue;
    activeNodes += active.nodes; activeText += active.text; activeWire += active.wire;
  }
  // Every live original constructor overlaps the completed prefix AND all
  // other active/failed native workspaces. Replace only this read's extent,
  // after the same parent has admitted the complete simultaneous quantities.
  const quote = sourceCall(original, material, 'InstalledSourceConstructionCapacity',
    [material.nodes + activeNodes, material.text + activeText, material.wire + activeWire,
      activeNodes, activeText, activeWire]);
  sourceCall(original, material, 'ReserveInstalledSourceConstruction',
    [material.capacity, material.input, quote]);
  if (workspace !== undefined) Object.assign(workspace, {nodes, text, wire});
}

function reconcileSource(original, material) {
  releaseFinishedSourceWorkspaces(material);
  if (material.workspaces.size !== 0) {
    // Core reconciliation is retained-only. Until every native child has
    // actually closed, keep the admitted high-water debit instead of shrinking
    // beneath a sibling's buffers or a failed original cleanup.
    reserveSource(original, material);
    return;
  }
  sourceCall(original, material, 'ReconcileInstalledSourceConstruction',
    [material.capacity, material.input, sourceQuote(original, material)]);
}

function retainSourceFailure(material, cause, workspace) {
  // Observe only the existing physical cleanup owner's status. Its original
  // retry remains with installed-host-cleanup; this adds no FD retry engine.
  const handle = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle')?.value;
  let child;
  if (handle !== undefined) {
    const method = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
    child = {handle, method};
  } else if (Object.getOwnPropertyDescriptor(Object(cause), 'cleanupPending')?.value === true) {
    child = {handle: undefined, method: undefined};
  }
  if (child !== undefined) material.cleanup.push(child);
  if (workspace !== undefined) {
    workspace.finished = true;
    workspace.cleanup = child;
    if (child === undefined) material.workspaces.delete(workspace);
  }
}

function freezeSourceProjection(value) {
  // The original JSON graph has already been funded and parsed. Freeze that
  // graph in place; do not emit/reparse or mint a second declaration holder.
  const pending = [value];
  while (pending.length !== 0) {
    const node = pending.pop();
    if (node !== null && typeof node === 'object') {
      for (const child of Object.values(node)) {
        if (child !== null && typeof child === 'object') pending.push(child);
      }
      Object.freeze(node);
    }
  }
  return value;
}

// This reader is created only by the real initializer, before the first
// configuration open. Its fixed Buffer peak is reserved before allocation;
// actual received bytes fund native decoding BEFORE concat/text/JSON.parse.
export function installedSourceConfigurationReader(services) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = sourceMaterial(original);
  if (material === undefined) return undefined;
  if (material.configurationReader !== undefined) return material.configurationReader;
  async function read(path, options, json) {
    if (options !== undefined && (nodeTypes.isProxy(options) ||
        Reflect.ownKeys(options).some(name => name !== 'maxBytes'))) {
      fail('InvalidInstalledConfigurationReaderOptions');
    }
    const bound = options === undefined ? undefined : Object.getOwnPropertyDescriptor(options, 'maxBytes');
    if (bound !== undefined && !Object.hasOwn(bound, 'value')) fail('InvalidInstalledConfigurationReaderOptions');
    const maxBytes = bound === undefined || bound.value === undefined
      ? (json ? installedConfigurationByteLimit : undefined) : bound.value;
    if (!Number.isSafeInteger(maxBytes) || maxBytes < 0 ||
        json && maxBytes > installedConfigurationByteLimit) fail('InvalidInstalledSourceProfileByteLimit');
    material.ioPending++;
    const workspace = {nodes: 0n, text: 0n, wire: 0n};
    material.workspaces.add(workspace);
    let decoded;
    try {
      reserveSource(original, material, 0n, 0n,
        2n * BigInt(maxBytes) + BigInt(installedConfigurationChunkBytes), workspace);
      const beforeDecode = bytes => {
        decoded = BigInt(bytes);
        // Native parsed input, checked profile/split projections and original
        // identity preimages can coexist. Four input-proportional native
        // views conservatively cover those representations. Invalid UTF8 may
        // expand to three UTF8 bytes per original byte; escaping is separate.
        reserveSource(original, material, json ? 4n * decoded : 0n,
          12n * decoded, 8n * decoded + BigInt(installedConfigurationChunkBytes), workspace);
      };
      const value = await (json ? readSourceProfileJson : readBoundedConfigurationText)(path,
        {maxBytes, beforeDecode, io: sourceIo(original, material)});
      // The original file has actually closed before retaining/reconciling.
      material.inputs.push(value);
      material.nodes += json ? 4n * decoded : 0n;
      material.text += 12n * decoded;
      // Text inputs can have an actual CA Buffer retained alongside the text.
      material.wire += json ? 0n : decoded;
      material.workspaces.delete(workspace);
      reconcileSource(original, material);
      return value;
    } catch (cause) {retainSourceFailure(material, cause, workspace); throw cause;}
    finally {material.ioPending--;}
  }
  async function readOriginal(path, binary) {
    material.ioPending++;
    const workspace = {nodes: 0n, text: 0n, wire: 0n};
    material.workspaces.add(workspace);
    let decoded;
    try {
      const value = await (binary ? readOriginalConfigurationBytes : readOriginalConfigurationText)(path, {
        io: sourceIo(original, material),
        beforeRead(bytes) {
          reserveSource(original, material, 0n, 0n,
            2n * BigInt(bytes) + BigInt(installedConfigurationChunkBytes), workspace);
        },
        beforeDecode(bytes) {
          decoded = BigInt(bytes);
          reserveSource(original, material, 0n, 12n * decoded,
            8n * decoded + BigInt(installedConfigurationChunkBytes), workspace);
        },
      });
      material.inputs.push(value); material.text += 12n * decoded;
      // Keep the existing key/CA parser and native byte overlap after
      // transferring the same original text or bytes to the Site.
      material.wire += 8n * decoded;
      material.workspaces.delete(workspace);
      reconcileSource(original, material);
      return value;
    } catch (cause) {retainSourceFailure(material, cause, workspace); throw cause;}
    finally {material.ioPending--;}
  }
  const reader = Object.freeze({
    readJson(path, options) {
      if (this !== reader) fail('ForeignInstalledConfigurationReader');
      return read(path, options, true);
    },
    readText(path, options) {
      if (this !== reader) fail('ForeignInstalledConfigurationReader');
      return read(path, options, false);
    },
    async readOriginalText(path) {
      if (this !== reader) fail('ForeignInstalledConfigurationReader');
      return readOriginal(path, false);
    },
    async readOriginalBytes(path) {
      if (this !== reader) fail('ForeignInstalledConfigurationReader');
      return readOriginal(path, true);
    },
  });
  material.configurationReader = reader;
  return reader;
}

export async function withInstalledSourceLoading(services, construct) {
  if (services === undefined) return construct();
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = sourceMaterial(original);
  if (material === undefined) return construct();
  // Keep the SAME awaited initializer pending through module selection,
  // runtime identity, provider construction and the final identity reread.
  // Nested reads retain their actual FD cleanup; no wrapper is priced here.
  material.ioPending++;
  try {return await construct();}
  catch (cause) {retainSourceFailure(material, cause); throw cause;}
  finally {material.ioPending--;}
}

// Provider construction consumes only this original context, never a public
// numerical capacity. Its declaration, native projection and Environment are
// retained together by the same Source successor through Request borrowing.
export function beginInstalledSourceInitialization(services, installation, connectorId, baseEnvironmentWire, role = 'source') {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = sourceMaterial(original);
  if (material === undefined) return undefined;
  if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
  if (original.selected.get(installation) === undefined || typeof connectorId !== 'string' ||
      typeof baseEnvironmentWire !== 'string' || !['source', 'effect'].includes(role) ||
      role === 'effect' && installation.effect === undefined) fail('ForeignInstalledSourceInitialization');
  const scope = {installation, connectorId, baseEnvironmentWire, role, prepared: undefined,
    source: undefined, active: true};
  material.contexts.push(scope); material.constructors++;
  function prepareOriginalDeclaration(restore, originalInput, basis, makeWire, expectedCatalogCid) {
    if (typeof restore !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    // Both existing Common constructors share the same original parent and
    // complete retained projection/Environment/failed-child allowance.
    reserveSource(original, material, 4n * basis, 8n * basis, 8n * basis);
    // Core restoration and projection can cross the original current callback.
    // Keep the SAME constructor fence until its complete outputs are retained.
    let prepared;
    material.busy = true;
    try {
      const wire = makeWire();
      const declaration = checked(Reflect.apply(restore, original.moon,
        [scope.connectorId, scope.installation.registration, scope.installation.revision, wire, expectedCatalogCid]));
      const declaredWire = Reflect.apply(original.declarationJson, original.moon, [declaration]);
      if (typeof declaredWire !== 'string') fail('InvalidInstalledSourceDeclaration');
      const declared = freezeSourceProjection(JSON.parse(declaredWire));
      // An Effect's one Environment needs its Mappings. Do not first build a
      // read-only Environment and repeat that work after Mapping generation.
      const environment = scope.role === 'effect' ? undefined
        : rowSourceCheckEnvironment(scope.baseEnvironmentWire, declared);
      prepared = Object.freeze({declaration, declared, environment});
      scope.prepared = prepared;
      scope.declarationBasis = basis;
      material.inputs.push(originalInput, wire, declaration, declaredWire, declared, environment);
      material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
    } finally {material.busy = false;}
    reconcileSource(original, material);
    return prepared;
  }
  const context = Object.freeze({
    prepareMappings(writesJson, writes) {
      if (this !== context || !scope.active || scope.prepared === undefined ||
          scope.role !== 'effect' || scope.source !== undefined || scope.mappingsAttempted || material.phase !== 'working') {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof original.prepareMapping !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
      const originalPrepared = scope.prepared;
      if (typeof writesJson !== 'string' || !Array.isArray(writes) || nodeTypes.isProxy(writes) ||
          !Object.isFrozen(writes) || writes.length === 0) fail('InvalidInstalledEffectMappings');
      // Inspect only checked immutable own String DATA before the current/
      // resize boundary. Do not stringify proportional input before backing.
      let units = 0n;
      const field = (value, name) => {
        if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || !Object.isFrozen(value)) {
          fail('InvalidInstalledEffectMappings');
        }
        const entry = Object.getOwnPropertyDescriptor(value, name);
        if (!entry || !Object.hasOwn(entry, 'value')) fail('InvalidInstalledEffectMappings');
        return entry.value;
      };
      for (let i = 0; i < writes.length; i++) {
        const write = field(writes, String(i)), resource = field(write, 'resource'), sources = field(write, 'sources');
        if (typeof resource !== 'string' || !Array.isArray(sources) || nodeTypes.isProxy(sources) ||
            !Object.isFrozen(sources)) fail('InvalidInstalledEffectMappings');
        units += BigInt(resource.length);
        for (let j = 0; j < sources.length; j++) {
          const source = field(sources, String(j));
          for (const name of ['target', 'field', 'null_behavior']) {
            const value = field(source, name);
            if (typeof value !== 'string') fail('InvalidInstalledEffectMappings');
            units += BigInt(name.length + value.length);
          }
        }
      }
      // Each retained Mapping can expand the original declaration/writes.
      // The final Environment overlaps those bodies. The SAME proportional
      // material recipe covers the failed prefix, without a second Resource.
      const basis = BigInt(writes.length) * (scope.declarationBasis + 6n * BigInt(writesJson.length)) +
        6n * (units + BigInt(scope.baseEnvironmentWire.length));
      scope.mappingsAttempted = true;
      reserveSource(original, material, 4n * basis, 8n * basis, 8n * basis);
      // Reserve can call the original current fence. Recheck only the local
      // original tuple, without another current callback or semantic check.
      if (!scope.active || material.phase !== 'working' || scope.prepared !== originalPrepared ||
          scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
      let prepared;
      material.busy = true;
      try {
        const runtime = Object.freeze({clientProgramRowSourcePrepareMapping: (...args) =>
          Reflect.apply(original.prepareMapping, original.moon, args)});
        const mappings = Object.freeze(writes.map(write => Object.freeze({resource: write.resource,
          ...rowSourceMapping(runtime, scope.prepared.declaration, writesJson, write.resource, write.sources)})));
        const environment = rowSourceCheckEnvironment(scope.baseEnvironmentWire, scope.prepared.declared,
          mappings.map(mapping => mapping.body));
        prepared = Object.freeze({...scope.prepared, environment, mappings});
        scope.prepared = prepared;
        material.inputs.push(writesJson, writes, mappings, environment);
        material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
      } finally {material.busy = false;}
      reconcileSource(original, material);
      return prepared;
    },
    prepareAuthoredDeclaration(viewsWire, expectedCatalogCid) {
      if (this !== context || !scope.active || scope.prepared !== undefined) {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof viewsWire !== 'string' || expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
        fail('InvalidInstalledSourceDeclarationViews');
      }
      // The original authored-fields wire is immutable input. Do not parse,
      // convert types or stringify another schema before its parent reserves.
      const units = BigInt(scope.connectorId.length) + BigInt(scope.baseEnvironmentWire.length) + BigInt(viewsWire.length);
      return prepareOriginalDeclaration(original.restoreAuthoredDeclaration, viewsWire,
        6n * units + 64n, () => viewsWire, expectedCatalogCid);
    },
    prepareDeclaration(views, expectedCatalogCid) {
      if (this !== context || !scope.active || scope.prepared !== undefined) {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof views === 'string') {
        if (expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
          fail('InvalidInstalledSourceDeclarationViews');
        }
        // Already published schema/facts wires keep their exact original
        // Common entrance. Reserve before parsing or constructing a view list.
        const units = BigInt(scope.connectorId.length) + BigInt(scope.baseEnvironmentWire.length) + BigInt(views.length);
        return prepareOriginalDeclaration(original.restoreDeclaration, views,
          6n * units + 64n, () => views, expectedCatalogCid);
      }
      if (!Array.isArray(views) || nodeTypes.isProxy(views) ||
          expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
        fail('InvalidInstalledSourceDeclarationViews');
      }
      // View specifications contain only provider-authored strings. Measure and
      // reserve before snapshot/stringify; no getter/receiver is invoked here.
      let units = BigInt(scope.connectorId.length + scope.baseEnvironmentWire.length);
      // These are fixed published-view selection frames and original String
      // references, not copied schema payload. Capture before the Core current
      // callback can replace the caller's authored fields.
      const snapshot = [];
      const allowed = ['resource', 'resource_kind', 'schema_wire', 'schema_cid',
        'request_schema_wire', 'facts_wire', 'acquisition_wire',
        'data_classification', 'resource_identity_wire'];
      for (let i = 0; i < views.length; i++) {
        const view = Object.getOwnPropertyDescriptor(views, String(i))?.value;
        if (!view || nodeTypes.isProxy(view)) fail('InvalidInstalledSourceDeclarationViews');
        const fields = Object.getOwnPropertyDescriptors(view);
        const selected = {};
        for (const name of Reflect.ownKeys(fields)) {
          if (!allowed.includes(name) || !Object.hasOwn(fields[name], 'value')) fail('InvalidInstalledSourceDeclarationViews');
          // Preserve the existing JSON.stringify omission rule. Common alone
          // decides required fields and optional classification/identity law.
          if (fields[name].value === undefined) continue;
          if (typeof fields[name].value !== 'string') fail('InvalidInstalledSourceDeclarationViews');
          units += BigInt(name.length + fields[name].value.length);
          selected[name] = fields[name].value;
        }
        snapshot.push(Object.freeze(selected));
      }
      // Restore owns parsed schema/request/facts, checked contract projections,
      // canonical identity preimages, Catalog+manifest and declaration JSON;
      // rowSourceCheckEnvironment then overlaps native inputs and output. This
      // conservative input-proportional allowance covers the whole operation,
      // including its failed child, using existing shared units (not VM prices).
      const basis = 6n * units + 64n * BigInt(views.length);
      return prepareOriginalDeclaration(original.restoreDeclaration, Object.freeze(snapshot), basis,
        () => JSON.stringify({views: snapshot}), expectedCatalogCid);
  }});
  sourceContexts.set(context, {original, material, scope});
  return context;
}

export function assertInstalledSourceConstruction(context, declaration, declared, environment, providerReader, mappings) {
  const retained = sourceContexts.get(context), prepared = retained?.scope.prepared;
  if (retained === undefined || prepared === undefined || !retained.scope.active || retained.material.phase !== 'working' ||
      prepared?.declaration !== declaration || prepared.declared !== declared || prepared.environment !== environment) {
    fail('ForeignInstalledSourceConstruction');
  }
  if (mappings !== undefined && prepared.mappings !== mappings) fail('ForeignInstalledSourceConstruction');
  if (providerReader !== undefined) {
    if (retained.scope.reader !== providerReader || retained.scope.readerDemand === undefined) {
      fail('ForeignInstalledSourceReaderDemand');
    }
    return retained.scope.readerDemand;
  }
}

// Retain the existing admitted protocol holder on the SAME Source successor.
// No Request needs to parse these unchanged installation bodies again. The
// numeric extents describe this constructor's input/output/failed-child overlap;
// only the original initial capacity can admit them, before the Core call.
export function prepareInstalledSourceAcquisitionContracts(context, query, evidence) {
  const retained = sourceContexts.get(context);
  if (retained === undefined || retained.material.phase !== 'working' ||
      !retained.scope.active || retained.scope.prepared === undefined || retained.scope.source !== undefined) {
    fail('ForeignInstalledSourceInitialization');
  }
  const {original, material, scope} = retained;
  if (material.busy) fail('InstalledSourceInitializationReentry');
  if (scope.acquisitionContracts !== undefined) fail('InstalledSourceAcquisitionContractsAlreadyPrepared');
  if (typeof query !== 'string' || typeof evidence !== 'string') fail('InvalidInstalledSourceAcquisitionContracts');
  if (typeof original.admitAcquisitionContracts !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
  const basis = 6n * (BigInt(query.length) + BigInt(evidence.length)) + 64n;
  reserveSource(original, material, 4n * basis, 8n * basis, 8n * basis);
  let contracts;
  material.busy = true;
  try {contracts = checked(Reflect.apply(original.admitAcquisitionContracts, original.moon, [query, evidence]));}
  finally {material.busy = false;}
  if (contracts === undefined || contracts === null) fail('InstalledSourceAcquisitionContractsUnavailable');
  // Retain before any subsequent current/reconcile callback can fail.
  scope.acquisitionContracts = contracts;
  material.inputs.push(query, evidence, contracts);
  material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
  original.current();
  if (material.phase !== 'working' || !scope.active || scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
  reconcileSource(original, material);
  return contracts;
}

export function retainInstalledSourceConstruction(context, source, declaration, declared, environment) {
  assertInstalledSourceConstruction(context, declaration, declared, environment);
  const retained = sourceContexts.get(context);
  if (retained.scope.source !== undefined) fail('InstalledSourceAlreadyConstructed');
  retained.scope.source = source;
}

export function closeInstalledSourceConstruction(context, source) {
  const retained = sourceContexts.get(context);
  if (retained === undefined || retained.scope.source !== source) fail('ForeignInstalledSourceConstruction');
  retained.scope.closed = true;
}

export function finishInstalledSourceInitialization(context, adapter, cause, failed = false) {
  if (context === undefined) return;
  const retained = sourceContexts.get(context);
  if (retained === undefined || !retained.scope.active) fail('ForeignInstalledSourceInitialization');
  if (!failed && retained.scope.source !== adapter) fail('InstalledSourceConstructorUnavailable');
  if (failed) retainSourceFailure(retained.material, cause);
  retained.scope.active = false; retained.material.constructors--;
}

export function reserveInstalledSourceEnvironment(services, ...wires) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = original.material;
  if (material === undefined) return;
  let basis = 0n;
  for (const wire of wires) {
    if (wire !== undefined) {
      if (typeof wire !== 'string') fail('InvalidInstalledSourceEnvironment');
      basis += BigInt(Buffer.byteLength(wire));
    }
  }
  // Existing merge parses each input, builds canonical identities and emits
  // the whole output while the old Source/declaration prefix stays retained.
  reserveSource(original, material, 16n * basis, 16n * basis, 8n * basis);
}

export function reserveInstalledSourceRuntimeIdentity(services) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = sourceMaterial(original);
  if (material === undefined) return;
  // Runtime identity streams immutable software through this existing single
  // chunk, not a full runtime Buffer. Selected code remains Host baseline.
  return async function readOriginalRuntimeIdentity(path) {
    if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
    material.ioPending++;
    const workspace = {nodes: 0n, text: 0n, wire: 0n};
    material.workspaces.add(workspace);
    try {
      reserveSource(original, material, 0n, 0n, BigInt(installedConfigurationChunkBytes), workspace);
      const value = await installedRuntimeBundleCid(path, {io: sourceIo(original, material)});
      material.workspaces.delete(workspace);
      // A runtime-only initialization has no retained body yet. Keep its
      // admitted debit until construction/retirement instead of reconciling a
      // zero body; a live sibling still requires its complete workspace.
      if (material.nodes + material.text + material.wire !== 0n || material.workspaces.size !== 0) {
        reconcileSource(original, material);
      }
      return value;
    }
    catch (cause) {retainSourceFailure(material, cause, workspace);throw cause;}
    finally {material.ioPending--;}
  };
}

export function completeInstalledSourceInitialization(services, sourceOriginal, environment, environmentWire) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = original.material;
  if (material === undefined) return;
  if (sourceOriginal !== material.input) fail('ForeignInstalledSourceMaterial');
  releaseFinishedSourceWorkspaces(material);
  if (material.ioPending !== 0 || material.constructors !== 0 || material.workspaces.size !== 0 || environment === undefined ||
      typeof environmentWire !== 'string') fail('InstalledSourceInitializationPending');
  const bytes = BigInt(Buffer.byteLength(environmentWire));
  reserveSource(original, material, 16n * bytes, 16n * bytes, 8n * bytes);
  material.inputs.push(environmentWire);
  material.nodes += 16n * bytes; material.text += 16n * bytes; material.wire += 8n * bytes;
  sourceCall(original, material, 'CompleteInstalledSourceMaterial', [material.capacity, material.input,
    sourceOriginal, environment, sourceQuote(original, material)]);
  material.sourceOriginal = sourceOriginal; material.environment = environment;
  material.environmentWire = environmentWire; material.phase = 'ready';
}

export function borrowInstalledSourceInitialization(services, sourceOriginal, environment) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = original.material;
  if (material === undefined) return undefined;
  if (material.phase !== 'ready' || material.sourceOriginal !== sourceOriginal || material.environment !== environment) {
    fail('ForeignInstalledSourceMaterial');
  }
  let holder = sourceCall(original, material, 'BorrowInstalledSourceMaterial', [material.capacity]);
  let returned, returnObserved = false;
  const view = Object.freeze({environment() {
    if (this !== view || returnObserved) fail('ForeignInstalledSourceMaterial');
    return sourceCall(original, material, 'BorrowedInstalledSourceEnvironment', [holder, sourceOriginal]);
  }, release() {
    if (this !== view) fail('ForeignInstalledSourceMaterial');
    if (!returnObserved) {
      returned = sourceCall(original, material, 'ReturnInstalledSourceMaterial', [holder]);
      returnObserved = true;
      holder = sourceOriginal = undefined;
    }
    return returned;
  }});
  return view;
}

export function retireInstalledSourceInitialization(services) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = original.material;
  if (material === undefined || material.phase === 'retired') return true;
  if (material.phase === 'opening' || material.busy) return false;
  if (material.ioPending !== 0 || material.constructors !== 0) return false;
  if (material.contexts.some(scope => scope.source !== undefined && scope.closed !== true)) return false;
  for (const child of material.cleanup) {
    if (typeof child.method !== 'function') return false;
    const value = Reflect.apply(child.method, child.handle, []);
    if (Object.getOwnPropertyDescriptor(value ?? {}, 'pending')?.value !== false) return false;
  }
  releaseFinishedSourceWorkspaces(material);
  if (material.workspaces.size !== 0) return false;
  material.phase = 'retiring';
  if (material.capacity === undefined && material.unit === undefined) return false;
  const completed = sourceCall(original, material, material.capacity === undefined
    ? 'AbortUncontinuedSourceMaterial' : 'RetireInstalledSourceMaterial',
  [material.capacity ?? material.unit, material.input]);
  if (completed === true) {
    for (const scope of material.contexts) {
      scope.prepared = scope.source = scope.installation = scope.baseEnvironmentWire = undefined;
      scope.reader = scope.readerDemand = undefined;
      scope.acquisitionContracts = undefined;
    }
    material.inputs.length = material.contexts.length = material.cleanup.length = 0;
    material.workspaces.clear();
    material.io = material.configurationReader = material.sourceOriginal = material.environment = material.environmentWire = undefined;
    material.input = material.unit = material.capacity = material.methods = undefined;
    original.initialPreparation = undefined;
    material.phase = 'retired';
  }
  return completed;
}

// The Calendar provider keeps its original, mandatory profile grammar. This
// projects rejection bounds into the SAME selected generic inventory; it
// neither changes that profile nor reserves or credits any capacity.
function calendarImplementationReaderLimits(supplied, selected) {
  if (selected === undefined || selected.metadata !== 0) {
    fail('InstalledCalendarImplementationProfileUnavailable');
  }
  const names = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxPages', 'maxRows',
    'maxRequests', 'perPage', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
    'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth', 'maxDeclarationBytes',
    'maxDeclarationNodes', 'maxSecretBytes', 'maxCaBytes'];
  if (Reflect.ownKeys(supplied).length !== names.length || names.some(name =>
    !Object.hasOwn(supplied[name] ?? {}, 'value') || !Number.isSafeInteger(supplied[name].value) ||
    supplied[name].value < 1 || supplied[name].value >= 2147483647)) {
    fail('InvalidInstalledCalendarImplementationLimits');
  }
  const original = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
  const policy = selected.value;
  const total = BigInt(original.maxResponseBytes) * BigInt(original.maxPages);
  // Four bytes per original UTF16 unit is a conservative UTF8 ceiling, not
  // a conversion/normalization of the cursor. Check before Number conversion.
  const cursor = 4n * BigInt(original.maxCursorUnits);
  if (original.perPage > 250 || original.maxPages > original.maxRequests ||
      original.perPage > policy.pageSize || original.maxRows > policy.maxTotalRows ||
      original.maxDeclarationBytes > policy.maxDeclarationBytes ||
      original.maxDeclarationNodes > policy.maxDeclarationNodes ||
      total > BigInt(policy.maxTotalResponseBytes) || cursor > BigInt(policy.maxCursorBytes)) {
    fail('InstalledSourceReaderImplementationBoundsExceeded');
  }
  return Object.freeze({original, limits: Object.freeze({
    maxResponseBytes: original.maxResponseBytes, maxTotalResponseBytes: Number(total),
    maxNodes: original.maxNodes, maxDepth: original.maxDepth,
    maxRows: Math.min(original.perPage, original.maxRows), maxTotalRows: original.maxRows,
    maxPages: original.maxPages, pageSize: original.perPage, maxCursorBytes: Number(cursor),
    maxIdentityBytes: original.maxValueTextBytes, maxTargetBytes: policy.maxTargetBytes,
    maxValueNodes: original.maxValueNodes, maxValueTextBytes: original.maxValueTextBytes,
    maxRowsWireBytes: original.maxRowsWireBytes, maxRowsWireNodes: original.maxRowsWireNodes,
    maxRowsWireDepth: original.maxRowsWireDepth, maxSecretBytes: original.maxSecretBytes,
  })});
}

// Project the two existing complete query/point provider grammars once. The
// result retains every original rejection bound; it is not another profile,
// a grant or an independently admitted capacity.
function nestedImplementationReaderLimits(supplied, columns, profile) {
  if (profile === undefined) fail('InstalledSourceSequenceProfileUnavailable');
  const query = Object.hasOwn(supplied, 'maxRowsWireBytes');
  const common = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxRequestBytes', 'maxTargetBytes',
    'maxNodes', 'maxDepth', 'maxIdentityBytes', 'maxRowNodes', 'maxRowDepth', 'maxRowTextBytes',
    'maxColumns', 'maxRowWork', 'maxPropertyPages', 'maxPropertyBytes', 'maxPropertyNodes',
    'maxPropertyTextBytes', 'maxCursorBytes', 'maxPropertyWork', 'pageSize', 'maxSecretBytes'];
  const selected = query
    ? ['maxPages', 'maxTotalRows', 'maxDataSources', 'maxProperties', 'maxNameBytes',
      'maxPageWork', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth', 'maxPropertyItems']
    : ['maxTextBytes', 'maxWireBytes', 'maxWireNodes', 'maxWireDepth',
      'maxDataSources', 'maxProperties', 'maxNameBytes', 'maxPropertyItems'];
  const names = [...common, ...selected];
  if (Reflect.ownKeys(supplied).length !== names.length || names.some(name =>
    !Object.hasOwn(supplied[name] ?? {}, 'value') || !Number.isSafeInteger(supplied[name].value) ||
    supplied[name].value < (!query && ['maxDataSources', 'maxProperties', 'maxNameBytes', 'maxPropertyItems'].includes(name) ? 0 : 1) ||
    supplied[name].value > 2147483647)) fail('InvalidInstalledSourceSequenceLimits');
  const original = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
  const queryPages = query ? original.maxPages : 1, totalRows = query ? original.maxTotalRows : 1;
  const rows = query ? Math.min(original.pageSize, totalRows) : 1;
  if (!Number.isSafeInteger(columns) || columns < 1 || columns > original.maxColumns ||
      original.pageSize > 100 || queryPages > 10000 || original.maxPropertyPages > 10000) {
    fail('InvalidInstalledSourceSequenceLimits');
  }
  const occurrences = BigInt(totalRows) * BigInt(columns);
  const structuralResponses = BigInt(queryPages) + occurrences * BigInt(original.maxPropertyPages);
  // The immutable selected profile owns this total physical response ceiling.
  // Logical query pages and per-property pages retain their original meanings.
  const ceiling = BigInt(profile.value.maxPages);
  const responses = structuralResponses < ceiling ? structuralResponses : ceiling;
  const limits = Object.freeze({
    maxResponseBytes: original.maxResponseBytes, maxTotalResponseBytes: original.maxTotalResponseBytes,
    maxNodes: original.maxNodes, maxDepth: original.maxDepth, maxRows: rows, maxTotalRows: totalRows,
    maxPages: queryPages, pageSize: original.pageSize, maxCursorBytes: original.maxCursorBytes,
    maxIdentityBytes: original.maxIdentityBytes, maxTargetBytes: original.maxTargetBytes,
    maxValueNodes: original.maxRowNodes, maxValueTextBytes: original.maxRowTextBytes,
    maxRowsWireBytes: query ? original.maxRowsWireBytes : original.maxWireBytes,
    maxRowsWireNodes: query ? original.maxRowsWireNodes : original.maxWireNodes,
    maxRowsWireDepth: query ? original.maxRowsWireDepth : original.maxWireDepth,
    maxSecretBytes: original.maxSecretBytes,
  });
  const quote = [...installedJsonSourceReaderLimitNames.map(name => limits[name]),
    original.maxRequestBytes, original.maxPropertyPages, original.maxPropertyBytes,
    original.maxPropertyNodes, original.maxPropertyTextBytes, Number(responses)];
  return Object.freeze({original, limits, quote: Object.freeze(quote), responses: Number(responses),
    propertyOccurrences: Number(occurrences < responses ? occurrences : responses), propertyPages: original.maxPropertyPages});
}

// Original Gmail list/get grammar, not a caller-supplied byte quote. The same
// service retains every selected bound and asks Core to compose its nominal
// prefix with the existing JSON response/row recipe before constructing it.
function gmailThreadImplementationReaderLimits(supplied, columns, profile) {
  const names = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','pageSize','maxPages',
    'maxThreads','maxMailboxBytes','maxTargetBytes','maxIdBytes','maxTokenBytes','maxMessages','maxLabels',
    'maxHeaders','maxHeaderUnits','maxCommentDepth','maxValueNodes','maxValueTextBytes',
    'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth',
    'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'];
  const mayBeZero = ['maxMessages','maxLabels','maxHeaders','maxHeaderUnits','maxCommentDepth','maxValueTextBytes'];
  if (profile === undefined || columns !== 5 || Reflect.ownKeys(supplied).length !== names.length || names.some(name =>
    !Object.hasOwn(supplied[name] ?? {},'value') || !Number.isSafeInteger(supplied[name].value) ||
    supplied[name].value < (mayBeZero.includes(name) ? 0 : 1) || supplied[name].value > 2147483647)) {
    fail('InvalidInstalledGmailThreadReaderLimits');
  }
  const original = Object.freeze(Object.fromEntries(names.map(name => [name,supplied[name].value])));
  if (original.pageSize > 500 || original.maxPages > 2147483647 - original.maxThreads ||
      original.maxMailboxBytes > profile.value.maxIdentityBytes ||
      original.maxDeclarationBytes > profile.value.maxDeclarationBytes ||
      original.maxDeclarationNodes > profile.value.maxDeclarationNodes) fail('InstalledSourceReaderImplementationBoundsExceeded');
  const responses = original.maxPages + original.maxThreads;
  return Object.freeze({original,responses,limits:Object.freeze({
    maxResponseBytes:original.maxResponseBytes,maxTotalResponseBytes:original.maxTotalResponseBytes,
    maxNodes:original.maxNodes,maxDepth:original.maxDepth,maxRows:1,maxTotalRows:original.maxThreads,
    maxPages:responses,pageSize:original.pageSize,maxCursorBytes:original.maxTokenBytes,maxIdentityBytes:original.maxIdBytes,
    maxTargetBytes:original.maxTargetBytes,maxValueNodes:original.maxValueNodes,
    // The quote's positive slot does not replace Gmail's valid zero-text guard.
    maxValueTextBytes:original.maxValueTextBytes === 0 ? 1 : original.maxValueTextBytes,
    maxRowsWireBytes:original.maxRowsWireBytes,maxRowsWireNodes:original.maxRowsWireNodes,
    maxRowsWireDepth:original.maxRowsWireDepth,maxSecretBytes:original.maxSecretBytes,
  }),sequence:Object.freeze({operation:'gmail:threads:list',maxUses:original.maxPages,
    children:Object.freeze([Object.freeze({operation:'gmail:threads:get',maxUses:original.maxThreads})])})});
}

// All three existing Slack resources use one selected implementation. The
// messages protocol's original total exchange/occurrence guards remain in its
// sequence; users/channels additionally need one separately scoped auth.test.
function slackImplementationReaderLimits(supplied, columns, profile) {
  const names = [...installedJsonSourceReaderLimitNames, 'maxDeclarationBytes',
    'maxDeclarationNodes', 'maxSecretBytes', 'maxCaBytes'];
  if (profile === undefined || Reflect.ownKeys(supplied).length !== names.length || names.some(name =>
    !Object.hasOwn(supplied[name] ?? {}, 'value') || !Number.isSafeInteger(supplied[name].value) ||
    supplied[name].value < 1 || supplied[name].value > 2147483647)) fail('InvalidInstalledSlackReaderLimits');
  const original = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
  if (original.maxPages === 2147483647 || original.pageSize >= 1000 ||
      columns > profile.value.maxColumns || original.maxDeclarationBytes > profile.value.maxDeclarationBytes ||
      original.maxDeclarationNodes > profile.value.maxDeclarationNodes) fail('InstalledSourceReaderImplementationBoundsExceeded');
  const children = entries => Object.freeze(entries.map(([operation,maxUses]) => Object.freeze({operation,maxUses})));
  const sequence = (operation,maxUses,entries) => Object.freeze({operation,maxUses,children:children(entries)});
  return Object.freeze({original,limits:Object.freeze({...Object.fromEntries(
    installedJsonSourceReaderLimitNames.map(name => [name,original[name]])),
    maxPages:original.maxPages+1,maxSecretBytes:original.maxSecretBytes}),
    sequences:Object.freeze({
      users:sequence('slack:users:list',original.maxPages,[['slack:workspace:identity',1]]),
      channels:sequence('slack:channels:list',original.maxPages,[['slack:workspace:identity',1]]),
      messages:sequence('slack:messages:history',original.maxPages,[
        ['slack:workspace:identity',original.maxPages],['slack:channels:list',original.maxPages],
        ['slack:messages:replies',original.maxPages]]),
    })});
}

// Snapshot only the existing required Source service methods. The connector
// chooses its own unavailable error and retains its explicit legacy branch.
// This view issues no service, installation, capacity or cleanup observation.
export function captureInstalledSourceServices(receiver, unavailable) {
  if (typeof unavailable !== 'function') throw new TypeError('InvalidInstalledSourceServiceErrorFactory');
  const refuse = () => {throw Reflect.apply(unavailable, undefined, []);};
  if (receiver === null || !['object', 'function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) refuse();
  const methods = Object.create(null);
  for (const name of ['sourceReaderImplementationProfile', 'sourceReaderImplementation', 'openRowSite', 'createSourceReader']) {
    const field = Object.getOwnPropertyDescriptor(receiver, name);
    if (field === undefined || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') refuse();
    methods[name] = field.value;
  }
  Object.freeze(methods);
  return Object.freeze(function invokeInstalledSourceService(name, ...args) {
    if (typeof name !== 'string' || !Object.hasOwn(methods, name)) refuse();
    return Reflect.apply(methods[name], receiver, args);
  });
}

export function createInstalledHostServices({root, principalId, moon, assertCurrent, receiver, initialPreparation}) {
  if (typeof root !== 'string' || !root || typeof principalId !== 'string' || !principalId ||
      !moon || typeof moon !== 'object' || typeof assertCurrent !== 'function') fail('InvalidInstalledHostServices');
  const selected = new WeakMap(), sites = new WeakMap(), siteInstallations = new WeakMap();
  const implementations = new WeakMap(), sourceImplementations = new WeakMap(), sourceProfiles = new WeakMap();
  const publicationOnly = false;
  const sourcePolicy = moon.clientProgramInstalledSourceReaderPolicy;
  const sourceProfile = moon.clientProgramInstalledJsonSourceReaderProfile;
  const sourceCapacity = moon.clientProgramInstalledJsonSourceReaderCapacity;
  const sourceRequestCapacity = moon.clientProgramInstalledJsonSourceReaderCapacityWithRequest;
  const preservingSourceRequestCapacity = moon.clientProgramInstalledPreservingJsonSourceReaderCapacityWithRequest;
  const gmailThreadCapacity = moon.clientProgramInstalledGmailThreadReaderCapacity;
  const slackCapacity = moon.clientProgramInstalledSlackSourceReaderCapacity;
  const current = () => {
    if (Reflect.apply(assertCurrent, receiver, []) !== undefined) fail('InstalledHostServiceCurrentCheckNotSynchronous');
  };
  current();
  const services = Object.freeze({
    sourceReaderImplementationProfile(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== (Object.hasOwn(fields, 'sourceInitialization') ? 4 : 3) || ['installation', 'metadataResponses', 'originUnits'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const metadata = fields.metadataResponses.value, origin = fields.originUnits.value;
      if (![metadata, origin].every(value => Number.isSafeInteger(value) && value >= 0 && value < 2147483647)) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const previous = sourceProfiles.get(selection);
      if (previous !== undefined) {
        if (previous.runtimeBundleCid !== runtimeBundleCid || previous.metadata !== metadata || previous.origin !== origin) {
          fail('InstalledSourceReaderSelectionChanged');
        }
        return previous.value;
      }
      if (sourceImplementations.has(selection)) fail('InstalledSourceReaderProfileSelectedLate');
      if (typeof sourceProfile !== 'function') fail('InstalledSourceReaderProfileUnavailable');
      const returned = Reflect.apply(sourceProfile, moon, [metadata, origin]);
      const values = runtimeIsBoxedSome(returned) ? runtimeField(returned, 0) : undefined;
      if (!Array.isArray(values) || values.length !== installedJsonSourceReaderProfileLimitNames.length ||
          values.some(value => !Number.isSafeInteger(value) || value < 1 || value >= 2147483647)) {
        fail('InvalidInstalledSourceReaderProfile');
      }
      const value = Object.freeze(Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map(
        (name, index) => [name, values[index]])));
      current(); sourceProfiles.set(selection, Object.freeze({runtimeBundleCid, metadata, origin, value}));
      return value;
    },
    sourceReaderImplementation(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) {
        fail('InvalidInstalledSourceReaderSelection');
      }
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      if (Reflect.ownKeys(fields).length !== (Object.hasOwn(fields, 'sourceInitialization') ? 4 : 3) +
          (Object.hasOwn(fields, 'requestConstruction') ? 1 : 0) +
          (Object.hasOwn(fields, 'preservingRequestConstruction') ? 1 : 0) ||
          Object.hasOwn(fields, 'requestConstruction') && Object.hasOwn(fields, 'preservingRequestConstruction') || ['installation', 'limits', 'columnCount'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      if (nodeTypes.isProxy(fields.limits.value ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const columns = fields.columnCount.value;
      const preservingResponse = Object.hasOwn(fields, 'preservingRequestConstruction');
      let requestConstruction;
      if (Object.hasOwn(fields, 'requestConstruction') || preservingResponse) {
        const field = preservingResponse ? fields.preservingRequestConstruction : fields.requestConstruction;
        if (!Object.hasOwn(field, 'value') || !field.value || nodeTypes.isProxy(field.value) ||
            !Object.isFrozen(field.value)) fail('InvalidInstalledSourceRequestConstruction');
        const original = Object.getOwnPropertyDescriptors(field.value);
        if (Reflect.ownKeys(original).length !== 2 ||
            !Object.hasOwn(original.capacity ?? {}, 'value') ||
            !Object.hasOwn(original.maxRequestBytes ?? {}, 'value') ||
            !Number.isSafeInteger(original.maxRequestBytes.value) ||
            original.maxRequestBytes.value < 1 || original.maxRequestBytes.value > 2147483647) {
          fail('InvalidInstalledSourceRequestConstruction');
        }
        requestConstruction = field.value;
      }
      const profile = sourceProfiles.get(selection);
      let supplied = Object.getOwnPropertyDescriptors(fields.limits.value ?? {}), calendarLimits, nestedLimits, threadLimits, slackLimits;
      if (Object.getOwnPropertyDescriptor(installation, 'registration')?.value === 'gmail' &&
          Object.hasOwn(supplied, 'maxThreads')) {
        threadLimits = gmailThreadImplementationReaderLimits(supplied, columns, profile);
        supplied = Object.getOwnPropertyDescriptors(threadLimits.limits);
      }
      if (Object.getOwnPropertyDescriptor(installation, 'registration')?.value === 'slack') {
        slackLimits = slackImplementationReaderLimits(supplied, columns, profile);
        supplied = Object.getOwnPropertyDescriptors(slackLimits.limits);
      }
      if (Object.hasOwn(supplied, 'maxRequestBytes')) {
        // Only the complete original nested grammar has the selected request
        // constructor inventory. A method/body allowance alone is not a recipe.
        if (!Object.hasOwn(supplied, 'maxPropertyPages')) fail('InstalledSourceReaderRequestCapacityUnavailable');
        nestedLimits = nestedImplementationReaderLimits(supplied, columns, profile);
        supplied = Object.getOwnPropertyDescriptors(nestedLimits.limits);
      }
      if (Object.getOwnPropertyDescriptor(installation, 'registration')?.value === 'calendar' &&
          !Object.hasOwn(supplied, 'maxTotalResponseBytes')) {
        const projected = calendarImplementationReaderLimits(supplied, profile);
        calendarLimits = projected.original;
        supplied = Object.getOwnPropertyDescriptors(projected.limits);
      }
      if (requestConstruction !== undefined &&
          (calendarLimits !== undefined || nestedLimits !== undefined || threadLimits !== undefined || slackLimits !== undefined)) {
        fail('InstalledSourceReaderRequestConstructionChanged');
      }
      const names = [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'];
      if (names.some(name => !Object.hasOwn(supplied[name] ?? {}, 'value') ||
          !Number.isSafeInteger(supplied[name].value) || supplied[name].value < 1 || supplied[name].value > 2147483647)) {
        fail('InvalidInstalledSourceReaderLimits');
      }
      if (profile !== undefined && (profile.runtimeBundleCid !== runtimeBundleCid ||
          columns > profile.value.maxColumns || names.some(name =>
            !(nestedLimits !== undefined && name === 'maxPages') && supplied[name].value > profile.value[name]))) {
        fail('InstalledSourceReaderImplementationBoundsExceeded');
      }
      const selectedRequestCapacity = preservingResponse ? preservingSourceRequestCapacity : sourceRequestCapacity;
      if ([sourcePolicy, requestConstruction === undefined ? sourceCapacity : selectedRequestCapacity].some(port => typeof port !== 'function')) fail('InstalledSourceReaderRuntimeUnavailable');
      const policy = Reflect.apply(sourcePolicy, moon, []);
      if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > policy[2] ||
        supplied.maxSecretBytes.value > policy[0]) fail('InstalledSourceReaderPolicyUnavailable');
      const limits = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
      const previous = sourceImplementations.get(selection);
      if (previous !== undefined) {
        if (previous.requestConstruction !== requestConstruction || previous.preservingResponse !== preservingResponse ||
            previous.runtimeBundleCid !== runtimeBundleCid || previous.columns !== columns ||
            (previous.nestedLimits === undefined) !== (nestedLimits === undefined) ||
            nestedLimits !== undefined && Object.keys(nestedLimits.original).some(function sequenceSelectionChanged(name) {
              return previous.nestedLimits.original[name] !== nestedLimits.original[name];
            }) ||
            (previous.calendarLimits === undefined) !== (calendarLimits === undefined) ||
            calendarLimits !== undefined && Object.keys(calendarLimits).some(function calendarSelectionChanged(name) {
              return previous.calendarLimits[name] !== calendarLimits[name];
            }) ||
            (previous.threadLimits === undefined) !== (threadLimits === undefined) ||
            threadLimits !== undefined && Object.keys(threadLimits.original).some(function threadSelectionChanged(name) {
              return previous.threadLimits.original[name] !== threadLimits.original[name];
            }) ||
            (previous.slackLimits === undefined) !== (slackLimits === undefined) ||
            slackLimits !== undefined && Object.keys(slackLimits.original).some(function slackSelectionChanged(name) {
              return previous.slackLimits.original[name] !== slackLimits.original[name];
            }) ||
            names.some(name => previous.value.limits[name] !== limits[name])) fail('InstalledSourceReaderSelectionChanged');
        return previous.value;
      }
      if (threadLimits !== undefined && typeof gmailThreadCapacity !== 'function') fail('InstalledSourceReaderRuntimeUnavailable');
      if (slackLimits !== undefined && typeof slackCapacity !== 'function') fail('InstalledSourceReaderRuntimeUnavailable');
      const capacity = Reflect.apply(slackLimits !== undefined ? slackCapacity : threadLimits === undefined ? requestConstruction === undefined ? sourceCapacity : selectedRequestCapacity : gmailThreadCapacity, moon,
        [nestedLimits?.quote ?? installedJsonSourceReaderLimitNames.map(name => limits[name]), columns, limits.maxSecretBytes,
          ...(slackLimits !== undefined ? [slackLimits.original.maxPages] : threadLimits === undefined
            ? requestConstruction === undefined ? [] : [requestConstruction.capacity]
            : [threadLimits.original.maxPages,threadLimits.original.maxMailboxBytes])]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      const value = Object.freeze({capacity, limits, runAcquisitionLimits: Object.freeze({
        maxBindings: policy[1], maxSecretBytes: limits.maxSecretBytes})});
      current(); sourceImplementations.set(selection, Object.freeze({runtimeBundleCid, columns, calendarLimits, nestedLimits, threadLimits, slackLimits, requestConstruction, preservingResponse, value}));
      return value;
    },
    createSourceReader(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      const standard = Object.hasOwn(fields, 'preparePageReader');
      const managedSequence = Object.hasOwn(fields, 'prepareReadSequence');
      const readerField = managedSequence ? 'prepareReadSequence' : standard ? 'preparePageReader'
        : Object.hasOwn(fields, 'readPages') ? 'readPages' : 'createReader';
      if (Reflect.ownKeys(fields).length !== (standard ? 5 : 4) + (Object.hasOwn(fields, 'sourceInitialization') ? 1 : 0) ||
          ['installation', 'implementation', 'site', readerField, ...(standard ? ['operation'] : [])].some(name =>
            !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value;
      const selection = requireSourceConstructor(services, installation, fields, true);
      const implementation = sourceImplementations.get(selection);
      if (implementation === undefined || implementation.value !== fields.implementation.value ||
          implementation.runtimeBundleCid !== selected.get(installation) ||
          siteInstallations.get(fields.site.value) !== selection) fail('ForeignInstalledSourceReaderSelection');
      // The normal JSON page recipe does not back a retained query/property
      // sequence. Keep this entry refused until that same Source recipe owns
      // constructor, prefix, output and failed-child overlap before use.
      if (managedSequence && implementation.threadLimits === undefined && implementation.slackLimits === undefined) fail('InstalledSourceReaderReadChildCapacityUnavailable');
      if (implementation.requestConstruction !== undefined && !standard) fail('InstalledSourceReaderStandardSelectionRequired');
      if (implementation.nestedLimits !== undefined && !managedSequence) fail('InstalledSourceReaderSequenceSelectionRequired');
      if (implementation.slackLimits !== undefined && !managedSequence) fail('InstalledSourceReaderSequenceSelectionRequired');
      if (implementation.threadLimits !== undefined && !managedSequence) fail('InstalledSourceReaderSequenceSelectionRequired');
      const originalSite = installedRowCredentialOperationSite(fields.site.value.credential);
      const limits = implementation.value.limits, nested = implementation.nestedLimits, threads = implementation.threadLimits, slack = implementation.slackLimits;
      const constructor = sourceContexts.get(selection);
      if (constructor?.scope.reader !== undefined) fail('InstalledSourceReaderAlreadyConstructed');
      const factory = createInstalledCredentialSourceReader({capacity: implementation.value.capacity,
        originalSite, [readerField]: fields[readerField].value, assertCurrent: current,
        maxResponses: nested?.responses ?? limits.maxPages,
        ...(standard ? {operation: fields.operation.value,
          ...(implementation.requestConstruction === undefined ? {} : {maxRequestBytes:implementation.requestConstruction.maxRequestBytes}),
          maxResponseBytes: limits.maxResponseBytes, maxTotalResponseBytes: limits.maxTotalResponseBytes,
          maxSecretBytes: limits.maxSecretBytes} : {}),
        ...(managedSequence ? {maxResponseBytes: limits.maxResponseBytes,
          ...(slack !== undefined ? {maxRequestBytes:2} : nested === undefined ? {} : {maxRequestBytes:nested.original.maxRequestBytes}),
          maxTotalResponseBytes: limits.maxTotalResponseBytes} : {})});
      if (constructor !== undefined) {
        const all = BigInt(nested?.responses ?? limits.maxPages) * BigInt(limits.maxResponseBytes);
        const prefix = BigInt(limits.maxTotalResponseBytes) + BigInt(limits.maxResponseBytes);
        constructor.scope.reader = factory;
        constructor.scope.readerDemand = Object.freeze({nested: nested !== undefined,
          ...(threads === undefined ? {} : {sequence:threads.sequence}),
          ...(slack === undefined ? {} : {sequences:slack.sequences}),
          responses: nested?.responses ?? limits.maxPages, queryPages: limits.maxPages,
          propertyPages: nested?.propertyPages, propertyOccurrences: nested?.propertyOccurrences,
          maxResponseBytes: limits.maxResponseBytes, maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
          maxRows: limits.maxRows, maxTotalRows: limits.maxTotalRows,
          transferBytes: nested === undefined && threads === undefined && slack === undefined || all < prefix ? all : prefix});
      }
      return factory;
    },
    openRowSite(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationPhysicalUnavailable');
      const presentation = Object.getOwnPropertyDescriptor(options ?? {}, 'secretPresentation');
      if (presentation !== undefined && !Object.hasOwn(presentation, 'value')) {
        fail('InvalidRowSourceSecretPresentation');
      }
      const installation = Object.getOwnPropertyDescriptor(options ?? {}, 'installation')?.value;
      const runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation,
        Object.getOwnPropertyDescriptors(options ?? {}), true);
      // An Effect has no Source reader from which to forward these limits.
      // Select the SAME Core implementation policy once on its original
      // constructor. These are rejection bounds only: the adopted Run's
      // operation extent must still back every actual binding/secret before
      // construction, and Account/claim still authorize each physical use.
      const constructor = sourceContexts.get(selection);
      let effectCredentialLimits;
      if (constructor?.scope.role === 'effect') {
        const {scope} = constructor;
        if (Object.hasOwn(options, 'runAcquisitionLimits') || scope.credentialSelecting) {
          fail('InstalledEffectCredentialSelectionUnavailable');
        }
        if (scope.credentialLimits === undefined) {
          if (typeof sourcePolicy !== 'function') fail('InstalledEffectCredentialPolicyUnavailable');
          scope.credentialSelecting = true;
          try {
            const policy = Reflect.apply(sourcePolicy, moon, []);
            if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
              !Number.isSafeInteger(value) || value < 1 || value > 2147483647)) {
              fail('InstalledEffectCredentialPolicyUnavailable');
            }
            // This is a local original/lifetime fence after the selected
            // callback, not a second current or semantic policy admission.
            if (requireSourceConstructor(services, installation,
              Object.getOwnPropertyDescriptors(options), true) !== selection) {
              fail('InstalledEffectCredentialSelectionUnavailable');
            }
            scope.credentialLimits = Object.freeze({maxBindings: policy[1], maxSecretBytes: policy[0]});
          } finally {scope.credentialSelecting = false;}
        }
        effectCredentialLimits = scope.credentialLimits;
      }
      // The caller supplies provider configuration only. It cannot replace the
      // original Host/runtime/current association with equal or copied DATA.
      const implementation = implementations.get(installation);
      if (implementation?.constructing) fail('InstalledEffectDefinitionSelectionReentry');
      if (implementation !== undefined) implementation.sealed = true;
      return openInstalledRowSite({...options,
        ...(effectCredentialLimits === undefined ? {} : {runAcquisitionLimits: effectCredentialLimits}),
        root, principalId, commonMoon: moon, runtimeBundleCid, assertCurrent: current,
        configurationReader: installedSourceConfigurationReader(services)}).then(original => {
          sites.set(original.site, implementation);
          siteInstallations.set(original.site, selection);
        return original;
      });
    },
  });
  const restoreDeclaration = moon.clientProgramRowSourceRestoreRelationDeclaration;
  const restoreAuthoredDeclaration = moon.clientProgramRowSourceRestoreDeclaration;
  const declarationJson = moon.clientProgramRowSourceDeclarationJson;
  const admitAcquisitionContracts = moon.clientProgramRowSourceAdmitAcquisitionContracts;
  const prepareMapping = moon.clientProgramRowSourcePrepareMapping;
  installations.set(services, {selected, current, sites, siteInstallations, implementations,
    sourceImplementations, sourceProfiles, moon, initialPreparation, restoreDeclaration, restoreAuthoredDeclaration, declarationJson,
    admitAcquisitionContracts, prepareMapping});
  return services;
}

export function retainInstalledHostServiceInstallation(services, installation, runtimeBundleCid) {
  if (services === undefined) return;
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  original.current();
  if (!installation || typeof installation !== 'object' || !Object.isFrozen(installation) ||
      !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
    fail('InvalidInstalledHostServiceInstallation');
  }
  const previous = original.selected.get(installation);
  if (previous !== undefined && previous !== runtimeBundleCid) fail(
    'InstalledHostServiceRuntimeChanged');
  original.selected.set(installation, runtimeBundleCid);
}
