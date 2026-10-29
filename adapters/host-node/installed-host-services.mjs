// Standard installed Host service owner. This public cut retains the exact
// original Source implementation/Site association; numerical DATA is neither
// a Run admission nor permission. Other service facets extend this SAME owner.
import {openInstalledRowSite, installedRowCredentialOperationSite, rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {readSourceProfileJson, readBoundedConfigurationText, installedConfigurationByteLimit,
  installedConfigurationChunkBytes, readOriginalConfigurationText} from './source-profile-json.mjs';
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
      prepared && selected.scope.prepared === undefined) {
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
  if (typeof original.restoreDeclaration !== 'function' || typeof original.declarationJson !== 'function') {
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
  });
  for (const fn of Object.values(methods)) {
    if (typeof fn !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
  }
  const material = {methods, input: undefined, unit: undefined, capacity: undefined,
    phase: 'opening', busy: false, ioPending: 0, constructors: 0,
    nodes: 0n, text: 0n, wire: 0n, inputs: [], contexts: [], cleanup: [],
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

function sourceQuote(original, material, nodes = 0n, text = 0n, wire = 0n) {
  return sourceCall(original, material, 'InstalledSourceConstructionCapacity',
    [material.nodes, material.text, material.wire, nodes, text, wire]);
}

function reserveSource(original, material, nodes = 0n, text = 0n, wire = 0n) {
  if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
  // The new retained result and the constructor workspace overlap the old
  // prefix. Both extents precede allocation; reconciliation only releases.
  const quote = sourceCall(original, material, 'InstalledSourceConstructionCapacity',
    [material.nodes + nodes, material.text + text, material.wire + wire, nodes, text, wire]);
  sourceCall(original, material, 'ReserveInstalledSourceConstruction',
    [material.capacity, material.input, quote]);
}

function reconcileSource(original, material) {
  sourceCall(original, material, 'ReconcileInstalledSourceConstruction',
    [material.capacity, material.input, sourceQuote(original, material)]);
}

function retainSourceFailure(material, cause) {
  // Observe only the existing physical cleanup owner's status. Its original
  // retry remains with installed-host-cleanup; this adds no FD retry engine.
  const handle = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle')?.value;
  if (handle !== undefined) {
    const method = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
    material.cleanup.push({handle, method});
  } else if (Object.getOwnPropertyDescriptor(Object(cause), 'cleanupPending')?.value === true) {
    material.cleanup.push({handle: undefined, method: undefined});
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
    let decoded;
    try {
      reserveSource(original, material, 0n, 0n,
        2n * BigInt(maxBytes) + BigInt(installedConfigurationChunkBytes));
      const beforeDecode = bytes => {
        decoded = BigInt(bytes);
        // Native parsed input, checked profile/split projections and original
        // identity preimages can coexist. Four input-proportional native
        // views conservatively cover those representations. Invalid UTF8 may
        // expand to three UTF8 bytes per original byte; escaping is separate.
        reserveSource(original, material, json ? 4n * decoded : 0n,
          12n * decoded, 8n * decoded + BigInt(installedConfigurationChunkBytes));
      };
      const value = await (json ? readSourceProfileJson : readBoundedConfigurationText)(path,
        {maxBytes, beforeDecode});
      // The original file has actually closed before retaining/reconciling.
      material.inputs.push(value);
      material.nodes += json ? 4n * decoded : 0n;
      material.text += 12n * decoded;
      // Text inputs can have an actual CA Buffer retained alongside the text.
      material.wire += json ? 0n : decoded;
      reconcileSource(original, material);
      return value;
    } catch (cause) {retainSourceFailure(material, cause); throw cause;}
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
      material.ioPending++;
      let decoded;
      try {
        const value = await readOriginalConfigurationText(path, {
          beforeRead(bytes) {
            reserveSource(original, material, 0n, 0n,
              2n * BigInt(bytes) + BigInt(installedConfigurationChunkBytes));
          },
          beforeDecode(bytes) {
            decoded = BigInt(bytes);
            reserveSource(original, material, 0n, 12n * decoded,
              8n * decoded + BigInt(installedConfigurationChunkBytes));
          },
        });
        material.inputs.push(value); material.text += 12n * decoded;
        // Preserve the funded key-parser/native byte overlap after handing
        // the same PEM text to the existing crypto constructor.
        material.wire += 8n * decoded;
        reconcileSource(original, material);
        return value;
      } catch (cause) {retainSourceFailure(material, cause); throw cause;}
      finally {material.ioPending--;}
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
export function beginInstalledSourceInitialization(services, installation, connectorId, baseEnvironmentWire) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = sourceMaterial(original);
  if (material === undefined) return undefined;
  if (material.phase !== 'working') fail('InstalledSourceInitializationClosed');
  if (original.selected.get(installation) === undefined || typeof connectorId !== 'string' ||
      typeof baseEnvironmentWire !== 'string') fail('ForeignInstalledSourceInitialization');
  const scope = {installation, connectorId, baseEnvironmentWire, prepared: undefined,
    source: undefined, active: true};
  material.contexts.push(scope); material.constructors++;
  const context = Object.freeze({prepareDeclaration(views, expectedCatalogCid) {
    if (this !== context || !scope.active || scope.prepared !== undefined) {
      fail('ForeignInstalledSourceInitialization');
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
    reserveSource(original, material, 4n * basis, 8n * basis, 8n * basis);
    Object.freeze(snapshot);
    const wire = JSON.stringify({views: snapshot});
    const declaration = checked(Reflect.apply(original.restoreDeclaration, original.moon,
      [scope.connectorId, scope.installation.registration, scope.installation.revision, wire, expectedCatalogCid]));
    const declaredWire = Reflect.apply(original.declarationJson, original.moon, [declaration]);
    if (typeof declaredWire !== 'string') fail('InvalidInstalledSourceDeclaration');
    const declared = freezeSourceProjection(JSON.parse(declaredWire));
    const environment = rowSourceCheckEnvironment(scope.baseEnvironmentWire, declared);
    const prepared = Object.freeze({declaration, declared, environment});
    scope.prepared = prepared;
    material.inputs.push(snapshot, wire, declaration, declaredWire, declared, environment);
    material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
    reconcileSource(original, material);
    return prepared;
  }});
  sourceContexts.set(context, {original, material, scope});
  return context;
}

export function assertInstalledSourceConstruction(context, declaration, declared, environment) {
  const retained = sourceContexts.get(context), prepared = retained?.scope.prepared;
  if (retained === undefined || prepared === undefined || !retained.scope.active || retained.material.phase !== 'working' ||
      prepared?.declaration !== declaration || prepared.declared !== declared || prepared.environment !== environment) {
    fail('ForeignInstalledSourceConstruction');
  }
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
  const material = original.material;
  if (material === undefined) return;
  // Runtime identity streams immutable software through this existing single
  // chunk, not a full runtime Buffer. Selected code remains Host baseline.
  reserveSource(original, material, 0n, 0n, BigInt(installedConfigurationChunkBytes));
}

export function completeInstalledSourceInitialization(services, sourceOriginal, environment, environmentWire) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  const material = original.material;
  if (material === undefined) return;
  if (sourceOriginal !== material.input) fail('ForeignInstalledSourceMaterial');
  if (material.ioPending !== 0 || material.constructors !== 0 || environment === undefined ||
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
  material.phase = 'retiring';
  if (material.capacity === undefined && material.unit === undefined) return false;
  const completed = sourceCall(original, material, material.capacity === undefined
    ? 'AbortUncontinuedSourceMaterial' : 'RetireInstalledSourceMaterial',
  [material.capacity ?? material.unit, material.input]);
  if (completed === true) {
    for (const scope of material.contexts) {
      scope.prepared = scope.source = scope.installation = scope.baseEnvironmentWire = undefined;
    }
    material.inputs.length = material.contexts.length = material.cleanup.length = 0;
    material.configurationReader = material.sourceOriginal = material.environment = material.environmentWire = undefined;
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
      if (Reflect.ownKeys(fields).length !== (Object.hasOwn(fields, 'sourceInitialization') ? 4 : 3) || ['installation', 'limits', 'columnCount'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      if (nodeTypes.isProxy(fields.limits.value ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const columns = fields.columnCount.value;
      const profile = sourceProfiles.get(selection);
      let supplied = Object.getOwnPropertyDescriptors(fields.limits.value ?? {}), calendarLimits;
      // This JSON implementation has no request-body construction inventory.
      // Do not discard a selected bound or treat it as actual backing.
      if (Object.hasOwn(supplied, 'maxRequestBytes')) fail('InstalledSourceReaderRequestCapacityUnavailable');
      if (Object.getOwnPropertyDescriptor(installation, 'registration')?.value === 'calendar' &&
          !Object.hasOwn(supplied, 'maxTotalResponseBytes')) {
        const projected = calendarImplementationReaderLimits(supplied, profile);
        calendarLimits = projected.original;
        supplied = Object.getOwnPropertyDescriptors(projected.limits);
      }
      const names = [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'];
      if (names.some(name => !Object.hasOwn(supplied[name] ?? {}, 'value') ||
          !Number.isSafeInteger(supplied[name].value) || supplied[name].value < 1 || supplied[name].value > 2147483647)) {
        fail('InvalidInstalledSourceReaderLimits');
      }
      if (profile !== undefined && (profile.runtimeBundleCid !== runtimeBundleCid ||
          columns > profile.value.maxColumns || names.some(name => supplied[name].value > profile.value[name]))) {
        fail('InstalledSourceReaderImplementationBoundsExceeded');
      }
      if ([sourcePolicy, sourceCapacity].some(port => typeof port !== 'function')) fail('InstalledSourceReaderRuntimeUnavailable');
      const policy = Reflect.apply(sourcePolicy, moon, []);
      if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > policy[2] ||
        supplied.maxSecretBytes.value > policy[0]) fail('InstalledSourceReaderPolicyUnavailable');
      const limits = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
      const previous = sourceImplementations.get(selection);
      if (previous !== undefined) {
        if (previous.runtimeBundleCid !== runtimeBundleCid || previous.columns !== columns ||
            (previous.calendarLimits === undefined) !== (calendarLimits === undefined) ||
            calendarLimits !== undefined && Object.keys(calendarLimits).some(function calendarSelectionChanged(name) {
              return previous.calendarLimits[name] !== calendarLimits[name];
            }) ||
            names.some(name => previous.value.limits[name] !== limits[name])) fail('InstalledSourceReaderSelectionChanged');
        return previous.value;
      }
      const capacity = Reflect.apply(sourceCapacity, moon,
        [installedJsonSourceReaderLimitNames.map(name => limits[name]), columns, limits.maxSecretBytes]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      const value = Object.freeze({capacity, limits, runAcquisitionLimits: Object.freeze({
        maxBindings: policy[1], maxSecretBytes: limits.maxSecretBytes})});
      current(); sourceImplementations.set(selection, Object.freeze({runtimeBundleCid, columns, calendarLimits, value}));
      return value;
    },
    createSourceReader(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      const standard = Object.hasOwn(fields, 'preparePageReader');
      const readerField = standard ? 'preparePageReader'
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
      const originalSite = installedRowCredentialOperationSite(fields.site.value.credential);
      return createInstalledCredentialSourceReader({capacity: implementation.value.capacity,
        originalSite, [readerField]: fields[readerField].value, assertCurrent: current,
        maxResponses: implementation.value.limits.maxPages,
        ...(standard ? {operation: fields.operation.value,
          maxResponseBytes: implementation.value.limits.maxResponseBytes,
          maxSecretBytes: implementation.value.limits.maxSecretBytes} : {})});
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
      // The caller supplies provider configuration only. It cannot replace the
      // original Host/runtime/current association with equal or copied DATA.
      const implementation = implementations.get(installation);
      if (implementation?.constructing) fail('InstalledEffectDefinitionSelectionReentry');
      if (implementation !== undefined) implementation.sealed = true;
      return openInstalledRowSite({...options, root, principalId, commonMoon: moon,
        runtimeBundleCid, assertCurrent: current,
        configurationReader: installedSourceConfigurationReader(services)}).then(original => {
          sites.set(original.site, implementation);
          siteInstallations.set(original.site, selection);
        return original;
      });
    },
  });
  const restoreDeclaration = moon.clientProgramRowSourceRestoreRelationDeclaration;
  const declarationJson = moon.clientProgramRowSourceDeclarationJson;
  installations.set(services, {selected, current, sites, siteInstallations, implementations,
    sourceImplementations, sourceProfiles, moon, initialPreparation, restoreDeclaration, declarationJson});
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
