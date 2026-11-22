import assert from 'node:assert/strict';

const json = v => JSON.stringify(v, null, 2) + '\n';
const text = {type: 'string', nullable: false};
const nullable = {type: 'string', nullable: true};
export const catalog = {connections: {salesforce: {
  views: [{resource: 'Account', resource_kind: 'record', data_classification: 'internal',
    schema: {id: text, clear_value: nullable, blank_value: nullable, omitted_value: nullable,
      null_input: nullable, empty_input: text, protected_value: text},
    facts: {relation_keys: {candidate_keys: [['id']]}}}],
  query_aliases: [{name: 'salesforce.accounts', resource: 'Account'}],
  data: [{resource: 'Account', items_path: ['salesforce', 'Account', 'rows'],
    key_path: ['salesforce', 'Account', 'key'], primary_identity: 'id'}],
  writes: [{resource: 'Account', primary_identity: 'id',
    writable_fields: ['clear_value', 'blank_value', 'omitted_value'],
    update_fields: ['clear_value', 'blank_value'],
    write_null_fields: ['clear_value'],
    permission: 'salesforce:record:update', observe_permission: 'salesforce:record:observe',
    approval: 'required', aliases: ['salesforce.Account']}],
}}};

const target = {id: 'a1', clear_value: 'remove this', blank_value: 'replace with empty',
  omitted_value: 'retain eligible value', null_input: null, empty_input: '', protected_value: 'outside write contract'};
const control = {id: 'a2-control', clear_value: 'control clear', blank_value: 'control blank',
  omitted_value: 'control omitted', null_input: 'control input', empty_input: 'other control input',
  protected_value: 'control protected'};
const changes = {clear_value: null, blank_value: ''};
export const beforeRows = [target, control];
export const afterRows = [{...target, clear_value: null, blank_value: ''}, control];
const data = {salesforce: {Account: {key: ['id'], rows: beforeRows}},
  control: {marker: 'untouched whole-document record', nested: {empty: '', nil: null}}};
export const before = json(data);
export const after = before
  .replace('"clear_value": "remove this"', '"clear_value": null')
  .replace('"blank_value": "replace with empty"', '"blank_value": ""');
assert.deepEqual(JSON.parse(after).salesforce.Account.rows, afterRows);
export const expectedRows = [{id: 'a1', omitted_value: 'retain eligible value', null_input: null, empty_input: ''}];
const effect = 'SELECT a.id, a.omitted_value, a.null_input, a.empty_input\n' +
  'FROM salesforce.accounts AS a WHERE a.id = @target\n' +
  '|> RESULT updates\n' +
  '|> EFFECT UPDATE salesforce.Account ID id SET (clear_value = null_input, blank_value = empty_input);\n';
const read = 'SELECT a.id, a.clear_value, a.blank_value, a.omitted_value, a.null_input, a.empty_input, a.protected_value\n' +
  'FROM salesforce.accounts AS a WHERE a.id = @target OR a.id = @control ORDER BY id\n' +
  '|> RESULT main;\n';
export const definition = {
  name: 'declared-null-empty-and-omitted',
  effect: {document: effect, format: 'aql', resultName: 'updates',
    parameterDeclarations: {target: {type: 'string'}}, parameters: {target: 'a1'}, expectedRows},
  read: {document: read, format: 'aql', resultName: 'main',
    parameterDeclarations: {target: {type: 'string'}, control: {type: 'string'}},
    parameters: {target: 'a1', control: 'a2-control'}, beforeRows, afterRows},
  review: {target: 'connector://salesforce/Account', identity: 'a1', before: target, changes},
};
export const files = {
  'actql.config.json': json({version: 'actql-config/0.1', profile: 'mock', connectors: './connectors.json',
    model_tasks: './model-tasks.json', state_dir: './.actql',
    mock: {catalog: './mock/catalog.json', data: './mock/data.json', answers: {}}}),
  'connectors.json': json({version: 'actql-connectors/0.1', connections: {salesforce: {connector: 'salesforce'}}}),
  'model-tasks.json': json({version: 'actql-model-tasks/0.1', tasks: {}, providers: {}}),
  'mock/catalog.json': json(catalog),
  'mock/data.json': before,
  'nullable-update.aql': effect,
  'nullable-read.aql': read,
};
