import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {installedEnvironmentDataWriterConstructionGeometry,
  installedEnvironmentMemberSortConstructionGeometry} from './installed-check-environment-construction.mjs';
import {authoredCommandProjection} from './installed-authored-command.mjs';
import {sourceEnvironmentConstructionGeometry, sourceDeclarationRetainedGeometry,
  sourceAuthoredViewConstructionGeometry, sourceJsonWireGeometry}
  from './installed-source-construction-geometry.mjs';
import type {composeInstalledSourceEnvironment as composeEnvironment} from './installed-funded-environment.mjs';
import type {createInstalledSourceMaterialAccounting} from './installed-source-material-accounting.mjs';
import type {RowSourceDeleteMappingMethod, RowSourceMappingMethod, rowSourceMapping} from './installed-row-source-mapping.mjs';
import type {rowSourceCheckEnvironment} from './installed-row-source-environment.mjs';

type Accounting = ReturnType<typeof createInstalledSourceMaterialAccounting>;
type Material = NonNullable<ReturnType<Accounting['sourceMaterial']>>;
type EnvironmentArgs = Parameters<NonNullable<Material['retainEnvironmentNativeOriginal']>>;
type NativeEnvironment = EnvironmentArgs[1];
type Declared = Parameters<typeof sourceEnvironmentConstructionGeometry>[1] & Readonly<{catalog_cid?: unknown}>;
type ContextEnvironment = NativeEnvironment | ReturnType<typeof composeEnvironment>;
type NativeValue = Extract<SynchronousRuntimeData, object>;
type Geometry = ReturnType<typeof sourceEnvironmentConstructionGeometry>['parsed'];
type CoreMethod = (...args: unknown[]) => unknown;
type Role = 'source' | 'effect';
type MappingCarrier = Readonly<{resource: string; mappingRef: string; mappingCid: string; body: string}>;
type MappingOutput = ReturnType<typeof rowSourceMapping>;
type ProviderOriginal = Readonly<{
  declared: Readonly<{declaration: unknown; catalog: string; manifest_entry: string;
    contracts: readonly string[]; source_views: readonly string[]}>;
  schemas: readonly string[]; capabilities: readonly string[];
}>;
type Original = Parameters<Accounting['sourceMaterial']>[0] &
  Readonly<{moon: EnvironmentArgs[0] & Parameters<typeof composeEnvironment>[1]; declarationJson: CoreMethod;
    restoreDeclaration?: unknown; restoreAuthoredDeclaration?: unknown;
    prepareMapping?: RowSourceMappingMethod; prepareUpdateMapping?: RowSourceMappingMethod;
    prepareDeleteMapping?: RowSourceDeleteMappingMethod;
    prepareUpdateMappingCapacity?: CoreMethod;
    current(): void}>;
type Prepared = Readonly<{
  declaration?: unknown; declared?: Declared; environment?: ContextEnvironment; environmentMappings?: readonly string[];
  commands?: readonly unknown[]; commandDefinition?: unknown; mappings?: readonly MappingCarrier[];
}>;
type CommandContext = Readonly<{
  prepareDeclaration(views: unknown, expectedCatalogCid?: unknown): Prepared;
  prepareDeclaredCommands(viewsWire: unknown, projection: object, expectedCatalogCid?: unknown): Prepared;
}>;
type Scope = {
  active: boolean; role: Role; installation: Readonly<{registration?: string; revision?: string}>;
  connectorId?: string; baseEnvironmentWire: string; prepared?: Prepared; source?: unknown;
  declarationBasis?: bigint; providerAttempted?: boolean; nativeInputAttempted?: boolean;
  derivedAttempted?: boolean; commandAttempted?: boolean; commandDeclarationWire?: string;
  declarationAttempted?: boolean; mappingsAttempted?: boolean; readMetadataAttempted?: boolean;
  publishedEnvironment?: boolean; borrowedDeclaration?: Scope; closed?: boolean;
};
type ContextPorts = Pick<Accounting, 'installedSourceConfigurationReader' | 'reserveSource' | 'reconcileSource' |
  'freezeSourceProjection' | 'sourceProjectionMethods' | 'requireSynchronousSourceConstruction'> & Readonly<{
  fail(code: string): never;
  original: Original;
  material: Material;
  services: object;
  scope: Scope;
  currentContext(): CommandContext;
  rowSourceCheckEnvironment: typeof rowSourceCheckEnvironment;
}>;

export function createInstalledSourceContextConstruction({fail: reject, original, material, services, scope,
  currentContext, installedSourceConfigurationReader, reserveSource, reconcileSource, freezeSourceProjection,
  sourceProjectionMethods, requireSynchronousSourceConstruction, rowSourceCheckEnvironment}: ContextPorts) {
  const fail: (code: string) => never = reject;

  function prepareSourceEnvironment(declared: Declared, mappings: readonly string[] = []) {
    const reader = installedSourceConfigurationReader(services)!;
    const geometry = sourceEnvironmentConstructionGeometry(scope.baseEnvironmentWire, declared, mappings);
    const before = scope.prepared;
    const construct = <Value extends NativeValue,>(quantity: Geometry, project: () => Value): Value => {
      if (!scope.active || material.phase !== 'working' || scope.prepared !== before) {
        fail('ForeignInstalledSourceInitialization');
      }
      return reader.prepareNativeInput(Object.freeze({capacity: () => {
        const {retained: r, workspace: w} = quantity;
        return checked(original.moon.clientProgramInstalledSourceConstructionCapacity(
          r.nodes, r.text, r.wire, w.nodes, w.text, w.wire));
      }, project}));
    };
    // Every phase has actually returned before the next quote. The SAME
    // native-input Owner keeps each returned original and full failure debt;
    // no busy constructor is discounted or replaced by a synthetic ACK.
    return rowSourceCheckEnvironment(scope.baseEnvironmentWire, declared, mappings,
      (value, document, body) => {
        material.retainEnvironmentNativeOriginal!(original.moon, value, document, body);
      }, {
        freeze: freezeSourceProjection,
        parse: project => construct(geometry.parsed, project),
        sort: (values, project) => construct(installedEnvironmentMemberSortConstructionGeometry(values), project),
        seal: body => construct({retained: {nodes: 2n, text: 0n, wire: 0n},
          workspace: {nodes: geometry.parsed.retained.nodes, text: 0n, wire: 0n}},
        () => freezeSourceProjection(body)),
        hash: (body, project) => construct(installedEnvironmentDataWriterConstructionGeometry(body, true),
          () => Object.freeze({cid: project()})).cid,
        encode: (document, project) => construct(installedEnvironmentDataWriterConstructionGeometry(document), project),
      });
  }
  function prepareOriginalDeclaration(restore: unknown, originalInput: unknown, basis: bigint, makeWire: () => string,
    expectedCatalogCid?: unknown, finish?: (declaration: unknown, wire: string) => Prepared) {
    if (typeof restore !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
    reserveSource(original, material, 4n * basis, 8n * basis, 8n * basis);
    if (!scope.active || material.phase !== 'working' || scope.prepared !== undefined) {
      fail('ForeignInstalledSourceInitialization');
    }
    let wire: string, declaration: unknown, declaredWire: unknown, declared: Declared | undefined;
    material.busy = true;
    try {
      wire = makeWire();
      declaration = checked(Reflect.apply(restore, original.moon,
        [scope.connectorId, scope.installation.registration, scope.installation.revision, wire, expectedCatalogCid]));
      declaredWire = Reflect.apply(original.declarationJson, original.moon, [declaration]);
      if (typeof declaredWire !== 'string') fail('InvalidInstalledSourceDeclaration');
      declared = finish === undefined ? freezeSourceProjection(JSON.parse(declaredWire) as Declared) : undefined;
      // Retain the original base before a selected native projection, its
      // extra reservation or Environment can fail. There is no second restore.
      material.inputs.push(originalInput, wire, declaration, declaredWire, declared);
      material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
      scope.declarationBasis = basis;
    } finally {material.busy = false;}
    const retainReturnedDeclaration = (expectedPrepared: Prepared | undefined) => {
      const retained = sourceDeclarationRetainedGeometry(wire, declaredWire as string);
      // The old complete allowance remains held while observing the same
      // original parent. Only a successful closed restore/export/parse may
      // replace its temporary workspace with the actual coheld outputs.
      reserveSource(original, material);
      if (!scope.active || material.phase !== 'working' || scope.prepared !== expectedPrepared) {
        fail('ForeignInstalledSourceInitialization');
      }
      const prior = {nodes:material.nodes, text:material.text, wire:material.wire};
      material.nodes += retained.nodes - 4n * basis;
      material.text += retained.text - 8n * basis;
      material.wire -= 8n * basis;
      try {reconcileSource(original, material);}
      catch (cause) {Object.assign(material, prior);throw cause;}
    };
    let prepared;
    if (finish !== undefined) {
      prepared = finish(declaration, declaredWire as string);
      // A preliminary declaration does not publish a prepared slot; a final
      // Command does. In either case retain the exact original across the
      // current callback, never another scope's or a reentrant replacement.
      const expectedPrepared = scope.prepared;
      if (expectedPrepared !== undefined && expectedPrepared !== prepared) fail('ForeignInstalledSourceInitialization');
      retainReturnedDeclaration(expectedPrepared);
    } else {
      retainReturnedDeclaration(undefined);
      // Use the SAME funded Environment constructor for authored and native
      // declarations. Its exact frozen original, census and failed prefix
      // stay with this Source material before any later semantic admission.
      const environment = scope.role === 'effect' ? undefined
        : prepareSourceEnvironment(declared!);
      material.busy = true;
      try {
        // A Mapping or projected Command finishes its ONE Environment later.
        prepared = Object.freeze({declaration, declared, environment});
        scope.prepared = prepared; material.inputs.push(environment);
      } finally {material.busy = false;}
    }
    reconcileSource(original, material);
    return prepared;
  }
  function captureDeclarationViews(views: unknown) {
    if (!Array.isArray(views) || nodeTypes.isProxy(views)) fail('InvalidInstalledSourceDeclarationViews');
  // View specifications contain only provider-authored strings. Measure and
  // reserve before snapshot/stringify; no getter/receiver is invoked here.
  let units = BigInt(scope.connectorId!.length + scope.baseEnvironmentWire.length);
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
    const selected: Record<string, string> = {};
    for (const name of Reflect.ownKeys(fields)) {
      if (!allowed.includes(name as string) || !Object.hasOwn(fields[name as string], 'value')) fail('InvalidInstalledSourceDeclarationViews');
      // Preserve the existing JSON.stringify omission rule. Common alone
      // decides required fields and optional classification/identity law.
      if (fields[name as string].value === undefined) continue;
      if (typeof fields[name as string].value !== 'string') fail('InvalidInstalledSourceDeclarationViews');
      units += BigInt((name as string).length + fields[name as string].value.length);
      selected[name as string] = fields[name as string].value;
    }
    snapshot.push(Object.freeze(selected));
  }
  // Restore owns parsed schema/request/facts, checked contract projections,
  // canonical identity preimages, Catalog+manifest and declaration JSON;
  // rowSourceCheckEnvironment then overlaps native inputs and output. This
  // conservative input-proportional allowance covers the whole operation,
  // including its failed child, using existing shared units (not VM prices).
  const basis = 6n * units + 64n * BigInt(views.length);
    return {snapshot: Object.freeze(snapshot), basis};
  }
  function prepareProviderConstruction(this: unknown, projection: object, role: Role, withMappings = false) {
    if (this !== currentContext() || scope.role !== role || !scope.active || scope.prepared === undefined ||
        scope.source !== undefined || scope.providerAttempted || material.phase !== 'working') {
      fail('ForeignInstalledSourceInitialization');
    }
    if (material.busy) fail('InstalledSourceInitializationReentry');
    const {capacity: capacityFor, project} = sourceProjectionMethods(projection);
    if (typeof material.methods!.ComposeInstalledSourceConstructionCapacity !== 'function' ||
        withMappings && typeof material.methods!.InstalledSourceRetainedConstructionCapacity !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    const prepared = scope.prepared;
    scope.providerAttempted = true;
    let quantity;
    material.busy = true;
    try {quantity = requireSynchronousSourceConstruction(material, Reflect.apply(capacityFor, projection, []));}
    finally {material.busy = false;}
    if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceCommandConstructionUnavailable');
    // A Source-issued reference outlives any one Run's Reader. Its complete
    // original constructor peak therefore belongs to this SAME initializer,
    // not a borrowed Reader reservation or an inferred spare allowance.
    const providerIndex = material.providers.length;
    material.providers.push(quantity); material.inputs.push(projection);
    reserveSource(original, material);
    if (!scope.active || material.phase !== 'working' || scope.prepared !== prepared || scope.source !== undefined) {
      fail('ForeignInstalledSourceInitialization');
    }
    let target;
    material.busy = true;
    try {
      target = requireSynchronousSourceConstruction(material, Reflect.apply(project, projection, []));
      if (!target || typeof target !== 'object' || nodeTypes.isProxy(target)) fail('InvalidInstalledSourceReadTarget');
      material.inputs.push(target);
      freezeSourceProjection(target);
    } finally {material.busy = false;}
    if (withMappings) {
      const fields = Object.getOwnPropertyDescriptors(target);
      const mappings = fields.mappingWires;
      if (!mappings || !Object.hasOwn(mappings, 'value') || !Array.isArray(mappings.value) ||
          nodeTypes.isProxy(mappings.value) || !Object.isFrozen(mappings.value)) fail('InvalidInstalledSourceNativeMappings');
      const wires = mappings.value;
      for (let i = 0; i < wires.length; i++) {
        const field = Object.getOwnPropertyDescriptor(wires, String(i));
        if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') fail('InvalidInstalledSourceNativeMappings');
      }
      // The selected pure producer has synchronously returned its SAME target
      // and complete frozen mapping strings. Its typed retained projection
      // owns every escaped original; no callback/physical cleanup ACK is inferred.
      // Throwing, asynchronous and invalid outputs above keep the full peak.
      material.busy = true;
      try {
        const retained = checked(Reflect.apply(material.methods!.InstalledSourceRetainedConstructionCapacity as CoreMethod,
          original.moon, [quantity]));
        if (!retained || typeof retained !== 'object' || nodeTypes.isProxy(retained) ||
            material.providers[providerIndex] !== quantity) fail('InstalledSourceCommandConstructionUnavailable');
        material.inputs.push(quantity, retained, wires);
        material.providers[providerIndex] = retained;
      } finally {material.busy = false;}
      // The same admitted declared body is reused, never restored/replaced.
      const environment = prepareSourceEnvironment(prepared.declared!, wires);
      if (!scope.active || material.phase !== 'working' || scope.prepared !== prepared || scope.source !== undefined) {
        fail('ForeignInstalledSourceInitialization');
      }
      material.busy = true;
      try {
        scope.prepared = Object.freeze({...prepared, environment, environmentMappings: wires});
        material.inputs.push(wires, environment);
      } finally {material.busy = false;}
    }
    reconcileSource(original, material);
    return target;
  }
  function prepareInitialNativeConstruction(projection: object, attempt: 'nativeInputAttempted') {
    if (!scope.active || scope.prepared !== undefined || scope.source !== undefined ||
        scope[attempt] || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
    if (material.busy) fail('InstalledSourceInitializationReentry');
    const methods = sourceProjectionMethods(projection);
    if (typeof material.methods!.ComposeInstalledSourceConstructionCapacity !== 'function') {
      fail('InstalledSourceInitializationRuntimeUnavailable');
    }
    scope[attempt] = true;
    let quantity;
    material.busy = true;
    try {quantity = requireSynchronousSourceConstruction(material,
      Reflect.apply(methods.capacity, projection, []));}
    finally {material.busy = false;}
    if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) {
      fail('InstalledSourceCommandConstructionUnavailable');
    }
    // The selected original recipe includes every returned native value and
    // failed constructor prefix. It stays on this initial parent through
    // Source retirement; this entrance does not issue another capacity.
    material.providers.push(quantity);material.inputs.push(projection);
    reserveSource(original, material);
    if (!scope.active || scope.prepared !== undefined || scope.source !== undefined ||
        material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
    return methods.project;
  }

  const declarations = {
    prepareDerivedDeclaredCommands(this: object, initialViews: unknown, derivation: object, projection?: object, expectedCatalogCid?: unknown): Prepared {
      if (this !== currentContext() || !scope.active || scope.prepared !== undefined || scope.derivedAttempted ||
          scope.commandAttempted || material.phase !== 'working' || material.busy) fail('InvalidInstalledSourceDerivedDeclaration');
      const {capacity: derivationCapacity, project: deriveFinalViews} = sourceProjectionMethods(derivation);
      if (projection !== undefined) sourceProjectionMethods(projection);
      scope.derivedAttempted = true;
      const {snapshot, basis} = captureDeclarationViews(initialViews);
      // This existing first restore supplies carrier schema CIDs for final
      // facts. It never fills the publishable prepared slot.
      const preliminary = prepareOriginalDeclaration(original.restoreDeclaration, snapshot, basis,
        () => JSON.stringify({views: snapshot}), undefined, (declaration, wire) => {
          const declared = freezeSourceProjection(JSON.parse(wire));
          const value = Object.freeze({declaration, declared, wire});
          material.inputs.push(value);
          return value;
        });
      // Domain-specific pure facts construction owns its typed recipe. Both
      // calls receive the SAME privately retained preliminary declaration;
      // no arbitrary callback is priced from its input wire length.
      let quantity;
      material.busy = true;
      try {quantity = requireSynchronousSourceConstruction(material,
        Reflect.apply(derivationCapacity, derivation, [preliminary.declared]));}
      finally {material.busy = false;}
      if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) {
        fail('InstalledSourceDerivedDeclarationCapacityUnavailable');
      }
      material.providers.push(quantity); material.inputs.push(derivation);
      reserveSource(original, material);
      if (!scope.active || scope.prepared !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
      let views;
      material.busy = true;
      try {
        views = requireSynchronousSourceConstruction(material,
          Reflect.apply(deriveFinalViews, derivation, [preliminary.declared]));
        material.inputs.push(views);
      } finally {material.busy = false;}
      // The callback's original quantity retains its output. Common prices
      // only its subsequent authored-view snapshot and shallow stringify,
      // before either allocation, using those actual immutable String fields.
      const geometry = sourceAuthoredViewConstructionGeometry(views);
      reserveSource(original, material, geometry.nodes, geometry.text, geometry.wire);
      if (!scope.active || scope.prepared !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
      let finalWire;
      material.busy = true;
      try {
        const final = captureDeclarationViews(views);
        material.inputs.push(final.snapshot);
        finalWire = JSON.stringify({views: final.snapshot});
        material.inputs.push(finalWire);
        material.nodes += geometry.nodes;
        material.text += geometry.text; material.wire += geometry.wire;
      } finally {material.busy = false;}
      // Same final RowDeclaration and native command producer entrance as
      // ordinary Command installations; no caller-supplied replacement wire.
      return projection === undefined ? currentContext().prepareDeclaration(finalWire, expectedCatalogCid)
        : currentContext().prepareDeclaredCommands(finalWire, projection, expectedCatalogCid);
    },
    prepareAuthoredCommands(this: object, viewsWire: unknown, specification: unknown, expectedCatalogCid?: unknown): Prepared {
      if (this !== currentContext()) fail('ForeignInstalledSourceInitialization');
      return currentContext().prepareDeclaredCommands(viewsWire,
        authoredCommandProjection(original.moon, specification), expectedCatalogCid);
    },
    prepareDeclaredCommands(this: object, viewsWire: unknown, projection: object, expectedCatalogCid?: unknown): Prepared {
      if (this !== currentContext() || !scope.active || scope.prepared !== undefined || scope.commandAttempted || material.phase !== 'working') {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof viewsWire !== 'string' || expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
        fail('InvalidInstalledSourceCommandProjection');
      }
      const {capacity: capacityFor, project} = sourceProjectionMethods(projection);
      if (typeof material.methods!.ComposeInstalledSourceConstructionCapacity !== 'function' ||
          typeof material.methods!.InstalledSourceRetainedConstructionCapacity !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
      scope.commandAttempted = true;
      const units = BigInt(scope.connectorId!.length) + BigInt(scope.baseEnvironmentWire.length) + BigInt(viewsWire.length);
      // The expected identity belongs to the FINAL Catalog, not its original
      // Source-only base. Preserve the native builders' existing identity law.
      return prepareOriginalDeclaration(original.restoreDeclaration, viewsWire, 6n * units + 64n,
        () => viewsWire, undefined, (declaration, declaredWire) => {
          let quantity;
          material.busy = true;
          try {quantity = requireSynchronousSourceConstruction(material, Reflect.apply(capacityFor, projection, [declaredWire]));}
          finally {material.busy = false;}
          if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceCommandConstructionUnavailable');
          // Retain the selected native peak before the original current/resize
          // call. Failed projections keep that same Source constructor debt.
          const providerIndex = material.providers.length;
          material.providers.push(quantity);material.inputs.push(projection);
          reserveSource(original, material);
          if (!scope.active || material.phase !== 'working' || scope.prepared !== undefined) fail('ForeignInstalledSourceInitialization');
          let projected: unknown, declared: Declared, commands: readonly unknown[], definition: unknown, outputWire: string;
          material.busy = true;
          try {
            projected = requireSynchronousSourceConstruction(material, Reflect.apply(project, projection, [declaredWire]));
            if (!projected || nodeTypes.isProxy(projected)) fail('InvalidInstalledSourceCommandProjection');
            const out = Object.getOwnPropertyDescriptors(projected as object);
            if (['declared','commands','wire'].some(name => !Object.hasOwn(out[name] ?? {}, 'value')) ||
                (out.definition !== undefined || scope.role === 'effect') &&
                  !Object.hasOwn(out.definition ?? {}, 'value')) fail('InvalidInstalledSourceCommandProjection');
            declared = freezeSourceProjection(out.declared.value);
            commands = freezeSourceProjection(out.commands.value);
            definition = out.definition === undefined ? undefined : freezeSourceProjection(out.definition.value);
            outputWire = out.wire.value;
            if (typeof outputWire !== 'string') fail('InvalidInstalledSourceCommandProjection');
            if (!Array.isArray(commands) || commands.length === 0 ||
                typeof declared?.catalog_cid !== 'string' || expectedCatalogCid !== undefined && expectedCatalogCid !== declared.catalog_cid) {
              fail('InstalledSourceCommandCatalogMismatch');
            }
            material.inputs.push(projected, declared, commands, definition, outputWire);
            // The closed native declaration exported only these canonical
            // wires/plain frozen outputs. Its original local parser/identity/
            // writer work cannot escape this successful synchronous result.
            // Keep the owner's retained output quantity before a later phase;
            // any throw/invalid async/invalid output above keeps the full peak.
            const retained = checked(Reflect.apply(material.methods!.InstalledSourceRetainedConstructionCapacity as CoreMethod,
              original.moon, [quantity]));
            if (!retained || typeof retained !== 'object' || nodeTypes.isProxy(retained) ||
                material.providers[providerIndex] !== quantity) fail('InstalledSourceCommandConstructionUnavailable');
            material.inputs.push(quantity, retained);
            material.providers[providerIndex] = retained;
          } finally {material.busy = false;}
          // A successfully installed original Source may already retain the
          // SAME immutable Environment inputs on this same initial parent.
          // Match the original entry and complete wires, never a CID/name or
          // copied holder. Both completed native output quantities stay
          // independently retained; only duplicate Environment assembly is omitted.
          const sourceScope = scope.role !== 'effect' ? undefined : material.contexts.find(other =>
            other.role === 'source' && other.finishedSuccessfully === true && other.source !== undefined &&
            other.closed !== true && other.installation === scope.installation &&
            other.connectorId === scope.connectorId && other.baseEnvironmentWire === scope.baseEnvironmentWire &&
            other.commandDeclarationWire === outputWire && (other.prepared as Prepared | undefined)?.environment !== undefined);
          if (sourceScope !== undefined) {
            const sourcePrepared = sourceScope.prepared as Prepared, sourceOriginal = sourceScope.source;
            // Preserve the original before-use current fence even when no new
            // workspace is needed. A reentrant close cannot reuse or rebuild
            // the retired input after this selected handoff.
            reserveSource(original, material);
            if (!scope.active || material.phase !== 'working' || scope.prepared !== undefined ||
                sourceScope.finishedSuccessfully !== true || sourceScope.closed === true ||
                sourceScope.source !== sourceOriginal || sourceScope.prepared !== sourcePrepared ||
                sourceScope.installation !== scope.installation ||
                sourceScope.commandDeclarationWire !== outputWire ||
                sourceScope.baseEnvironmentWire !== scope.baseEnvironmentWire) {
              fail('ForeignInstalledSourceInitialization');
            }
            const prepared = Object.freeze({declaration, declared, environment: sourcePrepared.environment,
              commands, commandDefinition: definition});
            scope.prepared = prepared;scope.commandDeclarationWire = outputWire;
            material.inputs.push(outputWire, prepared, sourceOriginal);
            return prepared;
          }
          // JSON output is already backed by the original native quantity.
          // Different inputs still fund their own complete Environment before
          // parsing/merging. An equal CID alone cannot select the reuse path.
          const sourcePhase = scope.role === 'source';
          const geometry = sourcePhase ? undefined : sourceEnvironmentConstructionGeometry(scope.baseEnvironmentWire, declared);
          let environment;
          if (sourcePhase) environment = prepareSourceEnvironment(declared);
          else reserveSource(original, material, geometry!.nodes, geometry!.text, geometry!.wire);
          if (!scope.active || material.phase !== 'working' || scope.prepared !== undefined) fail('ForeignInstalledSourceInitialization');
          let prepared;
          material.busy = true;
          try {
            if (!sourcePhase) environment = rowSourceCheckEnvironment(scope.baseEnvironmentWire, declared);
            prepared = Object.freeze({declaration, declared, environment, commands, commandDefinition: definition});
            scope.prepared = prepared;scope.commandDeclarationWire = outputWire;
            material.inputs.push(outputWire, environment);
            // Effects still need the full backing for their next constructor's
            // existing Environment parse. Only Source pure phases use the split.
            if (!sourcePhase) {
              material.nodes += geometry!.nodes;material.text += geometry!.text;material.wire += geometry!.wire;
            }
          } finally {material.busy = false;}
          return prepared;
        });
    },
    prepareAuthoredDeclaration(this: object, viewsWire: unknown, expectedCatalogCid?: unknown): Prepared {
      if (this !== currentContext() || !scope.active || scope.prepared !== undefined || scope.commandAttempted) {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof viewsWire !== 'string' || expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
        fail('InvalidInstalledSourceDeclarationViews');
      }
      // The original authored-fields wire is immutable input. Do not parse,
      // convert types or stringify another schema before its parent reserves.
      const units = BigInt(scope.connectorId!.length) + BigInt(scope.baseEnvironmentWire.length) + BigInt(viewsWire.length);
      return prepareOriginalDeclaration(original.restoreAuthoredDeclaration, viewsWire,
        6n * units + 64n, () => viewsWire, expectedCatalogCid);
    },
    prepareDeclaration(this: object, views: unknown, expectedCatalogCid?: unknown): Prepared {
      if (this !== currentContext() || !scope.active || scope.prepared !== undefined || scope.commandAttempted) {
        fail('ForeignInstalledSourceInitialization');
      }
      if (material.busy) fail('InstalledSourceInitializationReentry');
      if (typeof views === 'string') {
        if (expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
          fail('InvalidInstalledSourceDeclarationViews');
        }
        // Already published schema/facts wires keep their exact original
        // Common entrance. Reserve before parsing or constructing a view list.
        const units = BigInt(scope.connectorId!.length) + BigInt(scope.baseEnvironmentWire.length) + BigInt(views.length);
        return prepareOriginalDeclaration(original.restoreDeclaration, views,
          6n * units + 64n, () => views, expectedCatalogCid);
      }
      if (!Array.isArray(views) || nodeTypes.isProxy(views) ||
          expectedCatalogCid !== undefined && typeof expectedCatalogCid !== 'string') {
        fail('InvalidInstalledSourceDeclarationViews');
      }
      const {snapshot, basis} = captureDeclarationViews(views);
      return prepareOriginalDeclaration(original.restoreDeclaration, Object.freeze(snapshot), basis,
        () => JSON.stringify({views: snapshot}), expectedCatalogCid);
    },
  };

  return {prepareSourceEnvironment, prepareOriginalDeclaration, captureDeclarationViews,
    prepareProviderConstruction, prepareInitialNativeConstruction, ...declarations};
}

type RetainedContext = Readonly<{original: Original; material: Material; scope: Scope}>;
type SourceContextPorts = Omit<ContextPorts, 'original' | 'material' | 'services' | 'scope' | 'currentContext'> &
  Pick<Accounting, 'prepareSourceNativeInput' | 'retainCompletedSourceNativeConstruction'> & Readonly<{
    sourceContexts: Pick<WeakMap<object, RetainedContext>, 'get' | 'set'>;
    composeInstalledSourceEnvironment: typeof composeEnvironment;
    rowSourceMapping: typeof rowSourceMapping;
  }>;

export function createInstalledSourceContextFactory({fail: reject, sourceContexts, composeInstalledSourceEnvironment,
  installedSourceConfigurationReader, reserveSource, reconcileSource, freezeSourceProjection, sourceProjectionMethods,
  requireSynchronousSourceConstruction, prepareSourceNativeInput, retainCompletedSourceNativeConstruction,
  rowSourceCheckEnvironment, rowSourceMapping}: SourceContextPorts) {
  const fail: (code: string) => never = reject;
  function createInstalledSourceContext(original: Original, material: Material, installation: Scope['installation'],
    connectorId: string | undefined, baseEnvironmentWire: string, role: Role, services: object) {
    const scope: Scope = {installation, connectorId, baseEnvironmentWire, role, prepared: undefined,
      source: undefined, active: true};
    material.contexts.push(scope); material.constructors++;
    const inputProjections = new WeakSet<object>();
    const nativeInputOriginals = new WeakSet<object>();
    const validateNativeInputContext = (prepared: Prepared | undefined) => {
      if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
          material.phase !== 'working' || prepared !== undefined &&
          (scope.role !== 'effect' || prepared.declaration === undefined ||
            prepared.mappings !== undefined || prepared.commands !== undefined ||
            scope.mappingsAttempted || scope.commandAttempted || scope.providerAttempted)) {
        fail('ForeignInstalledSourceInitialization');
      }
    };
    const retainNativeInput = (value: object) => nativeInputOriginals.add(value);
    const {prepareSourceEnvironment, prepareOriginalDeclaration, captureDeclarationViews,
      prepareProviderConstruction, prepareInitialNativeConstruction, prepareDerivedDeclaredCommands,
      prepareAuthoredCommands, prepareDeclaredCommands, prepareAuthoredDeclaration, prepareDeclaration} =
      createInstalledSourceContextConstruction({fail, original, material, services, scope,
        currentContext: () => context, installedSourceConfigurationReader, reserveSource, reconcileSource, freezeSourceProjection,
        sourceProjectionMethods, requireSynchronousSourceConstruction, rowSourceCheckEnvironment});
    const context = Object.freeze({
      prepareInputConstruction(this: object, projection: object) {
        if (this !== context) fail('ForeignInstalledSourceInitialization');
        const project = prepareInitialNativeConstruction(projection, 'nativeInputAttempted');
        material.busy = true;
        try {
          const value = requireSynchronousSourceConstruction(material,
            Reflect.apply(project!, projection, []));
          material.inputs.push(value);
          if (!scope.active || scope.prepared !== undefined || material.phase !== 'working' ||
              value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) {
            fail('InvalidInstalledSourceNativeInput');
          }
          // A private original Buffer/opaque native value is retained as-is.
          // Walking or freezing its contents would allocate another input copy.
          return value;
        } finally {material.busy = false;}
      },
      prepareNativeInput(this: object, projection: object) {
        if (this !== context) fail('ForeignInstalledSourceInitialization');
        // Mapping constructors need the original declaration CID. Pin this
        // same tuple across every reservation and projection fence; Source and
        // already-started Mapping/Command/driver paths remain closed.
        const prepared = scope.prepared;
        return prepareSourceNativeInput(original, material, projection, inputProjections,
          () => validateNativeInputContext(prepared), retainNativeInput);
      },
      prepareReadMetadata(this: object, declared: unknown, project: unknown) {
        const prepared = scope.prepared;
        if (this !== context || scope.role !== 'source' || scope.readMetadataAttempted ||
            prepared?.declared !== declared || !Array.isArray((declared as {views?: unknown} | undefined)?.views) ||
            typeof project !== 'function') fail('ForeignInstalledSourceInitialization');
        scope.readMetadataAttempted = true;
        // Quote the complete original range once, before either variable-sized
        // metadata constructor. Strings and authority are borrowed originals.
        // Two retained containers hold N keys and N four-field records (7N+2
        // node slots), and the returned two-field metadata record takes three.
        // Their later synchronous binding check overlaps one Set
        // and one returned reference array (2N+2); keep that allowance with the
        // SAME Source material instead of issuing per-access reservations.
        const nodes = 9n * BigInt((declared as {views: readonly unknown[]}).views.length) + 7n;
        const quote = material.methods!.InstalledSourceConstructionCapacity;
        if (typeof quote !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
        const projection = Object.freeze({
          capacity() {
            // The existing native-input owner holds its synchronous busy fence.
            // This pure recipe observes no owner or permission; reservation and
            // current checks remain with prepareSourceNativeInput itself.
            return checked(Reflect.apply(quote, original.moon, [nodes, 0n, 0n, 0n, 0n, 0n]));
          },
          project,
        });
        return prepareSourceNativeInput(original, material, projection, inputProjections,
          () => {
            if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
                material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
            original.current();
          }, retainNativeInput);
      },
      prepareProviderEffect(this: object, site: object, provider: object, mappingOriginals: unknown) {
        if (this !== context || scope.role !== 'effect' || !scope.active || scope.prepared !== undefined ||
            scope.declarationAttempted || material.phase !== 'working' || material.busy ||
            !nativeInputOriginals.has(provider) || !Array.isArray(mappingOriginals) ||
            nodeTypes.isProxy(mappingOriginals) || !Object.isFrozen(mappingOriginals) ||
            !mappingOriginals.every(value => nativeInputOriginals.has(value))) {
          fail('ForeignInstalledSourceInitialization');
        }
        const {declared, schemas, capabilities} = provider as ProviderOriginal;
        const owns = Object.getOwnPropertyDescriptor(site, 'ownsDeclaration');
        if (!owns || !Object.hasOwn(owns, 'value') || typeof owns.value !== 'function' ||
            Reflect.apply(owns.value, site, [declared.declaration]) !== true) {
          fail('ForeignInstalledProviderDeclaration');
        }
        scope.declarationAttempted = true;
        const exported = Object.freeze({catalog: declared.catalog, manifest_entry: declared.manifest_entry,
          contracts: declared.contracts, view_bodies: declared.source_views,
          evidence_schemas: schemas, evidence_capabilities: capabilities});
        const mappingWires = mappingOriginals.map(value => value.body);
        // Complete the SAME pure Environment through the existing owner before
        // constructing the independent returned Mapping carriers. Its full peak
        // stays charged on failure; only its actual closed output survives here.
        const environment = prepareSourceEnvironment(exported, mappingWires);
        // Four String fields plus the record and array element for each retained Mapping.
        const mappingNodes = 1n + 6n * BigInt(mappingOriginals.length);
        reserveSource(original, material, mappingNodes);
        if (!scope.active || scope.prepared !== undefined || material.phase !== 'working') {
          fail('ForeignInstalledSourceInitialization');
        }
        let prepared;
        material.busy = true;
        try {
          const mappings = Object.freeze(mappingOriginals.map(value => Object.freeze({
            resource: value.write.resource, mappingRef: value.mappingRef,
            mappingCid: value.mappingCid, body: value.body})));
          // This opaque declaration belongs to the provider Site, not Common's
          // RowDeclaration type. Only its genuine exported DATA reaches Environment.
          prepared = Object.freeze({kind: 'providerEffect', declared: exported, environment, mappings});
          scope.prepared = prepared;
          material.inputs.push(site, provider, mappingOriginals, prepared);
          material.nodes += mappingNodes;
        } finally {material.busy = false;}
        reconcileSource(original, material);
        return prepared;
      },
      preparePublishedEnvironment(this: object, wire: unknown) {
        if (this !== context || !scope.active || scope.prepared !== undefined || scope.declarationAttempted ||
            material.phase !== 'working' || material.busy || typeof wire !== 'string') fail('ForeignInstalledSourceInitialization');
        scope.declarationAttempted = true;
        // The central constructor retains every input and native original under
        // this exact existing material before constructing the published view.
        const environment = composeInstalledSourceEnvironment(services, original.moon,
          scope.baseEnvironmentWire, undefined, wire);
        if (!scope.active || scope.prepared !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        scope.prepared = Object.freeze({environment});
        scope.publishedEnvironment = true;
        material.inputs.push(environment);
        return environment;
      },
      prepareNativeDeclaration(this: object, projection: object | undefined) {
        if (this !== context || !scope.active || scope.prepared !== undefined || scope.source !== undefined || scope.declarationAttempted ||
            material.phase !== 'working' || material.busy) fail('ForeignInstalledSourceInitialization');
        let {capacity: capacityFor, project}: Partial<ReturnType<typeof sourceProjectionMethods>> = sourceProjectionMethods(projection!);
        scope.declarationAttempted = true;
        let quantity;
        material.busy = true;
        try {quantity = requireSynchronousSourceConstruction(material, Reflect.apply(capacityFor!, projection, []));}
        finally {material.busy = false;}
        if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceDeclarationCapacityUnavailable');
        // Running and failed native construction keeps its complete original
        // peak. Only this caller can close the original declaration/export phase.
        const providerIndex = material.providers.length, projectionIndex = material.inputs.length;
        material.providers.push(quantity); material.inputs.push(projection);
        reserveSource(original, material);
        if (!scope.active || scope.prepared !== undefined || scope.source !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        let projected: unknown, declaration: unknown, declared: Declared, declaredWire: unknown;
        material.busy = true;
        try {
          // This declared native projection is synchronous and pure: no Site,
          // reader, callback or physical child can escape its failed prefix.
          // Unreturned native values become unreachable; the SAME complete
          // construction peak remains held, even when projection throws.
          projected = requireSynchronousSourceConstruction(material, Reflect.apply(project!, projection, []));
          material.inputs.push(projected);
          if (!scope.active || scope.prepared !== undefined || scope.source !== undefined ||
              material.phase !== 'working' || !projected || typeof projected !== 'object' ||
              nodeTypes.isProxy(projected) || !Object.isFrozen(projected)) fail('InvalidInstalledSourceDeclarationProjection');
          const projectedFields = Object.getOwnPropertyDescriptors(projected);
          if (Reflect.ownKeys(projectedFields).some(name => typeof name !== 'string' ||
              !Object.hasOwn(projectedFields[name], 'value'))) fail('InvalidInstalledSourceDeclarationProjection');
          const field = projectedFields.declaration;
          if (!field || !Object.hasOwn(field, 'value') || field.value === undefined) fail('InvalidInstalledSourceDeclarationProjection');
          declaration = field.value;
          declaredWire = requireSynchronousSourceConstruction(material,
            Reflect.apply(original.declarationJson, original.moon, [declaration]));
          material.inputs.push(declaration, declaredWire);
          if (typeof declaredWire !== 'string') fail('InvalidInstalledSourceDeclarationProjection');
        } finally {material.busy = false;}
        // Fund the outer exported JSON parse before observing its detached
        // member strings. The typed producer already retains the original wire.
        const parsedGeometry = sourceJsonWireGeometry(declaredWire);
        const parseNodes = 4n * parsedGeometry.nodes, parseText = 12n * parsedGeometry.units;
        reserveSource(original, material, parseNodes, parseText, 0n);
        // The original quote has TWO separate equal roles: returned tree and
        // parsing workspace. Keep their admitted total on failure; only the
        // successful pure parse can remove its ended workspace below. This is
        // not retained+execution (whose execution already contains retained).
        material.nodes += 2n * parseNodes; material.text += 2n * parseText;
        if (!scope.active || scope.prepared !== undefined || scope.source !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        material.busy = true;
        try {
          declared = JSON.parse(declaredWire);
          material.inputs.push(declared);
          freezeSourceProjection(declared);
        } finally {material.busy = false;}
        material.nodes -= parseNodes; material.text -= parseText;
        if (typeof material.methods!.InstalledSourceRetainedConstructionCapacity === 'function') {
          retainCompletedSourceNativeConstruction(original, material, providerIndex,
            projectionIndex, quantity, projection, () => {
              if (!scope.active || scope.prepared !== undefined || scope.source !== undefined) {
                fail('ForeignInstalledSourceInitialization');
              }
            });
          projection = capacityFor = project = quantity = undefined;
        }
        // A legacy runtime without the existing retained DATA port keeps its
        // old complete quote; no Host reconstruction or guessed shrink occurs.
        let environment;
        if (scope.role === 'effect') reserveSource(original, material);
        else environment = prepareSourceEnvironment(declared);
        if (!scope.active || scope.prepared !== undefined || scope.source !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        let prepared;
        material.busy = true;
        try {
          // Borrow the exact already-owned export. Consumers must not serialize
          // or export the declaration again just to recover its original wire.
          prepared = Object.freeze({declaration, declared, wire: declaredWire, environment});
          scope.prepared = prepared;
          // Preserve the existing raw Mapping continuation's declaration basis.
          scope.declarationBasis = 16n * (BigInt(declaredWire.length) + BigInt(scope.baseEnvironmentWire.length));
          material.inputs.push(environment);
        } finally {material.busy = false;}
        reconcileSource(original, material);
        return Object.freeze({...projected, ...prepared});
      },
      prepareBorrowedDeclaration(this: object, sourceContext: object) {
        const source = sourceContexts.get(sourceContext);
        if (this !== context || scope.role !== 'effect' || !scope.active ||
            scope.prepared !== undefined || scope.source !== undefined || scope.declarationAttempted ||
            material.phase !== 'working' || material.busy || source === undefined ||
            source.original !== original || source.material !== material ||
            source.scope.role !== 'source' || source.scope.installation !== scope.installation ||
            source.scope.connectorId !== scope.connectorId ||
            source.scope.baseEnvironmentWire !== scope.baseEnvironmentWire ||
            !source.scope.active || source.scope.closed || source.scope.prepared?.declaration === undefined ||
            source.scope.prepared.commands !== undefined || typeof source.scope.declarationBasis !== 'bigint') {
          fail('ForeignInstalledSourceInitialization');
        }
        const prepared = source.scope.prepared;
        scope.declarationAttempted = true;
        // Both contexts already belong to this exact material. Borrow the
        // existing immutable tuple without a copied declaration or new owner.
        // The original constructor quantity remains retained by that material.
        reserveSource(original, material);
        if (!scope.active || material.phase !== 'working' || scope.prepared !== undefined ||
            !source.scope.active || source.scope.closed || source.scope.prepared !== prepared) {
          fail('ForeignInstalledSourceInitialization');
        }
        scope.prepared = prepared;
        scope.declarationBasis = source.scope.declarationBasis;
        scope.borrowedDeclaration = source.scope;
        return prepared;
      },
      // Native connector producers already own and fund complete canonical
      // Mapping DATA. Retain those exact originals beside this SAME Common
      // declaration; Common still admits every Mapping at Program preparation.
      prepareNativeMappings(this: object, declared: unknown, mappingOriginals: unknown) {
        if (this !== context || scope.role !== 'effect' || !scope.active ||
            scope.prepared?.declaration === undefined || scope.source !== undefined ||
            scope.prepared.declared !== declared ||
            scope.mappingsAttempted || scope.prepared.mappings !== undefined ||
            scope.prepared.commands !== undefined || material.phase !== 'working' || material.busy ||
            !Array.isArray(mappingOriginals) || nodeTypes.isProxy(mappingOriginals) ||
            !Object.isFrozen(mappingOriginals) || mappingOriginals.length === 0) {
          fail('ForeignInstalledSourceInitialization');
        }
        const prepared = scope.prepared;
        for (let index = 0; index < mappingOriginals.length; index++) {
          const entry = Object.getOwnPropertyDescriptor(mappingOriginals, String(index));
          const value = entry?.value;
          if (!entry || !Object.hasOwn(entry, 'value') || !nativeInputOriginals.has(value) ||
              !Object.isFrozen(value)) fail('ForeignInstalledSourceInitialization');
          const fields = Object.getOwnPropertyDescriptors(value);
          for (const key of ['resource', 'mappingRef', 'mappingCid', 'body']) {
            const field = fields[key];
            if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
              fail('InvalidInstalledEffectMappings');
            }
          }
        }
        scope.mappingsAttempted = true;
        const mappingNodes = 1n + 6n * BigInt(mappingOriginals.length);
        reserveSource(original, material, mappingNodes);
        if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
            material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        let mappings;
        material.busy = true;
        try {
          mappings = Object.freeze(Array.prototype.map.call(mappingOriginals, (value: MappingCarrier) => Object.freeze({
            resource: value.resource, mappingRef: value.mappingRef,
            mappingCid: value.mappingCid, body: value.body})) as MappingCarrier[]);
          material.inputs.push(mappingOriginals, mappings);
          material.nodes += mappingNodes;
        } finally {material.busy = false;}
        const environment = prepareSourceEnvironment(prepared.declared!,
          Array.prototype.map.call(mappingOriginals, (value: MappingCarrier) => value.body) as string[]);
        if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
            material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
        scope.prepared = Object.freeze({...prepared, mappings, environment});
        material.inputs.push(scope.prepared);
        reconcileSource(original, material);
        return scope.prepared;
      },
      prepareMappings(this: object, writesJson: unknown, writes: unknown) {
        if (this !== context || !scope.active || scope.prepared === undefined ||
            scope.role !== 'effect' || scope.source !== undefined || scope.mappingsAttempted ||
            scope.prepared.commands !== undefined || material.phase !== 'working') {
          fail('ForeignInstalledSourceInitialization');
        }
        if (material.busy) fail('InstalledSourceInitializationReentry');
        if (typeof original.prepareMapping !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
        const originalPrepared = scope.prepared;
        if (typeof writesJson !== 'string' || !Array.isArray(writes) || nodeTypes.isProxy(writes) ||
            !Object.isFrozen(writes) || writes.length === 0) fail('InvalidInstalledEffectMappings');
        // Inspect only checked immutable own String DATA before the current/
        // resize boundary. Do not stringify proportional input before backing.
        let units = 0n, guarded = true, hasDelete = false;
        const field = (value: unknown, name: string): unknown => {
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
          const operationField = Object.getOwnPropertyDescriptor(write as object, 'operation');
          const operation = operationField === undefined ? 'create' : field(write, 'operation');
          if (operation !== 'create' && operation !== 'update' && operation !== 'delete' ||
              operation === 'update' && typeof original.prepareUpdateMapping !== 'function' ||
              operation === 'delete' && (sources.length !== 0 || typeof original.prepareDeleteMapping !== 'function')) {
            fail('InvalidInstalledEffectMappings');
          }
          guarded &&= operation !== 'create';
          hasDelete ||= operation === 'delete';
          units += BigInt(resource.length + operation.length);
          for (let j = 0; j < sources.length; j++) {
            const source = field(sources, String(j));
            for (const name of ['target', 'field', 'null_behavior']) {
              const value = field(source, name);
              if (typeof value !== 'string') fail('InvalidInstalledEffectMappings');
              units += BigInt(name.length + value.length);
            }
          }
        }
        if (!guarded && hasDelete) fail('InvalidInstalledEffectMappings');
        if (guarded) {
          const capacity = original.prepareUpdateMappingCapacity;
          if (typeof capacity !== 'function') fail('InstalledSourceInitializationRuntimeUnavailable');
          scope.mappingsAttempted = true;
          const validate = () => {
            if (!scope.active || material.phase !== 'working' || scope.prepared !== originalPrepared ||
                scope.source !== undefined) fail('ForeignInstalledSourceInitialization');
          };
          // Returned Mapping vector, one argument/closure cohort per constructor,
          // and the later body-reference vector. Payloads have their OWN native
          // quantities below; borrowed declaration/Environment are not restored.
          const containerNodes = 16n + 8n * BigInt(writes.length);
          reserveSource(original, material, containerNodes);
          validate();
          const mappings: (MappingCarrier & MappingOutput)[] = [];
          material.inputs.push(mappings);material.nodes += containerNodes;
          for (const write of writes) {
            if (write.operation === 'delete') {
              // The guarded construction quantity prices the same original
              // declaration and closed writes. DELETE has no source fields.
              const mapping = prepareSourceNativeInput(original, material, Object.freeze({
                capacity: () => checked(Reflect.apply(capacity, original.moon,
                  [originalPrepared.declaration, writesJson, write.resource, '[]'])),
                project() {
                  const runtime = Object.freeze({clientProgramRowSourcePrepareDeleteMapping: (...args: Parameters<RowSourceDeleteMappingMethod>) =>
                    Reflect.apply(original.prepareDeleteMapping!, original.moon, args)});
                  return Object.freeze({resource: write.resource,
                    ...rowSourceMapping(runtime, originalPrepared.declaration, writesJson, write.resource,
                      write.sources, 'delete')});
                },
              }), inputProjections, validate, retainNativeInput) as MappingCarrier & MappingOutput;
              mappings.push(mapping);
              continue;
            }
            const geometry = installedEnvironmentDataWriterConstructionGeometry(write.sources);
            const sourceWire = prepareSourceNativeInput(original, material, Object.freeze({
              capacity() {
                const {retained: r, workspace: w} = geometry;
                return checked(Reflect.apply(material.methods!.InstalledSourceConstructionCapacity as CoreMethod,
                  original.moon, [r.nodes, r.text, r.wire, w.nodes, w.text, w.wire]));
              },
              project: () => Object.freeze({wire: JSON.stringify(write.sources)}),
            }), inputProjections, validate, retainNativeInput) as Readonly<{wire: string}>;
            const mapping = prepareSourceNativeInput(original, material, Object.freeze({
              capacity: () => checked(Reflect.apply(capacity, original.moon,
                [originalPrepared.declaration, writesJson, write.resource, sourceWire.wire])),
              project() {
                const runtime = Object.freeze({clientProgramRowSourcePrepareUpdateMapping: (...args: Parameters<RowSourceMappingMethod>) =>
                  Reflect.apply(original.prepareUpdateMapping!, original.moon, args)});
                return Object.freeze({resource: write.resource,
                  ...rowSourceMapping(runtime, originalPrepared.declaration,
                    writesJson, write.resource, write.sources, 'update', sourceWire.wire)});
              },
            }), inputProjections, validate, retainNativeInput) as MappingCarrier & MappingOutput;
            mappings.push(mapping);
          }
          Object.freeze(mappings);
          // Every native constructor returned before this existing staged
          // Environment producer. Successful retained-only cuts keep all Mapping
          // outputs; any failed constructor/current fence keeps its FULL debt.
          const environment = prepareSourceEnvironment(originalPrepared.declared!,
            mappings.map(mapping => mapping.body));
          validate();
          scope.prepared = Object.freeze({...originalPrepared, mappings, environment});
          material.inputs.push(scope.prepared);
          reconcileSource(original, material);
          return scope.prepared;
        }
        // Each retained Mapping can expand the original declaration/writes.
        // The final Environment overlaps those bodies. The SAME proportional
        // material recipe covers the failed prefix, without a second Resource.
        const basis = BigInt(writes.length) * (scope.declarationBasis! + 6n * BigInt(writesJson.length)) +
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
          const runtime = Object.freeze({clientProgramRowSourcePrepareMapping: (...args: Parameters<RowSourceMappingMethod>) =>
            Reflect.apply(original.prepareMapping!, original.moon, args),
            clientProgramRowSourcePrepareUpdateMapping: (...args: Parameters<RowSourceMappingMethod>) =>
              Reflect.apply(original.prepareUpdateMapping!, original.moon, args)});
          const mappings = Object.freeze(writes.map(write => Object.freeze({resource: write.resource,
            ...rowSourceMapping(runtime, scope.prepared!.declaration, writesJson, write.resource, write.sources,
              Object.getOwnPropertyDescriptor(write, 'operation')?.value ?? 'create')})));
          const environment = rowSourceCheckEnvironment(scope.baseEnvironmentWire, scope.prepared.declared!,
            mappings.map(mapping => mapping.body));
          prepared = Object.freeze({...scope.prepared, environment, mappings});
          scope.prepared = prepared;
          material.inputs.push(writesJson, writes, mappings, environment);
          material.nodes += 4n * basis; material.text += 8n * basis; material.wire += 8n * basis;
        } finally {material.busy = false;}
        reconcileSource(original, material);
        return prepared;
      },
      prepareDerivedDeclaredCommands, prepareAuthoredCommands, prepareDeclaredCommands,
      prepareReadTarget(this: object, projection: object) {return prepareProviderConstruction.call(this, projection, 'source');},
      prepareReadTargetWithMappings(this: object, projection: object) {return prepareProviderConstruction.call(this, projection, 'source', true);},
      prepareEffectDriverConstruction(this: object, projection: object) {return prepareProviderConstruction.call(this, projection, 'effect');},
      prepareAuthoredDeclaration, prepareDeclaration,
    });
    sourceContexts.set(context, {original, material, scope});
    return context;
  }
  return createInstalledSourceContext;
}
