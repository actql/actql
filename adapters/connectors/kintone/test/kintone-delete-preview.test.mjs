import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';

const bytes = value => Buffer.from(JSON.stringify(value));
const valueLimits = () => moon.clientProgramKintoneValueLimits(8, 128, 1000, 16, 8192);
const limits = (maxBytes = 8192) => moon.clientProgramKintoneMutationLimits(100, 1000, 10000, maxBytes, 1000, 16);
const form = () => checked(moon.clientProgramKintoneProjectForm(bytes({revision: '7', properties: {
  Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'},
  Tags: {code: 'Tags', type: 'MULTI_SELECT', options: {a: {label: 'a'}, b: {label: 'b'}}},
}}), '12', moon.clientProgramKintoneFormLimits(8192, 1000, 16, 16, 512)));
const mapping = original => {
  const declarationLimits = moon.clientProgramKintoneDeclarationLimits(100000, 10000, 32, 1, 8);
  const declared = checked(moon.clientProgramKintoneDeclareRecords(original, undefined,
    ['Tags', 'Subject'], 'kintone', 'kintone/0.1', 'inquiries', valueLimits(), declarationLimits));
  return checked(moon.clientProgramKintonePrepareDeleteMapping(declared, 'inquiries', 'required', declarationLimits));
};
const target = (original, revision = '9007199254740994', fields = ['Tags', 'Subject']) => {
  const page = checked(moon.clientProgramKintoneProjectRecordPage(bytes({records: [{
    $id: {type: '__ID__', value: '9007199254740993'},
    $revision: {type: '__REVISION__', value: revision},
    Subject: {type: 'SINGLE_LINE_TEXT', value: 'original'},
    Tags: {type: 'MULTI_SELECT', value: ['b', 'a', 'b']},
  }], totalCount: null}), original, fields,
  moon.clientProgramKintonePageLimits(8192, 1000, 16, 4, 8, 32, 16)));
  return checked(moon.clientProgramKintoneOriginalRecordTarget(page, 0, 1000));
};
const preview = (owned, original) => checked(moon.clientProgramKintonePrepareDeletePreview(
  owned, original, valueLimits(), limits()));

test('actual original kintone before DATA preserves checked arrays, wide ID and exact revision fingerprint', () => {
  const catalog = form(), owned = mapping(catalog), original = target(catalog), before = preview(owned, original);
  assert.deepEqual(JSON.parse(moon.clientProgramKintoneDeletePreviewBefore(before)), {
    $id: '9007199254740993', Subject: 'original', Tags: ['b', 'a', 'b'],
  });
  assert.equal(moon.clientProgramKintoneDeletePreviewIdentity(before), '9007199254740993');
  const expected = 'sha256:' + createHash('sha256').update(JSON.stringify([
    '12', '9007199254740993', '9007199254740994',
  ])).digest('hex');
  assert.equal(moon.clientProgramKintoneDeletePreviewVersionCid(before), expected);
  const later = preview(owned, target(catalog, '9007199254740995'));
  assert.equal(moon.clientProgramKintoneDeletePreviewBefore(before), moon.clientProgramKintoneDeletePreviewBefore(later));
  assert.notEqual(moon.clientProgramKintoneDeletePreviewVersionCid(before), moon.clientProgramKintoneDeletePreviewVersionCid(later));
  assert.equal(moon.clientProgramKintoneDeletePreviewMatches(before, owned, original), true);
  assert.equal(moon.clientProgramKintoneDeletePreviewMatches(before, owned, target(catalog)), false);
  assert.equal(moon.clientProgramKintoneDeletePreviewMatches(before, mapping(catalog), original), false);
});

test('actual original before refuses equal foreign Form, incomplete selection and missing output bound', () => {
  const catalog = form(), owned = mapping(catalog);
  for (const original of [target(form()), target(catalog, '9007199254740994', [])]) {
    assert.equal(runtimeIsError(moon.clientProgramKintonePrepareDeletePreview(owned, original, valueLimits(), limits())), true);
  }
  assert.equal(runtimeIsError(moon.clientProgramKintonePrepareDeletePreview(owned, target(catalog), valueLimits(), limits(0))), true);
});
