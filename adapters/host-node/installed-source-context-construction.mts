import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {installedEnvironmentDataWriterConstructionGeometry,
  installedEnvironmentMemberSortConstructionGeometry} from './installed-check-environment-construction.mjs';
import {authoredCommandProjection} from './installed-authored-command.mjs';
import {sourceEnvironmentConstructionGeometry, sourceDeclarationRetainedGeometry, sourceAuthoredViewConstructionGeometry}
  from './installed-source-construction-geometry.mjs';
import type {createInstalledSourceMaterialAccounting} from './installed-source-material-accounting.mjs';

type Accounting = ReturnType<typeof createInstalledSourceMaterialAccounting>;
type Material = NonNullable<ReturnType<Accounting['sourceMaterial']>>;
type EnvironmentArgs = Parameters<NonNullable<Material['retainEnvironmentNativeOriginal']>>;
type NativeEnvironment = EnvironmentArgs[1];
type Declared = Parameters<typeof sourceEnvironmentConstructionGeometry>[1] & Readonly<{catalog_cid?: unknown}>;
type NativeValue = Extract<SynchronousRuntimeData, object>;
type Geometry = ReturnType<typeof sourceEnvironmentConstructionGeometry>['parsed'];
type CoreMethod = (...args: unknown[]) => unknown;
type Role = 'source' | 'effect';
type Original = Parameters<Accounting['sourceMaterial']>[0] &
  Readonly<{moon: EnvironmentArgs[0]; declarationJson: CoreMethod;
    restoreDeclaration?: unknown; restoreAuthoredDeclaration?: unknown}>;
type Prepared = Readonly<{
  declaration?: unknown; declared?: Declared; environment?: NativeEnvironment; environmentMappings?: readonly string[];
  commands?: readonly unknown[]; commandDefinition?: unknown;
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
};
type EnvironmentConstruction = Readonly<{
  freeze: Accounting['freezeSourceProjection'];
  parse<Value extends NativeValue>(project: () => Value): Value;
  sort<Value extends NativeValue>(values: readonly unknown[], project: () => Value): Value;
  seal<Value extends NativeValue>(body: Value): Value;
  hash(body: unknown, project: () => string): string;
  encode<Value extends NativeValue>(document: unknown, project: () => Value): Value;
}>;
type ContextPorts = Pick<Accounting, 'installedSourceConfigurationReader' | 'reserveSource' | 'reconcileSource' |
  'freezeSourceProjection' | 'sourceProjectionMethods' | 'requireSynchronousSourceConstruction'> & Readonly<{
  fail(code: string): never;
  original: Original;
  material: Material;
  services: object;
  scope: Scope;
  currentContext(): CommandContext;
  rowSourceCheckEnvironment(baseWire: string, declared: Declared, mappings?: readonly string[],
    retainOriginal?: (value: EnvironmentArgs[1], document: EnvironmentArgs[2], body: EnvironmentArgs[3]) => void,
    construction?: EnvironmentConstruction): NativeEnvironment;
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
