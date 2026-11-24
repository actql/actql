// Independently authored Project inputs/oracles for the existing public Mock
// capture/approve/recover consumer. No Host, Account, claim or key is supplied.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const field = (name: string) => ({field: name});
const schema = {group: {nullable: false, type: 'string'},
  id: {nullable: false, type: 'string'}, value: {nullable: false, type: 'string'}};
const json = (value: unknown) => JSON.stringify(value, null, 2) + '\n';
const originalDataWire = json({salesforce: {
  Account: {key: ['id'], rows: [{id: 'a1', group: 'selected', value: 'A-old'},
    {id: 'a-control', group: 'account-control', value: 'keep-account'}]},
  Contact: {key: ['id'], rows: [{id: 'c1', group: 'selected', value: 'C-old'},
    {id: 'c-control', group: 'contact-control', value: 'keep-contact'}]},
}, control: {unchanged: 'keep-physical-document'}});

function mapping(resource: string, kind = 'update') {
  // Exact existing request preimage, with literal canonical key ordering.
  // This is only the authored MappingRef, never an admitted Mapping/permit.
  const request = {key: null, kind, resource,
    row_mapping: kind === 'delete' ? {} : {value: {field: 'value', null_behavior: 'reject'}},
    target_schema: {additional_properties: false, fields: schema, nullable: false, type: 'object'},
    write_fields: kind === 'delete' ? [] : ['value']};
  return 'mapping:salesforce/' + resource + '/' + kind + '-' +
    createHash('sha256').update(JSON.stringify(request)).digest('hex').slice(0, 16) + '.v1';
}

export function multipleTargetMockProjectFiles() {
  const fields = ['account_id', 'contact_id', 'account_before', 'contact_before', 'account_next', 'contact_next'];
  const resources = ['Account', 'Contact'];
  const effect = (resource: string, prefix: string) => ({update: {target: 'connector://salesforce/' + resource,
    mapping: mapping(resource), from: {result: 'rows'}, id: prefix + '_id',
    set: {value: field(prefix + '_next')}}});
  return Object.freeze({
    'actql.config.json': json({version: 'actql-config/0.1', profile: 'mock', connectors: './connectors.json',
      model_tasks: './model-tasks.json', state_dir: './.actql',
      mock: {catalog: './mock/catalog.json', data: './mock/data.json', answers: {}}}),
    'connectors.json': json({version: 'actql-connectors/0.1', connections: {salesforce: {connector: 'salesforce'}}}),
    'model-tasks.json': json({version: 'actql-model-tasks/0.1', tasks: {}, providers: {}}),
    'mock/catalog.json': json({connections: {salesforce: {
      views: resources.map(resource => ({resource, resource_kind: 'record', data_classification: 'internal',
        schema, facts: {relation_keys: {candidate_keys: [['id']]}}})),
      query_aliases: resources.map(resource => ({name: 'salesforce.' + resource.toLowerCase() + 's', resource})),
      data: resources.map(resource => ({resource, items_path: ['salesforce', resource, 'rows'],
        key_path: ['salesforce', resource, 'key'], primary_identity: 'id'})),
      writes: [['Account', 'salesforce:record:update', 'salesforce:record:observe'],
        ['Contact', 'salesforce:contact:update', 'salesforce:contact:observe']]
        .map(([resource, permission, observe_permission]) => ({resource, primary_identity: 'id',
          writable_fields: ['value'], permission, observe_permission,
          approval: 'required', aliases: ['salesforce.' + resource]})),
    }}}),
    'mock/data.json': originalDataWire,
    'multiple-targets.program.json': json({version: 'actql/0.1', id: 'fixture.mock-disjoint-targets', stages: [{
      id: 'apply', inputs: {accounts: {connector: 'salesforce', resource: 'Account'},
        contacts: {connector: 'salesforce', resource: 'Contact'}}, from: 'accounts', steps: [
        {join: {with: 'contacts', kind: 'inner', on: [{left: 'group', right: 'group'}], select: {
          account_id: 'left.id', contact_id: 'right.id', account_before: 'left.value', contact_before: 'right.value'}}},
        {derive: {account_next: {literal: 'A-new'}, contact_next: {literal: 'C-new'}}},
        {select: fields, as: 'updates'},
      ], results: {rows: {from: 'updates', fields}}, effects: {
        account: effect('Account', 'account'), contact: effect('Contact', 'contact'),
      },
    }], results: {updates: {from: {stage: 'apply', result: 'rows'}}}}),
  });
}

// An ordinary Native Saved application uses one approved Effect set. The
// first and last members share the Account provider, the middle uses Contact.
// Each selects a different row in the one declared physical data file.
export function threeWriteMockProject() {
  const files = {...multipleTargetMockProjectFiles()};
  const programFile = 'multiple-targets.program.json';
  const data = JSON.parse(files['mock/data.json']);
  data.salesforce.Account.rows.push({id: 'a2', group: 'other', value: 'A2-old'});
  const before = json(data);
  files['mock/data.json'] = before;
  const program = JSON.parse(files[programFile]);
  program.id = 'fixture.mock-three-ordered-targets';
  const stage = program.stages[0];
  const projection = stage.steps.at(-1).select;
  const row = {
    account_id: 'a1', contact_id: 'c1', account_before: 'A-old', contact_before: 'C-old',
    account_next: 'A-new', contact_next: 'C-new', second_account_id: 'a2', second_account_next: 'A2-new',
  };
  Object.assign(stage.steps[1].derive, {
    second_account_id: {literal: row.second_account_id},
    second_account_next: {literal: row.second_account_next},
  });
  projection.push('second_account_id', 'second_account_next');
  stage.results.rows.fields = projection;
  const account = stage.effects.account, contact = stage.effects.contact;
  stage.effects = {a_first: account, b_middle: contact, c_last: {update: {
    ...account.update, id: 'second_account_id', set: {value: field('second_account_next')},
  }}};
  files[programFile] = json(program);
  const changes = Object.freeze([
    Object.freeze({resource: 'Account', id: 'a1', before: 'A-old', after: 'A-new'}),
    Object.freeze({resource: 'Contact', id: 'c1', before: 'C-old', after: 'C-new'}),
    Object.freeze({resource: 'Account', id: 'a2', before: 'A2-old', after: 'A2-new'}),
  ]);
  let after = before;
  for (const change of changes) {
    const original = '"value": ' + JSON.stringify(change.before);
    assert.equal(before.split(original).length, 2);
    after = after.replace(original, '"value": ' + JSON.stringify(change.after));
  }
  return Object.freeze({files: Object.freeze(files), programFile,
    before, after, changes, rows: Object.freeze([Object.freeze(row)])});
}

export function mixedDeleteUpdateMockProject() {
  const files = {...multipleTargetMockProjectFiles()};
  const catalog = JSON.parse(files['mock/catalog.json']);
  const {writes} = catalog.connections.salesforce;
  const {writable_fields, ...account} = writes[0];
  assert.deepEqual(writable_fields, ['value']);
  writes[0] = {...account, operation: 'delete', permission: 'salesforce:record:delete'};
  files['mock/catalog.json'] = json(catalog);

  const programFile = 'multiple-targets.program.json';
  const program = JSON.parse(files[programFile]);
  const {effects} = program.stages[0];
  const {set, ...selection} = effects.account.update;
  assert.deepEqual(set, {value: field('account_next')});
  effects.account = {delete: {...selection, mapping: mapping('Account', 'delete')}};
  files[programFile] = json(program);

  const before = files['mock/data.json'];
  const removed = `{
          "id": "a1",
          "group": "selected",
          "value": "A-old"
        },`;
  assert.equal(before.split(removed).length, 2);
  assert.equal(before.split('"C-old"').length, 2);
  const after = before.replace(removed, '').replace('"C-old"', '"C-new"');
  const rows = Object.freeze([Object.freeze({account_id: 'a1', contact_id: 'c1',
    account_before: 'A-old', contact_before: 'C-old', account_next: 'A-new', contact_next: 'C-new'})]);
  return Object.freeze({files: Object.freeze(files), programFile, before, after, rows});
}

export const multipleTargetMockWriteCount = 2;
export function checkMultipleTargetMockRows(rows: unknown) {
  assert.deepEqual(rows, [{account_id: 'a1', contact_id: 'c1', account_before: 'A-old',
    contact_before: 'C-old', account_next: 'A-new', contact_next: 'C-new'}]);
}

export function checkMultipleTargetMockReview(review: Readonly<{
  displayed_scope: {effects: readonly {kind: string; target: string; count: number}[]};
  displayed_rows: readonly {target_row_identity: string; row_preview_cid: string; preview_strength: string;
    target_guard: {state: string; version_cid: string}; before: unknown; intended_changes: unknown; after: unknown}[];
}>) {
  assert.deepEqual(review.displayed_scope.effects.map(({kind, target, count}) => ({kind, target, count}))
    .sort((a, b) => a.target.localeCompare(b.target)), [
    {kind: 'update', target: 'connector://salesforce/Account', count: 1},
    {kind: 'update', target: 'connector://salesforce/Contact', count: 1},
  ]);
  assert.equal(review.displayed_rows.length, 2);
  assert.deepEqual(review.displayed_rows.map(row => row.target_row_identity).sort(), ['a1', 'c1']);
  for (const row of review.displayed_rows) {
    const id = row.target_row_identity, prior = id === 'a1' ? 'A-old' : 'C-old', next = id === 'a1' ? 'A-new' : 'C-new';
    assert.match(row.row_preview_cid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(row.preview_strength, 'full_diff');
    assert.equal(row.target_guard.state, 'version');
    assert.match(row.target_guard.version_cid, /^sha256:[0-9a-f]{64}$/u);
    assert.deepEqual(row.before, {state: 'present', value: {group: 'selected', id, value: prior}});
    assert.deepEqual(row.intended_changes, {state: 'present', value: {value: next}});
    assert.deepEqual(row.after, {state: 'present', value: {value: next}});
  }
}

export function multipleTargetMockExpectedBytes(before: string) {
  assert.equal(before, originalDataWire, 'The controlled fixture must start with all original target/control bytes');
  let after = before;
  for (const [prior, next] of [['A-old', 'A-new'], ['C-old', 'C-new']]) {
    const original = '"value": ' + JSON.stringify(prior);
    assert.equal(before.split(original).length, 2);
    after = after.replace(original, '"value": ' + JSON.stringify(next));
  }
  return after;
}
