import assert from 'node:assert/strict';
import {isDeepStrictEqual} from 'node:util';
import type {AuthoredRecordApprovalCase} from './workflow.mjs';

type Row = Record<string, unknown>;
type Inventory = Record<string, Record<string, {key: string[]; rows: Row[]}>>;
type Target = {resource: string; primary_identity: string; writable_fields: string[]};
type Data = {resource: string; items_path: string[]; key_path: string[]; primary_identity: string};
type Mutation = {key: string} & (
  {operation: 'create'; before: null; after: Row} |
  {operation: 'update'; before: Row; after: Row} |
  {operation: 'delete'; before: Row; after: null});
type OrderedWrite = {resource: string; operation: 'create' | 'update' | 'delete'; key: string;
  before: Row | null; after: Row | null};

function dataMember(root: unknown, path: readonly string[]): unknown {
  let current = root;
  for (const name of path) {
    assert(current !== null && typeof current === 'object' && Object.hasOwn(current, name));
    current = (current as Row)[name];
  }
  return current;
}

export function recordApprovalOrderedMockProject(authored: AuthoredRecordApprovalCase, connection: string) {
  const {collection, review} = authored;
  assert(collection !== undefined && 'effects' in review && collection.connection === connection);
  const files = collection.projectFiles;
  const config = JSON.parse(files['actql.config.json']);
  assert.equal(config.version, 'actql-config/0.1');
  assert.equal(config.profile, 'mock');
  assert.equal(config.connectors, './connectors.json');
  assert.equal(config.state_dir, './.actql');
  assert.equal(config.model_tasks,
    Object.hasOwn(files, 'model-tasks.json') ? './model-tasks.json' : undefined);
  assert.equal(config.mock.catalog, './mock/catalog.json');
  assert.equal(config.mock.data, './mock/data.json');
  assert(Object.keys(config).every(field =>
    ['version', 'profile', 'connectors', 'state_dir', 'model_tasks', 'mock'].includes(field)));
  assert(Object.keys(config.mock).every(field => ['catalog', 'data', 'answers'].includes(field)));
  assert(Object.hasOwn(JSON.parse(files['connectors.json']).connections, connection));
  const catalog = JSON.parse(files['mock/catalog.json']).connections[connection] as {
    writes: (Target & {operation?: string})[]; data: Data[];
  };
  const originalData = JSON.parse(files['mock/data.json']);
  const expected = JSON.parse(collection.expectedData);
  const composed = structuredClone(originalData);
  const targets = new Map<string, {member: (typeof review.effects)[number]; offset: number}[]>();
  const prefix = 'connector://' + connection + '/';
  let rowCount = 0;
  for (const effect of review.effects) {
    assert(effect.target.startsWith(prefix));
    const resource = effect.target.slice(prefix.length);
    assert.equal(catalog.writes.filter(write =>
      write.resource === resource && (write.operation ?? 'update') === effect.kind).length, 1);
    const members = targets.get(resource) ?? [];
    members.push({member: effect, offset: rowCount});
    targets.set(resource, members);
    rowCount += effect.rows.length;
  }
  assert.equal(collection.expectedWrites, rowCount,
    'The selected Mock performs one replacement per original Effect row');
  const writes: OrderedWrite[] = [];
  const resources = [];
  for (const [resource, members] of targets) {
    const selected = catalog.data.filter(binding => binding.resource === resource);
    assert.equal(selected.length, 1);
    const {items_path: items, key_path: keyPath} = selected[0];
    assert(items.length > 0 && keyPath.length > 0);
    const rows = dataMember(originalData, items), after = dataMember(expected, items);
    const keys = dataMember(originalData, keyPath);
    assert(Array.isArray(rows) && Array.isArray(after) && Array.isArray(keys) && keys.length > 0);
    assert(keys.every(key => typeof key === 'string') && new Set(keys).size === keys.length);
    assert.deepEqual(dataMember(expected, keyPath), keys);
    const expectedRows: Row[] = after;
    const keyFields: string[] = keys;
    const physical = (row: Row) => JSON.stringify(keys.map(field => {
      assert(Object.hasOwn(row, field) &&
        (typeof row[field] === 'string' || typeof row[field] === 'boolean' || Number.isSafeInteger(row[field])));
      return row[field];
    }));
    const next = [...rows] as Row[];
    assert.equal(new Set(next.map(physical)).size, next.length);
    const keysAfter = new Set(expectedRows.map(physical));
    assert.equal(keysAfter.size, expectedRows.length);
    for (const {member, offset} of members) {
      let indexWithinMember = 0;
      for (const row of member.rows) {
        const ordinal = offset + indexWithinMember++;
        if (row.before === null) {
          const present = new Set(next.map(physical));
          const created: Row[] = expectedRows.filter(target => !present.has(physical(target)) &&
            Object.entries(row.changes!).every(([field, value]) =>
              Object.hasOwn(target, field) && isDeepStrictEqual(target[field], value)));
          assert.equal(created.length, 1, 'Expected one independent created row');
          next.push(created[0]);
          writes[ordinal] = {resource, operation: 'create', key: physical(created[0]), before: null, after: created[0]};
        } else {
          const priorKey = physical(row.before);
          const index = next.findIndex(target => physical(target) === priorKey);
          assert(index >= 0);
          assert.deepEqual(next[index], row.before, 'Expected the original ordered predecessor');
          if (member.kind === 'delete') {
            next.splice(index, 1);
            writes[ordinal] = {resource, operation: 'delete', key: priorKey, before: row.before, after: null};
          } else {
            next[index] = {...row.before, ...row.changes};
            assert.equal(physical(next[index]), priorKey, 'The original physical key must remain unchanged');
            writes[ordinal] = {resource, operation: 'update', key: priorKey, before: row.before, after: next[index]};
          }
        }
      }
    }
    assert.deepEqual(next, expectedRows, 'The expected file contains exactly the selected ordered changes');
    const controls: typeof collection.controls = collection.controls.filter(control => control.resource === resource);
    assert(controls.length > 0, 'Each changed resource has an independent control row');
    for (const {key} of controls) {
      assert.equal(key.length, keyFields.length);
      const matches = (rows: Row[]): Row[] => rows.filter(row =>
        keyFields.every((field, index) => Object.hasOwn(row, field) && row[field] === key[index]));
      const beforeControl: Row[] = matches(rows);
      assert.equal(beforeControl.length, 1);
      assert.deepEqual(matches(expectedRows), beforeControl, 'The independent control row remains unchanged');
    }
    const parent = dataMember(composed, items.slice(0, -1));
    assert(parent !== null && typeof parent === 'object');
    (parent as Row)[items[items.length - 1]] = after;
    resources.push({resource, keyFields, before: rows as Row[], after: expectedRows,
      controlKeys: controls.map(control => JSON.stringify(control.key))});
  }
  assert(collection.controls.every(control => targets.has(control.resource)));
  assert.deepEqual(expected, composed, 'Only selected resource rows may change');
  assert.notDeepEqual(expected, originalData, 'Expected independent changed rows');
  return {files, initial: originalData, changed: expected, approvedWrites: collection.expectedWrites, resources, writes};
}

export function recordApprovalMockResource(files: Record<string, string>, connection: string) {
  const catalog = JSON.parse(files['mock/catalog.json']) as {
    connections: Record<string, {writes: Target[]; data: Data[]}>;
  };
  const selected = catalog.connections[connection];
  assert(selected?.writes.length === 1, 'Expected one declared Mock write resource');
  const [{resource, primary_identity: identity, writable_fields: fields}] = selected.writes;
  assert(fields.length > 0 && !fields.includes(identity) && new Set(fields).size === fields.length);
  const inputs = selected.data.filter(input => input.resource === resource);
  assert.equal(inputs.length, 1);
  const [input] = inputs;
  assert.equal(input.primary_identity, identity);
  assert.deepEqual(input.items_path, [connection, resource, 'rows']);
  assert.deepEqual(input.key_path, [connection, resource, 'key']);
  const initial = JSON.parse(files['mock/data.json']) as Inventory;
  const {key, rows} = initial[connection][resource];
  assert.deepEqual(key, [identity]);
  const keys = rows.map(row => row[identity]);
  assert(keys.every(key => typeof key === 'string' && key.length > 0));
  assert.equal(new Set(keys).size, keys.length);
  return {initial, connection, resource, identity, rows, fields};
}

// These are independently authored complete row snapshots. The packed test
// compares the physical file with them after closing each original process.
export function recordApprovalMockInventory(
  original: ReturnType<typeof recordApprovalMockResource>, controlKey: string, mutations: readonly Mutation[],
) {
  const {initial, connection, resource, identity, fields} = original;
  assert(mutations.length > 0 && initial[connection][resource].rows.some(row => row[identity] === controlKey));
  const changed = structuredClone(initial);
  const rows = changed[connection][resource].rows;
  for (const {operation, key, before, after} of mutations) {
    assert.notEqual(key, controlKey, 'The independent control row cannot be mutated');
    const index = rows.findIndex(row => row[identity] === key);
    assert.deepEqual(index < 0 ? null : rows[index], before, 'Expected the original Mock predecessor');
    if (after !== null) {
      assert.equal(after[identity], key, 'Expected the same Mock row key');
      const unaffected = (row: Row) => Object.fromEntries(
        Object.entries(row).filter(([field]) => !fields.includes(field)));
      assert.deepEqual(unaffected(after), before === null ? {[identity]: key} : unaffected(before));
    }
    if (operation === 'create') rows.push(structuredClone(after));
    else if (operation === 'delete') rows.splice(index, 1);
    else rows[index] = structuredClone(after);
  }
  return {initial, changed, approvedWrites: mutations.length};
}

// Same existing declared-data mock contract. This writes no project and issues
// no permission; the caller deliberately installs these independent files.
export function recordApprovalMockProjectFiles({connection, resource, alias, identity, fields, schema, rows,
  updatePermission, observePermission}: {
  connection: string; resource: string; alias: string; identity: string; fields: readonly string[];
  schema: Record<string, {type: string; nullable: boolean}>; rows: readonly Row[];
  updatePermission: string; observePermission: string;
}) {
  for (const value of [connection, resource, alias, identity, updatePermission, observePermission]) {
    if (typeof value !== 'string' || !value) throw new TypeError('InvalidRecordUpdateMockInput');
  }
  const identities = rows.map(row => row[identity]);
  if (!Object.hasOwn(schema, identity) || schema[identity].nullable || fields.length === 0 ||
      fields.some(field => field === identity || !Object.hasOwn(schema, field)) || new Set(fields).size !== fields.length ||
      identities.some(key => typeof key !== 'string' || !key) || new Set(identities).size !== identities.length ||
      rows.some(row => Object.keys(row).some(name => !Object.hasOwn(schema, name)))) {
    throw new TypeError('AmbiguousRecordUpdateMockInput');
  }
  const json = (value: unknown) => JSON.stringify(value, null, 2) + '\n';
  return {
    'actql.config.json': json({version: 'actql-config/0.1', connectors: './connectors.json',
      state_dir: './.actql', profile: 'mock',
      mock: {catalog: './mock/catalog.json', data: './mock/data.json', answers: {}}}),
    'connectors.json': json({version: 'actql-connectors/0.1',
      connections: {[connection]: {connector: connection}}}),
    'mock/catalog.json': json({connections: {[connection]: {
      views: [{resource, resource_kind: 'record', schema,
        facts: {relation_keys: {candidate_keys: [[identity]]}}}],
      query_aliases: [{name: alias, resource}],
      data: [{resource, items_path: [connection, resource, 'rows'],
        key_path: [connection, resource, 'key'], primary_identity: identity}],
      writes: [{resource, primary_identity: identity, writable_fields: fields,
        permission: updatePermission, observe_permission: observePermission,
        approval: 'required', aliases: [connection + '.' + resource]}],
    }}}),
    'mock/data.json': json({[connection]: {[resource]: {key: [identity], rows}}}),
  };
}

export function recordUpdateMockProjectFiles({idField, valueField, recordId, previousValue, controlId, controlValue,
  ...original}: {
  connection: string; resource: string; alias: string; idField: string; valueField: string;
  recordId: string; previousValue: string; controlId: string; controlValue: string;
  updatePermission: string; observePermission: string;
}) {
  for (const value of [idField, valueField, recordId, previousValue, controlId, controlValue]) {
    if (typeof value !== 'string' || !value) throw new TypeError('InvalidRecordUpdateMockInput');
  }
  return recordApprovalMockProjectFiles({...original, identity: idField, fields: [valueField],
    schema: {[idField]: {type: 'string', nullable: false}, [valueField]: {type: 'string', nullable: false}},
    rows: [{[idField]: recordId, [valueField]: previousValue}, {[idField]: controlId, [valueField]: controlValue}]});
}
