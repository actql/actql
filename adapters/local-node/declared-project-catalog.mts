// Explicit model declarations only. This reader acquires no fixture records,
// credentials, permission, Source, Run, ContentRef or Effect approval.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import type {createDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {assertDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {resolve} from 'node:path';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceMapping} from '../host-node/installed-row-source-mapping.mjs';
import type {RowSourceMappingRuntime} from '../host-node/installed-row-source-mapping.mjs';
import {readBoundedConfigurationUtf8} from '../host-node/source-profile-json.mjs';
import {declaredProjectCatalogJsonParseConstructionGeometry,
  declaredProjectCatalogEntryHostConstructionGeometry,
  declaredProjectCatalogSavedInputArraysConstructionGeometry,
  declaredProjectCatalogSavedInputConstructionGeometry,
  declaredProjectCatalogScopeConstructionGeometry,
  declaredProjectCatalogFileFactsProjectionConstructionGeometry,
  declaredProjectCatalogPhysicalOverridesConstructionGeometry,
  declaredProjectCatalogMappingInputsConstructionGeometry,
  declaredProjectCatalogFinalDescriptorsConstructionGeometry,
  declaredProjectWritableInventoryConstructionGeometry,
  declaredFileReadProfileBindingConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';

type Inventory = ReturnType<typeof createDeclaredFileInstallationInventory>;
type Member = Awaited<ReturnType<Inventory['begin']>>;
type ConnectionOriginal = NonNullable<Parameters<Inventory['begin']>[0]>;
type CatalogOptions = Readonly<{
  directory?: string; catalogFile?: string; dataFile?: string; connections?: unknown;
  connectionOriginal?: ConnectionOriginal; assertCurrent?: () => unknown;
  openFile?: unknown; installationInventory?: Inventory;
}>;
type Quantity = Readonly<{nodes: bigint; text: bigint; wire: bigint}>;
type Geometry = Readonly<{retained: Quantity; workspace: Quantity}>;
type NativeValue = object & Readonly<{then?: never}>;
type Schema = Readonly<Record<string, Readonly<{type?: unknown; nullable?: unknown}>>>;
type View = Readonly<{
  resource: string; resource_kind: string; schema: Schema;
  request_schema?: unknown; facts?: unknown; acquisition?: unknown;
  resource_identity?: unknown; data_classification?: unknown;
}>;
type QueryAlias = Readonly<{name: string; resource: string; request?: object}>;
type DataBinding = Readonly<{resource: string; items_path: readonly string[]; key_path: readonly string[];
  primary_identity: string; schema?: Schema}>;
type FileBinding = Readonly<{
  listing_resource: string; content_resource: string; data_resource: string;
  identity_field: string; name_field: string; version_field: string; media_type_field: string;
  content_utf8_field: string; path_field?: string;
}>;
type WriteBase = Readonly<{
  resource: string; primary_identity: string;
  permission: string; observe_permission: string; approval: 'required'; aliases: readonly string[];
}>;
type UpdateWriteSpec = WriteBase & Readonly<{
  operation?: 'update'; writable_fields: readonly string[];
  update_fields?: readonly string[]; write_null_fields?: readonly string[];
}>;
type WriteSpec = UpdateWriteSpec | (WriteBase & Readonly<{operation: 'delete';
  writable_fields?: never; update_fields?: never; write_null_fields?: never}>);
type Entry = Readonly<{
  views: readonly View[]; query_aliases: readonly QueryAlias[]; data: readonly DataBinding[];
  writes?: readonly WriteSpec[]; file_bindings?: readonly FileBinding[];
}>;
type SavedView = {
  resource: string; resource_kind: string; schema_wire: string; schema_cid?: string;
  request_schema_wire?: string; facts_wire?: string; acquisition_wire?: string; resource_identity_wire?: string;
};
type SavedInput = Readonly<{
  wire: string; resources: readonly string[]; kinds: readonly string[]; schemas: readonly string[];
  requests: readonly (string | undefined)[]; facts: readonly (string | undefined)[];
  acquisitions: readonly (string | undefined)[]; identities: readonly (string | undefined)[];
}>;
type FileProfileFields = [identity: string, name: string, version: string, mediaType: string,
  contentUtf8: string, path: string | undefined, itemsPath: readonly string[], keyPath: readonly string[]];
type CatalogBindings = Readonly<{
  clientProjectCatalogAdmit(wire: string): unknown;
  clientProjectCatalogAdmissionConstructionCapacity(wire: string): unknown;
  clientProjectCatalogCount(catalog: unknown): number;
  clientProjectCatalogName(catalog: unknown, index: number): string | undefined;
  clientProjectCatalogEntryOriginalJson(catalog: unknown, index: number): string | undefined;
  clientProjectCatalogRelationDeclarationInput(catalog: unknown, index: number): unknown;
  clientProjectCatalogRelationDeclarationConstructionCapacity(catalog: unknown, index: number): unknown;
  clientProjectConnectionsCount(connections: unknown): number;
  clientProjectConnectionsName(connections: unknown, index: number): string | undefined;
  clientProjectConnectionsConnector(connections: unknown, index: number): string | undefined;
  clientProgramRowSourceRestoreRelationDeclaration(connector: string, registration: string, revision: string,
    views: string, expectedCatalogCid: string | undefined): unknown;
  clientProgramRowSourceDeclarationJson(declaration: unknown): string | undefined;
  clientProgramInstalledSourceConstructionCapacity(retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
    workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint): unknown;
  clientProgramRelationRestoreConstructionCapacity(connector: string, registration: string, revision: string,
    wire: string, resources: SavedInput['resources'], kinds: SavedInput['kinds'], schemas: SavedInput['schemas'],
    requests: SavedInput['requests'], facts: SavedInput['facts'], acquisitions: SavedInput['acquisitions'],
    identities: SavedInput['identities']): unknown;
  clientProgramRowSourceFileReadProfileConstructionCapacity(declaration: unknown, physical: unknown,
    ...fields: [...FileProfileFields, priorProfiles: number]): unknown;
  clientProgramRowSourceBindFileReadProfile(declaration: unknown, resource: string, physical: unknown,
    physicalResource: string, ...fields: FileProfileFields): unknown;
  clientProgramComposeInstalledSourceConstructionCapacity(quantity: unknown, providers: readonly unknown[]): unknown;
}>;
type Runtime = Partial<CatalogBindings> & RowSourceMappingRuntime;
type Restored = Readonly<Partial<ReturnType<Member['prepareNativeDeclaration']>>>;
type EffectPrepared = ReturnType<Member['prepareMappings']>;
type PhysicalBinding = Readonly<{
  resource: string; declaration: unknown; itemsPath: readonly string[]; keyPath: readonly string[];
  primaryIdentity: string; schema: Schema; writableFields: readonly string[];
}>;
type PublishedWrite = Readonly<WriteSpec & {mappingWire: string}>;
type WritableInventorySource = Readonly<{
  catalogue: Readonly<{connection: string}>;
  writes: readonly Readonly<{resource: string; operation?: WriteSpec['operation']; mappingWire: string}>[];
  physical: readonly Readonly<{resource: string; itemsPath: readonly string[]; schema: object}>[];
  effectPrepared?: Readonly<{mappings?: readonly Readonly<{resource: string; body: string}>[]}>;
}>;
type CatalogSource = Readonly<{
  declaration: unknown; wire: string; physical: readonly PhysicalBinding[]; writes: readonly PublishedWrite[];
  fileBindings: readonly FileBinding[]; scopeCid: string; sourceMember?: Member; sourcePrepared: Restored;
  effectMember?: Member; effectPrepared?: EffectPrepared;
  catalogue: Readonly<{
    connection: string; connectorId: string; provider: string; registration: string; revision: string;
    views: readonly Readonly<SavedView>[]; queryAliases: readonly QueryAlias[];
    updateAliases: readonly Readonly<{name: string; resource: string}>[];
  }>;
}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !value.includes('\0') && Buffer.byteLength(value) <= 4096;
const closed = (value: unknown, required: readonly string[], optional: readonly string[] = []) => object(value) &&
  required.every(name => Object.hasOwn(value, name)) &&
  Object.keys(value).every(name => required.includes(name) || optional.includes(name));
const list = (value: unknown): value is readonly unknown[] => Array.isArray(value) && value.length <= 128;
const names = (value: unknown): value is readonly string[] => list(value) && value.every(text) && new Set(value).size === value.length;
const path = (value: unknown): value is readonly string[] => list(value) && value.every(text) && value.length > 0 && value.length <= 16;
const freeze = <Value,>(value: Value): Value => {
  if (object(value) || Array.isArray(value)) {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};
const invalid: () => never = () => fail('InvalidInstalledMockCatalog');

type WritePermission = Pick<WriteBase, 'permission' | 'approval'>;
type ResourceWriteFacts = {resource: string; primary_identity: string;
  update?: WritePermission & {fields: readonly string[]}; delete?: WritePermission};
function writeFacts(specs: readonly WriteSpec[]) {
  const writes: ResourceWriteFacts[] = [];
  for (const spec of specs) {
    let facts = writes.find(value => value.resource === spec.resource);
    if (facts === undefined) {
      facts = {resource: spec.resource, primary_identity: spec.primary_identity};
      writes.push(facts);
    }
    const {permission, approval} = spec;
    if (spec.operation === 'delete') {
      if (facts.delete !== undefined) invalid();
      facts.delete = {permission, approval};
    } else {
      if (facts.update !== undefined) invalid();
      facts.update = {fields: spec.writable_fields, permission, approval};
    }
  }
  return {writes};
}
const noSources = Object.freeze([]);
const updateSources = (spec: UpdateWriteSpec) => Object.freeze((spec.update_fields ?? spec.writable_fields).map(name => Object.freeze({
  target: name, field: name, null_behavior: spec.write_null_fields?.includes(name) ? 'write_null' : 'reject',
})));

// The Common catalog parser first admits the exact bounded original, including
// duplicate keys and Unicode. Only its original entry spans are projected here.
function capturedCatalogOptions(options: unknown): CatalogOptions {
  if (!object(options) || nodeTypes.isProxy(options)) fail('ForeignDeclaredFileInstallation');
  const captured: Record<string, unknown> = {};
  for (const name of ['directory', 'catalogFile', 'dataFile', 'connections',
    'connectionOriginal', 'assertCurrent', 'openFile', 'installationInventory']) {
    const field = Object.getOwnPropertyDescriptor(options, name);
    if (field !== undefined && !Object.hasOwn(field, 'value')) fail('ForeignDeclaredFileInstallation');
    captured[name] = field?.value;
  }
  return Object.freeze(captured) as CatalogOptions;
}

export async function loadDeclaredProjectCatalog(moon: Runtime, options: CatalogOptions) {
  options = capturedCatalogOptions(options);
  assertDeclaredFileInstallationInventory(options?.installationInventory, moon,
    options?.connectionOriginal?.project);
  return projectDeclaredCatalog(moon, options);
}

// Metadata-only inspection is explicit. Its result has no issued installation
// members or prepared Source/Effect tuples and cannot enter physical factories.
export async function inspectDeclaredProjectCatalog(moon: Runtime, options: CatalogOptions) {
  options = capturedCatalogOptions(options);
  if (options?.installationInventory !== undefined) fail('ForeignDeclaredFileInstallation');
  return projectDeclaredCatalog(moon, options);
}

async function projectDeclaredCatalog(moon: Runtime, {directory, catalogFile, dataFile,
  connections, connectionOriginal, assertCurrent, openFile, installationInventory}: CatalogOptions) {
  if (!text(catalogFile) || !text(dataFile) || !text(directory) || typeof assertCurrent !== 'function') {
    fail('InstalledMockCatalogueUnavailable');
  }
  const methods = Object.fromEntries((['clientProjectCatalogAdmit', 'clientProjectCatalogCount',
    'clientProjectCatalogName', 'clientProjectCatalogEntryOriginalJson',
    'clientProjectCatalogRelationDeclarationInput',
    'clientProjectCatalogRelationDeclarationConstructionCapacity',
    'clientProjectConnectionsCount', 'clientProjectConnectionsName', 'clientProjectConnectionsConnector',
    'clientProgramRowSourceRestoreRelationDeclaration', 'clientProgramRowSourceDeclarationJson',
    ...(installationInventory === undefined ? [] :
      ['clientProgramInstalledSourceConstructionCapacity', 'clientProgramRelationRestoreConstructionCapacity'])] as const)
    .map(name => [name, moon?.[name as keyof CatalogBindings]]));
  if (Object.values(methods).some(value => typeof value !== 'function')) fail('InstalledProjectRuntimeUnavailable');
  const fileMethods = Object.freeze(Object.fromEntries(([
    'clientProgramRowSourceFileReadProfileConstructionCapacity',
    'clientProgramRowSourceBindFileReadProfile',
    'clientProgramComposeInstalledSourceConstructionCapacity',
  ] as const).map(name => [name, moon?.[name]])));
  const call = <Name extends keyof CatalogBindings>(name: Name, ...args: Parameters<CatalogBindings[Name]>) =>
    Reflect.apply(methods[name] as (...args: Parameters<CatalogBindings[Name]>) =>
      ReturnType<CatalogBindings[Name]>, moon, args);
  const fileCall = <Name extends keyof CatalogBindings>(name: Name, ...args: Parameters<CatalogBindings[Name]>) =>
    Reflect.apply(fileMethods[name] as (...args: Parameters<CatalogBindings[Name]>) =>
      ReturnType<CatalogBindings[Name]>, moon, args);
  if (installationInventory !== undefined && connectionOriginal?.connections !== connections) {
    fail('ForeignDeclaredFileInstallation');
  }
  const inputStage = <Value extends NativeValue>(member: Member | undefined, geometry: () => Geometry,
    project: () => Value, metadata = false): Value => {
    if (installationInventory === undefined) return project();
    const projection = Object.freeze({capacity() {
      const {retained, workspace} = geometry();
      return checked(call('clientProgramInstalledSourceConstructionCapacity',
        retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire));
    }, project});
    return metadata ? installationInventory.prepareMetadataInput(projection)
      : member!.prepareNativeInput(projection) as Value;
  };
  // Called only inside a funded JS stage. These are the actual original
  // Strings and parallel arrays consumed by the one native restore quote.
  const savedInput = (selected: readonly Readonly<SavedView>[], originalWire?: string): SavedInput => Object.freeze({wire: originalWire ?? wire({views: selected}),
    resources: selected.map(view => view.resource), kinds: selected.map(view => view.resource_kind),
    schemas: selected.map(view => view.schema_wire), requests: selected.map(view => view.request_schema_wire),
    facts: selected.map(view => view.facts_wire), acquisitions: selected.map(view => view.acquisition_wire),
    identities: selected.map(view => view.resource_identity_wire)});
  const restoreInput = (member: Member | undefined, connectorId: string, registration: string, revision: string,
    input: SavedInput, final = false, originalOnly = false): Restored => {
    const project = () => {
      const declaration = checked(call('clientProgramRowSourceRestoreRelationDeclaration',
        connectorId, registration, revision, input.wire, undefined));
      // Final installed export belongs to prepareNativeDeclaration. Intermediate
      // File/physical exports are each covered by this invocation's own quote.
      if (originalOnly || final && installationInventory !== undefined) return Object.freeze({declaration});
      const exported = call('clientProgramRowSourceDeclarationJson', declaration);
      if (typeof exported !== 'string') fail('InvalidHostRuntimeResult');
      return Object.freeze({declaration, wire: exported});
    };
    if (installationInventory === undefined) return project();
    const projection = Object.freeze({capacity() {
      const quantity = call('clientProgramRelationRestoreConstructionCapacity',
        connectorId, registration, revision, input.wire, input.resources, input.kinds,
        input.schemas, input.requests, input.facts, input.acquisitions, input.identities);
      if (quantity == null) fail('InstalledSourceDeclarationCapacityUnavailable');
      return quantity;
    }, project});
    return final ? member!.prepareNativeDeclaration(projection) : member!.prepareNativeInput(projection);
  };
  assertCurrent();
  const catalogPath = resolve(directory, catalogFile);
  const originalWire = installationInventory === undefined
    ? await readBoundedConfigurationUtf8(catalogPath,
      {maxBytes: 65536, ...(openFile === undefined ? {} : {openFile})})
    : await installationInventory.readMetadataUtf8(catalogPath, 65536);
  assertCurrent();
  const admit = () => checked(call('clientProjectCatalogAdmit', originalWire)) as NativeValue;
  const original = installationInventory === undefined ? admit()
    : installationInventory.prepareMetadataInput<NativeValue>(Object.freeze({
      capacity() {
        const quote = moon.clientProjectCatalogAdmissionConstructionCapacity;
        if (typeof quote !== 'function') fail('InstalledProjectRuntimeUnavailable');
        const quantity = Reflect.apply(quote, moon, [originalWire]);
        if (quantity == null) fail('InstalledProjectMetadataCapacityUnavailable');
        return quantity;
      }, project: admit,
    }));
  const count = call('clientProjectCatalogCount', original);
  const connectionCount = call('clientProjectConnectionsCount', connections);
  if (!Number.isSafeInteger(count) || count < 1 || count > 128 ||
      !Number.isSafeInteger(connectionCount) || connectionCount !== count) invalid();
  for (let index = 0; index < connectionCount; index++) {
    const name = call('clientProjectConnectionsName', connections, index);
    const connector = call('clientProjectConnectionsConnector', connections, index);
    if (!text(name) || !text(connector)) invalid();
    for (let previous = 0; previous < index; previous++) {
      if (call('clientProjectConnectionsName', connections, previous) === name) invalid();
    }
  }
  const sources: CatalogSource[] = [], aliases = new Set<string>(), updates = new Set<string>();
  for (let index = 0; index < count; index++) {
    const connection = call('clientProjectCatalogName', original, index)!;
    const entryWire = call('clientProjectCatalogEntryOriginalJson', original, index);
    let connectionIndex = -1, provider: string | undefined;
    for (let selected = 0; selected < connectionCount; selected++) {
      if (call('clientProjectConnectionsName', connections, selected) !== connection) continue;
      connectionIndex = selected;
      provider = call('clientProjectConnectionsConnector', connections, selected);
    }
    if (connectionIndex < 0 || typeof entryWire !== 'string' ||
        sources.some(source => source.catalogue.connection === connection)) invalid();
    const connectorId = connection, registration = 'declared_file', revision = registration + '/0.1';
    const sourceMember = installationInventory === undefined ? undefined
      : await installationInventory.begin(connectionOriginal, connectionIndex, 'source');
    const parsed = inputStage(sourceMember,
      () => declaredProjectCatalogJsonParseConstructionGeometry(entryWire),
      () => Object.freeze({entry: freeze(JSON.parse(entryWire) as Entry)}));
    const selected = inputStage(sourceMember,
      () => declaredProjectCatalogEntryHostConstructionGeometry(parsed.entry), () => {
      const entry = parsed.entry;
      if (!closed(entry, ['views', 'query_aliases', 'data'], ['writes', 'file_bindings']) ||
          !list(entry.views) || entry.views.length === 0 || !list(entry.query_aliases) ||
          !list(entry.data) || !list(entry.writes ?? []) || !list(entry.file_bindings ?? [])) invalid();
      const publicViews = new Map<string, View>();
      for (const view of entry.views) {
        if (!closed(view, ['resource', 'resource_kind', 'schema'],
          ['request_schema', 'facts', 'acquisition', 'resource_identity', 'data_classification']) ||
            !text(view.resource) || !text(view.resource_kind) || !object(view.schema) ||
            publicViews.has(view.resource)) invalid();
        publicViews.set(view.resource, view);
      }
      const queryAliases = entry.query_aliases.map(alias => {
        if (!closed(alias, ['name', 'resource'], ['request']) ||
            Object.hasOwn(alias, 'request') && !object(alias.request) ||
            !text(alias.name) || !publicViews.has(alias.resource) ||
            aliases.has(alias.name)) invalid();
        aliases.add(alias.name); return {...alias};
    });
    const data = new Map<string, DataBinding & Readonly<{schema: Schema}>>();
    for (const binding of entry.data) {
      if (!closed(binding, ['resource', 'items_path', 'key_path', 'primary_identity'], ['schema']) ||
          !publicViews.has(binding.resource) || data.has(binding.resource) ||
          !path(binding.items_path) || !path(binding.key_path) || !text(binding.primary_identity) ||
          binding.schema !== undefined && !object(binding.schema)) invalid();
      const schema = binding.schema ?? publicViews.get(binding.resource)!.schema;
      if (!Object.hasOwn(schema, binding.primary_identity) ||
          schema[binding.primary_identity]?.type !== 'string' || schema[binding.primary_identity]?.nullable !== false) invalid();
      data.set(binding.resource, {...binding, schema});
    }
    const bound = new Set<string>(), fileBindings: FileBinding[] = [];
    for (const binding of entry.file_bindings ?? []) {
      const required = ['listing_resource', 'content_resource', 'data_resource', 'identity_field',
        'name_field', 'version_field', 'media_type_field', 'content_utf8_field'] as const;
      if (!closed(binding, required, ['path_field']) || !required.every(name => text(binding[name])) ||
          binding.path_field !== undefined && !text(binding.path_field) ||
          !publicViews.has(binding.listing_resource) || !publicViews.has(binding.content_resource) ||
          !data.has(binding.data_resource) || binding.listing_resource === binding.content_resource ||
          bound.has(binding.listing_resource) || bound.has(binding.content_resource)) invalid();
      const physical = data.get(binding.data_resource)!;
      if (publicViews.get(binding.listing_resource)!.facts !== undefined ||
          publicViews.get(binding.content_resource)!.facts !== undefined) invalid();
      if (physical.primary_identity !== binding.identity_field || physical.schema === undefined) invalid();
      for (const name of ['identity_field', 'name_field', 'version_field', 'media_type_field', 'content_utf8_field'] as const) {
        const field = physical.schema[binding[name]];
        if (field?.type !== 'string' || field.nullable !== false) invalid();
      }
      if (binding.path_field !== undefined && physical.schema[binding.path_field]?.type !== 'string') invalid();
      bound.add(binding.listing_resource); bound.add(binding.content_resource);
      fileBindings.push({...binding});
    }
    for (const view of entry.views) {
      if (!data.has(view.resource) && !bound.has(view.resource)) invalid();
      if (data.has(view.resource) && Object.hasOwn(entry.data.find(value => value.resource === view.resource)!, 'schema') &&
          !fileBindings.some(value => value.data_resource === view.resource)) invalid();
    }
    const writeSpecs: WriteSpec[] = [];
    for (const spec of entry.writes ?? []) {
      if (!closed(spec, ['resource', 'primary_identity', 'permission', 'observe_permission', 'approval', 'aliases'],
        ['operation', 'writable_fields', 'write_null_fields', 'update_fields']) ||
          !data.has(spec.resource) || bound.has(spec.resource) ||
          !names(spec.aliases) || !spec.aliases.length || !text(spec.permission) || !text(spec.observe_permission) ||
          spec.approval !== 'required' || spec.primary_identity !== data.get(spec.resource)!.primary_identity) invalid();
      const operation = spec.operation ?? 'update';
      if (operation === 'delete') {
        if (Object.hasOwn(spec, 'writable_fields') || Object.hasOwn(spec, 'write_null_fields') ||
            Object.hasOwn(spec, 'update_fields')) invalid();
      } else if ((Object.hasOwn(spec, 'operation') && spec.operation !== 'update') ||
          !names(spec.writable_fields) || !spec.writable_fields.length) invalid();
      if (Object.hasOwn(spec, 'update_fields')) {
        const fields = spec.update_fields;
        if (!names(fields) || fields.length === 0) invalid();
        for (const name of fields) if (!spec.writable_fields!.includes(name)) invalid();
      }
      if (Object.hasOwn(spec, 'write_null_fields') &&
          (!list(spec.write_null_fields) || !spec.write_null_fields.every((name, index, fields) =>
            spec.writable_fields!.includes(name as string) && fields.indexOf(name) === index))) invalid();
      for (const alias of spec.aliases) {if (updates.has(alias)) invalid(); updates.add(alias);}
      writeSpecs.push(spec);
    }
    return Object.freeze({entry, publicViews, queryAliases,
      data, fileBindings, writeSpecs});
    });
    const {entry, publicViews, queryAliases, data, fileBindings, writeSpecs} = selected;
    const projection = Object.freeze({capacity() {
      const quantity = call('clientProjectCatalogRelationDeclarationConstructionCapacity', original, index);
      if (quantity == null) fail('InstalledSourceDeclarationCapacityUnavailable');
      return quantity;
    }, project() {
      return Object.freeze({wire: checked(call('clientProjectCatalogRelationDeclarationInput', original, index)) as string});
    }});
    const {wire: projectedWire} = installationInventory === undefined ? projection.project()
      : sourceMember!.prepareNativeInput(projection) as ReturnType<typeof projection.project>;
    // Existing restore geometry requires exact parallel Strings, and File
    // profile derivation uses saved view descriptors. This conversion is real,
    // separately funded and retained; never cast a JS object into MoonBit Json.
    const {views} = inputStage(sourceMember,
      () => declaredProjectCatalogJsonParseConstructionGeometry(projectedWire),
      () => Object.freeze({views: freeze(JSON.parse(projectedWire).views as readonly SavedView[])}));
    const dataPath = resolve(directory, dataFile);
    const {scopeCid} = inputStage(sourceMember,
      () => declaredProjectCatalogScopeConstructionGeometry(connection, provider!, dataPath, originalWire),
      () => Object.freeze({scopeCid: cid({connection, connector: provider!, dataPath, catalog: originalWire})}));
    let finalViews = views;
    let finalInput = inputStage(sourceMember,
      () => declaredProjectCatalogSavedInputArraysConstructionGeometry(finalViews),
      () => savedInput(finalViews, projectedWire));
    if (fileBindings.length) {
      const initialDeclaration = restoreInput(sourceMember, connectorId, registration, revision, finalInput);
      const {initial} = inputStage(sourceMember,
        () => declaredProjectCatalogJsonParseConstructionGeometry(initialDeclaration.wire!),
        () => Object.freeze({initial: freeze(JSON.parse(initialDeclaration.wire!) as {views: readonly {resource: string; carrier_schema_cid: string}[]})}));
      const facts = inputStage(sourceMember,
        () => declaredProjectCatalogFileFactsProjectionConstructionGeometry(entry, initial, scopeCid), () => {
        const factViews = views.map(view => ({...view}));
        for (const binding of fileBindings) {
          const versionCid = cid({scope: scopeCid, physical: data.get(binding.data_resource),
            version_field: binding.version_field, representation: 'exact_stored_bytes'});
          const listing = factViews.find(view => view.resource === binding.listing_resource)!;
          const content = factViews.find(view => view.resource === binding.content_resource)!;
          // Existing File contracts, derived from actual declared carrier CIDs.
          // These are static capability facts, not a current grant or reader.
          listing.facts_wire = wire({file_listing: {version: 'actql-file-list/0.1', kind: 'file_listing',
            selectable: [], allow_unfiltered_listing: true, admitted_scope_contract_cid: scopeCid,
            listing_schema_contract_cid: initial.views.find(view => view.resource === binding.listing_resource)!.carrier_schema_cid,
            version_capability: {contract_cid: versionCid, required_nonnull: true},
            max_listing_items: 100, max_examined_items: 100, max_listing_pages: 1, max_request_attempts: 1,
            max_listing_bytes: 1048576, max_listing_duration_ms: 30000, maximum_path_length: 4096}});
          content.facts_wire = wire({file_content: {version: 'actql-file-content/0.1', kind: 'file_content',
            admitted_scope_contract_cid: scopeCid,
            content_schema_contract_cid: initial.views.find(view => view.resource === binding.content_resource)!.carrier_schema_cid,
            version_capability: {contract_cid: versionCid, required_nonnull: true}, representation: 'exact_stored_bytes'},
            lookup_capacity: {version: 'actql-lookup-capacity/0.1', completeness: 'complete_per_requested_key',
              max_rows_per_key: 1, max_pages_per_request: 1, max_response_bytes_per_page: 1048576}});
        }
        return Object.freeze({views: freeze(factViews)});
      });
      finalViews = facts.views;
      finalInput = inputStage(sourceMember,
        () => declaredProjectCatalogSavedInputConstructionGeometry(finalViews),
        () => savedInput(finalViews));
    }
    const overrideCount = entry.data.reduce((count, binding) => count + (binding.schema === undefined ? 0 : 1), 0);
    const overrideInputs = overrideCount === 0 ? undefined : inputStage(sourceMember,
      () => declaredProjectCatalogPhysicalOverridesConstructionGeometry(entry, overrideCount), () => {
      const overrides = new Map<string, unknown>();
      for (const binding of data.values()) {
        if (entry.data.find(value => value.resource === binding.resource)!.schema === undefined) continue;
        overrides.set(binding.resource, savedInput([{resource: binding.resource,
          resource_kind: publicViews.get(binding.resource)!.resource_kind,
          schema_wire: wire(binding.schema), schema_cid: cid(binding.schema),
          facts_wire: wire({relation_keys: {candidate_keys: [[binding.primary_identity]]}})}]));
      }
      return overrides;
    });
    // Native input closes once the final declaration is prepared. Every
    // independent physical override must therefore be restored first.
    if (overrideInputs !== undefined) for (const [resource, input] of overrideInputs) {
      overrideInputs.set(resource, restoreInput(sourceMember, connectorId,
        registration + '_data', registration + '_data/0.1', input as SavedInput).declaration);
    }
    let sourcePrepared: Restored;
    if (fileBindings.length === 0) {
      sourcePrepared = restoreInput(sourceMember, connectorId, registration, revision, finalInput, true);
    } else {
      if (Object.values(fileMethods).some(method => typeof method !== 'function')) {
        fail('InstalledFileReadProfileUnavailable');
      }
      // Restore ONCE under the existing Source, retaining that typed original
      // before its profile constructor. No intermediate declaration export.
      const pending = restoreInput(sourceMember, connectorId, registration, revision, finalInput, false, true);
      const argumentsFor = (binding: FileBinding): [physical: unknown, ...fields: FileProfileFields] => {
        const physical = data.get(binding.data_resource)!;
        return [overrideInputs?.get(binding.data_resource) ?? pending.declaration,
          binding.identity_field, binding.name_field, binding.version_field,
          binding.media_type_field, binding.content_utf8_field, binding.path_field,
          physical.items_path, physical.key_path];
      };
      const projection = Object.freeze({
        capacity() {
          // The existing declared-Catalog caller inventory owns its fixed
          // argument vectors and descriptor loop. Native quotes own the SAME
          // actual declaration/profile bodies, not file or wire policy limits.
          const geometry = declaredFileReadProfileBindingConstructionGeometry(fileBindings.length);
          let quantity = checked(call('clientProgramInstalledSourceConstructionCapacity',
            geometry.retained.nodes, geometry.retained.text, geometry.retained.wire,
            geometry.workspace.nodes, geometry.workspace.text, geometry.workspace.wire));
          for (const [index, binding] of fileBindings.entries()) {
            const provider = fileCall('clientProgramRowSourceFileReadProfileConstructionCapacity',
              pending.declaration, ...argumentsFor(binding), index);
            quantity = checked(fileCall('clientProgramComposeInstalledSourceConstructionCapacity', quantity, [provider]));
          }
          return quantity;
        },
        project() {
          let declaration = pending.declaration;
          for (const binding of fileBindings) {
            const [physical, ...fields] = argumentsFor(binding);
            declaration = checked(fileCall('clientProgramRowSourceBindFileReadProfile',
              declaration, binding.content_resource, physical, binding.data_resource, ...fields));
          }
          return Object.freeze({declaration});
        },
      });
      if (installationInventory === undefined) {
        const {declaration} = projection.project();
        sourcePrepared = Object.freeze({declaration, wire: call('clientProgramRowSourceDeclarationJson', declaration)});
      } else sourcePrepared = sourceMember!.prepareNativeDeclaration(projection);
    }
    const {declaration, wire: declarationWire} = sourcePrepared;
    if (typeof declarationWire !== 'string') fail('InvalidHostRuntimeResult');
    let effectMember: Member | undefined, effectPrepared: EffectPrepared | undefined, mappingOriginals: readonly unknown[];
    if (installationInventory === undefined) {
      // Explicit non-installed declaration diagnostic only. Installed startup
      // always uses the admitted Effect context and original guarded continuation.
      const writesJson = wire(writeFacts(writeSpecs));
      mappingOriginals = writeSpecs.map(spec => {
        if (spec.operation === 'delete') {
          return rowSourceMapping(moon, declaration, writesJson, spec.resource, noSources, 'delete').body;
        }
        return rowSourceMapping(moon, declaration, writesJson, spec.resource, updateSources(spec), 'update').body;
      });
    } else if (writeSpecs.length) {
      effectMember = await installationInventory.begin(connectionOriginal, connectionIndex, 'effect');
      const mappingInput = inputStage(effectMember,
        () => declaredProjectCatalogMappingInputsConstructionGeometry(entryWire, writeSpecs.length), () => {
        const writesJson = wire(writeFacts(writeSpecs));
        const mappings = Object.freeze(writeSpecs.map(spec => Object.freeze({resource: spec.resource,
          operation: spec.operation ?? 'update', sources: spec.operation === 'delete' ? noSources : updateSources(spec)})));
        return Object.freeze({writesJson, mappings});
      });
      effectMember.prepareBorrowedDeclaration(sourceMember);
      effectPrepared = effectMember.prepareMappings(mappingInput.writesJson, mappingInput.mappings);
      mappingOriginals = effectPrepared.mappings!;
    } else mappingOriginals = [];
    const source = inputStage<CatalogSource>(undefined,
      () => declaredProjectCatalogFinalDescriptorsConstructionGeometry(entry, declarationWire, mappingOriginals, count),
      () => {
      const physical: PhysicalBinding[] = [];
      for (const binding of data.values()) {
        physical.push(Object.freeze({resource: binding.resource,
          declaration: overrideInputs?.get(binding.resource) ?? declaration,
          itemsPath: Object.freeze(binding.items_path), keyPath: Object.freeze(binding.key_path),
          primaryIdentity: binding.primary_identity, schema: freeze(binding.schema), writableFields: Object.freeze([])}));
      }
      const writes = writeSpecs.map((spec, index) => {
        const mappingWire = installationInventory === undefined ? mappingOriginals[index]
          : (mappingOriginals[index] as {body: unknown}).body;
        if (typeof mappingWire !== 'string') fail('InvalidHostRuntimeResult');
        return freeze({...spec, mappingWire});
      });
      return Object.freeze({declaration, wire: declarationWire, physical: Object.freeze(physical),
        writes: Object.freeze(writes), fileBindings: freeze(fileBindings), scopeCid,
        sourceMember, sourcePrepared, effectMember, effectPrepared,
        catalogue: freeze({connection, connectorId, provider: provider!, registration, revision, views: finalViews,
          queryAliases, updateAliases: writes.flatMap(spec => spec.aliases.map(name => ({name, resource: spec.resource})))})});
    }, true);
    sources.push(source);
    assertCurrent();
  }
  // Retain the actual opaque declaration inventory once on the SAME metadata
  // owner. Model Graph selection borrows it; it never reconstructs Catalogs or
  // accepts a profile label/wire as an implementation binding.
  let fileReadDeclarations: readonly unknown[] | undefined;
  if (sources.some(source => source.fileBindings.length !== 0)) {
    const projection = Object.freeze({
      capacity() {
        const count = BigInt(sources.length);
        return checked(call('clientProgramInstalledSourceConstructionCapacity',
          6n + count, 0n, 0n, 2n + count, 0n, 0n));
      },
      project: () => Object.freeze(sources.map(source => source.declaration)),
    });
    fileReadDeclarations = installationInventory === undefined ? projection.project()
      : installationInventory.prepareMetadataInput(projection);
  }
  const writables = inputStage(undefined,
    () => declaredProjectWritableInventoryConstructionGeometry(sources),
    () => projectDeclaredProjectWritableInventory(sources), true);
  return Object.freeze({original, originalWire, sources: Object.freeze(sources), writables, fileReadDeclarations});
}

// Post-admission metadata projection only. The installing caller must reserve
// its complete geometry before entry; this function issues no declaration,
// physical file, authority or installation from structural input alone.
export function projectDeclaredProjectWritableInventory<Source extends WritableInventorySource>(sources: readonly Source[]) {
  const targets: Readonly<{
    source: Source; write: Source['writes'][number]; physical: Source['physical'][number];
    mapping: NonNullable<NonNullable<Source['effectPrepared']>['mappings']>[number] | undefined;
    beforeFields: readonly string[];
  }>[] = [];
  for (const source of sources) for (const write of source.writes) {
    const physical = source.physical.find(value => value.resource === write.resource);
    if (physical === undefined) invalid();
    const mapping = source.effectPrepared?.mappings?.find(value =>
      value.resource === write.resource && value.body === write.mappingWire);
    if (source.effectPrepared !== undefined && mapping === undefined) invalid();
    targets.push(Object.freeze({source, write, physical, mapping,
      beforeFields: Object.freeze(Object.keys(physical.schema))}));
  }
  const compare = (left: string, right: string) => left < right ? -1 : left > right ? 1 : 0;
  const pathCompare = (left: typeof targets[number], right: typeof targets[number]) => {
    const a = left.physical.itemsPath, b = right.physical.itemsPath;
    for (let index = 0; index < Math.min(a.length, b.length); index++) {
      const order = compare(a[index], b[index]);
      if (order !== 0) return order;
    }
    return a.length - b.length;
  };
  targets.sort(pathCompare);
  for (let index = 1; index < targets.length; index++) {
    const previous = targets[index - 1], current = targets[index];
    if (previous.source === current.source && previous.physical === current.physical) continue;
    const before = previous.physical.itemsPath;
    const after = current.physical.itemsPath;
    if (before.length <= after.length && before.every((part, offset) => part === after[offset])) {
      fail('OverlappingMockWritableCollections');
    }
  }
  targets.sort((left, right) => compare(left.source.catalogue.connection, right.source.catalogue.connection) ||
    compare(left.write.resource, right.write.resource) ||
    compare(left.write.operation ?? 'update', right.write.operation ?? 'update'));
  for (let index = 1; index < targets.length; index++) {
    const previous = targets[index - 1], current = targets[index];
    if (previous.source.catalogue.connection === current.source.catalogue.connection &&
        previous.write.resource === current.write.resource &&
        (previous.source !== current.source || previous.physical !== current.physical ||
         (previous.write.operation ?? 'update') === (current.write.operation ?? 'update'))) {
      fail('DuplicateMockWritableTarget');
    }
  }
  return Object.freeze(targets);
}
