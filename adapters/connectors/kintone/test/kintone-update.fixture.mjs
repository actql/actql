import assert from 'node:assert/strict';
import * as common from '../../../../_build/js/debug/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createKintoneUpdateRequestAdapter} from '../host/kintone-update-request.mjs';

export const cid = mark => 'sha256:' + mark.repeat(64);
export const encode = value => canonicalJson(value, {dataKeys: true});
export const bytes = value => Buffer.from(JSON.stringify(value));
export const identity = '9007199254740993', revision = '9007199254740994';
export const form = {revision: '7', properties: {
  Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT', expression: ''},
  Tags: {code: 'Tags', type: 'MULTI_SELECT', options: {red: {label: 'red', index: '0'}}},
  Computed: {code: 'Computed', type: 'SINGLE_LINE_TEXT', expression: 'server'},
}};
export const value = {Subject: 'next 東京', Tags: ['red', 'red']};
export const policy = {maxInputBytes: 2048, maxRequestBytes: 2048, maxResponseBytes: 16384,
  maxNodes: 8000, maxDepth: 32, maxFields: 16, maxNameUnits: 512, maxColumns: 8,
  maxCells: 32, maxTableRows: 16, maxValueNodes: 8000, maxValueDepth: 32,
  maxValueTextBytes: 16384, maxIdentityBytes: 512, maxComparisonWork: 20000, maxRecoveryBytes: 65536};
export function observation({id = identity, rev = revision, subject = 'before'} = {}) {
  return {statusCode: 200, body: bytes({records: [{
    $id: {type: '__ID__', value: id}, $revision: {type: '__REVISION__', value: rev},
    Subject: {type: 'SINGLE_LINE_TEXT', value: subject},
    Tags: {type: 'MULTI_SELECT', value: ['red']},
    Computed: {type: 'SINGLE_LINE_TEXT', value: 'server'},
  }], totalCount: null})};
}
export function fixture(changes = {}) {
  const formLimits = common.clientProgramKintoneFormLimits(16384, 8000, 32, 16, 512);
  const catalog = checked(common.clientProgramKintoneProjectForm(bytes(form), '12', formLimits));
  const declarationLimits = common.clientProgramKintoneDeclarationLimits(65536, 8000, 32, 4, 16);
  const declaration = checked(common.clientProgramKintoneDeclareRecords(catalog, undefined,
    ['Subject', 'Tags', 'Computed'], 'kintone', 'kintone/0.1', 'inquiries',
    common.clientProgramKintoneValueLimits(8, 512, 8000, 32, 16384), declarationLimits));
  const mapping = checked(common.clientProgramKintonePrepareUpdateMapping(declaration, 'inquiries',
    [{target: 'Subject', field: 'subject', null_behavior: 'reject'},
      {target: 'Tags', field: 'tags', null_behavior: 'reject'}], 'required', declarationLimits));
  // Count only these external port entries, while invoking the actual native
  // implementation with its original runtime. Entries are not validation work.
  const calls = {}, moon = {};
  for (const [name, fn] of Object.entries(common)) moon[name] = typeof fn !== 'function' ? fn : function(...args) {
    assert.strictEqual(this, moon); calls[name] = (calls[name] ?? 0) + 1;
    return Reflect.apply(fn, common, args);
  };
  const options = {moon, declaration, mapping, origin: 'https://tenant.example.test', appId: '12',
    connectorId: 'kintone', resource: 'inquiries', siteBindingCid: cid('a'), generationCid: cid('b'),
    limits: policy, ...changes};
  return {options, calls, moon, adapter: createKintoneUpdateRequestAdapter(options)};
}
