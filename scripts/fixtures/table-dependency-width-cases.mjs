// Real, independently named Iceberg Tables supply every wide document. The
// checked Program consumes each document through len(), then persists one small
// approved Table operation. No extra body is added to the dependency inventory.
import assert from 'node:assert/strict';
import {types} from 'node:util';
import {createHash} from 'node:crypto';

const canonical = value => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map(key =>
    JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
};
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const number = {nullable: false, type: 'number'};
const string = {nullable: false, type: 'string'};

// Physical JSON replies deliberately allow null-prototype DATA records. Match
// every authored key and exact scalar without conflating representation with
// content; getters, proxies and unknown properties are not observed values.
export function observeTableWidthDataRecord(actual, expected) {
  assert(actual !== null && typeof actual === 'object' &&
    !Array.isArray(actual) && !types.isProxy(actual));
  assert(Object.getPrototypeOf(actual) === null ||
    Object.getPrototypeOf(actual) === Object.prototype);
  const keys = Reflect.ownKeys(actual), expectedKeys = Object.keys(expected);
  assert.equal(keys.length, expectedKeys.length);
  assert(keys.every(key => typeof key === 'string' && expectedKeys.includes(key)));
  return Object.fromEntries(expectedKeys.map(key => {
    const original = Object.getOwnPropertyDescriptor(expected, key);
    const observed = Object.getOwnPropertyDescriptor(actual, key);
    assert(original && Object.hasOwn(original, 'value') && observed &&
      Object.hasOwn(observed, 'value') && observed.enumerable);
    const value = observed.value;
    assert(value === null || typeof value === 'string' || typeof value === 'boolean' ||
      typeof value === 'number' && Number.isFinite(value));
    assert.equal(value, original.value);
    return [key, value];
  }));
}

export function tableDependencyWidthAccount(principalId, resources) {
  assert.equal(typeof principalId, 'string');
  return canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'table-dependency-width', entries: [
      {entry_id: 'effect', outcome: 'delegate', principal: {all: true},
        connection: {any_of: ['table-local']}, resource: {any_of: ['summary']},
        operation: {any_of: ['effect']}, exclusions: []},
      {entry_id: 'original-run-result-read', outcome: 'allow',
        principal: {any_of: [principalId]}, connection: {any_of: ['actql-remote-host']},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'read', outcome: 'allow', principal: {all: true},
        connection: {any_of: ['table-local']}, resource: {any_of: [...resources, 'summary'].sort()},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'run', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}, exclusions: []},
    ]});
}

export function tableDependencyWidthCase({tables = 24, rowsPerTable = 16,
  documentUnits = 48 * 1024} = {}) {
  assert(Number.isSafeInteger(tables) && tables >= 1 && tables < 32);
  assert(Number.isSafeInteger(rowsPerTable) && rowsPerTable >= 1 && rowsPerTable <= 64);
  assert(Number.isSafeInteger(documentUnits) && documentUnits >= 1024 && documentUnits <= 48 * 1024);
  const sourceSchema = {document: string, id: number};
  const schemaWire = canonical(sourceSchema), schemaCid = cid(sourceSchema);
  const mappingBody = {version: 'actql-table-storage-mapping/0.1', schema_cid: schemaCid,
    iceberg_format_version: 2, columns: [
      {name: 'document', value_field_id: 1, presence_field_id: null,
        physical_type: 'string', nullable: false, presence: 'required'},
      {name: 'id', value_field_id: 2, presence_field_id: null,
        physical_type: 'double', nullable: false, presence: 'required'},
    ]};
  const mapping = {...mappingBody, mapping_cid: cid(mappingBody)};
  const resources = Array.from({length: tables}, (_, index) => `documents_${index}`);
  const row = (table, ordinal) => {
    assert(Number.isSafeInteger(table) && table >= 0 && table < tables);
    assert(Number.isSafeInteger(ordinal) && ordinal >= 0 && ordinal < rowsPerTable);
    // Repartition the original six-by-sixty-four dataset without changing
    // one logical row, document byte or id. The physical Table is not its id.
    const id = table * rowsPerTable + ordinal;
    const originalTable = Math.floor(id / 64), originalOrdinal = id % 64;
    const header = `Document from Table ${originalTable}, row ${originalOrdinal}. `;
    const paragraph = `This document belongs to source ${originalTable} and record ${originalOrdinal}; ` +
      'the approved summary counts the characters of this actual stored text. ';
    const width = documentUnits + originalOrdinal;
    const document = (header + paragraph.repeat(Math.ceil(width / paragraph.length))).slice(0, width);
    assert.equal(document.length, width);
    assert.equal(Buffer.byteLength(document), width, 'This fixture deliberately uses ASCII documents');
    return {document, id};
  };
  const ordinalSum = count => Math.floor(count / 64) * 2016 +
    (count % 64) * (count % 64 - 1) / 2;
  const expectedSources = resources.map((resource, table) => ({resource, tableName: resource,
    rows: rowsPerTable, document_chars: rowsPerTable * documentUnits +
      ordinalSum((table + 1) * rowsPerTable) - ordinalSum(table * rowsPerTable),
    id_sum: rowsPerTable * table * rowsPerTable + rowsPerTable * (rowsPerTable - 1) / 2}));
  const fields = ['document_chars', 'id_sum', 'row_count'];
  const stages = resources.map((resource, table) => ({id: `capture${table}`,
    inputs: {source: {connector: 'table-input', resource}}, from: 'source', steps: [
      {derive: {document_chars: {len: {field: 'document'}}}, as: 'measured'},
      {from: 'measured', group: {by: [], aggregates: {
        document_chars: {fn: 'sum', field: 'document_chars'},
        id_sum: {fn: 'sum', field: 'id'}, row_count: {fn: 'count'},
      }}, as: 'summary'},
    ], results: {rows: {from: 'summary', fields}}}));
  const inputs = Object.fromEntries(stages.map(stage =>
    [stage.id, {result: {stage: stage.id, result: 'rows'}}]));
  const steps = [];
  let current = stages[0].id;
  for (let table = 1; table < tables; table++) {
    const next = `combined${table}`;
    steps.push({from: current, append: {with: stages[table].id}, as: next});
    current = next;
  }
  steps.push({from: current, group: {by: [], aggregates: Object.fromEntries(
    fields.map(field => [field, {fn: 'sum', field}]))}, as: 'summary'});
  stages.push({id: 'apply', inputs, steps,
    results: {rows: {from: 'summary', fields}},
    effects: {save: {store: {target: 'connector://table/catalog',
      mapping: 'mapping:table.catalog.v1', from: {result: 'rows'}}}}});
  const results = Object.fromEntries(resources.map((_, table) =>
    [`source${table}`, {from: {stage: `capture${table}`, result: 'rows'}}]));
  results.answer = {from: {stage: 'apply', result: 'rows'}};
  const program = {version: 'actql/0.1', id: 'ordinary-real-table-dependency-width', stages, results};
  const expected = [{document_chars: tables * rowsPerTable * documentUnits + ordinalSum(tables * rowsPerTable),
    id_sum: tables * rowsPerTable * (tables * rowsPerTable - 1) / 2,
    row_count: tables * rowsPerTable}];
  return Object.freeze({program, source: JSON.stringify(program), format: 'json',
    resources: Object.freeze(resources), schemaWire, schemaCid, mapping,
    rowsForSource(table) {return Array.from({length: rowsPerTable}, (_, index) => row(table, index));},
    expectedSources: Object.freeze(expectedSources), expected: Object.freeze(expected),
    sourceValueBytes: expected[0].document_chars, expectedSourceStarts: tables,
    expectedModelStarts: 0, expectedEffectOperations: 1,
    selected: Object.freeze({tables, rowsPerTable, documentUnits}),
    // These are explicit, finite fixture selections, not product default or
    // compiler quota changes. The provider's 4 MiB physical frame stays fixed.
    sourceLimits: Object.freeze({maxPages: 3, maxPageBytes: 4 * 1024 * 1024,
      maxPageRows: rowsPerTable, maxCaptureRows: rowsPerTable}),
    // Provisioning retains each committed physical reservation. Project the
    // finite Catalog selection from the actual seed count plus one Effect;
    // this storage profile is separate from the unchanged Request memory.
    catalogLimits: Object.freeze({bytes: Math.max(128 * 1024 * 1024,
      tables * 16 * 1024 * 1024 + 1024 * 1024),
    files: Math.max(256, (tables + 1) * 16), operations: Math.max(16, tables + 1)}),
    seedReservation: Object.freeze({bytes: 16 * 1024 * 1024, files: 16}),
    effectLimits: Object.freeze({reservation: {bytes: 1024 * 1024, files: 16}}),
    requestMemory: Object.freeze({retainedBytes: 1024 ** 3, executionBytes: 1024 ** 3}),
    sourceFreeMaxWork: 30000000});
}

// Actual selectors come from the successful physical seed receipts. This pure
// constructor neither seeds a Table nor forges a generation/receipt/grant.
export function tableDependencyWidthProfiles(selected, {python, catalog,
  selectors, accountConfigurationWire, environmentWire, mappingCid, tableEffectContractCid}) {
  assert.equal(selectors.length, selected.resources.length);
  assert(/^sha256:[0-9a-f]{64}$/u.test(tableEffectContractCid));
  // Read and write Catalog publications have distinct selector identities.
  // They use the same installed Local provider and physical Catalog, without
  // asking the common merger to replace a six-view Catalog with an empty one.
  const source = {version: 'actql-installed-local-table-source/0.1', connectorId: 'table-input',
    connection: 'table-local', python, catalog, accountConfigurationWire,
    targets: selected.resources.map((resource, index) => ({resource,
      selector: selectors[index], schemaWire: selected.schemaWire})), limits: selected.sourceLimits};
  const effect = {version: 'actql-installed-local-table-effect/0.1', connectorId: 'table',
    connection: 'table-local', python, catalog, accountConfigurationWire, environmentWire,
    targets: [{effectId: 'save', resource: 'summary', targetRef: 'connector://table/catalog',
      mappingRef: 'mapping:table.catalog.v1', mappingCid, action: 'create',
      catalogCid: catalog.catalogCid, namespace: ['test'], tableName: 'summary', expectedTable: null,
      permissions: ['scope:store'], footprint: {kind: 'collection',
        resource_identity_scheme_cid: tableEffectContractCid,
        provider_namespace: 'table', provider_boundary_cid: catalog.catalogCid,
        resource_kind: 'Table', provider_object_identity_cids: []}}], limits: selected.effectLimits};
  return {source, effect};
}
