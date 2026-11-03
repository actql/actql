// Explicit model declarations only. This reader acquires no fixture records,
// credentials, permission, Source, Run, ContentRef or Effect approval.
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {readBoundedConfigurationUtf8} from '../host-node/source-profile-json.mjs';
import {declaredProjectCatalogJsonParseConstructionGeometry,
  declaredProjectCatalogEntryProjectionConstructionGeometry,
  declaredProjectCatalogSavedInputConstructionGeometry,
  declaredProjectCatalogScopeConstructionGeometry,
  declaredProjectCatalogFileFactsProjectionConstructionGeometry,
  declaredProjectCatalogPhysicalOverridesConstructionGeometry,
  declaredProjectCatalogMappingInputsConstructionGeometry,
  declaredProjectCatalogFinalDescriptorsConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const wire = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !value.includes('\0') && Buffer.byteLength(value) <= 4096;
const closed = (value, required, optional = []) => object(value) &&
  required.every(name => Object.hasOwn(value, name)) &&
  Object.keys(value).every(name => required.includes(name) || optional.includes(name));
const list = value => Array.isArray(value) && value.length <= 128;
const names = value => list(value) && value.every(text) && new Set(value).size === value.length;
const path = value => list(value) && value.every(text) && value.length > 0 && value.length <= 16;
const freeze = value => {
  if (object(value) || Array.isArray(value)) {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};
const invalid = () => fail('InvalidInstalledMockCatalog');

// The Common catalog parser first admits the exact bounded original, including
// duplicate keys and Unicode. Only its original entry spans are projected here.
export async function loadDeclaredProjectCatalog(moon, {directory, catalogFile, dataFile,
  connections, connectionOriginal, assertCurrent, openFile, installationInventory}) {
  if (!text(catalogFile) || !text(dataFile) || !text(directory) || typeof assertCurrent !== 'function') {
    fail('InstalledMockCatalogueUnavailable');
  }
  const methods = Object.fromEntries(['clientProjectCatalogAdmit', 'clientProjectCatalogCount',
    'clientProjectCatalogName', 'clientProjectCatalogEntryOriginalJson',
    'clientProjectConnectionsCount', 'clientProjectConnectionsName', 'clientProjectConnectionsConnector',
    'clientProgramRowSourceRestoreRelationDeclaration', 'clientProgramRowSourceDeclarationJson',
    ...(installationInventory === undefined ? ['clientProgramRelationUpdateMapping'] :
      ['clientProgramInstalledSourceConstructionCapacity', 'clientProgramRelationRestoreConstructionCapacity'])]
    .map(name => [name, moon?.[name]]));
  if (Object.values(methods).some(value => typeof value !== 'function')) fail('InstalledProjectRuntimeUnavailable');
  const call = (name, ...args) => Reflect.apply(methods[name], moon, args);
  if (installationInventory !== undefined && connectionOriginal?.connections !== connections) {
    fail('ForeignDeclaredFileInstallation');
  }
  const inputStage = (member, geometry, project, metadata = false) => {
    if (installationInventory === undefined) return project();
    const projection = Object.freeze({capacity() {
      const {retained, workspace} = geometry();
      return checked(call('clientProgramInstalledSourceConstructionCapacity',
        retained.nodes, retained.text, retained.wire, workspace.nodes, workspace.text, workspace.wire));
    }, project});
    return metadata ? installationInventory.prepareMetadataInput(projection)
      : member.prepareNativeInput(projection);
  };
  // Called only inside a funded JS stage. These are the actual original
  // Strings and parallel arrays consumed by the one native restore quote.
  const savedInput = selected => Object.freeze({wire: wire({views: selected}),
    resources: selected.map(view => view.resource), kinds: selected.map(view => view.resource_kind),
    schemas: selected.map(view => view.schema_wire), requests: selected.map(view => view.request_schema_wire),
    facts: selected.map(view => view.facts_wire), acquisitions: selected.map(view => view.acquisition_wire),
    identities: selected.map(view => view.resource_identity_wire)});
  const restoreInput = (member, connectorId, registration, revision, input, final = false) => {
    const project = () => {
      const declaration = checked(call('clientProgramRowSourceRestoreRelationDeclaration',
        connectorId, registration, revision, input.wire, undefined));
      // Final installed export belongs to prepareNativeDeclaration. Intermediate
      // File/physical exports are each covered by this invocation's own quote.
      if (final && installationInventory !== undefined) return Object.freeze({declaration});
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
    return final ? member.prepareNativeDeclaration(projection) : member.prepareNativeInput(projection);
  };
  assertCurrent();
  const catalogPath = resolve(directory, catalogFile);
  const originalWire = installationInventory === undefined
    ? await readBoundedConfigurationUtf8(catalogPath,
      {maxBytes: 65536, ...(openFile === undefined ? {} : {openFile})})
    : await installationInventory.readMetadataUtf8(catalogPath, 65536);
  assertCurrent();
  const admit = () => checked(call('clientProjectCatalogAdmit', originalWire));
  const original = installationInventory === undefined ? admit()
    : installationInventory.prepareMetadataInput(Object.freeze({
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
  const sources = [], aliases = new Set(), updates = new Set();
  for (let index = 0; index < count; index++) {
    const connection = call('clientProjectCatalogName', original, index);
    const entryWire = call('clientProjectCatalogEntryOriginalJson', original, index);
    let connectionIndex = -1, provider;
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
      () => Object.freeze({entry: freeze(JSON.parse(entryWire))}));
    const selected = inputStage(sourceMember,
      () => declaredProjectCatalogEntryProjectionConstructionGeometry(parsed.entry), () => {
      const entry = parsed.entry;
      if (!closed(entry, ['views', 'query_aliases', 'data'], ['writes', 'file_bindings']) ||
          !list(entry.views) || entry.views.length === 0 || !list(entry.query_aliases) ||
          !list(entry.data) || !list(entry.writes ?? []) || !list(entry.file_bindings ?? [])) invalid();
      const views = [], publicViews = new Map();
      for (const view of entry.views) {
        if (!closed(view, ['resource', 'resource_kind', 'schema'],
          ['request_schema', 'facts', 'acquisition', 'resource_identity', 'data_classification']) ||
            !text(view.resource) || !text(view.resource_kind) || !object(view.schema) ||
            publicViews.has(view.resource)) invalid();
        const schemaWire = wire(view.schema);
        const saved = {resource: view.resource, resource_kind: view.resource_kind,
          schema_wire: schemaWire, schema_cid: cid(view.schema)};
        for (const name of ['request_schema', 'facts', 'acquisition', 'resource_identity']) {
          if (Object.hasOwn(view, name)) saved[name + '_wire'] = wire(view[name]);
        }
        if (Object.hasOwn(view, 'data_classification')) saved.data_classification = view.data_classification;
        views.push(saved); publicViews.set(view.resource, view);
      }
      const queryAliases = entry.query_aliases.map(alias => {
        if (!closed(alias, ['name', 'resource'], ['request']) ||
            Object.hasOwn(alias, 'request') && !object(alias.request) ||
            !text(alias.name) || !publicViews.has(alias.resource) ||
            aliases.has(alias.name)) invalid();
        aliases.add(alias.name); return {...alias};
    });
    const data = new Map();
    for (const binding of entry.data) {
      if (!closed(binding, ['resource', 'items_path', 'key_path', 'primary_identity'], ['schema']) ||
          !publicViews.has(binding.resource) || data.has(binding.resource) ||
          !path(binding.items_path) || !path(binding.key_path) || !text(binding.primary_identity) ||
          binding.schema !== undefined && !object(binding.schema)) invalid();
      const schema = binding.schema ?? publicViews.get(binding.resource).schema;
      if (!Object.hasOwn(schema, binding.primary_identity) ||
          schema[binding.primary_identity]?.type !== 'string' || schema[binding.primary_identity]?.nullable !== false) invalid();
      data.set(binding.resource, {...binding, schema});
    }
    const bound = new Set(), fileBindings = [];
    for (const binding of entry.file_bindings ?? []) {
      const required = ['listing_resource', 'content_resource', 'data_resource', 'identity_field',
        'name_field', 'version_field', 'media_type_field', 'content_utf8_field'];
      if (!closed(binding, required, ['path_field']) || !required.every(name => text(binding[name])) ||
          binding.path_field !== undefined && !text(binding.path_field) ||
          !publicViews.has(binding.listing_resource) || !publicViews.has(binding.content_resource) ||
          !data.has(binding.data_resource) || binding.listing_resource === binding.content_resource ||
          bound.has(binding.listing_resource) || bound.has(binding.content_resource)) invalid();
      const physical = data.get(binding.data_resource);
      if (publicViews.get(binding.listing_resource).facts !== undefined ||
          publicViews.get(binding.content_resource).facts !== undefined) invalid();
      if (physical.primary_identity !== binding.identity_field || physical.schema === undefined) invalid();
      for (const name of ['identity_field', 'name_field', 'version_field', 'media_type_field', 'content_utf8_field']) {
        const field = physical.schema[binding[name]];
        if (field?.type !== 'string' || field.nullable !== false) invalid();
      }
      if (binding.path_field !== undefined && physical.schema[binding.path_field]?.type !== 'string') invalid();
      bound.add(binding.listing_resource); bound.add(binding.content_resource);
      fileBindings.push({...binding});
    }
    for (const view of entry.views) {
      if (!data.has(view.resource) && !bound.has(view.resource)) invalid();
      if (data.has(view.resource) && Object.hasOwn(entry.data.find(value => value.resource === view.resource), 'schema') &&
          !fileBindings.some(value => value.data_resource === view.resource)) invalid();
    }
    const writeSpecs = [];
    for (const spec of entry.writes ?? []) {
      if (!closed(spec, ['resource', 'primary_identity', 'writable_fields', 'permission', 'observe_permission', 'approval', 'aliases']) ||
          !data.has(spec.resource) || bound.has(spec.resource) || !names(spec.writable_fields) || !spec.writable_fields.length ||
          !names(spec.aliases) || !spec.aliases.length || !text(spec.permission) || !text(spec.observe_permission) ||
          spec.approval !== 'required' || spec.primary_identity !== data.get(spec.resource).primary_identity) invalid();
      for (const alias of spec.aliases) {if (updates.has(alias)) invalid(); updates.add(alias);}
      writeSpecs.push(spec);
    }
    return Object.freeze({entry, views: freeze(views), publicViews, queryAliases,
      data, fileBindings, writeSpecs});
    });
    const {entry, views, publicViews, queryAliases, data, fileBindings, writeSpecs} = selected;
    // Existing installed Effect ownership currently admits one target. Reject
    // ambiguity before opening fixture data or constructing an Effect.
    if (writeSpecs.length + sources.reduce((sum, source) => sum + source.writes.length, 0) > 1) invalid();
    const dataPath = resolve(directory, dataFile);
    const {scopeCid} = inputStage(sourceMember,
      () => declaredProjectCatalogScopeConstructionGeometry(connection, provider, dataPath, originalWire),
      () => Object.freeze({scopeCid: cid({connection, connector: provider, dataPath, catalog: originalWire})}));
    let finalViews = views;
    let finalInput = inputStage(sourceMember,
      () => declaredProjectCatalogSavedInputConstructionGeometry(finalViews),
      () => savedInput(finalViews));
    if (fileBindings.length) {
      const initialDeclaration = restoreInput(sourceMember, connectorId, registration, revision, finalInput);
      const {initial} = inputStage(sourceMember,
        () => declaredProjectCatalogJsonParseConstructionGeometry(initialDeclaration.wire),
        () => Object.freeze({initial: freeze(JSON.parse(initialDeclaration.wire))}));
      const facts = inputStage(sourceMember,
        () => declaredProjectCatalogFileFactsProjectionConstructionGeometry(entry, initial, scopeCid), () => {
        const factViews = views.map(view => ({...view}));
        for (const binding of fileBindings) {
          const versionCid = cid({scope: scopeCid, physical: data.get(binding.data_resource),
            version_field: binding.version_field, representation: 'exact_stored_bytes'});
          const listing = factViews.find(view => view.resource === binding.listing_resource);
          const content = factViews.find(view => view.resource === binding.content_resource);
          // Existing File contracts, derived from actual declared carrier CIDs.
          // These are static capability facts, not a current grant or reader.
          listing.facts_wire = wire({file_listing: {version: 'actql-file-list/0.1', kind: 'file_listing',
            selectable: [], allow_unfiltered_listing: true, admitted_scope_contract_cid: scopeCid,
            listing_schema_contract_cid: initial.views.find(view => view.resource === binding.listing_resource).carrier_schema_cid,
            version_capability: {contract_cid: versionCid, required_nonnull: true},
            max_listing_items: 100, max_examined_items: 100, max_listing_pages: 1, max_request_attempts: 1,
            max_listing_bytes: 1048576, max_listing_duration_ms: 30000, maximum_path_length: 4096}});
          content.facts_wire = wire({file_content: {version: 'actql-file-content/0.1', kind: 'file_content',
            admitted_scope_contract_cid: scopeCid,
            content_schema_contract_cid: initial.views.find(view => view.resource === binding.content_resource).carrier_schema_cid,
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
      const overrides = new Map();
      for (const binding of data.values()) {
        if (entry.data.find(value => value.resource === binding.resource).schema === undefined) continue;
        overrides.set(binding.resource, savedInput([{resource: binding.resource,
          resource_kind: publicViews.get(binding.resource).resource_kind,
          schema_wire: wire(binding.schema), schema_cid: cid(binding.schema),
          facts_wire: wire({relation_keys: {candidate_keys: [[binding.primary_identity]]}})}]));
      }
      return overrides;
    });
    // Native input closes once the final declaration is prepared. Every
    // independent physical override must therefore be restored first.
    if (overrideInputs !== undefined) for (const [resource, input] of overrideInputs) {
      overrideInputs.set(resource, restoreInput(sourceMember, connectorId,
        registration + '_data', registration + '_data/0.1', input).declaration);
    }
    const sourcePrepared = restoreInput(sourceMember, connectorId, registration, revision, finalInput, true);
    const {declaration, wire: declarationWire} = sourcePrepared;
    if (typeof declarationWire !== 'string') fail('InvalidHostRuntimeResult');
    let effectMember, effectPrepared, mappingOriginals;
    if (installationInventory === undefined) {
      // Explicit non-installed declaration diagnostic only. Installed startup
      // always uses the admitted Effect context and generic UPDATE continuation.
      mappingOriginals = writeSpecs.map(spec => checked(call('clientProgramRelationUpdateMapping', declaration,
        spec.resource, spec.primary_identity, spec.writable_fields, spec.permission, spec.approval)));
    } else if (writeSpecs.length) {
      effectMember = await installationInventory.begin(connectionOriginal, connectionIndex, 'effect');
      const mappingInput = inputStage(effectMember,
        () => declaredProjectCatalogMappingInputsConstructionGeometry(entryWire, writeSpecs.length), () => {
        const writesJson = wire({writes: writeSpecs.map(spec => ({resource: spec.resource,
          primary_identity: spec.primary_identity, update: {fields: spec.writable_fields,
            permission: spec.permission, approval: spec.approval}}))});
        const mappings = Object.freeze(writeSpecs.map(spec => Object.freeze({resource: spec.resource,
          operation: 'update', sources: Object.freeze(spec.writable_fields.map(name => Object.freeze({
            target: name, field: name, null_behavior: 'reject'})))})));
        return Object.freeze({writesJson, mappings});
      });
      effectMember.prepareBorrowedDeclaration(sourceMember);
      effectPrepared = effectMember.prepareMappings(mappingInput.writesJson, mappingInput.mappings);
      mappingOriginals = effectPrepared.mappings;
    } else mappingOriginals = [];
    const source = inputStage(undefined,
      () => declaredProjectCatalogFinalDescriptorsConstructionGeometry(entry, declarationWire, mappingOriginals, count),
      () => {
      const physical = [];
      for (const binding of data.values()) {
        physical.push(Object.freeze({resource: binding.resource,
          declaration: overrideInputs?.get(binding.resource) ?? declaration,
          itemsPath: Object.freeze(binding.items_path), keyPath: Object.freeze(binding.key_path),
          primaryIdentity: binding.primary_identity, schema: freeze(binding.schema), writableFields: Object.freeze([])}));
      }
      const writes = writeSpecs.map((spec, index) => {
        const mappingWire = installationInventory === undefined ? mappingOriginals[index]
          : mappingOriginals[index].body;
        if (typeof mappingWire !== 'string') fail('InvalidHostRuntimeResult');
        return freeze({...spec, mappingWire});
      });
      return Object.freeze({declaration, wire: declarationWire, physical: Object.freeze(physical),
        writes: Object.freeze(writes), fileBindings: freeze(fileBindings), scopeCid,
        sourceMember, sourcePrepared, effectMember, effectPrepared,
        catalogue: freeze({connection, connectorId, provider, registration, revision, views: finalViews,
          queryAliases, updateAliases: writes.flatMap(spec => spec.aliases.map(name => ({name, resource: spec.resource})))})});
    }, true);
    sources.push(source);
    assertCurrent();
  }
  return Object.freeze({original, originalWire, sources: Object.freeze(sources)});
}
