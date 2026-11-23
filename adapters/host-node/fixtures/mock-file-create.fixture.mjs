import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {multipleTargetMockProjectFiles} from './mock-multiple-targets.fixture.mjs';

export function fileCreateMockProject() {
  const rows = [{group: 'inserted', value: null}];
  const text = {nullable: false, type: 'string'};
  const nullable = {nullable: true, type: 'string'};
  const mapping = 'mapping:salesforce/Account/create-' + createHash('sha256').update(JSON.stringify({
    key: null, kind: 'create', resource: 'Account',
    row_mapping: {group: {field: 'group', null_behavior: 'reject'}, value: {field: 'value', null_behavior: 'write_null'}},
    target_schema: {additional_properties: false, fields: {group: text, id: text, value: nullable},
      nullable: false, type: 'object'}, write_fields: ['group', 'value'],
  })).digest('hex').slice(0, 16) + '.v1';
  const files = {...multipleTargetMockProjectFiles()};
  delete files['multiple-targets.program.json'];
  const catalog = JSON.parse(files['mock/catalog.json']);
  const {views, writes} = catalog.connections.salesforce;
  views[0].schema.value.nullable = true;
  Object.assign(writes[0], {operation: 'create', permission: 'salesforce:record:create',
    writable_fields: ['group', 'value'], write_null_fields: ['value']});
  files['mock/catalog.json'] = JSON.stringify(catalog);
  const programFile = 'file-create.program.json';
  files[programFile] = JSON.stringify({
    version: 'actql/0.1', id: 'fixture.mock-file-create', stages: [{
      id: 'apply', inputs: {}, steps: [{values: {schema: {group: text, value: nullable}, rows}, as: 'proposals'}],
      results: {rows: {from: 'proposals', fields: ['group', 'value']}},
      effects: {create_account: {create: {target: 'connector://salesforce/Account', mapping,
        from: {result: 'rows'}}}},
    }], results: {main: {from: {stage: 'apply', result: 'rows'}}},
  });
  const before = files['mock/data.json'];
  const after = {state: 'present', value: {group: 'inserted', value: null}};
  const contentCid = 'sha256:' + createHash('sha256').update(JSON.stringify({
    value: after, version: 'actql-effect-content-row/0.1',
  })).digest('hex');

  function assertCreatedFile(bytes) {
    const accounts = JSON.parse(bytes).salesforce.Account.rows;
    const inserted = accounts.at(-1);
    assert.match(inserted?.id ?? '', /^[0-9a-f]{64}$/u);
    assert.equal(accounts.length, 3);
    assert.equal(new Set(accounts.map(row => row.id)).size, 3);
    const anchor = '"value": "keep-account"\n        }';
    assert.equal(before.split(anchor).length, 2);
    const added = JSON.stringify({group: 'inserted', id: inserted.id, value: null});
    assert.equal(bytes, before.replace(anchor, anchor + ',' + added),
      'CREATE must add exactly one row and preserve every original byte');
  }
  return {files, programFile, before, rows, resultName: 'main', assertCreatedFile,
    changes: [{kind: 'create', resource: 'Account', id: {content_cid: contentCid, occurrence: 0}, after}]};
}
