import {createAccountConstruction} from './account-construction.mjs';
import {composeInstalledSourceEnvironment, releaseRetiredInstalledEnvironmentComposition, bindInstalledEnvironmentConstruction,
  assertInstalledEnvironmentPublicationOriginal} from './installed-funded-environment.mjs';
import {installedEnvironmentDataWriterConstructionGeometry} from './installed-check-environment-construction.mjs';
// Standard installed Host service owner. This public cut retains the exact
// original Source implementation/Site association; numerical DATA is neither
// a Run admission nor permission. Other service facets extend this SAME owner.
import {openInstalledRowSite, installedRowCredentialOperationSite, rowSourceCheckEnvironment,
  rowSourceMapping, createInstalledRowSource, installRowSourceAuthorization} from './installed-row-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {sourceEnvironmentConstructionGeometry, sourceJsonWireGeometry}
  from './installed-source-construction-geometry.mjs';
import {createInstalledRowEffect, resolveInstalledRowEffectConstruction} from './installed-row-effect.mjs';
import {createInstalledTableSource, installedTableReadSite} from './installed-table-source.mjs';
import {createInstalledTableEffect} from './installed-table-effect.mjs';
import {installDuckDBSourceProfile, createInstalledDuckDBSource} from './installed-duckdb-source.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {captureConfigurationReaders} from './source-profile-json.mjs';
import {runtimeField, runtimeTag, runtimeIsBoxedSome, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {createInstalledCredentialSourceReader, installedJsonSourceReaderLimitNames,
  installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {types as nodeTypes} from 'node:util';
import {createInstalledSourcePhysicalConstruction} from './installed-source-physical-construction.mjs';
import {createInstalledSourceMaterialAccounting} from './installed-source-material-accounting.mjs';
import {createInstalledSourceContextCustody, captureInstalledSourceServices} from './installed-source-context-custody.mjs';
import {createInstalledSourceContextConstruction} from './installed-source-context-construction.mjs';

const sourceNativeThen = Promise.prototype.then;
const installations = new WeakMap();
const sourceContexts = new WeakMap();
const boundConstructions = new WeakMap();
const fail = code => {throw Object.assign(new TypeError(code), {code});};

const {sourceMaterial, sourceCall, reserveSource, reconcileSource,
  retainSourceFailure, requireSynchronousSourceConstruction, sourceProjectionMethods, freezeSourceProjection,
  retainCompletedSourceNativeConstruction, prepareSourceNativeInput, reserveSourceJsonConstruction,
  retainCompletedSourceJson, prepareModelTaskInput, installedSourceConfigurationReader, withInstalledSourceLoading,
  installedSourceEnvironmentConstructionReader, reserveInstalledSourceEnvironment, reserveInstalledSourceRuntimeIdentity,
  completeInstalledSourceInitialization, borrowInstalledSourceInitialization, isInstalledSourceInitializationRetired,
  retireInstalledSourceInitialization} =
  createInstalledSourceMaterialAccounting({fail, sourceNativeThen, installations, bindInstalledEnvironmentConstruction,
    assertInstalledEnvironmentPublicationOriginal, releaseRetiredInstalledEnvironmentComposition});
export {installedSourceConfigurationReader, withInstalledSourceLoading, installedSourceEnvironmentConstructionReader,
  reserveInstalledSourceEnvironment, reserveInstalledSourceRuntimeIdentity, completeInstalledSourceInitialization,
  borrowInstalledSourceInitialization, isInstalledSourceInitializationRetired, retireInstalledSourceInitialization};

const {reserveInstalledTableConstruction, installedTableReaderConstruction,
  reserveInstalledDuckDBConstruction} = createInstalledSourcePhysicalConstruction({fail, sourceCall, reserveSource});

const {requireSourceConstructor, beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization,
  retainBoundInstalledSourceFailure, assertInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
  prepareInstalledSourceAcquisitionContracts, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  finishInstalledSourceInitialization, retainInstalledHostServiceInstallation} =
  createInstalledSourceContextCustody({fail, installations, sourceContexts, boundConstructions, sourceMaterial,
    createInstalledSourceContext, retainInstalledHostInitializationFailure, reserveSource, reconcileSource,
    requireSynchronousSourceConstruction, retainSourceFailure, resolveInstalledRowEffectConstruction});
export {beginInstalledSourceInitialization, beginInstalledPublishedSourceInitialization,
  retainBoundInstalledSourceFailure, assertInstalledSourceConstruction, readInstalledSourceAcquisitionContract,
  prepareInstalledSourceAcquisitionContracts, retainInstalledSourceConstruction, closeInstalledSourceConstruction,
  finishInstalledSourceInitialization, retainInstalledHostServiceInstallation, captureInstalledSourceServices};

function createInstalledSourceContext(original, material, installation, connectorId, baseEnvironmentWire, role, services) {
  const scope = {installation, connectorId, baseEnvironmentWire, role, prepared: undefined,
    source: undefined, active: true};
  material.contexts.push(scope); material.constructors++;
  const inputProjections = new WeakSet();
  const nativeInputOriginals = new WeakSet();
  const validateNativeInputContext = prepared => {
    if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
        material.phase !== 'working' || prepared !== undefined &&
        (scope.role !== 'effect' || prepared.declaration === undefined ||
          prepared.mappings !== undefined || prepared.commands !== undefined ||
          scope.mappingsAttempted || scope.commandAttempted || scope.providerAttempted)) {
      fail('ForeignInstalledSourceInitialization');
    }
  };
  const retainNativeInput = value => nativeInputOriginals.add(value);
  const {prepareSourceEnvironment, prepareOriginalDeclaration, captureDeclarationViews,
    prepareProviderConstruction, prepareInitialNativeConstruction, prepareDerivedDeclaredCommands,
    prepareAuthoredCommands, prepareDeclaredCommands, prepareAuthoredDeclaration, prepareDeclaration} =
    createInstalledSourceContextConstruction({fail, original, material, services, scope,
      currentContext: () => context, installedSourceConfigurationReader, reserveSource, reconcileSource, freezeSourceProjection,
      sourceProjectionMethods, requireSynchronousSourceConstruction, rowSourceCheckEnvironment});
  const context = Object.freeze({
    prepareInputConstruction(projection) {
      if (this !== context) fail('ForeignInstalledSourceInitialization');
      const project = prepareInitialNativeConstruction(projection, 'nativeInputAttempted');
      material.busy = true;
      try {
        const value = requireSynchronousSourceConstruction(material,
          Reflect.apply(project, projection, []));
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
    prepareNativeInput(projection) {
      if (this !== context) fail('ForeignInstalledSourceInitialization');
      // Mapping constructors need the original declaration CID. Pin this
      // same tuple across every reservation and projection fence; Source and
      // already-started Mapping/Command/driver paths remain closed.
      const prepared = scope.prepared;
      return prepareSourceNativeInput(original, material, projection, inputProjections,
        () => validateNativeInputContext(prepared), retainNativeInput);
    },
    prepareReadMetadata(declared, project) {
      const prepared = scope.prepared;
      if (this !== context || scope.role !== 'source' || scope.readMetadataAttempted ||
          prepared?.declared !== declared || !Array.isArray(declared?.views) ||
          typeof project !== 'function') fail('ForeignInstalledSourceInitialization');
      scope.readMetadataAttempted = true;
      // Quote the complete original range once, before either variable-sized
      // metadata constructor. Strings and authority are borrowed originals.
      // Two retained containers hold N keys and N four-field records (7N+2
      // node slots), and the returned two-field metadata record takes three.
      // Their later synchronous binding check overlaps one Set
      // and one returned reference array (2N+2); keep that allowance with the
      // SAME Source material instead of issuing per-access reservations.
      const nodes = 9n * BigInt(declared.views.length) + 7n;
      const quote = material.methods.InstalledSourceConstructionCapacity;
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
    prepareProviderEffect(site, provider, mappingOriginals) {
      if (this !== context || scope.role !== 'effect' || !scope.active || scope.prepared !== undefined ||
          scope.declarationAttempted || material.phase !== 'working' || material.busy ||
          !nativeInputOriginals.has(provider) || !Array.isArray(mappingOriginals) ||
          nodeTypes.isProxy(mappingOriginals) || !Object.isFrozen(mappingOriginals) ||
          !mappingOriginals.every(value => nativeInputOriginals.has(value))) {
        fail('ForeignInstalledSourceInitialization');
      }
      const {declared, schemas, capabilities} = provider;
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
    preparePublishedEnvironment(wire) {
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
    prepareNativeDeclaration(projection) {
      if (this !== context || !scope.active || scope.prepared !== undefined || scope.source !== undefined || scope.declarationAttempted ||
          material.phase !== 'working' || material.busy) fail('ForeignInstalledSourceInitialization');
      let {capacity: capacityFor, project} = sourceProjectionMethods(projection);
      scope.declarationAttempted = true;
      let quantity;
      material.busy = true;
      try {quantity = requireSynchronousSourceConstruction(material, Reflect.apply(capacityFor, projection, []));}
      finally {material.busy = false;}
      if (!quantity || typeof quantity !== 'object' || nodeTypes.isProxy(quantity)) fail('InstalledSourceDeclarationCapacityUnavailable');
      // Running and failed native construction keeps its complete original
      // peak. Only this caller can close the original declaration/export phase.
      const providerIndex = material.providers.length, projectionIndex = material.inputs.length;
      material.providers.push(quantity); material.inputs.push(projection);
      reserveSource(original, material);
      if (!scope.active || scope.prepared !== undefined || scope.source !== undefined || material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
      let projected, declaration, declared, declaredWire;
      material.busy = true;
      try {
        // This declared native projection is synchronous and pure: no Site,
        // reader, callback or physical child can escape its failed prefix.
        // Unreturned native values become unreachable; the SAME complete
        // construction peak remains held, even when projection throws.
        projected = requireSynchronousSourceConstruction(material, Reflect.apply(project, projection, []));
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
      if (typeof material.methods.InstalledSourceRetainedConstructionCapacity === 'function') {
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
    prepareBorrowedDeclaration(sourceContext) {
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
    prepareNativeMappings(declared, mappingOriginals) {
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
        mappings = Object.freeze(Array.prototype.map.call(mappingOriginals, value => Object.freeze({
          resource: value.resource, mappingRef: value.mappingRef,
          mappingCid: value.mappingCid, body: value.body})));
        material.inputs.push(mappingOriginals, mappings);
        material.nodes += mappingNodes;
      } finally {material.busy = false;}
      const environment = prepareSourceEnvironment(prepared.declared,
        Array.prototype.map.call(mappingOriginals, value => value.body));
      if (!scope.active || scope.prepared !== prepared || scope.source !== undefined ||
          material.phase !== 'working') fail('ForeignInstalledSourceInitialization');
      scope.prepared = Object.freeze({...prepared, mappings, environment});
      material.inputs.push(scope.prepared);
      reconcileSource(original, material);
      return scope.prepared;
    },
    prepareMappings(writesJson, writes) {
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
        const operationField = Object.getOwnPropertyDescriptor(write, 'operation');
        const operation = operationField === undefined ? 'create' : field(write, 'operation');
        if (operation !== 'create' && operation !== 'update' ||
            operation === 'update' && typeof original.prepareUpdateMapping !== 'function') {
          fail('InvalidInstalledEffectMappings');
        }
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
      if (writes.every(write => write.operation === 'update')) {
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
        const mappings = [];
        material.inputs.push(mappings);material.nodes += containerNodes;
        for (const write of writes) {
          const geometry = installedEnvironmentDataWriterConstructionGeometry(write.sources);
          const sourceWire = prepareSourceNativeInput(original, material, Object.freeze({
            capacity() {
              const {retained: r, workspace: w} = geometry;
              return checked(Reflect.apply(material.methods.InstalledSourceConstructionCapacity,
                original.moon, [r.nodes, r.text, r.wire, w.nodes, w.text, w.wire]));
            },
            project: () => Object.freeze({wire: JSON.stringify(write.sources)}),
          }), inputProjections, validate, retainNativeInput);
          const mapping = prepareSourceNativeInput(original, material, Object.freeze({
            capacity: () => checked(Reflect.apply(capacity, original.moon,
              [originalPrepared.declaration, writesJson, write.resource, sourceWire.wire])),
            project() {
              const runtime = Object.freeze({clientProgramRowSourcePrepareUpdateMapping: (...args) =>
                Reflect.apply(original.prepareUpdateMapping, original.moon, args)});
              return Object.freeze({resource: write.resource,
                ...rowSourceMapping(runtime, originalPrepared.declaration,
                  writesJson, write.resource, write.sources, 'update', sourceWire.wire)});
            },
          }), inputProjections, validate, retainNativeInput);
          mappings.push(mapping);
        }
        Object.freeze(mappings);
        // Every native constructor returned before this existing staged
        // Environment producer. Successful retained-only cuts keep all Mapping
        // outputs; any failed constructor/current fence keeps its FULL debt.
        const environment = prepareSourceEnvironment(originalPrepared.declared,
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
          Reflect.apply(original.prepareMapping, original.moon, args),
          clientProgramRowSourcePrepareUpdateMapping: (...args) =>
            Reflect.apply(original.prepareUpdateMapping, original.moon, args)});
        const mappings = Object.freeze(writes.map(write => Object.freeze({resource: write.resource,
          ...rowSourceMapping(runtime, scope.prepared.declaration, writesJson, write.resource, write.sources,
            Object.getOwnPropertyDescriptor(write, 'operation')?.value ?? 'create')})));
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
    prepareDerivedDeclaredCommands, prepareAuthoredCommands, prepareDeclaredCommands,
    prepareReadTarget(projection) {return prepareProviderConstruction.call(this, projection, 'source');},
    prepareReadTargetWithMappings(projection) {return prepareProviderConstruction.call(this, projection, 'source', true);},
    prepareEffectDriverConstruction(projection) {return prepareProviderConstruction.call(this, projection, 'effect');},
    prepareAuthoredDeclaration, prepareDeclaration,
  });
  sourceContexts.set(context, {original, material, scope});
  return context;
}

// The ordinary loader owns this one bound factory. Connector code supplies
// domain inputs, never the initialization token or registration/retirement order.
// Keep partial acquisitions in the existing initialization failure carrier.
export function bindInstalledSourceConstruction(services, context, checkedProfile, profileConstruction) {
  const retained = sourceContexts.get(context), original = installations.get(services);
  if (retained === undefined || retained.original !== original) fail('ForeignInstalledSourceConstruction');
  if (boundConstructions.has(context)) fail('InstalledSourceConstructionAlreadyBound');
  const {scope, material} = retained;
  const owned = {site: undefined, authorization: undefined, reader: undefined, adapter: undefined,
    constructing: false, attempted: false};
  boundConstructions.set(context, owned);
  const current = () => {
    if (!scope.active || material.phase !== 'working' || owned.failed || owned.closed) fail('InstalledSourceInitializationClosed');
    original.current();
    if (!scope.active || material.phase !== 'working' || owned.failed || owned.closed) fail('InstalledSourceInitializationClosed');
  };
  const domain = (options, reserved = []) => {
    if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options)) fail('InvalidInstalledSourceConstruction');
    const fields = Object.getOwnPropertyDescriptors(options);
    for (const name of Reflect.ownKeys(fields)) {
      if (typeof name !== 'string' || !Object.hasOwn(fields[name], 'value') || reserved.includes(name)) {
        fail('InvalidInstalledSourceConstruction');
      }
    }
    return Object.fromEntries(Object.entries(fields).map(([name, field]) => [name, field.value]));
  };
  const identity = options => ({...domain(options, ['installation', 'sourceInitialization']),
    installation: scope.installation, sourceInitialization: context});
  const prepare = name => (...args) => {
    current();
    const value = Reflect.apply(context[name], context, args);
    current();
    return value;
  };
  async function construct(options, role, factory) {
    current();
    if (scope.role !== role || owned.attempted || owned.constructing || scope.prepared === undefined ||
        owned.site === undefined || owned.authorization === undefined ||
        scope.prepared.environment === undefined) fail('InstalledSourceConstructionUnavailable');
    const selected = domain(options, ['moon', 'sourceInitialization', 'declaration', 'declared', 'environment',
      'environmentWire', 'site', 'authorization', 'connectorId', 'connectorRegistration', 'connectorRevision']);
    const prepared = scope.prepared;
    const {projectSite, ...input} = selected;
    if (projectSite !== undefined && (typeof projectSite !== 'function' || nodeTypes.isProxy(projectSite) ||
        nodeTypes.isAsyncFunction(projectSite))) fail('InvalidInstalledSiteProjection');
    owned.attempted = true; owned.constructing = true;
    try {
      let site = owned.site;
      if (projectSite !== undefined) {
        // A grant projection changes domain method names, never physical
        // custody. Capture the owned Site's actual close before provider code.
        const originalSite = owned.site;
        const close = Object.getOwnPropertyDescriptor(originalSite, 'close');
        if (!close || !Object.hasOwn(close, 'value') || typeof close.value !== 'function') {
          fail('InvalidInstalledSiteProjection');
        }
        const projected = requireSynchronousSourceConstruction(material,
          Reflect.apply(projectSite, undefined, [originalSite]));
        material.inputs.push(projected);
        const fields = domain(projected, ['close', 'then']);
        site = Object.freeze({...fields, close: () => Reflect.apply(close.value, originalSite, [])});
      }
      material.inputs.push(site);
      current();
      // No connector callback runs between acquisition and retaining the actual
      // adapter. The constructor itself retains partial physical failures.
      const adapter = await factory({...input, moon: original.moon, sourceInitialization: context,
        ...prepared, environmentWire: prepared.environment.wire,
        connectorId: scope.connectorId, connectorRegistration: scope.installation.registration,
        connectorRevision: scope.installation.revision, site, authorization: owned.authorization});
      owned.adapter = adapter;
      current();
      if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
      return adapter;
    } finally {owned.constructing = false;}
  }
  const bound = Object.freeze({
    configurationReader: captureConfigurationReaders(installedSourceConfigurationReader(services), undefined,
      () => fail('InstalledConfigurationReaderUnavailable')),
    prepareDeclaration: prepare('prepareDeclaration'),
    prepareNativeDeclaration: prepare('prepareNativeDeclaration'),
    prepareNativeInput: prepare('prepareNativeInput'),
    preparePublishedEnvironment: prepare('preparePublishedEnvironment'),
    prepareProviderEffect(provider, mappings) {
      current();
      if (owned.site === undefined) fail('InstalledSourceSiteUnavailable');
      const value = context.prepareProviderEffect(owned.site, provider, mappings);
      current(); return value;
    },
    prepareAuthoredDeclaration: prepare('prepareAuthoredDeclaration'),
    prepareBorrowedDeclaration: prepare('prepareBorrowedDeclaration'),
    prepareMappings: prepare('prepareMappings'),
    prepareNativeMappings: prepare('prepareNativeMappings'),
    prepareDeclaredCommands: prepare('prepareDeclaredCommands'),
    prepareAuthoredCommands: prepare('prepareAuthoredCommands'),
    prepareDerivedDeclaredCommands: prepare('prepareDerivedDeclaredCommands'),
    prepareReadTarget: prepare('prepareReadTarget'),
    prepareReadTargetWithMappings: prepare('prepareReadTargetWithMappings'),
    prepareEffectDriverConstruction: prepare('prepareEffectDriverConstruction'),
    sourceReaderImplementationProfile(options) {
      current(); return services.sourceReaderImplementationProfile(identity(options));
    },
    sourceReaderImplementation(options) {
      current(); return services.sourceReaderImplementation(identity(options));
    },
    async openSpecializedSite(options) {
      current();
      if (owned.site !== undefined || owned.siteAttempted) fail('InstalledSourceSiteAlreadyConstructed');
      const selected = domain(options);
      const {authorizationConstructor, siteConstructor, siteArgument, accountConfiguration, siteOptions = {}} = selected;
      if (typeof authorizationConstructor !== 'function' || typeof siteConstructor !== 'function' ||
          nodeTypes.isProxy(authorizationConstructor) || nodeTypes.isProxy(siteConstructor)) fail('InvalidInstalledSpecializedSite');
      const input = domain(siteOptions, ['authorization','commonMoon','runtimeBundleCid','configurationReader','ownAuthorization']);
      owned.siteAttempted = true;
      const authorization = await Reflect.apply(authorizationConstructor, undefined, [{accountConfiguration,
        root: original.root, principalId: original.principalId, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}}]);
      owned.authorization = authorization;
      current();
      const site = await Reflect.apply(siteConstructor, undefined, [siteArgument, {...input, authorization,
        commonMoon: original.moon, runtimeBundleCid: original.selected.get(scope.installation),
        configurationReader: bound.configurationReader, ownAuthorization: true}]);
      owned.site = site;
      // Bind this SAME specialized original to its bound constructor just as
      // openRowSite does. Credential custody still validates the Site issuer;
      // this private association supplies no grant or physical acknowledgement.
      original.siteInstallations.set(site, context);
      current();
      return Object.freeze({site, authorization});
    },
    async openRowSite(options) {
      current();
      if (owned.site !== undefined || owned.siteAttempted) fail('InstalledSourceSiteAlreadyConstructed');
      const selected = domain(options);
      const profile = selected.profile;
      // The bound owner captures immutable installation DATA; a provider need
      // not remember to freeze a fresh domain profile before the Site call.
      const fields = domain(profile);
      const capturedProfile = Object.isFrozen(profile) ? profile : Object.freeze(fields);
      material.inputs.push(profile, capturedProfile);
      owned.siteAttempted = true;
      const opened = await services.openRowSite(identity({...selected, profile: capturedProfile}));
      // The actual shared Site constructor owns its Authorization even when
      // its own current check fails. Retain both before this facade reenters.
      owned.site = opened.site; owned.authorization = opened.authorization;
      current();
      return opened;
    },
    createSourceReader(options) {
      current();
      if (owned.reader !== undefined) fail('InstalledSourceReaderAlreadyConstructed');
      const selected = domain(options, ['site']);
      const reader = services.createSourceReader(identity({...selected, site: owned.site}));
      owned.reader = reader;
      current();
      return reader;
    },
    async createDuckDBSource() {
      current();
      if (scope.role !== 'source' || !scope.publishedEnvironment || scope.prepared?.environment === undefined ||
          typeof scope.connectorId !== 'string' || owned.attempted || owned.constructing) {
        fail('InstalledSourceConstructionUnavailable');
      }
      const prepared = scope.prepared;
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledDuckDBConstruction(original, material, checkedProfile, prepared.environment);
        current();
        const profile = await installDuckDBSourceProfile(checkedProfile, {
          root: original.root, principalId: original.principalId, runtime: original.moon,
          retainAuthorization(authorization) {
            // Retain before the installed profile can return or fail.
            owned.authorization = authorization;
            material.inputs.push(authorization);
          },
        });
        material.inputs.push(profile);
        current();
        // This known constructor registers its SAME adapter before returning;
        // connector DATA cannot supply a factory or register an arbitrary value.
        const adapter = await createInstalledDuckDBSource(profile, original.moon, {
          root: original.root, principalId: original.principalId,
          sourceInitialization: context, environment: prepared.environment,
          installation: scope.installation,
        });
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    async createTableSource(options) {
      current();
      if (scope.role !== 'source' || owned.attempted || scope.prepared !== undefined) {
        fail('InstalledSourceConstructionUnavailable');
      }
      const selected = domain(options, ['moon', 'sourceInitialization', 'environment', 'environmentWire',
        'declaration', 'declared', 'site', 'authorization', 'connectorId', 'connectorRegistration',
        'connectorRevision', 'baseEnvironmentWire']);
      const {accountConfiguration, createBridge, ...input} = selected;
      if (typeof createBridge !== 'function' || nodeTypes.isProxy(createBridge) ||
          nodeTypes.isAsyncFunction(createBridge)) fail('InvalidInstalledTableBridgeConstructor');
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledTableConstruction(original, material, checkedProfile, profileConstruction);
        const bridge = requireSynchronousSourceConstruction(material, Reflect.apply(createBridge, undefined, []));
        owned.bridge = bridge; material.inputs.push(bridge);
        if (!bridge || typeof bridge !== 'object' || nodeTypes.isProxy(bridge) ||
            'then' in bridge) fail('InvalidInstalledTableBridge');
        current();
        // Full installation construction remains retained above. A selected
        // Reader only sends ONE first selector; later reply-derived payloads
        // grow through that SAME RowRun before their actual allocation.
        const readerProfileCapacity = installedTableReaderConstruction(original, material,
          checkedProfile, profileConstruction, bridge);
        const prepared = context.prepareDeclaration(input.targets.map(target => ({
          resource: target.resource, resource_kind: 'table', schema_wire: target.schemaWire,
          schema_cid: target.selector.schema_cid,
        })));
        current();
        const authorization = await installRowSourceAuthorization({accountConfiguration,
          root: original.root, principalId: original.principalId,
          connectorRegistration: scope.installation.registration, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}});
        owned.authorization = authorization;
        current();
        const site = installedTableReadSite({connection: input.connection, authorization,
          principalId: original.principalId, ownAuthorization: true,
          targets: () => owned.adapter?.tableReadTargets ?? []});
        owned.site = site;
        current();
        const capacityMethod = original.moon.clientProgramInstalledTableSourceReaderCapacity;
        if (typeof capacityMethod !== 'function' || nodeTypes.isAsyncFunction(capacityMethod)) {
          fail('InstalledTableSourceReaderUnavailable');
        }
        const columns = Math.max(...prepared.declared.views.map(view => view.fields.length));
        const originalReaderCapacity = Reflect.apply(capacityMethod, original.moon, [columns, readerProfileCapacity]);
        // Preserve the original native reference Option for the existing typed
        // Source composition. Its canonical binding alone exposes the value;
        // Host never reconstructs a Some, tuple or scalar capacity.
        const readerCapacity = runtimeUnboxedReferenceOption(originalReaderCapacity);
        if (readerCapacity === undefined || readerCapacity === null || typeof readerCapacity !== 'object') {
          fail('InstalledTableSourceReaderUnavailable');
        }
        material.providers.push(originalReaderCapacity);
        reserveSource(original, material);
        current();
        const bindReader = reader => {
          current();
          if (owned.reader !== undefined || scope.reader !== undefined ||
              bridge.frameLimits === undefined || !Object.isFrozen(bridge.frameLimits)) {
            fail('InstalledTableSourceReaderUnavailable');
          }
          owned.reader = scope.reader = reader;
          // Two actual commands, each with its ready and reply frame. Page
          // count remains the original row-page profile; protocol transfer is
          // the actual four original bounded bodies, not re-encoded rows.
          scope.readerDemand = Object.freeze({nested:false,responses:4,
            queryPages:input.limits.maxPages,maxResponseBytes:input.limits.maxPageBytes,
            maxNodes:400000,maxDepth:32,maxRows:input.limits.maxPageRows,
            maxTotalRows:input.limits.maxCaptureRows,
            transferBytes:4n*BigInt(bridge.frameLimits.maxBytes)});
        };
        const adapter = await createInstalledTableSource({...input, bridge, site, authorization,
          readerCapacity, bindReader,
          moon: original.moon, sourceInitialization: context, ...prepared,
          baseEnvironmentWire: scope.baseEnvironmentWire,
          connectorId: scope.connectorId, connectorRegistration: scope.installation.registration,
          connectorRevision: scope.installation.revision});
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    async createTableEffect(options) {
      current();
      if (scope.role !== 'effect' || scope.publishedEnvironment !== true || owned.attempted ||
          scope.prepared?.environment === undefined) fail('InstalledSourceConstructionUnavailable');
      const selected = domain(options, ['moon', 'sourceInitialization', 'environment', 'environmentWire',
        'authorization', 'connectorId', 'connectorRegistration', 'connectorRevision', 'runtimeBundleCid']);
      const {accountConfiguration, createBridge, ...input} = selected;
      if (typeof createBridge !== 'function' || nodeTypes.isProxy(createBridge) ||
          nodeTypes.isAsyncFunction(createBridge)) fail('InvalidInstalledTableBridgeConstructor');
      const prepared = scope.prepared;
      owned.attempted = true; owned.constructing = true;
      try {
        reserveInstalledTableConstruction(original, material, checkedProfile, profileConstruction);
        const bridge = requireSynchronousSourceConstruction(material, Reflect.apply(createBridge, undefined, []));
        owned.bridge = bridge; material.inputs.push(bridge);
        if (!bridge || typeof bridge !== 'object' || nodeTypes.isProxy(bridge) ||
            'then' in bridge) fail('InvalidInstalledTableBridge');
        current();
        const authorization = await installRowSourceAuthorization({accountConfiguration,
          root: original.root, principalId: original.principalId,
          connectorRegistration: scope.installation.registration, gateOptions: {runtime: original.moon, accountConstruction: installedAccountConstruction(services)}});
        owned.authorization = authorization;
        current();
        const adapter = await createInstalledTableEffect({...input, bridge, moon: original.moon,
          sourceInitialization: context, environment: prepared.environment,
          environmentWire: prepared.environment.wire, authorization,
          connectorId: scope.connectorId, connectorRegistration: scope.installation.registration,
          connectorRevision: scope.installation.revision,
          runtimeBundleCid: original.selected.get(scope.installation)});
        owned.adapter = adapter;
        current();
        if (scope.prepared !== prepared || scope.source !== adapter) fail('ForeignInstalledSourceConstruction');
        return adapter;
      } finally {owned.constructing = false;}
    },
    createRowSource: options => construct(options, 'source', createInstalledRowSource),
    createRowEffect: options => construct(options, 'effect', createInstalledRowEffect),
  });
  return bound;
}

export function createInstalledHostServices({root, principalId, moon, assertCurrent, accountCurrent, receiver, initialPreparation}) {
  if (typeof root !== 'string' || !root || typeof principalId !== 'string' || !principalId ||
      !moon || typeof moon !== 'object' || typeof assertCurrent !== 'function') fail('InvalidInstalledHostServices');
  const selected = new WeakMap(), sites = new WeakMap(), siteInstallations = new WeakMap();
  const implementations = new WeakMap(), sourceImplementations = new WeakMap(), sourceProfiles = new WeakMap();
  const publicationOnly = false;
  const sourcePolicy = moon.clientProgramInstalledSourceReaderPolicy;
  const sourceProfile = moon.clientProgramInstalledJsonSourceReaderProfile;
  const sourceCapacity = moon.clientProgramInstalledJsonSourceReaderCapacity;
  const cursorSourceCapacity = moon.clientProgramInstalledJsonCursorSourceReaderCapacity;
  const cursorSourceRequestCapacity = moon.clientProgramInstalledJsonCursorSourceReaderCapacityWithRequest;
  const sourceRequestCapacity = moon.clientProgramInstalledJsonSourceReaderCapacityWithRequest;
  const preservingSourceRequestCapacity = moon.clientProgramInstalledPreservingJsonSourceReaderCapacityWithRequest;
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
          (Object.hasOwn(fields, 'preservingRequestConstruction') ? 1 : 0) +
          (Object.hasOwn(fields, 'cursorProgress') ? 1 : 0) +
          (Object.hasOwn(fields, 'readSequenceConstruction') ? 1 : 0) ||
          Object.hasOwn(fields, 'requestConstruction') && Object.hasOwn(fields, 'preservingRequestConstruction') || ['installation', 'limits', 'columnCount'].some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledSourceReaderSelection');
      if (nodeTypes.isProxy(fields.limits.value ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const installation = fields.installation.value, runtimeBundleCid = selected.get(installation);
      if (runtimeBundleCid === undefined) fail('ForeignInstalledHostServiceInstallation');
      const selection = requireSourceConstructor(services, installation, fields);
      const columns = fields.columnCount.value;
      const preservingResponse = Object.hasOwn(fields, 'preservingRequestConstruction');
      // Trusted Source construction selects its actual representation. Program
      // DATA and Account policy do not choose a cheaper quote or another mode.
      const cursorProgress = Object.hasOwn(fields, 'cursorProgress');
      if (cursorProgress && (!Object.hasOwn(fields.cursorProgress, 'value') ||
          fields.cursorProgress.value !== true ||
          preservingResponse || Object.hasOwn(fields, 'readSequenceConstruction'))) {
        fail('InvalidInstalledSourceReaderSelection');
      }
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
      // The selected Source supplies its SAME complete Core quote and original
      // occurrence declaration. This is retained construction DATA, not a grant,
      // owner, profile knob or a recipe selected again by registration here.
      let readSequenceConstruction;
      if (Object.hasOwn(fields, 'readSequenceConstruction')) {
        const field = fields.readSequenceConstruction;
        if (!Object.hasOwn(field, 'value') || field.value === null || typeof field.value !== 'object' ||
            nodeTypes.isProxy(field.value) || !Object.isFrozen(field.value)) fail('InvalidInstalledSourceSequenceConstruction');
        const original = Object.getOwnPropertyDescriptors(field.value);
        const names = Reflect.ownKeys(original);
        if (names.some(name => !['capacity', 'originalLimits', 'sequence', 'sequences', 'maxRequestBytes', 'maxQueryBytes'].includes(name)) ||
            names.some(name => !Object.hasOwn(original[name], 'value')) ||
            !Object.hasOwn(original, 'capacity') || !Object.hasOwn(original, 'originalLimits') ||
            Object.hasOwn(original, 'sequence') === Object.hasOwn(original, 'sequences') ||
            original.capacity.value === undefined || original.capacity.value === null ||
            original.originalLimits.value === null || typeof original.originalLimits.value !== 'object' ||
            nodeTypes.isProxy(original.originalLimits.value) || !Object.isFrozen(original.originalLimits.value)) {
          fail('InvalidInstalledSourceSequenceConstruction');
        }
        const occurrences = (original.sequence ?? original.sequences).value;
        if (occurrences === null || typeof occurrences !== 'object' || nodeTypes.isProxy(occurrences) ||
            !Object.isFrozen(occurrences) || original.maxRequestBytes !== undefined &&
            (!Number.isSafeInteger(original.maxRequestBytes.value) || original.maxRequestBytes.value < 1 ||
              original.maxRequestBytes.value > 2147483647) || original.maxQueryBytes !== undefined &&
            (!Number.isSafeInteger(original.maxQueryBytes.value) || original.maxQueryBytes.value < 1 ||
              original.maxQueryBytes.value > 2147483647)) fail('InvalidInstalledSourceSequenceConstruction');
        readSequenceConstruction = field.value;
      }
      const profile = sourceProfiles.get(selection);
      const supplied = Object.getOwnPropertyDescriptors(fields.limits.value ?? {});
      // A scalar method/body allowance cannot replace the original request
      // constructor or a complete selected sequence. The retired query/property
      // projection never admitted its 21-field quote through the real 16-field
      // JSON constructor, and its managed-read entry was refused as unfunded.
      if (Object.hasOwn(supplied, 'maxRequestBytes') || Object.hasOwn(supplied, 'maxQueryBytes')) fail('InstalledSourceReaderRequestCapacityUnavailable');
      if (requestConstruction !== undefined && readSequenceConstruction !== undefined) {
        fail('InstalledSourceReaderRequestConstructionChanged');
      }
      const names = [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'];
      if (names.some(name => !Object.hasOwn(supplied[name] ?? {}, 'value') ||
          !Number.isSafeInteger(supplied[name].value) || supplied[name].value < 1 || supplied[name].value > 2147483647)) {
        fail('InvalidInstalledSourceReaderLimits');
      }
      if (profile !== undefined && (profile.runtimeBundleCid !== runtimeBundleCid ||
          columns > profile.value.maxColumns || names.some(name =>
            supplied[name].value > profile.value[name]))) {
        fail('InstalledSourceReaderImplementationBoundsExceeded');
      }
      const selectedRequestCapacity = cursorProgress ? cursorSourceRequestCapacity
        : preservingResponse ? preservingSourceRequestCapacity : sourceRequestCapacity;
      const selectedPageCapacity = cursorProgress ? cursorSourceCapacity : sourceCapacity;
      if (typeof sourcePolicy !== 'function' || readSequenceConstruction === undefined &&
          typeof (requestConstruction === undefined ? selectedPageCapacity : selectedRequestCapacity) !== 'function') fail('InstalledSourceReaderRuntimeUnavailable');
      const policy = Reflect.apply(sourcePolicy, moon, []);
      // The Values cells-per-row default is not Source schema eligibility.
      // Source columns retain their declared bounds and typed RowRun capacity;
      // this bridge still requires the original Core Int representation.
      if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > 2147483647 ||
        supplied.maxSecretBytes.value > policy[0]) fail('InstalledSourceReaderPolicyUnavailable');
      const limits = Object.freeze(Object.fromEntries(names.map(name => [name, supplied[name].value])));
      const previous = sourceImplementations.get(selection);
      if (previous !== undefined) {
        if (previous.requestConstruction !== requestConstruction || previous.preservingResponse !== preservingResponse ||
            previous.cursorProgress !== cursorProgress ||
            previous.readSequenceConstruction !== readSequenceConstruction ||
            previous.runtimeBundleCid !== runtimeBundleCid || previous.columns !== columns ||
            names.some(name => previous.value.limits[name] !== limits[name])) fail('InstalledSourceReaderSelectionChanged');
        return previous.value;
      }
      const capacity = readSequenceConstruction !== undefined ? readSequenceConstruction.capacity
        : Reflect.apply(requestConstruction === undefined ? selectedPageCapacity : selectedRequestCapacity, moon,
          [installedJsonSourceReaderLimitNames.map(name => limits[name]), columns, limits.maxSecretBytes,
            ...(requestConstruction === undefined ? [] : [requestConstruction.capacity])]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      const value = Object.freeze({capacity, limits, runAcquisitionLimits: Object.freeze({
        maxBindings: policy[1], maxSecretBytes: limits.maxSecretBytes})});
      current(); sourceImplementations.set(selection, Object.freeze({runtimeBundleCid, columns, readSequenceConstruction, requestConstruction, preservingResponse, cursorProgress, value}));
      return value;
    },
    createSourceReader(options) {
      current();
      if (publicationOnly) fail('InstalledEffectPublicationSourceUnavailable');
      if (nodeTypes.isProxy(options ?? {})) fail('InvalidInstalledSourceReaderSelection');
      const fields = Object.getOwnPropertyDescriptors(options ?? {});
      const standard = Object.hasOwn(fields, 'preparePageReader');
      const managedSequence = Object.hasOwn(fields, 'prepareReadSequence');
      if (standard === managedSequence) fail('InvalidInstalledSourceReaderSelection');
      const readerField = managedSequence ? 'prepareReadSequence' : 'preparePageReader';
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
      if (managedSequence && implementation.readSequenceConstruction === undefined) fail('InstalledSourceReaderReadChildCapacityUnavailable');
      if (implementation.requestConstruction !== undefined && !standard) fail('InstalledSourceReaderStandardSelectionRequired');
      if (implementation.readSequenceConstruction !== undefined && !managedSequence) fail('InstalledSourceReaderSequenceSelectionRequired');
      const originalSite = installedRowCredentialOperationSite(fields.site.value.credential);
      const limits = implementation.value.limits, sequence = implementation.readSequenceConstruction;
      const maxQueryBytes = sequence !== undefined && Object.hasOwn(sequence, 'maxQueryBytes')
        ? sequence.maxQueryBytes : undefined;
      const constructor = sourceContexts.get(selection);
      if (constructor?.scope.reader !== undefined) fail('InstalledSourceReaderAlreadyConstructed');
      // Optional separately bound Resources are declared by this SAME complete
      // native sequence recipe. Names bound construction; only each original
      // Site-issued decision/grant authorizes the actual child.
      let resourceChildren;
      const sequences = sequence?.sequences === undefined ? [sequence?.sequence]
        : Object.values(sequence.sequences);
      for (const originalSequence of sequences) {
        for (const child of originalSequence?.children ?? []) {
          const resource = Object.getOwnPropertyDescriptor(child, 'resource');
          if (resource === undefined) continue;
          if (!Object.hasOwn(resource, 'value') || typeof resource.value !== 'string' || resource.value.length === 0) {
            fail('InvalidInstalledSourceResourceChildren');
          }
          resourceChildren ??= [];
          if (!resourceChildren.includes(resource.value)) resourceChildren.push(resource.value);
        }
      }
      if (resourceChildren !== undefined) Object.freeze(resourceChildren);
      const factory = createInstalledCredentialSourceReader({capacity: implementation.value.capacity,
        originalSite, [readerField]: fields[readerField].value, assertCurrent: current,
        ...(resourceChildren === undefined ? {} : {resourceChildren}),
        maxResponses: limits.maxPages,
        ...(standard ? {operation: fields.operation.value,
          ...(implementation.requestConstruction === undefined ? {} : {maxRequestBytes:implementation.requestConstruction.maxRequestBytes}),
          maxResponseBytes: limits.maxResponseBytes, maxTotalResponseBytes: limits.maxTotalResponseBytes,
          maxSecretBytes: limits.maxSecretBytes} : {}),
        ...(managedSequence ? {maxResponseBytes: limits.maxResponseBytes,
          ...(maxQueryBytes === undefined ? {} : {maxQueryBytes}),
          ...(sequence?.maxRequestBytes !== undefined ? {maxRequestBytes:sequence.maxRequestBytes}
            : {}),
          maxTotalResponseBytes: limits.maxTotalResponseBytes} : {})});
      if (constructor !== undefined) {
        const all = BigInt(limits.maxPages) * BigInt(limits.maxResponseBytes);
        const prefix = BigInt(limits.maxTotalResponseBytes) + BigInt(limits.maxResponseBytes);
        constructor.scope.reader = factory;
        constructor.scope.readerDemand = Object.freeze({nested: false,
          ...(sequence?.sequence === undefined ? {} : {sequence:sequence.sequence}),
          ...(sequence?.sequences === undefined ? {} : {sequences:sequence.sequences}),
          responses: limits.maxPages, queryPages: limits.maxPages,
          propertyPages: undefined, propertyOccurrences: undefined,
          maxResponseBytes: limits.maxResponseBytes, maxNodes: limits.maxNodes, maxDepth: limits.maxDepth,
          maxRows: limits.maxRows, maxTotalRows: limits.maxTotalRows,
          transferUnitBytes: BigInt(limits.maxResponseBytes),
          transferBytes: sequence === undefined || all < prefix ? all : prefix});
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
        accountConstruction: installedAccountConstruction(services),
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
  const acquisitionContractsCapacity = moon.clientProgramRowSourceAcquisitionContractsConstructionCapacity;
  const prepareMapping = moon.clientProgramRowSourcePrepareMapping;
  const prepareUpdateMapping = moon.clientProgramRowSourcePrepareUpdateMapping;
  const prepareUpdateMappingCapacity = moon.clientProgramRowSourceUpdateMappingConstructionCapacity;
  installations.set(services, {selected, current, sites, siteInstallations, implementations,
    sourceImplementations, sourceProfiles, moon, root, principalId, initialPreparation, accountCurrent, restoreDeclaration, restoreAuthoredDeclaration, declarationJson,
    admitAcquisitionContracts, acquisitionContractsCapacity, prepareMapping, prepareUpdateMapping,
    prepareUpdateMappingCapacity});
  return services;
}

// Private Account facet on the SAME initial/continued Host material. A
// nominal/control scope is insufficient; this entrance requires the actual
// selected Core capacity retained by this installed service.
export function installedAccountConstruction(services) {
  const original = installations.get(services);
  // Standalone legacy installers have no original numeric carrier. Ordinary
  // Host construction always supplies its actual initialization preparation.
  if (original !== undefined && original.initialPreparation === undefined) return undefined;
  if (original === undefined || typeof original.accountCurrent !== 'function') fail('AccountConstructionUnavailable');
  original.accountCurrent();
  const material = sourceMaterial(original);
  if (material === undefined || material.capacity === undefined || material.input === undefined) fail('AccountConstructionUnavailable');
  return original.accountConstruction ??= createAccountConstruction({moon: original.moon,
    current: original.accountCurrent,
    prepareRead: () => original.moon.clientProgramPrepareInstalledAccountRead(material.capacity, material.input)});
}

export async function closeInstalledAccountConstruction(services) {
  const original = installations.get(services);
  if (original === undefined) fail('ForeignInstalledHostServices');
  return original.accountConstruction === undefined || await original.accountConstruction.close();
}
