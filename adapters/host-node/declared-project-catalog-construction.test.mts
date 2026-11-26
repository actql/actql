import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/checkpoints.mjs';
import {declaredProjectCatalogEntryConstructionGeometry as geometry}
  from './declared-project-catalog-construction.mjs';

type FixtureSchema = Record<string, {type: string; nullable: boolean; description?: unknown}>;
type FixtureView = {
  resource: string; resource_kind: string; schema: FixtureSchema;
  request_schema?: unknown; facts?: unknown; acquisition?: unknown;
  resource_identity?: unknown; data_classification?: string;
};
type FixtureFileBinding = {
  listing_resource: string; content_resource: string; data_resource: string; version_field: string;
  identity_field: string; name_field: string; media_type_field: string; content_utf8_field: string;
};
type FixtureEntry = {
  views: FixtureView[]; query_aliases: {name: string; resource: string}[];
  data: {resource: string; items_path: string[]; key_path: string[]; primary_identity: string; schema?: FixtureSchema}[];
  file_bindings?: FixtureFileBinding[];
};
type SavedFixtureView = Record<string, string> & {resource: string; resource_kind: string};
type InitialFixture = {views: readonly {resource: string; carrier_schema_cid: string}[]};
type ScopeInputs = [connection: string, provider: string, path: string, catalog: string];

const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const sample = (text: unknown): FixtureEntry => ({views: [{resource: 'records', resource_kind: 'relation',
  schema: {id: {type: 'string', nullable: false}, label: {type: 'string', nullable: true, description: text}},
  request_schema: {type: 'object', fields: {}}, facts: {relation_keys: {candidate_keys: [['id']]}},
  data_classification: 'internal'}], query_aliases: [{name: 'records', resource: 'records'}],
  data: [{resource: 'records', items_path: ['records'], key_path: ['keys'], primary_identity: 'id'}]});

// Test-only execution of the exact pre-restore body serialization families.
function project(entry: Pick<FixtureEntry, 'views'>) {
  let hashedBytes = 0n;
  const views = entry.views.map(view => {
    const schema = wire(view.schema);
    const hashed = wire(view.schema);
    hashedBytes += BigInt(Buffer.byteLength(hashed));
    const result: SavedFixtureView = {resource: view.resource, resource_kind: view.resource_kind,
      schema_wire: schema, schema_cid: 'sha256:' + createHash('sha256').update(hashed).digest('hex')};
    for (const name of ['request_schema', 'facts', 'acquisition', 'resource_identity'] as const) {
      if (Object.hasOwn(view, name)) result[name + '_wire'] = wire(view[name]);
    }
    if (Object.hasOwn(view, 'data_classification')) result.data_classification = view.data_classification!;
    return result;
  });
  return {views, savedViewsWire: wire({views}), hashedBytes};
}

test('catalog entry geometry bounds actual canonical bodies hashes and detached restore wire', () => {
  for (const text of ['plain', '日本語😀', '\\"\n\r\t{}[]'.repeat(100), 'x'.repeat(10000)]) {
    const original = JSON.stringify(sample(text)), q = geometry(original);
    const actual = project(JSON.parse(original));
    assert.ok(q.bounds.savedViewsWireUnits >= BigInt(actual.savedViewsWire.length));
    const bodies = actual.views.flatMap(view => Object.entries(view)
      .filter(([key]) => key.endsWith('_wire')).map(([, value]) => value));
    assert.ok(q.bounds.savedBodyUnits >= bodies.reduce((sum, body) => sum + BigInt(body.length), 0n));
    assert.ok(q.wire >= actual.hashedBytes);
    assert.ok(q.retained.text >= 2n * BigInt(actual.savedViewsWire.length));
    assert.equal(q.nodes, q.retained.nodes + q.workspace.nodes);
    assert.equal(q.text, q.retained.text + q.workspace.text);
    assert.equal(q.wire, q.retained.wire + q.workspace.wire);
  }
});

test('catalog geometry scans before parse and retains malformed failure prefixes without admission', () => {
  const parse = JSON.parse, stringify = JSON.stringify;
  let calls = 0;
  JSON.parse = () => {calls++; throw new Error('must not parse to quote');};
  JSON.stringify = () => {calls++; throw new Error('must not serialize to quote');};
  try {
    for (const original of ['', '{', '{"views":[', '{"x":"\\u005', '{"x":1,"x":2}', '"\ud800"']) {
      const q = geometry(original);
      assert.ok(q.nodes > 0n && q.text > 0n && q.wire > 0n);
      assert.equal(q.input.units, BigInt(original.length));
    }
    assert.equal(calls, 0);
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
});

test('long scalar backing increases text but not constructor counts', () => {
  const short = geometry(JSON.stringify(sample('x')));
  const long = geometry(JSON.stringify(sample('x'.repeat(100000))));
  assert.equal(short.nodes, long.nodes);
  assert.equal(short.bounds.views, long.bounds.views);
  assert.ok(long.text > short.text && long.wire > short.wire);
  assert.equal(typeof long.text, 'bigint');
});

test('multi-view projection retains all native array entries and canonical outputs', () => {
  const entry = sample('nested');
  entry.views = Array.from({length: 128}, (_, index) => ({...entry.views[0], resource: `rows${index}`}));
  const q = geometry(JSON.stringify(entry)), actual = project(entry);
  assert.equal(q.bounds.views, 128n);
  assert.ok(q.bounds.savedViewsWireUnits >= BigInt(actual.savedViewsWire.length));
  assert.ok(q.retained.nodes >= 7n + 7n * 128n);
  assert.ok(q.workspace.wire >= actual.hashedBytes);
  const nested = sample({deep: true});
  nested.views[0].facts = {outer: {inner: ['value', {x: '\\"😀'}]}};
  const nq = geometry(JSON.stringify(nested));
  assert.ok(nq.bounds.savedViewsWireUnits >= BigInt(project(nested).savedViewsWire.length));
});

test('geometry refuses non-String originals without invoking coercion', () => {
  let calls = 0;
  const hostile = {toString() {calls++; return '{}';}};
  for (const input of [undefined, null, {}, [], 1, hostile]) assert.throws(() => geometry(input as string), TypeError);
  assert.equal(calls, 0);
});

import {declaredProjectCatalogScopeConstructionGeometry as scopeGeometry,
  declaredProjectCatalogFileFactsConstructionGeometry as fileGeometry,
  declaredProjectCatalogPhysicalOverridesConstructionGeometry as physicalGeometry,
  declaredProjectCatalogFinalDescriptorsConstructionGeometry as finalGeometry}
  from './declared-project-catalog-construction.mjs';

const digest = (value: unknown) => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const scopeInputs: ScopeInputs = ['logical-connection', 'configured-provider', '/project/日本語/data.json', '{"connections":{}}'];

function fileProjection(entry: FixtureEntry, initial: InitialFixture, scope: string) {
  const views = project(entry).views;
  let hashedBytes = 0n, factUnits = 0n;
  for (const binding of entry.file_bindings ?? []) {
    const source = entry.data.find(value => value.resource === binding.data_resource)!;
    const physical = {...source, schema: source.schema ?? entry.views.find(view => view.resource === source.resource)!.schema};
    const preimage = {scope, physical, version_field: binding.version_field, representation: 'exact_stored_bytes'};
    hashedBytes += BigInt(Buffer.byteLength(wire(preimage)));
    const version = digest(preimage);
    const listing = views.find(view => view.resource === binding.listing_resource)!;
    const content = views.find(view => view.resource === binding.content_resource)!;
    listing.facts_wire = wire({file_listing: {version: 'actql-file-list/0.1', kind: 'file_listing',
      selectable: [], allow_unfiltered_listing: true, admitted_scope_contract_cid: scope,
      listing_schema_contract_cid: initial.views.find(view => view.resource === binding.listing_resource)!.carrier_schema_cid,
      version_capability: {contract_cid: version, required_nonnull: true},
      max_listing_items: 100, max_examined_items: 100, max_listing_pages: 1, max_request_attempts: 1,
      max_listing_bytes: 1048576, max_listing_duration_ms: 30000, maximum_path_length: 4096}});
    content.facts_wire = wire({file_content: {version: 'actql-file-content/0.1', kind: 'file_content',
      admitted_scope_contract_cid: scope,
      content_schema_contract_cid: initial.views.find(view => view.resource === binding.content_resource)!.carrier_schema_cid,
      version_capability: {contract_cid: version, required_nonnull: true}, representation: 'exact_stored_bytes'},
      lookup_capacity: {version: 'actql-lookup-capacity/0.1', completeness: 'complete_per_requested_key',
        max_rows_per_key: 1, max_pages_per_request: 1, max_response_bytes_per_page: 1048576}});
    factUnits += BigInt(listing.facts_wire.length + content.facts_wire.length);
  }
  return {wire: wire({views}), factUnits, hashedBytes};
}

function fileFixture() {
  const entry = sample('unrelated saved content');
  const schema = {id: {type: 'string', nullable: false}, name: {type: 'string', nullable: false}};
  for (const name of ['name', 'version', 'media', 'content']) entry.views[0].schema[name] = {type: 'string', nullable: false};
  entry.views.push({resource: 'listing', resource_kind: 'file', schema},
    {resource: 'content', resource_kind: 'file', schema});
  entry.file_bindings = [{listing_resource: 'listing', content_resource: 'content', data_resource: 'records',
    identity_field: 'id', name_field: 'name', version_field: 'version', media_type_field: 'media', content_utf8_field: 'content'}];
  const initial = {views: entry.views.map(view => ({resource: view.resource, carrier_schema_cid: 'sha256:' + 'a'.repeat(64)}))};
  return {entry, initial};
}

test('scope stage uses exact provider namespace path and entire original catalog as borrowed Strings', () => {
  const q = scopeGeometry(...scopeInputs);
  const [connection, provider, dataPath, catalog] = scopeInputs;
  const actual = wire({connection, connector: provider, dataPath, catalog});
  assert.ok(q.bounds.scopePreimageUnits >= BigInt(actual.length));
  assert.ok(q.wire >= BigInt(Buffer.byteLength(actual)));
  assert.equal(q.retained.text, 142n);
  for (let index = 0; index < scopeInputs.length; index++) {
    const larger: ScopeInputs = [...scopeInputs]; larger[index] += '😀\\"'.repeat(100);
    const next = scopeGeometry(...larger);
    assert.equal(next.nodes, q.nodes);
    assert.ok(next.text > q.text && next.wire > q.wire);
  }
  assert.notEqual(digest({connection, connector: provider, dataPath, catalog}),
    digest({connection, connector: connection, dataPath, catalog}));
});

test('File stage includes initial parse version hash generated facts and retained final restore wire', () => {
  const {entry, initial} = fileFixture(), scope = 'sha256:' + 'b'.repeat(64);
  const original = JSON.stringify(entry), exported = JSON.stringify(initial);
  const q = fileGeometry(original, exported, scope, 1);
  const actual = fileProjection(entry, initial, scope);
  assert.ok(q.bounds.generatedFactsUnits! >= actual.factUnits);
  assert.ok(q.bounds.finalSavedViewsWireUnits >= BigInt(actual.wire.length));
  assert.ok(q.wire >= actual.hashedBytes);
  assert.ok(q.retained.text >= 2n * BigInt(exported.length + actual.wire.length));
  const twice = fileGeometry(original, exported, scope, 2);
  assert.equal(twice.bounds.generatedFactsUnits, 2n * q.bounds.generatedFactsUnits!);
  assert.equal(twice.wire, 2n * q.wire);
  const altered = fileGeometry(original, exported + ' '.repeat(1000), scope, 1);
  assert.ok(altered.text > q.text);
  assert.deepEqual(fileGeometry(original, exported, scope, 0).retained, {nodes: 0n, text: 0n, wire: 0n});
});

test('physical overrides sum schema hash candidate facts and detached payload for each actual restore', () => {
  const entry = sample('日本語\\"'.repeat(50)), original = JSON.stringify(entry);
  const view = entry.views[0], identity = entry.data[0].primary_identity;
  const selected = {resource: view.resource, resource_kind: view.resource_kind,
    schema_wire: wire(view.schema), schema_cid: digest(view.schema),
    facts_wire: wire({relation_keys: {candidate_keys: [[identity]]}})};
  const payload = wire({views: [selected]});
  const one = physicalGeometry(original, 1), two = physicalGeometry(original, 2);
  assert.ok(one.bounds.savedViewsWireUnits >= BigInt(payload.length));
  assert.ok(one.wire >= BigInt(Buffer.byteLength(wire(view.schema))));
  assert.equal(two.nodes - 1n, 2n * (one.nodes - 1n), 'one Map wrapper, summed override entries');
  for (const key of ['text', 'wire'] as const) assert.equal(two[key], 2n * one[key]);
  assert.deepEqual(physicalGeometry(original, 0).workspace, {nodes: 0n, text: 0n, wire: 0n});
  assert.equal(physicalGeometry(original, 0).retained.nodes, 1n, 'empty Map still constructed');
});

test('final descriptors borrow all native wires and reject accessor or proxy metadata arrays', () => {
  const original = JSON.stringify(sample('x'));
  const one = finalGeometry(original, '{}', ['{}'], 1, 0);
  const large = finalGeometry(original, 'x'.repeat(100000), ['y'.repeat(100000)], 1, 0);
  assert.deepEqual(one, large, 'native output text is borrowed, never reparsed or copied');
  assert.equal(one.retained.text, 0n);
  assert.equal(one.workspace.wire, 0n);
  const records = Object.freeze([Object.freeze({body: '{}', resource: 'rows'})]);
  assert.deepEqual(finalGeometry(original, '{}', records, 1, 0), one);
  assert.throws(() => finalGeometry(original, '{}', [{body: '{}'}], 1, 0), TypeError);
  let bodyReads = 0;
  const getter = Object.freeze({get body() {bodyReads++; return '{}';}});
  assert.throws(() => finalGeometry(original, '{}', Object.freeze([getter]), 1, 0), TypeError);
  assert.equal(bodyReads, 0);
  assert.ok(finalGeometry(original, '{}', ['{}', '{}'], 2, 0).nodes > one.nodes);
  let reads = 0;
  const array: unknown[] = [];
  Object.defineProperty(array, '0', {get() {reads++; return '{}';}});
  assert.throws(() => finalGeometry(original, '{}', array, 1, 0), TypeError);
  assert.throws(() => finalGeometry(original, '{}', new Proxy([], {get() {reads++;}}), 1, 0), TypeError);
  assert.equal(reads, 0);
});

test('all later quotations scan Strings only and reject unbounded count guesses', () => {
  const {entry, initial} = fileFixture();
  const original = JSON.stringify(entry), exported = JSON.stringify(initial);
  const parse = JSON.parse, stringify = JSON.stringify;
  JSON.parse = JSON.stringify = () => {throw new Error('quotation must not construct its input');};
  try {
    assert.ok(scopeGeometry(...scopeInputs).nodes > 0n);
    assert.ok(fileGeometry(original, exported, 'scope', 1).nodes > 0n);
    assert.ok(physicalGeometry(original, 1).nodes > 0n);
    assert.ok(finalGeometry(original, exported, ['mapping'], 1, 0).nodes > 0n);
    for (const count of [-1, 0.5, 129, Infinity, 1n, '1']) {
      assert.throws(() => fileGeometry(original, exported, 'scope', count as number), TypeError);
      assert.throws(() => physicalGeometry(original, count as number), TypeError);
      assert.throws(() => finalGeometry(original, exported, [], count as number, 0), TypeError);
    }
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
});

import {mockFileRowFootprint} from '../local-node/installed-mock-row-effect.mjs';
import {declaredProjectMockFootprintConstructionGeometry as footprintGeometry}
  from './declared-project-catalog-construction.mjs';

test('Mock write footprint quote includes the original ordered identity and preserves the scalar quote', () => {
  const paths = {itemsPath: ['rows'], keyPath: ['key']};
  const rowLimit = 2, requestBytes = 64;
  const measure = (primaryIdentity: unknown) =>
    footprintGeometry([{physical: {...paths, primaryIdentity}}], rowLimit, requestBytes);
  const scalar = measure('id');
  assert.equal(scalar.bounds.wireBytes, 254n);
  assert.deepEqual(scalar.retained, {nodes: 0n, text: 0n, wire: 0n});

  const fields = Object.freeze(['site' + '雪'.repeat(72), 'serial']);
  const tuple = Object.freeze({kind: 'tuple', fields});
  const ordered = measure(tuple);
  const selector = ['north', '9007199254740993'];
  assert.ok(ordered.workspace.wire >= BigInt(Buffer.byteLength(wire({
    items_path: paths.itemsPath, key_path: paths.keyPath, primary_identity: tuple, identity: selector,
  }))));
  assert.ok(ordered.workspace.nodes > scalar.workspace.nodes);
  assert.ok(ordered.workspace.text > scalar.workspace.text);
  assert.deepEqual(ordered.retained, scalar.retained);

  let getterCalls = 0;
  const hostile = Object.freeze({kind: 'tuple', get fields() {getterCalls++; return fields;}});
  assert.throws(() => measure(hostile), TypeError);
  assert.throws(() => measure({kind: 'tuple', fields}), TypeError);
  assert.equal(getterCalls, 0);
});

test('Mock exact footprints hash the checked original tuple and distinguish adjacent Int64 values', () => {
  const primaryIdentity = Object.freeze({kind: 'tuple' as const, fields: Object.freeze(['site', 'serial'])});
  const bindingCid = 'sha256:' + 'a'.repeat(64);
  const resourceIdentityCid = 'sha256:' + 'b'.repeat(64);
  const target = {physical: {primaryIdentity, itemsPath: ['rows'], keyPath: ['key']},
    write: {resource: 'Account'}, resourceIdentityCid};
  const west = Object.freeze(['west', '9007199254740993']);
  const next = Object.freeze(['west', '9007199254740994']);
  const rows = mockFileRowFootprint({bindingCid, target, selectors: [west, next]});
  const expected = (serial: string) => 'sha256:' + createHash('sha256').update(
    '{"identity":["west","' + serial + '"],"items_path":["rows"],"key_path":["key"],' +
    '"primary_identity":{"fields":["site","serial"],"kind":"tuple"}}').digest('hex');
  assert.equal(rows.resource_identity_scheme_cid, resourceIdentityCid);
  assert.deepEqual(rows.provider_object_identity_cids, [expected(west[1]), expected(next[1])]);
  const scalar = mockFileRowFootprint({bindingCid,
    target: {...target, physical: {...target.physical, primaryIdentity: 'id'}}, selectors: ['west']});
  assert.equal(scalar.resource_identity_scheme_cid, 'sha256:' + createHash('sha256').update(
    '{"identity_fields":["items_path","key_path","primary_identity","identity"],"kind":"mock-file-row-update"}').digest('hex'));
  assert.deepEqual(scalar.provider_object_identity_cids, ['sha256:' + createHash('sha256').update(
    '{"identity":"west","items_path":["rows"],"key_path":["key"],"primary_identity":"id"}').digest('hex')]);
  const alias = {...target, write: {resource: 'AccountAlias'}};
  assert.deepEqual(mockFileRowFootprint({bindingCid, target: alias, selectors: [west]}).provider_object_identity_cids,
    [rows.provider_object_identity_cids[0]]);
  assert.throws(() => mockFileRowFootprint({bindingCid, target, selectors: ['west|9007199254740993']}),
    {code: 'InvalidMockEffectFootprint'});
  assert.throws(() => mockFileRowFootprint({bindingCid, target, selectors: [Object.freeze(['west'])]}),
    {code: 'InvalidMockEffectFootprint'});
  assert.throws(() => mockFileRowFootprint({bindingCid, target: {physical: target.physical, write: target.write}, selectors: [west]}),
    {code: 'InvalidMockEffectFootprint'});
  let getterCalls = 0;
  const accessor = ['west', west[1]];
  Object.defineProperty(accessor, '1', {get() {getterCalls++; return west[1];}});
  assert.throws(() => mockFileRowFootprint({bindingCid, target, selectors: [Object.freeze(accessor)]}),
    {code: 'InvalidMockEffectFootprint'});
  assert.equal(getterCalls, 0);
});

import {declaredProjectCatalogMappingInputsConstructionGeometry as mappingGeometry}
  from './declared-project-catalog-construction.mjs';

function mappingProjection(specs: readonly ReturnType<typeof updateSpec>[]) {
  const writesJson = wire({writes: specs.map(spec => ({resource: spec.resource,
    primary_identity: spec.primary_identity,
    update: {fields: spec.writable_fields, permission: spec.permission, approval: spec.approval}}))});
  const mappings = Object.freeze(specs.map(spec => Object.freeze({resource: spec.resource,
    operation: 'update', sources: Object.freeze(spec.writable_fields.map(name =>
      Object.freeze({target: name, field: name, null_behavior: 'reject'})))})));
  return Object.freeze({writesJson, mappings});
}

const updateSpec = (text: string) => ({resource: 'records', primary_identity: 'id',
  writable_fields: ['label', text], permission: 'records.update',
  observe_permission: 'records.read', approval: 'required', aliases: ['apply']});

test('Mapping input geometry funds authored UPDATE JSON and frozen operations before prepareMappings', () => {
  for (const field of ['name', '日本語😀', '\\"\n'.repeat(30)]) {
    const entry = {...sample('kept'), writes: [updateSpec(field)]};
    const q = mappingGeometry(JSON.stringify(entry), entry.writes.length);
    const result = mappingProjection(entry.writes);
    assert.ok(q.bounds.writesJsonUnits >= BigInt(result.writesJson.length));
    assert.ok(q.retained.text >= 2n * BigInt(result.writesJson.length));
    assert.equal(q.wire, 0n);
    assert.equal(q.bounds.writeCount, 1n);
    assert.equal(result.mappings[0].operation, 'update');
    assert.equal(result.mappings[0].sources[1].target, field);
    assert.equal(result.mappings[0].sources[1].field, field);
    assert.equal(result.mappings[0].sources[1].null_behavior, 'reject');
    assert.ok(Object.isFrozen(result) && Object.isFrozen(result.mappings[0].sources[0]));
    assert.equal(q.nodes, q.retained.nodes + q.workspace.nodes);
  }
});

test('Mapping input geometry retains all write operations and an honest empty construction minimum', () => {
  const entry = {...sample('x'), writes: Array.from({length: 128}, (_, index) =>
    ({...updateSpec('value'), resource: `resource${index}`, aliases: [`apply${index}`]}))};
  const q = mappingGeometry(JSON.stringify(entry), 128), result = mappingProjection(entry.writes);
  assert.ok(q.bounds.writesJsonUnits >= BigInt(result.writesJson.length));
  assert.ok(q.retained.nodes >= 128n * (4n + 2n * 4n));
  const empty = mappingGeometry(JSON.stringify({...entry, writes: []}), 0);
  assert.ok(empty.nodes > 0n && empty.text > 0n);
  assert.ok(empty.bounds.writesJsonUnits >= BigInt(mappingProjection([]).writesJson.length));
  assert.equal(empty.bounds.sourceFields, 0n);
  const short = mappingGeometry(JSON.stringify({writes: [updateSpec('x')]}), 1);
  const long = mappingGeometry(JSON.stringify({writes: [updateSpec('x'.repeat(100000))]}), 1);
  assert.equal(short.nodes, long.nodes);
  assert.ok(long.text > short.text);
});

test('Mapping input quotation does not parse serialize or coerce and validates actual count domain', () => {
  const original = JSON.stringify({writes: [updateSpec('field')]});
  const parse = JSON.parse, stringify = JSON.stringify;
  JSON.parse = JSON.stringify = () => {throw new Error('unfunded quotation construction');};
  try {
    assert.ok(mappingGeometry(original, 1).nodes > 0n);
    assert.ok(mappingGeometry('{"writes":[', 1).nodes > 0n, 'geometry never attests admission');
    for (const count of [-1, 0.5, 129, Infinity, '1', 1n]) {
      assert.throws(() => mappingGeometry(original, count as number), TypeError);
    }
    let calls = 0;
    assert.throws(() => mappingGeometry({toString() {calls++; return original;}} as unknown as string, 1), TypeError);
    assert.equal(calls, 0);
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
});

import {declaredProjectCatalogJsonParseConstructionGeometry as parseGeometry,
  declaredProjectCatalogEntryProjectionConstructionGeometry as entryProjectionGeometry,
  declaredProjectCatalogSavedInputConstructionGeometry as savedGeometry,
  declaredProjectCatalogFileFactsProjectionConstructionGeometry as fileProjectionGeometry}
  from './declared-project-catalog-construction.mjs';
const deepFreeze = <Value,>(value: Value): Value => {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) deepFreeze(item);
    Object.freeze(value);
  }
  return value;
};

test('parse-first recipe funds malformed and huge failure prefixes without parsing', () => {
  const parse = JSON.parse, stringify = JSON.stringify;
  JSON.parse = JSON.stringify = () => {throw new Error('quote must not parse or stringify');};
  try {
    for (const original of ['', '{', '{"views":[', '[1,'.repeat(10000), '"' + 'x'.repeat(100000)]) {
      const q = parseGeometry(original);
      assert.ok(q.nodes > 0n);
      assert.ok(q.text >= 12n * BigInt(original.length));
      assert.equal(q.bounds.inputUnits, BigInt(original.length));
    }
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
});

test('actual entry projection uses two original views rather than assumed128', () => {
  const value = sample('plain');
  value.views.push({...value.views[0], resource: 'other'});
  const original = JSON.stringify(value), entry = deepFreeze(value);
  const q = entryProjectionGeometry(entry);
  assert.equal(q.bounds.views, 2n);
  assert.ok(q.nodes < geometry(original).nodes);
  assert.ok(q.text < geometry(original).text);
  const projected = project(entry), saved = savedGeometry(deepFreeze(projected.views));
  assert.ok(saved.bounds.savedViewsWireUnits >= BigInt(projected.savedViewsWire.length));
  assert.ok(q.bounds.savedBodyUnits >= projected.views.reduce((sum, view) => sum +
    Object.entries(view).filter(([key]) => key.endsWith('_wire'))
      .reduce((n, [, text]) => n + BigInt(text.length), 0n), 0n));
});

test('saved input scalar escaped-width inventory covers exact opaque Strings', () => {
  for (const text of ['abc', '\\"\n\r\t\u0001', '日本語😀', '\ud800', 'x'.repeat(100000)]) {
    const views = deepFreeze([{resource: 'a', resource_kind: 'relation', schema_wire: text,
      schema_cid: 'sha256:' + '0'.repeat(64), facts_wire: undefined}]);
    const expected = JSON.stringify({views});
    const q = savedGeometry(views);
    assert.equal(q.bounds.savedViewsWireUnits, BigInt(expected.length));
    assert.ok(q.retained.text >= 2n * BigInt(expected.length));
  }
});

test('immutable geometry refuses proxies accessors cycles holes and unsupported depth', () => {
  let calls = 0;
  const getter = Object.freeze({get views() {calls++; return [];}});
  assert.throws(() => entryProjectionGeometry(getter));
  assert.throws(() => entryProjectionGeometry(new Proxy(Object.freeze({}), {ownKeys() {calls++; return [];}})));
  const cycle: {self?: object} = {}; cycle.self = cycle; Object.freeze(cycle);
  assert.throws(() => entryProjectionGeometry(cycle));
  assert.throws(() => savedGeometry(Object.freeze(Array(2))));
  assert.throws(() => savedGeometry([{resource: 'mutable'}]));
  let deep = Object.freeze({});
  for (let i = 0; i < 258; i++) deep = Object.freeze({child: deep});
  assert.throws(() => entryProjectionGeometry(deep));
  assert.equal(calls, 0);
});

test('file projection selects actual original CIDs and excludes irrelevant export text', () => {
  const entry = deepFreeze({views: [{resource: 'files', schema: {id: {type: 'string', nullable: false}}},
    {resource: 'content', schema: {id: {type: 'string', nullable: false}}}],
    data: [{resource: 'files', items_path: ['rows'], key_path: ['id'], primary_identity: 'id'}],
    file_bindings: [{data_resource: 'files', listing_resource: 'files', content_resource: 'content', version_field: 'version'}]});
  const initial = (extra: string) => deepFreeze({views: [{resource: 'files', carrier_schema_cid: 'a'.repeat(71)},
    {resource: 'content', carrier_schema_cid: 'b'.repeat(71)}], extra});
  const first = fileProjectionGeometry(entry, initial(''), 'c'.repeat(71));
  const huge = fileProjectionGeometry(entry, initial('x'.repeat(100000)), 'c'.repeat(71));
  assert.equal(first.bounds.views, 2n);
  assert.equal(first.bounds.fileBindingCount, 1n);
  assert.deepEqual(first, huge);
  const parse = JSON.parse, stringify = JSON.stringify;
  JSON.parse = JSON.stringify = () => {throw new Error('no parse or serialization in quote');};
  try {
    assert.deepEqual(fileProjectionGeometry(entry, initial(''), 'c'.repeat(71)), first);
    entryProjectionGeometry(entry);
    savedGeometry(deepFreeze([{resource: 'files', schema_wire: '{}'}]));
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
  assert.throws(() => fileProjectionGeometry(entry, deepFreeze({views: []}), 'scope'));
});

test('physical immutable entry overload counts only exact selected schemas and rejects count mismatch', () => {
  const value = sample('public');
  value.data[0].schema = {id: {type: 'string', nullable: false}};
  const entry = deepFreeze(value), original = JSON.stringify(value);
  const q = physicalGeometry(entry, 1);
  assert.equal(q.bounds.overrideCount, 1n);
  assert.ok(q.text < physicalGeometry(original, 1).text);
  const binding = entry.data[0];
  const actual = wire({views: [{resource: binding.resource, resource_kind: entry.views[0].resource_kind,
    schema_wire: wire(binding.schema), schema_cid: 'sha256:' + 'a'.repeat(64),
    facts_wire: wire({relation_keys: {candidate_keys: [[binding.primary_identity]]}})}]});
  assert.ok(q.bounds.savedViewsWireUnits >= BigInt(actual.length));
  assert.throws(() => physicalGeometry(entry, 0));
  assert.equal(physicalGeometry(deepFreeze(sample('no override')), 0).retained.nodes, 1n);
});

test('final immutable entry overload uses actual data count and original mapping records', () => {
  const entry = deepFreeze(sample('x'));
  const mappings = Object.freeze([Object.freeze({body: '{}'})]);
  const q = finalGeometry(entry, '{}', mappings, 2, 0);
  assert.equal(q.bounds.mappingCount, 1n);
  assert.ok(q.nodes < finalGeometry(JSON.stringify(entry), '{}', mappings, 2, 0).nodes);
  assert.deepEqual(q, finalGeometry(entry, '{}', ['{}'], 2, 0));
  const ordered = finalGeometry(entry, '{}', mappings, 2, 1);
  assert.equal(ordered.retained.nodes, q.retained.nodes + 1n, 'retain one borrowed prepared key slot');
  assert.deepEqual(ordered.workspace, {...q.workspace, nodes: q.workspace.nodes + 3n},
    'each retained slot also traverses the arrays, slots and frames of the freeze workspace');
  assert.throws(() => finalGeometry(entry, '{}', mappings, 2, 2), TypeError);
});

import {declaredProjectCatalogEntryHostConstructionGeometry as hostOnlyGeometry,
  declaredProjectCatalogSavedInputArraysConstructionGeometry as arraysOnlyGeometry}
  from './declared-project-catalog-construction.mjs';

test('Common catalogue projection leaves only actual Host metadata descriptors in JS geometry', () => {
  const entry = deepFreeze(sample('日本語😀\\"\n'));
  const q = hostOnlyGeometry(entry), old = entryProjectionGeometry(entry);
  assert.equal(q.bounds.views, 1n);
  assert.equal(q.retained.text, 0n);
  assert.equal(q.workspace.wire, 0n, 'SHA/UTF8 belongs to the separately quoted Common projection');
  assert.ok(q.retained.nodes > 0n && q.workspace.nodes > 0n);
  assert.ok(old.retained.text > q.retained.text);
  assert.throws(() => hostOnlyGeometry(new Proxy(entry, {get() {assert.fail('no getter');}})));
});

test('Common catalogue exact returned wire is borrowed by funded restore arrays without another serialization', () => {
  const views = deepFreeze([{resource: 'records', resource_kind: 'record',
    schema_wire: '{"id":{"nullable":false,"type":"string"}}',
    schema_cid: 'sha256:' + '0'.repeat(64), facts_wire: '{"x":"雪"}'}]);
  const parse = JSON.parse, stringify = JSON.stringify;
  JSON.parse = JSON.stringify = () => {throw new Error('array quote must not parse/serialize');};
  try {
    const q = arraysOnlyGeometry(views);
    assert.equal(q.bounds.views, 1n);
    assert.equal(q.retained.text, 0n);
    assert.equal(q.workspace.text, 0n);
    assert.equal(q.retained.nodes, 24n); // wrapper10 + seven arrays(1+one item)
    assert.equal(q.workspace.nodes, 80n); // existing freeze/control overlap3*24+8
    assert.throws(() => arraysOnlyGeometry(views.slice()), /InvalidDeclaredProjectCatalogConstructionGeometry/u);
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
});
